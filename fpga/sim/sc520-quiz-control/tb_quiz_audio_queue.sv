`timescale 1ns/1ps
module tb_quiz_audio_queue;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0, tick_1ms=0, cancel=0, event_valid=0;
    reg [2:0] event_kind=0; reg [3:0] event_item=0;
    wire idle,fault,overflow,req_valid,stop_valid;
    wire [2:0] req_kind; wire [3:0] req_item;
    wire [15:0] req_tag,stop_tag;
    reg req_ready=0,device_busy=0,rsp_valid=0;
    reg [15:0] rsp_tag=0; reg [1:0] rsp_code=0;
    reg test_done=0;
    integer errors=0,checks=0,scenarios=0;
    reg [15:0] first_tag, second_tag;
    integer i;
    quiz_audio_queue #(.DEPTH(4),.WAIT_TICKS(4),.PLAY_TICKS(6),.STOP_TICKS(3)) dut (.*);

    task automatic step;
        @(posedge clk); #1; @(negedge clk); #1;
    endtask
    task automatic check(input bit good,input string why);
        checks=checks+1;
        if (!good) begin errors=errors+1; $display("CHECK_FAIL audio t=%0t %s",$time,why); end
    endtask
    task automatic scenario(input string name);
        scenarios=scenarios+1; $display("CASE audio %0d %s",scenarios,name);
    endtask
    task automatic reset_dut;
        rst_n=0; cancel=0; event_valid=0; tick_1ms=0;
        req_ready=0; device_busy=0; rsp_valid=0;
        step(); step(); rst_n=1; step();
        check(idle && !fault && !overflow && !req_valid && !stop_valid,"reset clears outputs");
    endtask
    task automatic send_event(input [2:0] kind,input [3:0] item);
        event_valid=1; event_kind=kind; event_item=item; step(); event_valid=0;
    endtask
    task automatic ticks(input integer n);
        tick_1ms=1; repeat(n) step(); tick_1ms=0;
    endtask
    task automatic response(input [15:0] tag,input [1:0] code);
        rsp_valid=1; rsp_tag=tag; rsp_code=code; step(); rsp_valid=0;
    endtask
    task automatic expect_request(input [2:0] kind,input [3:0] item);
        integer timeout;
        timeout=0;
        while (!req_valid && timeout<12) begin step(); timeout=timeout+1; end
        check(req_valid,"request appeared");
        check(req_kind===kind && req_item===item,"FIFO request kind/item");
        check(!stop_valid,"request never overlaps stop");
    endtask
    task automatic accept_request;
        req_ready=1; step(); req_ready=0;
        check(!req_valid && !idle,"accepted transaction remains active");
    endtask
    task automatic finish_request;
        response(req_tag,0); step();
    endtask

    initial begin
        #1;
        scenario("FIFO correct feedback then next question; replay retained");
        reset_dut();
        send_event(2,1);
        if ($test$plusargs("NEGATIVE")) force req_kind=3'd4;
        expect_request(2,1); first_tag=req_tag;
        if ($test$plusargs("NEGATIVE")) release req_kind;
        accept_request(); send_event(3,1); send_event(2,2); send_event(2,2);
        response(first_tag,2); check(!idle && !req_valid,"ACK not track done");
        device_busy=1; step(); device_busy=0; step();
        check(!req_valid && !idle,"busy falling not track done");
        response(first_tag+1,0); check(!req_valid && !idle,"wrong tag ignored");
        finish_request(); expect_request(3,1); accept_request(); finish_request();
        expect_request(2,2); accept_request(); finish_request();
        expect_request(2,2); accept_request(); finish_request();
        check(idle && !fault,"queue drained in strict order");

        scenario("all supported kinds and nine item payloads");
        for(i=1;i<=9;i=i+1) begin
            send_event(1,i[3:0]); expect_request(1,i[3:0]); accept_request(); finish_request();
        end
        send_event(4,9); expect_request(4,9); accept_request(); finish_request();
        send_event(6,0); expect_request(6,0); accept_request(); finish_request();
        send_event(7,0); expect_request(7,0); accept_request(); finish_request();

        scenario("ready and busy independently gate acceptance");
        reset_dut(); device_busy=1; req_ready=1; send_event(2,3); step();
        check(!req_valid && !idle,"busy inhibits new command"); ticks(2);
        device_busy=0; req_ready=0; #1; expect_request(2,3); first_tag=req_tag;
        step(); check(req_valid && req_tag==first_tag,"request stable under backpressure");
        tick_1ms=1; req_ready=1; step(); tick_1ms=0; req_ready=0;
        check(!fault && !req_valid,"acceptance beats wait timeout boundary"); finish_request();

        scenario("one explicit refusal retry uses a new tag");
        reset_dut(); send_event(2,4); expect_request(2,4); first_tag=req_tag; accept_request();
        response(first_tag,1); expect_request(2,4); second_tag=req_tag;
        check(first_tag!=second_tag,"retry gets new tag"); accept_request();
        response(first_tag,0); check(!idle,"old attempt completion ignored");
        finish_request(); check(idle && !fault,"retry completes");

        scenario("second refusal is a bounded failure");
        reset_dut(); send_event(2,4); expect_request(2,4); accept_request();
        response(req_tag,1); expect_request(2,4); accept_request(); response(req_tag,1);
        check(fault && idle && !stop_valid && !req_valid,"two explicit refusals fail without uncertain replay");
        cancel=1; step(); cancel=0; send_event(2,1); step();
        check(fault && idle && !req_valid,"cancel does not recover fault");

        scenario("never-ready timeout exact boundary");
        reset_dut(); send_event(2,1); expect_request(2,1); ticks(3);
        check(!fault && req_valid,"wait survives first three ticks"); ticks(1);
        check(fault && idle && !req_valid && !stop_valid,"fourth waiting tick fails");

        scenario("busy forever also reaches wait timeout");
        reset_dut(); device_busy=1; send_event(2,1); step(); ticks(4);
        check(fault && idle,"busy cannot indefinitely stall controller");

        scenario("ACK does not extend playback deadline; fault requests stop");
        reset_dut(); send_event(2,1); expect_request(2,1); accept_request();
        ticks(5); check(!fault,"play survives first five ticks");
        tick_1ms=1; response(req_tag,2); tick_1ms=0;
        check(fault && idle && stop_valid && !req_valid,"sixth tick with ACK still expires");
        first_tag=stop_tag; response(first_tag+1,3); check(stop_valid,"wrong stop tag ignored");
        response(first_tag,0); check(stop_valid,"track done is not stop acknowledgement");
        response(first_tag,3); check(!stop_valid && fault && idle,"confirmed stop preserves fault");

        scenario("end-of-track response beats playback timeout boundary");
        reset_dut(); send_event(2,2); expect_request(2,2); accept_request(); ticks(5);
        tick_1ms=1; response(req_tag,0); tick_1ms=0;
        check(idle && !fault && !stop_valid,"matching done wins boundary");

        scenario("cancel wins event and pending request acceptance");
        reset_dut(); send_event(2,2); expect_request(2,2);
        req_ready=1; cancel=1; event_valid=1; event_kind=4; step();
        req_ready=0; cancel=0; event_valid=0; step();
        check(idle && !fault && !stop_valid && !req_valid,"unaccepted transaction withdrawn without stop");

        scenario("cancel wins waiting and playback timeout boundaries");
        reset_dut(); send_event(2,2); expect_request(2,2); ticks(3);
        cancel=1; ticks(1); cancel=0;
        check(idle && !fault && !req_valid,"cancel beats waiting timeout");
        send_event(2,3); expect_request(2,3); accept_request(); ticks(5);
        cancel=1; ticks(1); cancel=0;
        check(stop_valid && !fault && !req_valid,"cancel beats playback timeout");
        response(stop_tag,3); check(idle && !fault,"canceled boundary resumes normally");

        scenario("cancel clears old queue; new events wait for stop completion");
        reset_dut(); send_event(2,3); expect_request(2,3); first_tag=req_tag; accept_request();
        send_event(3,3); cancel=1; event_valid=1; event_kind=4; step();
        cancel=0; event_valid=0;
        check(stop_valid && stop_tag==first_tag && !idle,"active cancel requests stop");
        send_event(2,4); req_ready=1; step(); req_ready=0;
        check(stop_valid && !req_valid,"new prompt held behind stop");
        response(first_tag,2); check(stop_valid,"ACK cannot satisfy stop");
        response(first_tag,3); expect_request(2,4); second_tag=req_tag;
        check(second_tag!=first_tag,"new prompt gets fresh tag after cancel");
        accept_request(); response(first_tag,0); check(!idle,"late canceled done ignored");
        finish_request(); check(idle && !fault,"normal cancel permits recovery");

        scenario("repeated cancel does not postpone stop timeout");
        reset_dut(); send_event(2,5); expect_request(2,5); accept_request();
        cancel=1; step(); cancel=0; ticks(2); check(stop_valid && !fault,"stop first two ticks");
        cancel=1; ticks(1); cancel=0;
        check(fault && idle && !stop_valid && !req_valid,"third stop tick fails even with cancel");
        send_event(2,1); step(); check(!req_valid,"uncertain stop never restarts audio");

        scenario("stop response beats timeout boundary");
        reset_dut(); send_event(2,1); expect_request(2,1); accept_request();
        cancel=1; step(); cancel=0; ticks(2);
        tick_1ms=1; response(stop_tag,3); tick_1ms=0;
        check(idle && !fault && !stop_valid,"stop success wins boundary");

        scenario("full FIFO pop and enqueue preserve every item");
        reset_dut(); send_event(2,1); expect_request(2,1); accept_request();
        send_event(2,2); send_event(2,3); send_event(2,4); send_event(2,5);
        response(req_tag,0);
        send_event(2,6);
        check(!overflow && !fault,"full simultaneous pop and push accepted");
        for(i=2;i<=6;i=i+1) begin
            expect_request(2,i[3:0]); accept_request(); finish_request();
        end
        check(idle && !fault,"wrapped FIFO remains ordered");

        scenario("overflow with active playback fails closed and stops");
        reset_dut(); send_event(2,1); expect_request(2,1); accept_request();
        for(i=2;i<=6;i=i+1) send_event(2,i[3:0]);
        check(overflow && fault && idle && stop_valid,"overflow refuses sequence loss");
        response(stop_tag,3); send_event(2,7); step();
        check(overflow && fault && !req_valid && !stop_valid,"overflow remains latched");

        scenario("overflow during cancellation keeps original stop deadline");
        reset_dut(); send_event(2,1); expect_request(2,1); accept_request();
        cancel=1; step(); cancel=0; ticks(2);
        for(i=2;i<=6;i=i+1) send_event(2,i[3:0]);
        check(overflow && fault && stop_valid,"stop still requested after queue overflow");
        ticks(1);
        check(fault && !stop_valid && idle,"overflow does not restart stop timer");

        scenario("overflow on waiting handshake suppresses acceptance");
        reset_dut(); send_event(2,1); expect_request(2,1);
        for(i=2;i<=5;i=i+1) send_event(2,i[3:0]);
        req_ready=1; event_valid=1; event_kind=2; event_item=6; #1;
        check(!req_valid,"overflow combinationally suppresses handshake"); step();
        req_ready=0; event_valid=0;
        check(fault && overflow && !stop_valid,"unaccepted overflow needs no stop");

        scenario("reset during playback and pending stop; no stale resurrection");
        reset_dut(); send_event(2,8); expect_request(2,8); accept_request(); reset_dut();
        send_event(2,9); expect_request(2,9); accept_request(); cancel=1; step();
        check(stop_valid,"stop active before reset"); reset_dut();
        response(16'hffff,0); step(); check(idle && !fault && !req_valid,"unsolicited post-reset response ignored");

        test_done=1;
        $display("SUMMARY audio scenarios=%0d checks=%0d errors=%0d",scenarios,checks,errors);
        #1; $finish;
    end
    initial begin
        #1000000;
        $display("WATCHDOG audio timeout"); errors=errors+1; test_done=1;
        $display("SUMMARY audio scenarios=%0d checks=%0d errors=%0d",scenarios,checks,errors);
        $finish;
    end
endmodule
