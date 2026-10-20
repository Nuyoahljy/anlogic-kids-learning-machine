`timescale 1ns/1ps
// Boundary injection isolates identity, final competition and confirmation.
// Raster/scene/mask semantics are checked by the separate real RGB tests.
module tb_contour29_pairing;
  reg clk=0;always #5 clk=~clk;
  reg rst_n=0,flush=0,be=0,se=0,me=0,bh=1,sh=1,mh=1,source=0,match_source=0;
  reg [3:0] anchor=1;
  reg [31:0] tag=0,raw_tag=0,shape_tag=0,match_tag=0;
  reg [2:0] bits=1,original=1;
  reg negative=0,recovery=0,card_valid=0;
  reg [1:0] body_color=1;
  reg [10:0] recovery_distance=8,geometry_minimum=80,best=32;
  integer errors=0,checks=0,scenarios=0,injected=0;
  reg test_done=0;
  pixel29_pipeline #(.ENABLE_OUTPUT(1),.USE_SCENE_ANALYSIS(1),.ROTATION_VARIANTS(256),.RENDER_ENABLE(0)) dut(
    .rst_n(rst_n),.capture_clk(clk),.display_clk(clk),
    .in_frame_start(1'b0),.in_frame_id(32'd0),.in_source_test(1'b0),.in_valid(1'b0),.in_eol(1'b0),
    .in_rgb96(96'd0),.in_frame_done(1'b0),.in_frame_good(1'b1),.in_done_id(32'd0),.in_done_source_test(1'b0),
    .in_revoke(1'b0),.tick_1ms(1'b0),.flush(flush),.key_mode_pulse(1'b0),.key_replay_pulse(1'b0),
    .key_skip_pulse(1'b0),.key_reset_pulse(1'b0),.audio_idle(1'b1),.audio_fault(1'b1),.video_frame_start(1'b0),
    .pixel_x(11'd0),.pixel_y(10'd0),.video_vsync(1'b0),.video_hsync(1'b0),.video_de(1'b0),.video_rgb(24'd0),
    .diag_pre_wb(96'd0),.diag_post_wb(96'd0),.diag_gain_r(9'd304),.diag_gain_b(9'd333),
    .diag_pixel_id(32'd0),.diag_stats_id(32'd0),.diag_stats_event(1'b0),.diag_stats_good(1'b0),.diag_neutral_count(21'd0));
  task ck(input bit ok,input string message);
    begin checks++;if(!ok)begin errors++;$display("FAIL pairing case=%0d time=%0t %s",scenarios,$time,message);end end
  endtask
  task clear_epoch;
    begin @(negedge clk);be=0;se=0;me=0;flush=1;repeat(8)@(negedge clk);
      flush=0;repeat(40)@(negedge clk);end
  endtask
  task evidence(input integer expected_item,input integer expected_count,input integer fault,input integer delay_cycles);
    integer before_count;
    begin
      scenarios++;tag++;raw_tag=tag;shape_tag=tag;match_tag=tag;match_source=source;bh=1;sh=1;mh=1;
      if(fault==1)match_tag=tag+1;
      if(fault==2)match_source=!source;
      if(fault==5)bh=0;
      if(fault==6)sh=0;
      before_count=dut.confirmed_block_count;
      @(negedge clk);if(fault!=3)be=1;
      @(negedge clk);be=0;if(fault!=4)se=1;
      @(negedge clk);se=0;
      repeat(delay_cycles)begin @(posedge clk);#1;ck(dut.confirmed_block_count==before_count,"no block count before card/shape competition closes");@(negedge clk);end
      if(fault==7)begin
        ck(dut.guarded_block_confirmation.raw_pending,"dropped match retains unconsumed raw, never confirms");
        clear_epoch;
        ck(dut.confirmed_block_count==0 && !dut.guarded_block_confirmation.raw_pending,"flush cancels dropped transaction");
      end else begin
        me=1;#1;
        ck(dut.raw_diag_event,"one final candidate event at match completion");
        ck(dut.raw_diag_item==expected_item,"final geometry/card competition candidate");
        if(fault!=0)ck(dut.join_revoke && !dut.raw_diag_good,"missing or mismatched evidence revokes");
        @(posedge clk);#1;
        ck(dut.confirmed_block_count==expected_count,"only final qualified frames affect block count");
        ck(dut.confirmed_block_valid==(expected_count>=3) &&
           dut.confirmed_block_item==(expected_count>=3 ? expected_item:0),"original three-frame output boundary");
        @(negedge clk);me=0;repeat(40)@(negedge clk);
      end
    end
  endtask
  initial begin
    force dut.block_event=be;force dut.block_healthy=bh;force dut.block_present=1'b1;force dut.block_valid=1'b1;
    force dut.block_item=anchor;force dut.block_id=raw_tag;force dut.block_source=source;force dut.block_count=8'd1;
    force dut.block_revoke=1'b0;force dut.cap_revoke=1'b0;force dut.scene_revoke=1'b0;force dut.wait_start=1'b0;
    force dut.shape_event=se;force dut.shape_healthy=sh;force dut.shape_ok=bits;force dut.shape_original=original;
    force dut.shape_negative=negative;force dut.shape_recovery=recovery;
    force dut.shape_recovery_distance=recovery_distance;force dut.shape_geometry_minimum=geometry_minimum;
    force dut.shape_contour_color=body_color;force dut.shape_id=shape_tag;force dut.shape_source=source;
    force dut.match_event=me;force dut.match_good=mh;force dut.match_present=1'b1;force dut.match_valid=card_valid;
    force dut.match_item=4'd10;force dut.match_id=match_tag;force dut.match_source=match_source;
    force dut.best_distance=best;force dut.second_distance=11'd100;force dut.sample_fg=11'd200;
    repeat(4)@(negedge clk);rst_n=1;repeat(40)@(negedge clk);
    for(integer color=0;color<3;color++)for(integer shape=0;shape<3;shape++)begin
      clear_epoch;anchor=1+color*3;bits=1<<shape;original=bits;negative=0;recovery=0;card_valid=0;body_color=color+1;
      evidence(1+color*3+shape,1,0,2);evidence(1+color*3+shape,2,0,3);evidence(1+color*3+shape,3,0,4);
    end
    clear_epoch;anchor=1;bits=1;original=0;negative=1;recovery=1;card_valid=1;body_color=1;best=32;
    evidence(1,1,0,25);evidence(1,2,0,8);evidence(1,3,0,2);
    best=24;evidence(0,0,0,2); // Equality at 8+16 is ambiguous.
    best=25;evidence(1,1,0,2);
    best=23;evidence(0,0,0,2);
    best=32;body_color=2;evidence(0,0,0,2);body_color=1;
    for(integer fault=1;fault<=7;fault++)begin
      clear_epoch;bits=1;original=1;recovery=0;negative=0;card_valid=0;
      evidence(1,1,0,2);evidence(1,2,0,2);
      evidence(0,0,fault,3);
      evidence(1,1,0,2);evidence(1,2,0,2);evidence(1,3,0,2);
    end
    clear_epoch;bits=0;original=0;negative=1;card_valid=1;
    evidence(0,0,0,2);ck(dut.card_count==0,"negative-only ellipse cannot accumulate apple confirmation");
    negative=0;geometry_minimum=80;best=30;
    evidence(0,0,0,2);ck(dut.card_count==1,"legitimate card starts independent confirmation");
    evidence(0,0,0,2);ck(dut.card_count==2,"legitimate card second frame");
    evidence(0,0,0,2);ck(dut.card_count==3 && dut.card_item==10,"legitimate apple is retained");
    clear_epoch;bits=2;original=2;card_valid=0;source=0;
    evidence(2,1,0,2);evidence(2,2,0,2);source=1;evidence(2,1,0,2);
    test_done=1;$display("RESULT pairing errors=%0d checks=%0d scenarios=%0d",errors,checks,scenarios);$finish;
  end
  initial begin #3000000;$display("WATCHDOG pairing");$finish;end
endmodule
