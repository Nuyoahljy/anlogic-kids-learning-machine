`timescale 1ns/1fs
module tb_quiz_runtime;
    reg clk=0;
    // Nominal board pixel clock. Checks use exact cycle counts, not rounded time.
    always #(1000000000.0/75000000.0/2.0) clk=~clk;
    reg rst_tick=0, rst_player=0;
    wire default_tick, fast_tick, boot_mode;
    quiz_millisecond_tick default_timer(.clk(clk),.rst_n(rst_tick),.tick_1ms(default_tick));
    quiz_millisecond_tick #(.CLOCK_HZ(1000)) fast_timer(.clk(clk),.rst_n(rst_tick),.tick_1ms(fast_tick));
    quiz_boot_controls #(.CLOCK_HZ(1000)) boot(.clk(clk),.rst_n(rst_tick),.key_mode_pulse(boot_mode));

    reg player_tick=0, req_valid=0, stop_valid=0;
    reg [2:0] req_kind=0;
    reg [3:0] req_item=0;
    reg [15:0] req_tag=0,stop_tag=0;
    wire req_ready,device_busy,rsp_valid;
    wire [15:0] rsp_tag;
    wire [1:0] rsp_code;
    quiz_mock_player #(.PLAY_TICKS(4)) player(
        .clk(clk),.rst_n(rst_player),.tick_1ms(player_tick),
        .req_valid(req_valid),.req_kind(req_kind),.req_item(req_item),.req_tag(req_tag),
        .req_ready(req_ready),.device_busy(device_busy),
        .stop_valid(stop_valid),.stop_tag(stop_tag),
        .rsp_valid(rsp_valid),.rsp_tag(rsp_tag),.rsp_code(rsp_code));

    reg test_done=0;
    integer errors=0,checks=0,cases=0;
    integer cycle,default_pulses=0,boot_pulses=0;

    task automatic step;
        @(posedge clk); #0.001;
    endtask
    task automatic check(input bit good,input string text);
        checks=checks+1;
        if(!good)begin errors=errors+1; $display("CHECK_FAIL runtime t=%0t %s",$time,text);end
    endtask
    task automatic mark_case(input string text);
        cases=cases+1; $display("CASE runtime %0d %s",cases,text);
    endtask
    task automatic timer_epoch(input integer count);
        for(cycle=1;cycle<=count;cycle=cycle+1)begin
            step();
            check(default_tick === (cycle%75000==0),"default millisecond pulse every 75000 cycles");
            check(fast_tick===1'b1,"CLOCK_HZ=1000 gives enable every cycle");
            // Two reset synchronizer cycles plus one registered tick latency.
            check(boot_mode === (cycle==1003 || cycle==2003),"boot mode only at simulated seconds 1 and 2");
            if(default_tick)default_pulses=default_pulses+1;
            if(boot_mode)boot_pulses=boot_pulses+1;
        end
    endtask
    task automatic reset_player;
        rst_player=0; req_valid=0; stop_valid=0; player_tick=0;
        step();step();
        check(!device_busy && !rsp_valid && req_ready,"player reset clears transaction");
        rst_player=1;step();
        check(!device_busy && !rsp_valid && req_ready,"player idle after reset");
    endtask
    task automatic accept(input [15:0] tag);
        check(req_ready,"ready before request");
        req_valid=1;req_tag=tag;req_kind=2;req_item=3;step();req_valid=0;
        check(device_busy && !req_ready && !rsp_valid,"acceptance starts busy without same-cycle response");
    endtask
    task automatic expect_ack(input [15:0] tag);
        step();
        check(rsp_valid && rsp_code==2 && rsp_tag==tag && device_busy,"ACK distinct from track completion");
    endtask

    initial begin
        #0.001;
        mark_case("default 75MHz divider and accelerated boot sequence");
        repeat(3)step();
        check(!default_tick && !fast_tick && !boot_mode,"timers held clear in reset");
        rst_tick=1;
        if($test$plusargs("NEGATIVE")) force default_tick=1'b0;
        timer_epoch(75003);
        if($test$plusargs("NEGATIVE")) release default_tick;

        mark_case("reset discards partial millisecond; boot one-shots repeat only in new epoch");
        rst_tick=0; #0.001;
        check(!default_tick && !fast_tick && !boot_mode,"asynchronous timer reset clears outputs");
        repeat(3)step();rst_tick=1;
        timer_epoch(75000);
        // In negative mode the first pulse is physically suppressed and the
        // shared per-cycle checker above is the intended single failure.
        check(default_pulses==($test$plusargs("NEGATIVE") ? 1 : 2),"observed divider pulse count");
        check(boot_pulses==4,"two boot pulses in each reset epoch, no periodic repeats");

        mark_case("accept and ACK do not consume playback ticks; fourth later tick completes");
        reset_player();player_tick=1;accept(16'h1010);expect_ack(16'h1010);
        player_tick=0;step();check(!rsp_valid && device_busy,"no tick means no playback progress");
        player_tick=1;
        repeat(3)begin step();check(device_busy && !rsp_valid,"first three post-ACK ticks remain busy");end
        step();player_tick=0;
        check(!device_busy && req_ready && rsp_valid && rsp_code==0 && rsp_tag==16'h1010,"fourth post-ACK tick is tagged track end");
        step();check(!rsp_valid,"completion is a one-cycle response");

        mark_case("busy rejects overlapping request without replacing active tag");
        accept(16'h2020);expect_ack(16'h2020);
        req_valid=1;req_tag=16'h9999;req_kind=4;req_item=9;
        repeat(2)begin step();check(!req_ready && device_busy && !rsp_valid,"busy request cannot be accepted");end
        req_valid=0;player_tick=1;repeat(4)step();player_tick=0;
        check(rsp_valid && rsp_code==0 && rsp_tag==16'h2020,"overlapping request did not corrupt completion tag");
        step();

        mark_case("stop beats pending ACK, and held stop is acknowledged once");
        accept(16'h3030);stop_valid=1;stop_tag=16'h3030;player_tick=1;step();
        check(rsp_valid && rsp_code==3 && rsp_tag==16'h3030 && !device_busy && !req_ready,"stop replaces pending ACK with cancellation");
        repeat(5)begin step();check(!rsp_valid && !device_busy && !req_ready,"held stop cannot acknowledge repeatedly or restart");end
        stop_valid=0;player_tick=0;step();
        check(req_ready && !rsp_valid,"release stop returns ready without stale response");

        mark_case("stop beats final playback tick");
        accept(16'h4040);expect_ack(16'h4040);player_tick=1;repeat(3)step();
        stop_valid=1;stop_tag=16'h4040;step();player_tick=0;
        check(rsp_valid && rsp_code==3 && rsp_tag==16'h4040 && !device_busy,"cancel wins over simultaneous end-of-track");
        stop_valid=0;step();check(!rsp_valid && req_ready,"canceled track never emits delayed done");

        mark_case("idle stop beats new request; idempotent stop carries requested tag");
        req_valid=1;req_tag=16'h5050;stop_valid=1;stop_tag=16'h6060;#0.001;
        check(!req_ready,"stop suppresses same-cycle request handshake");step();req_valid=0;
        check(rsp_valid && rsp_code==3 && rsp_tag==16'h6060 && !device_busy,"idle stop acknowledges without accepting request");
        stop_valid=0;step();check(req_ready && !rsp_valid,"idle cancellation drains cleanly");

        mark_case("reset cancels both pending ACK and playback");
        accept(16'h7070);reset_player();
        repeat(3)begin step();check(!rsp_valid && !device_busy,"no pending ACK after reset");end
        accept(16'h8080);expect_ack(16'h8080);player_tick=1;step();reset_player();
        player_tick=1;repeat(6)begin step();check(!rsp_valid && !device_busy,"no old track completion after reset");end
        player_tick=0;

        test_done=1;
        $display("SUMMARY runtime cases=%0d checks=%0d errors=%0d default_cycles=150003 boot_pulses=%0d test_done=%0d",cases,checks,errors,boot_pulses,test_done);
        #1;$finish;
    end
    initial begin
        #4000000;
        if(!test_done)begin errors=errors+1;test_done=1;
            $display("CHECK_FAIL runtime watchdog");
            $display("SUMMARY runtime checks=%0d errors=%0d test_done=%0d",checks,errors,test_done);
            $finish;
        end
    end
endmodule
