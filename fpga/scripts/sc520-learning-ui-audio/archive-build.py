"""Freeze a completed TD run before a later build can replace project outputs."""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import re
import shutil


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest().upper()


def load(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


parser = argparse.ArgumentParser()
parser.add_argument('--build-directory', type=Path, required=True)
args = parser.parse_args()
directory = args.build_directory.resolve()
result_path = directory / 'result.json'
result = load(result_path)
require(result['Variant'] == 'learning-ui-audio', 'Wrong build variant')
require(len(result['Stages']) == 2 and all(s['ExitCode'] == 0 for s in result['Stages']), 'Incomplete TD run')
require(sha(result['SourceSnapshot']) == result['SourceSnapshotSHA256'], 'Build source snapshot changed')
project = Path(__file__).resolve().parents[3] / 'fpga/custom_project/sc520-learning-ui-audio'
for name, digest in load(result['SourceSnapshot']).items():
    require(sha(project / name) == digest, f'Source changed: {name}')
bit = Path(result['Bit'])
require(sha(bit) == result['SHA256'], 'Project bit no longer matches this build')
phy = next(stage for stage in result['Stages'] if stage['Stage'] == 'phy_1')
stdout = Path(phy['Stdout'])
log = stdout.read_text(encoding='utf-8', errors='replace')
require('Generate bitstream completely' in log, 'No bitgen completion in the run log')
created = stdout.stat()
earliest = getattr(created, 'st_birthtime', created.st_ctime) - 2
latest = result_path.stat().st_mtime + 2
timing = bit.parent / 'final_timing.rpt'
area = bit.parent / 'camera_to_dsi_display_phy.area'
timing_text = timing.read_text(encoding='utf-8', errors='replace')
require('Tang Dynasty v6.2.168116' in timing_text and 'Confidence          : Routed' in timing_text, 'Wrong tool or unrouted timing report')
for label, prefix in [('Setup', 'S'), ('Hold', 'H')]:
    log_values = re.findall(label + r'\s+: WNS\s+(-?\d+)ps\s+TNS\s+(-?\d+)ps\s+NUM_FEPS\s+(\d+)', log)
    report_values = re.search(prefix + r'WNS:\s*(-?[\d.]+)ns,\s*' + prefix + r'TNS:\s*(-?[\d.]+)ns', timing_text)
    require(log_values and report_values, 'Missing final timing summaries')
    require(tuple(round(float(v)*1000) for v in report_values.groups()) == tuple(map(int, log_values[-1][:2])), 'Report/console timing mismatch')
artifacts = {}
for source, name in [(bit, 'built.bit'), (timing, 'final_timing.rpt'), (area, 'final_area.rpt')]:
    require(earliest <= source.stat().st_mtime <= latest, f'Output outside this run time interval: {source}')
    digest = sha(source)
    destination = directory / name
    if destination.exists():
        require(sha(destination) == digest, f'Refuse to replace a different archived output: {destination}')
    else:
        shutil.copyfile(source, destination)
    require(sha(destination) == digest and sha(source) == digest, 'Output changed during archive')
    artifacts[name] = dict(Path=str(destination), SHA256=digest, Bytes=destination.stat().st_size,
                           OriginalPath=str(source), OriginalModifiedAt=source.stat().st_mtime)
for stage in result['Stages']:
    for key in ['Stdout', 'Stderr']:
        path = Path(stage[key])
        artifacts[stage['Stage'] + '.' + key] = dict(Path=str(path), SHA256=sha(path), Bytes=path.stat().st_size)
for name, path in [('result.json', result_path), ('source-inputs.json', Path(result['SourceSnapshot']))]:
    artifacts[name] = dict(Path=str(path), SHA256=sha(path), Bytes=path.stat().st_size)
builder = directory / 'build-script.ps1'
if builder.exists():
    artifacts['build-script.ps1'] = dict(Path=str(builder), SHA256=sha(builder), Bytes=builder.stat().st_size)
manifest = dict(ArchivedAt=datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
                BuildResult=str(result_path), BuildResultSHA256=sha(result_path),
                BuilderSnapshotAvailable=builder.exists(), Artifacts=artifacts,
                Note='Explicit post-build snapshot. Timestamps reject reports refreshed after this result; no hardware test.')
archive = directory / 'archive-manifest.json'
if archive.exists():
    prior = load(archive)
    require(prior['BuildResultSHA256'] == manifest['BuildResultSHA256'], 'Archive belongs to another run')
    require({k: v['SHA256'] for k, v in prior['Artifacts'].items()} == {k: v['SHA256'] for k, v in artifacts.items()}, 'Archive changed')
else:
    archive.write_text(json.dumps(manifest, indent=2), encoding='utf-8')
print(f'ARCHIVED {archive} bit={artifacts["built.bit"]["SHA256"]}')
