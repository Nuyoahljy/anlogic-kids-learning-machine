// Capture-side real tap/metadata binding and compact diagnostic packet.
module pixel23_color_observer #(
    parameter integer FRAME_WIDTH=1280,FRAME_HEIGHT=720,
    parameter integer CLASS_X=160,CLASS_Y=120,CLASS_W=960,CLASS_H=480,
    parameter integer CENTER_X=636,CENTER_Y=356,PAPER_X=192,PAPER_Y=144
) (
    input wire clk,rst_n,diagnostics_rst_n,join_rst_n,flush,
    input wire frame_start,
    input wire [31:0] frame_id,
    input wire valid,eol,
    input wire [95:0] pre_wb,post_wb,post_tone,
    input wire [31:0] pixel_id,
    input wire [8:0] gain_r,gain_b,
    input wire stats_event,stats_good,
    input wire [31:0] stats_id,
    input wire [20:0] neutral_count,
    input wire frame_done,frame_good,
    input wire [31:0] done_id,
    input wire analysis_event,analysis_good,
    input wire [31:0] analysis_id,
    input wire [148:0] analysis_data,
    output wire out_event,
    output wire [799:0] out_packet
);
    localparam integer CB=$clog2(FRAME_WIDTH*FRAME_HEIGHT+1);
    reg have_stats;
    reg [31:0] final_stats_id;
    reg [20:0] final_neutral;
    reg epoch_bad;
    wire pixel_mismatch=valid && pixel_id!=frame_id;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin have_stats<=0;final_stats_id<=0;final_neutral<=0;epoch_bad<=0;end
        else if(flush)begin have_stats<=0;epoch_bad<=0;end
        else begin
            if(frame_start)begin have_stats<=0;epoch_bad<=0;end
            if(pixel_mismatch)epoch_bad<=1;
            if(stats_event)begin
                if(have_stats || !stats_good)epoch_bad<=1;
                have_stats<=stats_good;final_stats_id<=stats_id;final_neutral<=neutral_count;
            end
            if(frame_done)have_stats<=0;
        end
    end
    wire diag_event,diag_good,diag_reject;
    wire [31:0] diag_id;
    wire [8:0] diag_gr,diag_gb;
    wire [20:0] diag_neutral;
    wire [9*CB-1:0] hits;
    wire [41:0] lowclip,highclip;
    wire [269:0] sums;
    wire [143:0] samples;
    pixel14_color_diagnostics #(.FRAME_WIDTH(FRAME_WIDTH),.FRAME_HEIGHT(FRAME_HEIGHT),
      .CLASS_X(CLASS_X),.CLASS_Y(CLASS_Y),.CLASS_W(CLASS_W),.CLASS_H(CLASS_H),
      .CENTER_X(CENTER_X),.CENTER_Y(CENTER_Y),.PAPER_X(PAPER_X),.PAPER_Y(PAPER_Y)) diagnostics (
        .clk(clk),.rst_n(diagnostics_rst_n),.flush(flush),.in_sof(frame_start),.in_frame_id(frame_id),
        .in_valid(valid),.in_eol(eol),.in_pre_wb(pre_wb),.in_post_wb(post_wb),.in_post_tone(post_tone),
        .in_gain_r(gain_r),.in_gain_b(gain_b),.in_frame_done(frame_done),
        .in_frame_good(frame_good && have_stats && final_stats_id==done_id && !epoch_bad && !pixel_mismatch),
        .in_done_id(done_id),.in_neutral_count(final_neutral),.out_valid(diag_event),.out_trusted(diag_good),
        .out_reject(diag_reject),.out_reject_reason(),.out_frame_id(diag_id),.out_gain_r(diag_gr),.out_gain_b(diag_gb),
        .out_neutral_count(diag_neutral),.out_class_pixels(),.out_color_hits(hits),.out_roi_pixels(),
        .out_roi_lowclip(lowclip),.out_roi_highclip(highclip),.out_roi_rgb_sum(sums),
        .out_sample_rgb(samples),.out_sample_present(),.out_sample_xy());
    wire [622:0] color_record;
    assign color_record[31:0]=diag_reject ? frame_id:diag_id;
    assign color_record[175:32]=samples;
    genvar c;
    generate for(c=0;c<18;c=c+1)begin: means
        // Both observed8x8 windows have exactly64 pixels; pure shift, no divider.
        assign color_record[176+(c/3)*24+(2-c%3)*8+:8]=sums[c*15+6+:8];
    end
    for(c=0;c<9;c=c+1)begin: color_hits
        assign color_record[443+c*20+:20]=hits[c*CB+:CB];
    end endgenerate
    assign color_record[361:320]=lowclip;assign color_record[403:362]=highclip;
    assign color_record[412:404]=diag_gr;assign color_record[421:413]=diag_gb;
    assign color_record[442:422]=diag_neutral;
    pixel14_observation_join joiner (
        .clk(clk),.rst_n(join_rst_n),.flush(flush),.color_event(diag_event || diag_reject),.color_good(diag_event && diag_good),
        .color_data(color_record),.analysis_event(analysis_event),.analysis_good(analysis_good),
        .analysis_id(analysis_id),.analysis_data(analysis_data),.out_event(out_event),.out_packet(out_packet));
endmodule
