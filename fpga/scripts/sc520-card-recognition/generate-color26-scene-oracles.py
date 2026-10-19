"""Complete scene replay and normalized-mask oracles for old and new fixtures."""
from pathlib import Path
import hashlib,importlib.util,json
import numpy as np
from PIL import Image
R=Path(__file__).resolve().parents[3];S=Path(__file__).parent;E=R/'evidence/sc520-color-integration';F=E/'scene-oracles-v1';F.mkdir(parents=True,exist_ok=False)
spec=importlib.util.spec_from_file_location('oracle_rotation',S/'scene-rotation-model.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
text=(S/'scene-model.py').read_text();needle='    connected = np.zeros((height, width), dtype=bool)'
extra='''    rg=rgb[:,:,0].astype(np.int16)-rgb[:,:,1].astype(np.int16)
    bg=rgb[:,:,2].astype(np.int16)-rgb[:,:,1].astype(np.int16)
    similar &= (rg>=int(rg[border].min())-4)&(rg<=int(rg[border].max())+4)&(bg>=int(bg[border].min())-4)&(bg<=int(bg[border].max())+4)
'''
scope={};exec(compile(text.replace(needle,extra+needle),'scene_oracle','exec'),scope);m.base.analyze=scope['analyze']
def read(p):
 if p.suffix=='.png':return np.asarray(Image.open(p).convert('RGB'))
 x=np.loadtxt(p,dtype=np.uint32,converters=lambda x:int(x,16)).reshape(180,320);return np.stack([x>>16,(x>>8)&255,x&255],axis=-1).astype(np.uint8)
def mem(p,rgb):p.write_text(''.join(f'{r:02X}{g:02X}{b:02X}\n' for r,g,b in rgb.reshape(-1,3)),encoding='ascii')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
cases=[];A=R/'assets/templates/sc520-card-recognition/rotation-v1'
for c in json.loads((A/'fixtures.json').read_text()):
 p=A/'vectors'/(c['prefix']+'.rgb.mem');p=p if p.exists() else p.with_suffix('').with_suffix('.png');cases.append((c['prefix'],read(p),p))
for c in json.loads((E/'scenes/manifest.json').read_text())['Cases']:cases.append((c['Name'],read(Path(c['Path'])),Path(c['Path'])))
y,x=np.mgrid[:180,:320]
for name,color in [('gray',(90,90,90)),('wood',(105,86,66)),('red',(116,96,89)),('blue',(80,93,110)),('green_extreme',(0,255,0)),('magenta_extreme',(255,0,255))]:
 for kind in ['flat','brightness_wave','chroma_noise']:
  rgb=np.full((180,320,3),color,dtype=np.int16)
  if kind=='brightness_wave':rgb+=(((x//7+y//23)%5-2)*6)[:,:,None]
  if kind=='chroma_noise':
   for k in range(3):rgb[:,:,k]+=((x*(3+k)+y*(5+k))%9)-4
  cases.append((name+'_'+kind,np.clip(rgb,0,255).astype(np.uint8),None))
rows=[];lines=[]
for i,(name,rgb,source) in enumerate(cases):
 prefix=f'c{i:03d}';r=m.analyze(m.sample_frame(rgb));mem(F/(prefix+'.rgb.mem'),rgb);mem(F/(prefix+'.replay.mem'),r['replay_rgb'])
 (F/(prefix+'.mask.mem')).write_text(''.join(f'{int(v)}\n' for v in r['mask'].flat),encoding='ascii')
 lines.append(f'{prefix} {int(r["present"])} {r["scene_count"]} {r["glyph_count"]} {r["paper_count"]}\n')
 rows.append({'Index':i,'Prefix':prefix,'Name':name,'Source':str(source) if source else None,'SourceSHA256':sha(source) if source else None,'ExpectedPresent':r['present'],'Scene':r['scene_count'],'Glyph':r['glyph_count'],'Paper':r['paper_count'],'Outputs':[{'Path':str(F/(prefix+suffix)),'SHA256':sha(F/(prefix+suffix))} for suffix in ['.rgb.mem','.replay.mem','.mask.mem']]})
(F/'oracle-cases.txt').write_text(''.join(lines),encoding='ascii');(F/'manifest.json').write_text(json.dumps({'Cases':rows,'GeneratorSHA256':sha(Path(__file__))},ensure_ascii=False,indent=2)+'\n',encoding='utf-8');print('ORACLES',len(rows))
