`timescale 1ns/1ps
// Real color RTL -> real capture/scene/rotation/shape/business RTL. External
// qualified EOF is supplied after the observed color-output tail has drained.
// This does not exercise CSI, RAW decoding, DDR, HDMI PHY or physical RAM.
module tb_shape27_reset;
  real release_phase=0.73;
  wire [27:0] render_state;
  localparam integer GROUPS=320,HEIGHT=720,TOTAL=230400,HBLANK=80;
  reg capture_clk=0,display_clk=0;
  reg cap_run=1; always #4.83 if(cap_run)capture_clk=~capture_clk;
  always #6.6665 display_clk=~display_clk;
  reg rst_n=0,src_sof=0,src_valid=0,src_eol=0;
  reg [95:0] src_rgb=0;
  wire in_frame_start,in_valid,in_eol,src_ready;
  wire [95:0] in_rgb96;
  wire [95:0] diag_pre_wb,diag_post_wb;
  wire [8:0] diag_gain_r,diag_gain_b;
  wire [31:0] diag_pixel_id,diag_stats_id;
  wire diag_stats_event,diag_stats_good;
  wire [20:0] diag_neutral_count;
  wire [799:0] color_diag_packet;
  wire color_diag_fresh,color_diag_fault;
  wire [7:0] color_diag_age;
  reg [31:0] in_frame_id=0,in_done_id=0;
  reg [1:0] metadata_fault=0;
  wire [31:0] tap_stats_id,tap_pixel_id;
  wire tap_stats_event;
  assign diag_pixel_id=metadata_fault==2 ? tap_pixel_id^32'd1:tap_pixel_id;
  assign diag_stats_id=metadata_fault==1 ? tap_stats_id^32'd1:tap_stats_id;
  assign diag_stats_event=metadata_fault==3 ? 1'b0:tap_stats_event;
  pixel26_color_pipeline #(.DIAGNOSTICS(1)) color(
    .I_clk(capture_clk),.I_rst_n(rst_n),.I_tlast(src_eol),.I_tuser(src_sof),
    .I_tdata(src_rgb),.I_tvalid(src_valid),.I_tready(src_ready),
    .O_tlast(in_eol),.O_tuser(in_frame_start),.O_tdata(in_rgb96),.O_tvalid(in_valid),.O_tready(1'b1),.I_diag_frame_id(in_frame_id),
    .O_diag_pre_wb(diag_pre_wb),.O_diag_post_wb(diag_post_wb),.O_diag_gain_r(diag_gain_r),.O_diag_gain_b(diag_gain_b),
    .O_diag_pixel_id(tap_pixel_id),.O_diag_stats_done(tap_stats_event),.O_diag_stats_good(diag_stats_good),
    .O_diag_stats_id(tap_stats_id),.O_diag_neutral_count(diag_neutral_count));

  reg in_source_test=0,in_frame_done=0,in_frame_good=1,in_done_source_test=0,in_revoke=0;
  reg tick_1ms=0,flush=0,key_mode_pulse=0,key_replay_pulse=0,key_skip_pulse=0,key_reset_pulse=0;
  reg audio_idle=1,audio_fault=0,video_frame_start=0;
  reg [10:0] pixel_x=0;
  reg [9:0] pixel_y=0;
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
  pixel27_pipeline #(.ENABLE_OUTPUT(1),.USE_SCENE_ANALYSIS(1),.ROTATION_VARIANTS(256),.COLOR_DIAGNOSTICS(1),
    .TIMEOUT_MS(5),.FEEDBACK_TICKS(2)) dut(.*);

  reg [23:0] before_raster[0:57599],after_raster[0:57599];
  reg [95:0] expected[0:TOTAL-1],raw_expected[0:TOTAL-1];
  integer errors=0,checks=0,scenarios=0,injected=0,inject_fault=0,unused;
  reg test_done=0,frame_active=0;
  integer tag=0,cycles=0,first_input=-1,first_output=-1,input_groups=0,output_groups=0;
  integer input_lines=0,output_lines=0,frames_sent=0,frame_kind=0,black_groups=0,white_groups=0;
  integer healthy_events=0,revoke_events=0,answers=0,last_item=0,last_tag=0,last_count=0;
  reg last_present=0,last_valid=0;
  integer fd,cfd,fields,want_item,want_neutral,i,prior_answers,prior_score;
  string root_path,before_name,after_name;

  task ck(input bit ok,input string what);
    begin checks++;if(!ok)begin errors++;if(errors<20)$display("FAIL color-scene case=%0d frame=%0d time=%0t %s",scenarios,tag,$time,what);end end
  endtask
  task begin_case(input string what);
    begin scenarios++;$display("CASE color-scene %0d %s",scenarios,what);end
  endtask
  function [7:0] curve(input [7:0] v);
    integer knots[0:16];integer k;
    begin
      knots[0]=0;knots[1]=37;knots[2]=60;knots[3]=79;knots[4]=97;knots[5]=113;
      knots[6]=129;knots[7]=143;knots[8]=157;knots[9]=171;knots[10]=184;
      knots[11]=197;knots[12]=209;knots[13]=221;knots[14]=233;knots[15]=244;knots[16]=255;
      k=v/16;curve=v==255 ? 255 : knots[k]+((knots[k+1]-knots[k])*(v%16)+8)/16;
    end
  endfunction
  function [95:0] wb_word(input [95:0] value);
    integer i,gain,product;
    begin for(i=0;i<12;i++)begin
      gain=(i%3==0)?333:(i%3==2)?304:256;
      product=(value[i*8+:8]*gain)/256;
      wb_word[i*8+:8]=product>255?255:product;
    end end
  endfunction
  function [95:0] tone_word(input [95:0] value);
    integer byte_index;reg [95:0] wb;
    begin wb=wb_word(value);for(byte_index=0;byte_index<12;byte_index++)tone_word[byte_index*8+:8]=curve(wb[byte_index*8+:8]);end
  endfunction
  function [95:0] lane_probe(input integer gx,input integer gy);
    reg [23:0] lane2,lane3;
    begin
      lane2={8'(gx+gy),8'(gx*3+gy+83),8'(gx+gy*7+167)};
      lane3={8'(gx*5+gy+31),8'(gx+gy*3+119),8'(gx*7+gy+211)};
      lane_probe={lane3,lane2,24'hffffff,24'h000000};
    end
  endfunction
  always @(posedge capture_clk)begin
    cycles++;
    #1;
    if(rst_n && frame_active)begin
      if(src_sof)ck(in_frame_start===1 && !in_valid,"actual early SOF reaches capture before RGB");
      if(src_valid)begin
        if(first_input<0)first_input=cycles;
        ck(input_groups<TOTAL,"input raster has no extra RGB group");
        if(input_groups<TOTAL)begin
          expected[input_groups]=tone_word(src_rgb);
        end
        raw_expected[input_groups]=src_rgb;input_groups++;if(src_eol)input_lines++;
      end
      if(in_valid)begin
        if(first_output<0)first_output=cycles;
        if(inject_fault && injected==0 && output_groups==7)begin
          // Corrupt the live output of the actual color DUT, not the oracle.
          force color.O_tdata=96'h1;injected=1;#0.01;
          ck(in_rgb96===expected[output_groups],"injected live color output must fail RGB reference");
          release color.O_tdata;test_done=1;$fclose(fd);$display("DONE color-scene negative checks=%0d errors=%0d",checks,errors);$finish;
        end else begin
          ck(output_groups<input_groups && output_groups<TOTAL,"color output has an earlier matching input");
          if(output_groups<TOTAL)ck(in_rgb96===expected[output_groups],"all RGB bytes and four lanes match independent after reference");
          ck(diag_pre_wb===raw_expected[output_groups] && diag_post_wb===wb_word(raw_expected[output_groups]),"real parallel taps retain same four raw pixels at fixed field WB");
          ck(tap_pixel_id==tag && diag_gain_r==304 && diag_gain_b==333,"real tap frame/gain alignment");
          ck(in_eol===((output_groups%GROUPS)==GROUPS-1),"output EOL accompanies exact final group");
          ck(color.gain_r==304 && color.gain_b==333,"balanced reference freezes field WB for complete frame");
          if(frame_kind==0)begin
            if(in_rgb96[23:0]===24'h000000)black_groups++;
            if(in_rgb96[47:24]===24'hffffff)white_groups++;
          end
          output_groups++;if(in_eol)output_lines++;
        end
      end
    end
  end
  always @(posedge display_clk)begin
    #1;
    if(rst_n)begin
      if(obs_event && obs_healthy && !obs_revoke)begin
        healthy_events++;last_item=obs_item;last_tag=obs_frame_id;last_count=obs_count;
        last_present=obs_present;last_valid=obs_valid;
      end
      if(obs_revoke)revoke_events++;
      if(answer_valid)answers++;
    end
  end
  task drive(input bit s,input bit v,input bit e,input [95:0] rgb);
    begin @(negedge capture_clk);src_sof=s;src_valid=v;src_eol=e;src_rgb=rgb;end
  endtask
  task settle;begin repeat(80)@(negedge capture_clk);end endtask
  task reset_all;
    begin
      @(negedge capture_clk);rst_n=0;src_sof=0;src_valid=0;src_eol=0;src_rgb=0;
      in_frame_done=0;frame_active=0;flush=0;
      repeat(8)@(negedge capture_clk);#(release_phase);rst_n=1;settle;
      healthy_events=0;revoke_events=0;last_tag=0;last_item=0;last_valid=0;last_present=0;answers=0;
    end
  endtask
  task pulse_key(input integer key_index);
    begin
      @(negedge display_clk);
      case(key_index)1:key_mode_pulse=1;3:key_skip_pulse=1;default:key_reset_pulse=1;endcase
      @(negedge display_clk);key_mode_pulse=0;key_skip_pulse=0;key_reset_pulse=0;settle;
    end
  endtask
  task clear_epoch;
    begin @(negedge display_clk);flush=1;repeat(30)@(negedge display_clk);flush=0;settle;end
  endtask
  task load_card(input string before_file,input string after_file);
    begin
      $readmemh({root_path,"/mem/",before_file},before_raster);
      $readmemh({root_path,"/mem/",after_file},after_raster);
    end
  endtask
  reg [95:0] center_wb,paper_wb;
  task frame(input integer kind,input integer neutral_expect);
    integer px,py,blank,old_healthy,old_revoke,wait_cycles;
    reg [95:0] word;
    begin
      old_healthy=healthy_events;old_revoke=revoke_events;frames_sent++;tag++;
      input_groups=0;output_groups=0;input_lines=0;output_lines=0;
      first_input=-1;first_output=-1;black_groups=0;white_groups=0;
      frame_kind=kind;frame_active=1;in_frame_id=tag;
      drive(1,0,0,0);drive(0,0,0,0);repeat(8)drive(0,0,0,0);
      for(py=0;py<HEIGHT;py++)begin
        for(px=0;px<GROUPS;px++)begin
          if(kind==0)word=lane_probe(px,py);
          else if(kind==2)word={4{24'ha5a5a5}};
          else word={4{before_raster[(py/4)*GROUPS+px]}};
          drive(0,1,px==GROUPS-1,word);
        end
        repeat(HBLANK)drive(0,0,0,0);
      end
      repeat(8)drive(0,0,0,0);
      ck(input_groups==TOTAL && output_groups==TOTAL,"complete 1280x720 input and output counts");
      ck(input_lines==720 && output_lines==720,"all input and output lines retained");
      ck(first_output-first_input==54,"actual input-to-output latency is54 capture clocks");
      ck(!in_valid && !in_eol && in_rgb96==0,"last output group and EOL fully drained before external EOF");
      ck(color.complete && !color.bad && !color.drop_frame,"color frame is geometrically complete");
      if(neutral_expect>=0)ck(color.neutral_count==neutral_expect,"whole-frame neutral sample count matches original RGB construction");
      if(kind==0)ck(black_groups==TOTAL && white_groups==TOTAL,"black and white endpoints retained in distinct lanes");
      in_done_id=tag;in_frame_done=1;@(negedge capture_clk);in_frame_done=0;
      wait_cycles=0;
      while(wait_cycles<1200000 && healthy_events==old_healthy && revoke_events==old_revoke)begin
        @(negedge capture_clk);wait_cycles++;
      end
      settle;
      ck(wait_cycles<1200000 && healthy_events==old_healthy+1 && revoke_events==old_revoke,"one fresh healthy scene result after qualified EOF");
      ck(last_tag==tag && !link_fault && !obs_conflict,"source tag preserved through color/capture/scene/business");
      ck(color_diag_packet[31:0]==tag && !color_diag_fault,"observation belongs to same acquisition tag");
      if(metadata_fault==0)begin
        ck(color_diag_fresh && color_diag_packet[780],"complete observation reaches display through real CDC");
        ck(color_diag_packet[412:404]==304 && color_diag_packet[421:413]==333 && color_diag_packet[442:422]==color.neutral_count,"gain and final neutral associated with correct frame");
        center_wb=wb_word(raw_expected[360*320+160]);paper_wb=wb_word(raw_expected[148*320+49]);
        ck(color_diag_packet[55:32]===raw_expected[360*320+160][95:72] && color_diag_packet[79:56]===center_wb[95:72] && color_diag_packet[103:80]===expected[360*320+160][95:72],"center fixed-coordinate triple sample");
        ck(color_diag_packet[127:104]===raw_expected[148*320+49][95:72] && color_diag_packet[151:128]===paper_wb[95:72] && color_diag_packet[175:152]===expected[148*320+49][95:72],"paper fixed-coordinate triple sample");
        ck(color_diag_packet[738:735]==last_item && color_diag_packet[749:739]==diag_best && color_diag_packet[760:750]==diag_second && color_diag_packet[771:761]==diag_sample_fg,"final item and matcher diagnostics share packet identity");
      end else ck(!color_diag_packet[780],"missing or corrupt metadata is explicitly incomplete without changing business pixels");

      $fwrite(fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",tag,kind,input_groups,output_groups,output_lines,
        first_output-first_input,color.gain_r,color.gain_b,color.neutral_count,last_item,last_count,score,answers,wait_cycles);
      frame_active=0;
    end
  endtask
  reg [1:0] expected_release=0;
  reg busy_old=0,color_busy_old=0,request_old=0,color_request_old=0;
  reg [131:0] held_old=0;
  reg [799:0] color_held_old=0;
  integer reset_edges=0,payload_checks=0;
  always @(negedge rst_n)begin
    #0.01;
    ck(dut.capture_reset===0 && dut.capture_release===0,"all capture reset branches assert asynchronously");
    ck(dut.color_observation.observer.joiner.out_packet===0,"observation packet clears without waiting for a clock");
  end
  always @(posedge capture_clk or negedge rst_n)
    if(!rst_n)expected_release<=0;else expected_release<={expected_release[0],1'b1};
  always @(posedge capture_clk)begin
    #0.02;
    if(rst_n)begin
      if(inject_fault && !injected && expected_release[1])begin
        force dut.capture_release[8]=0;injected=1;#0.01;
        ck(dut.capture_release[8]===expected_release[1],"live reset-release corruption is detected");
        release dut.capture_release[8];test_done=1;$fclose(fd);$finish;
      end
      ck(dut.crst===expected_release[1] && dut.capture_release==={9{expected_release[1]}},
         "all ten capture second stages release together at original second edge");
      reset_edges++;
    end
  end
  always @(posedge capture_clk)begin
    #1.1;
    if(!rst_n)begin busy_old=0;color_busy_old=0;end
    else begin
      if(busy_old && request_old===dut.forward.request)begin
        ck(dut.forward.held_data===held_old,"business payload stable throughout outstanding handshake");payload_checks++;
      end
      if(color_busy_old && color_request_old===dut.color_observation.transport.link.request)begin
        ck(dut.color_observation.transport.link.held_data===color_held_old,"800-bit observation payload stable throughout outstanding handshake");payload_checks++;
      end
      busy_old=dut.forward.request!=dut.forward.ack_sync;
      color_busy_old=dut.color_observation.transport.link.request!=dut.color_observation.transport.link.ack_sync;
      request_old=dut.forward.request;color_request_old=dut.color_observation.transport.link.request;
      held_old=dut.forward.held_data;color_held_old=dut.color_observation.transport.link.held_data;
    end
  end
  initial begin
    unused=$value$plusargs("INJECT_FAULT=%d",inject_fault);
    if(!$value$plusargs("ASSET_ROOT=%s",root_path))$fatal(1,"ASSET_ROOT required");
    fd=$fopen("observations.csv","w");
    $fwrite(fd,"tag,kind,input_groups,output_groups,output_lines,latency_clocks,gain_r,gain_b,neutral_samples,item,stable_count,score,answers,post_eof_wait_clocks\n");
    begin_case("phase0.73 reset and first complete720p four-lane frame");
    reset_all;frame(0,-1);
    begin_case("phase2.17 asynchronous reassertion,first good frame and same-cycle branch release");
    release_phase=2.17;reset_all;frame(2,921600);
    begin_case("phase4.41 release,first good frame and complete source-tag payload");
    release_phase=4.41;reset_all;frame(2,921600);
    begin_case("bad external EOF revokes prior observation,then fresh full-frame recovery");
    prior_answers=revoke_events;tag++;in_frame_id=tag;
    drive(1,0,0,0);drive(0,0,0,0);repeat(8)drive(0,0,0,0);
    for(i=0;i<20;i++)drive(0,1,0,{4{24'ha5a5a5}});
    repeat(100)drive(0,0,0,0);
    in_done_id=tag;in_frame_good=0;in_frame_done=1;
    @(negedge capture_clk);in_frame_done=0;in_frame_good=1;settle;
    ck(revoke_events>prior_answers && !obs_valid,"truncated bad frame cannot retain valid recognition");
    ck(!color_diag_fresh || !color_diag_packet[780],"bad frame cannot retain a trusted observation");
    clear_epoch;frame(2,921600);
    begin_case("metadata mismatch is incomplete,subsequent frame restores identity");
    metadata_fault=1;frame(2,921600);metadata_fault=0;frame(2,921600);
    begin_case("stopped capture expires both recognition and diagnostic validity");
    @(negedge capture_clk);cap_run=0;
    repeat(5)begin @(negedge display_clk);tick_1ms=1;@(negedge display_clk);tick_1ms=0;end
    repeat(8)@(negedge display_clk);ck(!color_diag_fresh && timed_out,"stopped source expires independently");
    begin_case("asynchronous reset while capture stopped clears all branches and payload");
    #2.31;rst_n=0;#0.1;
    ck(dut.capture_release===0 && dut.forward.held_data===0 && dut.color_observation.transport.link.held_data===0,
       "reset assertion does not require a running capture clock");
    cap_run=1;release_phase=1.39;reset_all;frame(2,921600);
    ck(payload_checks>20 && reset_edges>1000000,"meaningful reset-edge and busy-payload coverage");
    $fclose(fd);test_done=1;
    $display("DONE timing23-reset scenarios=%0d frames=%0d checks=%0d reset_edges=%0d payload_checks=%0d errors=%0d",scenarios,frames_sent,checks,reset_edges,payload_checks,errors);$finish;
  end
  initial begin #500000000;$display("WATCHDOG color-scene");$finish;end
endmodule
