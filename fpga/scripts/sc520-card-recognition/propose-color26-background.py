"""Evaluate a boundary chroma-envelope gate without editing production RTL."""
from pathlib import Path
import hashlib,importlib.util,json
import numpy as np
from PIL import Image
R=Path(__file__).resolve().parents[3];S=Path(__file__).parent;E=R/'evidence/sc520-color-integration';O=E/'background-proposal-v2';O.mkdir(parents=True,exist_ok=False)
spec=importlib.util.spec_from_file_location('rotation',S/'scene-rotation-model.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
old_analyze=m.base.analyze;old_block=m.base.block_classify
source=(S/'scene-model.py').read_text();needle='    connected = np.zeros((height, width), dtype=bool)'
extra='''    rg=rgb[:,:,0].astype(np.int16)-rgb[:,:,1].astype(np.int16)
    bg=rgb[:,:,2].astype(np.int16)-rgb[:,:,1].astype(np.int16)
    similar &= (rg>=int(rg[border].min())-8)&(rg<=int(rg[border].max())+8)&(bg>=int(bg[border].min())-8)&(bg<=int(bg[border].max())+8)
'''
assert source.count(needle)==1;scope={};exec(compile(source.replace(needle,extra+needle),'chroma_envelope_model','exec'),scope);new_analyze=scope['analyze']
def normalized_block(rgb,present=True):
 # Retain original area/bbox/shape decisions; substitute just per-pixel labels.
 saved=np.asarray(rgb,dtype=np.int16);channels=np.moveaxis(saved,-1,0);total=channels.sum(axis=0);maximum=channels.max(axis=0);second=np.sort(channels,axis=0)[1];winner=channels.argmax(axis=0)
 good=(total>0)&(100*(maximum-second)>=3*total)
 synthetic=np.full_like(saved,255)
 for k,c in enumerate([(215,61,60),(245,205,45),(50,112,205)]):synthetic[good&(winner==k)]=c
 return old_block(synthetic,present)
def rgbread(p):
 x=np.loadtxt(p,dtype=np.uint32,converters=lambda x:int(x,16)).reshape(180,320)
 return np.stack([x>>16,(x>>8)&255,x&255],axis=-1).astype(np.uint8)
bank=m.read_bank(R/'assets/templates/sc520-card-recognition/rotation-v1/templates.mem')
def inspect(frame,scene_fn,block_fn):
 m.base.analyze=scene_fn;m.base.block_classify=block_fn;r=m.recognize(frame,bank)
 return {k:r[k] for k in ['item','present','scene_count','glyph_count','paper_count','paper_route','shape','conflict']}
field=[];manifest=json.loads((E/'scenes/manifest.json').read_text())
for c in manifest['Cases']:
 f=rgbread(Path(c['Path']));before=inspect(f,old_analyze,normalized_block);after=inspect(f,new_analyze,normalized_block)
 field.append({'Case':c['Name'],'TruthItem':c['Item'],'TruthPresent':c['Present'],'Before':before,'After':after,'Pass':after['item']==c['Item'] and after['present']==c['Present']})
legacy=[];A=R/'assets/templates/sc520-card-recognition/rotation-v1';cases=json.loads((A/'fixtures.json').read_text())
for c in cases:
 p=A/'vectors'/(c['prefix']+'.rgb.mem');f=rgbread(p) if p.exists() else np.asarray(Image.open(p.with_suffix('').with_suffix('.png')).convert('RGB'));before=inspect(f,old_analyze,old_block);after=inspect(f,new_analyze,old_block)
 legacy.append({'Case':c['prefix'],'Before':before,'After':after,'SameOutput':before['item']==after['item'] and before['present']==after['present'],'SameScene':before==after})
result={'ProductionRTLChanged':False,'MarginDN':8,'Method':'Original RGB +/-48 AND current boundary R-G / B-G min..max envelope expanded by8','FieldCases':field,'FieldPass':sum(c['Pass'] for c in field),'LegacyCases':legacy,'LegacyOutputChanges':[c for c in legacy if not c['SameOutput']],'LegacySceneChanges':[c for c in legacy if not c['SameScene']]}
(O/'proposal.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8');print(json.dumps({'FieldPass':result['FieldPass'],'FieldTotal':len(field),'FieldFailures':[c['Case'] for c in field if not c['Pass']],'LegacyTotal':len(legacy),'LegacyOutputChanges':len(result['LegacyOutputChanges']),'LegacySceneChanges':len(result['LegacySceneChanges'])}))
