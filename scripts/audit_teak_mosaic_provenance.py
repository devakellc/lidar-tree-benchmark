"""Fixed-grid RGB compatibility on the frozen historical TEAK_043 context.

No resampling, alignment fitting, frame attribution, model, or scoring is done.
Full TIFF bytes are hashed; only context-intersection windows are requested.
GDAL may decode compressed blocks that extend beyond the requested window.
"""
import argparse
import csv
import hashlib
import io
import json
import os
from pathlib import Path
import platform
from urllib.parse import unquote, urlsplit

import numpy as np
import rasterio
from rasterio.windows import Window

REPO = Path(__file__).resolve().parents[1]
CONFIG = REPO / 'docs/teak-mosaic-provenance-sources.json'
CONFIG_SHA256 = 'b6b73771a2f20b91143724df1e6f4a1b0e3a93cef985613b9ff04f0d393ba3ee'
CORE = [321034.5, 321074.5, 4096711.1, 4096751.1]
CONTEXT = [321009.5, 321099.5, 4096686.1, 4096776.1]
PARENTS = {
    'pilot': 'ac1e50570d2b383e517ccd3c49ca7ae543068ffd6e88ad06b5339fe971c066af',
    'timing': '41ebec99909fe29719bb52c5e1606738980132cbbf416ae608aa52fd78653bec',
}
GATES = dict(candidate_match_inventory_complete=True, exact_rgb_pixel_provenance=False,
             exact_lidar_rgb_lag='unknown', temporal_agreement_verified=False,
             reference_review_complete=False,
             registration_verified=False, real_scores=False, evaluation_ready=False,
             checkpoint_exposure='unknown', reserved_plots_processed=[])


def require(value, message):
    if not value:
        raise ValueError(message)


def sha(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def safe_path(path, exists=True):
    path = Path(os.path.abspath(path))
    require(not any(p.is_symlink() for p in [path, *path.parents]), 'Symlink path rejected')
    if exists:
        require(path.exists(), 'Missing path: ' + str(path))
    return path


def child(root, relative):
    p = Path(relative)
    require(not p.is_absolute() and '..' not in p.parts and str(p) == relative,
            'Unsafe relative payload path')
    path = safe_path(root / p)
    require(path.is_file(), 'Payload is not a regular file')
    return path


def record(path, name=None):
    path = safe_path(path)
    return dict(path=name or str(path), bytes=path.stat().st_size, sha256=sha(path))


def checked(root, row):
    path = child(root, row['path'])
    require(record(path, row['path']) == {k: row[k] for k in ('path', 'bytes', 'sha256')},
            'Pinned payload changed: ' + str(path))
    return path


def read_json(path):
    return json.loads(Path(path).read_text())


def json_bytes(value):
    return (json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + '\n').encode()


def csv_rows(path):
    with Path(path).open(newline='') as stream:
        return list(csv.DictReader(stream))


def candidate_records(rows, count=23):
    variants = sorted({r['variant_sha256'] for r in rows})
    require(len(variants) == 2 and len(rows) == count * 2, 'Incomplete two-variant inventory')
    groups = []
    for variant in variants:
        local = [{k: v for k, v in r.items() if k not in
                  ('variant_sha256', 'variant_source_url')} for r in rows
                 if r['variant_sha256'] == variant]
        require(len(local) == count and len({r['frame_id'] for r in local}) == count,
                'Duplicate or missing full frame IDs')
        require(all(r['intersects_context'] == 'TRUE' and
                    r['in_dp1_product_inventory'] == 'TRUE' for r in local),
                'Candidate outside context or product inventory')
        groups.append(sorted(local, key=lambda r: r['frame_id']))
    require(groups[0] == groups[1], 'KMZ local records differ')
    return groups[0]


def declaration():
    require(sha(CONFIG) == CONFIG_SHA256, 'Fixed source declaration changed')
    value = read_json(CONFIG)
    require(value['core_extent'] == CORE and value['context_extent'] == CONTEXT
            and value['parent_receipts'] == PARENTS and value['gates'] == GATES,
            'Fixed study declaration changed')
    return value


def validate_inputs(native, pilot, timing, archive, frozen):
    inputs = [record(checked(archive.parent, frozen['acquisition_plan']))]
    for label, root in [('pilot', pilot), ('timing', timing)]:
        path = child(root, 'receipt.json')
        require(sha(path) == PARENTS[label], 'Pinned parent receipt changed: ' + label)
        receipt = read_json(path)
        require(receipt['evaluation_ready'] is False, 'Parent eligibility changed')
        inputs.append(record(path))
        require(len({r['path'] for r in receipt['outputs']}) == len(receipt['outputs']),
                'Duplicate parent output')
        for row in receipt['outputs']:
            inputs.append(record(checked(root, row)))
        if label == 'timing':
            for row in receipt['manifests']:
                inputs.append(record(checked(REPO, row)))
    ps = read_json(pilot / 'pilot_summary.json')
    require(ps['plot'] == 'TEAK_043' and ps['core_extent'] == CORE
            and ps['context_extent'] == CONTEXT and ps['epsg'] == 32611,
            'Fixed parent support changed')
    rows = candidate_records(csv_rows(timing / 'camera_context_candidates.csv'))
    require(rows == frozen['candidate_records'], 'Declared candidates differ from parent')
    require(sum(r['intersects_core'] == 'TRUE' for r in rows) == 21,
            'Context-only candidates lost')
    require([r['frame_id'] + '_ort.tif' for r in rows] ==
            [r['path'] for r in frozen['frames']], 'Candidate/source crosswalk differs')
    expected_names = {r['path'] for r in frozen['frames'] + frozen['archive_metadata']}
    # Supporting docs are outside the pixel-input contract. No unlisted raster,
    # mask, auxiliary metadata, partial download, or other root file is accepted.
    actual_names = {p.name for p in archive.iterdir() if p.name != 'docs'}
    require(actual_names == expected_names, 'Missing or extra source archive entry')
    if (archive / 'docs').exists():
        safe_path(archive / 'docs')
    for row in frozen['archive_metadata'] + frozen['frames'] + frozen['documentary_sources']:
        inputs.append(record(checked(archive, row)))
    listing = read_json(archive / 'DP1.30010.001_TEAK_2018-06.json')
    require(all(listing[k] == v for k, v in frozen['release'].items()),
            'Released inventory identity differs')
    for row in frozen['frames']:
        matches = [r for r in listing['files'] if r['name'] == row['path']]
        require(len(matches) == 1 and matches[0]['size'] == row['bytes'],
                'Released source missing, duplicated, or resized')
    retrieval = read_json(archive / 'retrieval.json')
    require(len(retrieval) == 23 and len({r['path'] for r in retrieval}) == 23,
            'Incomplete retrieval records')
    by_name = {r['path']: r for r in retrieval}
    for row in frozen['frames']:
        r = by_name.get(row['path'])
        require(r is not None and all(r[k] == row[k] for k in
                ('path', 'bytes', 'sha256', 'source_url', 'retrieved_utc')),
                'Retrieval provenance differs')
        require(all(r[k] == v for k, v in frozen['release'].items()), 'Retrieval release differs')
        url = urlsplit(r['source_url'])
        expected = '/neon-aop-products/2018/FullSite/D17/2018_TEAK_3/L1/Camera/Images/'
        require(url.scheme == 'https' and url.netloc == 'storage.googleapis.com'
                and not url.query and not url.fragment and url.path.startswith(expected)
                and unquote(url.path.rsplit('/', 1)[1]) == r['path'], 'Invalid stable source URL')
    inputs.append(record(checked(native, frozen['native_rgb'])))
    return sorted(inputs, key=lambda r: r['path'])


def grid_header(dataset):
    t = dataset.transform
    require(dataset.crs is not None and dataset.crs.to_epsg() == 32611, 'Unsupported RGB CRS')
    require(dataset.count == 3 and dataset.dtypes == ('uint8',) * 3,
            'Expected three uint8 RGB bands')
    require(tuple(c.name for c in dataset.colorinterp) == ('red', 'green', 'blue'),
            'Expected RGB channel order')
    require(np.allclose([t.a, t.b, t.d, t.e], [.1, 0, 0, -.1], rtol=0, atol=1e-10),
            'Unsupported rotated or non-0.1 m north-up grid')
    return dict(crs=dataset.crs.to_string(), transform=list(t)[:6],
                bounds=list(dataset.bounds), width=dataset.width, height=dataset.height,
                dtypes=list(dataset.dtypes), nodata=list(dataset.nodatavals),
                colorinterp=[c.name for c in dataset.colorinterp],
                mask_flags=[[m.name for m in flags] for flags in dataset.mask_flag_enums],
                compression=dataset.compression.name if dataset.compression else None,
                image_structure=dataset.tags(ns='IMAGE_STRUCTURE'),
                block_shapes=[list(s) for s in dataset.block_shapes])


def integer_window(dataset, extent):
    xmin, xmax, ymin, ymax = extent
    w = dataset.window(xmin, ymin, xmax, ymax)
    terms = np.array([w.col_off, w.row_off, w.width, w.height])
    require(np.allclose(terms, np.round(terms), rtol=0, atol=1e-6),
            'Source does not share the fixed pixel grid')
    return tuple(int(x) for x in np.round(terms))


def read_region(dataset, extent, require_full=False):
    """Return raw RGB, geometry and all-band mask validity; never boundless-read."""
    col, row, width, height = integer_window(dataset, extent)
    require(width > 0 and height > 0, 'Empty target window')
    c0, r0 = max(col, 0), max(row, 0)
    c1, r1 = min(col + width, dataset.width), min(row + height, dataset.height)
    if require_full:
        require(c0 == col and r0 == row and c1 == col + width and r1 == row + height,
                'Native L3 does not cover fixed context')
    rgb = np.zeros((3, height, width), dtype=np.uint8)
    geometry = np.zeros((height, width), dtype=bool)
    valid = geometry.copy()
    if c1 > c0 and r1 > r0:
        dest = (slice(r0 - row, r1 - row), slice(c0 - col, c1 - col))
        win = Window(c0, r0, c1 - c0, r1 - r0)
        rgb[(slice(None), *dest)] = dataset.read(window=win, masked=False)
        geometry[dest] = True
        valid[dest] = np.all(dataset.read_masks(window=win) != 0, axis=0)
    return rgb, geometry, valid


def count(mask):
    return int(np.count_nonzero(mask))


def popcount(bits):
    result = np.zeros(bits.shape, dtype=np.uint8)
    for ordinal in range(23):
        result += ((bits >> ordinal) & 1).astype(np.uint8)
    return result


def region_summary(geometry, valid, matches, nonzero, native_valid, native_zero, select, days):
    n = popcount(matches)
    day_count = np.zeros(n.shape, dtype=np.uint8)
    nonzero_day_count = np.zeros(n.shape, dtype=np.uint8)
    for bitmask in days.values():
        day_count += ((matches & bitmask) != 0).astype(np.uint8)
        nonzero_day_count += ((nonzero & bitmask) != 0).astype(np.uint8)
    return dict(pixels=count(select), native_invalid=count(select & ~native_valid),
                native_all_channels_zero=count(select & native_zero),
                no_geometric_candidate=count(select & (geometry == 0)),
                no_valid_pair=count(select & (valid == 0)),
                zero_matches=count(select & (n == 0)), one_match=count(select & (n == 1)),
                multiple_matches=count(select & (n > 1)),
                single_day_matches=count(select & (day_count == 1)),
                multi_day_matches=count(select & (day_count > 1)),
                unique_day_compatible_pixels={day: count(select & (day_count == 1)
                    & ((matches & bits) != 0)) for day, bits in sorted(days.items())},
                nonzero_single_day_matches=count(select & (nonzero_day_count == 1)),
                nonzero_multi_day_matches=count(select & (nonzero_day_count > 1)),
                nonzero_unique_day_compatible_pixels={day: count(select & (nonzero_day_count == 1)
                    & ((nonzero & bits) != 0)) for day, bits in sorted(days.items())},
                nonzero_zero_matches=count(select & (nonzero == 0)),
                nonzero_one_match=count(select & (popcount(nonzero) == 1)),
                nonzero_multiple_matches=count(select & (popcount(nonzero) > 1)))


def compare_frames(native_path, frames, context=CONTEXT, core=CORE):
    # Ignore all external sidecars, including PAM/nodata overrides and .msk files.
    with rasterio.Env(GDAL_DISABLE_READDIR_ON_OPEN='EMPTY_DIR', GDAL_PAM_ENABLED='NO'):
        with rasterio.open(native_path) as native:
            headers = [dict(role='native_L3', frame_id='', **grid_header(native))]
            rgb, _, native_valid = read_region(native, context, require_full=True)
            c, r, w, h = integer_window(native, core)
            cc, rr, _, _ = integer_window(native, context)
            require(c >= cc and r >= rr and c + w <= cc + rgb.shape[2]
                    and r + h <= rr + rgb.shape[1], 'Core outside context')
            core_mask = np.zeros(native_valid.shape, dtype=bool)
            core_mask[r-rr:r-rr+h, c-cc:c-cc+w] = True
            transform = list(native.window_transform(Window(cc, rr, rgb.shape[2], rgb.shape[1])))[:6]
        shape = native_valid.shape
        geometry = np.zeros(shape, dtype='<u4')
        validity = geometry.copy()
        matches = geometry.copy()
        nonzero = geometry.copy()
        native_zero = np.all(rgb == 0, axis=0)
        native_achromatic = np.all(rgb == rgb[0], axis=0)
        native_255 = np.any(rgb == 255, axis=0)
        metrics, crosswalk, days = [], [], {}
        require(0 < len(frames) <= 23, 'No candidates or uint32 bitset capacity exceeded')
        for ordinal, frame in enumerate(frames):
            bit = np.uint32(1 << ordinal)
            day = frame['filename_utc'][:10]
            days[day] = days.get(day, np.uint32(0)) | bit
            with rasterio.open(frame['local_path']) as source:
                headers.append(dict(role='candidate_L1', frame_id=frame['frame_id'],
                                    **grid_header(source)))
                values, covered, source_valid = read_region(source, context)
            paired = native_valid & source_valid & covered
            same = paired & np.all(rgb == values, axis=0)
            zero = np.all(values == 0, axis=0) & covered
            geometry[covered] |= bit
            validity[paired] |= bit
            matches[same] |= bit
            nonzero[same & ~native_zero] |= bit
            crosswalk.append(dict(ordinal=ordinal, bit=int(bit), frame_id=frame['frame_id'],
                                  filename_utc=frame['filename_utc'], day=day,
                                  path=Path(frame['local_path']).name))
            for region, select in [('context', np.ones(shape, bool)), ('core', core_mask)]:
                metrics.append(dict(ordinal=ordinal, frame_id=frame['frame_id'], day=day,
                    region=region, pixels=count(select), geometric_overlap=count(select & covered),
                    outside=count(select & ~covered), source_invalid=count(select & covered & ~source_valid),
                    native_invalid_in_overlap=count(select & covered & ~native_valid),
                    valid_pairs=count(select & paired), exact_rgb_matches=count(select & same),
                    mismatches=count(select & paired & ~same),
                    source_all_channels_zero=count(select & zero),
                    equal_zero_ambiguous=count(select & same & native_zero),
                    equal_achromatic=count(select & same & native_achromatic),
                    equal_any_channel_255=count(select & same & native_255),
                    exact_nonzero_matches=count(select & same & ~native_zero)))
        arrays = dict(geometric_candidate_bits=geometry, valid_pair_bits=validity,
                      exact_match_bits=matches, exact_nonzero_match_bits=nonzero,
                      native_status=(native_valid.astype(np.uint8)
                                     | (native_zero.astype(np.uint8) << 1)
                                     | (native_achromatic.astype(np.uint8) << 2)
                                     | (native_255.astype(np.uint8) << 3)))
        summary = {region: region_summary(geometry, validity, matches, nonzero,
                   native_valid, native_zero, select, days)
                   for region, select in [('context', np.ones(shape, bool)), ('core', core_mask)]}
        return dict(headers=headers, frames=metrics, crosswalk=crosswalk, arrays=arrays,
                    regions=summary, transform=transform)


def csv_bytes(rows):
    stream = io.StringIO(newline='')
    writer = csv.DictWriter(stream, fieldnames=list(rows[0]), lineterminator='\n')
    writer.writeheader()
    writer.writerows(rows)
    return stream.getvalue().encode()


def products(result):
    summary = dict(schema_version=1, plot='TEAK_043',
        interpretation='fixed_grid_decoded_RGB_compatibility_only', **GATES,
        core_extent=CORE, context_extent=CONTEXT, epsg=32611,
        transform=result['transform'], regions=result['regions'],
        candidates=len(result['crosswalk']),
        native_status_bits={'0': 'all_RGB_masks_valid', '1': 'all_channels_zero',
                            '2': 'achromatic_triplet', '3': 'any_channel_255'},
        array_axes='row_southward,column_eastward; pixel centers are half a pixel inside edges',
        validity='all three raster masks valid; zeros remain raw and separately flagged',
        sidecars='external sidecars disabled; internal TIFF masks and nodata only',
        equality='all three uint8 values equal on the fixed grid; no resampling',
        nonzero_equality='raw valid-pair equality excluding all-channel-zero native triplets',
        read_scope='only context intersections requested; decoder blocks may extend beyond window')
    output = {'summary.json': json_bytes(summary), 'headers.json': json_bytes(result['headers']),
              'frame_diagnostics.csv': csv_bytes(result['frames']),
              'candidate_crosswalk.csv': csv_bytes(result['crosswalk'])}
    for name, array in result['arrays'].items():
        stream = io.BytesIO()
        np.save(stream, array, allow_pickle=False)
        output[name + '.npy'] = stream.getvalue()
    return output


def versions():
    return dict(python=platform.python_version(), numpy=np.__version__,
                rasterio=rasterio.__version__, gdal=rasterio.__gdal_version__)


def code_records():
    return [record(Path(__file__), 'scripts/' + Path(__file__).name),
            record(CONFIG, 'docs/' + CONFIG.name)]


def receipt(inputs, code, output):
    return dict(schema_version=1, plot='TEAK_043', **GATES, inputs=inputs, code=code,
                versions=versions(), outputs=[dict(path=name, bytes=len(data),
                sha256=hashlib.sha256(data).hexdigest()) for name, data in sorted(output.items())])


def verify_output(out, expected, expected_receipt):
    require({p.name for p in out.iterdir()} == set(expected) | {'receipt.json'},
            'Missing or extra output files')
    for name, data in {**expected, 'receipt.json': json_bytes(expected_receipt)}.items():
        require(child(out, name).read_bytes() == data, 'Recomputed output differs: ' + name)


def output_path(out, roots, verify):
    out = safe_path(out, exists=verify)
    for root in [*roots, REPO]:
        require(not out.is_relative_to(root) and not root.is_relative_to(out),
                'Output overlaps input or code tree')
    require(out.is_dir() if verify else not out.exists(),
            'Verification needs existing directory; a run needs a fresh output path')
    return out


def run(native, pilot, timing, archive, out, verify=False):
    roots = [safe_path(p) for p in (native, pilot, timing, archive)]
    native, pilot, timing, archive = roots
    out = output_path(out, roots, verify)
    frozen = declaration()
    inputs = validate_inputs(*roots, frozen)
    code = code_records()
    frames = [dict(row, local_path=str(archive / row['path'])) for row in frozen['frames']]
    result = compare_frames(native / frozen['native_rgb']['path'], frames)
    output = products(result)
    require(validate_inputs(*roots, frozen) == inputs and code_records() == code,
            'Inputs or code changed during analysis')
    expected_receipt = receipt(inputs, code, output)
    if verify:
        verify_output(out, output, expected_receipt)
    else:
        out.mkdir(parents=True, exist_ok=False)
        for name, data in output.items():
            with (out / name).open('xb') as stream:
                stream.write(data)
        # Receipt is last; interrupted writes cannot represent completion.
        with (out / 'receipt.json').open('xb') as stream:
            stream.write(json_bytes(expected_receipt))
        verify_output(out, output, expected_receipt)
    return result['regions']


def main():
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    for name in ('native', 'pilot', 'timing', 'archive', 'out'):
        parser.add_argument('--' + name, required=True, type=Path)
    parser.add_argument('--verify', action='store_true')
    args = parser.parse_args()
    try:
        print(json.dumps(run(**vars(args)), sort_keys=True))
    except (ValueError, OSError, KeyError, rasterio.errors.RasterioError) as exc:
        parser.exit(1, 'Audit failed: ' + str(exc) + '\n')


if __name__ == '__main__':
    main()
