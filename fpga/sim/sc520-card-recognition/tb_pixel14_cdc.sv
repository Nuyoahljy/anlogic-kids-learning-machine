`timescale 1ns/1ps
module tb_pixel14_cdc;
  reg src_clk=0,dst_clk=0,src_run=1,dst_run=1;
  integer src_half=3,dst_half=5;
  always begin #(src_half); if(src_run) src_clk=~src_clk; else src_clk=0; end
  always begin #(dst_half); if(dst_run) dst_clk=~dst_clk; else dst_clk=0; end
  reg rst_n=0,src_valid=0;
  reg [111:0] src_data=0;
  wire src_ready,src_fault,dst_valid,dst_fault;
  wire [111:0] dst_data;
  pixel14_result_cdc dut(.*);
  integer errors=0,checks=0,scenarios=0,injected=0,inject_fault=0,unused;
  reg test_done=0,score_enable=1;
  reg [111:0] expected[0:1023];
  integer wr=0,rd=0,i,before_count;
  reg last_valid=0;
  task ck(input bit pass,input string label);
    begin checks=checks+1;if(!pass)begin errors=errors+1;$display("ERROR cdc case=%0d %s",scenarios,label);end end
  endtask
  task start_case(input string label);
    begin scenarios=scenarios+1;$display("CASE cdc %0d %s",scenarios,label);end
  endtask
  always @(posedge src_clk) begin
    if(rst_n && src_valid && src_ready && score_enable) begin
      expected[wr]=src_data;wr=wr+1;
    end
  end
  always @(posedge dst_clk) begin
    #1;
    if(!rst_n) last_valid=0;
    else begin
      ck(!(dst_valid && last_valid),"destination event is one cycle");
      last_valid=dst_valid;
      if(dst_valid && score_enable) begin
        ck(rd<wr,"no unsolicited or duplicate packet");
        if(inject_fault && injected==0) begin
          force dut.dst_data=112'd0;injected=1;#0.01;
          ck(dst_data===expected[rd],"atomic payload and FIFO order (real output force)");
          release dut.dst_data;
        end else ck(dst_data===expected[rd],"atomic payload and FIFO order");
        rd=rd+1;
      end
    end
  end
  task reset_all;
    begin
      rst_n=0;src_valid=0;src_data=0;src_run=1;dst_run=1;score_enable=1;
      #60;wr=0;rd=0;last_valid=0;rst_n=1;
      repeat(8)@(negedge src_clk);
      ck(src_ready && !src_fault && !dst_fault,"common reset recovers handshake and fault");
    end
  endtask
  task send(input reg [111:0] value);
    begin
      while(!src_ready)@(negedge src_clk);
      @(negedge src_clk);src_data=value;src_valid=1;
      @(negedge src_clk);src_valid=0;src_data=~value;
    end
  endtask
  task drain;
    begin
      repeat(30)@(negedge dst_clk);
      ck(rd==wr,"all accepted payloads delivered exactly once");
      ck(!src_fault && !dst_fault,"legal traffic did not overflow");
    end
  endtask
  initial begin
    unused=$value$plusargs("INJECT_FAULT=%d",inject_fault);
    start_case("idle reset and one nonzero payload");reset_all;
    repeat(20)@(negedge dst_clk);ck(!dst_valid && rd==0,"reset produces no packet");
    send(112'hfedcba9876543210aa55ff001122);drain;
    start_case("alternating full-width payloads with source faster than destination");
    for(i=0;i<64;i=i+1) send({32'h9e3779b9^i,32'h01234567+i,32'h89abcdef-i,16'h1357^i[15:0]});
    drain;
    start_case("destination pause holds original source payload until acknowledge");
    @(negedge dst_clk);dst_run=0;before_count=rd;
    send(112'h0102030405060708091011121314);
    repeat(30)begin @(negedge src_clk);src_data=src_data+1;end
    ck(!src_ready && rd==before_count,"no overwrite while receiver paused");
    dst_run=1;drain;
    start_case("source pauses after launch; receiver still completes once");
    send(112'hffffffff00000000aaaaaaaa5555);
    @(negedge src_clk);src_run=0;
    repeat(20)@(negedge dst_clk);
    ck(rd==wr,"stopped source leaves stable packet readable");
    src_run=1;drain;
    start_case("destination faster and nonharmonic clock phase");
    src_half=7;dst_half=2;
    for(i=0;i<32;i=i+1)send({16'hbb66,i[31:0],~i[31:0],32'hd3c2b1a0});
    drain;
    start_case("common reset discards an outstanding packet without ghost event");
    @(negedge dst_clk);dst_run=0;send(112'hdeadbeefdeadbeefdeadbeefdead);
    reset_all;repeat(25)@(negedge dst_clk);ck(rd==0 && wr==0,"old epoch is not delivered after reset");
    send(112'h123456789abcdef00123456789ab);drain;
    start_case("illegal producer overwrite becomes persistent fault");
    score_enable=0;@(negedge dst_clk);dst_run=0;
    send(112'h1010101010101010101010101010);
    @(negedge src_clk);src_valid=1;src_data=112'h2020202020202020202020202020;
    @(negedge src_clk);src_valid=0;
    ck(src_fault && !src_ready,"overflow blocks producer until common reset");
    dst_run=1;repeat(20)@(negedge dst_clk);
    ck(dst_fault,"source overflow crosses even with no payload slot");
    before_count=rd;
    repeat(12)begin
      @(negedge src_clk);src_valid=1;src_data=src_data+1;
      @(negedge src_clk);src_valid=0;
    end
    repeat(10)@(negedge dst_clk);
    ck(dst_fault && !dst_valid && src_fault,"fault stays latched and no later events escape");
    start_case("reset recovers sticky overflow");reset_all;
    send(112'h5555aaaaffff00003333cccc1234);drain;
    ck(!inject_fault || injected==1,"exactly one deliberate output fault");
    test_done=1;
    $display("RESULT tb_pixel14_cdc errors=%0d checks=%0d scenarios=%0d injected=%0d",errors,checks,scenarios,injected);
    $finish;
  end
  initial begin #1000000;errors=errors+1;$display("WATCHDOG cdc");$finish;end
endmodule
