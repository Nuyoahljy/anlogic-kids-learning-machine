// Result packet, freshness and eight-class business share display_clk.
module items30_system #(
    parameter integer TIMEOUT_MS=100,ABSENT_SAMPLES=3,FEEDBACK_TICKS=1500,MAX_WRONG=2
) (
    input wire clk,rst_n,tick_1ms,flush,transport_revoke,
    input wire packet_in_event,
    input wire [191:0] packet_in,
    input wire key_mode_pulse,key_replay_pulse,key_skip_pulse,key_reset_pulse,
    input wire audio_idle,audio_fault,
    output wire detectors_flush,
    output wire obs_event,obs_healthy,obs_present,obs_valid,obs_revoke,obs_conflict,timed_out,
    output wire [3:0] obs_item,
    output wire [31:0] obs_frame_id,
    output wire obs_source_test,
    output wire [7:0] obs_count,
    output wire [1:0] mode,phase,output wire [3:0] score,question_index,target_item,display_item,
    output wire quiz_active,answer_valid,answer_correct,display_source_test,armed,
    output wire [2:0] feedback,output wire audio_event_valid,audio_cancel,
    output wire [2:0] audio_event_kind,output wire [3:0] audio_event_item,
    output wire [27:0] render_state,output wire [191:0] recognition_packet,
    output wire packet_event,packet_fresh,packet_fault,output wire [7:0] packet_age
);
    items30_result_join #(.TIMEOUT_MS(TIMEOUT_MS)) joiner(
      .clk(clk),.rst_n(rst_n),.tick_1ms(tick_1ms),.flush(flush),
      .transport_revoke(transport_revoke),.in_event(packet_in_event),.in_packet(packet_in),
      .detectors_flush(detectors_flush),.out_event(obs_event),.out_healthy(obs_healthy),
      .out_present(obs_present),.out_valid(obs_valid),.out_revoke(obs_revoke),
      .out_conflict(obs_conflict),.out_item(obs_item),.out_frame_id(obs_frame_id),
      .out_source_test(obs_source_test),.out_count(obs_count),.packet(recognition_packet),
      .packet_event(packet_event),.packet_fresh(packet_fresh),.packet_fault(packet_fault),
      .packet_age(packet_age),.timed_out(timed_out));
    items30_quiz_control #(.ABSENT_SAMPLES(ABSENT_SAMPLES),.FEEDBACK_TICKS(FEEDBACK_TICKS),.MAX_WRONG(MAX_WRONG)) control(
      .clk(clk),.rst_n(rst_n),.tick_1ms(tick_1ms),.sample_valid(obs_event),.det_present(obs_present),
      .det_stable(obs_valid),.det_item(obs_item),.source_test(obs_source_test),.sample_healthy(obs_healthy),
      .revoke(obs_revoke),.key_mode_pulse(key_mode_pulse),.key_replay_pulse(key_replay_pulse),
      .key_skip_pulse(key_skip_pulse),.key_reset_pulse(key_reset_pulse),.audio_idle(audio_idle),
      .audio_fault(audio_fault),.mode(mode),.phase(phase),.score(score),.question_index(question_index),
      .target_item(target_item),.quiz_active(quiz_active),.answer_valid(answer_valid),
      .answer_correct(answer_correct),.feedback(feedback),.display_item(display_item),
      .display_source_test(display_source_test),.armed(armed),.audio_event_valid(audio_event_valid),
      .audio_event_kind(audio_event_kind),.audio_event_item(audio_event_item),.audio_cancel(audio_cancel));
    assign render_state={mode,phase,score,question_index,target_item,display_item,feedback,
                         display_source_test,armed,audio_fault,!audio_idle,obs_healthy&&!obs_revoke};
endmodule
