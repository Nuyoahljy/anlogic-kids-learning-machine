module pixel_coord_adapter #(
    parameter integer FRAME_WIDTH = 1280,
    parameter integer FRAME_HEIGHT = 720
) (
    input wire clk, rst_n,
    input wire [23:0] in_rgb,
    input wire in_valid, in_sof, in_eol,
    output reg [23:0] out_rgb,
    output reg [10:0] out_x,
    output reg [9:0] out_y,
    output reg out_valid, out_sof, out_eol
);
    localparam SIZE_VALID = FRAME_WIDTH >= 1 && FRAME_WIDTH <= 2048 &&
                           FRAME_HEIGHT >= 1 && FRAME_HEIGHT <= 1024;
    reg synced;
    reg [10:0] next_x;
    reg [9:0] next_y;
    wire [10:0] pixel_x = in_sof ? 11'd0 : next_x;
    wire [9:0] pixel_y = in_sof ? 10'd0 : next_y;
    wire last_column = pixel_x == FRAME_WIDTH - 1;
    wire last_row = pixel_y == FRAME_HEIGHT - 1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            synced <= 0;
            next_x <= 0;
            next_y <= 0;
            out_rgb <= 0;
            out_x <= 0;
            out_y <= 0;
            out_valid <= 0;
            out_sof <= 0;
            out_eol <= 0;
        end else begin
            out_rgb <= 0;
            out_x <= 0;
            out_y <= 0;
            out_valid <= 0;
            out_sof <= 0;
            out_eol <= 0;
            if (in_valid && SIZE_VALID && (in_sof || synced)) begin
                if (in_eol != last_column) begin
                    synced <= 0;
                    next_x <= 0;
                    next_y <= 0;
                end else begin
                    out_rgb <= in_rgb;
                    out_x <= pixel_x;
                    out_y <= pixel_y;
                    out_valid <= 1;
                    out_sof <= in_sof;
                    out_eol <= in_eol;
                    if (last_column) begin
                        next_x <= 0;
                        if (last_row) begin
                            synced <= 0;
                            next_y <= 0;
                        end else begin
                            synced <= 1;
                            next_y <= pixel_y + 1'b1;
                        end
                    end else begin
                        synced <= 1;
                        next_x <= pixel_x + 1'b1;
                        next_y <= pixel_y;
                    end
                end
            end
        end
    end
endmodule
