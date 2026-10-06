`timescale 1ns/1ps
module tb_capacity;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0,frame_tick=0,in_valid=0,in_sof=0,in_eol=0;
    reg [10:0] in_x=0;
    reg [9:0] in_y=0;
    reg [1:0] in_color=0;
    wire out_frame,out_valid;
    wire [1:0] out_color;
    wire [21:0] out_area;
    wire [10:0] out_left,out_right;
    wire [9:0] out_top,out_bottom;
    integer errors=0,checked=0,frame_index,column_index,row_index;
    reg test_done=0;
    color_bbox_stats #(.X_MIN(0),.X_MAX(1279),.Y_MIN(0),.Y_MAX(719),
        .RUN_LENGTH(1),.MIN_AREA(1),.MIN_WIDTH(1),.MIN_HEIGHT(1)) dut (
        .clk(clk),.rst_n(rst_n),.frame_tick(frame_tick),.in_valid(in_valid),.in_sof(in_sof),
        .in_eol(in_eol),.in_x(in_x),.in_y(in_y),.in_color(in_color),.out_frame(out_frame),
        .out_valid(out_valid),.out_color(out_color),.out_area(out_area),.out_left(out_left),
        .out_right(out_right),.out_top(out_top),.out_bottom(out_bottom));
    initial begin
        repeat(3)@(negedge clk);rst_n=1;
        for(frame_index=0;frame_index<2;frame_index=frame_index+1)begin
            for(row_index=0;row_index<720;row_index=row_index+1)begin
                for(column_index=0;column_index<1280;column_index=column_index+1)begin
                    @(negedge clk);in_valid=1;in_sof=row_index==0&&column_index==0;
                    in_eol=column_index==1279;in_x=column_index;in_y=row_index;
                    in_color=frame_index==0 ? 2'd1 : row_index==719 && column_index>=1277 ? 2'd3 : 2'd0;
                    checked=checked+1;
                end
                @(negedge clk);in_valid=0;in_sof=0;in_eol=0;
            end
            @(negedge clk);frame_tick=1;@(posedge clk);#1;
            if(!out_frame||!out_valid)errors=errors+1;
            if(frame_index==0)begin
                if(out_area!=921600||out_color!=1||out_left!=0||out_right!=1279||out_top!=0||out_bottom!=719)errors=errors+1;
            end else if(out_area!=3||out_color!=3||out_left!=1277||out_right!=1279||out_top!=719||out_bottom!=719)errors=errors+1;
            @(negedge clk);frame_tick=0;
        end
        test_done=1;$display("RESULT capacity errors=%0d checked=%0d",errors,checked);$stop;
    end
endmodule
