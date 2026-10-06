module fixed_rect_overlay #(
    parameter integer X_MIN = 320,
    parameter integer X_MAX = 959,
    parameter integer Y_MIN = 120,
    parameter integer Y_MAX = 599,
    parameter [23:0] BORDER_RGB = 24'hFF0000
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [23:0] in_rgb,
    input  wire [10:0] in_x,
    input  wire [9:0]  in_y,
    input  wire        in_valid,
    input  wire        in_sof,
    input  wire        in_eol,
    output reg  [23:0] out_rgb,
    output reg  [10:0] out_x,
    output reg  [9:0]  out_y,
    output reg         out_valid,
    output reg         out_sof,
    output reg         out_eol
);

    localparam RECT_ENABLED = (X_MIN >= 0) && (X_MIN <= X_MAX) &&
                             (X_MAX <= 2047) && (Y_MIN >= 0) &&
                             (Y_MIN <= Y_MAX) && (Y_MAX <= 1023);

    wire inside_rect;
    wire on_border;

    assign inside_rect = RECT_ENABLED &&
                         (in_x >= X_MIN) && (in_x <= X_MAX) &&
                         (in_y >= Y_MIN) && (in_y <= Y_MAX);
    assign on_border = inside_rect &&
                       ((in_x == X_MIN) || (in_x == X_MAX) ||
                        (in_y == Y_MIN) || (in_y == Y_MAX));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_rgb   <= 24'h000000;
            out_x     <= 11'd0;
            out_y     <= 10'd0;
            out_valid <= 1'b0;
            out_sof   <= 1'b0;
            out_eol   <= 1'b0;
        end else begin
            out_valid <= in_valid;
            out_sof   <= in_valid && in_sof;
            out_eol   <= in_valid && in_eol;
            if (in_valid) begin
                out_rgb <= on_border ? BORDER_RGB : in_rgb;
                out_x   <= in_x;
                out_y   <= in_y;
            end else begin
                out_rgb <= 24'h000000;
                out_x   <= 11'd0;
                out_y   <= 10'd0;
            end
        end
    end

endmodule
