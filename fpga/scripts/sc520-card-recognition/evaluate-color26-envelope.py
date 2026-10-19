"""Sensitivity and boundary negative controls for the proposed scene gate."""
from pathlib import Path
import hashlib,importlib.util,json
import numpy as np
from PIL import Image
R=Path(__file__).resolve().parents[3];S=Path(__file__).parent;E=R/'evidence/sc520-color-integration';O=E/'envelope-evaluation-v1';O.mkdir(parents=True,exist_ok=False)
spec=importlib.util.spec_from_file_location('rotation_eval',S/'scene-rotation-model.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
old_analyze=m.base.analyze;old_block=m.base.block_classify
source=(S/'scene-model.py').read_text();needle='    connected = np.zeros((height, width), dtype=bool)'
def model(margin):
 extra=f'''    rg=rgb[:,:,0].astype(np.int16)-rgb[:,:,1].astype(np.int16)
    bg=rgb[:,:,2].astype(np.int16)-rgb[:,:,1].astype(np.int16)
    similar &= (rg>=int(rg[border].min())-{margin})&(rg<=int(rg[border].max())+{margin})&(bg>=int(bg[border].min())-{margin})&(bg<=int(bg[border].max())+{margin})
'''
 scope={};exec(compile(source.replace(needle,extra+needle),'envelope_model','exec'),scope);return scope['analyze']
def normalized_block(rgb,present=True):
 saved=np.asarray(rgb,dtype=np.int16);channels=np.moveaxis(saved,-1,0);total=channels.sum(axis=0);maximum=channels.max(axis=0);second=np.sort(channels,axis=0)[1];winner=channels.argmax(axis=0)
 good=(total>0)&(100*(maximum-second)>=3*total);synthetic=np.full_like(saved,255)
 for k,c in enumerate([(215,61,60),(245,205,45),(50,112,205)]):synthetic[good&(winner==k)]=c
 return old_block(synthetic,present)
def rgbread(p):
 if not p.exists():return np.asarray(Image.open(p.with_suffix('').with_suffix('.png')).convert('RGB'))
 x=np.loadtxt(p,dtype=np.uint32,converters=lambda x:int(x,16)).reshape(180,320);return np.stack([x>>16,(x>>8)&255,x&255],axis=-1).astype(np.uint8)
bank=m.read_bank(R/'assets/templates/sc520-card-recognition/rotation-v1/templates.mem')
def inspect(frame,fn,block=normalized_block):
 m.base.analyze=fn;m.base.block_classify=block;r=m.recognize(frame,bank)
 return {k:r[k] for k in ['item','present','scene_count','glyph_count','paper_count','paper_route','shape','conflict']}
manifest=json.loads((E/'scenes/manifest.json').read_text());frames=[(c,rgbread(Path(c['Path']))) for c in manifest['Cases']]
results=[]
for margin in [2,4,6,8]:
 fn=model(margin);rows=[]
 for c,f in frames:
  r=inspect(f,fn);rows.append({'Case':c['Name'],'Result':r,'Pass':r['item']==c['Item'] and r['present']==c['Present']})
 results.append({'Margin':margin,'Pass':sum(r['Pass'] for r in rows),'Cases':rows})
 print('MARGIN',margin,results[-1]['Pass'],[r['Case'] for r in rows if not r['Pass']])
fn=model(4);legacy=[];A=R/'assets/templates/sc520-card-recognition/rotation-v1'
for c in json.loads((A/'fixtures.json').read_text()):
 f=rgbread(A/'vectors'/(c['prefix']+'.rgb.mem'));before=inspect(f,old_analyze,old_block);after=inspect(f,fn,old_block)
 legacy.append({'Case':c['prefix'],'Before':before,'After':after,'SameOutput':before['item']==after['item'] and before['present']==after['present'],'SameGlyphShape':before['glyph_count']==after['glyph_count'] and before['shape']==after['shape']})
noise=[];y,x=np.mgrid[:180,:320]
for name,color in [('gray',(90,90,90)),('wood',(105,86,66)),('red',(116,96,89)),('blue',(80,93,110)),('green_extreme',(0,255,0)),('magenta_extreme',(255,0,255))]:
 for kind in ['flat','brightness_wave','chroma_noise']:
  rgb=np.full((180,320,3),color,dtype=np.int16)
  if kind=='brightness_wave':rgb+=(((x//7+y//23)%5-2)*6)[:,:,None]
  if kind=='chroma_noise':
   for c in range(3):rgb[:,:,c]+=((x*(3+c)+y*(5+c))%9)-4
  rgb=np.clip(rgb,0,255).astype(np.uint8);r=inspect(rgb,fn);noise.append({'Case':name+'_'+kind,'Result':r,'EmptyPass':not r['present'] and r['item']==0})
result={'ProductionRTLChanged':False,'Margins':results,'SelectedCandidateMargin':4,'LegacyCount':len(legacy),'Legacy':legacy,'LegacyOutputChanges':[c for c in legacy if not c['SameOutput']],'LegacyGlyphShapeChanges':[c for c in legacy if not c['SameGlyphShape']],'EmptyControls':noise,'Limitations':'Synthetic scenes and border controls; margin4 is not calibrated hardware noise or guarantee for mixed colored boundaries.'}
(O/'evaluation.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8');print('FINAL',len(legacy),len(result['LegacyOutputChanges']),len(result['LegacyGlyphShapeChanges']),sum(r['EmptyPass'] for r in noise),len(noise))
