`timescale 1ns/1ps
module tb_full;
    localparam TEST_NAME="full";
    localparam WIDTH=1280,HEIGHT=720,ROI_LEFT=320,ROI_RIGHT=959,ROI_TOP=120,ROI_BOTTOM=599;
    localparam TARGET_X=560,TARGET_Y=280,SCALE=2,HBLANK=370,VSYNC_CYCLES=8250,VBLANK_CYCLES=49500,SNAPSHOTS=1;
    `include "demo_test_body.svh"
endmodule
