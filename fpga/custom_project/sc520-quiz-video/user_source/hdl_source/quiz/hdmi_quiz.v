module hdmi_quiz #(
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
    parameter integer CLOCK_HZ = 75000000,
    parameter integer FEEDBACK_TICKS = 1500,
    parameter integer MOCK_PLAY_TICKS = 120,
    parameter integer AUDIO_WAIT_TICKS = 1000,
    parameter integer AUDIO_PLAY_TICKS = 15000,
    parameter integer AUDIO_STOP_TICKS = 1000
) (
    input wire clk,
    input wire rst_n,
    input wire in_vsync,
    input wire in_hsync,
    input wire in_de,
    input wire [23:0] in_rgb,
    input wire in_source_test,
    input wire key_mode_pulse, key_replay_pulse, key_skip_pulse, key_reset_pulse,
    output wire out_vsync,
    output wire out_hsync,
    output wire out_de,
    output wire [23:0] out_rgb
);
    reg [1:0] reset_sync;
    always @(posedge clk or negedge rst_n)
        if(!rst_n) reset_sync<=0; else reset_sync<={reset_sync[0],1'b1};
    wire core_rst_n=reset_sync[1];
    wire coord_valid, coord_sof;
    reg frame_source;
    wire source_change=coord_valid && coord_sof && (in_source_test != frame_source);
    wire analysis_rst_n=core_rst_n && !source_change;
    always @(posedge clk or negedge core_rst_n)
        if(!core_rst_n) frame_source<=0;
        else if(coord_valid && coord_sof) frame_source<=in_source_test;
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


    always @(posedge clk or negedge core_rst_n) begin
        if (!core_rst_n) begin
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
        .clk(clk), .rst_n(core_rst_n), .in_rgb(rgb_sample), .in_valid(de_pipe[0]),
        .in_sof(sample_sof), .in_eol(sample_eol), .out_rgb(coord_rgb),
        .out_x(coord_x), .out_y(coord_y), .out_valid(coord_valid),
        .out_sof(coord_sof), .out_eol(coord_eol)
    );

    rgb_color_segment #(.X_MIN(X_MIN), .X_MAX(X_MAX), .Y_MIN(Y_MIN), .Y_MAX(Y_MAX)) segment (
        .clk(clk), .rst_n(core_rst_n), .in_rgb(coord_rgb), .in_x(coord_x), .in_y(coord_y),
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
    shape_classifier #(.X_MIN(X_MIN), .X_MAX(X_MAX), .Y_MIN(Y_MIN), .Y_MAX(Y_MAX)) classifier (
        .clk(clk), .rst_n(analysis_rst_n), .in_frame(candidate_frame), .in_valid(candidate_valid),
        .in_color(candidate_color), .in_area(candidate_area), .in_left(candidate_left), .in_right(candidate_right),
        .in_top(candidate_top), .in_bottom(candidate_bottom), .out_frame(shape_frame),
        .out_shape(raw_shape), .out_color(raw_shape_color), .out_box_area(shape_box_area)
    );
    shape_confirm confirmation (.clk(clk), .rst_n(analysis_rst_n), .in_frame(shape_frame),
        .in_shape(raw_shape), .in_color(raw_shape_color), .out_shape(stable_shape),
        .out_color(stable_shape_color), .count(shape_count));
    reg learning_sample;
    always @(posedge clk or negedge core_rst_n) begin
        if (!core_rst_n) learning_sample <= 0;
        else if (source_change) learning_sample <= 0;
        else learning_sample <= shape_frame;
    end
    wire det_update, det_present, det_valid;
    // A color/position change withdraws the confirmed box for two frames.
    // The current raw candidate is held until the next frame and distinguishes
    // continued presence from actual removal while the box is reconfirmed.
    wire learning_presence = det_present || candidate_valid;
    wire [3:0] det_item, display_item;
    wire [9:0] det_bbox_x, det_bbox_y, det_bbox_w, det_bbox_h;
    wire [7:0] det_stable_count;
    reg det_source_test;
    always @(posedge clk or negedge core_rst_n)
        if(!core_rst_n) det_source_test<=0;
        else if(learning_sample) det_source_test<=frame_source;
    detection_adapter learning_adapter (
        .clk(clk), .rst_n(core_rst_n), .flush(source_change), .sample(learning_sample),
        .box_valid(box_valid), .box_color(box_color), .shape_color(stable_shape_color), .shape(stable_shape),
        .left(box_left), .right(box_right), .top(box_top), .bottom(box_bottom),
        .box_count(box_stable_count), .shape_count(shape_count),
        .det_update(det_update), .present(det_present), .det_valid(det_valid), .item_id(det_item),
        .bbox_x(det_bbox_x), .bbox_y(det_bbox_y), .bbox_w(det_bbox_w), .bbox_h(det_bbox_h), .stable_count(det_stable_count));
    // Qualify the raw pixel protocol independently of color/shape validity.
    // A malformed frame must revoke permission, never masquerade as empty space.
    localparam integer FRAME_PIXELS = FRAME_WIDTH * FRAME_HEIGHT;
    reg [21:0] health_pixels;
    reg [10:0] health_column;
    reg health_bad, frame_healthy, det_frame_healthy;
    wire completed_healthy = !health_bad && health_pixels == FRAME_PIXELS && !de_pipe[0];
    wire bad_frame_event = frame_tick && !completed_healthy;
    always @(posedge clk or negedge analysis_rst_n) begin
        if(!analysis_rst_n) begin
            health_pixels<=0; health_column<=0; health_bad<=0; frame_healthy<=0;
        end else if(frame_tick) begin
            frame_healthy<=completed_healthy;
            health_pixels<=0; health_column<=0; health_bad<=0;
        end else if(de_pipe[0]) begin
            if(sample_sof != (health_pixels==0) ||
               sample_eol != (health_column==FRAME_WIDTH-1) ||
               health_pixels>=FRAME_PIXELS || vsync_pipe[0]) health_bad<=1;
            if(health_pixels<FRAME_PIXELS+1) health_pixels<=health_pixels+1'b1;
            health_column<=health_column==FRAME_WIDTH-1 ? 11'd0 : health_column+1'b1;
        end
    end
    always @(posedge clk or negedge core_rst_n) begin
        if(!core_rst_n) det_frame_healthy<=0;
        else if(source_change || bad_frame_event) det_frame_healthy<=0;
        else if(learning_sample) det_frame_healthy<=frame_healthy;
    end
    wire tick_1ms;
    quiz_millisecond_tick #(.CLOCK_HZ(CLOCK_HZ)) timebase(clk,core_rst_n,tick_1ms);
    wire [1:0] mode,phase;
    wire [3:0] score,question_index,target_item;
    wire [2:0] feedback;
    wire quiz_active,answer_valid,answer_correct,display_source_test,armed;
    wire audio_event_valid,audio_cancel,audio_idle,audio_fault,audio_overflow;
    wire [2:0] audio_event_kind;
    wire [3:0] audio_event_item;
    wire req_valid,req_ready,player_busy,rsp_valid,stop_valid;
    wire [2:0] req_kind;
    wire [3:0] req_item;
    wire [15:0] req_tag,rsp_tag,stop_tag;
    wire [1:0] rsp_code;
    // Source switches and malformed frames are untrusted samples: revoke permission.
    // source_test here is also the control core's internal untrusted-sample flag.
    // The visible source label still uses the actual in_source_test frame tag.
    // Result samples otherwise refer to the completed frame, not the upcoming frame.
    quiz_control #(.FEEDBACK_TICKS(FEEDBACK_TICKS)) q_control (
        .clk(clk),.rst_n(core_rst_n),.tick_1ms(tick_1ms),
        .sample_valid(det_update || source_change || bad_frame_event),
        .det_present(!source_change && !bad_frame_event && det_frame_healthy && learning_presence),
        .det_stable(!source_change && !bad_frame_event && det_frame_healthy && det_valid),
        .det_item(det_item),.source_test(source_change || bad_frame_event || !det_frame_healthy || det_source_test),
        .key_mode_pulse(key_mode_pulse),.key_replay_pulse(key_replay_pulse),
        .key_skip_pulse(key_skip_pulse),.key_reset_pulse(key_reset_pulse),
        .audio_idle(audio_idle),.audio_fault(audio_fault),.mode(mode),.phase(phase),
        .score(score),.question_index(question_index),.target_item(target_item),
        .quiz_active(quiz_active),.answer_valid(answer_valid),.answer_correct(answer_correct),
        .feedback(feedback),.display_item(display_item),.display_source_test(display_source_test),
        .armed(armed),.audio_event_valid(audio_event_valid),.audio_event_kind(audio_event_kind),
        .audio_event_item(audio_event_item),.audio_cancel(audio_cancel));
    quiz_audio_queue #(.WAIT_TICKS(AUDIO_WAIT_TICKS),.PLAY_TICKS(AUDIO_PLAY_TICKS),.STOP_TICKS(AUDIO_STOP_TICKS)) audio_queue (
        .clk(clk),.rst_n(core_rst_n),.tick_1ms(tick_1ms),.cancel(audio_cancel || source_change),
        .event_valid(audio_event_valid),.event_kind(audio_event_kind),.event_item(audio_event_item),
        .idle(audio_idle),.fault(audio_fault),.overflow(audio_overflow),
        .req_valid(req_valid),.req_kind(req_kind),.req_item(req_item),.req_tag(req_tag),
        .req_ready(req_ready),.device_busy(player_busy),.rsp_valid(rsp_valid),.rsp_tag(rsp_tag),
        .rsp_code(rsp_code),.stop_valid(stop_valid),.stop_tag(stop_tag));
    quiz_mock_player #(.PLAY_TICKS(MOCK_PLAY_TICKS)) player (
        .clk(clk),.rst_n(core_rst_n),.tick_1ms(tick_1ms),
        .req_valid(req_valid),.req_kind(req_kind),.req_item(req_item),.req_tag(req_tag),
        .req_ready(req_ready),.device_busy(player_busy),.stop_valid(stop_valid),.stop_tag(stop_tag),
        .rsp_valid(rsp_valid),.rsp_tag(rsp_tag),.rsp_code(rsp_code));

    // Bundle snapshot on the first input pixel: no mid-frame score/text changes.
    reg [1:0] osd_mode,osd_phase;
    reg [3:0] osd_score,osd_question,osd_target,osd_item;
    reg [2:0] osd_feedback;
    reg osd_source,osd_armed,osd_audio_fault,osd_audio_busy;
    always @(posedge clk or negedge core_rst_n) begin
        if(!core_rst_n) begin
            osd_mode<=0; osd_phase<=0; osd_score<=0; osd_question<=0; osd_target<=0;
            osd_item<=0; osd_feedback<=0; osd_source<=0; osd_armed<=0;
            osd_audio_fault<=0; osd_audio_busy<=0;
        end else if(coord_valid && coord_sof) begin
            osd_mode<=mode; osd_phase<=phase; osd_score<=score;
            osd_question<=question_index; osd_target<=target_item;
            osd_item<=source_change ? 4'd0 : display_item; osd_feedback<=feedback;
            osd_source<=in_source_test; osd_armed<=!source_change && armed;
            osd_audio_fault<=audio_fault; osd_audio_busy<=!audio_idle;
        end
    end
    wire quiz_osd_active;
    wire [23:0] quiz_osd_rgb;
    quiz_osd panel(.pixel_x(segment_x),.pixel_y(segment_y),.mode(osd_mode),.phase(osd_phase),
        .score(osd_score),.question_index(osd_question),.target_item(osd_target),.display_item(osd_item),
        .feedback(osd_feedback),.source_test(osd_source),.armed(osd_armed),
        .audio_fault(osd_audio_fault),.audio_busy(osd_audio_busy),.active(quiz_osd_active),.rgb(quiz_osd_rgb));

    assign out_vsync = vsync_pipe[2];
    assign out_hsync = hsync_pipe[2];
    assign out_de = de_pipe[2];
    assign out_rgb = !out_de ? 24'd0 : !segment_valid ? rgb_fallback :
                     quiz_osd_active ? quiz_osd_rgb : border ? 24'hff0000 : dynamic_border ? 24'h00ffff : segment_rgb;
endmodule
