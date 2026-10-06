"""Create the task-owned HDMI quiz wrapper from the verified learning wrapper."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
OLD=ROOT/'fpga/custom_project/sc520-learning-ui-audio/user_source/hdl_source/learning/hdmi_learning.v'
NEW=ROOT/'fpga/custom_project/sc520-quiz-video/user_source/hdl_source'
s=OLD.read_text(encoding='utf-8-sig').replace('module hdmi_learning #(', 'module hdmi_quiz #(')
s=s.replace('    parameter integer SCENE_FRAMES = 180,\n    parameter integer DEMO_X = 560, DEMO_Y = 280, DEMO_SCALE_SHIFT = 2', '''    parameter integer CLOCK_HZ = 75000000,
    parameter integer FEEDBACK_TICKS = 1500,
    parameter integer MOCK_PLAY_TICKS = 120,
    parameter integer AUDIO_WAIT_TICKS = 1000,
    parameter integer AUDIO_PLAY_TICKS = 15000,
    parameter integer AUDIO_STOP_TICKS = 1000''')
s=s.replace('    output wire out_vsync,','''    input wire in_source_test,
    input wire key_mode_pulse, key_replay_pulse, key_skip_pulse, key_reset_pulse,
    output wire out_vsync,''')
# Existing video pipeline retains exactly three clocks of latency.
s=s.replace('.rst_n(rst_n)', '.rst_n(core_rst_n)').replace('or negedge rst_n','or negedge core_rst_n').replace('if (!rst_n)','if (!core_rst_n)')
s=s.replace('    wire coord_valid;\n', '').replace('    wire coord_sof;\n', '')
s=s.replace('    reg [2:0] vsync_pipe;','''    reg [1:0] reset_sync;
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
    reg [2:0] vsync_pipe;''')
a=s.index('    reg previous_input_vsync;'); b=s.index('    rgb_color_segment #',a)
s=s[:a]+s[b:]
s=s.replace('.in_rgb(demo_mode ? demo_rgb : coord_rgb)', '.in_rgb(coord_rgb)')
s=s.replace('    wire label_active;\n    wire [23:0] label_rgb;\n','')
a=s.index('    chinese_osd label'); b=s.index('    reg learning_sample;',a)
s=s[:a]+s[b:]
s=s.replace('else if (scene_changed)', 'else if (source_change)')
a=s.index('    wire [3:0] det_item, display_item;'); b=s.index('    detection_adapter learning_adapter',a)
s=s[:a]+'''    wire [3:0] det_item, display_item;
    wire [9:0] det_bbox_x, det_bbox_y, det_bbox_w, det_bbox_h;
    wire [7:0] det_stable_count;
    reg det_source_test;
    always @(posedge clk or negedge core_rst_n)
        if(!core_rst_n) det_source_test<=0;
        else if(learning_sample) det_source_test<=frame_source;
'''+s[b:]
s=s.replace('.flush(scene_changed)', '.flush(source_change)')
a=s.index('    learning_events learning_control'); b=s.index('    assign out_vsync',a)
s=s[:a]+'''    // Qualify the raw pixel protocol independently of color/shape validity.
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

'''+s[b:]
s=s.replace('(demo_mode ? 24\'h808080 : rgb_fallback)', 'rgb_fallback')
s=s.replace('learning_active ? learning_rgb : label_active ? label_rgb :', 'quiz_osd_active ? quiz_osd_rgb :')
assert 'demo_mode' not in s and 'scene_changed' not in s and 'learning_events ' not in s
(NEW/'quiz/hdmi_quiz.v').write_text(s,encoding='utf-8')
top=NEW/'design_top_wrapper.v'
t=(OLD.parent.parent/'design_top_wrapper.v').read_text(encoding='utf-8-sig')
assert t.count('hdmi_learning u_roi_overlay(')==1
t=t.replace('    hdmi_learning u_roi_overlay(', '''    wire S_quiz_sim_mode;
    // Simulation controls only: enter exploration after 1s, quiz after 2s.
    // Existing gain buttons and board IO are unchanged.
    quiz_boot_controls #(.CLOCK_HZ(75000000)) u_quiz_sim_controls(
        .clk(S_hdmi_pixel_clk),.rst_n(S_hdmi_rst_n),.key_mode_pulse(S_quiz_sim_mode));
    hdmi_quiz #(.CLOCK_HZ(75000000)) u_roi_overlay(''')
anchor='        .in_rgb      ( S_hdmi_out_data  ),'
assert t.count(anchor)==1
t=t.replace(anchor,anchor+'''
        .in_source_test(1'b0),
        .key_mode_pulse(S_quiz_sim_mode),
        .key_replay_pulse(1'b0),.key_skip_pulse(1'b0),.key_reset_pulse(1'b0),''')
top.write_text(t,encoding='utf-8')
print('Generated task-owned hdmi_quiz.v and board binding; camera input, simulated controls/audio.')
