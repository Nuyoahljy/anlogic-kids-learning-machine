// One current font ROM, one register layer. Status is snapshotted by compositor.
// Top text ends at x1007, leaving the complete Logo rectangle clear.
module pixel22_panel(
    input wire clk,rst_n,
    input wire [10:0] pixel_x,input wire [9:0] pixel_y,
    input wire [27:0] status,input wire [2:0] audio_state,input wire display_mode,
    output wire active,output wire [23:0] rgb
);
    wire top_panel=pixel_y>=8 && pixel_y<112;
    wire bottom_panel=pixel_y>=608 && pixel_y<712;
    wire [9:0] local_y=bottom_panel ? pixel_y-612:pixel_y-12;
    wire [10:0] local_x=pixel_x-48;
    wire [2:0] line_index={1'b0,local_y[6:5]}+(bottom_panel ? 3'd3:3'd0);
    wire text_area=pixel_x>=48 && pixel_x<(bottom_panel ? 1232:1008) &&
        ((pixel_y>=12 && pixel_y<108) || (pixel_y>=612 && pixel_y<708));
    wire panel_active=pixel_x>=32 && pixel_x<1248 && (top_panel || bottom_panel);
    wire [7:0] glyph;wire [1:0] tone;wire [15:0] font_bits;
    pixel22_content #(.SCENE_UI(1),.DISPLAY_UI(1)) content(
        .line_index(line_index),.char_index(local_x[10:5]),.mode(status[27:26]),.phase(status[25:24]),
        .score(status[23:20]),.question_index(status[19:16]),.target_item(status[15:12]),.display_item(status[11:8]),
        .feedback(status[7:5]),.source_test(status[4]),.armed(status[3]),
        .audio_fault(status[2]),.audio_busy(status[1]),.result_healthy(status[0]),.display_mode(display_mode),.audio_state(audio_state),
        .glyph(glyph),.tone(tone));
    pixel22_font_rom font(.clk(clk),.glyph(glyph),.row(local_y[4:1]),.bits(font_bits));
    reg active_d,text_d;reg [3:0] column_d;reg [1:0] tone_d;
    always @(posedge clk or negedge rst_n)
        if(!rst_n)begin active_d<=0;text_d<=0;column_d<=0;tone_d<=0;end
        else begin active_d<=panel_active;text_d<=text_area;column_d<=local_x[4:1];tone_d<=tone;end
    wire [23:0] ink=tone_d==1 ? 24'habe8f2:tone_d==2 ? 24'hffe3a3:tone_d==3 ? 24'h9ef0cc:24'hf5f7fa;
    assign active=active_d;
    assign rgb=!active_d ? 24'd0:text_d && font_bits[15-column_d] ? ink:24'h18242c;
endmodule
