"""Bind final software checks to immutable snapshots and the current production inputs."""
from pathlib import Path
from datetime import datetime,timezone,timedelta
import hashlib,json
R=Path(__file__).resolve().parents[3];E=R/'evidence/sc520-color-integration'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def artifact(p):return {'Path':str(p),'SHA256':sha(p),'Bytes':Path(p).stat().st_size}
names=['numeric-normal-20261019-114833-8e56eb','render-normal-20261019-114848-ff3507','scenes_bg-normal-20261019-121713-17c1cc','reset_bg-normal-20261019-121714-b483cf','pipeline_bg-normal-20261019-121714-e55f8e','block_pipe-normal-20261019-121840-8ecbb6','scene_oracle-normal-20261019-121407-c11020']
rows=[];refs=0
for name in names:
 p=E/'runs'/name/'run-manifest.json';m=json.loads(p.read_text());assert m['Qualified'] and m['NativeExitCode']==0 and m['Summary']['done']==1 and m['Summary']['errors']==0
 historical=[]
 for r in m['Inputs']:
  assert sha(r['Snapshot'])==r['SHA256'],r['Snapshot'];refs+=1
  if sha(r['Path'])!=r['SHA256']:historical.append({'Path':r['Path'],'Snapshot':r['Snapshot'],'SnapshotSHA256':r['SHA256'],'CurrentSHA256':sha(r['Path'])})
 for r in m['Outputs']:assert sha(r['Path'])==r['SHA256'],r['Path'];refs+=1
 rows.append({'Run':artifact(p),'Summary':m['Summary'],'SnapshotInputs':len(m['Inputs']),'Outputs':len(m['Outputs']),'HistoricalSourceVersions':historical})
build=E/'builds/6a50b261/inputs.json';b=json.loads(build.read_text());current=[]
for x in b['Files']:
 assert sha(x['Path'])==x['SHA256'],x['Path']
 if 'Snapshot' in x:assert sha(x['Snapshot'])==x['SnapshotSHA256'],x['Snapshot']
 if str(R) in x['Path'] and any(s in x['Path'].replace('\\','/') for s in ['/sc520-color-integration/','/sc520-color26-bg/']):current.append(x)
proofs=[Path('E:/juan/FPGA/learning/sc520-color-integration/review')/p for p in ['cube-20261019-114746-9737bf/audit.json','i2c-20261019-115350-6a99d0/audit.json','scene-envelope-20261019-121527-2b679e/audit.json','piped-classifier-20261019-121956-9af09e/audit.json']]
result={'CreatedAt':datetime.now(timezone(timedelta(hours=8))).isoformat(),'Owner':'01a15235-d7ad-7531-b390-c5fd0941eea0 /root/color26_impl','SoftwareQualified':True,'PhysicalQualified':False,'HardwareValidated':False,'BitGenerationAllowed':False,'Runs':rows,'VerifiedImmutableReferences':refs,'Summary':{'Scenarios':sum(r['Summary']['scenarios'] for r in rows),'Checks':sum(r['Summary']['checks'] for r in rows),'Errors':0},'IndependentReviewArtifacts':[artifact(p) for p in proofs if p.exists()],'BuildInputs':artifact(build),'SourceFreeze':current,'RejectedHistory':{'Counterexamples':'runs/scenes-normal-20261019-115257-c80240','PhysicalBaseline':'builds/6a50b260','Reason':'Four background cases failed before scene fix; baseline also setup -3.405ns and audio report unresolved.'},'Limitations':['Field texture is sampled from fixed final05 scene, then tiled into synthetic shapes. No new hardware generalization proof.','4DN margin is provisional; an interior chroma change beyond the observed border envelope can become unknown foreground.','Some historical runs compile unused previous pipeline modules and older runner scripts. Snapshot identity is preserved; only selected final production input graph is current.','Three audio gates0/TRACKS empty, no external audio pins; real playback unverified.']}
(E/'software-v2.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print(json.dumps({'Summary':result['Summary'],'VerifiedImmutableReferences':refs,'HistoricalVersions':{r['Run']['Path']:len(r['HistoricalSourceVersions']) for r in rows},'BuildInputsSHA256':sha(build)}))
