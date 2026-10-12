// Capture-domain candidate. A complete RGB raster is necessary but is never
// sufficient: in_frame_done must certify that the associated real capture EOF
// has been seen AND that this frame's ISP output has drained. It is a blank
// cycle, not a line tlast and not a locally invented last-pixel pulse.
module capture_rgb96 #(
    parameter integer FRAME_WIDTH=1280, FRAME_HEIGHT=720,
    parameter integer ROI_X=400, ROI_Y=120, ROI_SIZE=480,
    parameter integer BLOCK_ROI_X=320, BLOCK_ROI_Y=120,
    parameter integer BLOCK_ROI_WIDTH=640, BLOCK_ROI_HEIGHT=480,
    parameter integer DARK_THRESHOLD=180, CHROMA_THRESHOLD=40
) (
    input wire clk,rst_n,flush,
    input wire in_frame_start,
    input wire [31:0] in_frame_id,
    input wire in_source_test,
    input wire in_valid,in_eol,
    input wire [95:0] in_rgb96,
    input wire in_frame_done,in_frame_good,
    input wire [31:0] in_done_id,
    input wire in_done_source_test,
    input wire in_revoke,
    output reg card_frame_start,card_sample_valid,
    output reg [9:0] card_sample_index,
    output reg card_sample_foreground,
    output reg card_frame_end,card_frame_good,card_frame_present,
    output reg [31:0] card_frame_id,
    output reg card_source_test,
    output reg [19:0] roi_fg_count,
    output reg block_valid,block_sof,block_eol,
    output reg [10:0] block_x,
    output reg [9:0] block_y,
    output reg [23:0] block_rgb,
    output reg block_frame_end,block_frame_good,block_frame_present,
    output reg [19:0] block_roi_fg_count,
    output reg [31:0] block_frame_id,
    output reg block_source_test,
    output wire revoke
);
    localparam integer GROUPS_PER_LINE=FRAME_WIDTH/4;
    localparam integer TOTAL_GROUPS=GROUPS_PER_LINE*FRAME_HEIGHT;
    localparam integer CELL=ROI_SIZE/32;
    reg active,bad,orphan_reported,fault_pulse;
    reg [31:0] active_id,groups_seen;
    reg active_source;
    reg [10:0] group_x,lines_seen,next_sample_x;
    reg [9:0] raster_y,next_sample_y;
    reg [10:0] samples_seen;
    reg [19:0] foreground_seen,block_foreground_seen;
    wire start_accept=in_frame_start && !active && !in_frame_done && !in_revoke;
    wire start_collision=in_frame_start && (active || in_frame_done || in_revoke);
    wire stream_active=active || start_accept;
    wire [10:0] current_group=start_accept ? 11'd0 : group_x;
    wire [9:0] current_y=start_accept ? 10'd0 : raster_y;
    wire [31:0] current_groups=start_accept ? 32'd0 : groups_seen;
    wire [10:0] current_samples=start_accept ? 11'd0 : samples_seen;
    wire [10:0] current_sample_x=start_accept ? ROI_X+CELL/2 : next_sample_x;
    wire [9:0] current_sample_y=start_accept ? ROI_Y+CELL/2 : next_sample_y;
    wire [12:0] group_left={current_group,2'b00};
    wire pixel_fault=current_groups>=TOTAL_GROUPS ||
                     in_eol!=(current_group==GROUPS_PER_LINE-1) ||
                     (!start_accept && (in_frame_id!=active_id || in_source_test!=active_source));
    wire sample_hit=current_samples<1024 && current_y==current_sample_y &&
                    current_sample_x>=group_left && current_sample_x<group_left+4;
    wire [1:0] sample_lane=current_sample_x-group_left;
    wire complete_good=active && !bad && !in_revoke && !in_valid && !in_eol && !in_frame_start &&
                       in_frame_good && in_done_id==active_id && in_done_source_test==active_source &&
                       groups_seen==TOTAL_GROUPS && lines_seen==FRAME_HEIGHT && samples_seen==1024;
    assign revoke=in_revoke || fault_pulse;

    function [23:0] lane_pixel;
        input [95:0] data;
        input [1:0] lane;
        begin
            case(lane)
                0: lane_pixel=data[95:72];
                1: lane_pixel=data[71:48];
                2: lane_pixel=data[47:24];
                default: lane_pixel=data[23:0];
            endcase
        end
    endfunction
    function is_foreground;
        input [23:0] rgb;
        reg [7:0] r,g,b,minimum,maximum;
        begin
            r=rgb[23:16];g=rgb[15:8];b=rgb[7:0];
            minimum=r<g ? (r<b ? r:b) : (g<b ? g:b);
            maximum=r>g ? (r>b ? r:b) : (g>b ? g:b);
            is_foreground=minimum<DARK_THRESHOLD || ({1'b0,maximum}-{1'b0,minimum})>=CHROMA_THRESHOLD;
        end
    endfunction
    integer lane;
    reg [2:0] foreground_increment,block_foreground_increment;
    always @* begin
        foreground_increment=0;block_foreground_increment=0;
        for(lane=0;lane<4;lane=lane+1) begin
            if(current_y>=ROI_Y && current_y<ROI_Y+ROI_SIZE &&
               group_left+lane>=ROI_X && group_left+lane<ROI_X+ROI_SIZE)
                foreground_increment=foreground_increment+is_foreground(lane_pixel(in_rgb96,lane[1:0]));
            if(current_y>=BLOCK_ROI_Y && current_y<BLOCK_ROI_Y+BLOCK_ROI_HEIGHT &&
               group_left+lane>=BLOCK_ROI_X && group_left+lane<BLOCK_ROI_X+BLOCK_ROI_WIDTH)
                block_foreground_increment=block_foreground_increment+is_foreground(lane_pixel(in_rgb96,lane[1:0]));
        end
    end

    // synthesis translate_off
    initial begin
        if(FRAME_WIDTH<64 || FRAME_WIDTH>2048 || FRAME_WIDTH%4!=0 ||
           FRAME_HEIGHT<64 || FRAME_HEIGHT>1024 || FRAME_HEIGHT%4!=0 ||
           ROI_SIZE<128 || ROI_SIZE>992 || ROI_SIZE%32!=0 || ROI_X<0 || ROI_Y<0 ||
           ROI_X+ROI_SIZE>FRAME_WIDTH || ROI_Y+ROI_SIZE>FRAME_HEIGHT ||
           BLOCK_ROI_X<0 || BLOCK_ROI_Y<0 || BLOCK_ROI_WIDTH<1 || BLOCK_ROI_HEIGHT<1 ||
           BLOCK_ROI_X+BLOCK_ROI_WIDTH>FRAME_WIDTH || BLOCK_ROI_Y+BLOCK_ROI_HEIGHT>FRAME_HEIGHT ||
           BLOCK_ROI_WIDTH*BLOCK_ROI_HEIGHT>1048575 ||
           DARK_THRESHOLD<0 || DARK_THRESHOLD>255 || CHROMA_THRESHOLD<1 || CHROMA_THRESHOLD>255) begin
            $display("PIXEL14_CAPTURE_PARAMETER_ERROR: invalid geometry or thresholds");
            $finish;
        end
    end
    // synthesis translate_on

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            active<=0;bad<=0;orphan_reported<=0;fault_pulse<=0;
            active_id<=0;active_source<=0;groups_seen<=0;group_x<=0;raster_y<=0;lines_seen<=0;
            next_sample_x<=ROI_X+CELL/2;next_sample_y<=ROI_Y+CELL/2;samples_seen<=0;foreground_seen<=0;block_foreground_seen<=0;
            card_frame_start<=0;card_sample_valid<=0;card_sample_index<=0;card_sample_foreground<=0;
            card_frame_end<=0;card_frame_good<=0;card_frame_present<=1;card_frame_id<=0;card_source_test<=0;roi_fg_count<=0;
            block_valid<=0;block_sof<=0;block_eol<=0;block_x<=0;block_y<=0;block_rgb<=0;
            block_frame_end<=0;block_frame_good<=0;block_frame_present<=1;block_roi_fg_count<=0;block_frame_id<=0;block_source_test<=0;
        end else if(flush) begin
            // Synchronous cancellation is deliberately not a new revoke event.
            active<=0;bad<=0;orphan_reported<=0;fault_pulse<=0;
            groups_seen<=0;group_x<=0;raster_y<=0;lines_seen<=0;samples_seen<=0;foreground_seen<=0;block_foreground_seen<=0;
            next_sample_x<=ROI_X+CELL/2;next_sample_y<=ROI_Y+CELL/2;
            card_frame_start<=0;card_sample_valid<=0;card_frame_end<=0;card_frame_good<=0;card_frame_present<=1;roi_fg_count<=0;
            block_valid<=0;block_sof<=0;block_eol<=0;block_frame_end<=0;block_frame_good<=0;block_frame_present<=1;block_roi_fg_count<=0;
        end else begin
            fault_pulse<=0;card_frame_start<=0;card_sample_valid<=0;card_frame_end<=0;
            block_valid<=0;block_sof<=0;block_eol<=0;block_frame_end<=0;
            if(in_revoke && active) bad<=1;
            if(start_collision) begin
                // Do not silently relabel a partial old frame with a new tag.
                if(!bad && !orphan_reported) fault_pulse<=1;
                orphan_reported<=1;active<=0;bad<=1;
                if(active) begin
                    card_frame_end<=1;card_frame_good<=0;card_frame_present<=1;roi_fg_count<=foreground_seen;
                    block_frame_end<=1;block_frame_good<=0;block_frame_present<=1;block_roi_fg_count<=block_foreground_seen;
                end
            end else if(in_frame_done) begin
                card_frame_end<=1;card_frame_good<=complete_good;
                card_frame_present<=complete_good ? foreground_seen!=0 : 1'b1;
                roi_fg_count<=foreground_seen;
                block_frame_end<=1;block_frame_good<=complete_good;
                block_frame_present<=complete_good ? block_foreground_seen!=0 : 1'b1;
                block_roi_fg_count<=block_foreground_seen;
                if(!complete_good && !bad && !orphan_reported) fault_pulse<=1;
                if(!active) begin
                    card_frame_id<=in_done_id;card_source_test<=in_done_source_test;
                    block_frame_id<=in_done_id;block_source_test<=in_done_source_test;
                end
                active<=0;bad<=!complete_good;orphan_reported<=!complete_good;
            end else begin
                if(start_accept) begin
                    active<=1;bad<=0;orphan_reported<=0;active_id<=in_frame_id;active_source<=in_source_test;
                    groups_seen<=0;group_x<=0;raster_y<=0;lines_seen<=0;samples_seen<=0;foreground_seen<=0;block_foreground_seen<=0;
                    next_sample_x<=ROI_X+CELL/2;next_sample_y<=ROI_Y+CELL/2;
                    card_frame_start<=1;card_frame_id<=in_frame_id;card_source_test<=in_source_test;
                    card_frame_good<=0;card_frame_present<=1;roi_fg_count<=0;
                    block_frame_id<=in_frame_id;block_source_test<=in_source_test;block_frame_good<=0;block_frame_present<=1;block_roi_fg_count<=0;
                end
                if(in_valid && stream_active) begin
                    if(pixel_fault || in_revoke) begin
                        if((!bad || start_accept) && !in_revoke) fault_pulse<=1;
                        bad<=1;
                    end
                    if(current_groups<TOTAL_GROUPS+1) groups_seen<=current_groups+1'b1;
                    if(current_group==GROUPS_PER_LINE-1) begin
                        group_x<=0;
                        if(current_y<FRAME_HEIGHT-1) raster_y<=current_y+1'b1;
                        if(lines_seen<FRAME_HEIGHT+1) lines_seen<=lines_seen+1'b1;
                    end else group_x<=current_group+1'b1;
                    if((!bad || start_accept) && !pixel_fault && !in_revoke) begin
                        foreground_seen<=(start_accept ? 20'd0 : foreground_seen)+foreground_increment;
                        block_foreground_seen<=(start_accept ? 20'd0 : block_foreground_seen)+block_foreground_increment;
                        if(sample_hit) begin
                            card_sample_valid<=1;card_sample_index<=current_samples[9:0];
                            card_sample_foreground<=is_foreground(lane_pixel(in_rgb96,sample_lane));
                            samples_seen<=current_samples+1'b1;
                            if(current_samples[4:0]==31) begin
                                next_sample_x<=ROI_X+CELL/2;next_sample_y<=current_sample_y+CELL;
                            end else next_sample_x<=current_sample_x+CELL;
                        end
                        if(current_y[1:0]==2) begin
                            block_valid<=1;block_sof<=current_group==0 && current_y==2;
                            block_eol<=current_group==GROUPS_PER_LINE-1;
                            block_x<=current_group;block_y<=current_y>>2;
                            block_rgb<=in_rgb96[47:24];
                        end
                    end
                end else if(in_eol && stream_active) begin
                    if(!bad || start_accept) fault_pulse<=1;
                    bad<=1;
                end else if((in_valid || in_eol) && !stream_active && !orphan_reported) begin
                    orphan_reported<=1;fault_pulse<=1;
                end
            end
        end
    end
endmodule
