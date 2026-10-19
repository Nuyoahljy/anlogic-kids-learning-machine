"""Generate only from an explicit main-review approval bound to the routed DB."""
from pathlib import Path
import argparse,hashlib,json,subprocess
R=Path(__file__).resolve().parents[3]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
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
 script=f'''if {{[catch {{
import_device ph1_35p.db -package PH1P35MDG324 -speed 3
open_project {{{project.as_posix()}}} -noanalyze
import_db {{{db.as_posix()}}}
bitgen -bit sc520-d0261.bit
}} message]}} {{puts stderr $message;exit 1}}
puts "MAIN_APPROVED_D0261_BITGEN_COMPLETE"
exit 0
'''
 (out/'bitgen.tcl').write_text(script,encoding='ascii');(out/'approval.json').write_bytes(a.approval.read_bytes())
 tool=Path('D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe');command=[str(tool),str(out/'bitgen.tcl')]
 with (out/'stdout.log').open('wb') as stdout,(out/'stderr.log').open('wb') as stderr:
  code=subprocess.run(command,cwd=out,stdout=stdout,stderr=stderr,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0)).returncode
 unchanged=all(sha(p)==h for p,h in protected.items());bit=out/'sc520-d0261.bit'
 complete=code==0 and unchanged and bit.exists() and bit.stat().st_size>0 and 'MAIN_APPROVED_D0261_BITGEN_COMPLETE' in (out/'stdout.log').read_text(errors='replace')
 result={'Complete':complete,'NativeExitCode':code,'InputsUnchanged':unchanged,'ProtectedInputs':protected,'Command':command,'ToolSHA256':sha(tool),'HardwareValidated':False,'DownloadExecuted':False,'FlashExecuted':False,'Bit':{'Path':str(bit),'SHA256':sha(bit),'Bytes':bit.stat().st_size} if bit.exists() else None}
 (out/'result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print(json.dumps(result['Bit']));return 0 if complete else 1
if __name__=='__main__':raise SystemExit(main())
