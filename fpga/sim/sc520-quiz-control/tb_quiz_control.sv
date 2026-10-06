`timescale 1ns/1ps
// Independent behavioral checks for the local quiz-control proposal.
// Camera recognition is mocked at its result interface; this is not an accuracy test.
module tb_quiz_control;
    localparam integer FB_TICKS = 4;
    localparam [3:0] K_MODE=1, K_REPLAY=2, K_SKIP=4, K_RESET=8;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0, tick_1ms=0, sample_valid=0, det_present=0, det_stable=0;
    reg [3:0] det_item=0;
    reg source_test=0;
    reg key_mode_pulse=0, key_replay_pulse=0, key_skip_pulse=0, key_reset_pulse=0;
    reg audio_idle=1, audio_fault=0;
    wire [1:0] mode, phase;
    wire [3:0] score, question_index, target_item, display_item, audio_event_item;
    wire quiz_active, answer_valid, answer_correct, display_source_test, armed;
    wire [2:0] feedback, audio_event_kind;
    wire audio_event_valid, audio_cancel;
    integer errors=0, checks=0, cases=0, cycles=0;
    integer answer_count=0, correct_count=0, cancel_count=0;
    integer event_count[0:7];
    integer coverage_items=0, trace_fd=0;
    reg test_done=0, previous_answer=0;
    reg [3:0] previous_score=0;
    string trace_path;

    quiz_control #(.ABSENT_SAMPLES(3), .FEEDBACK_TICKS(FB_TICKS), .MAX_WRONG(2)) dut (
        .clk(clk), .rst_n(rst_n), .tick_1ms(tick_1ms), .sample_valid(sample_valid),
        .det_present(det_present), .det_stable(det_stable), .det_item(det_item),
        .source_test(source_test), .key_mode_pulse(key_mode_pulse),
        .key_replay_pulse(key_replay_pulse), .key_skip_pulse(key_skip_pulse),
        .key_reset_pulse(key_reset_pulse), .audio_idle(audio_idle), .audio_fault(audio_fault),
        .mode(mode), .score(score), .question_index(question_index), .target_item(target_item),
        .quiz_active(quiz_active), .answer_valid(answer_valid), .answer_correct(answer_correct),
        .feedback(feedback), .phase(phase), .display_item(display_item),
        .display_source_test(display_source_test), .armed(armed),
        .audio_event_valid(audio_event_valid), .audio_event_kind(audio_event_kind),
        .audio_event_item(audio_event_item), .audio_cancel(audio_cancel)
    );

    task automatic verify(input bit condition, input string label_text);
        begin
            checks=checks+1;
            if (condition !== 1'b1) begin
                errors=errors+1;
                $display("FAIL cycle=%0d case=%0d %s mode=%0d phase=%0d q=%0d target=%0d score=%0d arm=%b", cycles,cases,label_text,mode,phase,question_index,target_item,score,armed);
            end
        end
    endtask

    task automatic mark_case(input string label_text);
        begin cases=cases+1; $display("CASE %0d %s",cases,label_text); end
    endtask

    // All stimuli change at falling edges; samples/ticks are independent strobes.
    task automatic drive(input bit sv, input bit present, input bit stable,
                         input integer item, input bit test_source,
                         input integer keys, input bit tick);
        begin
            @(negedge clk);
            sample_valid=sv; det_present=present; det_stable=stable; det_item=item;
            source_test=test_source; tick_1ms=tick;
            key_mode_pulse=keys[0]; key_replay_pulse=keys[1];
            key_skip_pulse=keys[2]; key_reset_pulse=keys[3];
            @(posedge clk); #2;
        end
    endtask

    task automatic idle_cycles(input integer count);
        integer k;
        begin for(k=0;k<count;k=k+1) drive(0,0,0,0,0,0,0); end
    endtask
    task automatic ticks(input integer count);
        integer k;
        begin for(k=0;k<count;k=k+1) drive(0,0,0,0,0,0,1); end
    endtask
    task automatic sample(input bit present,input bit stable,input integer item,input bit src);
        begin drive(1,present,stable,item,src,0,0); end
    endtask
    task automatic keys(input integer mask);
        begin drive(0,0,0,0,0,mask,0); end
    endtask
    task automatic remove_object;
        begin sample(0,0,0,0); sample(0,0,0,0); sample(0,0,0,0); verify(armed,"three trusted absent samples arm"); end
    endtask
    task automatic place(input integer item);
        begin sample(1,1,item,0); end
    endtask

    task automatic fresh_quiz;
        begin
            keys(K_RESET); idle_cycles(1);
            keys(K_MODE); idle_cycles(1);
            verify(mode==1 && score==0,"fresh exploration before quiz");
            keys(K_MODE);
            verify(mode==2 && question_index==1 && target_item==1 && phase==1 && quiz_active,"quiz begins at first question");
            verify(audio_cancel && !audio_event_valid,"quiz entry cancels before new question event");
            idle_cycles(1);
            verify(audio_event_valid && audio_event_kind==2 && audio_event_item==1,"question arrives one clock after entry");
            idle_cycles(1);
        end
    endtask

    task automatic finish_feedback;
        integer k;
        begin
            for(k=0;k<FB_TICKS+2;k=k+1) ticks(1);
            idle_cycles(2);
            verify(phase!=2,"feedback completed after required ticks and audio idle/fault");
        end
    endtask

    always @(posedge clk) begin
        #1;
        cycles=cycles+1;
        if(rst_n && !test_done) begin
            verify(score<=10,"score always within 0..10");
            verify(mode<=2,"mode encoding is legal");
            verify(!(audio_cancel && audio_event_valid),"cancel and new audio event never overlap");
            verify(!(previous_answer && answer_valid),"answer is one cycle only");
            if(score>previous_score)
                verify(answer_valid && answer_correct && score==previous_score+1,"every score increment has exactly one correct answer");
            if(score<previous_score)
                verify(score==0 && (key_reset_pulse || (key_mode_pulse && mode==2)),"score decreases only on explicit reset or a new round");
            if(mode==2) begin
                verify(question_index>=1 && question_index<=10,"quiz question index is 1..10");
                verify(target_item==((question_index==10)?1:question_index),"preset question target sequence");
                verify(quiz_active==(phase!=3),"active deasserts exactly on finished round");
            end else begin
                verify(question_index==0 && target_item==0 && !quiz_active,"non-quiz has no question");
            end
            if(answer_valid) begin
                answer_count=answer_count+1;
                if(answer_correct) correct_count=correct_count+1;
                verify(mode==2 && phase==2,"answer enters feedback in quiz");
                verify(sample_valid && det_present && det_stable && !source_test && det_item>=1 && det_item<=9,"only a real supported stable sample may answer");
                verify(feedback==(answer_correct?1:((feedback==3)?3:2)),"feedback agrees with answer result");
                verify(audio_event_valid && audio_event_kind==(answer_correct?3:4),"answer produces matching audio event");
                verify(score==(answer_correct?(previous_score+1):previous_score),"answer applies exactly the specified score delta");
                coverage_items=coverage_items | (1 << (det_item-1));
            end
            if(audio_event_valid) event_count[audio_event_kind]=event_count[audio_event_kind]+1;
            if(audio_cancel) cancel_count=cancel_count+1;
            if(trace_fd!=0)
                $fdisplay(trace_fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",cycles,mode,phase,question_index,target_item,score,feedback,display_item,display_source_test,armed,audio_fault,answer_valid,answer_correct,audio_event_valid,audio_event_kind);
        end
        previous_answer=answer_valid;
        previous_score=score;
    end

    integer i,j,a0,c0,e0,q0,expected_score,expected_item;
    initial begin
        for(i=0;i<8;i=i+1) event_count[i]=0;
        if($value$plusargs("TRACE=%s",trace_path)) begin
            trace_fd=$fopen(trace_path,"w");
            if(trace_fd==0) begin $display("FAIL unable to open trace"); errors=errors+1; end
            else $fdisplay(trace_fd,"cycle,mode,phase,question,target,score,feedback,item,source_test,armed,audio_fault,answer_valid,answer_correct,event_valid,event_kind");
        end
        mark_case("reset and idle do not score or automatically explore");
        idle_cycles(3); rst_n=1; idle_cycles(2);
        verify(mode==0 && phase==0 && score==0 && !armed,"reset state");
        a0=answer_count; e0=event_count[1];
        for(i=1;i<=9;i=i+1) place(i);
        verify(mode==0 && answer_count==a0 && event_count[1]==e0,"stable input in idle does not start a mode");

        mark_case("exploration old object, independent sample cadence, all nine names, hold dedup");
        keys(K_MODE); idle_cycles(1); place(1);
        verify(event_count[1]==e0 && !armed,"object already present at exploration entry is blocked");
        sample(0,0,0,0); idle_cycles(8);
        verify(!armed,"clocks without samples cannot count absence");
        sample(0,0,0,0); verify(!armed,"two absent samples not enough");
        sample(0,0,0,0); verify(armed,"third absent sample arms despite clock gaps");
        for(i=1;i<=9;i=i+1) begin
            if(i!=1) remove_object();
            place(i);
            verify(audio_event_valid && audio_event_kind==1 && audio_event_item==i,"name event maps every item");
            verify(display_item==i && !display_source_test,"real sample updates item display");
            e0=event_count[1];
            place(i); sample(1,0,0,0); place((i%9)+1);
            verify(event_count[1]==e0 && !armed,"hold, unknown and class change do not replay name");
        end

        mark_case("explore replay uses same-clock sample and merges first-placement event");
        drive(1,1,1,2,0,K_REPLAY,0);
        verify(audio_event_valid && audio_event_kind==1 && audio_event_item==2,"same-clock class change and replay uses new item");
        e0=event_count[1];
        drive(1,1,0,0,0,K_REPLAY,0);
        verify(event_count[1]==e0 && !audio_event_valid && display_item==0,"unknown sample plus replay does not speak stale item");
        remove_object(); e0=event_count[1];
        drive(1,1,1,3,0,K_REPLAY,0);
        verify(event_count[1]==e0+1 && audio_event_item==3 && !armed,"first stable item and replay merge and consume placement");
        place(3);
        verify(event_count[1]==e0+1 && !audio_event_valid,"merged exploration replay cannot auto-trigger again next clock");

        mark_case("quiz entered with old object and untrusted absences");
        keys(K_MODE); idle_cycles(2); a0=answer_count;
        for(i=1;i<=9;i=i+1) place(i);
        verify(answer_count==a0 && !armed && score==0,"old object and continuous color changes cannot answer first question");
        sample(0,0,0,0); sample(0,0,0,0);
        sample(1,0,0,0); sample(0,0,0,0); sample(0,0,0,0);
        verify(!armed,"unknown presence interrupts consecutive absence");
        sample(0,1,1,0); sample(0,0,0,0); sample(0,0,0,0);
        verify(!armed && answer_count==a0,"contradictory absent stable sample neither arms nor answers");
        sample(0,0,0,1); sample(0,0,0,0); sample(0,0,0,0);
        verify(!armed,"test-source absence cannot complete trusted removal");
        sample(0,0,0,0); verify(armed,"three real absences after test source recover");
        sample(1,1,1,1);
        verify(!armed && answer_count==a0 && score==0 && display_item==1 && display_source_test,"simulation source displays but revokes scoring permission");
        place(1); verify(answer_count==a0,"return to real source without new removal is blocked");
        remove_object();
        sample(0,1,1,0); verify(answer_count==a0,"contradictory stable sample cannot answer even when armed");
        for(i=10;i<=15;i=i+1) sample(1,1,i,0);
        verify(answer_count==a0 && display_item==0,"unsupported IDs do not answer or display supported object");
        remove_object(); place(1);
        verify(answer_valid && answer_correct && score==1 && feedback==1,"first correct answer increments once");

        mark_case("feedback respects minimum tick time and waits audio, then fault permits progress");
        audio_idle=0; a0=answer_count;
        place(1); place(2); idle_cycles(15);
        verify(phase==2 && answer_count==a0 && score==1,"clocks and held targets cannot finish feedback or rescore");
        for(i=0;i<FB_TICKS+3;i=i+1) drive(0,0,0,0,0,K_REPLAY,1);
        verify(phase==2 && score==1,"audio busy holds feedback after timer despite replay");
        audio_fault=1; ticks(1); idle_cycles(2);
        verify(question_index==2 && phase==1 && !armed,"audio fault releases completed feedback to next question");
        audio_fault=0; audio_idle=1;
        place(2); verify(answer_count==a0,"new question rejects old target still in picture");

        mark_case("first wrong retries same question, no automatic question replay, then correct");
        remove_object(); place(3);
        verify(answer_valid && !answer_correct && score==1 && feedback==2,"first wrong has retry feedback and no penalty");
        e0=event_count[2];
        ticks(FB_TICKS-1); verify(phase==2,"feedback cannot end before minimum tick count");
        finish_feedback();
        verify(question_index==2 && phase==1 && !armed && event_count[2]==e0,"retry clears arm and does not auto replay question");
        a0=answer_count; place(2); verify(answer_count==a0,"same old placement cannot retry");
        remove_object(); place(2); verify(score==2 && answer_correct,"correct retry earns one point");
        finish_feedback(); verify(question_index==3,"correct retry advances to next question");

        mark_case("second wrong reveals answer; skip during feedback wins over replay and sample");
        remove_object(); place(1); finish_feedback(); remove_object(); place(2);
        verify(feedback==3 && score==2 && question_index==3,"second wrong reveals without scoring");
        a0=answer_count;
        drive(1,1,1,3,0,K_SKIP|K_REPLAY,1);
        verify(question_index==4 && phase==1 && score==2 && audio_cancel && !audio_event_valid,"skip takes priority during feedback");
        verify(answer_count==a0 && !armed,"skip and sample cannot answer same clock");
        idle_cycles(1); verify(audio_event_valid && audio_event_kind==2 && audio_event_item==4,"skip publishes next question after cancel");

        mark_case("clear beats all keys and sample; mode beats skip/replay/sample");
        drive(1,1,1,4,0,15,1);
        verify(mode==0 && score==0 && phase==0 && audio_cancel && !answer_valid,"clear wins over all concurrent actions");
        drive(1,1,1,1,0,K_MODE|K_SKIP|K_REPLAY,1);
        verify(mode==1 && !answer_valid && !audio_event_valid,"mode wins from idle");
        drive(1,1,1,1,0,K_MODE|K_SKIP|K_REPLAY,1);
        verify(mode==2 && question_index==1 && !answer_valid && !audio_event_valid,"mode wins entering quiz");
        e0=event_count[2]; keys(K_REPLAY);
        verify(event_count[2]==e0+1 && audio_event_valid && audio_event_kind==2,"pending question and replay merge into one event");
        idle_cycles(2); verify(event_count[2]==e0+1,"merged replay has no delayed duplicate");

        mark_case("skip wins over replay/sample; replay wins over answer without consuming placement");
        remove_object(); a0=answer_count;
        drive(1,1,1,1,0,K_SKIP|K_REPLAY,0);
        verify(question_index==2 && score==0 && answer_count==a0 && audio_cancel && !audio_event_valid,"skip wins in wait state");
        idle_cycles(2); remove_object(); e0=event_count[2];
        drive(1,1,1,2,0,K_REPLAY,0);
        verify(answer_count==a0 && armed && event_count[2]==e0+1,"replay suppresses same-clock answer but preserves arm");
        verify(audio_event_item==2,"replay targets current question");
        place(2); verify(answer_count==a0+1 && score==1,"later real sample answers after replay");
        for(i=0;i<FB_TICKS+2;i=i+1) drive(0,0,0,0,0,K_REPLAY,1);
        idle_cycles(2);
        verify(question_index==3 && phase==1,"replay during feedback cannot freeze timer");

        mark_case("mode exit preserves score; clear and reset discard pending/active behavior");
        keys(K_MODE); verify(mode==0 && score==1 && question_index==0 && target_item==0 && audio_cancel,"mode exit retains score only");
        keys(K_RESET); verify(score==0,"clear resets retained score");
        fresh_quiz(); remove_object(); place(1); audio_idle=0;
        @(negedge clk); rst_n=0; #2;
        verify(mode==0 && score==0 && phase==0 && !answer_valid,"asynchronous reset during audio-busy feedback");
        idle_cycles(2); rst_n=1; audio_idle=1; idle_cycles(2);
        verify(!audio_event_valid && !armed,"reset does not emit stale audio or arm");

        mark_case("complete all-correct ten-question round covers nine IDs and score upper bound");
        fresh_quiz(); a0=answer_count; c0=correct_count; e0=event_count[7];
        for(i=1;i<=10;i=i+1) begin
            expected_item=(i==10)?1:i;
            verify(question_index==i && target_item==expected_item,"correct round question sequence");
            remove_object(); place(expected_item);
            verify(score==i && answer_correct,"all-correct round accumulates exactly one point");
            place(expected_item); place((expected_item%9)+1);
            verify(score==i,"held/change target does not score twice");
            finish_feedback();
        end
        verify(score==10 && phase==3 && !quiz_active && question_index==10,"round ends at ten points and ten questions");
        verify(answer_count==a0+10 && correct_count==c0+10 && event_count[7]==e0+1,"exactly ten answers and one completion event");
        for(i=1;i<=9;i=i+1) begin remove_object_finished(); place(i); keys(K_SKIP|K_REPLAY); ticks(1); end
        verify(score==10 && phase==3 && answer_count==a0+10 && event_count[7]==e0+1,"finished round cannot overflow score or restart by skip/replay");
        keys(K_MODE); verify(mode==0 && score==10,"finished mode exit preserves total");
        keys(K_MODE); idle_cycles(1); keys(K_MODE); idle_cycles(2);
        verify(score==0 && question_index==1 && phase==1,"new round resets ten-point previous total");

        mark_case("all-wrong round uses exactly two attempts per question and ends at zero");
        fresh_quiz(); a0=answer_count; c0=correct_count; e0=event_count[7];
        for(i=1;i<=10;i=i+1) begin
            expected_item=(i==10)?1:i;
            for(j=1;j<=2;j=j+1) begin
                remove_object(); place((expected_item%9)+1);
                verify(score==0 && !answer_correct && feedback==((j==1)?2:3),"wrong attempt feedback and zero lower bound");
                finish_feedback();
                if(j==1) verify(question_index==i && phase==1,"first wrong keeps same question");
            end
        end
        verify(phase==3 && score==0 && answer_count==a0+20 && correct_count==c0 && event_count[7]==e0+1,"all-wrong round ends after twenty attempts");

        mark_case("all-skipped round ends without answer events or points");
        fresh_quiz(); a0=answer_count; e0=event_count[7];
        for(i=1;i<=10;i=i+1) begin keys(K_SKIP); verify(audio_cancel && !audio_event_valid,"each skip cancels first"); idle_cycles(2); end
        verify(phase==3 && score==0 && answer_count==a0 && event_count[7]==e0+1,"ten skips finish zero-score round");

        mark_case("mixed correct and skip round yields five points with audio fault continuously active");
        fresh_quiz(); audio_idle=0; audio_fault=1; expected_score=0;
        for(i=1;i<=10;i=i+1) begin
            if(i%2) begin
                remove_object(); place((i==10)?1:i); expected_score=expected_score+1;
                finish_feedback();
            end else begin keys(K_SKIP); idle_cycles(2); end
            verify(score==expected_score,"mixed round score equals accepted correct answers");
        end
        verify(phase==3 && score==5,"faulting audio does not freeze mixed round");
        audio_idle=1; audio_fault=0;

        mark_case("checker negative control and final coverage");
        verify(coverage_items==511,"all nine supported IDs participated in scored answers");
        if($test$plusargs("NEGATIVE")) begin
            // Deliberately wrong expectation: the exact same checker must reject it.
            verify(score==9,"NEGATIVE_CONTROL expected false score assertion");
        end
        test_done=1;
        $display("SUMMARY checks=%0d errors=%0d cases=%0d cycles=%0d answers=%0d correct=%0d item_mask=%0d test_done=%0d",checks,errors,cases,cycles,answer_count,correct_count,coverage_items,test_done);
        if(trace_fd!=0) $fclose(trace_fd);
        #10; $finish;
    end

    task automatic remove_object_finished;
        begin sample(0,0,0,0); sample(0,0,0,0); sample(0,0,0,0); verify(!armed,"finished phase never rearms"); end
    endtask

    initial begin
        #1000000;
        if(!test_done) begin errors=errors+1; test_done=1; $display("FAIL watchdog timeout"); $display("SUMMARY checks=%0d errors=%0d test_done=%0d",checks,errors,test_done); $finish; end
    end
endmodule
