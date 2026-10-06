"""Qualify an explicit set of eight simulations; never select latest runs.

Selection JSON: {"Runs": [{"Testcase":"osd", "Negative":false,
"Manifest":"absolute/or/repo-relative/run-manifest.json"}, ...]}.
Use --runs-json selection.json --write to freeze the final verification manifest.
Without --write this script is read-only. Without --runs-json it revalidates the
already selected verification-manifest.json, including its artifact hashes.
"""
from pathlib import Path
import argparse
import datetime as dt
import hashlib
import json
import re
import uuid

REPO = Path(__file__).resolve().parents[3]
EVIDENCE = REPO/'evidence/sc520-quiz-video'
RUNS = EVIDENCE/'runs'
HDL = 'fpga/custom_project/sc520-quiz-video/user_source/hdl_source'
EXPECTED = {(name, negative) for name in ('osd','runtime','video','full') for negative in (False,True)}


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest().upper()


def load(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def resolve(path):
    value = Path(path)
    return (value if value.is_absolute() else REPO/value).resolve()


def input_set(testcase):
    if testcase == 'osd':
        sources = ['quiz/quiz_osd.v','quiz/quiz_content.v','quiz/quiz_font_rom.v']
        top = 'tb_quiz_osd'
    elif testcase == 'runtime':
        sources = ['quiz/quiz_millisecond_tick.v','quiz/quiz_boot_controls.v','quiz/quiz_mock_player.v']
        top = 'tb_quiz_runtime'
    else:
        sources = ['roi/pixel_coord_adapter.v','roi/rgb_color_segment.v','roi/color_bbox_stats.v',
                   'roi/bbox_stabilizer.v','roi/shape_classifier.v','roi/shape_confirm.v','learning/detection_adapter.v']
        sources += ['quiz/'+p.name for p in sorted((REPO/HDL/'quiz').glob('*.v'))]
        top = 'tb_quiz_video'
    names = {HDL+'/'+name for name in sources}
    names.add(f'fpga/sim/sc520-quiz-video/{top}.sv')
    if testcase != 'runtime':
        names.add('fpga/sim/sc520-quiz-video/quiz_bitmap_reference.svh')
    names.update(('fpga/scripts/sc520-quiz-video/simulate.ps1','fpga/scripts/sc520-quiz-video/run-sim.do'))
    return names


def verify_run(selection):
    testcase, negative = selection['Testcase'], selection['Negative']
    require(type(negative) is bool, 'Selection Negative must be a JSON boolean')
    require((testcase,negative) in EXPECTED, 'Unsupported selected testcase')
    path = resolve(selection['Manifest'])
    require(path.name == 'run-manifest.json' and path.is_relative_to(RUNS.resolve()), 'Run is not inside task runs directory')
    if 'ManifestSHA256' in selection:
        require(sha(path) == selection['ManifestSHA256'], f'Selected run manifest changed: {path}')
    data = load(path)
    directory = path.parent
    require(data.get('Task') == 'sc520-quiz-video' and data.get('Testcase') == testcase and
            data.get('Negative') is negative, f'Run identity mismatch: {path}')
    require(resolve(data['WorkingDirectory']) == directory, 'Run working directory mismatch')
    require(data.get('ExpectedExitCode') == int(negative) and data.get('ExitCode') == int(negative), 'Unexpected simulation exit code')
    require(data.get('ChangedInputs') == [], 'Inputs changed while running')
    before, after = data['InputsSHA256'], data['InputsAfterSHA256']
    require(set(before) == input_set(testcase) and set(before) == set(after), 'Input set does not match selected testcase')
    for name, digest in before.items():
        current = resolve(name)
        snapshot = (directory/'inputs'/name).resolve()
        require(current.is_relative_to(REPO) and snapshot.is_relative_to(directory/'inputs'), 'Escaping input path')
        require(after[name] == digest and sha(current) == digest and sha(snapshot) == digest, f'Input hash mismatch: {name}')
    outputs = data['OutputSHA256']
    required_outputs = {'summary.json','transcript.log','wave.wlf'}
    if testcase in ('video','full'):
        required_outputs.add('video-frames.csv')
    require(required_outputs <= set(outputs), 'Missing required summary/log/wave/trace')
    for name, digest in outputs.items():
        output = (directory/name).resolve()
        require(output.is_relative_to(directory) and output.is_file(), f'Invalid output: {name}')
        require(sha(output) == digest, f'Output hash mismatch: {output}')
    require(all((directory/name).stat().st_size > 0 for name in required_outputs), 'Empty required output')
    summary = load(directory/'summary.json')
    require(data.get('Summary') == summary and summary.get('done') == 1 and summary.get('checks',0) > 0,
            'Incomplete or inconsistent summary')
    require(summary.get('testcase') == testcase and summary.get('negative') == int(negative), 'Summary identity mismatch')
    require(summary['errors'] > 0 if negative else summary['errors'] == 0, 'Unexpected assertion result')
    command = data.get('Command','')
    require(re.search(r'\bset quiz_test '+testcase+r'\b', command) and
            re.search(r'\bset quiz_negative '+str(int(negative))+r'\b',command), 'Command/test identity mismatch')
    if testcase in ('video','full'):
        require(re.search(r'\bset quiz_full '+str(int(testcase=='full'))+r'\b',command), 'Wrong full-frame parameter')
    transcript = (directory/'transcript.log').read_text(encoding='utf-8', errors='replace')
    require(not re.search(r'(?m)^#\s*\*\*\s*(?:Error|Fatal):', transcript), 'Simulator compilation/runtime error')
    require(all(int(value) == 0 for value in re.findall(r'\bErrors:\s*(\d+)',transcript)), 'Nonzero simulator error count')
    lines = re.findall(r'(?m)^#\s*SUMMARY\b[^\r\n]*', transcript)
    require(lines, 'No testbench SUMMARY line')
    numbers = dict((key,int(value)) for key,value in re.findall(r'(\w+)=(\d+)',lines[-1]))
    require(numbers.get('errors') == summary['errors'] and numbers.get('checks') == summary['checks'], 'Transcript/summary counts differ')
    if 'test_done' in numbers:
        require(numbers['test_done'] == 1, 'Transcript says unfinished')
    failures = re.findall(r'(?m)^#\s*(?:CHECK_FAIL|FAIL)\b[^\r\n]*', transcript)
    require(bool(failures) if negative else not failures, 'Missing negative checker failure or unexpected normal failure')
    require('watchdog' not in '\n'.join(failures).lower(), 'Watchdog is not a valid negative test')
    warnings = [int(x) for x in re.findall(r'Warnings:\s*(\d+)',transcript)]
    return dict(Testcase=testcase, Negative=negative, Manifest=str(path), ManifestSHA256=sha(path),
                Summary=summary, TranscriptSummary=lines[-1], ExitCode=data['ExitCode'],
                ToolWarningsMax=max(warnings,default=0),
                Trace=str(directory/'video-frames.csv') if testcase in ('video','full') else None)


def artifacts():
    paths = set()
    for base, patterns in [
        (REPO/'fpga/scripts/sc520-quiz-video',('*.py','*.ps1','*.do')),
        (REPO/'fpga/sim/sc520-quiz-video',('*.sv','*.svh')),
        (REPO/HDL/'quiz',('*.v',)),
        (EVIDENCE,('*.md','*.html','*.png','*.jpg','origin.json','project-manifests.json','warning-analysis.json'))]:
        for pattern in patterns:
            paths.update(base.glob(pattern))
    paths.add(REPO/HDL/'design_top_wrapper.v')
    paths.add(REPO/'memory/branches/sc520-quiz-video.md')
    paths.add(Path('E:/juan/FPGA/learning/sc520-quiz-video/README.md'))
    paths.add(REPO/'fpga/custom_project/sc520-quiz-video/td_project/camera_to_dsi_display.al')
    for stage in ('syn_1','phy_1'):
        paths.add(REPO/f'fpga/custom_project/sc520-quiz-video/td_project/camera_to_dsi_display_Runs/{stage}/camera_to_dsi_display.prj')
    return [dict(Path=str(path), SHA256=sha(path)) for path in sorted(paths) if path.is_file()]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--runs-json', type=Path)
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    output = EVIDENCE/'verification-manifest.json'
    old = load(output) if not args.runs_json and output.is_file() else None
    require(args.runs_json or old is not None, 'Provide --runs-json with eight explicit selections; there is no latest-run discovery')
    source = load(args.runs_json) if args.runs_json else old
    selections = source if isinstance(source,list) else source.get('Runs',source.get('Tests',[]))
    require(len(selections) == 8, 'Exactly eight selected runs required')
    identities = [(entry['Testcase'],entry['Negative']) for entry in selections]
    require(len(set(identities)) == 8 and set(identities) == EXPECTED, 'Require normal/negative for osd/runtime/video/full, without duplicates')
    tests = [verify_run(entry) for entry in selections]
    protect_path = EVIDENCE/'protected-before.json'
    protected = load(protect_path)['Files']
    require(len(protected) == 883, 'Unexpected protection snapshot scope')
    for entry in protected:
        require(sha(entry['Path']) == entry['SHA256'], f'Protected file changed: {entry["Path"]}')
    current_artifacts = artifacts()
    if old and not args.write:
        require(sha(protect_path) == old['ProtectedSnapshotSHA256'], 'Protection snapshot changed')
        require({entry['Path']:entry['SHA256'] for entry in old['Artifacts']} ==
                {entry['Path']:entry['SHA256'] for entry in current_artifacts}, 'Handoff artifact set/hash changed')
    payload = dict(Task='sc520-quiz-video', Status='RTL_simulation_verified_waiting_build_or_review',
                   VerifiedAt=dt.datetime.now(dt.timezone(dt.timedelta(hours=8))).isoformat(), Tests=tests,
                   Artifacts=current_artifacts, ProtectedCount=len(protected), ProtectedDifferences=[],
                   ProtectedSnapshotSHA256=sha(protect_path), HardwareTested=False, PhysicalAudioTested=False,
                   Note='Explicit selected RTL simulations only. TD build evidence is verified separately by verify-build.py.')
    if args.write:
        temporary = output.with_name('.verification-manifest-'+uuid.uuid4().hex+'.tmp')
        temporary.write_text(json.dumps(payload, ensure_ascii=False, indent=2)+'\n',encoding='utf-8')
        temporary.replace(output)
    total = sum(test['Summary']['checks'] for test in tests if not test['Negative'])
    print(f'EVIDENCE_VERIFIED runs=8 normal_checks={total} protected={len(protected)} written={int(args.write)}')


if __name__ == '__main__':
    main()
