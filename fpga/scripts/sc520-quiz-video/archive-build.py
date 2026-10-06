"""Freeze a new isolated TD run; validate identities, timing and output freshness."""
from pathlib import Path
import argparse
import datetime as dt
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


def stamp(value):
    return dt.datetime.fromisoformat(value).timestamp()


def input_names(project):
    files = list((project/'user_source').rglob('*')) + list((project/'td_project/al_ip').rglob('*'))
    files += [p for p in (project/'td_project').iterdir() if p.suffix in ('.al','.sdc')]
    files += [project/f'td_project/camera_to_dsi_display_Runs/{s}/{n}'
              for s in ('syn_1','phy_1') for n in ('camera_to_dsi_display.prj','camera_to_dsi_display.tcl','settings.cfg')]
    return {p.relative_to(project).as_posix() for p in files if p.is_file()}


def metrics(timing, area, log):
    require('Tang Dynasty v6.2.168116' in timing and re.search(r'Confidence\s*:\s*Routed', timing),
            'Wrong TD version or unrouted timing report')
    out = {}
    for label, prefix in [('Setup', 'S'), ('Hold', 'H')]:
        console = re.findall(label+r'\s+: WNS\s+(-?\d+)ps\s+TNS\s+(-?\d+)ps\s+NUM_FEPS\s+(\d+)', log)
        report = re.search(prefix+r'WNS:\s*(-?[\d.]+)ns,\s*'+prefix+r'TNS:\s*(-?[\d.]+)ns', timing)
        require(console and report, f'Missing {label} summary')
        values = tuple(round(float(v)*1000) for v in report.groups())
        require(values == tuple(map(int, console[-1][:2])), f'{label} console/report mismatch')
        out[label+'WNSps'], out[label+'TNSps'] = values
        out[label+'FailingEndpoints'] = int(console[-1][2])
    coverage = re.search(r'STA coverage\s*:\s*([\d.]+)%', timing)
    require(coverage, 'Missing STA coverage')
    out['STACoveragePercent'] = float(coverage[1])
    for key in ('IO','lut6','reg','slice','eram','dsp','pll'):
        match = re.search(r'^#'+key+r'\s+(\d+)\b', area, re.M)
        require(match, f'Missing area metric: {key}')
        out[key] = int(match[1])
    out['TimingNonnegative'] = out['SetupWNSps'] >= 0 and out['HoldWNSps'] >= 0 and out['SetupTNSps'] == 0 and out['HoldTNSps'] == 0
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--build-directory', required=True, type=Path)
    args = parser.parse_args()
    directory = args.build_directory.resolve()
    result_path = directory / 'result.json'
    result = load(result_path)
    start = load(directory / 'started.json')
    require(result['Variant'] == 'quiz-video' and not result['ChangedInputs'], 'Wrong variant or changed inputs')
    require(sha(directory/'started.json') == result['StartedManifestSHA256'], 'Start identity changed')
    require(sha(result['SourceSnapshot']) == result['SourceSnapshotSHA256'], 'Source manifest changed')
    source, build = Path(result['SourceProject']), Path(result['BuildProject'])
    require(build.resolve().is_relative_to(directory), 'Build project outside run directory')
    input_hashes = load(result['SourceSnapshot'])
    require(input_names(source) == set(input_hashes) and input_names(build) == set(input_hashes),
            'Input file set changed during build')
    for relative, digest in input_hashes.items():
        require(sha(source/relative) == digest and sha(build/relative) == digest, f'Input changed: {relative}')
    for name, digest in result['BuilderHashes'].items():
        require(sha(directory/'tools'/name) == digest, f'Builder snapshot changed: {name}')
    require(sha(start['ProtectionSnapshot']) == start['ProtectionSnapshotSHA256'], 'Protection snapshot changed')
    protected = load(start['ProtectionSnapshot'])['Files']
    for entry in protected:
        require(sha(entry['Path']) == entry['SHA256'], f"Protected file changed: {entry['Path']}")
    require([s['Stage'] for s in result['Stages']] == ['syn_1','phy_1'], 'Missing stages')
    artifacts = {}

    def freeze(path, name, earliest=None, latest=None):
        path = Path(path)
        require(path.is_file(), f'Missing output: {path}')
        if earliest is not None:
            require(earliest-2 <= path.stat().st_mtime <= latest+2, f'Output not generated in this run: {path}')
        digest = sha(path)
        target = directory/name
        target.parent.mkdir(parents=True, exist_ok=True)
        if path.resolve() != target.resolve():
            if target.exists():
                require(sha(target) == digest, f'Refuse different existing archive: {target}')
            else:
                shutil.copyfile(path, target)
        require(sha(path) == digest and sha(target) == digest, 'Output changed during archive')
        artifacts[name] = dict(Path=str(target), SHA256=digest, Bytes=target.stat().st_size,
                               OriginalPath=str(path), OriginalModifiedEpoch=path.stat().st_mtime)

    for stage in result['Stages']:
        require(stage['ExitCode'] == 0 and stage['MarkerFresh'], 'Unsuccessful TD stage')
        a, b = stamp(stage['StartedAtUtc']), stamp(stage['FinishedAtUtc'])
        text = Path(stage['Stdout']).read_text(encoding='utf-8', errors='replace')
        require(f'SC520_QUIZ_VIDEO_STAGE_OK {stage["Stage"]}' in text, 'Missing stage success token')
        for key in ('Stdout','Stderr','Launcher','Marker'):
            freeze(stage[key], f'archive/{stage["Stage"]}/{Path(stage[key]).name}', a, b)
        native_logs = sorted(Path(stage['WorkingDirectory']).glob('td_*.log*'))
        require(native_logs, 'Missing native TD logs')
        for path in native_logs:
            freeze(path, f'archive/{stage["Stage"]}/{path.name}', a, b)
    phy = result['Stages'][1]
    log = Path(phy['Stdout']).read_text(encoding='utf-8', errors='replace')
    require('Generate bitstream completely' in log, 'No bit generation confirmation')
    bit = Path(result['Bit'])
    require(sha(bit) == result['SHA256'], 'Result bit identity mismatch')
    a, b = stamp(phy['StartedAtUtc']), stamp(phy['FinishedAtUtc'])
    for filename, target in [('camera_to_dsi_display.bit','built.bit'),
                             ('camera_to_dsi_display_compress.bit','built_compress.bit'),
                             ('final_timing.rpt','final_timing.rpt'),
                             ('camera_to_dsi_display_phy.area','final_area.rpt')]:
        freeze(bit.parent/filename, target, a, b)
    statistics = metrics((directory/'final_timing.rpt').read_text(encoding='utf-8', errors='replace'),
                         (directory/'final_area.rpt').read_text(encoding='utf-8', errors='replace'), log)
    for filename in ('result.json','started.json','stages.json','source-inputs.json'):
        freeze(directory/filename, filename)
    for name in result['BuilderHashes']:
        freeze(directory/'tools'/name, 'tools/'+name)
    warnings = {}
    for stage in result['Stages']:
        lines = Path(stage['Stdout']).read_text(encoding='utf-8', errors='replace').splitlines()
        warnings[stage['Stage']] = sorted(set(line.strip() for line in lines if 'WARNING' in line))
    warning_path = directory/'warning-summary.json'
    payload = json.dumps(warnings, indent=2)+'\n'
    if warning_path.exists():
        require(warning_path.read_text(encoding='utf-8') == payload, 'Warning summary changed')
    else:
        warning_path.write_text(payload, encoding='utf-8')
    freeze(warning_path, warning_path.name)
    manifest = dict(ArchivedAt=dt.datetime.now(dt.timezone(dt.timedelta(hours=8))).isoformat(),
                    Variant='quiz-video', BuildResult=str(result_path), BuildResultSHA256=sha(result_path),
                    Artifacts=artifacts, Metrics=statistics, ProtectedFilesVerified=len(protected),
                    HardwareValidated=False, PhysicalAudioImplemented=False,
                    Note='TD compile/route evidence only; not physical recognition, audio or button acceptance.')
    target = directory/'archive-manifest.json'
    if target.exists():
        prior = load(target)
        require(prior['BuildResultSHA256'] == manifest['BuildResultSHA256'] and prior['Metrics'] == statistics and
                {k:v['SHA256'] for k,v in prior['Artifacts'].items()} == {k:v['SHA256'] for k,v in artifacts.items()},
                'Archive already exists with different content')
    else:
        target.write_text(json.dumps(manifest, indent=2)+'\n', encoding='utf-8')
    print('ARCHIVED', target, json.dumps(statistics))


if __name__ == '__main__':
    main()
