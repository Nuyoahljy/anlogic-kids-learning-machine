`timescale 1ns/1ps
module tb_sequence;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0,frame_tick=0;
    wire demo_mode,scene_changed;
    wire [3:0] scene;
    wire [15:0] scene_frame;
    wire [1:0] expected_shape,expected_color;
    integer errors=0,checks=0,frame_index;
    reg test_done=0;
    demo_sequence dut(.*);
    task check(input bit condition);
        begin checks=checks+1;if(!condition)begin errors=errors+1;if(errors<8)$display("ERROR sequence frame=%0d",frame_index);end end
    endtask
    initial begin
        repeat(3)@(negedge clk);rst_n=1;
        for(frame_index=0;frame_index<=1805;frame_index=frame_index+1)begin
            @(negedge clk);frame_tick=1;@(negedge clk);frame_tick=0;
            check(demo_mode===(frame_index<1800));
            check(scene===(frame_index<1800?frame_index/180:9));
            check(scene_frame===(frame_index<1800?frame_index%180:0));
            check(scene_changed===(frame_index>0&&frame_index<=1800&&frame_index%180==0));
            check(expected_shape===(frame_index<1620?((frame_index/180)%3)+1:0));
            check(expected_color===(frame_index<1620?(frame_index/540)+1:0));
            repeat(2)@(negedge clk);check(scene_changed===0);
        end
        rst_n=0;@(negedge clk);check(demo_mode===1&&scene===0&&scene_frame===0);
        rst_n=1;@(negedge clk);frame_tick=1;@(negedge clk);frame_tick=0;check(scene_frame===0);
        test_done=1;$display("RESULT sequence errors=%0d checks=%0d",errors,checks);$stop;
    end
endmodule
