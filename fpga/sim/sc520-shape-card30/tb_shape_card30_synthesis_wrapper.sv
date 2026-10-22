`timescale 1ns/1ps
module tb_shape_card30_synthesis_wrapper;
    reg capture_clk=0;always #4.83 capture_clk=~capture_clk;
    reg display_clk=0;always #6.734 display_clk=~display_clk;
    reg rst_n=0,input_write_enable=0;reg [63:0] input_data=0;reg [1:0] input_select=0;
    wire [2:0] observation_phase;wire [63:0] observation_data;
    shape30_synthesis_wrapper dut(.*);
    integer errors=0,checks=0,scenarios=1,inject=0,n;reg test_done=0;
    reg [224:0] expected_inputs,literal_inputs,previous_inputs;
    reg [348:0] literal_outputs,forced_outputs;reg [383:0] padded;
    reg [2:0] previous_phase;integer seen=0;
    task ck(input bit ok,input string message);
        begin checks++;if(!ok)begin errors++;if(errors<20)$display("FAIL synthesis wrapper %s",message);end end
    endtask
    task load_inputs(input [224:0] value);
        reg [255:0] padded_input;
        begin
            padded_input={31'd0,value};
            for(integer chunk=0;chunk<4;chunk++)begin
                @(negedge capture_clk);previous_inputs=dut.loaded_inputs;
                input_select=chunk;input_data=padded_input[chunk*64+:64];input_write_enable=1;
                @(negedge capture_clk);input_write_enable=0;
                case(chunk)
                    0:previous_inputs[63:0]=input_data;
                    1:previous_inputs[127:64]=input_data;
                    2:previous_inputs[191:128]=input_data;
                    3:previous_inputs[224:192]=input_data[32:0];
                endcase
                ck(dut.loaded_inputs===previous_inputs,"selected chunk changes only its exact assigned input bits");
            end
            literal_inputs={dut.dut.in_frame_start,dut.dut.in_frame_id,dut.dut.in_source_test,
                dut.dut.in_valid,dut.dut.in_eol,dut.dut.in_rgb96,dut.dut.in_frame_done,dut.dut.in_frame_good,
                dut.dut.in_done_id,dut.dut.in_done_source_test,dut.dut.in_revoke,dut.dut.tick_1ms,dut.dut.flush,
                dut.dut.key_mode_pulse,dut.dut.key_replay_pulse,dut.dut.key_skip_pulse,dut.dut.key_reset_pulse,
                dut.dut.audio_idle,dut.dut.audio_fault,dut.dut.video_frame_start,dut.dut.video_vsync,
                dut.dut.video_hsync,dut.dut.video_de,dut.dut.pixel_x,dut.dut.pixel_y,dut.dut.video_rgb};
            ck(literal_inputs===value,"all225 independently controlled bits reach exact pipeline inputs");
        end
    endtask
    initial begin
        n=$value$plusargs("INJECT_FAULT=%d",inject);
        repeat(4)@(negedge capture_clk);rst_n=1;ck(dut.loaded_inputs==0,"probe input reset");
        for(integer polarity=0;polarity<2;polarity++)for(integer bit_index=0;bit_index<225;bit_index++)begin
            expected_inputs=225'd1<<bit_index;
            if(polarity)expected_inputs=~expected_inputs;
            load_inputs(expected_inputs);
        end
        input_write_enable=0;previous_inputs=dut.loaded_inputs;
        for(integer chunk=0;chunk<4;chunk++)begin
            input_select=chunk;input_data=~64'd0;
            repeat(2)@(negedge capture_clk);
            ck(dut.loaded_inputs===previous_inputs,"write disabled holds every input bit in each selected chunk");
        end
        @(negedge display_clk);
        for(integer i=0;i<120;i++)begin
            previous_phase=observation_phase;@(negedge display_clk);
            literal_outputs={dut.dut.out_vsync,dut.dut.out_hsync,dut.dut.out_de,dut.dut.out_rgb,
                dut.dut.obs_event,dut.dut.obs_healthy,dut.dut.obs_present,dut.dut.obs_valid,
                dut.dut.obs_revoke,dut.dut.obs_conflict,dut.dut.timed_out,dut.dut.obs_item,
                dut.dut.obs_frame_id,dut.dut.obs_source_test,dut.dut.obs_count,dut.dut.mode,dut.dut.phase,
                dut.dut.score,dut.dut.question_index,dut.dut.target_item,dut.dut.display_item,
                dut.dut.quiz_active,dut.dut.answer_valid,dut.dut.answer_correct,dut.dut.display_source_test,
                dut.dut.armed,dut.dut.feedback,dut.dut.audio_event_valid,dut.dut.audio_cancel,
                dut.dut.audio_event_kind,dut.dut.audio_event_item,dut.dut.link_fault,dut.dut.quarantined,
                dut.dut.render_state,dut.dut.recognition_packet,dut.dut.recognition_event,
                dut.dut.recognition_fresh,dut.dut.recognition_fault,dut.dut.recognition_age};
            padded={35'd0,literal_outputs};
            ck(dut.observed===literal_outputs,"all349 pipeline bits explicitly connected");
            ck(observation_data===padded[observation_phase*64+:64],"phase selects exact uncompressed64bit chunk");
            ck(observation_phase==(previous_phase==5 ? 0:previous_phase+1),"six-state phase advances");
            seen=seen|(1<<observation_phase);
        end
        ck(seen==63,"all six chunks observed");
        forced_outputs=0;
        force {dut.dut.out_vsync,dut.dut.out_hsync,dut.dut.out_de,dut.dut.out_rgb,
            dut.dut.obs_event,dut.dut.obs_healthy,dut.dut.obs_present,dut.dut.obs_valid,
            dut.dut.obs_revoke,dut.dut.obs_conflict,dut.dut.timed_out,dut.dut.obs_item,
            dut.dut.obs_frame_id,dut.dut.obs_source_test,dut.dut.obs_count,dut.dut.mode,dut.dut.phase,
            dut.dut.score,dut.dut.question_index,dut.dut.target_item,dut.dut.display_item,
            dut.dut.quiz_active,dut.dut.answer_valid,dut.dut.answer_correct,dut.dut.display_source_test,
            dut.dut.armed,dut.dut.feedback,dut.dut.audio_event_valid,dut.dut.audio_cancel,
            dut.dut.audio_event_kind,dut.dut.audio_event_item,dut.dut.link_fault,dut.dut.quarantined,
            dut.dut.render_state,dut.dut.recognition_packet,dut.dut.recognition_event,
            dut.dut.recognition_fresh,dut.dut.recognition_fault,dut.dut.recognition_age}=forced_outputs;
        for(integer polarity=0;polarity<2;polarity++)for(integer bit_index=0;bit_index<349;bit_index++)begin
            forced_outputs=349'd1<<bit_index;
            if(polarity)forced_outputs=~forced_outputs;
            padded={35'd0,forced_outputs};
            for(integer chunk=0;chunk<6;chunk++)begin
                previous_phase=observation_phase;@(negedge display_clk);
                ck(dut.observed===forced_outputs,"all349 output bits walking1/walking0 reach their literal mapping");
                ck(observation_data===padded[observation_phase*64+:64],"every walking output bit traverses every exact chunk");
                ck(observation_phase==(previous_phase==5 ? 0:previous_phase+1),"forced outputs do not disturb six-state phase");
            end
        end
        release {dut.dut.out_vsync,dut.dut.out_hsync,dut.dut.out_de,dut.dut.out_rgb,
            dut.dut.obs_event,dut.dut.obs_healthy,dut.dut.obs_present,dut.dut.obs_valid,
            dut.dut.obs_revoke,dut.dut.obs_conflict,dut.dut.timed_out,dut.dut.obs_item,
            dut.dut.obs_frame_id,dut.dut.obs_source_test,dut.dut.obs_count,dut.dut.mode,dut.dut.phase,
            dut.dut.score,dut.dut.question_index,dut.dut.target_item,dut.dut.display_item,
            dut.dut.quiz_active,dut.dut.answer_valid,dut.dut.answer_correct,dut.dut.display_source_test,
            dut.dut.armed,dut.dut.feedback,dut.dut.audio_event_valid,dut.dut.audio_cancel,
            dut.dut.audio_event_kind,dut.dut.audio_event_item,dut.dut.link_fault,dut.dut.quarantined,
            dut.dut.render_state,dut.dut.recognition_packet,dut.dut.recognition_event,
            dut.dut.recognition_fresh,dut.dut.recognition_fault,dut.dut.recognition_age};
        rst_n=0;@(negedge display_clk);ck(observation_phase==0&&dut.loaded_inputs==0,"wrapper reset");
        if(inject)ck(observation_phase==1,"negative wrapper phase oracle");
        test_done=1;$display("RESULT synthesis_wrapper errors=%0d checks=%0d scenarios=%0d",errors,checks,scenarios);$finish;
    end
endmodule
