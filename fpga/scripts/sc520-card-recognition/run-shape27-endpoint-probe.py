"""Execute the exact main-approved five-query read-only probe once, preserving evidence."""
from pathlib import Path
import ctypes
import datetime as dt
import hashlib
import importlib.util
import json
import re
import shutil
import subprocess

R = Path(__file__).resolve().parents[3]
RUN = R/'evidence/sc520-shape27/builds/6a50b270-phy-r2'
OUT = R/'evidence/sc520-shape27/endpoint-probe-r2-01'
SOURCE = Path('E:/juan/FPGA/learning/sc520-shape27/physical-review/endpoint-probe-20261020-r2-01')
PROBE_SHA = '818F042131E59C14BAEE2A00C3CAECA326CF3E3D635A94F19752FABC6204F803'
DB_SHA = '7755E6390D684DA939D01EB3851716425F92385C556E24570B0CE779C3F4B05B'


def now():
    return dt.datetime.now(dt.timezone(dt.timedelta(hours=8))).isoformat()


def main():
    spec = importlib.util.spec_from_file_location('resume_gate', Path(__file__).with_name('resume-shape27-phy-v2.py'))
    gate = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gate)
    gate.idle()
    gate.verify(RUN)
    assert gate.sha(SOURCE/'probe.tcl') == PROBE_SHA
    requests = gate.read(SOURCE/'requests.json')
    assert requests['RouteDB']['SHA256'] == DB_SHA
    assert len(requests['Requests']) == 5
    protected = {str(p): gate.sha(p) for p in sorted(RUN.rglob('*')) if p.is_file()}
    for path in [SOURCE/'probe.tcl', SOURCE/'requests.json', Path(__file__), gate.TOOL]:
        protected[str(path)] = gate.sha(path)
    def bind(value):
        if isinstance(value, dict):
            if 'Path' in value and 'SHA256' in value:
                gate.check(value)
                protected[value['Path']] = value['SHA256']
            for child in value.values():
                bind(child)
        elif isinstance(value, list):
            for child in value:
                bind(child)
    bind(requests)
    assert not OUT.exists(), 'Never replace an existing probe attempt'
    occupied = ctypes.windll.kernel32.GetLogicalDrives()
    aliases = subprocess.check_output(['subst.exe'], text=True).splitlines()
    drive = next((d+':' for d in 'UTSRQ' if not occupied & (1 << (ord(d)-ord('A')))
                  and not any(line.startswith(d+':') for line in aliases)), None)
    assert drive, 'No unoccupied task drive'
    OUT.mkdir(parents=True, exist_ok=False)
    for name in ['probe.tcl', 'requests.json']:
        shutil.copyfile(SOURCE/name, OUT/name)
        protected[str(OUT/name)] = gate.sha(SOURCE/name)
    started = {'StartedAt': now(), 'Owner': 'Codex /root/shape27_impl_resume T027',
               'Approval': 'Current main /root explicitly approved this exact five-query Tcl by SHA; no extra TD commands.',
               'Probe': gate.artifact(OUT/'probe.tcl'), 'Requests': gate.artifact(OUT/'requests.json'),
               'Generator': gate.artifact(__file__), 'Tool': gate.artifact(gate.TOOL),
               'ProtectedFiles': protected, 'ObservedMappings': aliases,
               'RouteDB': requests['RouteDB'], 'PhysicalQualified': False,
               'BitGenerationAllowed': False, 'HardwareValidated': False}
    gate.save_new(OUT/'started.json', started)
    result = {'Complete': False, 'PhysicalQualified': False, 'BitGenerationAllowed': False,
              'HardwareValidated': False, 'StartedAt': started['StartedAt'],
              'TemporaryMapping': {'Drive': drive, 'Target': str(OUT), 'Released': False}}
    subprocess.run(['subst.exe', drive, str(OUT)], check=True)
    try:
        command = [str(gate.TOOL), drive+'/probe.tcl']
        with (OUT/'stdout.log').open('xb') as stdout, (OUT/'stderr.log').open('xb') as stderr:
            p = subprocess.Popen(command, cwd=drive+'/', stdout=stdout, stderr=stderr,
                                 creationflags=subprocess.CREATE_NO_WINDOW)
            gate.save_new(OUT/'process.json', {'PID': p.pid, 'Command': command, 'Cwd': drive+'/', 'At': now()})
            print(f'T027_READONLY_PROBE PID={p.pid} output={OUT}', flush=True)
            result['PID'] = p.pid
            result['NativeExitCode'] = p.wait()
        result['NativeFinishedAt'] = now()
        raw = (OUT/'stdout.log').read_text(errors='replace')
        result['Errors'] = [line for line in raw.splitlines() if re.search(r'\bERROR\b', line)]
        result['StderrEmpty'] = (OUT/'stderr.log').stat().st_size == 0
        result['OriginalTimingMarker'] = 'T027_PROBE_ORIGINAL_TIMING_OK' in raw
        result['ProbeCompleteMarker'] = 'T027_ENDPOINT_PROBE_DONE' in raw
        result['ChangedProtectedFiles'] = [path for path, expected in protected.items() if gate.sha(path) != expected]
        gate.verify(RUN)
        result['FrozenInputsUnchanged'] = True
        result['BitFilesFound'] = [str(p) for p in OUT.rglob('*.bit')]
        result['Complete'] = (result['NativeExitCode'] == 0 and not result['Errors'] and result['StderrEmpty']
            and result['OriginalTimingMarker'] and result['ProbeCompleteMarker']
            and not result['ChangedProtectedFiles'] and not result['BitFilesFound'])
        result['Outputs'] = [gate.artifact(p) for p in sorted(OUT.iterdir()) if p.is_file()]
    except BaseException as exc:
        result['Failure'] = repr(exc)
        raise
    finally:
        lines = subprocess.check_output(['subst.exe'], text=True).splitlines()
        if drive+'\\: => '+str(OUT) in lines:
            subprocess.run(['subst.exe', drive, '/D'], check=True)
            result['TemporaryMapping']['Released'] = True
        else:
            result['TemporaryMapping']['ChangedExternally'] = True
        result['FinishedAt'] = now()
        gate.save_new(OUT/'result.json', result)
    print(json.dumps({k: result[k] for k in ['Complete', 'NativeExitCode', 'OriginalTimingMarker', 'ProbeCompleteMarker']}))
    return 0 if result['Complete'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
