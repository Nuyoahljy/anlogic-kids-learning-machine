`timescale 1ns/1ps
module tb_display;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    wire vtc_vs, vtc_hs, vtc_de, vtc_sof, vtc_eol;
    wire raw_vs, raw_hs, raw_de, read_enable;
    wire [23:0] raw_rgb;
    wire out_vs, out_hs, out_de;
    wire [23:0] out_rgb;
    reg [23:0] pattern = 24'h123456;
    integer errors = 0;
    integer checked_cycles = 0;
    integer checked_pixels = 0;
    integer full_frames = 0;
    integer all_full_frames = 0;
    integer border_pixels = 0;
    integer bypass_pixels = 0;
    integer reset_checks = 0;
    integer inherited_read_skips = 0;
    integer phase = 0;
    reg test_done = 0;
    reg [26:0] expected [0:2];
    reg previous_vs = 0;
    reg reference_armed = 0;
    integer pixel_index = 0;
    integer pixel_x;
    integer pixel_y;
    integer frame_border = 0;
    reg [23:0] expected_rgb;
    reg edge_pixel;
    reg negative_control = 0;

    uivtc #(.H_ActiveSize(1280), .H_FrameSize(1650),
        .H_SyncStart(1390), .H_SyncEnd(1430),
        .V_ActiveSize(720), .V_FrameSize(750),
        .V_SyncStart(725), .V_SyncEnd(730)) timing (
        .I_vtc_rstn(rst_n), .I_vtc_clk(clk),
        .O_vtc_vs(vtc_vs), .O_vtc_hs(vtc_hs), .O_vtc_de_valid(vtc_de),
        .O_vtc_user(vtc_sof), .O_vtc_last(vtc_eol));

    hdmi_mixer #(.H_OFFSET(0), .V_OFFSET(0), .IMG_WIDTH(1280),
        .IMG_HEIGHT(720), .DEBUG_MODE(0)) mixer (
        .I_clk(clk), .I_rst_n(rst_n),
        .I_video_vsync(vtc_vs), .I_video_hsync(vtc_hs), .I_video_de(vtc_de),
        .I_video_user(vtc_sof), .I_video_last(vtc_eol), .I_debug_status(4'd0),
        .O_video_rd_en(read_enable), .I_video_rd_data(pattern),
        .O_hdmi_vsync(raw_vs), .O_hdmi_hsync(raw_hs),
        .O_hdmi_de(raw_de), .O_hdmi_data(raw_rgb));

    hdmi_roi_overlay dut (.clk(clk), .rst_n(rst_n),
        .in_vsync(raw_vs), .in_hsync(raw_hs), .in_de(raw_de), .in_rgb(raw_rgb),
        .out_vsync(out_vs), .out_hsync(out_hs), .out_de(out_de), .out_rgb(out_rgb));

    always @(posedge clk) begin
        if (!rst_n) pattern <= 24'h123456;
        else pattern <= pattern + 24'h030507;
    end

    task automatic fail(input string message);
        begin
            errors = errors + 1;
            if (errors <= 8) $display("ERROR display: %s at %0t", message, $time);
        end
    endtask

    always @(posedge clk) begin
        if (!rst_n) begin
            expected[0] = 0;
            expected[1] = 0;
            expected[2] = 0;
            previous_vs = 0;
            reference_armed = 0;
            pixel_index = 0;
            full_frames = 0;
            frame_border = 0;
            #1;
            if ({out_vs,out_hs,out_de,out_rgb} !== 27'd0) fail("reset outputs not zero");
            reset_checks = reset_checks + 1;
        end else begin
            if (raw_vs && !previous_vs) begin
                reference_armed = 1;
                pixel_index = 0;
                frame_border = 0;
            end
            previous_vs = raw_vs;
            expected_rgb = raw_de ? raw_rgb : 24'd0;
            if (raw_de && reference_armed) begin
                pixel_x = pixel_index % 1280;
                pixel_y = pixel_index / 1280;
                edge_pixel = ((pixel_x == 320 || pixel_x == 959) && pixel_y >= 120 && pixel_y <= 599) ||
                             ((pixel_y == 120 || pixel_y == 599) && pixel_x >= 320 && pixel_x <= 959);
                if (edge_pixel) begin
                    expected_rgb = 24'hff0000;
                    frame_border = frame_border + 1;
                    border_pixels = border_pixels + 1;
                end
                pixel_index = pixel_index + 1;
                if (pixel_index == 1280*720) begin
                    if (frame_border != 2236) fail("wrong full-frame border count");
                    full_frames = full_frames + 1;
                    all_full_frames = all_full_frames + 1;
                    reference_armed = 0;
                end
            end else if (raw_de) bypass_pixels = bypass_pixels + 1;
            expected[2] = expected[1];
            expected[1] = expected[0];
            expected[0] = {raw_vs,raw_hs,raw_de,expected_rgb};
            if (read_enable && !vtc_de) fail("DDR read outside active video");
            if (vtc_de && !read_enable) inherited_read_skips = inherited_read_skips + 1;
            #1;
            if ({out_vs,out_hs,out_de,out_rgb} !== expected[2]) fail("RGB/DE/VS/HS or three-stage latency mismatch");
            checked_cycles = checked_cycles + 1;
            if (out_de) checked_pixels = checked_pixels + 1;
        end
    end

    initial begin
        negative_control = $test$plusargs("negative_control");
        repeat (8) @(negedge clk);
        rst_n = 1;
        phase = 1;
        wait(full_frames == 2);
        wait(reference_armed && pixel_index == 1280*100+501);
        @(negedge clk);
        rst_n = 0;
        phase = 2;
        repeat (8) @(negedge clk);
        rst_n = 1;
        wait(full_frames == 3);
        repeat (8) @(negedge clk);
        if (all_full_frames != 5 || bypass_pixels < 1280*720 || reset_checks < 16) fail("coverage incomplete");
        test_done = 1;
        $display("RESULT display errors=%0d full_frames=%0d checked_cycles=%0d checked_pixels=%0d border_pixels=%0d bypass_pixels=%0d reset_checks=%0d", errors, all_full_frames, checked_cycles, checked_pixels, border_pixels, bypass_pixels, reset_checks);
        $display("BASELINE_OBSERVATION inherited_read_skips=%0d (unaltered vendor VTC/mixer; not a DDR verification)", inherited_read_skips);
        $stop;
    end

    initial begin
        #150000000;
        $display("TIMEOUT display");
        errors = errors + 1;
        $stop;
    end

    initial begin
        #1;
        if (negative_control) begin
            wait(out_de);
            @(negedge clk);
            force dut.out_rgb = 24'hdeadbe;
            repeat (4) @(negedge clk);
            release dut.out_rgb;
        end
    end
endmodule
