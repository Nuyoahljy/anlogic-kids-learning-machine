`timescale 1ns/1ps
// Complete 1280x720 RGB96 rasters, scene preprocessing, both classifiers,
// asynchronous mailbox, real business controller and its existing OSD.
module tb_contour29_scenes;
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
  `ifdef LEGACY_D0270
  pixel27_pipeline #
`else
  pixel29_pipeline #
`endif
(.ENABLE_OUTPUT(1),.USE_SCENE_ANALYSIS(1),.ROTATION_VARIANTS(256),.TIMEOUT_MS(500),.FEEDBACK_TICKS(10),.RENDER_ENABLE(0)) dut(.*);
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


  assign audio_idle=1'b1;assign audio_fault=1'b1;
  initial begin
    unused=$value$plusargs("INJECT_FAULT=%d",inject_fault);
    if(!$value$plusargs("ASSET_ROOT=%s",root_path))$fatal(1,"ASSET_ROOT required");
    repeat(6)@(negedge capture_clk);rst_n=1;settle;pulse_key(1);
    fd=$fopen({root_path,"/cases.txt"},"r");if(!fd)$fatal(1,"cases missing");
    bfd=$fopen("scene-results.csv","w");$fwrite(bfd,"case,frame,item,valid,present,count,scene,glyph,paper,shape,raw\n");
    while(!$feof(fd))begin
      fields=$fscanf(fd,"%d %d %s\n",want_item,want_present,prefix);
      if(fields==3)begin
        begin_case(prefix);clear_epoch;load_raster(prefix);
        for(i=0;i<3;i++)begin
          frame(1);
          if(inject_fault && injected==0 && i==2)begin force dut.obs_item=15;injected=1;#1;ck(obs_item==want_item,"live output injection is detected");release dut.obs_item;end
          ck(last_present==want_present,"full scene occupancy from independent geometric construction");
          ck(last_valid==(want_item!=0&&i==2) && last_item==(i==2?want_item:0),"three-frame confirmed shape/card truth");
          $fwrite(bfd,"%s,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d\n",prefix,i,last_item,last_valid,last_present,last_count,dut.scene_pixels,dut.glyph_pixels,dut.paper_pixels,dut.shape_ok,dut.block_item);
        end
      end else if(fields!=-1)$fatal(1,"invalid scene row");
    end
    $fclose(fd);$fclose(bfd);test_done=1;$display("DONE scenes checks=%d errors=%d",checks,errors);$finish;
  end
  initial begin #2000000000;$display("WATCHDOG scenes");$finish;end
endmodule
