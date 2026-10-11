`timescale 1ns/1ps
// Contract-level stimuli: independent transaction tags and sparse tick counts.
// No checker reads pending slots, age, last_id, or other DUT implementation state.
module tb_items14_join;
  reg clk=0;
  always #5 clk=~clk;
  integer errors=0,checks=0,scenarios=0,injected=0;
  reg test_done=0;
  integer inject_fault=0,ignored,lane,k,n,limit;

  reg rst_n[0:1],tick_1ms[0:1],flush[0:1],block_revoke[0:1],card_revoke[0:1];
  reg be[0:1],bh[0:1],bp[0:1],bv[0:1],bs[0:1];
  reg ce[0:1],ch[0:1],cp[0:1],cv[0:1],cs[0:1];
  reg [3:0] bi[0:1],ci[0:1];
  reg [31:0] bt[0:1],ct[0:1];
  reg [7:0] bc[0:1],cc[0:1];
  wire detectors_flush[0:1],oe[0:1],oh[0:1],op[0:1],ov[0:1];
  wire orevoke[0:1],oconflict[0:1],osource[0:1],timed_out[0:1];
  wire [3:0] oi[0:1];
  wire [31:0] ot[0:1];
  wire [7:0] oc[0:1];

  genvar g;
  generate for(g=0;g<2;g=g+1) begin:lane_dut
    items14_result_join #(.TIMEOUT_MS(g==0?1:5)) dut (
      .clk(clk),.rst_n(rst_n[g]),.tick_1ms(tick_1ms[g]),.flush(flush[g]),
      .block_revoke(block_revoke[g]),.card_revoke(card_revoke[g]),
      .block_event(be[g]),.block_healthy(bh[g]),.block_present(bp[g]),.block_valid(bv[g]),
      .block_item(bi[g]),.block_frame_id(bt[g]),.block_source_test(bs[g]),.block_count(bc[g]),
      .card_event(ce[g]),.card_healthy(ch[g]),.card_present(cp[g]),.card_valid(cv[g]),
      .card_item(ci[g]),.card_frame_id(ct[g]),.card_source_test(cs[g]),.card_count(cc[g]),
      .detectors_flush(detectors_flush[g]),.out_event(oe[g]),.out_healthy(oh[g]),
      .out_present(op[g]),.out_valid(ov[g]),.out_revoke(orevoke[g]),.out_conflict(oconflict[g]),
      .out_item(oi[g]),.out_frame_id(ot[g]),.out_source_test(osource[g]),
      .out_count(oc[g]),.timed_out(timed_out[g]));
  end endgenerate

  task ck(input bit ok,input string label);
    begin
      checks=checks+1;
      if(!ok)begin errors=errors+1;$display("ERROR items14_join case=%0d time=%0t %s",scenarios,$time,label);end
    end
  endtask
  task start_case(input integer p,input string label);
    begin scenarios=scenarios+1;$display("CASE items14_join %0d lane=%0d %s",scenarios,p,label);end
  endtask
  // Payload is driven separately from event strobes; unframed levels may change.
  task payload(input integer p,input bit bhealthy,input bit bpresent,input bit bvalid,
    input integer bitem,input logic [31:0] btag,input bit bsource,input integer bcount,
    input bit chealthy,input bit cpresent,input bit cvalid,input integer citem,
    input logic [31:0] ctag,input bit csource,input integer ccount);
    begin
      bh[p]=bhealthy;bp[p]=bpresent;bv[p]=bvalid;bi[p]=bitem;bt[p]=btag;bs[p]=bsource;bc[p]=bcount;
      ch[p]=chealthy;cp[p]=cpresent;cv[p]=cvalid;ci[p]=citem;ct[p]=ctag;cs[p]=csource;cc[p]=ccount;
    end
  endtask
  task cycle(input integer p,input bit ms,input bit fl,input bit br,input bit cr,
    input bit b_event,input bit c_event,input bit expected_flush);
    begin
      @(negedge clk);
      tick_1ms[p]=ms;flush[p]=fl;block_revoke[p]=br;card_revoke[p]=cr;be[p]=b_event;ce[p]=c_event;
      #1;ck(detectors_flush[p]===expected_flush,"clear reaches both detectors before sampling edge");
      @(posedge clk);#1;
    end
  endtask
  task idle(input integer p,input bit ms,input bit expected_flush);
    begin cycle(p,ms,0,0,0,0,0,expected_flush);end
  endtask
  task expect_record(input integer p,input bit event_flag,input bit healthy,input bit present,
    input bit valid,input integer item,input logic [31:0] tag,input bit source,input integer count,
    input bit revoked,input bit conflict,input bit expired,input string label);
    begin
      ck(oe[p]===event_flag,{label," event"});ck(oh[p]===healthy,{label," healthy"});
      ck(op[p]===present,{label," presence"});ck(ov[p]===valid,{label," stable validity"});
      ck(oi[p]===item,{label," item"});ck(ot[p]===tag,{label," completed-frame tag"});
      ck(osource[p]===source,{label," source"});ck(oc[p]===count,{label," stable count"});
      ck(orevoke[p]===revoked,{label," revoke"});ck(oconflict[p]===conflict,{label," conflict"});
      ck(timed_out[p]===expired,{label," timeout latch"});
    end
  endtask
  task reset_lane(input integer p);
    begin
      @(negedge clk);rst_n[p]=0;tick_1ms[p]=0;flush[p]=0;block_revoke[p]=0;card_revoke[p]=0;
      be[p]=0;ce[p]=0;payload(p,0,0,0,0,0,0,0,0,0,0,0,0,0,0);
      @(posedge clk);#1;
      expect_record(p,0,0,1,0,0,0,0,0,0,0,0,"reset is not an observation of absence");
      ck(!detectors_flush[p],"reset has no outstanding clear request");
      @(negedge clk);rst_n[p]=1;
    end
  endtask
  task good_block(input integer p,input integer item,input logic [31:0] tag,input bit source,input integer count);
    begin
      // A real colored block also counts as card foreground; it is still unique.
      payload(p,1,1,1,item,tag,source,count,1,1,0,0,tag,source,0);
      cycle(p,0,0,0,0,1,1,0);
      expect_record(p,1,1,1,1,item,tag,source,count,0,0,0,"unique block with non-card foreground");
    end
  endtask
  task good_card(input integer p,input integer item,input logic [31:0] tag,input bit source,input integer count);
    begin
      payload(p,1,1,0,0,tag,source,0,1,1,1,item,tag,source,count);
      cycle(p,0,0,0,0,1,1,0);
      expect_record(p,1,1,1,1,item,tag,source,count,0,0,0,"unique card with unclassified color foreground");
    end
  endtask

  initial begin
    ignored=$value$plusargs("INJECT_FAULT=%d",inject_fault);
    for(lane=0;lane<2;lane=lane+1)begin
      rst_n[lane]=0;tick_1ms[lane]=0;flush[lane]=0;block_revoke[lane]=0;card_revoke[lane]=0;
      be[lane]=0;ce[lane]=0;payload(lane,0,0,0,0,0,0,0,0,0,0,0,0,0,0);
    end
    for(lane=0;lane<2;lane=lane+1)begin
      limit=lane==0?1:5;
      start_case(lane,"startup timeout uses sparse ticks and expires only once");
      reset_lane(lane);
      for(k=0;k<12;k=k+1)begin
        idle(lane,0,0);expect_record(lane,0,0,1,0,0,0,0,0,0,0,0,"clock cycles alone are not millisecond ticks");
      end
      for(k=1;k<limit;k=k+1)begin idle(lane,1,0);ck(!timed_out[lane]&&!oe[lane],"startup before final tick");end
      idle(lane,1,1);expect_record(lane,1,0,1,0,0,0,0,0,1,0,1,"startup final tick revokes");
      for(k=0;k<9;k=k+1)begin
        payload(lane,1,1,1,1,900,0,255,1,1,1,10,900,0,255);
        idle(lane,1,0);expect_record(lane,0,0,1,0,0,0,0,0,0,0,1,"held unframed data cannot feed watchdog");
      end

      start_case(lane,"all fourteen unique legal candidates and one actual output fault");
      reset_lane(lane);
      for(k=1;k<=14;k=k+1)begin
        if(k<=9)payload(lane,1,1,1,k,100+k,0,3+k,1,1,0,14,100+k,0,250);
        else payload(lane,1,1,0,9,100+k,0,250,1,1,1,k,100+k,0,3+k);
        cycle(lane,0,0,0,0,1,1,0);
        if(inject_fault && !injected && lane==1 && k==13)begin
          force lane_dut[1].dut.out_valid=1'b0;injected=1;#1;
        end
        expect_record(lane,1,1,1,1,k,100+k,0,3+k,0,0,0,"legal class with exact selected diagnostic count");
        if(inject_fault && lane==1 && k==13)release lane_dut[1].dut.out_valid;
      end
      idle(lane,0,0);expect_record(lane,0,1,1,1,14,114,0,17,0,0,0,"result held without repeated observation");

      start_case(lane,"block arrives first and unframed replacement payload is ignored");
      reset_lane(lane);
      payload(lane,1,1,1,6,200,0,33,1,1,1,12,999,1,99);
      cycle(lane,0,0,0,0,1,0,0);expect_record(lane,0,0,1,0,0,0,0,0,0,0,0,"single pending block is not a pair");
      for(k=0;k<4;k=k+1)begin
        payload(lane,0,0,1,15,888,1,255,0,0,1,15,777,1,255);
        idle(lane,0,0);expect_record(lane,0,0,1,0,0,0,0,0,0,0,0,"unframed illegal payload ignored");
      end
      payload(lane,0,0,1,15,888,1,255,1,1,0,0,200,0,0);
      cycle(lane,0,0,0,0,0,1,0);expect_record(lane,1,1,1,1,6,200,0,33,0,0,0,"stored block paired only with matching card event");

      start_case(lane,"card arrives first then stable result changes without a fake absence");
      payload(lane,0,0,1,15,888,1,255,1,1,1,13,201,0,200);
      cycle(lane,0,0,0,0,0,1,0);expect_record(lane,0,1,1,1,6,200,0,33,0,0,0,"old published result waits while card pending");
      payload(lane,1,0,0,0,201,0,0,0,0,1,15,777,1,255);
      cycle(lane,0,0,0,0,1,0,0);expect_record(lane,1,1,1,1,13,201,0,200,0,0,0,"stored card drives output metadata");

      start_case(lane,"healthy empty and each unknown presence combination remain distinct");
      for(k=0;k<4;k=k+1)begin
        payload(lane,1,k[0],0,9,210+k,0,2,1,k[1],0,14,210+k,0,2);
        cycle(lane,0,0,0,0,1,1,0);
        expect_record(lane,1,1,k!=0,0,0,210+k,0,0,0,0,0,"only both absent is trusted empty; unknown does not revoke");
      end

      start_case(lane,"conflict is healthy but revokes and advances anti-replay history");
      payload(lane,1,1,1,2,220,0,3,1,1,1,10,220,0,3);
      cycle(lane,0,0,0,0,1,1,1);expect_record(lane,1,1,1,0,0,220,0,0,1,1,0,"two stable candidates have no priority winner");
      idle(lane,0,0);expect_record(lane,0,1,1,0,0,220,0,0,0,0,0,"conflict notification is one cycle");
      payload(lane,1,1,1,2,220,0,3,1,1,0,0,220,0,0);
      cycle(lane,0,0,0,0,1,1,1);expect_record(lane,1,0,1,0,0,220,0,0,1,0,0,"same tag cannot return after conflict flush");
      good_card(lane,11,221,0,3);

      start_case(lane,"mismatched tags clear both slots and do not publish a crossed pair");
      payload(lane,1,1,1,3,230,0,5,1,0,0,0,231,0,0);
      cycle(lane,0,0,0,0,1,0,0);ck(!oe[lane],"mismatch first half pending");
      cycle(lane,0,0,0,0,0,1,1);expect_record(lane,1,0,1,0,0,221,0,0,1,0,0,"tag mismatch retains last published tag");
      payload(lane,1,1,1,4,232,0,7,1,1,0,0,232,0,0);
      cycle(lane,0,0,0,0,0,1,0);ck(!oe[lane],"old block slot was removed");
      cycle(lane,0,0,0,0,1,0,0);expect_record(lane,1,1,1,1,4,232,0,7,0,0,0,"fresh pair recovers after mismatch");

      start_case(lane,"same-frame source mismatch and epoch source change are rejected");
      payload(lane,1,1,1,5,233,0,3,1,1,0,0,233,1,0);
      cycle(lane,0,0,0,0,1,1,1);expect_record(lane,1,0,1,0,0,232,0,0,1,0,0,"sources differ within pair");
      payload(lane,1,1,0,0,234,1,0,1,1,1,14,234,1,3);
      cycle(lane,0,0,0,0,1,1,1);expect_record(lane,1,0,1,0,0,232,0,0,1,0,0,"internal fault cannot start a new source epoch");
      good_block(lane,5,235,0,3);

      start_case(lane,"same-port overflow drops both old and new transaction halves");
      payload(lane,1,1,1,6,240,0,3,1,1,0,0,240,0,0);
      cycle(lane,0,0,0,0,1,0,0);ck(!oe[lane],"first block occupies slot");
      payload(lane,1,1,1,7,241,0,3,1,1,0,0,240,0,0);
      cycle(lane,0,0,0,0,1,1,1);expect_record(lane,1,0,1,0,0,235,0,0,1,0,0,"overflow wins over otherwise completable old pair");
      payload(lane,1,1,1,7,241,0,3,1,1,0,0,241,0,0);
      cycle(lane,0,0,0,0,0,1,0);ck(!oe[lane],"overflow did not retain new block either");
      cycle(lane,0,0,0,0,1,0,0);expect_record(lane,1,1,1,1,7,241,0,3,0,0,0,"fresh block completes retained new card");
      payload(lane,1,1,0,0,242,0,0,1,1,1,12,242,0,3);
      cycle(lane,0,0,0,0,0,1,0);ck(!oe[lane],"first card occupies slot");
      cycle(lane,0,0,0,0,0,1,1);expect_record(lane,1,0,1,0,0,241,0,0,1,0,0,"card repeated event also overflows");

      start_case(lane,"malformed valid records and unhealthy frames revoke immediately");
      for(k=0;k<8;k=k+1)begin
        payload(lane,1,1,0,0,250+k,0,0,1,1,0,0,250+k,0,0);
        case(k)
          0:begin bv[lane]=1;bi[lane]=0;end
          1:begin bv[lane]=1;bi[lane]=10;end
          2:begin bv[lane]=1;bi[lane]=9;bp[lane]=0;end
          3:begin cv[lane]=1;ci[lane]=9;end
          4:begin cv[lane]=1;ci[lane]=15;end
          5:begin cv[lane]=1;ci[lane]=10;cp[lane]=0;end
          6:bh[lane]=0;
          7:ch[lane]=0;
        endcase
        cycle(lane,0,0,0,0,k<3||k==6,k>=3&&k!=6,1);
        expect_record(lane,1,0,1,0,0,241,0,0,1,0,0,"invalid half alone revokes without waiting for partner");
        idle(lane,0,0);ck(!oe[lane]&&!orevoke[lane],"event-driven fault does not repeat in empty cycle");
      end
      good_block(lane,8,260,0,3);

      start_case(lane,"duplicate backward and half-range tags cannot be replayed");
      for(k=0;k<3;k=k+1)begin
        if(k==0)payload(lane,1,0,0,0,260,0,0,1,0,0,0,260,0,0);
        if(k==1)payload(lane,1,0,0,0,259,0,0,1,0,0,0,259,0,0);
        if(k==2)payload(lane,1,0,0,0,32'h80000104,0,0,1,0,0,0,32'h80000104,0,0);
        cycle(lane,0,0,0,0,1,1,1);expect_record(lane,1,0,1,0,0,260,0,0,1,0,0,"replayed empty frame cannot rearm a consumer");
      end
      good_card(lane,14,261,0,255);

      start_case(lane,"external flush resets history while keeping last display tag on revoke");
      payload(lane,1,1,1,1,300,0,3,1,0,0,0,300,0,0);
      cycle(lane,1,1,0,0,1,1,1);expect_record(lane,1,0,1,0,0,261,0,0,1,0,0,"flush beats healthy pair and tick");
      for(k=0;k<7;k=k+1)begin
        cycle(lane,1,1,0,0,1,1,1);expect_record(lane,0,0,1,0,0,261,0,0,0,0,0,"held flush emits one notification and holds detectors clear");
      end
      idle(lane,0,0);expect_record(lane,0,0,1,0,0,261,0,0,0,0,0,"flush release cannot publish discarded pair");
      good_card(lane,10,32'hfffffffe,1,3);
      good_block(lane,1,32'hffffffff,1,3);
      good_card(lane,11,32'h00000000,1,3);
      good_block(lane,2,32'h7fffffff,1,3);
      payload(lane,1,0,0,0,32'hffffffff,1,0,1,0,0,0,32'hffffffff,1,0);
      cycle(lane,0,0,0,0,1,1,1);expect_record(lane,1,0,1,0,0,32'h7fffffff,1,0,1,0,0,"exact half range rejected after legal maximal forward jump");

      start_case(lane,"held detector revokes are explicit and do not erase replay history");
      reset_lane(lane);good_card(lane,12,400,0,9);
      payload(lane,1,1,1,2,401,0,3,1,0,0,0,401,0,0);
      cycle(lane,0,0,1,0,1,1,1);expect_record(lane,1,0,1,0,0,400,0,0,1,0,0,"block revoke wins over apparently healthy pair");
      for(k=0;k<5;k=k+1)begin
        cycle(lane,0,0,1,0,1,1,1);expect_record(lane,0,0,1,0,0,400,0,0,0,0,0,"held block revoke remains quiet");
      end
      idle(lane,0,0);ck(!oe[lane],"release discards all events presented under revoke");
      payload(lane,1,1,0,0,400,0,0,1,1,1,12,400,0,9);
      cycle(lane,0,0,0,0,1,1,1);expect_record(lane,1,0,1,0,0,400,0,0,1,0,0,"detector revoke preserves consumed tag history");
      good_block(lane,3,402,0,3);
      cycle(lane,0,0,0,1,0,0,1);expect_record(lane,1,0,1,0,0,402,0,0,1,0,0,"card revoke works without a result event");
      cycle(lane,0,0,0,1,0,0,1);expect_record(lane,0,0,1,0,0,402,0,0,0,0,0,"held card revoke is also one notification");
      idle(lane,0,0);good_card(lane,13,403,0,3);

      start_case(lane,"exact watchdog deadline accepts a healthy pair and renews fully");
      for(k=1;k<limit;k=k+1)begin idle(lane,1,0);ck(!timed_out[lane],"before declared deadline");end
      payload(lane,1,1,1,4,404,0,4,1,1,0,0,404,0,0);
      cycle(lane,1,0,0,0,1,1,0);expect_record(lane,1,1,1,1,4,404,0,4,0,0,0,"complete healthy pair wins final tick");
      for(k=1;k<limit;k=k+1)begin idle(lane,1,0);ck(!timed_out[lane],"full deadline interval after renewal");end
      idle(lane,1,1);expect_record(lane,1,0,1,0,0,404,0,0,1,0,1,"live result expires at next final tick");
      for(k=0;k<5;k=k+1)begin idle(lane,1,0);expect_record(lane,0,0,1,0,0,404,0,0,0,0,1,"continued stop cannot repeat timeout pulse");end
      payload(lane,1,0,0,0,404,0,0,1,0,0,0,404,0,0);
      cycle(lane,0,0,0,0,1,1,1);expect_record(lane,1,0,1,0,0,404,0,0,1,0,1,"duplicate healthy pair cannot recover timed-out epoch");
      payload(lane,1,0,0,0,405,0,0,1,1,0,0,405,0,0);
      cycle(lane,1,0,0,0,1,1,0);expect_record(lane,1,1,1,0,0,405,0,0,0,0,0,"fresh healthy unknown recovers without inventing stable class");

      start_case(lane,"unpaired healthy traffic cannot conceal partner disappearance");
      for(k=1;k<limit;k=k+1)begin idle(lane,1,0);ck(!timed_out[lane],"partner deadline not yet reached");end
      payload(lane,1,1,1,5,406,0,3,1,1,0,0,406,0,0);
      cycle(lane,1,0,0,0,1,0,1);expect_record(lane,1,0,1,0,0,405,0,0,1,0,1,"one healthy half does not win deadline");
      cycle(lane,0,0,0,0,0,1,0);expect_record(lane,0,0,1,0,0,405,0,0,0,0,1,"late partner cannot resurrect half discarded at timeout");
      cycle(lane,0,0,0,0,1,0,0);expect_record(lane,1,1,1,1,5,406,0,3,0,0,0,"only complete fresh pair recovers");

      start_case(lane,"bad records never renew watchdog even when both event strobes pulse");
      for(k=1;k<=limit;k=k+1)begin
        payload(lane,1,0,0,0,500+k,0,0,0,0,0,0,500+k,0,0);
        cycle(lane,1,0,0,0,1,1,1);
        expect_record(lane,1,0,1,0,0,406,0,0,1,0,k==limit,"unhealthy pair revokes and timer continues");
      end
      payload(lane,0,0,0,0,550,0,0,1,0,0,0,550,0,0);
      cycle(lane,1,0,0,0,1,1,1);expect_record(lane,1,0,1,0,0,406,0,0,1,0,1,"more bad frames cannot clear timeout");
      payload(lane,1,0,0,0,551,0,0,1,0,0,0,551,0,0);
      cycle(lane,1,0,0,0,1,1,0);expect_record(lane,1,1,0,0,0,551,0,0,0,0,0,"fresh healthy empty pair renews watchdog");

      start_case(lane,"conflict on final tick renews frame health but still revokes business result");
      for(k=1;k<limit;k=k+1)begin idle(lane,1,0);ck(!timed_out[lane],"conflict deadline approach");end
      payload(lane,1,1,1,9,552,0,3,1,1,1,14,552,0,3);
      cycle(lane,1,0,0,0,1,1,1);expect_record(lane,1,1,1,0,0,552,0,0,1,1,0,"healthy conflict wins timeout only, no selected object");
      for(k=1;k<limit;k=k+1)begin idle(lane,1,0);ck(!timed_out[lane],"conflict gave a complete renewal interval");end
      idle(lane,1,1);expect_record(lane,1,0,1,0,0,552,0,0,1,0,1,"timeout after conflict still emits normal revoke");

      reset_lane(lane);@(negedge clk);rst_n[lane]=0;
    end
    ck(!inject_fault || injected==1,"negative run forced exactly one actual DUT output");
    test_done=1;
    $display("RESULT tb_items14_join errors=%0d checks=%0d scenarios=%0d injected=%0d",errors,checks,scenarios,injected);
    $finish;
  end
  initial begin
    #1000000;errors=errors+1;
    $display("WATCHDOG tb_items14_join errors=%0d checks=%0d scenarios=%0d",errors,checks,scenarios);
    $finish;
  end
endmodule
