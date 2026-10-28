`timescale 1ns/1ps
`include "recognition30_packet.vh"
// Actual pipeline and observer; all stimuli use public ports. No force/stubs.
// RGB/statistics are the ISP-side stimulus boundary, not a simulated sensor.
module tb_pipeline_calibration;
    // The real matcher scans 400*256 cells after scene normalization.
    localparam integer RETIRE_CYCLES=300000;
    reg capture_clk=0,display_clk=0,rst_n=0;
    always #4.83 capture_clk=~capture_clk;
    always #6.6665 display_clk=~display_clk;
    reg in_frame_start=0,in_source_test=0,in_valid=0,in_eol=0;
    reg [31:0] in_frame_id=0,in_done_id=0;
    reg [95:0] in_rgb96={4{24'ha0a0a0}};
    reg in_frame_done=0,in_frame_good=1,in_done_source_test=0,in_revoke=0;
    reg tick_1ms=0,flush=0,calibration_inhibit=0;
    reg key_mode_pulse=0,key_replay_pulse=0,key_skip_pulse=0,key_reset_pulse=0;
    reg audio_idle=1,audio_fault=0;
    reg [1:0] style_request=0,calibration_state=0,tf_state=0;
    reg video_frame_start=0,video_vsync=0,video_hsync=0,video_de=0;
    reg [10:0] pixel_x=0; reg [9:0] pixel_y=0; reg [23:0] video_rgb=0;
    wire calibration_flush,recognition_event,recognition_fresh,recognition_fault;
    wire [191:0] recognition_packet;
    wire obs_event,obs_healthy,obs_present,obs_valid,obs_revoke;
    wire [3:0] obs_item;
    pixel310_pipeline #(.FRAME_WIDTH(128),.FRAME_HEIGHT(128),
        .CARD_X(0),.CARD_Y(0),.CARD_SIZE(128),
        .SCENE_X(0),.SCENE_Y(0),.SCENE_WIDTH(128),.SCENE_HEIGHT(128),
        .SCENE_SAMPLE_STEP(4),.CONFIRM_FRAMES(1),.RENDER_ENABLE(0),.SHAPE_ENABLE(0)) dut(
        .rst_n(rst_n),.capture_clk(capture_clk),.display_clk(display_clk),
        .in_frame_start(in_frame_start),.in_frame_id(in_frame_id),.in_source_test(in_source_test),
        .in_valid(in_valid),.in_eol(in_eol),.in_rgb96(in_rgb96),
        .in_frame_done(in_frame_done),.in_frame_good(in_frame_good),.in_done_id(in_done_id),
        .in_done_source_test(in_done_source_test),.in_revoke(in_revoke),
        .tick_1ms(tick_1ms),.flush(flush),.calibration_inhibit(calibration_inhibit),
        .style_request(style_request),.calibration_state(calibration_state),.tf_state(tf_state),
        .key_mode_pulse(key_mode_pulse),.key_replay_pulse(key_replay_pulse),
        .key_skip_pulse(key_skip_pulse),.key_reset_pulse(key_reset_pulse),
        .audio_idle(audio_idle),.audio_fault(audio_fault),
        .video_frame_start(video_frame_start),.video_vsync(video_vsync),
        .video_hsync(video_hsync),.video_de(video_de),.pixel_x(pixel_x),.pixel_y(pixel_y),.video_rgb(video_rgb),
        .calibration_flush(calibration_flush),.recognition_event(recognition_event),
        .recognition_packet(recognition_packet),.recognition_fresh(recognition_fresh),.recognition_fault(recognition_fault),
        .obs_event(obs_event),.obs_healthy(obs_healthy),.obs_present(obs_present),
        .obs_valid(obs_valid),.obs_revoke(obs_revoke),.obs_item(obs_item));
    reg stats_event=0;
    wire cal_event,cal_good; wire [215:0] cal_means; wire [62:0] cal_high;
    pixel286_color_observer #(.FRAME_WIDTH(128),.FRAME_HEIGHT(128),
        .CLASS_X(0),.CLASS_Y(0),.CLASS_W(128),.CLASS_H(128),
        .CENTER_X(64),.CENTER_Y(64),.PAPER_X(16),.PAPER_Y(16),
        .GRID_X0(16),.GRID_X1(64),.GRID_X2(112),.GRID_Y0(16),.GRID_Y1(64),.GRID_Y2(112)) grid(
        .clk(capture_clk),.rst_n(rst_n),.diagnostics_rst_n(rst_n),.join_rst_n(rst_n),
        .flush(calibration_flush),.frame_start(in_frame_start),.frame_id(in_frame_id),
        .valid(in_valid),.eol(in_eol),.pre_wb(in_rgb96),.post_wb(in_rgb96),.post_tone(in_rgb96),
        .pixel_id(in_frame_id),.gain_r(9'd256),.gain_b(9'd256),
        .stats_event(stats_event),.stats_good(1'b1),.stats_id(in_frame_id),.neutral_count(21'd16384),
        .spatial_status(6'd0),.frame_done(in_frame_done),.frame_good(in_frame_good),.done_id(in_done_id),
        .analysis_event(1'b0),.analysis_good(1'b0),.analysis_id(32'd0),.analysis_data(149'd0),
        .cal_event(cal_event),.cal_good(cal_good),.cal_means(cal_means),.cal_high(cal_high),.out_event(),.out_packet());
    integer checks=0,frames=0,good_cal_events=0,normal_packets=0,scene_starts=0,test_done=0;
    integer blocked_cycles=0,reverse_events=0,natural_revokes=0;
    integer capture_cycles=0,matcher_events=0,arbitration_events=0,confirmation_events=0;
    integer public_revokes=0,busy_start_cycle=0,expected_normal_id=0,aborted_id=0;
    integer last_normal_id=0,inflight_busy_cases=0,normal_busy_cases=0,max_revoke_cycles=0;
    reg assert_block=0,monitor=0;
    reg awaiting_revoke=0;
    task ck(input bit ok,input string message);
        checks++;
        if(!ok)begin
            $display("FAIL R4C %s frame=%0d checks=%0d cal=%0d packets=%0d",message,in_frame_id,checks,good_cal_events,normal_packets);
            $display("STATE drop=%b source=%b transport=%b reverse_events=%0d source_revokes=%0d grid_active=%b groups=%0d lines=%0d reject=%h",dut.drop_capture,dut.source_revoke,dut.transport_flush,reverse_events,natural_revokes,grid.diagnostics.active,grid.diagnostics.groups_seen,grid.diagnostics.lines_seen,grid.diagnostics.out_reject_reason);
            $display("RETIRE scene=%0d matcher=%0d arb=%0d filter=%0d matcher_state=%0d saved_id=%0d public_revokes=%0d",scene_starts,matcher_events,arbitration_events,confirmation_events,dut.matcher.state,dut.matcher.saved_id,public_revokes);
            $fatal(1,"R4C pipeline regression");
        end
    endtask
    always @(negedge capture_clk)if(monitor)begin
        capture_cycles++;
        if(cal_event && cal_good)begin
            good_cal_events++;
            ck(cal_means==={27{8'd160}},"nine real windows retain their channel means");
            ck(cal_high===63'd0,"nine windows contain no clipped pixels");
        end
        if(dut.scene.start_ok && !dut.detector_flush &&
           !dut.scene.raster_fault && !dut.scene.engine_fault)scene_starts++;
        if(dut.reverse_event)reverse_events++;
        if(dut.source_revoke)natural_revokes++;
        if(dut.match_event)begin
            matcher_events++;
            ck(dut.match_id!=aborted_id,"an inhibited in-flight scan never emits its old result");
            ck(dut.match_good && !dut.match_present && !dut.match_valid &&
               dut.match_foreground==0,"real blank matcher result is healthy and absent");
        end
        if(dut.ae)arbitration_events++;
        if(dut.fe)confirmation_events++;
        if(awaiting_revoke)
            ck(capture_cycles-busy_start_cycle<=128,"busy revokes the public observation within the bounded CDC latency");
        if(assert_block)begin
            blocked_cycles++;
            ck(dut.detector_flush===1'b1,"recognition stays flushed through busy and its partial release frame");
            ck(!dut.sc_start && !dut.match_event && !dut.ae && !dut.fe,"no partial-frame recognition result");
        end
    end
    always @(negedge display_clk)if(monitor)begin
        if(obs_revoke)begin
            public_revokes++;
            ck(!obs_healthy && obs_present && !obs_valid && obs_item==0,
               "public revoke removes recognition eligibility");
            if(awaiting_revoke)begin
                awaiting_revoke=0;
                if(capture_cycles-busy_start_cycle>max_revoke_cycles)
                    max_revoke_cycles=capture_cycles-busy_start_cycle;
                ck(capture_cycles-busy_start_cycle<=128,"busy public revoke is prompt");
            end
        end
        if(recognition_event && !recognition_packet[`R30_REVOKE])begin
            normal_packets++;
            last_normal_id=recognition_packet[`R30_ID];
            ck(!assert_block,"no normal result crosses CDC during recognition quarantine");
            ck(last_normal_id==expected_normal_id && last_normal_id!=aborted_id,
               "only the expected complete frame reaches the public packet");
            ck(recognition_fresh && !recognition_fault &&
               recognition_packet[`R30_ID_KNOWN] && recognition_packet[`R30_HEALTHY],
               "real blank publication is fresh, healthy and tagged");
            ck(!recognition_packet[`R30_PRESENT] && !recognition_packet[`R30_VALID] &&
               recognition_packet[`R30_ITEM]==0 && recognition_packet[`R30_RAW_ITEM]==0 &&
               recognition_packet[`R30_COUNT]==0 && recognition_packet[`R30_SCENE_COUNT]==0 &&
               recognition_packet[`R30_GLYPH_COUNT]==0 && recognition_packet[`R30_FOREGROUND]==0,
               "a uniform blank stays absent rather than becoming an unknown foreground");
            ck(obs_event && obs_healthy && !obs_present && !obs_valid && obs_item==0,
               "business observation preserves real blank semantics");
        end
    end
    task idle(input integer n); repeat(n)@(negedge capture_clk); endtask
    task start_busy;
        begin
            busy_start_cycle=capture_cycles;
            awaiting_revoke=1;calibration_inhibit=1;assert_block=1;
        end
    endtask
    task retire(input integer previous_packets,input integer expected_id);
        integer cycles;
        begin
            cycles=0;
            while(normal_packets==previous_packets && cycles<RETIRE_CYCLES)begin idle(1);cycles++;end
            ck(normal_packets==previous_packets+1,"next complete frame reaches real recognition CDC/system exactly once");
            ck(last_normal_id==expected_id,"retired public result has the complete-frame tag");
            ck(!dut.source_fault,"ordinary calibration recovery has no transport fault");
            $display("RETIRE R4C frame=%0d waited=%0d matcher=%0d arb=%0d filter=%0d",expected_id,cycles,matcher_events,arbitration_events,confirmation_events);
        end
    endtask
    // action 1 releases busy halfway through real pixels; 2 gives a real
    // source revoke; 3 requests real reverse transport flush from display;
    // 4 inhibits an already published result; 5 inhibits a real active scan.
    task frame(input integer action);
        integer y,x;
        @(negedge capture_clk); in_frame_id++;in_done_id=in_frame_id;in_frame_start=1;
        @(negedge capture_clk); in_frame_start=0;
        idle(4);
        for(y=0;y<128;y++)begin
            for(x=0;x<32;x++)begin
                @(negedge capture_clk);in_valid=1;in_eol=(x==31);
                if(y==64 && x==0)begin
                    if(action==1)calibration_inhibit=0;
                    if(action==2)in_revoke=1;
                    if(action==3)flush=1;
                    if(action==4)begin
                        ck(recognition_fresh && !recognition_fault &&
                           !recognition_packet[`R30_REVOKE],"busy starts from an already normal public result");
                        normal_busy_cases++;start_busy();
                    end
                    if(action==5)begin
                        ck(dut.matcher.state==2 && dut.matcher.saved_good &&
                           dut.matcher.saved_id==in_frame_id-1 && dut.matcher_busy,
                           "busy starts while the previous complete frame is really scanning");
                        aborted_id=dut.matcher.saved_id;inflight_busy_cases++;start_busy();
                    end
                end
                if(y==64 && x==12)begin in_revoke=0;flush=0;end
            end
            @(negedge capture_clk);in_valid=0;in_eol=0;
            idle(4);
        end
        idle(8);stats_event=1;
        @(negedge capture_clk);stats_event=0;
        idle(4);in_frame_done=1;
        @(negedge capture_clk);in_frame_done=0;
        idle(32);frames++;
    endtask
    integer before_cal,before_packets,before_starts,before_reverse,before_revoke,waited;
    integer before_public_revoke,before_match_events,scan_id;
    initial begin
        idle(8);rst_n=1;idle(50);monitor=1;
        calibration_inhibit=1;assert_block=1;idle(4);
        // The first busy transition sends an actual revoke through the public
        // mailbox. Let that bounded reverse-clear transaction settle first.
        frame(0);idle(100);before_cal=good_cal_events;frame(0);
        ck(good_cal_events==before_cal+1,"busy must permit a complete trustworthy calibration frame");
        frame(0);ck(good_cal_events==before_cal+2,"holding busy permits subsequent independent statistics");
        before_packets=normal_packets;before_starts=scene_starts;
        frame(1);idle(100);
        ck(good_cal_events==before_cal+3,"midframe busy release preserves complete calibration statistics");
        ck(normal_packets==before_packets && scene_starts==before_starts,"partial release frame never enters recognition");
        assert_block=0;expected_normal_id=in_frame_id+1;frame(0);
        retire(before_packets,expected_normal_id);
        ck(scene_starts==before_starts+1,"next complete frame enters real scene processing");
        ck(normal_packets>before_packets,"next complete frame reaches real recognition CDC/system");
        ck(!dut.source_fault,"ordinary calibration recovery has no transport fault");

        // Revoke a real already-published observation from the middle of a
        // new raster, then preserve statistics while that busy level is held.
        before_packets=normal_packets;before_public_revoke=public_revokes;frame(4);
        ck(!awaiting_revoke && public_revokes>before_public_revoke,"already-normal busy produced a real public revoke");
        ck(normal_packets==before_packets,"already-normal busy cannot publish its partial frame");
        ck(recognition_packet[`R30_REVOKE] && !obs_valid && obs_item==0,"old normal observation remains revoked");
        before_cal=good_cal_events;before_starts=scene_starts;frame(0);
        ck(good_cal_events==before_cal+1,"held busy after a normal result preserves statistics");
        frame(1);idle(100);
        ck(good_cal_events==before_cal+2,"already-normal midframe busy release preserves statistics");
        ck(normal_packets==before_packets && scene_starts==before_starts,"already-normal partial release cannot enter recognition");
        assert_block=0;expected_normal_id=in_frame_id+1;frame(0);retire(before_packets,expected_normal_id);
        ck(scene_starts==before_starts+1,"already-normal busy resumes only at the next complete frame");

        // Let a complete raster genuinely enter the full 256-variant scan.
        // The next real raster inhibits it halfway through; no internal drive
        // or replacement detector participates in this cancellation witness.
        before_packets=normal_packets;scan_id=in_frame_id+1;expected_normal_id=scan_id;frame(0);
        waited=0;
        while(!(dut.matcher.state==2 && dut.matcher.saved_id==scan_id) && waited<RETIRE_CYCLES)begin idle(1);waited++;end
        ck(dut.matcher.state==2 && dut.matcher.saved_good && dut.matcher.saved_id==scan_id,
           "complete input reaches the real matcher before in-flight busy");
        ck(normal_packets==before_packets,"in-flight result has not published before busy");
        before_match_events=matcher_events;before_public_revoke=public_revokes;frame(5);
        ck(!awaiting_revoke && public_revokes>before_public_revoke,"in-flight busy produced a real public revoke");
        idle(RETIRE_CYCLES);
        ck(matcher_events==before_match_events && normal_packets==before_packets,
           "canceled complete scan cannot leak a late matcher or public result");
        before_cal=good_cal_events;before_starts=scene_starts;frame(0);
        ck(good_cal_events==before_cal+1,"in-flight busy preserves subsequent complete calibration statistics");
        frame(1);idle(100);
        ck(good_cal_events==before_cal+2,"in-flight partial release preserves complete calibration statistics");
        ck(normal_packets==before_packets && scene_starts==before_starts,"in-flight partial release never enters recognition");
        assert_block=0;expected_normal_id=in_frame_id+1;frame(0);retire(before_packets,expected_normal_id);
        ck(scene_starts==before_starts+1,"in-flight busy resumes only at the next complete frame");

        before_cal=good_cal_events;before_revoke=natural_revokes;frame(2);idle(100);
        ck(natural_revokes>before_revoke,"public input revoke reaches the real source failure path");
        ck(good_cal_events==before_cal,"source-revoked frame is not accepted for calibration");
        ck(calibration_flush,"source fault waits for a clean frame");
        before_packets=normal_packets;expected_normal_id=in_frame_id+1;frame(0);idle(30000);
        ck(good_cal_events==before_cal+1,"clean frame reopens statistics after source fault");
        retire(before_packets,expected_normal_id);
        before_cal=good_cal_events;before_reverse=reverse_events;frame(3);idle(100);
        ck(reverse_events>before_reverse,"display flush crosses the actual reverse mailbox");
        ck(good_cal_events==before_cal,"transport-flushed frame is not accepted for calibration");
        ck(calibration_flush,"transport flush waits for a clean frame");
        before_packets=normal_packets;expected_normal_id=in_frame_id+1;frame(0);idle(30000);
        ck(good_cal_events==before_cal+1,"statistics recover after a transport flush");
        retire(before_packets,expected_normal_id);
        ck(normal_busy_cases==1 && inflight_busy_cases==1,"both real busy-entry states were exercised");
        test_done=1;
        $display("PASS R4C pipeline checks=%0d frames=%0d cal=%0d packets=%0d blocked_cycles=%0d reverse=%0d source_revokes=%0d matcher=%0d arb=%0d filter=%0d normal_busy=%0d inflight_busy=%0d public_revokes=%0d max_revoke_cycles=%0d",checks,frames,good_cal_events,normal_packets,blocked_cycles,reverse_events,natural_revokes,matcher_events,arbitration_events,confirmation_events,normal_busy_cases,inflight_busy_cases,public_revokes,max_revoke_cycles);
        $finish;
    end
    initial begin #30000000;$fatal(1,"R4C pipeline watchdog");end
endmodule
