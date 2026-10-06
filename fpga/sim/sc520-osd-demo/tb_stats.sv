`timescale 1ns/1ps
module tb_stats;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0, frame_tick=0, in_valid=0, in_sof=0, in_eol=0;
    reg [10:0] in_x=0;
    reg [9:0] in_y=0;
    reg [1:0] in_color=0;
    wire out_frame,out_valid;
    wire [1:0] out_color;
    wire [21:0] out_area;
    wire [10:0] out_left,out_right;
    wire [9:0] out_top,out_bottom;
    integer errors=0, cases=0, checked=0, column_index,row_index,scenario;
    reg test_done=0;
    reg [1:0] image [0:15][0:31];
    color_bbox_stats #(.FRAME_WIDTH(32),.FRAME_HEIGHT(16),.X_MIN(4),.X_MAX(27),
        .Y_MIN(2),.Y_MAX(13),.MIN_AREA(12),.MIN_WIDTH(3),.MIN_HEIGHT(2)) dut (
        .clk(clk),.rst_n(rst_n),.frame_tick(frame_tick),.in_valid(in_valid),.in_sof(in_sof),
        .in_eol(in_eol),.in_x(in_x),.in_y(in_y),.in_color(in_color),.out_frame(out_frame),
        .out_valid(out_valid),.out_color(out_color),.out_area(out_area),.out_left(out_left),
        .out_right(out_right),.out_top(out_top),.out_bottom(out_bottom));
    task automatic fail(input string message);
        begin errors=errors+1; if(errors<=12) $display("ERROR stats case=%0d %s",scenario,message); end
    endtask
    task automatic clear_image;
        integer xpos,ypos;
        begin
            for(ypos=0;ypos<16;ypos=ypos+1)
                for(xpos=0;xpos<32;xpos=xpos+1) image[ypos][xpos]=0;
        end
    endtask
    task automatic rectangle(input integer left,right,top,bottom,input [1:0] color);
        integer xpos,ypos;
        begin
            for(ypos=top;ypos<=bottom;ypos=ypos+1)
                for(xpos=left;xpos<=right;xpos=xpos+1) image[ypos][xpos]=color;
        end
    endtask
    task automatic run_frame(input bit valid,input [1:0] color,input integer area,left,right,top,bottom,
                              input integer fault);
        begin
            for(row_index=0;row_index<16;row_index=row_index+1) begin
                for(column_index=0;column_index<32;column_index=column_index+1) begin
                    @(negedge clk);
                    in_x=column_index; in_y=row_index;
                    in_color=image[row_index][column_index];
                    in_valid=!(fault==1 && row_index==15 && column_index==31);
                    in_sof=(row_index==0 && column_index==0) || (fault==2 && row_index==8 && column_index==0);
                    in_eol=(column_index==31) && !(fault==3 && row_index==7);
                    if(fault==4 && row_index==8 && column_index==0) begin rst_n=0; #1; rst_n=1; end
                    @(posedge clk); #1;
                    if(out_frame) fail("frame report during active video");
                    checked=checked+1;
                end
                @(negedge clk); in_valid=0; in_sof=0; in_eol=0;
                repeat(2) @(negedge clk);
            end
            @(negedge clk); frame_tick=1;
            @(posedge clk); #1;
            if(!out_frame || out_valid!==valid) fail("frame validity");
            if(valid) begin
                if(out_color!==color || out_area!==area || out_left!==left || out_right!==right ||
                    out_top!==top || out_bottom!==bottom) fail("area/color/bounds");
            end else if({out_color,out_area,out_left,out_right,out_top,out_bottom}!==66'd0) fail("invalid result not cleared");
            @(negedge clk); frame_tick=0;
            @(posedge clk); #1;
            if(out_frame) fail("frame strobe not one cycle");
            cases=cases+1;
        end
    endtask
    initial begin
        repeat(3) @(negedge clk); rst_n=1;
        scenario=0; clear_image; run_frame(0,0,0,0,0,0,0,0);
        scenario=1; rectangle(6,13,4,7,1); run_frame(1,1,32,6,13,4,7,0);
        scenario=2; clear_image;
        for(row_index=2;row_index<=13;row_index=row_index+1) begin image[row_index][4]=1; image[row_index][20]=1;image[row_index][21]=1;end
        run_frame(0,0,0,0,0,0,0,0);
        scenario=3; clear_image; rectangle(6,13,4,7,1);image[12][25]=1;image[12][26]=1;run_frame(1,1,32,6,13,4,7,0);
        scenario=4; clear_image; rectangle(14,19,6,9,3);run_frame(1,3,24,14,19,6,9,0);
        scenario=5; clear_image; rectangle(4,6,2,5,2);run_frame(1,2,12,4,6,2,5,0);
        scenario=6; clear_image; rectangle(4,6,2,4,2);run_frame(0,0,0,0,0,0,0,0);
        scenario=7; clear_image; rectangle(4,4,2,13,1);run_frame(0,0,0,0,0,0,0,0);
        scenario=8; clear_image; rectangle(4,27,2,2,1);run_frame(0,0,0,0,0,0,0,0);
        scenario=9; clear_image; rectangle(6,13,4,7,1);rectangle(18,25,8,11,3);run_frame(0,0,0,0,0,0,0,0);
        scenario=10; clear_image; rectangle(6,13,4,7,1);rectangle(18,21,8,11,3);run_frame(1,1,32,6,13,4,7,0);
        scenario=11; clear_image; rectangle(6,13,4,7,1);rectangle(18,22,8,11,3);run_frame(0,0,0,0,0,0,0,0);
        for(scenario=12;scenario<=15;scenario=scenario+1) begin
            clear_image;rectangle(6,13,4,7,1);run_frame(0,0,0,0,0,0,0,scenario-11);
        end
        scenario=16;clear_image;rectangle(4,27,2,13,2);run_frame(1,2,288,4,27,2,13,0);
        scenario=17;clear_image;rectangle(0,31,0,15,1);rectangle(4,27,2,13,0);run_frame(0,0,0,0,0,0,0,0);
        scenario=18;clear_image;rectangle(24,27,11,13,3);run_frame(1,3,12,24,27,11,13,0);
        test_done=1;$display("RESULT stats errors=%0d cases=%0d checked=%0d",errors,cases,checked);$stop;
    end
endmodule
