"""Forward execution cleanup and replay without detector or Docker execution."""
import ast
import inspect
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import fgiemit_process_v2 as process
import run_fgiemit_reserve as historical_reserve
import run_fgiemit_reserve_v2 as reserve
import run_ensemble_pipeline as historical_pipeline
import run_ensemble_pipeline_v2 as pipeline
import test_fgiemit_reserve_runner as reserve_tests
import test_ensemble_pipeline as pipeline_tests


class ReserveV2Tests(reserve_tests.ReserveRunnerTests):
    def setUp(self):
        patch = mock.patch.object(reserve_tests, 'runner', reserve)
        patch.start()
        self.addCleanup(patch.stop)


class PipelineV2Tests(pipeline_tests.PipelineTests):
    def setUp(self):
        patch = mock.patch.object(pipeline_tests, 'pipeline', pipeline)
        patch.start()
        self.addCleanup(patch.stop)


class ProcessV2Tests(unittest.TestCase):
    def assert_process_stopped(self, pid):
        child = Path('/proc') / str(pid) / 'stat'
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            try:
                state = child.read_text().split()[2]
            except FileNotFoundError:
                return
            # A killed orphan can remain a zombie until init reaps it.
            if state in ('Z', 'X'):
                return
            time.sleep(.01)
        self.fail(f'Process {pid} remained alive after cleanup')

    def test_docker_cleanup_failure_cannot_leave_local_processes_running(self):
        failures = [subprocess.TimeoutExpired(['docker', 'rm'], 30),
                    FileNotFoundError('docker missing'),
                    subprocess.CalledProcessError(1, ['docker', 'rm'])]
        real_popen = subprocess.Popen
        for failure in failures:
            with self.subTest(failure=type(failure).__name__), tempfile.TemporaryDirectory() as tmp:
                directory = Path(tmp)
                child_file = directory / 'child.pid'
                command = [sys.executable, '-c',
                    'import subprocess,sys,time; from pathlib import Path; '
                    'p=subprocess.Popen([sys.executable,"-c","import time; time.sleep(60)"]); '
                    'Path(sys.argv[1]).write_text(str(p.pid)); time.sleep(60)', str(child_file)]
                processes = []

                def capture(*args, **kwargs):
                    proc = real_popen(*args, **kwargs)
                    processes.append(proc)
                    return proc

                try:
                    with mock.patch.object(process.subprocess, 'Popen', side_effect=capture), \
                            mock.patch.object(process.subprocess, 'run', side_effect=failure) as cleanup:
                        with self.assertRaises(subprocess.TimeoutExpired) as raised:
                            process.bounded(command, directory, container='owned-test', timeout=.5)
                    self.assertEqual(raised.exception.cmd, command)
                    self.assertEqual(raised.exception.timeout, .5)
                    cleanup.assert_called_once_with(['docker', 'rm', '-f', 'owned-test'],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30, check=True)
                    self.assertEqual(processes[0].returncode, -signal.SIGKILL)
                    self.assertTrue(child_file.is_file(), 'real grandchild did not start')
                    self.assert_process_stopped(child_file.read_text())
                    self.assertIn('Container cleanup failed', (directory / 'inference.log').read_text())
                    self.assertFalse((directory / 'execution.json').exists())
                finally:
                    for proc in processes:
                        try:
                            os.killpg(proc.pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                        proc.wait(timeout=5)

    def test_nonzero_parent_exit_cleans_descendants_and_keeps_original_error(self):
        real_popen = subprocess.Popen
        for failure in (None, subprocess.CalledProcessError(1, ['docker', 'rm'])):
            with self.subTest(cleanup_failure=failure is not None), tempfile.TemporaryDirectory() as tmp:
                directory = Path(tmp); child_file = directory/'child.pid'; processes = []
                command = [sys.executable, '-c',
                    'import subprocess,sys; from pathlib import Path; '
                    'p=subprocess.Popen([sys.executable,"-c","import time; time.sleep(60)"]); '
                    'Path(sys.argv[1]).write_text(str(p.pid)); raise SystemExit(7)', str(child_file)]

                def capture(*args, **kwargs):
                    proc = real_popen(*args, **kwargs)
                    processes.append(proc)
                    return proc

                try:
                    with mock.patch.object(process.subprocess, 'Popen', side_effect=capture), \
                            mock.patch.object(process.subprocess, 'run', side_effect=failure) as cleanup:
                        with self.assertRaisesRegex(RuntimeError, 'Detector exited with status 7'):
                            process.bounded(command, directory, container='owned-test')
                    cleanup.assert_called_once_with(['docker', 'rm', '-f', 'owned-test'],
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30, check=True)
                    self.assertEqual(processes[0].returncode, 7)
                    self.assertEqual(reserve.read_json(directory/'execution.json')['exit_code'], 7)
                    self.assert_process_stopped(child_file.read_text())
                    if failure:
                        self.assertIn('Container cleanup failed', (directory/'inference.log').read_text())
                finally:
                    for proc in processes:
                        try:
                            os.killpg(proc.pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                        proc.wait(timeout=5)

    def test_interruption_survives_cleanup_failure_and_reaps_process(self):
        real_popen = subprocess.Popen
        processes = []
        interrupted = KeyboardInterrupt('original interruption')

        def capture(*args, **kwargs):
            proc = real_popen(*args, **kwargs)
            processes.append(proc)
            real_wait = proc.wait
            calls = 0

            def wait(*args, **kwargs):
                nonlocal calls
                calls += 1
                if calls == 1:
                    raise interrupted
                return real_wait(*args, **kwargs)

            proc.wait = wait
            return proc

        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            try:
                with mock.patch.object(process.subprocess, 'Popen', side_effect=capture), \
                        mock.patch.object(process.subprocess, 'run', side_effect=FileNotFoundError('docker')):
                    with self.assertRaises(KeyboardInterrupt) as raised:
                        process.bounded([sys.executable, '-c', 'import time; time.sleep(60)'],
                                        directory, container='owned-test')
                self.assertIs(raised.exception, interrupted)
                self.assertEqual(processes[0].returncode, -signal.SIGKILL)
            finally:
                for proc in processes:
                    try:
                        os.killpg(proc.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    proc.wait(timeout=5)

    def test_normal_completion_and_nonzero_exit_keep_execution_receipts(self):
        for status in (0, 7):
            with self.subTest(status=status), tempfile.TemporaryDirectory() as tmp:
                directory = Path(tmp)
                command = [sys.executable, '-c', f'raise SystemExit({status})']
                with mock.patch.object(process.subprocess, 'run') as cleanup:
                    if status:
                        with self.assertRaisesRegex(RuntimeError, 'status 7'):
                            process.bounded(command, directory)
                    else:
                        self.assertGreaterEqual(process.bounded(command, directory), 0)
                    cleanup.assert_not_called()
                self.assertEqual(reserve.read_json(directory / 'execution.json')['exit_code'], status)


class VersionBoundaryTests(unittest.TestCase):
    def test_historical_receipts_dispatch_without_mutating_historical_modules(self):
        legacy_bounded = historical_reserve.engine.bounded
        with mock.patch.object(reserve, 'read_json', return_value=dict(stage='fgiemit_reserve_execution_v1')), \
                mock.patch.object(historical_reserve, 'verify', return_value='old reserve') as verify:
            self.assertEqual(reserve.verify(Path('/root'), Path('/prepared'), Path('/run')), 'old reserve')
            verify.assert_called_once()
        with mock.patch.object(pipeline, 'read_json', return_value=dict(schema_version=1)), \
                mock.patch.object(pipeline.prepared_inputs, 'check_location'), \
                mock.patch.object(historical_pipeline, 'verify', return_value='old products') as verify:
            self.assertEqual(pipeline.verify(Path('/root'), Path('/products')), 'old products')
            verify.assert_called_once()
        self.assertIs(historical_reserve.engine.bounded, legacy_bounded)
        self.assertIs(reserve.engine.bounded, process.bounded)
        self.assertIs(historical_pipeline.reserve, historical_reserve)

    def test_new_receipt_binds_versioned_code_before_first_cell(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            root, prepared, out = (base / n for n in ('development', 'prepared', 'run'))
            root.mkdir(); (prepared / 'contract').mkdir(parents=True)
            reserve.write_json(root / 'development_checkpoint_provenance_v2.json', dict(gpu_root=str(base/'gpu')))
            for name in ('manifest.json', 'contract/matrix.json'):
                reserve.write_json(prepared/name, {})
            (prepared/'contract/reference_apexes.csv').write_text('plot,instance\n1003,1\n')
            cells = [dict(plot=p, arm=a, reference_count=n) for p,n in
                zip(reserve.inputs.policy.RESERVE, reserve.inputs.policy.RESERVE_COUNTS)
                for a in reserve.inputs.policy.ARMS]
            matrix = dict(cells=cells, runtime_directory=str(base/'runtime'))

            def fail(*args):
                receipt = reserve.read_json(out/'run.json')
                self.assertEqual(receipt['schema_version'], 2)
                self.assertEqual(receipt['stage'], 'fgiemit_reserve_execution_v2')
                self.assertEqual(receipt['code_sha256'], reserve.code_hashes())
                self.assertIn('scripts/fgiemit_process_v2.py', receipt['code_sha256'])
                raise RuntimeError('controlled failure')

            with mock.patch.object(reserve, 'preflight', return_value=matrix), \
                    mock.patch.object(reserve.engine, 'run_cell', side_effect=fail) as run:
                self.assertFalse(reserve.run(root, prepared, out))
                self.assertEqual(run.call_count, 1)
                receipt = reserve.verify(root, prepared, out)
                self.assertTrue(receipt['expansion_stopped'])
                receipt['code_sha256']['scripts/fgiemit_process_v2.py'] = 'changed'
                reserve.write_json(out/'run.json', receipt)
                with self.assertRaisesRegex(ValueError, 'code or outputs changed'):
                    reserve.verify(root, prepared, out)

    def test_sink_creation_or_write_failure_precedes_inference(self):
        for operation in ('mkdir', 'write'):
            with self.subTest(operation=operation), tempfile.TemporaryDirectory() as tmp:
                base = Path(tmp); root = base/'development'; root.mkdir()
                out = base/'products'
                target = mock.patch.object(Path, 'mkdir', side_effect=PermissionError('sink unavailable')) \
                    if operation == 'mkdir' else mock.patch.object(pipeline, 'write_json',
                        side_effect=PermissionError('sink not writable'))
                with target, mock.patch.object(pipeline.reserve, 'run') as run:
                    with self.assertRaises(PermissionError):
                        pipeline.assemble(root, 'reserve', base/'prepared', base/'run', out, execute=True)
                    run.assert_not_called()

    def test_pipeline_code_is_bound_before_optional_inference(self):
        with tempfile.TemporaryDirectory() as tmp:
            base=Path(tmp); root=base/'development'; root.mkdir(); out=base/'products'
            current = {'pipeline': 'loaded-version'}

            def hashes(*args):
                return dict(current)

            def execute(*args):
                current['pipeline'] = 'changed-during-inference'

            with mock.patch.object(pipeline.prepared_inputs.policy, 'hashes', side_effect=hashes), \
                    mock.patch.object(pipeline.reserve, 'run', side_effect=execute) as run, \
                    mock.patch.object(pipeline, 'get_inputs') as inputs:
                with self.assertRaisesRegex(ValueError, 'code changed during execution'):
                    pipeline.assemble(root, 'reserve', base/'prepared', base/'run', out, execute=True)
                run.assert_called_once()
                inputs.assert_not_called()
            self.assertEqual(pipeline.read_json(out/'assembly_status.json')['state'], 'failed')
            self.assertFalse((out/'manifest.json').exists())

    def test_later_preflight_failure_preserves_product_failure_status(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp); root=base/'development'; root.mkdir(); out=base/'products'
            with mock.patch.object(pipeline, 'get_inputs', side_effect=ValueError('parent mismatch')):
                with self.assertRaisesRegex(ValueError, 'parent mismatch'):
                    pipeline.assemble(root, 'reserve', base/'prepared', base/'run', out)
            status = pipeline.read_json(out/'assembly_status.json')
            self.assertEqual(status['state'], 'failed')
            self.assertIn('parent mismatch', status['error'])
            self.assertFalse((out/'manifest.json').exists())

    def test_prior_contract_attempt_blocks_fresh_run_regardless_of_state(self):
        for state in ('running', 'failed', 'planned', 'successful_nonempty'):
            with self.subTest(state=state), tempfile.TemporaryDirectory() as tmp:
                base=Path(tmp); prepared=base/'prepared'; prepared.mkdir()
                prior=base/'prior'; prior.mkdir()
                parent = {'contract/matrix.json': 'sealed-contract'}
                reserve.write_json(prior/'run.json', dict(prepared_directory=str(prepared),
                    parent_sha256=parent, cells=[dict(state=state)]))
                with mock.patch.object(reserve, 'parents', return_value=parent):
                    with self.assertRaisesRegex(ValueError, 'already has an attempt'):
                        reserve.claim_attempt(prepared, base/'fresh')
                self.assertFalse((base/'fresh').exists())

    def test_atomic_contract_claim_allows_only_one_competing_caller(self):
        from concurrent.futures import ThreadPoolExecutor
        with tempfile.TemporaryDirectory() as tmp:
            base=Path(tmp); prepared=base/'prepared'; prepared.mkdir()
            with mock.patch.object(reserve, 'parents', return_value={'contract/matrix.json': 'contract'}):
                with ThreadPoolExecutor(max_workers=2) as pool:
                    futures=[pool.submit(reserve.claim_attempt, prepared, base/name)
                             for name in ('first', 'second')]
                successes, failures = [], []
                for future in futures:
                    try:
                        successes.append(future.result())
                    except ValueError as error:
                        failures.append(error)
                self.assertEqual(len(successes), 1)
                self.assertEqual(len(failures), 1)
                self.assertTrue((successes[0]/'attempt.json').is_file())
                with self.assertRaisesRegex(ValueError, 'already has an attempt claim'):
                    reserve.claim_attempt(prepared, base/'third')

    def test_development_rejects_ignored_parent_arguments_before_read_or_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            base=Path(tmp); root=base/'development'; root.mkdir(); out=base/'products'
            for prepared,run in ((base/'arbitrary-prepared',None), (None,base/'arbitrary-run')):
                with self.subTest(prepared=prepared,run=run), \
                        mock.patch.object(pipeline, 'get_inputs') as inputs, \
                        mock.patch.object(pipeline.reserve, 'run') as inference:
                    with self.assertRaisesRegex(ValueError, 'Development parents'):
                        pipeline.assemble(root, 'development', prepared, run, out)
                    inputs.assert_not_called()
                    inference.assert_not_called()
                    self.assertFalse(out.exists())
            out.mkdir()
            pipeline.write_json(out/'manifest.json', dict(stage='development',
                method='selected_policy', prepared_directory=None, run_directory=str(base/'arbitrary-run')))
            with mock.patch.object(pipeline, 'verify') as verify:
                with self.assertRaisesRegex(ValueError, 'Development parents'):
                    pipeline.main(['--root',str(root),'--out',str(out),'--verify',
                                   '--run',str(base/'arbitrary-run')])
                verify.assert_not_called()

    def test_verify_honors_explicit_expected_options_before_parent_replay(self):
        with tempfile.TemporaryDirectory() as tmp:
            base=Path(tmp); root=base/'development'; root.mkdir(); out=base/'products'; out.mkdir()
            manifest=dict(stage='development', method='consensus_point', prepared_directory=None,
                          run_directory=None, product_ready=True)
            pipeline.write_json(out/'manifest.json', manifest)
            common=['--root', str(root), '--out', str(out), '--verify']
            with mock.patch.object(pipeline, 'verify', return_value=manifest) as verify:
                for option,value in (('--stage','reserve'), ('--method','selected_policy'),
                                     ('--prepared',str(base/'prepared')), ('--run',str(base/'run'))):
                    with self.subTest(option=option), self.assertRaisesRegex(ValueError, 'differs|Development parents'):
                        pipeline.main(common+[option,value])
                    verify.assert_not_called()
                self.assertEqual(pipeline.main(common), 0)
                self.assertEqual(pipeline.main(common+['--stage','development',
                    '--method','consensus_point']), 0)
                self.assertEqual(verify.call_count, 2)

    def test_scientific_functions_are_unchanged(self):
        for old, new, functions in (
                (historical_reserve.engine, reserve.engine, ('docker_command', 'run_cell')),
                (historical_pipeline, pipeline, ('get_inputs', 'input_tables', 'pooled_metrics', 'export_instances'))):
            for name in functions:
                with self.subTest(name=name):
                    self.assertEqual(ast.dump(ast.parse(inspect.getsource(getattr(old, name)))),
                                     ast.dump(ast.parse(inspect.getsource(getattr(new, name)))))


if __name__ == '__main__':
    unittest.main()
