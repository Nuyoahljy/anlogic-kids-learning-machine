"""Isolated reproduction of current C002 failure; does not edit board RTL."""
from pathlib import Path
from datetime import datetime,timezone,timedelta
import argparse,hashlib,json,subprocess,uuid
ROOT=Path(__file__).resolve().parents[3]
VENDOR=ROOT.parent/'sc520-fixed-roi/fpga/custom_project/sc520-board-keys/user_source/hdl_source'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--negative',action='store_true');ap.add_argument('--probe',action='store_true');a=ap.parse_args()
    mode='negative' if a.negative else 'watchdog' if a.probe else 'normal'
    run=ROOT/'evidence/sc520-card-recognition/color-contract'/f"{mode}-{datetime.now().strftime('%Y%m%d-%H%M%S')}-{uuid.uuid4().hex[:6]}";snap=run/'inputs';snap.mkdir(parents=True)
    sources=[ROOT/'fpga/custom_project/sc520-pixel14/overlay/pixel14_color_pipeline.v',ROOT/'fpga/rtl/sc520-card-recognition/pixel14/block_frame_recognizer.v',VENDOR/'signal_delay.v',ROOT/'evidence/sc520-card-recognition/imaging-audit/ip_behavioral_models.sv',ROOT/'fpga/sim/sc520-card-recognition/tb_pixel14_color_contract.sv',Path(__file__).resolve()]
    inputs=[]
    for p in sources:
        q=snap/p.name;q.write_bytes(p.read_bytes());inputs.append({'Path':str(p),'Snapshot':str(q),'SHA256':sha(p)})
    sim=Path('D:/modeltech64_10.7/win64/vsim.exe');(run/'modelsim.ini').write_bytes((sim.parent.parent/'modelsim.ini').read_bytes())
    tcl='onerror {quit -force -code 2}\nonbreak {resume}\nvlib work\nvmap work work\nvlog -sv '+' '.join('{'+str(snap/p.name).replace('\\','/')+'}' for p in sources[:-1])+'\n'
    tcl+=f'vsim -voptargs=+acc work.tb_pixel14_color_contract +INJECT_FAULT={int(a.negative)}\nonfinish stop\n'+('run 500 ns\n' if a.probe else 'run -all\n')
    tcl+='set e [examine -radix decimal /tb_pixel14_color_contract/errors]\nset n [examine -radix decimal /tb_pixel14_color_contract/checks]\nset d [examine -radix unsigned /tb_pixel14_color_contract/test_done]\nset i [examine -radix decimal /tb_pixel14_color_contract/injected]\nset fd [open summary.json w]\nputs $fd [format {{"errors":%d,"checks":%d,"done":%d,"injected":%d}} $e $n $d $i]\nclose $fd\nif {!$d} {quit -force -code 2}\nif {$e} {quit -force -code 1}\nquit -force -code 0\n'
    (run/'run.do').write_text(tcl,encoding='utf-8');cmd=[str(sim),'-c','-modelsimini',str(run/'modelsim.ini'),'-l','transcript.log','-do','do run.do']
    with (run/'stdout.log').open('wb') as out,(run/'stderr.log').open('wb') as err:r=subprocess.run(cmd,cwd=run,stdout=out,stderr=err,timeout=180)
    summary=json.loads((run/'summary.json').read_text()) if (run/'summary.json').exists() else None
    unchanged=all(sha(x['Path'])==sha(x['Snapshot'])==x['SHA256'] for x in inputs)
    qualified=unchanged and summary is not None and summary['errors']==int(a.negative) and summary['done']==int(not a.probe) and r.returncode==(2 if a.probe else int(a.negative))
    result={'CreatedAt':datetime.now(timezone(timedelta(hours=8))).isoformat(),'Mode':mode,'Command':cmd,'Inputs':inputs,'Summary':summary,'NativeExitCode':r.returncode,'QualifiedReproduction':qualified,'BoardFix':False,'Scope':'Constructed RGB counterexamples, actual four new-color-module modes and actual color-gate counters. No photographic RGB inference or sensor measurement.'}
    result['Outputs']=[{'Path':str(p),'SHA256':sha(p)} for p in run.iterdir() if p.is_file() and p.name!='modelsim.ini']
    (run/'result.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8');print(json.dumps({'run':str(run),'reproduced':qualified,'summary':summary}));return 0 if qualified else 1
if __name__=='__main__':raise SystemExit(main())
