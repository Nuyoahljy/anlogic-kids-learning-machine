`include "recognition30_packet.vh"
// I0309: confirmed card geometry and the public R30 record share one atomic CDC.
module pixel309_pipeline #(
    parameter integer FRAME_WIDTH=1280,FRAME_HEIGHT=720,
    parameter integer CARD_X=400,CARD_Y=120,CARD_SIZE=480,
    parameter integer SCENE_X=160,SCENE_Y=120,SCENE_WIDTH=960,SCENE_HEIGHT=480,
    parameter integer SCENE_SAMPLE_STEP=8,CONFIRM_FRAMES=3,ROTATION_VARIANTS=256,
    parameter integer WAIT_CYCLES=1200000,TIMEOUT_MS=100,FEEDBACK_TICKS=1500,
    parameter integer RENDER_ENABLE=1,SHAPE_ENABLE=1,TRACK_ENABLE=0,
    parameter TEMPLATE_FILE="templates.mem",GEOMETRY_FILE="contour29-shapes.mem",
    parameter LOGO_INDEX_FILE="anlogic_logo_index.mem",LOGO_PALETTE_FILE="anlogic_logo_palette.mem"
) (
    input wire rst_n,capture_clk,display_clk,
    input wire in_frame_start,input wire [31:0] in_frame_id,
    input wire in_source_test,in_valid,in_eol,input wire [95:0] in_rgb96,
    input wire in_frame_done,in_frame_good,input wire [31:0] in_done_id,
    input wire in_done_source_test,in_revoke,
    input wire tick_1ms,flush,
    input wire [1:0] style_request,
    input wire [1:0] calibration_state,tf_state,
    input wire key_mode_pulse,key_replay_pulse,key_skip_pulse,key_reset_pulse,
    input wire audio_idle,audio_fault,
    input wire video_frame_start,video_vsync,video_hsync,video_de,
    input wire [10:0] pixel_x,input wire [9:0] pixel_y,input wire [23:0] video_rgb,
    output wire out_vsync,out_hsync,out_de,output wire [23:0] out_rgb,
    output wire obs_event,obs_healthy,obs_present,obs_valid,obs_revoke,obs_conflict,timed_out,
    output wire [3:0] obs_item,output wire [31:0] obs_frame_id,
    output wire obs_source_test,output wire [7:0] obs_count,
    output wire [1:0] mode,phase,
    output wire [3:0] score,question_index,target_item,display_item,
    output wire quiz_active,answer_valid,answer_correct,display_source_test,armed,
    output wire [2:0] feedback,output wire audio_event_valid,audio_cancel,
    output wire [2:0] audio_event_kind,output wire [3:0] audio_event_item,
    output wire link_fault,quarantined,
    output wire calibration_flush,
    output wire [27:0] render_state,
    output wire [191:0] recognition_packet,
    output wire recognition_event,recognition_fresh,recognition_fault,
    output wire [7:0] recognition_age
);
    (* preserve *) reg [1:0] capture_reset;
    reg [1:0] display_reset;
    (* preserve *) reg [5:0] capture_release;
    always @(posedge capture_clk or negedge rst_n)
        if(!rst_n)capture_reset<=0;else capture_reset<={capture_reset[0],1'b1};
    always @(posedge capture_clk or negedge rst_n)
        if(!rst_n)capture_release<=0;else capture_release<={6{capture_reset[0]}};
    always @(posedge display_clk or negedge rst_n)
        if(!rst_n)display_reset<=0;else display_reset<={display_reset[0],1'b1};
    wire crst=capture_reset[1],drst=display_reset[1];
    reg flush_meta,flush_sync,staging_fault,staging_meta,staging_sync;
    always @(posedge capture_clk or negedge rst_n)
        if(!rst_n)begin flush_meta<=0;flush_sync<=0;end
        else begin flush_meta<=flush;flush_sync<=flush_meta;end
    always @(posedge display_clk or negedge rst_n)
        if(!rst_n)begin staging_meta<=0;staging_sync<=0;end
        else begin staging_meta<=staging_fault;staging_sync<=staging_meta;end
    wire reverse_event,reverse_fault,reverse_ready,reverse_src_fault;
    wire forward_ready,forward_fault,packet_event,forward_dst_fault;
    wire [0:0] reverse_data;
    wire [239:0] forward_packet;
    wire [191:0] packet=forward_packet[191:0];
    wire [47:0] track_packet=forward_packet[239:192];
    wire bp_valid,bp_sof,bp_eol,bp_end,bp_good,bp_present,bp_source,cap_revoke;
    wire [10:0] bp_x;
    wire [9:0] bp_y;
    wire [23:0] bp_rgb;
    wire [31:0] bp_id;
    wire scene_revoke,sc_start,sc_valid,sc_fg,sc_end,sc_good,sc_present,sc_source;
    wire axis_start,axis_valid,axis_end,y_available,scene_axis_eligible,scene_y_allowed;
    wire [9:0] sc_index,axis_index;
    wire axis_fg;
    wire [31:0] sc_id;
    wire [15:0] scene_pixels,glyph_pixels,paper_pixels;
    wire [3:0] scene_flags;
    wire [7:0] ymin,ymax;
    wire [11:0] bbox_width,bbox_height;
    wire [10:0] bbox_left,bbox_right;
    wire [9:0] bbox_top,bbox_bottom;
    wire shape_event,shape_healthy,shape_present,shape_source;
    wire [31:0] shape_id;
    wire [10:0] circle,square,triangle,ellipse,axis_circle;
    wire match_event,match_good,match_present,match_valid,match_source;
    wire [3:0] match_item;
    wire [31:0] match_id;
    wire [10:0] match_best,match_second,match_foreground;
    reg matcher_busy,done_previous,revoke_seen,drop_capture;
    wire boundary_revoke=in_frame_start&&done_previous;
    wire matcher_collision=sc_start&&matcher_busy;
    wire source_revoke=cap_revoke||scene_revoke||in_revoke||boundary_revoke||matcher_collision;
    wire source_fault=forward_fault||reverse_fault||staging_fault;
    wire new_revoke=source_revoke&&!revoke_seen;
    wire wait_start=drop_capture&&!(in_frame_start&&!in_revoke);
    wire transport_flush=reverse_event||source_fault||flush_sync;
    wire local_flush=transport_flush||wait_start;
    wire detector_flush=local_flush||source_revoke;
    assign calibration_flush=detector_flush;
    always @(posedge capture_clk or negedge rst_n) begin
        if(!rst_n)begin matcher_busy<=0;done_previous<=0;revoke_seen<=0;drop_capture<=1;end
        else if(!crst)begin matcher_busy<=0;done_previous<=0;revoke_seen<=0;drop_capture<=1;end
        else begin
            done_previous<=in_frame_done;revoke_seen<=source_revoke;
            if(detector_flush)matcher_busy<=0;
            else begin
                if(match_event)matcher_busy<=0;
                if(sc_start)matcher_busy<=1;
            end
            if(source_fault||reverse_event||source_revoke||flush_sync)drop_capture<=1;
            else if(in_frame_start)drop_capture<=0;
        end
    end
    capture_rgb96 #(.FRAME_WIDTH(FRAME_WIDTH),.FRAME_HEIGHT(FRAME_HEIGHT),
        .ROI_X(CARD_X),.ROI_Y(CARD_Y),.ROI_SIZE(CARD_SIZE),
        .BLOCK_ROI_X(SCENE_X),.BLOCK_ROI_Y(SCENE_Y),
        .BLOCK_ROI_WIDTH(SCENE_WIDTH),.BLOCK_ROI_HEIGHT(SCENE_HEIGHT)) capture (
        .clk(capture_clk),.rst_n(capture_release[0]),.flush(local_flush),
        .in_frame_start(in_frame_start),.in_frame_id(in_frame_id),.in_source_test(in_source_test),
        .in_valid(in_valid),.in_eol(in_eol),.in_rgb96(in_rgb96),.in_frame_done(in_frame_done),
        .in_frame_good(in_frame_good),.in_done_id(in_done_id),
        .in_done_source_test(in_done_source_test),.in_revoke(in_revoke),
        .card_frame_start(),.card_sample_valid(),.card_sample_index(),.card_sample_foreground(),
        .card_frame_end(),.card_frame_good(),.card_frame_present(),.card_frame_id(),.card_source_test(),
        .roi_fg_count(),.block_valid(bp_valid),.block_sof(bp_sof),.block_eol(bp_eol),
        .block_x(bp_x),.block_y(bp_y),.block_rgb(bp_rgb),.block_frame_end(bp_end),
        .block_frame_good(bp_good),.block_frame_present(bp_present),.block_roi_fg_count(),
        .block_frame_id(bp_id),.block_source_test(bp_source),.revoke(cap_revoke));
    pixel307_scene_preprocess #(.FRAME_WIDTH(FRAME_WIDTH/4),.FRAME_HEIGHT(FRAME_HEIGHT/4),
        .ROI_X(SCENE_X/4),.ROI_Y(SCENE_Y/4),.GRID_WIDTH(SCENE_WIDTH/SCENE_SAMPLE_STEP),
        .GRID_HEIGHT(SCENE_HEIGHT/SCENE_SAMPLE_STEP),.SAMPLE_STEP(SCENE_SAMPLE_STEP/4),
        .SHAPE_ENABLE(SHAPE_ENABLE)) scene (
        .clk(capture_clk),.rst_n(capture_release[1]),.flush(detector_flush),
        .in_valid(bp_valid),.in_sof(bp_sof),.in_eol(bp_eol),.in_x(bp_x),.in_y(bp_y),
        .in_rgb(bp_rgb),.in_frame_end(bp_end),.in_frame_good(bp_good),.in_frame_id(bp_id),
        .in_source_test(bp_source),.replay_valid(),.replay_sof(),.replay_eol(),.replay_x(),
        .replay_y(),.replay_rgb(),.replay_end(),.replay_good(),.replay_present(),.replay_id(),.replay_source(),
        .card_start(sc_start),.card_valid(sc_valid),.card_index(sc_index),.card_fg(sc_fg),
        .card_end(sc_end),.card_good(sc_good),.card_present(sc_present),.card_id(sc_id),.card_source(sc_source),
        .axis_start(axis_start),.axis_valid(axis_valid),.axis_end(axis_end),
        .axis_index(axis_index),.axis_fg(axis_fg),.glyph_bbox_width(bbox_width),
        .glyph_bbox_height(bbox_height),.glyph_bbox_left(bbox_left),
        .glyph_bbox_right(bbox_right),.glyph_bbox_top(bbox_top),
        .glyph_bbox_bottom(bbox_bottom),.glyph_y_min(ymin),.glyph_y_max(ymax),
        .glyph_y_available(y_available),.glyph_axis_eligible(scene_axis_eligible),
        .glyph_y_allowed(scene_y_allowed),.out_revoke(scene_revoke),.dbg_scene_count(scene_pixels),
        .dbg_glyph_count(glyph_pixels),.dbg_paper_count(paper_pixels),.dbg_scene_event(),
        .dbg_scene_flags(scene_flags));
    generate if(SHAPE_ENABLE)begin:shape_enabled
    pixel302_shape_scores #(.GEOMETRY_FILE(GEOMETRY_FILE)) shape (
        .clk(capture_clk),.rst_n(capture_release[2]),.flush(detector_flush),
        .full_start(sc_start),.full_valid(sc_valid),.full_end(sc_end),
        .axis_start(axis_start),.axis_valid(axis_valid),.axis_end(axis_end),
        .sample_index(axis_valid?axis_index:sc_index),.sample_fg(axis_valid?axis_fg:sc_fg),
        .frame_good(sc_good),.frame_present(sc_present),
        .frame_id(sc_id),.frame_source(sc_source),.out_frame(shape_event),.out_healthy(shape_healthy),
        .out_present(shape_present),.out_id(shape_id),.out_source(shape_source),
        .circle_distance(circle),.square_distance(square),.triangle_distance(triangle),
        .ellipse_distance(ellipse),.axis_circle_distance(axis_circle));
    end else begin:shape_disabled
        assign shape_event=1'b0;assign shape_healthy=1'b0;assign shape_present=1'b0;
        assign shape_id=32'd0;assign shape_source=1'b0;
        assign circle=11'd2047;assign square=11'd2047;assign triangle=11'd2047;
        assign ellipse=11'd2047;assign axis_circle=11'd2047;
    end endgenerate
    pixel302_rotation_matcher #(.TEMPLATE_FILE(TEMPLATE_FILE),.VARIANTS(ROTATION_VARIANTS),
        .ENABLE_OUTPUT(1)) matcher (
        .clk(capture_clk),.rst_n(capture_release[3]),.flush(detector_flush),.frame_start(sc_start),
        .sample_valid(sc_valid),.sample_index(sc_index),.sample_foreground(sc_fg),
        .frame_end(sc_end),.frame_good(sc_good),.frame_present(sc_present),
        .frame_id(sc_id),.frame_source_test(sc_source),.out_frame(match_event),
        .out_healthy(match_good),.out_present(match_present),.out_valid(match_valid),
        .out_item(),.out_raw_winner(match_item),.out_best(match_best),.out_second(match_second),
        .out_fg_count(match_foreground),.out_frame_id(match_id),.out_source_test(match_source));
    wire ae,ah,ap,av,asrc,acq,aclip,aborder,apaper,aknown,aarb;
    wire [3:0] ai,araw,ashape,acard;
    wire [31:0] aid;
    wire [7:0] ac,reason;
    wire [2:0] bits,available;
    wire [10:0] d0,d1,d2,db,ds,df;
    wire [15:0] asc,agc;
    wire [10:0] abbox_left,abbox_right;
    wire [9:0] abbox_top,abbox_bottom;
    pixel309_arbitrate #(.WAIT_CYCLES(WAIT_CYCLES),.SHAPE_ENABLE(SHAPE_ENABLE)) arb (
        .clk(capture_clk),.rst_n(capture_release[4]),.flush(detector_flush),
        .scene_event(SHAPE_ENABLE?axis_end:sc_end),.scene_healthy(sc_good),.scene_present(sc_present),
        .scene_frame_id(sc_id),.scene_source_test(sc_source),.scene_count(scene_pixels),
        .scene_glyph_count(glyph_pixels),.scene_y_available(y_available),.scene_y_min(ymin),
        .scene_y_max(ymax),.scene_bbox_width(bbox_width),.scene_bbox_height(bbox_height),
        .scene_bbox_left(bbox_left),.scene_bbox_right(bbox_right),
        .scene_bbox_top(bbox_top),.scene_bbox_bottom(bbox_bottom),
        .scene_axis_eligible(scene_axis_eligible),.scene_y_allowed(scene_y_allowed),
        .scene_clipped(scene_flags[1]),.scene_border_uncertain(scene_flags[3]),.scene_paper_flag(scene_flags[2]),
        .shape_event(shape_event),.shape_healthy(shape_healthy),.shape_present(shape_present),
        .shape_frame_id(shape_id),.shape_source_test(shape_source),.shape_circle(circle),
        .shape_square(square),.shape_triangle(triangle),.shape_ellipse(ellipse),
        .shape_axis_circle(axis_circle),.shape_aspect_good(1'b0),
        .card_event(match_event),.card_healthy(match_good),.card_present(match_present),
        .card_valid(match_valid),.card_item(match_item),.card_frame_id(match_id),.card_source_test(match_source),
        .card_count(8'd0),.card_best(match_best),.card_second(match_second),
        .card_foreground(match_foreground),.card_qualified(match_valid),
        .out_event(ae),.out_healthy(ah),.out_present(ap),.out_valid(av),.out_item(ai),
        .out_frame_id(aid),.out_source_test(asrc),.out_count(ac),.out_reason(reason),
        .out_shape_bits(bits),.out_circle(d0),.out_square(d1),.out_triangle(d2),
        .out_card_best(db),.out_card_second(ds),.out_foreground(df),.out_available(available),
        .out_scene_count(asc),.out_glyph_count(agc),.out_raw_item(araw),.out_card_qualified(acq),
        .out_clipped(aclip),.out_border_uncertain(aborder),.out_paper_flag(apaper),
        .out_shape_item(ashape),.out_card_winner(acard),
        .out_bbox_left(abbox_left),.out_bbox_right(abbox_right),
        .out_bbox_top(abbox_top),.out_bbox_bottom(abbox_bottom),
        .out_identity_known(aknown),.out_arbitrated(aarb));
    wire fe,fh,fp,fv,fsrc;
    wire [3:0] fi;
    wire [31:0] fid;
    wire [7:0] fc;
    items30_result_filter #(.CONFIRM_FRAMES(CONFIRM_FRAMES)) confirmation (
        .clk(capture_clk),.rst_n(capture_release[5]),.flush(detector_flush),.in_frame(ae),
        .in_healthy(ah),.in_present(ap),.in_valid(av),.in_item(ai),.in_frame_id(aid),
        .in_source_test(asrc),.out_frame(fe),.out_healthy(fh),.out_present(fp),.out_valid(fv),
        .out_item(fi),.out_frame_id(fid),.out_source_test(fsrc),.stable_count(fc));
    reg metadata_pending,send_pending,revoke_pending;
    reg [191:0] metadata,send_packet;
    reg [191:0] assembled;
    reg [47:0] track_pending_meta,track_send_meta;
    // These coordinates were captured by the arbiter with aid/asrc, not the
    // scene engine's next live frame. Invalid extents never acquire validity.
    wire track_bbox_good=abbox_right>=abbox_left && abbox_bottom>=abbox_top &&
        abbox_right<SCENE_WIDTH/SCENE_SAMPLE_STEP &&
        abbox_bottom<SCENE_HEIGHT/SCENE_SAMPLE_STEP;
    wire [10:0] track_x_capture=SCENE_X + abbox_left*SCENE_SAMPLE_STEP;
    wire [9:0] track_y_capture=SCENE_Y + abbox_top*SCENE_SAMPLE_STEP;
    wire [10:0] track_w_capture=(abbox_right>=abbox_left) ?
        (abbox_right-abbox_left+1'b1)*SCENE_SAMPLE_STEP : 0;
    wire [9:0] track_h_capture=(abbox_bottom>=abbox_top) ?
        (abbox_bottom-abbox_top+1'b1)*SCENE_SAMPLE_STEP : 0;
    wire [47:0] track_meta_value={TRACK_ENABLE && ah && ap && av && aknown && aarb &&
        !aclip && !aborder && ai>=4'd10 && ai<=4'd14 && track_bbox_good,
        track_x_capture,track_y_capture,track_w_capture,track_h_capture,5'd0};
    wire filtered_identity=metadata_pending && fid==metadata[`R30_ID] && fsrc==metadata[`R30_SOURCE];
    wire send_revoke=revoke_pending||new_revoke;
    wire send_event=!transport_flush&&forward_ready&&(send_revoke||(!wait_start&&send_pending));
    reg [191:0] revoke_packet;
    always @* begin
        revoke_packet=0;
        revoke_packet[`R30_PRESENT]=1;revoke_packet[`R30_REVOKE]=1;
        revoke_packet[`R30_REASON]=8'h01;
        revoke_packet[`R30_CIRCLE]=2047;revoke_packet[`R30_SQUARE]=2047;
        revoke_packet[`R30_TRIANGLE]=2047;revoke_packet[`R30_CARD_BEST]=2047;
        revoke_packet[`R30_CARD_SECOND]=2047;revoke_packet[`R30_FOREGROUND]=2047;
        revoke_packet[`R30_PACKET_REV]=1;revoke_packet[`R30_CATALOG_REV]=1;
        assembled=metadata;
        assembled[`R30_HEALTHY]=fh&&filtered_identity;
        assembled[`R30_PRESENT]=fh&&filtered_identity?fp:1'b1;
        assembled[`R30_VALID]=fv&&fh&&filtered_identity;
        assembled[`R30_REVOKE]=!fh||!filtered_identity;
        assembled[`R30_ITEM]=fv&&fh&&filtered_identity?fi:4'd0;
        assembled[`R30_COUNT]=fh&&filtered_identity?fc:8'd0;
    end
    always @(posedge capture_clk or negedge rst_n) begin
        if(!rst_n) begin
            metadata_pending<=0;send_pending<=0;revoke_pending<=0;
            metadata<=0;send_packet<=0;staging_fault<=0;
            track_pending_meta<=0;track_send_meta<=0;
        end else if(!crst) begin
            metadata_pending<=0;send_pending<=0;revoke_pending<=0;staging_fault<=0;
            track_pending_meta<=0;track_send_meta<=0;
        end else begin
            if(reverse_event)staging_fault<=0;
            if(transport_flush)revoke_pending<=0;
            else if(new_revoke)revoke_pending<=!send_event;
            else if(send_event&&send_revoke)revoke_pending<=0;
            if(detector_flush)begin metadata_pending<=0;send_pending<=0;end
            else begin
                if(send_event&&!send_revoke)send_pending<=0;
                if(fe)begin
                    metadata_pending<=0;
                    if(!filtered_identity || (send_pending&&!(send_event&&!send_revoke)))staging_fault<=1;
                    else begin
                        send_pending<=1;send_packet<=assembled;
                        // Track eligibility is granted only by the same
                        // confirmed result that supplies the public R30 item.
                        track_send_meta<={track_pending_meta[47] && fv && fh && fp &&
                            filtered_identity && fi>=4'd10 && fi<=4'd14 &&
                            fi==metadata[`R30_RAW_ITEM],track_pending_meta[46:0]};
                    end
                end
                if(ae)begin
                    if(metadata_pending&&!fe)staging_fault<=1;
                    else begin
                        metadata_pending<=1;metadata<=0;
                        track_pending_meta<=track_meta_value;
                        metadata[`R30_ID]<=aid;metadata[`R30_SOURCE]<=asrc;
                        metadata[`R30_CLIPPED]<=aclip;metadata[`R30_BORDER]<=aborder;
                        metadata[`R30_PAPER]<=apaper;metadata[`R30_SHAPE_ITEM]<=ashape;
                        metadata[`R30_CARD_ITEM]<=acard;metadata[`R30_SHAPE_BITS]<=bits;
                        metadata[`R30_CARD_QUALIFIED]<=acq;metadata[`R30_SCENE_COUNT]<=asc;
                        metadata[`R30_GLYPH_COUNT]<=agc;metadata[`R30_RAW_ITEM]<=araw;
                        metadata[`R30_AVAILABLE]<=available;metadata[`R30_ARBITRATED]<=aarb;
                        metadata[`R30_REASON]<=reason;metadata[`R30_CIRCLE]<=d0;
                        metadata[`R30_SQUARE]<=d1;metadata[`R30_TRIANGLE]<=d2;
                        metadata[`R30_CARD_BEST]<=db;metadata[`R30_CARD_SECOND]<=ds;
                        metadata[`R30_FOREGROUND]<=df;metadata[`R30_PACKET_REV]<=1;
                        metadata[`R30_CATALOG_REV]<=1;metadata[`R30_ID_KNOWN]<=aknown;
                    end
                end
            end
        end
    end
    // The 48 private geometry bits and 192 public bits are one mailbox
    // transaction. Request/acknowledgement and fault handling cannot diverge.
    // Existing forward instance naming is retained for the physical CDC paths;
    // its held_data/dst_data payload is now 240 bits and needs the same review.
    pixel14_result_cdc #(.WIDTH(240)) forward (
        .rst_n(rst_n),.src_clk(capture_clk),.src_valid(send_event),
        .src_data(send_revoke?{48'd0,revoke_packet}:{track_send_meta,send_packet}),
        .src_ready(forward_ready),.src_fault(forward_fault),
        .dst_clk(display_clk),.dst_valid(packet_event),
        .dst_data(forward_packet),.dst_fault(forward_dst_fault));
    wire system_flush;
    wire clear_level=flush||system_flush;
    reg [47:0] track_display_packet;
    reg flush_seen,external_flush_seen,reverse_pending;
    reg [2:0] quiet_count;
    wire clear_request=(clear_level&&!flush_seen)||(flush&&!external_flush_seen);
    wire clear_dispatch=reverse_ready&&(clear_request||reverse_pending);
    assign link_fault=forward_dst_fault||reverse_src_fault||staging_sync;
    assign quarantined=flush||!reverse_ready||quiet_count!=0||clear_request||reverse_pending||link_fault;
    always @(posedge display_clk or negedge rst_n) begin
        if(!rst_n)begin flush_seen<=0;external_flush_seen<=0;reverse_pending<=0;quiet_count<=4;end
        else if(!drst)begin flush_seen<=0;external_flush_seen<=0;reverse_pending<=0;quiet_count<=4;end
        else begin
            flush_seen<=clear_level;external_flush_seen<=flush;
            if(clear_dispatch)reverse_pending<=0;else if(clear_request)reverse_pending<=1;
            if(clear_request||!reverse_ready||reverse_pending)quiet_count<=4;
            else if(quiet_count!=0)quiet_count<=quiet_count-1'b1;
        end
    end
    pixel14_result_cdc #(.WIDTH(1)) backward (
        .rst_n(rst_n),.src_clk(display_clk),.src_valid(clear_dispatch),.src_data(1'b1),
        .src_ready(reverse_ready),.src_fault(reverse_src_fault),.dst_clk(capture_clk),
        .dst_valid(reverse_event),.dst_data(reverse_data),.dst_fault(reverse_fault));
    wire accepted=packet_event&&!flush&&reverse_ready&&quiet_count==0&&!link_fault;
    wire packet_revoke=link_fault||quiet_count!=0||!reverse_ready;
    always @(posedge display_clk or negedge rst_n) begin
        if(!rst_n)track_display_packet<=0;
        else if(!drst || clear_level || quarantined)track_display_packet<=0;
        else if(accepted)track_display_packet<=TRACK_ENABLE?track_packet:48'd0;
        else if(!recognition_fresh || recognition_fault || timed_out)track_display_packet<=0;
    end
    wire track_display_valid=TRACK_ENABLE && track_display_packet[47] &&
        recognition_fresh && !recognition_fault && !quarantined && !clear_level &&
        recognition_packet[`R30_ID_KNOWN] && recognition_packet[`R30_HEALTHY] &&
        recognition_packet[`R30_PRESENT] && recognition_packet[`R30_VALID] &&
        !recognition_packet[`R30_REVOKE] && recognition_packet[`R30_ITEM]>=4'd10 &&
        recognition_packet[`R30_ITEM]<=4'd14;
    pixel309_system #(.TIMEOUT_MS(TIMEOUT_MS),.FEEDBACK_TICKS(FEEDBACK_TICKS),
        .SHAPE_ENABLE(SHAPE_ENABLE)) system (
        .clk(display_clk),.rst_n(drst),.tick_1ms(tick_1ms),.flush(flush),
        .transport_revoke(packet_revoke),.packet_in_event(accepted),.packet_in(packet),
        .key_mode_pulse(key_mode_pulse),.key_replay_pulse(key_replay_pulse),
        .key_skip_pulse(key_skip_pulse),.key_reset_pulse(key_reset_pulse),
        .audio_idle(audio_idle),.audio_fault(audio_fault),.detectors_flush(system_flush),
        .obs_event(obs_event),.obs_healthy(obs_healthy),.obs_present(obs_present),
        .obs_valid(obs_valid),.obs_revoke(obs_revoke),.obs_conflict(obs_conflict),.timed_out(timed_out),
        .obs_item(obs_item),.obs_frame_id(obs_frame_id),.obs_source_test(obs_source_test),.obs_count(obs_count),
        .mode(mode),.phase(phase),.score(score),.question_index(question_index),.target_item(target_item),
        .display_item(display_item),.quiz_active(quiz_active),.answer_valid(answer_valid),
        .answer_correct(answer_correct),.display_source_test(display_source_test),.armed(armed),
        .feedback(feedback),.audio_event_valid(audio_event_valid),.audio_cancel(audio_cancel),
        .audio_event_kind(audio_event_kind),.audio_event_item(audio_event_item),.render_state(render_state),
        .recognition_packet(recognition_packet),.packet_event(recognition_event),
        .packet_fresh(recognition_fresh),.packet_fault(recognition_fault),.packet_age(recognition_age));
    generate if(RENDER_ENABLE)begin:render
        pixel309_compositor_track #(.SCENE_X(SCENE_X),.SCENE_Y(SCENE_Y),.SCENE_WIDTH(SCENE_WIDTH),
            .SCENE_HEIGHT(SCENE_HEIGHT),.TRACK_ENABLE(TRACK_ENABLE),
            .COORD_ENABLE(TRACK_ENABLE),
            .LOGO_INDEX_FILE(LOGO_INDEX_FILE),.LOGO_PALETTE_FILE(LOGO_PALETTE_FILE)) compositor (
            .clk(display_clk),.rst_n(drst),.in_frame_start(video_frame_start),.in_de(video_de),
            .in_hsync(video_hsync),.in_vsync(video_vsync),.mode_request(1'b0),.style_request(style_request),
            .calibration_state(calibration_state),.tf_state(tf_state),
            .in_x(pixel_x),.in_y(pixel_y),.in_rgb(video_rgb),.business_state(render_state),
            .recognition_packet(recognition_packet),.recognition_fresh(recognition_fresh),
            .recognition_fault(recognition_fault),.recognition_age(recognition_age),
            .track_valid(track_display_valid),
            .track_x(track_display_packet[46:36]),.track_y(track_display_packet[35:26]),
            .track_w(track_display_packet[25:15]),.track_h(track_display_packet[14:5]),
            .out_frame_start(),.out_de(out_de),.out_hsync(out_hsync),.out_vsync(out_vsync),
            .out_mode(),.out_x(),.out_y(),.out_rgb(out_rgb),.out_panel_active(),
            .out_diag_active(),.out_logo_active());
    end else begin:bypass
        reg [5:0] de,hs,vs;
        reg [23:0] rgb[0:5];
        integer i;
        always @(posedge display_clk or negedge rst_n)begin
            if(!rst_n)begin de<=0;hs<=0;vs<=0;for(i=0;i<6;i=i+1)rgb[i]<=0;end
            else begin
                de<={de[4:0],video_de};hs<={hs[4:0],video_hsync};vs<={vs[4:0],video_vsync};
                rgb[0]<=video_rgb;for(i=1;i<6;i=i+1)rgb[i]<=rgb[i-1];
            end
        end
        assign out_de=de[5];assign out_hsync=hs[5];assign out_vsync=vs[5];
        assign out_rgb=de[5]?rgb[5]:24'd0;
    end endgenerate
endmodule




