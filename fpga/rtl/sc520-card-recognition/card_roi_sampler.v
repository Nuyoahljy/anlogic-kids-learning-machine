// Fixed square ROI, 32x32 centre samples, complete-frame health qualification.
// Coordinates and SOF/EOL describe the raw pre-OSD raster. frame_end is a
// separate pulse in blanking; the final expected pixel alone never commits.
module card_roi_sampler #(
    parameter integer FRAME_WIDTH = 1280,
    parameter integer FRAME_HEIGHT = 720,
    parameter integer ROI_X = 400,
    parameter integer ROI_Y = 120,
    parameter integer ROI_SIZE = 480,
    parameter integer DARK_THRESHOLD = 180,
    parameter integer CHROMA_THRESHOLD = 40
) (
    input wire clk, rst_n, flush,
    input wire in_valid, in_sof, in_eol,
    input wire [10:0] in_x,
    input wire [9:0] in_y,
    input wire [23:0] in_rgb,
    input wire in_frame_end,
    input wire [31:0] in_frame_id,
    input wire in_source_test,
    output reg frame_start,
    output reg sample_valid,
    output reg [9:0] sample_index,
    output reg sample_foreground,
    output reg frame_end, frame_good, frame_present,
    output reg [31:0] frame_id,
    output reg frame_source_test,
    output reg [19:0] roi_fg_count,
    output reg fault_event
);
    localparam integer CELL = ROI_SIZE / 32;
    localparam integer PIXELS = FRAME_WIDTH * FRAME_HEIGHT;
    reg active, bad;
    reg [31:0] pixels_seen, active_id;
    reg [10:0] next_x, next_sample_x;
    reg [9:0] next_y, next_sample_y;
    reg [10:0] samples_seen;
    reg [19:0] foreground_seen;
    reg active_source;
    wire [7:0] r = in_rgb[23:16];
    wire [7:0] g = in_rgb[15:8];
    wire [7:0] b = in_rgb[7:0];
    wire [7:0] minimum = r < g ? (r < b ? r : b) : (g < b ? g : b);
    wire [7:0] maximum = r > g ? (r > b ? r : b) : (g > b ? g : b);
    wire [8:0] chroma = {1'b0,maximum} - {1'b0,minimum};
    wire foreground = minimum < DARK_THRESHOLD || chroma >= CHROMA_THRESHOLD;
    wire in_roi = in_x >= ROI_X && in_x < ROI_X+ROI_SIZE &&
                  in_y >= ROI_Y && in_y < ROI_Y+ROI_SIZE;
    wire raster_error = in_sof || in_x != next_x || in_y != next_y ||
                        in_eol != (next_x == FRAME_WIDTH-1) ||
                        pixels_seen >= PIXELS || in_source_test != active_source ||
                        in_frame_id != active_id;
    wire complete_good = active && !bad && !in_valid && !in_sof && !in_eol &&
                         pixels_seen == PIXELS && samples_seen == 1024 &&
                         in_source_test == active_source && in_frame_id == active_id;

    // synthesis translate_off
    initial begin
        if (FRAME_WIDTH < 64 || FRAME_WIDTH > 2048 || FRAME_HEIGHT < 64 || FRAME_HEIGHT > 1024 ||
            ROI_SIZE < 64 || ROI_SIZE > 992 || ROI_SIZE % 32 != 0 ||
            ROI_X < 0 || ROI_Y < 0 || ROI_X+ROI_SIZE > FRAME_WIDTH || ROI_Y+ROI_SIZE > FRAME_HEIGHT ||
            DARK_THRESHOLD < 0 || DARK_THRESHOLD > 255 || CHROMA_THRESHOLD < 1 || CHROMA_THRESHOLD > 255) begin
            $display("CARD_PARAMETER_ERROR: invalid sampler geometry or thresholds");
            $finish;
        end
    end
    // synthesis translate_on

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active<=0; bad<=0; pixels_seen<=0; active_id<=0; active_source<=0;
            next_x<=0; next_y<=0; next_sample_x<=ROI_X+CELL/2; next_sample_y<=ROI_Y+CELL/2;
            samples_seen<=0; foreground_seen<=0;
            frame_start<=0; sample_valid<=0; sample_index<=0; sample_foreground<=0;
            frame_end<=0; frame_good<=0; frame_present<=1; frame_id<=0; frame_source_test<=0;
            roi_fg_count<=0; fault_event<=0;
        end else if (flush) begin
            active<=0; bad<=0; pixels_seen<=0; active_id<=0; active_source<=0;
            next_x<=0; next_y<=0; next_sample_x<=ROI_X+CELL/2; next_sample_y<=ROI_Y+CELL/2;
            samples_seen<=0; foreground_seen<=0;
            frame_start<=0; sample_valid<=0; sample_index<=0; sample_foreground<=0;
            frame_end<=0; frame_good<=0; frame_present<=1; frame_id<=0; frame_source_test<=0;
            roi_fg_count<=0; fault_event<=1;
        end else begin
            frame_start<=0; sample_valid<=0; frame_end<=0; fault_event<=0;
            if (in_frame_end) begin
                frame_end<=1;
                frame_good<=complete_good;
                frame_present<=complete_good ? foreground_seen!=0 : 1'b1;
                frame_id<=active ? active_id : in_frame_id;
                frame_source_test<=active ? active_source : in_source_test;
                roi_fg_count<=foreground_seen;
                if (!complete_good) fault_event<=1;
                active<=0; bad<=0; pixels_seen<=0; samples_seen<=0; foreground_seen<=0;
                next_x<=0; next_y<=0; next_sample_x<=ROI_X+CELL/2; next_sample_y<=ROI_Y+CELL/2;
            end else if (in_valid) begin
                if (!active) begin
                    active<=1;
                    active_id<=in_frame_id; active_source<=in_source_test;
                    frame_start<=1;
                    bad<=!in_sof || in_x!=0 || in_y!=0 || in_eol;
                    if (!in_sof || in_x!=0 || in_y!=0 || in_eol) fault_event<=1;
                    pixels_seen<=1; next_x<=1; next_y<=0;
                    samples_seen<=0;
                    foreground_seen<=in_roi && foreground ? 20'd1 : 20'd0;
                    next_sample_x<=ROI_X+CELL/2; next_sample_y<=ROI_Y+CELL/2;
                end else begin
                    if (raster_error) begin bad<=1; fault_event<=1; end
                    if (pixels_seen < PIXELS+1) pixels_seen<=pixels_seen+1'b1;
                    if (next_x == FRAME_WIDTH-1) begin
                        next_x<=0;
                        if (next_y < FRAME_HEIGHT-1) next_y<=next_y+1'b1;
                    end else next_x<=next_x+1'b1;
                    if (in_roi && foreground && foreground_seen != 20'hfffff)
                        foreground_seen<=foreground_seen+1'b1;
                    if (samples_seen < 1024 && in_x == next_sample_x && in_y == next_sample_y) begin
                        sample_valid<=1;
                        sample_index<=samples_seen[9:0]; sample_foreground<=foreground;
                        samples_seen<=samples_seen+1'b1;
                        if (samples_seen[4:0] == 31) begin
                            next_sample_x<=ROI_X+CELL/2;
                            next_sample_y<=next_sample_y+CELL;
                        end else next_sample_x<=next_sample_x+CELL;
                    end
                end
            end else if (in_sof || in_eol) begin
                bad<=1;
                fault_event<=1;
            end
        end
    end
endmodule
