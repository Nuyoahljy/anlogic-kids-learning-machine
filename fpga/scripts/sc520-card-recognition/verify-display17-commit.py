"""Verify committed task bytes, line-ending normalization and frozen evidence."""
from pathlib import Path
import argparse, datetime, hashlib, json, subprocess

ROOT = Path(__file__).resolve().parents[3]
E = ROOT / 'evidence/sc520-card-recognition'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--output', type=Path, required=True)
    args = ap.parse_args()
    assert not args.output.exists(), args.output
    commit = git('rev-parse', 'HEAD').decode().strip()
    base = '68e2b4d01485fa1b3049d81e98a09c2e3dc98a94'
    paths = [x.decode() for x in git('diff', '--name-only', '-z', base, commit).split(b'\0') if x]
    exact, normalized = [], []
    for path in paths:
        assert path.startswith(('fpga/', 'assets/', 'hardware/', 'evidence/sc520-card-recognition/', 'memory/branches/sc520-card-recognition.md')), path
        local = (ROOT / path).read_bytes()
        blob = git('show', commit + ':' + path)
        row = {'Path': str(ROOT / path), 'GitSHA256': hashlib.sha256(blob).hexdigest().upper(), 'LocalSHA256': sha(ROOT / path)}
        if blob == local:
            exact.append(row)
        else:
            assert blob.replace(b'\r\n', b'\n') == local.replace(b'\r\n', b'\n'), ('Committed bytes differ beyond CRLF', path)
            normalized.append(row)
    start = json.loads((E / 'display17/start.json').read_text(encoding='utf-8-sig'))
    for row in start['Protected'] + start['Imports']:
        assert sha(row['Path']) == row['SHA256'], row['Path']
    manifest = json.loads((E / 'delivery-0117/manifest.json').read_text(encoding='utf-8-sig'))
    for key in ('Bit', 'OriginalBit', 'PhysicalAudit', 'SoftwareAudit', 'Guide'):
        item = manifest[key]
        assert sha(item['Path']) == item['SHA256'], item['Path']
    build = Path(manifest['OriginalBit']['Path']).parents[3]
    inputs = json.loads((build / 'inputs.json').read_text(encoding='utf-8-sig'))
    for item in inputs['Files']:
        assert sha(item['Path']) == item['SHA256'], item['Path']
        if item.get('Snapshot'):
            assert sha(item['Snapshot']) == item['SnapshotSHA256'], item['Snapshot']
    report = {'At': datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
              'Commit': commit, 'Base': base, 'Qualified': True, 'ExactFiles': exact,
              'CRLFOnlyFiles': normalized, 'ProtectedCount': len(start['Protected']), 'FrozenBuildInputs': len(inputs['Files']),
              'DeliverySHA256': manifest['Bit']['SHA256'], 'HardwareValidated': False}
    with args.output.open('x', encoding='utf-8') as stream:
        json.dump(report, stream, ensure_ascii=False, indent=2)
        stream.write('\n')
    print(json.dumps({'Commit': commit, 'Exact': len(exact), 'CRLFOnly': len(normalized), 'Protected': len(start['Protected'])}))


if __name__ == '__main__':
    main()
