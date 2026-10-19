`timescale 1ns/1ps
// Result-record integration: the classifier and camera are deliberately upstream.
module tb_shape27_render;
  wire [27:0] render_state;
  reg [2:0] audio_state=0;
  integer errors=0,checks=0,scenarios=0,injected=0;
  reg test_done=0;
  integer inject_fault=0,ignored,item,j,q,round,tag=0;
  reg clk=0;
  always #6.6665 clk=~clk;
  reg rst_n=0,tick_1ms=0,flush=0,block_revoke=0,card_revoke=0;
  reg block_event=0,block_healthy=1,block_present=0,block_valid=0;
  reg [3:0] block_item=0;
  reg [31:0] block_frame_id=0;
  reg block_source_test=0;
  reg [7:0] block_count=3;
  reg card_event=0,card_healthy=1,card_present=0,card_valid=0;
  reg [3:0] card_item=0;
  reg [31:0] card_frame_id=0;
  reg card_source_test=0;
  reg [7:0] card_count=3;
  reg key_mode_pulse=0,key_replay_pulse=0,key_skip_pulse=0,key_reset_pulse=0;
  reg audio_idle=1,audio_fault=0,video_frame_start=0;
  reg [10:0] pixel_x=0;
  reg [9:0] pixel_y=0;
  wire detectors_flush,obs_event,obs_healthy,obs_present,obs_valid,obs_revoke,obs_conflict,timed_out;
  wire [3:0] obs_item,score,question_index,target_item,display_item;
  wire [31:0] obs_frame_id;
  wire obs_source_test;
  wire [7:0] obs_count;
  wire [1:0] mode,phase;
  wire quiz_active,answer_valid,answer_correct,display_source_test,armed;
  wire [2:0] feedback,audio_event_kind;
  wire audio_event_valid,audio_cancel,osd_active;
  wire [3:0] audio_event_item;
  wire [23:0] osd_rgb;
  wire legacy_osd_active;wire [23:0] legacy_osd_rgb;
  items14_system #(.TIMEOUT_MS(5),.ABSENT_SAMPLES(3),.FEEDBACK_TICKS(2),.SCENE_UI(1),.RENDER_ENABLE(0)) dut(.osd_active(legacy_osd_active),.osd_rgb(legacy_osd_rgb),.*);

  wire requested,next_request;
  pixel17_display_request selector(.clk(clk),.rst_n(rst_n),.business_mode(mode),
    .key_mode_pulse(key_mode_pulse),.key_skip_pulse(key_skip_pulse),.key_reset_pulse(key_reset_pulse),
    .requested(requested),.next_request(next_request));
  reg in_de=0,in_hsync=0,in_vsync=0;reg [23:0] in_rgb=0;
  reg [799:0] color_packet=0;reg color_fresh=1;reg [7:0] color_age=8'h12;
  reg [255:0] diagnostic=0;reg [31:0] i2c_diagnostic=32'h01413e02;reg [7:0] business_flags=8'h43;
  wire out_fs,out_de,out_hs,out_vs,out_mode,panel_marker,diag_marker,logo_marker;
  wire [10:0] out_x;wire [9:0] out_y;wire [23:0] out_rgb;wire [1:0] color_id;
  pixel26_compositor #(.VERSION(16'h0270),.LOGO_INDEX_FILE("anlogic_logo_index.mem"),.LOGO_PALETTE_FILE("anlogic_logo_palette.mem")) renderer(
    .clk(clk),.rst_n(rst_n),.in_frame_start(video_frame_start),.in_de(in_de),.in_hsync(in_hsync),.in_vsync(in_vsync),
    .mode_request(next_request),.in_x(pixel_x),.in_y(pixel_y),.in_rgb(in_rgb),.business_state(render_state),.audio_state(audio_state),
    .color_packet(color_packet),.color_fresh(color_fresh),.color_age(color_age),.diagnostic(diagnostic),
    .i2c_diagnostic(i2c_diagnostic),.business_flags(business_flags),
    .out_frame_start(out_fs),.out_de(out_de),.out_hsync(out_hs),.out_vsync(out_vs),.out_mode(out_mode),
    .out_x(out_x),.out_y(out_y),.out_rgb(out_rgb),.out_color_id(color_id),
    .out_panel_active(panel_marker),.out_diag_active(diag_marker),.out_logo_active(logo_marker));
  assign osd_active=renderer.panel_active;
  assign osd_rgb=renderer.panel_rgb;
  reg model_request=0,model_mode=0,model_next;
  reg [25:0] metadata_pipe[0:5];reg [23:0] rgb_pipe[0:5];reg compare_pipe[0:5];
  reg [1:0] color_pipe[0:5];reg [23:0] golden[0:921599];
  reg compare_pixel=0;reg [23:0] expected_pixel=0;
  integer pi,valid_cycles=0,x,y,frame_case,fd,prior_count;
  integer emitted_pixels=0;reg save_pixels=0;string asset_root;
  function [23:0] camera_pixel(input integer x);
    begin case(x/320)0:camera_pixel=24'h746059;1:camera_pixel=24'h93ac76;
      2:camera_pixel=24'h505d6e;default:camera_pixel=24'h707070;endcase end
  endfunction
  always @(posedge clk) begin
    if(!rst_n)begin
      model_request=0;model_mode=0;valid_cycles=0;
      for(pi=0;pi<6;pi++)begin metadata_pipe[pi]=0;rgb_pipe[pi]=0;compare_pipe[pi]=0;color_pipe[pi]=0;end
    end else begin
      model_next=key_reset_pulse ? 0:(!key_mode_pulse && key_skip_pulse && mode<2) ? !model_request:model_request;
      model_request=model_next;if(video_frame_start)model_mode=model_next;
      for(pi=5;pi>0;pi--)begin metadata_pipe[pi]=metadata_pipe[pi-1];rgb_pipe[pi]=rgb_pipe[pi-1];
        compare_pipe[pi]=compare_pipe[pi-1];color_pipe[pi]=color_pipe[pi-1];end
      metadata_pipe[0]={video_frame_start,in_de,in_hsync,in_vsync,model_mode,pixel_x,pixel_y};
      rgb_pipe[0]=expected_pixel;compare_pipe[0]=compare_pixel;
      color_pipe[0]=!in_de ? 0:pixel_x<320 ? 1:pixel_x<640 ? 2:pixel_x<960 ? 3:0;
      valid_cycles++;
      #1;
      if(valid_cycles>=6)begin
        ck({out_fs,out_de,out_hs,out_vs,out_mode,out_x,out_y}===metadata_pipe[5],"all metadata delayed exactly six register layers");
        if(compare_pipe[5])begin
          if(inject_fault && !injected && out_x==160 && out_y==120)begin force renderer.logo.out_rgb=24'h010203;injected=1;#0.001;end
          ck(out_rgb===rgb_pipe[5],$sformatf("independent golden image mismatch x=%0d y=%0d actual=%h expected=%h",out_x,out_y,out_rgb,rgb_pipe[5]));
          ck(color_id===color_pipe[5],"four-color sideband stays aligned");
          if(inject_fault && injected)release renderer.logo.out_rgb;
          if(save_pixels && out_de)begin $fwrite(fd,"%c%c%c",out_rgb[23:16],out_rgb[15:8],out_rgb[7:0]);emitted_pixels++;end
        end
        if(!out_de)ck(out_rgb==0,"blanking outputs black through full chain");
      end
    end
  end
  task keys(input bit k1,input bit k2,input bit k3,input bit k4,input bit fs);
    begin @(negedge clk);key_mode_pulse=k1;key_replay_pulse=k2;key_skip_pulse=k3;key_reset_pulse=k4;video_frame_start=fs;
      @(posedge clk);#2;@(negedge clk);key_mode_pulse=0;key_replay_pulse=0;key_skip_pulse=0;key_reset_pulse=0;video_frame_start=0;
      @(posedge clk);#2;end
  endtask
  task init_diagnostic;
    integer i;
    begin
      color_packet=0;diagnostic=0;color_age=8'h12;i2c_diagnostic=32'h01413e02;business_flags=8'h43;
      color_packet[31:0]=32'h12345678;color_packet[780]=1;
      color_packet[175:32]={24'hf4f5ea,24'heff0e2,24'hf0e8e0,24'hb79d9d,24'h9f8080,24'ha08080};
      color_packet[319:176]={24'heeefe4,24'he7e8da,24'he8e0d8,24'hb69b9b,24'h9b7e7e,24'h9e7e7e};
      for(i=0;i<6;i++)begin color_packet[320+i*7+:7]=i+1;color_packet[362+i*7+:7]=i+10;end
      color_packet[412:404]=255;color_packet[421:413]=258;color_packet[442:422]=21'h00abc0;
      for(i=0;i<9;i++)color_packet[443+i*20+:20]=i+1;
      color_packet[638:623]=16'h0456;color_packet[654:639]=16'h0033;color_packet[670:655]=16'h0123;
      color_packet[678:671]=8'h35;color_packet[682:679]=2;color_packet[685:683]=5;
      color_packet[718:686]={11'h089,11'h045,11'h013};color_packet[726:719]=3;color_packet[734:727]=0;color_packet[738:735]=2;
      color_packet[749:739]=11'h021;color_packet[760:750]=11'h050;color_packet[771:761]=11'h3aa;
      diagnostic[239:224]=16'h0040;diagnostic[223:208]=16'h0330;
      diagnostic[191:160]=32'h46500;diagnostic[159:128]=32'h38400;diagnostic[127:96]=32'h38400;
      diagnostic[95:80]=16'h02d0;diagnostic[79:64]=16'h02d0;
    end
  endtask
  task full_frame(input integer which);
    begin
      start_case($sformatf("full720p independent pixel/reference case %0d",which));
      $readmemh($sformatf("%s/golden-%0d.mem",asset_root,which),golden);
      fd=$fopen($sformatf("actual-%0d.ppm",which),"wb");$fwrite(fd,"P6\n1280 720\n255\n");save_pixels=1;emitted_pixels=0;
      init_diagnostic();audio_state=which==0 ? 0:which==1 ? 1:which==2 ? 3:4;
      for(y=0;y<720;y++)begin
        for(x=0;x<1280;x++)begin
          @(negedge clk);pixel_x=x;pixel_y=y;in_de=1;in_hsync=(x<3);in_vsync=(y<2);
          video_frame_start=(x==0 && y==0);in_rgb=camera_pixel(x);expected_pixel=golden[y*1280+x];compare_pixel=1;
          key_skip_pulse=(which==0 && x==100 && y==300);
          if(which==1 && x==0 && y==550)begin color_packet=~color_packet;diagnostic=~diagnostic;color_age=255;end
          @(posedge clk);#2;
        end
        @(negedge clk);in_de=0;compare_pixel=0;video_frame_start=0;key_skip_pulse=0;
        repeat(8)@(posedge clk);
      end
      @(negedge clk);in_de=0;compare_pixel=0;video_frame_start=0;
      repeat(8)@(negedge clk);save_pixels=0;$fclose(fd);
      ck(emitted_pixels==921600,"complete emitted720p frame length");
    end
  endtask
  task diagnostic_strip(input integer golden_case,input integer first_row,input integer last_row);
    begin
      $readmemh($sformatf("%s/golden-%0d.mem",asset_root,golden_case),golden);
      for(y=first_row;y<=last_row;y++)for(x=32;x<800;x++)begin
        @(negedge clk);pixel_x=x;pixel_y=y;in_de=1;in_rgb=camera_pixel(x);expected_pixel=golden[y*1280+x];compare_pixel=1;
        @(posedge clk);#2;
      end
      @(negedge clk);in_de=0;compare_pixel=0;repeat(8)@(negedge clk);
    end
  endtask
  `include "items14_text_reference.svh"
  integer bank[0:13];
  task ck(input bit ok,input string msg);
    begin checks=checks+1;if(!ok)begin errors=errors+1;
      if(errors<30)$display("FAIL system case=%0d t=%0t %s mode=%0d q=%0d target=%0d score=%0d obs=%0d/%0d/%0d",scenarios,$time,msg,mode,question_index,target_item,score,obs_event,obs_valid,obs_item);end end
  endtask
  always @(negedge clk)if(errors>30)$fatal(1,"too many mismatches");
  task start_case(input string msg);
    begin scenarios=scenarios+1;$display("CASE system %0d %s",scenarios,msg);end
  endtask
  task idle_cycle;
    begin @(negedge clk);block_event=0;card_event=0;tick_1ms=0;@(posedge clk);#1;end
  endtask
  task change_mode;
    begin @(negedge clk);key_mode_pulse=1;@(posedge clk);#1;
      @(negedge clk);key_mode_pulse=0;@(posedge clk);#1;end
  endtask
  task reset_key;
    begin @(negedge clk);key_reset_pulse=1;@(posedge clk);#1;
      @(negedge clk);key_reset_pulse=0;@(posedge clk);#1;idle_cycle();end
  endtask
  task flush_epoch;
    begin @(negedge clk);flush=1;block_event=0;card_event=0;tick_1ms=0;@(posedge clk);#1;
      ck(!display_item && !armed && audio_cancel,"epoch flush clears display and arming immediately");
      @(negedge clk);flush=0;@(posedge clk);#1;idle_cycle();end
  endtask
  // Return just after control consumes the paired observation, while its audio
  // and answer pulses are still visible. Split can put either detector first.
  task pair_record(input integer b_item,input integer c_item,input bit b_present,
    input bit c_present,input bit source,input integer split);
    begin
      tag=tag+1;
      @(negedge clk);tick_1ms=0;block_event=(split!=2);card_event=(split!=1);
      block_healthy=1;card_healthy=1;block_present=b_present;card_present=c_present;
      block_valid=b_item!=0;card_valid=c_item!=0;block_item=b_item;card_item=c_item;
      block_frame_id=tag;card_frame_id=tag;block_source_test=source;card_source_test=source;
      @(posedge clk);#1;
      if(split!=0)begin
        ck(!obs_event,"one detector alone cannot publish an observation");
        @(negedge clk);block_event=(split==2);card_event=(split==1);
        @(posedge clk);#1;
      end
      ck(obs_event && obs_frame_id==tag && obs_source_test==source,"pair carries its own frame and source tags");
      ck(obs_healthy,"complete paired records are healthy");
      idle_cycle();
    end
  endtask
  task absence;
    begin for(j=0;j<3;j=j+1) pair_record(0,0,0,0,0,j%3);ck(armed,"three paired healthy absences arm answer");end
  endtask
  task recognized(input integer which,input integer split);
    begin pair_record(which<=9?which:0,which>=10?which:0,1,1,0,split);end
  endtask
  task snapshot;
    begin @(negedge clk);video_frame_start=1;@(posedge clk);#1;
      @(negedge clk);video_frame_start=0;@(posedge clk);#1;end
  endtask
  task object_glyph(input integer which);
    begin
      @(negedge clk);pixel_x=48+32*5;pixel_y=676;#1;
      @(posedge clk);#1;ck(renderer.panel.content.glyph===items14_ref_text(which>=1&&which<=14?27+which:27,0),"display first glyph follows snapshotted detected object");
      @(posedge clk);#1;ck(osd_active,"detected-name pixel belongs to lower panel");
    end
  endtask
  task millisecond;
    begin @(negedge clk);tick_1ms=1;block_event=0;card_event=0;@(posedge clk);#1;
      @(negedge clk);tick_1ms=0;@(posedge clk);#1;end
  endtask
  initial begin
    ignored=$value$plusargs("INJECT_FAULT=%d",inject_fault);
    ignored=$value$plusargs("ASSET_ROOT=%s",asset_root);
    bank[0]=1;bank[1]=10;bank[2]=2;bank[3]=11;bank[4]=3;bank[5]=12;bank[6]=4;
    bank[7]=13;bank[8]=5;bank[9]=14;bank[10]=6;bank[11]=7;bank[12]=8;bank[13]=9;
    start_case("startup and all fourteen objects through join/control/OSD/audio event");
    repeat(3)@(posedge clk);
    @(negedge clk);rst_n=1;idle_cycle();
    ck(mode==0 && !armed && !obs_valid && !answer_valid,"reset starts idle without stale observation");
    change_mode();ck(mode==1,"K1 enters exploration");
    for(item=1;item<=14;item=item+1)begin
      absence();
      pair_record(0,0,1,1,0,0);ck(armed,"healthy unknown preserves already earned arming");
      recognized(item,item%3);
      ck(obs_valid && obs_item==item,"single candidate selected despite other foreground");
      ck(display_item==item,"fourteen-class display item accepted");
      ck(audio_event_valid && audio_event_kind==1 && audio_event_item==item && !armed,"exploration creates correctly mapped one-shot speech event");
      recognized(item,0);
      ck(!audio_event_valid && !answer_valid && display_item==item,"holding an object does not repeat automatic speech");
      snapshot();object_glyph(item);
    end

    start_case("frame snapshot prevents mid-frame name tearing");
    recognized(10,0);snapshot();object_glyph(10);
    recognized(14,1);object_glyph(10);
    snapshot();object_glyph(14);
    @(negedge clk);pixel_x=640;pixel_y=360;@(posedge clk);#1;
    @(posedge clk);#1;ck(!osd_active && osd_rgb==0,"central ROI remains unobscured");

    start_case("conflict withdraws stale object and arming before replay");
    absence();pair_record(1,10,1,1,0,0);
    ck(!armed && display_item==0 && audio_cancel && !audio_event_valid,"dual candidate conflict revokes control state");
    recognized(10,0);ck(!audio_event_valid && !armed,"new classification after conflict cannot reuse prior arming");
    absence();recognized(10,0);ck(audio_event_valid && audio_event_item==10,"fresh absences allow recovery");

    start_case("queued valid observation is killed by same-edge upstream fault");
    absence();tag=tag+1;
    @(negedge clk);block_event=1;card_event=1;block_valid=0;card_valid=1;
    block_present=1;card_present=1;block_item=0;card_item=10;
    block_frame_id=tag;card_frame_id=tag;@(posedge clk);#1;
    ck(obs_valid && obs_event,"valid pair is queued for control");
    @(negedge clk);block_event=0;card_event=0;card_revoke=1;@(posedge clk);#1;
    ck(!audio_event_valid && !answer_valid && !armed && display_item==0 && audio_cancel,"fault inhibits consuming previously queued observation");
    @(negedge clk);card_revoke=0;@(posedge clk);#1;idle_cycle();

    start_case("timeout cannot count as object removal");
    absence();
    for(item=0;item<5;item=item+1)millisecond();
    ck(timed_out && !armed && display_item==0,"five ticks without paired result revoke armed state");
    recognized(14,0);ck(!timed_out && !audio_event_valid && !armed,"classification resumes without timeout impersonating absence");
    absence();recognized(14,0);ck(audio_event_valid && audio_event_item==14,"explicit fresh absence restores exploration");

    start_case("test-source label survives revoke and real source needs epoch flush");
    flush_epoch();pair_record(0,12,1,1,1,0);
    ck(display_source_test && display_item==12 && !armed,"test object displays with actual source");
    @(negedge clk);card_revoke=1;@(posedge clk);#1;
    ck(display_source_test && !display_item && !armed,"revocation preserves TEST provenance");
    @(negedge clk);card_revoke=0;@(posedge clk);#1;idle_cycle();
    flush_epoch();recognized(6,0);ck(!display_source_test && display_item==6,"new real epoch may update source label");

    start_case("TEST timeout provenance and unhealthy OSD change together at frame start");
    flush_epoch();pair_record(0,12,1,1,1,0);snapshot();object_glyph(12);
    for(item=0;item<5;item=item+1)millisecond();
    ck(timed_out && display_source_test && display_item==0,"TEST source survives actual paired-result timeout");
    object_glyph(12); // Display remains on its previous whole-frame snapshot.
    snapshot();
    @(negedge clk);pixel_x=48;pixel_y=44;#1;
    @(posedge clk);#1;ck(renderer.panel.content.glyph===items14_ref_text(7,0),"new OSD source line remains TEST after timeout");
    @(posedge clk);#1;
    @(negedge clk);pixel_x=48;pixel_y=644;#1;
    @(posedge clk);#1;ck(renderer.panel.content.glyph===items14_ref_text(42,0),"new OSD snapshot includes unhealthy warning");
    @(posedge clk);#1;
    @(negedge clk);pixel_x=48+32*5;pixel_y=676;#1;
    @(posedge clk);#1;ck(renderer.panel.content.glyph===items14_ref_text(43,5),"unhealthy name field differs from stale car name");
    @(posedge clk);#1;flush_epoch();

    start_case("queued correct quiz answer and simultaneous replay lose to new fault");
    reset_key();change_mode();change_mode();absence();
    ck(target_item==1 && score==0 && phase==1 && armed,"quiz fault case begins genuinely armed for target one");
    tag=tag+1;
    @(negedge clk);block_event=1;card_event=1;block_valid=1;card_valid=0;
    block_present=1;card_present=1;block_item=1;card_item=0;
    block_frame_id=tag;card_frame_id=tag;block_source_test=0;card_source_test=0;
    @(posedge clk);#1;ck(obs_event && obs_valid && obs_item==1,"correct target waits in registered observation");
    @(negedge clk);block_event=0;card_event=0;card_revoke=1;key_replay_pulse=1;
    @(posedge clk);#1;
    ck(!answer_valid && score==0 && phase==1 && target_item==1 && question_index==1,
      "new fault prevents scoring queued correct answer and preserves question");
    ck(!audio_event_valid && !armed && audio_cancel && display_item==0,"new fault also defeats same-edge replay");
    @(negedge clk);card_revoke=0;key_replay_pulse=0;@(posedge clk);#1;idle_cycle();
    absence();recognized(1,0);
    ck(answer_valid && answer_correct && score==1,"fresh absence and result recover quiz scoring");

    start_case("twenty scored questions cover rotating fourteen-item bank");
    reset_key();change_mode();change_mode();
    for(round=0;round<2;round=round+1)begin
      for(q=0;q<10;q=q+1)begin
        item=bank[(round*10+q)%14];
        ck(mode==2 && phase==1 && question_index==q+1 && target_item==item,"rotating target has correct session position");
        absence();recognized(item,q%3);
        ck(answer_valid && answer_correct && score==q+1 && phase==2,"paired stable correct object scores once");
        ck(audio_event_valid && audio_event_kind==3 && audio_event_item==item,"answer audio event names actual target");
        recognized(item,0);ck(!answer_valid && score==q+1,"persistent target cannot score twice");
        millisecond();millisecond();
        if(q==9)ck(phase==3 && !quiz_active && question_index==10 && score==10,"ten-question round ends without question eleven");
      end
      if(round==0)begin change_mode();change_mode();change_mode();end
    end
    start_case("OSD target and observed object stay separate in a question");
    reset_key();change_mode();change_mode();
    // First target is red circle; display an unarmed umbrella without scoring.
    recognized(14,0);ck(target_item==1 && display_item==14 && score==0,"target is not fabricated from observation");
    snapshot();object_glyph(14);
    @(negedge clk);pixel_x=48+32*4;pixel_y=612;#1;
    @(posedge clk);#1;ck(renderer.panel.content.glyph===items14_ref_text(28,0),"question line still names target red circle");
    @(posedge clk);#1;

    start_case("new K3 display routing, all key priorities, quiz completion");
    reset_key();keys(0,0,1,0,1);ck(requested && mode==0 && score==0 && !audio_event_valid,"idle K3 flips image only, including FS edge");
    keys(1,0,1,0,0);ck(mode==1 && requested,"K1 suppresses simultaneous K3 toggle");
    keys(1,1,1,1,1);ck(mode==0 && !requested && score==0,"K4 wins and requests original image on FS edge");
    change_mode();recognized(1,0);keys(0,1,0,0,0);ck(!requested,"K2 replay keeps display selection");
    keys(0,0,1,0,0);ck(requested && mode==1,"explore K3 changes request");
    keys(1,0,1,0,0);ck(mode==2 && requested,"enter quiz with simultaneous K3 preserves request");
    for(q=0;q<10;q++)keys(0,0,1,0,0);
    ck(phase==3 && !quiz_active && requested && score==0,"ten quiz skips end round without changing image");
    keys(0,0,1,0,1);ck(phase==3 && requested && question_index==10,"completion page K3 never flips image");
    reset_key();change_mode();recognized(1,0);color_fresh=1;
    full_frame(0);ck(requested && !answer_valid && score==0,"mid-frame explore K3 only queues image change");
    full_frame(1);change_mode();absence();
    full_frame(2);
    start_case("live diagnostic invalidation and recovery cannot revive old snapshot");
    @(negedge clk);color_fresh=0;repeat(3)@(negedge clk);diagnostic_strip(3,520,591);
    color_fresh=1;repeat(3)@(negedge clk);diagnostic_strip(3,520,531);
    snapshot();diagnostic_strip(2,520,531);
    @(negedge clk);card_revoke=1;color_fresh=0;@(posedge clk);#2;
    @(negedge clk);card_revoke=0;repeat(3)@(negedge clk);
    full_frame(3);
    start_case("asynchronous reset removes full-chain pixels");
    @(negedge clk);rst_n=0;#2;ck(!out_de && out_rgb==0 && !logo_marker,"reset clears output validity independent of ROM initialization");
    ck(!inject_fault || injected==1,"negative mode injected exactly one final-video output error");
    test_done=1;$display("RESULT tb_shape27_render errors=%0d checks=%0d scenarios=%0d injected=%0d",errors,checks,scenarios,injected);$finish;
  end
  initial begin #120000000;errors=errors+1;$display("WATCHDOG tb_shape27_render");$finish;end
endmodule
