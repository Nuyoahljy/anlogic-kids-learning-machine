// Isolated, capture-clock diagnostics. All three RGB buses MUST already name
// the same four pixels. This module neither aligns ISP stages nor certifies CSI.
// The integration adapter must also align gain metadata and certify done_id.
module pixel14_color_diagnostics #(
    parameter integer FRAME_WIDTH=1280, FRAME_HEIGHT=720,
    parameter integer CLASS_X=160, CLASS_Y=120, CLASS_W=960, CLASS_H=480,
    parameter integer CENTER_X=636, CENTER_Y=356, CENTER_W=8, CENTER_H=8,
    parameter integer PAPER_X=192, PAPER_Y=144, PAPER_W=8, PAPER_H=8,
    parameter integer LANE0_MSB=1, LOW_CLIP=8, HIGH_CLIP=247,
    parameter integer COUNT_BITS=$clog2(FRAME_WIDTH*FRAME_HEIGHT+1),
    parameter integer ROI_COUNT_BITS=$clog2((CENTER_W*CENTER_H>PAPER_W*PAPER_H ?
                                           CENTER_W*CENTER_H:PAPER_W*PAPER_H)+1),
    parameter integer SUM_BITS=ROI_COUNT_BITS+8
) (
    input wire clk,rst_n,flush,
    input wire in_valid,in_sof,in_eol,
    input wire [31:0] in_frame_id,
    input wire [95:0] in_pre_wb,in_post_wb,in_post_tone,
    input wire [8:0] in_gain_r,in_gain_b,
    input wire in_frame_done,in_frame_good,
    input wire [31:0] in_done_id,
    input wire [20:0] in_neutral_count,
    output reg out_valid,out_trusted,out_reject,
    output reg [7:0] out_reject_reason,
    output reg [31:0] out_frame_id,
    output reg [8:0] out_gain_r,out_gain_b,
    output reg [20:0] out_neutral_count,
    output reg [COUNT_BITS-1:0] out_class_pixels,
    output reg [9*COUNT_BITS-1:0] out_color_hits,
    output reg [2*ROI_COUNT_BITS-1:0] out_roi_pixels,
    output reg [6*ROI_COUNT_BITS-1:0] out_roi_lowclip,out_roi_highclip,
    output reg [18*SUM_BITS-1:0] out_roi_rgb_sum,
    output reg [143:0] out_sample_rgb,
    output reg [1:0] out_sample_present,
    output wire [47:0] out_sample_xy
);
    localparam integer GROUPS=FRAME_WIDTH/4, TOTAL=GROUPS*FRAME_HEIGHT;
    localparam integer GROUP_BITS=$clog2(TOTAL+1);
    localparam [11:0] CENTER_SX=CENTER_X+CENTER_W/2, CENTER_SY=CENTER_Y+CENTER_H/2;
    localparam [11:0] PAPER_SX=PAPER_X+PAPER_W/2, PAPER_SY=PAPER_Y+PAPER_H/2;
    assign out_sample_xy={PAPER_SY,PAPER_SX,CENTER_SY,CENTER_SX};

    reg active,pending;
    reg [31:0] active_id;
    reg [8:0] frame_gain_r,frame_gain_b;
    reg [20:0] done_neutral;
    reg [GROUP_BITS-1:0] groups_seen;
    reg [10:0] group_x;
    reg [12:0] raster_y,lines_seen;
    wire start_ok=in_sof && !active && !pending && !in_frame_done;
    wire stream_active=active || start_ok;
    wire [10:0] current_group=start_ok ? 11'd0:group_x;
    wire [12:0] current_y=start_ok ? 13'd0:raster_y;
    wire [12:0] group_left={current_group,2'b00};
    wire [GROUP_BITS-1:0] prior_groups=start_ok ? {GROUP_BITS{1'b0}}:groups_seen;

    // Reasons are bit fields: overlap, orphan, marker, raster, frame identity,
    // external done/good, changing gain, missing internal sampling coverage.
    wire overlap=(in_sof && !start_ok) ||
                 (pending && (in_valid || in_sof || in_eol || in_frame_done));
    wire orphan=in_valid && !stream_active;
    wire marker=in_eol && !in_valid;
    wire raster=in_valid && stream_active &&
        (prior_groups>=TOTAL || current_y>=FRAME_HEIGHT ||
         in_eol!=(current_group==GROUPS-1));
    wire identity=(in_valid && active && in_frame_id!=active_id) ||
                  (in_frame_done && active && in_done_id!=active_id);
    wire bad_done=in_frame_done && (!active || pending || in_valid || in_sof || in_eol ||
        !in_frame_good || groups_seen!=TOTAL || lines_seen!=FRAME_HEIGHT);
    wire changed_gain=in_valid && active && groups_seen!=0 &&
        (in_gain_r!=frame_gain_r || in_gain_b!=frame_gain_b);
    wire [7:0] fault={1'b0,changed_gain,bad_done,identity,raster,marker,orphan,overlap};
    wire accept_pixel=in_valid && stream_active && fault==0 && !flush;

    function [23:0] pixel;
        input [95:0] data;
        input integer lane;
        begin
            if(LANE0_MSB)pixel=data[(3-lane)*24+:24];
            else pixel=data[lane*24+:24];
        end
    endfunction
    function [2:0] color_mask;
        input [23:0] rgb;
        reg [8:0] r,g,b;
        begin
            r={1'b0,rgb[23:16]};g={1'b0,rgb[15:8]};b={1'b0,rgb[7:0]};
            color_mask[0]=r>=80 && r>=g+9'd32 && r>=b+9'd32;
            color_mask[1]=r>=96 && g>=80 && b<=96 && r<=g+9'd80 &&
                          g<=r+9'd80 && r>=b+9'd32 && g>=b+9'd24;
            color_mask[2]=b>=80 && b>=r+9'd24 && b>=g+9'd24;
        end
    endfunction
    wire [287:0] stages={in_post_tone,in_post_wb,in_pre_wb};
    reg [2:0] add_class,add_roi[0:1],add_hits[0:8];
    reg [2:0] add_low[0:5],add_high[0:5];
    reg [9:0] add_sum[0:17];
    reg [143:0] sample_rgb;
    reg [1:0] sample_mask;
    reg [23:0] rgb;
    reg [2:0] hits;
    reg in_class,in_roi;
    integer lane,s,c,q,x,k;
    always @* begin
        add_class=0;sample_rgb=0;sample_mask=0;rgb=0;hits=0;
        in_class=0;in_roi=0;x=0;
        for(k=0;k<2;k=k+1)add_roi[k]=0;
        for(k=0;k<9;k=k+1)add_hits[k]=0;
        for(k=0;k<6;k=k+1)begin add_low[k]=0;add_high[k]=0;end
        for(k=0;k<18;k=k+1)add_sum[k]=0;
        for(lane=0;lane<4;lane=lane+1)begin
            x=group_left+lane;
            in_class=x>=CLASS_X && x<CLASS_X+CLASS_W && current_y>=CLASS_Y && current_y<CLASS_Y+CLASS_H;
            if(in_class)add_class=add_class+1'b1;
            for(s=0;s<3;s=s+1)begin
                rgb=pixel(stages[s*96+:96],lane);hits=color_mask(rgb);
                for(c=0;c<3;c=c+1)
                    if(in_class)add_hits[s*3+c]=add_hits[s*3+c]+hits[c];
                for(q=0;q<2;q=q+1)begin
                    in_roi=q==0 ? (x>=CENTER_X && x<CENTER_X+CENTER_W && current_y>=CENTER_Y && current_y<CENTER_Y+CENTER_H):
                                   (x>=PAPER_X && x<PAPER_X+PAPER_W && current_y>=PAPER_Y && current_y<PAPER_Y+PAPER_H);
                    if(in_roi)begin
                        if(s==0)add_roi[q]=add_roi[q]+1'b1;
                        add_low[q*3+s]=add_low[q*3+s]+(rgb[23:16]<=LOW_CLIP || rgb[15:8]<=LOW_CLIP || rgb[7:0]<=LOW_CLIP);
                        add_high[q*3+s]=add_high[q*3+s]+(rgb[23:16]>=HIGH_CLIP || rgb[15:8]>=HIGH_CLIP || rgb[7:0]>=HIGH_CLIP);
                        add_sum[(q*3+s)*3]=add_sum[(q*3+s)*3]+{2'b0,rgb[23:16]};
                        add_sum[(q*3+s)*3+1]=add_sum[(q*3+s)*3+1]+{2'b0,rgb[15:8]};
                        add_sum[(q*3+s)*3+2]=add_sum[(q*3+s)*3+2]+{2'b0,rgb[7:0]};
                    end
                    if((q==0 && x==CENTER_SX && current_y==CENTER_SY) ||
                       (q==1 && x==PAPER_SX && current_y==PAPER_SY))begin
                        sample_mask[q]=1;sample_rgb[(q*3+s)*24+:24]=rgb;
                    end
                end
            end
        end
    end

    // One registered group-contribution stage separates RGB comparisons from
    // the frame accumulators. Done is accepted on a blank cycle; publish one
    // clock later, after the final registered contribution has been consumed.
    reg d_valid,d_clear;
    reg [2:0] d_class,d_roi[0:1],d_hits[0:8],d_low[0:5],d_high[0:5];
    reg [9:0] d_sum[0:17];
    reg [143:0] d_sample_rgb;
    reg [1:0] d_sample_mask;
    reg [COUNT_BITS-1:0] class_pixels,hits_count[0:8];
    reg [ROI_COUNT_BITS-1:0] roi_pixels[0:1],low_count[0:5],high_count[0:5];
    reg [SUM_BITS-1:0] rgb_sum[0:17];
    reg [143:0] saved_samples;
    reg [1:0] saved_sample_mask;
    wire coverage_ok=class_pixels==CLASS_W*CLASS_H && roi_pixels[0]==CENTER_W*CENTER_H &&
                     roi_pixels[1]==PAPER_W*PAPER_H && saved_sample_mask==2'b11;
    integer i;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            active<=0;pending<=0;active_id<=0;frame_gain_r<=0;frame_gain_b<=0;done_neutral<=0;
            groups_seen<=0;group_x<=0;raster_y<=0;lines_seen<=0;
            d_valid<=0;d_clear<=0;d_class<=0;d_sample_rgb<=0;d_sample_mask<=0;
            class_pixels<=0;saved_samples<=0;saved_sample_mask<=0;
            out_valid<=0;out_trusted<=0;out_reject<=0;out_reject_reason<=0;out_frame_id<=0;
            out_gain_r<=0;out_gain_b<=0;out_neutral_count<=0;out_class_pixels<=0;out_color_hits<=0;
            out_roi_pixels<=0;out_roi_lowclip<=0;out_roi_highclip<=0;out_roi_rgb_sum<=0;
            out_sample_rgb<=0;out_sample_present<=0;
            for(i=0;i<2;i=i+1)begin d_roi[i]<=0;roi_pixels[i]<=0;end
            for(i=0;i<9;i=i+1)begin d_hits[i]<=0;hits_count[i]<=0;end
            for(i=0;i<6;i=i+1)begin d_low[i]<=0;d_high[i]<=0;low_count[i]<=0;high_count[i]<=0;end
            for(i=0;i<18;i=i+1)begin d_sum[i]<=0;rgb_sum[i]<=0;end
        end else begin
            out_valid<=0;out_reject<=0;
            if(flush || fault!=0)begin
                active<=0;pending<=0;d_valid<=0;d_clear<=0;
                groups_seen<=0;group_x<=0;raster_y<=0;lines_seen<=0;
                out_trusted<=0;out_sample_present<=0;
                if(!flush)begin out_reject<=1;out_reject_reason<=fault;end
            end else begin
                d_valid<=accept_pixel;d_clear<=start_ok;
                if(accept_pixel)begin
                    d_class<=add_class;d_sample_rgb<=sample_rgb;d_sample_mask<=sample_mask;
                    for(i=0;i<2;i=i+1)d_roi[i]<=add_roi[i];
                    for(i=0;i<9;i=i+1)d_hits[i]<=add_hits[i];
                    for(i=0;i<6;i=i+1)begin d_low[i]<=add_low[i];d_high[i]<=add_high[i];end
                    for(i=0;i<18;i=i+1)d_sum[i]<=add_sum[i];
                end
                if(d_clear || d_valid)begin
                    class_pixels<=(d_clear ? 0:class_pixels)+(d_valid ? d_class:0);
                    for(i=0;i<2;i=i+1)roi_pixels[i]<=(d_clear ? 0:roi_pixels[i])+(d_valid ? d_roi[i]:0);
                    for(i=0;i<9;i=i+1)hits_count[i]<=(d_clear ? 0:hits_count[i])+(d_valid ? d_hits[i]:0);
                    for(i=0;i<6;i=i+1)begin
                        low_count[i]<=(d_clear ? 0:low_count[i])+(d_valid ? d_low[i]:0);
                        high_count[i]<=(d_clear ? 0:high_count[i])+(d_valid ? d_high[i]:0);
                    end
                    for(i=0;i<18;i=i+1)rgb_sum[i]<=(d_clear ? 0:rgb_sum[i])+(d_valid ? d_sum[i]:0);
                    if(d_clear)begin saved_samples<=0;saved_sample_mask<=0;end
                    if(d_valid)begin
                        saved_sample_mask<=(d_clear ? 2'b00:saved_sample_mask)|d_sample_mask;
                        for(i=0;i<2;i=i+1)if(d_sample_mask[i])saved_samples[i*72+:72]<=d_sample_rgb[i*72+:72];
                    end
                end
                if(start_ok)begin
                    active<=1;active_id<=in_frame_id;groups_seen<=0;group_x<=0;raster_y<=0;lines_seen<=0;
                    out_trusted<=0;out_sample_present<=0;out_reject_reason<=0;
                end
                if(accept_pixel)begin
                    groups_seen<=prior_groups+1'b1;
                    if(prior_groups==0)begin frame_gain_r<=in_gain_r;frame_gain_b<=in_gain_b;end
                    if(in_eol)begin
                        group_x<=0;raster_y<=current_y+1'b1;lines_seen<=current_y+1'b1;
                    end else begin group_x<=current_group+1'b1;raster_y<=current_y;end
                end
                if(in_frame_done)begin active<=0;pending<=1;done_neutral<=in_neutral_count;end
                if(pending)begin
                    pending<=0;
                    if(coverage_ok)begin
                        out_valid<=1;out_trusted<=1;out_reject_reason<=0;
                        out_frame_id<=active_id;out_gain_r<=frame_gain_r;out_gain_b<=frame_gain_b;out_neutral_count<=done_neutral;
                        out_class_pixels<=class_pixels;out_sample_rgb<=saved_samples;out_sample_present<=saved_sample_mask;
                        for(i=0;i<2;i=i+1)out_roi_pixels[i*ROI_COUNT_BITS+:ROI_COUNT_BITS]<=roi_pixels[i];
                        for(i=0;i<9;i=i+1)out_color_hits[i*COUNT_BITS+:COUNT_BITS]<=hits_count[i];
                        for(i=0;i<6;i=i+1)begin
                            out_roi_lowclip[i*ROI_COUNT_BITS+:ROI_COUNT_BITS]<=low_count[i];
                            out_roi_highclip[i*ROI_COUNT_BITS+:ROI_COUNT_BITS]<=high_count[i];
                        end
                        for(i=0;i<18;i=i+1)out_roi_rgb_sum[i*SUM_BITS+:SUM_BITS]<=rgb_sum[i];
                    end else begin out_trusted<=0;out_sample_present<=0;out_reject<=1;out_reject_reason<=8'h80;end
                end
            end
        end
    end
    // synthesis translate_off
    initial begin
        if(FRAME_WIDTH<4 || FRAME_WIDTH>4096 || FRAME_WIDTH%4!=0 || FRAME_HEIGHT<1 || FRAME_HEIGHT>4096 ||
           CLASS_X<0 || CLASS_Y<0 || CLASS_W<1 || CLASS_H<1 || CLASS_X+CLASS_W>FRAME_WIDTH || CLASS_Y+CLASS_H>FRAME_HEIGHT ||
           CENTER_X<0 || CENTER_Y<0 || CENTER_W<1 || CENTER_H<1 || CENTER_X+CENTER_W>FRAME_WIDTH || CENTER_Y+CENTER_H>FRAME_HEIGHT ||
           PAPER_X<0 || PAPER_Y<0 || PAPER_W<1 || PAPER_H<1 || PAPER_X+PAPER_W>FRAME_WIDTH || PAPER_Y+PAPER_H>FRAME_HEIGHT ||
           COUNT_BITS<$clog2(FRAME_WIDTH*FRAME_HEIGHT+1) ||
           ROI_COUNT_BITS<$clog2((CENTER_W*CENTER_H>PAPER_W*PAPER_H ? CENTER_W*CENTER_H:PAPER_W*PAPER_H)+1) ||
           SUM_BITS<ROI_COUNT_BITS+8 || LOW_CLIP<0 || HIGH_CLIP>255 || LOW_CLIP>=HIGH_CLIP ||
           (LANE0_MSB!=0 && LANE0_MSB!=1))$fatal(1,"color diagnostics invalid parameters");
    end
    // synthesis translate_on
endmodule
