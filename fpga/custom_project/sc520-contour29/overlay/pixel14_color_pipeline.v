// T026: fixed Q8 WB 304/256/333, stage2 tone1. Original 54-cycle path.
// Task-local replacement for legacy prefix gray-world AWB.
// The private ISP contract deliberately sends SOF ahead of pixels: video_in
// needs this interval to reset its asynchronous FIFO. signal_delay preserves
// the legacy line buffer; O_tlast accompanies the final valid output group.
// This is a free-running camera pipeline, not an AXI skid/backpressure buffer.
module pixel26_color_pipeline #(
    parameter integer IMG_HEIGHT=720, IMG_WIDTH=1280,
    parameter integer WB_ENABLE=1, TONE_ENABLE=1,
    parameter integer MIN_NEUTRAL=1024,
    parameter integer MIN_NEUTRAL_VALUE=64, MAX_NEUTRAL_VALUE=247,
    parameter integer GAIN_MIN=192, GAIN_MAX=384,
    parameter integer DIAGNOSTICS=0
) (
    input wire I_clk,I_rst_n,I_tlast,I_tuser,
    input wire [95:0] I_tdata,
    input wire I_tvalid,
    output wire I_tready,
    output wire O_tlast,O_tuser,
    output wire [95:0] O_tdata,
    output wire O_tvalid,
    input wire O_tready,
    input wire [31:0] I_diag_frame_id,
    output wire [95:0] O_diag_pre_wb,O_diag_post_wb,
    output wire [8:0] O_diag_gain_r,O_diag_gain_b,
    output wire [31:0] O_diag_pixel_id,O_diag_stats_id,
    output wire O_diag_stats_done,O_diag_stats_good,
    output wire [20:0] O_diag_neutral_count
);
    localparam integer GROUPS=IMG_WIDTH/4, TOTAL=GROUPS*IMG_HEIGHT;
    wire [8:0] gain_r=9'd304,gain_b=9'd333;
    reg [8:0] next_gain_r,next_gain_b;
    reg active,bad,complete,pending,drop_frame;
    reg [20:0] groups_seen,neutral_count;
    reg [12:0] line_groups,lines_seen;
    reg [27:0] sum_r,sum_g,sum_b;
    reg [27:0] saved_r,saved_g,saved_b;
    reg [36:0] weighted_r,weighted_b,target_g,tolerance;
    reg [1:0] update_stage;
    reg [9:0] add_r,add_g,add_b;
    reg [2:0] add_count;
    // Statistics are independent of the unchanged54-cycle pixel path.
    // A: per-lane min/max. B: neutral qualification. C: pair sums.
    // D: four-lane sum. Frame controls follow the same four registers, so
    // neither a simultaneous first group nor the final group is omitted.
    reg [3:0] stats_valid_pipe,stats_sof_pipe,stats_eol_pipe,stats_bad_sof_pipe;
    wire interrupted_tail;
    wire stats_valid=stats_valid_pipe[3],stats_sof=stats_sof_pipe[3],stats_eol=stats_eol_pipe[3];
    wire stats_bad_sof=stats_bad_sof_pipe[3];
    reg [7:0] raw_r[0:3],raw_g[0:3],raw_b[0:3],minimum_a[0:3],maximum_a[0:3];
    reg [7:0] selected_r[0:3],selected_g[0:3],selected_b[0:3];
    reg selected_count[0:3];
    reg [8:0] pair_r[0:1],pair_g[0:1],pair_b[0:1];
    reg [1:0] pair_count[0:1];
    function [7:0] minimum3;
        input [7:0] r,g,b;
        reg [7:0] rg;
        begin rg=r<g ? r : g;minimum3=rg<b ? rg : b;end
    endfunction
    function [7:0] maximum3;
        input [7:0] r,g,b;
        reg [7:0] rg;
        begin rg=r>g ? r : g;maximum3=rg>b ? rg : b;end
    endfunction
    wire [3:0] neutral_a;
    genvar n;
    generate for(n=0;n<4;n=n+1)begin: neutral_qualification
        assign neutral_a[n]=minimum_a[n]>=MIN_NEUTRAL_VALUE && maximum_a[n]<=MAX_NEUTRAL_VALUE &&
            ({1'b0,maximum_a[n]}-{1'b0,minimum_a[n]})<=(maximum_a[n]>>2);
    end endgenerate
    integer lane,pair_index;
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin
            stats_valid_pipe<=0;stats_sof_pipe<=0;stats_eol_pipe<=0;stats_bad_sof_pipe<=0;
            add_r<=0;add_g<=0;add_b<=0;add_count<=0;
            for(lane=0;lane<4;lane=lane+1)begin
                raw_r[lane]<=0;raw_g[lane]<=0;raw_b[lane]<=0;minimum_a[lane]<=0;maximum_a[lane]<=0;
                selected_r[lane]<=0;selected_g[lane]<=0;selected_b[lane]<=0;selected_count[lane]<=0;
            end
            for(pair_index=0;pair_index<2;pair_index=pair_index+1)begin
                pair_r[pair_index]<=0;pair_g[pair_index]<=0;pair_b[pair_index]<=0;pair_count[pair_index]<=0;
            end
        end else begin
            stats_valid_pipe<={stats_valid_pipe[2:0],I_tvalid};
            stats_sof_pipe<={stats_sof_pipe[2:0],I_tuser};
            stats_eol_pipe<={stats_eol_pipe[2:0],I_tlast};
            stats_bad_sof_pipe<={stats_bad_sof_pipe[2:0],I_tuser && interrupted_tail};
            for(lane=0;lane<4;lane=lane+1)begin
                if(I_tvalid)begin
                    raw_r[lane]<=I_tdata[lane*24+16+:8];raw_g[lane]<=I_tdata[lane*24+8+:8];raw_b[lane]<=I_tdata[lane*24+:8];
                    minimum_a[lane]<=minimum3(I_tdata[lane*24+16+:8],I_tdata[lane*24+8+:8],I_tdata[lane*24+:8]);
                    maximum_a[lane]<=maximum3(I_tdata[lane*24+16+:8],I_tdata[lane*24+8+:8],I_tdata[lane*24+:8]);
                end
                if(stats_valid_pipe[0])begin
                    selected_r[lane]<=neutral_a[lane] ? raw_r[lane] : 0;
                    selected_g[lane]<=neutral_a[lane] ? raw_g[lane] : 0;
                    selected_b[lane]<=neutral_a[lane] ? raw_b[lane] : 0;
                    selected_count[lane]<=neutral_a[lane];
                end
            end
            if(stats_valid_pipe[1])begin
                for(pair_index=0;pair_index<2;pair_index=pair_index+1)begin
                    pair_r[pair_index]<={1'b0,selected_r[2*pair_index]}+{1'b0,selected_r[2*pair_index+1]};
                    pair_g[pair_index]<={1'b0,selected_g[2*pair_index]}+{1'b0,selected_g[2*pair_index+1]};
                    pair_b[pair_index]<={1'b0,selected_b[2*pair_index]}+{1'b0,selected_b[2*pair_index+1]};
                    pair_count[pair_index]<={1'b0,selected_count[2*pair_index]}+{1'b0,selected_count[2*pair_index+1]};
                end
            end
            if(stats_valid_pipe[2])begin
                add_r<={1'b0,pair_r[0]}+{1'b0,pair_r[1]};add_g<={1'b0,pair_g[0]}+{1'b0,pair_g[1]};
                add_b<={1'b0,pair_b[0]}+{1'b0,pair_b[1]};add_count<={1'b0,pair_count[0]}+{1'b0,pair_count[1]};
            end
        end
    end

    reg [95:0] input_d0,input_d1;
    reg input_valid_d0,input_valid_d1;
    wire [95:0] delayed_data;
    wire delayed_valid,unused_delayed_sof;
    reg valid_m,valid_s,valid_o,last_o;
    reg [16:0] product_r[0:3],product_b[0:3];
    reg [7:0] green_m[0:3];
    reg [95:0] saturated_data,output_data;
    // A new SOF during old delayed output is a truncated frame boundary.
    // Discard the entire incoming frame instead of changing gains mid-tail.
    assign interrupted_tail=delayed_valid || valid_m || valid_s || valid_o ||
                          input_valid_d0 || input_valid_d1;
    // Pixel suppression is immediate at rawSOF; do not wait for statistics.
    always @(posedge I_clk or negedge I_rst_n)
        if(!I_rst_n)drop_frame<=0;
        else if(I_tuser)drop_frame<=interrupted_tail;
    wire current_active=active || stats_sof;
    wire [20:0] prior_groups=stats_sof ? 21'd0 : groups_seen;
    wire [12:0] prior_line_groups=stats_sof ? 13'd0 : line_groups;
    wire [12:0] prior_lines=stats_sof ? 13'd0 : lines_seen;
    wire [20:0] total_after=prior_groups+(stats_valid ? 1'b1 : 1'b0);
    wire [13:0] line_after={1'b0,prior_line_groups}+(stats_valid ? 1'b1 : 1'b0);
    wire geometry_bad=(stats_valid && (!current_active || prior_groups>=TOTAL || prior_line_groups>=GROUPS)) ||
                      (stats_eol && (!current_active || line_after!=GROUPS || prior_lines>=IMG_HEIGHT));
    wire ending=stats_eol && current_active && prior_lines==IMG_HEIGHT-1 &&
                line_after==GROUPS && total_after==TOTAL;

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            next_gain_r<=304;next_gain_b<=333;
            active<=0;bad<=0;complete<=0;pending<=0;
            groups_seen<=0;line_groups<=0;lines_seen<=0;neutral_count<=0;
            sum_r<=0;sum_g<=0;sum_b<=0;saved_r<=0;saved_g<=0;saved_b<=0;
            weighted_r<=0;weighted_b<=0;target_g<=0;tolerance<=0;update_stage<=0;
        end else begin
            if(stats_sof) begin
                if(WB_ENABLE && active && complete && !bad && pending && !stats_bad_sof) begin
                    // Fixed field WB; neutral statistics never change gains.
                end
                active<=1;bad<=stats_bad_sof;
                complete<=0;pending<=0;update_stage<=0;
                groups_seen<=stats_valid ? 1 : 0;
                line_groups<=stats_eol ? 0 : (stats_valid ? 1 : 0);
                lines_seen<=stats_eol ? 1 : 0;
                neutral_count<=stats_valid ? add_count : 0;
                sum_r<=stats_valid ? add_r : 0;sum_g<=stats_valid ? add_g : 0;sum_b<=stats_valid ? add_b : 0;
                if(geometry_bad)bad<=1;
            end else begin
                if(geometry_bad)begin bad<=1;pending<=0;end
                if(stats_valid && active) begin
                    if(groups_seen<TOTAL+1)groups_seen<=groups_seen+1'b1;
                    if(line_groups<GROUPS+1)line_groups<=line_groups+1'b1;
                    if(groups_seen<TOTAL) begin
                        neutral_count<=neutral_count+add_count;
                        sum_r<=sum_r+add_r;sum_g<=sum_g+add_g;sum_b<=sum_b+add_b;
                    end
                end
                if(stats_eol && active) begin
                    line_groups<=0;
                    if(lines_seen<IMG_HEIGHT+1)lines_seen<=lines_seen+1'b1;
                end
                if(ending && !bad && !geometry_bad) begin
                    complete<=1;
                    if(neutral_count+(stats_valid ? add_count : 0)>=MIN_NEUTRAL) begin
                        saved_r<=sum_r+(stats_valid ? add_r : 0);
                        saved_g<=sum_g+(stats_valid ? add_g : 0);
                        saved_b<=sum_b+(stats_valid ? add_b : 0);
                        update_stage<=1;
                    end
                end else if(update_stage==1) begin
                    weighted_r<=saved_r*gain_r;weighted_b<=saved_b*gain_b;
                    target_g<={1'b0,saved_g,8'd0};
                    tolerance<={7'd0,saved_g,2'd0}; // 1/64 of target: deadband
                    update_stage<=2;
                end else if(update_stage==2) begin
                    next_gain_r<=gain_r;next_gain_b<=gain_b;
                    if(weighted_r+tolerance<target_g && gain_r<GAIN_MAX)next_gain_r<=gain_r+1'b1;
                    else if(weighted_r>target_g+tolerance && gain_r>GAIN_MIN)next_gain_r<=gain_r-1'b1;
                    if(weighted_b+tolerance<target_g && gain_b<GAIN_MAX)next_gain_b<=gain_b+1'b1;
                    else if(weighted_b>target_g+tolerance && gain_b>GAIN_MIN)next_gain_b<=gain_b-1'b1;
                    pending<=!bad;update_stage<=0;
                end
            end
        end
    end

    // The two input registers and the original 50-cycle line RAM retain
    // sufficient pre-data SOF lead for the existing DDR input FIFO reset.
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin input_d0<=0;input_d1<=0;input_valid_d0<=0;input_valid_d1<=0;end
        else begin
            input_d0<=I_tdata;input_valid_d0<=I_tvalid;
            input_d1<=I_tuser ? 0 : input_d0;
            input_valid_d1<=I_tuser ? 0 : input_valid_d0;
        end
    end
    signal_delay #(.IMG_HEIGHT(IMG_HEIGHT),.IMG_WIDTH(IMG_WIDTH),.DATA_WIDTH(96),.DELAY_CYCLE(50)) delay_pixels(
        .I_clk(I_clk),.I_rst_n(I_rst_n),.I_tuser(I_tuser),
        .I_valid(input_valid_d1),.I_data(input_d1),
        .O_valid(delayed_valid),.O_data(delayed_data),.O_tuser(unused_delayed_sof));

    // Piecewise interpolation of y=255*(x/255)^0.7. Full 0..255 range.
    // Empirical tone candidate only; it is not calibrated sRGB or a CCM.
    function [7:0] tone07;
        input [7:0] value;
        reg [7:0] base;
        reg [11:0] nibble,interpolation;
        begin
            nibble={8'd0,value[3:0]};
            // All slopes are constants. Spell out exact shift/add products
            // so twelve channel instances do not infer twelve tiny DSPs.
            case(value[7:4])
                0:begin base=0;interpolation=(nibble<<5)+(nibble<<2)+nibble;end
                1:begin base=37;interpolation=(nibble<<4)+(nibble<<2)+(nibble<<1)+nibble;end
                2:begin base=60;interpolation=(nibble<<4)+(nibble<<1)+nibble;end
                3:begin base=79;interpolation=(nibble<<4)+(nibble<<1);end
                4:begin base=97;interpolation=nibble<<4;end
                5:begin base=113;interpolation=nibble<<4;end
                6:begin base=129;interpolation=(nibble<<3)+(nibble<<2)+(nibble<<1);end
                7:begin base=143;interpolation=(nibble<<3)+(nibble<<2)+(nibble<<1);end
                8:begin base=157;interpolation=(nibble<<3)+(nibble<<2)+(nibble<<1);end
                9:begin base=171;interpolation=(nibble<<3)+(nibble<<2)+nibble;end
                10:begin base=184;interpolation=(nibble<<3)+(nibble<<2)+nibble;end
                11:begin base=197;interpolation=(nibble<<3)+(nibble<<2);end
                12:begin base=209;interpolation=(nibble<<3)+(nibble<<2);end
                13:begin base=221;interpolation=(nibble<<3)+(nibble<<2);end
                14:begin base=233;interpolation=(nibble<<3)+(nibble<<1)+nibble;end
                default:begin base=244;interpolation=(nibble<<3)+(nibble<<1)+nibble;end
            endcase
            interpolation=interpolation+8;
            tone07=value==255 ? 255 : base+(interpolation>>4);
        end
    endfunction
    function [7:0] clamp_gain;
        input [16:0] value;
        begin clamp_gain=value[16] ? 8'd255 : value[15:8];end
    endfunction
    integer p,c;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            valid_m<=0;valid_s<=0;valid_o<=0;last_o<=0;
            saturated_data<=0;output_data<=0;
            for(p=0;p<4;p=p+1)begin product_r[p]<=0;product_b[p]<=0;green_m[p]<=0;end
        end else if(I_tuser || drop_frame) begin
            valid_m<=0;valid_s<=0;valid_o<=0;last_o<=0;
            saturated_data<=0;output_data<=0;
        end else begin
            valid_m<=delayed_valid;valid_s<=valid_m;valid_o<=valid_s;
            last_o<=valid_s && !valid_m;
            for(p=0;p<4;p=p+1) begin
                if(delayed_valid) begin
                    product_r[p]<=delayed_data[p*24+16+:8]*(WB_ENABLE ? gain_r : 9'd256);
                    product_b[p]<=delayed_data[p*24+:8]*(WB_ENABLE ? gain_b : 9'd256);
                    green_m[p]<=delayed_data[p*24+8+:8];
                end
                if(valid_m) saturated_data[p*24+:24]<={clamp_gain(product_r[p]),green_m[p],clamp_gain(product_b[p])};
            end
            for(c=0;c<12;c=c+1)
                output_data[c*8+:8]<=valid_s ? (TONE_ENABLE ? tone07(saturated_data[c*8+:8]) : saturated_data[c*8+:8]) : 0;
        end
    end
    assign I_tready=O_tready;
    assign O_tuser=I_tuser;
    assign O_tvalid=valid_o;
    assign O_tlast=last_o;
    assign O_tdata=valid_o ? output_data : 96'd0;
    // Diagnostic taps are parallel registers; they do not enter the video path.
    // delayed_data is the pre-WB value of the same pixel as product_r/b.
    generate if(DIAGNOSTICS) begin : observation
        reg [95:0] pre_m,pre_s,pre_o,post_o;
        reg [8:0] gr_m,gr_s,gr_o,gb_m,gb_s,gb_o;
        reg [31:0] raw_id,stats_id0,stats_id1,stats_id2,stats_id3;
        reg [31:0] id_m,id_s,id_o,stats_result_id;
        reg stats_event,stats_good;
        reg diag_id_bad;
        reg [20:0] final_neutral;
        always @(posedge I_clk or negedge I_rst_n)begin
            if(!I_rst_n)begin
                pre_m<=0;pre_s<=0;pre_o<=0;post_o<=0;
                gr_m<=0;gr_s<=0;gr_o<=0;gb_m<=0;gb_s<=0;gb_o<=0;
                raw_id<=0;stats_id0<=0;stats_id1<=0;stats_id2<=0;stats_id3<=0;
                id_m<=0;id_s<=0;id_o<=0;stats_result_id<=0;
                stats_event<=0;stats_good<=0;final_neutral<=0;diag_id_bad<=0;
            end else begin
                stats_id0<=I_diag_frame_id;stats_id1<=stats_id0;stats_id2<=stats_id1;stats_id3<=stats_id2;
                if(I_tuser)begin raw_id<=I_diag_frame_id;diag_id_bad<=0;end
                else if(I_tvalid && I_diag_frame_id!=raw_id)diag_id_bad<=1;
                stats_event<=0;
                if(ending)begin
                    stats_event<=1;stats_good<=!bad && !geometry_bad && !stats_bad_sof && !diag_id_bad && stats_id3==raw_id;
                    stats_result_id<=stats_id3;
                    final_neutral<=neutral_count+(stats_valid ? add_count : 0);
                end
                if(I_tuser || drop_frame)begin
                    pre_m<=0;pre_s<=0;pre_o<=0;post_o<=0;
                    id_m<=0;id_s<=0;id_o<=0;
                end else begin
                    if(delayed_valid)begin
                        pre_m<=delayed_data;gr_m<=WB_ENABLE ? gain_r:9'd256;gb_m<=WB_ENABLE ? gain_b:9'd256;id_m<=raw_id;
                    end
                    if(valid_m)begin pre_s<=pre_m;gr_s<=gr_m;gb_s<=gb_m;id_s<=id_m;end
                    if(valid_s)begin pre_o<=pre_s;post_o<=saturated_data;gr_o<=gr_s;gb_o<=gb_s;id_o<=id_s;end
                end
            end
        end
        assign O_diag_pre_wb=valid_o ? pre_o:96'd0;
        assign O_diag_post_wb=valid_o ? post_o:96'd0;
        assign O_diag_gain_r=gr_o;assign O_diag_gain_b=gb_o;assign O_diag_pixel_id=id_o;
        assign O_diag_stats_done=stats_event;assign O_diag_stats_good=stats_good;
        assign O_diag_stats_id=stats_result_id;assign O_diag_neutral_count=final_neutral;
    end else begin : no_observation
        assign O_diag_pre_wb=0;assign O_diag_post_wb=0;assign O_diag_gain_r=0;assign O_diag_gain_b=0;
        assign O_diag_pixel_id=0;assign O_diag_stats_done=0;assign O_diag_stats_good=0;
        assign O_diag_stats_id=0;assign O_diag_neutral_count=0;
    end endgenerate
    initial begin
        if(IMG_WIDTH%4!=0 || GROUPS<64 || IMG_HEIGHT<1 || IMG_WIDTH>8192 || IMG_HEIGHT>1024 ||
           TOTAL>262144 || MIN_NEUTRAL<1 || MIN_NEUTRAL_VALUE<0 || MAX_NEUTRAL_VALUE>255 ||
           GAIN_MIN<1 || GAIN_MIN>256 || GAIN_MAX<256 || GAIN_MAX>511)
            $error("pixel14_color_pipeline parameter error");
    end
endmodule
