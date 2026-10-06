module demo_pattern #(
    parameter integer BASE_X = 560, BASE_Y = 280,
    parameter integer SCALE_SHIFT = 2
) (
    input wire [10:0] pixel_x,
    input wire [9:0] pixel_y,
    input wire [1:0] shape, color,
    input wire [15:0] scene_frame,
    output wire [23:0] rgb
);
    wire [10:0] left = BASE_X + {7'd0,scene_frame[5:2]};
    wire [10:0] local_x = pixel_x-left;
    wire [9:0] local_y = pixel_y-BASE_Y;
    wire [4:0] column = local_x >> SCALE_SHIFT;
    wire [4:0] row = local_y >> SCALE_SHIFT;
    wire [4:0] folded_row = row < 16 ? row : 31-row;
    reg [4:0] half_width;
    always @* begin
        half_width = 16;
        case (folded_row)
            0: half_width=4;
            1: half_width=7;
            2: half_width=9;
            3: half_width=10;
            4: half_width=11;
            5: half_width=12;
            6: half_width=13;
            7,8: half_width=14;
            9,10,11: half_width=15;
            12,13,14,15: half_width=16;
        endcase
    end
    wire within_shape = pixel_x >= left && pixel_x < left+(32 << SCALE_SHIFT) &&
                  pixel_y >= BASE_Y && pixel_y < BASE_Y+(32 << SCALE_SHIFT);
    wire circle_hit = column >= 16-half_width && column < 16+half_width;
    wire triangle_hit = column >= 15-(row >> 1) && column <= 16+(row >> 1);
    wire hit = within_shape && (shape == 2 || (shape == 1 && circle_hit) || (shape == 3 && triangle_hit));
    assign rgb = !hit ? 24'h808080 : color == 1 ? 24'hff0000 : color == 2 ? 24'hffff00 : color == 3 ? 24'h0000ff : 24'h808080;
endmodule
