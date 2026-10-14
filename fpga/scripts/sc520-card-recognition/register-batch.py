"""Register an explicit SC520 change batch and regenerate/check the shared index."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import subprocess
import uuid

REPO = Path(__file__).resolve().parents[3]
WORKSPACE = Path('E:/juan/FPGA')


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--suffix', required=True)
    ap.add_argument('--summary', required=True)
    ap.add_argument('--validation', required=True)
    ap.add_argument('--next', required=True)
    ap.add_argument('--file', action='append', default=[])
    ap.add_argument('--dir', action='append', default=[])
    ap.add_argument('--status', default='开发中；非硬件验收')
    args = ap.parse_args()
    now = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8)))
    ident = now.strftime('%Y%m%d-%H%M%S') + '-sc520-card-recognition-' + args.suffix + '-' + uuid.uuid4().hex[:6]
    target = WORKSPACE / 'workspace-records' / (ident + '.json')
    changes = []
    for group, entries in [('file', args.file), ('dir', args.dir)]:
        for entry in entries:
            path = (REPO / entry).resolve()
            path.relative_to(REPO)
            if not path.exists() or (group == 'file' and not path.is_file()):
                raise ValueError(f'Missing batch path: {path}')
            action = 'generated'
            if group == 'file':
                tracked = subprocess.run(['git', 'ls-files', '--error-unmatch', str(path)], cwd=REPO, capture_output=True)
                action = 'modified' if tracked.returncode == 0 else 'added'
            item = {'Path': path.as_posix(), 'Action': action,
                    'Purpose': args.summary + '；' + path.relative_to(REPO).as_posix(), 'Status': args.status}
            if path.is_file():
                item['SHA256'] = hashlib.sha256(path.read_bytes()).hexdigest().upper()
            changes.append(item)
    changes.append({'Path': target.as_posix(), 'Action': 'added',
                    'Purpose': '本批独立文件登记，时间为真实登记时间', 'Status': args.status})
    record = {'Id': ident, 'UpdatedAt': now.isoformat(), 'Task': 'sc520-card-recognition',
              'Owner': '01a13561-2629-7fa2-86a0-4087ad34cc7c /root', 'Workdir': REPO.as_posix(),
              'Summary': args.summary, 'Validation': args.validation, 'NextStep': args.next, 'Changes': changes}
    with target.open('x', encoding='utf-8') as stream:
        json.dump(record, stream, indent=2, ensure_ascii=False)
        stream.write('\n')
    script = WORKSPACE / 'anlogic-kids-learning-machine/tools/update-workspace-index.ps1'
    subprocess.run(['pwsh', '-NoProfile', '-File', str(script)], check=True)
    subprocess.run(['pwsh', '-NoProfile', '-File', str(script), '-Check'], check=True)
    print(json.dumps({'record': str(target), 'changes': len(changes)}, ensure_ascii=False))


if __name__ == '__main__':
    main()
