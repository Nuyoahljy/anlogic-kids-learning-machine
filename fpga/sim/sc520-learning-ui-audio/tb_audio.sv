`timescale 1ns/1ps
module tb_audio;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0, flush=0, tick=0;
    reg [2:0] audio_event=0; reg [3:0] audio_item_id=0;
    reg manual_mode=1, man_ready=1, man_busy=0, man_rsp_valid=0, man_rsp_error=0;
    reg [15:0] man_rsp_tag=0;
    wire cmd_valid, cmd_ready, rsp_valid, rsp_error, player_busy;
    wire [3:0] cmd_item; wire [2:0] cmd_event; wire [15:0] cmd_tag, rsp_tag;
    wire [1:0] status; wire pending, completed_pulse, failed_pulse;
    wire mock_ready, mock_busy, mock_rsp_valid, mock_rsp_error; wire [15:0] mock_rsp_tag;
    assign cmd_ready=manual_mode?man_ready:mock_ready;
    assign player_busy=manual_mode?man_busy:mock_busy;
    assign rsp_valid=manual_mode?man_rsp_valid:mock_rsp_valid;
    assign rsp_tag=manual_mode?man_rsp_tag:mock_rsp_tag;
    assign rsp_error=manual_mode?man_rsp_error:mock_rsp_error;
    audio_event_player #(.READY_TIMEOUT_TICKS(3),.PLAY_TIMEOUT_TICKS(4),.MAX_RETRIES(1)) dut(
        .clk(clk),.rst_n(rst_n),.flush(flush),.tick(tick),.audio_event(audio_event),.audio_item_id(audio_item_id),
        .cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd_item(cmd_item),.cmd_event(cmd_event),.cmd_tag(cmd_tag),
        .rsp_valid(rsp_valid),.rsp_tag(rsp_tag),.rsp_error(rsp_error),.player_busy(player_busy),
        .status(status),.pending(pending),.completed_pulse(completed_pulse),.failed_pulse(failed_pulse));
    mock_audio_player #(.PLAY_TICKS(2)) mock(
        .clk(clk),.rst_n(rst_n),.flush(flush),.tick(tick),.cmd_valid(cmd_valid && !manual_mode),
        .cmd_ready(mock_ready),.cmd_item(cmd_item),.cmd_event(cmd_event),.cmd_tag(cmd_tag),
        .rsp_valid(mock_rsp_valid),.rsp_tag(mock_rsp_tag),.rsp_error(mock_rsp_error),.player_busy(mock_busy));

    // Independent one-tick / zero-retry controller and directly driven mock.
    reg e_rst=0,e_flush=0,e_tick=0,e_ready=0,e_busy=0,e_rsp_valid=0,e_error=0;
    reg [2:0] e_event=0; reg [3:0] e_item=0; reg [15:0] e_tag=0;
    wire e_valid,e_pending,e_done,e_failed; wire [3:0] e_cmd_item; wire [2:0] e_cmd_event;
    wire [15:0] e_cmd_tag; wire [1:0] e_status;
    audio_event_player #(.READY_TIMEOUT_TICKS(1),.PLAY_TIMEOUT_TICKS(1),.MAX_RETRIES(0)) edge_dut(
        .clk(clk),.rst_n(e_rst),.flush(e_flush),.tick(e_tick),.audio_event(e_event),.audio_item_id(e_item),
        .cmd_valid(e_valid),.cmd_ready(e_ready),.cmd_item(e_cmd_item),.cmd_event(e_cmd_event),.cmd_tag(e_cmd_tag),
        .rsp_valid(e_rsp_valid),.rsp_tag(e_tag),.rsp_error(e_error),.player_busy(e_busy),.status(e_status),
        .pending(e_pending),.completed_pulse(e_done),.failed_pulse(e_failed));
    reg m_rst=0,m_flush=0,m_tick=0,m_valid=0; reg [3:0] m_item=0; reg [2:0] m_event=0; reg [15:0] m_tag=0;
    wire m_ready,m_rsp_valid,m_error,m_busy; wire [15:0] m_rsp_tag;
    mock_audio_player #(.PLAY_TICKS(1)) edge_mock(.clk(clk),.rst_n(m_rst),.flush(m_flush),.tick(m_tick),
        .cmd_valid(m_valid),.cmd_ready(m_ready),.cmd_item(m_item),.cmd_event(m_event),.cmd_tag(m_tag),
        .rsp_valid(m_rsp_valid),.rsp_tag(m_rsp_tag),.rsp_error(m_error),.player_busy(m_busy));

    // Instantiate without parameter overrides to cover shipped 300/900/1/120 defaults.
    reg d_rst=0,d_flush=0,d_tick=0,d_manual=1,d_ready=1,d_busy=0,d_rsp_valid=0,d_error=0;
    reg [2:0] d_event=0; reg [3:0] d_item=0; reg [15:0] d_rsp_tag=0;
    wire d_valid,d_pending,d_done,d_failed; wire [3:0] d_cmd_item; wire [2:0] d_cmd_event;
    wire [15:0] d_cmd_tag; wire [1:0] d_status;
    wire dm_ready,dm_busy,dm_rsp_valid,dm_error; wire [15:0] dm_rsp_tag;
    audio_event_player default_dut(.clk(clk),.rst_n(d_rst),.flush(d_flush),.tick(d_tick),
        .audio_event(d_event),.audio_item_id(d_item),.cmd_valid(d_valid),
        .cmd_ready(d_manual?d_ready:dm_ready),.cmd_item(d_cmd_item),.cmd_event(d_cmd_event),.cmd_tag(d_cmd_tag),
        .rsp_valid(d_manual?d_rsp_valid:dm_rsp_valid),.rsp_tag(d_manual?d_rsp_tag:dm_rsp_tag),
        .rsp_error(d_manual?d_error:dm_error),.player_busy(d_manual?d_busy:dm_busy),
        .status(d_status),.pending(d_pending),.completed_pulse(d_done),.failed_pulse(d_failed));
    mock_audio_player default_mock(.clk(clk),.rst_n(d_rst),.flush(d_flush),.tick(d_tick),
        .cmd_valid(d_valid && !d_manual),.cmd_ready(dm_ready),.cmd_item(d_cmd_item),.cmd_event(d_cmd_event),.cmd_tag(d_cmd_tag),
        .rsp_valid(dm_rsp_valid),.rsp_tag(dm_rsp_tag),.rsp_error(dm_error),.player_busy(dm_busy));

    integer errors=0, checks=0, cases=0, cycles=0, handshakes=0, completions=0, failures=0;
    integer base_h, base_c, base_f, default_tick; reg [15:0] old_tag, retry_tag;
    reg [3:0] history_item[0:255]; reg [2:0] history_event[0:255]; reg [15:0] history_tag[0:255];
    reg test_done=0; reg [15:0] offered_tag; reg [3:0] offered_item; reg [2:0] offered_event; reg stalled=0;
    always @(posedge clk) begin
        if(rst_n && !flush && cmd_valid && cmd_ready) begin
            history_item[handshakes]=cmd_item; history_event[handshakes]=cmd_event; history_tag[handshakes]=cmd_tag;
            handshakes=handshakes+1;
        end
        if(rst_n && completed_pulse) completions=completions+1;
        if(rst_n && failed_pulse) failures=failures+1;
        // Transaction metadata must not change during an unaccepted offer.
        if(stalled && rst_n && !flush && status==1) begin
            if({cmd_tag,cmd_item,cmd_event} !== {offered_tag,offered_item,offered_event}) begin
                errors=errors+1; $display("FAIL metadata changed while stalled at %0t",$time);
            end
        end
        stalled=rst_n && !flush && status==1 && !(cmd_valid && cmd_ready);
        offered_tag=cmd_tag; offered_item=cmd_item; offered_event=cmd_event;
    end
    task check(input bit good,input string msg); begin checks=checks+1; if(!good) begin errors=errors+1; $display("FAIL case=%0d %s t=%0t",cases,msg,$time); end end endtask
    task case_start(input string msg); begin cases=cases+1; $display("CASE %0d %s",cases,msg); end endtask
    task step; begin @(posedge clk); #1; cycles=cycles+1; end endtask
    task clocks(input integer n); integer i; begin for(i=0;i<n;i=i+1) begin @(negedge clk); step(); end end endtask
    task reset_main; begin
        @(negedge clk); rst_n=0; flush=0; tick=0; audio_event=0; audio_item_id=0;
        manual_mode=1; man_ready=1; man_busy=0; man_rsp_valid=0; man_rsp_error=0; man_rsp_tag=0;
        step(); check(status==0 && !pending && !cmd_valid && !completed_pulse && !failed_pulse,"reset clear");
        @(negedge clk); rst_n=1; step();
    end endtask
    task send(input reg [3:0] item,input reg [2:0] evt); begin
        @(negedge clk); audio_item_id=item; audio_event=evt; step(); @(negedge clk); audio_event=0;
    end endtask
    task start_play(input reg [3:0] item,input reg [2:0] evt); begin
        send(item,evt); check(status==1 && cmd_item==item && cmd_event==evt,"offer metadata");
        step(); check(status==2,"accepted -> playing");
    end endtask
    task pulse_tick; begin @(negedge clk); tick=1; step(); @(negedge clk); tick=0; end endtask
    task response(input reg [15:0] tag,input bit err); begin
        @(negedge clk); man_rsp_valid=1; man_rsp_tag=tag; man_rsp_error=err; step();
        @(negedge clk); man_rsp_valid=0; man_rsp_error=0;
    end endtask
    task flush_main; begin @(negedge clk); flush=1; step(); @(negedge clk); flush=0; end endtask
    task reset_default; begin
        @(negedge clk); d_rst=0; d_flush=0; d_tick=0; d_manual=1; d_ready=1; d_busy=0;
        d_rsp_valid=0; d_error=0; d_event=0; d_item=0; d_rsp_tag=0;
        step(); @(negedge clk); d_rst=1; step();
        check(d_status==0 && !d_pending,"default controller reset");
    end endtask
    task start_default; begin
        @(negedge clk); d_event=1; d_item=1; step();
        @(negedge clk); d_event=0; d_tick=1; step();
        check(d_status==2 && !d_failed,"default handshake with tick");
    end endtask

    initial begin
        case_start("invalid inputs ignored; reset"); reset_main(); base_h=handshakes;
        send(0,1); send(10,1); send(15,5); send(1,0); send(1,2); send(1,3); send(1,4); send(1,6); send(1,7);
        clocks(2); check(status==0 && !pending && handshakes==base_h,"unsupported events/items ignored");

        case_start("name success; pulses one cycle; no auto repetition"); reset_main(); base_h=handshakes;
        start_play(1,1); old_tag=cmd_tag; response(old_tag,0);
        check(status==0 && completed_pulse && !failed_pulse,"matching success completes");
        clocks(1); check(!completed_pulse && !failed_pulse,"completion pulse cleared");
        clocks(8); check(handshakes==base_h+1 && status==0,"no spontaneous replay");

        case_start("automatic active and pending duplicate merge"); reset_main(); start_play(2,1); old_tag=cmd_tag; base_h=handshakes;
        send(2,1); check(!pending,"active auto duplicate ignored"); send(3,1); check(pending,"new item queued");
        send(3,1); check(pending,"pending duplicate merged"); response(old_tag,0); clocks(2);
        check(handshakes==base_h+1 && cmd_item==3 && status==2,"pending once"); response(cmd_tag,0); clocks(4);
        check(status==0 && !pending && handshakes==base_h+1,"queue drained once");

        case_start("latest pending replaces earlier item"); reset_main(); start_play(1,1); old_tag=cmd_tag; base_h=handshakes;
        send(2,1); send(3,1); send(9,1); response(old_tag,0); clocks(2);
        check(handshakes==base_h+1 && cmd_item==9,"only latest pending accepted"); response(cmd_tag,0); clocks(3); check(status==0,"no hidden queue");

        case_start("explicit replay queues active; repeated replay merges pending"); reset_main(); start_play(4,1); old_tag=cmd_tag; base_h=handshakes;
        send(4,5); send(4,5); send(4,1); check(pending,"single replay pending survives auto duplicate");
        response(old_tag,0); clocks(2); check(handshakes==base_h+1 && cmd_event==5 && cmd_item==4,"replay dispatched once");
        response(cmd_tag,0); clocks(3); check(status==0 && handshakes==base_h+1,"repeat key does not stack pending copies");

        case_start("replay upgrades same pending item; promotion edge merge"); reset_main(); start_play(1,1); old_tag=cmd_tag; base_h=handshakes;
        send(2,1); send(2,5); response(old_tag,0);
        // Drive duplicate in the same edge that promotes pending.
        audio_event=5; audio_item_id=2; step(); @(negedge clk); audio_event=0; step();
        check(status==2 && cmd_event==5 && cmd_item==2 && !pending && handshakes==base_h+1,"promotion duplicate merged");

        case_start("safe not-started error retries with fresh tag"); reset_main(); start_play(5,1); old_tag=cmd_tag; base_h=handshakes;
        send(6,1); response(old_tag,1); retry_tag=cmd_tag;
        check(status==1 && retry_tag!=old_tag && pending && !failed_pulse,"bounded retry retains pending");
        step(); check(status==2 && handshakes==base_h+1,"retry accepted");
        response(old_tag,0); check(status==2 && !completed_pulse,"old attempt success ignored");
        response(retry_tag,0); clocks(2); check(status==2 && cmd_item==6,"pending follows retry success"); response(cmd_tag,0); clocks(3);

        case_start("safe error retry exhausted enters latched fault and clears queue"); reset_main(); start_play(7,1); old_tag=cmd_tag;
        send(8,1); response(old_tag,1); step(); old_tag=cmd_tag; response(old_tag,1);
        check(status==3 && failed_pulse && !pending && !cmd_valid,"second rejection fails"); base_h=handshakes;
        send(9,1); response(old_tag,0); clocks(5); check(status==3 && !failed_pulse && handshakes==base_h,"fault ignores late success and events");
        flush_main(); check(status==0 && !pending,"flush recovers fault"); start_play(9,1); response(cmd_tag,0); clocks(2);

        case_start("ready stall stable metadata and timeout only on tick"); reset_main(); man_ready=0; send(1,1); old_tag=cmd_tag; base_h=handshakes;
        clocks(12); check(status==1 && cmd_tag==old_tag,"no tick no timeout"); send(2,1); pulse_tick(); pulse_tick();
        check(status==1 && pending && handshakes==base_h,"offer before third tick"); pulse_tick();
        check(status==3 && failed_pulse && !pending && handshakes==base_h,"ready timeout uncertain no retry");
        man_ready=1; clocks(3); check(status==3,"ready arriving late cannot recover");

        case_start("busy blocks offer despite ready; deassert allows acceptance"); reset_main(); man_busy=1; send(2,1); base_h=handshakes;
        check(status==1 && !cmd_valid,"busy suppresses offer"); pulse_tick(); pulse_tick(); check(handshakes==base_h,"busy handshake blocked");
        man_busy=0; step(); check(status==2 && handshakes==base_h+1,"busy release accepted"); response(cmd_tag,0); clocks(2);

        case_start("busy held enters ready timeout"); reset_main(); man_busy=1; send(3,1); base_h=handshakes;
        pulse_tick(); pulse_tick(); pulse_tick(); check(status==3 && failed_pulse && handshakes==base_h,"busy timeout");

        case_start("acceptance wins ready timeout boundary"); reset_main(); man_ready=0; send(4,1); pulse_tick(); pulse_tick();
        @(negedge clk); man_ready=1; tick=1; step(); check(status==2 && !failed_pulse,"handshake priority on third tick");
        @(negedge clk); tick=0; response(cmd_tag,0); clocks(2);

        case_start("playing timeout uncertain; queue cleared; no replay"); reset_main(); start_play(5,1); old_tag=cmd_tag; send(6,1); base_h=handshakes;
        clocks(12); check(status==2,"play timer waits tick"); pulse_tick(); pulse_tick(); pulse_tick(); check(status==2,"playing before fourth tick");
        pulse_tick(); check(status==3 && failed_pulse && !pending,"playing timeout fault"); response(old_tag,0); clocks(3);
        check(status==3 && handshakes==base_h,"no unsafe timeout retry");

        case_start("matching completion wins play timeout boundary"); reset_main(); start_play(6,1); old_tag=cmd_tag;
        pulse_tick(); pulse_tick(); pulse_tick(); @(negedge clk); tick=1; man_rsp_valid=1; man_rsp_tag=old_tag;
        step(); check(status==0 && completed_pulse && !failed_pulse,"response priority fourth tick");
        @(negedge clk); tick=0; man_rsp_valid=0; clocks(2);

        case_start("wrong-tag responses ignored including deadline"); reset_main(); start_play(7,1); old_tag=cmd_tag;
        response(old_tag+1,0); response(old_tag+1,1); check(status==2 && !completed_pulse,"wrong tag no effect");
        pulse_tick(); pulse_tick(); pulse_tick(); @(negedge clk); tick=1; man_rsp_valid=1; man_rsp_tag=old_tag+1;
        step(); check(status==3 && failed_pulse,"wrong response cannot defer timeout"); @(negedge clk); tick=0; man_rsp_valid=0;

        case_start("flush cancels offer/pending and stale response cannot finish next command"); reset_main(); man_ready=0; send(8,1); old_tag=cmd_tag; send(9,1);
        flush_main(); check(status==0 && !pending && !cmd_valid,"flush clears stalled offer"); man_ready=1; start_play(1,1);
        check(cmd_tag!=old_tag,"flush/new command tag differs"); response(old_tag,0); check(status==2 && !completed_pulse,"pre-flush response ignored"); response(cmd_tag,0); clocks(2);

        case_start("flush dominates accepted response/tick/event"); reset_main(); start_play(2,1); old_tag=cmd_tag;
        @(negedge clk); flush=1; tick=1; man_rsp_valid=1; man_rsp_tag=old_tag; audio_event=1; audio_item_id=3;
        step(); check(status==0 && !pending && !completed_pulse && !failed_pulse,"flush priority");
        @(negedge clk); flush=0; tick=0; man_rsp_valid=0; audio_event=0; clocks(3); check(status==0,"event during flush discarded");

        case_start("reset cancels playing and fault; all pulse outputs clear"); reset_main(); start_play(3,1); send(4,1); reset_main();
        check(status==0 && !pending,"playing reset"); man_ready=0; send(5,1); pulse_tick(); pulse_tick(); pulse_tick(); check(status==3,"fault set"); reset_main();
        check(status==0,"reset recovers fault");

        case_start("event coincident with success; active auto is duplicate"); reset_main(); start_play(1,1); old_tag=cmd_tag; base_h=handshakes;
        @(negedge clk); man_rsp_valid=1; man_rsp_tag=old_tag; audio_event=1; audio_item_id=1; step();
        @(negedge clk); man_rsp_valid=0; audio_event=0; clocks(3); check(status==0 && handshakes==base_h,"same-edge automatic duplicate suppressed");
        start_play(2,1); old_tag=cmd_tag; @(negedge clk); man_rsp_valid=1; man_rsp_tag=old_tag; audio_event=1; audio_item_id=3; step();
        @(negedge clk); man_rsp_valid=0; audio_event=0; clocks(2); check(status==2 && cmd_item==3,"different event survives completion"); response(cmd_tag,0); clocks(2);

        case_start("mock integrated success and two tick completion"); reset_main(); manual_mode=0; base_h=handshakes;
        start_play(4,1); check(mock_busy,"mock started"); clocks(5); check(mock_busy && status==2,"mock waits tick");
        pulse_tick(); check(mock_busy && !mock_rsp_valid,"first tick not done"); pulse_tick(); check(!mock_busy && mock_rsp_valid,"second tick done");
        step(); check(status==0 && completed_pulse,"controller consumes mock response"); clocks(2); check(handshakes==base_h+1,"mock no repetition");

        case_start("mock flush cancels playback and queued item"); reset_main(); manual_mode=0; start_play(5,1); send(6,1); pulse_tick();
        flush_main(); check(status==0 && !pending && !mock_busy && !mock_rsp_valid,"joint flush cancels mock"); pulse_tick(); pulse_tick(); clocks(2);
        check(status==0 && !mock_rsp_valid,"cancelled mock emits no delayed response");

        case_start("one-tick timeout, zero retries and handshake precedence");
        @(negedge clk); e_rst=1; e_event=1; e_item=1; step(); @(negedge clk); e_event=0; e_tick=1;
        step(); check(e_status==3 && e_failed,"one tick ready timeout");
        @(negedge clk); e_flush=1; step(); @(negedge clk); e_flush=0; e_event=1; e_ready=1; step();
        @(negedge clk); e_event=0; step(); check(e_status==2 && !e_failed,"one tick handshake wins");
        @(negedge clk); e_tick=0; e_rsp_valid=1; e_tag=e_cmd_tag; e_error=1; step(); check(e_status==3 && e_failed,"zero retries fails first rejection");
        @(negedge clk); e_rsp_valid=0; e_error=0; e_flush=1; step();
        @(negedge clk); e_flush=0; e_event=1; step(); @(negedge clk); e_event=0; step();
        @(negedge clk); e_tick=1; step(); check(e_status==3 && e_failed,"one tick playing timeout");
        @(negedge clk); e_rst=0; e_tick=0;

        case_start("direct mock invalid command, one-tick boundary, busy and reset");
        @(negedge clk); m_rst=1; m_valid=1; m_item=0; m_event=1; m_tag=16'h1234; step();
        check(m_rsp_valid && m_error && m_rsp_tag==16'h1234 && !m_busy,"mock rejects invalid without start");
        @(negedge clk); m_item=9; m_event=5; m_tag=16'h5678; m_tick=1; step();
        check(m_busy && !m_rsp_valid && !m_ready,"accept edge tick not counted");
        @(negedge clk); m_item=8; m_tag=16'hffff; step();
        check(!m_busy && m_rsp_valid && !m_error && m_rsp_tag==16'h5678,"busy command ignored; first later tick completes original");
        @(negedge clk); m_valid=0; m_tick=0; step(); check(!m_rsp_valid,"mock pulse one cycle");
        @(negedge clk); m_valid=1; m_item=1; m_event=1; step(); @(negedge clk); m_rst=0; step();
        check(!m_busy && !m_rsp_valid && !m_ready,"mock reset cancels"); @(negedge clk); m_valid=0;

        case_start("default mock completes exactly 120 ticks after handshake"); reset_default(); d_manual=0; start_default();
        check(dm_busy && !dm_rsp_valid,"default mock handshake does not count tick");
        for(default_tick=1;default_tick<120;default_tick=default_tick+1) begin
            @(negedge clk); step();
            check(dm_busy && !dm_rsp_valid && d_status==2 && !d_done,"default mock not early");
        end
        @(negedge clk); step(); check(!dm_busy && dm_rsp_valid && !dm_error,"default mock 120th tick completes");
        @(negedge clk); d_tick=0; step(); check(d_status==0 && d_done && !d_failed,"default mock completion consumed");

        case_start("default ready timeout exactly 300 ticks"); reset_default(); d_ready=0;
        @(negedge clk); d_event=1; d_item=2; step(); @(negedge clk); d_event=0; d_tick=1;
        for(default_tick=1;default_tick<300;default_tick=default_tick+1) begin
            step(); check(d_status==1 && !d_failed,"default ready not early"); @(negedge clk);
        end
        step(); check(d_status==3 && d_failed && !d_valid,"default ready 300th tick faults");
        @(negedge clk); d_tick=0;

        case_start("default playing timeout exactly 900 ticks"); reset_default(); start_default();
        for(default_tick=1;default_tick<900;default_tick=default_tick+1) begin
            @(negedge clk); step(); check(d_status==2 && !d_failed,"default playing not early");
        end
        @(negedge clk); step(); check(d_status==3 && d_failed && !d_valid,"default playing 900th tick faults");
        @(negedge clk); d_tick=0;

        case_start("default MAX_RETRIES=1 retries once then faults"); reset_default(); start_default(); old_tag=d_cmd_tag;
        @(negedge clk); d_tick=0; d_rsp_valid=1; d_rsp_tag=old_tag; d_error=1; step();
        check(d_status==1 && d_cmd_tag!=old_tag && !d_failed,"default first rejection retries fresh tag"); retry_tag=d_cmd_tag;
        @(negedge clk); d_rsp_valid=0; d_error=0; step(); check(d_status==2,"default retry accepted");
        @(negedge clk); d_rsp_valid=1; d_rsp_tag=retry_tag; d_error=1; step();
        check(d_status==3 && d_failed && !d_pending,"default second rejection exhausts");
        @(negedge clk); d_rsp_valid=0; d_error=0; d_rst=0;

        case_start("fault output checker negative control");
        if($test$plusargs("negative_control")) begin
            reset_main(); man_ready=0; send(1,1); force dut.state=2'd0; pulse_tick(); pulse_tick(); pulse_tick();
            check(status==3 && failed_pulse,"injected state fault must be detected"); release dut.state;
        end
        test_done=1; $display("AUDIO_RESULT cases=%0d checks=%0d errors=%0d cycles=%0d handshakes=%0d completions=%0d failures=%0d",cases,checks,errors,cycles,handshakes,completions,failures);
    end
endmodule
