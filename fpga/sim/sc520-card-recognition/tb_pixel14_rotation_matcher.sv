`timescale 1ns/1ps
module tb_pixel14_rotation_matcher;
  reg clk=0; always #5 clk=~clk;
  reg rst_n=0,flush=0,frame_start=0,sample_valid=0,sample_foreground=0,frame_end=0,frame_good=1,frame_present=1;
  reg [9:0] sample_index=0;
  reg [31:0] frame_id=0;
  reg frame_source_test=0;
  wire out_frame,out_healthy,out_present,out_valid,out_source_test;
  wire [3:0] out_item;
  wire [10:0] out_best,out_second,out_fg_count;
  wire [31:0] out_frame_id;
  pixel14_rotation_matcher #(.ENABLE_OUTPUT(1),.VARIANTS(3)) dut(.*);
  integer errors=0,checks=0,scenarios=0,injected=0,inject_fault=0,unused;
  reg test_done=0;
  integer events=0,old_events,c,v,i;
  task ck(input bit ok,input string msg);
    begin checks++;if(!ok)begin errors++;$display("FAIL matcher case=%0d %s",scenarios,msg);end end
  endtask
  task begin_case(input string msg);begin scenarios++;$display("CASE matcher %0d %s",scenarios,msg);end endtask
  always @(posedge clk)begin #1;if(out_frame)events++;end
  // Independent hand-defined family: 60 bits per class, variants shifted four
  // bits. Intra-class distance=8/16, inter-class distance=120 (disjoint sets).
  function bit pixel(input integer cls,input integer variant,input integer ix,input bit noise);
    integer px,py,cell_index;
    begin
      px=ix%32;py=ix/32;cell_index=(py-6)*20+px-6;pixel=0;
      if(px>=6 && px<26 && py>=6 && py<26)begin
        if(cls>=0)pixel=(cell_index>=cls*75+variant*4 && cell_index<cls*75+60+variant*4) || (noise && cell_index>=390 && cell_index<=391);
        else if(cls==-2)pixel=cell_index<30 || (cell_index>=75 && cell_index<105);
        else if(cls==-3)pixel=cell_index%2==0;
      end
    end
  endfunction
  task send_frame(input integer cls,input integer variant,input integer count,input bit good,input bit noise,input bit duplicate);
    integer ix;
    begin
      @(negedge clk);frame_id++;frame_start=1;old_events=events;
      @(negedge clk);frame_start=0;
      for(ix=0;ix<count;ix++)begin
        sample_valid=1;sample_index=duplicate && ix==100 ? 99:ix;
        sample_foreground=pixel(cls,variant,ix,noise);@(negedge clk);
      end
      sample_valid=0;frame_end=1;frame_good=good;frame_present=cls!=-1;
      @(negedge clk);frame_end=0;repeat(1300)@(negedge clk);
      ck(events==old_events+1,"one completion per submitted frame");
      ck(out_frame_id==frame_id && out_source_test==frame_source_test,"source and frame identity retained");
    end
  endtask
  initial begin
    unused=$value$plusargs("INJECT_FAULT=%d",inject_fault);
    repeat(4)@(negedge clk);rst_n=1;repeat(3)@(negedge clk);
    for(c=0;c<5;c++)for(v=0;v<3;v++)begin
      begin_case($sformatf("class %0d variant %0d independent distance",c,v));
      send_frame(c,v,1024,1,0,0);
      if(inject_fault && injected==0)begin force dut.out_item=0;injected=1;#1;end
      ck(out_valid && out_item==c+10 && out_healthy && out_present,"same-class close variants do not reduce class margin");
      if(inject_fault && injected==1)release dut.out_item;
      ck(out_best==0 && out_second==120 && out_fg_count==60,"exact template has analytical 0/120 distances");
    end
    begin_case("two extra noise pixels have known analytical distance");
    frame_source_test=1;send_frame(2,1,1024,1,1,0);
    ck(out_valid && out_item==12 && out_best==2 && out_second==122 && out_fg_count==62,"noise count and interclass margin");
    begin_case("empty remains healthy absent, never accepted");
    send_frame(-1,0,1024,1,0,0);ck(out_healthy && !out_present && !out_valid && out_item==0 && out_fg_count==0,"absence gate");
    begin_case("equal distance between different classes is unknown present");
    send_frame(-2,0,1024,1,0,0);ck(out_healthy && out_present && !out_valid && out_best==60 && out_second==60,"tie rejects");
    begin_case("unrelated texture rejected");
    send_frame(-3,0,1024,1,0,0);ck(out_healthy && out_present && !out_valid && out_best>40,"distance gate");
    begin_case("bad source health cannot be rehabilitated by exact template");
    send_frame(0,0,1024,0,0,0);ck(!out_healthy && out_present && !out_valid && out_item==0,"bad frame fail closed");
    begin_case("missing sample rejected");
    send_frame(0,0,1023,1,0,0);ck(!out_healthy && !out_valid && out_present,"count mismatch rejects");
    begin_case("duplicate sample index rejected");
    send_frame(0,0,1024,1,0,1);ck(!out_healthy && !out_valid,"index mismatch rejects");
    begin_case("excess sample rejected");
    send_frame(0,0,1025,1,0,0);ck(!out_healthy && !out_valid,"excess count rejects");
    begin_case("flush cancels partial capture and new exact frame recovers");
    old_events=events;@(negedge clk);frame_start=1;@(negedge clk);frame_start=0;sample_valid=1;sample_index=0;
    @(negedge clk);sample_valid=0;flush=1;repeat(5)@(negedge clk);flush=0;repeat(1300)@(negedge clk);
    ck(events==old_events && !out_valid,"flush produces no stale accepted event");
    send_frame(4,2,1024,1,0,0);ck(out_healthy && out_valid && out_item==14,"fresh recovery");
    test_done=1;$display("DONE matcher scenarios=%0d checks=%0d errors=%0d",scenarios,checks,errors);$finish;
  end
  initial begin #2000000;$display("WATCHDOG matcher");$finish;end
endmodule
