"""Seal T023 evidence and a lossless compact view; never generate a bit."""
from pathlib import Path
import copy
import datetime
import hashlib
import json
import shutil

ROOT = Path(__file__).resolve().parents[3]
E = ROOT / 'evidence/sc520-card-recognition/timing23'


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def art(path):
    path = Path(path).resolve()
    return {'Path': str(path), 'SHA256': sha(path), 'Bytes': path.stat().st_size}


def emit(path, value):
    with path.open('x', encoding='utf-8') as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write('\n')


def main():
    raw_path = E / 'physical-audit-v2.json'
    raw = read(raw_path)
    assert raw['ProbeQualified'] and raw['AllIndependentChecksPassed']
    assert raw['GlobalTimingPassed'] and raw['ResourcesPassed']
    assert not any(raw[k] for k in (
        'CandidateQualified', 'Downloadable', 'BitGenerationAllowed',
        'HardwareValidated', 'FullSystemTimingSignoff'))
    run = Path(raw['Run'])
    assert not list(run.rglob('*.bit'))
    assert not list((ROOT / 'fpga/custom_project/sc520-timing23').rglob('*.bit'))
    compact = copy.deepcopy(raw)
    reset = compact['IndependentChecks']['TenResetBranchesAndOutboundTiming']['Evidence']
    sets = {}
    for row in reset['OutboundPaths']:
        paths, own, copacked = [row.pop(k) for k in ('Paths', 'OwnQPaths', 'CoPackedQPaths')]
        own_indices = [i for i, p in enumerate(paths) if p['OwnResetQ']]
        other_indices = [i for i, p in enumerate(paths) if not p['OwnResetQ']]
        assert own == [paths[i] for i in own_indices]
        assert copacked == [paths[i] for i in other_indices]
        clean = [{k: v for k, v in p.items() if k != 'OwnResetQ'} for p in paths]
        key = hashlib.sha256(json.dumps(clean, sort_keys=True).encode()).hexdigest().upper()
        if key in sets:
            assert sets[key] == clean
        else:
            sets[key] = clean
        row.update(PathSet=key, OwnQPathIndices=own_indices, CoPackedQPathIndices=other_indices)
    reset['OutboundPathSets'] = sets
    expanded = copy.deepcopy(compact)
    expanded_reset = expanded['IndependentChecks']['TenResetBranchesAndOutboundTiming']['Evidence']
    expanded_sets = expanded_reset.pop('OutboundPathSets')
    for row in expanded_reset['OutboundPaths']:
        clean = expanded_sets[row.pop('PathSet')]
        own_indices, other_indices = [row.pop(k) for k in ('OwnQPathIndices', 'CoPackedQPathIndices')]
        paths = [{**p, 'OwnResetQ': p['SourceNet'] == row['Reset']} for p in clean]
        row.update(Paths=paths, OwnQPaths=[paths[i] for i in own_indices],
                   CoPackedQPaths=[paths[i] for i in other_indices])
    assert expanded == raw, 'Compact evidence must reconstruct every original field'
    compact['CompactView'] = {
        'OriginalAudit': art(raw_path), 'LosslessRoundTripVerified': True,
        'SharedResetPathSetCount': len(sets), 'Program': art(__file__),
        'Scope': 'Storage view of physical-audit-v2; no new physical execution or qualification.',
    }
    compact_path = E / 'physical-audit-compact-v1.json'
    emit(compact_path, compact)
    source = ROOT / 'fpga/scripts/sc520-card-recognition/audit-timing23-physical.py'
    bound = next(x for x in raw['Programs'] if Path(x['Path']).name == source.name)
    assert sha(source) == bound['SHA256']
    source_dir = E / 'audit-source-v2'
    source_dir.mkdir(exist_ok=False)
    shutil.copyfile(source, source_dir / source.name)
    assert sha(source_dir / source.name) == bound['SHA256']
    checked = {}

    def references(value):
        if isinstance(value, dict):
            if 'Path' in value and 'SHA256' in value:
                path = Path(value['Path']).resolve()
                key = str(path).casefold()
                if key not in checked:
                    checked[key] = sha(path)
                assert checked[key] == value['SHA256'].upper(), value['Path']
                if 'Bytes' in value:
                    assert path.stat().st_size == value['Bytes'], value['Path']
            for child in value.values():
                references(child)
        elif isinstance(value, list):
            for child in value:
                references(child)

    references(raw)
    software = read(E / 'software-validation-v1.json')
    references(software)
    start = read(E / 'start.json')
    references(start)
    assert len(start['Protected']) == 763
    history = read(E / 'physical-audit-v1.json')
    historical_program = next(x for x in history['Programs'] if Path(x['Path']).name == source.name)
    manifest = {
        'At': datetime.datetime.now().astimezone().isoformat(),
        'Owner': raw['Owner'], 'Task': 'D057/D059 T023',
        'Status': '离线时序及资源审计通过，等待主对话审核；无下载镜像',
        'BaseCommit': start['BaseCommit'], 'Run': str(run),
        'PhysicalAudit': art(raw_path), 'CompactPhysicalAudit': art(compact_path),
        'Software': art(E / 'software-validation-v1.json'), 'Start': art(E / 'start.json'),
        'Guide': art(ROOT / 'hardware/sc520-card-recognition/timing23-validation.md'),
        'AuditorSource': art(source_dir / source.name),
        'HistoricalFailedAudit': art(E / 'physical-audit-v1.json'),
        'HistoricalProgramSHA256': historical_program['SHA256'],
        'HistoricalProgramSourceAvailable': False,
        'HistoricalSourceLimitation': 'The v1 program digest is retained. Exact reconstruction '
            'of its pre-line-ending-patch source did not match; current source is archived only as v2.',
        'ReferencesChecked': len(checked), 'ProtectedCount': 763,
        'TimingNs': raw['TimingNs'], 'Resources': raw['Resources'],
        'OriginalSynchronizerPairs': raw['OriginalSynchronizerPairs'],
        'AdditionalResetPairs': raw['AdditionalResetPairs'],
        'DisplayLayers': 6, 'SampleToOutputEdges': 5, 'ISPPixelLatency': 54,
        'DiagnosticSnapshotBits': 800, 'BusinessAudioSnapshotBits': 31,
        'Preview': [f['Preview'] for f in software['FullFrames']],
        'BuildKeyReports': [art(p) for p in sorted((run / 'analysis').glob('*.rpt'))],
        'Program': art(__file__), 'BitGenerationAllowed': False, 'Downloadable': False,
        'HardwareValidated': False, 'FullSystemTimingSignoff': False,
        'Limits': raw['Limits'],
    }
    emit(E / 'validation-manifest-v1.json', manifest)
    print(json.dumps({'CompactBytes': compact_path.stat().st_size, 'ResetPathSets': len(sets),
                      'References': len(checked), 'Protected': 763, 'Downloadable': False}))


if __name__ == '__main__':
    main()
