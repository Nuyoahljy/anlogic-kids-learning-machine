"""Validate current sources, actual test evidence and TD output before copying a bit."""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[3]
TASK = 'sc520-learning-ui-audio'
EVIDENCE = ROOT / 'evidence' / TASK
PROJECT = ROOT / 'fpga/custom_project' / TASK


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest().upper()


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def verify_map(values, base=ROOT):
    for name, expected in values.items():
        path = Path(name)
        if not path.is_absolute():
            path = base / path
        require(sha(path) == expected.upper(), f'Changed input/output: {path}')


def latest(paths, negative):
    candidates = [p for p in paths if bool(read(p).get('Negative')) == negative]
    require(candidates, f'Missing report, negative={negative}')
    return max(candidates, key=lambda p: p.stat().st_mtime_ns)


def validate_test(path, kind, negative):
    report = read(path)
    require(report['ExitCode'] == (1 if negative else 0), f'Unexpected process exit: {path}')
    require(report['ExpectedExitCode'] == report['ExitCode'], f'Incorrect exit expectation: {path}')
    if kind == 'transition':
        require(report['Phase'] == 'after-fix', 'Transition must use the fixed implementation')
    source_key = next((key for key in ['InputSHA256', 'SourceSHA256', 'SourceSHA256Before'] if key in report), None)
    require(source_key is not None, f'No input binding: {path}')
    verify_map(report[source_key])
    if 'SourceSHA256After' in report:
        require(report['SourceSHA256After'] == report[source_key] and not report['ChangedInputs'], 'Inputs changed during test')
    if 'InputsUnchanged' in report:
        require(report['InputsUnchanged'], 'Test input changed')
    if 'OutputSHA256' in report:
        verify_map(report['OutputSHA256'])
    for artifact in report.get('Artifacts', {}).values():
        require(sha(artifact['Path']) == artifact['SHA256'], 'Changed recorded artifact')
    summary = report['Summary']
    summary_path = Path(summary) if isinstance(summary, str) else path.parent / 'summary.json'
    if isinstance(summary, str):
        summary = read(summary_path)
    else:
        require(summary == read(summary_path), 'Summary object/file mismatch')
    if 'SummarySHA256' in report:
        require(sha(summary_path) == report['SummarySHA256'], 'Summary changed')
    expected_errors = {'demo': 4, 'events': 1, 'audio': 1, 'osd': 5406984}.get(kind, 0) if negative else 0
    require(summary['testcase'] == ('learning_osd' if kind == 'osd' else kind), 'Wrong test type')
    if kind != 'transition':
        require(bool(summary['negative']) == negative, 'Wrong negative-control mode')
    require(summary['done'] == 1 and summary['errors'] == expected_errors, f'Unexpected summary: {path}')
    if 'Log' in report:
        log = Path(report['Log'])
        require(sha(log) == report['LogSHA256'], 'Transcript changed')
    else:
        log = summary_path.parent / 'transcript.log'
    transcript = log.read_text(encoding='utf-8', errors='replace')
    require(re.search(r'RESULT[^\r\n]*errors=' + str(expected_errors) + r'\b', transcript), f'Missing actual result in {log}')
    return dict(Kind=kind, Negative=negative, Report=str(path), ReportSHA256=sha(path),
                Summary=str(summary_path), SummarySHA256=sha(summary_path), Result=summary,
                Transcript=str(log), TranscriptSHA256=sha(log), ExitCode=report['ExitCode'])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--build-directory', type=Path, required=True)
    args = parser.parse_args()
    args.build_directory = args.build_directory.resolve()
    origin = read(EVIDENCE / 'origin.json')
    verify_map(origin['SourceInputs'], Path(origin['Source']))
    require(sha(origin['Rollback']) == origin['RollbackSHA256'], 'OSD candidate changed')
    protected = read(EVIDENCE / 'protected-inputs.json')
    verify_map(protected)
    changed = [name for name, digest in origin['SourceInputs'].items() if sha(PROJECT / name) != digest]
    expected_changes = ['user_source/hdl_source/design_top_wrapper.v', 'td_project/camera_to_dsi_display.al',
                        'td_project/camera_to_dsi_display_Runs/syn_1/camera_to_dsi_display.prj',
                        'td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display.prj']
    require(set(changed) == set(expected_changes), f'Unexpected inherited changes: {changed}')
    old_top = (Path(origin['Source']) / expected_changes[0]).read_bytes()
    require((PROJECT / expected_changes[0]).read_bytes() == old_top.replace(b'hdmi_osd_demo', b'hdmi_learning'), 'Unexpected board top change')
    for project_file in expected_changes[1:]:
        text = (PROJECT / project_file).read_text(encoding='utf-8-sig')
        for name in ['detection_adapter', 'learning_events', 'audio_event_player', 'mock_audio_player',
                     'learning_content', 'learning_font_rom', 'learning_osd', 'hdmi_learning']:
            require(text.count('/learning/' + name + '.v"') == 1, f'Source list: {name} / {project_file}')
    tests = []
    for kind, negatives in [('sequence', [False]), ('demo', [False, True]), ('full', [False])]:
        reports = list((EVIDENCE / 'sim-runs').glob(f'launch-{kind}-*.log.json'))
        for negative in negatives:
            tests.append(validate_test(latest(reports, negative), kind, negative))
    for kind, manifest_name in [('events', 'run-manifest.json'), ('osd', 'run-manifest.json'),
                                ('audio', 'manifest.json'), ('transition', 'run-manifest.json')]:
        reports = list((EVIDENCE / (kind + '-runs')).glob('*/' + manifest_name))
        for negative in ([False] if kind == 'transition' else [False, True]):
            tests.append(validate_test(latest(reports, negative), kind, negative))
    build_path = args.build_directory / 'result.json'
    build = read(build_path)
    require(build['Variant'] == 'learning-ui-audio', 'Incorrect build variant')
    require(len(build['Stages']) == 2 and all(s['ExitCode'] == 0 for s in build['Stages']), 'Build did not finish')
    require(sha(build['SourceSnapshot']) == build['SourceSnapshotSHA256'], 'Changed build snapshot')
    verify_map(read(build['SourceSnapshot']), PROJECT)
    archive_path = args.build_directory / 'archive-manifest.json'
    archive = read(archive_path)
    require(archive['BuildResultSHA256'] == sha(build_path), 'Archive/result mismatch')
    for item in archive['Artifacts'].values():
        require(sha(item['Path']) == item['SHA256'], 'Changed archived build artifact')
    frozen_bit = Path(archive['Artifacts']['built.bit']['Path'])
    require(sha(frozen_bit) == build['SHA256'], 'Changed archived bit')
    phy = next(s for s in build['Stages'] if s['Stage'] == 'phy_1')
    text = Path(phy['Stdout']).read_text(encoding='utf-8', errors='replace')
    timings = {}
    for label in ['Setup', 'Hold']:
        matches = re.findall(label + r'\s+: WNS\s+(-?\d+)ps\s+TNS\s+(-?\d+)ps\s+NUM_FEPS\s+(\d+)', text)
        require(matches, f'Missing {label} timing')
        wns, tns, endpoints = map(int, matches[-1])
        require(wns >= 0 and tns == 0 and endpoints == 0, f'Timing failed {label}: {matches[-1]}')
        timings[label + 'WNSps'] = wns
    require('Generate bitstream completely' in text, 'Missing bitgen completion')
    timing_src = Path(archive['Artifacts']['final_timing.rpt']['Path'])
    timing_text = timing_src.read_text(encoding='utf-8', errors='replace')
    coverage = re.search(r'STA coverage\s+: ([\d.]+)%', timing_text)
    require(coverage, 'Missing STA coverage')
    candidates = EVIDENCE / 'candidates'
    candidates.mkdir(exist_ok=True)
    candidate = candidates / 'sc520_learning_ui_audio.bit'
    try:
        with candidate.open('xb') as destination, frozen_bit.open('rb') as source:
            shutil.copyfileobj(source, destination)
    except FileExistsError:
        require(sha(candidate) == build['SHA256'], 'Refuse to replace a different candidate')
    require(sha(candidate) == build['SHA256'], 'Candidate copy mismatch')
    now = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat()
    result = dict(Status='software_verified_waiting_hardware_and_interface_review', GeneratedAt=now,
                  Candidate=str(candidate), SHA256=sha(candidate), Bytes=candidate.stat().st_size,
                  HardwareValidated=False, PhysicalAudioImplemented=False,
                  GitHEAD=subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip(),
                  UncommittedTask=True, Origin=str(EVIDENCE / 'origin.json'), OriginSHA256=sha(EVIDENCE / 'origin.json'),
                  PackageScript=str(Path(__file__).resolve()), PackageScriptSHA256=sha(__file__),
                  OriginalInputsVerified=len(origin['SourceInputs']), ProtectedFilesVerified=len(protected),
                  ChangedImportedInputs=changed, BuildResult=str(build_path), BuildResultSHA256=sha(build_path),
                  BuildArchive=str(archive_path), BuildArchiveSHA256=sha(archive_path),
                  SourceSnapshot=build['SourceSnapshot'], SourceSnapshotSHA256=build['SourceSnapshotSHA256'],
                  TimingReport=str(args.build_directory / 'final_timing.rpt'), TimingSHA256=sha(args.build_directory / 'final_timing.rpt'),
                  AreaReport=str(args.build_directory / 'final_area.rpt'), AreaSHA256=sha(args.build_directory / 'final_area.rpt'),
                  STACoveragePercent=float(coverage.group(1)), Tests=tests, **timings,
                  Risks=['No hardware testing; mock player produces no sound and exports no UART pins',
                         'Same-stream transitions use qualified raw candidate presence; this is not universal object tracking',
                         'Inherited camera/DDR/HDMI PHY not simulated; inherited clock warnings and incomplete STA coverage',
                         'Heuristic shape detection and RGB thresholds remain uncalibrated for real objects',
                         'Local interface/queue/timeout/cancellation semantics await main review'])
    (EVIDENCE / 'candidate-manifest.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    (candidates / 'SHA256SUMS.txt').write_text(sha(candidate) + '  ' + candidate.name + '\n', encoding='ascii')
    print(f'PACKAGED tests={len(tests)} protected={len(protected)} SHA256={sha(candidate)} timing={timings}')


if __name__ == '__main__':
    main()
