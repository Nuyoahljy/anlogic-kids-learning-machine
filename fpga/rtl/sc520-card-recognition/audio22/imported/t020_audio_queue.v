// T020 private implementation copied from the frozen 2026-10-10 reference.
// Reference SHA256 3d99f4a6760f45513e51a84a6dc785e8bd06ad8a420b261153af52e4175dfd08.
// No content-based dedup: intentional replay may carry the same kind/item.
`timescale 1ns/1ps
// Local, transport-neutral contract. No UART, file numbers, pins or real audio.
// All inputs share clk; rsp is earliest one cycle AFTER request acceptance.
module t020_audio_queue #(
    parameter integer DEPTH = 8,
    parameter integer WAIT_TICKS = 1000,
    parameter integer PLAY_TICKS = 24000,
    parameter integer STOP_TICKS = 1000
) (
    input wire clk, input wire rst_n, input wire tick_1ms,
    input wire cancel,
    input wire event_valid, input wire [2:0] event_kind,
    input wire [3:0] event_item,
    output wire idle, output reg fault, output reg overflow,
    output wire req_valid, output wire [2:0] req_kind,
    output wire [3:0] req_item, output wire [15:0] req_tag,
    input wire req_ready, input wire device_busy,
    input wire rsp_valid, input wire [15:0] rsp_tag,
    input wire [1:0] rsp_code,
    output wire stop_valid, output wire [15:0] stop_tag
);
    function integer bits_for;
        input integer n;
        integer value;
        begin
            value = n - 1;
            bits_for = 0;
            while (value > 0) begin
                bits_for = bits_for + 1;
                value = value >> 1;
            end
            if (bits_for < 1) bits_for = 1;
        end
    endfunction
    localparam integer PTR_W = bits_for(DEPTH);
    localparam integer COUNT_W = bits_for(DEPTH + 1);
    localparam [2:0] S_IDLE=0, S_WAIT=1, S_PLAY=2, S_STOP=3, S_FAULT=4;
    reg [2:0] state;
    reg [6:0] queue [0:DEPTH-1];
    reg [PTR_W-1:0] rd_ptr, wr_ptr;
    reg [COUNT_W-1:0] count;
    reg [2:0] active_kind;
    reg [3:0] active_item;
    reg [15:0] active_tag, next_tag;
    reg retried;
    reg [31:0] timer;
    wire pop = (state == S_IDLE) && (count != 0) && !cancel && !fault;
    wire full = (count == DEPTH);
    wire overflow_now = event_valid && full && !pop && !cancel && !fault;
    wire push = event_valid && !cancel && !fault && (!full || pop);
    wire matched = rsp_valid && (rsp_tag == active_tag);
    // idle means the controller may progress. fault does NOT certify physical
    // silence; stop can still be pending, or its outcome may be unknown.
    assign idle = fault || ((state == S_IDLE) && (count == 0) && !event_valid);
    assign req_valid = (state == S_WAIT) && !device_busy && !cancel &&
                       !fault && !overflow_now;
    assign req_kind = active_kind;
    assign req_item = active_item;
    assign req_tag = active_tag;
    assign stop_valid = (state == S_STOP);
    assign stop_tag = active_tag;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            rd_ptr <= 0; wr_ptr <= 0; count <= 0;
            active_kind <= 0; active_item <= 0;
            active_tag <= 0; next_tag <= 1;
            retried <= 0; timer <= 0;
            fault <= 0; overflow <= 0;
        end else begin
            // One pending entry can enter and leave in the same clock, even
            // when full. The old head is captured before this synchronous write.
            if (push) begin
                queue[wr_ptr] <= {event_kind, event_item};
                wr_ptr <= (wr_ptr == DEPTH-1) ? 0 : wr_ptr + 1'b1;
            end
            if (pop) rd_ptr <= (rd_ptr == DEPTH-1) ? 0 : rd_ptr + 1'b1;
            case ({push,pop})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: begin end
            endcase
            case (state)
                S_IDLE: begin
                    timer <= 0;
                    if (pop) begin
                        {active_kind,active_item} <= queue[rd_ptr];
                        active_tag <= next_tag;
                        next_tag <= next_tag + 1'b1;
                        retried <= 0;
                        state <= S_WAIT;
                    end
                end
                S_WAIT: begin
                    if (cancel) begin
                        state <= S_IDLE;
                        timer <= 0;
                    end else if (req_valid && req_ready) begin
                        state <= S_PLAY;
                        timer <= 0;
                    end else if (tick_1ms) begin
                        if (timer >= WAIT_TICKS-1) begin
                            fault <= 1;
                            state <= S_FAULT;
                            count <= 0; rd_ptr <= 0; wr_ptr <= 0;
                        end else timer <= timer + 1'b1;
                    end
                end
                S_PLAY: begin
                    if (cancel) begin
                        state <= S_STOP;
                        timer <= 0;
                    end else if (matched && (rsp_code == 0)) begin
                        state <= S_IDLE;
                        timer <= 0;
                    end else if (matched && (rsp_code == 1)) begin
                        // Code 1 MUST mean definitely not executed, never a
                        // generic communication error or an uncertain result.
                        timer <= 0;
                        if (!retried) begin
                            retried <= 1;
                            active_tag <= next_tag;
                            next_tag <= next_tag + 1'b1;
                            state <= S_WAIT;
                        end else begin
                            fault <= 1;
                            state <= S_FAULT;
                            count <= 0; rd_ptr <= 0; wr_ptr <= 0;
                        end
                    end else if (tick_1ms) begin
                        // ACK (2), unsolicited stop (3), busy falling and wrong
                        // tags never mean end-of-track or restart this timer.
                        if (timer >= PLAY_TICKS-1) begin
                            fault <= 1;
                            state <= S_STOP;
                            timer <= 0;
                            count <= 0; rd_ptr <= 0; wr_ptr <= 0;
                        end else timer <= timer + 1'b1;
                    end
                end
                S_STOP: begin
                    if (matched && (rsp_code == 3)) begin
                        state <= fault ? S_FAULT : S_IDLE;
                        timer <= 0;
                    end else if (tick_1ms) begin
                        if (timer >= STOP_TICKS-1) begin
                            fault <= 1;
                            state <= S_FAULT;
                            count <= 0; rd_ptr <= 0; wr_ptr <= 0;
                        end else timer <= timer + 1'b1;
                    end
                end
                default: begin
                    state <= S_FAULT;
                    count <= 0; rd_ptr <= 0; wr_ptr <= 0;
                end
            endcase
            // Cancel wins against event and request acceptance. A stop already
            // in progress retains its deadline even with repeated cancels.
            if (cancel) begin
                count <= 0; rd_ptr <= 0; wr_ptr <= 0;
                if (!fault) begin
                    if ((state == S_IDLE) || (state == S_WAIT)) begin
                        state <= S_IDLE;
                        timer <= 0;
                    end else if (state == S_PLAY) begin
                        state <= S_STOP;
                        timer <= 0;
                    end
                end
            end
            // Never silently lose a queued prompt or reorder feedback. Disable
            // new audio for this reset epoch, stopping an accepted transaction.
            if (overflow_now) begin
                overflow <= 1;
                fault <= 1;
                count <= 0; rd_ptr <= 0; wr_ptr <= 0;
                if (state == S_PLAY) begin
                    state <= S_STOP;
                    timer <= 0;
                end else if (state != S_STOP) state <= S_FAULT;
                else if (matched && (rsp_code == 3)) state <= S_FAULT;
            end
        end
    end
endmodule
