// Stage1 original processing, stage2 font/diagnostic/video, stages3..6 original Logo.
// Input sampled at N is presented after N+5. One recognition snapshot on original FS.
module pixel30_compositor #(
    parameter [15:0] VERSION=16'h0300,
    parameter integer SCENE_X=160,SCENE_Y=120,SCENE_WIDTH=960,SCENE_HEIGHT=480,
    parameter LOGO_INDEX_FILE="anlogic_logo_index.mem",LOGO_PALETTE_FILE="anlogic_logo_palette.mem"
)(
    input wire clk,rst_n,
    input wire in_frame_start,in_de,in_hsync,in_vsync,mode_request,
    input wire [10:0] in_x,input wire [9:0] in_y,input wire [23:0] in_rgb,
    input wire [27:0] business_state,
    input wire [191:0] recognition_packet,
    input wire recognition_fresh,recognition_fault,input wire [7:0] recognition_age,
    output wire out_frame_start,out_de,out_hsync,out_vsync,out_mode,
    output wire [10:0] out_x,output wire [9:0] out_y,output wire [23:0] out_rgb,
    output wire out_panel_active,out_diag_active,out_logo_active
);
    reg [27:0] frame_business;
    reg [191:0] snapshot;reg [7:0] age;reg snapshot_fresh,invalidated,trust_invalidated;
    always @(posedge clk or negedge rst_n)
        if(!rst_n)begin frame_business<=0;snapshot<=0;age<=255;snapshot_fresh<=0;invalidated<=0;trust_invalidated<=0;end
        else if(in_frame_start)begin
            frame_business<=business_state;snapshot<=recognition_packet;age<=recognition_age;
            snapshot_fresh<=recognition_fresh&&!recognition_fault;invalidated<=0;trust_invalidated<=0;
        end else begin
            if(!recognition_fresh || recognition_fault)invalidated<=1;
            if(!recognition_fresh || recognition_fault || !recognition_packet[186] ||
                !recognition_packet[33] || recognition_packet[36])trust_invalidated<=1;
        end
    wire usable=snapshot_fresh&&!invalidated&&recognition_fresh&&!recognition_fault;
    wire trusted=usable&&!trust_invalidated&&recognition_packet[186]&&recognition_packet[33]&&
        !recognition_packet[36]&&snapshot[186]&&snapshot[33]&&!snapshot[36];
    wire [27:0] status={frame_business[27:12],trusted?frame_business[11:8]:4'd0,
                        frame_business[7:1],frame_business[0]&&trusted};
    wire p_fs,p_de,p_hs,p_vs,p_mode;wire [10:0] p_x;wire [9:0] p_y;wire [23:0] p_rgb;wire [1:0] p_color;
    pixel26_processing_display #(.ROI_ENABLE(0)) processing(
        .clk(clk),.rst_n(rst_n),.in_frame_start(in_frame_start),.in_de(in_de),.in_hsync(in_hsync),.in_vsync(in_vsync),
        .mode_request(mode_request),.in_x(in_x),.in_y(in_y),.in_rgb(in_rgb),
        .out_frame_start(p_fs),.out_de(p_de),.out_hsync(p_hs),.out_vsync(p_vs),.out_mode(p_mode),
        .out_x(p_x),.out_y(p_y),.out_rgb(p_rgb),.out_color_id(p_color));
    wire panel_active,diag_active;wire [23:0] panel_rgb,diag_rgb;
    pixel30_panel panel(.clk(clk),.rst_n(rst_n),.pixel_x(p_x),.pixel_y(p_y),.status(status),.display_mode(p_mode),
        .active(panel_active),.rgb(panel_rgb));
    pixel30_diagnostic #(.VERSION(VERSION)) diagnostic_panel(
        .clk(clk),.rst_n(rst_n),.pixel_x(in_x),.pixel_y(in_y),.packet(snapshot),.usable(usable),.age(age),
        .active(diag_active),.rgb(diag_rgb));
    reg [49:0] video_d;reg border_d;
    always @(posedge clk or negedge rst_n)
        if(!rst_n)begin video_d<=0;border_d<=0;end
        else begin
            video_d<={p_fs,p_de,p_hs,p_vs,p_mode,p_x,p_y,p_rgb};
            border_d<=p_x>=SCENE_X && p_x<SCENE_X+SCENE_WIDTH && p_y>=SCENE_Y && p_y<SCENE_Y+SCENE_HEIGHT &&
                (p_x==SCENE_X || p_x==SCENE_X+SCENE_WIDTH-1 || p_y==SCENE_Y || p_y==SCENE_Y+SCENE_HEIGHT-1);
        end
    wire d_de=video_d[48];
    wire [23:0] mixed=!d_de ? 24'd0:diag_active ? diag_rgb:panel_active ? panel_rgb:border_d ? 24'hff0000:video_d[23:0];
    sc520_logo_pipeline #(.X_ORIGIN(1008),.Y_ORIGIN(24),.INDEX_FILE(LOGO_INDEX_FILE),.PALETTE_FILE(LOGO_PALETTE_FILE)) logo(
        .clk(clk),.rst_n(rst_n),.in_frame_start(video_d[49]),.in_de(d_de),.in_hsync(video_d[47]),.in_vsync(video_d[46]),
        .in_mode(video_d[45]),.in_x(video_d[44:34]),.in_y(video_d[33:24]),.in_rgb(mixed),
        .out_frame_start(out_frame_start),.out_de(out_de),.out_hsync(out_hsync),.out_vsync(out_vsync),.out_mode(out_mode),
        .out_x(out_x),.out_y(out_y),.out_rgb(out_rgb),.logo_active(out_logo_active));
    reg [1:0] a0,a1,a2,a3;
    always @(posedge clk or negedge rst_n)
        if(!rst_n)begin a0<=0;a1<=0;a2<=0;a3<=0;end
        else begin a0<={d_de&&panel_active,d_de&&diag_active};a1<=a0;a2<=a1;a3<=a2;end
    assign {out_panel_active,out_diag_active}=a3;
endmodule
