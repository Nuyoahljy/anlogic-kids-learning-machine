"""Snapshot/run the independent shape guard qualification only."""
from pathlib import Path
import argparse,datetime,hashlib,json,shutil,subprocess,time,uuid
HERE=Path(__file__).resolve().parent;REPO=HERE.parents[2]
VSIM=Path('D:/modeltech64_10.7/win64/vsim.exe')
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def now():return datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat()
def save(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--negative',action='store_true');ap.add_argument('--watchdog-probe',action='store_true');a=ap.parse_args()
    mode='negative' if a.negative else ('watchdog' if a.watchdog_probe else 'normal')
    run=HERE/'runs'/f'{mode}-{datetime.datetime.now().strftime("%Y%m%d-%H%M%S")}-{uuid.uuid4().hex[:6]}';run.mkdir(parents=True,exist_ok=False)
    snap=run/'inputs';snap.mkdir();sources=[REPO/'fpga/rtl/sc520-card-recognition/pixel14/pixel14_block_shape_guard.v',HERE/'tb_block_shape_guard.sv',HERE/'cases.txt',HERE/'model-report.json',HERE/'block_shape_model.py',Path(__file__).resolve()]
    inputs=[]
    for p in sources:
        q=snap/p.name;shutil.copyfile(p,q);inputs.append({'path':str(p),'snapshot':str(q),'sha256_before':sha(p),'snapshot_sha256':sha(q)})
    shutil.copyfile(snap/'cases.txt',run/'cases.txt');shutil.copyfile(VSIM.parent.parent/'modelsim.ini',run/'modelsim.ini')
    text='''onerror {quit -force -code 2}
vlib work
vmap work work
vlog inputs/pixel14_block_shape_guard.v
vlog -sv inputs/tb_block_shape_guard.sv
vsim -voptargs=+acc -wlf wave.wlf work.tb_block_shape_guard +INJECT_FAULT=%d
onfinish stop
%s
set errors [examine -radix decimal /tb_block_shape_guard/errors]
set checks [examine -radix decimal /tb_block_shape_guard/checks]
set scenarios [examine -radix decimal /tb_block_shape_guard/scenarios]
set done [examine -radix unsigned /tb_block_shape_guard/test_done]
set injected [examine -radix decimal /tb_block_shape_guard/injected]
set f [open summary.json w]
puts $f [format {{"errors":%%d,"checks":%%d,"scenarios":%%d,"done":%%d,"injected":%%d}} $errors $checks $scenarios $done $injected]
close $f
if {!$done} {quit -force -code 2}
if {$errors != 0} {quit -force -code 1}
quit -force -code 0
'''%(int(a.negative),'run 500 ns' if a.watchdog_probe else 'run -all')
    (run/'run.do').write_text(text,encoding='utf-8');cmd=[str(VSIM),'-modelsimini',str(run/'modelsim.ini'),'-c','-l','transcript.log','-do','do run.do']
    report={'started_at':now(),'mode':mode,'command':cmd,'inputs':inputs,'scope':'Complete normalized glyph stream and protocol, no block/color replacement and no camera validation'};save(run/'run-start.json',report)
    with (run/'stdout.log').open('wb') as out,(run/'stderr.log').open('wb') as err:result=subprocess.run(cmd,cwd=run,stdout=out,stderr=err,timeout=180)
    summary=json.loads((run/'summary.json').read_text()) if (run/'summary.json').exists() else None
    for x in inputs:x['sha256_after']=sha(x['path'])
    unchanged=all(x['sha256_before']==x['snapshot_sha256']==x['sha256_after'] for x in inputs)
    expected=(2,0,0,0) if a.watchdog_probe else (int(a.negative),1,int(a.negative),int(a.negative))
    actual=(result.returncode,summary.get('done'),summary.get('errors'),summary.get('injected')) if summary else None
    report.update(finished_at=now(),summary=summary,native_exit=result.returncode,inputs_unchanged=unchanged,qualified=unchanged and expected==actual)
    report['outputs']=[{'path':str(p),'sha256':sha(p)} for p in sorted(run.iterdir()) if p.is_file() and p.name not in ('wave.wlf','modelsim.ini')]
    save(run/'run-manifest.json',report);print(json.dumps({'run':str(run),'qualified':report['qualified'],'native_exit':result.returncode,'summary':summary}))
    return 0 if report['qualified'] else 1
if __name__=='__main__':raise SystemExit(main())
