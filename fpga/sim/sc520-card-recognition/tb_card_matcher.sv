`timescale 1ns/1ps
module tb_card_matcher;
  reg clk=0; always #5 clk=~clk;
  reg rst_n=0, flush=0, frame_start=0, sample_valid=0, sample_foreground=0;
  reg frame_end=0, frame_good=1, frame_present=1, frame_source_test=0;
  reg [9:0] sample_index=0;
  reg [31:0] frame_id=0;
  wire out_frame,out_healthy,out_present,out_valid,out_source_test;
  wire [3:0] out_item;
  wire [10:0] out_best,out_second,out_fg_count;
  wire [31:0] out_frame_id;
  wire off_frame,off_healthy,off_present,off_valid,off_source;
  wire [3:0] off_item;
  wire [10:0] off_best,off_second,off_fg;
  wire [31:0] off_id;
  integer errors=0,checks=0,scenarios=0; reg test_done=0;
  integer inject_fault=0, injected=0;
  reg [4:0] golden_rom[0:1023];
  reg bits[0:1023];
  string asset_root;
  integer k,j,fg,best,second,winner,d[0:4],tmp;
  reg expected_valid;

  // Deliberately exercise configurable cutoff 120 independently of the safer
  // shipped cutoff; the full RGB pipeline tests the shipped default.
  card_matcher #(.ENABLE_OUTPUT(1),.MAX_DISTANCE(120),.TEMPLATE_FILE("templates.mem")) dut(
    .clk(clk),.rst_n(rst_n),.flush(flush),.frame_start(frame_start),
    .sample_valid(sample_valid),.sample_index(sample_index),.sample_foreground(sample_foreground),
    .frame_end(frame_end),.frame_good(frame_good),.frame_present(frame_present),
    .frame_id(frame_id),.frame_source_test(frame_source_test),
    .out_frame(out_frame),.out_healthy(out_healthy),.out_present(out_present),
    .out_valid(out_valid),.out_item(out_item),.out_best(out_best),.out_second(out_second),
    .out_fg_count(out_fg_count),.out_frame_id(out_frame_id),.out_source_test(out_source_test));
  card_matcher #(.TEMPLATE_FILE("templates.mem")) disabled_dut(
    .clk(clk),.rst_n(rst_n),.flush(flush),.frame_start(frame_start),
    .sample_valid(sample_valid),.sample_index(sample_index),.sample_foreground(sample_foreground),
    .frame_end(frame_end),.frame_good(frame_good),.frame_present(frame_present),
    .frame_id(frame_id),.frame_source_test(frame_source_test),
    .out_frame(off_frame),.out_healthy(off_healthy),.out_present(off_present),
    .out_valid(off_valid),.out_item(off_item),.out_best(off_best),.out_second(off_second),
    .out_fg_count(off_fg),.out_frame_id(off_id),.out_source_test(off_source));

  task ck(input bit ok,input string label);
    begin checks=checks+1; if(!ok) begin errors=errors+1; $display("ERROR matcher case=%0d %s",scenarios,label); end end
  endtask
  task tick;
    begin @(posedge clk); #1; end
  endtask
  task idle(input integer cycles);
    integer c;
    begin
      @(negedge clk); frame_start=0;sample_valid=0;frame_end=0;
      for(c=0;c<cycles;c=c+1) begin tick();ck(!out_frame,"no unsolicited frame");ck(!off_valid && off_item==0,"disabled output remains closed");end
    end
  endtask
  task canonical(input integer card);
    integer q; begin for(q=0;q<1024;q=q+1) bits[q]=golden_rom[q][card]; end
  endtask
  task compute_golden;
    integer a,b;
    begin
      fg=0;for(a=0;a<5;a=a+1)d[a]=0;
      for(a=0;a<1024;a=a+1)begin
        fg=fg+bits[a];for(b=0;b<5;b=b+1)if(bits[a]!=golden_rom[a][b])d[b]=d[b]+1;
      end
      // An independent full sort of five distances, rather than the RTL reducer.
      winner=0;for(a=1;a<5;a=a+1)if(d[a]<d[winner])winner=a;
      best=d[winner]; second=2047;
      for(a=0;a<5;a=a+1)if(a!=winner && d[a]<second)second=d[a];
      expected_valid=(best<=120 && second-best>=24 && fg>=16 && fg<=850);
    end
  endtask
  task begin_frame(input integer id,input bit source);
    begin
      @(negedge clk);frame_start=1;sample_valid=0;frame_end=0;
      frame_id=id;frame_source_test=source;frame_good=1;frame_present=1;
      tick();ck(!out_frame,"start must not publish result");
      @(negedge clk);frame_start=0;
    end
  endtask
  task sample(input integer idx,input bit value);
    begin
      sample_valid=1;sample_index=idx;sample_foreground=value;
      tick();ck(!out_frame,"no early result before explicit end");
      @(negedge clk);
    end
  endtask
  task stream_bits(input integer gap_every);
    integer a;
    begin
      for(a=0;a<1024;a=a+1)begin
        if(gap_every>0 && a%gap_every==0)begin sample_valid=0;tick();ck(!out_frame,"gap is not frame boundary");@(negedge clk);end
        sample(a,bits[a]);
      end
      sample_valid=0;
    end
  endtask
  task finish_frame(input bit healthy,input bit present,input bit compare_distance);
    integer n;bit found,ev;
    begin
      frame_end=1; tick();
      @(negedge clk);frame_end=0;sample_valid=0;
      found=0;
      for(n=0;n<8 && !found;n=n+1)begin tick();if(out_frame)found=1;end
      ck(found,"frame must publish within eight cycles");
      if(found)begin
        if(inject_fault && !injected && healthy && expected_valid)begin
          force dut.out_item=4'd15; injected=1; #1;
        end
        ck(out_healthy===healthy,"frame health");
        ck(out_present===(healthy?present:1'b1),"unknown/bad must not mean empty");
        ev=healthy && present && expected_valid;
        ck(out_valid===ev,"accept/reject differs from independent popcount");
        ck(out_item===(ev?winner+10:0),"logical card identifier");
        ck(out_frame_id===frame_id && out_source_test===frame_source_test,"metadata association");
        ck(off_frame && off_healthy===out_healthy && off_present===out_present,"disabled diagnostic frame retained");
        ck(off_valid===1'b0 && off_item===4'd0,"default ENABLE_OUTPUT=0");
        if(compare_distance)begin
          ck(out_best===best,"minimum distance");ck(out_second===second,"runner-up distance");
          ck(out_fg_count===fg,"11-bit foreground count incl 1024");
          ck(off_best===out_best && off_second===out_second && off_fg===out_fg_count,"disabled diagnostic distances retained");
        end
        if(injected)release dut.out_item;
      end
      idle(3);
    end
  endtask
  task good_case(input string name,input integer id,input bit present,input integer gaps);
    begin scenarios=scenarios+1;$display("CASE matcher %0d %s",scenarios,name);compute_golden();begin_frame(id,id%2);stream_bits(gaps);frame_present=present;finish_frame(1,present,1);end
  endtask
  task orphan_end_case(input string name,input integer id,input bit source,input bit simultaneous_sample);
    begin
      scenarios=scenarios+1;$display("CASE matcher %0d %s",scenarios,name);
      @(negedge clk);frame_start=0;sample_valid=simultaneous_sample;sample_index=17;sample_foreground=1;
      frame_end=1;frame_good=1;frame_present=0;frame_id=id;frame_source_test=source;
      tick();ck(!out_frame && !off_frame,"orphan end follows normal one-clock result latency");
      @(negedge clk);frame_end=0;sample_valid=0;
      // Metadata must belong to the end just observed, not to these later inputs.
      frame_id=id+1000;frame_source_test=!source;frame_good=0;frame_present=1;
      tick();
      ck(out_frame && off_frame,"idle orphan end emits one diagnostic frame");
      ck(out_healthy===1'b0 && out_present===1'b1 && out_valid===1'b0 && out_item===4'd0,
        "orphan end is unhealthy present and unclassified");
      ck(out_best===11'd0 && out_second===11'd0 && out_fg_count===11'd0,
        "orphan end clears stale scores and counts");
      ck(out_frame_id===id && out_source_test===source,"orphan end metadata is latched");
      ck(off_healthy===1'b0 && off_present===1'b1 && off_valid===1'b0 && off_item===4'd0,
        "disabled matcher preserves orphan health event");
      ck(off_best===11'd0 && off_second===11'd0 && off_fg===11'd0 && off_id===id && off_source===source,
        "disabled orphan diagnostics and metadata");
      idle(3);
    end
  endtask
  initial begin
    if(!$value$plusargs("ASSET_ROOT=%s",asset_root))asset_root=".";
    tmp=$value$plusargs("INJECT_FAULT=%d",inject_fault);
    $readmemh({asset_root,"/templates.mem"},golden_rom);
    repeat(4)tick();@(negedge clk);rst_n=1;idle(2);
    orphan_end_case("empty frame without any start after reset",90,1,0);
    for(k=0;k<5;k=k+1)begin canonical(k);good_case("canonical",100+k,1,17);ck(best==0 && winner==k,"canonical identity known independently");end
    orphan_end_case("trailing orphan end cannot reuse a valid frame",91,0,0);
    orphan_end_case("orphan end with simultaneous sample",92,1,1);
    canonical(0);for(k=0;k<40;k=k+1)bits[(k*73)%1024]=!bits[(k*73)%1024];good_case("40 deterministic dispersed flips",200,1,0);
    canonical(0);for(k=0;k<120;k=k+1)bits[k]=!bits[k];good_case("distance cutoff equality",201,1,0);
    ck(best==120 && expected_valid,"distance equality fixture is accepted");
    canonical(0);for(k=0;k<121;k=k+1)bits[k]=!bits[k];good_case("distance cutoff plus one",202,1,0);
    ck(best==121 && !expected_valid,"distance plus-one fixture is rejected");
    canonical(0);j=0;for(k=0;k<1024;k=k+1)if(golden_rom[k][0]!=golden_rom[k][4] && j<75)begin bits[k]=golden_rom[k][4];j=j+1;end
    good_case("margin cutoff equality",209,1,0);ck(second-best==24 && expected_valid,"margin equality fixture is accepted");
    canonical(0);j=0;for(k=0;k<1024;k=k+1)if(golden_rom[k][0]!=golden_rom[k][1] && j<54)begin bits[k]=golden_rom[k][1];j=j+1;end
    good_case("margin cutoff minus one",210,1,0);ck(second-best==23 && !expected_valid,"margin minus-one fixture is rejected");
    canonical(0);j=0;for(k=0;k<1024;k=k+1)if(golden_rom[k][0]!=golden_rom[k][4] && j<87)begin bits[k]=golden_rom[k][4];j=j+1;end
    good_case("exact equal-distance tie",211,1,0);ck(second==best && !expected_valid,"true tie fixture rejected");
    // Alternate differing positions to form a deterministic near-tie.
    canonical(0);j=0;for(k=0;k<1024;k=k+1)if(golden_rom[k][0]!=golden_rom[k][1])begin if(j%2==0)bits[k]=golden_rom[k][1];j=j+1;end
    good_case("ambiguous midpoint must use margin",203,1,0);ck(!expected_valid,"ambiguous fixture rejected");
    for(k=0;k<1024;k=k+1)bits[k]=0;good_case("all zero present",204,1,0);good_case("all zero genuine empty",205,0,0);
    for(k=0;k<1024;k=k+1)bits[k]=1;good_case("all 1024 bits foreground",206,1,0);ck(fg==1024,"fixture reaches 11-bit boundary");
    canonical(0);for(k=0;k<1024;k=k+1)bits[k]=!bits[k];good_case("1024 differences from template zero",208,1,0);ck(dut.distance[0]===11'd1024,"per-template 11-bit distance boundary");
    canonical(4);bits[1023]=!bits[1023];good_case("last sample contributes",207,1,0);
    // Structural faults must produce one unhealthy event and never valid empty.
    canonical(2);compute_golden();scenarios=scenarios+1;begin_frame(299,0);
    frame_present=0;finish_frame(0,0,0);
    canonical(2);compute_golden();scenarios=scenarios+1;begin_frame(300,0);
    for(k=0;k<1023;k=k+1)sample(k,bits[k]);sample_valid=0;finish_frame(0,1,0);
    scenarios=scenarios+1;begin_frame(301,0);
    for(k=0;k<1024;k=k+1)sample(k==700?699:k,bits[k]);sample_valid=0;finish_frame(0,1,0);
    scenarios=scenarios+1;begin_frame(302,0);stream_bits(0);sample(0,bits[0]);sample_valid=0;finish_frame(0,1,0);
    scenarios=scenarios+1;begin_frame(313,0);stream_bits(0);sample_valid=1;sample_index=0;finish_frame(0,1,0);
    scenarios=scenarios+1;begin_frame(303,0);stream_bits(0);frame_good=0;frame_present=0;finish_frame(0,0,0);
    scenarios=scenarios+1;begin_frame(304,0);for(k=0;k<19;k=k+1)sample(k,bits[k]);
    begin_frame(305,1);stream_bits(0);finish_frame(0,1,0);
    // Flush/reset do not emit a result by themselves; a later orphan end is reported.
    scenarios=scenarios+1;begin_frame(306,0);for(k=0;k<70;k=k+1)sample(k,bits[k]);sample_valid=0;flush=1;tick();@(negedge clk);flush=0;idle(4);
    orphan_end_case("late end after flushed capture revokes qualification",314,0,0);
    good_case("clean restart after flush",307,1,0);
    scenarios=scenarios+1;begin_frame(308,0);for(k=0;k<70;k=k+1)sample(k,bits[k]);sample_valid=0;rst_n=0;tick();@(negedge clk);rst_n=1;idle(4);
    good_case("clean restart after reset",309,1,0);
    // New start during DRAIN suppresses old result and poisons replacement frame.
    scenarios=scenarios+1;begin_frame(310,0);stream_bits(0);frame_end=1;tick();
    @(negedge clk);frame_end=0;frame_start=1;frame_id=311;tick();ck(!out_frame,"new frame cancels draining result");
    @(negedge clk);frame_start=0;stream_bits(0);finish_frame(0,1,0);
    good_case("clean restart after overlap",312,1,0);
    orphan_end_case("late end after completed replacement frame",315,1,0);
    ck(!inject_fault || injected,"negative run exercised actual output corruption");
    test_done=1;$display("RESULT tb_card_matcher errors=%0d checks=%0d scenarios=%0d injected=%0d",errors,checks,scenarios,injected);$finish;
  end
  initial begin #10000000; errors=errors+1;$display("WATCHDOG tb_card_matcher");$finish;end
endmodule
