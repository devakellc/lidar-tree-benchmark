#!/usr/bin/env python3
"""Read-only verification of the accepted historical TEAK detector smoke."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import subprocess
import sys


PINNED = {
    'receipt.json': '3a4f162c78713b9772026b8d2356731376a66cfb9cd4326896e28235169dde03',
    'preparation.json': '253852c44d6bdc4208532cf256a86d38874501aa5919edfd76c7ea63da4327e8',
    'attempt.json': '586cf5407432eb0a115a7c967ecfd8949866f15f6e258095cc2c6a9bf028be27',
}
HISTORICAL_COMMIT = 'f628bd92a01c262133db180c2c86e5e1900a5c19'
RUNNER = 'scripts/run_teak_detector_smoke.py'
LIBRARY = 'scripts/teak_detector_smoke_lib.py'
CHM = 'scripts/fgiemit_pilot_cell.R'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def regular_path(path):
    """Reject redirected components before opening any authenticated file."""
    path = Path(path)
    require(path.is_absolute() and '..' not in path.parts,
            'Expected an absolute path without traversal: ' + str(path))
    for component in (path, *path.parents):
        require(not component.is_symlink(), 'Symlink is not allowed: ' + str(component))
    require(path.is_file(), 'Required historical file is absent: ' + str(path))
    return path


def sha(path):
    digest = hashlib.sha256()
    with regular_path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def inventory(root, excluded=()):
    result = {}
    for directory, dirs, files in os.walk(root, followlinks=False):
        for name in dirs + files:
            require(not (Path(directory) / name).is_symlink(),
                    'Symlink in historical tree: ' + str(Path(directory) / name))
        dirs[:] = sorted(d for d in dirs if d not in excluded)
        for name in sorted(files):
            if name not in excluded:
                path = Path(directory) / name
                result[str(path.relative_to(root))] = sha(path)
    return result


def verify_code(root, expected):
    require(isinstance(expected, dict) and {RUNNER, LIBRARY, CHM}.issubset(expected),
            'Historical runner, library or CHM is not sealed')
    for name, digest in expected.items():
        relative = PurePosixPath(name)
        require(not relative.is_absolute() and '..' not in relative.parts
                and str(relative) == name, 'Invalid sealed code path: ' + name)
        require(sha(root / name) == digest, 'Sealed historical code changed: ' + name)
    for path in (root / 'scripts').iterdir():
        require(not path.is_symlink(), 'Symlink in historical scripts: ' + str(path))
        require(not path.is_dir() or path.name == '__pycache__',
                'Unsealed Python package in historical scripts: ' + str(path))
        require(path.suffix not in ('.pyc', '.so'),
                'Unsealed importable code in historical scripts: ' + str(path))
    observed = {str(p.relative_to(root)): sha(p) for p in (root / 'scripts').iterdir()
                if p.is_file() and p.suffix in ('.py', '.R')}
    observed.update({'gpu/' + name: digest for name, digest in
                     inventory(root / 'gpu', {'__pycache__'}).items()})
    observed['docs/teak-detector-smoke.json'] = sha(root / 'docs/teak-detector-smoke.json')
    require(observed == expected, 'Historical code inventory changed; retain the sealed checkout')


def authenticated_context(out):
    # Authenticate bytes before trusting any paths, commands or code inventories.
    for name, digest in PINNED.items():
        require(sha(out / name) == digest, 'Pinned historical identity changed: ' + name)
    receipt = json.loads((out / 'receipt.json').read_text())
    preparation = json.loads((out / 'preparation.json').read_text())
    attempt = json.loads((out / 'attempt.json').read_text())
    require(receipt['preparation_sha256'] == PINNED['preparation.json']
            == attempt['preparation_sha256']
            and receipt['attempt_sha256'] == PINNED['attempt.json'],
            'Historical receipt chain changed')
    require(str(out) == preparation['paths']['out'] == attempt['out'],
            'Replay requires the original sealed output location')
    cells = [cell for cell in preparation['cells'] if cell['arm'] == 'chm_vwf']
    require(len(cells) == 1, 'Expected one sealed CHM command')
    command = cells[0]['command']
    require(len(command) == 11 and command[:4] == ['/usr/bin/time', '-f', '%M', '-o']
            and command[5] == 'Rscript' and command[7] == 'chm',
            'Unexpected historical CHM command')
    chm = regular_path(Path(command[6]))
    require(chm.parts[-2:] == ('scripts', 'fgiemit_pilot_cell.R'),
            'Unexpected historical CHM code location')
    root = chm.parents[1]
    verify_code(root, preparation['code'])
    revision = subprocess.check_output(
        ['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip()
    require(revision == HISTORICAL_COMMIT, 'Retained historical checkout revision changed')
    ledger = Path(attempt['ledger_path'])
    require(sha(ledger) == PINNED['attempt.json'], 'Shared historical attempt claim changed')
    return root, preparation, ledger


def replay(out):
    out = Path(os.path.abspath(out))
    root, preparation, ledger = authenticated_context(out)
    before = inventory(out)
    require({name: digest for name, digest in before.items()
             if name != 'receipt.json' and '__pycache__' not in Path(name).parts}
            == json.loads((out / 'receipt.json').read_text())['output_sha256'],
            'Historical output inventory changed')
    environment = os.environ.copy()
    environment['PYTHONDONTWRITEBYTECODE'] = '1'
    # No supplied command is executed. Only this fixed verification invocation
    # is permitted; resource probes in the sealed verifier do not run detectors.
    # Ignore Python path overrides and existing bytecode: source files above,
    # rather than an unsealed cache beside them, must supply historical code.
    result = subprocess.run(
        [sys.executable, '-B', '-E', '-X', 'pycache_prefix=/dev/null',
         str(root / RUNNER), '--verify', '--out', str(out)],
        cwd=root, env=environment, check=False)
    require(inventory(out) == before, 'Historical artifacts changed during verification')
    require(sha(ledger) == PINNED['attempt.json'], 'Historical ledger changed during verification')
    verify_code(root, preparation['code'])
    return result.returncode


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, allow_abbrev=False)
    parser.add_argument('--out', type=Path, required=True,
                        help='Original accepted run directory; no relocation or retry')
    args = parser.parse_args(argv)
    try:
        return replay(args.out)
    except (ValueError, OSError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        print('Historical smoke replay refused: ' + str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
