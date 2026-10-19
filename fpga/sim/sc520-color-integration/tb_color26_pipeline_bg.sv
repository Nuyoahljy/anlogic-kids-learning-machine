`timescale 1ns/1ps
// Complete 1280x720 RGB96 rasters, scene preprocessing, both classifiers,
// asynchronous mailbox, real business controller and its existing OSD.
module tb_color26_pipeline_bg;
  wire [27:0] render_state;
  reg capture_clk=0,display_clk=0,cap_run=1;
  always #4.83 if(cap_run)capture_clk=~capture_clk;
  always #520.833333 display_clk=~display_clk; // UART test clock960kHz; hardware probe remains75MHz
  reg rst_n=0,in_frame_start=0,in_source_test=0,in_valid=0,in_eol=0;
  reg [31:0] in_frame_id=0,in_done_id=0;
  reg [95:0] in_rgb96=0;
  reg in_frame_done=0,in_frame_good=1,in_done_source_test=0,in_revoke=0;
  reg tick_1ms=0,flush=0,key_mode_pulse=0,key_replay_pulse=0,key_skip_pulse=0,key_reset_pulse=0;
  wire audio_idle,audio_fault;reg video_frame_start=0;
  reg [10:0] pixel_x=220;
  reg [9:0] pixel_y=300;
  reg video_vsync=0,video_hsync=0,video_de=0;
  reg [23:0] video_rgb=0;
  wire out_vsync,out_hsync,out_de;
  wire [23:0] out_rgb;
  wire obs_event,obs_healthy,obs_present,obs_valid,obs_revoke,obs_conflict,timed_out;
  wire [3:0] obs_item,score,question_index,target_item,display_item;
  wire [31:0] obs_frame_id;
  wire obs_source_test;
  wire [7:0] obs_count;
  wire [1:0] mode,phase;
  wire quiz_active,answer_valid,answer_correct,display_source_test,armed;
  wire [2:0] feedback,audio_event_kind;
  wire audio_event_valid,audio_cancel,link_fault,quarantined;
  wire [3:0] audio_event_item;
  wire [10:0] diag_best,diag_second,diag_sample_fg;
  // Unused diagnostics in this retained baseline test. New observers have
  // their own enabled test, while the image/business expectations stay fixed.
  wire [95:0] diag_pre_wb=0,diag_post_wb=0;
  wire [8:0] diag_gain_r=0,diag_gain_b=0;
  wire [31:0] diag_pixel_id=0,diag_stats_id=0;
  wire diag_stats_event=0,diag_stats_good=0;
  wire [20:0] diag_neutral_count=0;
  wire [799:0] color_diag_packet;
  wire color_diag_fresh,color_diag_fault;
  wire [7:0] color_diag_age;
  pixel26_bg_pipeline #(.ENABLE_OUTPUT(1),.USE_SCENE_ANALYSIS(1),.ROTATION_VARIANTS(256),.TIMEOUT_MS(500),.FEEDBACK_TICKS(10),.RENDER_ENABLE(0)) dut(.*);
  reg [23:0] raster[0:57599];
  integer errors=0,checks=0,scenarios=0,injected=0,inject_fault=0,unused;
  reg test_done=0;
  integer tag=0,healthy_events=0,revoke_events=0,answers=0,speech=0,last_item=0,last_tag=0,last_count=0;
  reg last_present=0,last_valid=0,last_source=0;
  string root_path,prefix,empty_path,apple_path,unknown_path,business_label;
  integer fd,bfd,fields,want_item,want_present,i,x,y,previous,prior_answers,wait_cycles;
  task ck(input bit ok,input string msg);
    begin checks++;if(!ok)begin errors++;$display("FAIL scene-system case=%0d time=%0t %s last=%0d/%0d/%0d tag=%0d wanttag=%0d",scenarios,$time,msg,last_item,last_present,last_valid,last_tag,tag);end end
  endtask
  task begin_case(input string msg);begin scenarios++;$display("CASE scene-system %0d %s",scenarios,msg);end endtask
  always @(posedge display_clk)begin
    #1;
    if(rst_n)begin
      if(obs_event && obs_healthy && !obs_revoke)begin
        healthy_events++;last_item=obs_item;last_tag=obs_frame_id;last_count=obs_count;
        last_present=obs_present;last_valid=obs_valid;last_source=obs_source_test;
        ck(!obs_valid || (obs_item>=1 && obs_item<=14),"legal unified item");
      end
      if(obs_revoke)revoke_events++;
      if(answer_valid)answers++;
      if(audio_event_valid)speech++;
    end
  end
  task settle;begin repeat(24)@(negedge display_clk);end endtask
  task load_raster(input string name);
    begin $readmemh({root_path,"/",name,".rgb.mem"},raster);end
  endtask
  task start_frame;
    begin tag++;@(negedge capture_clk);in_frame_id=tag;in_frame_start=1;
      @(negedge capture_clk);in_frame_start=0;end
  endtask
  task pixels(input integer rows);
    integer px,py;
    reg [23:0] value;
    begin
      for(py=0;py<rows;py++)for(px=0;px<320;px++)begin
        value=raster[(py/4)*320+px];
        in_valid=1;in_eol=px==319;in_rgb96={4{value}};
        @(negedge capture_clk);
      end
      in_valid=0;in_eol=0;in_rgb96=0;
    end
  endtask
  task frame(input bit good);
    integer old_revoke,old_healthy,cycle_count;
    begin
      old_revoke=revoke_events;old_healthy=healthy_events;
      start_frame;pixels(720);in_frame_done=1;in_frame_good=good;
      in_done_id=tag;in_done_source_test=in_source_test;
      @(negedge capture_clk);in_frame_done=0;
      cycle_count=0;
      while(cycle_count<1200000 && healthy_events==old_healthy && revoke_events==old_revoke)begin
        @(negedge capture_clk);cycle_count++;
      end
      settle;
      ck(cycle_count<1200000,"scene completion/revoke within less than one 60fps capture period");
      if(good)ck(last_tag==tag && !link_fault,"fresh atomically paired scene result delivered");
    end
  endtask
  task pulse_key(input integer key_index);
    begin
      @(negedge display_clk);
      case(key_index)1:key_mode_pulse=1;2:key_replay_pulse=1;3:key_skip_pulse=1;4:key_reset_pulse=1;endcase
      @(negedge display_clk);key_mode_pulse=0;key_replay_pulse=0;key_skip_pulse=0;key_reset_pulse=0;settle;
    end
  endtask
  task clear_epoch;begin @(negedge display_clk);flush=1;repeat(30)@(negedge display_clk);flush=0;settle;end endtask
  task expect_current(input integer item,input bit present);
    begin ck(last_tag==tag && last_present==present && last_item==item && last_valid==(item!=0),"physical-construction truth matches unified item and occupancy");end
  endtask

  function [559:0] test_map;
    reg [559:0] r;
    begin r=0;for(integer k=0;k<35;k++)r[k*16+:16]=16'h1201+k;test_map=r;end
  endfunction
  integer tick_div=0;
  always @(posedge display_clk)begin
    tick_1ms<=0;
    if(!rst_n)tick_div<=0;else if(tick_div==959)begin tick_div<=0;tick_1ms<=1;end else tick_div<=tick_div+1;
  end
  wire uart_tx,uart_rx,busy_async,initialized,queue_overflow,audio_reset;
  wire [2:0] audio_state;reg [2:0] response_policy=0;reg hold_play=0,busy_mismatch=0;reg [31:0] duration_ms=40;
  pixel22_audio #(.CLK_HZ(960000),.TRACKS(test_map()),.MAP_VERIFIED(1),.STATUS_VERIFIED(1),.MODE_VERIFIED(1),
    .BOOT_TICKS(80),.INIT_TICKS(200),.QUERY_TICKS(2),.RESPONSE_TICKS(30),.QUIET_TICKS(2),.BUSY_FILTER_TICKS(1),
    .START_TICKS(140),.PLAY_TICKS(200),.STOP_TICKS(140)) audio(
    .clk(display_clk),.reset_n(rst_n),.reset_released(audio_reset),.*);
  dfr0534_uart_model peripheral(.clk(display_clk),.tx(uart_tx),.rx(uart_rx),.busy(busy_async),.*);
  always @(posedge display_clk)begin #2;ck(dut.drst===audio_reset,"audio and pipeline release the same reset epoch");end
  task wait_audio;
    begin do begin wait(audio_idle);repeat(15)@(negedge display_clk);end while(!audio_idle);ck(!audio_fault,"real UART finishes without audio fault");end
  endtask
  task finish_test;
    begin test_done=1;$display("RESULT tb_color26_pipeline_bg errors=%0d checks=%0d scenarios=%0d injected=%0d UARTchecks=%0d",errors,checks,scenarios,injected,peripheral.checks);$finish;end
  endtask
  initial begin
    unused=$value$plusargs("INJECT_FAULT=%d",inject_fault);
    if(!$value$plusargs("ASSET_ROOT=%s",root_path))$fatal(1,"ASSET_ROOT required");
    repeat(6)@(negedge capture_clk);rst_n=1;settle;
    begin_case("actual RGB96 pipeline to UART object10,256 rotation bank");
    pulse_key(1);load_raster("r000_empty_dark");for(i=0;i<3;i++)frame(1);ck(armed,"real empty frames arm exploration");
    load_raster("r003_card_10_angle_0");for(i=0;i<3;i++)frame(1);expect_current(10,1);
    if(inject_fault)begin force audio.bridge.player.physical_track=16'h1201;injected=1;end
    wait(peripheral.plays==1);
    ck(peripheral.tracks[0]==16'h120a,"real pipeline item10 reaches synthetic track120a");
    if(inject_fault)begin release audio.bridge.player.physical_track;finish_test();end
    wait_audio();ck(speech==1 && score==0,"one object announcement through the actual pipeline event outputs");
    begin_case("pipeline K2 two intentional replays and K3 image request without audio");
    previous=peripheral.plays;pulse_key(2);pulse_key(2);wait(peripheral.plays==previous+2);wait_audio();
    ck(peripheral.tracks[previous]==16'h120a && peripheral.tracks[previous+1]==16'h120a,"both replay requests retain object identity");
    previous=speech;pulse_key(3);ck(speech==previous && mode==1,"explore K3 never emits a speech request");
    begin_case("pipeline quiz skip/cancel,score once,and UART feedback");
    pulse_key(1);pulse_key(3);ck(target_item==10 && score==0,"question skip selects apple");
    load_raster("r000_empty_dark");for(i=0;i<3;i++)frame(1);ck(armed,"actual empty frames arm quiz");
    prior_answers=answers;load_raster("r003_card_10_angle_0");for(i=0;i<3;i++)frame(1);
    ck(score==1 && answers==prior_answers+1,"capture card answer scores exactly once with real audio busy");
    frame(1);ck(score==1 && answers==prior_answers+1,"retained RGB card cannot score twice");
    wait_audio();
    begin_case("bad frame and stopped capture revoke while audio remains independently serviceable");
    previous=revoke_events;frame(0);ck(revoke_events>previous && !armed,"bad frame revokes pipeline recognition");
    @(negedge capture_clk);cap_run=0;wait(timed_out);repeat(15)@(negedge display_clk);
    ck(!obs_valid && !armed && !link_fault,"stopped capture cannot retain a valid answer");
    begin_case("K4 cancels but does not reset initialized player");
    cap_run=1;pulse_key(4);ck(mode==0 && score==0 && audio_reset && initialized,"K4 only cancels current context");
    wait_audio();ck(!queue_overflow,"bounded scenario queue never overflowed");
    finish_test();
  end
  initial begin #(64'd5000000000);$display("WATCHDOG audio22-pipeline");$finish;end
endmodule
