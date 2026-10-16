"""Read existing T022 evidence before changing inherited task files; never run TD."""
from pathlib import Path
import argparse, datetime, hashlib, json, subprocess
from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parents[3]
E = ROOT / 'evidence/sc520-card-recognition'


def read(p):
    return json.loads(Path(p).read_text(encoding='utf-8-sig'))


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()


def art(p):
    p = Path(p).resolve()
    return {'Path': str(p), 'SHA256': sha(p), 'Bytes': p.stat().st_size}


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--output', required=True, type=Path)
    ap.add_argument('--owner', required=True)
    args = ap.parse_args()
    assert not args.output.exists()
    checkpoint = Path('E:/juan/FPGA/learning/sc520-contest-roadmap/main-takeover-20261016.json')
    prior = read(checkpoint)
    assert git('branch', '--show-current').decode().strip() == 'task/sc520-card-recognition'
    assert git('rev-parse', 'HEAD').decode().strip() == prior['BoardHead']
    inherited = prior['BoardStableUncommittedHashes']
    assert len(inherited) == 97
    for f in inherited:
        assert sha(f['Path']) == f['SHA256'], f['Path']
    start = read(E / 'audio22/start.json')
    for f in start['Protected'] + start['Imports']:
        assert sha(f['Path']) == f['SHA256'], f['Path']
    for f in start['Imports']:
        blob = git('show', f['SourceCommit'] + ':' + f['SourcePath'])
        assert blob == Path(f['Path']).read_bytes(), f['Path']
        assert git('rev-parse', f['SourceCommit'] + ':' + f['SourcePath']).decode().strip() == f['GitBlob']
    softpath = E / 'audio22/software-validation-v2.json'
    soft = read(softpath)
    assert soft['Qualified'] and len(soft['Runs']) == 12
    assert soft['PositiveScenarios'] == 44 and soft['PositiveChecks'] == 12199365
    references, modes = 0, []
    for f in soft['Runs']:
        assert sha(f['Path']) == f['SHA256']
        r = read(f['Path'])
        mode = f['Mode']
        expected_exit = {'normal': 0, 'negative': 1, 'watchdog': 2}[mode]
        assert r['Qualified'] and r['NativeExitCode'] == expected_exit
        assert r['Summary'] == f['Summary'] and r['Command'] == f['Command']
        s = r['Summary']
        assert s['done'] == int(mode != 'watchdog')
        assert s['errors'] == s['injected'] == int(mode == 'negative')
        for x in r['Inputs']:
            assert sha(x['path']) == sha(x['snapshot']) == x['sha256_before'].upper() == x['sha256_after'].upper() == x['snapshot_sha256'].upper()
            references += 1
        for x in r['Outputs']:
            assert sha(x['path']) == x['sha256'].upper(), x['path']
            references += 1
        modes.append({'Test': f['Test'], 'Mode': mode, 'NativeExitCode': r['NativeExitCode'], 'Summary': s})
    assert references == soft['CurrentReferencesChecked'] == 602
    old = read(ROOT / 'assets/templates/sc520-card-recognition/display17/font-extension.json')
    new = read(ROOT / 'assets/templates/sc520-card-recognition/audio22/font-extension.json')
    glyphs = {x['id']: x for x in new['Glyphs']}
    assert len(old['Glyphs']) == 158 and len(new['Glyphs']) == 163
    assert all(g == glyphs[g['id']] for g in old['Glyphs'])
    frames = []
    for f in soft['FullFrames']:
        images = []
        for name in ('ActualPPM', 'Golden', 'Preview'):
            assert sha(f[name]['Path']) == f[name]['SHA256']
            im = Image.open(f[name]['Path']).convert('RGB')
            assert im.size == (1280, 720)
            images.append(im)
        assert all(ImageChops.difference(images[0], im).getbbox() is None for im in images[1:])
        frames.append(f)
    parent = E / 'builds/6a50b220'
    run = E / 'builds/route220-v2'
    inputs = read(parent / 'inputs.json')
    for f in inputs['Files']:
        assert sha(f['Path']) == f['SHA256']
        if f.get('Snapshot'):
            assert sha(f['Snapshot']) == f['SnapshotSHA256']
    recovery = read(run / 'resume.json')
    for f in recovery['CopiedFiles']:
        assert sha(f['Source']) == sha(f['Path']) == f['SHA256']
    assert not list(run.rglob('*.bit')) and not list(parent.rglob('*.bit'))
    result = {'At': datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
              'Owner': args.owner, 'Program': art(__file__), 'Checkpoint': art(checkpoint),
              'InheritedFilesChecked': 97, 'ProtectedCount': len(start['Protected']),
              'ImportsCheckedAgainstGit': len(start['Imports']), 'Software': art(softpath),
              'RawRunReferencesChecked': references, 'Runs': modes, 'FullFrames': frames,
              'OldGlyphsPreserved': 158, 'GlyphCount': 163, 'InputsChecked': len(inputs['Files']),
              'Recovery': art(run / 'resume.json'), 'RecoveryFilesChecked': len(recovery['CopiedFiles']),
              'SoftwareReexecuted': False, 'SynthesisOrPlacementReexecuted': False,
              'BitFilesFound': [], 'FinalPhysicalQualification': False, 'HardwareValidated': False}
    with args.output.open('x', encoding='utf-8') as stream:
        json.dump(result, stream, ensure_ascii=False, indent=2)
        stream.write('\n')
    print(json.dumps({k: result[k] for k in ('InheritedFilesChecked', 'ProtectedCount', 'ImportsCheckedAgainstGit', 'RawRunReferencesChecked', 'InputsChecked', 'RecoveryFilesChecked')}))


if __name__ == '__main__':
    main()
