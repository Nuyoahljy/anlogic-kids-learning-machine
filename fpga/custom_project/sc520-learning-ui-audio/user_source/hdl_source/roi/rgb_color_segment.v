module rgb_color_segment #(
    parameter integer X_MIN = 320,
    parameter integer X_MAX = 959,
    parameter integer Y_MIN = 120,
    parameter integer Y_MAX = 599,
    parameter [8:0] RED_MIN = 80,
    parameter [8:0] RED_MARGIN = 32,
    parameter [8:0] BLUE_MIN = 80,
    parameter [8:0] BLUE_MARGIN = 24,
    parameter [8:0] YELLOW_RED_MIN = 96,
    parameter [8:0] YELLOW_GREEN_MIN = 80,
    parameter [8:0] YELLOW_BLUE_MAX = 96,
    parameter [8:0] YELLOW_BALANCE = 80
) (
    input wire clk,
    input wire rst_n,
    input wire [23:0] in_rgb,
    input wire [10:0] in_x,
    input wire [9:0] in_y,
    input wire in_valid,
    input wire in_sof,
    input wire in_eol,
    output reg [23:0] out_rgb,
    output reg [10:0] out_x,
    output reg [9:0] out_y,
    output reg out_valid,
    output reg out_sof,
    output reg out_eol,
    output reg out_roi,
    output reg [1:0] out_color
);
    wire [8:0] red = {1'b0, in_rgb[23:16]};
    wire [8:0] green = {1'b0, in_rgb[15:8]};
    wire [8:0] blue = {1'b0, in_rgb[7:0]};
    wire roi = in_x >= X_MIN && in_x <= X_MAX &&
               in_y >= Y_MIN && in_y <= Y_MAX;
    wire red_hit = red >= RED_MIN &&
                   red >= green + RED_MARGIN && red >= blue + RED_MARGIN;
    wire blue_hit = blue >= BLUE_MIN &&
                    blue >= red + BLUE_MARGIN && blue >= green + BLUE_MARGIN;
    wire yellow_hit = red >= YELLOW_RED_MIN && green >= YELLOW_GREEN_MIN &&
                      blue <= YELLOW_BLUE_MAX &&
                      red <= green + YELLOW_BALANCE && green <= red + YELLOW_BALANCE &&
                      red >= blue + 9'd32 && green >= blue + 9'd24;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_rgb <= 0;
            out_x <= 0;
            out_y <= 0;
            out_valid <= 0;
            out_sof <= 0;
            out_eol <= 0;
            out_roi <= 0;
            out_color <= 0;
        end else begin
            out_rgb <= in_valid ? in_rgb : 24'd0;
            out_x <= in_valid ? in_x : 11'd0;
            out_y <= in_valid ? in_y : 10'd0;
            out_valid <= in_valid;
            out_sof <= in_valid && in_sof;
            out_eol <= in_valid && in_eol;
            out_roi <= in_valid && roi;
            out_color <= 0;
            if (in_valid && roi) begin
                if (yellow_hit) out_color <= 2'd2;
                else if (red_hit) out_color <= 2'd1;
                else if (blue_hit) out_color <= 2'd3;
            end
        end
    end
endmodule
