`timescale 1ns/1ps
module tb_stability;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0,in_frame=0,in_valid=0;
    reg [1:0] in_color=0;
    reg [10:0] in_left=0,in_right=0;
    reg [9:0] in_top=0,in_bottom=0;
    wire out_valid;
    wire [1:0] out_color;
    wire [10:0] out_left,out_right;
    wire [9:0] out_top,out_bottom;
    wire [7:0] stable_count;
    integer errors=0,checked=0,repeat_index;
    reg test_done=0;
    bbox_stabilizer dut (.clk(clk),.rst_n(rst_n),.in_frame(in_frame),.in_valid(in_valid),
        .in_color(in_color),.in_left(in_left),.in_right(in_right),.in_top(in_top),.in_bottom(in_bottom),
        .out_valid(out_valid),.out_color(out_color),.out_left(out_left),.out_right(out_right),
        .out_top(out_top),.out_bottom(out_bottom),.stable_count(stable_count));
    task automatic fail(input string message);
        begin errors=errors+1;if(errors<=12)$display("ERROR stability checked=%0d %s",checked,message);end
    endtask
    task automatic frame(input bit valid,input [1:0] color,input integer xpos,
        input bit expected_valid,input [1:0] expected_color,input integer expected_x,input integer expected_count);
        begin
            @(negedge clk);in_frame=1;in_valid=valid;in_color=color;
            in_left=xpos;in_right=xpos+19;in_top=100;in_bottom=119;
            @(posedge clk);#1;
            if(out_valid!==expected_valid || out_color!==expected_color || stable_count!==expected_count)fail("valid/color/count");
            if(expected_valid)begin
                if(out_left!==expected_x || out_right!==expected_x+19 || out_top!==100 || out_bottom!==119)fail("bounds");
            end else if({out_left,out_right,out_top,out_bottom}!==42'd0)fail("stale hidden bounds");
            @(negedge clk);in_frame=0;in_left=900;in_color=0;
            repeat(3)@(posedge clk);#1;
            if(out_valid!==expected_valid || out_color!==expected_color || stable_count!==expected_count)fail("changed outside frame boundary");
            checked=checked+1;
        end
    endtask
    initial begin
        repeat(3)@(negedge clk);rst_n=1;
        frame(1,1,100,0,0,0,1);frame(1,1,100,0,0,0,2);frame(1,1,100,1,1,100,3);
        frame(1,1,101,1,1,100,4);frame(1,1,108,1,1,108,5);
        frame(0,0,0,1,1,108,0);frame(1,1,108,1,1,108,1);
        frame(0,0,0,1,1,108,0);frame(0,0,0,0,0,0,0);
        frame(1,3,200,0,0,0,1);frame(1,3,200,0,0,0,2);frame(1,3,200,1,3,200,3);
        frame(1,3,300,0,0,0,1);frame(1,3,300,0,0,0,2);frame(1,3,300,1,3,300,3);
        frame(1,2,300,0,0,0,1);frame(1,2,300,0,0,0,2);frame(1,2,300,1,2,300,3);
        for(repeat_index=4;repeat_index<=300;repeat_index=repeat_index+1)
            frame(1,2,300,1,2,300,repeat_index<255?repeat_index:255);
        frame(1,0,300,1,2,300,0);frame(1,0,300,0,0,0,0);
        frame(1,1,400,0,0,0,1);frame(1,3,400,0,0,0,1);frame(1,1,400,0,0,0,1);
        @(negedge clk);rst_n=0;#1;
        if({out_valid,out_color,out_left,out_right,out_top,out_bottom,stable_count}!==53'd0)fail("async reset");
        @(negedge clk);rst_n=1;
        frame(1,1,400,0,0,0,1);frame(1,1,400,0,0,0,2);frame(1,1,400,1,1,400,3);
        @(negedge clk);in_frame=1;in_valid=1;in_color=1;in_left=450;in_right=400;
        @(posedge clk);#1;if(!out_valid || stable_count!=0)fail("first invalid geometry miss");
        @(negedge clk);in_frame=0;@(negedge clk);in_frame=1;
        @(posedge clk);#1;if(out_valid || out_color!=0)fail("invalid geometry clear");
        @(negedge clk);in_frame=0;
        test_done=1;$display("RESULT stability errors=%0d checked=%0d",errors,checked);$stop;
    end
endmodule
