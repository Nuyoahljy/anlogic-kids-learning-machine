"""Audit exact new-DUT tests, inherited oracles, protected inputs and images."""
from pathlib import Path
import argparse, datetime, hashlib, json, re
from PIL import Image,ImageChops

ROOT=Path(__file__).resolve().parents[3]
E=ROOT/'evidence/sc520-card-recognition'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def art(p):
    p=Path(p).resolve();return {'Path':str(p),'SHA256':sha(p),'Bytes':p.stat().st_size}
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--output',type=Path,required=True);a=ap.parse_args()
    assert not a.output.exists()
    runs=[];references=0
    for test in ('business','default','render','pipeline','reset'):
        for mode in ('normal','negative','watchdog'):
            candidates=[]
            for p in (E/'runs').glob(f'timing23-{test}-{mode}-*/run-manifest.json'):
                r=read(p)
                if r.get('Qualified') and all(sha(x['path'])==x['sha256_before'].upper() for x in r['Inputs']):
                    candidates.append((p,r))
            assert candidates,(test,mode)
            p,r=max(candidates,key=lambda x:x[1]['FinishedAt']);s=r['Summary']
            assert r['NativeExitCode']==(2 if mode=='watchdog' else int(mode=='negative'))
            assert s['done']==int(mode!='watchdog') and s['errors']==int(mode=='negative') and s['injected']==int(mode=='negative')
            for x in r['Inputs']:
                assert sha(x['path'])==sha(x['snapshot'])==x['sha256_before'].upper()==x['sha256_after'].upper()==x['snapshot_sha256'].upper();references+=1
            for x in r['Outputs']:assert sha(x['path'])==x['sha256'].upper(),x;references+=1
            runs.append({**art(p),'Test':test,'Mode':mode,'Summary':s,'Command':r['Command']})
    protected=read(E/'audio22/start.json')
    for x in protected['Protected']+protected['Imports']:assert sha(x['Path'])==x['SHA256'],x['Path']
    old=read(ROOT/'assets/templates/sc520-card-recognition/display17/font-extension.json')
    new=read(ROOT/'assets/templates/sc520-card-recognition/audio22/font-extension.json')
    byid={g['id']:g for g in new['Glyphs']}
    for g in old['Glyphs']:assert byid[g['id']]==g
    source=ROOT/'fpga/sim/sc520-card-recognition/audio22'
    adapted=ROOT/'fpga/sim/sc520-card-recognition/timing23'
    oracles=[]
    for test in ('business','default','render','pipeline'):
        text=(source/f'tb_audio22_{test}.sv').read_text(encoding='utf-8-sig')
        expected=text.replace('tb_audio22_','tb_timing23_').replace('pixel22_compositor','pixel23_compositor').replace('pixel14_pipeline #','pixel23_pipeline #')
        target=adapted/f'tb_timing23_{test}.sv'
        assert target.read_text(encoding='utf-8-sig')==expected,('Independent oracle changed',target)
        oracles.append({'Original':art(source/f'tb_audio22_{test}.sv'),'Adapted':art(target),'OnlyDUTAndTopNamesChanged':True})
    render=Path(next(x['Path'] for x in runs if x['Test']=='render' and x['Mode']=='normal')).parent
    preview=E/'timing23/preview-v1';assert not preview.exists();preview.mkdir()
    frames=[]
    for i in range(4):
        actual=render/f'actual-{i}.ppm';gold=ROOT/f'assets/templates/sc520-card-recognition/audio22/golden-{i}.png'
        im=Image.open(actual).convert('RGB');assert im.size==(1280,720)
        assert ImageChops.difference(im,Image.open(gold).convert('RGB')).getbbox() is None
        p=preview/f'actual-{i}-timing23.png';im.save(p)
        frames.append({'ActualPPM':art(actual),'Golden':art(gold),'Preview':art(p),'PixelsCompared':921600})
    reset=Path(next(x['Path'] for x in runs if x['Test']=='reset' and x['Mode']=='normal')).parent
    text=(reset/'transcript.log').read_text(encoding='utf-8-sig')
    coverage=re.search(r'DONE timing23-reset scenarios=(\d+) frames=(\d+) checks=(\d+) reset_edges=(\d+) payload_checks=(\d+) errors=(\d+)',text)
    assert coverage and coverage[1]=='7' and coverage[2]=='7' and int(coverage[4])>1000000 and int(coverage[5])>20 and coverage[6]=='0'
    normal=[x['Summary'] for x in runs if x['Mode']=='normal']
    result={'At':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),'Qualified':True,'Runs':runs,
        'PositiveScenarios':sum(x['scenarios'] for x in normal),'PositiveChecks':sum(x['checks'] for x in normal),
        'CurrentReferencesChecked':references,'OldGlyphsPreserved':len(old['Glyphs']),'GlyphCount':len(new['Glyphs']),
        'ProtectedCount':len(protected['Protected']),'Protection':art(E/'audio22/start.json'),'IndependentOracleBindings':oracles,
        'ResetCoverage':dict(zip(('Scenarios','Frames','Checks','ResetEdges','PayloadChecks','Errors'),map(int,coverage.groups()))),
        'FullFrames':frames,'HardwareDefault':art(ROOT/'assets/templates/sc520-card-recognition/audio22/hardware-default.json'),
        'SyntheticTestProfile':art(ROOT/'assets/templates/sc520-card-recognition/audio22/offline-test.json'),'Program':art(__file__),
        'HardwareValidated':False,'BitGenerationAllowed':False,
        'Scope':'T023 same-cycle reset distribution and coordinate pipeline. Five groups each with normal, actual DUT-output injection and early-stop rejection. Existing 54-clock image path, six-register-layer display, one packet snapshot, real UART/queue/business, four720p images.'}
    a.output.parent.mkdir(parents=True,exist_ok=True)
    with a.output.open('x',encoding='utf-8') as f:json.dump(result,f,ensure_ascii=False,indent=2);f.write('\n')
    print(json.dumps({k:result[k] for k in ('Qualified','PositiveScenarios','PositiveChecks','CurrentReferencesChecked','ProtectedCount')}))
if __name__=='__main__':main()
