"""Synthetic contracts for the no-reference historical TEAK smoke."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

import laspy
import numpy as np
from pyproj import CRS

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import teak_detector_smoke_lib as lib
import run_teak_detector_smoke as runner


def parents(n=100):
    h = laspy.LasHeader(point_format=3, version='1.2')
    h.scales = [.001, .001, .001]
    h.offsets = [320000, 4090000, 0]
    h.add_crs(CRS.from_epsg(32611))
    native = laspy.LasData(h)
    native.add_extra_dim(laspy.ExtraBytesParams(name='pilot_row', type=np.uint32))
    native.x = 321000 + np.arange(n) * .02
    native.y = 4096000 + np.arange(n) * .03
    native.z = 2100 + np.arange(n) * .1
    native.pilot_row = np.arange(n)
    native.point_source_id = 12 + np.arange(n) % 3
    native.classification = np.where(np.arange(n) % 7 == 0, 7, 2)
    native.return_number = 1 + np.arange(n) % 2
    native.number_of_returns = np.full(n, 2)
    native.user_data = np.arange(n) % 5
    native.gps_time = 120.25 + np.arange(n)
    native.red = np.arange(n) + 20
    native.withheld = np.arange(n) % 2
    normalized = lib.clone_cloud(native)
    normalized.add_extra_dim(laspy.ExtraBytesParams(name='Zref', type=np.float64))
    normalized.Zref = np.asarray(native.z)
    normalized.z = np.arange(n) * .05 - .2
    return native, normalized


def test_preparation(out):
    pilot = out / 'pilot'
    fixed = lib.declaration()
    return dict(paths=dict(runtime=str(out / 'runtime'), gpu=str(out / 'environment/gpu'), pilot=str(pilot)),
                origin=[321000, 4096000, 2100],
                support=dict(core=[321000, 321040, 4096000, 4096040],
                             context=[320975, 321065, 4095975, 4096065], pixel_m=.1,
                             hashes={str(pilot / 'native_context.laz'): 'native',
                                     str(pilot / 'normalized_context.laz'): 'normalized'},
                             chm=lib.chm_parameters(3.75, 5.36)),
                resources=dict(images=fixed['images'], checkpoints=fixed['checkpoints'],
                               model_source={'model.py': 'model-source-hash'}),
                cells=[dict(arm=a, command=['fake'], container=None) for a in lib.ARMS])


class PointContracts(unittest.TestCase):
    def setUp(self):
        self.native, self.normalized = parents()
        self.origin = [321000, 4096000, 2100]

    def test_local_translation_preserves_all_rows_and_negative_agl(self):
        lib.validate_parents(self.native, self.normalized, 100)
        for parent, agl in [(self.native, False), (self.normalized, True)]:
            staged = lib.transport(parent, self.origin, agl)
            self.assertIsNone(staged.header.parse_crs())
            np.testing.assert_array_equal(staged.source_row, parent.pilot_row)
            np.testing.assert_array_equal(staged.X, parent.X)
            self.assertEqual(list(staged.point_format.extra_dimension_names), ['source_row'])
            self.assertTrue(np.all(np.asarray(staged.classification) == 1))
            if agl:
                np.testing.assert_array_equal(staged.z, parent.z)
                self.assertLess(min(staged.z), 0)

    def test_parent_reorder_return_and_crs_rejected(self):
        for edit in ('row', 'return', 'crs', 'zref'):
            cloud = lib.clone_cloud(self.normalized)
            if edit == 'row':
                cloud.pilot_row[1] = 0
            elif edit == 'return':
                cloud.return_number[1] = 1
            elif edit == 'crs':
                cloud.header.add_crs(CRS.from_epsg(32610))
            else:
                cloud.Zref[1] += 1
            with self.subTest(edit=edit), self.assertRaises(ValueError):
                lib.validate_parents(self.native, cloud)

    def test_product_roundtrip_keeps_original_psid_and_every_dimension(self):
        raw = np.r_[np.full(50, 42), np.zeros(50)].astype(np.int64)
        with tempfile.TemporaryDirectory() as tmp:
            for parent in (self.native, self.normalized):
                path = Path(tmp) / 'product.laz'
                lib.export_product(parent, raw, raw, path)
                cloud = laspy.read(path)
                np.testing.assert_array_equal(cloud.point_source_id, self.native.point_source_id)
                lib.check_product(parent, cloud, raw, raw)
                cloud.user_data[0] = 9
                with self.assertRaises(ValueError):
                    lib.check_product(parent, cloud, raw, raw)

    def test_strict_adapter_alignment_duplicate_xyz_and_missing_fields(self):
        source = lib.transport(self.native, self.origin)
        source.X[1], source.Y[1], source.Z[1] = source.X[0], source.Y[0], source.Z[0]
        pred = lib.clone_cloud(source)
        pred.add_extra_dim(laspy.ExtraBytesParams(name='sat_row', type=np.uint32))
        pred.add_extra_dim(laspy.ExtraBytesParams(name='pred_instance', type=np.uint32))
        pred.sat_row = np.arange(100)
        pred.pred_instance = np.zeros(100)
        labels, _ = lib.aligned_labels(source, pred, 'segmentanytree')
        self.assertTrue(np.all(labels == 0))
        pred.sat_row[1] = 0
        with self.assertRaises(ValueError):
            lib.aligned_labels(source, pred, 'segmentanytree')
        pred.sat_row = np.arange(100)
        pred.header.offsets[0] += 1
        with self.assertRaises(ValueError):
            lib.aligned_labels(source, pred, 'segmentanytree')

    def test_fixed_filter_raw_extent_background_and_no_id_renumber(self):
        raw = np.r_[np.full(50, 42), np.full(30, 99), np.zeros(20)].astype(np.int64)
        filtered, _ = lib.fixed_filter(raw, np.asarray(self.native.z))
        self.assertEqual(set(filtered), {0, 42})
        self.assertTrue(np.all(filtered[50:] == 0))

    def test_proxy_clipping_degenerate_outside_and_agl_tie(self):
        native, normalized = parents(6)
        native.x = np.array([321000, 321002, 321004, 321004, 321010, 321012])
        native.y = np.array([4096000, 4096002, 4096004, 4096005, 4096010, 4096012])
        normalized.z = np.array([2, 2, 3, 4, 5, 6])
        labels = np.array([1, 1, 2, 2, 3, 3])
        support = dict(core=[321001, 321006, 4096001, 4096006],
                       context=[321000, 321090, 4096000, 4096090], pixel_m=.1)
        result = lib.instance_diagnostics(native, normalized, labels, labels, support)
        boxes = result['point_extent_proxies']
        self.assertEqual([b['status'] for b in boxes],
                         ['positive_area_intersection', 'degenerate_point_extent', 'outside_support'])
        self.assertEqual(boxes[0]['image_overlap_fraction'], .25)
        self.assertEqual(boxes[0]['clipped_pixel_box'], [0, 40, 10, 50])
        self.assertIsNone(boxes[1]['clipped_metric_box'])
        self.assertEqual(result['apexes'][0]['source_row'], 0)
        self.assertFalse(result['apexes'][0]['apex_in_core'])

    def test_successful_empty_neural_products(self):
        source = lib.transport(self.native, self.origin)
        pred = lib.clone_cloud(source)
        pred.add_extra_dim(laspy.ExtraBytesParams(name='sat_row', type=np.uint32))
        pred.add_extra_dim(laspy.ExtraBytesParams(name='pred_instance', type=np.uint32))
        pred.sat_row = np.arange(100)
        pred.pred_instance = np.zeros(100)
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            (directory / 'model_io').mkdir()
            pred.write(directory / 'model_io/predictions.laz')
            lib.write_json(directory / 'model_io/predictions.laz.json', dict(rows=100, background=100, export='native_full_cloud_before_background_removal'))
            support = dict(core=[0, 1, 0, 1], context=[-25, 26, -25, 26], pixel_m=.1)
            result = lib.neural_result(directory, source, self.native, self.normalized,
                                       'segmentanytree', support, write=True)
            self.assertEqual(result['counts']['retained_instances'], 0)
            self.assertEqual(result['counts']['filtered_background_points'], 100)
            self.assertEqual(result, lib.neural_result(directory, source, self.native,
                                                      self.normalized, 'segmentanytree', support))


class ExecutionContracts(unittest.TestCase):
    def test_persistent_claim_no_retry_even_after_crash(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            lib.write_json(out / 'preparation.json', test_preparation(out))
            runner.claim(out)
            with self.assertRaises(FileExistsError):
                runner.claim(out)
            with patch.object(runner, 'verify_preparation') as verify, self.assertRaises(ValueError):
                runner.execute(out)
            verify.assert_not_called()

    def test_first_failure_stops_later_cells_unknown(self):
        native, normalized = parents()
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            (out / 'prepared').mkdir()
            lib.transport(native, [321000, 4096000, 2100]).write(out / 'prepared/geometry.las')
            preparation = test_preparation(out)
            for arm in lib.ARMS:
                (out / arm).mkdir()
            lib.write_json(out / 'preparation.json', preparation)
            lib.write_json(out / 'states.json', [dict(arm=a, state='planned', counts=None) for a in lib.ARMS])
            with patch.object(runner, 'bounded', side_effect=TimeoutError('bounded')) as run:
                with self.assertRaises(TimeoutError):
                    runner.execute_cells(preparation, native, normalized, out)
                self.assertEqual(run.call_count, 1)
                self.assertEqual(run.call_args.kwargs['timeout'], 3600)
            states = lib.read_json(out / 'states.json')
            self.assertEqual([s['state'] for s in states], ['failed', 'planned', 'planned'])
            self.assertTrue(all(s['counts'] is None for s in states))
            self.assertTrue((out / 'attempt.json').exists())
            runner.validate_state_evidence(out, preparation, states)
            for key, value in [('error', ''), ('model_observed', False), ('counts', {}),
                               ('elapsed_seconds', -1), ('failure_phase', 'unknown')]:
                changed = copy.deepcopy(states)
                changed[0][key] = value
                with self.subTest(key=key), self.assertRaises(ValueError):
                    runner.validate_state_evidence(out, preparation, changed)

    def test_verify_prepared_never_runs_inference(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            lib.write_json(out / 'states.json', [dict(arm=a, state='planned', counts=None) for a in lib.ARMS])
            with patch.object(runner, 'verify_preparation', return_value=(test_preparation(out), None, None)), patch.object(runner, 'bounded') as run:
                result = runner.verify(out)
                self.assertIsNone(result['compatibility_true'])
                run.assert_not_called()

    def test_model_mounts_exclude_root_gpu_and_parents(self):
        out, gpu = Path('/tmp/smoke'), Path('/models/gpu')
        directory = out / 'segmentanytree'
        command = ['docker', 'run', '--network', 'none',
                   '-v', f'{out / "prepared/geometry.las"}:/input/geometry.las:ro',
                   '-v', f'{directory / "model_io"}:/output', '-v', f'{lib.REPO / "gpu"}:/adapter:ro']
        runner.check_mounts(command, directory, out, gpu)
        with self.assertRaises(ValueError):
            runner.check_mounts(command + ['-v', '/reference:/reference:ro'], directory, out, gpu)
        command[-1] = f'{gpu}:/adapter:ro'
        with self.assertRaises(ValueError):
            runner.check_mounts(command, directory, out, gpu)

    def test_all_empty_execution_verifies_without_inference_and_recomputes_exports(self):
        native, normalized = parents()
        origin = [321000, 4096000, 2100]
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)
            (out / 'prepared').mkdir()
            staged = lib.transport(native, origin)
            staged.write(out / 'prepared/geometry.las')
            support = dict(core=[321000, 321040, 4096000, 4096040],
                           context=[320975, 321065, 4095975, 4096065], pixel_m=.1)
            preparation = test_preparation(out)
            lib.write_json(out / 'preparation.json', preparation)
            lib.write_json(out / 'states.json', [dict(arm=a, state='planned', counts=None) for a in lib.ARMS])
            for arm in lib.ARMS:
                (out / arm).mkdir()

            def fake_detector(command, directory, **kwargs):
                if directory.name == 'chm_vwf':
                    (directory / 'raw_treetops.csv').write_text('x,y,z,instance\n')
                    (directory / 'peak_rss_kib.txt').write_text('100\n')
                else:
                    (directory / 'model_io').mkdir()
                    pred = lib.clone_cloud(staged)
                    if directory.name == 'segmentanytree':
                        pred.add_extra_dim(laspy.ExtraBytesParams(name='sat_row', type=np.uint32))
                        pred.add_extra_dim(laspy.ExtraBytesParams(name='pred_instance', type=np.uint32))
                        pred.sat_row = np.arange(100)
                        receipt = dict(rows=100, background=100, export='native_full_cloud_before_background_removal')
                    else:
                        pred.add_extra_dim(laspy.ExtraBytesParams(name='ff3d_row', type=np.uint32))
                        pred.add_extra_dim(laspy.ExtraBytesParams(name='ff3d_score', type=np.float32))
                        pred.ff3d_row = np.arange(100)
                        receipt = [dict(source_rows=100, points=100, layout='whole_scene')]
                    pred.write(directory / 'model_io/predictions.laz')
                    lib.write_json(directory / 'model_io/predictions.laz.json', receipt)
                lib.write_json(directory / 'execution.json', dict(exit_code=0, wall_seconds=.01))
                return .01

            with patch.object(runner, 'verify_preparation', return_value=(preparation, native, normalized)):
                with patch.object(runner, 'bounded', side_effect=fake_detector) as run:
                    receipt = runner.execute(out)
                    self.assertEqual(run.call_count, 3)
                self.assertTrue(receipt['compatibility_true'])
                self.assertEqual([s['state'] for s in receipt['states']], ['successful_empty'] * 3)
                with patch.object(runner, 'bounded', side_effect=AssertionError('inference in verify')) as run:
                    runner.verify(out)
                    run.assert_not_called()
                for key, value in [('schema_version', 999), ('model_observed', False),
                                   ('evaluation_ready', True), ('real_scores', True)]:
                    changed = dict(receipt, **{key: value})
                    lib.write_json(out / 'receipt.json', changed)
                    with self.subTest(key=key), self.assertRaisesRegex(ValueError, 'receipt claim'):
                        runner.verify(out)
                lib.write_json(out / 'receipt.json', receipt)
                # Even if somebody reseals hashes, derivation from raw predictions
                # must reject a changed table instead of trusting its counts.
                path = out / 'segmentanytree/diagnostics.json'
                diagnostics = lib.read_json(path)
                diagnostics['counts']['retained_instances'] = 1
                lib.write_json(path, diagnostics)
                receipt['output_sha256'] = lib.inventory(out, {'receipt.json', '__pycache__'})
                lib.write_json(out / 'receipt.json', receipt)
                with self.assertRaisesRegex(ValueError, 'Derived diagnostics'):
                    runner.verify(out)

    def test_complete_command_reconstruction_rejects_changed_prefix_or_image(self):
        out, gpu = Path('/tmp/smoke'), Path('/models/gpu')
        images = dict(segmentanytree='sha256:sat', forestformer3d='sha256:ff')
        for arm in lib.ARMS:
            cell = dict(arm=arm, container=None if arm == 'chm_vwf' else 'fgiemit-reserve-0123456789ab')
            command = runner.expected_command(cell, out, gpu, images)
            cell['command'] = command
            runner.validate_cell_command(cell, out, gpu, images)
            changed = list(command)
            changed[0] = 'another-command'
            with self.assertRaisesRegex(ValueError, 'Complete detector command'):
                runner.validate_cell_command(dict(cell, command=changed), out, gpu, images)
            if arm != 'chm_vwf':
                changed = list(command)
                changed[changed.index(images[arm])] = 'unreviewed:image'
                with self.assertRaisesRegex(ValueError, 'Complete detector command'):
                    runner.validate_cell_command(dict(cell, command=changed), out, gpu, images)

    def test_scientific_ledger_blocks_second_output_and_code_edit(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            first, second = root / 'one', root / 'two'
            first.mkdir()
            second.mkdir()
            preparation = test_preparation(first)
            preparation['paths']['gpu'] = str(root / 'gpu')
            lib.write_json(first / 'preparation.json', preparation)
            runner.claim(first)
            runner.verify_claim(first, preparation)
            changed = copy.deepcopy(preparation)
            changed['paths']['out'] = str(second)
            changed['code'] = {'runner.py': 'different-incidental-code'}
            lib.write_json(second / 'preparation.json', changed)
            self.assertEqual(runner.ledger_identity(preparation)[0], runner.ledger_identity(changed)[0])
            with self.assertRaises(FileExistsError):
                runner.claim(second)
            self.assertFalse((second / 'attempt.json').exists())
            # Losing the local record does not free the shared scientific claim.
            (first / 'attempt.json').unlink()
            with self.assertRaises(FileExistsError):
                runner.claim(first)

    def test_preparation_metadata_and_declaration_are_recomputed(self):
        native, normalized = parents()
        metadata = runner.preparation_metadata(native, normalized)
        runner.validate_preparation_metadata(metadata, native, normalized)
        for key, value in [('evaluation_ready', True), ('attempts', 2), ('schema_version', 999),
                           ('native_dimensions', ['X', 'Y', 'Z']), ('negative_agl_rows', 0),
                           ('source_rows_sha256', 'wrong'), ('origin', [0, 0, 0]),
                           ('model_observed', True), ('source_point_rows', 99)]:
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, 'Preparation metadata'):
                runner.validate_preparation_metadata(dict(metadata, **{key: value}), native, normalized)
        declaration = lib.read_json(lib.CONFIG)
        for key, value in [('attempts', 2), ('evaluation_ready', True), ('arms', ['forestformer3d']),
                           ('schema_version', 999), ('timeout_seconds', 7200)]:
            with patch.object(lib, 'read_json', return_value=dict(declaration, **{key: value})):
                with self.subTest(key=key), self.assertRaisesRegex(ValueError, 'declaration'):
                    lib.declaration()

    def test_chm_context_height_and_instance_admission(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            support = dict(core=[321000, 321040, 4096000, 4096040],
                           context=[320975, 321065, 4095975, 4096065])
            origin = [321000, 4096000, 2100]
            path = directory / 'raw_treetops.csv'
            path.write_text('x,y,z,instance\n-25,0,2,1\n65,0,3,2\n')
            self.assertEqual(lib.chm_result(directory, origin, support)['counts']['context_treetops'], 2)
            for rows in ('65.01,0,3,1\n', '0,-25.01,3,1\n', '0,0,1.9,1\n',
                         '0,0,3,0\n', '0,0,3,1\n1,1,3,1\n'):
                path.write_text('x,y,z,instance\n' + rows)
                with self.subTest(rows=rows), self.assertRaises(ValueError):
                    lib.chm_result(directory, origin, support)

    def test_output_archive_overlap_rejected(self):
        root = Path('/tmp/project')
        with self.assertRaises(ValueError):
            runner.protect_output(root / 'work/teak-native-pilot/new', root / 'pilot', root / 'policy', root / 'gpu', root / 'runtime')


if __name__ == '__main__':
    unittest.main(failfast=True)
