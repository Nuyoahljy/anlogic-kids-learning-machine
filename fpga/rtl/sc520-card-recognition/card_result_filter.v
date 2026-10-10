// Task-local result filter. An unknown foreground is present but never stable.
// Source changes start a fresh run; frame IDs are forwarded as observation tags.
module card_result_filter #(
    parameter integer CONFIRM_FRAMES = 3
) (
    input wire clk,
    input wire rst_n,
    input wire flush,
    input wire in_frame,
    input wire in_healthy,
    input wire in_present,
    input wire in_valid,
    input wire [3:0] in_item,
    input wire [31:0] in_frame_id,
    input wire in_source_test,
    output reg out_frame,
    output reg out_healthy,
    output reg out_present,
    output reg out_valid,
    output reg [3:0] out_item,
    output reg [31:0] out_frame_id,
    output reg out_source_test,
    output reg [7:0] stable_count
);
    localparam PARAM_VALID = CONFIRM_FRAMES >= 1 && CONFIRM_FRAMES <= 255;
    reg [3:0] last_item;
    reg last_source;
    wire candidate = PARAM_VALID && in_healthy && in_present && in_valid &&
        in_item >= 4'd10 && in_item <= 4'd14;
    wire same_candidate = stable_count != 0 && last_item == in_item &&
        last_source == in_source_test;
    wire [7:0] next_count = same_candidate ?
        (stable_count == 8'd255 ? 8'd255 : stable_count + 1'b1) : 8'd1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_frame <= 0;
            out_healthy <= 0;
            out_present <= 0;
            out_valid <= 0;
            out_item <= 0;
            out_frame_id <= 0;
            out_source_test <= 0;
            stable_count <= 0;
            last_item <= 0;
            last_source <= 0;
        end else if (flush) begin
            out_frame <= 0;
            out_healthy <= 0;
            out_present <= 0;
            out_valid <= 0;
            out_item <= 0;
            out_frame_id <= 0;
            out_source_test <= 0;
            stable_count <= 0;
            last_item <= 0;
            last_source <= 0;
        end else begin
            out_frame <= in_frame;
            if (in_frame) begin
                out_healthy <= in_healthy && PARAM_VALID;
                out_present <= in_healthy && PARAM_VALID ? in_present : 1'b1;
                out_frame_id <= in_frame_id;
                out_source_test <= in_source_test;
                last_source <= in_source_test;
                if (candidate) begin
                    last_item <= in_item;
                    stable_count <= next_count;
                    out_valid <= next_count >= CONFIRM_FRAMES;
                    out_item <= next_count >= CONFIRM_FRAMES ? in_item : 4'd0;
                end else begin
                    last_item <= 0;
                    stable_count <= 0;
                    out_valid <= 0;
                    out_item <= 0;
                end
            end
        end
    end
    // synthesis translate_off
    initial begin
        if (!PARAM_VALID) $fatal(1, "card_result_filter CONFIRM_FRAMES must be in 1..255");
    end
    // synthesis translate_on
endmodule
