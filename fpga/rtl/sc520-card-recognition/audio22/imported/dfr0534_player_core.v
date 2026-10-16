`timescale 1ns/1ps
// Tagged queue adapter. Profile defaults are placeholders, NOT hardware facts.
// No automatic recovery after uncertain execution: reset, startup stop and a
// fresh status exchange are required. The physical module need not reset with
// this FPGA. A timeout never means "definitely not executed".
module dfr0534_player_core #(
    parameter integer MAX_DATA=16,
    parameter integer MAP_VERIFIED=0, STATUS_VERIFIED=0, MODE_VERIFIED=0,
    parameter [7:0] STOPPED_STATUS=8'h00, PLAYING_STATUS=8'h01,
    parameter [7:0] SINGLE_STOP_MODE=8'h02,
    parameter integer VOLUME=20,
    parameter integer BOOT_TICKS=2000, INIT_TICKS=6000,
    parameter integer QUERY_TICKS=100, RESPONSE_TICKS=250,
    parameter integer QUIET_TICKS=50, BUSY_FILTER_TICKS=5,
    parameter integer START_TICKS=3000, PLAY_TICKS=20000, STOP_TICKS=1000
)(
    input wire clk, rst_n, tick_1ms, busy_async,
    input wire req_valid, input wire [2:0] req_kind,
    input wire [3:0] req_item, input wire [15:0] req_tag,
    output wire req_ready, device_busy,
    input wire stop_valid, input wire [15:0] stop_tag,
    output reg rsp_valid, output reg [15:0] rsp_tag,
    output reg [1:0] rsp_code,
    input wire map_hit, input wire [15:0] physical_track,
    output reg initialized, fault,
    output reg cmd_valid, output reg [7:0] cmd, cmd_len,
    output reg [MAX_DATA*8-1:0] cmd_data,
    input wire cmd_ready, tx_done, tx_error,
    input wire rx_valid, rx_error, rx_activity, rx_frame_start,
    input wire [7:0] rx_cmd, rx_len,
    input wire [MAX_DATA*8-1:0] rx_data,
    output reg flush_rx
);
    localparam integer ENABLED=MAP_VERIFIED && STATUS_VERIFIED && MODE_VERIFIED;
    localparam [3:0] S_BOOT=0, S_STOP=1, S_TX=2, S_QUIET=3,
        S_QUERY=4, S_REPLY=5, S_MODE=6, S_VOLUME=7, S_IDLE=8,
        S_PLAY=9, S_FAULT=10, S_EMERGENCY=11, S_DRAIN=12, S_REJECT=13;
    localparam [2:0] O_STOP=0, O_QUERY=1, O_MODE=2, O_VOLUME=3,
        O_PLAY=4, O_EMERGENCY=5;
    localparam [1:0] P_INIT=0, P_START=1, P_PLAY=2, P_STOP=3;
    reg [3:0] state;
    reg [2:0] sent_op;
    reg [1:0] phase;
    reg [15:0] active_tag, track;
    reg tag_valid, active, cancel_pending, stop_seen, frame_in_window;
    reg [31:0] state_ticks, operation_ticks, quiet_ticks;
    // Both flip-flops must be kept as a synchronizer when bound to real pins.
    (* async_reg = "true" *) reg busy_meta, busy_safe;
    reg [31:0] low_ticks, high_ticks;
    wire low_stable=!busy_safe && (low_ticks >= BUSY_FILTER_TICKS);
    wire high_stable=busy_safe && (high_ticks >= BUSY_FILTER_TICKS);
    wire stop_match=stop_valid && tag_valid && (stop_tag==active_tag) && !stop_seen;
    wire stopping=cancel_pending || stop_match;
    wire status_reply=rx_valid && !rx_error && frame_in_window && (rx_cmd==8'h01) && (rx_len==1);
    wire stopped_reply=status_reply && (rx_data[7:0]==STOPPED_STATUS) && low_stable;
    wire playing_reply=status_reply && (rx_data[7:0]==PLAYING_STATUS) && high_stable;
    wire progress_on_deadline=(state==S_REPLY) && !stopping &&
        (((phase==P_START) && playing_reply) ||
         (((phase==P_PLAY) || (phase==P_STOP)) && stopped_reply));
    assign req_ready=ENABLED && initialized && !fault && (state==S_IDLE) &&
                     !stop_valid && low_stable;
    assign device_busy=!ENABLED || !initialized || fault || (state!=S_IDLE) || !low_stable;

    always @* begin
        cmd_valid=0; cmd=0; cmd_len=0; cmd_data=0;
        if (ENABLED) begin
            case (state)
                S_STOP,S_EMERGENCY: begin cmd_valid=1; cmd=8'h04; end
                S_QUERY: begin cmd_valid=!stop_match; cmd=8'h01; end
                S_MODE: begin cmd_valid=1; cmd=8'h18; cmd_len=1; cmd_data[7:0]=SINGLE_STOP_MODE; end
                S_VOLUME: begin cmd_valid=1; cmd=8'h13; cmd_len=1; cmd_data[7:0]=VOLUME; end
                S_PLAY: begin
                    cmd_valid=!stopping; cmd=8'h07; cmd_len=2;
                    // Protocol takes track MSB first; payload lane zero is first.
                    cmd_data[7:0]=track[15:8]; cmd_data[15:8]=track[7:0];
                end
                default: begin end
            endcase
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy_meta<=0; busy_safe<=0; low_ticks<=0; high_ticks<=0;
        end else begin
            busy_meta<=busy_async; busy_safe<=busy_meta;
            // Revoke qualification immediately on a synchronized transition.
            if (busy_safe) low_ticks<=0;
            else if (tick_1ms && low_ticks < BUSY_FILTER_TICKS) low_ticks<=low_ticks+1'b1;
            if (!busy_safe) high_ticks<=0;
            else if (tick_1ms && high_ticks < BUSY_FILTER_TICKS) high_ticks<=high_ticks+1'b1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=S_BOOT; sent_op<=O_STOP; phase<=P_INIT;
            active_tag<=0; track<=0; tag_valid<=0; active<=0;
            cancel_pending<=0; stop_seen<=0; frame_in_window<=0;
            state_ticks<=0; operation_ticks<=0; quiet_ticks<=0;
            initialized<=0; fault<=0; rsp_valid<=0; rsp_tag<=0; rsp_code<=0;
            flush_rx<=1;
        end else begin
            rsp_valid<=0; flush_rx<=0;
            if (!stop_valid) stop_seen<=0;
            if (rx_activity || rx_frame_start || rx_valid || rx_error) quiet_ticks<=0;
            else if (tick_1ms && quiet_ticks < QUIET_TICKS) quiet_ticks<=quiet_ticks+1'b1;
            if (tick_1ms) begin
                if (state_ticks != 32'hffffffff) state_ticks<=state_ticks+1'b1;
                if (operation_ticks != 32'hffffffff) operation_ticks<=operation_ticks+1'b1;
            end
            // Only AA headers recognized after the query's final stop bit arm
            // a reply. This is not a wire-level transaction ID: late duplicate
            // replies inside a valid window remain a protocol limitation.
            if (rx_frame_start) frame_in_window<=(state==S_REPLY);
            if (rx_error || rx_valid) frame_in_window<=0;

            if (ENABLED && !fault) begin
                case (state)
                    S_BOOT: begin
                        if (state_ticks>=BOOT_TICKS && quiet_ticks>=QUIET_TICKS) begin
                            state<=S_STOP; state_ticks<=0; operation_ticks<=0; phase<=P_INIT;
                        end
                    end
                    S_STOP,S_MODE,S_VOLUME,S_PLAY,S_QUERY: begin
                        if (cmd_valid && cmd_ready) begin
                            case (state)
                                S_STOP: sent_op<=O_STOP;
                                S_MODE: sent_op<=O_MODE;
                                S_VOLUME: sent_op<=O_VOLUME;
                                S_PLAY: sent_op<=O_PLAY;
                                default: begin sent_op<=O_QUERY; frame_in_window<=0; flush_rx<=1; end
                            endcase
                            state<=S_TX; state_ticks<=0;
                        end
                    end
                    S_TX: begin
                        if (tx_done) begin
                            state_ticks<=0;
                            if (sent_op==O_QUERY) begin
                                state<=S_REPLY; frame_in_window<=0;
                            end else if (stopping && sent_op!=O_STOP) begin
                                state<=S_STOP;
                            end else if (sent_op==O_MODE) state<=S_VOLUME;
                            else if (sent_op==O_VOLUME) begin
                                initialized<=1; state<=S_DRAIN;
                            end else state<=S_QUIET;
                        end
                    end
                    S_QUIET: begin
                        if (state_ticks>=QUERY_TICKS && quiet_ticks>=QUIET_TICKS) begin
                            state<=S_QUERY; state_ticks<=0;
                        end
                    end
                    S_REPLY: begin
                        // An outstanding query is consumed before cancellation
                        // starts another one. Invalid/unrelated frames do not
                        // extend the fixed response deadline.
                        if (status_reply) begin
                            state_ticks<=0;
                            if (stopping && phase!=P_STOP) begin
                                phase<=P_STOP; state<=S_STOP;
                            end else if (stopping && cancel_pending && phase==P_STOP && sent_op==O_QUERY) begin
                                // cancel_pending clears only when STOP is sent;
                                // this reply belongs to the pre-stop query.
                                state<=S_STOP;
                            end else if (phase==P_INIT && stopped_reply) begin
                                state<=S_MODE;
                            end else if (phase==P_START && playing_reply) begin
                                phase<=P_PLAY; operation_ticks<=0; state<=S_QUIET;
                            end else if (phase==P_PLAY && stopped_reply) begin
                                rsp_valid<=1; rsp_tag<=active_tag; rsp_code<=0;
                                active<=0; state<=S_DRAIN;
                            end else if (phase==P_STOP && stopped_reply) begin
                                rsp_valid<=1; rsp_tag<=active_tag; rsp_code<=3;
                                active<=0; state<=S_DRAIN;
                            end else state<=S_QUIET;
                        end
                    end
                    S_DRAIN: begin
                        if (state_ticks>=QUIET_TICKS && quiet_ticks>=QUIET_TICKS && low_stable) begin
                            state<=S_IDLE; state_ticks<=0;
                        end
                    end
                    S_IDLE: begin
                        if (req_valid && req_ready) begin
                            active_tag<=req_tag; track<=physical_track;
                            tag_valid<=1; active<=1; cancel_pending<=0;
                            operation_ticks<=0; state_ticks<=0; phase<=P_START;
                            if (map_hit && physical_track!=0) state<=S_PLAY;
                            else state<=S_REJECT;
                        end else if (high_stable) begin
                            // Unexpected playback outside an owned transaction.
                            fault<=1; initialized<=0; state<=S_EMERGENCY;
                            state_ticks<=0;
                        end
                    end
                    S_REJECT: begin
                        // The request was accepted, but no PLAY bytes were sent.
                        rsp_valid<=1; rsp_tag<=active_tag; rsp_code<=1;
                        active<=0; state<=S_DRAIN; state_ticks<=0;
                    end
                    default: begin fault<=1; initialized<=0; state<=S_EMERGENCY; end
                endcase

                if (stop_match) begin
                    stop_seen<=1; cancel_pending<=1; active<=1;
                    phase<=P_STOP; operation_ticks<=0; rsp_valid<=0;
                    if (state!=S_TX && state!=S_REPLY) begin state<=S_STOP; state_ticks<=0; end
                    // A same-cycle reply ends the old query, so it is safe to
                    // send STOP next. It must never certify that STOP completed.
                    if (state==S_REPLY && status_reply) begin state<=S_STOP; state_ticks<=0; end
                    if (state==S_TX && tx_done && sent_op!=O_QUERY) begin state<=S_STOP; state_ticks<=0; end
                end
                // Mark STOP dispatched, not acknowledged. Only its subsequent
                // status reply plus stable BUSY low can produce code 3.
                if (state==S_STOP && cmd_valid && cmd_ready) cancel_pending<=0;

                if (tx_error ||
                    (tick_1ms && state==S_BOOT && state_ticks>=BOOT_TICKS+INIT_TICKS-1 && quiet_ticks<QUIET_TICKS) ||
                    (state==S_REPLY && tick_1ms && state_ticks>=RESPONSE_TICKS-1 && !status_reply) ||
                    (state==S_DRAIN && (high_stable || (tick_1ms && state_ticks>=INIT_TICKS-1))) ||
                    (tick_1ms && state!=S_BOOT && !initialized && phase==P_INIT && operation_ticks>=INIT_TICKS-1 &&
                        !(state==S_TX && sent_op==O_VOLUME && tx_done)) ||
                    (tick_1ms && active && !stop_match && !progress_on_deadline &&
                        ((phase==P_START && operation_ticks>=START_TICKS-1) ||
                         (phase==P_PLAY && operation_ticks>=PLAY_TICKS-1) ||
                         (phase==P_STOP && operation_ticks>=STOP_TICKS-1)))) begin
                    fault<=1; initialized<=0; state<=S_EMERGENCY;
                    rsp_valid<=0; state_ticks<=0; frame_in_window<=0;
                end
            end else if (fault) begin
                // Best effort silence after uncertain execution. No result is
                // emitted, even when this final frame was physically sent.
                if (state==S_EMERGENCY && cmd_valid && cmd_ready) begin
                    sent_op<=O_EMERGENCY; state<=S_TX; state_ticks<=0;
                end else if (state==S_TX && tx_done) state<=S_FAULT;
            end
        end
    end

    // synthesis translate_off
    initial begin
        if (MAX_DATA<2 || VOLUME<0 || VOLUME>30 || STOPPED_STATUS==PLAYING_STATUS ||
            BOOT_TICKS<1 || INIT_TICKS<1 || QUERY_TICKS<1 || RESPONSE_TICKS<1 ||
            QUIET_TICKS<1 || BUSY_FILTER_TICKS<1 || START_TICKS<1 || PLAY_TICKS<1 || STOP_TICKS<1)
            $fatal(1,"dfr0534_player_core: invalid parameters");
    end
    // synthesis translate_on
endmodule
