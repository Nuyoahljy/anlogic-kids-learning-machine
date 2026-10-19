"""Field-backed numeric oracle and independent full-frame UI fixtures."""
from pathlib import Path
import hashlib,json,random,re
R=Path(__file__).resolve().parents[3];S=Path(__file__).parent
F=R/'evidence/sc520-color-integration/fixtures';F.mkdir(parents=True,exist_ok=True)
FIELD=Path('E:/juan/FPGA/learning/sc520-validation/evidence/rgb-recognition-20261018/received')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def classify(rgb):
 ranked=sorted(enumerate(rgb),key=lambda x:x[1],reverse=True);total=sum(rgb)
 return ranked[0][0]+1 if total and 100*(ranked[0][1]-ranked[1][1])>=3*total else 0
def saturated(rgb):
 # Exact rational reference evaluated with Python unbounded signed integers.
 weighted=sum(x*c for x,c in zip(rgb,[77,150,29]))
 return tuple(max(0,min(255,(1280*x-weighted+512)//1024)) for x in rgb)
def packed(rgb):return rgb[0]<<16|rgb[1]<<8|rgb[2]
rows=json.loads((FIELD/'corrected-per-frame.json').read_text())['stage2'];vectors=[];inputs=[];counts={}
rois={'blue':(40,65,80,105),'yellow':(124,65,164,105),'red':(234,65,274,105)}
for row in rows:
 p=FIELD/Path(row['path']);p=p/'frame.rgb';data=p.read_bytes();inputs.append({'Path':str(p),'SHA256':sha(p)})
 for color,(x0,y0,x1,y1) in rois.items():
  tally=counts.setdefault(color,[0,0,0,0])
  for y in range(y0,y1):
   for x in range(x0,x1):
    rgb=tuple(data[(y*320+x)*3:(y*320+x)*3+3]);cid=classify(rgb);tally[cid]+=1;vectors.append((rgb,cid,saturated(rgb)))
seed=random.Random(260019)
for _ in range(65536):
 rgb=tuple(seed.randrange(256) for _ in range(3));vectors.append((rgb,classify(rgb),saturated(rgb)))
for v in range(256):
 for rgb in [(v,v,v),(v,0,0),(0,v,0),(0,0,v),(v,v,0),(v,0,v),(0,v,v)]:vectors.append((rgb,classify(rgb),saturated(rgb)))
for rgb in [(35,32,33),(34,33,33),(0,0,0),(255,255,255),(1,0,0),(255,255,0),(0,255,0)]:vectors.append((rgb,classify(rgb),saturated(rgb)))
(F/'numeric.mem').write_text(''.join(f'{(packed(rgb)<<26)|(cid<<24)|packed(sat):013X}\n' for rgb,cid,sat in vectors),encoding='ascii')
# Use the first real stage2 frame ROI means for blue/yellow/red input swatches.
swatches=[tuple(round(x) for x in rows[0]['patches'][c]['mean_rgb']) for c in ['red','yellow','blue']]+[(112,112,112)]
assert [classify(c) for c in swatches]==[1,2,3,0]
(F/'numeric-meta.json').write_text(json.dumps({'Count':len(vectors),'FieldPixelCounts':counts,'Sources':inputs,'Swatches':swatches,'GeneratorSHA256':sha(Path(__file__))},indent=2)+'\n',encoding='utf-8')
source=(S/'generate-audio22-fixtures.py').read_text(encoding='utf-8')
source=source.replace("ASSET=ROOT/'assets/templates/sc520-card-recognition/audio22'",f"ASSET=Path({str(F)!r})")
source=source.replace("(ASSET/'font-extension.json')","(ROOT/'assets/templates/sc520-card-recognition/audio22/font-extension.json')")
source=source.replace('D0220','D0260')
source=source.replace('[0xc04020,0xc0b030,0x3050c0,0x607080]',str([packed(saturated(c)) for c in swatches]))
scope={'__name__':'color26_fixture','__file__':str(S/'generate-audio22-fixtures.py')};exec(compile(source,'independent_ui_fixture','exec'),scope);scope['main']()
tb=(R/'fpga/sim/sc520-card-recognition/timing23/tb_timing23_render.sv').read_text(encoding='utf-8').replace('tb_timing23_render','tb_color26_render').replace('pixel23_compositor','pixel26_compositor')
for old,new in zip(['c04020','c0b030','3050c0','607080'],[f'{packed(c):06x}' for c in swatches]):tb=tb.replace(old,new)
(R/'fpga/sim/sc520-color-integration/tb_color26_render.sv').write_text(tb,encoding='utf-8',newline='\n')
# Reuse reset/transport contracts; independently adjust only the numeric oracle.
p=R/'fpga/sim/sc520-color-integration/tb_color26_reset.sv'
tb=(R/'fpga/sim/sc520-card-recognition/timing23/tb_timing23_reset.sv').read_text(encoding='utf-8').replace('tb_timing23_reset','tb_color26_reset').replace('pixel23_pipeline','pixel26_pipeline').replace('pixel14_color_pipeline','pixel26_color_pipeline')
start=tb.index('          if(frame_kind==0)expected[');end=tb.index('\n        end',start)
tb=tb[:start]+'          expected[input_groups]=tone_word(src_rgb);'+tb[end:]
tb=tb.replace('    integer byte_index;\n    begin for(byte_index=0;byte_index<12;byte_index++)tone_word[byte_index*8+:8]=curve(value[byte_index*8+:8]);end','''    integer byte_index;reg [95:0] wb;
    begin wb=wb_word(value);for(byte_index=0;byte_index<12;byte_index++)tone_word[byte_index*8+:8]=curve(wb[byte_index*8+:8]);end''')
tb=tb.replace('  function [95:0] tone_word', '''  function [95:0] wb_word(input [95:0] value);
    integer i,gain,product;
    begin for(i=0;i<12;i++)begin
      gain=(i%3==0)?333:(i%3==2)?304:256;
      product=(value[i*8+:8]*gain)/256;
      wb_word[i*8+:8]=product>255?255:product;
    end end
  endfunction
  function [95:0] tone_word''')
tb=tb.replace('diag_post_wb===raw_expected[output_groups]','diag_post_wb===wb_word(raw_expected[output_groups])').replace('at unit WB','at fixed field WB')
tb=tb.replace('diag_gain_r==256 && diag_gain_b==256','diag_gain_r==304 && diag_gain_b==333').replace('color.gain_r==256 && color.gain_b==256','color.gain_r==304 && color.gain_b==333').replace('freezes unit WB','freezes field WB')
tb=tb.replace('color_diag_packet[412:404]==256 && color_diag_packet[421:413]==256','color_diag_packet[412:404]==304 && color_diag_packet[421:413]==333')
tb=tb.replace('  task frame(input integer kind','  reg [95:0] center_wb,paper_wb;\n  task frame(input integer kind')
tb=tb.replace('        ck(color_diag_packet[55:32]', '        center_wb=wb_word(raw_expected[360*320+160]);paper_wb=wb_word(raw_expected[148*320+49]);\n        ck(color_diag_packet[55:32]')
tb=tb.replace('color_diag_packet[79:56]===raw_expected[360*320+160][95:72]','color_diag_packet[79:56]===center_wb[95:72]').replace('color_diag_packet[151:128]===raw_expected[148*320+49][95:72]','color_diag_packet[151:128]===paper_wb[95:72]')
p.write_text(tb,encoding='utf-8',newline='\n')
print('COLOR26_FIXTURES',len(vectors),counts,swatches)
