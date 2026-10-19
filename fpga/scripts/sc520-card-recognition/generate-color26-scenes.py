"""Preserve old shape geometry while substituting actual measured stage2 texture."""
from pathlib import Path
import hashlib,json
import numpy as np
R=Path(__file__).resolve().parents[3];F=R/'evidence/sc520-color-integration/scenes';F.mkdir(parents=True,exist_ok=True)
A=R/'assets/templates/sc520-card-recognition/rotation-v1';rows=json.loads((A/'fixtures.json').read_text())
FIELD=Path('E:/juan/FPGA/learning/sc520-validation/evidence/rgb-recognition-20261018/received')
first=json.loads((FIELD/'corrected-per-frame.json').read_text())['stage2'][0];field_path=FIELD/first['path']/'frame.rgb';field=np.frombuffer(field_path.read_bytes(),dtype=np.uint8).reshape(180,320,3)
rois=[(234,65,274,105),(124,65,164,105),(40,65,80,105)];cases=[]
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def write(name,rgb,item,present,source=None,recipe=''):
 p=F/(name+'.rgb.mem');p.write_text(''.join(f'{r:02X}{g:02X}{b:02X}\n' for r,g,b in rgb.reshape(-1,3)),encoding='ascii')
 cases.append({'Name':name,'Item':item,'Present':present,'Path':str(p),'SHA256':digest(p),'Source':str(source) if source else None,'SourceSHA256':digest(source) if source else None,'Recipe':recipe})
for row in rows:
 item=row['truth_item']
 if row['category']=='block' and 1<=item<=9:
  p=A/'vectors'/(row['prefix']+'.rgb.mem');packed=np.array([int(x,16) for x in p.read_text().split()],dtype=np.uint32).reshape(180,320)
  rgb=np.stack([packed>>16,(packed>>8)&255,packed&255],axis=-1).astype(np.uint8)
  # Existing fixture's uniform saturated object color is exactly the least
  # frequent non-neutral saturated color, and must form a nonempty region.
  colors,counts=np.unique(rgb.reshape(-1,3),axis=0,return_counts=True)
  candidates=[tuple(c) for c in colors if int(max(c))-int(min(c))>100]
  assert len(candidates)==1,(row['prefix'],candidates)
  mask=np.all(rgb==candidates[0],axis=-1);assert mask.sum()>100
  color=(item-1)//3;x0,y0,x1,y1=rois[color];texture=field[y0:y1,x0:x1]
  y,x=np.nonzero(mask);rgb[y,x]=texture[(y-y.min())%40,(x-x.min())%40]
  write('field_block_'+str(item),rgb,item,True,p,'Original shape mask/background; actual first stage2 ROI texture tiled without smoothing. Synthetic scene, not new field capture.')
for item in range(10,15):
 row=next(x for x in rows if x['truth_item']==item and x['prefix'].endswith('angle_0'))
 p=A/'vectors'/(row['prefix']+'.rgb.mem');v=np.array([int(x,16) for x in p.read_text().split()],dtype=np.uint32).reshape(180,320)
 rgb=np.stack([v>>16,(v>>8)&255,v&255],axis=-1).astype(np.uint8);write('card_'+str(item),rgb,item,True,p,'Original stage2 classifier fixture bytes unchanged.')
for name,color in [('black',(0,0,0)),('white',(255,255,255)),('gray',(112,112,112)),('red',(116,96,89)),('yellow',(147,172,118)),('blue',(80,93,110)),('green',(0,255,0))]:
 write('empty_'+name,np.full((180,320,3),color,dtype=np.uint8),0,False,recipe='Uniform entire raster; existing scene background must reject foreground even when pixels classify.')
(F/'cases.txt').write_text(''.join(f'{c["Item"]} {int(c["Present"])} {c["Name"]}\n' for c in cases),encoding='ascii')
(F/'manifest.json').write_text(json.dumps({'FieldSource':str(field_path),'FieldSHA256':digest(field_path),'Cases':cases,'GeneratorSHA256':digest(Path(__file__))},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
tb=(R/'fpga/sim/sc520-color-integration/tb_color26_pipeline.sv').read_text();tb=tb[:tb.index('  function [559:0] test_map;')].replace('tb_color26_pipeline','tb_color26_scenes')
tb+='''
  assign audio_idle=1'b1;assign audio_fault=1'b1;
  initial begin
    unused=$value$plusargs("INJECT_FAULT=%d",inject_fault);
    if(!$value$plusargs("ASSET_ROOT=%s",root_path))$fatal(1,"ASSET_ROOT required");
    repeat(6)@(negedge capture_clk);rst_n=1;settle;pulse_key(1);
    fd=$fopen({root_path,"/cases.txt"},"r");if(!fd)$fatal(1,"cases missing");
    bfd=$fopen("scene-results.csv","w");$fwrite(bfd,"case,frame,item,valid,present,count,scene,glyph,paper,shape\\n");
    while(!$feof(fd))begin
      fields=$fscanf(fd,"%d %d %s\\n",want_item,want_present,prefix);
      if(fields==3)begin
        begin_case(prefix);clear_epoch;load_raster(prefix);
        for(i=0;i<3;i++)begin
          frame(1);
          if(inject_fault && injected==0 && i==2)begin force dut.obs_item=15;injected=1;#1;ck(obs_item==want_item,"live output injection is detected");release dut.obs_item;end
          ck(last_present==want_present,"full scene occupancy from independent geometric construction");
          ck(last_valid==(want_item!=0&&i==2) && last_item==(i==2?want_item:0),"three-frame confirmed shape/card truth");
          $fwrite(bfd,"%s,%d,%d,%d,%d,%d,%d,%d,%d,%d\\n",prefix,i,last_item,last_valid,last_present,last_count,dut.scene_pixels,dut.glyph_pixels,dut.paper_pixels,dut.shape_ok);
        end
      end else if(fields!=-1)$fatal(1,"invalid scene row");
    end
    $fclose(fd);$fclose(bfd);test_done=1;$display("DONE scenes checks=%d errors=%d",checks,errors);$finish;
  end
  initial begin #2000000000;$display("WATCHDOG scenes");$finish;end
endmodule
'''
(R/'fpga/sim/sc520-color-integration/tb_color26_scenes.sv').write_text(tb,encoding='utf-8',newline='\n')
print('SCENES_CREATED',len(cases))
