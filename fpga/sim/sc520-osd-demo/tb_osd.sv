`timescale 1ns/1ps
module tb_osd;
    reg [10:0] pixel_x;
    reg [9:0] pixel_y;
    reg demo_mode,box_valid;
    reg [1:0] expected_shape,expected_color,shape,color;
    wire active;
    wire [23:0] rgb;
    reg test_done=0;
    integer errors=0,checks=0,case_index,index,xpos,ypos,line_index,column;
    integer expected_glyph[0:26];
    reg [23:0] ink[0:2];
    reg [15:0] bits;
    reg [23:0] wanted;
    reg within_osd;
    chinese_osd dut(.*);
    `include "font_reference.svh"
    initial begin
        for(case_index=0;case_index<13;case_index=case_index+1)begin
            for(index=0;index<27;index=index+1)expected_glyph[index]=0;
            case(case_index)
                0: begin
                    demo_mode=1;box_valid=1;expected_shape=1;expected_color=1;shape=1;color=1;
                    expected_glyph[0]=1;
                    expected_glyph[1]=2;
                    expected_glyph[2]=3;
                    expected_glyph[3]=4;
                    expected_glyph[9]=8;
                    expected_glyph[10]=9;
                    expected_glyph[11]=12;
                    expected_glyph[12]=15;
                    expected_glyph[13]=16;
                    expected_glyph[14]=17;
                    expected_glyph[18]=10;
                    expected_glyph[19]=11;
                    expected_glyph[20]=12;
                    expected_glyph[21]=15;
                    expected_glyph[22]=16;
                    expected_glyph[23]=17;
                    ink[0]=24'hffff00;
                    ink[1]=24'hff0000;
                    ink[2]=24'hff0000;
                end
                1: begin
                    demo_mode=1;box_valid=1;expected_shape=2;expected_color=1;shape=2;color=1;
                    expected_glyph[0]=1;
                    expected_glyph[1]=2;
                    expected_glyph[2]=3;
                    expected_glyph[3]=4;
                    expected_glyph[9]=8;
                    expected_glyph[10]=9;
                    expected_glyph[11]=12;
                    expected_glyph[12]=15;
                    expected_glyph[13]=18;
                    expected_glyph[14]=19;
                    expected_glyph[15]=17;
                    expected_glyph[18]=10;
                    expected_glyph[19]=11;
                    expected_glyph[20]=12;
                    expected_glyph[21]=15;
                    expected_glyph[22]=18;
                    expected_glyph[23]=19;
                    expected_glyph[24]=17;
                    ink[0]=24'hffff00;
                    ink[1]=24'hff0000;
                    ink[2]=24'hff0000;
                end
                2: begin
                    demo_mode=1;box_valid=1;expected_shape=3;expected_color=1;shape=3;color=1;
                    expected_glyph[0]=1;
                    expected_glyph[1]=2;
                    expected_glyph[2]=3;
                    expected_glyph[3]=4;
                    expected_glyph[9]=8;
                    expected_glyph[10]=9;
                    expected_glyph[11]=12;
                    expected_glyph[12]=15;
                    expected_glyph[13]=20;
                    expected_glyph[14]=21;
                    expected_glyph[15]=17;
                    expected_glyph[18]=10;
                    expected_glyph[19]=11;
                    expected_glyph[20]=12;
                    expected_glyph[21]=15;
                    expected_glyph[22]=20;
                    expected_glyph[23]=21;
                    expected_glyph[24]=17;
                    ink[0]=24'hffff00;
                    ink[1]=24'hff0000;
                    ink[2]=24'hff0000;
                end
                3: begin
                    demo_mode=1;box_valid=1;expected_shape=1;expected_color=2;shape=1;color=2;
                    expected_glyph[0]=1;
                    expected_glyph[1]=2;
                    expected_glyph[2]=3;
                    expected_glyph[3]=4;
                    expected_glyph[9]=8;
                    expected_glyph[10]=9;
                    expected_glyph[11]=13;
                    expected_glyph[12]=15;
                    expected_glyph[13]=16;
                    expected_glyph[14]=17;
                    expected_glyph[18]=10;
                    expected_glyph[19]=11;
                    expected_glyph[20]=13;
                    expected_glyph[21]=15;
                    expected_glyph[22]=16;
                    expected_glyph[23]=17;
                    ink[0]=24'hffff00;
                    ink[1]=24'hffff00;
                    ink[2]=24'hffff00;
                end
                4: begin
                    demo_mode=1;box_valid=1;expected_shape=2;expected_color=2;shape=2;color=2;
                    expected_glyph[0]=1;
                    expected_glyph[1]=2;
                    expected_glyph[2]=3;
                    expected_glyph[3]=4;
                    expected_glyph[9]=8;
                    expected_glyph[10]=9;
                    expected_glyph[11]=13;
                    expected_glyph[12]=15;
                    expected_glyph[13]=18;
                    expected_glyph[14]=19;
                    expected_glyph[15]=17;
                    expected_glyph[18]=10;
                    expected_glyph[19]=11;
                    expected_glyph[20]=13;
                    expected_glyph[21]=15;
                    expected_glyph[22]=18;
                    expected_glyph[23]=19;
                    expected_glyph[24]=17;
                    ink[0]=24'hffff00;
                    ink[1]=24'hffff00;
                    ink[2]=24'hffff00;
                end
                5: begin
                    demo_mode=1;box_valid=1;expected_shape=3;expected_color=2;shape=3;color=2;
                    expected_glyph[0]=1;
                    expected_glyph[1]=2;
                    expected_glyph[2]=3;
                    expected_glyph[3]=4;
                    expected_glyph[9]=8;
                    expected_glyph[10]=9;
                    expected_glyph[11]=13;
                    expected_glyph[12]=15;
                    expected_glyph[13]=20;
                    expected_glyph[14]=21;
                    expected_glyph[15]=17;
                    expected_glyph[18]=10;
                    expected_glyph[19]=11;
                    expected_glyph[20]=13;
                    expected_glyph[21]=15;
                    expected_glyph[22]=20;
                    expected_glyph[23]=21;
                    expected_glyph[24]=17;
                    ink[0]=24'hffff00;
                    ink[1]=24'hffff00;
                    ink[2]=24'hffff00;
                end
                6: begin
                    demo_mode=1;box_valid=1;expected_shape=1;expected_color=3;shape=1;color=3;
                    expected_glyph[0]=1;
                    expected_glyph[1]=2;
                    expected_glyph[2]=3;
                    expected_glyph[3]=4;
                    expected_glyph[9]=8;
                    expected_glyph[10]=9;
                    expected_glyph[11]=14;
                    expected_glyph[12]=15;
                    expected_glyph[13]=16;
                    expected_glyph[14]=17;
                    expected_glyph[18]=10;
                    expected_glyph[19]=11;
                    expected_glyph[20]=14;
                    expected_glyph[21]=15;
                    expected_glyph[22]=16;
                    expected_glyph[23]=17;
                    ink[0]=24'hffff00;
                    ink[1]=24'h0000ff;
                    ink[2]=24'h0000ff;
                end
                7: begin
                    demo_mode=1;box_valid=1;expected_shape=2;expected_color=3;shape=2;color=3;
                    expected_glyph[0]=1;
                    expected_glyph[1]=2;
                    expected_glyph[2]=3;
                    expected_glyph[3]=4;
                    expected_glyph[9]=8;
                    expected_glyph[10]=9;
                    expected_glyph[11]=14;
                    expected_glyph[12]=15;
                    expected_glyph[13]=18;
                    expected_glyph[14]=19;
                    expected_glyph[15]=17;
                    expected_glyph[18]=10;
                    expected_glyph[19]=11;
                    expected_glyph[20]=14;
                    expected_glyph[21]=15;
                    expected_glyph[22]=18;
                    expected_glyph[23]=19;
                    expected_glyph[24]=17;
                    ink[0]=24'hffff00;
                    ink[1]=24'h0000ff;
                    ink[2]=24'h0000ff;
                end
                8: begin
                    demo_mode=1;box_valid=1;expected_shape=3;expected_color=3;shape=3;color=3;
                    expected_glyph[0]=1;
                    expected_glyph[1]=2;
                    expected_glyph[2]=3;
                    expected_glyph[3]=4;
                    expected_glyph[9]=8;
                    expected_glyph[10]=9;
                    expected_glyph[11]=14;
                    expected_glyph[12]=15;
                    expected_glyph[13]=20;
                    expected_glyph[14]=21;
                    expected_glyph[15]=17;
                    expected_glyph[18]=10;
                    expected_glyph[19]=11;
                    expected_glyph[20]=14;
                    expected_glyph[21]=15;
                    expected_glyph[22]=20;
                    expected_glyph[23]=21;
                    expected_glyph[24]=17;
                    ink[0]=24'hffff00;
                    ink[1]=24'h0000ff;
                    ink[2]=24'h0000ff;
                end
                9: begin
                    demo_mode=1;box_valid=0;expected_shape=0;expected_color=0;shape=0;color=0;
                    expected_glyph[0]=1;
                    expected_glyph[1]=2;
                    expected_glyph[2]=3;
                    expected_glyph[3]=4;
                    expected_glyph[9]=8;
                    expected_glyph[10]=9;
                    expected_glyph[11]=28;
                    expected_glyph[12]=29;
                    expected_glyph[18]=10;
                    expected_glyph[19]=11;
                    expected_glyph[20]=25;
                    expected_glyph[21]=26;
                    expected_glyph[22]=27;
                    ink[0]=24'hffff00;
                    ink[1]=24'hffffff;
                    ink[2]=24'hffffff;
                end
                10: begin
                    demo_mode=1;box_valid=1;expected_shape=2;expected_color=2;shape=0;color=0;
                    expected_glyph[0]=1;
                    expected_glyph[1]=2;
                    expected_glyph[2]=3;
                    expected_glyph[3]=4;
                    expected_glyph[9]=8;
                    expected_glyph[10]=9;
                    expected_glyph[11]=13;
                    expected_glyph[12]=15;
                    expected_glyph[13]=18;
                    expected_glyph[14]=19;
                    expected_glyph[15]=17;
                    expected_glyph[18]=10;
                    expected_glyph[19]=11;
                    expected_glyph[20]=22;
                    expected_glyph[21]=23;
                    expected_glyph[22]=24;
                    ink[0]=24'hffff00;
                    ink[1]=24'hffff00;
                    ink[2]=24'hffffff;
                end
                11: begin
                    demo_mode=0;box_valid=0;expected_shape=0;expected_color=0;shape=0;color=0;
                    expected_glyph[0]=5;
                    expected_glyph[1]=6;
                    expected_glyph[2]=3;
                    expected_glyph[3]=4;
                    expected_glyph[9]=8;
                    expected_glyph[10]=9;
                    expected_glyph[11]=5;
                    expected_glyph[12]=6;
                    expected_glyph[13]=7;
                    expected_glyph[18]=10;
                    expected_glyph[19]=11;
                    expected_glyph[20]=25;
                    expected_glyph[21]=26;
                    expected_glyph[22]=27;
                    ink[0]=24'h00ffff;
                    ink[1]=24'hffffff;
                    ink[2]=24'hffffff;
                end
                12: begin
                    demo_mode=0;box_valid=1;expected_shape=0;expected_color=0;shape=3;color=3;
                    expected_glyph[0]=5;
                    expected_glyph[1]=6;
                    expected_glyph[2]=3;
                    expected_glyph[3]=4;
                    expected_glyph[9]=8;
                    expected_glyph[10]=9;
                    expected_glyph[11]=5;
                    expected_glyph[12]=6;
                    expected_glyph[13]=7;
                    expected_glyph[18]=10;
                    expected_glyph[19]=11;
                    expected_glyph[20]=14;
                    expected_glyph[21]=15;
                    expected_glyph[22]=20;
                    expected_glyph[23]=21;
                    expected_glyph[24]=17;
                    ink[0]=24'h00ffff;
                    ink[1]=24'hffffff;
                    ink[2]=24'h0000ff;
                end
            endcase
            for(ypos=0;ypos<128;ypos=ypos+1)
                for(xpos=0;xpos<352;xpos=xpos+1)begin
                    pixel_x=xpos;pixel_y=ypos;within_osd=xpos>=32&&xpos<320&&ypos>=16&&ypos<112;
                    if(within_osd)begin
                        line_index=(ypos-16)/32;column=(xpos-32)/32;
                        bits=reference_font(expected_glyph[line_index*9+column],((ypos-16)%32)/2);
                        wanted=bits[15-((xpos-32)%32)/2]?((line_index>0&&column<2)?24'hffffff:ink[line_index]):24'h202020;
                    end
                    #1;checks=checks+1;
                    if(active!==within_osd||(within_osd&&rgb!==wanted))begin errors=errors+1;if(errors<8)$display("ERROR osd case=%0d xy=%0d,%0d actual=%h expected=%h",case_index,xpos,ypos,rgb,wanted);end
                end
        end
        test_done=1;$display("RESULT osd errors=%0d cases=%0d pixels=%0d",errors,case_index,checks);$stop;
    end
endmodule
