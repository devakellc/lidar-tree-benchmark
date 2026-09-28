"""One historical development smoke: row-safe transport and diagnostic exports."""
import copy
import csv
import hashlib
import json
import os
from pathlib import Path
import subprocess

import laspy
import numpy as np

from fgiemit_pilot_lib import aligned_labels, fixed_filter
from fgiemit_comparison_lib import chm_parameters
import prepare_fgiemit_pilot_runtime as runtime

REPO = Path(__file__).resolve().parents[1]
ARMS = ('chm_vwf', 'segmentanytree', 'forestformer3d')
CONFIG = REPO / 'docs/teak-detector-smoke.json'
EXCLUDED = {'.git', 'data', 'work_dirs', '__pycache__'}


def declaration():
    value = read_json(CONFIG)
    expected = dict(schema_version=1, plot='TEAK_043', role='historical_development_diagnostic',
                    evaluation_ready=False, real_scores=False, arms=list(ARMS),
                    timeout_seconds=3600, concurrency=1, attempts=1, fail_stop=True,
                    pilot_receipt_sha256='ac1e50570d2b383e517ccd3c49ca7ae543068ffd6e88ad06b5339fe971c066af',
                    policy_receipt_sha256='3dcfd975bff6dc5492a6c3430fc0e8e5ef816c87e18145aa30b262cb8a694ff4')
    for key, item in expected.items():
        require(type(value.get(key)) is type(item) and value[key] == item,
                'Invalid fixed smoke declaration: ' + key)
    require(set(value['images']) == set(ARMS[1:]) and set(value['checkpoints']) == set(ARMS[1:]),
            'Declared neural arms changed')
    require(value['images']['forestformer3d'] ==
            'sha256:fd60f5cdc5ae880af13b339f4aa1f1e891a3809c7f39fb15d2b5ff04978799f3',
            'Declared FF3D image changed')
    return value


def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def read_json(path):
    return json.loads(Path(path).read_text())


def write_json(path, value):
    path = Path(path)
    temporary = path.with_suffix(path.suffix + '.tmp')
    with temporary.open('w') as stream:
        json.dump(value, stream, indent=2, allow_nan=False)
        stream.write('\n')
        stream.flush()
        os.fsync(stream.fileno())
    temporary.replace(path)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def inventory(root, exclude=()):
    root = Path(root)
    result = {}
    for directory, dirs, files in os.walk(root, followlinks=False):
        dirs[:] = sorted(d for d in dirs if d not in exclude)
        for name in dirs + files:
            require(not (Path(directory) / name).is_symlink(), 'Symlink in sealed tree')
        for name in sorted(files):
            if name not in exclude:
                path = Path(directory) / name
                result[str(path.relative_to(root))] = sha(path)
    return result


def code_identity():
    # A conservative superset seals all transitive Python/R imports, including
    # scripts sourced by the existing CHM branch, plus the complete adapter mount.
    result = {str(p.relative_to(REPO)): sha(p) for p in sorted((REPO / 'scripts').iterdir())
              if p.is_file() and p.suffix in ('.py', '.R')}
    result.update({'gpu/' + k: v for k, v in inventory(REPO / 'gpu', {'__pycache__'}).items()})
    result['docs/teak-detector-smoke.json'] = sha(CONFIG)
    return result


def check_payloads(root, rows):
    result = {}
    for row in rows:
        path = (root / row['path']).resolve(strict=True)
        require(path.is_relative_to(root.resolve()), 'Parent payload escapes archive')
        require(path.stat().st_size == row['bytes'] and sha(path) == row['sha256'],
                'Parent payload changed: ' + str(path))
        result[str(path)] = row['sha256']
    return result


def parents(pilot, policy):
    frozen = declaration()
    hashes = {}
    receipts = {}
    for name, root in [('pilot', pilot), ('policy', policy)]:
        path = root / 'receipt.json'
        require(sha(path) == frozen[name + '_receipt_sha256'], 'Pinned parent receipt changed')
        receipt = read_json(path)
        require(receipt['evaluation_ready'] is False, 'Parent evaluation flag changed')
        receipts[name] = receipt
        hashes[str(path)] = sha(path)
        hashes.update(check_payloads(root, receipt['outputs']))
    # Verify linked receipts/manifests by bytes; do not deserialize annotations.
    for row in receipts['policy']['inputs']:
        path = Path(row['path']).resolve(strict=True)
        require(('bytes' not in row or path.stat().st_size == row['bytes']) and sha(path) == row['sha256'],
                'Policy parent link changed')
        hashes[str(path)] = row['sha256']
    package_path = Path(receipts['policy']['inputs'][0]['path'])
    package = read_json(package_path)
    hashes.update(check_payloads(package_path.parent, package['outputs']))
    require(receipts['policy']['verified_parent_outputs']['package'] == package['outputs'],
            'Policy package payload link changed')
    require(receipts['policy']['verified_parent_outputs']['pilot'] == receipts['pilot']['outputs'],
            'Policy pilot payload link changed')
    for name, expected in [('teak-native-pilot-sources.json', receipts['pilot']['manifest_sha256']),
                           ('teak-canopy-sources.json', receipts['pilot']['parent_manifest_sha256'])]:
        require(sha(REPO / 'docs' / name) == expected, 'Linked source manifest changed')
        hashes[str(REPO / 'docs' / name)] = expected
    ps = read_json(pilot / 'pilot_summary.json')
    for arm in ARMS[1:]:
        require(frozen['checkpoints'][arm] == ps['checkpoint_review']['checkpoints'][arm]['sha256'],
                'Declared checkpoint differs from pinned parent')
    require(frozen['images']['segmentanytree'] == ps['checkpoint_review']['checkpoints']['segmentanytree']['image_digest'],
            'Declared SAT image differs from pinned parent')
    cs = read_json(policy / 'policy_summary.json')
    require(ps['plot'] == 'TEAK_043' and ps['role'] == 'historical_development_pilot'
            and ps['evaluation_ready'] is False and cs['real_scores'] is False
            and cs['evaluation_ready'] is False, 'Not the declared development diagnostic')
    roles = cs['policy']['plots']
    require([p for p in roles if p['plotID'] == 'TEAK_043'] ==
            [dict(plotID='TEAK_043', spatial_group='TEAK_043', role='development', evaluation_ready=False)],
            'TEAK_043 role changed')
    reserved = [p['plotID'] for p in roles if p['role'] == 'reserved_unadmitted']
    require(len(reserved) == 11 and cs['policy']['pilot_receipt_sha256'] == frozen['pilot_receipt_sha256'],
            'Reservation or pilot link changed')
    with (policy / 'plot_policy.csv').open() as stream:
        plot = next(r for r in csv.DictReader(stream) if r['plotID'] == 'TEAK_043')
    core = [float(plot['rgb_' + k]) for k in ('xmin', 'xmax', 'ymin', 'ymax')]
    require(core == ps['core_extent'] and int(plot['rgb_epsg']) == ps['epsg'] == 32611,
            'Image frame changed')
    with (pilot / 'density.csv').open() as stream:
        density = {r['footprint']: {k: float(v) for k, v in r.items() if k != 'footprint'}
                   for r in csv.DictReader(stream)}
    d = density['context_25m']
    require(d['n_points'] == ps['source_point_rows'] == ps['normalized_point_rows'] == 43460
            and d['area_m2'] == 8100 and d['first_returns'] == 30398, 'Context support changed')
    for name in ('context_25m', 'image_core'):
        r = density[name]
        require(np.isclose(r['frdens'], r['first_returns'] / r['area_m2'])
                and np.isclose(r['pdens'], r['n_points'] / r['area_m2']), 'Density denominator changed')
    return dict(hashes=hashes, core=core, context=ps['context_extent'], epsg=32611,
                pixel_m=float(plot['rgb_resolution_m']), density=density,
                chm=dict(chm_parameters(d['frdens'], d['pdens']), frdens=d['frdens'], pdens=d['pdens']),
                reserved_unadmitted=reserved, checkpoints=ps['checkpoint_review']['checkpoints'])


def validate_parents(native, normalized, expected_rows=None):
    n = len(native.points)
    require(expected_rows is None or n == expected_rows, 'Unexpected native point count')
    require(len(normalized.points) == n, 'Normalized point count changed')
    for cloud in (native, normalized):
        require('pilot_row' in cloud.point_format.dimension_names, 'Missing pilot_row')
        require(np.array_equal(cloud.pilot_row, np.arange(n)), 'Parent row order changed')
        require(cloud.header.parse_crs() is not None and cloud.header.parse_crs().to_epsg() == 32611,
                'Wrong parent CRS')
        require(np.isfinite(np.column_stack((cloud.x, cloud.y, cloud.z))).all(), 'Nonfinite parent geometry')
    require(np.array_equal(native.header.scales, normalized.header.scales)
            and np.array_equal(native.header.offsets[:2], normalized.header.offsets[:2]),
            'Normalization frame changed')
    require('Zref' in normalized.point_format.dimension_names, 'Missing normalized absolute Zref')
    require(np.allclose(normalized.Zref, native.z, rtol=0, atol=native.header.scales[2] / 2),
            'Normalized Zref differs from absolute native Z')
    for name in native.point_format.dimension_names:
        if name != 'Z':
            require(name in normalized.point_format.dimension_names
                    and np.array_equal(native[name], normalized[name]), 'Normalization changed ' + name)


def transport(parent, origin, normalized=False):
    header = laspy.LasHeader(point_format=7, version='1.4')
    header.scales = parent.header.scales.copy()
    header.offsets = parent.header.offsets - np.array([origin[0], origin[1], 0 if normalized else origin[2]])
    cloud = laspy.LasData(header)
    cloud.add_extra_dim(laspy.ExtraBytesParams(name='source_row', type=np.uint32))
    for name in ('X', 'Y', 'Z', 'return_number', 'number_of_returns'):
        cloud[name] = np.asarray(parent[name]).copy()
    cloud.classification = np.ones(len(parent.points), dtype=np.uint8)
    cloud.source_row = np.asarray(parent.pilot_row, dtype=np.uint32)
    validate_transport(parent, cloud, origin, normalized)
    return cloud


def validate_transport(parent, staged, origin, normalized=False):
    require(staged.header.parse_crs() is None, 'Invented CRS on local coordinates')
    require(list(staged.point_format.extra_dimension_names) == ['source_row'], 'Extra model labels')
    require(np.array_equal(staged.source_row, parent.pilot_row), 'Transport source rows changed')
    require(np.array_equal(staged.header.scales, parent.header.scales), 'Transport precision changed')
    shift = np.array([origin[0], origin[1], 0 if normalized else origin[2]])
    require(np.array_equal(staged.header.offsets, parent.header.offsets - shift), 'Local offsets changed')
    for name in ('X', 'Y', 'Z', 'return_number', 'number_of_returns'):
        require(np.array_equal(staged[name], parent[name]), 'Transport changed ' + name)
    restored = np.column_stack((staged.x, staged.y, staged.z)) + shift
    require(np.allclose(restored, np.column_stack((parent.x, parent.y, parent.z)), rtol=0, atol=1e-8),
            'Translation is not reversible')
    require(np.all(np.asarray(staged.classification) == 1), 'Model classification is not synthetic')
    for name in staged.point_format.dimension_names:
        if name not in ('X', 'Y', 'Z', 'return_number', 'number_of_returns', 'classification', 'source_row'):
            require(np.all(np.asarray(staged[name]) == 0), 'Unexpected model attribute: ' + name)


def check_product(parent, product, raw, filtered):
    require(len(parent.points) == len(product.points), 'Export dropped rows')
    require(product.header.parse_crs() == parent.header.parse_crs()
            and np.array_equal(product.header.scales, parent.header.scales)
            and np.array_equal(product.header.offsets, parent.header.offsets), 'Export changed frame')
    expected = set(parent.point_format.dimension_names) | {'raw_pred_instance', 'pred_instance'}
    require(set(product.point_format.dimension_names) == expected, 'Export dimensions changed')
    for name in parent.point_format.dimension_names:
        require(np.array_equal(parent[name], product[name]), 'Export changed original ' + name)
    require(np.array_equal(product.raw_pred_instance, raw)
            and np.array_equal(product.pred_instance, filtered), 'Export prediction labels changed')


def clone_cloud(parent):
    return laspy.LasData(copy.deepcopy(parent.header), parent.points.copy())


def export_product(parent, raw, filtered, path):
    require(not {'raw_pred_instance', 'pred_instance'} & set(parent.point_format.dimension_names),
            'Prediction field collision')
    result = clone_cloud(parent)
    for name, values in [('raw_pred_instance', raw), ('pred_instance', filtered)]:
        result.add_extra_dim(laspy.ExtraBytesParams(name=name, type=np.int64))
        result[name] = values
    result.write(path)
    check_product(parent, laspy.read(path), raw, filtered)


def inside(x, y, core):
    return bool(core[0] <= x <= core[1] and core[2] <= y <= core[3])


def instance_diagnostics(native, normalized, raw, labels, support):
    core, context, pixel = support['core'], support['context'], support['pixel_m']
    x, y, z, agl = map(np.asarray, (native.x, native.y, native.z, normalized.z))
    objects, apexes = [], []
    for ident in np.unique(labels[labels > 0]):
        rows = np.flatnonzero(labels == ident)
        # Stable source-row order breaks AGL ties, including duplicate XYZ.
        apex = int(rows[np.argmax(agl[rows])])
        box = [float(x[rows].min()), float(x[rows].max()), float(y[rows].min()), float(y[rows].max())]
        area = (box[1] - box[0]) * (box[3] - box[2])
        clip = [max(box[0], core[0]), min(box[1], core[1]), max(box[2], core[2]), min(box[3], core[3])]
        overlap = max(0, clip[1] - clip[0]) * max(0, clip[3] - clip[2])
        status = 'degenerate_point_extent' if area <= 0 else 'outside_support' if overlap <= 0 else 'positive_area_intersection'
        def pixels(b):
            return [(b[0] - core[0]) / pixel, (core[3] - b[3]) / pixel,
                    (b[1] - core[0]) / pixel, (core[3] - b[2]) / pixel]
        touch = bool(box[0] <= context[0] + native.header.scales[0]
                     or box[1] >= context[1] - native.header.scales[0]
                     or box[2] <= context[2] + native.header.scales[1]
                     or box[3] >= context[3] - native.header.scales[1])
        common = dict(instance=int(ident), points=len(rows), raw_z_extent_m=float(np.ptp(z[rows])),
                      apex_in_core=inside(x[apex], y[apex], core), context_edge_touch=touch)
        apexes.append(dict(common, source_row=apex, x=float(x[apex]), y=float(y[apex]),
                           native_z=float(z[apex]), agl_z=float(agl[apex])))
        objects.append(dict(common, geometry='sparse_point_extent_proxy', raw_metric_box=box,
                            raw_pixel_box=pixels(box), status=status,
                            clipped_metric_box=clip if overlap > 0 and area > 0 else None,
                            clipped_pixel_box=pixels(clip) if overlap > 0 and area > 0 else None,
                            image_overlap_fraction=overlap / area if area > 0 else None,
                            source_rows_sha256=hashlib.sha256(rows.astype('<u4').tobytes()).hexdigest()))
    return dict(apexes=apexes, point_extent_proxies=objects,
                counts=dict(points=len(labels), raw_instances=len(np.unique(raw[raw > 0])),
                            retained_instances=len(apexes), filtered_instances=len(np.unique(raw[raw > 0])) - len(apexes),
                            raw_background_points=int(np.count_nonzero(raw == 0)),
                            filtered_background_points=int(np.count_nonzero(labels == 0)),
                            in_core_apexes=sum(a['apex_in_core'] for a in apexes),
                            positive_area_boxes=sum(o['status'] == 'positive_area_intersection' for o in objects),
                            outside_boxes=sum(o['status'] == 'outside_support' for o in objects),
                            degenerate_boxes=sum(o['status'] == 'degenerate_point_extent' for o in objects)))


def neural_result(directory, staged, native, normalized, arm, support, write=False):
    predicted = laspy.read(directory / 'model_io/predictions.laz')
    needed = {'X', 'Y', 'Z', 'source_row', 'return_number', 'number_of_returns'}
    needed |= {'sat_row', 'pred_instance'} if arm == 'segmentanytree' else {'ff3d_row', 'ff3d_score', 'user_data', 'point_source_id'}
    require(needed <= set(predicted.point_format.dimension_names), 'Missing adapter output fields')
    raw, scores = aligned_labels(staged, predicted, arm)
    labels, _ = fixed_filter(raw, np.asarray(staged.z), scores)
    resources = read_json(directory / 'model_io/predictions.laz.json')
    if arm == 'forestformer3d':
        require(isinstance(resources, list) and len(resources) == 1
                and resources[0]['source_rows'] == len(native.points)
                and resources[0]['points'] == len(native.points)
                and resources[0]['layout'] == 'whole_scene', 'Incomplete FF3D scene receipt')
    else:
        require(resources['rows'] == len(native.points)
                and resources['export'] == 'native_full_cloud_before_background_removal'
                and resources['background'] == int(np.count_nonzero(raw == 0)), 'Incomplete SAT native receipt')
    result = instance_diagnostics(native, normalized, raw, labels, support)
    result['resources'] = resources
    for parent, name in [(native, 'native_predictions.laz'), (normalized, 'normalized_predictions.laz')]:
        if write:
            export_product(parent, raw, labels, directory / name)
        else:
            check_product(parent, laspy.read(directory / name), raw, labels)
    return result


def chm_result(directory, origin, support):
    with (directory / 'raw_treetops.csv').open() as stream:
        rows = list(csv.DictReader(stream))
    apexes = []
    seen = set()
    for row in rows:
        x, y, z = (float(row[k]) for k in ('x', 'y', 'z'))
        require(np.isfinite([x, y, z]).all(), 'Nonfinite CHM treetop')
        x += origin[0]
        y += origin[1]
        context = support['context']
        # Parent LAS precision is millimetres; a half-unit tolerance covers
        # serialization at an exactly declared rectangle edge without padding it.
        tolerance = .0005
        require(context[0] - tolerance <= x <= context[1] + tolerance
                and context[2] - tolerance <= y <= context[3] + tolerance,
                'CHM treetop lies outside declared context')
        ident = float(row['instance'])
        require(np.isfinite(ident) and ident > 0 and ident == int(ident) and ident not in seen,
                'Invalid or duplicated CHM instance ID')
        require(z >= 2, 'CHM treetop below the frozen minimum height')
        seen.add(ident)
        apexes.append(dict(instance=int(ident), x=x, y=y, agl_z=z,
                           in_core=inside(x, y, support['core'])))
    return dict(context_treetops=apexes, core_treetops=[a for a in apexes if a['in_core']],
                counts=dict(context_treetops=len(apexes), core_treetops=sum(a['in_core'] for a in apexes)))


def resources(gpu, runtime_dir, support):
    frozen = declaration()
    images = frozen['images']
    for ident in images.values():
        observed = subprocess.check_output(['docker', 'image', 'inspect', '--format', '{{.Id}}', ident], text=True, timeout=60).strip()
        require(observed == ident, 'Installed image ID mismatch')
    model = gpu / 'store/forestformer3d/ForestFormer3D'
    checkpoint = model / 'work_dirs/clean_forestformer/epoch_3000_fix.pth'
    require(sha(checkpoint) == frozen['checkpoints']['forestformer3d'], 'FF3D checkpoint changed')
    sat_path = support['checkpoints']['segmentanytree']['path']
    command = ['docker', 'run', '--rm', '--network', 'none', '--read-only', '--entrypoint', 'sha256sum',
               images['segmentanytree'], sat_path]
    sat_hash = subprocess.check_output(command, text=True, timeout=120).split()[0]
    require(sat_hash == frozen['checkpoints']['segmentanytree'], 'SAT checkpoint changed')
    # Existing installed source is already patched. Require that exact state;
    # the entrypoint then makes no changes to its copied source.
    patch = REPO / 'gpu/forestformer3d-sm120/ff3d_repo.patch'
    subprocess.run(['git', 'apply', '--reverse', '--check', str(patch)], cwd=model,
                   check=True, capture_output=True, timeout=60)
    for name, expected in frozen['installed_ff3d_patched_files'].items():
        require(sha(model / name) == expected, 'Installed patched FF3D source changed')
    runtime.verify(runtime_dir)
    return dict(images=images, checkpoints=frozen['checkpoints'], sat_checkpoint_command=command,
                runtime_receipt_sha256=sha(runtime_dir / 'runtime.json'), model_source=inventory(model, EXCLUDED))
