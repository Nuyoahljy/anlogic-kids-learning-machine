module shape_classifier #(
    parameter integer X_MIN = 320, X_MAX = 959,
    parameter integer Y_MIN = 120, Y_MAX = 599,
    parameter integer MIN_SIZE = 24,
    parameter integer TRI_LOW = 51, TRI_HIGH = 80,
    parameter integer CIRCLE_LOW = 88, CIRCLE_HIGH = 110,
    parameter integer SQUARE_LOW = 116
) (
    input wire clk, rst_n,
    input wire in_frame, in_valid,
    input wire [1:0] in_color,
    input wire [21:0] in_area,
    input wire [10:0] in_left, in_right,
    input wire [9:0] in_top, in_bottom,
    output reg out_frame,
    output reg [1:0] out_shape, out_color,
    output reg [23:0] out_box_area
);
    reg [1:0] state;
    reg [3:0] step;
    reg [23:0] product, multiplicand;
    reg [11:0] multiplier;
    reg [11:0] width, height;
    reg [21:0] area;
    reg [1:0] color;
    reg geometry_valid;
    reg [31:0] scaled_area, tri_low, tri_high, circle_low, circle_high, square_low, box_full;
    wire [11:0] input_width = {1'b0,in_right} - {1'b0,in_left} + 12'd1;
    wire [11:0] input_height = {2'b0,in_bottom} - {2'b0,in_top} + 12'd1;
    wire near_square = {4'd0,width} * 16'd5 >= {4'd0,height} * 16'd4 &&
                       {4'd0,height} * 16'd5 >= {4'd0,width} * 16'd4;
    wire triangle_aspect = {4'd0,width} * 16'd2 >= {4'd0,height} &&
                          {4'd0,width} * 16'd4 <= {4'd0,height} * 16'd7;
    wire usable = geometry_valid && area != 0 && {2'd0,area} <= product;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= 0; step <= 0; product <= 0; multiplicand <= 0; multiplier <= 0;
            width <= 0; height <= 0; area <= 0; color <= 0; geometry_valid <= 0;
            scaled_area <= 0; tri_low <= 0; tri_high <= 0; circle_low <= 0;
            circle_high <= 0; square_low <= 0; box_full <= 0;
            out_frame <= 0; out_shape <= 0; out_color <= 0; out_box_area <= 0;
        end else begin
            out_frame <= 0;
            if (in_frame) begin
                state <= 1; step <= 0; product <= 0;
                width <= input_width; height <= input_height;
                multiplicand <= {12'd0,input_width}; multiplier <= input_height;
                area <= in_area; color <= in_color;
                geometry_valid <= in_valid && in_color != 0 && in_left <= in_right && in_top <= in_bottom &&
                    in_left > X_MIN && in_right < X_MAX && in_top > Y_MIN && in_bottom < Y_MAX &&
                    input_width >= MIN_SIZE && input_height >= MIN_SIZE;
            end else if (state == 1) begin
                if (multiplier[0]) product <= product + multiplicand;
                multiplicand <= multiplicand << 1; multiplier <= multiplier >> 1;
                if (step == 11) state <= 2;
                else step <= step + 1'b1;
            end else if (state == 2) begin
                scaled_area <= {3'd0,area,7'd0};
                tri_low <= product * TRI_LOW; tri_high <= product * TRI_HIGH;
                circle_low <= product * CIRCLE_LOW; circle_high <= product * CIRCLE_HIGH;
                square_low <= product * SQUARE_LOW; box_full <= {1'd0,product,7'd0};
                state <= 3;
            end else if (state == 3) begin
                out_frame <= 1; out_shape <= 0;
                out_color <= usable ? color : 2'd0;
                out_box_area <= product;
                if (usable && scaled_area <= box_full) begin
                    if (near_square && scaled_area >= square_low) out_shape <= 2;
                    else if (near_square && scaled_area >= circle_low && scaled_area <= circle_high) out_shape <= 1;
                    else if (triangle_aspect && scaled_area >= tri_low && scaled_area <= tri_high) out_shape <= 3;
                end
                state <= 0;
            end
        end
    end
endmodule
