// Resource probe only: four independently writable chunks drive all225 inputs.
// Six fixed64-bit output chunks expose all349 outputs without folding.
// Wrapper registers/mux/IO are reported separately; no production timing claim.
module shape30_synthesis_wrapper #(
    parameter TEMPLATE_FILE="templates.mem",GEOMETRY_FILE="contour29-shapes.mem",
    parameter LOGO_INDEX_FILE="anlogic_logo_index.mem",LOGO_PALETTE_FILE="anlogic_logo_palette.mem"
) (
    input wire rst_n,capture_clk,display_clk,
    input wire [63:0] input_data,input wire [1:0] input_select,input wire input_write_enable,
    output reg [2:0] observation_phase,
    output reg [63:0] observation_data
);
    reg [224:0] loaded_inputs;
    always @(posedge capture_clk or negedge rst_n)
        if(!rst_n)loaded_inputs<=0;
        else if(input_write_enable)case(input_select)
            0:loaded_inputs[63:0]<=input_data;
            1:loaded_inputs[127:64]<=input_data;
            2:loaded_inputs[191:128]<=input_data;
            3:loaded_inputs[224:192]<=input_data[32:0];
        endcase
    wire in_frame_start,in_source_test,in_valid,in_eol;
    wire [31:0] in_frame_id,in_done_id;wire [95:0] in_rgb96;
    wire in_frame_done,in_frame_good,in_done_source_test,in_revoke,tick_1ms,flush;
    wire key_mode_pulse,key_replay_pulse,key_skip_pulse,key_reset_pulse,audio_idle,audio_fault;
    wire video_frame_start,video_vsync,video_hsync,video_de;
    wire [10:0] pixel_x;wire [9:0] pixel_y;wire [23:0] video_rgb;
    assign {in_frame_start,in_frame_id,in_source_test,in_valid,in_eol,in_rgb96,
        in_frame_done,in_frame_good,in_done_id,in_done_source_test,in_revoke,tick_1ms,flush,
        key_mode_pulse,key_replay_pulse,key_skip_pulse,key_reset_pulse,audio_idle,audio_fault,
        video_frame_start,video_vsync,video_hsync,video_de,pixel_x,pixel_y,video_rgb}=loaded_inputs;
    wire out_vsync,out_hsync,out_de;wire [23:0] out_rgb;
    wire obs_event,obs_healthy,obs_present,obs_valid,obs_revoke,obs_conflict,timed_out;
    wire [3:0] obs_item;wire [31:0] obs_frame_id;wire obs_source_test;wire [7:0] obs_count;
    wire [1:0] mode,phase;wire [3:0] score,question_index,target_item,display_item;
    wire quiz_active,answer_valid,answer_correct,display_source_test,armed;
    wire [2:0] feedback;wire audio_event_valid,audio_cancel;
    wire [2:0] audio_event_kind;wire [3:0] audio_event_item;
    wire link_fault,quarantined;wire [27:0] render_state;
    wire [191:0] recognition_packet;wire recognition_event,recognition_fresh,recognition_fault;
    wire [7:0] recognition_age;
    pixel30_pipeline #(.RENDER_ENABLE(1),.ROTATION_VARIANTS(256),
        .TEMPLATE_FILE(TEMPLATE_FILE),.GEOMETRY_FILE(GEOMETRY_FILE),
        .LOGO_INDEX_FILE(LOGO_INDEX_FILE),.LOGO_PALETTE_FILE(LOGO_PALETTE_FILE)) dut(
        .rst_n(rst_n),.capture_clk(capture_clk),.display_clk(display_clk),
        .in_frame_start(in_frame_start),.in_frame_id(in_frame_id),.in_source_test(in_source_test),
        .in_valid(in_valid),.in_eol(in_eol),.in_rgb96(in_rgb96),.in_frame_done(in_frame_done),
        .in_frame_good(in_frame_good),.in_done_id(in_done_id),.in_done_source_test(in_done_source_test),
        .in_revoke(in_revoke),.tick_1ms(tick_1ms),.flush(flush),
        .key_mode_pulse(key_mode_pulse),.key_replay_pulse(key_replay_pulse),
        .key_skip_pulse(key_skip_pulse),.key_reset_pulse(key_reset_pulse),
        .audio_idle(audio_idle),.audio_fault(audio_fault),
        .video_frame_start(video_frame_start),.video_vsync(video_vsync),.video_hsync(video_hsync),
        .video_de(video_de),.pixel_x(pixel_x),.pixel_y(pixel_y),.video_rgb(video_rgb),
        .out_vsync(out_vsync),.out_hsync(out_hsync),.out_de(out_de),.out_rgb(out_rgb),
        .obs_event(obs_event),.obs_healthy(obs_healthy),.obs_present(obs_present),.obs_valid(obs_valid),
        .obs_revoke(obs_revoke),.obs_conflict(obs_conflict),.timed_out(timed_out),
        .obs_item(obs_item),.obs_frame_id(obs_frame_id),.obs_source_test(obs_source_test),.obs_count(obs_count),
        .mode(mode),.phase(phase),.score(score),.question_index(question_index),.target_item(target_item),
        .display_item(display_item),.quiz_active(quiz_active),.answer_valid(answer_valid),
        .answer_correct(answer_correct),.display_source_test(display_source_test),.armed(armed),.feedback(feedback),
        .audio_event_valid(audio_event_valid),.audio_cancel(audio_cancel),
        .audio_event_kind(audio_event_kind),.audio_event_item(audio_event_item),
        .link_fault(link_fault),.quarantined(quarantined),.render_state(render_state),
        .recognition_packet(recognition_packet),.recognition_event(recognition_event),
        .recognition_fresh(recognition_fresh),.recognition_fault(recognition_fault),.recognition_age(recognition_age));
    wire [348:0] observed={out_vsync,out_hsync,out_de,out_rgb,
        obs_event,obs_healthy,obs_present,obs_valid,obs_revoke,obs_conflict,timed_out,
        obs_item,obs_frame_id,obs_source_test,obs_count,mode,phase,score,question_index,target_item,display_item,
        quiz_active,answer_valid,answer_correct,display_source_test,armed,feedback,audio_event_valid,audio_cancel,
        audio_event_kind,audio_event_item,link_fault,quarantined,render_state,recognition_packet,
        recognition_event,recognition_fresh,recognition_fault,recognition_age};
    always @(posedge display_clk or negedge rst_n)
        if(!rst_n)observation_phase<=0;
        else observation_phase<=observation_phase==5 ? 0:observation_phase+1'b1;
    always @* case(observation_phase)
        0:observation_data=observed[63:0];
        1:observation_data=observed[127:64];
        2:observation_data=observed[191:128];
        3:observation_data=observed[255:192];
        4:observation_data=observed[319:256];
        5:observation_data={35'd0,observed[348:320]};
        default:observation_data=0;
    endcase
endmodule
