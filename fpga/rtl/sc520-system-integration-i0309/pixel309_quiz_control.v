// Task-local software candidate; no camera, GPIO or audio-player binding.
// Derived from the read-only four-key reference, not a replacement in that project:
// E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-fixed-roi/
// fpga/custom_project/sc520-board-keys/user_source/hdl_source/quiz/quiz_control.v
// Reference SHA256: CD41CB3FBD5F5B698CFE1A5AA7E8FB699F91929112EED97B3D9AF724662B8DD0
module pixel309_quiz_control #(
    parameter integer ABSENT_SAMPLES = 3,
    parameter integer FEEDBACK_TICKS = 1500,
    parameter integer MAX_WRONG = 2,
    parameter integer SHAPE_ENABLE = 1
) (
    input wire clk, rst_n, tick_1ms,
    input wire sample_valid, det_present, det_stable,
    input wire [3:0] det_item,
    input wire source_test,
    input wire sample_healthy, revoke,
    input wire key_mode_pulse, key_replay_pulse, key_skip_pulse, key_reset_pulse,
    input wire audio_idle, audio_fault,
    output reg [1:0] mode,
    output reg [3:0] score, question_index, target_item,
    output wire quiz_active,
    output reg answer_valid, answer_correct,
    output reg [2:0] feedback,
    output reg [1:0] phase,
    output reg [3:0] display_item,
    output reg display_source_test,
    output reg armed,
    output reg audio_event_valid,
    output reg [2:0] audio_event_kind,
    output reg [3:0] audio_event_item,
    output reg audio_cancel
);
    localparam [1:0] IDLE=0, EXPLORE=1, QUIZ=2;
    localparam [1:0] INACTIVE=0, WAIT_ANSWER=1, FEEDBACK=2, FINISHED=3;
    localparam integer QUESTION_COUNT = SHAPE_ENABLE ? 8 : 5;
    localparam integer AW = ABSENT_SAMPLES < 2 ? 1 : $clog2(ABSENT_SAMPLES+1);
    localparam integer FW = FEEDBACK_TICKS < 2 ? 1 : $clog2(FEEDBACK_TICKS+1);
    reg [AW-1:0] absent_count;
    reg [FW-1:0] feedback_count;
    reg [3:0] wrong_count;
    reg pending_event;
    reg [2:0] pending_kind;
    reg [3:0] pending_item;
    reg [3:0] question_slot, next_round_start;

    wire invalidation = revoke || (sample_valid && !sample_healthy);
    wire legal_item = (SHAPE_ENABLE && det_item>=1 && det_item<=3) || (det_item>=10 && det_item<=14);
    wire real_answer = sample_valid && sample_healthy && !revoke && !source_test &&
        det_present && det_stable && legal_item && armed;
    wire [3:0] replay_item = sample_valid ?
        ((sample_healthy && det_present && det_stable && legal_item) ? det_item : 4'd0) : display_item;
    wire [3:0] next_slot = question_slot == QUESTION_COUNT-1 ? 4'd0 : question_slot + 4'd1;
    wire [3:0] next_round_item, next_question_item;

    // Both lookups use one mapping definition; target and queued prompt use
    // the same lookup result on each entry/advance edge.
    pixel309_question_bank #(.SHAPE_ENABLE(SHAPE_ENABLE)) round_bank(.index(next_round_start), .item(next_round_item));
    pixel309_question_bank #(.SHAPE_ENABLE(SHAPE_ENABLE)) advance_bank(.index(next_slot), .item(next_question_item));
    assign quiz_active = mode == QUIZ && phase != FINISHED;

    task queue_later;
        input [2:0] kind;
        input [3:0] item;
        begin pending_event <= 1; pending_kind <= kind; pending_item <= item; end
    endtask

    task advance_question;
        begin
            armed <= 0; absent_count <= 0; wrong_count <= 0;
            feedback <= 0; feedback_count <= 0;
            if (question_index == 10) begin
                phase <= FINISHED;
                queue_later(3'd7, 4'd0);
            end else begin
                question_index <= question_index + 1'b1;
                question_slot <= next_slot;
                target_item <= next_question_item;
                phase <= WAIT_ANSWER;
                queue_later(3'd2, next_question_item);
            end
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mode <= IDLE; phase <= INACTIVE; score <= 0;
            question_index <= 0; target_item <= 0; wrong_count <= 0;
            question_slot <= 0; next_round_start <= 0;
            answer_valid <= 0; answer_correct <= 0; feedback <= 0;
            display_item <= 0; display_source_test <= 0;
            armed <= 0; absent_count <= 0; feedback_count <= 0;
            audio_event_valid <= 0; audio_event_kind <= 0; audio_event_item <= 0;
            audio_cancel <= 0; pending_event <= 0; pending_kind <= 0; pending_item <= 0;
        end else begin
            answer_valid <= 0; answer_correct <= 0;
            audio_event_valid <= 0; audio_event_kind <= 0; audio_event_item <= 0;
            audio_cancel <= 0;

            // Invalidation always clears recognition state, even when a higher
            // priority key deliberately changes mode or advances the question.
            if (invalidation) begin
                // Preserve provenance: invalidating TEST is not a CAMERA sample.
                // Only a subsequent healthy observation changes the source tag.
                display_item <= 0;
                armed <= 0; absent_count <= 0;
            end else if (sample_valid) begin
                display_source_test <= source_test;
                display_item <= det_present && det_stable && legal_item ? det_item : 4'd0;
                if (source_test) begin armed <= 0; absent_count <= 0; end
                else if (mode == EXPLORE || (mode == QUIZ && phase == WAIT_ANSWER)) begin
                    // Only a healthy real empty record counts. Unknown, illegal
                    // IDs and inconsistent records never impersonate absence.
                    if (!det_present && !det_stable && det_item == 0) begin
                        if (absent_count < ABSENT_SAMPLES) absent_count <= absent_count + 1'b1;
                        if (absent_count >= ABSENT_SAMPLES-1) armed <= 1;
                    end else absent_count <= 0;
                end else begin armed <= 0; absent_count <= 0; end
            end

            // K4 > K1 > active K3 > revoke > pending audio/feedback/K2/answer.
            // Explicit keys cancel the previous audio context; their new event
            // is queued for the next cycle and may itself be revoked later.
            if (key_reset_pulse) begin
                mode <= IDLE; phase <= INACTIVE; score <= 0;
                question_index <= 0; target_item <= 0; wrong_count <= 0;
                question_slot <= 0; next_round_start <= 0;
                feedback <= 0; feedback_count <= 0; armed <= 0; absent_count <= 0;
                audio_cancel <= 1; queue_later(3'd6, 4'd0);
            end else if (key_mode_pulse) begin
                audio_cancel <= 1; pending_event <= 0;
                armed <= 0; absent_count <= 0; feedback <= 0; feedback_count <= 0; wrong_count <= 0;
                if (mode == IDLE) begin mode <= EXPLORE; phase <= INACTIVE; end
                else if (mode == EXPLORE) begin
                    mode <= QUIZ; phase <= WAIT_ANSWER; score <= 0;
                    question_index <= 1; question_slot <= next_round_start;
                    target_item <= next_round_item; queue_later(3'd2, next_round_item);
                    next_round_start <= next_round_start >= QUESTION_COUNT-2 ?
                        next_round_start - (QUESTION_COUNT-2) : next_round_start + 4'd2;
                end else begin
                    mode <= IDLE; phase <= INACTIVE; question_index <= 0; target_item <= 0;
                end
            end else if (key_skip_pulse && quiz_active) begin
                audio_cancel <= 1; advance_question();
            end else if (invalidation) begin
                // No score, question, mode, feedback or retry mutation on revoke.
                // Drop every queued event, including an object-specific question.
                pending_event <= 0; pending_kind <= 0; pending_item <= 0;
                audio_cancel <= 1;
            end else begin
                if (pending_event) begin
                    audio_event_valid <= 1; audio_event_kind <= pending_kind;
                    audio_event_item <= pending_item; pending_event <= 0;
                end
                if (mode == QUIZ && phase == FEEDBACK) begin
                    // K2 cannot restart or stall the feedback timer.
                    if (tick_1ms && feedback_count < FEEDBACK_TICKS)
                        feedback_count <= feedback_count + 1'b1;
                    if ((feedback_count >= FEEDBACK_TICKS ||
                        (tick_1ms && feedback_count >= FEEDBACK_TICKS-1)) &&
                        (audio_idle || audio_fault)) begin
                        armed <= 0; absent_count <= 0; feedback_count <= 0;
                        if (feedback == 2) begin phase <= WAIT_ANSWER; feedback <= 0; end
                        else advance_question();
                    end
                end else if (key_replay_pulse && !pending_event) begin
                    if (mode == QUIZ && phase == WAIT_ANSWER) begin
                        audio_event_valid <= 1; audio_event_kind <= 2; audio_event_item <= target_item;
                    end else if (mode == EXPLORE && replay_item != 0) begin
                        audio_event_valid <= 1; audio_event_kind <= 1; audio_event_item <= replay_item;
                        if (real_answer) begin armed <= 0; absent_count <= 0; end
                    end
                end else if (real_answer && !key_replay_pulse && !pending_event) begin
                    if (mode == EXPLORE) begin
                        armed <= 0; absent_count <= 0;
                        audio_event_valid <= 1; audio_event_kind <= 1; audio_event_item <= det_item;
                    end else if (mode == QUIZ && phase == WAIT_ANSWER) begin
                        armed <= 0; absent_count <= 0; answer_valid <= 1;
                        answer_correct <= det_item == target_item;
                        phase <= FEEDBACK; feedback_count <= 0;
                        audio_event_valid <= 1; audio_event_item <= target_item;
                        if (det_item == target_item) begin
                            if (score < 10) score <= score + 1'b1;
                            feedback <= 1; audio_event_kind <= 3;
                        end else begin
                            wrong_count <= wrong_count + 1'b1;
                            feedback <= wrong_count >= MAX_WRONG-1 ? 3'd3 : 3'd2;
                            audio_event_kind <= 4;
                        end
                    end
                end
            end
        end
    end
    // synthesis translate_off
    initial begin
        if (ABSENT_SAMPLES < 1 || FEEDBACK_TICKS < 1 || MAX_WRONG < 1 || MAX_WRONG > 15)
            $fatal(1, "items14_quiz_control parameter out of supported range");
    end
    // synthesis translate_on
endmodule
