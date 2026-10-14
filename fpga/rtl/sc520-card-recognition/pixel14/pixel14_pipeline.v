// Capture-domain RGB96 analysis and display-domain business/OSD candidate.
// in_frame_done is a qualified external capture-close pulse AFTER ISP drain.
// It is deliberately not manufactured from HDMI timing or the last pixel.
module pixel14_pipeline #(
    parameter integer FRAME_WIDTH=1280, FRAME_HEIGHT=720,
    parameter integer CARD_X=400, CARD_Y=120, CARD_SIZE=480,
    parameter integer BLOCK_X_MIN=80, BLOCK_X_MAX=239,
    parameter integer BLOCK_Y_MIN=30, BLOCK_Y_MAX=149,
    parameter integer BLOCK_MIN_AREA=16, BLOCK_MIN_WIDTH=2, BLOCK_MIN_HEIGHT=2,
    parameter integer BLOCK_RUN_LENGTH=1,
    parameter integer CONFIRM_FRAMES=3, ENABLE_OUTPUT=0,
    parameter integer USE_SCENE_ANALYSIS=0,
    parameter integer ROTATION_VARIANTS=0,
    parameter integer SCENE_X=160,SCENE_Y=120,SCENE_WIDTH=960,SCENE_HEIGHT=480,
    parameter integer SCENE_SAMPLE_STEP=8,
    parameter integer TIMEOUT_MS=100, FEEDBACK_TICKS=1500,
    parameter TEMPLATE_FILE="templates.mem"
) (
    input wire rst_n,capture_clk,display_clk,
    input wire in_frame_start,
    input wire [31:0] in_frame_id,
    input wire in_source_test,in_valid,in_eol,
    input wire [95:0] in_rgb96,
    input wire in_frame_done,in_frame_good,
    input wire [31:0] in_done_id,
    input wire in_done_source_test,in_revoke,
    input wire tick_1ms,flush,
    input wire key_mode_pulse,key_replay_pulse,key_skip_pulse,key_reset_pulse,
    input wire audio_idle,audio_fault,
    input wire video_frame_start,
    input wire [10:0] pixel_x,
    input wire [9:0] pixel_y,
    input wire video_vsync,video_hsync,video_de,
    input wire [23:0] video_rgb,
    output reg out_vsync,out_hsync,out_de,
    output wire [23:0] out_rgb,
    output wire obs_event,obs_healthy,obs_present,obs_valid,obs_revoke,obs_conflict,timed_out,
    output wire [3:0] obs_item,
    output wire [31:0] obs_frame_id,
    output wire obs_source_test,
    output wire [7:0] obs_count,
    output wire [1:0] mode,phase,
    output wire [3:0] score,question_index,target_item,display_item,
    output wire quiz_active,answer_valid,answer_correct,display_source_test,armed,
    output wire [2:0] feedback,
    output wire audio_event_valid,audio_cancel,
    output wire [2:0] audio_event_kind,
    output wire [3:0] audio_event_item,
    output wire link_fault,quarantined,
    output reg [10:0] diag_best,diag_second,diag_sample_fg
);
    reg [1:0] capture_reset,display_reset;
    always @(posedge capture_clk or negedge rst_n)
        if(!rst_n) capture_reset<=0; else capture_reset<={capture_reset[0],1'b1};
    always @(posedge display_clk or negedge rst_n)
        if(!rst_n) display_reset<=0; else display_reset<={display_reset[0],1'b1};
    wire crst=capture_reset[1],drst=display_reset[1];

    wire cap_start,cap_sample,cap_fg,cap_end,cap_good,cap_present,cap_source,cap_revoke;
    wire [9:0] cap_index;
    wire [31:0] cap_id;
    wire [19:0] roi_fg_count;
    wire bp_valid,bp_sof,bp_eol,bp_end,bp_good,bp_present,bp_source;
    wire [10:0] bp_x;
    wire [9:0] bp_y;
    wire [23:0] bp_rgb;
    wire [31:0] bp_id;
    wire block_event,block_healthy,block_present,block_valid,block_source,block_revoke;
    wire [3:0] block_item;
    wire [31:0] block_id;
    wire [7:0] block_count;
    wire card_event,card_healthy,card_present,card_valid,card_source;
    wire [3:0] card_item;
    wire [31:0] card_id;
    wire [7:0] card_count;
    wire match_event,match_good,match_present,match_valid,match_source;
    wire [3:0] match_item;
    wire [31:0] match_id;
    wire [10:0] best_distance,second_distance,sample_fg;
    localparam integer SCENE_COLUMNS=SCENE_WIDTH/SCENE_SAMPLE_STEP;
    localparam integer SCENE_ROWS=SCENE_HEIGHT/SCENE_SAMPLE_STEP;
    wire scene_revoke;
    wire sp_valid,sp_sof,sp_eol,sp_end,sp_good,sp_present,sp_source;
    wire [10:0] sp_x;
    wire [9:0] sp_y;
    wire [23:0] sp_rgb;
    wire [31:0] sp_id;
    wire sc_start,sc_valid,sc_fg,sc_end,sc_good,sc_present,sc_source;
    wire [9:0] sc_index;
    wire [31:0] sc_id;
    wire shape_event,shape_healthy,shape_source;
    wire [2:0] shape_ok;
    wire [31:0] shape_id;
    reg [2:0] saved_shape_ok;
    reg saved_shape_healthy,saved_shape_source;
    reg [31:0] saved_shape_id;
    wire confirmed_block_event,confirmed_block_healthy,confirmed_block_present,confirmed_block_valid,confirmed_block_source;
    wire [3:0] confirmed_block_item;
    wire [31:0] confirmed_block_id;
    wire [7:0] confirmed_block_count;

    wire reverse_event,reverse_fault,reverse_ready,reverse_src_fault;
    wire forward_ready,forward_fault,packet_event,forward_dst_fault;
    wire [0:0] reverse_data;
    wire [131:0] packet;
    reg staging_fault;
    reg staging_fault_meta,staging_fault_sync;
    reg flush_meta,flush_sync;
    always @(posedge capture_clk or negedge rst_n)
        if(!rst_n) begin flush_meta<=0;flush_sync<=0;end
        else begin flush_meta<=flush;flush_sync<=flush_meta;end
    always @(posedge display_clk or negedge rst_n)
        if(!rst_n) begin staging_fault_meta<=0;staging_fault_sync<=0;end
        else begin staging_fault_meta<=staging_fault;staging_fault_sync<=staging_fault_meta;end
    wire source_fault=forward_fault || reverse_fault || staging_fault;
    reg done_previous;
    always @(posedge capture_clk or negedge rst_n)
        if(!rst_n) done_previous<=0; else done_previous<=in_frame_done;
    // The matcher drains on a quiet clock after EOF. Reject an immediate next
    // SOF instead of silently dropping the old result and poisoning the new one.
    wire boundary_revoke=in_frame_start && done_previous;
    wire source_revoke=cap_revoke || block_revoke || scene_revoke || in_revoke || boundary_revoke;
    reg revoke_seen,drop_capture;
    wire new_revoke=source_revoke && !revoke_seen;
    wire wait_start=drop_capture && !(in_frame_start && !in_revoke);
    wire transport_flush=reverse_event || source_fault || flush_sync;
    wire local_flush=transport_flush || wait_start;
    wire detector_flush=local_flush || source_revoke;
    always @(posedge capture_clk or negedge rst_n) begin
        if(!rst_n) begin revoke_seen<=0;drop_capture<=1;end
        else if(!crst) begin revoke_seen<=0;drop_capture<=1;end
        else begin
            revoke_seen<=source_revoke;
            if(source_fault || reverse_event || source_revoke || flush_sync) drop_capture<=1;
            else if(in_frame_start) drop_capture<=0;
        end
    end
    capture_rgb96 #(.FRAME_WIDTH(FRAME_WIDTH),.FRAME_HEIGHT(FRAME_HEIGHT),
        .ROI_X(CARD_X),.ROI_Y(CARD_Y),.ROI_SIZE(CARD_SIZE),
        .BLOCK_ROI_X(BLOCK_X_MIN*4),.BLOCK_ROI_Y(BLOCK_Y_MIN*4),
        .BLOCK_ROI_WIDTH((BLOCK_X_MAX-BLOCK_X_MIN+1)*4),
        .BLOCK_ROI_HEIGHT((BLOCK_Y_MAX-BLOCK_Y_MIN+1)*4)) capture (
        .clk(capture_clk),.rst_n(crst),.flush(local_flush),
        .in_frame_start(in_frame_start),.in_frame_id(in_frame_id),.in_source_test(in_source_test),
        .in_valid(in_valid),.in_eol(in_eol),.in_rgb96(in_rgb96),
        .in_frame_done(in_frame_done),.in_frame_good(in_frame_good),
        .in_done_id(in_done_id),.in_done_source_test(in_done_source_test),.in_revoke(in_revoke),
        .card_frame_start(cap_start),.card_sample_valid(cap_sample),.card_sample_index(cap_index),
        .card_sample_foreground(cap_fg),.card_frame_end(cap_end),.card_frame_good(cap_good),
        .card_frame_present(cap_present),.card_frame_id(cap_id),.card_source_test(cap_source),
        .roi_fg_count(roi_fg_count),.block_valid(bp_valid),.block_sof(bp_sof),.block_eol(bp_eol),
        .block_x(bp_x),.block_y(bp_y),.block_rgb(bp_rgb),.block_frame_end(bp_end),
        .block_frame_good(bp_good),.block_frame_present(bp_present),
        .block_frame_id(bp_id),.block_source_test(bp_source),.revoke(cap_revoke));
    generate if(USE_SCENE_ANALYSIS) begin : scene_mode
        pixel14_scene_preprocess #(.FRAME_WIDTH(FRAME_WIDTH/4),.FRAME_HEIGHT(FRAME_HEIGHT/4),
            .ROI_X(SCENE_X/4),.ROI_Y(SCENE_Y/4),.GRID_WIDTH(SCENE_COLUMNS),.GRID_HEIGHT(SCENE_ROWS),
            .SAMPLE_STEP(SCENE_SAMPLE_STEP/4)) scene (
            .clk(capture_clk),.rst_n(crst),.flush(detector_flush),
            .in_valid(bp_valid),.in_sof(bp_sof),.in_eol(bp_eol),.in_x(bp_x),.in_y(bp_y),.in_rgb(bp_rgb),
            .in_frame_end(bp_end),.in_frame_good(bp_good),.in_frame_id(bp_id),.in_source_test(bp_source),
            .replay_valid(sp_valid),.replay_sof(sp_sof),.replay_eol(sp_eol),.replay_x(sp_x),.replay_y(sp_y),
            .replay_rgb(sp_rgb),.replay_end(sp_end),.replay_good(sp_good),.replay_present(sp_present),
            .replay_id(sp_id),.replay_source(sp_source),
            .card_start(sc_start),.card_valid(sc_valid),.card_index(sc_index),.card_fg(sc_fg),
            .card_end(sc_end),.card_good(sc_good),.card_present(sc_present),.card_id(sc_id),.card_source(sc_source),
            .out_revoke(scene_revoke),.dbg_scene_count(),.dbg_glyph_count());
    end else begin : legacy_mode
        assign scene_revoke=1'b0;
        assign {sp_valid,sp_sof,sp_eol,sp_end,sp_good,sp_present,sp_source}=
               {bp_valid,bp_sof,bp_eol,bp_end,bp_good,bp_present,bp_source};
        assign sp_x=bp_x;assign sp_y=bp_y;assign sp_rgb=bp_rgb;assign sp_id=bp_id;
        assign {sc_start,sc_valid,sc_fg,sc_end,sc_good,sc_present,sc_source}=
               {cap_start,cap_sample,cap_fg,cap_end,cap_good,cap_present,cap_source};
        assign sc_index=cap_index;assign sc_id=cap_id;
    end endgenerate
    block_frame_recognizer #(.FRAME_WIDTH(USE_SCENE_ANALYSIS ? SCENE_COLUMNS : FRAME_WIDTH/4),
        .FRAME_HEIGHT(USE_SCENE_ANALYSIS ? SCENE_ROWS : FRAME_HEIGHT/4),
        .X_MIN(USE_SCENE_ANALYSIS ? 0 : BLOCK_X_MIN),.X_MAX(USE_SCENE_ANALYSIS ? SCENE_COLUMNS-1 : BLOCK_X_MAX),
        .Y_MIN(USE_SCENE_ANALYSIS ? 0 : BLOCK_Y_MIN),.Y_MAX(USE_SCENE_ANALYSIS ? SCENE_ROWS-1 : BLOCK_Y_MAX),
        .MIN_AREA(BLOCK_MIN_AREA),.MIN_WIDTH(BLOCK_MIN_WIDTH),.MIN_HEIGHT(BLOCK_MIN_HEIGHT),
        .RUN_LENGTH(BLOCK_RUN_LENGTH),.CONFIRM_FRAMES(USE_SCENE_ANALYSIS ? 1 : CONFIRM_FRAMES)) blocks (
        .clk(capture_clk),.rst_n(crst),.flush(detector_flush),
        .in_valid(sp_valid),.in_sof(sp_sof),.in_eol(sp_eol),.in_x(sp_x),.in_y(sp_y),.in_rgb(sp_rgb),
        .in_frame_end(sp_end),.in_frame_good(sp_good),.in_frame_present(sp_present),
        .in_frame_id(sp_id),.in_source_test(sp_source),
        .out_frame(block_event),.out_healthy(block_healthy),.out_present(block_present),.out_valid(block_valid),
        .out_item(block_item),.out_frame_id(block_id),.out_source_test(block_source),
        .stable_count(block_count),.out_revoke(block_revoke));
    generate if(USE_SCENE_ANALYSIS) begin : shape_mode
        pixel14_block_shape_guard shape_guard (
            .clk(capture_clk),.rst_n(crst),.flush(detector_flush),.frame_start(sc_start),
            .sample_valid(sc_valid),.sample_index(sc_index),.sample_foreground(sc_fg),
            .frame_end(sc_end),.frame_good(sc_good),.frame_present(sc_present),
            .frame_id(sc_id),.frame_source_test(sc_source),.out_frame(shape_event),
            .out_healthy(shape_healthy),.shape_ok(shape_ok),.out_frame_id(shape_id),.out_source_test(shape_source),
            .distance_circle(),.distance_square(),.distance_triangle());
    end else begin : no_shape_mode
        assign shape_event=0;assign shape_healthy=1;assign shape_ok=3'b111;
        assign shape_id=0;assign shape_source=0;
    end endgenerate
    generate if(USE_SCENE_ANALYSIS) begin : guarded_block_confirmation
        reg raw_pending;
        reg [48:0] raw_record;
        wire identity=raw_pending && shape_id==raw_record[40:9] && shape_source==raw_record[8];
        wire healthy=identity && raw_record[47] && shape_healthy;
        wire shape_matches=(raw_record[44:41]==1 || raw_record[44:41]==4 || raw_record[44:41]==7) ? shape_ok[0] :
                           (raw_record[44:41]==2 || raw_record[44:41]==5 || raw_record[44:41]==8) ? shape_ok[1] :
                           (raw_record[44:41]==3 || raw_record[44:41]==6 || raw_record[44:41]==9) ? shape_ok[2] : 1'b0;
        wire valid=healthy && raw_record[45] && shape_matches;
        always @(posedge capture_clk or negedge rst_n)begin
            if(!rst_n)begin raw_pending<=0;raw_record<=0;end
            else if(!crst || detector_flush)begin raw_pending<=0;raw_record<=0;end
            else begin
                if(shape_event)raw_pending<=0;
                if(block_event)begin
                    raw_pending<=1;
                    raw_record<={1'b1,block_healthy,block_present,block_valid,block_item,block_id,block_source,block_count};
                end
            end
        end
        // Confirmation runs AFTER shape qualification. A rejected glyph cannot
        // contribute earlier frames toward a later genuine block's stability.
        pixel14_block_filter #(.CONFIRM_FRAMES(CONFIRM_FRAMES)) block_confirmation (
            .clk(capture_clk),.rst_n(crst),.flush(detector_flush),.in_frame(shape_event),
            .in_healthy(healthy),.in_present(raw_record[46]),.in_valid(valid),
            .in_item(valid ? raw_record[44:41] : 4'd0),.in_frame_id(shape_id),.in_source_test(shape_source),
            .out_frame(confirmed_block_event),.out_healthy(confirmed_block_healthy),.out_present(confirmed_block_present),
            .out_valid(confirmed_block_valid),.out_item(confirmed_block_item),.out_frame_id(confirmed_block_id),
            .out_source_test(confirmed_block_source),.stable_count(confirmed_block_count));
    end else begin : legacy_block_confirmation
        assign confirmed_block_event=block_event;assign confirmed_block_healthy=block_healthy;
        assign confirmed_block_present=block_present;assign confirmed_block_valid=block_valid;
        assign confirmed_block_item=block_item;assign confirmed_block_id=block_id;
        assign confirmed_block_source=block_source;assign confirmed_block_count=block_count;
    end endgenerate
    generate if(ROTATION_VARIANTS>0) begin : rotation_mode
        pixel14_rotation_matcher #(.TEMPLATE_FILE(TEMPLATE_FILE),.ENABLE_OUTPUT(ENABLE_OUTPUT),
            .VARIANTS(ROTATION_VARIANTS)) matcher (
            .clk(capture_clk),.rst_n(crst),.flush(detector_flush),.frame_start(sc_start),
            .sample_valid(sc_valid),.sample_index(sc_index),.sample_foreground(sc_fg),
            .frame_end(sc_end),.frame_good(sc_good),.frame_present(sc_present),
            .frame_id(sc_id),.frame_source_test(sc_source),.out_frame(match_event),.out_healthy(match_good),
            .out_present(match_present),.out_valid(match_valid),.out_item(match_item),
            .out_best(best_distance),.out_second(second_distance),.out_fg_count(sample_fg),
            .out_frame_id(match_id),.out_source_test(match_source));
    end else begin : fixed_orientation_mode
    pixel14_card_matcher #(.TEMPLATE_FILE(TEMPLATE_FILE),.ENABLE_OUTPUT(ENABLE_OUTPUT),
        .TEMPLATES_PER_CLASS(USE_SCENE_ANALYSIS ? 3 : 1)) matcher (
        .clk(capture_clk),.rst_n(crst),.flush(detector_flush),.frame_start(sc_start),
        .sample_valid(sc_valid),.sample_index(sc_index),.sample_foreground(sc_fg),
        .frame_end(sc_end),.frame_good(sc_good),.frame_present(sc_present),
        .frame_id(sc_id),.frame_source_test(sc_source),.out_frame(match_event),.out_healthy(match_good),
        .out_present(match_present),.out_valid(match_valid),.out_item(match_item),
        .out_best(best_distance),.out_second(second_distance),.out_fg_count(sample_fg),
        .out_frame_id(match_id),.out_source_test(match_source));
    end endgenerate
    wire shape_match_identity=saved_shape_healthy && saved_shape_id==match_id && saved_shape_source==match_source;
    wire qualified_match_good=match_good && (!USE_SCENE_ANALYSIS || shape_match_identity);
    wire qualified_match_valid=match_valid && (!USE_SCENE_ANALYSIS || (shape_match_identity && saved_shape_ok==0));
    card_result_filter #(.CONFIRM_FRAMES(CONFIRM_FRAMES)) confirmation (
        .clk(capture_clk),.rst_n(crst),.flush(detector_flush),.in_frame(match_event),
        .in_healthy(qualified_match_good),.in_present(match_present),.in_valid(qualified_match_valid),
        .in_item(qualified_match_valid ? match_item : 4'd0),
        .in_frame_id(match_id),.in_source_test(match_source),.out_frame(card_event),
        .out_healthy(card_healthy),.out_present(card_present),.out_valid(card_valid),.out_item(card_item),
        .out_frame_id(card_id),.out_source_test(card_source),.stable_count(card_count));
    // The two classifiers finish a few capture clocks apart. Stage each once
    // and send one atomic pair; separate mailbox writes would falsely overrun.
    // One waiting pair is allowed while the mailbox is busy. A second result
    // for either occupied slot is a real overflow and withdraws trust.
    reg block_pending,card_pending,revoke_pending,shape_pending;
    reg [48:0] block_record,card_record;
    reg [32:0] card_diagnostics;
    wire send_revoke=revoke_pending || new_revoke;
    wire send_pair=block_pending && card_pending && (!USE_SCENE_ANALYSIS || shape_pending) && !source_revoke;
    wire shape_identity=saved_shape_id==block_record[40:9] && saved_shape_source==block_record[8];
    wire selected_shape_ok=(block_record[44:41]==1 || block_record[44:41]==4 || block_record[44:41]==7) ? saved_shape_ok[0] :
                           (block_record[44:41]==2 || block_record[44:41]==5 || block_record[44:41]==8) ? saved_shape_ok[1] :
                           (block_record[44:41]==3 || block_record[44:41]==6 || block_record[44:41]==9) ? saved_shape_ok[2] : 1'b0;
    wire qualified_block=!USE_SCENE_ANALYSIS || (shape_identity && saved_shape_healthy && selected_shape_ok);
    wire qualified_health=!USE_SCENE_ANALYSIS || (shape_identity && saved_shape_healthy);
    wire [48:0] qualified_block_record={block_record[48],block_record[47] && qualified_health,block_record[46],
        block_record[45] && qualified_block,qualified_block ? block_record[44:41] : 4'd0,
        block_record[40:8],qualified_block ? block_record[7:0] : 8'd0};
    wire send_event=!transport_flush && forward_ready && (send_revoke || (!wait_start && send_pair));
    wire [131:0] send_data=send_revoke ? {33'd0,1'b1,98'd0} :
        {card_diagnostics,1'b0,qualified_block_record,card_record};
    always @(posedge capture_clk or negedge rst_n) begin
        if(!rst_n) begin
            block_pending<=0;card_pending<=0;revoke_pending<=0;staging_fault<=0;
            shape_pending<=0;saved_shape_ok<=0;saved_shape_healthy<=0;saved_shape_id<=0;saved_shape_source<=0;
            block_record<=0;card_record<=0;card_diagnostics<=0;
        end else if(!crst) begin
            block_pending<=0;card_pending<=0;revoke_pending<=0;staging_fault<=0;
            shape_pending<=0;saved_shape_ok<=0;saved_shape_healthy<=0;saved_shape_id<=0;saved_shape_source<=0;
            block_record<=0;card_record<=0;card_diagnostics<=0;
        end else begin
            if(transport_flush) revoke_pending<=0;
            else if(new_revoke) revoke_pending<=!send_event;
            else if(send_event && send_revoke) revoke_pending<=0;
            if(local_flush || source_revoke) begin
                block_pending<=0;card_pending<=0;shape_pending<=0;
            end else begin
            if(send_event) begin
                if(!send_revoke) begin block_pending<=0;card_pending<=0;shape_pending<=0;end
            end
            if(shape_event)begin
                if(shape_pending && !(send_event && !send_revoke))staging_fault<=1;
                else begin
                    shape_pending<=1;saved_shape_ok<=shape_ok;saved_shape_healthy<=shape_healthy;
                    saved_shape_id<=shape_id;saved_shape_source<=shape_source;
                end
            end
            if(confirmed_block_event) begin
                if(block_pending && !(send_event && !send_revoke)) staging_fault<=1;
                else begin
                    block_pending<=1;
                    block_record<={1'b1,confirmed_block_healthy,confirmed_block_present,confirmed_block_valid && ENABLE_OUTPUT!=0,
                        confirmed_block_item,confirmed_block_id,confirmed_block_source,confirmed_block_count};
                end
            end
            if(card_event) begin
                if(card_pending && !(send_event && !send_revoke)) staging_fault<=1;
                else begin
                    card_pending<=1;
                    card_record<={1'b1,card_healthy,card_present,card_valid,
                        card_item,card_id,card_source,card_count};
                    card_diagnostics<={best_distance,second_distance,sample_fg};
                end
            end
            end
        end
    end
    pixel14_result_cdc #(.WIDTH(132)) forward (
        .rst_n(rst_n),.src_clk(capture_clk),.src_valid(send_event),.src_data(send_data),
        .src_ready(forward_ready),.src_fault(forward_fault),.dst_clk(display_clk),
        .dst_valid(packet_event),.dst_data(packet),.dst_fault(forward_dst_fault));

    wire system_flush;
    reg flush_seen,external_flush_seen,reverse_pending;
    reg [2:0] quiet_count;
    wire clear_level=flush || system_flush;
    // An external pulse is an independent epoch request, even while an earlier
    // internal clear keeps clear_level high. Queue it if the mailbox is busy.
    wire clear_request=(clear_level && !flush_seen) || (flush && !external_flush_seen);
    wire clear_dispatch=reverse_ready && (clear_request || reverse_pending);
    assign link_fault=forward_dst_fault || reverse_src_fault || staging_fault_sync;
    assign quarantined=flush || !reverse_ready || quiet_count!=0 || clear_request || reverse_pending || link_fault;
    always @(posedge display_clk or negedge rst_n) begin
        if(!rst_n) begin flush_seen<=0;external_flush_seen<=0;reverse_pending<=0;quiet_count<=4;end
        else if(!drst) begin flush_seen<=0;external_flush_seen<=0;reverse_pending<=0;quiet_count<=4;end
        else begin
            flush_seen<=clear_level;
            external_flush_seen<=flush;
            if(clear_dispatch) reverse_pending<=0;
            else if(clear_request) reverse_pending<=1;
            if(clear_request || !reverse_ready || reverse_pending) quiet_count<=4;
            else if(quiet_count!=0) quiet_count<=quiet_count-1'b1;
        end
    end
    pixel14_result_cdc #(.WIDTH(1)) backward (
        .rst_n(rst_n),.src_clk(display_clk),.src_valid(clear_dispatch),.src_data(1'b1),
        .src_ready(reverse_ready),.src_fault(reverse_src_fault),.dst_clk(capture_clk),
        .dst_valid(reverse_event),.dst_data(reverse_data),.dst_fault(reverse_fault));
    // A packet may itself request a clear. Do not feed that combinational
    // decision back into its own acceptance; quarantine takes effect on edge.
    wire accepted=packet_event && !flush && reverse_ready && quiet_count==0 && !link_fault;
    wire packet_revoke=(accepted && packet[98]) || link_fault || quiet_count!=0 || !reverse_ready;
    wire b_event=accepted && packet[97] && !packet[98];
    wire c_event=accepted && packet[48] && !packet[98];
    wire osd_active;
    wire [23:0] osd_rgb;
    items14_system #(.TIMEOUT_MS(TIMEOUT_MS),.FEEDBACK_TICKS(FEEDBACK_TICKS),.SCENE_UI(USE_SCENE_ANALYSIS)) system (
        .clk(display_clk),.rst_n(drst),.tick_1ms(tick_1ms),.flush(flush),
        .block_revoke(packet_revoke),.card_revoke(1'b0),
        .block_event(b_event),.block_healthy(packet[96]),.block_present(packet[95]),.block_valid(packet[94]),
        .block_item(packet[93:90]),.block_frame_id(packet[89:58]),.block_source_test(packet[57]),.block_count(packet[56:49]),
        .card_event(c_event),.card_healthy(packet[47]),.card_present(packet[46]),.card_valid(packet[45]),
        .card_item(packet[44:41]),.card_frame_id(packet[40:9]),.card_source_test(packet[8]),.card_count(packet[7:0]),
        .key_mode_pulse(key_mode_pulse),.key_replay_pulse(key_replay_pulse),.key_skip_pulse(key_skip_pulse),
        .key_reset_pulse(key_reset_pulse),.audio_idle(audio_idle),.audio_fault(audio_fault),
        .video_frame_start(video_frame_start),.pixel_x(pixel_x),.pixel_y(pixel_y),
        .detectors_flush(system_flush),.obs_event(obs_event),.obs_healthy(obs_healthy),.obs_present(obs_present),
        .obs_valid(obs_valid),.obs_revoke(obs_revoke),.obs_conflict(obs_conflict),.timed_out(timed_out),
        .obs_item(obs_item),.obs_frame_id(obs_frame_id),.obs_source_test(obs_source_test),.obs_count(obs_count),
        .mode(mode),.phase(phase),.score(score),.question_index(question_index),.target_item(target_item),
        .display_item(display_item),.quiz_active(quiz_active),.answer_valid(answer_valid),.answer_correct(answer_correct),
        .display_source_test(display_source_test),.armed(armed),.feedback(feedback),
        .audio_event_valid(audio_event_valid),.audio_event_kind(audio_event_kind),.audio_event_item(audio_event_item),
        .audio_cancel(audio_cancel),.osd_active(osd_active),.osd_rgb(osd_rgb));
    reg [23:0] rgb_delay;
    reg roi_border;
    always @(posedge display_clk or negedge rst_n) begin
        if(!rst_n) begin
            rgb_delay<=0;out_vsync<=0;out_hsync<=0;out_de<=0;roi_border<=0;
            diag_best<=0;diag_second<=0;diag_sample_fg<=0;
        end else if(!drst) begin
            rgb_delay<=0;out_vsync<=0;out_hsync<=0;out_de<=0;roi_border<=0;
            diag_best<=0;diag_second<=0;diag_sample_fg<=0;
        end else begin
            rgb_delay<=video_rgb;out_vsync<=video_vsync;out_hsync<=video_hsync;out_de<=video_de;
            if(USE_SCENE_ANALYSIS)
                roi_border<=pixel_x>=SCENE_X && pixel_x<SCENE_X+SCENE_WIDTH &&
                    pixel_y>=SCENE_Y && pixel_y<SCENE_Y+SCENE_HEIGHT &&
                    (pixel_x==SCENE_X || pixel_x==SCENE_X+SCENE_WIDTH-1 ||
                     pixel_y==SCENE_Y || pixel_y==SCENE_Y+SCENE_HEIGHT-1);
            else roi_border<=pixel_x>=CARD_X && pixel_x<CARD_X+CARD_SIZE &&
                    pixel_y>=CARD_Y && pixel_y<CARD_Y+CARD_SIZE &&
                    (pixel_x==CARD_X || pixel_x==CARD_X+CARD_SIZE-1 ||
                     pixel_y==CARD_Y || pixel_y==CARD_Y+CARD_SIZE-1);
            if(packet_revoke || flush) begin diag_best<=0;diag_second<=0;diag_sample_fg<=0;end
            else if(c_event) begin
                diag_best<=packet[131:121];diag_second<=packet[120:110];diag_sample_fg<=packet[109:99];
            end
        end
    end
    assign out_rgb=!out_de ? 24'd0 : osd_active ? osd_rgb : roi_border ? 24'hff0000 : rgb_delay;
endmodule
