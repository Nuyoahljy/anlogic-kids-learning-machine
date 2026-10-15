`timescale 1ns/1ps
// Complete 1280x720 RGB96 rasters, scene preprocessing, both classifiers,
// asynchronous mailbox, real business controller and its existing OSD.
module tb_pixel14_scene_system #(parameter integer ROTATIONS=0,MATRIX_ONLY=0);
  wire [27:0] render_state;
  reg capture_clk=0,display_clk=0,cap_run=1;
  always #4.83 if(cap_run)capture_clk=~capture_clk;
  always #6.6665 display_clk=~display_clk;
  reg rst_n=0,in_frame_start=0,in_source_test=0,in_valid=0,in_eol=0;
  reg [31:0] in_frame_id=0,in_done_id=0;
  reg [95:0] in_rgb96=0;
  reg in_frame_done=0,in_frame_good=1,in_done_source_test=0,in_revoke=0;
  reg tick_1ms=0,flush=0,key_mode_pulse=0,key_replay_pulse=0,key_skip_pulse=0,key_reset_pulse=0;
  reg audio_idle=1,audio_fault=0,video_frame_start=0;
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
  pixel14_pipeline #(.ENABLE_OUTPUT(1),.USE_SCENE_ANALYSIS(1),.ROTATION_VARIANTS(ROTATIONS),.TIMEOUT_MS(5),.FEEDBACK_TICKS(2)) dut(.*);
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
  task settle;begin repeat(80)@(negedge capture_clk);end endtask
  task load_raster(input string name);
    begin $readmemh({root_path,"/vectors/",name,".rgb.mem"},raster);end
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
  task pulse_tick;begin @(negedge display_clk);tick_1ms=1;@(negedge display_clk);tick_1ms=0;end endtask
  task clear_epoch;begin @(negedge display_clk);flush=1;repeat(30)@(negedge display_clk);flush=0;settle;end endtask
  task expect_current(input integer item,input bit present);
    begin ck(last_tag==tag && last_present==present && last_item==item && last_valid==(item!=0),"physical-construction truth matches unified item and occupancy");end
  endtask
  initial begin
    unused=$value$plusargs("INJECT_FAULT=%d",inject_fault);
    if(!$value$plusargs("ASSET_ROOT=%s",root_path))$fatal(1,"ASSET_ROOT required");
    fd=$fopen({root_path,"/system-cases.txt"},"r");if(!fd)$fatal(1,"system-cases missing");
    // Physical-construction fixtures selected before looking at RTL outcomes.
    empty_path="006_empty_dark";apple_path="053_card_10_dark_51_0";unknown_path="696_unknown_checker_dark";
    if(ROTATIONS>0)begin
      bfd=$fopen({root_path,"/business-cases.txt"},"r");
      if(!bfd)$fatal(1,"rotation business-cases missing");
      fields=$fscanf(bfd,"%s %s",business_label,empty_path);
      if(fields!=2 || business_label!="empty")$fatal(1,"invalid rotation empty case");
      fields=$fscanf(bfd,"%s %s",business_label,apple_path);
      if(fields!=2 || business_label!="apple")$fatal(1,"invalid rotation apple case");
      fields=$fscanf(bfd,"%s %s",business_label,unknown_path);$fclose(bfd);
      if(fields!=2 || business_label!="unknown")$fatal(1,"invalid rotation unknown case");
    end
    begin_case("reset and K1 exploration");
    repeat(6)@(negedge capture_clk);rst_n=1;settle;pulse_key(1);
    ck(mode==1 && !link_fault && !quarantined,"startup and physical-pulse key interface");
    while(!$feof(fd))begin
      fields=$fscanf(fd,"%s %d %d\n",prefix,want_item,want_present);
      if(fields==3)begin
        begin_case(prefix);clear_epoch;load_raster(prefix);
        for(i=1;i<=3;i++)begin
          frame(1);
          ck(last_present==want_present,"empty and unknown stay distinct during confirmation");
          ck(last_valid==(want_item!=0 && i==3),"exactly three good frames required after clear");
        end
        if(inject_fault && injected==0 && want_item!=0)begin force dut.obs_item=0;injected=1;#1;end
        if(want_item!=0)ck(obs_item==want_item,"live observation ID agrees with truth");
        if(inject_fault && injected==1)begin
          release dut.obs_item;test_done=1;
          $display("DONE scene-system negative probe errors=%0d checks=%0d",errors,checks);$finish;
        end
        expect_current(want_item,want_present);
      end else if(fields!=-1)$fatal(1,"invalid system case row");
    end
    $fclose(fd);
    if(MATRIX_ONLY)begin
      test_done=1;$display("DONE scene-system matrix scenarios=%0d checks=%0d errors=%0d",scenarios,checks,errors);$finish;
    end
    begin_case("K2 replays a stable real card in exploration");
    clear_epoch;load_raster(apple_path);for(i=0;i<3;i++)frame(1);expect_current(10,1);
    previous=speech;pulse_key(2);ck(speech==previous+1,"K2 emits one object replay");
    begin_case("K1 enters quiz and K3 selects apple without scoring");
    pulse_key(1);ck(mode==2 && target_item==1,"quiz first question");pulse_key(3);
    ck(target_item==10 && score==0,"skip target and no score");
    begin_case("dark empty scene rearms, apple scores once while retained");
    load_raster(empty_path);for(i=0;i<3;i++)frame(1);ck(armed,"three real dark empty frames rearm");
    prior_answers=answers;load_raster(apple_path);for(i=0;i<3;i++)frame(1);
    ck(score==1 && answers==prior_answers+1 && answer_correct==0 && feedback==1,"correct answer counted once");
    frame(1);frame(1);ck(score==1 && answers==prior_answers+1 && !armed,"held object does not rescore");
    pulse_tick;pulse_tick;settle;frame(1);
    ck(!armed && score==1 && answers==prior_answers+1,"new question cannot reuse retained object");
    begin_case("unknown occupancy cannot rearm after an answer");
    load_raster(unknown_path);for(i=0;i<3;i++)frame(1);expect_current(0,1);ck(!armed,"unknown is not an empty scene");
    begin_case("bad frame cancels a two-empty-frame rearm sequence");
    load_raster(empty_path);frame(1);frame(1);ck(!armed,"two empties insufficient");
    previous=revoke_events;frame(0);ck(revoke_events>previous && !armed && !obs_valid,"bad frame revokes");
    frame(1);frame(1);ck(!armed,"recovery must restart absence count");frame(1);ck(armed,"third fresh empty rearms");
    begin_case("capture clock stop revokes in display domain");
    @(negedge capture_clk);cap_run=0;for(i=0;i<5;i++)pulse_tick;
    repeat(12)@(negedge display_clk);ck(timed_out && !armed && !obs_valid,"stop does not allow another answer");
    cap_run=1;settle;for(i=0;i<3;i++)frame(1);ck(armed && !timed_out,"recovery after stopped capture requires real frames");
    begin_case("held flush and partial restart cannot publish old empty frame");
    @(negedge display_clk);flush=1;settle;previous=healthy_events;
    start_frame;pixels(360);@(negedge display_clk);flush=0;
    @(negedge capture_clk);pixels(360);in_frame_done=1;in_done_id=tag;
    @(negedge capture_clk);in_frame_done=0;repeat(1000)@(negedge capture_clk);
    ck(healthy_events==previous && !armed,"no trusted observation after mid-frame clear release");
    for(i=0;i<3;i++)frame(1);ck(armed,"fresh frame after held flush recovers");
    begin_case("replayed acquisition tag cannot create empty evidence");
    tag--;previous=revoke_events;frame(1);ck(revoke_events>previous && !armed,"replayed tag rejected");
    begin_case("K4 clears score and returns idle");
    pulse_key(4);ck(mode==0 && score==0 && !quiz_active && !armed,"K4 clears quiz state");
    begin_case("visible ROI border is exactly 960x480 and RGB/sync delay is one cycle");
    for(y=118;y<=601;y++)for(x=158;x<=1121;x++)begin
      if(y==118 || y==120 || y==599 || y==601 || x==158 || x==160 || x==1119 || x==1121)begin
        @(negedge display_clk);pixel_x=x;pixel_y=y;video_de=1;video_hsync=x%2;video_vsync=y%2;video_rgb=24'h214365;
        @(posedge display_clk);#1;
        ck(out_de && out_hsync==(x%2) && out_vsync==(y%2),"video sidebands aligned");
        ck(out_rgb==((x>=160 && x<1120 && y>=120 && y<600 && (x==160 || x==1119 || y==120 || y==599)) ? 24'hff0000:24'h214365),"visible operating boundary matches sampled ROI");
      end
    end
    @(negedge display_clk);video_de=0;@(posedge display_clk);#1;ck(out_rgb==0 && !out_de,"blanking stays black");
    test_done=1;$display("DONE scene-system scenarios=%0d checks=%0d errors=%0d",scenarios,checks,errors);$finish;
  end
  initial begin #2500000000;$display("WATCHDOG scene-system");$finish;end
endmodule
