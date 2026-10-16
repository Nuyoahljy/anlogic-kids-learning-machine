"""Seal current coordinator documents against their latest exact shared records."""
from pathlib import Path
import argparse, datetime, hashlib, json

ROOT = Path(__file__).resolve().parents[3]
WORKSPACE = Path('E:/juan/FPGA')
MAIN = WORKSPACE / 'anlogic-kids-learning-machine'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--tag', required=True)
    ap.add_argument('--owner', required=True)
    args = ap.parse_args()
    out = ROOT / 'evidence/sc520-card-recognition/timing23' / args.tag
    assert not out.exists(), out
    names = ['AGENTS.md', 'PROJECT_MEMORY.md', 'PLAN.md', 'TASKS.md', 'DECISIONS.md',
             'docs/03-interface-contracts.md', 'docs/10-active-coordination.md']
    paths = {str((MAIN / name).resolve()).casefold(): MAIN / name for name in names}
    latest = {}
    for path in (WORKSPACE / 'workspace-records').glob('*.json'):
        record = read(path)
        if record['Task'] != 'sc520-main-coordination':
            continue
        for change in record['Changes']:
            key = str(Path(change['Path']).resolve()).casefold()
            if key in paths and change.get('SHA256') and (key not in latest or record['UpdatedAt'] > latest[key][0]):
                latest[key] = (record['UpdatedAt'], path, change['SHA256'].upper())
    assert set(latest) == set(paths)
    documents = []
    out.mkdir(parents=True)
    for i, (key, source) in enumerate(paths.items()):
        stamp, record, expected = latest[key]
        assert sha(source) == expected, ('Current main document has no matching latest registration', source, record)
        snapshot = out / f'{i}-{source.name}'
        snapshot.write_bytes(source.read_bytes())
        assert sha(source) == sha(snapshot) == expected
        documents.append({'Path': str(source.resolve()), 'Snapshot': str(snapshot.resolve()), 'SHA256': expected,
                          'RecordPath': str(record.resolve()), 'RecordSHA256': sha(record), 'RegisteredAt': stamp})
    scope = WORKSPACE / 'learning/sc520-contest-roadmap/t023-timing-optimization-scope-20261016.md'
    assert sha(scope) == 'ED77BFC1CD5ED3EBA73130C9C73C8D12326434DF7F410BEC64B87EB5F1DB2F60'
    review = {'At': datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
              'Owner': args.owner,
              'Documents': documents, 'ScopePath': str(scope), 'ScopeSHA256': sha(scope),
              'MainDocumentsModified': False}
    with (out / 'review.json').open('x', encoding='utf-8') as stream:
        json.dump(review, stream, ensure_ascii=False, indent=2)
        stream.write('\n')
    print(json.dumps({'Documents': len(documents), 'Review': str(out / 'review.json')}))


if __name__ == '__main__':
    main()
