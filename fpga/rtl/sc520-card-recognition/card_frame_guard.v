// Task-local result guard. clk and tick_1ms must continue when video stops.
// Revocation records retain the previous frame tag; they are not new frames.
module card_frame_guard #(
    parameter integer TIMEOUT_MS = 100
) (
    input wire clk,
    input wire rst_n,
    input wire tick_1ms,
    input wire flush,
    input wire in_frame,
    input wire in_healthy,
    input wire in_present,
    input wire in_valid,
    input wire [3:0] in_item,
    input wire [31:0] in_frame_id,
    input wire in_source_test,
    input wire [7:0] in_stable_count,
    output wire recognizer_flush,
    output reg out_frame,
    output reg out_healthy,
    output reg out_present,
    output reg out_valid,
    output reg [3:0] out_item,
    output reg [31:0] out_frame_id,
    output reg out_source_test,
    output reg [7:0] out_stable_count,
    output reg timed_out
);
    localparam integer COUNTER_WIDTH = TIMEOUT_MS < 2 ? 1 : $clog2(TIMEOUT_MS);
    localparam [COUNTER_WIDTH-1:0] LAST_TICK = TIMEOUT_MS - 1;
    reg [COUNTER_WIDTH-1:0] elapsed_ms;
    reg flush_seen;

    wire healthy_frame = in_frame && in_healthy;
    wire legal_item = in_item >= 4'd10 && in_item <= 4'd14;
    // A complete healthy result wins when it coincides with the deadline.
    // A timeout is a single flush request, so recovery can collect new frames.
    wire timeout_now = rst_n && !flush && !timed_out && !healthy_frame &&
                       tick_1ms && elapsed_ms == LAST_TICK;
    assign recognizer_flush = flush || timeout_now;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            elapsed_ms <= 0;
            flush_seen <= 0;
            timed_out <= 0;
            out_frame <= 0;
            out_healthy <= 0;
            out_present <= 1;
            out_valid <= 0;
            out_item <= 0;
            out_frame_id <= 0;
            out_source_test <= 0;
            out_stable_count <= 0;
        end else begin
            out_frame <= 0;
            flush_seen <= flush;

            if (flush) begin
                elapsed_ms <= 0;
                timed_out <= 0;
                // Held flush suppresses every result but emits one revocation.
                out_frame <= !flush_seen;
                out_healthy <= 0;
                out_present <= 1;
                out_valid <= 0;
                out_item <= 0;
                out_stable_count <= 0;
            end else if (timeout_now) begin
                timed_out <= 1;
                out_frame <= 1;
                out_healthy <= 0;
                out_present <= 1;
                out_valid <= 0;
                out_item <= 0;
                out_stable_count <= 0;
            end else begin
                if (healthy_frame) begin
                    elapsed_ms <= 0;
                    timed_out <= 0;
                end else if (tick_1ms && !timed_out) begin
                    elapsed_ms <= elapsed_ms + 1'b1;
                end

                if (in_frame) begin
                    out_frame <= 1;
                    out_healthy <= in_healthy;
                    out_present <= in_healthy ? in_present : 1'b1;
                    out_valid <= in_healthy && in_valid && legal_item;
                    out_item <= in_healthy && in_valid && legal_item ? in_item : 4'd0;
                    out_frame_id <= in_frame_id;
                    out_source_test <= in_source_test;
                    // Healthy candidates keep their progress before confirmation.
                    out_stable_count <= !in_healthy || (in_valid && !legal_item) ?
                                        8'd0 : in_stable_count;
                end else if (!in_valid && (out_valid || in_stable_count == 0)) begin
                    // The upstream fault path can clear its result without an
                    // out_frame event. Propagate that withdrawal, never absence.
                    // An unconfirmed healthy candidate can normally have valid=0
                    // with count=1/2; preserve that count until an actual clear.
                    out_valid <= 0;
                    out_item <= 0;
                    out_stable_count <= 0;
                end
            end
        end
    end

    // synthesis translate_off
    initial begin
        if (TIMEOUT_MS < 1)
            $fatal(1, "card_frame_guard TIMEOUT_MS must be at least 1");
    end
    // synthesis translate_on
endmodule
