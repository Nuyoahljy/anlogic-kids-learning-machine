// Result-level integration candidate. No camera, physical pins or UART binding.
// OSD coordinates/status snapshot share clk; osd_active/rgb have one-cycle latency.
module items14_system #(
    parameter integer TIMEOUT_MS=100,ABSENT_SAMPLES=3,FEEDBACK_TICKS=1500,MAX_WRONG=2
) (
    input wire clk,rst_n,tick_1ms,flush,block_revoke,card_revoke,
    input wire block_event,block_healthy,block_present,block_valid,
    input wire [3:0] block_item,
    input wire [31:0] block_frame_id,
    input wire block_source_test,
    input wire [7:0] block_count,
    input wire card_event,card_healthy,card_present,card_valid,
    input wire [3:0] card_item,
    input wire [31:0] card_frame_id,
    input wire card_source_test,
    input wire [7:0] card_count,
    input wire key_mode_pulse,key_replay_pulse,key_skip_pulse,key_reset_pulse,
    input wire audio_idle,audio_fault,
    input wire video_frame_start,
    input wire [10:0] pixel_x,
    input wire [9:0] pixel_y,
    output wire detectors_flush,
    output wire obs_event,obs_healthy,obs_present,obs_valid,obs_revoke,obs_conflict,timed_out,
    output wire [3:0] obs_item,
    output wire [31:0] obs_frame_id,
    output wire obs_source_test,
    output wire [7:0] obs_count,
    output wire [1:0] mode,phase,
    output wire [3:0] score,question_index,target_item,display_item,
    output wire quiz_active,answer_valid,answer_correct,display_source_test,armed,
    output wire [2:0] feedback,
    output wire audio_event_valid,audio_cancel,
    output wire [2:0] audio_event_kind,
    output wire [3:0] audio_event_item,
    output wire osd_active,
    output wire [23:0] osd_rgb
);
    items14_result_join #(.TIMEOUT_MS(TIMEOUT_MS)) joiner(
        .clk(clk),.rst_n(rst_n),.tick_1ms(tick_1ms),.flush(flush),
        .block_revoke(block_revoke),.card_revoke(card_revoke),
        .block_event(block_event),.block_healthy(block_healthy),.block_present(block_present),
        .block_valid(block_valid),.block_item(block_item),.block_frame_id(block_frame_id),
        .block_source_test(block_source_test),.block_count(block_count),
        .card_event(card_event),.card_healthy(card_healthy),.card_present(card_present),
        .card_valid(card_valid),.card_item(card_item),.card_frame_id(card_frame_id),
        .card_source_test(card_source_test),.card_count(card_count),.detectors_flush(detectors_flush),
        .out_event(obs_event),.out_healthy(obs_healthy),.out_present(obs_present),.out_valid(obs_valid),
        .out_item(obs_item),.out_frame_id(obs_frame_id),.out_source_test(obs_source_test),
        .out_count(obs_count),.out_revoke(obs_revoke),.out_conflict(obs_conflict),.timed_out(timed_out));
    // The combinational flush inhibits consuming an older queued observation on
    // the same edge that a new fault occurs. Registered revoke covers the next edge.
    wire revoke_now=obs_revoke || detectors_flush;
    items14_quiz_control #(.ABSENT_SAMPLES(ABSENT_SAMPLES),.FEEDBACK_TICKS(FEEDBACK_TICKS),.MAX_WRONG(MAX_WRONG)) control(
        .clk(clk),.rst_n(rst_n),.tick_1ms(tick_1ms),.sample_valid(obs_event),.sample_healthy(obs_healthy),
        .revoke(revoke_now),.det_present(obs_present),.det_stable(obs_valid),.det_item(obs_item),
        .source_test(obs_source_test),.key_mode_pulse(key_mode_pulse),.key_replay_pulse(key_replay_pulse),
        .key_skip_pulse(key_skip_pulse),.key_reset_pulse(key_reset_pulse),.audio_idle(audio_idle),.audio_fault(audio_fault),
        .mode(mode),.phase(phase),.score(score),.question_index(question_index),.target_item(target_item),
        .quiz_active(quiz_active),.answer_valid(answer_valid),.answer_correct(answer_correct),.feedback(feedback),
        .display_item(display_item),.display_source_test(display_source_test),.armed(armed),
        .audio_event_valid(audio_event_valid),.audio_event_kind(audio_event_kind),
        .audio_event_item(audio_event_item),.audio_cancel(audio_cancel));
    reg result_healthy;
    reg [1:0] osd_mode,osd_phase;
    reg [3:0] osd_score,osd_question,osd_target,osd_item;
    reg [2:0] osd_feedback;
    reg osd_source,osd_armed,osd_audio_fault,osd_audio_busy,osd_healthy;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            result_healthy<=0;osd_mode<=0;osd_phase<=0;osd_score<=0;osd_question<=0;
            osd_target<=0;osd_item<=0;osd_feedback<=0;osd_source<=0;osd_armed<=0;
            osd_audio_fault<=0;osd_audio_busy<=0;osd_healthy<=0;
        end else begin
            if(revoke_now) result_healthy<=0;
            else if(obs_event) result_healthy<=obs_healthy;
            if(video_frame_start) begin
                osd_mode<=mode;osd_phase<=phase;osd_score<=score;osd_question<=question_index;
                osd_target<=target_item;osd_item<=revoke_now ? 4'd0 : display_item;
                osd_feedback<=feedback;osd_source<=display_source_test;osd_armed<=!revoke_now && armed;
                osd_audio_fault<=audio_fault;osd_audio_busy<=!audio_idle;osd_healthy<=!revoke_now && result_healthy;
            end
        end
    end
    items14_osd panel(.clk(clk),.rst_n(rst_n),.pixel_x(pixel_x),.pixel_y(pixel_y),
        .mode(osd_mode),.phase(osd_phase),.score(osd_score),.question_index(osd_question),
        .target_item(osd_target),.display_item(osd_item),.feedback(osd_feedback),
        .source_test(osd_source),.armed(osd_armed),.audio_fault(osd_audio_fault),.audio_busy(osd_audio_busy),
        .result_healthy(osd_healthy),.active(osd_active),.rgb(osd_rgb));
endmodule
