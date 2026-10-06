module chinese_osd (
    input wire [10:0] pixel_x,
    input wire [9:0] pixel_y,
    input wire demo_mode, box_valid,
    input wire [1:0] expected_shape, expected_color, shape, color,
    output wire active,
    output wire [23:0] rgb
);
    wire [10:0] local_x = pixel_x-11'd32;
    wire [9:0] local_y = pixel_y-10'd16;
    wire [3:0] cell_index = local_x[8:5];
    wire [1:0] line_index = local_y[6:5];
    reg [5:0] glyph;
    reg [1:0] name_shape, name_color;
    reg [23:0] ink;
    wire [15:0] font_bits;
    function [5:0] shape_glyph;
        input [1:0] shape_code;
        input [3:0] position;
        begin
            shape_glyph = 0;
            case (shape_code)
                1: case (position)
                    0: shape_glyph = 6'd16;
                    1: shape_glyph = 6'd17;
                endcase
                2: case (position)
                    0: shape_glyph = 6'd18;
                    1: shape_glyph = 6'd19;
                    2: shape_glyph = 6'd17;
                endcase
                3: case (position)
                    0: shape_glyph = 6'd20;
                    1: shape_glyph = 6'd21;
                    2: shape_glyph = 6'd17;
                endcase
            endcase
        end
    endfunction
    function [5:0] color_glyph;
        input [1:0] color_code;
        begin
            case (color_code)
                1: color_glyph = 6'd12;
                2: color_glyph = 6'd13;
                3: color_glyph = 6'd14;
                default: color_glyph = 0;
            endcase
        end
    endfunction
    always @* begin
        glyph = 0; name_shape = 0; name_color = 0; ink = 24'hffffff;
        if (line_index == 0) begin
            ink = demo_mode ? 24'hffff00 : 24'h00ffff;
            if (demo_mode) begin
                case (cell_index)
                        0: glyph = 6'd1;
                        1: glyph = 6'd2;
                        2: glyph = 6'd3;
                        3: glyph = 6'd4;
                endcase
            end else begin
                case (cell_index)
                        0: glyph = 6'd5;
                        1: glyph = 6'd6;
                        2: glyph = 6'd3;
                        3: glyph = 6'd4;
                endcase
            end
        end else if (line_index == 1 || line_index == 2) begin
            name_shape = line_index == 1 ? expected_shape : shape;
            name_color = line_index == 1 ? expected_color : color;
            if (cell_index == 0) glyph = line_index == 1 ? 6'd8 : 6'd10;
            else if (cell_index == 1) glyph = line_index == 1 ? 6'd9 : 6'd11;
            else if (line_index == 1 && !demo_mode) begin
                case (cell_index)
                    2: glyph=6'd5; 3: glyph=6'd6; 4: glyph=6'd7;
                endcase
            end else if ((line_index == 1 && expected_shape == 0) || (line_index == 2 && !box_valid)) begin
                if (line_index == 1) begin
                    case (cell_index)
                        2: glyph=6'd28; 3: glyph=6'd29;
                    endcase
                end else begin
                    case (cell_index)
                        2: glyph=6'd25; 3: glyph=6'd26; 4: glyph=6'd27;
                    endcase
                end
            end else if (name_shape == 0 || name_color == 0) begin
                case (cell_index)
                    2: glyph=6'd22; 3: glyph=6'd23; 4: glyph=6'd24;
                endcase
            end else begin
                ink = name_color == 1 ? 24'hff0000 : name_color == 2 ? 24'hffff00 : 24'h0000ff;
                if (cell_index == 2) glyph = color_glyph(name_color);
                else if (cell_index == 3) glyph = 6'd15;
                else glyph = shape_glyph(name_shape,cell_index-4'd4);
            end
        end
    end
    osd_font_rom font(.glyph(glyph),.row(local_y[4:1]),.bits(font_bits));
    assign active = pixel_x >= 32 && pixel_x < 320 && pixel_y >= 16 && pixel_y < 112;
    assign rgb = font_bits[15-local_x[4:1]] ? ink : 24'h202020;
endmodule
