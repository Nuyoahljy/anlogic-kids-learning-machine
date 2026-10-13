// Task-local observer for the selected SC520 CSI parser and AWB96 tap.
// All inputs share clk. cfg_done/error must already be synchronized to clk.
// This certifies observed framing/counts, not CRC/ECC (vendor does not expose it).
module pixel14_capture_provenance #(
    parameter integer FRAME_WIDTH=1280, FRAME_HEIGHT=720,
    parameter integer DRAIN_IDLE_CYCLES=64, FRAME_TIMEOUT_CYCLES=2000000,
    parameter integer HS_TRAIL_MAX_WORDS=16
) (
    input wire clk,rst_n,
    input wire csi_sof,csi_eof,
    input wire [15:0] csi_length,
    input wire csi_valid,hs_valid,lane_error,
    input wire raw_sof,raw_eof,raw_valid,
    input wire isp_sof,isp_valid,isp_eol,
    input wire cfg_done,cfg_error,
    output wire frame_start,
    output wire [31:0] frame_id,
    output wire frame_done,frame_good,
    output wire [31:0] done_id,
    output wire revoke,
    output wire [255:0] diagnostic
);
    localparam integer GROUPS=FRAME_WIDTH/4*FRAME_HEIGHT;
    localparam integer CSI_WORDS=FRAME_WIDTH*10/32*FRAME_HEIGHT;
    localparam integer LINE_WORDS=FRAME_WIDTH*10/16;
    localparam integer IW=$clog2(DRAIN_IDLE_CYCLES+1);
    localparam integer TW=$clog2(FRAME_TIMEOUT_CYCLES+1);
    reg active,bad,isp_seen,raw_seen,eof_seen,raw_end_seen,fault_pulse;
    reg hs_d,length_d,burst_is_raw;
    reg [31:0] sequence_id,active_id;
    reg [19:0] raw_count,csi_count,isp_count;
    reg [15:0] hs_words;
    reg [10:0] line_count,isp_lines,isp_x;
    reg [IW-1:0] idle_count;
    reg [TW-1:0] age;
    wire packet_start=csi_length!=0 && !length_d;
    wire blank=!isp_valid && !isp_eol && !isp_sof;
    wire timed_out=age>=FRAME_TIMEOUT_CYCLES-1;
    wire drained=idle_count>=DRAIN_IDLE_CYCLES && isp_count>=GROUPS;
    // CSI short-packet decode precedes the end of aligned D-PHY HS-valid.
    // Wait for that transport window to close, rather than rejecting EOF in it.
    wire close_ready=eof_seen && raw_end_seen && drained && !hs_valid && !burst_is_raw;
    wire structure_good=raw_seen && eof_seen && raw_end_seen &&
        line_count==FRAME_HEIGHT && csi_count==CSI_WORDS && raw_count==GROUPS &&
        isp_count==GROUPS && isp_lines==FRAME_HEIGHT && !hs_valid && !burst_is_raw;
    assign frame_id=active_id;
    assign done_id=active_id;
    assign frame_start=active && isp_sof && !isp_seen && !csi_sof && !bad;
    // Combinational blank qualification guarantees done cannot coincide with
    // the next valid group. Never register done beside an undelayed pixel tap.
    assign frame_done=active && isp_seen && blank && !csi_sof && (close_ready || timed_out);
    assign frame_good=frame_done && close_ready && structure_good && !bad &&
        cfg_done && !cfg_error && !lane_error && !csi_valid && !raw_valid &&
        !raw_sof && !raw_eof && !csi_eof && !packet_start;
    assign revoke=fault_pulse || (active && bad) || lane_error || !cfg_done || cfg_error;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            active<=0;bad<=0;isp_seen<=0;raw_seen<=0;eof_seen<=0;raw_end_seen<=0;fault_pulse<=0;
            hs_d<=0;length_d<=0;burst_is_raw<=0;sequence_id<=0;active_id<=0;
            raw_count<=0;csi_count<=0;isp_count<=0;hs_words<=0;line_count<=0;isp_lines<=0;isp_x<=0;
            idle_count<=0;age<=0;
        end else begin
            fault_pulse<=0;hs_d<=hs_valid;length_d<=csi_length!=0;
            if(hs_valid) begin
                if(!hs_d) hs_words<=1;
                else if(hs_words!=16'hffff) hs_words<=hs_words+1'b1;
            end
            if(!hs_valid && hs_d) begin
                // Preserve minimum header/payload/CRC coverage. The aligned HS
                // window may include a bounded tail after the CSI payload.
                if(active && burst_is_raw &&
                   (hs_words<LINE_WORDS+3 || hs_words>LINE_WORDS+3+HS_TRAIL_MAX_WORDS)) bad<=1;
                burst_is_raw<=0;
            end
            if(csi_sof) begin
                sequence_id<=sequence_id+1'b1;
                // An overlap is ambiguous: discard both frames, then resync
                // only at a subsequent independent CSI SOF.
                if(active) begin active<=0;bad<=1;fault_pulse<=1;end
                else begin
                    active<=1;active_id<=sequence_id+1'b1;
                    bad<=!cfg_done || cfg_error || lane_error || csi_eof || isp_sof;
                    isp_seen<=0;raw_seen<=0;eof_seen<=0;raw_end_seen<=0;
                    raw_count<=0;csi_count<=0;isp_count<=0;line_count<=0;isp_lines<=0;isp_x<=0;
                    idle_count<=0;age<=0;burst_is_raw<=0;
                end
            end else if(active) begin
                if(age<FRAME_TIMEOUT_CYCLES) age<=age+1'b1;
                if(!cfg_done || cfg_error || lane_error) bad<=1;
                if(packet_start) begin
                    burst_is_raw<=1;
                    if(csi_length!=LINE_WORDS || eof_seen || line_count>=FRAME_HEIGHT || !hs_valid) bad<=1;
                    if(line_count<FRAME_HEIGHT+1) line_count<=line_count+1'b1;
                end
                if(csi_valid) begin
                    if(csi_count<CSI_WORDS+1) csi_count<=csi_count+1'b1;
                    if(eof_seen || csi_count>=CSI_WORDS) bad<=1;
                end
                if(raw_sof) begin if(raw_seen || raw_count!=0) bad<=1;raw_seen<=1;end
                if(raw_valid) begin
                    if(raw_count<GROUPS+1) raw_count<=raw_count+1'b1;
                    // Vendor RAW EOF forwards the CSI short packet before
                    // the multi-cycle RAW regrouping tail necessarily drains.
                    if(!(raw_seen || raw_sof) || raw_count>=GROUPS) bad<=1;
                end
                if(csi_eof) begin
                    eof_seen<=1;
                    if(eof_seen || line_count!=FRAME_HEIGHT || csi_count!=CSI_WORDS || burst_is_raw) bad<=1;
                end
                if(raw_eof) begin
                    raw_end_seen<=1;
                    if(raw_end_seen || !eof_seen || !raw_seen) bad<=1;
                end
                if(isp_sof) begin
                    if(isp_seen || !raw_seen) bad<=1;
                    isp_seen<=1;
                end
                if(isp_valid) begin
                    idle_count<=0;
                    if(isp_count<GROUPS+1) isp_count<=isp_count+1'b1;
                    if(!(isp_seen || frame_start) || isp_count>=GROUPS || isp_eol!=(isp_x==FRAME_WIDTH/4-1)) bad<=1;
                    if(isp_x==FRAME_WIDTH/4-1) begin
                        isp_x<=0;
                        if(isp_lines<FRAME_HEIGHT+1) isp_lines<=isp_lines+1'b1;
                    end else isp_x<=isp_x+1'b1;
                end else begin
                    if(isp_eol) bad<=1;
                    if(blank && idle_count<DRAIN_IDLE_CYCLES) idle_count<=idle_count+1'b1;
                    else if(!blank) idle_count<=0;
                end
                if(frame_done) begin
                    active<=0;
                    if(!frame_good) fault_pulse<=1;
                end else if(timed_out) begin
                    active<=0;bad<=1;fault_pulse<=1;
                end
            end else if(isp_sof || csi_eof || raw_eof) fault_pulse<=1;
        end
    end

    // Diagnostics never drive frame_good/revoke. Freeze a completed/rejected
    // frame's counts so a photograph can identify the first failure boundary.
    // The top captures all 256 bits atomically through a separate mailbox.
    reg [15:0] frame_errors,last_errors,frame_hs_max,last_hs_max;
    reg [15:0] frame_eof_hs,last_eof_hs,seen_frames,good_frames;
    reg [19:0] last_csi,last_raw,last_isp;
    reg [10:0] last_lines,last_isp_lines;
    reg [20:0] last_age;
    reg [15:0] faults;
    always @* begin
        faults=0;
        if(!cfg_done) faults[0]=1;
        if(cfg_error) faults[1]=1;
        if(lane_error) faults[2]=1;
        if(csi_sof && active) faults[3]=1;
        if(active) begin
            if(packet_start && (csi_length!=LINE_WORDS || eof_seen || line_count>=FRAME_HEIGHT || !hs_valid)) faults[4]=1;
            if(!hs_valid && hs_d && burst_is_raw &&
               (hs_words<LINE_WORDS+3 || hs_words>LINE_WORDS+3+HS_TRAIL_MAX_WORDS)) faults[5]=1;
            if(csi_valid && (eof_seen || csi_count>=CSI_WORDS)) faults[6]=1;
            if((raw_sof && (raw_seen || raw_count!=0)) ||
               (raw_valid && (!(raw_seen || raw_sof) || raw_count>=GROUPS))) faults[7]=1;
            if(csi_eof && (eof_seen || line_count!=FRAME_HEIGHT || csi_count!=CSI_WORDS || burst_is_raw)) faults[8]=1;
            if(raw_eof && (raw_end_seen || !eof_seen || !raw_seen)) faults[9]=1;
            if(isp_sof && (isp_seen || !raw_seen)) faults[10]=1;
            if((isp_valid && (!(isp_seen || frame_start) || isp_count>=GROUPS ||
                isp_eol!=(isp_x==FRAME_WIDTH/4-1))) || (!isp_valid && isp_eol)) faults[11]=1;
            if(frame_done && !frame_good && (!structure_good || raw_sof || raw_eof || csi_eof || packet_start)) faults[12]=1;
            if(timed_out && !close_ready) faults[13]=1;
        end else if(isp_sof || csi_eof || raw_eof) faults[14]=1;
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            frame_errors<=0;last_errors<=0;frame_hs_max<=0;last_hs_max<=0;
            frame_eof_hs<=0;last_eof_hs<=0;seen_frames<=0;good_frames<=0;
            last_csi<=0;last_raw<=0;last_isp<=0;last_lines<=0;last_isp_lines<=0;last_age<=0;
        end else begin
            if(csi_sof) seen_frames<=seen_frames+1'b1;
            if(frame_good) good_frames<=good_frames+1'b1;
            if(csi_sof && !active) begin
                frame_errors<=faults;frame_hs_max<=0;frame_eof_hs<=0;
            end else if(active) begin
                frame_errors<=frame_errors | faults;
                if(!hs_valid && hs_d && burst_is_raw && hs_words>frame_hs_max) frame_hs_max<=hs_words;
                if(csi_eof) frame_eof_hs<={hs_valid,hs_words[14:0]};
            end
            if(active && (frame_done || timed_out || csi_sof)) begin
                last_errors<=frame_errors | faults;
                last_hs_max<=!hs_valid && hs_d && burst_is_raw && hs_words>frame_hs_max ? hs_words : frame_hs_max;
                last_eof_hs<=csi_eof ? {hs_valid,hs_words[14:0]} : frame_eof_hs;
                last_csi<=csi_count;last_raw<=raw_count;last_isp<=isp_count;
                last_lines<=line_count;last_isp_lines<=isp_lines;last_age<=age;
            end else if(!active && !csi_sof && faults[14]) last_errors<=last_errors | faults;
        end
    end
    wire [15:0] live_errors=last_errors | {13'd0,lane_error,cfg_error,!cfg_done};
    assign diagnostic={16'h0107,live_errors,last_hs_max,last_eof_hs,
        12'd0,last_csi[19:16],last_csi[15:0],12'd0,last_raw[19:16],last_raw[15:0],
        12'd0,last_isp[19:16],last_isp[15:0],5'd0,last_lines,5'd0,last_isp_lines,
        11'd0,last_age[20:16],last_age[15:0],seen_frames,good_frames};
    // synthesis translate_off
    initial if(FRAME_WIDTH<8 || FRAME_WIDTH%16!=0 || FRAME_HEIGHT<1 ||
        GROUPS>1048574 || CSI_WORDS>1048574 || DRAIN_IDLE_CYCLES<2 || FRAME_TIMEOUT_CYCLES<8 ||
        FRAME_TIMEOUT_CYCLES>2097151 || HS_TRAIL_MAX_WORDS<0 || HS_TRAIL_MAX_WORDS>256)
        $fatal(1,"pixel14 provenance invalid parameters");
    // synthesis translate_on
endmodule
