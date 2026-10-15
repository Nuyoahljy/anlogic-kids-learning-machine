"""Qualify current T017 tests, exact optical baseline protection and four images."""
from pathlib import Path
import argparse,datetime,hashlib,json,subprocess
from PIL import Image,ImageChops
ROOT=Path(__file__).resolve().parents[3];E=ROOT/'evidence/sc520-card-recognition'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def art(p):return {'Path':str(Path(p).resolve()),'SHA256':sha(p),'Bytes':Path(p).stat().st_size}
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--output',type=Path,required=True);a=ap.parse_args();assert not a.output.exists()
    selected=[]
    for prefix,mode in [('display17-system','normal'),('display17-system','negative'),('display17-system','watchdog'),('i14-system','normal'),('p14-scene_system','normal')]:
        choices=[]
        for p in (E/'runs').glob(prefix+'-'+mode+'-*/run-manifest.json'):
            r=read(p)
            if r.get('Qualified') and r.get('InputsUnchanged') and all(sha(x['path'])==x['sha256_before'].upper() for x in r['Inputs']):choices.append((p,r))
        assert choices,(prefix,mode)
        p,r=max(choices,key=lambda x:x[1]['FinishedAt']);s=r['Summary']
        assert r['NativeExitCode']==(2 if mode=='watchdog' else int(mode=='negative'))
        assert s['done']==int(mode!='watchdog') and s['errors']==int(mode=='negative') and s['injected']==int(mode=='negative')
        for x in r['Inputs']:
            assert sha(x['path'])==sha(x['snapshot'])==x['sha256_before'].upper()==x['sha256_after'].upper()==x['snapshot_sha256'].upper()
        for x in r['Outputs']:assert sha(x['path'])==x['sha256'].upper(),x['path']
        selected.append({**art(p),'Prefix':prefix,'Mode':mode,'Summary':s,'Command':r['Command']})
    start=read(E/'display17/start.json')
    for x in start['Protected']+start['Imports']:assert sha(x['Path'])==x['SHA256'],x['Path']
    unchanged=[]
    for p in sorted((ROOT/'fpga/rtl/sc520-card-recognition/pixel14').glob('*.v')):
        if p.name=='pixel14_pipeline.v':continue
        rel=p.relative_to(ROOT).as_posix();old=subprocess.check_output(['git','show',start['BaseCommit']+':'+rel],cwd=ROOT)
        assert p.read_bytes().replace(b'\r\n',b'\n')==old.replace(b'\r\n',b'\n'),rel;unchanged.append(art(p))
    for name in ['isp_top.v','pixel14_color_pipeline.v','uii2c.v','uicfgcs520.v','pin.adc']:
        p=ROOT/'fpga/custom_project/sc520-pixel17/overlay'/name;old=ROOT/'evidence/sc520-card-recognition/builds/6a50b116/overlay'/name
        assert sha(p)==sha(old),name;unchanged.append(art(p))
    oldfont=read(ROOT/'assets/templates/sc520-card-recognition/items14/font-manifest.json')
    newfont=read(ROOT/'assets/templates/sc520-card-recognition/display17/font-extension.json')
    byid={x['id']:x for x in newfont['Glyphs']}
    for g in oldfont['glyphs']:assert byid[g['id']]==g,g['char']
    run=Path(selected[0]['Path']).parent;preview=E/'display17/preview';preview.mkdir(exist_ok=True)
    images=[]
    for i in range(4):
        actual=run/f'actual-{i}.ppm';gold=ROOT/f'assets/templates/sc520-card-recognition/display17/golden-{i}.png'
        image=Image.open(actual).convert('RGB');assert image.size==(1280,720)
        assert ImageChops.difference(image,Image.open(gold).convert('RGB')).getbbox() is None,i
        output=preview/f'actual-{i}-0117.png';assert not output.exists();image.save(output)
        images.append({'ActualPPM':art(actual),'Golden':art(gold),'Preview':art(output),'PixelsCompared':921600})
    normals=[x for x in selected if x['Mode']=='normal']
    report={'CreatedAt':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),'Qualified':True,'Runs':selected,
      'PositiveScenarios':sum(x['Summary']['scenarios'] for x in normals),'PositiveChecks':sum(x['Summary']['checks'] for x in normals),
      'ProtectedCount':len(start['Protected']),'Protected':start['Protected'],'Imports':start['Imports'],'CoreUnchanged':unchanged,
      'OldGlyphsPreserved':len(oldfont['glyphs']),'NewGlyphCount':len(newfont['Glyphs']),'FullFrames':images,
      'DisplayLayers':6,'SampleToOutputEdges':5,'HardwareValidated':False,'Program':art(__file__),
      'Scope':'Current business/control + new renderer, K3/K4/multiple keys, full720p independent RGB+metadata, live diagnostic invalidation, final RGB corruption and early termination; default business and80-case classifier compatibility.'}
    a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'qualified':True,'runs':len(selected),'cases':report['PositiveScenarios'],'checks':report['PositiveChecks'],'frames':4,'protected':len(start['Protected'])}))
if __name__=='__main__':main()
