`timescale 1ns/1ps
module tb_sync;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0, in_vs=0, in_hs=0, in_de=0;
    reg [23:0] in_rgb=0;
    wire out_vs,out_hs,out_de;
    wire [23:0] out_rgb;
    reg [26:0] expected [0:2];
    reg [23:0] expected_rgb;
    reg [1:0] color;
    reg test_done=0;
    integer errors=0, checked=0, column_index, row_index;
    `include "color_reference.svh"
    hdmi_dynamic_box #(.FRAME_WIDTH(16),.FRAME_HEIGHT(4),.X_MIN(4),.X_MAX(11),.Y_MIN(1),.Y_MAX(2)) dut (
        .clk(clk),.rst_n(rst_n),.in_vsync(in_vs),.in_hsync(in_hs),.in_de(in_de),.in_rgb(in_rgb),
        .out_vsync(out_vs),.out_hsync(out_hs),.out_de(out_de),.out_rgb(out_rgb));

    task automatic fail(input string message);
        begin
            errors=errors+1;
            if(errors<=8) $display("ERROR sync: %s checked=%0d",message,checked);
        end
    endtask

    task automatic cycle(input bit vs, input bit de, input [23:0] rgb,
                         input bit accepted, input integer xpos, input integer ypos);
        begin
            @(negedge clk);
            in_vs=vs; in_de=de; in_hs=!de; in_rgb=rgb;
            expected_rgb=de ? rgb : 0;
            if(de && accepted && xpos>=4 && xpos<=11 && ypos>=1 && ypos<=2) begin
                color=reference_color(rgb);
                case(color)
                    1: expected_rgb=24'hff0000;
                    2: expected_rgb=24'hffff00;
                    3: expected_rgb=24'h0000ff;
                    default: expected_rgb=0;
                endcase
                if(xpos==4 || xpos==11 || ypos==1 || ypos==2) expected_rgb=24'hff0000;
            end
            expected[2]=expected[1]; expected[1]=expected[0];
            expected[0]={vs,!de,de,expected_rgb};
            @(posedge clk); #1;
            if({out_vs,out_hs,out_de,out_rgb}!==expected[2]) fail("lost sync/fallback/latency");
            checked=checked+1;
        end
    endtask

    task automatic frame_start;
        begin
            cycle(1,0,0,0,0,0); cycle(1,0,0,0,0,0);
            cycle(0,0,0,0,0,0); cycle(0,0,0,0,0,0);
        end
    endtask

    task automatic row(input integer ypos,input integer length,input bit synced);
        integer xpos;
        begin
            for(xpos=0;xpos<length;xpos=xpos+1)
                cycle(0,1,24'h314159,synced && xpos<16 && !((xpos==length-1)!=(xpos==15)),xpos,ypos);
            repeat(3) cycle(0,0,24'hffffff,0,0,0);
        end
    endtask

    task automatic reset_check;
        begin
            @(negedge clk); rst_n=0; #1;
            if({out_vs,out_hs,out_de,out_rgb}!==27'd0) fail("async reset");
            expected[0]=0; expected[1]=0; expected[2]=0;
            @(negedge clk); in_de=0; in_vs=0; in_hs=0; in_rgb=0;
            rst_n=1;
        end
    endtask

    initial begin
        expected[0]=0; expected[1]=0; expected[2]=0;
        repeat(2) @(negedge clk); rst_n=1;
        row(0,16,0);
        frame_start;
        row(0,16,1); row(1,8,1); row(2,16,0); row(3,16,0);
        frame_start;
        for(row_index=0;row_index<4;row_index=row_index+1) row(row_index,16,1);
        frame_start;
        row(0,16,1); row(1,18,1); row(2,16,0); row(3,16,0);
        frame_start;
        row(0,16,1);
        for(column_index=0;column_index<8;column_index=column_index+1)
            cycle(0,1,24'h314159,1,column_index,1);
        reset_check;
        row(0,16,0);
        frame_start;
        for(row_index=0;row_index<4;row_index=row_index+1) row(row_index,16,1);
        repeat(6) cycle(0,0,0,0,0,0);
        test_done=1;
        $display("RESULT sync errors=%0d checked=%0d",errors,checked);
        $stop;
    end
endmodule
