// Stage1 original processing, stage2 font/diagnostic/video, stages3..6 original Logo.
// Three style registers inserted after natural saturation: N sampled -> N+8 output. Snapshot remains original FS.
module pixel309_compositor_track #(
    parameter [15:0] VERSION=16'h0309,
    parameter integer SCENE_X=160,SCENE_Y=120,SCENE_WIDTH=960,SCENE_HEIGHT=480,
    parameter integer TRACK_ENABLE=1,COORD_ENABLE=0,
    parameter LOGO_INDEX_FILE="anlogic_logo_index.mem",LOGO_PALETTE_FILE="anlogic_logo_palette.mem"
)(
    input wire clk,rst_n,
    input wire in_frame_start,in_de,in_hsync,in_vsync,mode_request,
    input wire [1:0] style_request,
    input wire [1:0] calibration_state,tf_state,
    input wire [10:0] in_x,input wire [9:0] in_y,input wire [23:0] in_rgb,
    input wire [27:0] business_state,
    input wire [191:0] recognition_packet,
    input wire recognition_fresh,recognition_fault,input wire [7:0] recognition_age,
    input wire track_valid,
    input wire [10:0] track_x,track_w,
    input wire [9:0] track_y,track_h,
    output wire out_frame_start,out_de,out_hsync,out_vsync,out_mode,
    output wire [10:0] out_x,output wire [9:0] out_y,output wire [23:0] out_rgb,
    output wire out_panel_active,out_diag_active,out_logo_active
);
    // A new target/position is committed only at the ORIGINAL display SOF.
    // Withdrawal applies to input pixels immediately and is sticky until SOF.
    // Compute the border at that same input pixel; shifting just this bit avoids
    // applying a new SOF snapshot to the previous frame's delayed style pixels.
    reg frame_track_valid;
    reg [10:0] frame_track_x,frame_track_w;
    reg [9:0] frame_track_y,frame_track_h;
    wire [10:0] pixel_track_x=in_frame_start?track_x:frame_track_x;
    wire [9:0] pixel_track_y=in_frame_start?track_y:frame_track_y;
    wire [10:0] pixel_track_w=in_frame_start?track_w:frame_track_w;
    wire [9:0] pixel_track_h=in_frame_start?track_h:frame_track_h;
    wire [11:0] pixel_track_right={1'b0,pixel_track_x}+{1'b0,pixel_track_w};
    wire [10:0] pixel_track_bottom={1'b0,pixel_track_y}+{1'b0,pixel_track_h};
    wire pixel_track_valid=TRACK_ENABLE && track_valid &&
        (in_frame_start || frame_track_valid) && pixel_track_w!=0 && pixel_track_h!=0;
    wire input_track_border=in_de && pixel_track_valid &&
        {1'b0,in_x}>={1'b0,pixel_track_x} && {1'b0,in_x}<pixel_track_right &&
        {1'b0,in_y}>={1'b0,pixel_track_y} && {1'b0,in_y}<pixel_track_bottom &&
        (in_x==pixel_track_x || {1'b0,in_x}==pixel_track_right-1'b1 ||
         in_y==pixel_track_y || {1'b0,in_y}==pixel_track_bottom-1'b1);
    reg [3:0] track_border_pipe;
    always @(posedge clk or negedge rst_n)
        if(!rst_n)begin
            frame_track_valid<=0;frame_track_x<=0;frame_track_y<=0;
            frame_track_w<=0;frame_track_h<=0;track_border_pipe<=0;
        end else begin
            if(in_frame_start)begin
                frame_track_valid<=track_valid;
                frame_track_x<=track_x;frame_track_y<=track_y;
                frame_track_w<=track_w;frame_track_h<=track_h;
            end else if(!track_valid)frame_track_valid<=0;
            track_border_pipe<={track_border_pipe[2:0],input_track_border};
        end
    wire coord_ink;
    generate if(COORD_ENABLE && TRACK_ENABLE)begin:coordinates
        pixel309_track_caption caption(
            .clk(clk),.rst_n(rst_n),.in_frame_start(in_frame_start),.in_de(in_de),
            .in_x(in_x),.in_y(in_y),.track_x(track_x),.track_y(track_y),
            .track_valid(pixel_track_valid),.out_ink(coord_ink));
    end else begin:no_coordinates
        assign coord_ink=1'b0;
    end endgenerate
    reg [27:0] frame_business;
    reg [1:0] frame_calibration,frame_tf;
    always @(posedge clk or negedge rst_n)
        if(!rst_n)begin frame_calibration<=0;frame_tf<=0;end
        else if(in_frame_start)begin frame_calibration<=calibration_state;frame_tf<=tf_state;end
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
    reg [1:0] frame_style;
    always @(posedge clk or negedge rst_n)
        if(!rst_n)frame_style<=0;else if(in_frame_start)frame_style<=style_request;
    wire c_fs,c_de,c_hs,c_vs;wire [1:0] c_mode;
    wire [10:0] c_x;wire [9:0] c_y;wire [23:0] c_rgb;
    sc520_cartoon_style style(.clk(clk),.rst_n(rst_n),.mode_request(frame_style),
        .in_frame_start(p_fs),.in_de(p_de),.in_hsync(p_hs),.in_vsync(p_vs),
        .in_x(p_x),.in_y(p_y),.in_rgb(p_rgb),.out_frame_start(c_fs),.out_de(c_de),
        .out_hsync(c_hs),.out_vsync(c_vs),.out_x(c_x),.out_y(c_y),.out_rgb(c_rgb),.out_mode(c_mode));
    // The two-layer diagnostic starts one clock before the one-layer panel.
    reg [20:0] diag_xy0,diag_xy1;
    always @(posedge clk or negedge rst_n)
        if(!rst_n)begin diag_xy0<=0;diag_xy1<=0;end
        else begin diag_xy0<={p_x,p_y};diag_xy1<=diag_xy0;end
    wire panel_active,diag_active;wire [23:0] panel_rgb,diag_rgb;
    pixel301_panel panel(.clk(clk),.rst_n(rst_n),.pixel_x(c_x),.pixel_y(c_y),.status(status),
        .style_mode(c_mode),.cal_state(frame_calibration),.tf_state(frame_tf),
        .active(panel_active),.rgb(panel_rgb));
    pixel30_diagnostic #(.VERSION(VERSION)) diagnostic_panel(
        .clk(clk),.rst_n(rst_n),.pixel_x(diag_xy1[20:10]),.pixel_y(diag_xy1[9:0]),.packet(snapshot),.usable(usable),.age(age),
        .active(diag_active),.rgb(diag_rgb));
    reg [49:0] video_d;reg border_d,track_border_d,coord_ink_d;
    always @(posedge clk or negedge rst_n)
        if(!rst_n)begin video_d<=0;border_d<=0;track_border_d<=0;coord_ink_d<=0;end
        else begin
            video_d<={c_fs,c_de,c_hs,c_vs,1'b0,c_x,c_y,c_rgb};
            border_d<=c_x>=SCENE_X && c_x<SCENE_X+SCENE_WIDTH && c_y>=SCENE_Y && c_y<SCENE_Y+SCENE_HEIGHT &&
                (c_x==SCENE_X || c_x==SCENE_X+SCENE_WIDTH-1 || c_y==SCENE_Y || c_y==SCENE_Y+SCENE_HEIGHT-1);
            track_border_d<=track_border_pipe[3];
            coord_ink_d<=coord_ink;
        end
    wire d_de=video_d[48];
    // Coordinates occupy only the blank panel area; diagnostic and Logo retain priority.
    wire [23:0] mixed=!d_de ? 24'd0:diag_active ? diag_rgb:
        panel_active ? (coord_ink_d?24'h00ffff:panel_rgb):
        (TRACK_ENABLE && track_border_d) ? 24'h00ffff : border_d ? 24'hff0000:video_d[23:0];
    sc520_logo_tile4_pipeline #(.X_ORIGIN(1008),.Y_ORIGIN(24),.MAP_FILE(LOGO_INDEX_FILE),.DICT_FILE(LOGO_PALETTE_FILE)) logo(
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
