"""Independent imaging audit; no board access and no changes to vendor sources."""
from pathlib import Path
import argparse, datetime, hashlib, json, shutil, subprocess, time, uuid

HERE=Path(__file__).resolve().parent
REPO=HERE.parents[2]
OLD=REPO.parent/'sc520-fixed-roi/fpga/custom_project/sc520-board-keys/user_source/hdl_source'
VSIM=Path('D:/modeltech64_10.7/win64/vsim.exe')
def digest(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def now(): return datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat()
def save(p,x): p.write_text(json.dumps(x,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--negative',action='store_true');ap.add_argument('--watchdog-probe',action='store_true');a=ap.parse_args()
    mode='negative' if a.negative else ('watchdog' if a.watchdog_probe else 'normal')
    run=HERE/'runs'/f'{mode}-{datetime.datetime.now().strftime("%Y%m%d-%H%M%S")}-{uuid.uuid4().hex[:6]}'
    run.mkdir(parents=True,exist_ok=False);snap=run/'inputs';snap.mkdir()
    sources=[OLD/'awb.v',OLD/'signal_delay.v',REPO/'fpga/custom_project/sc520-pixel14/overlay/pixel14_color_pipeline.v',HERE/'ip_behavioral_models.sv',HERE/'tb_color_pipeline.sv',Path(__file__).resolve()]
    inputs=[]
    for p in sources:
        q=snap/p.name;shutil.copyfile(p,q);inputs.append({'path':str(p),'snapshot':str(q),'sha256_before':digest(p),'snapshot_sha256':digest(q)})
    ini=VSIM.parent.parent/'modelsim.ini';shutil.copyfile(ini,run/'modelsim.ini')
    do='''onerror {quit -force -code 2}
vlib work
vmap work work
vlog -sv inputs/awb.v inputs/signal_delay.v inputs/pixel14_color_pipeline.v inputs/ip_behavioral_models.sv inputs/tb_color_pipeline.sv
vsim -voptargs=+acc -wlf wave.wlf work.tb_color_pipeline +INJECT_FAULT=%d
onfinish stop
%s
set errors [examine -radix decimal /tb_color_pipeline/errors]
set checks [examine -radix decimal /tb_color_pipeline/checks]
set scenarios [examine -radix decimal /tb_color_pipeline/scenarios]
set done [examine -radix unsigned /tb_color_pipeline/test_done]
set injected [examine -radix decimal /tb_color_pipeline/injected]
set f [open summary.json w]
puts $f [format {{"errors":%%d,"checks":%%d,"scenarios":%%d,"done":%%d,"injected":%%d}} $errors $checks $scenarios $done $injected]
close $f
if {!$done} {quit -force -code 2}
if {$errors != 0} {quit -force -code 1}
quit -force -code 0
''' % (int(a.negative),'run 500 ns' if a.watchdog_probe else 'run -all')
    (run/'run.do').write_text(do,encoding='utf-8')
    cmd=[str(VSIM),'-modelsimini',str(run/'modelsim.ini'),'-c','-l','transcript.log','-do','do run.do']
    report={'started_at':now(),'mode':mode,'command':cmd,'workdir':str(run),'inputs':inputs,
      'scope':'Actual unchanged awb.v and signal_delay.v with explicitly behavioral divider and dual-port memory boundaries; no vendor IP timing qualification, camera, DDR, PHY or hardware evidence.'}
    save(run/'run-start.json',report);start=time.monotonic()
    with (run/'stdout.log').open('wb') as out,(run/'stderr.log').open('wb') as err:
      result=subprocess.run(cmd,cwd=run,stdout=out,stderr=err,timeout=180)
    summary=json.loads((run/'summary.json').read_text()) if (run/'summary.json').exists() else None
    for x in inputs:x['sha256_after']=digest(x['path'])
    unchanged=all(x['sha256_before']==x['snapshot_sha256']==x['sha256_after'] for x in inputs)
    expected=(2,0,0,0) if a.watchdog_probe else (int(a.negative),1,int(a.negative),int(a.negative))
    actual=(result.returncode,summary.get('done'),summary.get('errors'),summary.get('injected')) if summary else None
    qualified=unchanged and expected==actual and (a.watchdog_probe or summary['checks']>0)
    report.update(finished_at=now(),elapsed_seconds=time.monotonic()-start,native_exit=result.returncode,summary=summary,inputs_unchanged=unchanged,qualified=qualified)
    report['outputs']=[{'path':str(p),'sha256':digest(p)} for p in sorted(run.iterdir()) if p.is_file() and p.name not in ('wave.wlf','modelsim.ini')]
    save(run/'run-manifest.json',report)
    print(json.dumps({'run':str(run),'qualified':qualified,'native_exit':result.returncode,'summary':summary}))
    return 0 if qualified else 1
if __name__=='__main__':raise SystemExit(main())
