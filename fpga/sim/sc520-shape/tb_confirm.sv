`timescale 1ns/1ps
module tb_confirm;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0,in_frame=0;
    reg [1:0] in_shape=0,in_color=0;
    wire [1:0] out_shape,out_color;
    wire [7:0] count;
    integer errors=0,checked=0,repeat_index;
    reg test_done=0;
    shape_confirm dut(.*);
    task automatic sample(input integer shape,color,expected_shape,expected_color,expected_count);
        begin
            @(negedge clk);in_frame=1;in_shape=shape;in_color=color;
            @(posedge clk);#1;
            if(out_shape!==expected_shape||out_color!==expected_color||count!==expected_count)errors=errors+1;
            @(negedge clk);in_frame=0;in_shape=0;
            repeat(3)@(posedge clk);#1;
            if(out_shape!==expected_shape||out_color!==expected_color||count!==expected_count)errors=errors+1;
            checked=checked+1;
        end
    endtask
    initial begin
        repeat(3)@(negedge clk);rst_n=1;
        sample(1,1,0,0,1);sample(1,1,0,0,2);sample(1,1,1,1,3);
        sample(2,1,0,0,1);sample(2,1,0,0,2);sample(2,1,2,1,3);
        sample(2,2,0,0,1);sample(2,2,0,0,2);sample(2,2,2,2,3);
        sample(0,2,0,0,0);sample(2,2,0,0,1);sample(3,3,0,0,1);sample(3,3,0,0,2);sample(3,3,3,3,3);
        for(repeat_index=4;repeat_index<=270;repeat_index=repeat_index+1)sample(3,3,3,3,repeat_index<255?repeat_index:255);
        sample(3,0,0,0,0);
        @(negedge clk);rst_n=0;#1;if(out_shape||out_color||count)errors=errors+1;
        test_done=1;$display("RESULT confirm errors=%0d checked=%0d",errors,checked);$stop;
    end
endmodule
