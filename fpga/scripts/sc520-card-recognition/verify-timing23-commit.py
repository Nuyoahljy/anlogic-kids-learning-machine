"""Verify the committed T023 increment against actual local evidence bytes."""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[3]
BASE = '9f670bc80f07ea178fa6a1787683bde7ca60b9d3'
E = ROOT / 'evidence/sc520-card-recognition/timing23'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--output', required=True, type=Path)
    args = ap.parse_args()
    assert not args.output.exists()
    assert not git('status', '--porcelain').strip(), 'Worktree must be clean before this verification'
    commit = git('rev-parse', 'HEAD').decode().strip()
    assert commit != BASE
    existing = git('diff', '--diff-filter=MD', '--name-only', BASE, commit).decode().splitlines()
    assert existing == ['memory/branches/sc520-card-recognition.md'], existing
    exact = []
    for raw_name in git('diff', '--name-only', '-z', BASE, commit).split(b'\0'):
        if not raw_name:
            continue
        name = raw_name.decode()
        assert name.startswith(('fpga/', 'hardware/', 'evidence/sc520-card-recognition/',
                                'memory/branches/sc520-card-recognition.md')), name
        local = (ROOT / name).read_bytes()
        blob = git('show', commit + ':' + name)
        assert local == blob, ('Git altered evidence bytes', name)
        exact.append({'Path': str(ROOT / name), 'SHA256': sha(ROOT / name)})
    manifest_path = E / 'validation-manifest-v1.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8-sig'))
    verified = {}

    def references(value):
        if isinstance(value, dict):
            if 'Path' in value and 'SHA256' in value:
                path = str(Path(value['Path']).resolve())
                if path not in verified:
                    verified[path] = sha(path)
                assert verified[path] == value['SHA256'].upper(), path
            for child in value.values():
                references(child)
        elif isinstance(value, list):
            for child in value:
                references(child)

    references(manifest)
    start = json.loads((E / 'start.json').read_text(encoding='utf-8-sig'))
    references(start)
    run = Path(manifest['Run'])
    inputs = json.loads((run / 'inputs.json').read_text(encoding='utf-8-sig'))
    for item in inputs['Files']:
        assert sha(item['Path']) == item['SHA256'].upper()
        if item.get('Snapshot'):
            assert sha(item['Snapshot']) == item['SnapshotSHA256'].upper()
    assert not list(run.rglob('*.bit'))
    assert not manifest['Downloadable'] and not manifest['BitGenerationAllowed']
    result = {
        'At': datetime.datetime.now().astimezone().isoformat(), 'Commit': commit, 'Base': BASE,
        'Qualified': True, 'Scope': 'Git/evidence byte identity only; no hardware qualification.',
        'ExactFiles': exact, 'CRLFOnlyFiles': [], 'ProtectedCount': len(start['Protected']),
        'InputsChecked': len(inputs['Files']), 'ManifestSHA256': sha(manifest_path),
        'ManifestPath': str(manifest_path.resolve()), 'HardwareValidated': False,
        'Downloadable': False, 'BitFilesFound': [],
    }
    with args.output.open('x', encoding='utf-8') as stream:
        json.dump(result, stream, ensure_ascii=False, indent=2)
        stream.write('\n')
    print(json.dumps({'Commit': commit, 'ExactFiles': len(exact),
                      'Protected': len(start['Protected']), 'Inputs': len(inputs['Files'])}))


if __name__ == '__main__':
    main()
