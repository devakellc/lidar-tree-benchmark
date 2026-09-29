"""Synthetic contracts; no real TEAK pixels or network access."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import numpy as np
import rasterio
from rasterio.transform import from_origin

SPEC = importlib.util.spec_from_file_location(
    'mosaic', Path(__file__).resolve().parents[1] / 'scripts/audit_teak_mosaic_provenance.py')
m = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(m)


class MosaicTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.context = [0, .4, 0, .4]
        self.core = [.1, .3, .1, .3]
        self.rgb = np.full((3, 4, 4), 17, dtype=np.uint8)
        self.rgb[:, 0, 0] = 0
        self.rgb[:, 0, 1] = [255, 15, 16]
        self.rgb[:, 0, 2] = [1, 2, 3]

    def tearDown(self):
        self.temp.cleanup()

    def raster(self, name, values=None, x=0, y=.4, mask=None, **kwargs):
        values = self.rgb if values is None else values
        path = self.root / name
        profile = dict(driver='GTiff', count=3, width=values.shape[2],
                       height=values.shape[1], dtype=values.dtype, crs='EPSG:32611',
                       transform=from_origin(x, y, .1, .1), photometric='RGB')
        profile.update(kwargs)
        with rasterio.Env(GDAL_TIFF_INTERNAL_MASK=True):
            with rasterio.open(path, 'w', **profile) as ds:
                ds.write(values)
                if mask is not None:
                    ds.write_mask(mask)
        return path

    def frame(self, path, day='2018-06-14'):
        return dict(local_path=str(path), frame_id=path.stem,
                    filename_utc=day + 'T00:00:00Z')

    def compare(self, native, frames):
        return m.compare_frames(native, frames, self.context, self.core)

    def test_partial_coverage_zero_padding_and_ambiguity(self):
        native = self.raster('native.tif')
        full = self.raster('full.tif')
        partial = self.raster('partial.tif', self.rgb[:, :, 2:], x=.2)
        other = self.raster('other.tif')
        result = self.compare(native, [self.frame(full), self.frame(partial),
                                     self.frame(other, '2018-06-15')])
        raw = result['arrays']['exact_match_bits']
        self.assertTrue(np.all(raw[:, :2] == 5))
        self.assertTrue(np.all(raw[:, 2:] == 7))
        self.assertEqual(result['arrays']['exact_nonzero_match_bits'][0, 0], 0)
        self.assertEqual(result['arrays']['native_status'][0, 0], 7)
        self.assertEqual(result['arrays']['native_status'][0, 1], 9)
        self.assertEqual(result['regions']['context']['multiple_matches'], 16)
        self.assertEqual(result['regions']['context']['multi_day_matches'], 16)
        partial_row = result['frames'][2]
        self.assertEqual(partial_row['outside'], 8)
        self.assertEqual(partial_row['exact_rgb_matches'], 8)
        self.assertEqual(partial_row['equal_zero_ambiguous'], 0)

    def test_no_candidates_and_outside_frame(self):
        native = self.raster('native.tif')
        with self.assertRaisesRegex(ValueError, 'No candidates'):
            self.compare(native, [])
        outside = self.raster('outside.tif', x=1)
        result = self.compare(native, [self.frame(outside)])
        self.assertEqual(result['regions']['context']['zero_matches'], 16)
        self.assertEqual(result['regions']['context']['no_geometric_candidate'], 16)
        self.assertEqual(result['frames'][0]['exact_rgb_matches'], 0)

    def test_masks_nodata_and_255_preserved(self):
        native = self.raster('native.tif')
        mask = np.full((4, 4), 255, dtype=np.uint8)
        mask[1, 1] = 0
        source = self.raster('source.tif', mask=mask)
        result = self.compare(native, [self.frame(source)])
        row = result['frames'][0]
        self.assertEqual(row['source_invalid'], 1)
        self.assertEqual(row['valid_pairs'], 15)
        self.assertEqual(row['equal_any_channel_255'], 1)
        self.assertEqual(result['arrays']['geometric_candidate_bits'][1, 1], 1)
        self.assertEqual(result['arrays']['valid_pair_bits'][1, 1], 0)
        nodata = self.raster('nodata.tif', nodata=0)
        result = self.compare(native, [self.frame(nodata)])
        self.assertEqual(result['frames'][0]['source_invalid'], 1)
        self.assertEqual(result['frames'][0]['source_all_channels_zero'], 1)
        self.assertEqual(result['frames'][0]['equal_zero_ambiguous'], 0)

    def test_external_masks_cannot_change_decoder_products(self):
        native = self.raster('native.tif')
        source = self.raster('source.tif')
        baseline = m.products(self.compare(native, [self.frame(source)]))
        for path in [native, source]:
            with rasterio.Env(GDAL_TIFF_INTERNAL_MASK=False):
                with rasterio.open(path, 'r+') as dataset:
                    dataset.write_mask(np.zeros((4, 4), dtype=np.uint8))
            self.assertTrue(Path(str(path) + '.msk').is_file())
            # Prove the external fixture affects an ordinary decoder.
            with rasterio.Env(GDAL_DISABLE_READDIR_ON_OPEN='FALSE'):
                with rasterio.open(path) as dataset:
                    self.assertFalse(np.any(dataset.read_masks()))
            self.assertEqual(baseline, m.products(self.compare(native, [self.frame(source)])))

    def test_external_pam_nodata_cannot_change_decoder_products(self):
        native = self.raster('native.tif')
        source = self.raster('source.tif')
        baseline = m.products(self.compare(native, [self.frame(source)]))
        for path in [native, source]:
            pam = Path(str(path) + '.aux.xml')
            pam.write_text('<PAMDataset>' + ''.join(
                f'<PAMRasterBand band="{band}"><NoDataValue>17</NoDataValue>'
                '</PAMRasterBand>' for band in [1, 2, 3]) + '</PAMDataset>')
            # The TIFF itself has no nodata; PAM alone changes default masks.
            with rasterio.Env(GDAL_DISABLE_READDIR_ON_OPEN='FALSE', GDAL_PAM_ENABLED='YES'):
                with rasterio.open(path) as dataset:
                    self.assertEqual(dataset.nodatavals, (17, 17, 17))
                    self.assertEqual(np.count_nonzero(np.all(dataset.read_masks() != 0, axis=0)), 3)
            self.assertEqual(baseline, m.products(self.compare(native, [self.frame(source)])))

    def test_exact_triplet_single_multiple_and_days(self):
        native = self.raster('native.tif')
        a = self.rgb.copy()
        a[:, 1, 1] += 1
        b = a.copy()
        b[2, 1, 2] += 1
        first = self.raster('a.tif', a)
        second = self.raster('b.tif', b)
        result = self.compare(native, [self.frame(first), self.frame(second)])
        region = result['regions']['context']
        self.assertEqual((region['zero_matches'], region['one_match'], region['multiple_matches']),
                         (1, 1, 14))
        self.assertEqual(region['single_day_matches'], 15)
        self.assertEqual(region['unique_day_compatible_pixels'], {'2018-06-14': 15})
        self.assertEqual(region['nonzero_unique_day_compatible_pixels'], {'2018-06-14': 14})
        self.assertEqual(region['multi_day_matches'], 0)
        self.assertEqual(sum(region[k] for k in ['zero_matches', 'one_match', 'multiple_matches']), 16)
        self.assertEqual(result['regions']['core']['pixels'], 4)

    def test_reject_grid_crs_dtype_rotation_and_missing_native_coverage(self):
        native = self.raster('native.tif')
        cases = [('shift.tif', dict(x=.05)), ('crs.tif', dict(crs='EPSG:32610')),
                 ('missing.tif', dict(crs=None)),
                 ('dtype.tif', dict(values=self.rgb.astype('uint16'))),
                 ('rotated.tif', dict(transform=rasterio.Affine(.1, .01, 0, 0, -.1, .4)))]
        for name, kwargs in cases:
            with self.subTest(name=name):
                source = self.raster(name, **kwargs)
                with self.assertRaises(ValueError):
                    self.compare(native, [self.frame(source)])
        small = self.raster('small.tif', self.rgb[:, :, 2:], x=.2)
        with self.assertRaisesRegex(ValueError, 'does not cover'):
            self.compare(small, [self.frame(native)])

    def candidates(self):
        return [dict(frame_id=f'full_{i}', placemark_name='reused_short_name',
                     variant_sha256=v, variant_source_url='https://example.org/' + v,
                     intersects_context='TRUE', intersects_core=str(i < 2),
                     in_dp1_product_inventory='TRUE', coordinates_lon_lat_alt=str(i))
                for v in ['a', 'b'] for i in range(3)]

    def test_candidate_records_reject_missing_extra_duplicate_or_changed_local(self):
        rows = self.candidates()
        self.assertEqual(len(m.candidate_records(rows, count=3)), 3)
        cases = [rows[:-1], rows + [rows[0]], [], [rows[0], *rows[2:]],
                 [rows[0], rows[0], *rows[2:]]]
        changed = copy.deepcopy(rows)
        changed[-1]['coordinates_lon_lat_alt'] = 'altered'
        cases.append(changed)
        changed = copy.deepcopy(rows)
        changed[-1]['in_dp1_product_inventory'] = 'FALSE'
        cases.append(changed)
        for bad in cases:
            with self.assertRaises(ValueError):
                m.candidate_records(bad, count=3)

    def test_checked_reject_tamper_escape_and_symlinks(self):
        path = self.root / 'data.bin'
        path.write_bytes(b'original')
        row = m.record(path, path.name)
        self.assertEqual(m.checked(self.root, row), path)
        path.write_bytes(b'changed!')
        with self.assertRaisesRegex(ValueError, 'Pinned payload'):
            m.checked(self.root, row)
        with self.assertRaises(ValueError):
            m.child(self.root, '../escape')
        link = self.root / 'link'
        link.symlink_to(path)
        with self.assertRaisesRegex(ValueError, 'Symlink'):
            m.safe_path(link)
        linked_dir = self.root / 'dirlink'
        linked_dir.symlink_to(self.root, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'Symlink'):
            m.safe_path(linked_dir / 'data.bin')

    def test_output_isolation_freshness_unknown_cli(self):
        root = self.root / 'input'
        root.mkdir()
        for path in [root, root / 'child', self.root]:
            with self.assertRaises(ValueError):
                m.output_path(path, [root], False)
        self.assertEqual(m.output_path(self.root / 'fresh', [root], False), self.root / 'fresh')
        result = subprocess.run([sys.executable, m.__file__, '--nat=foo'], capture_output=True)
        self.assertNotEqual(result.returncode, 0)

    def test_deterministic_products_and_resealed_gates_fail_replay(self):
        native = self.raster('native.tif')
        frame = self.raster('frame.tif')
        output = m.products(self.compare(native, [self.frame(frame)]))
        self.assertEqual(output, m.products(self.compare(native, [self.frame(frame)])))
        receipt = m.receipt([], [], output)
        out = self.root / 'output'
        out.mkdir()
        for name, data in {**output, 'receipt.json': m.json_bytes(receipt)}.items():
            (out / name).write_bytes(data)
        before = {p.name: (p.stat().st_mtime_ns, p.read_bytes()) for p in out.iterdir()}
        m.verify_output(out, output, receipt)
        after = {p.name: (p.stat().st_mtime_ns, p.read_bytes()) for p in out.iterdir()}
        self.assertEqual(before, after)
        summary = json.loads(output['summary.json'])
        summary['evaluation_ready'] = True
        bad_output = dict(output, **{'summary.json': m.json_bytes(summary)})
        (out / 'summary.json').write_bytes(bad_output['summary.json'])
        (out / 'receipt.json').write_bytes(m.json_bytes(m.receipt([], [], bad_output)))
        with self.assertRaisesRegex(ValueError, 'Recomputed output'):
            m.verify_output(out, output, receipt)
        # A receipt-only gate promotion also fails even with unmodified products.
        (out / 'summary.json').write_bytes(output['summary.json'])
        bad_receipt = dict(receipt, exact_rgb_pixel_provenance=True)
        (out / 'receipt.json').write_bytes(m.json_bytes(bad_receipt))
        with self.assertRaisesRegex(ValueError, 'receipt.json'):
            m.verify_output(out, output, receipt)

    def test_run_replay_and_input_tamper_without_writes(self):
        roots = [self.root / name for name in ['native', 'pilot', 'timing', 'archive']]
        for root in roots:
            root.mkdir()
        native = self.raster('native.tif')
        source = self.raster('source.tif')
        native.rename(roots[0] / 'native.tif')
        source.rename(roots[3] / 'source.tif')
        source = roots[3] / 'source.tif'
        frozen = dict(native_rgb={'path': 'native.tif'}, frames=[dict(
            path='source.tif', frame_id='source', filename_utc='2018-06-14T00:00:00Z')])
        pinned = m.record(source, source.name)
        def validate(*args):
            return [m.record(m.checked(roots[3], pinned))]
        out = self.root / 'run'
        compare = m.compare_frames
        def tiny_compare(native, frames):
            return compare(native, frames, self.context, self.core)
        with patch.object(m, 'declaration', return_value=frozen), \
                patch.object(m, 'validate_inputs', side_effect=validate), \
                patch.object(m, 'compare_frames', side_effect=tiny_compare):
            m.run(*roots, out)
            before = {p.name: (p.stat().st_mtime_ns, p.read_bytes()) for p in out.iterdir()}
            m.run(*roots, out, verify=True)
            after = {p.name: (p.stat().st_mtime_ns, p.read_bytes()) for p in out.iterdir()}
            self.assertEqual(before, after)
            source.write_bytes(source.read_bytes() + b'tamper')
            with self.assertRaisesRegex(ValueError, 'Pinned payload'):
                m.run(*roots, out, verify=True)
            after = {p.name: (p.stat().st_mtime_ns, p.read_bytes()) for p in out.iterdir()}
            self.assertEqual(before, after)
            source.unlink()
            with self.assertRaisesRegex(ValueError, 'Missing path'):
                m.run(*roots, self.root / 'missing-run')
            self.assertFalse((self.root / 'missing-run').exists())

    def test_declaration_resealed_promotion_rejected(self):
        value = m.declaration()
        self.assertEqual(len(value['frames']), 23)
        self.assertEqual(sum(r['bytes'] for r in value['frames']), 669643369)
        bad = self.root / 'declaration.json'
        value['gates']['evaluation_ready'] = True
        bad.write_bytes(m.json_bytes(value))
        with patch.object(m, 'CONFIG', bad):
            with self.assertRaisesRegex(ValueError, 'declaration changed'):
                m.declaration()
        with patch.object(m, 'CONFIG', bad), patch.object(m, 'CONFIG_SHA256', m.sha(bad)):
            with self.assertRaisesRegex(ValueError, 'study declaration changed'):
                m.declaration()


if __name__ == '__main__':
    unittest.main()
