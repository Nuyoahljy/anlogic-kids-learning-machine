`timescale 1ns/1ps
module tb_pixel14_pipeline #(parameter integer FULL=0);
  localparam FW=FULL?1280:256,FH=FULL?720:256,CX=FULL?400:64,CY=FULL?120:64,CS=FULL?480:128;
  reg capture_clk=0,display_clk=0,cap_run=1;
  integer cap_half=5,display_half=7;
  always #(cap_half) if(cap_run) capture_clk=~capture_clk;
  always #(display_half) display_clk=~display_clk;
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
  pixel14_pipeline #(.FRAME_WIDTH(FW),.FRAME_HEIGHT(FH),.CARD_X(CX),.CARD_Y(CY),.CARD_SIZE(CS),
    .BLOCK_X_MIN(FULL?80:8),.BLOCK_X_MAX(FULL?239:55),.BLOCK_Y_MIN(FULL?30:8),.BLOCK_Y_MAX(FULL?149:55),
    .BLOCK_MIN_AREA(16),.ENABLE_OUTPUT(1),.TIMEOUT_MS(5),.FEEDBACK_TICKS(2)) dut(.*);
  integer errors=0,checks=0,scenarios=0,injected=0,inject_fault=0,unused;
  reg test_done=0;
  integer tag=0,item,i,healthy_events=0,revoke_events=0,answers=0,speech=0,old_events;
  integer last_item=0,last_count=0,last_tag=0;
  reg last_present=0,last_valid=0,last_source=0;
  reg [4:0] templates[0:1023];
  task ck(input bit ok,input string msg);
    begin checks++;if(!ok)begin errors++;$display("FAIL pipeline case=%0d time=%0t %s obs=%0d/%0d/%0d tag=%0d fault=%b",scenarios,$time,msg,obs_healthy,obs_valid,obs_item,obs_frame_id,link_fault);end end
  endtask
  task start_case(input string msg);begin scenarios++;$display("CASE pipeline %0d %s",scenarios,msg);end endtask
  always @(posedge display_clk) begin
    #1;
    if(rst_n)begin
      if(obs_event && obs_healthy && !obs_revoke)begin
        healthy_events++;last_item=obs_item;last_count=obs_count;last_tag=obs_frame_id;
        last_present=obs_present;last_valid=obs_valid;last_source=obs_source_test;
        ck(!obs_valid || (obs_item>=1 && obs_item<=14),"legal unified item");
      end
      if(obs_revoke)revoke_events++;
      if(answer_valid)answers++;
      if(audio_event_valid)speech++;
    end
  end
  function [23:0] rgb_at(input integer kind,input integer x,input integer y);
    integer index;
    begin
      rgb_at=24'hffffff;
      if(kind>=10 && kind<=14 && x>=CX && x<CX+CS && y>=CY && y<CY+CS)begin
        index=((y-CY)/(CS/32))*32+(x-CX)/(CS/32);
        if(templates[index][kind-10])rgb_at=24'h000000;
      end
      if(kind==2 && x>=CX+CS/4 && x<CX+CS*3/4 && y>=CY+CS/4 && y<CY+CS*3/4)rgb_at=24'hff2020;
      if(kind==1 && x==(FULL?321:33) && y==(FULL?121:33))rgb_at=24'h000000; // missed by both samplers
    end
  endfunction
  task settle;begin repeat(80)@(negedge capture_clk);end endtask
  task start_frame;
    begin tag++;@(negedge capture_clk);in_frame_id=tag;in_frame_start=1;
      @(negedge capture_clk);in_frame_start=0;end
  endtask
  task pixels(input integer kind,input integer stop_y);
    integer x,y,l;
    begin
      for(y=0;y<stop_y;y++)for(x=0;x<FW;x+=4)begin
        in_valid=1;in_eol=x==FW-4;
        for(l=0;l<4;l++)in_rgb96[95-l*24 -:24]=rgb_at(kind,x+l,y);
        @(negedge capture_clk);
      end
      in_valid=0;in_eol=0;in_rgb96=0;
    end
  endtask
  task finish_frame(input bit good);
    begin
      in_frame_done=1;in_frame_good=good;in_done_id=tag;in_done_source_test=in_source_test;
      @(negedge capture_clk);in_frame_done=0;
    end
  endtask
  task frame(input integer kind,input bit good);
    begin start_frame;pixels(kind,FH);finish_frame(good);settle;end
  endtask
  task expect_frame(input integer kind,input integer count,input bit present);
    begin
      ck(last_tag==tag && !link_fault,"both near-adjacent classifier events delivered as one frame without mailbox overrun");
      ck(last_item==kind && last_count==count && last_present==present && last_valid==(kind!=0),"expected current-frame classification, presence and confirmation");
    end
  endtask
  task pulse_tick;
    begin @(negedge display_clk);tick_1ms=1;@(negedge display_clk);tick_1ms=0;end
  endtask
  task clear_epoch;
    begin @(negedge display_clk);flush=1;repeat(30)@(negedge display_clk);flush=0;settle;end
  endtask
  task mode_key;
    begin @(negedge display_clk);key_mode_pulse=1;@(negedge display_clk);key_mode_pulse=0;settle;end
  endtask
  initial begin
    unused=$value$plusargs("INJECT_FAULT=%d",inject_fault);
    $readmemh("templates.mem",templates);
    start_case("reset settles without permanent reverse clear feedback");
    repeat(6)@(negedge capture_clk);rst_n=1;settle;
    ck(!link_fault && !quarantined && !obs_valid,"startup handshake settles");
    mode_key;ck(mode==1,"exploration mode through physical pulse interface");
    start_case("healthy empty frames arm exploration using both current-frame records");
    for(i=0;i<3;i++)begin frame(0,1);expect_frame(0,0,0);end
    ck(armed,"three full empty frames arm");
    for(item=10;item<=14;item++)begin
      start_case($sformatf("full RGB96 card item %0d three-frame confirmation",item));
      for(i=1;i<=3;i++)begin
        frame(item,1);
        ck(last_tag==tag && last_present && !link_fault,"card and block results remain paired and current");
        ck(last_valid==(i==3) && last_item==(i==3?item:0),"new card requires exactly three complete frames");
      end
      if(inject_fault && injected==0)begin force dut.diag_best=11'd1;injected=1;#1;end
      ck(diag_best==0 && diag_second>diag_best && diag_sample_fg>0,"template diagnostics cross with matching card event");
      if(inject_fault && injected==1)release dut.diag_best;
      ck(display_item==item,"business display accepts real pixel recognition");
    end
    start_case("per-frame colored square integrates the block route");
    for(i=1;i<=3;i++)begin frame(2,1);ck(last_tag==tag && !link_fault,"block packet delivered");
      ck(last_valid==(i==3) && last_item==(i==3?2:0),"square confirmation belongs to current frame");end
    start_case("a foreground speck outside sampled centers cannot become absence");
    frame(1,1);expect_frame(0,0,1);
    start_case("real pixel card answer increments score once after explicit removal");
    mode_key;ck(mode==2 && target_item==1,"quiz starts from first bank slot");
    @(negedge display_clk);key_skip_pulse=1;
    @(negedge display_clk);key_skip_pulse=0;settle;
    ck(target_item==10 && score==0,"skip reaches apple question without scoring");
    for(i=0;i<3;i++)frame(0,1);
    ck(armed,"quiz armed by actual empty raster");
    old_events=answers;
    for(i=0;i<3;i++)frame(10,1);
    ck(score==1 && answers==old_events+1 && feedback==1,"stable apple pixels produce one correct answer");
    frame(10,1);ck(score==1 && answers==old_events+1,"holding apple does not rescore");
    mode_key;mode_key;ck(mode==1,"return to exploration for recovery tests");
    start_case("bad capture closes withdraw stale recognition and permit three-frame recovery");
    old_events=revoke_events;frame(10,0);
    ck(revoke_events>old_events && !obs_valid && !armed && display_item==0 && !link_fault,"bad EOF revokes without permanent transport fault");
    for(i=1;i<=3;i++)begin frame(10,1);ck(last_valid==(i==3),"fault recovery restarts confirmation");end
    start_case("capture clock stops while display timeout continues");
    @(negedge capture_clk);cap_run=0;
    for(i=0;i<5;i++)pulse_tick;
    repeat(12)@(negedge display_clk);
    ck(timed_out && !obs_valid && !armed && display_item==0,"display watchdog revokes without capture clock");
    cap_run=1;settle;
    for(i=1;i<=3;i++)begin frame(10,1);ck(last_valid==(i==3) && !link_fault,"stopped-clock recovery starts from zero confirmation");end
    start_case("held external flush clears all complete frames and release mid-frame");
    @(negedge display_clk);flush=1;settle;old_events=healthy_events;
    for(i=0;i<3;i++)frame(11,1);
    ck(healthy_events==old_events && !obs_valid,"held flush suppresses all frames");
    start_frame;pixels(11,FH/2);
    @(negedge display_clk);flush=0;
    // The release-frame tail has no new SOF and must remain untrusted.
    @(negedge capture_clk);pixels(11,FH/2);finish_frame(1);settle;
    ck(healthy_events==old_events && !obs_valid,"mid-frame release cannot publish pre-cleared work");
    for(i=1;i<=3;i++)begin frame(11,1);ck(last_valid==(i==3),"held-flush release requires three fresh frames");end
    start_case("replayed frame IDs revoke and cannot be relabelled by repeated HDMI frames");
    tag--;old_events=revoke_events;frame(11,1);
    ck(revoke_events>old_events && !obs_valid && !link_fault,"duplicate acquisition tag rejected");
    for(i=0;i<20;i++)begin @(negedge display_clk);video_frame_start=1;@(negedge display_clk);video_frame_start=0;end
    ck(!obs_valid && !armed,"display frames do not manufacture capture observations");
    start_case("source switch requires explicit epoch clear");
    in_source_test=1;old_events=revoke_events;frame(12,1);
    ck(revoke_events>old_events && !obs_valid,"unannounced source switch rejected");
    clear_epoch;
    for(i=1;i<=3;i++)begin frame(12,1);ck(last_valid==(i==3) && last_source,"new epoch retains TEST provenance");end
    start_case("next frame capture overlaps previous frame distance ranking");
    old_events=healthy_events;
    start_frame;pixels(12,FH);finish_frame(1);
    start_frame;pixels(12,FH);finish_frame(1);settle;
    ck(healthy_events==old_events+2 && last_tag==tag && last_item==12 && !link_fault,
       "two independent frame records survive minimum drain gap and concurrent ranking");
    start_case("EOF immediately followed by SOF is explicitly revoked");
    old_events=revoke_events;start_frame;pixels(12,FH);finish_frame(1);
    in_frame_start=1;tag++;in_frame_id=tag;
    @(negedge capture_clk);in_frame_start=0;settle;
    ck(revoke_events>old_events && !obs_valid && !link_fault,"missing matcher drain gap is rejected");
    start_case("a second short external flush during reverse quarantine is not lost");
    cap_half=11;display_half=5;clear_epoch;old_events=healthy_events;
    fork
      begin
        @(negedge display_clk);flush=1;@(negedge display_clk);flush=0;
        wait(dut.quiet_count==1 && dut.reverse_ready);
        @(negedge display_clk);flush=1;@(negedge display_clk);flush=0;
      end
      begin
        wait(dut.reverse_event===1'b1);
        start_frame;pixels(12,FH);finish_frame(1);settle;
      end
    join
    ck(healthy_events==old_events && !obs_valid && !link_fault,"second clear cancels a frame started after the first clear");
    for(i=1;i<=3;i++)begin frame(12,1);ck(last_valid==(i==3),"short-clear recovery requires fresh confirmation");end
    start_case("video RGB, blanking and sync retain one-cycle alignment");
    for(i=0;i<32;i++)begin
      @(negedge display_clk);pixel_x=220;pixel_y=300;
      video_de=i%3!=0;video_vsync=i[0];video_hsync=i[1];video_rgb=24'h123400+i;
      @(posedge display_clk);#2;
      ck(out_de==video_de && out_vsync==video_vsync && out_hsync==video_hsync,"sync and DE latency match RGB");
      ck(out_rgb==(video_de?video_rgb:24'd0),"outside OSD and ROI, RGB is unchanged or blanked");
    end
    ck(!inject_fault || injected==1,"one deliberate DUT output corruption was checked");
    test_done=1;$display("RESULT pixel14_pipeline errors=%0d checks=%0d scenarios=%0d injected=%0d",errors,checks,scenarios,injected);$finish;
  end
  initial begin #1000000000;errors++;$display("WATCHDOG pipeline");$finish;end
endmodule
