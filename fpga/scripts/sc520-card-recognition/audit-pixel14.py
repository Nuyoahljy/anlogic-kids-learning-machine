"""Read back current pixel14 test inputs, qualified outputs and protected baselines."""
import hashlib
import json
import argparse
from pathlib import Path
from datetime import datetime, timezone, timedelta

ROOT = Path(__file__).resolve().parents[3]
EVIDENCE = ROOT / 'evidence/sc520-card-recognition'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=EVIDENCE / 'pixel14-validation-v2.json')
    args = parser.parse_args()
    baselines = json.loads((EVIDENCE / 'pixel14-baseline.json').read_text(encoding='utf-8'))
    for item in baselines['Protected']:
        require(sha(item['Path']) == item['SHA256'].upper(), 'protected file changed: '+item['Path'])
    candidates = []
    for path in (EVIDENCE / 'runs').glob('p14-*/run-manifest.json'):
        manifest = json.loads(path.read_text(encoding='utf-8'))
        if not manifest.get('Qualified'):
            continue
        current = all(sha(i['path']) == i['sha256_before'].upper() for i in manifest['Inputs'])
        if current:
            candidates.append((path, manifest))
    selected = []
    for test in ('capture', 'block', 'cdc', 'pipeline', 'provenance'):
        for mode in ('normal', 'negative', 'watchdog'):
            matches = [(p, m) for p, m in candidates if m['Test'] == test and m['Mode'] == mode]
            require(bool(matches), f'no current qualified run: {test}/{mode}')
            path, manifest = max(matches, key=lambda pair: pair[1]['FinishedAt'])
            if test == 'pipeline':
                require(manifest.get('FullResolution') is True, 'final pipeline qualification must use 1280x720')
            for item in manifest['Inputs']:
                h = item['sha256_before'].upper()
                require(h == sha(item['snapshot']) == item['sha256_after'].upper() == item['snapshot_sha256'].upper(),
                        'input snapshot mismatch: '+item['path'])
            for item in manifest['Outputs']:
                require(sha(item['path']) == item['sha256'].upper(), 'output hash mismatch: '+item['path'])
            summary = manifest['Summary']
            require(not manifest['TimedOut'] and manifest['InputsUnchanged'], 'invalid execution: '+str(path))
            if mode == 'watchdog':
                require(manifest['NativeExitCode'] == 2 and summary['done'] == 0 and summary['errors'] == 0,
                        'premature finish was not rejected')
            else:
                expected = int(mode == 'negative')
                require(manifest['NativeExitCode'] == expected and summary['done'] == 1 and
                        summary['errors'] == expected and summary['injected'] == expected and
                        summary['checks'] > 0 and summary['scenarios'] > 0, 'invalid test qualification')
            selected.append({'Path': str(path), 'SHA256': sha(path), 'Test': test, 'Mode': mode,
                             'FullResolution': manifest.get('FullResolution', False),
                             'Summary': summary, 'NativeExitCode': manifest['NativeExitCode'],
                             'Command': manifest['Command']})
    positive = [x for x in selected if x['Mode'] == 'normal']
    result = {
        'Task': 'sc520-card-recognition', 'Stage': 'pixel14',
        'VerifiedAt': datetime.now(timezone(timedelta(hours=8))).isoformat(timespec='seconds'),
        'ProtectedFiles': len(baselines['Protected']), 'Runs': selected,
        'NormalScenarios': sum(x['Summary']['scenarios'] for x in positive),
        'NormalChecks': sum(x['Summary']['checks'] for x in positive), 'NormalErrors': 0,
        'Scope': 'Synthetic RGB96 and CSI/RAW/ISP framing; input snapshots, outputs and protected files verified. This does not certify physical camera recognition, DDR frame alignment, hardware CDC or board operation.'
    }
    out = args.output.resolve()
    require(out.parent == EVIDENCE.resolve(), 'validation output must stay in task evidence directory')
    out.write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({'validated': str(out), 'runs': len(selected),
                      'scenarios': result['NormalScenarios'], 'checks': result['NormalChecks'],
                      'protected': result['ProtectedFiles']}))


if __name__ == '__main__':
    main()
