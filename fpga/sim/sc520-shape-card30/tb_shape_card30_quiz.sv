`timescale 1ns/1ps
module tb_shape_card30_quiz;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,tick_1ms=0,sample_valid=0,det_present=0,det_stable=0,source_test=0;
    reg sample_healthy=1,revoke=0,key_mode_pulse=0,key_replay_pulse=0,key_skip_pulse=0,key_reset_pulse=0;
    reg audio_idle=1,audio_fault=0;reg [3:0] det_item=0;
    wire [1:0] mode,phase;wire [3:0] score,question_index,target_item,display_item,audio_event_item;
    wire quiz_active,answer_valid,answer_correct,display_source_test,armed,audio_event_valid,audio_cancel;
    wire [2:0] feedback,audio_event_kind;
    items30_quiz_control #(.FEEDBACK_TICKS(2)) dut(.*);
    reg [3:0] bank_index=0;wire [3:0] bank_item;
    items30_question_bank bank(.index(bank_index),.item(bank_item));
    integer errors=0,checks=0,scenarios=0,inject=0,n;reg test_done=0;
    task ck(input bit ok,input string message);
        begin checks++;if(!ok)begin errors++;$display("FAIL quiz case%0d %s",scenarios,message);end end
    endtask
    function [3:0] item_at(input integer slot);
        case(slot%8)0:item_at=1;1:item_at=10;2:item_at=2;3:item_at=11;
            4:item_at=3;5:item_at=12;6:item_at=13;default:item_at=14;endcase
    endfunction
    task key(input integer which);
        begin
            key_mode_pulse=which==1;key_replay_pulse=which==2;key_skip_pulse=which==3;key_reset_pulse=which==4;
            @(negedge clk);key_mode_pulse=0;key_replay_pulse=0;key_skip_pulse=0;key_reset_pulse=0;
        end
    endtask
    task observe(input integer item,input bit present,stable,healthy,test_source);
        begin
            det_item=item;det_present=present;det_stable=stable;sample_healthy=healthy;source_test=test_source;
            sample_valid=1;@(negedge clk);sample_valid=0;@(negedge clk);
        end
    endtask
    task empty_gate;
        begin
            observe(0,0,0,1,0);observe(0,0,0,1,0);ck(!armed,"two empties cannot arm");
            observe(0,0,0,1,0);ck(armed,"third healthy camera empty arms");
        end
    endtask
    task finish_feedback;
        begin tick_1ms=1;repeat(2)@(negedge clk);tick_1ms=0;@(negedge clk);end
    endtask
    initial begin
        n=$value$plusargs("INJECT_FAULT=%d",inject);
        repeat(4)@(negedge clk);rst_n=1;
        scenarios++;
        for(integer i=0;i<16;i++)begin bank_index=i;#1;ck(bank_item==(i<8?item_at(i):0),"eight-slot catalog and illegal slots");end
        @(negedge clk);key(1);ck(mode==1,"K1 explore");
        observe(0,1,0,1,0);ck(!armed,"unknown present is not empty");
        observe(1,1,1,1,1);ck(display_source_test&&!armed,"test cannot arm or score");
        empty_gate();observe(1,1,1,1,0);ck(display_item==1&&!armed,"explore actual object consumes arm");
        scenarios++;key(2);ck(audio_event_valid&&audio_event_kind==1&&audio_event_item==1,"K2 explore replay");
        @(negedge clk);key(3);ck(mode==1,"inactive K3 has no quiz mutation");
        key(1);ck(mode==2&&question_index==1&&target_item==1,"K1 first quiz");
        repeat(2)@(negedge clk);
        for(integer q=1;q<=10;q++)begin
            scenarios++;ck(question_index==q&&target_item==item_at(q-1),"all ten target lookups wrap eight slots");
            observe(0,1,0,1,0);ck(!armed,"present unknown cannot satisfy next question empty gate");
            empty_gate();
            det_item=target_item;det_present=1;det_stable=1;sample_healthy=1;source_test=0;sample_valid=1;
            @(negedge clk);
            ck(answer_valid&&answer_correct&&score==q&&phase==2&&feedback==1,"one answer one point");
            ck(audio_event_valid&&audio_event_kind==3&&audio_event_item==target_item,"correct audio event new catalog");
            sample_valid=0;@(negedge clk);ck(!answer_valid&&score==q,"answer event not held");
            finish_feedback();
        end
        ck(score==10&&phase==3&&!quiz_active,"ten-point finish");
        scenarios++;key(1);ck(mode==0,"quiz K1 returns idle");key(1);key(1);
        ck(target_item==2&&question_index==1,"next round rotates by two catalog slots");
        repeat(2)@(negedge clk);empty_gate();
        det_item=14;det_present=1;det_stable=1;sample_valid=1;@(negedge clk);
        ck(answer_valid&&!answer_correct&&feedback==2&&score==0,"first wrong retry no points");
        sample_valid=0;finish_feedback();ck(phase==1,"wrong retry returns waiting");
        empty_gate();det_item=14;det_present=1;det_stable=1;sample_valid=1;@(negedge clk);
        ck(answer_valid&&!answer_correct&&feedback==3&&score==0,"second wrong shows answer no points");
        sample_valid=0;finish_feedback();ck(question_index==2,"second wrong advances");
        scenarios++;key(3);ck(question_index==3&&audio_cancel,"active K3 skip");
        repeat(2)@(negedge clk);key(2);ck(audio_event_valid&&audio_event_kind==2&&audio_event_item==target_item,"K2 question replay");
        scenarios++;empty_gate();revoke=1;key_replay_pulse=1;@(negedge clk);
        ck(!armed&&!audio_event_valid&&audio_cancel&&display_item==0,"revoke dominates replay and recognition");
        revoke=0;key_replay_pulse=0;observe(0,0,0,0,0);ck(!armed,"bad empty never arms");
        scenarios++;key_reset_pulse=1;key_mode_pulse=1;key_skip_pulse=1;@(negedge clk);
        ck(mode==0&&phase==0&&score==0&&question_index==0&&audio_cancel,"K4 priority and clears score");
        key_reset_pulse=0;key_mode_pulse=0;key_skip_pulse=0;@(negedge clk);
        ck(audio_event_valid&&audio_event_kind==6&&audio_event_item==0,"reset deferred cancel event");
        if(inject)ck(score==1,"negative final score oracle");
        test_done=1;$display("RESULT quiz errors=%0d checks=%0d scenarios=%0d",errors,checks,scenarios);$finish;
    end
endmodule
