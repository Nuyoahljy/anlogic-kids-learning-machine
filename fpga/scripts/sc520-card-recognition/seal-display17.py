"""Export the qualified T017 candidate without changing its optical baseline."""
from pathlib import Path
import argparse, datetime, hashlib, json

ROOT = Path(__file__).resolve().parents[3]
E = ROOT / 'evidence/sc520-card-recognition'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def art(path):
    path = Path(path).resolve()
    return {'Path': str(path), 'SHA256': sha(path), 'Bytes': path.stat().st_size}


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--audit', type=Path, required=True)
    args = ap.parse_args()
    report = read(args.audit)
    assert report['CandidateQualified'] and report['Baseline0116Preserved']
    assert len(report['ROMs']) == 39 and report['TotalSynchronizerPairs'] == 21
    assert not report['Resources']['OverCapacity']
    assert report['TimingNs']['SWNS'] >= 0 and report['TimingNs']['HWNS'] >= 0
    assert report['TimingNs']['STNS'] == report['TimingNs']['HTNS'] == 0
    source = Path(report['Bit']['Path'])
    assert art(source) == report['Bit']
    for item in report['ProtectedFiles'] + report['ImportedSources']:
        assert sha(item['Path']) == item['SHA256']
    output = E / 'delivery-0117'
    assert not output.exists(), output
    output.mkdir()
    target = output / 'sc520-pixel17-0117.bit'
    target.write_bytes(source.read_bytes())
    assert sha(target) == sha(source)
    baseline = read(E / 'delivery-0116/manifest.json')
    resource_names = ['lut6', 'reg', 'slice', 'eram', 'dsp']
    delta = {name: report['Resources']['Used'][name] - baseline['Resources']['Used'][name] for name in resource_names}
    software = Path(report['SoftwareValidation']['Path'])
    guide = ROOT / 'hardware/sc520-card-recognition/display17-integration.md'
    document = {'CreatedAt': datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
                'Version': 'D0117', 'Task': 'D046/T017', 'BaselineCommit': '68e2b4d01485fa1b3049d81e98a09c2e3dc98a94',
                'DisplaySourceCommit': 'edaced3542a4a056aa90397aefadb45e279e69e2',
                'SynthesisRun': '6a50b117', 'PhysicalRun': Path(report['Run']).name,
                'Status': '等待主审核；显示整机候选，未上板',
                'Bit': art(target), 'OriginalBit': art(source), 'PhysicalAudit': art(args.audit),
                'SoftwareAudit': art(software), 'Guide': art(guide), 'Resources': report['Resources'],
                'ResourceDeltaFrom0116': delta, 'GlobalTimingNs': report['TimingNs'],
                'ROMCount': 39, 'TotalSynchronizerPairs': 21,
                'MailboxBits': {**{x['Name']: x['Bits'] for x in report['Mailboxes']}, 'color': report['ColorMailbox']['Bits']},
                'DisplayLayers': 6, 'SampleToOutputEdges': 5, 'Baseline0116Preserved': True,
                'AudioIntegrated': False, 'HardwareValidated': False, 'FullSystemTimingSignoff': False,
                'Preview': [frame['Preview'] for frame in read(software)['FullFrames']], 'Program': art(__file__),
                'Limits': report['Scope']}
    with (output / 'manifest.json').open('x', encoding='utf-8') as stream:
        json.dump(document, stream, ensure_ascii=False, indent=2)
        stream.write('\n')
    print(json.dumps({'Bit': str(target), 'SHA256': sha(target), 'ResourceDelta': delta}))


if __name__ == '__main__':
    main()
