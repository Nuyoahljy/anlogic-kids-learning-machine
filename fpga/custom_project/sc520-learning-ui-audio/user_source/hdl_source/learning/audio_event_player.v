// Local same-clock transaction adapter. No UART/electrical assumptions.
// rsp_error means definitely NOT started; an uncertain result must not use it.
// One active transaction and one latest-wins pending slot; event inputs are pulses.
module audio_event_player #(
    parameter integer READY_TIMEOUT_TICKS = 300,
    parameter integer PLAY_TIMEOUT_TICKS = 900,
    parameter integer MAX_RETRIES = 1
)(
    input wire clk, input wire rst_n, input wire flush, input wire tick,
    input wire [2:0] audio_event, input wire [3:0] audio_item_id,
    output wire cmd_valid, input wire cmd_ready,
    output wire [3:0] cmd_item, output wire [2:0] cmd_event,
    output wire [15:0] cmd_tag,
    input wire rsp_valid, input wire [15:0] rsp_tag, input wire rsp_error,
    input wire player_busy,
    output wire [1:0] status, output wire pending,
    output reg completed_pulse, output reg failed_pulse
);
    localparam [1:0] IDLE=2'd0, OFFER=2'd1, PLAYING=2'd2, FAULT=2'd3;
    localparam integer READY_LIMIT = (READY_TIMEOUT_TICKS < 1) ? 1 : READY_TIMEOUT_TICKS;
    localparam integer PLAY_LIMIT = (PLAY_TIMEOUT_TICKS < 1) ? 1 : PLAY_TIMEOUT_TICKS;
    function integer bits_for;
        input integer value;
        integer n;
        begin n=value-1; bits_for=0; while(n>0) begin bits_for=bits_for+1; n=n>>1; end
        if(bits_for<1) bits_for=1; end
    endfunction
    localparam integer TIMER_BITS=bits_for((READY_LIMIT>PLAY_LIMIT)?READY_LIMIT:PLAY_LIMIT);
    localparam integer RETRY_BITS=bits_for(MAX_RETRIES+1);
    reg [1:0] state, state_n;
    reg [3:0] active_item, active_item_n, pending_item, pending_item_n;
    reg [2:0] active_event, active_event_n, pending_event, pending_event_n;
    reg pending_v, pending_v_n;
    reg [15:0] active_tag, active_tag_n, next_tag, next_tag_n;
    reg [TIMER_BITS-1:0] timer_count, timer_count_n;
    reg [RETRY_BITS-1:0] retries, retries_n;
    reg complete_n, fail_n;
    assign status=state;
    assign pending=pending_v;
    assign cmd_valid=(state==OFFER) && !player_busy && !flush && rst_n;
    assign cmd_item=active_item;
    assign cmd_event=active_event;
    assign cmd_tag=active_tag;

    always @* begin
        state_n=state; active_item_n=active_item; active_event_n=active_event;
        pending_item_n=pending_item; pending_event_n=pending_event; pending_v_n=pending_v;
        active_tag_n=active_tag; next_tag_n=next_tag;
        timer_count_n=timer_count; retries_n=retries;
        complete_n=1'b0; fail_n=1'b0;
        // Capture before promoting pending so a same-edge duplicate is merged.
        if(state!=FAULT && (audio_event==3'd1 || audio_event==3'd5)
           && audio_item_id>=4'd1 && audio_item_id<=4'd9) begin
            if(audio_event==3'd1 &&
               (((state==OFFER || state==PLAYING) && active_item==audio_item_id)
                || (pending_v && pending_item==audio_item_id))) begin
                // Automatic duplicate: retain all queue metadata.
            end else if(pending_v && pending_item==audio_item_id) begin
                pending_event_n=audio_event;
            end else begin
                pending_v_n=1'b1; pending_item_n=audio_item_id; pending_event_n=audio_event;
            end
        end
        case(state)
            IDLE: begin
                timer_count_n=0; retries_n=0;
                if(pending_v_n) begin
                    active_item_n=pending_item_n; active_event_n=pending_event_n;
                    active_tag_n=next_tag; next_tag_n=next_tag+16'd1;
                    pending_v_n=1'b0; state_n=OFFER;
                end
            end
            OFFER: begin
                if(cmd_ready && !player_busy) begin
                    state_n=PLAYING; timer_count_n=0;
                end else if(tick) begin
                    if(timer_count>=READY_LIMIT-1) begin
                        state_n=FAULT; pending_v_n=1'b0; fail_n=1'b1; timer_count_n=0;
                    end else timer_count_n=timer_count+1'b1;
                end
            end
            PLAYING: begin
                // Only an accepted transaction's matching response is meaningful.
                if(rsp_valid && rsp_tag==active_tag) begin
                    timer_count_n=0;
                    if(!rsp_error) begin
                        complete_n=1'b1; state_n=IDLE;
                    end else if(retries<MAX_RETRIES) begin
                        retries_n=retries+1'b1; state_n=OFFER;
                        active_tag_n=next_tag; next_tag_n=next_tag+16'd1;
                    end else begin
                        fail_n=1'b1; state_n=FAULT; pending_v_n=1'b0;
                    end
                end else if(tick) begin
                    if(timer_count>=PLAY_LIMIT-1) begin
                        fail_n=1'b1; state_n=FAULT; pending_v_n=1'b0; timer_count_n=0;
                    end else timer_count_n=timer_count+1'b1;
                end
            end
            FAULT: begin pending_v_n=1'b0; timer_count_n=0; end
            default: begin state_n=FAULT; pending_v_n=1'b0; fail_n=1'b1; end
        endcase
        if(flush) begin
            state_n=IDLE; pending_v_n=1'b0; timer_count_n=0; retries_n=0;
            active_item_n=0; active_event_n=0; pending_item_n=0; pending_event_n=0;
            active_tag_n=next_tag; next_tag_n=next_tag+16'd1;
            complete_n=1'b0; fail_n=1'b0;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE; active_item<=0; active_event<=0; pending_item<=0; pending_event<=0;
            pending_v<=0; active_tag<=0; next_tag<=0; timer_count<=0; retries<=0;
            completed_pulse<=0; failed_pulse<=0;
        end else begin
            state<=state_n; active_item<=active_item_n; active_event<=active_event_n;
            pending_item<=pending_item_n; pending_event<=pending_event_n; pending_v<=pending_v_n;
            active_tag<=active_tag_n; next_tag<=next_tag_n; timer_count<=timer_count_n; retries<=retries_n;
            completed_pulse<=complete_n; failed_pulse<=fail_n;
        end
    end
endmodule
