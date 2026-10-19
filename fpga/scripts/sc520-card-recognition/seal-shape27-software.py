"""Verify immutable software evidence and the frozen D0261 before main review."""
from pathlib import Path
from datetime import datetime,timezone,timedelta
import argparse,csv,hashlib,json
R=Path(__file__).resolve().parents[3]
E=R/'evidence/sc520-shape27'
OLD=R/'evidence/sc520-color-integration'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def artifact(p):return {'Path':str(p),'SHA256':sha(p),'Bytes':Path(p).stat().st_size}
def save(p,data):
    with p.open('x',encoding='utf-8') as f:json.dump(data,f,ensure_ascii=False,indent=2);f.write('\n')
ap=argparse.ArgumentParser()
ap.add_argument('--lifecycle-run',required=True)
a=ap.parse_args()
names=[
    'scenes-normal-20261019-204351-38a6c6',
    'scenes-normal-20261019-205055-7fd100',
    'reset-normal-20261019-204553-e12822',
    'pipeline-normal-20261019-204553-9a0787',
    'render-normal-20261019-205055-a6c750',
    'pairing-normal-20261019-205055-453de5',
    a.lifecycle_run,
]
rows=[]
def verify_run(name,success):
    p=E/'runs'/name/'run-manifest.json'
    m=json.loads(p.read_text())
    assert m['Summary']['done']==1 and m['InputsUnchanged']
    assert m['NativeExitCode']==(0 if success else 1)
    assert m['Summary']['errors']==(0 if success else 30)
    for item in m['Inputs']:
        assert sha(item['Path'])==item['SHA256']==sha(item['Snapshot']),item['Path']
    for item in m['Outputs']:assert sha(item['Path'])==item['SHA256'],item['Path']
    return {'Run':artifact(p),'Summary':m['Summary'],'Inputs':len(m['Inputs']),'Outputs':len(m['Outputs'])}
for name in names:rows.append(verify_run(name,True))
legacy_name='scenes-legacy-20261019-204351-462c46'
legacy=verify_run(legacy_name,False)
gates=[]
for name,code,done,errors,injected in [
    ('reset-negative-20261019-210149-29e13c',1,1,1,1),
    ('reset-watchdog-20261019-210149-561bbb',2,0,0,0),
]:
    p=E/'runs'/name/'run-manifest.json'
    m=json.loads(p.read_text())
    assert m['Qualified'] and m['InputsUnchanged'] and m['NativeExitCode']==code
    assert [m['Summary'][k] for k in ['done','errors','injected']]==[done,errors,injected]
    for i in m['Inputs']:assert sha(i['Path'])==i['SHA256']==sha(i['Snapshot'])
    for i in m['Outputs']:assert sha(i['Path'])==i['SHA256']
    gates.append({'Run':artifact(p),'Summary':m['Summary'],'ExpectedNativeExitCode':code})
old_manifest=json.loads(Path(legacy['Run']['Path']).read_text())
new_manifest=json.loads(Path(rows[0]['Run']['Path']).read_text())
for item in old_manifest['Inputs']:
    if Path(item['Path']).suffix=='.mem' or Path(item['Path']).name=='cases.txt':
        matches=[i for i in new_manifest['Inputs'] if i['Path']==item['Path']]
        assert len(matches)==1 and matches[0]['SHA256']==item['SHA256']
def csv_rows(name):
    with (E/'runs'/name/'scene-results.csv').open(newline='') as f:
        return [{k:v.strip() for k,v in r.items()} for r in csv.DictReader(f)]
old_csv,new_csv=csv_rows(legacy_name),csv_rows(names[0])
assert len(old_csv)==len(new_csv)==186
assert [(r['case'],r['frame']) for r in old_csv]==[(r['case'],r['frame']) for r in new_csv]
square=[]
for old,new in zip(old_csv,new_csv):
    if new['case'] in ['block_2_gray20','block_2_gray25','block_2_wrong20','block_2_wrong25'] and new['frame']=='2':
        assert old['item']=='0' and new['item']=='2' and new['shape']=='2'
        square.append({'Case':new['case'],'Old':old,'New':new})
assert len(square)==4
build=OLD/'builds/6a50b261/inputs.json'
b=json.loads(build.read_text())
assert len(b['Files'])==388
protected=[]
for item in b['Files']:
    assert sha(item['Path'])==item['SHA256'],item['Path']
    protected.append(artifact(item['Path']))
    if 'Snapshot' in item:
        assert sha(item['Snapshot'])==item['SnapshotSHA256'],item['Snapshot']
        protected.append(artifact(item['Snapshot']))
db=OLD/'builds/6a50b261/td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display_pr.db'
bit=OLD/'bitgen-d0261-v4/sc520-d0261.bit'
assert sha(build)=='99CE59144021DC9FAA26F554850F0CCC530A1D816BC3467085A3B17C12EA5486'
assert sha(db)=='3A95B2E4A0C801703D5A498F161267F5D560328DC934F7BE0E0B867308001CC1'
assert sha(bit)=='FB9CBC03119EF3F58F366BD0AAA09C895E7C7C877D1535250F983AE5C5346D40'
protected += [artifact(build),artifact(db),artifact(bit)]
protection={'FrozenBuildInputCount':388,'BuildInputs':artifact(build),'RouteDatabase':artifact(db),
    'Bit':artifact(bit),'Files':protected,'AllCurrentAndSnapshotHashesVerified':True}
save(E/'protected-d0261.json',protection)
production=sorted((R/'fpga/rtl/sc520-shape27').glob('*.v'))
production+=sorted((R/'fpga/custom_project/sc520-shape27/overlay').glob('*'))
production+=[R/'fpga/scripts/sc520-card-recognition'/n for n in [
    'prepare-shape27.py','build-shape27.ps1','generate-shape27-bit.py']]
review=Path('E:/juan/FPGA/learning/sc520-shape27/review/run-20261019-204556-94b862/result.json')
independent=json.loads(review.read_text())
assert independent['Passed'] and independent['Summary']['Errors']==0
for i in independent['Inputs']:assert sha(i['Path'])==i['SHA256']==sha(i['Snapshot'])
report={'CreatedAt':datetime.now(timezone(timedelta(hours=8))).isoformat(),
    'Task':'sc520-shape27','Owner':'Codex /root/shape27_impl_resume',
    'SoftwareQualified':True,'MainAccepted':False,'PhysicalQualified':False,
    'HardwareValidated':False,'BitGenerationAllowed':False,
    'Runs':rows,'RunnerGuards':gates,'LegacySameTruthCompleteFailure':legacy,
    'DamagedRedSquareComparison':square,
    'Summary':{'Scenarios':sum(r['Summary']['scenarios'] for r in rows),
        'Checks':sum(r['Summary']['checks'] for r in rows),'Errors':0},
    'SourceFreeze':[artifact(p) for p in production],
    'FrozenD0261':artifact(E/'protected-d0261.json'),
    'IndependentBoundaryReview':artifact(review),
    'OriginalInterruptedRun':str(E/'runs/scenes-legacy-20261019-203636-a35a42'),
    'RejectedTestHistory':[
        {'Run':'lifecycle-normal-20261019-205055-73a725','Reason':'Test-only TIMEOUT500 exceeded observation bridge parameter range; time-zero failure, retained.'},
        {'Run':'lifecycle-normal-20261019-205243-1d2127','Reason':'Test-only synthetic stats pulse coincided with EOF; observer requires previously cached stats. Also attempted source switch without required epoch flush. Both invalid stimulus failures retained, no production change.'}],
    'Limits':[
        'All damaged shapes are synthetic; not a replay of the user JPEG. White substrate is the current operating constraint.',
        'The 2/3 coverage is an engineering candidate, with 2:1 dominant bichromatic inputs permitted.',
        'CSV raw is an internal 1/4/7 color anchor; diagnostic packet RB is the combined public 1..9 item.',
        'Pairing test forces classifier-boundary evidence and isolates unrelated engines; full raster tests exercise the complete engines separately.',
        'Original source bootstrap scripts are historical and refuse to overwrite the resumed implementation.',
        'Git holds compact logs/manifests. Preserve and SHA-verify local immutable snapshots, fixtures, raw pixels and tool outputs separately.',
        'No TD, bitgen, download, Flash or new hardware result is claimed by this software report.']}
save(E/'software-v1.json',report)
print(json.dumps({'Report':str(E/'software-v1.json'),'SHA256':sha(E/'software-v1.json'),
    'Summary':report['Summary'],'ProtectedFilesAndSnapshots':len(protected)}))
