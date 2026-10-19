"""Read-only production diagnosis; new white-background controls, never retune RTL."""
from pathlib import Path
import csv,hashlib,importlib.util,json
import numpy as np
from PIL import Image
R=Path(__file__).resolve().parents[3];E=R/'evidence/sc520-color-integration'
F=E/'scenes';O=E/'scene-diagnosis-v1';O.mkdir(parents=True,exist_ok=False);L=E/'scenes-white-v1';L.mkdir()
spec=importlib.util.spec_from_file_location('original_scene',Path(__file__).with_name('scene-model.py'));model=importlib.util.module_from_spec(spec);spec.loader.exec_module(model)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def rgbread(p):
 x=np.array([int(s,16) for s in p.read_text().split()],dtype=np.uint32).reshape(180,320)
 return np.stack([x>>16,(x>>8)&255,x&255],axis=-1).astype(np.uint8)
def summary(rgb):
 sampled=model.sample_frame(rgb);result=model.analyze(sampled)
 return sampled,result,{k:result[k] for k in ['background_rgb','present','scene_count','glyph_count','scene_bbox','glyph_bbox','border_similar','border_count','background_qualified','edge_contact']}
manifest=json.loads((F/'manifest.json').read_text());cases=[];lines=[]
for c in manifest['Cases']:
 if not c['Name'].startswith('field_block_'):continue
 item=c['Item'];p=Path(c['Path']);rgb=rgbread(p);old=rgbread(Path(c['Source']))
 colors=np.unique(old.reshape(-1,3),axis=0);fill=next(x for x in colors if int(max(x))-int(min(x))>100)
 mask=np.all(old==fill,axis=-1);sampled,result,s=summary(rgb);original_mask=model.sample_frame(np.repeat(mask[:,:,None],3,axis=2))[:,:,0].astype(bool)
 old_sample,old_result,old_s=summary(old)
 distance=np.abs(sampled.astype(np.int16)-np.array(s['background_rgb'])).max(axis=-1)
 object_dist=distance[original_mask]
 white=rgb.copy();white[~mask]=255;_,_,white_s=summary(white)
 name='white_'+c['Name'];q=L/(name+'.rgb.mem');q.write_text(''.join(f'{r:02X}{g:02X}{b:02X}\n' for r,g,b in white.reshape(-1,3)),encoding='ascii');lines.append(f'{item} 1 {name}\n')
 Image.fromarray(rgb).save(O/(c['Name']+'.png'))
 vis=np.repeat(result['scene'][:,:,None].astype(np.uint8)*255,3,axis=2);Image.fromarray(vis).resize((600,300)).save(O/(c['Name']+'-scene.png'))
 cases.append({'Case':c['Name'],'Item':item,'NewScene':s,'OriginalIdealColorScene':old_s,'WhiteControlScene':white_s,'SampledObjectPixels':int(original_mask.sum()),'ObjectWithinBackgroundTolerance48':int(np.count_nonzero(object_dist<=48)),'ObjectMaxChannelDistanceMinMedianMax':[int(object_dist.min()),float(np.median(object_dist)),int(object_dist.max())],'ObjectRGBMin':rgb[mask].min(axis=0).tolist(),'ObjectRGBMax':rgb[mask].max(axis=0).tolist(),'Source':c,'WhiteControl':{'Path':str(q),'SHA256':sha(q)}})
(L/'cases.txt').write_text(''.join(lines),encoding='ascii')
result={'ProductionRTLChanged':False,'BG_TOLERANCE':48,'SceneQuantization':'lower border median in 16-wide bins, center=bin*16+8','Reason':'Scene flood-fill admits boundary-connected pixels as background when every RGB channel is within48. New low-chroma colors can be consumed before normalized block classification.','Cases':cases,'Model':{'Path':str(Path(model.__file__)),'SHA256':sha(Path(model.__file__))},'SourceManifest':{'Path':str(F/'manifest.json'),'SHA256':sha(F/'manifest.json')}}
(O/'diagnosis.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
for c in cases:print(c['Item'],c['NewScene']['background_rgb'],c['SampledObjectPixels'],c['ObjectWithinBackgroundTolerance48'],c['NewScene']['scene_count'],c['WhiteControlScene']['scene_count'])
