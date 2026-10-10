// Standalone pre-OSD coordinate-stream experiment. Not connected to board IO.
module card_recognizer #(
    parameter integer FRAME_WIDTH=1280, FRAME_HEIGHT=720,
    parameter integer ROI_X=400, ROI_Y=120, ROI_SIZE=480,
    parameter integer DARK_THRESHOLD=180, CHROMA_THRESHOLD=40,
    parameter integer MAX_DISTANCE=40, MIN_MARGIN=24,
    parameter integer MIN_FG=16, MAX_FG=850, CONFIRM_FRAMES=3,
    parameter integer ENABLE_OUTPUT=0,
    parameter TEMPLATE_FILE="templates.mem"
) (
    input wire clk,rst_n,flush,
    input wire in_valid,in_sof,in_eol,
    input wire [10:0] in_x,
    input wire [9:0] in_y,
    input wire [23:0] in_rgb,
    input wire in_frame_end,
    input wire [31:0] in_frame_id,
    input wire in_source_test,
    output wire out_frame,out_healthy,out_present,out_valid,
    output wire [3:0] out_item,
    output wire [31:0] out_frame_id,
    output wire out_source_test,
    output wire [7:0] stable_count,
    output wire [10:0] best_distance,second_distance,sample_fg_count,
    output wire [19:0] roi_fg_count
);
    wire frame_start,sample_valid,sample_foreground,frame_end,frame_good,frame_present;
    wire [9:0] sample_index;
    wire [31:0] captured_id;
    wire captured_source,fault_event;
    wire match_frame,match_healthy,match_present,match_valid,match_source;
    wire [3:0] match_item;
    wire [31:0] match_id;

    card_roi_sampler #(.FRAME_WIDTH(FRAME_WIDTH),.FRAME_HEIGHT(FRAME_HEIGHT),
        .ROI_X(ROI_X),.ROI_Y(ROI_Y),.ROI_SIZE(ROI_SIZE),
        .DARK_THRESHOLD(DARK_THRESHOLD),.CHROMA_THRESHOLD(CHROMA_THRESHOLD)) sampler (
        .clk(clk),.rst_n(rst_n),.flush(flush),.in_valid(in_valid),.in_sof(in_sof),.in_eol(in_eol),
        .in_x(in_x),.in_y(in_y),.in_rgb(in_rgb),.in_frame_end(in_frame_end),
        .in_frame_id(in_frame_id),.in_source_test(in_source_test),
        .frame_start(frame_start),.sample_valid(sample_valid),.sample_index(sample_index),
        .sample_foreground(sample_foreground),.frame_end(frame_end),.frame_good(frame_good),
        .frame_present(frame_present),.frame_id(captured_id),.frame_source_test(captured_source),
        .roi_fg_count(roi_fg_count),.fault_event(fault_event));

    card_matcher #(.TEMPLATE_FILE(TEMPLATE_FILE),.MAX_DISTANCE(MAX_DISTANCE),.MIN_MARGIN(MIN_MARGIN),
        .MIN_FG(MIN_FG),.MAX_FG(MAX_FG),.ENABLE_OUTPUT(ENABLE_OUTPUT)) matcher (
        .clk(clk),.rst_n(rst_n),.flush(flush),.frame_start(frame_start),
        .sample_valid(sample_valid),.sample_index(sample_index),.sample_foreground(sample_foreground),
        .frame_end(frame_end),.frame_good(frame_good),.frame_present(frame_present),
        .frame_id(captured_id),.frame_source_test(captured_source),
        .out_frame(match_frame),.out_healthy(match_healthy),.out_present(match_present),.out_valid(match_valid),
        .out_item(match_item),.out_best(best_distance),.out_second(second_distance),.out_fg_count(sample_fg_count),
        .out_frame_id(match_id),.out_source_test(match_source));

    card_result_filter #(.CONFIRM_FRAMES(CONFIRM_FRAMES)) confirmation (
        .clk(clk),.rst_n(rst_n),.flush(flush || fault_event),
        .in_frame(match_frame),.in_healthy(match_healthy),.in_present(match_present),
        .in_valid(match_valid),.in_item(match_item),.in_frame_id(match_id),.in_source_test(match_source),
        .out_frame(out_frame),.out_healthy(out_healthy),.out_present(out_present),.out_valid(out_valid),
        .out_item(out_item),.out_frame_id(out_frame_id),.out_source_test(out_source_test),.stable_count(stable_count));
endmodule
