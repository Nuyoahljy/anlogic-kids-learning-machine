`timescale 1ns/1ps
// 独立接口测试：截止时刻由刺激中的 tick 个数决定，不读取 DUT 内部计数器。
// 先分别验证 TIMEOUT_MS=1/5，再连接真实 card_result_filter 验证恢复路径。
module tb_card_guard;
  reg clk=0;
  always #5 clk=~clk;
  integer errors=0,checks=0,scenarios=0,injected=0;
  reg test_done=0;
  integer inject_fault=0,ignored,lane,k,j,limit;

  reg rst_n[0:1],tick_1ms[0:1],flush[0:1];
  reg in_frame[0:1],in_healthy[0:1],in_present[0:1],in_valid[0:1];
  reg [3:0] in_item[0:1];
  reg [31:0] in_frame_id[0:1];
  reg in_source_test[0:1];
  reg [7:0] in_stable_count[0:1];
  wire recognizer_flush[0:1],out_frame[0:1],out_healthy[0:1];
  wire out_present[0:1],out_valid[0:1],out_source_test[0:1],timed_out[0:1];
  wire [3:0] out_item[0:1];
  wire [31:0] out_frame_id[0:1];
  wire [7:0] out_stable_count[0:1];

  card_frame_guard #(.TIMEOUT_MS(1)) dut_fast(
    .clk(clk),.rst_n(rst_n[0]),.tick_1ms(tick_1ms[0]),.flush(flush[0]),
    .in_frame(in_frame[0]),.in_healthy(in_healthy[0]),.in_present(in_present[0]),
    .in_valid(in_valid[0]),.in_item(in_item[0]),.in_frame_id(in_frame_id[0]),
    .in_source_test(in_source_test[0]),.in_stable_count(in_stable_count[0]),
    .recognizer_flush(recognizer_flush[0]),.out_frame(out_frame[0]),
    .out_healthy(out_healthy[0]),.out_present(out_present[0]),.out_valid(out_valid[0]),
    .out_item(out_item[0]),.out_frame_id(out_frame_id[0]),
    .out_source_test(out_source_test[0]),.out_stable_count(out_stable_count[0]),
    .timed_out(timed_out[0]));
  card_frame_guard #(.TIMEOUT_MS(5)) dut_slow(
    .clk(clk),.rst_n(rst_n[1]),.tick_1ms(tick_1ms[1]),.flush(flush[1]),
    .in_frame(in_frame[1]),.in_healthy(in_healthy[1]),.in_present(in_present[1]),
    .in_valid(in_valid[1]),.in_item(in_item[1]),.in_frame_id(in_frame_id[1]),
    .in_source_test(in_source_test[1]),.in_stable_count(in_stable_count[1]),
    .recognizer_flush(recognizer_flush[1]),.out_frame(out_frame[1]),
    .out_healthy(out_healthy[1]),.out_present(out_present[1]),.out_valid(out_valid[1]),
    .out_item(out_item[1]),.out_frame_id(out_frame_id[1]),
    .out_source_test(out_source_test[1]),.out_stable_count(out_stable_count[1]),
    .timed_out(timed_out[1]));

  reg chain_rst_n=0,chain_tick=0,chain_flush=0;
  reg raw_frame=0,raw_healthy=0,raw_present=0,raw_valid=0,raw_source=0;
  reg [3:0] raw_item=0;
  reg [31:0] raw_tag=0;
  wire filtered_frame,filtered_healthy,filtered_present,filtered_valid,filtered_source;
  wire [3:0] filtered_item;
  wire [31:0] filtered_tag;
  wire [7:0] filtered_count;
  wire chain_recognizer_flush,chain_frame,chain_healthy,chain_present,chain_valid;
  wire chain_source,chain_timed_out;
  wire [3:0] chain_item;
  wire [31:0] chain_tag;
  wire [7:0] chain_count;
  card_result_filter #(.CONFIRM_FRAMES(3)) real_filter(
    .clk(clk),.rst_n(chain_rst_n),.flush(chain_recognizer_flush),
    .in_frame(raw_frame),.in_healthy(raw_healthy),.in_present(raw_present),
    .in_valid(raw_valid),.in_item(raw_item),.in_frame_id(raw_tag),.in_source_test(raw_source),
    .out_frame(filtered_frame),.out_healthy(filtered_healthy),.out_present(filtered_present),
    .out_valid(filtered_valid),.out_item(filtered_item),.out_frame_id(filtered_tag),
    .out_source_test(filtered_source),.stable_count(filtered_count));
  card_frame_guard #(.TIMEOUT_MS(5)) dut_chain(
    .clk(clk),.rst_n(chain_rst_n),.tick_1ms(chain_tick),.flush(chain_flush),
    .in_frame(filtered_frame),.in_healthy(filtered_healthy),.in_present(filtered_present),
    .in_valid(filtered_valid),.in_item(filtered_item),.in_frame_id(filtered_tag),
    .in_source_test(filtered_source),.in_stable_count(filtered_count),
    .recognizer_flush(chain_recognizer_flush),.out_frame(chain_frame),
    .out_healthy(chain_healthy),.out_present(chain_present),.out_valid(chain_valid),
    .out_item(chain_item),.out_frame_id(chain_tag),.out_source_test(chain_source),
    .out_stable_count(chain_count),.timed_out(chain_timed_out));

  task ck(input bit ok,input string label);
    begin
      checks=checks+1;
      if(!ok)begin errors=errors+1;$display("ERROR guard case=%0d time=%0t %s",scenarios,$time,label);end
    end
  endtask
  task start_case(input integer p,input string label);
    begin scenarios=scenarios+1;$display("CASE guard %0d lane=%0d %s",scenarios,p,label);end
  endtask
  // 检查在有效时钟沿之前的 flush，而非延迟一拍后才出现的通知。
  task step(input integer p,input bit ms,input bit fl,input bit frame,
    input bit healthy,input bit present,input bit valid,input integer item,
    input integer tag,input bit source,input integer count,input bit expected_flush);
    begin
      @(negedge clk);
      tick_1ms[p]=ms;flush[p]=fl;in_frame[p]=frame;in_healthy[p]=healthy;
      in_present[p]=present;in_valid[p]=valid;in_item[p]=item;
      in_frame_id[p]=tag;in_source_test[p]=source;in_stable_count[p]=count;
      #1;ck(recognizer_flush[p]===expected_flush,"recognizer_flush before sampling edge");
      @(posedge clk);#1;
    end
  endtask
  task quiet_step(input integer p,input bit ms,input bit expected_flush);
    begin
      step(p,ms,0,0,in_healthy[p],in_present[p],in_valid[p],in_item[p],
        in_frame_id[p],in_source_test[p],in_stable_count[p],expected_flush);
    end
  endtask
  task expect_record(input integer p,input bit frame,input bit healthy,
    input bit present,input bit valid,input integer item,input integer tag,
    input bit source,input integer count,input bit expired,input string label);
    begin
      ck(out_frame[p]===frame,{label," event"});
      ck(out_healthy[p]===healthy,{label," health"});
      ck(out_present[p]===present,{label," presence"});
      ck(out_valid[p]===valid,{label," validity"});
      ck(out_item[p]===item,{label," item"});
      ck(out_frame_id[p]===tag,{label," frame tag"});
      ck(out_source_test[p]===source,{label," source"});
      ck(out_stable_count[p]===count,{label," confirmation count"});
      ck(timed_out[p]===expired,{label," timeout latch"});
    end
  endtask
  task reset_lane(input integer p);
    begin
      @(negedge clk);rst_n[p]=0;tick_1ms[p]=0;flush[p]=0;in_frame[p]=0;
      in_healthy[p]=0;in_present[p]=0;in_valid[p]=0;in_item[p]=0;
      in_frame_id[p]=0;in_source_test[p]=0;in_stable_count[p]=0;
      @(posedge clk);#1;
      expect_record(p,0,0,1,0,0,0,0,0,0,"reset has no event and no trusted absence");
      ck(recognizer_flush[p]===1'b0,"reset does not request upstream flush");
      @(negedge clk);rst_n[p]=1;
    end
  endtask

  task chain_step(input bit ms,input bit fl,input bit frame,input integer tag,
    input bit expected_flush);
    begin
      @(negedge clk);chain_tick=ms;chain_flush=fl;raw_frame=frame;
      raw_healthy=1;raw_present=1;raw_valid=1;raw_item=10;raw_tag=tag;raw_source=1;
      #1;ck(chain_recognizer_flush===expected_flush,"chain flush exists before filter sampling edge");
      @(posedge clk);#1;
    end
  endtask
  task expect_chain(input bit frame,input bit healthy,input bit valid,input integer count,
    input integer tag,input bit expired,input string label);
    begin
      ck(chain_frame===frame,{label," event"});
      ck(chain_healthy===healthy && chain_present===1'b1,{label," health and presence"});
      ck(chain_valid===valid && chain_item===(valid?10:0),{label," stable result"});
      ck(chain_count===count,{label," count"});
      ck(chain_tag===tag && chain_source===1'b1,{label," metadata"});
      ck(chain_timed_out===expired,{label," timeout latch"});
    end
  endtask
  task chain_sample(input integer ordinal,input integer tag);
    begin
      chain_step(0,0,1,tag,0);
      ck(filtered_frame===1'b1 && filtered_count===ordinal,"real filter advances once per raw frame");
      ck(filtered_valid===(ordinal>=3),"real filter requires three fresh observations");
      ck(chain_frame===1'b0,"guard waits for registered filter event");
      chain_step(0,0,0,tag,0);
      expect_chain(1,1,ordinal>=3,ordinal,tag,0,"fresh filtered frame");
      chain_step(0,0,0,tag,0);
      expect_chain(0,1,ordinal>=3,ordinal,tag,0,"candidate count survives inter-frame gap");
    end
  endtask

  initial begin
    ignored=$value$plusargs("INJECT_FAULT=%d",inject_fault);
    for(lane=0;lane<2;lane=lane+1)begin
      rst_n[lane]=0;tick_1ms[lane]=0;flush[lane]=0;in_frame[lane]=0;
      in_healthy[lane]=0;in_present[lane]=0;in_valid[lane]=0;
      in_item[lane]=0;in_frame_id[lane]=0;in_source_test[lane]=0;in_stable_count[lane]=0;
    end
    for(lane=0;lane<2;lane=lane+1)begin
      limit=(lane==0)?1:5;
      start_case(lane,"startup without pixels, sparse ticks, single timeout");
      reset_lane(lane);
      for(k=0;k<17;k=k+1)begin
        quiet_step(lane,0,0);
        expect_record(lane,0,0,1,0,0,0,0,0,0,"clocks alone do not age milliseconds");
      end
      for(k=1;k<limit;k=k+1)begin
        quiet_step(lane,1,0);
        expect_record(lane,0,0,1,0,0,0,0,0,0,"before declared startup deadline");
        for(j=0;j<3;j=j+1)begin quiet_step(lane,0,0);ck(!out_frame[lane] && !timed_out[lane],"sparse interval remains live");end
      end
      quiet_step(lane,1,1);
      expect_record(lane,1,0,1,0,0,0,0,0,1,"exact startup deadline");
      for(k=0;k<12;k=k+1)begin
        // A healthy level without in_frame is deliberately not a watchdog feed.
        step(lane,1,0,0,1,0,1,14,999,1,255,0);
        expect_record(lane,0,0,1,0,0,0,0,0,1,"timeout remains latched and does not repeat");
      end

      start_case(lane,"recovery, deadline priority, renewal before deadline");
      step(lane,0,0,1,1,1,1,10,101,1,3,0);
      expect_record(lane,1,1,1,1,10,101,1,3,0,"healthy frame recovers from timeout");
      for(k=0;k<9;k=k+1)begin quiet_step(lane,0,0);expect_record(lane,0,1,1,1,10,101,1,3,0,"no-pixel gap preserves live result");end
      for(k=1;k<limit;k=k+1)begin quiet_step(lane,1,0);expect_record(lane,0,1,1,1,10,101,1,3,0,"before healthy boundary frame");end
      step(lane,1,0,1,1,1,1,14,102,0,4,0);
      expect_record(lane,1,1,1,1,14,102,0,4,0,"healthy frame wins at exact deadline");
      for(k=1;k<limit;k=k+1)begin quiet_step(lane,1,0);ck(!timed_out[lane] && !out_frame[lane],"renewed full deadline interval");end
      step(lane,0,0,1,1,1,1,11,103,1,5,0);
      expect_record(lane,1,1,1,1,11,103,1,5,0,"healthy frame before deadline also renews");
      for(k=1;k<limit;k=k+1)begin quiet_step(lane,1,0);ck(!timed_out[lane] && !out_frame[lane],"second renewal interval");end
      quiet_step(lane,1,1);
      expect_record(lane,1,0,1,0,0,103,1,0,1,"stalled live result revokes with retained metadata");

      start_case(lane,"healthy unknown and empty results feed watchdog");
      step(lane,1,0,1,1,1,0,0,201,0,0,0);
      expect_record(lane,1,1,1,0,0,201,0,0,0,"unknown foreground is a healthy recovery");
      for(k=1;k<limit;k=k+1)begin quiet_step(lane,1,0);ck(!timed_out[lane],"unknown renewed watchdog");end
      step(lane,1,0,1,1,0,0,0,202,1,0,0);
      expect_record(lane,1,1,0,0,0,202,1,0,0,"healthy empty frame wins deadline");
      for(k=1;k<limit;k=k+1)begin quiet_step(lane,1,0);expect_record(lane,0,1,0,0,0,202,1,0,0,"empty result remains healthy before deadline");end
      quiet_step(lane,1,1);
      expect_record(lane,1,0,1,0,0,202,1,0,1,"timeout never masquerades as observed empty");

      start_case(lane,"all item codes and independent checker fault injection");
      for(k=0;k<16;k=k+1)begin
        step(lane,0,0,1,1,1,1,k,300+k,k%2,7,0);
        if(inject_fault && !injected && lane==1 && k==10)begin
          force dut_slow.out_valid=1'b0;injected=1;#1;
        end
        expect_record(lane,1,1,1,k>=10 && k<=14,(k>=10 && k<=14)?k:0,
          300+k,k%2,(k>=10 && k<=14)?7:0,0,"item whitelist");
        if(inject_fault && lane==1 && k==10)release dut_slow.out_valid;
      end

      start_case(lane,"candidate gaps, no-event withdrawal and ignored data");
      step(lane,0,0,1,1,1,0,0,401,0,1,0);
      expect_record(lane,1,1,1,0,0,401,0,1,0,"first legitimate candidate count");
      quiet_step(lane,0,0);
      expect_record(lane,0,1,1,0,0,401,0,1,0,"invalid candidate count one is retained in gap");
      step(lane,0,0,0,0,0,0,14,987,1,2,0);
      expect_record(lane,0,1,1,0,0,401,0,1,0,"unframed data cannot replace candidate metadata or count");
      step(lane,0,0,1,1,1,0,0,402,0,2,0);
      expect_record(lane,1,1,1,0,0,402,0,2,0,"second legitimate candidate count");
      quiet_step(lane,0,0);
      expect_record(lane,0,1,1,0,0,402,0,2,0,"invalid candidate count two is retained in gap");
      step(lane,0,0,0,0,0,0,0,988,1,0,0);
      expect_record(lane,0,1,1,0,0,402,0,0,0,"upstream zero count clears pending candidate without event");
      step(lane,0,0,1,1,1,1,12,403,1,3,0);
      expect_record(lane,1,1,1,1,12,403,1,3,0,"confirmed state before early fault withdrawal");
      step(lane,0,0,0,0,0,0,14,989,0,2,0);
      expect_record(lane,0,1,1,0,0,403,1,0,0,"invalid level promptly withdraws old confirmed state");
      step(lane,0,0,0,1,0,1,14,990,0,255,0);
      expect_record(lane,0,1,1,0,0,403,1,0,0,"unframed valid cannot resurrect withdrawn result");

      start_case(lane,"bad frames cannot extend deadline or clear timeout");
      reset_lane(lane);
      step(lane,0,0,1,1,1,1,12,500,0,3,0);
      expect_record(lane,1,1,1,1,12,500,0,3,0,"healthy origin of bad-frame sequence");
      for(k=1;k<limit;k=k+1)begin
        step(lane,1,0,1,0,0,1,13,500+k,k%2,200,0);
        expect_record(lane,1,0,1,0,0,500+k,k%2,0,0,"bad frames are untrusted present records");
      end
      step(lane,1,0,1,0,0,1,14,599,1,255,1);
      expect_record(lane,1,0,1,0,0,500+limit-1,(limit-1)%2,0,1,
        "deadline beats bad frame and retains previously published metadata");
      for(k=0;k<3;k=k+1)begin
        step(lane,1,0,1,0,0,1,14,600+k,k%2,255,0);
        expect_record(lane,1,0,1,0,0,600+k,k%2,0,1,"later bad frame does not recover timeout");
      end
      step(lane,0,0,1,1,1,0,0,610,0,1,0);
      expect_record(lane,1,1,1,0,0,610,0,1,0,"healthy candidate clears timeout");

      start_case(lane,"flush priority, held flush, rearm and deadline restart");
      step(lane,0,0,1,1,1,1,13,701,1,3,0);
      for(k=1;k<limit;k=k+1)begin quiet_step(lane,1,0);ck(!timed_out[lane],"approach flush boundary");end
      step(lane,1,1,1,1,1,1,14,799,0,255,1);
      expect_record(lane,1,0,1,0,0,701,1,0,0,"flush beats healthy frame and deadline");
      for(k=0;k<7;k=k+1)begin
        step(lane,1,1,1,1,0,1,10,800+k,0,255,1);
        expect_record(lane,0,0,1,0,0,701,1,0,0,"held flush has exactly one revocation event");
      end
      quiet_step(lane,0,0);
      expect_record(lane,0,0,1,0,0,701,1,0,0,"flush release does not produce event");
      for(k=1;k<limit;k=k+1)begin quiet_step(lane,1,0);expect_record(lane,0,0,1,0,0,701,1,0,0,"full deadline restarts after held flush");end
      quiet_step(lane,1,1);
      expect_record(lane,1,0,1,0,0,701,1,0,1,"new timeout after flush release");
      step(lane,1,1,1,1,1,1,10,899,0,3,1);
      expect_record(lane,1,0,1,0,0,701,1,0,0,"new flush clears timeout and emits one new revocation");
      step(lane,0,1,0,0,0,0,0,0,0,0,1);
      expect_record(lane,0,0,1,0,0,701,1,0,0,"second held flush remains quiet");
      step(lane,1,0,1,1,1,1,14,702,0,3,0);
      expect_record(lane,1,1,1,1,14,702,0,3,0,"healthy frame on flush release resumes normally");
      reset_lane(lane);
      @(negedge clk);rst_n[lane]=0;
    end

    start_case(2,"real three-frame filter is synchronously cleared at timeout");
    @(negedge clk);chain_rst_n=1;
    chain_sample(1,901);chain_sample(2,902);chain_sample(3,903);
    for(k=0;k<11;k=k+1)begin
      chain_step(0,0,0,903,0);
      expect_chain(0,1,1,3,903,0,"stable result survives clocks without millisecond ticks");
    end
    for(k=1;k<5;k=k+1)begin
      chain_step(1,0,0,903,0);
      expect_chain(0,1,1,3,903,0,"real filter stable before timeout");
      chain_step(0,0,0,903,0);
      expect_chain(0,1,1,3,903,0,"sparse chain tick gap");
    end
    chain_step(1,0,0,903,1);
    expect_chain(1,0,0,0,903,1,"chain deadline withdraws confirmed result");
    ck(filtered_count===8'd0 && filtered_valid===1'b0 && filtered_frame===1'b0,
      "real filter clears on the very same timeout edge");
    for(k=0;k<8;k=k+1)begin
      chain_step(1,0,0,903,0);
      expect_chain(0,0,0,0,903,1,"continuous stop causes no extra timeout event");
      ck(filtered_count===8'd0,"filter has no stale confirmation history");
    end
    start_case(2,"first two post-timeout frames unconfirmed, third confirmed");
    chain_sample(1,904);chain_sample(2,905);chain_sample(3,906);
    ck(!inject_fault || injected==1,"negative run applied exactly one real output force");
    test_done=1;
    $display("RESULT tb_card_guard errors=%0d checks=%0d scenarios=%0d injected=%0d",errors,checks,scenarios,injected);
    $finish;
  end
  initial begin
    #1000000;
    errors=errors+1;$display("WATCHDOG tb_card_guard errors=%0d checks=%0d scenarios=%0d",errors,checks,scenarios);
    $finish;
  end
endmodule
