"""Generate only extra T027 tests and independent D0270 UI reference images."""
from pathlib import Path
import hashlib,json
R=Path(__file__).resolve().parents[3]
S=Path(__file__).parent
T=R/'fpga/sim/sc520-shape27'
F=R/'evidence/sc520-shape27/render-fixtures'
assert not F.exists() or not any(F.iterdir()),"Refuse to overwrite existing T027 reference images"
F.mkdir(parents=True,exist_ok=True)
source=(S/'generate-audio22-fixtures.py').read_text(encoding='utf-8')
swatches=json.loads((R/'evidence/sc520-color-integration/fixtures/numeric-meta.json').read_text())['Swatches']
def saturation(rgb):
    weighted=sum(v*c for v,c in zip(rgb,[77,150,29]))
    return tuple(max(0,min(255,(1280*v-weighted+512)//1024)) for v in rgb)
packed=lambda rgb:(rgb[0]<<16)|(rgb[1]<<8)|rgb[2]
source=source.replace("ASSET=ROOT/'assets/templates/sc520-card-recognition/audio22'",f"ASSET=Path({str(F)!r})")
source=source.replace("(ASSET/'font-extension.json')","(ROOT/'assets/templates/sc520-card-recognition/audio22/font-extension.json')")
source=source.replace('D0220','D0270').replace('[0xc04020,0xc0b030,0x3050c0,0x607080]',str([packed(saturation(c)) for c in swatches]))
scope={'__name__':'shape27_fixture','__file__':str(S/'generate-audio22-fixtures.py')}
exec(compile(source,'independent_shape27_ui_fixture','exec'),scope)
scope['main']()
render=(R/'fpga/sim/sc520-color-integration/tb_color26_render.sv').read_text()
render=render.replace('tb_color26_render','tb_shape27_render')
render=render.replace('pixel26_compositor #(','pixel26_compositor #(.VERSION(16\'h0270),')
(T/'tb_shape27_render.sv').write_text(render,encoding='utf-8',newline='\n')

s=(T/'tb_shape27_scenes.sv').read_text().replace('tb_shape27_scenes','tb_shape27_lifecycle')
s=s.replace('.RENDER_ENABLE(0)', '.RENDER_ENABLE(0),.COLOR_DIAGNOSTICS(1)')
s=s.replace('.TIMEOUT_MS(500)', '.TIMEOUT_MS(100)')
s=s.replace('diag_pre_wb=0,diag_post_wb=0','diag_pre_wb=in_rgb96,diag_post_wb=in_rgb96')
s=s.replace('diag_gain_r=0,diag_gain_b=0','diag_gain_r=304,diag_gain_b=333')
s=s.replace('diag_pixel_id=0,diag_stats_id=0','diag_pixel_id=in_frame_id,diag_stats_id=in_done_id')
s=s.replace('wire diag_stats_event=0,diag_stats_good=0','reg synthetic_stats_event=0;\n  wire diag_stats_event=synthetic_stats_event,diag_stats_good=in_frame_good')
s=s.replace('start_frame;pixels(720);in_frame_done=1;in_frame_good=good;\n      in_done_id=tag;in_done_source_test=in_source_test;',
'''start_frame;pixels(720);
      in_done_id=tag;in_done_source_test=in_source_test;in_frame_good=good;
      synthetic_stats_event=1;@(negedge capture_clk);
      synthetic_stats_event=0;@(negedge capture_clk);in_frame_done=1;''')
start=s.index('  initial begin\n    unused=$value$plusargs')
s=s[:start]+r'''
  integer expected_raw=0,raw_events=0,prior_raw=0,diagnostic_checks=0,fi;
  always @(posedge capture_clk)begin
    #1;
    if(rst_n && dut.raw_diag_event)begin
      raw_events++;
      ck(dut.raw_diag_good && dut.raw_diag_id==tag &&
         dut.raw_diag_source==in_source_test,"raw candidate requires same complete frame and source");
      ck(dut.raw_diag_item==expected_raw,"D0270 raw candidate retains public color+shape 1..9 meaning");
    end
  end
  task qualified_frames(input integer item,input string name,input bit fresh);
    begin
      expected_raw=item;load_raster(name);
      for(fi=0;fi<3;fi++)begin
        prior_raw=raw_events;frame(1);
        ck(raw_events==prior_raw+1,"exactly one raw geometry-qualified candidate per complete frame");
        ck(last_present && last_valid==(item!=0 && (!fresh || fi==2)) &&
           last_item==((item!=0 && (!fresh || fi==2))?item:0),"three-frame confirmation after color+shape combination");
        ck(color_diag_fresh && !color_diag_fault && color_diag_packet[780] &&
           color_diag_packet[31:0]==tag,"diagnostic packet is complete and belongs to acquisition frame");
        ck(color_diag_packet[682:679]==item && color_diag_packet[738:735]==last_item,
           "rendered RB and final item expose different confirmation stages with original item meaning");
        diagnostic_checks++;
      end
    end
  endtask
  initial begin
    unused=$value$plusargs("INJECT_FAULT=%d",inject_fault);
    if(!$value$plusargs("ASSET_ROOT=%s",root_path))$fatal(1,"ASSET_ROOT required");
    repeat(6)@(negedge capture_clk);rst_n=1;settle;pulse_key(1);
    for(integer item=1;item<=9;item++)begin
      begin_case($sformatf("all nine raw color+shape IDs, item%0d",item));
      clear_epoch;qualified_frames(item,$sformatf("block_%0d_gray25",item),1);
    end
    begin_case("same color changing complete shape starts fresh confirmation");
    qualified_frames(8,"block_8_wrong25",1);
    qualified_frames(9,"block_9_wrong25",1);
    begin_case("present gray withdraws stable result; colored square needs three fresh frames");
    qualified_frames(0,"gray",1);
    qualified_frames(2,"block_2_gray25",1);
    begin_case("source epoch change restarts confirmation without mixing source IDs");
    clear_epoch;in_source_test=1;qualified_frames(2,"block_2_wrong25",1);
    clear_epoch;in_source_test=0;qualified_frames(2,"block_2_gray25",1);
    begin_case("bad external EOF withdraws stable result; full healthy recovery is fresh");
    previous=revoke_events;frame(0);
    ck(revoke_events>previous && !obs_valid,"bad EOF cannot retain earlier stable square");
    clear_epoch;qualified_frames(2,"block_2_wrong25",1);
    begin_case("reset assertion clears stable candidate and pending pair asynchronously");
    @(negedge capture_clk);rst_n=0;#0.1;
    ck(dut.guarded_block_confirmation.raw_pending===0 &&
       dut.guarded_block_confirmation.raw_record===0 && !obs_valid,"reset clears shape/color pending association");
    repeat(8)@(negedge capture_clk);rst_n=1;settle;
    qualified_frames(2,"block_2_gray25",1);
    ck(diagnostic_checks==51,"all expected complete raw and final diagnostic pairs were checked");
    test_done=1;$display("DONE lifecycle errors=%0d checks=%0d scenarios=%0d raw_events=%0d diagnostic_pairs=%0d",
      errors,checks,scenarios,raw_events,diagnostic_checks);$finish;
  end
  initial begin #2000000000;$display("WATCHDOG lifecycle");$finish;end
endmodule
'''
(T/'tb_shape27_lifecycle.sv').write_text(s,encoding='utf-8',newline='\n')
print('T027 extra testbench and independent D0270 full-frame references generated')
