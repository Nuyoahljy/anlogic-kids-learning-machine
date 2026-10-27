// I0309: retain the eight-class default; card-only mode has no shape dependency.
module pixel309_arbitrate #(
    parameter integer WAIT_CYCLES=1200000,
    parameter integer SHAPE_ENABLE=1
) (
    input wire clk,rst_n,flush,
    input wire scene_event,scene_healthy,scene_present,
    input wire [31:0] scene_frame_id,input wire scene_source_test,
    input wire [15:0] scene_count,scene_glyph_count,
    input wire scene_y_available,input wire [7:0] scene_y_min,scene_y_max,
    input wire [11:0] scene_bbox_width,scene_bbox_height,
    input wire [10:0] scene_bbox_left,scene_bbox_right,
    input wire [9:0] scene_bbox_top,scene_bbox_bottom,
    input wire scene_axis_eligible,scene_y_allowed,
    input wire scene_clipped,scene_border_uncertain,scene_paper_flag,
    input wire shape_event,shape_healthy,shape_present,
    input wire [31:0] shape_frame_id,input wire shape_source_test,
    input wire [10:0] shape_circle,shape_square,shape_triangle,
    input wire [10:0] shape_ellipse,shape_axis_circle,
    input wire shape_aspect_good,
    input wire card_event,card_healthy,card_present,card_valid,
    input wire [3:0] card_item,input wire [31:0] card_frame_id,
    input wire card_source_test,input wire [7:0] card_count,
    input wire [10:0] card_best,card_second,card_foreground,
    input wire card_qualified,
    output reg out_event,out_healthy,out_present,out_valid,
    output reg [3:0] out_item,output reg [31:0] out_frame_id,
    output reg out_source_test,output reg [7:0] out_count,
    output reg [7:0] out_reason,
    output reg [2:0] out_shape_bits,
    output reg [10:0] out_circle,out_square,out_triangle,
    output reg [10:0] out_card_best,out_card_second,out_foreground,
    output reg [2:0] out_available,
    output reg [15:0] out_scene_count,out_glyph_count,
    output reg [3:0] out_raw_item,
    output reg out_card_qualified,out_clipped,out_border_uncertain,out_paper_flag,
    output reg [3:0] out_shape_item,out_card_winner,
    output reg [10:0] out_bbox_left,out_bbox_right,
    output reg [9:0] out_bbox_top,out_bbox_bottom,
    output reg out_identity_known,out_arbitrated
);
    localparam integer AW=WAIT_CYCLES<2?1:$clog2(WAIT_CYCLES+1);
    localparam integer PREEXPIRY_AGE=WAIT_CYCLES<=1?0:WAIT_CYCLES-2;
    reg [AW-1:0] age;
    reg expiry_due;
    reg [2:0] seen;
    reg active;
    reg [31:0] active_id;
    reg active_source;
    reg s_good,s_present,s_yavailable,s_clip,s_border,s_paper;
    reg [15:0] s_count,s_glyph;
    reg [7:0] s_ymin,s_ymax;
    reg [11:0] s_width,s_height;
    reg [10:0] s_left,s_right;
    reg [9:0] s_top,s_bottom;
    reg s_axis_cached,s_y_cached;
    reg x_good,x_present;
    reg [10:0] x_circle,x_square,x_triangle,x_ellipse,x_axis;
    reg x_negative_plain,x_negative_axis;
    reg [2:0] x_distance_plain,x_distance_axis;
    reg [10:0] x_shape_best_plain,x_shape_best_axis;
    reg [10:0] x_competitor_plain,x_competitor_axis;
    reg c_good,c_present,c_qualified;
    reg [3:0] c_item;
    reg [10:0] c_best,c_second,c_foreground;
    wire shape_event_enabled=SHAPE_ENABLE && shape_event;
    wire any_event=scene_event||shape_event_enabled||card_event;
    wire [31:0] anchor_id=active?active_id:scene_event?scene_frame_id:
                                  shape_event_enabled?shape_frame_id:card_frame_id;
    wire anchor_source=active?active_source:scene_event?scene_source_test:
                               shape_event_enabled?shape_source_test:card_source_test;
    wire scene_matches=scene_frame_id==anchor_id && scene_source_test==anchor_source;
    wire shape_matches=shape_frame_id==anchor_id && shape_source_test==anchor_source;
    wire card_matches=card_frame_id==anchor_id && card_source_test==anchor_source;
    wire duplicate=(scene_event&&seen[0]) || (shape_event_enabled&&seen[1]) || (card_event&&seen[2]);
    wire identity_fault=(scene_event&&!scene_matches)||(shape_event_enabled&&!shape_matches)||
                         (card_event&&!card_matches);
    wire [2:0] arrived=seen | {card_event&&card_matches&&!seen[2],
                              shape_event_enabled&&shape_matches&&!seen[1],
                              scene_event&&scene_matches&&!seen[0]};
    wire ready=SHAPE_ENABLE ? (arrived==3'b111) : (arrived[0]&&arrived[2]);
    wire preexpiry_now=WAIT_CYCLES<=1 ? (age>=0) : ((age>=PREEXPIRY_AGE) && !(&age));
    wire expired=active&&!ready&&expiry_due;
    wire fault=duplicate||identity_fault||expired;
    wire take_scene=scene_event&&scene_matches&&!seen[0];
    wire take_shape=shape_event_enabled&&shape_matches&&!seen[1];
    wire take_card=card_event&&card_matches&&!seen[2];
    wire use_sgood=take_scene?scene_healthy:s_good;
    wire use_spresent=take_scene?scene_present:s_present;
    wire use_xgood=take_shape?shape_healthy:x_good;
    wire use_xpresent=take_shape?shape_present:x_present;
    wire use_cgood=take_card?card_healthy:c_good;
    wire use_cpresent=take_card?card_present:c_present;
    wire use_yavailable=take_scene?scene_y_available:s_yavailable;
    wire [7:0] use_ymin=take_scene?scene_y_min:s_ymin;
    wire [7:0] use_ymax=take_scene?scene_y_max:s_ymax;
    wire [11:0] use_width=take_scene?scene_bbox_width:s_width;
    wire [11:0] use_height=take_scene?scene_bbox_height:s_height;
    wire [10:0] use_left=take_scene?scene_bbox_left:s_left;
    wire [10:0] use_right=take_scene?scene_bbox_right:s_right;
    wire [9:0] use_top=take_scene?scene_bbox_top:s_top;
    wire [9:0] use_bottom=take_scene?scene_bbox_bottom:s_bottom;
    wire use_clip=take_scene?scene_clipped:s_clip;
    wire use_border=take_scene?scene_border_uncertain:s_border;
    wire use_paper=take_scene?scene_paper_flag:s_paper;
    wire [15:0] use_scene_count=take_scene?scene_count:s_count;
    wire [15:0] use_glyph_count=take_scene?scene_glyph_count:s_glyph;
    wire [10:0] dc=take_shape?shape_circle:x_circle;
    wire [10:0] dq=take_shape?shape_square:x_square;
    wire [10:0] dt=take_shape?shape_triangle:x_triangle;
    wire [10:0] de=take_shape?shape_ellipse:x_ellipse;
    wire [10:0] da=take_shape?shape_axis_circle:x_axis;
    wire [3:0] winner=take_card?card_item:c_item;
    wire [10:0] best=take_card?card_best:c_best;
    wire [10:0] second=take_card?card_second:c_second;
    wire [10:0] foreground=take_card?card_foreground:c_foreground;
    wire card_self_qualified=take_card?card_qualified:c_qualified;
    wire scene_axis_local=scene_axis_eligible;
    wire scene_y_local=scene_y_allowed;
    // synthesis translate_off
    wire geometry_available=arrived[0]&&use_yavailable && use_width!=0 && use_height!=0;
    wire [15:0] width8={1'b0,use_width,3'b000};
    wire [15:0] height8={1'b0,use_height,3'b000};
    wire [15:0] width7=width8-{4'd0,use_width};
    wire [15:0] height7=height8-{4'd0,use_height};
    // synthesis translate_on
    wire [10:0] live_effective_plain=shape_circle;
    wire [10:0] live_effective_axis=shape_axis_circle<shape_circle?shape_axis_circle:shape_circle;
    wire [10:0] live_shape_best_plain=live_effective_plain<shape_square?
                             (live_effective_plain<shape_triangle?live_effective_plain:shape_triangle):
                             (shape_square<shape_triangle?shape_square:shape_triangle);
    wire [10:0] live_shape_best_axis=live_effective_axis<shape_square?
                             (live_effective_axis<shape_triangle?live_effective_axis:shape_triangle):
                             (shape_square<shape_triangle?shape_square:shape_triangle);
    wire [10:0] live_competitor_plain=live_shape_best_plain<shape_ellipse?
                                      live_shape_best_plain:shape_ellipse;
    wire [10:0] live_competitor_axis=live_shape_best_axis<shape_ellipse?
                                     live_shape_best_axis:shape_ellipse;
    wire live_negative_plain={1'b0,shape_ellipse}>{1'b0,live_shape_best_plain}+12'd8;
    wire live_negative_axis={1'b0,shape_ellipse}>{1'b0,live_shape_best_axis}+12'd8;
    wire [2:0] live_distance_plain={shape_triangle<=11'd20,shape_square<=11'd20,
                                    live_effective_plain<=11'd20};
    wire [2:0] live_distance_axis={shape_triangle<=11'd20,shape_square<=11'd20,
                                   live_effective_axis<=11'd20};
    reg axis_eligible;
    reg y_allowed;
    always @* begin
        axis_eligible=arrived[0] && (take_scene?scene_axis_local:s_axis_cached);
        y_allowed=arrived[0] && (take_scene?scene_y_local:s_y_cached);
        // synthesis translate_off
        if((take_scene!==1'b0)&&(take_scene!==1'b1)) begin
            axis_eligible=geometry_available && width8>=height7 && height8>=width7;
            y_allowed=geometry_available && use_ymax>=use_ymin &&
                        ({1'b0,use_ymax}-{1'b0,use_ymin})<=9'd64;
        end
        // synthesis translate_on
    end
    reg negative_margin;
    reg [2:0] distance_bits;
    reg [10:0] selected_shape_best,selected_competitor;
    // synthesis translate_off
    wire [10:0] fallback_effective_circle=axis_eligible&&da<dc?da:dc;
    wire [10:0] fallback_shape_best=fallback_effective_circle<dq?
                             (fallback_effective_circle<dt?fallback_effective_circle:dt):
                             (dq<dt?dq:dt);
    wire [10:0] fallback_competitor=fallback_shape_best<de?fallback_shape_best:de;
    // synthesis translate_on
    always @* begin
        negative_margin=take_shape?
                        (axis_eligible?live_negative_axis:live_negative_plain):
                        (axis_eligible?x_negative_axis:x_negative_plain);
        distance_bits=take_shape?
                      (axis_eligible?live_distance_axis:live_distance_plain):
                      (axis_eligible?x_distance_axis:x_distance_plain);
        selected_shape_best=take_shape?
                            (axis_eligible?live_shape_best_axis:live_shape_best_plain):
                            (axis_eligible?x_shape_best_axis:x_shape_best_plain);
        selected_competitor=take_shape?
                            (axis_eligible?live_competitor_axis:live_competitor_plain):
                            (axis_eligible?x_competitor_axis:x_competitor_plain);
        // synthesis translate_off
        if(((take_shape!==1'b0)&&(take_shape!==1'b1)) ||
           ((axis_eligible!==1'b0)&&(axis_eligible!==1'b1))) begin
            negative_margin={1'b0,de}>{1'b0,fallback_shape_best}+12'd8;
            distance_bits={dt<=11'd20,dq<=11'd20,fallback_effective_circle<=11'd20};
            selected_shape_best=fallback_shape_best;
            selected_competitor=fallback_competitor;
        end
        // synthesis translate_on
    end
    wire shape_margin={1'b0,best}>{1'b0,selected_shape_best}+12'd8;
    wire card_margin={1'b0,selected_competitor}>{1'b0,best}+12'd8;
    wire negative_allows=negative_margin;
    wire [2:0] positive_bits=y_allowed&&negative_allows?distance_bits:3'b000;
    wire unique_shape=positive_bits==3'b001||positive_bits==3'b010||positive_bits==3'b100;
    wire [3:0] shape_candidate=!unique_shape?4'd0:
                         positive_bits[0]?4'd1:positive_bits[1]?4'd2:4'd3;
    // The original card qualification is max40/margin24; C only tightens apple.
    wire card_candidate=card_self_qualified && winner>=10 && winner<=14 &&
             second>=best && ({1'b0,second}-{1'b0,best})>=12'd24 &&
             best<=(winner==10?11'd32:11'd40);
    wire shape_wins=SHAPE_ENABLE && unique_shape && shape_margin;
    wire card_wins=card_candidate && (!SHAPE_ENABLE || card_margin);
    wire presence_consistent=SHAPE_ENABLE ?
        (use_spresent==use_xpresent && use_spresent==use_cpresent) :
        (use_spresent==use_cpresent);
    wire complete_good=SHAPE_ENABLE ?
        (use_sgood&&use_xgood&&use_cgood&&presence_consistent) :
        (use_sgood&&use_cgood&&presence_consistent);
    wire [3:0] decision=!use_spresent||use_clip||use_border?4'd0:
                               shape_wins?shape_candidate:card_wins?winner:4'd0;
    wire shape_competition=SHAPE_ENABLE &&
                            ((distance_bits!=0&&!unique_shape) ||
                             (distance_bits!=0&&!negative_allows));
    wire family_competition=SHAPE_ENABLE &&
                            (unique_shape||card_candidate) && !shape_wins&&!card_wins;
    wire card_competition=card_self_qualified && second>=best &&
                           ({1'b0,second}-{1'b0,best})<12'd24;
    wire [7:0] decision_reason=(!complete_good?8'h01:8'h00) |
              ((use_clip||use_border)?8'h08:8'h00) |
              ((use_spresent&&!use_clip&&!use_border&&decision==0&&
                (shape_competition||family_competition||card_competition))?8'h10:8'h00) |
              ((use_spresent&&!use_clip&&!use_border&&decision==0)?8'h20:8'h00);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            seen<=0;active<=0;age<=0;expiry_due<=0;active_id<=0;active_source<=0;
            s_good<=0;s_present<=1;s_yavailable<=0;s_clip<=0;s_border<=0;s_paper<=0;
            s_count<=0;s_glyph<=0;s_ymin<=0;s_ymax<=0;s_width<=0;s_height<=0;
            s_left<=0;s_right<=0;s_top<=0;s_bottom<=0;
            s_axis_cached<=0;s_y_cached<=0;
            x_good<=0;x_present<=1;x_circle<=2047;x_square<=2047;x_triangle<=2047;x_ellipse<=2047;x_axis<=2047;
            x_negative_plain<=0;x_negative_axis<=0;x_distance_plain<=0;x_distance_axis<=0;
            x_shape_best_plain<=2047;x_shape_best_axis<=2047;
            x_competitor_plain<=2047;x_competitor_axis<=2047;
            c_good<=0;c_present<=1;c_qualified<=0;c_item<=0;c_best<=2047;c_second<=2047;c_foreground<=2047;
            out_event<=0;out_healthy<=0;out_present<=1;out_valid<=0;out_item<=0;
            out_frame_id<=0;out_source_test<=0;out_count<=0;out_reason<=0;
            out_shape_bits<=0;out_circle<=2047;out_square<=2047;out_triangle<=2047;
            out_card_best<=2047;out_card_second<=2047;out_foreground<=2047;
            out_available<=0;out_scene_count<=0;out_glyph_count<=0;out_raw_item<=0;
            out_card_qualified<=0;out_clipped<=0;out_border_uncertain<=0;out_paper_flag<=0;
            out_shape_item<=0;out_card_winner<=0;out_identity_known<=0;out_arbitrated<=0;
            out_bbox_left<=0;out_bbox_right<=0;out_bbox_top<=0;out_bbox_bottom<=0;
        end else begin
            out_event<=0;
            if(flush) begin
                seen<=0;active<=0;age<=0;expiry_due<=0;out_event<=0;out_valid<=0;out_item<=0;
            end else if(fault || ready) begin
                seen<=0;active<=0;age<=0;expiry_due<=0;
                out_event<=1;out_frame_id<=anchor_id;out_source_test<=anchor_source;
                out_identity_known<=1;out_available<=arrived;
                out_healthy<=ready&&!fault&&complete_good;
                out_present<=arrived[0]?use_spresent:1'b1;
                out_valid<=ready&&!fault&&complete_good&&decision!=0;
                out_item<=ready&&!fault&&complete_good?decision:4'd0;
                out_count<=0;
                out_arbitrated<=ready&&!fault;
                out_raw_item<=ready&&!fault?decision:4'd0;
                out_reason<=fault?((duplicate||identity_fault?8'h02:8'h00)|(expired?8'h04:8'h00)):decision_reason;
                out_scene_count<=arrived[0]?use_scene_count:16'd0;
                out_glyph_count<=arrived[0]?use_glyph_count:16'd0;
                out_clipped<=arrived[0]&&use_clip;
                out_border_uncertain<=arrived[0]&&use_border;
                out_paper_flag<=arrived[0]&&use_paper;
                out_shape_bits<=SHAPE_ENABLE&&arrived[1]?positive_bits:3'd0;
                out_shape_item<=SHAPE_ENABLE&&arrived[1]?shape_candidate:4'd0;
                out_circle<=SHAPE_ENABLE&&arrived[1]?dc:11'd2047;
                out_square<=SHAPE_ENABLE&&arrived[1]?dq:11'd2047;
                out_triangle<=SHAPE_ENABLE&&arrived[1]?dt:11'd2047;
                out_card_best<=arrived[2]?best:11'd2047;
                out_card_second<=arrived[2]?second:11'd2047;
                out_foreground<=arrived[2]?foreground:11'd2047;
                out_card_winner<=arrived[2]?winner:4'd0;
                out_card_qualified<=arrived[2]&&card_candidate;
                out_bbox_left<=arrived[0]?use_left:0;
                out_bbox_right<=arrived[0]?use_right:0;
                out_bbox_top<=arrived[0]?use_top:0;
                out_bbox_bottom<=arrived[0]?use_bottom:0;
            end else begin
                if(active) begin
                    age<=age+1'b1;
                    expiry_due<=preexpiry_now;
                end
                if(any_event&&!active) begin
                    active<=1;active_id<=anchor_id;active_source<=anchor_source;age<=0;
                    expiry_due<=(WAIT_CYCLES<=1);
                end
                seen<=arrived;
                if(scene_event) begin
                    s_good<=scene_healthy;s_present<=scene_present;s_yavailable<=scene_y_available;
                    s_clip<=scene_clipped;s_border<=scene_border_uncertain;s_paper<=scene_paper_flag;
                    s_count<=scene_count;s_glyph<=scene_glyph_count;s_ymin<=scene_y_min;s_ymax<=scene_y_max;
                    s_width<=scene_bbox_width;s_height<=scene_bbox_height;
                    s_left<=scene_bbox_left;s_right<=scene_bbox_right;
                    s_top<=scene_bbox_top;s_bottom<=scene_bbox_bottom;
                    s_axis_cached<=scene_axis_local;s_y_cached<=scene_y_local;
                end
                if(shape_event_enabled) begin
                    x_good<=shape_healthy;x_present<=shape_present;x_circle<=shape_circle;x_square<=shape_square;
                    x_triangle<=shape_triangle;x_ellipse<=shape_ellipse;x_axis<=shape_axis_circle;
                    x_negative_plain<=live_negative_plain;x_negative_axis<=live_negative_axis;
                    x_distance_plain<=live_distance_plain;x_distance_axis<=live_distance_axis;
                    x_shape_best_plain<=live_shape_best_plain;x_shape_best_axis<=live_shape_best_axis;
                    x_competitor_plain<=live_competitor_plain;x_competitor_axis<=live_competitor_axis;
                end
                if(card_event) begin
                    c_good<=card_healthy;c_present<=card_present;c_qualified<=card_qualified;
                    c_item<=card_item;c_best<=card_best;c_second<=card_second;c_foreground<=card_foreground;
                end
            end
        end
    end
    // synthesis translate_off
    initial if(WAIT_CYCLES<1) $fatal(1,"pixel309_arbitrate WAIT_CYCLES must be positive");
    // synthesis translate_on
endmodule




