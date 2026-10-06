`timescale 1ns/1ps
module tb_quiz_osd;
    reg [10:0] pixel_x=0;
    reg [9:0] pixel_y=0;
    reg [1:0] mode=0,phase=0;
    reg [3:0] score=0,question_index=0,target_item=0,display_item=0;
    reg [2:0] feedback=0;
    reg source_test=0,armed=0,audio_fault=0,audio_busy=0;
    wire active;
    wire [23:0] rgb;
    reg [2:0] query_line=0;
    reg [5:0] query_char=0;
    wire [7:0] query_glyph;
    wire [1:0] query_tone;
    reg [7:0] font_glyph=0;
    reg [3:0] font_row=0;
    wire [15:0] font_bits;
    integer checks=0,errors=0,cases=0,pixel_checks=0,content_checks=0;
    reg test_done=0;
    quiz_osd dut(.*);
    quiz_content query(.line_index(query_line),.char_index(query_char),.mode(mode),.phase(phase),
        .score(score),.question_index(question_index),.target_item(target_item),.display_item(display_item),
        .feedback(feedback),.source_test(source_test),.armed(armed),.audio_fault(audio_fault),.audio_busy(audio_busy),
        .glyph(query_glyph),.tone(query_tone));
    quiz_font_rom font_query(.glyph(font_glyph),.row(font_row),.bits(font_bits));
    `include "quiz_bitmap_reference.svh"

    // Expected display state is assembled independently of the DUT selector.
    // Common font/text assets are checked in a full-bitmap reference format.
    function automatic integer number_glyph(input integer number,input integer digit_place);
        if(number<0 || number>10) number_glyph=45;
        else if(digit_place==0) number_glyph=48+number/10;
        else number_glyph=48+number%10;
    endfunction
    function automatic integer object_text(input integer item);
        object_text=(item>=1 && item<=9)?27+item:27;
    endfunction
    function automatic integer expected_glyph(input integer row,input integer column);
        integer message_id;
        begin
            expected_glyph=0;message_id=0;
            if(row==0) begin
                case(column)
                    0,1,2,3: expected_glyph=quiz_ref_text(mode+1,column);
                    6,7: expected_glyph=quiz_ref_text(5,column-6);
                    9,10: expected_glyph=(mode==2 && question_index>=1 && question_index<=10)?number_glyph(question_index,column-9):45;
                    11,22: expected_glyph=47;
                    12,23: expected_glyph=49;
                    13,24: expected_glyph=48;
                    17,18: expected_glyph=quiz_ref_text(6,column-17);
                    20,21: expected_glyph=number_glyph(score,column-20);
                endcase
            end else if(row==1) expected_glyph=quiz_ref_text(source_test?7:8,column);
            else if(row==2) expected_glyph=quiz_ref_text(audio_fault?11:audio_busy?10:9,column);
            else if(row==3) begin
                if(mode==0) expected_glyph=quiz_ref_text(12,column);
                else if(mode==1) expected_glyph=quiz_ref_text(13,column);
                else if(mode==3 || phase==0) expected_glyph=quiz_ref_text(16,column);
                else if(phase==3) begin
                    if(column==14 || column==15) expected_glyph=number_glyph(score,column-14);
                    else if(column<14) expected_glyph=quiz_ref_text(15,column);
                end else if(column<4) expected_glyph=quiz_ref_text(14,column);
                else expected_glyph=quiz_ref_text(object_text(target_item),column-4);
            end else if(row==4) begin
                if(source_test) message_id=17;
                else if(mode==2 && phase==3) message_id=18;
                else if(mode==2 && phase==2) begin
                    if(feedback>=1 && feedback<=3) message_id=18+feedback;
                    else message_id=16;
                end else if(mode==2 && phase==1) message_id=armed?22:23;
                else if(mode<2) message_id=24;
                else message_id=16;
                expected_glyph=quiz_ref_text(message_id,column);
            end else if(row==5) begin
                if(mode==2 && phase==2 && feedback==3)
                    expected_glyph=column<5?quiz_ref_text(26,column):quiz_ref_text(object_text(target_item),column-5);
                else expected_glyph=column<5?quiz_ref_text(25,column):quiz_ref_text(object_text(display_item),column-5);
            end
        end
    endfunction
    function automatic integer expected_tone(input integer row);
        begin
            expected_tone=0;
            case(row)
                0: expected_tone=1;
                1: expected_tone=source_test?2:1;
                2: expected_tone=audio_fault?2:0;
                3: if(mode==2 && phase!=0) expected_tone=phase==3?3:1;
                4: begin
                    if(source_test) expected_tone=2;
                    else if(mode==2 && phase==3) expected_tone=3;
                    else if(mode==2 && phase==2) expected_tone=feedback==1?3:2;
                    else if(mode==3 || (mode==2 && phase==0)) expected_tone=2;
                end
                5: if(mode==2 && phase==2 && feedback==3) expected_tone=2;
            endcase
        end
    endfunction
    function automatic bit expected_active(input integer x,input integer y);
        expected_active=x>=32 && x<=1247 && ((y>=8 && y<=111)||(y>=608 && y<=711));
    endfunction
    function automatic [23:0] expected_rgb(input integer x,input integer y);
        integer row, column, fx, fy, tone, code;
        reg [255:0] bitmap;
        begin
            expected_rgb=0;
            if(expected_active(x,y)) begin
                expected_rgb=24'h18242C;
                if(x>=48 && x<1232 && ((y>=12 && y<108)||(y>=612 && y<708))) begin
                    row=y<120?(y-12)/32:3+(y-612)/32;
                    column=(x-48)/32;
                    fx=((x-48)%32)/2;
                    fy=y<120?((y-12)%32)/2:((y-612)%32)/2;
                    code=expected_glyph(row,column);bitmap=quiz_ref_bitmap(code);
                    tone=expected_tone(row);
                    if(bitmap[(15-fy)*16+15-fx]) begin
                        case(tone)
                            0: expected_rgb=24'hF5F7FA;
                            1: expected_rgb=24'hABE8F2;
                            2: expected_rgb=24'hFFE3A3;
                            3: expected_rgb=24'h9EF0CC;
                        endcase
                    end
                end
            end
        end
    endfunction

    task automatic verify(input bit condition,input string label_text);
        begin
            checks=checks+1;
            if(!condition) begin
                errors=errors+1;
                if(errors<15) $display("FAIL OSD case=%0d %s x=%0d y=%0d",cases,label_text,pixel_x,pixel_y);
            end
        end
    endtask
    task automatic check_pixel(input integer x,input integer y);
        begin
            pixel_x=x;pixel_y=y;#1;
            verify(active===expected_active(x,y) && rgb===expected_rgb(x,y),"pixel active/RGB mismatch");
            pixel_checks=pixel_checks+1;
        end
    endtask
    task automatic check_content;
        integer row,column;
        begin
            for(row=0;row<8;row=row+1)for(column=0;column<64;column=column+1)begin
                query_line=row;query_char=column;#1;
                verify(query_glyph===expected_glyph(row,column) && query_tone===expected_tone(row),"content/tone mismatch");
                content_checks=content_checks+1;
            end
        end
    endtask
    task automatic select_case(input integer which);
        begin
            mode=2;phase=1;score=0;question_index=1;target_item=1;display_item=1;
            feedback=0;source_test=0;armed=1;audio_fault=0;audio_busy=0;
            case(which)
                0: begin mode=0;phase=0;question_index=0;target_item=0;display_item=0;armed=0;end
                1: begin mode=1;phase=0;question_index=0;target_item=0;display_item=5;end
                2,3,4,5,6,7,8,9,10: begin target_item=which-1;question_index=which-1;display_item=which-1;score=which-2;end
                11: begin phase=2;feedback=1;score=1;audio_busy=1;end
                12: begin phase=2;feedback=2;target_item=5;display_item=4;question_index=5;score=3;end
                13: begin phase=2;feedback=3;target_item=9;display_item=7;question_index=9;score=4;end
                14: begin phase=3;question_index=10;score=10;armed=0;end
                15: begin source_test=1;display_item=9;armed=0;end
                16: begin audio_fault=1;audio_busy=1;target_item=6;display_item=0;armed=0;end
                17: begin armed=0;end
                18: begin display_item=15;target_item=15;end
                19: begin question_index=15;score=15;end
                20: begin mode=3;phase=0;end
                21: begin phase=2;feedback=0;end
                22: begin phase=2;feedback=7;end
                23: begin phase=0;end
                24: begin phase=3;question_index=10;score=0;end
                25: begin phase=2;feedback=1;source_test=1;end
            endcase
        end
    endtask

    integer scenario,x,y,row,code,fd,i;
    reg [255:0] expected_bitmap;
    reg [23:0] visible_rgb;
    initial begin
        for(code=0;code<256;code=code+1)for(row=0;row<16;row=row+1)begin
            font_glyph=code;font_row=row;#1;expected_bitmap=quiz_ref_bitmap(code);
            verify(font_bits===expected_bitmap[255-row*16 -: 16],"font row differs from independent bitmap packing");
        end
        for(scenario=0;scenario<26;scenario=scenario+1)begin
            cases=cases+1;select_case(scenario);check_content();fd=0;
            if(!$test$plusargs("NEGATIVE") && (scenario==0 || scenario==1 || scenario==2 || (scenario>=10 && scenario<=17)))begin
                fd=$fopen($sformatf("quiz-osd-%02d.ppm",scenario),"w");
                verify(fd!=0,"PPM output opens");
                if(fd) $fwrite(fd,"P3\n1280 240\n255\n");
            end
            // Exact output pixels of top and bottom 120-line strips.
            // Inactive pixels use a neutral viewing background only in the PPM.
            for(y=0;y<720;y=y+1)if(y<120 || y>=600)begin
                for(x=0;x<1280;x=x+1)begin
                    check_pixel(x,y);
                    if(fd)begin
                        visible_rgb=active?rgb:24'h344048;
                        $fwrite(fd,"%0d %0d %0d ",visible_rgb[23:16],visible_rgb[15:8],visible_rgb[7:0]);
                    end
                end
                if(fd)$fwrite(fd,"\n");
            end
            if(fd)$fclose(fd);
            check_pixel(2047,1023);check_pixel(1280,8);check_pixel(1280,608);
            $display("CASE OSD=%0d mode=%0d phase=%0d target=%0d feedback=%0d score=%0d test=%b fault=%b",scenario,mode,phase,target_item,feedback,score,source_test,audio_fault);
        end
        // Exhaust all central pixels: no status can hide the detector ROI.
        for(y=120;y<=599;y=y+1)for(x=320;x<=959;x=x+1)check_pixel(x,y);
        // All unsupported object codes must choose unknown in both target and display.
        for(i=0;i<16;i=i+1)begin mode=2;phase=1;target_item=i;display_item=i;check_content();end
        if($test$plusargs("NEGATIVE"))begin
            force dut.rgb=24'hFFFFFF;
            check_pixel(32,8); // Real RGB corruption reaches ordinary pixel checker.
            release dut.rgb;
        end
        test_done=1;
        $display("SUMMARY checks=%0d errors=%0d cases=%0d pixels=%0d content=%0d test_done=%0d",checks,errors,cases,pixel_checks,content_checks,test_done);
        $finish;
    end
    initial begin #20000000; $fatal(1,"OSD watchdog timeout"); end
endmodule
