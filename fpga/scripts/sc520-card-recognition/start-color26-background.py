"""Create a second candidate, preserving all files bound by the running 260 build."""
from pathlib import Path
R=Path(__file__).resolve().parents[3];S=Path(__file__).parent;P=R/'fpga/custom_project/sc520-color26-bg';RTL=R/'fpga/rtl/sc520-color-integration'
assert not P.exists()
def write(p,s):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s,encoding='utf-8',newline='\n')
for p in (R/'fpga/custom_project/sc520-color26/overlay').iterdir():
 s=p.read_text(encoding='utf-8')
 if p.name=='design_top_wrapper.v':s=s.replace('pixel26_pipeline #','pixel26_bg_pipeline #').replace("16'h0260","16'h0261")
 write(P/'overlay'/p.name,s)
write(P/'.gitattributes','* -text\n')
s=(RTL/'pixel26_pipeline.v').read_text().replace('module pixel26_pipeline','module pixel26_bg_pipeline').replace('pixel14_scene_preprocess #','pixel26_scene_preprocess #')
write(RTL/'pixel26_bg_pipeline.v',s)
s=(R/'fpga/rtl/sc520-card-recognition/pixel14/pixel14_scene_preprocess.v').read_text().replace('module pixel14_scene_preprocess','module pixel26_scene_preprocess')
s='// T026 background revision: per-frame border chroma envelope, margin4 DN.\n// Same raster, RAM, processing schedule, masks and interfaces as original.\n'+s
needle='    reg ready0,ready1,capture_active,capture_bank,process_bank;'
s=s.replace(needle,needle+'''\n    // All extrema belong to the same complete capture bank as RGB/histograms.
    reg signed [8:0] min_rg0,max_rg0,min_bg0,max_bg0;
    reg signed [8:0] min_rg1,max_rg1,min_bg1,max_bg1;
    wire signed [8:0] sample_rg=$signed({1'b0,in_rgb[23:16]})-$signed({1'b0,in_rgb[15:8]});
    wire signed [8:0] sample_bg=$signed({1'b0,in_rgb[7:0]})-$signed({1'b0,in_rgb[15:8]});
    wire signed [8:0] border_min_rg=process_bank ? min_rg1:min_rg0;
    wire signed [8:0] border_max_rg=process_bank ? max_rg1:max_rg0;
    wire signed [8:0] border_min_bg=process_bank ? min_bg1:min_bg0;
    wire signed [8:0] border_max_bg=process_bank ? max_bg1:max_bg0;
''')
s=s.replace('        reg [8:0] dr,dg,db;','''        reg [8:0] dr,dg,db;
        reg signed [9:0] rg,bg,low_rg,high_rg,low_bg,high_bg;''')
s=s.replace('            background_like=dr<=BG_TOLERANCE && dg<=BG_TOLERANCE && db<=BG_TOLERANCE;', '''            rg=$signed({2'b00,rgb[23:16]})-$signed({2'b00,rgb[15:8]});
            bg=$signed({2'b00,rgb[7:0]})-$signed({2'b00,rgb[15:8]});
            low_rg=$signed({border_min_rg[8],border_min_rg})-10'sd4;
            high_rg=$signed({border_max_rg[8],border_max_rg})+10'sd4;
            low_bg=$signed({border_min_bg[8],border_min_bg})-10'sd4;
            high_bg=$signed({border_max_bg[8],border_max_bg})+10'sd4;
            background_like=dr<=BG_TOLERANCE && dg<=BG_TOLERANCE && db<=BG_TOLERANCE &&
                rg>=low_rg && rg<=high_rg && bg>=low_bg && bg<=high_bg;''')
s=s.replace('            ready0<=0;ready1<=0;capture_active<=0;capture_bank<=0;process_bank<=0;', '''            ready0<=0;ready1<=0;capture_active<=0;capture_bank<=0;process_bank<=0;
            min_rg0<=0;max_rg0<=0;min_bg0<=0;max_bg0<=0;
            min_rg1<=0;max_rg1<=0;min_bg1<=0;max_bg1<=0;''')
s=s.replace('                ready0<=0;ready1<=0;capture_active<=0;capture_pixels<=0;capture_samples<=0;', '''                ready0<=0;ready1<=0;capture_active<=0;capture_pixels<=0;capture_samples<=0;
                min_rg0<=0;max_rg0<=0;min_bg0<=0;max_bg0<=0;
                min_rg1<=0;max_rg1<=0;min_bg1<=0;max_bg1<=0;''')
needle='                        if(sample_border) begin'
insert=''
for bank in [1,0]:
 insert+=('                            if(selected_bank) begin\n' if bank else '                            end else begin\n')
 for name,op in [('min_rg','<'),('max_rg','>'),('min_bg','<'),('max_bg','>')]:
  signal='sample_'+name[-2:]
  insert+=f'                                if(start_ok || capture_samples==0 || {signal}{op}{name}{bank}){name}{bank}<={signal};\n'
insert+='                            end\n'
s=s.replace(needle,needle+'\n'+insert)
write(RTL/'pixel26_scene_preprocess.v',s)
# New build writer and launch preserve the old candidate's source identity.
s=(S/'prepare-color26.py').read_text().replace("sc520-color26'","sc520-color26-bg'").replace("'prepare-color26.py','build-color26.ps1'","'prepare-color26-bg.py','build-color26-bg.ps1'")
write(S/'prepare-color26-bg.py',s)
s=(S/'build-color26.ps1').read_text().replace('prepare-color26.py','prepare-color26-bg.py')
write(S/'build-color26-bg.ps1',s)
for kind in ['reset','pipeline','scenes']:
 p=R/'fpga/sim/sc520-color-integration'/f'tb_color26_{kind}.sv'
 s=p.read_text().replace(f'tb_color26_{kind}',f'tb_color26_{kind}_bg').replace('pixel26_pipeline #','pixel26_bg_pipeline #')
 write(p.with_name(f'tb_color26_{kind}_bg.sv'),s)
print('NEW_BACKGROUND_CANDIDATE_CREATED')
