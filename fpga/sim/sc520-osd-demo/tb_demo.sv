`timescale 1ns/1ps
module tb_demo;
    localparam TEST_NAME="demo";
    localparam WIDTH=384,HEIGHT=240,ROI_LEFT=16,ROI_RIGHT=367,ROI_TOP=144,ROI_BOTTOM=223;
    localparam TARGET_X=100,TARGET_Y=160,SCALE=0,HBLANK=8,VSYNC_CYCLES=64,VBLANK_CYCLES=80,SNAPSHOTS=0;
    `include "demo_test_body.svh"
endmodule
