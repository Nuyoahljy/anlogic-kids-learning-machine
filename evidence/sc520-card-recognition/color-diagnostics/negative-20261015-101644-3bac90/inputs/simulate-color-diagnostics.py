"""Isolated color diagnostics qualification; never edits active ISP or TD inputs."""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import argparse
import hashlib
import json
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[3]


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def main():
    ap = argparse.ArgumentParser()
    modes = ap.add_mutually_exclusive_group()
    modes.add_argument('--negative', action='store_true')
    modes.add_argument('--probe', action='store_true')
    args = ap.parse_args()
    mode = 'negative' if args.negative else 'watchdog' if args.probe else 'normal'
    run = ROOT / 'evidence/sc520-card-recognition/color-diagnostics' / f'{mode}-{datetime.now():%Y%m%d-%H%M%S}-{uuid.uuid4().hex[:6]}'
    snap = run / 'inputs'
    snap.mkdir(parents=True)
    sources = [ROOT / 'fpga/rtl/sc520-card-recognition/color_diag/pixel14_color_diagnostics.v',
               ROOT / 'fpga/sim/sc520-card-recognition/tb_pixel14_color_diagnostics.sv', Path(__file__).resolve()]
    inputs = []
    for path in sources:
        target = snap / path.name
        target.write_bytes(path.read_bytes())
        inputs.append({'Path': str(path), 'Snapshot': str(target), 'SHA256': sha(path)})
    sim = Path('D:/modeltech64_10.7/win64/vsim.exe')
    (run / 'modelsim.ini').write_bytes((sim.parent.parent / 'modelsim.ini').read_bytes())
    tcl = 'onerror {quit -force -code 2}\nonbreak {resume}\nvlib work\nvmap work work\n'
    tcl += 'vlog -sv ' + ' '.join('{' + str(snap / p.name).replace('\\', '/') + '}' for p in sources[:-1]) + '\n'
    tcl += f'vsim -voptargs=+acc work.tb_pixel14_color_diagnostics +INJECT_FAULT={int(args.negative)}\nonfinish stop\n'
    tcl += 'run 500 ns\n' if args.probe else 'run -all\n'
    for name in ['errors', 'checks', 'scenarios', 'injected', 'test_done']:
        tcl += f'set {name} [examine -radix unsigned /tb_pixel14_color_diagnostics/{name}]\n'
    tcl += '''set fd [open summary.json w]
puts $fd [format {{"errors":%d,"checks":%d,"scenarios":%d,"injected":%d,"done":%d}} $errors $checks $scenarios $injected $test_done]
close $fd
if {!$test_done} {quit -force -code 2}
if {$errors} {quit -force -code 1}
quit -force -code 0
'''
    (run / 'run.do').write_text(tcl, encoding='utf-8')
    command = [str(sim), '-c', '-modelsimini', str(run / 'modelsim.ini'), '-l', 'transcript.log', '-do', 'do run.do']
    exception = None
    with (run / 'stdout.log').open('wb') as out, (run / 'stderr.log').open('wb') as err:
        try:
            proc = subprocess.run(command, cwd=run, stdout=out, stderr=err, timeout=240)
            native_exit = proc.returncode
        except subprocess.TimeoutExpired as exc:
            exception = str(exc)
            native_exit = None
    summary = json.loads((run / 'summary.json').read_text()) if (run / 'summary.json').exists() else None
    unchanged = all(sha(x['Path']) == sha(x['Snapshot']) == x['SHA256'] for x in inputs)
    expected_exit = 2 if args.probe else int(args.negative)
    qualified = (unchanged and summary is not None and native_exit == expected_exit
                 and summary['done'] == int(not args.probe) and summary['errors'] == int(args.negative)
                 and summary['injected'] == int(args.negative)
                 and (args.probe or (summary['scenarios'] == 42 and summary['checks'] >= 1400)))
    result = {'CreatedAt': datetime.now(timezone(timedelta(hours=8))).isoformat(), 'Mode': mode,
              'Command': command, 'Inputs': inputs, 'Summary': summary, 'NativeExitCode': native_exit,
              'Qualified': qualified, 'InputsUnchanged': unchanged, 'Exception': exception,
              'Scope': 'Isolated aligned RGB96 diagnostics; four sample lane offsets, both lane orders, 1280x720 frames, synthetic triples; no real CSI/ISP alignment, physical timing or board evidence.',
              'BoardFix': False, 'ProductionIntegration': False}
    result['Outputs'] = [{'Path': str(p), 'SHA256': sha(p)} for p in run.iterdir() if p.is_file() and p.name != 'modelsim.ini']
    (run / 'result.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'Run': str(run), 'Qualified': qualified, 'Summary': summary, 'NativeExitCode': native_exit}))
    return 0 if qualified else 1


if __name__ == '__main__':
    raise SystemExit(main())
