// T027 color evidence, restricted to explicit complete-glyph mask.
// No color-pixel bounding box or fill-ratio shape inference. Full raster health and full-resolution
// presence are required; held boxes from an earlier frame are never reused.
module pixel27_color_core #(
    parameter integer FRAME_WIDTH=320,FRAME_HEIGHT=180,
    parameter integer X_MIN=80,X_MAX=239,Y_MIN=30,Y_MAX=149,
    parameter integer MIN_AREA=16,MIN_WIDTH=2,MIN_HEIGHT=2,
    parameter integer RUN_LENGTH=1,CONFIRM_FRAMES=3
) (
    input wire clk,rst_n,flush,in_valid,in_sof,in_eol,
    input wire [10:0] in_x,
    input wire [9:0] in_y,
    input wire [23:0] in_rgb,
    input wire [1:0] in_color,
    input wire in_glyph,
    input wire in_frame_end,in_frame_good,in_frame_present,
    input wire [31:0] in_frame_id,
    input wire in_source_test,
    output reg out_frame,out_healthy,out_present,out_valid,
    output reg [3:0] out_item,
    output reg [31:0] out_frame_id,
    output reg out_source_test,
    output reg [7:0] stable_count,
    output reg out_revoke
);
    reg active;
    reg [2:0] stage;
    reg [31:0] active_id,pixels;
    reg active_source,saved_present;
    reg [10:0] expected_x;
    reg [9:0] expected_y;
    reg [19:0] area[0:2];
    reg [19:0] glyph_area;
    reg [10:0] glyph_left,glyph_right;
    reg [9:0] glyph_top,glyph_bottom;
    reg [1:0] selected_color;
    reg [19:0] selected_area;
    reg coverage_good;
    reg [3:0] candidate,previous_item;
    reg previous_source;
    integer k;
    wire roi=in_x>=X_MIN && in_x<=X_MAX && in_y>=Y_MIN && in_y<=Y_MAX;
    wire [1:0] color;
    assign color=in_color;
    wire start_ok=in_valid && in_sof && !active && stage==0 && !in_frame_end;
    wire raster_bad=in_valid &&
        (!(active || start_ok) || (in_sof && !start_ok) ||
         in_x!=(start_ok ? 0 : expected_x) || in_y!=(start_ok ? 0 : expected_y) ||
         in_eol!=(in_x==FRAME_WIDTH-1) || (!start_ok &&
             (in_frame_id!=active_id || in_source_test!=active_source || pixels>=FRAME_WIDTH*FRAME_HEIGHT)));
    wire marker_bad=(!in_valid && (in_sof || in_eol)) ||
        (in_frame_end && (!active || stage!=0 || in_valid || in_sof || in_eol || !in_frame_good ||
         pixels!=FRAME_WIDTH*FRAME_HEIGHT || in_frame_id!=active_id || in_source_test!=active_source ||
         (!in_frame_present && glyph_area!=0)));
    reg [1:0] winning_color;
    reg [19:0] winning_area;
    integer winning_index;
    always @* begin
        winning_color=0;winning_area=0;winning_index=0;
        if(area[0]>=MIN_AREA && {1'b0,area[0]}>={area[1],1'b0} && {1'b0,area[0]}>={area[2],1'b0})begin
            winning_color=1;winning_area=area[0];winning_index=0;
        end else if(area[1]>=MIN_AREA && {1'b0,area[1]}>={area[0],1'b0} && {1'b0,area[1]}>={area[2],1'b0})begin
            winning_color=2;winning_area=area[1];winning_index=1;
        end else if(area[2]>=MIN_AREA && {1'b0,area[2]}>={area[0],1'b0} && {1'b0,area[2]}>={area[1],1'b0})begin
            winning_color=3;winning_area=area[2];winning_index=2;
        end
    end
    // 22 bits hold 3 * (2^20-1); no truncation or division.
    wire [21:0] color_triple={1'b0,selected_area,1'b0}+{2'b00,selected_area};
    wire [21:0] glyph_double={1'b0,glyph_area,1'b0};
    wire same_candidate=candidate!=0 && candidate==previous_item && active_source==previous_source;
    wire [7:0] next_count=candidate==0 ? 8'd0 : same_candidate ?
        (stable_count==255 ? 8'd255 : stable_count+1'b1) : 8'd1;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            active<=0;stage<=0;active_id<=0;active_source<=0;saved_present<=1;pixels<=0;
            expected_x<=0;expected_y<=0;selected_color<=0;selected_area<=0;glyph_area<=0;
            glyph_left<=0;glyph_right<=0;glyph_top<=0;glyph_bottom<=0;
            coverage_good<=0;candidate<=0;previous_item<=0;previous_source<=0;
            out_frame<=0;out_healthy<=0;out_present<=1;out_valid<=0;out_item<=0;
            out_frame_id<=0;out_source_test<=0;stable_count<=0;out_revoke<=0;
            for(k=0;k<3;k=k+1)area[k]<=0;
        end else begin
            out_frame<=0;out_revoke<=0;
            if(flush || raster_bad || marker_bad)begin
                active<=0;stage<=0;pixels<=0;previous_item<=0;stable_count<=0;glyph_area<=0;
                selected_color<=0;selected_area<=0;coverage_good<=0;candidate<=0;
                glyph_left<=0;glyph_right<=0;glyph_top<=0;glyph_bottom<=0;
                for(k=0;k<3;k=k+1)area[k]<=0;
                out_healthy<=0;out_present<=1;out_valid<=0;out_item<=0;
                out_revoke<=!flush;
            end else begin
                if(start_ok)begin
                    active<=1;active_id<=in_frame_id;active_source<=in_source_test;pixels<=0;glyph_area<=0;
                    glyph_left<=0;glyph_right<=0;glyph_top<=0;glyph_bottom<=0;
                    for(k=0;k<3;k=k+1)area[k]<=0;
                end
                if(in_valid)begin
                    pixels<=(start_ok ? 0 : pixels)+1;
                    if(in_x==FRAME_WIDTH-1)begin expected_x<=0;expected_y<=in_y+1'b1;end
                    else begin expected_x<=in_x+1'b1;expected_y<=in_y;end
                    if(roi && in_glyph)begin
                        glyph_area<=(start_ok ? 0 : glyph_area)+1'b1;
                        if(start_ok || glyph_area==0 || in_x<glyph_left)glyph_left<=in_x;
                        if(start_ok || glyph_area==0 || in_x>glyph_right)glyph_right<=in_x;
                        if(start_ok || glyph_area==0 || in_y<glyph_top)glyph_top<=in_y;
                        if(start_ok || glyph_area==0 || in_y>glyph_bottom)glyph_bottom<=in_y;
                        if(color!=0)area[color-1]<=(start_ok ? 0 : area[color-1])+1'b1;
                    end
                end
                if(in_frame_end)begin active<=0;stage<=1;saved_present<=in_frame_present;end
                else if(stage==1)begin
                    selected_color<=winning_color;selected_area<=winning_area;
                    stage<=2;
                end else if(stage==2)begin
                    coverage_good<=saved_present && selected_color!=0 && glyph_area>=MIN_AREA &&
                        selected_area<=glyph_area && color_triple>=glyph_double &&
                        ({1'b0,glyph_right}-{1'b0,glyph_left}+12'd1)>=MIN_WIDTH &&
                        ({1'b0,glyph_bottom}-{1'b0,glyph_top}+11'd1)>=MIN_HEIGHT &&
                        glyph_left>X_MIN && glyph_right<X_MAX && glyph_top>Y_MIN && glyph_bottom<Y_MAX;
                    stage<=3;
                end else if(stage==3)begin
                    stage<=4;
                end else if(stage==4)begin
                    // Internal anchors 1/4/7 encode color only. The pipeline
                    // adds the unique complete-glyph shape after tag pairing.
                    candidate<=coverage_good ? (selected_color-1)*3+1 : 0;
                    stage<=5;
                end else if(stage==5)begin
                    out_frame<=1;out_healthy<=1;out_present<=saved_present;
                    out_frame_id<=active_id;out_source_test<=active_source;
                    stable_count<=next_count;previous_item<=candidate;previous_source<=active_source;
                    out_valid<=candidate!=0 && next_count>=CONFIRM_FRAMES;
                    out_item<=candidate!=0 && next_count>=CONFIRM_FRAMES ? candidate : 0;
                    stage<=0;
                end
            end
        end
    end
    // synthesis translate_off
    initial if(FRAME_WIDTH<1 || FRAME_WIDTH>2048 || FRAME_HEIGHT<1 || FRAME_HEIGHT>1024 ||
        FRAME_WIDTH*FRAME_HEIGHT>1048575 || X_MIN<0 || X_MAX>=FRAME_WIDTH || X_MIN>=X_MAX ||
        Y_MIN<0 || Y_MAX>=FRAME_HEIGHT || Y_MIN>=Y_MAX || MIN_AREA<1 || MIN_WIDTH<1 || MIN_HEIGHT<1 ||
        RUN_LENGTH!=1 || CONFIRM_FRAMES<1 || CONFIRM_FRAMES>255)
        $fatal(1,"pixel26_block_recognizer invalid parameters (RUN_LENGTH must be 1)");
    // synthesis translate_on
endmodule
