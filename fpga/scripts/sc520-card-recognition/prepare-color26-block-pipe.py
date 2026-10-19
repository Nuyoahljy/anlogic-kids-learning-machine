"""Derive block core plus two-stage metadata-aligned capture wrapper."""
from pathlib import Path
R=Path(__file__).resolve().parents[3];D=R/'fpga/rtl/sc520-color-integration'
s=(D/'pixel26_block_recognizer.v').read_text();end=s.index('\n    reg active;')
header=s[:end].replace('module pixel26_block_recognizer','module pixel26_block_recognizer_piped').replace('output reg','output wire')
core=s.replace('module pixel26_block_recognizer','module pixel26_block_core').replace('    input wire [23:0] in_rgb,','    input wire [23:0] in_rgb,\n    input wire [1:0] in_color,')
core=core.replace('    pixel26_color_classify classify(.in_rgb(in_rgb),.color_id(color));','    assign color=in_color;')
(D/'pixel26_block_core.v').write_text(core,encoding='utf-8',newline='\n')
body='''
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
'''
(D/'pixel26_block_recognizer_piped.v').write_text(header+body,encoding='utf-8',newline='\n')
p=D/'pixel26_bg_pipeline.v';s=p.read_text();assert 'pixel26_block_recognizer #' in s;p.write_text(s.replace('pixel26_block_recognizer #','pixel26_block_recognizer_piped #'),encoding='utf-8',newline='\n')
print('ALIGNED_BLOCK_PIPE_CREATED')
