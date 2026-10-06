"""Copy only verified build inputs, without replacing peer-owned new RTL."""
from pathlib import Path
import argparse
import datetime as dt
import hashlib
import json
import os
import re
import shutil
import xml.etree.ElementTree as ET

REPO = Path(__file__).resolve().parents[3]
SOURCE = REPO / 'fpga/custom_project/sc520-learning-ui-audio'
PROJECT = REPO / 'fpga/custom_project/sc520-quiz-video'
EVIDENCE = REPO / 'evidence/sc520-quiz-video'
MANIFESTS = ['td_project/camera_to_dsi_display.al'] + [
    f'td_project/camera_to_dsi_display_Runs/{stage}/camera_to_dsi_display.prj'
    for stage in ('syn_1', 'phy_1')]


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest().upper()


def load(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def now():
    return dt.datetime.now(dt.timezone(dt.timedelta(hours=8))).isoformat()


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def save(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')


def allowed(relative):
    return relative.startswith(('user_source/', 'td_project/al_ip/')) or relative in (
        MANIFESTS + ['td_project/camera_to_dsi_display.sdc'] + [
            f'td_project/camera_to_dsi_display_Runs/{s}/{n}'
            for s in ('syn_1', 'phy_1') for n in ('camera_to_dsi_display.tcl', 'settings.cfg')])


def protect():
    path = EVIDENCE / 'protected-before.json'
    if path.exists():
        files = load(path)['Files']
        for entry in files:
            require(sha(entry['Path']) == entry['SHA256'], f"Protected bytes changed: {entry['Path']}")
        return
    previous = load(REPO / 'evidence/sc520-quiz-control/protected-before.json')
    paths = {Path(entry['Path']).resolve() for entry in previous['Files']}
    # Protect the preceding software handoff too; no wave/cache recopy required.
    handoff = load(REPO / 'evidence/sc520-quiz-control/verification-manifest.json')
    paths.update(Path(entry['Path']).resolve() for entry in handoff['Artifacts'])
    paths.add(REPO / 'evidence/sc520-quiz-control/verification-manifest.json')
    for name in ('sc520-shape', 'sc520-osd-demo', 'sc520-learning-ui-audio'):
        candidate = REPO / f'evidence/{name}/candidate-manifest.json'
        paths.add(candidate)
        paths.add(Path(load(candidate)['Candidate']))
    save(path, dict(CapturedAt=now(), Owner='01a11124-e100-75e2-9e85-9f9686e23c73 /root/audio',
                    Purpose='Before independent quiz video preparation; old candidates and source bytes protected',
                    Files=[dict(Path=str(p), SHA256=sha(p)) for p in sorted(paths)]))


def refresh():
    quiz = sorted((PROJECT / 'user_source/hdl_source/quiz').glob('*.v'))
    outputs = []
    for relative in MANIFESTS:
        original = (SOURCE / relative).read_bytes()
        text = original.decode('utf-8-sig')
        text = re.sub(r'(<Project\b[^>]*?) Path="[^"]*"', r'\1 Path="."', text, count=1)
        orders = [int(n) for n in re.findall(r'Name="CompileOrder" Val="(\d+)"', text)]
        order = max(orders, default=0) + 1
        additions = []
        for index, filename in enumerate(quiz):
            reference = os.path.relpath(filename, (PROJECT / relative).parent).replace('\\', '/')
            additions.append(f'            <File Path="{reference}"><FileInfo>'
                             f'<Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&amp;R" Val="true"/>'
                             f'<Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="{order+index}"/>'
                             f'</FileInfo></File>')
        require(text.count('</Verilog>') == 1, f'Unexpected Verilog section: {relative}')
        text = text.replace('        </Verilog>', '\n'.join(additions)+'\n        </Verilog>')
        # Existing files use literal P&R in attributes; TD accepts this syntax,
        # although general XML parsers do not. Keep its format unchanged.
        text = text.replace('UsedInP&amp;R', 'UsedInP&R')
        target = PROJECT / relative
        data = text.encode('utf-8')
        if not target.exists() or target.read_bytes() != data:
            target.write_bytes(data)
        for reference in re.findall(r'<File Path="([^"]+)"', text):
            resolved = (target.parent / reference).resolve()
            require(resolved.is_relative_to(PROJECT.resolve()), f'External project file: {reference}')
            require(resolved.is_file(), f'Missing project reference: {resolved}')
        outputs.append(dict(Path=str(target), SHA256=sha(target)))
    return dict(RefreshedAt=now(), QuizFiles=[str(p) for p in quiz], Manifests=outputs)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--refresh-manifests', action='store_true')
    args = parser.parse_args()
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    protect()
    candidate_path = REPO / 'evidence/sc520-learning-ui-audio/candidate-manifest.json'
    candidate = load(candidate_path)
    require(sha(candidate['Candidate']) == candidate['SHA256'], 'Learning candidate changed')
    require(sha(candidate['SourceSnapshot']) == candidate['SourceSnapshotSHA256'], 'Source snapshot changed')
    inputs = load(candidate['SourceSnapshot'])
    for relative, digest in inputs.items():
        require(allowed(relative), f'Refuse output/cache in input snapshot: {relative}')
        require(sha(SOURCE / relative) == digest, f'Old source changed: {relative}')
    if args.refresh_manifests:
        require((EVIDENCE / 'origin.json').is_file(), 'Run initial prepare first')
        result = refresh()
        save(EVIDENCE / 'project-manifests.json', result)
        print(f'REFRESHED quiz_files={len(result["QuizFiles"])} manifests=3')
        return
    origin_path = EVIDENCE / 'origin.json'
    if origin_path.exists():
        raise RuntimeError('Preparation already recorded; use --refresh-manifests; never overwrite origin')
    copied = []
    for relative, digest in sorted(inputs.items()):
        target = PROJECT / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        existed = target.exists()
        if not existed:
            shutil.copyfile(SOURCE / relative, target)
        require(sha(target) == digest or relative == 'user_source/hdl_source/design_top_wrapper.v',
                f'Existing destination differs; not overwriting: {relative}')
        copied.append(dict(Source=str(SOURCE / relative), Destination=str(target),
                           SourceSHA256=digest, PreparedSHA256=sha(target), Copied=not existed))
    for name in ('quiz_control.v', 'quiz_audio_queue.v'):
        original = REPO / f'fpga/custom_project/sc520-quiz-control/{name}'
        target = PROJECT / f'user_source/hdl_source/quiz/{name}'
        target.parent.mkdir(parents=True, exist_ok=True)
        existed = target.exists()
        if not existed:
            shutil.copyfile(original, target)
        require(sha(original) == sha(target), f'Quiz source copy differs: {name}')
        copied.append(dict(Source=str(original), Destination=str(target), SourceSHA256=sha(original),
                           PreparedSHA256=sha(target), Copied=not existed))
    result = refresh()
    save(EVIDENCE / 'project-manifests.json', result)
    save(origin_path, dict(PreparedAt=now(), Source=str(SOURCE), Destination=str(PROJECT),
                          CandidateManifest=str(candidate_path), CandidateManifestSHA256=sha(candidate_path),
                          Candidate=str(candidate['Candidate']), CandidateSHA256=candidate['SHA256'],
                          SourceSnapshot=candidate['SourceSnapshot'], SourceSnapshotSHA256=candidate['SourceSnapshotSHA256'],
                          Files=copied, UpdatedManifests=result['Manifests'],
                          PixelClockHz=75000000, PixelClockEvidence='PLL.clk4_out -> S_hdmi_pixel_clk; PLL.v C4=75MHz',
                          HardwareValidated=False))
    print(f'PREPARED old_inputs={len(inputs)} quiz_copies=2 destination={PROJECT}')


if __name__ == '__main__':
    main()
