`timescale 1ns/1ps
// 103.519669MHz capture, 720 rows*2396 clocks ~=60.008fps.
// New frames never wait for the previous recognition transaction.
module tb_contour29_fpsdiag;
  reg capture_clk=0,display_clk=0;
  always #4.83 capture_clk=~capture_clk;
  always #6.6665 display_clk=~display_clk;
  reg rst_n=0,in_frame_start=0,in_source_test=0,in_valid=0,in_eol=0;
  reg [31:0] in_frame_id=0,in_done_id=0;
  reg [95:0] in_rgb96=0;
  reg in_frame_done=0,in_frame_good=1,in_done_source_test=0,in_revoke=0;
  reg tick_1ms=0,flush=0,key_mode_pulse=0,key_replay_pulse=0,key_skip_pulse=0,key_reset_pulse=0;
  wire audio_idle=1,audio_fault=1;
  reg video_frame_start=0,video_vsync=0,video_hsync=0,video_de=0;
  reg [10:0] pixel_x=0;reg [9:0] pixel_y=0;reg [23:0] video_rgb=0;
  wire out_vsync,out_hsync,out_de;wire [23:0] out_rgb;
  wire obs_event,obs_healthy,obs_present,obs_valid,obs_revoke,obs_conflict,timed_out;
  wire [3:0] obs_item,score,question_index,target_item,display_item;
  wire [31:0] obs_frame_id;wire obs_source_test;wire [7:0] obs_count;
  wire [1:0] mode,phase;wire quiz_active,answer_valid,answer_correct,display_source_test,armed;
  wire [2:0] feedback,audio_event_kind;wire audio_event_valid,audio_cancel;wire [3:0] audio_event_item;
  wire link_fault,quarantined;wire [10:0] diag_best,diag_second,diag_sample_fg;
  wire [95:0] diag_pre_wb=0,diag_post_wb=0;wire [8:0] diag_gain_r=304,diag_gain_b=333;
  wire [31:0] diag_pixel_id=0,diag_stats_id=0;wire diag_stats_event=0,diag_stats_good=0;wire [20:0] diag_neutral_count=0;
  wire [799:0] color_diag_packet;wire color_diag_fresh,color_diag_fault;wire [7:0] color_diag_age;
  wire [27:0] render_state;
  pixel29_pipeline #(.ENABLE_OUTPUT(1),.USE_SCENE_ANALYSIS(1),.ROTATION_VARIANTS(256),.RENDER_ENABLE(0)) dut(.*);
  reg [23:0] raster[0:57599];
  integer errors=0,checks=0,scenarios=0,injected=0;
  reg test_done=0,stress=0,saw_bank_overlap=0;
  integer capture_cycles=0,eof_cycle[0:15],normal_events=0,revoke_events=0,last_tag=0,max_post_eof=0,max_fifo=0;
  integer tick_div=0,wait_cycles=0,before_revoke=0;
  string assets;
  task ck(input bit value,input string message);
    begin checks++;if(!value)begin errors++;$display("FAIL fps time=%0t %s",$time,message);end end
  endtask
  always @(posedge capture_clk)begin
    capture_cycles++;
    if(rst_n && dut.scene_mode.scene.capture_active && dut.scene_mode.scene.state!=0 &&
       dut.scene_mode.scene.capture_bank!=dut.scene_mode.scene.process_bank)saw_bank_overlap=1;
    if(rst_n && dut.scene_mode.scene.fifo_tail>max_fifo)max_fifo=dut.scene_mode.scene.fifo_tail;
  end
  always @(posedge display_clk)begin
    tick_1ms<=0;
    if(!rst_n)tick_div<=0;
    else if(tick_div==74999)begin tick_div<=0;tick_1ms<=1;end else tick_div<=tick_div+1;
    #1;
    if(rst_n)begin
      if(obs_revoke)begin revoke_events++;$display("REVOKE time=%0t cycle=%0d stress=%0d link_fault=%0d quarantine=%0d",$time,capture_cycles,stress,link_fault,quarantined);end
      if(obs_event && obs_healthy && !obs_revoke && !stress)begin
        normal_events++;last_tag=obs_frame_id;
        ck(obs_frame_id==normal_events && obs_source_test==0,"continuous tags are delivered once and in order");
        ck(obs_present && !obs_conflict && obs_valid==(obs_frame_id>=3) &&
           obs_item==(obs_frame_id>=3 ? 1:0),"continuous circle confirms only from three complete identities");
        if(capture_cycles-eof_cycle[obs_frame_id]>max_post_eof)max_post_eof=capture_cycles-eof_cycle[obs_frame_id];
        ck(capture_cycles-eof_cycle[obs_frame_id]<1200000,"continuous worst EOF-to-final within original bound");
      end
    end
  end
  task send_frame(input integer tag,input integer blank);
    reg [23:0] value;
    begin
      @(negedge capture_clk);in_frame_id=tag;in_frame_start=1;
      @(negedge capture_clk);in_frame_start=0;
      for(integer y=0;y<720;y++)begin
        for(integer x=0;x<320;x++)begin
          value=raster[(y/4)*320+x];in_valid=1;in_eol=x==319;in_rgb96={4{value}};
          @(negedge capture_clk);
        end
        in_valid=0;in_eol=0;
        if(y==719)begin
          in_frame_done=1;in_done_id=tag;eof_cycle[tag]=capture_cycles;
          @(negedge capture_clk);in_frame_done=0;
        end
        repeat(blank)@(negedge capture_clk);
      end
      repeat(8)@(negedge capture_clk);
    end
  endtask
  initial begin
    if(!$value$plusargs("ASSET_ROOT=%s",assets))$fatal(1,"ASSET_ROOT required");
    $readmemh({assets,"/c062.rgb.mem"},raster);
    repeat(8)@(negedge capture_clk);rst_n=1;repeat(30)@(negedge capture_clk);
    scenarios++;
    for(integer tag=1;tag<=4;tag++)send_frame(tag,2076);
    wait_cycles=0;while(normal_events<4 && wait_cycles<1200000)begin @(negedge capture_clk);wait_cycles++;end
    ck(normal_events==4 && last_tag==4,"four continuous 60fps frames complete without producer waits");
    $display("NORMAL_WINDOW_END revokes=%0d link_fault=%0d quarantined=%0d cycles=%0d",revoke_events,link_fault,quarantined,capture_cycles);
    ck(revoke_events==0 && !link_fault && !quarantined,"no revoke, overflow or mailbox fault at supported rate");
    ck(saw_bank_overlap && max_fifo<=7200,"capture/process overlap uses opposite banks and bounded shared FIFO");
    scenarios++;stress=1;before_revoke=revoke_events;
    for(integer tag=5;tag<=9;tag++)send_frame(tag,0);
    repeat(200)@(negedge display_clk);
    ck(revoke_events>before_revoke && !obs_valid,"overspeed input explicitly revokes instead of retaining old class");
    test_done=1;
    $display("RESULT fps errors=%0d checks=%0d scenarios=%0d normal_events=%0d max_post_eof=%0d max_fifo=%0d overlap=%0d",errors,checks,scenarios,normal_events,max_post_eof,max_fifo,saw_bank_overlap);
    $finish;
  end
  initial begin #(64'd150000000);$display("WATCHDOG fps");$finish;end
endmodule
