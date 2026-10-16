"""Bind a completed T022 commit to local test/probe bytes and prior protection."""
from pathlib import Path
import argparse,datetime,hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[3];E=ROOT/'evidence/sc520-card-recognition'
BASE='fe5173964657dacc9c6723fe00e7ed5975901462'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def git(*a):return subprocess.check_output(['git',*a],cwd=ROOT)
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--output',required=True,type=Path)
    ap.add_argument('--manifest',type=Path,default=E/'audio22/integration-manifest-v1.json')
    a=ap.parse_args();assert not a.output.exists()
    commit=git('rev-parse','HEAD').decode().strip();assert commit!=BASE
    assert not git('status','--porcelain').strip(),'Task worktree is not clean'
    existing=git('diff','--diff-filter=MD','--name-only',BASE,commit).decode().splitlines()
    assert existing==['memory/branches/sc520-card-recognition.md'],existing
    exact=[];normalized=[]
    for p in git('diff','--name-only','-z',BASE,commit).split(b'\0'):
        if not p:continue
        name=p.decode();assert name.startswith(('fpga/','assets/','hardware/','evidence/sc520-card-recognition/','memory/branches/sc520-card-recognition.md'))
        local=(ROOT/name).read_bytes();blob=git('show',commit+':'+name)
        row={'Path':str(ROOT/name),'SHA256':sha(ROOT/name),'GitSHA256':hashlib.sha256(blob).hexdigest().upper()}
        if blob==local:exact.append(row)
        else:
            assert blob.replace(b'\r\n',b'\n')==local.replace(b'\r\n',b'\n'),name
            normalized.append(row)
    start=json.loads((E/'audio22/start.json').read_text(encoding='utf-8-sig'))
    for x in start['Protected']+start['Imports']:assert sha(x['Path'])==x['SHA256'],x['Path']
    manifest=json.loads(a.manifest.read_text(encoding='utf-8-sig'))
    assert manifest['Downloadable'] is False and manifest['BitGenerationAllowed'] is False
    def check(x):
        if isinstance(x,dict):
            if 'Path' in x and 'SHA256' in x:assert sha(x['Path'])==x['SHA256'],x['Path']
            for v in x.values():check(v)
        elif isinstance(x,list):
            for v in x:check(v)
    check(manifest)
    run=Path(manifest['Run']);inputs=json.loads((run/'inputs.json').read_text(encoding='utf-8-sig'))
    for x in inputs['Files']:
        assert sha(x['Path'])==x['SHA256'],x['Path']
        if x.get('Snapshot'):assert sha(x['Snapshot'])==x['SnapshotSHA256'],x['Snapshot']
    assert not list(run.rglob('*.bit')) and not list((ROOT/'fpga/custom_project/sc520-audio22').rglob('*.bit'))
    result={'At':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),'Commit':commit,'Base':BASE,
        'Qualified':True,'VerificationScope':'Git and evidence byte identity only; no physical qualification',
        'ManifestStatus':manifest['Status'],'ManifestPath':str(a.manifest.resolve()),'ManifestSHA256':sha(a.manifest),
        'ExactFiles':exact,'CRLFOnlyFiles':normalized,'ExistingSourceFilesModified':[],
        'ProtectedCount':len(start['Protected']),'InputsChecked':len(inputs['Files']),'HardwareValidated':False,'BitFilesFound':[]}
    with a.output.open('x',encoding='utf-8') as f:json.dump(result,f,ensure_ascii=False,indent=2);f.write('\n')
    print(json.dumps({'Commit':commit,'Exact':len(exact),'CRLFOnly':len(normalized),'Protected':len(start['Protected']),'Inputs':len(inputs['Files'])}))
if __name__=='__main__':main()
