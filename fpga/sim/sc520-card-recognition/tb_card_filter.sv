`timescale 1ns/1ps
module tb_card_filter;
  reg clk=0;always #5 clk=~clk;
  reg rst_n=0,flush=0,in_frame=0,in_healthy=0,in_present=0,in_valid=0,in_source_test=0;
  reg [3:0]in_item=0;reg[31:0]in_frame_id=0;
  wire out_frame,out_healthy,out_present,out_valid,out_source_test;
  wire[3:0]out_item;wire[31:0]out_frame_id;wire[7:0]stable_count;
  integer errors=0,checks=0,scenarios=0;reg test_done=0;
  integer count=0,candidate=0,k;reg source=0;
  card_result_filter dut(.*);
  task ck(input bit ok,input string label);begin checks=checks+1;if(!ok)begin errors=errors+1;$display("ERROR filter %s",label);end end endtask
  task tick;begin @(posedge clk);#1;end endtask
  task sample(input bit healthy,input bit present,input bit valid,input integer item,input bit src);
    bit accepted;begin
      scenarios=scenarios+1;@(negedge clk);in_frame=1;in_frame_id=in_frame_id+1;
      in_healthy=healthy;in_present=present;in_valid=valid;in_item=item;in_source_test=src;
      accepted=healthy && present && valid && item>=10 && item<=14;
      if(!accepted)begin count=0;candidate=0;source=0;end
      else if(candidate!=item || source!=src || count==0)begin count=1;candidate=item;source=src;end
      else if(count<255)count=count+1;
      tick();
      ck(out_frame,"one result per input frame");ck(out_healthy===healthy,"health metadata");
      ck(out_present===(healthy?present:1'b1),"bad frame remains present/unknown");
      ck(out_valid===(accepted && count>=3),"exact three-frame confirmation or immediate withdrawal");
      ck(out_item===((accepted && count>=3)?item:0),"confirmed item only");
      ck(stable_count===count,"stability counter and saturation");
      ck(out_frame_id===in_frame_id && out_source_test===src,"metadata and source");
      @(negedge clk);in_frame=0;tick();ck(!out_frame,"out_frame pulse width");
    end
  endtask
  initial begin
    repeat(3)tick();@(negedge clk);rst_n=1;
    sample(1,1,1,10,0);sample(1,1,1,10,0);sample(1,1,1,10,0);sample(1,1,1,10,0);
    sample(1,1,0,0,0);sample(1,1,1,10,0);sample(1,1,1,10,0);sample(1,1,1,10,0);
    sample(0,0,1,10,0);sample(1,1,1,11,0);sample(1,1,1,11,0);sample(1,1,1,11,0);
    sample(1,0,0,0,0);sample(1,1,1,12,0);sample(1,1,1,12,1);sample(1,1,1,12,1);sample(1,1,1,12,1);
    sample(1,1,1,14,1);sample(1,1,1,14,1);sample(1,1,1,14,1);
    for(k=0;k<16;k=k+1)if(k<10||k>14)sample(1,1,1,k,0);
    for(k=0;k<260;k=k+1)sample(1,1,1,13,0);
    @(negedge clk);flush=1;in_frame=1;tick();ck(!out_frame && !out_valid && stable_count==0,"flush overrides coincident frame");
    @(negedge clk);flush=0;in_frame=0;count=0;candidate=0;source=0;
    sample(1,1,1,13,0);sample(1,1,1,13,0);
    @(negedge clk);rst_n=0;tick();ck(!out_frame && !out_valid && stable_count==0,"reset cancels pending stability");
    @(negedge clk);rst_n=1;count=0;candidate=0;source=0;
    sample(1,1,1,13,0);sample(1,1,1,13,0);sample(1,1,1,13,0);
    test_done=1;$display("RESULT tb_card_filter errors=%0d checks=%0d scenarios=%0d",errors,checks,scenarios);$finish;
  end
  initial begin #1000000;errors=errors+1;$display("WATCHDOG tb_card_filter");$finish;end
endmodule
