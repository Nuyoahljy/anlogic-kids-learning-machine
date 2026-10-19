`timescale 1ns/1ps
// Inject only classifier-boundary evidence into the actual production pipeline.
// This isolates pairing and temporal confirmation from scene/capture engines;
// complete raster tests separately exercise those engines without these forces.
module tb_shape27_pairing;
  reg clk=0,rst_n=0;
  always #5 clk=~clk;
  integer errors=0,checks=0,scenarios=0,injected=0;
  reg test_done=0;
  reg be=0,se=0,bh=1,bp=1,bv=1,bs=0,ss=0,sh=1;
  reg [3:0] bi=1;
  reg [31:0] bid=0,sid=0;
  reg [2:0] bits=1;
  integer tag=0;
  pixel27_pipeline #(.ENABLE_OUTPUT(1),.USE_SCENE_ANALYSIS(1),
    .ROTATION_VARIANTS(256),.RENDER_ENABLE(0)) dut(
    .rst_n(rst_n),.capture_clk(clk),.display_clk(clk),
    .in_frame_start(1'b0),.in_frame_id(32'd0),.in_source_test(1'b0),
    .in_valid(1'b0),.in_eol(1'b0),.in_rgb96(96'd0),
    .in_frame_done(1'b0),.in_frame_good(1'b1),.in_done_id(32'd0),
    .in_done_source_test(1'b0),.in_revoke(1'b0),.tick_1ms(1'b0),.flush(1'b0),
    .key_mode_pulse(1'b0),.key_replay_pulse(1'b0),.key_skip_pulse(1'b0),.key_reset_pulse(1'b0),
    .audio_idle(1'b1),.audio_fault(1'b1),.video_frame_start(1'b0),
    .pixel_x(11'd0),.pixel_y(10'd0),.video_vsync(1'b0),.video_hsync(1'b0),
    .video_de(1'b0),.video_rgb(24'd0),
    .diag_pre_wb(96'd0),.diag_post_wb(96'd0),.diag_gain_r(9'd304),.diag_gain_b(9'd333),
    .diag_pixel_id(32'd0),.diag_stats_id(32'd0),.diag_stats_event(1'b0),
    .diag_stats_good(1'b0),.diag_neutral_count(21'd0));
  task ck(input bit ok,input string msg);
    begin checks++;if(!ok)begin errors++;$display("FAIL pairing %s time=%0t",msg,$time);end end
  endtask
  task evidence(input integer anchor,input integer shape_bits,input integer fault,
    input integer want_raw,input integer want_count,input bit want_valid);
    begin
      scenarios++;tag++;
      @(negedge clk);bi=anchor;bits=shape_bits;bid=tag;sid=tag;
      bh=1;bp=1;bv=1;sh=1;bs=0;ss=0;
      case(fault)
        1:sid=tag+1;
        2:ss=1;
        3:bh=0;
        4:sh=0;
        5:bv=0;
      endcase
      be=1;@(posedge clk);#1;
      ck(dut.guarded_block_confirmation.raw_pending,"raw candidate retained once until shape event");
      @(negedge clk);be=0;se=1;#1;
      ck(dut.raw_diag_event && dut.raw_diag_id==sid && dut.raw_diag_source==ss,
        "raw diagnostic forwards actual shape identity");
      ck(dut.raw_diag_item==want_raw,"only a unique same-identity healthy shape and color anchor form public item");
      ck(dut.raw_diag_good==(fault!=1 && fault!=2 && fault!=3 && fault!=4),
        "raw health rejects mismatched tag/source or unhealthy classifier");
      @(posedge clk);#1;
      ck(dut.confirmed_block_event && dut.confirmed_block_count==want_count,
        "rejection clears original filter count; valid sequence counts from one");
      ck(dut.confirmed_block_valid==want_valid &&
         dut.confirmed_block_item==(want_valid?want_raw:0),"original filter confirms only at three frames");
      ck(!dut.guarded_block_confirmation.raw_pending,"shape consumes the staged raw candidate");
      @(negedge clk);se=0;repeat(2)@(negedge clk);
    end
  endtask
  initial begin
    force dut.block_event=be;force dut.block_healthy=bh;force dut.block_present=bp;
    force dut.block_valid=bv;force dut.block_item=bi;force dut.block_id=bid;
    force dut.block_source=bs;force dut.block_count=8'd1;
    force dut.shape_event=se;force dut.shape_healthy=sh;force dut.shape_ok=bits;
    force dut.shape_id=sid;force dut.shape_source=ss;
    // Other engines are deliberately inactive in this isolated pairing test.
    force dut.detector_flush=1'b0;force dut.source_fault=1'b0;
    force dut.source_revoke=1'b0;
    repeat(4)@(negedge clk);rst_n=1;repeat(8)@(negedge clk);
    for(integer color=0;color<3;color++)begin
      for(integer shape=0;shape<8;shape++)begin
        if(shape==1 || shape==2 || shape==4)begin
          evidence(1+color*3,shape,0,1+color*3+(shape==1?0:shape==2?1:2),1,0);
        end else evidence(1+color*3,shape,0,0,0,0);
      end
    end
    for(integer anchor=0;anchor<16;anchor++)begin
      if(anchor!=1 && anchor!=4 && anchor!=7)evidence(anchor,2,0,0,0,0);
    end
    for(integer fault=1;fault<=5;fault++)begin
      evidence(1,2,0,2,1,0);
      evidence(1,2,0,2,2,0);
      evidence(1,2,fault,0,0,0);
      evidence(1,2,0,2,1,0);
      evidence(1,2,0,2,2,0);
      evidence(1,2,0,2,3,1);
      evidence(1,0,0,0,0,0);
    end
    test_done=1;$display("DONE pairing errors=%0d checks=%0d scenarios=%0d",errors,checks,scenarios);$finish;
  end
  initial begin #1000000;$display("WATCHDOG pairing");$finish;end
endmodule
