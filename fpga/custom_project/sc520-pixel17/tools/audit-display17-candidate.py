"""T017 exact-build adapter: new font/Logo bindings, unchanged CDC/I2C policy."""
from pathlib import Path
import argparse, importlib.util, json, re, subprocess

ROOT = Path(__file__).resolve().parents[4]
LEGACY = ROOT / 'fpga/custom_project/sc520-pixel14/tools'


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


observation = load('display17_observation_audit', LEGACY / 'audit-observation-candidate.py')
base, scene, phys = observation.base, observation.scene, observation.phys
original_logical_roms = base.logical_roms


def logical_roms(run, profile):
    result = original_logical_roms(run, profile)
    result['font']['Instance'] = r'^u_p17_display/panel/font/'
    result['font']['Output'] = r'^u_p17_display/panel/font_bits\[(\d+)\]$'
    for kind, file, width, instance in [
            ('logo-index', 'anlogic_logo_index.mem', 10, r'^u_p17_display/logo/ramread0_'),
            ('logo-palette', 'anlogic_logo_palette.mem', 24, r'^u_p17_display/logo/ramread1_')]:
        words = [int(x, 16) for x in base.read(run / file).split()]
        assert len(words) == (16384 if width == 10 else 1024)
        result[kind] = {'Words': words, 'Width': width, 'Instance': instance, 'Output': r'(?!)', 'ConstantZeroBits': []}
    return result


def preservation(run):
    evidence = ROOT / 'evidence/sc520-card-recognition'
    start_path = evidence / 'display17/start.json'
    start = json.loads(base.read(start_path))
    for item in start['Protected'] + start['Imports']:
        assert base.sha(item['Path']) == item['SHA256'], item['Path']
    assert len(start['Protected']) == 155 and len(start['Imports']) == 9
    baseline = evidence / 'builds/6a50b116'
    unchanged = []
    for folder, names in [('overlay', ['isp_top.v', 'pixel14_color_pipeline.v', 'uii2c.v', 'uicfgcs520.v', 'pin.adc', 'pixel14.sdc']),
                          ('rtl', ['capture_rgb96.v', 'pixel14_capture_provenance.v', 'pixel14_color_observer.v',
                                   'pixel14_observation_join.v', 'pixel14_observation_bridge.v', 'pixel14_color_diag_osd.v',
                                   'pixel14_scene_preprocess.v', 'pixel14_rotation_matcher.v', 'pixel14_block_shape_guard.v',
                                   'pixel14_block_filter.v', 'card_result_filter.v', 'items14_quiz_control.v', 'items14_result_join.v'])]:
        for name in names:
            path = run / folder / name
            assert base.sha(path) == base.sha(baseline / folder / name), name
            unchanged.append(base.artifact(path))
    assert base.sha(run / 'templates.mem') == base.sha(baseline / 'templates.mem')
    top = base.read(run / 'overlay/design_top_wrapper.v')
    for literal in ['.RENDER_ENABLE(0)', 'pixel17_compositor', 'pixel17_display_request',
                    '.SCENE_X(P17_SCENE_X)', '.SCENE_Y(P17_SCENE_Y)', '.SCENE_WIDTH(P17_SCENE_W)',
                    '.SCENE_HEIGHT(P17_SCENE_H)', '.COLOR_DIAGNOSTICS(1)']:
        assert literal in top, literal
    assert 'pixel14_color_diag_osd #' not in top
    assert 'DFR0534' not in top and 'audio_dfr' not in top
    changed = subprocess.check_output(['git', 'diff', '--name-only', start['BaseCommit']], cwd=ROOT, text=True).splitlines()
    allowed = ('fpga/', 'assets/', 'hardware/', 'evidence/sc520-card-recognition/', 'memory/branches/sc520-card-recognition.md')
    assert all(path.startswith(allowed) for path in changed), changed
    return {'StartProtection': base.artifact(start_path), 'ProtectedFiles': start['Protected'], 'ImportedSources': start['Imports'],
            'UnchangedCoreSnapshots': unchanged, 'Baseline0116Preserved': True, 'Baseline0116Bit': base.artifact(baseline / 'td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display.bit')}


def resume_review(run):
    path = run / 'resume.json'
    resume = json.loads(base.read(path))
    parent = Path(resume['ParentRun'])
    assert resume['SynthesisReexecuted'] is False
    assert base.sha(parent / 'stages.json') == resume['ParentStages']
    for item in resume['CopiedFiles']:
        assert base.sha(item['Source']) == base.sha(item['Path']) == item['SHA256'], item
    assert base.sha(run / 'inputs.json') == base.sha(parent / 'inputs.json')
    original_stages = json.loads(base.read(parent / 'stages.json'))
    stages = json.loads(base.read(run / 'result.json'))['Stages']
    assert stages[0] == original_stages, ('Synthesis stage record is not original', stages[0], original_stages)
    return {'PhysicalResume': base.artifact(path), 'InheritedSynthesisStage': original_stages,
            'ResumeCopiedFilesChecked': len(resume['CopiedFiles']), 'SynthesisReexecuted': False}


def audit(run, bindings, coordinator, software):
    # Process-local profile adaptation; historical auditor files are immutable.
    base.logical_roms = logical_roms
    report = observation.audit(run, bindings, coordinator)
    assert report['CandidateQualified'] and len(report['ROMs']) == 39
    assert report['TotalSynchronizerPairs'] == 21
    assert {x['Name']: x['Bits'] for x in report['Mailboxes']} == {'business': 80, 'diagnostic': 106, 'i2c': 28}
    assert report['ColorMailbox']['Bits'] == 762
    report.update(preservation(run))
    report.update(resume_review(run))
    soft = json.loads(base.read(software))
    assert soft['Qualified'] and soft['PositiveScenarios'] == 107 and soft['PositiveChecks'] == 11342730
    for item in soft['Runs']:
        assert base.sha(item['Path']) == item['SHA256']
        manifest = json.loads(base.read(item['Path']))
        for entry in manifest['Inputs']:
            assert base.sha(entry['path']) == base.sha(entry['snapshot']) == entry['sha256_before'].upper()
        for entry in manifest['Outputs']:
            assert base.sha(entry['path']) == entry['sha256'].upper()
    for frame in soft['FullFrames']:
        for entry in ('ActualPPM', 'Golden', 'Preview'):
            assert base.sha(frame[entry]['Path']) == frame[entry]['SHA256']
    report.update({'Program': base.artifact(__file__), 'SoftwareValidation': base.artifact(software),
                   'Purpose': 'T017 current business, full-frame processing, diagnostic and official Logo display integration.',
                   'DisplayLayers': 6, 'SampleToOutputEdges': 5, 'ColorCorrectionChanged': False,
                   'AudioIntegrated': False, 'HardwareValidated': False, 'FullSystemTimingSignoff': False,
                   'Scope': 'ROM/bit/frozen-input/routed timing,21 synchronizer pairs,4 retained mailboxes and parent-clock I2C qualification; optical baseline preserved. No board, audio, new GPIO, CRC/ECC-content, exact DDR frame identity, external electrical or MTBF qualification.'})
    return report


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('run', type=Path)
    ap.add_argument('--bindings', type=Path, required=True)
    ap.add_argument('--coordinator-review', type=Path, required=True)
    ap.add_argument('--software', type=Path, required=True)
    ap.add_argument('--output', type=Path, required=True)
    ap.add_argument('--syn-rom-only', action='store_true')
    args = ap.parse_args()
    if args.syn_rom_only:
        base.logical_roms = logical_roms
        result = base.rom_audit(args.run.resolve(), 'scene', False, json.loads(base.read(args.bindings)))
        assert len(result['ROMs']) == 39 and not result['UnreviewedAddressOrSelectMappings']
        result.update(ROMContentAndSelectQualified=True, CandidateQualified=False, HardwareValidated=False,
                      Program=base.artifact(__file__))
    else:
        result = audit(args.run.resolve(), json.loads(base.read(args.bindings)), args.coordinator_review, args.software)
    base.emit(args.output, result)
    print(json.dumps({'Qualified': result['CandidateQualified'], 'ROMs': len(result['ROMs']), 'Timing': result.get('TimingNs'),
                      'Resources': result.get('Resources', {}).get('Used'), 'Output': str(args.output)}))
