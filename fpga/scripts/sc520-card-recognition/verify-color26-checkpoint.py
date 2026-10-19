"""Read-only verification of the Git checkpoint against owned frozen build sources."""
from pathlib import Path
import hashlib,json,subprocess
R=Path(__file__).resolve().parents[3];E=R/'evidence/sc520-color-integration'
def sha(data):return hashlib.sha256(data).hexdigest().upper()
head='9c550baec978e68c836f6589c439eca950844e46'
subprocess.run(['git','merge-base','--is-ancestor',head,'HEAD'],cwd=R,check=True)
b=json.loads((E/'builds/6a50b261/inputs.json').read_text());rows=[]
snapshots=0
for item in b['Files']:
 p=Path(item['Path'])
 assert sha(p.read_bytes())==item['SHA256'],p
 if 'Snapshot' in item:
  assert sha(Path(item['Snapshot']).read_bytes())==item['SnapshotSHA256'],item['Snapshot']
  snapshots+=1
 try:rel=p.relative_to(R).as_posix()
 except ValueError:continue
 if not (rel.startswith('fpga/rtl/sc520-color-integration/') or rel.startswith('fpga/custom_project/sc520-color26-bg/') or 'color26-bg' in rel):continue
 blob=subprocess.check_output(['git','show',head+':'+rel],cwd=R)
 assert sha(blob)==item['SHA256']==sha(p.read_bytes()),rel
 rows.append({'Path':str(p),'SHA256':item['SHA256'],'GitBlobSHA256':sha(blob)})
before=subprocess.check_output(['git','diff','--name-only','--diff-filter=MDR','c04530c',head],cwd=R,text=True).splitlines();assert not before,before
result={'Commit':head,'Base':'c04530c','ModifiedOrDeletedBaseFiles':before,'FrozenOwnedSourcesChecked':len(rows),'Sources':rows,'Qualified':True}
output=E/'checkpoint-source-review.json'
existed=output.exists()
if existed:
 assert json.loads(output.read_text(encoding='utf-8-sig'))==result,'Existing checkpoint result differs'
else:
 with output.open('x',encoding='utf-8') as stream:stream.write(json.dumps(result,indent=2)+'\n')
print(json.dumps({'Commit':head,'FrozenOwnedSourcesChecked':len(rows),'BuildInputsChecked':len(b['Files']),'SnapshotsChecked':snapshots,'ExistingResultVerifiedWithoutRewrite':existed,'Qualified':True}))
