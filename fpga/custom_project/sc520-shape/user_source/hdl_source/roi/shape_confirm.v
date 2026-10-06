module shape_confirm #(
    parameter integer CONFIRM_FRAMES = 3
) (
    input wire clk, rst_n, in_frame,
    input wire [1:0] in_shape, in_color,
    output reg [1:0] out_shape, out_color,
    output reg [7:0] count
);
    reg [1:0] last_shape, last_color;
    wire matches = last_shape == in_shape && last_color == in_color;
    wire [7:0] next_count = matches ? (count == 255 ? 8'd255 : count + 1'b1) : 8'd1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            last_shape <= 0; last_color <= 0; count <= 0; out_shape <= 0; out_color <= 0;
        end else if (in_frame) begin
            last_shape <= in_shape; last_color <= in_color;
            if (in_shape == 0 || in_color == 0 || CONFIRM_FRAMES < 1 || CONFIRM_FRAMES > 255) begin
                count <= 0; out_shape <= 0; out_color <= 0;
            end else begin
                count <= next_count;
                out_shape <= next_count >= CONFIRM_FRAMES ? in_shape : 2'd0;
                out_color <= next_count >= CONFIRM_FRAMES ? in_color : 2'd0;
            end
        end
    end
endmodule
