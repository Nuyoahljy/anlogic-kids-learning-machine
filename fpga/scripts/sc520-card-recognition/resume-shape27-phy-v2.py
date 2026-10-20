"""Prepare an isolated T027 physical retry; execute only with a bound main approval."""
from pathlib import Path
import argparse
import ctypes
import datetime as dt
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys

REPO = Path(__file__).resolve().parents[3]
BUILDS = REPO / 'evidence/sc520-shape27/builds'
OLD = BUILDS / '6a50b270'
TOOL = Path('D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe')
SOFTWARE_APPROVAL = Path('E:/juan/FPGA/learning/sc520-shape27/main-review/software-approved.json')
COMMIT = 'b7247b8d8963ff60bd8a2f710a174e5434531b33'
APPROVAL_SHA = 'A771885BF61297914B2ECD274262D3DC71BD4CD225424165252FDCC5357D2096'
INPUT_SHA = 'ECC2A1BE92EF800218165386709B30CD0BF81990E9B2608E5296D861322D95F8'
TOOL_SHA = 'E2E04ADA5E256DCCD017240C0F4DCFACE7F96DCA67CDE0E56E606AC0E02F827A'
SYN = 'td_project/camera_to_dsi_display_Runs/syn_1'
PHY = 'td_project/camera_to_dsi_display_Runs/phy_1'


def now():
    return dt.datetime.now(dt.timezone(dt.timedelta(hours=8))).isoformat()


def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest().upper()


def artifact(path):
    p = Path(path).resolve()
    return {'Path': str(p), 'SHA256': sha(p), 'Bytes': p.stat().st_size}


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def save_new(path, value):
    with Path(path).open('x', encoding='utf-8', newline='\n') as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write('\n')


def check(row):
    if sha(row['Path']) != row['SHA256'].upper():
        raise RuntimeError('SHA changed: ' + row['Path'])


def process_state():
    text = subprocess.check_output([
        'powershell.exe', '-NoProfile', '-Command',
        "@(Get-CimInstance Win32_Process | Where-Object {$_.Name -match '^td.*\\.exe$'} | "
        "Select-Object Name,ProcessId,ParentProcessId,CreationDate,CommandLine) | ConvertTo-Json -Depth 3"
    ], text=True, encoding='utf-8', errors='replace')
    rows = json.loads(text) if text.strip() else []
    return rows if isinstance(rows, list) else [rows]


def idle():
    rows = process_state()
    active = [r for r in rows if r['Name'].lower() != 'td.exe']
    if active:
        raise RuntimeError('An existing TD console/build process must be resolved: ' + repr(active))
    return rows


def freeze(reset_path):
    head = subprocess.check_output(['git', '-C', str(REPO), 'rev-parse', 'HEAD'], text=True).strip()
    if head != COMMIT:
        raise RuntimeError('Frozen source commit mismatch: ' + head)
    for path, expected in [(SOFTWARE_APPROVAL, APPROVAL_SHA), (OLD/'inputs.json', INPUT_SHA), (TOOL, TOOL_SHA)]:
        if sha(path) != expected:
            raise RuntimeError('Fixed prerequisite SHA changed: ' + str(path))
    approved = read(SOFTWARE_APPROVAL)
    assert approved['Stage'] == 'software_accepted' and approved['BuildAllowed'] is True
    assert approved['SourceCommit'] == COMMIT and approved['BuildRun'] == '6a50b270'
    for name in ('BitGenerationAllowed', 'DownloadAllowed', 'FlashAllowed', 'HardwareValidated'):
        assert approved[name] is False
    for name in ('SoftwareReview', 'IndependentReview', 'SoftwareManifest'):
        check(approved[name])
    software = read(approved['SoftwareManifest']['Path'])
    assert len(software['SourceFreeze']) == 16
    for row in software['SourceFreeze']:
        check(row)
    inputs = read(OLD/'inputs.json')
    assert len(inputs['Files']) == 396 and len(inputs['ManifestSources']) == 121
    for row in inputs['Files']:
        check(row)
        if row.get('Snapshot'):
            check({'Path': row['Snapshot'], 'SHA256': row['SnapshotSHA256']})
    protected = read(REPO/'evidence/sc520-shape27/protected-d0261.json')
    assert len(protected['Files']) == 465
    for row in protected['Files']:
        check(row)
    reset = read(reset_path)
    assert reset['Qualified'] is True and reset['Stage'] == 'synthesis only'
    assert reset['SecondStageCount'] == 10
    assert Path(reset['Netlist']['Path']).resolve() == OLD/SYN/'pixel14-syn_1-netlist.v'
    for name in ('Netlist', 'Program', 'Parser'):
        check(reset[name])
    stages = read(OLD/'stages.json')
    assert stages['Stage'] == 'syn_1' and stages['ExitCode'] == 0 and stages['MarkerFresh'] is True
    assert 'PIXEL14_STAGE_OK syn_1' in (OLD/'syn_1.stdout.log').read_text(errors='replace')
    assert not (OLD/PHY/'.opt_route.end.f').exists()
    assert not (OLD/PHY/'camera_to_dsi_display_pr.db').exists()
    assert not list(OLD.rglob('*.bit'))
    return {'SourceCommit': head, 'SourceFreezeCount': 16, 'InputCount': 396,
            'SnapshotCount': sum(bool(r.get('Snapshot')) for r in inputs['Files']),
            'ProtectedD0261Count': 465, 'ResetQualified': True,
            'ResetMaximumFanout': reset['MaximumBranchFanout']}


def prepare(run, reset_path):
    processes = idle()
    verified = freeze(reset_path)
    if run.exists():
        raise RuntimeError('Refuse to replace an existing run: ' + str(run))
    # Hash every old file before creating any new physical output.
    history = [artifact(p) for p in sorted(OLD.rglob('*')) if p.is_file()]
    copied = []
    paths = ['inputs.json', 'profile.json', 'td_project/camera_to_dsi_display.al',
             'templates.mem', 'anlogic_logo_index.mem', 'anlogic_logo_palette.mem',
             SYN+'/camera_to_dsi_display_gate.db', SYN+'/pixel14-syn_1-netlist.v',
             PHY+'/camera_to_dsi_display.prj', PHY+'/settings.cfg', PHY+'/camera_to_dsi_display.tcl']
    paths += [p.relative_to(OLD).as_posix() for dirname in ('rtl', 'overlay', 'tools')
              for p in sorted((OLD/dirname).rglob('*')) if p.is_file()]
    run.mkdir(parents=True, exist_ok=False)
    for rel in paths:
        src, dst = OLD/rel, run/rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dst)
        assert sha(src) == sha(dst)
        copied.append({'Original': artifact(src), 'Copy': artifact(dst)})
    reset_copy = run/'reset-synthesis.json'
    shutil.copyfile(reset_path, reset_copy)
    copied.append({'Original': artifact(reset_path), 'Copy': artifact(reset_copy)})
    settings = (run/PHY/'settings.cfg').read_text(encoding='utf-8-sig')
    assert re.search(r'^set start_step opt_place$', settings, re.M)
    assert re.search(r'^set end_step opt_route$', settings, re.M)
    assert re.search(r'^set parent ../syn_1$', settings, re.M)
    launch = '''if {[catch {
 source settings.cfg
 if {$device_name ne "ph1_35p.db" || $package_name ne "PH1P35MDG324" || $speed != 3} {error "Wrong device"}
 if {$start_step ne "opt_place" || $end_step ne "opt_route" || $parent ne "../syn_1"} {error "D0270 frozen-synthesis physical retry only"}
 proc bitgen {args} {error "T027 bitgen is prohibited"}
 source camera_to_dsi_display.tcl
 write_verilog pixel14-phy_1-netlist.v
 report_clock_summary -file pixel14-clocks.rpt
 report_timing_exception -file pixel14-exceptions.rpt
 source ../../../overlay/report-pixel14-cdc.tcl
} message]} {puts stderr $message; exit 1}
puts "PIXEL14_STAGE_OK phy_1"
exit 0
'''
    (run/'phy_1.launch.tcl').write_text(launch, encoding='ascii', newline='\n')
    plan = {'PreparedAt': now(), 'Owner': 'Codex /root/shape27_impl_resume T027 20261020',
            'Stage': 'prepared_not_executed', 'RunDirectory': str(run), 'OriginalRun': str(OLD),
            'Purpose': 'D0270 route-only resume from frozen synthesis', 'Verified': verified,
            'SoftwareApproval': artifact(SOFTWARE_APPROVAL),
            'SourceSynthesisDatabase': artifact(OLD/SYN/'camera_to_dsi_display_gate.db'),
            'ResetAudit': artifact(reset_path),
            'Generator': artifact(__file__), 'Tool': artifact(TOOL),
            'Launcher': artifact(run/'phy_1.launch.tcl'), 'CopiedFiles': copied,
            'OriginalHistory': history, 'ObservedTDProcesses': processes,
            'ObservedMappings': subprocess.check_output(['subst.exe'], text=True).splitlines(),
            'HistoryConclusion': 'Original synthesis complete; legacy reset audit rejected. First physical retry has place DB but no route DB, end marker or result; console is absent. Cause of interruption unknown.',
            'PhysicalQualified': False, 'BitGenerationAllowed': False,
            'DownloadAllowed': False, 'FlashAllowed': False, 'HardwareValidated': False}
    save_new(run/'preparation.json', plan)
    print(json.dumps({'Preparation': artifact(run/'preparation.json'), 'CopiedFiles': len(copied),
                      'PreservedOldFiles': len(history), 'TDStarted': False}, ensure_ascii=False))


def verify(run):
    plan = read(run/'preparation.json')
    assert plan['Stage'] == 'prepared_not_executed' and Path(plan['RunDirectory']) == run
    freeze(plan['ResetAudit']['Path'])
    for name in ('Generator', 'Tool', 'Launcher', 'SoftwareApproval', 'SourceSynthesisDatabase', 'ResetAudit'):
        check(plan[name])
    for pair in plan['CopiedFiles']:
        check(pair['Original'])
        check(pair['Copy'])
    for row in plan['OriginalHistory']:
        check(row)
    actual = {str(p.resolve()) for p in OLD.rglob('*') if p.is_file()}
    assert actual == {r['Path'] for r in plan['OriginalHistory']}, 'Original run file inventory changed'
    return plan


def execute(run, approval_path):
    idle()
    plan = verify(run)
    approval = read(approval_path)
    assert approval['Stage'] == 'phy_resume_approved' and approval['ApprovedBy']
    assert approval['Purpose'] == plan['Purpose'] and Path(approval['RunDirectory']).resolve() == run
    assert Path(approval['Preparation']['Path']).resolve() == run/'preparation.json'
    check(approval['Preparation'])
    for name in ('BitGenerationAllowed', 'DownloadAllowed', 'FlashAllowed', 'HardwareValidated'):
        assert approval[name] is False
    # An interrupted attempt is preserved, never silently run again in its folder.
    assert not (run/'started.json').exists()
    assert not list((run/PHY).glob('.*.f'))
    assert not list((run/PHY).glob('*.db'))
    occupied = ctypes.windll.kernel32.GetLogicalDrives()
    aliases = subprocess.check_output(['subst.exe'], text=True).splitlines()
    drive = next((d+':' for d in 'UTSRQ' if not occupied & (1 << (ord(d)-ord('A')))
                  and not any(line.startswith(d+':') for line in aliases)), None)
    assert drive, 'No free task drive'
    subprocess.run(['subst.exe', drive, str(run)], check=True)
    start = dt.datetime.now(dt.timezone.utc)
    result = {'Stage': 'phy_1', 'RunDirectory': str(run), 'StartedAtUtc': start.isoformat(),
              'Approval': artifact(approval_path), 'Preparation': artifact(run/'preparation.json'),
              'SourceSynthesisDatabase': plan['SourceSynthesisDatabase'], 'Complete': False,
              'BitGenerationAllowed': False, 'HardwareValidated': False, 'TimingQualified': False,
              'TemporaryMapping': {'Drive': drive, 'Target': str(run), 'Released': False}}
    try:
        save_new(run/'started.json', result)
        command = [str(TOOL), drive+'/phy_1.launch.tcl']
        with (run/'stdout.log').open('xb') as stdout, (run/'stderr.log').open('xb') as stderr:
            p = subprocess.Popen(command, cwd=drive+'/'+PHY, stdout=stdout, stderr=stderr,
                                 creationflags=subprocess.CREATE_NO_WINDOW)
            save_new(run/'process.json', {'PID': p.pid, 'Command': command, 'Cwd': drive+'/'+PHY, 'StartedAt': now()})
            print(f'PIXEL14_TD phy_1_retry PID={p.pid} run={run}', flush=True)
            result['PID'] = p.pid
            result['NativeExitCode'] = p.wait()
        raw = (run/'stdout.log').read_text(errors='replace')
        result['LogErrors'] = [line for line in raw.splitlines() if re.search(r'\bERROR\b', line)]
        result['StderrEmpty'] = (run/'stderr.log').stat().st_size == 0
        marker = run/PHY/'.opt_route.end.f'
        result['MarkerFresh'] = marker.exists() and marker.stat().st_mtime >= start.timestamp()
        required = [PHY+'/camera_to_dsi_display_pr.db', PHY+'/camera_to_dsi_display_pr.timing',
                    PHY+'/pixel14-phy_1-netlist.v', 'analysis/shape27-objects.txt',
                    'analysis/shape27-inbound.rpt', 'analysis/shape27-outbound.rpt']
        result['RequiredOutputsPresent'] = all((run/r).is_file() and (run/r).stat().st_size > 0 for r in required)
        result['DatabaseImportSucceeded'] = 'Import design success TD_VERSION=6.2.168116' in raw
        result['CompletionMarkers'] = all(x in raw for x in ['PIXEL14_STAGE_OK phy_1', 'PIXEL14_CDC_PHYSICAL_REPORTS_OK'])
        result['BitFilesFound'] = [str(p) for p in run.rglob('*.bit')]
        verify(run)
        result['OriginalAndFrozenInputsUnchanged'] = True
        result['Complete'] = (result['NativeExitCode'] == 0 and not result['LogErrors']
            and result['StderrEmpty'] and result['MarkerFresh'] and result['RequiredOutputsPresent']
            and result['DatabaseImportSucceeded'] and result['CompletionMarkers'] and not result['BitFilesFound'])
        result['KeyOutputs'] = [artifact(run/r) for r in required if (run/r).is_file()]
    except BaseException as exc:
        result['Failure'] = repr(exc)
        raise
    finally:
        lines = subprocess.check_output(['subst.exe'], text=True).splitlines()
        expected = drive+'\\: => '+str(run)
        if expected in lines:
            subprocess.run(['subst.exe', drive, '/D'], check=True)
            result['TemporaryMapping']['Released'] = True
        else:
            result['TemporaryMapping']['ChangedByOtherProcess'] = True
        result['FinishedAt'] = now()
        save_new(run/'result.json', result)
    print(json.dumps({'Complete': result['Complete'], 'NativeExitCode': result['NativeExitCode'],
                      'PhysicalQualified': False, 'BitGenerationAllowed': False}))
    return 0 if result['Complete'] else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument('--prepare', action='store_true')
    mode.add_argument('--verify-prepared', action='store_true')
    mode.add_argument('--execute', action='store_true')
    ap.add_argument('--run-id', default='6a50b270-phy-r2')
    ap.add_argument('--approval', type=Path)
    ap.add_argument('--reset-audit', type=Path)
    args = ap.parse_args()
    assert re.fullmatch(r'6a50b270-phy-r[2-9][0-9]*', args.run_id), 'Explicit T027 retry identity required'
    run = (BUILDS/args.run_id).resolve()
    if args.prepare:
        assert args.reset_audit, '--reset-audit from this recovery review required'
        prepare(run, args.reset_audit.resolve())
    elif args.verify_prepared:
        verify(run)
        print('PREPARED_HASHES_OK; TD not started')
    else:
        assert args.approval, '--approval required before TD can start'
        return execute(run, args.approval.resolve())
    return 0


if __name__ == '__main__':
    sys.exit(main())
