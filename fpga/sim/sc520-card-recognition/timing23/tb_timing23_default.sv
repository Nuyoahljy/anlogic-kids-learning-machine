`timescale 1ns/1ps
module tb_timing23_default;
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
    pixel22_audio #(.CLK_HZ(CLK_HZ),.TRACKS(560'd0),
        .MAP_VERIFIED(0),.STATUS_VERIFIED(0),.MODE_VERIFIED(0),
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
        $display("RESULT tb_timing23_default errors=%0d checks=%0d scenarios=%0d injected=%0d UARTchecks=%0d",errors,checks,scenarios,injected,peripheral.checks);
        $finish;
    endtask
    integer n,e,s,a,q,target;
    initial begin
        unused=$value$plusargs("INJECT_FAULT=%d",inject_fault);
        unused=$value$plusargs("ASSET_ROOT=%s",asset_root);
        $readmemh({asset_root,"/font-reference.mem"},reference_font);$readmemh({asset_root,"/audio-glyphs.mem"},audio_glyphs);
        repeat(8)@(negedge clk);rst_n=1;repeat(8)@(negedge clk);
        scenario("formal unconfigured default reaches current business and display");
        check(audio_fault && audio_idle && !initialized && audio_state==0,"default profile exposes unavailable service");
        audio_picture(0);if(inject_fault)finish_test();
        scenario("unconfigured exploration/replay preserves business and never transmits");
        key(1);arm();sample(1,1,1,0);check(display_item==1 && events==1,"business accepts real item with unavailable audio");
        key(2);check(events==2,"explicit replay still produces one event");
        key(3);check(requested && events==2,"explore display request remains separate");
        scenario("unconfigured quiz score/feedback progresses through fault-idle");
        key(1);check(mode==2 && target_item==1 && requested,"mode switch preserves selected display");
        arm();sample(1,1,1,0);check(score==1 && phase==2,"unconfigured audio cannot manufacture or suppress valid score");
        q=question_index;#(15000000);check(question_index==q+1 && score==1,"feedback timer proceeds without audio deadlock");
        key(4);check(mode==0 && score==0 && !requested && audio_fault && audio_reset,"K4 cancels context without enabling audio");
        #(100000000);
        check(uart_tx && peripheral.frames==0 && peripheral.plays==0 && !initialized,"default never sends startup or playback bytes despite business events");
        finish_test();
    end
    initial begin #(64'd1000000000);$fatal(1,"default watchdog");end
endmodule
