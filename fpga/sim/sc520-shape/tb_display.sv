`timescale 1ns/1ps
module tb_display;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0;
    wire vtc_vs,vtc_hs,vtc_de,vtc_sof,vtc_eol;
    wire raw_vs,raw_hs,raw_de,read_enable;
    wire [23:0] raw_rgb;
    wire out_vs,out_hs,out_de;
    wire [23:0] out_rgb;
    reg [23:0] pattern=24'h808080;
    integer errors=0,checked_cycles=0,checked_pixels=0,full_frames=0;
    integer border_pixels=0,cyan_pixels=0,reset_checks=0,frame_checks=0,inherited_read_skips=0;
    integer source_frame=0,source_index=0,source_x,source_y;
    reg source_previous_vs=0,source_armed=0;
    integer raw_frame=0,pixel_index=0,pixel_x,pixel_y,frame_border,frame_cyan;
    reg raw_previous_vs=0,reference_armed=0;
    reg expected_box_valid;
    integer expected_box_left,expected_box_top;
    integer expected_box_color,expected_stable;
    reg [4:0] question_row;
    integer glyph_row,glyph_column;
    reg expected_candidate_valid;
    integer expected_candidate_left,expected_candidate_top,expected_candidate_color;
    reg [23:0] expected_rgb;
    reg [26:0] expected [0:2];
    reg negative_control=0,test_done=0;

    uivtc #(.H_ActiveSize(1280),.H_FrameSize(1650),.H_SyncStart(1390),.H_SyncEnd(1430),
        .V_ActiveSize(720),.V_FrameSize(750),.V_SyncStart(725),.V_SyncEnd(730)) timing (
        .I_vtc_rstn(rst_n),.I_vtc_clk(clk),.O_vtc_vs(vtc_vs),.O_vtc_hs(vtc_hs),
        .O_vtc_de_valid(vtc_de),.O_vtc_user(vtc_sof),.O_vtc_last(vtc_eol));
    hdmi_mixer #(.H_OFFSET(0),.V_OFFSET(0),.IMG_WIDTH(1280),.IMG_HEIGHT(720),.DEBUG_MODE(0)) mixer (
        .I_clk(clk),.I_rst_n(rst_n),.I_video_vsync(vtc_vs),.I_video_hsync(vtc_hs),
        .I_video_de(vtc_de),.I_video_user(vtc_sof),.I_video_last(vtc_eol),.I_debug_status(4'd0),
        .O_video_rd_en(read_enable),.I_video_rd_data(pattern),.O_hdmi_vsync(raw_vs),
        .O_hdmi_hsync(raw_hs),.O_hdmi_de(raw_de),.O_hdmi_data(raw_rgb));
    hdmi_shape dut (.clk(clk),.rst_n(rst_n),.in_vsync(raw_vs),.in_hsync(raw_hs),
        .in_de(raw_de),.in_rgb(raw_rgb),.out_vsync(out_vs),.out_hsync(out_hs),.out_de(out_de),.out_rgb(out_rgb));

    function automatic [23:0] scene(input integer frame_id,xpos,ypos);
        integer left,top,color;
        begin
            left=-100;top=-100;color=0;
            if(frame_id>=2 && frame_id<=6)begin
                left=frame_id<=4 ? 400 : frame_id==5 ? 408 : 409;top=220;color=1;
            end else if(frame_id>=9 && frame_id<=14)begin left=600;top=300;color=3;end
            else if(frame_id>=15 && frame_id<=20)begin left=frame_id<=17?520:700;top=280;color=2;end
            scene=24'h808080;
            if(xpos>=left && xpos<left+40 && ypos>=top && ypos<top+30)begin
                case(color)
                    1:scene=24'hff0000;
                    2:scene=24'hffff00;
                    3:scene=24'h0000ff;
                endcase
            end
            if(frame_id==12 && ypos==550 && (xpos==850 || xpos==851))scene=24'h0000ff;
            if((frame_id==13 || frame_id==14) && xpos>=400 && xpos<440 && ypos>=200 && ypos<230)scene=24'hff0000;
        end
    endfunction

    task automatic fail(input string message);
        begin
            errors=errors+1;
            if(errors<=12)$display("ERROR display frame=%0d pixel=%0d %s at %0t",raw_frame,pixel_index,message,$time);
        end
    endtask

    task automatic frame_expectations;
        begin
            expected_box_valid=0;expected_box_left=0;expected_box_top=0;expected_box_color=0;expected_stable=0;
            case(raw_frame)
                3,4:expected_stable=raw_frame-2;
                5:begin expected_box_valid=1;expected_box_left=400;expected_box_top=220;expected_box_color=1;expected_stable=3;end
                6,7,8:begin expected_box_valid=1;expected_box_left=408;expected_box_top=220;expected_box_color=1;expected_stable=raw_frame==8?0:raw_frame-2;end
                10,11:expected_stable=raw_frame-9;
                12,13,14:begin expected_box_valid=1;expected_box_left=600;expected_box_top=300;expected_box_color=3;expected_stable=raw_frame==14?0:raw_frame-9;end
                16,17:expected_stable=raw_frame-15;
                18:begin expected_box_valid=1;expected_box_left=520;expected_box_top=280;expected_box_color=2;expected_stable=3;end
                19,20:expected_stable=raw_frame-18;
                21,22:begin expected_box_valid=1;expected_box_left=700;expected_box_top=280;expected_box_color=2;expected_stable=raw_frame==21?3:0;end
            endcase
            expected_candidate_valid=0;expected_candidate_color=0;expected_candidate_left=0;expected_candidate_top=0;
            if(raw_frame>=3 && raw_frame<=7)begin
                expected_candidate_valid=1;expected_candidate_color=1;expected_candidate_top=220;
                expected_candidate_left=raw_frame<=5?400:raw_frame==6?408:409;
            end else if(raw_frame>=10 && raw_frame<=13)begin
                expected_candidate_valid=1;expected_candidate_color=3;expected_candidate_left=600;expected_candidate_top=300;
            end else if(raw_frame>=16 && raw_frame<=21)begin
                expected_candidate_valid=1;expected_candidate_color=2;expected_candidate_left=raw_frame<=18?520:700;expected_candidate_top=280;
            end
        end
    endtask

    always @(negedge clk)begin
        if(!rst_n)begin
            source_frame=0;source_index=0;source_previous_vs=0;source_armed=0;pattern=24'h808080;
        end else begin
            if(vtc_vs && !source_previous_vs)begin source_frame=source_frame+1;source_index=0;source_armed=1;end
            source_previous_vs=vtc_vs;
            pattern=24'h808080;
            if(vtc_de && source_armed)begin
                source_x=source_index%1280;source_y=source_index/1280;
                pattern=scene(source_frame,source_x,source_y);
                source_index=source_index+1;
            end
        end
    end

    always @(posedge clk)begin
        if(!rst_n)begin
            expected[0]=0;expected[1]=0;expected[2]=0;
            raw_frame=0;raw_previous_vs=0;reference_armed=0;pixel_index=0;
            expected_box_valid=0;frame_border=0;frame_cyan=0;
            #1;
            if({out_vs,out_hs,out_de,out_rgb}!==27'd0 || dut.box_valid!==1'b0)fail("reset outputs");
            reset_checks=reset_checks+1;
        end else begin
            if(raw_vs && !raw_previous_vs)begin
                raw_frame=raw_frame+1;pixel_index=0;reference_armed=1;frame_border=0;frame_cyan=0;
                frame_expectations;
            end
            raw_previous_vs=raw_vs;
            expected_rgb=raw_de?raw_rgb:24'd0;
            if(raw_de && reference_armed)begin
                pixel_x=pixel_index%1280;pixel_y=pixel_index/1280;
                if(pixel_index==0)begin
                    if(dut.box_valid!==expected_box_valid || dut.box_color!==expected_box_color || dut.box_stable_count!==expected_stable)fail("stable box state");
                    if(expected_box_valid && (dut.box_left!==expected_box_left || dut.box_right!==expected_box_left+39 ||
                        dut.box_top!==expected_box_top || dut.box_bottom!==expected_box_top+29))fail("stable bounds");
                    if(dut.candidate_valid!==expected_candidate_valid || dut.candidate_color!==expected_candidate_color)fail("candidate valid/color");
                    if(expected_candidate_valid && (dut.candidate_area!==1200 || dut.candidate_left!==expected_candidate_left ||
                        dut.candidate_right!==expected_candidate_left+39 || dut.candidate_top!==expected_candidate_top ||
                        dut.candidate_bottom!==expected_candidate_top+29))fail("candidate area/bounds");
                    if(dut.stable_shape!==0)fail("40x30 rectangle must remain unknown");
                    frame_checks=frame_checks+1;
                end
                if(expected_box_valid && pixel_x>=expected_box_left && pixel_x<expected_box_left+40 &&
                    pixel_y>=expected_box_top && pixel_y<expected_box_top+30 &&
                    (pixel_x<expected_box_left+2 || pixel_x>=expected_box_left+38 ||
                     pixel_y<expected_box_top+2 || pixel_y>=expected_box_top+28))begin
                    expected_rgb=24'h00ffff;frame_cyan=frame_cyan+1;cyan_pixels=cyan_pixels+1;
                end
                if(((pixel_x==320 || pixel_x==959)&&pixel_y>=120&&pixel_y<=599) ||
                   ((pixel_y==120 || pixel_y==599)&&pixel_x>=320&&pixel_x<=959))begin
                    expected_rgb=24'hff0000;frame_border=frame_border+1;border_pixels=border_pixels+1;
                end
                if(expected_box_valid && pixel_x>=32 && pixel_x<72 && pixel_y>=32 && pixel_y<88)begin
                    glyph_row=(pixel_y-32)/8;glyph_column=(pixel_x-32)/8;
                    case(glyph_row)
                        0:question_row=5'b01110;
                        1:question_row=5'b10001;
                        2:question_row=5'b00001;
                        3:question_row=5'b00010;
                        4,6:question_row=5'b00100;
                        default:question_row=0;
                    endcase
                    expected_rgb=question_row[4-glyph_column]?24'hffffff:24'h202020;
                end
                pixel_index=pixel_index+1;
                if(pixel_index==1280*720)begin
                    if(frame_border!=2236 || frame_cyan!=(expected_box_valid?264:0))fail("frame border totals");
                    full_frames=full_frames+1;reference_armed=0;
                end
            end
            expected[2]=expected[1];expected[1]=expected[0];expected[0]={raw_vs,raw_hs,raw_de,expected_rgb};
            if(read_enable&&!vtc_de)fail("read outside active video");
            if(vtc_de&&!read_enable)inherited_read_skips=inherited_read_skips+1;
            #1;
            if({out_vs,out_hs,out_de,out_rgb}!==expected[2])fail("RGB/sync/three-cycle alignment");
            checked_cycles=checked_cycles+1;
            if(out_de)checked_pixels=checked_pixels+1;
        end
    end

    initial begin
        negative_control=$test$plusargs("negative_control");
        repeat(8)@(negedge clk);#2;rst_n=1;
        wait(full_frames==21);
        wait(raw_frame==22 && pixel_index==1280*100+501);
        @(negedge clk);#2;rst_n=0;
        repeat(8)@(negedge clk);#2;rst_n=1;
        wait(full_frames==26);
        repeat(8)@(negedge clk);
        if(frame_checks!=27 || reset_checks<16 || cyan_pixels!=2640 || border_pixels!=58136)fail("coverage incomplete");
        test_done=1;
        $display("RESULT display errors=%0d full_frames=%0d checked_cycles=%0d checked_pixels=%0d frame_checks=%0d border_pixels=%0d cyan_pixels=%0d reset_checks=%0d",errors,full_frames,checked_cycles,checked_pixels,frame_checks,border_pixels,cyan_pixels,reset_checks);
        $display("BASELINE_OBSERVATION inherited_read_skips=%0d",inherited_read_skips);
        $stop;
    end
    initial begin
        #400000000;errors=errors+1;$display("TIMEOUT display");$stop;
    end
    initial begin
        #1;if(negative_control)begin
            wait(out_de);@(negedge clk);force dut.out_rgb=24'hdeadbe;
            repeat(4)@(negedge clk);release dut.out_rgb;
        end
    end
endmodule
