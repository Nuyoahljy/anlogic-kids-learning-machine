// Current-frame block candidate. Full raster health and full-resolution
// presence are required; held boxes from an earlier frame are never reused.
module pixel26_block_recognizer_piped #(
    parameter integer FRAME_WIDTH=320,FRAME_HEIGHT=180,
    parameter integer X_MIN=80,X_MAX=239,Y_MIN=30,Y_MAX=149,
    parameter integer MIN_AREA=16,MIN_WIDTH=2,MIN_HEIGHT=2,
    parameter integer RUN_LENGTH=1,CONFIRM_FRAMES=3
) (
    input wire clk,rst_n,flush,in_valid,in_sof,in_eol,
    input wire [10:0] in_x,
    input wire [9:0] in_y,
    input wire [23:0] in_rgb,
    input wire in_frame_end,in_frame_good,in_frame_present,
    input wire [31:0] in_frame_id,
    input wire in_source_test,
    output wire out_frame,out_healthy,out_present,out_valid,
    output wire [3:0] out_item,
    output wire [31:0] out_frame_id,
    output wire out_source_test,
    output wire [7:0] stable_count,
    output wire out_revoke
);
    reg [59:0] meta_a,meta_b;
    wire [1:0] color;
    pixel26_classify_pipe classify(.clk(clk),.rst_n(rst_n),.flush(flush),.in_rgb(in_rgb),.color_id(color));
    always @(posedge clk or negedge rst_n)
        if(!rst_n)begin meta_a<=0;meta_b<=0;end
        else if(flush)begin meta_a<=0;meta_b<=0;end
        else begin
            meta_a<={in_valid,in_sof,in_eol,in_frame_end,in_frame_good,in_frame_present,in_source_test,in_x,in_y,in_frame_id};
            meta_b<=meta_a;
        end
    wire v,s,e,fe,fg,fp,source;wire [10:0] x;wire [9:0] y;wire [31:0] id;
    assign {v,s,e,fe,fg,fp,source,x,y,id}=meta_b;
    pixel26_block_core #(.FRAME_WIDTH(FRAME_WIDTH),.FRAME_HEIGHT(FRAME_HEIGHT),.X_MIN(X_MIN),.X_MAX(X_MAX),
        .Y_MIN(Y_MIN),.Y_MAX(Y_MAX),.MIN_AREA(MIN_AREA),.MIN_WIDTH(MIN_WIDTH),.MIN_HEIGHT(MIN_HEIGHT),
        .RUN_LENGTH(RUN_LENGTH),.CONFIRM_FRAMES(CONFIRM_FRAMES)) core(
        .clk(clk),.rst_n(rst_n),.flush(flush),.in_valid(v),.in_sof(s),.in_eol(e),.in_x(x),.in_y(y),.in_rgb(24'd0),.in_color(color),
        .in_frame_end(fe),.in_frame_good(fg),.in_frame_present(fp),.in_frame_id(id),.in_source_test(source),
        .out_frame(out_frame),.out_healthy(out_healthy),.out_present(out_present),.out_valid(out_valid),.out_item(out_item),
        .out_frame_id(out_frame_id),.out_source_test(out_source_test),.stable_count(stable_count),.out_revoke(out_revoke));
endmodule
