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


def check_protected(items):
    reviewed_path = EVIDENCE / 'external-document-updates-20261013-v2.json'
    reviewed = json.loads(reviewed_path.read_text(encoding='utf-8'))
    require(sha(reviewed['RecordPath']) == reviewed['RecordSHA256'], 'external record changed')
    record = json.loads(Path(reviewed['RecordPath']).read_text(encoding='utf-8-sig'))
    main = ROOT.parents[2] / 'anlogic-kids-learning-machine'
    allowed = {main / n for n in ('AGENTS.md', 'DECISIONS.md', 'PLAN.md', 'PROJECT_MEMORY.md', 'TASKS.md')}
    exceptions = {Path(x['Path']): x for x in reviewed['Changes']}
    require(len(exceptions) == len(reviewed['Changes']) and set(exceptions) <= allowed,
            'external review must name only the five main coordination documents')
    observed = []
    for item in items:
        path = Path(item['Path'])
        actual = sha(path)
        if actual == item['SHA256'].upper():
            continue
        change = exceptions.get(path)
        require(change is not None and change['BaselineSHA256'].upper() == item['SHA256'].upper()
                and change['ObservedSHA256'] == actual, 'protected file changed: ' + str(path))
        change_record = record
        if 'RecordPath' in change:
            require(sha(change['RecordPath']) == change['RecordSHA256'], 'external follow-up record changed')
            change_record = json.loads(Path(change['RecordPath']).read_text(encoding='utf-8-sig'))
        require(any(Path(x['Path']) == path and x.get('SHA256') == actual for x in change_record['Changes']),
                'external change not bound to main coordination record: ' + str(path))
        observed.append(change)
    return observed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=EVIDENCE / 'pixel14-validation-v3.json')
    args = parser.parse_args()
    baselines = json.loads((EVIDENCE / 'pixel14-baseline.json').read_text(encoding='utf-8'))
    external_changes = check_protected(baselines['Protected'])
    history = json.loads((EVIDENCE / 'pixel14-boardfix-baseline.json').read_text(encoding='utf-8'))
    for item in [history['OldBit'], *history['ProtectedHistory']]:
        require(sha(item['Path']) == item['SHA256'].upper(), 'historical evidence changed: '+item['Path'])
    candidates = []
    for path in (EVIDENCE / 'runs').glob('p14-*/run-manifest.json'):
        manifest = json.loads(path.read_text(encoding='utf-8'))
        if not manifest.get('Qualified'):
            continue
        current = all(sha(i['path']) == i['sha256_before'].upper() for i in manifest['Inputs'])
        if current:
            candidates.append((path, manifest))
    selected = []
    for test in ('capture', 'block', 'cdc', 'pipeline', 'provenance', 'diag'):
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
        'ProtectedFiles': len(baselines['Protected']), 'ProtectedHistoryFiles': len(history['ProtectedHistory']), 'Runs': selected,
        'ProtectedFilesUnchanged': len(baselines['Protected']) - len(external_changes),
        'ReviewedExternalDocumentationChanges': external_changes,
        'ExternalReviewSHA256': sha(EVIDENCE / 'external-document-updates-20261013-v2.json'),
        'NormalScenarios': sum(x['Summary']['scenarios'] for x in positive),
        'NormalChecks': sum(x['Summary']['checks'] for x in positive), 'NormalErrors': 0,
        'Scope': 'Synthetic RGB96 and CSI/RAW/ISP framing; input snapshots, outputs and protected files verified. This does not certify physical camera recognition, DDR frame alignment, hardware CDC or board operation.'
    }
    out = args.output.resolve()
    require(out.parent == EVIDENCE.resolve(), 'validation output must stay in task evidence directory')
    require(not out.exists(), 'choose a new output name; do not overwrite historical validation')
    out.write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({'validated': str(out), 'runs': len(selected),
                      'scenarios': result['NormalScenarios'], 'checks': result['NormalChecks'],
                      'protected': result['ProtectedFiles']}))


if __name__ == '__main__':
    main()
