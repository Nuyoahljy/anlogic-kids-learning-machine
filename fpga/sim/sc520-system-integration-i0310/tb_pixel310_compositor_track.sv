`timescale 1ns/1ps

module tb_pixel310_compositor_track;
    reg clk=0,rst_n=0;
    reg in_frame_start=0,in_de=1,in_hsync=0,in_vsync=0,mode_request=0;
    reg [1:0] style_request=0,calibration_state=0,tf_state=0;
    reg [10:0] in_x=0;reg [9:0] in_y=0;reg [23:0] in_rgb=24'h123456;
    reg [27:0] business_state=0;reg [191:0] recognition_packet=0;
    reg recognition_fresh=1,recognition_fault=0;reg [7:0] recognition_age=0;
    reg track_valid=0;reg [10:0] track_x=0,track_w=0;reg [9:0] track_y=0,track_h=0;
    wire en_fs,en_de,en_hs,en_vs,en_mode,en_panel,en_diag,en_logo;
    wire dis_fs,dis_de,dis_hs,dis_vs,dis_mode,dis_panel,dis_diag,dis_logo;
    wire [10:0] en_x,dis_x;wire [9:0] en_y,dis_y;wire [23:0] en_rgb,dis_rgb;
    integer errors=0;

    always #5 clk=~clk;

    pixel310_compositor_track #(.DIAGNOSTIC_ENABLE(1),.TRACK_ENABLE(1),.COORD_ENABLE(1)) enabled(
        .clk(clk),.rst_n(rst_n),.in_frame_start(in_frame_start),.in_de(in_de),
        .in_hsync(in_hsync),.in_vsync(in_vsync),.mode_request(mode_request),
        .style_request(style_request),.calibration_state(calibration_state),.tf_state(tf_state),
        .in_x(in_x),.in_y(in_y),.in_rgb(in_rgb),.business_state(business_state),
        .recognition_packet(recognition_packet),.recognition_fresh(recognition_fresh),
        .recognition_fault(recognition_fault),.recognition_age(recognition_age),
        .track_valid(track_valid),.track_x(track_x),.track_w(track_w),.track_y(track_y),.track_h(track_h),
        .out_frame_start(en_fs),.out_de(en_de),.out_hsync(en_hs),.out_vsync(en_vs),
        .out_mode(en_mode),.out_x(en_x),.out_y(en_y),.out_rgb(en_rgb),
        .out_panel_active(en_panel),.out_diag_active(en_diag),.out_logo_active(en_logo));
    pixel310_compositor_track #(.DIAGNOSTIC_ENABLE(0),.DETAIL_STATUS_ENABLE(0),
        .TRACK_ENABLE(1),.COORD_ENABLE(1)) disabled(
        .clk(clk),.rst_n(rst_n),.in_frame_start(in_frame_start),.in_de(in_de),
        .in_hsync(in_hsync),.in_vsync(in_vsync),.mode_request(mode_request),
        .style_request(style_request),.calibration_state(calibration_state),.tf_state(tf_state),
        .in_x(in_x),.in_y(in_y),.in_rgb(in_rgb),.business_state(business_state),
        .recognition_packet(recognition_packet),.recognition_fresh(recognition_fresh),
        .recognition_fault(recognition_fault),.recognition_age(recognition_age),
        .track_valid(track_valid),.track_x(track_x),.track_w(track_w),.track_y(track_y),.track_h(track_h),
        .out_frame_start(dis_fs),.out_de(dis_de),.out_hsync(dis_hs),.out_vsync(dis_vs),
        .out_mode(dis_mode),.out_x(dis_x),.out_y(dis_y),.out_rgb(dis_rgb),
        .out_panel_active(dis_panel),.out_diag_active(dis_diag),.out_logo_active(dis_logo));

    task settle(input integer cycles);
        begin repeat(cycles) @(posedge clk); #1; end
    endtask
    task expect_equal_except_diag;
        begin
            if({en_fs,en_de,en_hs,en_vs,en_mode,en_x,en_y,en_rgb,en_panel,en_logo} !==
               {dis_fs,dis_de,dis_hs,dis_vs,dis_mode,dis_x,dis_y,dis_rgb,dis_panel,dis_logo}) begin
                $display("ERROR: formal output chain differs outside diagnostic layer");errors=errors+1;
            end
        end
    endtask

    initial begin
        repeat(4) @(posedge clk);rst_n=1;

        in_x=500;in_y=300;in_rgb=24'h123456;settle(12);
        expect_equal_except_diag();
        if(en_diag || dis_diag || dis_rgb!==24'h123456)begin $display("ERROR: plain video");errors=errors+1;end

        in_x=200;in_y=300;in_rgb=24'h123456;settle(12);
        if(!en_diag || en_rgb!==24'hff0000)begin $display("ERROR: enabled diagnostic missing");errors=errors+1;end
        if(dis_diag || dis_rgb!==24'h123456)begin $display("ERROR: disabled diagnostic leaked");errors=errors+1;end

        in_x=100;in_y=300;settle(12);
        expect_equal_except_diag();
        if(!dis_panel || dis_rgb!==24'h00ff00)begin $display("ERROR: formal panel removed");errors=errors+1;end

        in_x=300;in_y=300;settle(12);
        expect_equal_except_diag();
        if(!dis_logo || dis_rgb!==24'h0000ff)begin $display("ERROR: logo chain removed");errors=errors+1;end

        track_valid=1;track_x=400;track_y=300;track_w=4;track_h=4;
        in_x=400;in_y=300;in_frame_start=1;@(posedge clk);#1;in_frame_start=0;settle(12);
        expect_equal_except_diag();
        if(dis_rgb!==24'h00ffff)begin $display("ERROR: tracking border removed");errors=errors+1;end

        in_x=100;in_y=100;settle(12);
        expect_equal_except_diag();
        if(!dis_panel || dis_rgb!==24'h00ffff)begin $display("ERROR: coordinate caption removed");errors=errors+1;end

        track_valid=0;in_x=100;in_y=80;settle(12);
        if(!en_panel || en_rgb!==24'h00ff00)begin $display("ERROR: compatibility detail row missing");errors=errors+1;end
        if(!dis_panel || dis_rgb!==24'h18242c)begin $display("ERROR: release detail row not hidden");errors=errors+1;end

        calibration_state=1;in_frame_start=1;@(posedge clk);#1;in_frame_start=0;settle(12);
        if(!dis_panel || dis_rgb!==24'h00ff00)begin $display("ERROR: calibration notice hidden");errors=errors+1;end

        if(errors==0)$display("PASS: release UI keeps transient calibration notice and hides idle detail");
        else $display("FAIL: errors=%0d",errors);
        $finish;
    end
endmodule

module pixel309_track_caption(
    input wire clk,rst_n,in_frame_start,in_de,input wire [10:0] in_x,input wire [9:0] in_y,
    input wire [10:0] track_x,input wire [9:0] track_y,input wire track_valid,output wire out_ink);
    assign out_ink=track_valid && in_x==100;
endmodule

module pixel26_processing_display #(parameter integer ROI_ENABLE=0)(
    input wire clk,rst_n,in_frame_start,in_de,in_hsync,in_vsync,mode_request,
    input wire [10:0] in_x,input wire [9:0] in_y,input wire [23:0] in_rgb,
    output wire out_frame_start,out_de,out_hsync,out_vsync,out_mode,
    output wire [10:0] out_x,output wire [9:0] out_y,output wire [23:0] out_rgb,output wire [1:0] out_color_id);
    assign out_frame_start=in_frame_start;assign out_de=in_de;assign out_hsync=in_hsync;assign out_vsync=in_vsync;
    assign out_mode=mode_request;assign out_x=in_x;assign out_y=in_y;assign out_rgb=in_rgb;assign out_color_id=0;
endmodule

module sc520_cartoon_style(
    input wire clk,rst_n,input wire [1:0] mode_request,input wire in_frame_start,in_de,in_hsync,in_vsync,
    input wire [10:0] in_x,input wire [9:0] in_y,input wire [23:0] in_rgb,
    output wire out_frame_start,out_de,out_hsync,out_vsync,output wire [10:0] out_x,
    output wire [9:0] out_y,output wire [23:0] out_rgb,output wire [1:0] out_mode);
    assign out_frame_start=in_frame_start;assign out_de=in_de;assign out_hsync=in_hsync;assign out_vsync=in_vsync;
    assign out_x=in_x;assign out_y=in_y;assign out_rgb=in_rgb;assign out_mode=mode_request;
endmodule

module pixel301_panel(
    input wire clk,rst_n,input wire [10:0] pixel_x,input wire [9:0] pixel_y,input wire [27:0] status,
    input wire [1:0] style_mode,cal_state,tf_state,output wire active,output wire [23:0] rgb);
    assign active=pixel_x==100;assign rgb=24'h00ff00;
endmodule

module pixel30_diagnostic #(parameter [15:0] VERSION=16'h0300)(
    input wire clk,rst_n,input wire [10:0] pixel_x,input wire [9:0] pixel_y,
    input wire [191:0] packet,input wire usable,input wire [7:0] age,output wire active,output wire [23:0] rgb);
    assign active=pixel_x==200;assign rgb=24'hff0000;
endmodule

module sc520_logo_tile4_pipeline #(
    parameter integer X_ORIGIN=0,Y_ORIGIN=0,parameter MAP_FILE="",parameter DICT_FILE="")(
    input wire clk,rst_n,in_frame_start,in_de,in_hsync,in_vsync,in_mode,
    input wire [10:0] in_x,input wire [9:0] in_y,input wire [23:0] in_rgb,
    output wire out_frame_start,out_de,out_hsync,out_vsync,out_mode,
    output wire [10:0] out_x,output wire [9:0] out_y,output wire [23:0] out_rgb,output wire logo_active);
    assign logo_active=in_x==300;assign out_rgb=logo_active?24'h0000ff:in_rgb;
    assign out_frame_start=in_frame_start;assign out_de=in_de;assign out_hsync=in_hsync;assign out_vsync=in_vsync;
    assign out_mode=in_mode;assign out_x=in_x;assign out_y=in_y;
endmodule
