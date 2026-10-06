#!/usr/bin/env python3
"""Qualify actual normal/negative runs against current inputs and protected bytes."""
import argparse
import csv
import hashlib
import json
import re
from datetime import datetime, timezone, timedelta
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
EVIDENCE = REPO / 'evidence/sc520-quiz-control'


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def read_json(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def qualify(path, testcase, negative):
    run = read_json(path)
    assert run['Testcase'] == testcase and run['Negative'] is negative
    assert not run['ChangedInputs'], 'inputs changed during original run'
    assert run['ExitCode'] == int(negative) == run['ExpectedExitCode']
    summary = read_json(path.parent / 'summary.json')
    assert run['Summary'] == summary
    assert summary['testcase'] == testcase and summary['negative'] == int(negative)
    assert summary['done'] == 1 and summary['checks'] > 0
    assert summary['errors'] > 0 if negative else summary['errors'] == 0
    for relative, expected in run['InputsSHA256'].items():
        assert digest(REPO / relative) == expected, f'current input changed: {relative}'
        assert run['InputsAfterSHA256'][relative] == expected
        assert digest(path.parent / 'inputs' / relative) == expected, f'snapshot changed: {relative}'
    for relative, expected in run['OutputSHA256'].items():
        assert digest(path.parent / relative) == expected, f'result changed: {relative}'
    transcript = (path.parent / 'transcript.log').read_text(encoding='utf-8-sig')
    summaries = re.findall(r'^# SUMMARY .*$', transcript, re.M)
    assert len(summaries) == 1, 'missing/ambiguous completion log'
    assert re.search(r'\bchecks=' + str(summary['checks']) + r'\b', summaries[0])
    assert re.search(r'\berrors=' + str(summary['errors']) + r'\b', summaries[0])
    assert not re.search(r'Errors: [1-9]|Warnings: [1-9]', transcript), 'compiler/tool errors or warnings'
    assert bool(re.search(r'^# (?:CHECK_)?FAIL\b', transcript, re.M)) is negative, 'failure marker disagrees with run type'
    return {'Testcase': testcase, 'Negative': negative, 'Manifest': str(path),
            'ManifestSHA256': digest(path), 'Summary': summary,
            'TranscriptSummary': summaries[0], 'ExitCode': run['ExitCode'],
            'Trace': str(path.parent / 'trace.csv') if (path.parent / 'trace.csv').exists() else None}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write', action='store_true', help='save verification-manifest.json')
    args = parser.parse_args()
    selected = []
    skipped = []
    for testcase in ('control', 'audio', 'keys', 'system'):
        for negative in (False, True):
            label = 'negative' if negative else 'normal'
            matches = sorted((EVIDENCE / 'runs').glob(f'{testcase}-{label}-*/run-manifest.json'), reverse=True)
            for path in matches:
                try:
                    result = qualify(path, testcase, negative)
                except (AssertionError, KeyError, OSError, ValueError) as exc:
                    skipped.append({'Manifest': str(path), 'Reason': str(exc)})
                else:
                    selected.append(result)
                    break
            else:
                raise RuntimeError(f'no qualified current {testcase}/{label} run; {skipped}')
    protected = read_json(EVIDENCE / 'protected-before.json')
    differences = [entry['Path'] for entry in protected['Files'] if digest(entry['Path']) != entry['SHA256']]
    if differences:
        raise RuntimeError(f'protected files changed: {differences}')
    artifacts = []
    for folder in ('fpga/custom_project/sc520-quiz-control', 'fpga/sim/sc520-quiz-control', 'fpga/scripts/sc520-quiz-control'):
        for path in sorted((REPO / folder).glob('*')):
            if path.is_file():
                artifacts.append({'Path': str(path), 'SHA256': digest(path)})
    for testcase, filename in (('control', 'display-preview.html'), ('system', 'system-preview.html')):
        path = EVIDENCE / filename
        html = path.read_text(encoding='utf-8')
        trace = Path(next(test['Trace'] for test in selected if test['Testcase'] == testcase and not test['Negative']))
        assert digest(trace) in html, 'preview trace hash differs from qualified run'
        embedded = json.loads(re.search(r'<script id="trace-data" type="application/json">(.*?)</script>', html, re.S)[1])
        with trace.open(encoding='utf-8-sig', newline='') as stream:
            source_rows = list(csv.DictReader(stream))
        assert len(embedded) == len(source_rows)
        assert all(row == {key: int(raw[key]) for key in row} for row, raw in zip(embedded, source_rows)), 'preview rows differ from actual trace'
        artifacts.append({'Path': str(path), 'SHA256': digest(path), 'SourceTraceSHA256': digest(trace)})
    for filename in ('run-report.md', 'local-interface.md', 'audio-notes.md', 'preview-notes.md',
                     'ui-checks.json', 'display-preview-full.jpg', 'display-preview.jpg'):
        path = EVIDENCE / filename
        artifacts.append({'Path': str(path), 'SHA256': digest(path)})
    for path in (REPO / 'memory/branches/sc520-quiz-control.md',
                 Path('E:/juan/FPGA/learning/sc520-quiz-control/README.md')):
        artifacts.append({'Path': str(path), 'SHA256': digest(path)})
    result = {'Task': 'sc520-quiz-control', 'Status': 'RTL_simulation_verified_waiting_review',
              'VerifiedAt': datetime.now(timezone(timedelta(hours=8))).isoformat(),
              'Tests': selected, 'RejectedRecentRuns': skipped, 'Artifacts': artifacts,
              'ProtectedCount': len(protected['Files']), 'ProtectedDifferences': differences,
              'ProtectedSnapshotSHA256': digest(EVIDENCE / 'protected-before.json'),
              'HardwareTested': False, 'PhysicalAudioTested': False, 'TDSynthesisRun': False,
              'Note': 'All detector, key and player stimuli are simulated. Negative failures are intentional.'}
    if args.write:
        (EVIDENCE / 'verification-manifest.json').write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    for test in selected:
        print(test['TranscriptSummary'])
    print(f'PASS qualified_runs={len(selected)} protected_files={len(protected["Files"])} differences=0')


if __name__ == '__main__':
    main()
