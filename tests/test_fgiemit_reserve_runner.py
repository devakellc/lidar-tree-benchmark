"""Reserve execution boundaries and failure preservation, without inference."""
import ast
import copy
import inspect
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import run_fgiemit_reserve as runner
import run_fgiemit_pilot as pilot


class ReserveRunnerTests(unittest.TestCase):
    def test_cell_algorithms_differ_only_by_explicit_input_path(self):
        original = inspect.getsource(pilot.run_cell)
        adapted = original.replace('root, gpu, runtime_dir, references', 'prepared, gpu, runtime_dir, references')
        adapted = adapted.replace('    prepared = root / "development_inputs" / plot\n', '')
        adapted = adapted.replace('docker_command(cell, directory, root, gpu)',
                                  'docker_command(cell, directory, prepared, gpu)')
        self.assertEqual(ast.dump(ast.parse(adapted)),
                         ast.dump(ast.parse(inspect.getsource(runner.engine.run_cell))))

    def test_failed_cell_stops_and_keeps_remaining_denominators(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            root, prepared, out = (base / n for n in ('development', 'inputs', 'run'))
            root.mkdir(); (prepared / 'contract').mkdir(parents=True)
            runner.write_json(root / 'development_checkpoint_provenance_v2.json', dict(gpu_root=str(base/'gpu')))
            for p in ('manifest.json', 'contract/matrix.json'):
                runner.write_json(prepared / p, {})
            (prepared / 'contract/reference_apexes.csv').write_text('plot,instance\n1003,1\n')
            cells = [dict(plot=p, arm=a, reference_count=n) for p,n in
                zip(runner.inputs.policy.RESERVE, runner.inputs.policy.RESERVE_COUNTS)
                for a in runner.inputs.policy.ARMS]
            matrix = dict(cells=cells, runtime_directory=str(base/'runtime'))
            with mock.patch.object(runner, 'preflight', return_value=matrix), \
                    mock.patch.object(runner.development, 'validate_success'), \
                    mock.patch.object(runner.engine, 'run_cell', side_effect=[
                        dict(state='successful_empty', predictions=0), RuntimeError('export mismatch')]) as run:
                self.assertFalse(runner.run(root, prepared, out))
                self.assertEqual(run.call_count, 2)
                receipt = runner.verify(root, prepared, out)
                self.assertEqual([c['state'] for c in receipt['cells']],
                                 ['successful_empty', 'failed'] + ['planned'] * 7)
                self.assertNotIn('predictions', receipt['cells'][1])
                self.assertEqual([c['reference_count'] for c in receipt['cells']],
                                 [54]*3 + [155]*3 + [48]*3)
                self.assertFalse((out/'1003/forestformer3d').exists())
                with self.assertRaisesRegex(ValueError, 'existing attempt'):
                    runner.run(root, prepared, out)
                for change in ('reordered', 'after_failure', 'denominator'):
                    bad = copy.deepcopy(receipt)
                    if change == 'reordered': bad['cells'].reverse()
                    elif change == 'after_failure': bad['cells'][2]['state'] = 'successful_empty'
                    else: bad['cells'][0]['reference_count'] = 53
                    with self.subTest(change=change), self.assertRaises(ValueError):
                        runner.validate_records(bad, matrix, out)

    def test_outputs_must_be_fresh_siblings_outside_development(self):
        with tempfile.TemporaryDirectory() as tmp:
            base=Path(tmp); root=base/'development'; prepared=base/'prepared'
            root.mkdir(); prepared.mkdir()
            for out in (root/'run', prepared, prepared/'run', base.parent/'run'):
                with self.subTest(out=out), self.assertRaises(ValueError):
                    runner.preflight(root, prepared, out)

    def test_reserve_containers_only_see_explicit_geometry_and_scratch(self):
        with tempfile.TemporaryDirectory() as tmp:
            base=Path(tmp); prepared=base/'prepared/inputs/1003'
            prepared.mkdir(parents=True)
            for arm in ('segmentanytree', 'forestformer3d'):
                directory=base/'run/1003'/arm; directory.mkdir(parents=True)
                cell=dict(plot='1003', arm=arm, config=dict(image='pinned-image'))
                with mock.patch.object(runner.engine.subprocess, 'run'):
                    command,_=runner.engine.docker_command(cell,directory,prepared,base/'gpu')
                mounts=[command[i+1] for i,x in enumerate(command) if x=='-v']
                self.assertIn(f'{prepared}/geometry.las:/input/geometry.las:ro',mounts)
                self.assertEqual([x for x in mounts if not x.endswith(':ro')],
                                 [f'{directory}/model_io:/output'])
                self.assertTrue(all(not (prepared/'reference.laz').is_relative_to(Path(x.split(':')[0]))
                                    for x in mounts))


if __name__ == '__main__':
    unittest.main()
