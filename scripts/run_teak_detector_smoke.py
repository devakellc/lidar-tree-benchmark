#!/usr/bin/env python3
"""Prepare, execute once, or verify the bounded TEAK_043 compatibility smoke."""
import argparse
import hashlib
import json
import os
import re
from pathlib import Path
import time

import laspy
import numpy as np

import fgiemit_reserve_cell_v2 as adapter
from fgiemit_process_v2 import bounded
import prepare_fgiemit_pilot_runtime as runtime
import teak_detector_smoke_lib as lib


def paths_from(preparation):
    return {k: Path(v) for k, v in preparation['paths'].items()}


def protect_output(out, pilot, policy, gpu, runtime_dir):
    root = gpu.parent
    protected = [pilot, policy, gpu, runtime_dir, lib.REPO / 'gpu',
                 root / 'work/teak-native-pilot', root / 'work/teak-canopy-reference',
                 root / 'work/teak-native-pilot-output', root / 'work/teak-canopy-policy-output',
                 root / 'work/teak-detector-smoke-attempts']
    for path in protected:
        path = path.resolve()
        lib.require(not out.is_relative_to(path) and not path.is_relative_to(out),
                    'Output overlaps protected input, archive, model or runtime directory')


def check_mounts(command, directory, out, gpu):
    mounts = [command[i + 1] for i, v in enumerate(command) if v == '-v']
    expected = {f'{out / "prepared/geometry.las"}:/input/geometry.las:ro',
                f'{directory / "model_io"}:/output', f'{lib.REPO / "gpu"}:/adapter:ro'}
    if directory.name == 'forestformer3d':
        expected.add(f'{gpu / "store/forestformer3d/ForestFormer3D/work_dirs/clean_forestformer/epoch_3000_fix.pth"}:/checkpoint/weights.pth:ro')
    lib.require(set(mounts) == expected and len(mounts) == len(expected), 'Unexpected model mounts')
    lib.require(command[command.index('--network') + 1] == 'none', 'Model network is not disabled')


def expected_command(cell, out, gpu, images):
    """Pure reconstruction: verification never calls the staging helper."""
    arm = cell['arm']
    directory = out / arm
    if arm == 'chm_vwf':
        lib.require(cell['container'] is None, 'CHM has an unexpected container')
        return ['/usr/bin/time', '-f', '%M', '-o', str(directory / 'peak_rss_kib.txt'),
                'Rscript', str(lib.REPO / 'scripts/fgiemit_pilot_cell.R'), 'chm',
                str(out / 'prepared/normalized.laz'), str(directory / 'config.json'),
                str(directory / 'raw_treetops.csv')]
    name = cell['container']
    lib.require(isinstance(name, str) and re.fullmatch(r'fgiemit-reserve-[a-f0-9]{12}', name),
                'Unexpected owned container identity')
    command = ['docker', 'run', '--rm', '--name', name, '--network', 'none', '--gpus', 'all',
               '-v', f'{out / "prepared/geometry.las"}:/input/geometry.las:ro',
               '-v', f'{directory / "model_io"}:/output', '-v', f'{lib.REPO / "gpu"}:/adapter:ro']
    if arm == 'segmentanytree':
        return command + ['--shm-size=8g', '--ipc=host', '--entrypoint', 'python3',
                          images[arm], '/adapter/run_fgiemit_segmentanytree.py',
                          '/input/geometry.las', '/output/predictions.laz']
    checkpoint = gpu / 'store/forestformer3d/ForestFormer3D/work_dirs/clean_forestformer/epoch_3000_fix.pth'
    return command + ['-v', f'{checkpoint}:/checkpoint/weights.pth:ro', '--entrypoint', 'bash',
                      images[arm], '/adapter/forestformer3d-sm120/ff3d_entry.sh',
                      '/input/geometry.las', '/output/predictions.laz', '/checkpoint/weights.pth',
                      '/output/model', '/adapter/forestformer3d-sm120/ff3d_repo.patch',
                      '/adapter/forestformer3d-sm120/ff3d_arm.py']


def validate_cell_command(cell, out, gpu, images):
    lib.require(cell['command'] == expected_command(cell, out, gpu, images),
                'Complete detector command changed')


def preparation_metadata(native, normalized):
    """Recompute all descriptive claims from fixed policy and parent point rows."""
    declaration = lib.declaration()
    return dict(schema_version=declaration['schema_version'], plot=declaration['plot'],
                role=declaration['role'], evaluation_ready=False, real_scores=False,
                source_point_rows=len(native.points), normalized_point_rows=len(normalized.points),
                origin=[float(np.min(native.x)), float(np.min(native.y)), float(np.min(native.z))],
                source_rows_sha256=hashlib.sha256(np.asarray(native.pilot_row, dtype='<u4').tobytes()).hexdigest(),
                native_dimensions=list(native.point_format.dimension_names),
                normalized_dimensions=list(normalized.point_format.dimension_names),
                negative_agl_rows=int(np.count_nonzero(np.asarray(normalized.z) < 0)),
                native_noise_class7_rows=int(np.count_nonzero(np.asarray(native.classification) == 7)),
                frame='local metres = original UTM XYZ minus origin; normalized Z remains pilot TIN AGL',
                model_observed=False, timeout_seconds=3600, attempts=1, concurrency=1, fail_stop=True)


def validate_preparation_metadata(preparation, native, normalized):
    for key, value in preparation_metadata(native, normalized).items():
        lib.require(type(preparation.get(key)) is type(value) and preparation[key] == value,
                    'Preparation metadata changed: ' + key)


def scientific_contract(preparation):
    """Output paths and incidental runner/document edits cannot enable a repeat."""
    fixed = lib.declaration()
    pilot = Path(preparation['paths']['pilot'])
    return dict(schema_version=1, plot='TEAK_043',
                parent_receipts={k: fixed[k + '_receipt_sha256'] for k in ('pilot', 'policy')},
                source_clouds={name: preparation['support']['hashes'][str(pilot / name)]
                               for name in ('native_context.laz', 'normalized_context.laz')},
                images=preparation['resources']['images'], checkpoints=preparation['resources']['checkpoints'],
                model_source=preparation['resources']['model_source'],
                lasr_revision=runtime.REVISION, arms=list(lib.ARMS),
                chm=preparation['support']['chm'],
                filter=dict(min_points=40, min_native_raw_z_extent_m=1.5, confidence_cutoff=None),
                transport='all_native_rows_local_translation_no_label_inputs',
                normalization='unchanged_parent_TIN_AGL',
                timeout_seconds=3600, attempts=1, concurrency=1, fail_stop=True)


def ledger_identity(preparation):
    contract = scientific_contract(preparation)
    key = hashlib.sha256(json.dumps(contract, sort_keys=True, separators=(',', ':'),
                                    allow_nan=False).encode()).hexdigest()
    root = Path(preparation['paths']['gpu']).resolve().parent / 'work/teak-detector-smoke-attempts'
    return root / (key + '.json'), key, contract


def prepare(pilot, policy, gpu, runtime_dir, out):
    protect_output(out, pilot, policy, gpu, runtime_dir)
    lib.require(not out.exists(), 'Preparation requires a fresh output directory')
    support = lib.parents(pilot, policy)
    identity = lib.resources(gpu, runtime_dir, support)
    native = laspy.read(pilot / 'native_context.laz')
    normalized = laspy.read(pilot / 'normalized_context.laz')
    lib.validate_parents(native, normalized, 43460)
    origin = np.array([np.min(native.x), np.min(native.y), np.min(native.z)])
    out.mkdir(parents=True)
    staged = out / 'prepared'
    staged.mkdir()
    for cloud, name, agl in [(native, 'geometry.las', False), (normalized, 'normalized.laz', True)]:
        lib.transport(cloud, origin, agl).write(staged / name)
        lib.validate_transport(cloud, laspy.read(staged / name), origin, agl)
    cells = []
    for arm in lib.ARMS:
        directory = out / arm
        directory.mkdir()
        config = support['chm'] if arm == 'chm_vwf' else dict(image=identity['images'][arm])
        lib.write_json(directory / 'config.json', config)
        if arm == 'chm_vwf':
            command = ['/usr/bin/time', '-f', '%M', '-o', str(directory / 'peak_rss_kib.txt'),
                       'Rscript', str(lib.REPO / 'scripts/fgiemit_pilot_cell.R'), 'chm',
                       str(staged / 'normalized.laz'), str(directory / 'config.json'),
                       str(directory / 'raw_treetops.csv')]
            container = None
        else:
            command, container = adapter.docker_command(dict(arm=arm, plot='TEAK_043', config=config),
                                                         directory, staged, gpu)
            check_mounts(command, directory, out, gpu)
        cells.append(dict(arm=arm, command=command, container=container, config=config))
    copied = lib.inventory(out / 'forestformer3d/model_io/model', lib.EXCLUDED)
    lib.require(copied == identity['model_source'], 'Copied FF3D source differs from sealed installed source')
    preparation = dict(preparation_metadata(native, normalized),
                       paths=dict(pilot=str(pilot), policy=str(policy), gpu=str(gpu), runtime=str(runtime_dir), out=str(out)),
                       support=support, resources=identity, cells=cells,
                       code=lib.code_identity(), staged_sha256=lib.inventory(out))
    lib.write_json(out / 'preparation.json', preparation)
    lib.write_json(out / 'states.json', [dict(arm=a, state='planned', counts=None) for a in lib.ARMS])
    verify_preparation(out)
    return preparation


def verify_preparation(out):
    preparation = lib.read_json(out / 'preparation.json')
    p = paths_from(preparation)
    lib.require(p['out'] == out, 'Output path differs from preparation')
    protect_output(out, p['pilot'], p['policy'], p['gpu'], p['runtime'])
    lib.require(preparation['code'] == lib.code_identity(), 'Sealed code or smoke configuration changed')
    support = lib.parents(p['pilot'], p['policy'])
    lib.require(support == preparation['support'], 'Parent metadata or payloads changed')
    lib.require(lib.resources(p['gpu'], p['runtime'], support) == preparation['resources'], 'Runtime identity changed')
    for name, expected in preparation['staged_sha256'].items():
        lib.require(lib.sha(out / name) == expected, 'Prepared payload changed: ' + name)
    lib.require(lib.inventory(out / 'forestformer3d/model_io/model', lib.EXCLUDED)
                == preparation['resources']['model_source'], 'Copied model source changed')
    native = laspy.read(p['pilot'] / 'native_context.laz')
    normalized = laspy.read(p['pilot'] / 'normalized_context.laz')
    lib.validate_parents(native, normalized, 43460)
    validate_preparation_metadata(preparation, native, normalized)
    for parent, name, agl in [(native, 'geometry.las', False), (normalized, 'normalized.laz', True)]:
        lib.validate_transport(parent, laspy.read(out / 'prepared' / name), preparation['origin'], agl)
    lib.require([c['arm'] for c in preparation['cells']] == list(lib.ARMS), 'Cell order changed')
    for cell in preparation['cells']:
        arm = cell['arm']
        config = support['chm'] if arm == 'chm_vwf' else dict(image=preparation['resources']['images'][arm])
        lib.require(cell['config'] == config == lib.read_json(out / arm / 'config.json'), 'Cell configuration changed')
        if arm != 'chm_vwf':
            check_mounts(cell['command'], out / arm, out, p['gpu'])
        validate_cell_command(cell, out, p['gpu'], preparation['resources']['images'])
    return preparation, native, normalized


def exclusive_json(path, record):
    # Both the file and directory entry are durable before model launch.
    with path.open('x') as stream:
        json.dump(record, stream, indent=2, allow_nan=False)
        stream.write('\n')
        stream.flush()
        os.fsync(stream.fileno())
    fd = os.open(path.parent, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def claim(out, preparation=None):
    preparation = preparation if preparation is not None else lib.read_json(out / 'preparation.json')
    ledger, key, contract = ledger_identity(preparation)
    ledger.parent.mkdir(parents=True, exist_ok=True)
    record = dict(schema_version=1, scientific_contract_sha256=key, scientific_contract=contract,
                  preparation_sha256=lib.sha(out / 'preparation.json'), out=str(out),
                  ledger_path=str(ledger), attempts=1, claimed_unix=time.time())
    # Claim the shared scientific contract first. A crash before the local copy
    # still consumes the attempt and cannot be rescued by another output path.
    exclusive_json(ledger, record)
    exclusive_json(out / 'attempt.json', record)


def verify_claim(out, preparation):
    ledger, key, contract = ledger_identity(preparation)
    attempt = lib.read_json(out / 'attempt.json')
    lib.require(attempt == lib.read_json(ledger), 'Shared and local attempt claims differ')
    expected = dict(schema_version=1, scientific_contract_sha256=key, scientific_contract=contract,
                    preparation_sha256=lib.sha(out / 'preparation.json'), out=str(out),
                    ledger_path=str(ledger), attempts=1)
    for name, value in expected.items():
        lib.require(type(attempt.get(name)) is type(value) and attempt[name] == value,
                    'Attempt identity changed: ' + name)
    lib.require(isinstance(attempt.get('claimed_unix'), (int, float))
                and np.isfinite(attempt['claimed_unix']) and attempt['claimed_unix'] > 0,
                'Invalid attempt timestamp')
    return attempt


def execute_cells(preparation, native, normalized, out):
    p = paths_from(preparation)
    states = lib.read_json(out / 'states.json')
    lib.require(states == [dict(arm=a, state='planned', counts=None) for a in lib.ARMS], 'Cells were already attempted')
    claim(out, preparation)
    staged = laspy.read(out / 'prepared/geometry.las')
    for cell, state in zip(preparation['cells'], states):
        arm = cell['arm']
        directory = out / arm
        state.update(state='running', model_observed=True)
        lib.write_json(out / 'states.json', states)
        start = time.monotonic()
        phase = 'inference'
        try:
            lib.write_json(directory / 'command.json', dict(argv=cell['command'], timeout_seconds=3600))
            (directory / 'inference.log').touch(exist_ok=True)
            elapsed = bounded(cell['command'], directory, container=cell['container'], timeout=3600,
                              env=runtime.environment(p['runtime']) if arm == 'chm_vwf' else None)
            phase = 'export'
            if arm == 'chm_vwf':
                result = lib.chm_result(directory, preparation['origin'], preparation['support'])
                count = result['counts']['context_treetops']
                result['resources'] = dict(peak_host_rss_kib=int((directory / 'peak_rss_kib.txt').read_text()))
            else:
                result = lib.neural_result(directory, staged, native, normalized, arm, preparation['support'], write=True)
                count = result['counts']['retained_instances']
            lib.write_json(directory / 'diagnostics.json', result)
            phase = 'verification'
            verify_preparation(out)
            state.update(state='successful_nonempty' if count else 'successful_empty',
                         counts=result['counts'], inference_wall_seconds=elapsed)
        except BaseException as error:
            state.update(state='failed', counts=None, elapsed_seconds=time.monotonic() - start,
                         error=f'{type(error).__name__}: {str(error) or "no exception message"}', error_type=type(error).__name__,
                         failure_phase=phase)
            lib.write_json(directory / 'failure.json', state)
            lib.write_json(out / 'states.json', states)
            raise
        lib.write_json(out / 'states.json', states)


def execute(out):
    lib.require(not (out / 'attempt.json').exists(), 'Attempt consumed; verification only, no retry')
    preparation, native, normalized = verify_preparation(out)
    try:
        execute_cells(preparation, native, normalized, out)
    finally:
        if (out / 'attempt.json').exists():
            states = lib.read_json(out / 'states.json')
            success = all(s['state'].startswith('successful_') for s in states)
            # Preserve a failure receipt even if the detector raised. Verification
            # independently rechecks parents/code/raw-to-derived exports afterward.
            receipt = dict(schema_version=1, preparation_sha256=lib.sha(out / 'preparation.json'),
                           attempt_sha256=lib.sha(out / 'attempt.json'), states=states,
                           compatibility_true=success, evaluation_ready=False, real_scores=False,
                           model_observed=any(s.get('model_observed') is True for s in states),
                           reserved_plots_processed=[],
                           output_sha256=lib.inventory(out, {'receipt.json', '__pycache__'}))
            lib.write_json(out / 'receipt.json', receipt)
    return verify(out)


def validate_state_evidence(out, preparation, states):
    stopped = False
    for state, cell in zip(states, preparation['cells']):
        arm, status = state['arm'], state['state']
        lib.require(status in ('planned', 'failed', 'successful_empty', 'successful_nonempty'),
                    'Incomplete cell state')
        if status == 'planned':
            lib.require(stopped and state == dict(arm=arm, state='planned', counts=None),
                        'Planned cell has observation data or lacks a preceding failure')
            continue
        lib.require(not stopped, 'Execution continued after failure')
        lib.require(state.get('model_observed') is True, 'Attempted cell missing observation flag')
        directory = out / arm
        lib.require(lib.read_json(directory / 'command.json') ==
                    dict(argv=cell['command'], timeout_seconds=3600), 'Cell command evidence changed')
        lib.require((directory / 'inference.log').is_file(), 'Cell inference log missing')
        if status == 'failed':
            stopped = True
            lib.require(state.get('counts') is None and isinstance(state.get('error'), str)
                        and isinstance(state.get('error_type'), str) and bool(state['error_type'])
                        and state['error'].startswith(state['error_type'] + ': ')
                        and bool(state['error'].split(': ', 1)[1])
                        and state.get('failure_phase') in ('inference', 'export', 'verification'),
                        'Missing meaningful failure evidence')
            seconds = state.get('elapsed_seconds')
            lib.require(type(seconds) in (int, float) and np.isfinite(seconds) and seconds >= 0,
                        'Invalid failure elapsed time')
            lib.require(lib.read_json(directory / 'failure.json') == state, 'Failure record differs from state')
        else:
            lib.require(not {'error', 'error_type', 'failure_phase', 'elapsed_seconds'} & set(state),
                        'Successful cell carries failure evidence')
            seconds = state.get('inference_wall_seconds')
            lib.require(type(seconds) in (int, float) and np.isfinite(seconds) and seconds >= 0,
                        'Invalid detector elapsed time')
            execution = lib.read_json(directory / 'execution.json')
            lib.require(execution == dict(exit_code=0, wall_seconds=seconds), 'Successful execution evidence changed')


def validate_receipt_claims(receipt, states):
    success = all(s['state'].startswith('successful_') for s in states)
    expected = dict(schema_version=1, compatibility_true=success, evaluation_ready=False,
                    real_scores=False, reserved_plots_processed=[],
                    model_observed=any(s.get('model_observed') is True for s in states))
    for key, value in expected.items():
        lib.require(type(receipt.get(key)) is type(value) and receipt[key] == value,
                    'Invalid smoke receipt claim: ' + key)


def verify(out):
    preparation, native, normalized = verify_preparation(out)
    if not (out / 'attempt.json').exists():
        lib.require(not (out / 'receipt.json').exists(), 'Receipt without an attempt')
        lib.require(lib.read_json(out / 'states.json') == [dict(arm=a, state='planned', counts=None) for a in lib.ARMS],
                    'Unclaimed run has changed states')
        lib.require(not ledger_identity(preparation)[0].exists(),
                    'Scientific contract already claimed; no second output attempt')
        return dict(state='prepared', compatibility_true=None, evaluation_ready=False, real_scores=False)
    verify_claim(out, preparation)
    receipt = lib.read_json(out / 'receipt.json')
    lib.require(receipt['preparation_sha256'] == lib.sha(out / 'preparation.json')
                == lib.read_json(out / 'attempt.json')['preparation_sha256'], 'Attempt contract changed')
    lib.require(receipt['attempt_sha256'] == lib.sha(out / 'attempt.json'), 'Attempt claim changed')
    lib.require(receipt['output_sha256'] == lib.inventory(out, {'receipt.json', '__pycache__'}),
                'Raw output, logs or exports changed')
    states = lib.read_json(out / 'states.json')
    lib.require(states == receipt['states'] and [s['arm'] for s in states] == list(lib.ARMS), 'Cell states changed')
    validate_receipt_claims(receipt, states)
    validate_state_evidence(out, preparation, states)
    staged = laspy.read(out / 'prepared/geometry.las')
    stopped = False
    for state in states:
        arm, status = state['arm'], state['state']
        lib.require(status in ('planned', 'failed', 'successful_empty', 'successful_nonempty'), 'Incomplete cell state')
        if stopped:
            lib.require(status == 'planned', 'Execution continued after failure')
        if status in ('planned', 'failed'):
            stopped = True
            lib.require(state['counts'] is None, 'Failed or unrun counts must remain unknown')
            continue
        directory = out / arm
        if arm == 'chm_vwf':
            result = lib.chm_result(directory, preparation['origin'], preparation['support'])
            result['resources'] = dict(peak_host_rss_kib=int((directory / 'peak_rss_kib.txt').read_text()))
            count = result['counts']['context_treetops']
        else:
            result = lib.neural_result(directory, staged, native, normalized, arm, preparation['support'])
            count = result['counts']['retained_instances']
        lib.require(result == lib.read_json(directory / 'diagnostics.json'), 'Derived diagnostics differ from raw output')
        lib.require(state['counts'] == result['counts'] and status == ('successful_nonempty' if count else 'successful_empty'),
                    'Success counts/state changed')
    success = all(s['state'].startswith('successful_') for s in states)
    lib.require(receipt['compatibility_true'] == success and receipt['evaluation_ready'] is False
                and receipt['real_scores'] is False and receipt['reserved_plots_processed'] == [], 'Invalid smoke claims')
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    for name in ('prepare', 'execute', 'verify'):
        mode.add_argument('--' + name, action='store_true')
    parser.add_argument('--out', type=Path, required=True)
    for name in ('pilot', 'policy', 'gpu', 'runtime'):
        parser.add_argument('--' + name, type=Path)
    args = parser.parse_args()
    out = args.out.resolve()
    if args.prepare:
        if any(getattr(args, k) is None for k in ('pilot', 'policy', 'gpu', 'runtime')):
            parser.error('--prepare requires --pilot --policy --gpu --runtime')
        prepare(args.pilot.resolve(strict=True), args.policy.resolve(strict=True),
                args.gpu.resolve(strict=True), args.runtime.resolve(strict=True), out)
        print('Prepared TEAK_043 compatibility smoke; no inference run')
    else:
        lib.require(all(getattr(args, k) is None for k in ('pilot', 'policy', 'gpu', 'runtime')),
                    'Execute/verify use the sealed preparation paths; provide only --out')
        receipt = execute(out) if args.execute else verify(out)
        print(json.dumps({k: receipt[k] for k in ('compatibility_true', 'evaluation_ready', 'real_scores')}))


if __name__ == '__main__':
    main()
