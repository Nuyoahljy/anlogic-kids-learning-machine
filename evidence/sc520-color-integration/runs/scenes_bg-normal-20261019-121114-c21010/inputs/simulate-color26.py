"""T026 snapshot runner with native status, functional/negative/watchdog gates."""
from pathlib import Path
import argparse,datetime,hashlib,json,subprocess,time,uuid
R=Path(__file__).resolve().parents[3];HERE=Path(__file__).parent
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def save(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--test',choices=['numeric','pipeline','reset','render','scenes','pipeline_bg','reset_bg','scenes_bg'],required=True);ap.add_argument('--negative',action='store_true');ap.add_argument('--watchdog-probe',action='store_true');ap.add_argument('--scene-dir',type=Path);a=ap.parse_args()
 base=R/'fpga/rtl/sc520-card-recognition';new=R/'fpga/rtl/sc520-color-integration'
 rtl=sorted(new.glob('*.v'))
 if a.test!='numeric':
  for folder in ['items14','display17','audio22','audio22/imported','pixel14','color_diag','timing23']:rtl+=sorted((base/folder).glob('*.v'))
  rtl+=[base/n for n in ['card_matcher.v','card_template_rom.v','card_result_filter.v']]
  rtl+=[R/'fpga/sim/sc520-card-recognition/audio22/dfr0534_uart_model.sv']
 if a.test in ['reset','reset_bg']:rtl+=[R/'fpga/custom_project/sc520-color26/overlay/pixel14_color_pipeline.v',R.parent/'sc520-fixed-roi/fpga/custom_project/sc520-board-keys/user_source/hdl_source/signal_delay.v',R/'evidence/sc520-card-recognition/imaging-audit/ip_behavioral_models.sv']
 tb=R/'fpga/sim/sc520-color-integration'/f'tb_color26_{a.test}.sv'
 refs=[R/'assets/templates/sc520-card-recognition/display17'/n for n in ['anlogic_logo_index.mem','anlogic_logo_palette.mem']]
 refs+=[R/'assets/templates/sc520-card-recognition/rotation-v1/templates.mem',R/'assets/templates/sc520-card-recognition/items14/items14_text_reference.svh']
 refs+=list((R/'assets/templates/sc520-card-recognition/rotation-v1/vectors').glob('r000_empty_dark.rgb.mem'))+list((R/'assets/templates/sc520-card-recognition/rotation-v1/vectors').glob('r003_card_10_angle_0.rgb.mem'))
 refs+=list((R/'evidence/sc520-color-integration/fixtures').glob('*.mem'))
 if a.test in ['scenes','scenes_bg']:
  scene_dir=a.scene_dir or R/'evidence/sc520-color-integration/scenes'
  refs+=list(scene_dir.glob('*.mem'))+[scene_dir/'cases.txt']
 sources=rtl+[tb,Path(__file__).resolve(),HERE/'run-audio22.do']+refs
 assert len(sources)==len(set(sources))
 mode='negative' if a.negative else 'watchdog' if a.watchdog_probe else 'normal'
 run=R/'evidence/sc520-color-integration/runs'/f'{a.test}-{mode}-{datetime.datetime.now():%Y%m%d-%H%M%S}-{uuid.uuid4().hex[:6]}'
 snap=run/'inputs';snap.mkdir(parents=True)
 items=[]
 for p in sources:
  q=snap/p.name;assert not q.exists(),q;q.write_bytes(p.read_bytes());items.append({'Path':str(p),'Snapshot':str(q),'SHA256':sha(p)})
 simulator=Path('D:/modeltech64_10.7/win64/vsim.exe');ini=simulator.parent.parent/'modelsim.ini';(run/'modelsim.ini').write_bytes(ini.read_bytes())
 path=lambda p:'{'+p.as_posix()+'}'
 command=[str(simulator),'-modelsimini',str(run/'modelsim.ini'),'-c','-l','transcript.log','-do',f'set card_top tb_color26_{a.test}; set card_sources [list '+ ' '.join(path(snap/p.name) for p in rtl)+f']; set card_tb {path(snap/tb.name)}; set card_assets {path(snap)}; set card_negative {int(a.negative)}; set card_probe {int(a.watchdog_probe)}; source {path(snap/"run-audio22.do")}']
 report={'Task':'sc520-color-integration','Owner':'01a15235-d7ad-7531-b390-c5fd0941eea0 /root/color26_impl','Test':a.test,'Mode':mode,'Command':command,'Inputs':items,'WorkingDirectory':str(run),'StartedAt':datetime.datetime.now().astimezone().isoformat(),'HardwareValidated':False}
 save(run/'run-start.json',report);start=time.monotonic()
 with (run/'stdout.log').open('wb') as out,(run/'stderr.log').open('wb') as err:
  p=subprocess.Popen(command,cwd=run,stdout=out,stderr=err);report['PID']=p.pid
  try:code=p.wait(timeout=900)
  except subprocess.TimeoutExpired:subprocess.run(['taskkill','/PID',str(p.pid),'/T','/F'],capture_output=True);code=p.wait();report['TimedOut']=True
 summary=json.loads((run/'summary.json').read_text()) if (run/'summary.json').exists() else None
 unchanged=all(sha(x['Path'])==x['SHA256']==sha(x['Snapshot']) for x in items)
 qualified=bool(summary and unchanged and not report.get('TimedOut'))
 if qualified:
  qualified=(code==2 and summary['done']==0 and summary['errors']==0) if a.watchdog_probe else (code==int(a.negative) and summary['done']==1 and summary['errors']==int(a.negative) and summary['injected']==int(a.negative) and summary['checks']>0 and summary['scenarios']>0)
 report.update(NativeExitCode=code,Summary=summary,InputsUnchanged=unchanged,Qualified=qualified,ElapsedSeconds=time.monotonic()-start)
 report['Outputs']=[{'Path':str(p),'SHA256':sha(p)} for p in sorted(run.iterdir()) if p.is_file() and p.suffix not in ['.wlf']]
 save(run/'run-manifest.json',report);print(json.dumps({'run':str(run),'Qualified':qualified,'NativeExitCode':code,'Summary':summary}));return 0 if qualified else 1
if __name__=='__main__':raise SystemExit(main())
