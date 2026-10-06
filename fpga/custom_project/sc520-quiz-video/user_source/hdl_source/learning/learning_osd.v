// Bottom panel only: y=608..711, below the detector ROI ending at y=599.
// Fully combinational; parent video timing and latency are unchanged.
// audio_status is the abstract software player's state, never hardware evidence.
module learning_osd (
    input wire [10:0] pixel_x,
    input wire [9:0] pixel_y,
    input wire [3:0] item_id,
    input wire det_valid,
    input wire demo_mode,
    input wire [1:0] audio_status,
    output wire active,
    output wire [23:0] rgb
);
    wire [9:0] text_y = pixel_y - 10'd612;
    wire [1:0] line_index = text_y[6:5];
    wire [10:0] value_x = pixel_x - 11'd160;
    wire [10:0] label_x = pixel_x - 11'd48;
    wire [10:0] status_x = pixel_x - 11'd928;
    wire [5:0] value_index = line_index == 0 ? {1'b0,value_x[9:5]} : value_x[9:4];
    wire [7:0] value_glyph;
    wire valid_item;
    reg [7:0] glyph;
    reg [3:0] font_column;
    reg [23:0] ink;
    wire [15:0] font_bits;
    learning_content content(.item_id(item_id),.det_valid(det_valid),
        .line_index(line_index),.char_index(value_index),.glyph(value_glyph),.valid_item(valid_item));
    always @* begin
        glyph = 0; font_column = 0; ink = 24'hF5F7FA;
        if (pixel_y >= 10'd612 && pixel_y < 10'd708) begin
            if (pixel_x >= 11'd48 && pixel_x < 11'd144) begin
                font_column = label_x[4:1];
                case (label_x[6:5])
                    0: case (line_index)
                        0: glyph=8'd128; 1: glyph=8'd130; 2: glyph=8'd132;
                    endcase
                    1: case (line_index)
                        0: glyph=8'd129; 1: glyph=8'd131; 2: glyph=8'd129;
                    endcase
                    2: glyph=8'd58;
                endcase
                ink = 24'hC4D6E3;
            end else if (pixel_x >= 11'd160 && pixel_x < 11'd864) begin
                glyph = value_glyph;
                font_column = line_index == 0 ? value_x[4:1] : {1'b0,value_x[3:1]};
                if (!valid_item) ink = 24'hC4D6E3;
            end else if (pixel_x >= 11'd928 && pixel_x < 11'd1216) begin
                font_column = status_x[4:1];
                case (line_index)
                    0: begin
                        case (status_x[8:5])
                            0: glyph=8'd145; 1: glyph=8'd131; 2: glyph=8'd146; 3: glyph=8'd147; 4: glyph=8'd58;
                            5: case (audio_status)
                                0: glyph=8'd148; 1: glyph=8'd150; 2: glyph=8'd152; 3: glyph=8'd154;
                            endcase
                            6: case (audio_status)
                                0: glyph=8'd149; 1: glyph=8'd151; 2: glyph=8'd153; 3: glyph=8'd155;
                            endcase
                        endcase
                        if (audio_status == 3) ink=24'hFFCC99;
                        else if (audio_status == 2) ink=24'h9EF0CC;
                    end
                    1: begin
                        case (status_x[8:5])
                            0: glyph=demo_mode ? 8'd156 : 8'd160;
                            1: glyph=demo_mode ? 8'd157 : 8'd161;
                            2: glyph=8'd158; 3: glyph=8'd159;
                        endcase
                        ink=demo_mode ? 24'hFFE3A3 : 24'hABE8F2;
                    end
                    2: begin
                        case (status_x[8:5])
                            0: glyph=8'd162; 1: glyph=8'd163; 2: glyph=8'd164; 3: glyph=8'd165; 4: glyph=8'd166;
                        endcase
                        ink=24'hC4D6E3;
                    end
                endcase
            end
        end
    end
    learning_font_rom font(.glyph(glyph),.row(text_y[4:1]),.bits(font_bits));
    assign active = pixel_x >= 11'd32 && pixel_x < 11'd1248 && pixel_y >= 10'd608 && pixel_y < 10'd712;
    assign rgb = !active ? 24'd0 :
        (font_bits[15-font_column] ? ink : 24'h18242C);
endmodule
