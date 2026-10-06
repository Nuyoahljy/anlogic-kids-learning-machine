module bbox_stabilizer #(
    parameter integer CONFIRM_FRAMES = 3,
    parameter integer DROP_FRAMES = 2,
    parameter integer MAX_STEP = 32,
    parameter integer JITTER = 2
) (
    input wire clk,
    input wire rst_n,
    input wire in_frame,
    input wire in_valid,
    input wire [1:0] in_color,
    input wire [10:0] in_left,
    input wire [10:0] in_right,
    input wire [9:0] in_top,
    input wire [9:0] in_bottom,
    output reg out_valid,
    output reg [1:0] out_color,
    output reg [10:0] out_left,
    output reg [10:0] out_right,
    output reg [9:0] out_top,
    output reg [9:0] out_bottom,
    output reg [7:0] stable_count
);
    reg [1:0] previous_color;
    reg [10:0] previous_left, previous_right;
    reg [9:0] previous_top, previous_bottom;
    reg [7:0] misses;
    function [10:0] distance;
        input [10:0] first, second;
        begin distance = first >= second ? first-second : second-first; end
    endfunction
    wire close_to_previous = in_color == previous_color &&
        distance(in_left,previous_left) <= MAX_STEP && distance(in_right,previous_right) <= MAX_STEP &&
        distance({1'b0,in_top},{1'b0,previous_top}) <= MAX_STEP &&
        distance({1'b0,in_bottom},{1'b0,previous_bottom}) <= MAX_STEP;
    wire close_to_display = distance(in_left,out_left) <= JITTER && distance(in_right,out_right) <= JITTER &&
        distance({1'b0,in_top},{1'b0,out_top}) <= JITTER &&
        distance({1'b0,in_bottom},{1'b0,out_bottom}) <= JITTER;
    wire [7:0] next_count = close_to_previous ?
        (stable_count == 255 ? 8'd255 : stable_count + 1'b1) : 8'd1;
    wire parameters_valid = CONFIRM_FRAMES >= 1 && CONFIRM_FRAMES <= 255 &&
        DROP_FRAMES >= 1 && DROP_FRAMES <= 255;
    wire candidate_valid = in_valid && in_color != 0 && in_left <= in_right && in_top <= in_bottom;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 0;
            out_color <= 0;
            out_left <= 0;
            out_right <= 0;
            out_top <= 0;
            out_bottom <= 0;
            stable_count <= 0;
            misses <= 0;
            previous_color <= 0;
            previous_left <= 0;
            previous_right <= 0;
            previous_top <= 0;
            previous_bottom <= 0;
        end else if (in_frame) begin
            if (!candidate_valid || !parameters_valid) begin
                stable_count <= 0;
                if (misses != 255) misses <= misses + 1'b1;
                if (misses >= DROP_FRAMES-1 || !parameters_valid) begin
                    out_valid <= 0;
                    out_color <= 0;
                    out_left <= 0;
                    out_right <= 0;
                    out_top <= 0;
                    out_bottom <= 0;
                    previous_color <= 0;
                end
            end else begin
                misses <= 0;
                stable_count <= next_count;
                previous_color <= in_color;
                previous_left <= in_left;
                previous_right <= in_right;
                previous_top <= in_top;
                previous_bottom <= in_bottom;
                if ((out_valid && close_to_previous) || next_count >= CONFIRM_FRAMES) begin
                    out_valid <= 1;
                    out_color <= in_color;
                    if (!out_valid || !close_to_previous || !close_to_display) begin
                        out_left <= in_left;
                        out_right <= in_right;
                        out_top <= in_top;
                        out_bottom <= in_bottom;
                    end
                end else begin
                    out_valid <= 0;
                    out_color <= 0;
                    out_left <= 0;
                    out_right <= 0;
                    out_top <= 0;
                    out_bottom <= 0;
                end
            end
        end
    end
endmodule
