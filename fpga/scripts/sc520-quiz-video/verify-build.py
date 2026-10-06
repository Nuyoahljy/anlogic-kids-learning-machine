"""Read-only build preflight or archived build verification."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import runpy


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest().upper()


def load(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def require(ok, text):
    if not ok:
        raise RuntimeError(text)


def preflight(repo):
    project = repo/'fpga/custom_project/sc520-quiz-video'
    quiz = project/'user_source/hdl_source/quiz'
    for name in ('quiz_control.v','quiz_audio_queue.v','hdmi_quiz.v','quiz_millisecond_tick.v',
                 'quiz_mock_player.v','quiz_boot_controls.v','quiz_osd.v','quiz_font_rom.v'):
        require((quiz/name).is_file(), f'Missing final module: {name}')
    top = (project/'user_source/hdl_source/design_top_wrapper.v').read_text(encoding='utf-8-sig')
    require(re.search(r'\bhdmi_quiz\b', top), 'Board top still lacks hdmi_quiz')
    paths = [project/'td_project/camera_to_dsi_display.al'] + [
        project/f'td_project/camera_to_dsi_display_Runs/{s}/camera_to_dsi_display.prj' for s in ('syn_1','phy_1')]
    for path in paths:
        text = path.read_text(encoding='utf-8-sig')
        references = []
        for name in re.findall(r'<File Path="([^"]+)"', text):
            resolved = (path.parent/name).resolve()
            require(resolved.is_relative_to(project.resolve()) and resolved.is_file(), f'Invalid file reference: {name}')
            references.append(resolved)
        for file in quiz.glob('*.v'):
            require(file.resolve() in references, f'Module absent from {path.name}: {file.name}; refresh manifests')
    origin = load(repo/'evidence/sc520-quiz-video/origin.json')
    mutable = {'design_top_wrapper.v','camera_to_dsi_display.al','camera_to_dsi_display.prj'}
    for entry in origin['Files']:
        require(sha(entry['Source']) == entry['SourceSHA256'], f'Origin changed: {entry["Source"]}')
        if Path(entry['Destination']).name not in mutable:
            require(sha(entry['Destination']) == entry['PreparedSHA256'], f'Imported source modified: {entry["Destination"]}')
    protected = load(repo/'evidence/sc520-quiz-video/protected-before.json')['Files']
    for entry in protected:
        require(sha(entry['Path']) == entry['SHA256'], f'Protected file changed: {entry["Path"]}')
    print(f'PREFLIGHT_PASS quiz_files={len(list(quiz.glob("*.v")))} origin={len(origin["Files"])} protected={len(protected)}')


def verify(directory):
    archive = load(directory/'archive-manifest.json')
    result = load(archive['BuildResult'])
    require(archive['Variant'] == 'quiz-video' and result['Variant'] == 'quiz-video', 'Wrong task')
    require(sha(archive['BuildResult']) == archive['BuildResultSHA256'], 'Result changed')
    require(not result['ChangedInputs'], 'Input mutation recorded')
    for entry in archive['Artifacts'].values():
        require(sha(entry['Path']) == entry['SHA256'], f'Artifact changed: {entry["Path"]}')
    require(sha(result['SourceSnapshot']) == result['SourceSnapshotSHA256'], 'Source list changed')
    helpers = runpy.run_path(str(directory/'tools/archive-build.py'))
    input_hashes = load(result['SourceSnapshot'])
    for project in (result['SourceProject'], result['BuildProject']):
        require(helpers['input_names'](Path(project)) == set(input_hashes), 'Input set changed after build')
    for relative, digest in input_hashes.items():
        for project in (result['SourceProject'], result['BuildProject']):
            require(sha(Path(project)/relative) == digest, f'Source bytes changed: {relative}')
    started = load(directory/'started.json')
    require(sha(started['ProtectionSnapshot']) == started['ProtectionSnapshotSHA256'], 'Protection list changed')
    protected = load(started['ProtectionSnapshot'])['Files']
    for entry in protected:
        require(sha(entry['Path']) == entry['SHA256'], f'Protected bytes changed: {entry["Path"]}')
    require([s['Stage'] for s in result['Stages']] == ['syn_1','phy_1'] and
            all(s['ExitCode'] == 0 and s['MarkerFresh'] for s in result['Stages']), 'Missing successful fresh stages')
    metrics = helpers['metrics']((directory/'final_timing.rpt').read_text(encoding='utf-8', errors='replace'),
                                 (directory/'final_area.rpt').read_text(encoding='utf-8', errors='replace'),
                                 Path(result['Stages'][1]['Stdout']).read_text(encoding='utf-8', errors='replace'))
    require(metrics == archive['Metrics'], 'Archived metrics do not match reports')
    require(archive['Metrics']['TimingNonnegative'], 'Bit built but routed timing has negative slack')
    require(archive['HardwareValidated'] is False and archive['PhysicalAudioImplemented'] is False, 'Invalid hardware claim')
    print(f'BUILD_VERIFIED artifacts={len(archive["Artifacts"])} protected={len(protected)} bit={result["SHA256"]}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--preflight', action='store_true')
    parser.add_argument('--build-directory', type=Path)
    args = parser.parse_args()
    if args.preflight:
        preflight(Path(__file__).resolve().parents[3])
    elif args.build_directory:
        verify(args.build_directory.resolve())
    else:
        parser.error('Use --preflight or --build-directory')
