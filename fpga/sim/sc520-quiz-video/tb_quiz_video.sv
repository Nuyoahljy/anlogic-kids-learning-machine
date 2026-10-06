`timescale 1ns/1ps
module tb_quiz_video # (parameter integer FULL=0);
    localparam integer WIDTH=FULL?1280:384, HEIGHT=FULL?720:240;
    localparam integer RX0=FULL?320:16,RX1=FULL?959:367,RY0=FULL?120:144,RY1=FULL?599:223;
    localparam integer SIDE=FULL?128:32,BASE_X=FULL?560:120,BASE_Y=FULL?280:168;
    localparam integer FRAME_CLOCKS=(WIDTH+8)*HEIGHT+96,FEEDBACK_CLOCKS=2*FRAME_CLOCKS;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,in_vsync=0,in_hsync=0,in_de=0,in_source_test=0;
    reg [23:0] in_rgb=24'h808080;
    reg key_mode_pulse=0,key_replay_pulse=0,key_skip_pulse=0,key_reset_pulse=0;
    wire out_vsync,out_hsync,out_de;
    wire [23:0] out_rgb;
    integer errors=0,checks=0,cases=0,frames=0,cycles=0,pixel_checks=0,ui_checks=0;
    integer answer_events=0,name_events=0,replay_events=0,tick_count=0,det_mask=0;
    integer input_x=0,input_y=0,frame_id=-1,source_item=0,ppm_fd=0,trace_fd=0;
    integer history_x[0:2],history_y[0:2];
    reg [23:0] history_rgb[0:2];
    reg [2:0] history_de=0,history_vs=0,history_hs=0;
    reg test_done=0,negative_fired=0;
    reg [26:0] frame_snapshot=0;
    integer snap_mode=0,snap_phase=0,snap_score=0,snap_question=0,snap_target=0,snap_feedback=0,snap_source=0;
    integer mid_frame_keys=0;
    integer capture_expected_phase=-1,capture_expected_score=-1,capture_expected_feedback=-1;
    string capture_name;
    `include "quiz_bitmap_reference.svh"

    hdmi_quiz #(.FRAME_WIDTH(WIDTH),.FRAME_HEIGHT(HEIGHT),.X_MIN(RX0),.X_MAX(RX1),.Y_MIN(RY0),.Y_MAX(RY1),
        .CLOCK_HZ(1000),.FEEDBACK_TICKS(FEEDBACK_CLOCKS),.MOCK_PLAY_TICKS(FRAME_CLOCKS/4),
        .AUDIO_WAIT_TICKS(4*FRAME_CLOCKS),.AUDIO_PLAY_TICKS(4*FRAME_CLOCKS),.AUDIO_STOP_TICKS(4*FRAME_CLOCKS)) dut (
        .clk(clk),.rst_n(rst_n),.in_vsync(in_vsync),.in_hsync(in_hsync),.in_de(in_de),.in_rgb(in_rgb),
        .in_source_test(in_source_test),.key_mode_pulse(key_mode_pulse),.key_replay_pulse(key_replay_pulse),
        .key_skip_pulse(key_skip_pulse),.key_reset_pulse(key_reset_pulse),
        .out_vsync(out_vsync),.out_hsync(out_hsync),.out_de(out_de),.out_rgb(out_rgb)
    );
    task automatic verify(input bit condition,input string label_text);
        begin checks=checks+1;if(condition!==1'b1)begin errors=errors+1;
            if(errors<30)$display("FAIL f=%0d xy=%0d,%0d %s mode=%0d phase=%0d q=%0d score=%0d det=%0d arm=%b",frame_id,history_x[2],history_y[2],label_text,dut.mode,dut.phase,dut.question_index,dut.score,dut.det_item,dut.armed);
        end end
    endtask
    task automatic mark_case(input string label_text);
        begin cases=cases+1;$display("CASE %0d full=%0d %s",cases,FULL,label_text);end
    endtask
    function automatic [23:0] input_pixel(input integer px,py,item);
        integer xx,yy,dx,dy,shape,color,bar;
        bit shape_hit;
        begin
            xx=px-BASE_X;yy=py-BASE_Y;shape_hit=0;shape=(item-1)%3+1;color=(item-1)/3+1;
            if(xx>=0 && xx<SIDE && yy>=0 && yy<SIDE && item!=0)begin
                dx=2*xx-(SIDE-1);dy=2*yy-(SIDE-1);bar=SIDE*13/32;
                if(item==10)begin shape_hit=(xx>=(SIDE-bar)/2 && xx<(SIDE+bar)/2)||(yy>=(SIDE-bar)/2 && yy<(SIDE+bar)/2);color=1;end
                else case(shape)
                    1:shape_hit=(dx*dx+dy*dy<=SIDE*SIDE);
                    2:shape_hit=1;
                    3:shape_hit=(dx<=yy && -dx<=yy);
                endcase
            end
            input_pixel=24'h808080;
            if(shape_hit)case(color)1:input_pixel=24'hff0000;2:input_pixel=24'hffff00;3:input_pixel=24'h0000ff;endcase
        end
    endfunction
    function automatic bit is_panel(input integer px,py);
        is_panel=px>=32 && px<1248 && ((py>=8 && py<112)||(py>=608 && py<712));
    endfunction

    // Independent sparse UI oracle: public text IDs and complete font bitmaps,
    // never the DUT glyph/font addressing. Other panel pixels are captured only.
    task automatic check_ui_pixel(input integer px,py,input [23:0] actual);
        integer line,col,glyph,tone,local_y,row,bitcol,msg;
        reg [255:0] bitmap;
        reg [23:0] ink,expected;
        bit selected;
        begin
            selected=0;glyph=0;tone=0;line=-1;col=0;local_y=0;
            if(is_panel(px,py) && (px==32 || px==1247 || py==8 || py==111 || py==608 || py==711))begin selected=1;expected=24'h18242c;end
            else if(FULL && px>=48 && px<1232 && ((py>=12&&py<44)||(py>=612&&py<676)))begin
                col=(px-48)/32;
                if(py<44)begin line=0;local_y=py-12;end
                else begin line=3+(py-612)/32;local_y=(py-612)%32;end
                if(line==0 && (col==20||col==21))begin
                    selected=1;tone=1;glyph=48+((col==20)?snap_score/10:snap_score%10);
                end else if(line==3 && snap_mode==2)begin
                    if(snap_phase==3 && col<16)begin
                        selected=1;tone=3;
                        if(col<14)glyph=quiz_ref_text(15,col);else glyph=48+((col==14)?snap_score/10:snap_score%10);
                    end else if((snap_phase==1 || snap_phase==2) && col<9)begin
                        selected=1;tone=1;glyph=(col<4)?quiz_ref_text(14,col):quiz_ref_text(27+snap_target,col-4);
                    end
                end else if(line==4 && col<5 && snap_mode==2 && snap_phase==2 && !snap_source)begin
                    selected=1;msg=snap_feedback==1?19:(snap_feedback==2?20:21);tone=snap_feedback==1?3:2;glyph=quiz_ref_text(msg,col);
                end
                if(selected)begin
                    bitmap=quiz_ref_bitmap(glyph);row=local_y/2;bitcol=((px-48)%32)/2;
                    ink=tone==1?24'habe8f2:(tone==2?24'hffe3a3:(tone==3?24'h9ef0cc:24'hf5f7fa));
                    expected=bitmap[255-row*16-bitcol]?ink:24'h18242c;
                end
            end
            if(selected)begin verify(actual===expected,"independent UI text/score/panel pixel");ui_checks=ui_checks+1;end
        end
    endtask

    always @(posedge clk)begin
        if(!rst_n)begin history_de=0;history_vs=0;history_hs=0;end
        else if(!test_done)begin
            history_de={history_de[1:0],in_de};history_vs={history_vs[1:0],in_vsync};history_hs={history_hs[1:0],in_hsync};
            history_x[2]=history_x[1];history_x[1]=history_x[0];history_x[0]=input_x;
            history_y[2]=history_y[1];history_y[1]=history_y[0];history_y[0]=input_y;
            history_rgb[2]=history_rgb[1];history_rgb[1]=history_rgb[0];history_rgb[0]=in_rgb;
            #1;cycles=cycles+1;
            verify({out_vsync,out_hsync,out_de}==={history_vs[2],history_hs[2],history_de[2]},"three-cycle video synchronization");
            if(dut.tick_1ms)tick_count=tick_count+1;
            if(dut.q_control.answer_valid)begin answer_events=answer_events+1;verify(!in_source_test,"test video never supplies scored answer");end
            if(dut.q_control.audio_event_valid && dut.q_control.audio_event_kind==1)name_events=name_events+1;
            if(dut.q_control.audio_event_valid && dut.q_control.audio_event_kind==2)replay_events=replay_events+1;
            if(dut.det_update && dut.det_valid && dut.det_item>=1 && dut.det_item<=9)det_mask=det_mask|(1<<(dut.det_item-1));
            if(!out_de)verify(out_rgb===0,"blanking pixels are black");
            else begin
                pixel_checks=pixel_checks+1;
                if(history_x[2]==0 && history_y[2]==0)begin
                    frame_snapshot={dut.osd_mode,dut.osd_phase,dut.osd_score,dut.osd_question,dut.osd_target,dut.osd_item,dut.osd_feedback,dut.osd_source,dut.osd_armed,dut.osd_audio_fault,dut.osd_audio_busy};
                    snap_mode=dut.osd_mode;snap_phase=dut.osd_phase;snap_score=dut.osd_score;snap_question=dut.osd_question;snap_target=dut.osd_target;snap_feedback=dut.osd_feedback;snap_source=dut.osd_source;
                    if(capture_expected_phase>=0)verify(snap_phase==capture_expected_phase,"captured frame has expected quiz phase");
                    if(capture_expected_score>=0)verify(snap_score==capture_expected_score,"captured frame has expected score");
                    if(capture_expected_feedback>=0)verify(snap_feedback==capture_expected_feedback,"captured frame has expected feedback");
                    $fdisplay(trace_fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",frame_id,snap_mode,snap_phase,snap_question,snap_target,snap_score,snap_feedback,snap_source,dut.osd_item,dut.osd_audio_fault);
                end else verify(frame_snapshot==={dut.osd_mode,dut.osd_phase,dut.osd_score,dut.osd_question,dut.osd_target,dut.osd_item,dut.osd_feedback,dut.osd_source,dut.osd_armed,dut.osd_audio_fault,dut.osd_audio_busy},"all OSD state remains frozen throughout frame");
                if(!is_panel(history_x[2],history_y[2]) && (history_x[2]<RX0 || history_x[2]>RX1 || history_y[2]<RY0 || history_y[2]>RY1))
                    verify(out_rgb===history_rgb[2],"camera RGB outside overlays passes through");
                check_ui_pixel(history_x[2],history_y[2],out_rgb);
                if(ppm_fd)$fwrite(ppm_fd,"%c%c%c",out_rgb[23:16],out_rgb[15:8],out_rgb[7:0]);
            end
        end
    end
    task automatic pause_video(input integer clocks);
        begin in_de=0;in_vsync=0;in_hsync=0;repeat(clocks)@(negedge clk);end
    endtask
    task automatic press(input integer mask);
        begin
            @(negedge clk);key_mode_pulse=mask[0];key_replay_pulse=mask[1];key_skip_pulse=mask[2];key_reset_pulse=mask[3];
            @(negedge clk);key_mode_pulse=0;key_replay_pulse=0;key_skip_pulse=0;key_reset_pulse=0;
            repeat(4)@(negedge clk);
        end
    endtask
    task automatic send_frame(input integer item,input bit src,input string image_name);
        integer xx,yy;
        begin
            frame_id=frame_id+1;source_item=item;in_source_test=src;
            if(image_name!="" && FULL && !$test$plusargs("NEGATIVE"))begin
                ppm_fd=$fopen({image_name,".ppm"},"wb");verify(ppm_fd!=0,"open complete 720p PPM");
                $fwrite(ppm_fd,"P6\n%0d %0d\n255\n",WIDTH,HEIGHT);
            end
            @(negedge clk);in_de=0;in_vsync=1;repeat(64)@(negedge clk);in_vsync=0;repeat(16)@(negedge clk);
            for(yy=0;yy<HEIGHT;yy=yy+1)begin
                for(xx=0;xx<WIDTH;xx=xx+1)begin
                    input_x=xx;input_y=yy;in_rgb=input_pixel(xx,yy,item);in_de=1;in_hsync=0;
                    if(mid_frame_keys!=0 && yy==HEIGHT/2 && xx==0)begin key_mode_pulse=mid_frame_keys[0];key_replay_pulse=mid_frame_keys[1];key_skip_pulse=mid_frame_keys[2];key_reset_pulse=mid_frame_keys[3];end
                    else begin key_mode_pulse=0;key_replay_pulse=0;key_skip_pulse=0;key_reset_pulse=0;end
                    if($test$plusargs("NEGATIVE") && !negative_fired && xx==8 && yy==HEIGHT-1)begin force out_rgb=24'h123456;negative_fired=1;end
                    @(negedge clk);
                    if(negative_fired)release out_rgb;
                end
                in_de=0;in_hsync=1;repeat(8)@(negedge clk);in_hsync=0;
            end
            in_de=0;repeat(16)@(negedge clk);
            if(ppm_fd)begin $fclose(ppm_fd);ppm_fd=0;end
            mid_frame_keys=0;capture_expected_phase=-1;capture_expected_score=-1;capture_expected_feedback=-1;frames=frames+1;
        end
    endtask
    task automatic repeated_frames(input integer item,input bit src,input integer count);
        integer n;begin for(n=0;n<count;n=n+1)send_frame(item,src,"");end
    endtask
    task automatic confirmed_empty;
        begin repeated_frames(0,0,7);verify(dut.armed,"video-derived confirmed absence arms answer");end
    endtask
    // Malformed input is not evidence of an empty physical scene. A VS-only
    // interval or incomplete raster must invalidate insertion permission.
    task automatic malformed_frame(input integer kind);
        integer xx,active_width;
        begin
            frame_id=frame_id+1;in_source_test=0;
            @(negedge clk);in_de=0;in_vsync=1;
            if(kind==3)begin
                // Eight real DE pixels illegally overlap active VS.
                for(xx=0;xx<8;xx=xx+1)begin
                    input_x=xx;input_y=0;in_de=1;in_rgb=24'h808080;@(negedge clk);
                end
                in_de=0;repeat(56)@(negedge clk);
            end else repeat(64)@(negedge clk);
            in_vsync=0;repeat(16)@(negedge clk);
            if(kind==1 || kind==2)begin
                active_width=(kind==2)?WIDTH+1:WIDTH/2;
                for(xx=0;xx<active_width;xx=xx+1)begin
                    input_x=xx;input_y=0;in_de=1;in_rgb=24'h808080;@(negedge clk);
                end
                in_de=0;in_hsync=1;repeat(8)@(negedge clk);in_hsync=0;
            end
            repeat(48)@(negedge clk);frames=frames+1;
        end
    endtask
    task automatic wait_answer(input integer item,input integer expected_score,input bit correct);
        integer before_answers,n;
        begin
            before_answers=answer_events;n=0;
            while(answer_events==before_answers && n<7)begin send_frame(item,0,"");n=n+1;end
            verify(answer_events==before_answers+1,"one answer arises from actual RGB detection");
            verify(dut.score==expected_score && dut.phase==2,"detected answer yields expected score and feedback");
            verify(dut.feedback==(correct?1:2),"correct/wrong feedback agrees with synthetic camera object");
        end
    endtask
    integer i,a0,n0,t0,q0;
    initial begin
        trace_fd=$fopen("video-frames.csv","w");$fdisplay(trace_fd,"frame,mode,phase,question,target,score,feedback,source_test,item,audio_fault");
        repeat(5)@(negedge clk);rst_n=1;repeat(5)@(negedge clk);
        mark_case("startup and real camera RGB detection");
        if(!FULL)begin
            press(1);confirmed_empty();n0=name_events;
            for(i=1;i<=9;i=i+1)begin repeated_frames(i,0,4);verify(dut.det_valid && dut.det_item==i,"nine synthetic color/shape images map through real detector");end
            verify(det_mask==511 && name_events==n0+1,"continuous class changes cover nine IDs but one placement name");
            repeated_frames(10,0,4);verify(!dut.det_valid && !dut.armed,"unknown colored object does not count as removal");
            press(1);a0=answer_events;repeated_frames(1,0,4);
            verify(dut.question_index==1 && answer_events==a0 && !dut.armed,"object already present when entering quiz cannot answer");
        end else begin press(1);press(1);end
        capture_expected_phase=1;capture_expected_score=0;send_frame(0,0,"question");

        mark_case("RGB correct answer, frozen feedback screen and timebase without video");
        confirmed_empty();
        if(!FULL)begin
            malformed_frame(0);malformed_frame(1);malformed_frame(2);malformed_frame(3);
            verify(!dut.armed,"bad frame revokes already armed permission");
            confirmed_empty();
        end
        wait_answer(1,1,1);q0=dut.question_index;
        capture_expected_phase=2;capture_expected_score=1;capture_expected_feedback=1;send_frame(1,0,"correct");
        t0=tick_count;pause_video(3*FRAME_CLOCKS);
        verify(tick_count>t0+FRAME_CLOCKS && dut.question_index==q0+1 && dut.phase==1,"stopped video still advances millisecond feedback/audio timers");
        if(!FULL)begin
            mark_case("missing or incomplete frames cannot act as removal of a held object");
            a0=answer_events;
            for(i=0;i<8;i=i+1)malformed_frame(i%4);
            verify(!dut.armed,"malformed frames cannot accumulate trusted absence");
            repeated_frames(1,0,5);
            verify(answer_events==a0 && !dut.armed,"restoring unchanged old object after malformed frames cannot answer");
        end
        a0=answer_events;repeated_frames(2,0,4);verify(answer_events==a0,"color/shape replacement without removal cannot answer next question");

        mark_case("RGB wrong answer and current-question replay");
        confirmed_empty();n0=replay_events;press(2);verify(replay_events==n0+1,"replay emits current question event");
        wait_answer(1,1,0);capture_expected_phase=2;capture_expected_score=1;capture_expected_feedback=2;send_frame(1,0,"wrong");
        pause_video(3*FRAME_CLOCKS);verify(dut.question_index==2 && dut.phase==1 && !dut.armed,"wrong answer returns to same question requiring removal");

        if(!FULL)begin
            mark_case("source-test label and test-to-real isolation through frame pipeline");
            repeated_frames(0,1,7);repeated_frames(2,1,5);
            verify(dut.score==1 && !dut.armed && dut.osd_source,"internal test source displays but never scores");
            a0=answer_events;repeated_frames(2,0,5);
            verify(answer_events==a0 && dut.score==1 && !dut.armed && !dut.osd_source,"test-to-real old object cannot inherit an armed answer");
            confirmed_empty();wait_answer(2,2,1);pause_video(3*FRAME_CLOCKS);
            verify(dut.question_index==3 && dut.score==2,"fresh real placement after source switch may score");
        end

        mark_case("midframe skip holds one coherent screen; finish round and clear");
        q0=dut.question_index;mid_frame_keys=4;send_frame(0,0,"");
        verify(dut.question_index==q0+1,"midframe skip updates live control while OSD remains frozen");
        while(dut.phase!=3)press(4);
        capture_expected_phase=3;capture_expected_score=FULL?1:2;send_frame(0,0,"finished");
        verify(!dut.q_control.quiz_active,"last question ends round");
        press(8);capture_expected_phase=0;capture_expected_score=0;send_frame(0,0,"cleared");
        verify(dut.mode==0 && dut.score==0,"clear returns idle zero score");
        verify(!dut.audio_fault,"normal mock audio remains healthy");
        if($test$plusargs("NEGATIVE"))verify(negative_fired,"negative output corruption was exercised");
        $fclose(trace_fd);test_done=1;
        $display("SUMMARY checks=%0d errors=%0d cases=%0d frames=%0d pixels=%0d ui_checks=%0d answers=%0d item_mask=%0d test_done=%0d",checks,errors,cases,frames,pixel_checks,ui_checks,answer_events,det_mask,test_done);
        #10;$finish;
    end
    initial begin #2000000000;if(!test_done)begin errors=errors+1;test_done=1;$display("FAIL watchdog timeout");$display("SUMMARY checks=%0d errors=%0d test_done=%0d",checks,errors,test_done);$finish;end end
endmodule
