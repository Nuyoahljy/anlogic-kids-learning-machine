module hdmi_osd_demo #(
    parameter integer FRAME_WIDTH = 1280,
    parameter integer FRAME_HEIGHT = 720,
    parameter integer X_MIN = 320,
    parameter integer X_MAX = 959,
    parameter integer Y_MIN = 120,
    parameter integer Y_MAX = 599,
    parameter integer MIN_AREA = 256,
    parameter integer MIN_WIDTH = 8,
    parameter integer MIN_HEIGHT = 8,
    parameter integer RUN_LENGTH = 3,
    parameter integer CONFIRM_FRAMES = 3,
    parameter integer DROP_FRAMES = 2,
    parameter integer MAX_STEP = 32,
    parameter integer JITTER = 2,
    parameter integer SCENE_FRAMES = 180,
    parameter integer DEMO_X = 560, DEMO_Y = 280, DEMO_SCALE_SHIFT = 2
) (
    input wire clk,
    input wire rst_n,
    input wire in_vsync,
    input wire in_hsync,
    input wire in_de,
    input wire [23:0] in_rgb,
    output wire out_vsync,
    output wire out_hsync,
    output wire out_de,
    output wire [23:0] out_rgb
);
    reg [2:0] vsync_pipe;
    reg [2:0] hsync_pipe;
    reg [2:0] de_pipe;
    reg [23:0] rgb_sample;
    reg [23:0] rgb_delay;
    reg [23:0] rgb_fallback;
    reg frame_pending;
    reg previous_vsync;
    wire sample_sof = de_pipe[0] && frame_pending;
    wire sample_eol = de_pipe[0] && !in_de;
    wire [23:0] coord_rgb;
    wire [10:0] coord_x;
    wire [9:0] coord_y;
    wire coord_valid;
    wire coord_sof;
    wire coord_eol;
    wire [23:0] segment_rgb;
    wire [10:0] segment_x;
    wire [9:0] segment_y;
    wire segment_valid;
    wire segment_sof, segment_eol;
    wire segment_roi;
    wire [1:0] segment_color;
    wire border = segment_roi &&
                  (segment_x == X_MIN || segment_x == X_MAX ||
                   segment_y == Y_MIN || segment_y == Y_MAX);
    wire candidate_frame, candidate_valid;
    wire [1:0] candidate_color;
    wire [21:0] candidate_area;
    wire [10:0] candidate_left, candidate_right;
    wire [9:0] candidate_top, candidate_bottom;
    wire box_valid;
    wire [1:0] box_color;
    wire [10:0] box_left, box_right;
    wire [9:0] box_top, box_bottom;
    wire [7:0] box_stable_count;
    wire frame_tick = vsync_pipe[2] && !previous_vsync;
    wire inside_box = box_valid && segment_x >= box_left && segment_x <= box_right &&
                      segment_y >= box_top && segment_y <= box_bottom;
    wire dynamic_border = inside_box &&
        (segment_x-box_left < 2 || box_right-segment_x < 2 ||
         segment_y-box_top < 2 || box_bottom-segment_y < 2);


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vsync_pipe <= 0;
            hsync_pipe <= 0;
            de_pipe <= 0;
            rgb_sample <= 0;
            rgb_delay <= 0;
            rgb_fallback <= 0;
            frame_pending <= 0;
            previous_vsync <= 0;
        end else begin
            previous_vsync <= vsync_pipe[2];
            vsync_pipe <= {vsync_pipe[1:0], in_vsync};
            hsync_pipe <= {hsync_pipe[1:0], in_hsync};
            de_pipe <= {de_pipe[1:0], in_de};
            rgb_sample <= in_rgb;
            rgb_delay <= rgb_sample;
            rgb_fallback <= rgb_delay;
            if (in_vsync && !vsync_pipe[0]) frame_pending <= 1;
            else if (de_pipe[0]) frame_pending <= 0;
        end
    end

    pixel_coord_adapter #(.FRAME_WIDTH(FRAME_WIDTH), .FRAME_HEIGHT(FRAME_HEIGHT)) coordinates (
        .clk(clk), .rst_n(rst_n), .in_rgb(rgb_sample), .in_valid(de_pipe[0]),
        .in_sof(sample_sof), .in_eol(sample_eol), .out_rgb(coord_rgb),
        .out_x(coord_x), .out_y(coord_y), .out_valid(coord_valid),
        .out_sof(coord_sof), .out_eol(coord_eol)
    );

    reg previous_input_vsync;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) previous_input_vsync <= 0;
        else previous_input_vsync <= in_vsync;
    end
    wire demo_mode, scene_changed;
    wire [3:0] scene;
    wire [15:0] scene_frame;
    wire [1:0] expected_shape, expected_color;
    wire [23:0] demo_rgb;
    wire analysis_rst_n = rst_n && !scene_changed;
    demo_sequence #(.SCENE_FRAMES(SCENE_FRAMES)) sequence_control (
        .clk(clk),.rst_n(rst_n),.frame_tick(in_vsync && !previous_input_vsync),
        .demo_mode(demo_mode),.scene(scene),.scene_frame(scene_frame),.scene_changed(scene_changed),
        .expected_shape(expected_shape),.expected_color(expected_color));
    demo_pattern #(.BASE_X(DEMO_X),.BASE_Y(DEMO_Y),.SCALE_SHIFT(DEMO_SCALE_SHIFT)) pattern_source (
        .pixel_x(coord_x),.pixel_y(coord_y),.shape(expected_shape),.color(expected_color),
        .scene_frame(scene_frame),.rgb(demo_rgb));

    rgb_color_segment #(.X_MIN(X_MIN), .X_MAX(X_MAX), .Y_MIN(Y_MIN), .Y_MAX(Y_MAX)) segment (
        .clk(clk), .rst_n(rst_n), .in_rgb(demo_mode ? demo_rgb : coord_rgb), .in_x(coord_x), .in_y(coord_y),
        .in_valid(coord_valid), .in_sof(coord_sof), .in_eol(coord_eol),
        .out_rgb(segment_rgb), .out_x(segment_x), .out_y(segment_y),
        .out_valid(segment_valid), .out_sof(segment_sof), .out_eol(segment_eol),
        .out_roi(segment_roi), .out_color(segment_color)
    );

    color_bbox_stats #(
        .FRAME_WIDTH(FRAME_WIDTH), .FRAME_HEIGHT(FRAME_HEIGHT),
        .X_MIN(X_MIN), .X_MAX(X_MAX), .Y_MIN(Y_MIN), .Y_MAX(Y_MAX),
        .RUN_LENGTH(RUN_LENGTH), .MIN_AREA(MIN_AREA), .MIN_WIDTH(MIN_WIDTH), .MIN_HEIGHT(MIN_HEIGHT)
    ) statistics (
        .clk(clk), .rst_n(analysis_rst_n), .frame_tick(frame_tick), .in_valid(segment_valid),
        .in_sof(segment_sof), .in_eol(segment_eol), .in_x(segment_x), .in_y(segment_y),
        .in_color(segment_color), .out_frame(candidate_frame), .out_valid(candidate_valid),
        .out_color(candidate_color), .out_area(candidate_area), .out_left(candidate_left),
        .out_right(candidate_right), .out_top(candidate_top), .out_bottom(candidate_bottom)
    );

    bbox_stabilizer #(.CONFIRM_FRAMES(CONFIRM_FRAMES), .DROP_FRAMES(DROP_FRAMES),
        .MAX_STEP(MAX_STEP), .JITTER(JITTER)) stabilizer (
        .clk(clk), .rst_n(analysis_rst_n), .in_frame(candidate_frame), .in_valid(candidate_valid),
        .in_color(candidate_color), .in_left(candidate_left), .in_right(candidate_right),
        .in_top(candidate_top), .in_bottom(candidate_bottom), .out_valid(box_valid),
        .out_color(box_color), .out_left(box_left), .out_right(box_right),
        .out_top(box_top), .out_bottom(box_bottom), .stable_count(box_stable_count)
    );

    wire shape_frame;
    wire [1:0] raw_shape, raw_shape_color, stable_shape, stable_shape_color;
    wire [23:0] shape_box_area;
    wire [7:0] shape_count;
    wire label_active;
    wire [23:0] label_rgb;
    shape_classifier #(.X_MIN(X_MIN), .X_MAX(X_MAX), .Y_MIN(Y_MIN), .Y_MAX(Y_MAX)) classifier (
        .clk(clk), .rst_n(analysis_rst_n), .in_frame(candidate_frame), .in_valid(candidate_valid),
        .in_color(candidate_color), .in_area(candidate_area), .in_left(candidate_left), .in_right(candidate_right),
        .in_top(candidate_top), .in_bottom(candidate_bottom), .out_frame(shape_frame),
        .out_shape(raw_shape), .out_color(raw_shape_color), .out_box_area(shape_box_area)
    );
    shape_confirm confirmation (.clk(clk), .rst_n(analysis_rst_n), .in_frame(shape_frame),
        .in_shape(raw_shape), .in_color(raw_shape_color), .out_shape(stable_shape),
        .out_color(stable_shape_color), .count(shape_count));
    chinese_osd label (.demo_mode(demo_mode),.expected_shape(expected_shape),.expected_color(expected_color),.pixel_x(segment_x), .pixel_y(segment_y), .box_valid(box_valid),
        .shape(stable_shape_color == box_color ? stable_shape : 2'd0),
        .color(stable_shape_color), .active(label_active), .rgb(label_rgb));

    assign out_vsync = vsync_pipe[2];
    assign out_hsync = hsync_pipe[2];
    assign out_de = de_pipe[2];
    assign out_rgb = !out_de ? 24'd0 : !segment_valid ? (demo_mode ? 24'h808080 : rgb_fallback) :
                     label_active ? label_rgb : border ? 24'hff0000 : dynamic_border ? 24'h00ffff : segment_rgb;
endmodule
