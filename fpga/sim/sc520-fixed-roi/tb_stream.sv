`timescale 1ns/1ps
module tb_stream;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg [23:0] in_rgb = 0;
    reg in_valid = 0, in_sof = 0, in_eol = 0;
    wire [23:0] coord_rgb, out_rgb;
    wire [10:0] coord_x, out_x;
    wire [9:0] coord_y, out_y;
    wire coord_valid, coord_sof, coord_eol;
    wire out_valid, out_sof, out_eol;
    integer errors = 0;
    integer checked_cycles = 0;
    integer border_pixels = 0;
    integer gaps = 0;
    integer column_index, row_index, frame_index;
    reg test_done = 0;
    reg [47:0] expected0 = 0, expected1 = 0;
    reg [47:0] next_expected = 0;

    pixel_coord_adapter coordinates (.clk(clk), .rst_n(rst_n),
        .in_rgb(in_rgb), .in_valid(in_valid), .in_sof(in_sof), .in_eol(in_eol),
        .out_rgb(coord_rgb), .out_x(coord_x), .out_y(coord_y),
        .out_valid(coord_valid), .out_sof(coord_sof), .out_eol(coord_eol));
    fixed_rect_overlay rectangle (.clk(clk), .rst_n(rst_n),
        .in_rgb(coord_rgb), .in_x(coord_x), .in_y(coord_y),
        .in_valid(coord_valid), .in_sof(coord_sof), .in_eol(coord_eol),
        .out_rgb(out_rgb), .out_x(out_x), .out_y(out_y),
        .out_valid(out_valid), .out_sof(out_sof), .out_eol(out_eol));

    task automatic step(input bit valid_pixel, input bit first_pixel, input bit last_pixel,
        input integer horizontal, input integer vertical, input bit accepted);
        reg [23:0] source_rgb;
        reg [23:0] reference_rgb;
        reg border;
        begin
            @(negedge clk);
            source_rgb = {horizontal[7:0], vertical[7:0], 8'h35};
            in_rgb = source_rgb;
            in_valid = valid_pixel;
            in_sof = first_pixel;
            in_eol = last_pixel;
            border = ((horizontal == 320 || horizontal == 959) && vertical >= 120 && vertical <= 599) ||
                     ((vertical == 120 || vertical == 599) && horizontal >= 320 && horizontal <= 959);
            reference_rgb = border ? 24'hff0000 : source_rgb;
            next_expected = accepted ? {1'b1,first_pixel,last_pixel,horizontal[10:0],vertical[9:0],reference_rgb} : 48'd0;
            if (accepted && border) border_pixels = border_pixels + 1;
            if (!valid_pixel) gaps = gaps + 1;
            @(posedge clk);
            expected1 = expected0;
            expected0 = next_expected;
            #1;
            if ({out_valid,out_sof,out_eol,out_x,out_y,out_rgb} !== expected1) begin
                errors = errors + 1;
                if (errors <= 8) $display("ERROR stream actual=%h expected=%h", {out_valid,out_sof,out_eol,out_x,out_y,out_rgb}, expected1);
            end
            checked_cycles = checked_cycles + 1;
        end
    endtask

    initial begin
        repeat (4) @(negedge clk);
        rst_n = 1;
        step(1,0,0,0,0,0);
        step(0,1,1,0,0,0);
        for (frame_index=0; frame_index<2; frame_index=frame_index+1) begin
            for (row_index=0; row_index<720; row_index=row_index+1) begin
                for (column_index=0; column_index<1280; column_index=column_index+1) begin
                    step(1,column_index==0 && row_index==0,column_index==1279,column_index,row_index,1);
                    if (column_index%127==5) step(0,1,1,0,0,0);
                end
                step(0,0,0,0,0,0);
            end
        end
        step(1,0,0,0,0,0);
        step(1,1,0,0,0,1);
        step(1,0,1,1,0,0);
        step(1,0,0,2,0,0);
        step(1,1,0,0,0,1);
        step(1,0,0,1,0,1);
        step(0,0,0,0,0,0);
        step(0,0,0,0,0,0);
        @(negedge clk);
        rst_n=0;
        repeat(2) @(negedge clk);
        if ({out_valid,out_sof,out_eol,out_x,out_y,out_rgb} !== 48'd0) errors=errors+1;
        expected0=0;
        expected1=0;
        rst_n=1;
        step(1,0,0,0,0,0);
        step(1,1,0,0,0,1);
        step(1,0,0,1,0,1);
        step(0,0,0,0,0,0);
        step(0,0,0,0,0,0);
        if(border_pixels != 4472 || gaps < 10000) errors=errors+1;
        test_done=1;
        $display("RESULT stream errors=%0d full_frames=2 checked_cycles=%0d border_pixels=%0d gaps=%0d", errors,checked_cycles,border_pixels,gaps);
        $stop;
    end
endmodule
