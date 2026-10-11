`timescale 1ns/1ps
// Result-record integration: the classifier and camera are deliberately upstream.
module tb_items14_system;
  reg clk=0;
  always #5 clk=~clk;
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
  items14_system #(.TIMEOUT_MS(5),.ABSENT_SAMPLES(3),.FEEDBACK_TICKS(2)) dut(.*);
  `include "items14_text_reference.svh"
  integer errors=0,checks=0,scenarios=0,injected=0;
  reg test_done=0;
  integer inject_fault=0,ignored,item,j,q,round,tag=0;
  integer bank[0:13];
  task ck(input bit ok,input string msg);
    begin checks=checks+1;if(!ok)begin errors=errors+1;
      $display("FAIL system case=%0d t=%0t %s mode=%0d q=%0d target=%0d score=%0d obs=%0d/%0d/%0d",scenarios,$time,msg,mode,question_index,target_item,score,obs_event,obs_valid,obs_item);end end
  endtask
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
      ck(dut.panel.content.glyph===items14_ref_text(which>=1&&which<=14?27+which:27,0),"display first glyph follows snapshotted detected object");
      @(posedge clk);#1;ck(osd_active,"detected-name pixel belongs to lower panel");
    end
  endtask
  task millisecond;
    begin @(negedge clk);tick_1ms=1;block_event=0;card_event=0;@(posedge clk);#1;
      @(negedge clk);tick_1ms=0;@(posedge clk);#1;end
  endtask
  initial begin
    ignored=$value$plusargs("INJECT_FAULT=%d",inject_fault);
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
      if(inject_fault && item==13)begin force dut.control.display_item=4'd15;injected=1;#1;end
      ck(display_item==item,"fourteen-class display item accepted");
      if(inject_fault && item==13)release dut.control.display_item;
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
    ck(!osd_active && osd_rgb==0,"central ROI remains unobscured");

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
    ck(dut.panel.content.glyph===items14_ref_text(7,0),"new OSD source line remains TEST after timeout");
    @(posedge clk);#1;
    @(negedge clk);pixel_x=48;pixel_y=644;#1;
    ck(dut.panel.content.glyph===items14_ref_text(42,0),"new OSD snapshot includes unhealthy warning");
    @(posedge clk);#1;
    @(negedge clk);pixel_x=48+32*5;pixel_y=676;#1;
    ck(dut.panel.content.glyph===items14_ref_text(43,5),"unhealthy name field differs from stale car name");
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
    ck(dut.panel.content.glyph===items14_ref_text(28,0),"question line still names target red circle");
    @(posedge clk);#1;
    ck(!inject_fault || injected==1,"negative mode injected exactly one actual output error");
    test_done=1;$display("RESULT tb_items14_system errors=%0d checks=%0d scenarios=%0d injected=%0d",errors,checks,scenarios,injected);$finish;
  end
  initial begin #1000000;errors=errors+1;$display("WATCHDOG tb_items14_system");$finish;end
endmodule
