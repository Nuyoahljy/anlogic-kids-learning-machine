`timescale 1ns/1ps
module tb_timing23_business;
    localparam integer CLK_HZ=960000;
    localparam real CLK_NS=1000000000.0/CLK_HZ;
    function [559:0] test_map;
        reg [559:0] result;
        begin
            result=0;
            for(integer i=0;i<35;i++) result[i*16+:16]=16'h1201+i;
            test_map=result;
        end
    endfunction
    reg clk=0;always #(CLK_NS/2)clk=~clk;
    reg rst_n=0,tick_1ms=0;
    integer divider=0;
    always @(posedge clk) begin
        tick_1ms<=0;
        if(!rst_n) divider<=0;
        else if(divider==959) begin divider<=0;tick_1ms<=1;end
        else divider<=divider+1;
    end
    reg sample_valid=0,sample_healthy=1,revoke=0,det_present=0,det_stable=0,source_test=0;
    reg [3:0] det_item=0;
    reg key_mode_pulse=0,key_replay_pulse=0,key_skip_pulse=0,key_reset_pulse=0;
    wire [1:0] mode,phase;
    wire [3:0] score,question_index,target_item,display_item;
    wire quiz_active,answer_valid,answer_correct,display_source_test,armed;
    wire [2:0] feedback;
    wire audio_event_valid,audio_cancel,audio_idle,audio_fault;
    wire [2:0] audio_event_kind;
    wire [3:0] audio_event_item;
    wire uart_tx,uart_rx,busy_async,initialized,queue_overflow;wire [2:0] audio_state;
    reg [2:0] response_policy=0;
    reg hold_play=0,busy_mismatch=0;
    reg [31:0] duration_ms=40;
    reg video_frame_start=0,in_de=0,disabled_view=0;
    reg [10:0] pixel_x=0;reg [9:0] pixel_y=0;
    reg [31:0] sample_tag=0;reg bad_join_tag=0;
    wire [27:0] render_state;wire audio_reset;
    wire obs_event,obs_healthy,obs_present,obs_valid,obs_revoke,obs_conflict,timed_out;
    wire [3:0] obs_item;wire [31:0] obs_frame_id;wire obs_source_test;wire [7:0] obs_count;
    items14_system #(.TIMEOUT_MS(2000),.ABSENT_SAMPLES(2),.FEEDBACK_TICKS(10),.SCENE_UI(1),.RENDER_ENABLE(0)) business(
        .clk(clk),.rst_n(audio_reset),.tick_1ms(tick_1ms),.flush(1'b0),.block_revoke(revoke),.card_revoke(1'b0),
        .block_event(sample_valid),.block_healthy(sample_healthy),.block_present(det_present && det_item<10),
        .block_valid(det_stable && det_item<10),.block_item(det_item),.block_frame_id(sample_tag),.block_source_test(source_test),.block_count(8'd3),
        .card_event(sample_valid),.card_healthy(sample_healthy),.card_present(det_present && det_item>=10),
        .card_valid(det_stable && det_item>=10),.card_item(det_item),.card_frame_id(sample_tag+bad_join_tag),.card_source_test(source_test),.card_count(8'd3),
        .key_mode_pulse(key_mode_pulse),.key_replay_pulse(key_replay_pulse),.key_skip_pulse(key_skip_pulse),.key_reset_pulse(key_reset_pulse),
        .audio_idle(audio_idle),.audio_fault(audio_fault),.video_frame_start(video_frame_start),.pixel_x(pixel_x),.pixel_y(pixel_y),
        .detectors_flush(),.obs_event(obs_event),.obs_healthy(obs_healthy),.obs_present(obs_present),.obs_valid(obs_valid),.obs_item(obs_item),
        .obs_frame_id(obs_frame_id),.obs_source_test(obs_source_test),.obs_count(obs_count),.obs_revoke(obs_revoke),.obs_conflict(obs_conflict),.timed_out(timed_out),
        .mode(mode),.phase(phase),.score(score),.question_index(question_index),.target_item(target_item),.display_item(display_item),
        .quiz_active(quiz_active),.answer_valid(answer_valid),.answer_correct(answer_correct),.display_source_test(display_source_test),.armed(armed),.feedback(feedback),
        .audio_event_valid(audio_event_valid),.audio_event_kind(audio_event_kind),.audio_event_item(audio_event_item),.audio_cancel(audio_cancel),
        .osd_active(),.osd_rgb(),.render_state(render_state));
    pixel22_audio #(.CLK_HZ(CLK_HZ),.TRACKS(test_map()),
        .MAP_VERIFIED(1),.STATUS_VERIFIED(1),.MODE_VERIFIED(1),
        .BOOT_TICKS(80),.INIT_TICKS(200),.QUERY_TICKS(2),.RESPONSE_TICKS(30),
        .QUIET_TICKS(2),.BUSY_FILTER_TICKS(1),.START_TICKS(140),.PLAY_TICKS(200),.STOP_TICKS(140),
        .DEPTH(8)) dut(.reset_n(rst_n),.reset_released(audio_reset),.*);
    wire disabled_tx,disabled_fault,disabled_idle,disabled_init;wire [2:0] disabled_state;
    pixel22_audio #(.CLK_HZ(CLK_HZ)) disabled(
        .clk(clk),.reset_n(rst_n),.reset_released(),.audio_state(disabled_state),.tick_1ms(tick_1ms),
        .audio_event_valid(audio_event_valid),.audio_event_kind(audio_event_kind),
        .audio_event_item(audio_event_item),.audio_cancel(audio_cancel),
        .uart_rx(uart_rx),.busy_async(busy_async),.uart_tx(disabled_tx),
        .audio_idle(disabled_idle),.audio_fault(disabled_fault),.initialized(disabled_init),.queue_overflow());
    dfr0534_uart_model peripheral(.clk(clk),.tx(uart_tx),.rx(uart_rx),.busy(busy_async),.*);
    integer checks=0,scenarios=0,events=0,ends=0,stopped=0,accepted=0,answers=0;
    reg [15:0] current_tag;
    reg mutate=0,injecting_wrong_tag=0;
    integer errors=0,injected=0,inject_fault=0,unused;reg test_done=0;
    task automatic check(input bit ok,input string message);
        checks++;
        if(!ok) begin errors++;if(errors<20)$display("FAIL business %s time=%0t",message,$time);if(errors>20)$fatal(1,"too many errors");end
    endtask
    task automatic scenario(input string label);
        scenarios++;$display("SCENARIO %0d %s",scenarios,label);
    endtask
    always @(posedge clk) if(rst_n) begin
        if(audio_event_valid)events++;
        if(answer_valid)answers++;
        if(dut.bridge.req_valid && dut.bridge.req_ready) begin accepted++;current_tag=dut.bridge.req_tag;end
        if(dut.bridge.rsp_valid && !injecting_wrong_tag) begin
            check(dut.bridge.rsp_tag==current_tag,"response tag belongs to accepted transaction");
            check(dut.bridge.rsp_code!=2,"TX does not invent ACK");
            if(dut.bridge.rsp_code==0)ends++;
            if(dut.bridge.rsp_code==3)stopped++;
        end
        if(tick_1ms) check(disabled_tx && disabled_fault && disabled_idle && !disabled_init,
            "hardware defaults are disabled and visibly unavailable");
    end
    task automatic key(input integer index);
        @(negedge clk);
        case(index) 1:key_mode_pulse=1;2:key_replay_pulse=1;3:key_skip_pulse=1;4:key_reset_pulse=1;endcase
        @(negedge clk);key_mode_pulse=0;key_replay_pulse=0;key_skip_pulse=0;key_reset_pulse=0;
        repeat(5)@(negedge clk);
    endtask
    task automatic sample(input integer item,input bit present,input bit stable,input bit test_source);
        @(negedge clk);sample_tag++;sample_valid=1;det_item=item;det_present=present;det_stable=stable;source_test=test_source;
        @(negedge clk);sample_valid=0;repeat(8)@(negedge clk);
    endtask
    task automatic arm;
        sample(0,0,0,0);sample(0,0,0,0);check(armed,"healthy absence arms once");
    endtask
    task automatic wait_idle;
        do begin wait(audio_idle);repeat(12)@(negedge clk);end while(!audio_idle);
        check(!audio_fault,"normal transaction completed without fault");
    endtask
    task automatic reset_fpga;
        @(negedge clk);rst_n=0;repeat(8)@(negedge clk);rst_n=1;
        response_policy=0;busy_mismatch=0;hold_play=0;
        wait(initialized);wait_idle();
    endtask
    wire requested,next_request,out_de;wire [23:0] out_rgb;
    pixel17_display_request selector(.clk(clk),.rst_n(audio_reset),.business_mode(mode),
        .key_mode_pulse(key_mode_pulse),.key_skip_pulse(key_skip_pulse),.key_reset_pulse(key_reset_pulse),.requested(requested),.next_request(next_request));
    pixel23_compositor renderer(.clk(clk),.rst_n(audio_reset),.in_frame_start(video_frame_start),.in_de(in_de),.in_hsync(1'b0),.in_vsync(1'b0),
        .mode_request(next_request),.in_x(pixel_x),.in_y(pixel_y),.in_rgb(24'h123456),.business_state(render_state),.audio_state(disabled_view ? disabled_state:audio_state),
        .color_packet(800'd0),.color_fresh(1'b0),.color_age(8'd0),.diagnostic(256'd0),.i2c_diagnostic(32'd0),.business_flags(8'd0),
        .out_frame_start(),.out_de(out_de),.out_hsync(),.out_vsync(),.out_mode(),.out_x(),.out_y(),.out_rgb(out_rgb),
        .out_color_id(),.out_panel_active(),.out_diag_active(),.out_logo_active());
    reg [15:0] reference_font[0:4095];reg [7:0] audio_glyphs[0:159];string asset_root;
    reg compare_pixel=0;reg [23:0] expected_pixel=0,expected_pipe[0:5];reg compare_pipe[0:5];integer valid_cycles=0;
    always @(posedge clk) begin
        for(integer i=5;i>0;i--)begin expected_pipe[i]=expected_pipe[i-1];compare_pipe[i]=compare_pipe[i-1];end
        expected_pipe[0]=expected_pixel;compare_pipe[0]=compare_pixel;valid_cycles++;
        #2;
        if(audio_reset && valid_cycles>6 && compare_pipe[5])begin
            if(inject_fault && !injected)begin force renderer.logo.out_rgb=24'h010203;injected=1;#1;end
            check(out_rgb===expected_pipe[5],"real audio status renders the independently expected bitmap through six stages");
            if(injected)release renderer.logo.out_rgb;
        end
    end
    task automatic audio_picture(input integer expected_state);
        integer xx,yy,code;reg [23:0] ink;
        check((disabled_view ? disabled_state:audio_state)==expected_state,"actual audio state before frame snapshot");
        @(negedge clk);video_frame_start=1;@(negedge clk);video_frame_start=0;
        ink=expected_state==4 ? 24'hffe3a3:expected_state==2 ? 24'h9ef0cc:24'hf5f7fa;
        for(yy=76;yy<108;yy++)for(xx=48;xx<48+32*8;xx++)begin
            @(negedge clk);pixel_x=xx;pixel_y=yy;in_de=1;compare_pixel=1;
            code=audio_glyphs[expected_state*32+(xx-48)/32];
            expected_pixel=reference_font[code*16+(yy-76)/2][15-((xx-48)%32)/2] ? ink:24'h18242c;
        end
        @(negedge clk);in_de=0;compare_pixel=0;repeat(8)@(negedge clk);
        check(renderer.frame_state[30:28]==expected_state,"one audio/business frame snapshot remains stable while UART advances");
    endtask
    task automatic finish_test;
        test_done=1;
        $display("RESULT tb_timing23_business errors=%0d checks=%0d scenarios=%0d injected=%0d UARTchecks=%0d",errors,checks,scenarios,injected,peripheral.checks);
        $finish;
    endtask
    integer n,e,s,a,q,target;
    initial begin
        unused=$value$plusargs("INJECT_FAULT=%d",inject_fault);
        unused=$value$plusargs("ASSET_ROOT=%s",asset_root);
        $readmemh({asset_root,"/font-reference.mem"},reference_font);$readmemh({asset_root,"/audio-glyphs.mem"},audio_glyphs);
        repeat(8)@(negedge clk);rst_n=1;repeat(8)@(negedge clk);
        scenario("default disabled and initializing state share the actual current renderer");
        disabled_view=1;audio_picture(0);disabled_view=0;audio_picture(1);
        if(inject_fault)finish_test();
        scenario("pre-init event queue + real explore dedup");
        key(1);arm();sample(1,1,1,0);
        n=events;repeat(8)sample(1,1,1,0);
        check(events==n,"held object cannot duplicate announcement");
        #(50000000);check(peripheral.plays==0 && !initialized && !audio_fault,"queued throughout startup");
        wait(peripheral.plays==1);audio_picture(3);wait_idle();audio_picture(2);
        check(peripheral.tracks[0]==16'h1201,"object1 maps to its own synthetic track");
        check(peripheral.last_mode==2 && peripheral.last_volume==8,"startup configuration bytes");

        scenario("explore K3 display changes have no audio event or cancellation");
        n=events;s=peripheral.stops;key(3);check(requested && mode==1 && events==n && peripheral.stops==s,"K3 only selects processing");
        key(3);check(!requested && events==n,"K3 returns original without speech");
        scenario("explicit replay uses07 and remains intentionally repeatable");
        n=peripheral.plays;key(2);key(2);wait(peripheral.plays==n+2);wait_idle();
        check(peripheral.tracks[n]==16'h1201 && peripheral.tracks[n+1]==16'h1201,"two explicit replays retained");

        scenario("test source and revoked recognition cannot auto announce");
        n=events;sample(0,0,0,1);sample(10,1,1,1);check(events==n && !armed,"test source does not arm/score");
        @(negedge clk);revoke=1;@(negedge clk);revoke=0;repeat(8)@(negedge clk);
        check(!armed && display_item==0,"revoke clears held recognition");

        scenario("quiz question and early correct feedback obey audio drain");
        key(1);check(mode==2 && target_item==1,"first real question target1");
        wait(peripheral.plays==n+1); // n is events==plays at this point
        arm();sample(1,1,1,0);check(score==1 && phase==2,"correct answer score once");
        q=question_index;#(15000000);check(question_index==q,"feedback waits for queued audio");
        wait(question_index==2);check(target_item==10,"sole real question-bank order");
        wait_idle();check(peripheral.tracks[peripheral.plays-2]==16'h121d,"correct feedback slot28");

        scenario("wrong answer retries current target without score");
        arm();sample(2,1,1,0);wait(phase==1);wait_idle();check(score==1 && target_item==10,"first wrong retains question");
        check(peripheral.tracks[peripheral.plays-1]==16'h121e,"wrong feedback slot29");

        scenario("skip cancels playback then emits new target");
        hold_play=1;key(2);n=peripheral.plays;wait(peripheral.plays>n);s=stopped;e=ends;
        wait(peripheral.playing_queries>0);key(3);wait(stopped>s);hold_play=0;
        wait(question_index==3);wait_idle();check(target_item==2 && ends>e,"new question follows confirmed STOP");

        scenario("K4 cancels old context and queues reset prompt");
        hold_play=1;key(2);n=peripheral.plays;wait(peripheral.plays>n);s=stopped;
        key(4);wait(stopped>s);hold_play=0;wait_idle();
        check(mode==0 && score==0 && peripheral.tracks[peripheral.plays-1]==16'h1222,"reset uses logical206 slot33");

        scenario("ten skipped questions reach completion slot34");
        key(1);key(1);
        for(integer i=1;i<=10;i++) begin wait_idle();key(3);end
        wait_idle();check(phase==3 && peripheral.tracks[peripheral.plays-1]==16'h1223,"round finished logical207");

        scenario("checksum fault cannot masquerade as curve end; K4 not recovery");
        key(4);wait_idle();key(1);arm();hold_play=1;sample(14,1,1,0);
        n=peripheral.plays;wait(peripheral.plays>n);response_policy=2;e=ends;
        wait(audio_fault);check(ends==e,"corrupt reply emits no end");audio_picture(4);
        key(4);#(20000000);check(audio_fault,"business reset cannot clear transport uncertainty");
        response_policy=0;reset_fpga();check(!audio_fault,"hardware reset + startup query recovers");

        scenario("late reply stays quarantined until reset");
        key(1);arm();hold_play=1;sample(7,1,1,0);n=peripheral.plays;wait(peripheral.plays>n);
        response_policy=3;e=ends;wait(audio_fault);#(85000000);
        check(audio_fault && ends==e,"late status never completes failed transaction");
        reset_fpga();

        scenario("BUSY/status mismatch and missing response are bounded faults");
        key(1);arm();hold_play=1;busy_mismatch=1;sample(4,1,1,0);e=ends;
        wait(audio_fault);check(ends==e,"status01 without BUSY cannot start/end");reset_fpga();
        key(1);arm();sample(5,1,1,0);n=peripheral.plays;wait(peripheral.plays>n);response_policy=1;e=ends;
        wait(audio_fault);check(ends==e,"no reply is uncertain, not code0 or retry");reset_fpga();

        scenario("warm reset stops a still-playing physical module");
        key(1);arm();hold_play=1;sample(6,1,1,0);n=peripheral.plays;wait(peripheral.plays>n);
        s=peripheral.stops;reset_fpga();check(peripheral.stops>s && !busy_async,"startup reclaims physical module");
        check(!queue_overflow && accepted>20 && ends>15 && stopped>=2,"coverage counters");
        scenario("wrong join tags revoke recognition and cannot score");
        key(1);arm();a=answers;e=events;bad_join_tag=1;sample(3,1,1,0);bad_join_tag=0;
        check(!obs_valid && !armed && answers==a && events==e,"mismatched capture tags cannot speak or score");
        reset_fpga();
        scenario("wrong response tag cannot complete the current request");
        key(1);arm();hold_play=1;sample(1,1,1,0);wait(dut.bridge.queue.state==2);e=ends;
        @(negedge clk);injecting_wrong_tag=1;force dut.bridge.queue.rsp_valid=1;force dut.bridge.queue.rsp_tag=16'h7fff;force dut.bridge.queue.rsp_code=0;
        @(negedge clk);release dut.bridge.queue.rsp_valid;release dut.bridge.queue.rsp_tag;release dut.bridge.queue.rsp_code;injecting_wrong_tag=0;
        check(dut.bridge.queue.state==2,"wrong tag ignored by active queue");hold_play=0;wait_idle();
        scenario("full queue is a sticky fault, K4 leaves player reset released");
        arm();hold_play=1;sample(1,1,1,0);wait(dut.bridge.queue.state==2);
        repeat(12)key(2);wait(queue_overflow);check(audio_fault && audio_idle,"overflow fault permits business progress");
        key(4);check(audio_reset && audio_fault && mode==0 && score==0,"K4 cancels but cannot reset fault epoch");#(250000000);reset_fpga();
        scenario("initialization silence is bounded and visibly faults");
        @(negedge clk);rst_n=0;repeat(8)@(negedge clk);response_policy=1;rst_n=1;wait(audio_fault);
        check(!initialized && audio_idle,"init failure does not deadlock business");audio_picture(4);key(1);check(mode==1,"mode key works on failed audio");reset_fpga();
        scenario("capture stopped timeout revokes recognition without false answer");
        key(1);arm();sample(8,1,1,0);a=answers;wait(timed_out);repeat(12)@(negedge clk);
        check(!armed && display_item==0 && answers==a,"capture timeout removes current recognition");
        $display("PASS tb_timing23_business checks=%0d scenarios=%0d events=%0d accepted=%0d ends=%0d stopped=%0d UARTchecks=%0d",checks,scenarios,events,accepted,ends,stopped,peripheral.checks);
        finish_test();
    end
    initial begin #(64'd20000000000);$fatal(1,"business watchdog");end
endmodule
