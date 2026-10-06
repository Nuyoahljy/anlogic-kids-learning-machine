module color_bbox_stats #(
    parameter integer FRAME_WIDTH = 1280,
    parameter integer FRAME_HEIGHT = 720,
    parameter integer X_MIN = 320,
    parameter integer X_MAX = 959,
    parameter integer Y_MIN = 120,
    parameter integer Y_MAX = 599,
    parameter integer RUN_LENGTH = 3,
    parameter integer MIN_AREA = 256,
    parameter integer MIN_WIDTH = 8,
    parameter integer MIN_HEIGHT = 8
) (
    input wire clk,
    input wire rst_n,
    input wire frame_tick,
    input wire in_valid,
    input wire in_sof,
    input wire in_eol,
    input wire [10:0] in_x,
    input wire [9:0] in_y,
    input wire [1:0] in_color,
    output reg out_frame,
    output reg out_valid,
    output reg [1:0] out_color,
    output reg [21:0] out_area,
    output reg [10:0] out_left,
    output reg [10:0] out_right,
    output reg [9:0] out_top,
    output reg [9:0] out_bottom
);
    localparam integer TOTAL_PIXELS = FRAME_WIDTH * FRAME_HEIGHT;
    localparam PARAM_VALID = FRAME_WIDTH >= 1 && FRAME_WIDTH <= 2048 &&
        FRAME_HEIGHT >= 1 && FRAME_HEIGHT <= 1024 && RUN_LENGTH >= 1 && RUN_LENGTH <= 16;
    reg [21:0] area [1:3];
    reg [10:0] left_edge [1:3];
    reg [10:0] right_edge [1:3];
    reg [9:0] top_edge [1:3];
    reg [9:0] bottom_edge [1:3];
    reg [21:0] pixel_count;
    reg [10:0] expected_x;
    reg [9:0] expected_y;
    reg frame_bad;
    reg frame_complete;
    reg [1:0] run_color;
    reg [4:0] run_length;
    reg [10:0] run_last_x;
    reg [9:0] run_last_y;
    integer channel;
    wire roi_hit = in_color != 0 && in_x >= X_MIN && in_x <= X_MAX &&
                   in_y >= Y_MIN && in_y <= Y_MAX;
    wire run_continues = run_length != 0 && run_color == in_color &&
        run_last_y == in_y && {1'b0,in_x} == {1'b0,run_last_x} + 12'd1 && !in_sof;
    wire [4:0] next_run_length = run_continues ?
        (run_length < RUN_LENGTH ? run_length + 5'd1 : run_length) : 5'd1;
    wire run_ready = roi_hit && next_run_length >= RUN_LENGTH;
    wire [21:0] contribution = run_continues && run_length >= RUN_LENGTH ? 22'd1 : RUN_LENGTH;
    wire [10:0] accepted_left = contribution == 1 ? in_x : in_x - (RUN_LENGTH-1);
    wire protocol_good = in_x == expected_x && in_y == expected_y &&
        in_sof == (pixel_count == 0) && in_eol == (expected_x == FRAME_WIDTH-1) &&
        pixel_count < TOTAL_PIXELS;
    wire [1:0] winner = area[1] >= area[2] && area[1] >= area[3] ? 2'd1 :
                        area[2] >= area[3] ? 2'd2 : 2'd3;
    wire dominant = (winner == 1 || {1'b0,area[winner]} >= {area[1],1'b0}) &&
                    (winner == 2 || {1'b0,area[winner]} >= {area[2],1'b0}) &&
                    (winner == 3 || {1'b0,area[winner]} >= {area[3],1'b0});
    wire qualified = PARAM_VALID && !frame_bad && frame_complete && pixel_count == TOTAL_PIXELS &&
        area[winner] >= MIN_AREA && dominant &&
        ({1'b0,right_edge[winner]} - {1'b0,left_edge[winner]} + 12'd1) >= MIN_WIDTH &&
        ({1'b0,bottom_edge[winner]} - {1'b0,top_edge[winner]} + 11'd1) >= MIN_HEIGHT;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_frame <= 0;
            out_valid <= 0;
            out_color <= 0;
            out_area <= 0;
            out_left <= 0;
            out_right <= 0;
            out_top <= 0;
            out_bottom <= 0;
            pixel_count <= 0;
            expected_x <= 0;
            expected_y <= 0;
            frame_bad <= 0;
            frame_complete <= 0;
            run_color <= 0;
            run_length <= 0;
            run_last_x <= 0;
            run_last_y <= 0;
            for (channel=1; channel<=3; channel=channel+1) begin
                area[channel] <= 0;
                left_edge[channel] <= 0;
                right_edge[channel] <= 0;
                top_edge[channel] <= 0;
                bottom_edge[channel] <= 0;
            end
        end else begin
            out_frame <= 0;
            if (frame_tick) begin
                out_frame <= 1;
                out_valid <= qualified;
                out_color <= qualified ? winner : 2'd0;
                out_area <= qualified ? area[winner] : 22'd0;
                out_left <= qualified ? left_edge[winner] : 11'd0;
                out_right <= qualified ? right_edge[winner] : 11'd0;
                out_top <= qualified ? top_edge[winner] : 10'd0;
                out_bottom <= qualified ? bottom_edge[winner] : 10'd0;
                pixel_count <= 0;
                expected_x <= 0;
                expected_y <= 0;
                frame_bad <= 0;
                frame_complete <= 0;
                run_color <= 0;
                run_length <= 0;
                for (channel=1; channel<=3; channel=channel+1) begin
                    area[channel] <= 0;
                    left_edge[channel] <= 0;
                    right_edge[channel] <= 0;
                    top_edge[channel] <= 0;
                    bottom_edge[channel] <= 0;
                end
            end else if (in_valid) begin
                if (!protocol_good) frame_bad <= 1;
                if (pixel_count < TOTAL_PIXELS+1) pixel_count <= pixel_count + 1'b1;
                if (expected_x == FRAME_WIDTH-1) begin
                    expected_x <= 0;
                    expected_y <= expected_y == FRAME_HEIGHT-1 ? 10'd0 : expected_y + 1'b1;
                end else expected_x <= expected_x + 1'b1;
                if (protocol_good && pixel_count == TOTAL_PIXELS-1) frame_complete <= 1;
                run_length <= roi_hit ? next_run_length : 5'd0;
                run_color <= roi_hit ? in_color : 2'd0;
                run_last_x <= in_x;
                run_last_y <= in_y;
                if (run_ready && protocol_good) begin
                    for (channel=1; channel<=3; channel=channel+1) begin
                        if (in_color == channel) begin
                            area[channel] <= area[channel] + contribution;
                            if (area[channel] == 0 || accepted_left < left_edge[channel]) left_edge[channel] <= accepted_left;
                            if (area[channel] == 0 || in_x > right_edge[channel]) right_edge[channel] <= in_x;
                            if (area[channel] == 0 || in_y < top_edge[channel]) top_edge[channel] <= in_y;
                            if (area[channel] == 0 || in_y > bottom_edge[channel]) bottom_edge[channel] <= in_y;
                        end
                    end
                end
            end else begin
                run_length <= 0;
                run_color <= 0;
            end
        end
    end
endmodule
