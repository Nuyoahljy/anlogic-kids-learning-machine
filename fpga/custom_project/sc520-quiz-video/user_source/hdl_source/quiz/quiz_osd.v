// Two disjoint panels; central x320..959,y120..599 ROI is never obscured.
// Parent snapshots all status inputs atomically at frame start. No latency here.
module quiz_osd(
    input wire [10:0] pixel_x,
    input wire [9:0] pixel_y,
    input wire [1:0] mode,phase,
    input wire [3:0] score,question_index,target_item,display_item,
    input wire [2:0] feedback,
    input wire source_test,armed,audio_fault,audio_busy,
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
    wire [23:0] ink=tone==1 ? 24'hABE8F2 : tone==2 ? 24'hFFE3A3 :
                          tone==3 ? 24'h9EF0CC : 24'hF5F7FA;
    quiz_content content(.line_index(line_index),.char_index(local_x[10:5]),
        .mode(mode),.phase(phase),.score(score),.question_index(question_index),
        .target_item(target_item),.display_item(display_item),.feedback(feedback),
        .source_test(source_test),.armed(armed),.audio_fault(audio_fault),.audio_busy(audio_busy),
        .glyph(glyph),.tone(tone));
    quiz_font_rom font(.glyph(glyph),.row(local_y[4:1]),.bits(font_bits));
    assign active=pixel_x>=11'd32 && pixel_x<11'd1248 && (top_panel || bottom_panel);
    assign rgb=!active ? 24'd0 :
        (text_area && font_bits[15-local_x[4:1]] ? ink : 24'h18242C);
endmodule
