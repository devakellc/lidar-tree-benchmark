"""Contracts for dispatching accepted smoke verification to its sealed code."""
import contextlib
import io
import importlib.util
import json
import marshal
import os
from pathlib import Path
import subprocess
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import replay_teak_detector_smoke as replay


class HistoricalReplayTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.root = self.base / 'historical'
        self.out = self.base / 'accepted'
        self.current = self.base / 'current'
        for root in (self.root, self.current):
            (root / 'scripts').mkdir(parents=True)
        (self.root / 'gpu').mkdir()
        (self.root / 'docs').mkdir()
        self.out.mkdir()
        self.runner = self.root / replay.RUNNER
        self.runner.write_text(
            'import sys\n'
            'assert sys.argv[1:] == ["--verify", "--out", ' + repr(str(self.out)) + ']\n'
            'assert sys.dont_write_bytecode\n')
        for name in (replay.LIBRARY, replay.CHM, 'docs/teak-detector-smoke.json', 'gpu/adapter.py'):
            (self.root / name).write_text('{}\n')
        self.code = {str(path.relative_to(self.root)): replay.sha(path)
                     for path in self.root.rglob('*') if path.is_file()}
        self.preparation = {
            'paths': {'out': str(self.out)}, 'code': self.code,
            'cells': [{'arm': 'chm_vwf', 'command': [
                '/usr/bin/time', '-f', '%M', '-o', str(self.out / 'rss.txt'),
                'Rscript', str(self.root / replay.CHM), 'chm', 'input', 'config', 'output']}],
        }
        self.ledger = self.base / 'ledger.json'
        self.seal()
        self.pins = patch.object(replay, 'PINNED', self.identities)
        self.pins.start()
        self.addCleanup(self.pins.stop)
        self.git = patch.object(replay.subprocess, 'check_output', return_value=replay.HISTORICAL_COMMIT + '\n')
        self.git.start()
        self.addCleanup(self.git.stop)

    def seal(self):
        (self.out / 'preparation.json').write_text(json.dumps(self.preparation))
        attempt = {'preparation_sha256': replay.sha(self.out / 'preparation.json'),
                   'out': str(self.out), 'ledger_path': str(self.ledger)}
        (self.out / 'attempt.json').write_text(json.dumps(attempt))
        self.ledger.write_text(json.dumps(attempt))
        receipt = {'preparation_sha256': attempt['preparation_sha256'],
                   'attempt_sha256': replay.sha(self.out / 'attempt.json'),
                   'output_sha256': {name: digest for name, digest in replay.inventory(self.out).items()
                                     if name != 'receipt.json'}}
        (self.out / 'receipt.json').write_text(json.dumps(receipt))
        self.identities = {name: replay.sha(self.out / name) for name in replay.PINNED}

    def refused_without_dispatch(self, expected):
        with patch.object(replay.subprocess, 'run') as run:
            with self.assertRaisesRegex(ValueError, expected):
                replay.replay(self.out)
            run.assert_not_called()

    def test_valid_dispatch_ignores_unrelated_current_checkout_scripts(self):
        (self.current / 'scripts/new_analysis.R').write_text('stop("unrelated")\n')
        before = replay.inventory(self.out)
        cwd = Path.cwd()
        try:
            os.chdir(self.current)
            with patch.object(replay.subprocess, 'run', wraps=subprocess.run) as run:
                self.assertEqual(replay.replay(self.out), 0)
                argv = run.call_args.args[0]
                self.assertEqual(argv, [sys.executable, '-B', '-E', '-X', 'pycache_prefix=/dev/null',
                                        str(self.runner),
                                        '--verify', '--out', str(self.out)])
                self.assertEqual(run.call_args.kwargs['cwd'], self.root)
        finally:
            os.chdir(cwd)
        self.assertEqual(replay.inventory(self.out), before)

    def test_receipt_preparation_and_attempt_tampering(self):
        for name in replay.PINNED:
            with self.subTest(name=name):
                path = self.out / name
                original = path.read_bytes()
                path.write_bytes(original + b' ')
                self.refused_without_dispatch('Pinned historical identity changed')
                path.write_bytes(original)

    def test_substituted_command_path_is_rejected_before_execution(self):
        malicious = self.base / 'malicious/scripts'
        malicious.mkdir(parents=True)
        (malicious / 'fgiemit_pilot_cell.R').write_text('malicious')
        self.preparation['cells'][0]['command'][6] = str(malicious / 'fgiemit_pilot_cell.R')
        (self.out / 'preparation.json').write_text(json.dumps(self.preparation))
        self.refused_without_dispatch('Pinned historical identity changed')

    def test_every_sealed_code_file_is_checked_before_execution(self):
        for name in self.code:
            with self.subTest(name=name):
                path = self.root / name
                original = path.read_bytes()
                path.write_bytes(original + b'changed')
                self.refused_without_dispatch('Sealed historical code changed')
                path.write_bytes(original)

    def test_absent_historical_code_is_explicit_failure(self):
        self.runner.unlink()
        self.refused_without_dispatch('Required historical file is absent')

    def test_added_historical_code_is_rejected(self):
        (self.root / 'scripts/extra.py').write_text('')
        self.refused_without_dispatch('Historical code inventory changed')

    def test_unsealed_python_package_and_sourceless_module_are_rejected(self):
        directory = self.root / 'scripts/numpy'
        directory.mkdir()
        self.refused_without_dispatch('Unsealed Python package')
        directory.rmdir()
        (self.root / 'scripts/numpy.pyc').write_bytes(b'untrusted')
        self.refused_without_dispatch('Unsealed importable code')

    def test_unsealed_bytecode_cache_is_not_executed(self):
        helper = self.root / replay.LIBRARY
        self.runner.write_text('import teak_detector_smoke_lib\n')
        self.code[replay.RUNNER] = replay.sha(self.runner)
        self.seal()
        cache = Path(importlib.util.cache_from_source(str(helper)))
        cache.parent.mkdir()
        marker = self.base / 'untrusted-bytecode-ran'
        malicious = compile('open(' + repr(str(marker)) + ', "w").write("bad")', str(helper), 'exec')
        header = importlib.util.MAGIC_NUMBER + struct.pack('<III', 0,
                    int(helper.stat().st_mtime), helper.stat().st_size)
        cache.write_bytes(header + marshal.dumps(malicious))
        with patch.object(replay, 'PINNED', self.identities):
            self.assertEqual(replay.replay(self.out), 0)
        self.assertFalse(marker.exists())

    def test_sealed_code_symlink_is_rejected_even_with_equal_bytes(self):
        copy = self.base / 'runner.py'
        copy.write_bytes(self.runner.read_bytes())
        self.runner.unlink()
        self.runner.symlink_to(copy)
        self.refused_without_dispatch('Symlink is not allowed')

    def test_symlinked_historical_directory_is_rejected(self):
        scripts = self.root / 'scripts'
        moved = self.base / 'moved-scripts'
        scripts.rename(moved)
        scripts.symlink_to(moved, target_is_directory=True)
        self.refused_without_dispatch('Symlink is not allowed')

    def test_path_escape_in_code_inventory_is_rejected(self):
        for name in ('../escape.py', '/absolute.py', 'scripts/../escape.py'):
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, 'Invalid sealed code path'):
                replay.verify_code(self.root, dict(self.code, **{name: 'a' * 64}))

    def test_output_tampering_does_not_launch_verifier(self):
        (self.out / 'injected-output.txt').write_text('unexpected')
        self.refused_without_dispatch('Historical output inventory changed')

    def test_changed_ledger_does_not_launch_verifier(self):
        self.ledger.write_text('{}')
        self.refused_without_dispatch('Shared historical attempt claim changed')

    def test_changed_historical_commit_does_not_launch_verifier(self):
        with patch.object(replay.subprocess, 'check_output', return_value='other\n'):
            self.refused_without_dispatch('historical checkout revision changed')

    def test_failed_verifier_status_is_propagated(self):
        with patch.object(replay.subprocess, 'run', return_value=subprocess.CompletedProcess([], 17)):
            self.assertEqual(replay.replay(self.out), 17)

    def test_writes_by_verifier_are_detected(self):
        def mutate(*args, **kwargs):
            (self.out / 'unexpected').write_text('changed')
            return subprocess.CompletedProcess([], 0)
        with patch.object(replay.subprocess, 'run', side_effect=mutate):
            with self.assertRaisesRegex(ValueError, 'Historical artifacts changed during verification'):
                replay.replay(self.out)

    def test_execution_retry_and_code_override_flags_are_not_supported(self):
        for flag in ('--execute', '--prepare', '--retry', '--verify', '--code-root', '--ou'):
            with self.subTest(flag=flag), contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as raised:
                    replay.main(['--out', str(self.out), flag])
                self.assertEqual(raised.exception.code, 2)


if __name__ == '__main__':
    unittest.main()
