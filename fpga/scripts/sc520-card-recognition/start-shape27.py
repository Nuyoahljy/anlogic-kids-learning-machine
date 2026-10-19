"""Historical one-shot scaffold, superseded by the checked-in resumed sources.

Refuses an existing T027 tree. It is not a regeneration recipe for reviewed RTL.
"""
from pathlib import Path
import shutil
R=Path(__file__).resolve().parents[3]
old=R/'fpga/rtl/sc520-color-integration';new=R/'fpga/rtl/sc520-shape27'
new.mkdir(parents=True,exist_ok=False)
def write(p,s):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s,encoding='utf-8',newline='\n')
def once(s,a,b):assert s.count(a)==1,(a,s.count(a));return s.replace(a,b)
s=(old/'pixel26_scene_preprocess.v').read_text().replace('pixel26_scene_preprocess','pixel27_scene_preprocess')
s=once(s,'output reg replay_valid,replay_sof,replay_eol,','output reg replay_valid,replay_sof,replay_eol,\n    output reg replay_glyph, // same-cycle filtered glyph, with existing scene eligibility gates')
s=s.replace('replay_valid<=0;replay_sof<=0;replay_eol<=0;','replay_valid<=0;replay_sof<=0;replay_eol<=0;replay_glyph<=0;')
s=once(s,'replay_x<=scan_x;replay_y<=scan_y;replay_rgb<=','replay_glyph<=scene_present && !scene_clipped && !paper_route && mask_q[1];\n                        replay_x<=scan_x;replay_y<=scan_y;replay_rgb<=')
write(new/'pixel27_scene_preprocess.v',s)
s=(old/'pixel26_block_core.v').read_text().replace('pixel26_block_core','pixel27_color_core')
s=once(s,'input wire [1:0] in_color,','input wire [1:0] in_color,\n    input wire in_glyph,')
start=s.index('    reg [10:0] left_edge');end=s.index('    reg [3:0] candidate',start)
s=s[:start]+'''    reg [19:0] glyph_area;
    reg [1:0] selected_color;
    reg [19:0] selected_area;
    reg coverage_good;
'''+s[end:]
start=s.index('    wire [29:0] scaled_area');end=s.index('    wire same_candidate',start)
s=s[:start]+'''    // 22 bits hold 3 * (2^20-1); no truncation or division.
    wire [21:0] color_triple={1'b0,selected_area,1'b0}+{2'b00,selected_area};
    wire [21:0] glyph_double={1'b0,glyph_area,1'b0};
'''+s[end:]
s=s.replace('expected_x<=0;expected_y<=0;selected_color<=0;selected_area<=0;width<=0;height<=0;','expected_x<=0;expected_y<=0;selected_color<=0;selected_area<=0;glyph_area<=0;')
s=s.replace('geometry_good<=0;box_area<=0;candidate<=0;previous_item<=0;previous_source<=0;','coverage_good<=0;candidate<=0;previous_item<=0;previous_source<=0;')
s=s.replace('            selected_left<=0;selected_right<=0;selected_top<=0;selected_bottom<=0;\n','')
s=s.replace('for(k=0;k<3;k=k+1)begin area[k]<=0;left_edge[k]<=0;right_edge[k]<=0;top_edge[k]<=0;bottom_edge[k]<=0;end','for(k=0;k<3;k=k+1)area[k]<=0;')
s=s.replace('active<=0;stage<=0;pixels<=0;previous_item<=0;stable_count<=0;','active<=0;stage<=0;pixels<=0;previous_item<=0;stable_count<=0;glyph_area<=0;')
s=s.replace('active<=1;active_id<=in_frame_id;active_source<=in_source_test;pixels<=0;','active<=1;active_id<=in_frame_id;active_source<=in_source_test;pixels<=0;glyph_area<=0;')
start=s.index('                    if(roi && color!=0)begin');end=s.index('\n                end\n                if(in_frame_end)',start)
s=s[:start]+'''                    if(roi && in_glyph)begin
                        glyph_area<=(start_ok ? 0 : glyph_area)+1'b1;
                        if(color!=0)area[color-1]<=(start_ok ? 0 : area[color-1])+1'b1;
                    end'''+s[end:]
start=s.index('                    selected_left<=');end=s.index('                end else if(stage==5)',start)
s=s[:start]+'''                    stage<=2;
                end else if(stage==2)begin
                    coverage_good<=saved_present && selected_color!=0 && glyph_area>=MIN_AREA &&
                        selected_area<=glyph_area && color_triple>=glyph_double;
                    stage<=3;
                end else if(stage==3)begin
                    stage<=4;
                end else if(stage==4)begin
                    // Internal anchors 1/4/7 encode color only. The pipeline
                    // adds the unique complete-glyph shape after tag pairing.
                    candidate<=coverage_good ? (selected_color-1)*3+1 : 0;
                    stage<=5;
'''+s[end:]
s=s.replace('// Current-frame block candidate. Full raster health and full-resolution','// T027 color evidence, restricted to explicit complete-glyph mask.\n// No color-pixel bounding box or fill-ratio shape inference. Full raster health and full-resolution')
write(new/'pixel27_color_core.v',s)
s=(old/'pixel26_block_recognizer_piped.v').read_text().replace('pixel26_block_recognizer_piped','pixel27_color_recognizer').replace('pixel26_block_core','pixel27_color_core')
s=once(s,'input wire [23:0] in_rgb,','input wire [23:0] in_rgb,\n    input wire in_glyph,')
s=s.replace('[59:0] meta_a','[60:0] meta_a').replace('meta_a<={in_valid,','meta_a<={in_glyph,in_valid,').replace('wire v,s,e,fe,fg,fp,source;','wire glyph,v,s,e,fe,fg,fp,source;').replace('assign {v,s,e,fe,fg,fp,source,x,y,id}','assign {glyph,v,s,e,fe,fg,fp,source,x,y,id}').replace('.in_color(color),','.in_color(color),.in_glyph(glyph),')
write(new/'pixel27_color_recognizer.v',s)
s=(old/'pixel26_bg_pipeline.v').read_text().replace('pixel26_bg_pipeline','pixel27_pipeline').replace('pixel26_scene_preprocess','pixel27_scene_preprocess')
s=once(s,'wire sp_valid,sp_sof,sp_eol,sp_end,sp_good,sp_present,sp_source;','wire sp_valid,sp_sof,sp_eol,sp_end,sp_good,sp_present,sp_source;\n    wire sp_glyph;')
s=once(s,'.replay_rgb(sp_rgb),','.replay_rgb(sp_rgb),.replay_glyph(sp_glyph),')
s=once(s,'assign sp_x=bp_x;','assign sp_glyph=1\'b1;\n        assign sp_x=bp_x;')
# Keep the legacy non-scene path byte-for-byte in behavior.
start=s.index('    pixel26_block_recognizer_piped');end=s.index('    generate if(USE_SCENE_ANALYSIS) begin : shape_mode',start)
legacy=s[start:end];modern=legacy.replace('pixel26_block_recognizer_piped','pixel27_color_recognizer').replace('.in_rgb(sp_rgb),','.in_rgb(sp_rgb),.in_glyph(sp_glyph),')
s=s[:start]+'    generate if(USE_SCENE_ANALYSIS) begin : glyph_color_mode\n'+modern+'    end else begin : legacy_color_mode\n'+legacy+'    end endgenerate\n'+s[end:]
start=s.index('        wire shape_matches=');end=s.index('        always @(posedge capture_clk',start)
s=s[:start]+'''        wire [1:0] unique_shape=shape_ok==3'b001 ? 1 : shape_ok==3'b010 ? 2 : shape_ok==3'b100 ? 3 : 0;
        wire color_anchor=raw_record[44:41]==1 || raw_record[44:41]==4 || raw_record[44:41]==7;
        wire valid=healthy && raw_record[45] && color_anchor && unique_shape!=0;
        wire [3:0] combined_item=raw_record[44:41]+{2'b00,unique_shape}-1'b1;
'''+s[end:]
s=once(s,'.in_item(valid ? raw_record[44:41] : 4\'d0)','.in_item(valid ? combined_item : 4\'d0)')
write(new/'pixel27_pipeline.v',s)
project=R/'fpga/custom_project/sc520-shape27'
shutil.copytree(R/'fpga/custom_project/sc520-color26-bg/overlay',project/'overlay')
top=project/'overlay/design_top_wrapper.v';s=top.read_text().replace('pixel26_bg_pipeline','pixel27_pipeline').replace("16'h0261","16'h0270");write(top,s)
write(project/'.gitattributes','* text eol=lf\n')
scripts=Path(__file__).parent
s=(scripts/'prepare-color26-bg.py').read_text().replace('sc520-color26-bg','sc520-shape27').replace('prepare-color26-bg.py','prepare-shape27.py').replace('build-color26-bg.ps1','build-shape27.ps1').replace('T026','T027').replace('/root/color26_impl','/root/shape27_impl')
s=s.replace('sources += sorted((REPO/\'fpga/rtl/sc520-color-integration\').glob(\'*.v\'))','sources += sorted((REPO/\'fpga/rtl/sc520-color-integration\').glob(\'*.v\'))\\n    sources += sorted((REPO/\'fpga/rtl/sc520-shape27\').glob(\'*.v\'))')
write(scripts/'prepare-shape27.py',s)
s=(scripts/'build-color26-bg.ps1').read_text().replace('prepare-color26-bg.py','prepare-shape27.py').replace('evidence/sc520-color-integration','evidence/sc520-shape27').replace('T026','T027').replace('/root/color26_impl','/root/shape27_impl');write(scripts/'build-shape27.ps1',s)
s=(scripts/'generate-color26-bit.py').read_text().replace('evidence/sc520-color-integration','evidence/sc520-shape27').replace('d0261','d0270').replace('D0261','D0270');write(scripts/'generate-shape27-bit.py',s)
print('T027 source and isolated overlay created')
