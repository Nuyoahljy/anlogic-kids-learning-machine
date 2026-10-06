module shape_label (
    input wire [10:0] pixel_x,
    input wire [9:0] pixel_y,
    input wire box_valid,
    input wire [1:0] shape, color,
    output wire active,
    output wire [23:0] rgb
);
    wire [10:0] local_x = pixel_x - 11'd32;
    wire [9:0] local_y = pixel_y - 10'd32;
    wire [2:0] column = local_x[5:3];
    wire [2:0] row = local_y[5:3];
    reg [4:0] glyph;
    always @* begin
        glyph = 0;
        case (shape)
            1: case (row)
                0,6: glyph=5'b01111;
                1,2,3,4,5: glyph=5'b10000;
            endcase
            2: case (row)
                0: glyph=5'b01111;
                1,2: glyph=5'b10000;
                3: glyph=5'b01110;
                4,5: glyph=5'b00001;
                6: glyph=5'b11110;
            endcase
            3: case (row)
                0: glyph=5'b11111;
                1,2,3,4,5,6: glyph=5'b00100;
            endcase
            default: case (row)
                0: glyph=5'b01110;
                1: glyph=5'b10001;
                2: glyph=5'b00001;
                3: glyph=5'b00010;
                4,6: glyph=5'b00100;
            endcase
        endcase
    end
    wire lit = column < 5 && glyph[4-column];
    wire [23:0] ink = shape == 0 ? 24'hffffff : color == 1 ? 24'hff0000 :
                      color == 2 ? 24'hffff00 : color == 3 ? 24'h0000ff : 24'hffffff;
    assign active = box_valid && pixel_x >= 32 && pixel_x < 72 && pixel_y >= 32 && pixel_y < 88;
    assign rgb = lit ? ink : 24'h202020;
endmodule
