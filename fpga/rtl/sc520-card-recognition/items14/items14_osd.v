// Candidate two-panel OSD; central x320..959,y120..599 stays unobscured.
// Parent snapshots status atomically at frame start. One clock of ROM latency.
// Derived from the four-key quiz_osd.v; provenance is in font-manifest.json.
module items14_osd #(
    parameter integer SCENE_UI=0
) (
    input wire clk,
    input wire rst_n,
    input wire [10:0] pixel_x,
    input wire [9:0] pixel_y,
    input wire [1:0] mode,phase,
    input wire [3:0] score,question_index,target_item,display_item,
    input wire [2:0] feedback,
    input wire source_test,armed,audio_fault,audio_busy,result_healthy,
    output wire active,
    output wire [23:0] rgb
);
    wire top_panel=pixel_y>=10'd8 && pixel_y<10'd112;
    wire bottom_panel=pixel_y>=10'd608 && pixel_y<10'd712;
    wire [9:0] local_y=bottom_panel ? pixel_y-10'd612 : pixel_y-10'd12;
    wire [10:0] local_x=pixel_x-11'd48;
    wire text_area=pixel_x>=11'd48 && pixel_x<11'd1232 &&
                  ((pixel_y>=10'd12 && pixel_y<10'd108) ||
                   (pixel_y>=10'd612 && pixel_y<10'd708));
    wire [2:0] line_index={1'b0,local_y[6:5]}+(bottom_panel ? 3'd3 : 3'd0);
    wire [7:0] glyph;
    wire [1:0] tone;
    wire [15:0] font_bits;
    wire panel_active=pixel_x>=11'd32 && pixel_x<11'd1248 && (top_panel || bottom_panel);
    reg active_d, text_area_d;
    reg [3:0] font_column_d;
    reg [1:0] tone_d;
    wire [23:0] ink=tone_d==1 ? 24'hABE8F2 : tone_d==2 ? 24'hFFE3A3 :
                          tone_d==3 ? 24'h9EF0CC : 24'hF5F7FA;
    items14_content #(.SCENE_UI(SCENE_UI)) content(.line_index(line_index),.char_index(local_x[10:5]),
        .mode(mode),.phase(phase),.score(score),.question_index(question_index),
        .target_item(target_item),.display_item(display_item),.feedback(feedback),
        .source_test(source_test),.armed(armed),.audio_fault(audio_fault),.audio_busy(audio_busy),
        .result_healthy(result_healthy),.glyph(glyph),.tone(tone));
    items14_font_rom font(.clk(clk),.glyph(glyph),.row(local_y[4:1]),.bits(font_bits));
    // Reset validity, not the memory, so the synchronous ROM remains inferable.
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            active_d<=0; text_area_d<=0; font_column_d<=0; tone_d<=0;
        end else begin
            active_d<=panel_active; text_area_d<=text_area;
            font_column_d<=local_x[4:1]; tone_d<=tone;
        end
    end
    assign active=active_d;
    assign rgb=!active ? 24'd0 :
        (text_area_d && font_bits[15-font_column_d] ? ink : 24'h18242C);
endmodule
