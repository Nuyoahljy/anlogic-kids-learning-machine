`timescale 1ns/1ps
// Independent expectations for the task-local 14-item controller.
// Behavior reference (read-only): E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/
// sc520-fixed-roi/fpga/custom_project/sc520-board-keys/user_source/hdl_source/quiz/quiz_control.v
// Reference SHA256: CD41CB3FBD5F5B698CFE1A5AA7E8FB699F91929112EED97B3D9AF724662B8DD0
module tb_items14_control;
    reg clk=0, rst_n=0, tick_1ms=0;
    reg sample_valid=0, sample_healthy=1, revoke=0;
    reg det_present=0, det_stable=0, source_test=0;
    reg [3:0] det_item=0, keys=0;
    reg audio_idle=1, audio_fault=0;
    wire [1:0] mode, phase;
    wire [3:0] score, question_index, target_item, display_item;
    wire quiz_active, answer_valid, answer_correct, display_source_test, armed;
    wire [2:0] feedback, audio_event_kind;
    wire audio_event_valid, audio_cancel;
    wire [3:0] audio_event_item;
    reg [3:0] bank_index=0;
    wire [3:0] bank_item;
    integer errors=0, checks=0, scenarios=0, injected=0;
    reg test_done=0;
    integer inject_fault=0, ignored;
    reg [3:0] expected_bank[0:15];
    reg [3:0] expected_questions[0:19];
    reg [3:0] expected_starts[0:7];
    reg [15:0] seen_all=0, seen_round=0;
    integer i, j, round_no, q, offset;

    always #5 clk=~clk;
    items14_quiz_control #(.ABSENT_SAMPLES(3), .FEEDBACK_TICKS(3), .MAX_WRONG(2)) dut (
        .clk(clk), .rst_n(rst_n), .tick_1ms(tick_1ms),
        .sample_valid(sample_valid), .sample_healthy(sample_healthy), .revoke(revoke),
        .det_present(det_present), .det_stable(det_stable), .det_item(det_item),
        .source_test(source_test), .key_mode_pulse(keys[0]), .key_replay_pulse(keys[1]),
        .key_skip_pulse(keys[2]), .key_reset_pulse(keys[3]),
        .audio_idle(audio_idle), .audio_fault(audio_fault),
        .mode(mode), .score(score), .question_index(question_index), .target_item(target_item),
        .quiz_active(quiz_active), .answer_valid(answer_valid), .answer_correct(answer_correct),
        .feedback(feedback), .phase(phase), .display_item(display_item),
        .display_source_test(display_source_test), .armed(armed),
        .audio_event_valid(audio_event_valid), .audio_event_kind(audio_event_kind),
        .audio_event_item(audio_event_item), .audio_cancel(audio_cancel)
    );
    items14_question_bank bank(.index(bank_index), .item(bank_item));

    task ck(input reg pass, input string label);
        begin
            checks=checks+1;
            if (pass !== 1'b1) begin
                errors=errors+1;
                $display("FAIL t=%0t case=%0d %s mode=%0d q=%0d target=%0d score=%0d phase=%0d audio=%0d/%0d/%0d",
                    $time,scenarios,label,mode,question_index,target_item,score,phase,
                    audio_event_valid,audio_event_kind,audio_event_item);
            end
        end
    endtask

    task start_case(input string label);
        begin scenarios=scenarios+1; $display("CASE %0d %s",scenarios,label); end
    endtask

    // Keys are {K4 reset, K3 skip, K2 replay, K1 mode}.
    task step(input [3:0] k, input reg sv, healthy, present, stable,
              input [3:0] item, input reg src, rev, tick, idle, fault);
        begin
            @(negedge clk);
            keys=k; sample_valid=sv; sample_healthy=healthy;
            det_present=present; det_stable=stable; det_item=item;
            source_test=src; revoke=rev; tick_1ms=tick; audio_idle=idle; audio_fault=fault;
            @(posedge clk); #1;
            ck((^{mode,phase,score,question_index,target_item,display_item,quiz_active,
                answer_valid,answer_correct,feedback,display_source_test,armed,
                audio_event_valid,audio_event_kind,audio_event_item,audio_cancel}) !== 1'bx,
                "public outputs remain known");
            ck(score<=10 && question_index<=10 && target_item<=14 && display_item<=14,
                "public score/question/item ranges");
            ck(!answer_valid || (mode==2 && phase==2),"answer pulse has quiz feedback context");
            ck(!audio_cancel || (!audio_event_valid && !answer_valid),"cancel never accompanies stale event or answer");
        end
    endtask

    task quiet;
        begin step(0,0,1,0,0,0,0,0,0,1,0); end
    endtask
    task press(input [3:0] k);
        begin step(k,0,1,0,0,0,0,0,0,1,0); end
    endtask
    task sample(input reg present,stable, input [3:0] item, input reg src);
        begin step(0,1,1,present,stable,item,src,0,0,1,0); end
    endtask
    task tick;
        begin step(0,0,1,0,0,0,0,0,1,1,0); end
    endtask
    task expect_audio(input reg valid, input [2:0] kind, input [3:0] item, input string label);
        begin ck(audio_event_valid===valid && audio_event_kind===kind && audio_event_item===item,label); end
    endtask
    task reset_dut;
        begin
            @(negedge clk); rst_n=0; keys=0; sample_valid=0; sample_healthy=1;
            revoke=0; det_present=0; det_stable=0; det_item=0; source_test=0;
            tick_1ms=0; audio_idle=1; audio_fault=0;
            @(posedge clk); #1;
            ck(mode===0 && phase===0 && score===0 && question_index===0 && target_item===0,
                "asynchronous reset initializes session");
            ck(display_item===0 && !display_source_test && !armed && !audio_event_valid && !answer_valid,
                "reset clears observation and pulse state");
            @(negedge clk); rst_n=1;
            @(posedge clk); #1;
        end
    endtask
    task arm_real;
        begin
            sample(0,0,0,0); ck(!armed,"first real absence does not arm");
            sample(0,0,0,0); ck(!armed,"second real absence does not arm");
            sample(0,0,0,0); ck(armed,"third consecutive real absence arms");
            expect_audio(0,0,0,"empty background emits no object audio");
        end
    endtask
    task enter_quiz;
        begin
            reset_dut(); press(1); ck(mode===1,"K1 enters exploration");
            press(1);
            ck(mode===2 && phase===1 && question_index===1 && target_item===1 && score===0,
                "K1 starts first round at explicit item 1");
            ck(audio_cancel && !armed,"round entry cancels old audio and disarms");
            expect_audio(0,0,0,"new question waits one cycle after cancellation");
            quiet(); expect_audio(1,2,1,"first question prompt matches target");
        end
    endtask
    task expect_revoke(input [3:0] q_expected, target_expected, score_expected,
                       input [1:0] phase_expected, input string label);
        begin
            ck(mode===2 && question_index===q_expected && target_item===target_expected &&
                score===score_expected && phase===phase_expected,label);
            ck(display_item===0 && !display_source_test && !armed && dut.absent_count===0,
                "revoke clears recognition and absence history");
            ck(audio_cancel && !answer_valid && !answer_correct && !dut.pending_event,
                "revoke cancels pending event and all same-cycle answer effects");
            expect_audio(0,0,0,"revoke emits no audio event");
        end
    endtask

    initial begin
        ignored=$value$plusargs("INJECT_FAULT=%d",inject_fault);
        // Test oracles are explicit literals, never obtained from the DUT mapping.
        expected_bank[0]=1; expected_bank[1]=10; expected_bank[2]=2; expected_bank[3]=11;
        expected_bank[4]=3; expected_bank[5]=12; expected_bank[6]=4; expected_bank[7]=13;
        expected_bank[8]=5; expected_bank[9]=14; expected_bank[10]=6; expected_bank[11]=7;
        expected_bank[12]=8; expected_bank[13]=9; expected_bank[14]=0; expected_bank[15]=0;
        expected_questions[0]=1; expected_questions[1]=10; expected_questions[2]=2;
        expected_questions[3]=11; expected_questions[4]=3; expected_questions[5]=12;
        expected_questions[6]=4; expected_questions[7]=13; expected_questions[8]=5;
        expected_questions[9]=14; expected_questions[10]=6; expected_questions[11]=7;
        expected_questions[12]=8; expected_questions[13]=9; expected_questions[14]=1;
        expected_questions[15]=10; expected_questions[16]=2; expected_questions[17]=11;
        expected_questions[18]=3; expected_questions[19]=12;
        expected_starts[0]=1; expected_starts[1]=6; expected_starts[2]=4; expected_starts[3]=2;
        expected_starts[4]=8; expected_starts[5]=5; expected_starts[6]=3; expected_starts[7]=1;

        start_case("question bank has fourteen explicit entries and two invalid indices");
        for(i=0;i<16;i=i+1) begin
            bank_index=i; #1; ck(bank_item===expected_bank[i],"independent question-bank table");
        end
        bank_index=4'bx; #1; ck(bank_item===0,"unknown bank index fails closed");

        start_case("reset and one real-output fault injection");
        reset_dut();
        if(inject_fault) begin force dut.display_item=4'd15; injected=injected+1; end
        #1; ck(display_item===4'd0,"reset display output is zero");
        if(inject_fault) release dut.display_item;
        reset_dut();

        start_case("all fourteen real objects in exploration with repeat suppression and K2");
        press(1);
        for(i=1;i<=14;i=i+1) begin
            arm_real(); sample(1,1,i,0);
            ck(display_item===i[3:0] && !display_source_test && !armed && !answer_valid && score===0,
                "exploration shows real item without quiz scoring");
            expect_audio(1,1,i,"exploration announces each real item");
            for(j=0;j<3;j=j+1) begin
                sample(1,1,i,0); expect_audio(0,0,0,"held object is not automatically repeated");
                ck(!answer_valid && score===0,"held exploration object cannot score");
            end
            press(2); expect_audio(1,1,i,"K2 repeats displayed item");
            quiet(); ck(display_item===i[3:0],"clock gaps preserve last healthy display");
        end

        start_case("test-source observations display but never arm or score");
        reset_dut(); press(1);
        for(i=0;i<4;i=i+1) begin sample(0,0,0,1); ck(!armed,"test absence cannot arm"); end
        for(i=1;i<=14;i=i+1) begin
            sample(1,1,i,1);
            ck(display_item===i[3:0] && display_source_test && !armed && !answer_valid && score===0,
                "test item retains source marker and no answer eligibility");
            expect_audio(0,0,0,"test item has no automatic name event");
        end

        start_case("revoked TEST provenance remains TEST until a healthy CAMERA observation");
        sample(1,1,14,1);
        ck(display_source_test && display_item===14,"healthy TEST object establishes provenance");
        step(0,0,1,0,0,0,0,1,0,1,0);
        ck(display_source_test && display_item===0 && !armed && dut.absent_count===0 && audio_cancel,
            "sample-free revoke clears object but preserves TEST source tag");
        expect_audio(0,0,0,"revoked TEST object produces no audio");
        quiet(); ck(display_source_test && display_item===0,"idle cycle cannot relabel revoked TEST as CAMERA");
        step(0,1,1,1,1,6,0,1,0,1,0);
        ck(display_source_test && display_item===0 && !armed && audio_cancel,
            "coincident revoke rejects even a healthy CAMERA source update");
        step(0,1,0,1,1,6,0,0,0,1,0);
        ck(display_source_test && display_item===0 && !armed && audio_cancel,
            "unhealthy CAMERA observation cannot replace last healthy TEST provenance");
        sample(1,1,6,0);
        ck(!display_source_test && display_item===6 && !armed && !answer_valid && !audio_cancel,
            "subsequent healthy CAMERA observation updates source tag without arming");
        expect_audio(0,0,0,"source recovery still needs new real absence to announce");
        arm_real(); sample(0,0,0,1); ck(!armed && dut.absent_count===0,"test source revokes existing arm");

        start_case("unknown and inconsistent records interrupt consecutive absence");
        sample(0,0,0,0); sample(0,0,0,0); sample(1,0,0,0);
        ck(!armed && dut.absent_count===0,"present unknown is not an empty background");
        sample(0,0,0,0); sample(0,0,0,0); sample(0,0,15,0);
        ck(!armed && dut.absent_count===0,"nonzero item in absent record is not empty");
        sample(0,0,0,0); sample(0,0,0,0); sample(1,1,15,0);
        ck(!armed && display_item===0,"reserved item 15 cannot arm or display");
        sample(0,0,0,0); sample(0,0,0,0); sample(1,1,0,0);
        ck(!armed && display_item===0,"stable item zero cannot impersonate an object");
        arm_real();
        for(i=0;i<6;i=i+1) sample(0,0,0,0);
        ck(armed && dut.absent_count===3,"absence counter saturates after arming");

        start_case("two full ten-question rounds cover all fourteen without per-round duplicates");
        enter_quiz();
        for(round_no=0;round_no<2;round_no=round_no+1) begin
            seen_round=0;
            if(round_no==1) begin
                press(1); ck(mode===0,"K1 leaves finished quiz");
                press(1); ck(mode===1,"K1 returns to exploration");
                press(1); ck(target_item===6 && question_index===1 && score===0,"next round begins at explicit item 6");
                quiet(); expect_audio(1,2,6,"next-round first prompt matches new target");
            end
            for(q=1;q<=10;q=q+1) begin
                offset=round_no*10+q-1;
                ck(mode===2 && phase===1 && quiz_active && question_index===q[3:0] &&
                    target_item===expected_questions[offset],"explicit target for every question");
                ck(!seen_round[expected_questions[offset]],"no repeated target in a ten-question round");
                seen_round[expected_questions[offset]]=1; seen_all[expected_questions[offset]]=1;
                sample(1,1,expected_questions[offset],1);
                ck(!answer_valid && !armed && score==q-1,"test-source correct item cannot score");
                arm_real();
                step(2,1,1,1,1,expected_questions[offset],0,0,0,1,0);
                expect_audio(1,2,expected_questions[offset],"K2 and correct item replays this question");
                ck(!answer_valid && phase===1 && score==q-1,"K2 wins over a simultaneous correct answer");
                sample(1,1,expected_questions[offset],0);
                ck(answer_valid && answer_correct && score===q[3:0] && phase===2 && feedback===1 && !armed,
                    "correct real item scores exactly once");
                expect_audio(1,3,expected_questions[offset],"correct feedback carries same target item");
                sample(1,1,expected_questions[offset],0);
                ck(!answer_valid && score===q[3:0],"held correct answer cannot score twice");
                expect_audio(0,0,0,"feedback ignores held object");
                tick(); tick();
                step(2,0,1,0,0,0,0,0,1,1,0);
                ck(score===q[3:0] && !armed,"feedback advances without changing score or arming");
                expect_audio(0,0,0,"feedback K2 cannot steal next-prompt scheduling");
                if(q<10) begin
                    ck(question_index==q+1 && target_item===expected_questions[offset+1] && phase===1,
                        "feedback advance and target stay aligned");
                    quiet(); expect_audio(1,2,expected_questions[offset+1],"advance prompt uses exact next item");
                end else begin
                    ck(phase===3 && !quiz_active && question_index===10 && score===10,
                        "tenth answer finishes at ten points");
                    quiet(); expect_audio(1,7,0,"completion event is emitted once");
                    sample(1,1,expected_questions[offset],0);
                    ck(!answer_valid && score===10 && phase===3,"finished quiz cannot score further");
                    press(6); expect_audio(0,0,0,"skip and replay are inert after completion");
                end
            end
        end
        ck(seen_all===16'h7ffe,"two-round union contains every item 1 through 14");

        start_case("seven-round starting-position cycle and restart at the first item");
        reset_dut(); press(1);
        for(i=0;i<8;i=i+1) begin
            press(1);
            ck(mode===2 && phase===1 && question_index===1 && target_item===expected_starts[i] && score===0,
                "explicit starting item follows full modulo-fourteen rotation");
            quiet(); expect_audio(1,2,expected_starts[i],"each rotated first prompt matches target");
            press(1); ck(mode===0,"K1 can leave an unfinished round");
            press(1); ck(mode===1,"return to exploration before next rotating round");
        end

        start_case("wrong answer retry, busy-audio wait, and audio-fault progress");
        enter_quiz(); arm_real(); sample(1,1,2,0);
        ck(answer_valid && !answer_correct && feedback===2 && score===0 && phase===2,
            "first wrong answer selects retry without a point");
        expect_audio(1,4,1,"wrong-answer audio is bound to asked target");
        for(i=0;i<6;i=i+1) step(2,0,1,0,0,0,0,0,1,0,0);
        ck(phase===2 && question_index===1 && score===0,"busy audio holds completed feedback timer");
        step(0,0,1,0,0,0,0,0,0,0,1);
        ck(phase===1 && feedback===0 && question_index===1 && target_item===1 && !armed,
            "audio fault releases feedback into same-question retry");
        sample(1,1,1,0); ck(!answer_valid && score===0,"retry needs a new absence sequence");
        arm_real(); sample(1,1,3,0);
        ck(answer_valid && !answer_correct && feedback===3 && score===0,"second wrong answer reveals answer");
        tick(); tick(); tick();
        ck(phase===1 && question_index===2 && target_item===10 && score===0,"wrong limit advances without points");
        quiet(); expect_audio(1,2,10,"after wrong limit next prompt is the new card item");

        start_case("skip during feedback and waiting never adds a point");
        arm_real(); sample(1,1,10,0); ck(score===1 && phase===2,"prepare scored feedback before skip");
        press(4); ck(question_index===3 && target_item===2 && phase===1 && score===1 && audio_cancel,
            "K3 ends feedback and keeps earned score");
        quiet(); expect_audio(1,2,2,"skip queues next matching prompt");
        arm_real(); step(6,1,1,1,1,2,0,1,0,1,0);
        ck(question_index===4 && target_item===11 && score===1 && !answer_valid && audio_cancel,
            "K3 wins over revoke, replay and correct answer without scoring");
        ck(display_item===0 && !armed,"coincident revoke still clears recognition under K3");
        quiet(); expect_audio(1,2,11,"higher-priority skip may queue only its new context");

        start_case("revoke suppresses same-cycle correct answer and K2 in waiting");
        enter_quiz(); arm_real();
        step(2,1,1,1,1,1,0,1,0,1,0);
        expect_revoke(1,1,0,1,"explicit revoke preserves waiting question and score");
        sample(1,1,1,0); ck(!answer_valid && score===0,"post-revoke object needs fresh absence");
        arm_real();
        step(2,1,0,1,1,1,0,0,0,1,0);
        expect_revoke(1,1,0,1,"unhealthy observation also suppresses answer and replay");
        sample(0,0,0,0); sample(0,0,0,0);
        step(0,0,1,0,0,0,0,1,0,1,0);
        expect_revoke(1,1,0,1,"sample-free revoke discards partial absence history");
        sample(0,0,0,0); ck(!armed && dut.absent_count===1,"absence must restart after revoke");

        start_case("revoke drops pending object-specific question prompt");
        reset_dut(); press(1); press(1);
        ck(dut.pending_event,"round entry has a queued prompt");
        step(2,0,1,0,0,0,0,1,0,1,0);
        expect_revoke(1,1,0,1,"queued prompt revoke leaves target intact");
        quiet(); expect_audio(0,0,0,"revoked pending prompt never escapes one cycle later");
        press(2); expect_audio(1,2,1,"later deliberate K2 uses current preserved target");

        start_case("revoke on feedback deadline freezes session while clearing recognition");
        arm_real(); sample(1,1,1,0); tick(); tick();
        ck(dut.feedback_count===2,"prepare one tick before feedback deadline");
        for(i=0;i<5;i=i+1) begin
            step(2,1,0,1,1,1,0,0,1,1,0);
            expect_revoke(1,1,1,2,"held untrusted input cannot advance or rescore feedback");
            ck(feedback===1 && dut.feedback_count===2,"revoke preserves feedback value and remaining timer");
        end
        tick(); ck(question_index===2 && target_item===10 && score===1 && phase===1,
            "feedback resumes from remaining tick after healthy timing returns");
        quiet(); expect_audio(1,2,10,"resumed feedback sends matching next prompt");

        start_case("exploration revoke prevents stale display replay and automatic reuse");
        reset_dut(); press(1); arm_real(); sample(1,1,14,0);
        step(2,0,1,0,0,0,0,1,0,1,0);
        ck(mode===1 && display_item===0 && !armed && audio_cancel && !answer_valid,
            "sample-free exploration revoke clears display and eligibility");
        expect_audio(0,0,0,"same-edge stale replay is suppressed");
        press(2); expect_audio(0,0,0,"later replay has no stale object");
        sample(1,1,14,0); expect_audio(0,0,0,"object after revoke is not automatically announced without removal");
        arm_real(); sample(1,1,14,0); expect_audio(1,1,14,"fresh absence restores exploration announcement");
        step(0,0,0,0,0,0,0,0,0,1,0);
        ck(display_item===14 && !audio_cancel,"healthy bit is ignored when sample_valid is zero");

        start_case("four-key priority with revoke and reset of rotating start");
        enter_quiz(); arm_real(); sample(1,1,1,0);
        step(15,1,0,1,1,1,0,1,1,1,0);
        ck(mode===0 && phase===0 && question_index===0 && target_item===0 && score===0 && audio_cancel,
            "K4 wins over K1 K3 K2 revoke and feedback deadline");
        ck(display_item===0 && !armed,"reset plus revoke clears old observation");
        quiet(); expect_audio(1,6,0,"reset queues only reset audio");
        press(1);
        step(7,1,0,1,1,14,0,1,0,1,0);
        ck(mode===2 && question_index===1 && target_item===1 && score===0 && audio_cancel,
            "K1 beats K3 and revoke and reset returned round start to item 1");
        quiet(); expect_audio(1,2,1,"K1 emits prompt for its new question context");
        step(7,0,1,0,0,0,0,1,0,1,0);
        ck(mode===0 && question_index===0 && target_item===0,"K1 exits quiz rather than skipping under revoke");
        quiet(); expect_audio(0,0,0,"mode exit leaves no old pending prompt");
        press(1); press(1); quiet(); expect_audio(1,2,6,"even an aborted round rotates the next start by ten");
        press(8); quiet(); press(1); press(1); quiet();
        expect_audio(1,2,1,"K4 resets future round rotation to explicit item 1");

        start_case("ten explicit skips finish at zero and issue only one completion event");
        for(q=1;q<=10;q=q+1) begin
            ck(question_index===q[3:0] && target_item===expected_questions[q-1],"skip-only round target order");
            press(4); ck(score===0 && !answer_valid && audio_cancel,"skip never produces a point or answer");
            quiet();
            if(q<10) expect_audio(1,2,expected_questions[q],"skip prompt matches explicit next item");
            else expect_audio(1,7,0,"tenth skip sends completion event");
        end
        ck(phase===3 && !quiz_active && question_index===10 && score===0,"zero-point ten-question completion");
        press(4); expect_audio(0,0,0,"extra skip cannot repeat completion");
        quiet(); expect_audio(0,0,0,"completion is a single pulse");
        ck(!inject_fault || injected===1,"negative run forced one actual DUT output exactly once");
        ck(inject_fault || injected===0,"normal run contains no fault injection");
        test_done=1;
        $display("RESULT tb_items14_control errors=%0d checks=%0d scenarios=%0d injected=%0d",errors,checks,scenarios,injected);
        $finish;
    end

    initial begin
        #1000000;
        errors=errors+1;
        $display("WATCHDOG tb_items14_control errors=%0d checks=%0d scenarios=%0d",errors,checks,scenarios);
        $finish;
    end
endmodule
