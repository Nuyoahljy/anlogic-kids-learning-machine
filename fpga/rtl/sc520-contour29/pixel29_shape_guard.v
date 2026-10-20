// Full glyph and color contour share one frame/index and one constant ROM.
// Ellipse bits are rejection-only. New recovery is circle-only.
module pixel29_shape_guard #(
    parameter GEOMETRY_FILE="contour29-shapes.mem"
) (
    input wire clk,rst_n,flush,frame_start,sample_valid,
    input wire [9:0] sample_index,
    input wire sample_foreground,contour_foreground,contour_axis_foreground,full_axis_foreground,
    input wire frame_end,frame_good,frame_present,
    input wire [31:0] frame_id,
    input wire frame_source_test,
    input wire contour_qualified,contour_aspect_good,contour_boundary_repair,contour_exterior_ok,
    input wire [1:0] contour_color,
    output reg out_frame,out_healthy,
    output reg [2:0] shape_ok,original_shape_ok,contour_shape_ok,
    output reg negative_only,recovery_geometry_good,
    output reg [10:0] recovery_distance,geometry_minimum,
    output reg [1:0] out_contour_color,
    output reg [31:0] out_frame_id,
    output reg out_source_test,
    output reg [10:0] distance_circle,distance_square,distance_triangle
);
    localparam [1:0] IDLE=0,CAPTURE=1,RANK=2,EMIT=3;
    reg [1:0] state;
    reg [10:0] count;
    reg [15:0] geometry[0:1023];
    reg [15:0] geometry_q;
    wire rom_enable=state==CAPTURE && sample_valid && !frame_start && count<1024 && !flush;
    always @(posedge clk)if(rom_enable)geometry_q<=geometry[sample_index];
    initial $readmemh(GEOMETRY_FILE,geometry);

    reg [10:0] full_distance[0:2],body_distance[0:2];
    reg [10:0] full_axis_distance[0:1],body_axis_distance[0:1];
    reg [10:0] full_ellipse_distance[0:11],body_ellipse_distance[0:11];
    reg [10:0] full_ellipse_min,body_ellipse_min;
    reg [3:0] rank_index;
    reg pending_valid,pending_full,pending_body,pending_body_axis,pending_full_axis;
    reg bad,saved_good,saved_present,active_source,saved_source;
    reg saved_body,saved_aspect,saved_boundary,saved_exterior;
    reg [1:0] saved_color;
    reg [31:0] active_id,saved_id;
    wire tag_bad=frame_id!=active_id || frame_source_test!=active_source;
    wire [10:0] full_axis_min=full_axis_distance[0]<full_axis_distance[1] ? full_axis_distance[0]:full_axis_distance[1];
    wire [10:0] body_axis_min=body_axis_distance[0]<body_axis_distance[1] ? body_axis_distance[0]:body_axis_distance[1];
    wire [10:0] full_min01=full_distance[0]<full_distance[1] ? full_distance[0]:full_distance[1];
    wire [10:0] full_min=full_min01<full_distance[2] ? full_min01:full_distance[2];
    wire [10:0] body_min01=body_distance[0]<body_distance[1] ? body_distance[0]:body_distance[1];
    wire [10:0] body_min=body_min01<body_distance[2] ? body_min01:body_distance[2];
    wire [2:0] full_bits={full_distance[2]<=20,full_distance[1]<=20,full_distance[0]<=20};
    wire axis_circle=saved_aspect && !saved_boundary && body_axis_min<=20 && body_axis_min<body_ellipse_min;
    wire [2:0] body_bits=axis_circle ? 3'b001 :
        {body_distance[2]<=20,body_distance[1]<=20,body_distance[0]<=20};
    wire body_single=body_bits==1 || body_bits==2 || body_bits==4;
    wire conflict=saved_body && body_single && full_bits!=0 && full_bits!=body_bits;
    wire recover=saved_body && axis_circle && saved_exterior && full_ellipse_min>20 && full_bits==0;
    integer i;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;count<=0;rank_index<=0;bad<=0;pending_valid<=0;
            pending_full<=0;pending_body<=0;pending_body_axis<=0;pending_full_axis<=0;
            saved_good<=0;saved_present<=1;active_id<=0;saved_id<=0;active_source<=0;saved_source<=0;
            saved_body<=0;saved_aspect<=0;saved_boundary<=0;saved_exterior<=0;saved_color<=0;
            full_ellipse_min<=1025;body_ellipse_min<=1025;
            out_frame<=0;out_healthy<=0;shape_ok<=0;original_shape_ok<=0;contour_shape_ok<=0;
            negative_only<=0;recovery_geometry_good<=0;recovery_distance<=1025;geometry_minimum<=1025;
            out_contour_color<=0;out_frame_id<=0;out_source_test<=0;
            distance_circle<=0;distance_square<=0;distance_triangle<=0;
            for(i=0;i<3;i=i+1)begin full_distance[i]<=0;body_distance[i]<=0;end
            for(i=0;i<2;i=i+1)begin full_axis_distance[i]<=0;body_axis_distance[i]<=0;end
            for(i=0;i<12;i=i+1)begin full_ellipse_distance[i]<=0;body_ellipse_distance[i]<=0;end
        end else if(flush)begin
            state<=IDLE;count<=0;bad<=0;pending_valid<=0;saved_good<=0;
            out_frame<=0;out_healthy<=0;shape_ok<=0;original_shape_ok<=0;contour_shape_ok<=0;
            negative_only<=0;recovery_geometry_good<=0;out_contour_color<=0;
        end else begin
            out_frame<=0;pending_valid<=0;
            if(frame_start)begin
                state<=CAPTURE;count<=0;bad<=state==CAPTURE || state==RANK || sample_valid || frame_end;
                active_id<=frame_id;active_source<=frame_source_test;
                for(i=0;i<3;i=i+1)begin full_distance[i]<=0;body_distance[i]<=0;end
                for(i=0;i<2;i=i+1)begin full_axis_distance[i]<=0;body_axis_distance[i]<=0;end
                for(i=0;i<12;i=i+1)begin full_ellipse_distance[i]<=0;body_ellipse_distance[i]<=0;end
            end else if(state==CAPTURE)begin
                if(tag_bad)bad<=1;
                if(pending_valid)begin
                    for(i=0;i<3;i=i+1)begin
                        full_distance[i]<=full_distance[i]+(pending_full^geometry_q[i]);
                        body_distance[i]<=body_distance[i]+(pending_body^geometry_q[i]);
                    end
                    full_axis_distance[0]<=full_axis_distance[0]+(pending_full_axis^geometry_q[0]);
                    full_axis_distance[1]<=full_axis_distance[1]+(pending_full_axis^geometry_q[3]);
                    body_axis_distance[0]<=body_axis_distance[0]+(pending_body_axis^geometry_q[0]);
                    body_axis_distance[1]<=body_axis_distance[1]+(pending_body_axis^geometry_q[3]);
                    for(i=0;i<12;i=i+1)begin
                        full_ellipse_distance[i]<=full_ellipse_distance[i]+(pending_full^geometry_q[4+i]);
                        body_ellipse_distance[i]<=body_ellipse_distance[i]+(pending_body^geometry_q[4+i]);
                    end
                end
                if(sample_valid)begin
                    if(count>=1024 || {1'b0,sample_index}!=count)bad<=1;
                    if(count<1025)count<=count+1'b1;
                    pending_valid<=rom_enable;pending_full<=sample_foreground;
                    pending_body<=contour_foreground;pending_body_axis<=contour_axis_foreground;
                    pending_full_axis<=full_axis_foreground;
                end
                if(frame_end)begin
                    saved_good<=frame_good && !bad && !tag_bad && count==1024 && !sample_valid;
                    saved_present<=frame_present;saved_id<=active_id;saved_source<=active_source;
                    saved_body<=contour_qualified;saved_aspect<=contour_aspect_good;
                    saved_boundary<=contour_boundary_repair;saved_exterior<=contour_exterior_ok;saved_color<=contour_color;
                    full_ellipse_min<=1025;body_ellipse_min<=1025;rank_index<=0;state<=RANK;
                end
            end else if(state==RANK)begin
                if(sample_valid || frame_end) saved_good<=0;
                if(full_ellipse_distance[rank_index]<full_ellipse_min)full_ellipse_min<=full_ellipse_distance[rank_index];
                if(body_ellipse_distance[rank_index]<body_ellipse_min)body_ellipse_min<=body_ellipse_distance[rank_index];
                if(rank_index==11)state<=EMIT;else rank_index<=rank_index+1'b1;
            end else if(state==EMIT)state<=IDLE;
            else if(frame_end)begin
                saved_good<=0;saved_present<=1;saved_id<=frame_id;saved_source<=frame_source_test;
                saved_body<=0;full_ellipse_min<=1025;body_ellipse_min<=1025;state<=EMIT;
            end
            if(state==EMIT)begin
                out_frame<=1;out_healthy<=saved_good && !sample_valid && !frame_end;
                shape_ok<=saved_good && saved_present && !conflict ? (full_bits!=0 ? full_bits:recover ? 3'b001:3'b000):3'b000;
                original_shape_ok<=saved_good && saved_present ? full_bits:3'b000;
                contour_shape_ok<=saved_good && saved_body ? body_bits:3'b000;
                negative_only<=saved_good && (full_axis_min<=20 || full_ellipse_min<=20 ||
                    (saved_body && (body_axis_min<=20 || body_ellipse_min<=20)));
                recovery_geometry_good<=saved_good && recover && !conflict;
                recovery_distance<=body_axis_min;
                geometry_minimum<=saved_body && body_min<full_min ? body_min:full_min;
                out_contour_color<=saved_color;out_frame_id<=saved_id;out_source_test<=saved_source;
                distance_circle<=full_distance[0];distance_square<=full_distance[1];distance_triangle<=full_distance[2];
            end
        end
    end
endmodule
