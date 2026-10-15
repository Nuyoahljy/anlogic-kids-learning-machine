`timescale 1ns/1ps
module tb_pixel14_observation;
  reg clk=0,dclk=0,cap_run=1;always #5 if(cap_run)clk=~clk;always #7 dclk=~dclk;
  reg rst_n=0,flush=0,color_event=0,color_good=1,analysis_event=0,analysis_good=1;
  reg [622:0] color_data=0;
  reg [31:0] analysis_id=0;
  reg [148:0] analysis_data=0;
  wire out_event;wire [799:0] out_packet;
  pixel14_observation_join dut(.*);
  reg bridge_event=0;reg [799:0] bridge_packet=0;
  reg tick=0,rev=0;
  wire [799:0] received;wire fresh,fault;wire [7:0] age;
  pixel14_observation_bridge #(.TIMEOUT_MS(5)) bridge(.rst_n(rst_n),.capture_clk(clk),.display_clk(dclk),
    .src_event(bridge_event),.src_packet(bridge_packet),.tick_1ms(tick),.display_revoke(rev),
    .display_packet(received),.fresh(fresh),.fault(fault),.age_ms(age));
  integer errors=0,checks=0,scenarios=0,injected=0,inject_fault=0,unused,i;
  reg test_done=0;
  reg [622:0] expected_color;
  reg [799:0] expected_packet;
  reg [31:0] observed_tag=0;
  always @(negedge dclk)begin
    if(rst_n && fresh && received[31:0]!=observed_tag)begin
      ck(age==0,"newly visible packet has its own zero age even on delivery edge");
      observed_tag=received[31:0];
    end
  end
  task ck(input bit ok,input string message);begin checks++;if(!ok)begin errors++;$display("FAIL observation %0d %s",scenarios,message);end end endtask
  task newcase(input string message);begin scenarios++;$display("CASE observation %0d %s",scenarios,message);end endtask
  task quiet;begin @(negedge clk);color_event=0;analysis_event=0;flush=0;@(posedge clk);#1;end endtask
  task color(input integer tag,input bit good);
    begin @(negedge clk);color_data={19{32'hb16f83a5}};color_data[31:0]=tag;color_good=good;color_event=1;analysis_event=0;@(posedge clk);#1;end
  endtask
  task analyze(input integer tag,input bit good);
    begin @(negedge clk);analysis_id=tag;analysis_good=good;analysis_data={4{32'hf1596db2}};analysis_event=1;color_event=0;@(posedge clk);#1;end
  endtask
  task emit(input integer tag,input bit complete);
    begin
      @(negedge clk);bridge_packet={25{32'h0357aff1}};bridge_packet[31:0]=tag;bridge_packet[780]=complete;
      expected_packet=bridge_packet;bridge_event=1;@(negedge clk);bridge_event=0;repeat(24)@(negedge dclk);
    end
  endtask
  task age_tick;begin @(negedge dclk);tick=1;@(negedge dclk);tick=0;end endtask
  initial begin
    unused=$value$plusargs("INJECT_FAULT=%d",inject_fault);
    newcase("reset starts without trusted data");repeat(5)@(negedge clk);rst_n=1;repeat(20)@(negedge clk);ck(!fresh&&!out_event,"empty reset");
    newcase("two capture banks join by exact identity in reversed completion order");
    color(100,1);expected_color=color_data;quiet;color(101,1);quiet;
    analyze(101,1);ck(out_event && out_packet[780] && out_packet[31:0]==101 && out_packet[771:623]==analysis_data,"bank1 exact pair");quiet;
    analyze(100,1);ck(out_packet[780] && out_packet[622:0]==expected_color,"bank0 preserved while bank1 consumed");quiet;
    newcase("unknown analysis cannot reuse earlier color");analyze(100,1);ck(out_event&&!out_packet[780]&&out_packet[779:772]==16,"consumed tag is incomplete");quiet;
    newcase("same-cycle complete pair includes current data");
    @(negedge clk);color_event=1;color_good=1;color_data=623'd77;analysis_event=1;analysis_good=1;analysis_id=77;analysis_data=149'h123456789;
    @(posedge clk);#1;ck(out_event&&out_packet[780]&&out_packet[622:0]==color_data&&out_packet[771:623]==analysis_data,"same-cycle pair");quiet;
    analyze(77,1);ck(!out_packet[780],"same-cycle pair not left pending");quiet;
    newcase("duplicate color and missing/full buffer are rejected");color(201,1);quiet;color(201,1);ck(!out_packet[780]&&out_packet[779:772]==2,"duplicate color");quiet;
    color(201,1);quiet;color(202,1);quiet;color(203,1);ck(!out_packet[780]&&out_packet[779:772]==4,"overflow diagnosed");quiet;
    analyze(201,1);ck(!out_packet[780],"overflow cannot mix old sample");quiet;
    newcase("bad raster and bad semantic snapshot remain incomplete");color(300,0);ck(!out_packet[780],"bad color reject");quiet;
    color(301,1);quiet;analyze(301,0);ck(!out_packet[780]&&out_packet[779:772]==8,"bad semantics reject");quiet;
    newcase("flush drops pending identity and emits one invalidation");color(400,1);quiet;
    @(negedge clk);flush=1;@(posedge clk);#1;ck(out_event&&!out_packet[780]&&out_packet[779:772]==1,"flush invalidation");
    @(posedge clk);#1;ck(!out_event,"held flush not repeated");quiet;analyze(400,1);ck(!out_packet[780],"no old record after flush");quiet;
    newcase("all800 payload bits cross the actual asynchronous mailbox atomically");emit(1,1);
    if(inject_fault)begin force bridge.display_packet=800'd0;injected=1;#1;end
    ck(fresh&&!fault&&received===expected_packet,"full atomic packet");
    if(inject_fault)release bridge.display_packet;
    newcase("replayed complete tags are rejected but incomplete tags remain visible");emit(1,1);ck(!received[780]&&received[779:772]==32,"replayed tag");emit(1,0);ck(fresh&&!received[780],"new incomplete event");
    newcase("new complete tag recovers and five ticks expire even with stopped capture");emit(2,1);ck(fresh&&received[780],"fresh recovery");
    @(negedge clk);cap_run=0;for(i=0;i<5;i++)age_tick;ck(!fresh&&age>=5,"display timeout independent of capture");cap_run=1;
    newcase("display revoke invalidates data immediately");emit(3,1);@(negedge dclk);rev=1;#1;ck(!fresh,"combinational revoke gate");@(negedge dclk);rev=0;ck(!fresh,"held stale record not rehabilitated");
    emit(4,1);ck(fresh&&received[31:0]==4,"new capture required for freshness");
    newcase("back-to-back source overruns become incomplete, never a silently reused good packet");
    @(negedge clk);bridge_packet=0;bridge_packet[31:0]=5;bridge_packet[780]=1;bridge_event=1;
    @(negedge clk);bridge_packet[31:0]=6;
    @(negedge clk);bridge_packet[31:0]=7;
    @(negedge clk);bridge_event=0;repeat(40)@(negedge dclk);
    ck(fresh&&!received[780]&&received[779:772]==64&&received[31:0]==7,"overflow last identity and explicit reason retained");
    emit(8,1);ck(fresh&&received[780]&&received[31:0]==8,"normal new identity recovers after busy overflow");
    test_done=1;$display("DONE observation checks=%0d errors=%0d",checks,errors);$finish;
  end
  initial begin #1000000;$display("WATCHDOG observation");$finish;end
endmodule
