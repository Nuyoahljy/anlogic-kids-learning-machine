"""Independent guard cases from the frozen scene-v2 images plus exact masks."""
from pathlib import Path
import datetime, hashlib, importlib.util, json, math
import numpy as np
from PIL import Image
import block_shape_model as guard
HERE=Path(__file__).resolve().parent;REPO=HERE.parents[2]
SCENE=REPO/'assets/templates/sc520-card-recognition/scene-v2'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def array_sha(x):return hashlib.sha256(np.ascontiguousarray(x).tobytes()).hexdigest().upper()
def save(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def main():
    modulepath=REPO/'fpga/scripts/sc520-card-recognition/scene-model.py'
    spec=importlib.util.spec_from_file_location('scene_guard_input',modulepath);scene=importlib.util.module_from_spec(spec);spec.loader.exec_module(scene)
    rows=json.loads((SCENE/'fixtures.json').read_text());manifest=json.loads((SCENE/'manifest.json').read_text())
    outputs={x['path'].replace('\\','/'):x['sha256'] for x in manifest['outputs']}
    assert sha(SCENE/'fixtures.json')==outputs['fixtures.json']
    cases=[];source_rows=[];matrix=[]
    def add(name,mask,kind,block_item=0,truth_item=0):
        result=guard.classify(mask);cases.append({'index':len(cases),'name':name,'kind':kind,'block_item':block_item,
          'truth_item':truth_item,**result,'gated_item':guard.gate(block_item,mask),'mask':np.asarray(mask,dtype=np.uint8).reshape(-1).tolist()})
    for shape,mask in enumerate(guard.templates(),1):
        add(f'analytic_shape_{shape}',mask,'analytic',shape,shape)
        for errors in [1,19,20,21,40]:
            altered=mask.copy().reshape(-1)
            # Flip distinct full-address pixels, including padding, to check
            # that every bit participates in the 1024-bit distance.
            altered[np.arange(errors)]=~altered[np.arange(errors)]
            add(f'analytic_shape_{shape}_flip{errors}',altered.reshape(32,32),'threshold_boundary',shape,shape)
    add('empty',np.zeros((32,32),bool),'negative')
    add('full1024',np.ones((32,32),bool),'negative')
    for shape,mask in enumerate(guard.templates(),1):
        hole=mask.copy();hole[12:20,12:20]=False;add(f'shape_{shape}_hole8',hole,'hole_negative',shape,0)
    for row in rows:
        if not row['required'] or not row['block_item']:continue
        image=SCENE/'vectors'/f"{row['prefix']}.png"
        assert sha(image)==outputs[image.relative_to(SCENE).as_posix()]
        frame=np.asarray(Image.open(image).convert('RGB'))
        analysis=scene.analyze(scene.sample_frame(frame));mask=analysis['mask']
        assert array_sha(mask)==row['mask_sha256'],row['prefix']
        add(row['prefix'],mask,'scene_'+row['category'],row['block_item'],row['truth_item'])
        source_rows.append({'path':str(image),'sha256':sha(image),'mask_sha256':row['mask_sha256']})
    scene_cases=[x for x in cases if x['kind'].startswith('scene_')]
    positives=[x for x in scene_cases if 1<=x['truth_item']<=9]
    negatives=[x for x in scene_cases if not 1<=x['truth_item']<=9]
    assert len(positives)==81 and len(negatives)==138
    assert all(x['gated_item']==x['truth_item'] for x in positives)
    assert all(x['gated_item']==0 for x in negatives)
    # Independent rasterized ideal blocks over scale and small angle. These
    # are measurements, not hard-coded acceptance claims for rotated blocks.
    for shape in range(3):
      for side in [16,20,28,40,56]:
       for angle in [-15,-10,-5,-2,0,2,5,10,15]:
        yy,xx=np.mgrid[0:80,0:80];xf=xx+0.5-40;yf=yy+0.5-40
        ca=math.cos(math.radians(angle));sa=math.sin(math.radians(angle))
        rx=ca*xf+sa*yf;ry=-sa*xf+ca*yf;half=side/2
        if shape==0:raw=rx*rx+ry*ry<=half*half
        elif shape==1:raw=(np.abs(rx)<half)&(np.abs(ry)<half)
        else:raw=(ry>=-half)&(ry<half)&(2*np.abs(rx)<=ry+half)
        mask=scene.normalize(raw)
        c=guard.classify(mask);matrix.append({'shape':shape+1,'side_grid_cells':side,'angle_degrees':angle,**c})
        add(f'ideal_s{shape+1}_size{side}_angle{angle:+d}',mask,'rotation_measurement',shape+1,shape+1)
    # One compact text file is a native RTL input: count, then each index,
    # expected bitset and all distances, followed by 1024 numeric bits.
    with (HERE/'cases.txt').open('w',encoding='ascii') as f:
        f.write(str(len(cases))+'\n')
        for x in cases:
            f.write(f"{x['index']} {x['shape_bits']} {' '.join(map(str,x['distance']))}\n")
            f.write(' '.join(map(str,x['mask']))+'\n')
    for x in cases:x.pop('mask')
    save(HERE/'cases.json',cases);save(HERE/'rotation-measurements.json',matrix)
    report={'created_at':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
      'threshold':20,'comparison_bits':1024,'active_region':[6,6,20,20],'case_count':len(cases),
      'scene_true_blocks':len(positives),'scene_false_block_candidates':len(negatives),
      'true_block_max_matching_distance':max(x['distance'][(x['truth_item']-1)%3] for x in positives),
      'false_block_min_matching_distance':min(x['distance'][(x['block_item']-1)%3] for x in negatives),
      'false_block_min_any_distance':min(min(x['distance']) for x in negatives),
      'true_blocks_preserved':sum(x['gated_item']==x['truth_item'] for x in positives),
      'false_blocks_rejected':sum(x['gated_item']==0 for x in negatives),
      'source_images':source_rows,'sources':[{'path':str(p),'sha256':sha(p)} for p in [modulepath,SCENE/'manifest.json',SCENE/'fixtures.json',HERE/'block_shape_model.py',Path(__file__).resolve()]],
      'outputs':[{'path':str(HERE/name),'sha256':sha(HERE/name)} for name in ['cases.txt','cases.json','rotation-measurements.json']],
      'limits':['Frozen v2 synthetic scene masks, not camera measurements.','Rotation measurements are separate from the 81 original block acceptance cases.','Small holes/contour noise up to the Hamming budget can pass by design; this is approximate shape evidence, not universal convexity proof.']}
    save(HERE/'model-report.json',report)
    print(json.dumps({k:v for k,v in report.items() if not isinstance(v,list)}))
if __name__=='__main__':main()
