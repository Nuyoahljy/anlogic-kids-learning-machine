"""Historical initial fixture/bootstrap generator; never overwrite resumed tests."""
from pathlib import Path
import json,hashlib,numpy as np
R=Path(__file__).resolve().parents[3];S=Path(__file__).parent
if (R/'fpga/sim/sc520-shape27/tb_shape27_scenes.sv').exists():
 raise SystemExit('Historical bootstrap is retired for an existing T027 tree; use committed tests and immutable fixture manifests.')
F=R/'evidence/sc520-shape27/fixtures';F.mkdir(parents=True,exist_ok=True)
T=R/'fpga/sim/sc520-shape27';T.mkdir(parents=True,exist_ok=True)
A=R/'assets/templates/sc520-card-recognition/rotation-v1'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def write(p,s):p.write_text(s,encoding='utf-8',newline='\n')
cases=[];colors=[(180,60,60),(140,180,50),(50,65,180)]
def save(name,rgb,item,present,recipe):
 p=F/(name+'.rgb.mem');write(p,''.join('%02X%02X%02X\n'%tuple(v) for v in rgb.reshape(-1,3)))
 cases.append(dict(Name=name,Item=item,Present=present,Path=str(p),SHA256=sha(p),Recipe=recipe))
rows=json.loads((A/'fixtures.json').read_text())
for item in range(1,10):
 row=next(r for r in rows if r['category']=='block' and r['truth_item']==item)
 src=A/'vectors'/(row['prefix']+'.rgb.mem');packed=np.array([int(x,16) for x in src.read_text().split()],np.uint32).reshape(180,320)
 rgb=np.stack([packed>>16,(packed>>8)&255,packed&255],-1).astype(np.uint8)
 unique=np.unique(rgb.reshape(-1,3),axis=0);object_colors=[c for c in unique if int(max(c))-int(min(c))>100];assert len(object_colors)==1
 mask=np.all(rgb==object_colors[0],axis=-1);yy,xx=np.indices(mask.shape);ci=(item-1)//3
 for mode in ['plain','gray20','gray25','wrong20','wrong25']:
  out=np.full_like(rgb,255);out[mask]=colors[ci]
  divisor=5 if mode.endswith('20') else 4
  damage=mask & (((xx//2)+3*(yy//2))%divisor==0)
  if mode.startswith('gray'):out[damage]=(96,96,96)
  if mode.startswith('wrong'):out[damage]=colors[(ci+1)%3]
  save(f'block_{item}_{mode}',out,item,True,f'Existing analytic shape silhouette {src.name}; all-white background; {mode} deterministic grid cells. Fully synthetic, NOT reconstructed JPEG or field RGB.')
 # Extra negatives anchored to square silhouette; present stays true.
 if item==2:
  for mode in ['gray','sparse_red','half_color','gray_external','square_external','clipped']:
   out=np.full_like(rgb,255);out[mask]=(96,96,96) if mode in ['gray','sparse_red','gray_external'] else colors[0]
   if mode=='sparse_red':out[mask & (((xx//2)+3*(yy//2))%5==0)]=colors[0]
   if mode=='half_color':out[mask & (((xx//2)+yy//2)%2==0)]=colors[1]
   if mode in ['gray_external','square_external']:
    # Isolated 2x2 input cells outside glyph; the existing neighbor filter rejects them.
    for x,y in [(64,54),(72,54),(64,62)]:out[y:y+2,x:x+2]=colors[0]
   if mode=='clipped':out[:]=255;out[30:94,100:164]=colors[0]
   save(mode,out,2 if mode=='square_external' else 0,True,'Synthetic negative/isolated-dot construction '+mode)
for item in range(10,15):
 row=next(r for r in rows if r['truth_item']==item and r['prefix'].endswith('angle_0'));src=A/'vectors'/(row['prefix']+'.rgb.mem')
 p=F/(f'card_{item}.rgb.mem');p.write_bytes(src.read_bytes());cases.append(dict(Name=f'card_{item}',Item=item,Present=True,Path=str(p),SHA256=sha(p),Recipe='Unchanged original independent card fixture '+str(src)))
for name,color in [('white',(255,255,255)),('gray',(96,96,96)),('black',(0,0,0)),('red',colors[0]),('yellow',colors[1]),('blue',colors[2])]:save('empty_'+name,np.full((180,320,3),color,np.uint8),0,False,'Uniform full raster')
write(F/'cases.txt',''.join(f'{c["Item"]} {int(c["Present"])} {c["Name"]}\n' for c in cases))
write(F/'manifest.json',json.dumps(dict(Cases=cases,GeneratorSHA256=sha(Path(__file__)),Synthetic=True),indent=2)+'\n')
for name,source in [('scenes','scenes_bg'),('pipeline','pipeline_bg'),('reset','reset_bg')]:
 s=(R/'fpga/sim/sc520-color-integration'/f'tb_color26_{source}.sv').read_text().replace(f'tb_color26_{source}',f'tb_shape27_{name}').replace('pixel26_bg_pipeline','pixel27_pipeline')
 if name=='scenes':
  s=s.replace('pixel27_pipeline #','`ifdef LEGACY_D0261\n  pixel26_bg_pipeline #\n`else\n  pixel27_pipeline #\n`endif\n')
  s=s.replace('paper,shape\\n','paper,shape,raw\\n').replace('%d,%d,%d,%d,%d,%d,%d,%d,%d\\n','%d,%d,%d,%d,%d,%d,%d,%d,%d,%d\\n').replace('dut.paper_pixels,dut.shape_ok);','dut.paper_pixels,dut.shape_ok,dut.block_item);')
 write(T/f'tb_shape27_{name}.sv',s)
s=(S/'simulate-color26.py').read_text().replace("choices=['numeric','pipeline','reset','render','scenes','pipeline_bg','reset_bg','scenes_bg','scene_oracle','block_pipe']","choices=['pipeline','reset','scenes','core']").replace("a=ap.parse_args()","ap.add_argument('--legacy',action='store_true');a=ap.parse_args()")
s=s.replace("rtl=sorted(new.glob('*.v'))","rtl=sorted(new.glob('*.v'))+sorted((R/'fpga/rtl/sc520-shape27').glob('*.v'))")
s=s.replace("tb=R/'fpga/sim/sc520-color-integration'/f'tb_color26_{a.test}.sv'","tb=R/'fpga/sim/sc520-shape27'/f'tb_shape27_{a.test}.sv'")
s=s.replace("evidence/sc520-color-integration/runs","evidence/sc520-shape27/runs").replace("scene_dir=a.scene_dir or R/'evidence/sc520-color-integration/scenes'","scene_dir=a.scene_dir or R/'evidence/sc520-shape27/fixtures'").replace("mode='negative' if a.negative else 'watchdog' if a.watchdog_probe else 'normal'","mode='legacy' if a.legacy else 'negative' if a.negative else 'watchdog' if a.watchdog_probe else 'normal'")
s=s.replace('tb_color26_{a.test}','tb_shape27_{a.test}').replace("rtl+[tb,Path(__file__).resolve(),HERE/'run-audio22.do']","rtl+[tb,Path(__file__).resolve(),HERE/'run-shape27.do']").replace('snap/"run-audio22.do"','snap/"run-shape27.do"').replace("set card_top tb_shape27_{a.test};","set card_legacy {int(a.legacy)}; set card_top tb_shape27_{a.test};")
s=s.replace("code=p.wait(timeout=900)","code=p.wait(timeout=1800)")
write(S/'simulate-shape27.py',s)
s=(S/'run-audio22.do').read_text().replace('    vlog -sv +incdir+$card_assets $card_tb','    if {$card_legacy} {vlog -sv +define+LEGACY_D0261 +incdir+$card_assets $card_tb} else {vlog -sv +incdir+$card_assets $card_tb}')
write(S/'run-shape27.do',s)
print('T027 fixtures',len(cases))
