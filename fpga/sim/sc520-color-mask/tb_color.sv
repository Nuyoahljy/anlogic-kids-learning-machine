`timescale 1ns/1ps
module tb_color;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg [23:0] in_rgb = 0;
    reg [10:0] in_x = 0;
    reg [9:0] in_y = 0;
    reg in_valid = 0, in_sof = 0, in_eol = 0;
    wire [23:0] out_rgb;
    wire [10:0] out_x;
    wire [9:0] out_y;
    wire out_valid, out_sof, out_eol, out_roi;
    wire [1:0] out_color;
    integer errors = 0, checked = 0;
    integer histogram [0:3];
    integer red_index, green_index, blue_index, sample_index, boundary_index;
    integer thresholds [0:15];
    reg test_done = 0;
    reg [31:0] random_state = 32'h927351ac;
    `include "color_reference.svh"

    rgb_color_segment dut (
        .clk(clk), .rst_n(rst_n), .in_rgb(in_rgb), .in_x(in_x), .in_y(in_y),
        .in_valid(in_valid), .in_sof(in_sof), .in_eol(in_eol), .out_rgb(out_rgb),
        .out_x(out_x), .out_y(out_y), .out_valid(out_valid), .out_sof(out_sof),
        .out_eol(out_eol), .out_roi(out_roi), .out_color(out_color)
    );

    task automatic fail(input string message);
        begin
            errors = errors + 1;
            if (errors <= 8) $display("ERROR color: %s at %0t", message, $time);
        end
    endtask

    task automatic check_pixel(input [23:0] rgb, input integer xpos, input integer ypos,
                               input bit valid, input bit sof, input bit eol);
        reg expected_roi;
        reg [1:0] expected_color;
        begin
            @(negedge clk);
            in_rgb = rgb; in_x = xpos; in_y = ypos;
            in_valid = valid; in_sof = sof; in_eol = eol;
            expected_roi = valid && xpos >= 320 && xpos <= 959 && ypos >= 120 && ypos <= 599;
            expected_color = expected_roi ? reference_color(rgb) : 2'd0;
            @(posedge clk); #1;
            if (out_valid !== valid || out_sof !== (valid && sof) || out_eol !== (valid && eol)) fail("metadata latency");
            if (out_rgb !== (valid ? rgb : 24'd0) || out_x !== (valid ? xpos : 0) ||
                out_y !== (valid ? ypos : 0)) fail("RGB/coordinates latency");
            if (out_roi !== expected_roi || out_color !== expected_color) fail("ROI/color mismatch");
            histogram[expected_color] = histogram[expected_color] + 1;
            checked = checked + 1;
        end
    endtask

    initial begin
        for (sample_index=0; sample_index<4; sample_index=sample_index+1) histogram[sample_index]=0;
        thresholds[0]=0; thresholds[1]=23; thresholds[2]=24; thresholds[3]=31;
        thresholds[4]=32; thresholds[5]=47; thresholds[6]=48; thresholds[7]=79;
        thresholds[8]=80; thresholds[9]=95; thresholds[10]=96; thresholds[11]=97;
        thresholds[12]=127; thresholds[13]=223; thresholds[14]=254; thresholds[15]=255;
        repeat(3) @(negedge clk);
        if ({out_rgb,out_x,out_y,out_valid,out_sof,out_eol,out_roi,out_color} !== 51'd0) fail("initial reset");
        rst_n = 1;
        if (reference_color(24'hff0000)!=1 || reference_color(24'hffff00)!=2 ||
            reference_color(24'h0000ff)!=3 || reference_color(24'hffffff)!=0 ||
            reference_color(24'h00ff00)!=0 || reference_color(24'hff00ff)!=0) fail("reference anchors");
        for (red_index=0; red_index<16; red_index=red_index+1)
            for (green_index=0; green_index<16; green_index=green_index+1)
                for (blue_index=0; blue_index<16; blue_index=blue_index+1)
                    check_pixel({8'(thresholds[red_index]),8'(thresholds[green_index]),8'(thresholds[blue_index])},
                                640,360,1,red_index==0,blue_index==15);
        for (red_index=0; red_index<256; red_index=red_index+1)
            for (green_index=0; green_index<256; green_index=green_index+1) begin
                check_pixel({8'(red_index),8'(green_index),8'd0},640,360,1,0,0);
                check_pixel({8'(green_index),8'd255,8'(red_index)},640,360,1,0,0);
            end
        for (sample_index=0; sample_index<20000; sample_index=sample_index+1) begin
            random_state = {random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
            check_pixel(random_state[23:0],640,360,sample_index%7!=0,sample_index%11==0,sample_index%13==0);
        end
        for (boundary_index=0; boundary_index<2; boundary_index=boundary_index+1) begin
            for (sample_index=319; sample_index<=321; sample_index=sample_index+1)
                check_pixel(24'hff0000,sample_index+boundary_index*639,360,1,0,0);
            for (sample_index=119; sample_index<=121; sample_index=sample_index+1)
                check_pixel(24'h0000ff,640,sample_index+boundary_index*479,1,0,0);
        end
        check_pixel(24'hffff00,320,120,1,1,0);
        check_pixel(24'hffff00,959,599,1,0,1);
        @(negedge clk); rst_n=0; #1;
        if ({out_rgb,out_x,out_y,out_valid,out_sof,out_eol,out_roi,out_color} !== 51'd0) fail("midstream async reset");
        @(negedge clk); rst_n=1;
        check_pixel(24'h0000ff,640,360,1,1,1);
        for (sample_index=0; sample_index<4; sample_index=sample_index+1)
            if(histogram[sample_index]<100) fail("missing class coverage");
        test_done=1;
        $display("RESULT color errors=%0d checked=%0d none=%0d red=%0d yellow=%0d blue=%0d",errors,checked,histogram[0],histogram[1],histogram[2],histogram[3]);
        $stop;
    end
endmodule
