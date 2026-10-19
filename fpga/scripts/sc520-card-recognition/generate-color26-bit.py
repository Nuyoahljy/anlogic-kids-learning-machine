"""Generate only from an explicit main-review approval bound to the routed DB."""
from pathlib import Path
import argparse,ctypes,hashlib,json,subprocess
from contextlib import contextmanager
R=Path(__file__).resolve().parents[3]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
@contextmanager
def short_workspace():
 occupied=ctypes.windll.kernel32.GetLogicalDrives()
 aliases=subprocess.check_output(['subst.exe'],text=True)
 drive=next((d+':' for d in 'VUTSR' if not occupied&(1<<(ord(d)-ord('A'))) and not any(line.startswith(d+':') for line in aliases.splitlines())),None)
 assert drive,'No free temporary drive for TD MAX_PATH workaround'
 subprocess.run(['subst.exe',drive,str(R.parent)],check=True)
 try:yield Path(drive+'/'),drive
 finally:subprocess.run(['subst.exe',drive,'/D'],check=True)
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--approval',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args()
 approval=json.loads(a.approval.read_text(encoding='utf-8-sig'))
 assert approval['Stage']=='bitgen_approved' and approval['ApprovedBy'],'Main review has not approved bitgen'
 assert approval['Purpose']=='SRAM validation only' and approval['HardwareValidated'] is False
 protected={str(a.approval.resolve()):sha(a.approval)}
 for name in ['RouteDatabase','BuildInputs','SoftwareReview','PhysicalReview']:
  row=approval[name];p=Path(row['Path']).resolve();assert sha(p)==row['SHA256'].upper(),(name,p);protected[str(p)]=sha(p)
 db=Path(approval['RouteDatabase']['Path']).resolve();inputs_path=Path(approval['BuildInputs']['Path']).resolve();run=inputs_path.parent
 run.relative_to(R/'evidence/sc520-color-integration/builds');assert db==run/'td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display_pr.db'
 inputs=json.loads(inputs_path.read_text(encoding='utf-8-sig'))
 for row in inputs['Files']:
  assert sha(row['Path'])==row['SHA256'];protected[row['Path']]=row['SHA256']
  if 'Snapshot' in row:assert sha(row['Snapshot'])==row['SnapshotSHA256'];protected[row['Snapshot']]=row['SnapshotSHA256']
 project=run/'td_project/camera_to_dsi_display.al';protected[str(project)]=sha(project)
 out=a.output.resolve();out.relative_to(R/'evidence/sc520-color-integration');out.mkdir(parents=True,exist_ok=False)
 for p in [db,project,out]:assert not any(c in str(p) for c in '{}\r\n')
 tool=Path('D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe')
 with short_workspace() as (short_root,drive):
  def short(p):return (short_root/p.relative_to(R.parent)).as_posix()
  script=f'''if {{[catch {{
import_device ph1_35p.db -package PH1P35MDG324 -speed 3
cd {{{short(project.parent)}}}
open_project {{{short(project)}}} -noanalyze
import_db {{{short(db)}}}
cd {{{short(out)}}}
bitgen -bit sc520-d0261.bit
}} message]}} {{puts stderr $message;exit 1}}
puts "MAIN_APPROVED_D0261_BITGEN_COMPLETE"
exit 0
'''
  (out/'bitgen.tcl').write_text(script,encoding='ascii');(out/'approval.json').write_bytes(a.approval.read_bytes())
  command=[str(tool),short(out/'bitgen.tcl')]
  with (out/'stdout.log').open('wb') as stdout,(out/'stderr.log').open('wb') as stderr:
   code=subprocess.run(command,cwd=short(out),stdout=stdout,stderr=stderr,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0)).returncode
 unchanged=all(sha(p)==h for p,h in protected.items());bit=out/'sc520-d0261.bit'
 text=(out/'stdout.log').read_text(errors='replace');errors=[line for line in text.splitlines() if 'ERROR' in line]
 imported='Import design success TD_VERSION=6.2.168116' in text
 complete=code==0 and unchanged and bit.exists() and bit.stat().st_size>0 and not errors and (out/'stderr.log').stat().st_size==0 and imported and 'MAIN_APPROVED_D0261_BITGEN_COMPLETE' in text
 result={'Complete':complete,'NativeExitCode':code,'InputsUnchanged':unchanged,'ProtectedInputs':protected,'Command':command,'ToolSHA256':sha(tool),'GeneratorSHA256':sha(__file__),'TemporaryMapping':{'Drive':drive,'Target':str(R.parent),'Released':True},'LogErrors':errors,'DatabaseImportSucceeded':imported,'HardwareValidated':False,'DownloadExecuted':False,'FlashExecuted':False,'Bit':{'Path':str(bit),'SHA256':sha(bit),'Bytes':bit.stat().st_size} if bit.exists() else None}
 (out/'result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print(json.dumps(result['Bit']));return 0 if complete else 1
if __name__=='__main__':raise SystemExit(main())
