`timescale 1ns/1ps
module tb_shapes;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0,in_vsync=0,in_hsync=0,in_de=0;
    reg [23:0] in_rgb=24'h808080;
    wire out_vsync,out_hsync,out_de;
    wire [23:0] out_rgb;
    integer errors=0,frames=0,pixels=0,shape_index,color_index,size_index,repeat_index;
    reg test_done=0;
    hdmi_shape #(.FRAME_WIDTH(128),.FRAME_HEIGHT(96),.X_MIN(8),.X_MAX(119),.Y_MIN(8),.Y_MAX(87)) dut(.*);
    task automatic fail(input string message);
        begin errors=errors+1;if(errors<=10)$display("ERROR shapes shape=%0d color=%0d size=%0d %s",shape_index,color_index,size_index,message);end
    endtask
    task automatic frame(input integer shape,color,size,input bit clipped,input integer expected_shape,input integer expected_stable);
        integer xpos,ypos,local_x,local_y,left,top,offset_x,offset_y;
        reg hit;
        begin
            left=clipped?8:32;top=16;
            for(ypos=0;ypos<96;ypos=ypos+1)begin
                for(xpos=0;xpos<128;xpos=xpos+1)begin
                    @(negedge clk);in_de=1;in_hsync=0;
                    local_x=xpos-left;local_y=ypos-top;
                    offset_x=2*local_x-(size-1);offset_y=2*local_y-(size-1);
                    hit=local_x>=0&&local_x<size&&local_y>=0&&local_y<size;
                    if(shape==1)hit=hit&&(offset_x*offset_x+offset_y*offset_y<=size*size);
                    else if(shape==3)hit=hit&&(offset_x<0?-offset_x:offset_x)<=local_y;
                    else if(shape==0)hit=0;
                    in_rgb=!hit?24'h808080:color==1?24'hff0000:color==2?24'hffff00:24'h0000ff;
                    pixels=pixels+1;
                end
                @(negedge clk);in_de=0;in_hsync=1;repeat(3)@(negedge clk);
            end
            repeat(8)@(negedge clk);in_vsync=1;repeat(64)@(negedge clk);
            if(dut.raw_shape!==expected_shape)fail("raw class");
            if(dut.stable_shape!==expected_stable)fail("confirmation");
            if(expected_stable!=0 && dut.stable_shape_color!==color)fail("color");
            in_vsync=0;repeat(8)@(negedge clk);frames=frames+1;
        end
    endtask
    initial begin
        repeat(3)@(negedge clk);rst_n=1;in_vsync=1;repeat(64)@(negedge clk);in_vsync=0;repeat(8)@(negedge clk);
        for(size_index=32;size_index<=64;size_index=size_index+16)
            for(shape_index=1;shape_index<=3;shape_index=shape_index+1)
                for(color_index=1;color_index<=3;color_index=color_index+1)begin
                    frame(0,1,size_index,0,0,0);
                    for(repeat_index=1;repeat_index<=3;repeat_index=repeat_index+1)
                        frame(shape_index,color_index,size_index,0,shape_index,repeat_index<3?0:shape_index);
                end
        frame(2,1,40,1,0,0);
        frame(0,1,40,0,0,0);
        test_done=1;$display("RESULT shapes errors=%0d frames=%0d pixels=%0d",errors,frames,pixels);$stop;
    end
endmodule
