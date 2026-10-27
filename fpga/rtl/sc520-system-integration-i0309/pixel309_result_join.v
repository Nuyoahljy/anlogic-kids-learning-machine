`include "recognition30_packet.vh"
// I0309: public R30 remains 192 bits; required detector families follow SHAPE_ENABLE.
module pixel309_result_join #(
    parameter integer TIMEOUT_MS=100,SHAPE_ENABLE=1
) (
    input wire clk,rst_n,tick_1ms,flush,transport_revoke,
    input wire in_event,
    input wire [191:0] in_packet,
    output wire detectors_flush,
    output reg out_event,out_healthy,out_present,out_valid,out_revoke,out_conflict,
    output reg [3:0] out_item,
    output reg [31:0] out_frame_id,
    output reg out_source_test,
    output reg [7:0] out_count,
    output reg [191:0] packet,
    output reg packet_event,packet_fresh,packet_fault,
    output reg [7:0] packet_age,
    output reg timed_out
);
    localparam [2:0] REQUIRED_AVAILABLE=SHAPE_ENABLE?3'b111:3'b101;
    localparam integer TW=TIMEOUT_MS<2?1:$clog2(TIMEOUT_MS+1);
    reg [TW-1:0] age;
    reg [1:0] history_valid;
    reg active_source,source_valid,clear_seen;
    reg [31:0] last_id0,last_id1;
    wire known=in_packet[`R30_ID_KNOWN];
    wire source=in_packet[`R30_SOURCE];
    wire [31:0] advance=in_packet[`R30_ID]-(source?last_id1:last_id0);
    wire old_id=known && history_valid[source] && (advance==0 || advance[31]);
    wire source_change=known && source_valid && source!=active_source;
    wire legal_item=in_packet[`R30_ITEM]==0 ||
        (SHAPE_ENABLE && in_packet[`R30_ITEM]>=1 && in_packet[`R30_ITEM]<=3) ||
        (in_packet[`R30_ITEM]>=10 && in_packet[`R30_ITEM]<=14);
    wire legal_raw=in_packet[`R30_RAW_ITEM]==0 ||
        (SHAPE_ENABLE && in_packet[`R30_RAW_ITEM]>=1 && in_packet[`R30_RAW_ITEM]<=3) ||
        (in_packet[`R30_RAW_ITEM]>=10 && in_packet[`R30_RAW_ITEM]<=14);
    wire legal_winner=in_packet[`R30_CARD_ITEM]==0 ||
        (in_packet[`R30_CARD_ITEM]>=10 && in_packet[`R30_CARD_ITEM]<=14);
    wire unavailable_scene=!in_packet[100] && (in_packet[`R30_SCENE_COUNT]!=0 ||
        in_packet[`R30_GLYPH_COUNT]!=0 || in_packet[`R30_CLIPPED] ||
        in_packet[`R30_BORDER] || in_packet[`R30_PAPER]);
    wire unavailable_shape=!in_packet[101] && (in_packet[`R30_SHAPE_ITEM]!=0 ||
        in_packet[`R30_SHAPE_BITS]!=0 || in_packet[`R30_CIRCLE]!=2047 ||
        in_packet[`R30_SQUARE]!=2047 || in_packet[`R30_TRIANGLE]!=2047);
    wire unavailable_card=!in_packet[102] && (in_packet[`R30_CARD_ITEM]!=0 ||
        in_packet[`R30_CARD_QUALIFIED] || in_packet[`R30_CARD_BEST]!=2047 ||
        in_packet[`R30_CARD_SECOND]!=2047 || in_packet[`R30_FOREGROUND]!=2047);
    wire structural_bad=
        in_packet[`R30_PACKET_REV]!=1 || in_packet[`R30_CATALOG_REV]!=1 ||
        in_packet[191:187]!=0 || !legal_item || !legal_raw || !legal_winner ||
        in_packet[`R30_SHAPE_ITEM]>3 || unavailable_scene || unavailable_shape || unavailable_card ||
        (in_packet[`R30_AVAILABLE]!=REQUIRED_AVAILABLE &&
            (in_packet[`R30_ARBITRATED] || in_packet[`R30_RAW_ITEM]!=0)) ||
        ((!in_packet[`R30_HEALTHY] || in_packet[`R30_REVOKE]) &&
            (in_packet[`R30_VALID] || in_packet[`R30_ITEM]!=0 ||
             in_packet[`R30_COUNT]!=0 || !in_packet[`R30_REVOKE])) ||
        (in_packet[`R30_VALID] && (!in_packet[`R30_HEALTHY] ||
            !in_packet[`R30_PRESENT] || in_packet[`R30_REVOKE] ||
            in_packet[`R30_ITEM]==0 || in_packet[`R30_COUNT]<3 ||
            in_packet[`R30_ITEM]!=in_packet[`R30_RAW_ITEM])) ||
        (in_packet[`R30_HEALTHY] && !in_packet[`R30_PRESENT] &&
            (in_packet[`R30_RAW_ITEM]!=0 || in_packet[`R30_COUNT]!=0)) ||
        (in_packet[`R30_HEALTHY] && !in_packet[`R30_VALID] && in_packet[`R30_COUNT]>=3) ||
        (in_packet[`R30_HEALTHY] && in_packet[`R30_RAW_ITEM]==0 && in_packet[`R30_COUNT]!=0) ||
        (in_packet[`R30_HEALTHY] && in_packet[`R30_RAW_ITEM]!=0 && in_packet[`R30_COUNT]==0) ||
        (!in_packet[`R30_VALID] && in_packet[`R30_ITEM]!=0) ||
        (in_packet[`R30_HEALTHY] && (!known ||
            in_packet[`R30_AVAILABLE]!=REQUIRED_AVAILABLE || !in_packet[`R30_ARBITRATED])) ||
        (!known && (in_packet[`R30_HEALTHY] || !in_packet[`R30_REVOKE] ||
            in_packet[`R30_VALID] || in_packet[`R30_ITEM]!=0 ||
            in_packet[`R30_COUNT]!=0 || in_packet[`R30_ARBITRATED] ||
            in_packet[`R30_RAW_ITEM]!=0 || in_packet[`R30_AVAILABLE]!=0));
    wire packet_bad=in_event && (structural_bad || old_id || source_change);
    wire packet_invalid=in_event && (!in_packet[`R30_HEALTHY] || in_packet[`R30_REVOKE]);
    wire external_clear=flush || transport_revoke;
    wire accepted=in_event && !external_clear && !packet_bad;
    wire timeout_now=!external_clear && !accepted && !timed_out &&
        tick_1ms && age>=TIMEOUT_MS-1;
    reg [191:0] sanitized;
    always @* begin
        sanitized=packet_bad&&known?in_packet:192'd0;
        sanitized[`R30_HEALTHY]=0;sanitized[`R30_PRESENT]=1;
        sanitized[`R30_VALID]=0;sanitized[`R30_REVOKE]=1;
        sanitized[`R30_ITEM]=0;sanitized[`R30_COUNT]=0;
        sanitized[`R30_PACKET_REV]=1;sanitized[`R30_CATALOG_REV]=1;
        sanitized[`R30_RESERVED]=0;
        sanitized[`R30_REASON]=packet_bad?in_packet[`R30_REASON]|8'h02:
            timeout_now?8'h04:flush?8'h80:8'h40;
        if(!packet_bad||!known)begin
            sanitized[`R30_ID_KNOWN]=0;sanitized[`R30_AVAILABLE]=0;
            sanitized[`R30_ARBITRATED]=0;sanitized[`R30_RAW_ITEM]=0;
        end
        if(sanitized[`R30_AVAILABLE]!=REQUIRED_AVAILABLE)begin
            sanitized[`R30_ARBITRATED]=0;sanitized[`R30_RAW_ITEM]=0;
        end
        if(!sanitized[100])begin
            sanitized[`R30_SCENE_COUNT]=0;sanitized[`R30_GLYPH_COUNT]=0;
            sanitized[`R30_CLIPPED]=0;sanitized[`R30_BORDER]=0;sanitized[`R30_PAPER]=0;
        end
        if(!sanitized[101])begin
            sanitized[`R30_SHAPE_ITEM]=0;sanitized[`R30_SHAPE_BITS]=0;
            sanitized[`R30_CIRCLE]=2047;sanitized[`R30_SQUARE]=2047;sanitized[`R30_TRIANGLE]=2047;
        end
        if(!sanitized[102])begin
            sanitized[`R30_CARD_ITEM]=0;sanitized[`R30_CARD_QUALIFIED]=0;
            sanitized[`R30_CARD_BEST]=2047;sanitized[`R30_CARD_SECOND]=2047;
            sanitized[`R30_FOREGROUND]=2047;
        end
        if(sanitized[`R30_SHAPE_ITEM]>3)begin sanitized[`R30_SHAPE_ITEM]=0;sanitized[`R30_SHAPE_BITS]=0;end
        if(!legal_winner)begin sanitized[`R30_CARD_ITEM]=0;sanitized[`R30_CARD_QUALIFIED]=0;end
        if(!legal_raw)sanitized[`R30_RAW_ITEM]=0;
    end
    assign detectors_flush=flush || transport_revoke || packet_bad || packet_invalid || timeout_now;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            age<=0;timed_out<=0;history_valid<=0;last_id0<=0;last_id1<=0;
            active_source<=0;source_valid<=0;clear_seen<=0;
            out_event<=0;out_healthy<=0;out_present<=1;out_valid<=0;out_revoke<=0;
            out_conflict<=0;out_item<=0;out_frame_id<=0;out_source_test<=0;out_count<=0;
            packet<=0;packet_event<=0;packet_fresh<=0;packet_fault<=0;packet_age<=255;
        end else begin
            out_event<=0;out_revoke<=0;out_conflict<=0;packet_event<=0;
            clear_seen<=external_clear;
            // Internal faults retain both source histories. A switch consumes
            // its tag but is rejected, requiring a newer frame after clearing.
            if(flush) begin
                history_valid<=0;last_id0<=0;last_id1<=0;source_valid<=0;
                age<=0;timed_out<=0;
            end else if(in_event && known && !old_id) begin
                history_valid[source]<=1;
                if(source)last_id1<=in_packet[`R30_ID];else last_id0<=in_packet[`R30_ID];
                if(!structural_bad)begin active_source<=source;source_valid<=1;end
            end
            if(external_clear || packet_bad || timeout_now) begin
                out_event<=!external_clear || !clear_seen;
                out_revoke<=!external_clear || !clear_seen;
                out_healthy<=0;out_present<=1;out_valid<=0;out_item<=0;out_count<=0;
                out_frame_id<=sanitized[`R30_ID_KNOWN]?sanitized[`R30_ID]:32'd0;
                out_source_test<=sanitized[`R30_ID_KNOWN]?sanitized[`R30_SOURCE]:1'b0;
                packet_fresh<=0;packet_fault<=!flush;packet_age<=255;
                packet<=sanitized;
                if(packet_bad) begin
                    packet_event<=1;
                end
                if(timeout_now)timed_out<=1;
            end else if(accepted) begin
                age<=0;timed_out<=0;packet_age<=0;
                packet<=in_packet;packet_event<=1;packet_fresh<=1;packet_fault<=0;
                out_event<=1;out_healthy<=in_packet[`R30_HEALTHY] && !in_packet[`R30_REVOKE];
                out_present<=in_packet[`R30_HEALTHY] ? in_packet[`R30_PRESENT]:1'b1;
                out_valid<=in_packet[`R30_VALID] && in_packet[`R30_HEALTHY] && !in_packet[`R30_REVOKE];
                out_revoke<=!in_packet[`R30_HEALTHY] || in_packet[`R30_REVOKE];
                out_item<=in_packet[`R30_VALID] && in_packet[`R30_HEALTHY] &&
                    !in_packet[`R30_REVOKE] ? in_packet[`R30_ITEM]:4'd0;
                out_frame_id<=known?in_packet[`R30_ID]:32'd0;out_source_test<=known?source:1'b0;
                out_count<=in_packet[`R30_HEALTHY] && !in_packet[`R30_REVOKE] ? in_packet[`R30_COUNT]:8'd0;
            end else if(tick_1ms && !timed_out) begin
                if(age<TIMEOUT_MS)age<=age+1'b1;
                if(packet_fresh && packet_age!=255)packet_age<=packet_age+1'b1;
            end
        end
    end
    // synthesis translate_off
    initial if(TIMEOUT_MS<1 || TIMEOUT_MS>255)
        $fatal(1,"pixel309_result_join TIMEOUT_MS must be in 1..255");
    // synthesis translate_on
endmodule
