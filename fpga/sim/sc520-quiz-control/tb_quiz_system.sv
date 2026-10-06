`timescale 1ns/1ps
// End-to-end local control + audio queue test. Player responses are deliberate
// test stimuli: code 0=end, 1=definitely not executed, 2=ACK, 3=stop confirmed.
module tb_quiz_system;
    localparam integer FB=4, WAIT_LIMIT=8, PLAY_LIMIT=12, STOP_LIMIT=6;
    localparam [3:0] K_MODE=1, K_REPLAY=2, K_SKIP=4, K_RESET=8;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0,tick_1ms=0,sample_valid=0,det_present=0,det_stable=0,source_test=0;
    reg [3:0] det_item=0;
    reg key_mode_pulse=0,key_replay_pulse=0,key_skip_pulse=0,key_reset_pulse=0;
    wire [1:0] mode,phase;
    wire [3:0] score,question_index,target_item,display_item,audio_event_item;
    wire quiz_active,answer_valid,answer_correct,display_source_test,armed;
    wire [2:0] feedback,audio_event_kind;
    wire audio_event_valid,audio_cancel,audio_idle,audio_fault,audio_overflow;
    wire req_valid,stop_valid;
    wire [2:0] req_kind;
    wire [3:0] req_item;
    wire [15:0] req_tag,stop_tag;
    reg req_ready=0,device_busy=0,rsp_valid=0;
    reg [15:0] rsp_tag=0;
    reg [1:0] rsp_code=0;
    integer errors=0,checks=0,cases=0,cycles=0,accepted=0,answers=0;
    integer accepted_kind[0:255],accepted_item[0:255];
    reg [15:0] accepted_tag[0:255];
    reg [15:0] mock_active_tag=0;
    reg [3:0] previous_score=0;
    reg previous_answer=0,test_done=0;
    integer trace_fd=0;
    string trace_path;

    quiz_control #(.ABSENT_SAMPLES(3),.FEEDBACK_TICKS(FB),.MAX_WRONG(2)) control (
        .clk(clk),.rst_n(rst_n),.tick_1ms(tick_1ms),.sample_valid(sample_valid),
        .det_present(det_present),.det_stable(det_stable),.det_item(det_item),.source_test(source_test),
        .key_mode_pulse(key_mode_pulse),.key_replay_pulse(key_replay_pulse),
        .key_skip_pulse(key_skip_pulse),.key_reset_pulse(key_reset_pulse),
        .audio_idle(audio_idle),.audio_fault(audio_fault),.mode(mode),.score(score),
        .question_index(question_index),.target_item(target_item),.quiz_active(quiz_active),
        .answer_valid(answer_valid),.answer_correct(answer_correct),.feedback(feedback),.phase(phase),
        .display_item(display_item),.display_source_test(display_source_test),.armed(armed),
        .audio_event_valid(audio_event_valid),.audio_event_kind(audio_event_kind),
        .audio_event_item(audio_event_item),.audio_cancel(audio_cancel)
    );
    quiz_audio_queue #(.DEPTH(8),.WAIT_TICKS(WAIT_LIMIT),.PLAY_TICKS(PLAY_LIMIT),.STOP_TICKS(STOP_LIMIT)) audio_queue (
        .clk(clk),.rst_n(rst_n),.tick_1ms(tick_1ms),.cancel(audio_cancel),
        .event_valid(audio_event_valid),.event_kind(audio_event_kind),.event_item(audio_event_item),
        .idle(audio_idle),.fault(audio_fault),.overflow(audio_overflow),
        .req_valid(req_valid),.req_kind(req_kind),.req_item(req_item),.req_tag(req_tag),
        .req_ready(req_ready),.device_busy(device_busy),.rsp_valid(rsp_valid),
        .rsp_tag(rsp_tag),.rsp_code(rsp_code),.stop_valid(stop_valid),.stop_tag(stop_tag)
    );

    task automatic verify(input bit condition,input string label_text);
        begin
            checks=checks+1;
            if(condition!==1'b1) begin
                errors=errors+1;
                $display("FAIL cycle=%0d case=%0d %s mode=%0d phase=%0d q=%0d score=%0d audio_idle=%b fault=%b accepted=%0d",cycles,cases,label_text,mode,phase,question_index,score,audio_idle,audio_fault,accepted);
            end
        end
    endtask
    task automatic mark_case(input string label_text);
        begin cases=cases+1; $display("CASE %0d %s",cases,label_text); end
    endtask
    task automatic drive(input bit sv,input bit present,input bit stable,input integer item,
                         input bit src,input integer keys,input bit tick,
                         input bit response,input integer tag,input integer code);
        begin
            @(negedge clk);
            sample_valid=sv;det_present=present;det_stable=stable;det_item=item;source_test=src;
            key_mode_pulse=keys[0];key_replay_pulse=keys[1];key_skip_pulse=keys[2];key_reset_pulse=keys[3];
            tick_1ms=tick;rsp_valid=response;rsp_tag=tag;rsp_code=code;
            @(posedge clk);#2;
        end
    endtask
    task automatic idle_cycles(input integer count);
        integer n;
        begin for(n=0;n<count;n=n+1) drive(0,0,0,0,0,0,0,0,0,0); end
    endtask
    task automatic ticks(input integer count);
        integer n;
        begin for(n=0;n<count;n=n+1) drive(0,0,0,0,0,0,1,0,0,0); end
    endtask
    task automatic keys(input integer mask);
        begin drive(0,0,0,0,0,mask,0,0,0,0); end
    endtask
    task automatic response(input integer tag,input integer code,input bit tick);
        begin drive(0,0,0,0,0,0,tick,1,tag,code); end
    endtask
    task automatic remove_object;
        integer n;
        begin
            for(n=0;n<3;n=n+1) drive(1,0,0,0,0,0,0,0,0,0);
            verify(armed,"confirmed real removal arms system");
        end
    endtask
    task automatic place(input integer item,input bit src);
        begin drive(1,1,1,item,src,0,0,0,0,0); end
    endtask
    task automatic fresh_quiz;
        begin
            @(negedge clk);rst_n=0;req_ready=0;device_busy=0;rsp_valid=0;
            idle_cycles(3);rst_n=1;idle_cycles(2);
            verify(mode==0 && score==0 && audio_idle && !audio_fault,"shared reset clears control and audio queue");
            keys(K_MODE);idle_cycles(1);keys(K_MODE);idle_cycles(3);
            verify(mode==2 && question_index==1 && phase==1 && !armed,"fresh quiz waits for new placement");
        end
    endtask
    task automatic accept_expected(input integer kind,input integer item);
        integer before_count,n;
        begin
            before_count=accepted;req_ready=1;device_busy=0;n=0;
            while(accepted==before_count && n<16) begin idle_cycles(1);n=n+1;end
            req_ready=0;device_busy=1;
            verify(accepted==before_count+1,"exactly one expected transaction accepted");
            if(accepted>before_count) begin
                verify(accepted_kind[before_count]==kind && accepted_item[before_count]==item,"FIFO transaction kind/item match expected order");
                mock_active_tag=accepted_tag[before_count];
            end
        end
    endtask
    task automatic complete_active;
        begin response(mock_active_tag,0,0);device_busy=0;idle_cycles(1);end
    endtask
    task automatic confirm_stop;
        integer n;
        begin
            n=0;while(!stop_valid && n<8)begin idle_cycles(1);n=n+1;end
            verify(stop_valid,"cancel requests explicit stop of accepted transaction");
            response(stop_tag,3,0);device_busy=0;idle_cycles(2);
        end
    endtask
    task automatic finish_with_fault;
        begin ticks(FB);idle_cycles(3);verify(phase!=2,"fault lets feedback complete after its minimum duration");end
    endtask

    // Capture transport handshakes BEFORE sequential DUT updates.
    always @(posedge clk) begin
        if(rst_n && req_valid && req_ready) begin
            if(accepted<256) begin
                accepted_kind[accepted]=req_kind;accepted_item[accepted]=req_item;accepted_tag[accepted]=req_tag;
            end
            accepted=accepted+1;
        end
        #1;cycles=cycles+1;
        if(rst_n && !test_done) begin
            verify(score<=10,"system score stays in 0..10");
            verify(!(audio_cancel && audio_event_valid),"control cancel and event do not overlap");
            verify(!(stop_valid && req_valid),"new request cannot overlap stop barrier");
            verify(!audio_overflow,"scenario has no unexpected audio queue overflow");
            verify(!(answer_valid && previous_answer),"system answer pulse is one clock");
            if(audio_fault)verify(!req_valid,"fault disables new audio requests");
            if(answer_valid)begin
                answers=answers+1;
                verify(sample_valid && det_present && det_stable && !source_test,"mock test source cannot score");
                verify(score==(answer_correct?(previous_score+1):previous_score),"system answer has exact score delta");
            end
            if(score>previous_score)verify(answer_valid && answer_correct,"audio traffic cannot cause extra score");
            if(trace_fd!=0)$fdisplay(trace_fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",cycles,mode,phase,question_index,target_item,score,feedback,display_item,display_source_test,armed,audio_fault,answer_valid,answer_correct,audio_event_valid,audio_event_kind);
        end
        previous_score=score;previous_answer=answer_valid;
    end

    integer i,fault_type,a0,before_accept,old_tag,expected_item;
    initial begin
        if($value$plusargs("TRACE=%s",trace_path))begin
            trace_fd=$fopen(trace_path,"w");
            if(trace_fd==0)begin errors=errors+1;$display("FAIL trace open failed");end
            else $fdisplay(trace_fd,"cycle,mode,phase,question,target,score,feedback,item,source_test,armed,audio_fault,answer_valid,answer_correct,event_valid,event_kind");
        end

        mark_case("early answer queues correct behind question; ACK/busy/wrong tag are not end");
        fresh_quiz();accept_expected(2,1);before_accept=accepted;
        remove_object();place(1,0);
        verify(score==1 && phase==2 && answer_correct,"early correct answer updates display and score immediately");
        ticks(FB);
        verify(question_index==1 && phase==2 && !audio_idle,"minimum feedback elapsed but queued audio blocks next question");
        response(mock_active_tag,2,1);device_busy=0;idle_cycles(3);
        verify(accepted==before_accept && question_index==1 && phase==2 && !audio_idle,"ACK and busy falling do not finish question audio");
        response(mock_active_tag+1,0,0);
        verify(question_index==1 && !audio_idle,"wrong-tag completion ignored in composed system");
        complete_active();
        verify(question_index==1 && phase==2,"correct feedback remains pending after question completion");
        accept_expected(3,1);verify(question_index==1,"correct transaction runs before next question");
        complete_active();idle_cycles(3);
        verify(question_index==2 && phase==1 && !armed,"next question starts only after preceding prompt and feedback end");

        mark_case("audio may end early but feedback waits minimum tick duration");
        accept_expected(2,2);complete_active();remove_object();place(2,0);
        accept_expected(3,2);complete_active();idle_cycles(4);
        verify(phase==2 && question_index==2 && score==2,"no ticks means no feedback expiry even with audio idle");
        ticks(FB-1);verify(phase==2 && question_index==2,"feedback retains all but final required tick");
        ticks(1);idle_cycles(3);
        verify(question_index==3 && phase==1,"exact minimum tick permits next question after audio drain");

        mark_case("replay and wrong feedback preserve FIFO order and retry same question");
        accept_expected(2,3);keys(K_REPLAY);remove_object();place(4,0);ticks(FB);
        verify(feedback==2 && question_index==3 && score==2,"wrong answer waits behind original and replayed question");
        complete_active();accept_expected(2,3);
        verify(question_index==3 && phase==2,"replayed question precedes wrong feedback");
        complete_active();accept_expected(4,3);complete_active();idle_cycles(3);
        verify(question_index==3 && phase==1 && !armed && !req_valid && audio_idle,"first wrong retries without an automatic extra question");
        a0=answers;place(3,0);verify(answers==a0,"held answer cannot automatically retry");
        remove_object();place(3,0);accept_expected(3,3);complete_active();ticks(FB);idle_cycles(3);
        verify(question_index==4 && score==3,"correct retry advances exactly once");

        mark_case("skip flushes queued feedback and barriers next prompt on stop acknowledgement");
        accept_expected(2,4);old_tag=mock_active_tag;
        remove_object();place(4,0);verify(score==4 && phase==2,"fourth answer is accepted before explicit skip");
        keys(K_SKIP);idle_cycles(3);before_accept=accepted;
        verify(question_index==5 && phase==1 && stop_valid,"skip advances immediately and requests stop of old question");
        req_ready=1;device_busy=0;idle_cycles(3);
        verify(accepted==before_accept && stop_valid && !req_valid,"new question cannot pass unconfirmed stop");
        response(old_tag,0,0);idle_cycles(2);
        verify(stop_valid && accepted==before_accept,"late end of canceled question is not stop acknowledgement");
        req_ready=0;confirm_stop();accept_expected(2,5);
        verify(accepted==before_accept+1,"queued old correct feedback was discarded by skip");

        mark_case("clear and successive mode changes cancel old epoch while stop is pending");
        old_tag=mock_active_tag;keys(K_RESET);idle_cycles(2);
        verify(mode==0 && score==0 && stop_valid,"clear updates UI immediately while player awaits stop");
        keys(K_MODE);idle_cycles(1);keys(K_MODE);idle_cycles(3);
        verify(mode==2 && question_index==1 && score==0 && stop_valid,"mode changes establish new quiz without bypassing stop");
        before_accept=accepted;response(old_tag,2,0);idle_cycles(1);
        verify(stop_valid && accepted==before_accept,"ACK of canceled transaction does not release stop barrier");
        confirm_stop();accept_expected(2,1);
        verify(accepted==before_accept+1,"new question is first command after canceled clear and old question");
        complete_active();

        // Each fault case is a full independent reset epoch followed by ten
        // real correct answers. The local mock never turns test patterns into answers.
        for(fault_type=0;fault_type<3;fault_type=fault_type+1)begin
            if(fault_type==0)mark_case("permanent player busy faults; complete ten-question round silently");
            else if(fault_type==1)mark_case("ready permanently low faults; complete ten-question round silently");
            else mark_case("ACK without track end and missing stop response fault; ten questions still complete");
            fresh_quiz();
            if(fault_type==0)begin device_busy=1;req_ready=1;ticks(WAIT_LIMIT+2);end
            else if(fault_type==1)begin device_busy=0;req_ready=0;ticks(WAIT_LIMIT+2);end
            else begin
                accept_expected(2,1);
                for(i=0;i<PLAY_LIMIT;i=i+1)response(mock_active_tag,2,1);
                verify(audio_fault && stop_valid,"play timeout despite repeated ACK begins stop attempt");
                ticks(STOP_LIMIT+1);
            end
            verify(audio_fault && !req_valid && mode==2 && phase==1,"audio failure disables voice while quiz display continues");
            before_accept=accepted;a0=answers;
            remove_object();place(1,1);
            verify(score==0 && answers==a0 && display_item==1 && display_source_test && !armed,"test-source image remains marked and cannot score under audio fault");
            place(1,0);verify(score==0 && answers==a0,"test-to-real switch requires fresh removal");
            for(i=1;i<=10;i=i+1)begin
                expected_item=(i==10)?1:i;
                verify(question_index==i && target_item==expected_item,"fault round retains complete question sequence");
                remove_object();place(expected_item,0);
                verify(score==i && answer_valid && answer_correct,"fault round still scores real answer exactly once");
                finish_with_fault();
            end
            verify(score==10 && phase==3 && !quiz_active && answers==a0+10,"fault round completes all ten questions");
            verify(accepted==before_accept && audio_fault,"fault is sticky and no late audio leaks into round");
        end

        mark_case("shared reset recovers fault and common FIFO checker rejects corruption");
        fresh_quiz();verify(!audio_fault,"shared reset recovers the failed audio epoch");
        if($test$plusargs("NEGATIVE"))begin
            force req_kind=3'd3;
            accept_expected(2,1);
            release req_kind;
        end else accept_expected(2,1);
        complete_active();
        test_done=1;
        $display("SUMMARY checks=%0d errors=%0d cases=%0d cycles=%0d accepted=%0d answers=%0d test_done=%0d",checks,errors,cases,cycles,accepted,answers,test_done);
        if(trace_fd!=0)$fclose(trace_fd);
        #10;$finish;
    end
    initial begin
        #1000000;
        if(!test_done)begin errors=errors+1;test_done=1;$display("FAIL watchdog timeout");$display("SUMMARY checks=%0d errors=%0d test_done=%0d",checks,errors,test_done);$finish;end
    end
endmodule
