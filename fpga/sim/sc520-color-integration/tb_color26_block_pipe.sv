`timescale 1ns/1ps
module tb_color26_block_pipe;
  reg clk=0;always #5 clk=~clk;
  reg rst_n=0,flush=0,in_valid=0,in_sof=0,in_eol=0;
  reg [10:0] in_x=0;
  reg [9:0] in_y=0;
  reg [23:0] in_rgb=24'hffffff;
  reg in_frame_end=0,in_frame_good=1,in_frame_present=0,in_source_test=0;
  reg [31:0] in_frame_id=0;
  wire out_frame,out_healthy,out_present,out_valid,out_source_test,out_revoke;
  wire [3:0] out_item;
  wire [31:0] out_frame_id;
  wire [7:0] stable_count;
  pixel26_block_recognizer_piped #(.FRAME_WIDTH(64),.FRAME_HEIGHT(64),.X_MIN(8),.X_MAX(55),
    .Y_MIN(8),.Y_MAX(55),.MIN_AREA(16)) dut(.*);
  integer errors=0,checks=0,scenarios=0,injected=0,inject_fault=0,unused;
  reg test_done=0;
  integer tag=0,item,i,events=0,revokes=0,old_events,old_revokes;
  integer last_item,last_count,last_tag;
  reg last_valid,last_present,last_source;
  task ck(input bit ok,input string msg);begin checks++;if(!ok)begin errors++;$display("FAIL block %0d %s",scenarios,msg);end end endtask
  task new_case(input string msg);begin scenarios++;$display("CASE block %0d %s",scenarios,msg);end endtask
  always @(posedge clk)begin
    #1;
    if(out_revoke)revokes++;
    if(out_frame)begin
      events++;last_item=out_item;last_count=stable_count;last_tag=out_frame_id;
      last_valid=out_valid;last_present=out_present;last_source=out_source_test;
      ck(out_healthy,"only complete frames publish healthy records");
      if(inject_fault && injected==0 && out_valid)begin
        force dut.out_item=4'd15;injected=1;#0.01;
        ck(out_item>=1 && out_item<=9,"deliberately corrupted real DUT item is illegal");release dut.out_item;
      end else ck(!out_valid || (out_item>=1 && out_item<=9),"block item range");
    end
  end
  function [23:0] pixel(input integer kind,input integer x,input integer y);
    integer shape,c,dx,dy;
    reg hit;
    begin
      pixel=24'hffffff;hit=0;shape=(kind-1)%3+1;c=(kind-1)/3+1;dx=2*x-63;dy=2*y-63;
      if(kind>=1 && kind<=9)begin
        if(shape==2)hit=x>=24 && x<40 && y>=24 && y<40;
        if(shape==1)hit=dx*dx+dy*dy<=256;
        if(shape==3)hit=x>=24 && x<40 && y>=24 && y<40 && (dx<0?-dx:dx)<=y-24;
        if(hit)pixel=c==1 ? 24'hff2020 : c==2 ? 24'h93ac76 : 24'h2020ff;
      end
      if(kind==99 && x>=24 && x<40 && y>=24 && y<40)pixel=0;
      if(kind==97 && x>=8 && x<24 && y>=24 && y<40)pixel=24'hff2020;
      if(kind==96 && x>=24 && x<40 && y>=24 && y<40)pixel=x<32?24'hff2020:24'h2020ff;
    end
  endfunction
  task frame(input integer kind,input integer defect);
    integer x,y;
    begin
      tag++;in_frame_id=tag;
      for(y=0;y<(defect==1?63:64);y++)for(x=0;x<64;x++)begin
        @(negedge clk);in_valid=1;in_x=x;in_y=y;in_sof=x==0 && y==0;in_eol=x==63;in_rgb=pixel(kind,x,y);
        if(defect==2 && x==12 && y==12)in_x=13;
        if(defect==3 && x==12 && y==12)in_frame_id=tag+99;
        if(defect==4 && x==12 && y==12)in_source_test=~in_source_test;
        if(defect==5 && x==12 && y==12)in_eol=1;
      end
      @(negedge clk);in_valid=0;in_sof=0;in_eol=0;in_frame_end=1;
      in_frame_good=defect!=6;in_frame_present=kind!=0 && defect!=7;
      @(negedge clk);in_frame_end=0;repeat(10)@(negedge clk);
    end
  endtask
  task clear;
    begin @(negedge clk);flush=1;repeat(4)@(negedge clk);flush=0;repeat(3)@(negedge clk);end
  endtask

  wire ref_frame,ref_healthy,ref_present,ref_valid,ref_source,ref_revoke;
  wire [3:0] ref_item;wire [31:0] ref_id;wire [7:0] ref_count;
  pixel26_block_recognizer #(.FRAME_WIDTH(64),.FRAME_HEIGHT(64),.X_MIN(8),.X_MAX(55),
    .Y_MIN(8),.Y_MAX(55),.MIN_AREA(16)) reference(
    .out_frame(ref_frame),.out_healthy(ref_healthy),.out_present(ref_present),.out_valid(ref_valid),
    .out_item(ref_item),.out_frame_id(ref_id),.out_source_test(ref_source),.stable_count(ref_count),.out_revoke(ref_revoke),.*);
  reg [1:0] reference_events=0;reg [47:0] reference_data0=0,reference_data1=0;
  always @(posedge clk)begin
    if(!rst_n||flush)begin reference_events<=0;reference_data0<=0;reference_data1<=0;end
    else begin
      reference_events<={reference_events[0],ref_frame};
      reference_data0<={ref_healthy,ref_present,ref_valid,ref_item,ref_id,ref_source,ref_count};reference_data1<=reference_data0;
    end
    #1;
    if(rst_n&&!flush)begin
      ck(out_frame===reference_events[1],"completed event differs from exact two-cycle reference offset");
      if(out_frame)ck({out_healthy,out_present,out_valid,out_item,out_frame_id,out_source_test,stable_count}===reference_data1,
        "complete tag/source/health/item/count atomically follows two-cycle offset");
    end
  end

  initial begin
    unused=$value$plusargs("INJECT_FAULT=%d",inject_fault);
    repeat(5)@(negedge clk);rst_n=1;repeat(3)@(negedge clk);
    for(item=1;item<=9;item++)begin
      new_case($sformatf("full raster item %0d",item));
      for(i=1;i<=3;i++)begin
        old_events=events;frame(item,0);
        ck(events==old_events+1 && last_tag==tag && last_present,"one current complete record");
        ck(last_count==i && last_valid==(i==3) && last_item==(i==3?item:0),"exact three-frame classification");
      end
    end
    new_case("healthy empty resets stable state");frame(0,0);
    ck(!last_present && !last_valid && last_count==0 && last_item==0,"empty is explicit and clears candidate");
    for(item=96;item<=99;item++)begin
      new_case("mixed colors, clipped box, unsampled foreground and black unknown");frame(item,0);
      ck(last_present && !last_valid && last_count==0,"unknown foreground is never absence");
    end
    for(item=1;item<=7;item++)begin
      new_case($sformatf("raster or metadata defect %0d withdraws stale result",item));
      clear;for(i=0;i<3;i++)frame(2,0);old_events=events;old_revokes=revokes;
      frame(2,item);
      ck(events==old_events && revokes>old_revokes && !out_valid && stable_count==0,"invalid frame never publishes or reuses old result");
      for(i=1;i<=3;i++)begin frame(2,0);ck(last_valid==(i==3),"fault recovery starts confirmation anew");end
    end
    new_case("flush is silent, held, and resets confirmation");old_revokes=revokes;clear;
    ck(revokes==old_revokes && !out_valid,"flush does not feed back revoke");
    for(i=1;i<=3;i++)begin frame(1,0);ck(last_valid==(i==3),"flush recovery");end
    new_case("source change resets confirmation without mislabelling result");
    in_source_test=~in_source_test;frame(1,0);
    ck(last_count==1 && !last_valid && last_source==in_source_test,"source-labelled new candidate");
    ck(!inject_fault || injected==1,"exactly one real output fault injected");
    test_done=1;$display("RESULT block errors=%0d checks=%0d scenarios=%0d injected=%0d",errors,checks,scenarios,injected);$finish;
  end
  initial begin #10000000;errors++;$display("WATCHDOG block");$finish;end
endmodule
