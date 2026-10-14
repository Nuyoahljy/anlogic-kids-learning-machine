"""Independently reread selected SC520 run manifests and the retained baseline."""
import argparse
from datetime import datetime, timedelta, timezone
import hashlib
import json
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[3]
EVIDENCE=ROOT/'evidence/sc520-card-recognition'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def artifact(path):
    path=Path(path).resolve()
    return {'Path':str(path),'SHA256':sha(path),'Bytes':path.stat().st_size}


def run_check(path):
    data=read(path)
    assert data['Qualified'] and data['InputsUnchanged'] and not data['TimedOut'],path
    summary=data['Summary'];mode=data['Mode']
    if mode=='watchdog':
        assert data['NativeExitCode']==2 and summary['done']==0 and summary['errors']==0,path
    else:
        expected=int(mode=='negative')
        assert data['NativeExitCode']==expected and summary['done']==1 and summary['checks']>0,path
        assert summary['errors']==expected and summary['injected']==expected,path
    for item in data['Inputs']:
        expected=item['sha256_before'].upper()
        assert expected==sha(item['path'])==sha(item['snapshot'])==item['sha256_after'].upper()==item['snapshot_sha256'].upper(),item
    for item in data['Outputs']:
        assert sha(item['path'])==item['sha256'].upper(),item
    return {**artifact(path),'Test':data['Test'],'Mode':mode,'FullResolution':data.get('FullResolution'),
            'RotationVariants':data.get('RotationVariants',0),'MatrixOnly':data.get('MatrixOnly',False),
            'Summary':summary,'NativeExitCode':data['NativeExitCode'],'Command':data['Command'],
            'InputsChecked':len(data['Inputs']),'OutputsChecked':len(data['Outputs'])}


def report_check(path):
    data=read(path)
    if Path(path).name=='rotation-checks.json':
        assert data['checks']>0 and data['failed']==0 and len(data['details'])==data['checks'],path
        assert all(item.get('passed') is True for item in data['details']),path
    else:
        assert data.get('Qualified',data.get('qualified',False)),path
    checked={}
    def walk(value):
        if isinstance(value,list):
            for child in value:walk(child)
        elif isinstance(value,dict):
            for pk,hk in [('Path','SHA256'),('path','sha256')]:
                if pk in value and hk in value and isinstance(value[pk],str) and isinstance(value[hk],str) and len(value[hk])==64:
                    p=Path(value[pk])
                    if not p.is_absolute():p=Path(path).parent/p
                    assert sha(p)==value[hk].upper(),p
                    checked[str(p)]=value[hk].upper()
            for child in value.values():walk(child)
    walk(data)
    return {**artifact(path),'ReferencedArtifactsChecked':len(checked)}


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--run',type=Path,action='append',default=[])
    ap.add_argument('--report',type=Path,action='append',default=[])
    ap.add_argument('--output',type=Path,required=True)
    args=ap.parse_args()
    assert not args.output.exists(),'Use a new audit output, preserving older evidence'
    runs=[run_check(p) for p in args.run]
    required={('scene_system','normal'),('scene_system','negative'),('scene_system','watchdog'),
              ('rotation_matcher','normal'),('rotation_matcher','negative'),('rotation_matcher','watchdog'),('pipeline','normal')}
    assert required<={(r['Test'],r['Mode']) for r in runs},'Incomplete final run set'
    assert any(r['Test']=='scene_system' and r['Mode']=='normal' and not r['MatrixOnly'] and r['RotationVariants']==256 and r['FullResolution'] for r in runs)
    assert any(r['Test']=='scene_system' and r['Mode']=='normal' and r['MatrixOnly'] and r['Summary']['scenarios']>=28 for r in runs)
    assert any(r['Test']=='pipeline' and r['FullResolution'] for r in runs)
    reports=[report_check(p) for p in args.report]
    # The source scripts evolved, but every original generated scene-v1 file
    # from the recovery checkpoint must still be byte-identical.
    checkpoint=Path('E:/juan/FPGA/learning/sc520-contest-roadmap/recovery-checkpoint-20261013.json')
    kept=[x for x in read(checkpoint)['Board']['PendingFiles'] if '/scene-v1/' in x['Path'].replace('\\','/')]
    assert len(kept)==1095,len(kept)
    for item in kept:assert sha(item['Path'])==item['SHA256'],item['Path']
    old=EVIDENCE/'builds/6a50b10a'
    old_inputs=read(old/'inputs.json')
    snapshots=external=0
    for item in old_inputs['Files']:
        if item.get('Snapshot'):
            assert sha(item['Snapshot'])==item['SnapshotSHA256'],item['Snapshot'];snapshots+=1
        if not Path(item['Path']).is_relative_to(ROOT):
            assert sha(item['Path'])==item['SHA256'],item['Path'];external+=1
    oldbit=EVIDENCE/'delivery-0109/sc520-pixel14-0109.bit'
    assert sha(oldbit)=='3A7CD3912C0C72FC6553382E2FB00B61F3A432B251C1C236A35BDFE1FAC7D3F8'
    result={'CreatedAt':datetime.now(timezone(timedelta(hours=8))).isoformat(),'Qualified':True,
            'Owner':'01a13561-2629-7fa2-86a0-4087ad34cc7c /root','Workdir':str(ROOT),
            'HeadAtAudit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
            'Runs':runs,'ComponentReports':reports,'OriginalSceneFilesPreserved':len(kept),
            'Old0109SnapshotEntriesChecked':snapshots,'External0109SourceEntriesUnchanged':external,
            'Old0109Bit':artifact(oldbit),'RecoveryCheckpoint':artifact(checkpoint),'AuditTool':artifact(__file__),
            'Limits':'Software evidence only. Angle matrix includes documented refusals. Physical camera, board, audio and display branch integration are not validated here.'}
    args.output.parent.mkdir(parents=True,exist_ok=True)
    with args.output.open('x',encoding='utf-8') as stream:json.dump(result,stream,ensure_ascii=False,indent=2);stream.write('\n')
    print(json.dumps({'output':str(args.output),'qualified':True,'runs':len(runs),'reports':len(reports),'preserved':len(kept)}))


if __name__=='__main__':main()
