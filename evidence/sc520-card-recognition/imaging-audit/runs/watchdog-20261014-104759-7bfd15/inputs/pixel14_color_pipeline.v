// Task-local replacement for legacy prefix gray-world AWB.
// The private ISP contract deliberately sends SOF ahead of pixels: video_in
// needs this interval to reset its asynchronous FIFO. signal_delay preserves
// the legacy line buffer; O_tlast accompanies the final valid output group.
// This is a free-running camera pipeline, not an AXI skid/backpressure buffer.
module pixel14_color_pipeline #(
    parameter integer IMG_HEIGHT=720, IMG_WIDTH=1280,
    parameter integer WB_ENABLE=1, TONE_ENABLE=1,
    parameter integer MIN_NEUTRAL=1024,
    parameter integer MIN_NEUTRAL_VALUE=64, MAX_NEUTRAL_VALUE=247,
    parameter integer GAIN_MIN=192, GAIN_MAX=384
) (
    input wire I_clk,I_rst_n,I_tlast,I_tuser,
    input wire [95:0] I_tdata,
    input wire I_tvalid,
    output wire I_tready,
    output wire O_tlast,O_tuser,
    output wire [95:0] O_tdata,
    output wire O_tvalid,
    input wire O_tready
);
    localparam integer GROUPS=IMG_WIDTH/4, TOTAL=GROUPS*IMG_HEIGHT;
    reg [8:0] gain_r,gain_b,next_gain_r,next_gain_b;
    reg active,bad,complete,pending,drop_frame;
    reg [20:0] groups_seen,neutral_count;
    reg [12:0] line_groups,lines_seen;
    reg [27:0] sum_r,sum_g,sum_b;
    reg [27:0] saved_r,saved_g,saved_b;
    reg [36:0] weighted_r,weighted_b,target_g,tolerance;
    reg [1:0] update_stage;
    reg [9:0] add_r,add_g,add_b;
    reg [2:0] add_count;
    integer lane;
    reg [7:0] cr,cg,cb,cmin,cmax;
    always @* begin
        add_r=0;add_g=0;add_b=0;add_count=0;
        cr=0;cg=0;cb=0;cmin=0;cmax=0;
        for(lane=0;lane<4;lane=lane+1) begin
            cr=I_tdata[lane*24+16+:8];
            cg=I_tdata[lane*24+8+:8];
            cb=I_tdata[lane*24+:8];
            cmin=cr<cg ? cr : cg; if(cb<cmin)cmin=cb;
            cmax=cr>cg ? cr : cg; if(cb>cmax)cmax=cb;
            if(cmin>=MIN_NEUTRAL_VALUE && cmax<=MAX_NEUTRAL_VALUE &&
               ({1'b0,cmax}-{1'b0,cmin})<=(cmax>>2)) begin
                add_r=add_r+{2'd0,cr};add_g=add_g+{2'd0,cg};add_b=add_b+{2'd0,cb};
                add_count=add_count+1'b1;
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
    wire interrupted_tail=delayed_valid || valid_m || valid_s || valid_o ||
                          input_valid_d0 || input_valid_d1;
    wire current_active=active || I_tuser;
    wire [20:0] prior_groups=I_tuser ? 21'd0 : groups_seen;
    wire [12:0] prior_line_groups=I_tuser ? 13'd0 : line_groups;
    wire [12:0] prior_lines=I_tuser ? 13'd0 : lines_seen;
    wire [20:0] total_after=prior_groups+(I_tvalid ? 1'b1 : 1'b0);
    wire [13:0] line_after={1'b0,prior_line_groups}+(I_tvalid ? 1'b1 : 1'b0);
    wire geometry_bad=(I_tvalid && (!current_active || prior_groups>=TOTAL || prior_line_groups>=GROUPS)) ||
                      (I_tlast && (!current_active || line_after!=GROUPS || prior_lines>=IMG_HEIGHT));
    wire ending=I_tlast && current_active && prior_lines==IMG_HEIGHT-1 &&
                line_after==GROUPS && total_after==TOTAL;

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            gain_r<=256;gain_b<=256;next_gain_r<=256;next_gain_b<=256;
            active<=0;bad<=0;complete<=0;pending<=0;drop_frame<=0;
            groups_seen<=0;line_groups<=0;lines_seen<=0;neutral_count<=0;
            sum_r<=0;sum_g<=0;sum_b<=0;saved_r<=0;saved_g<=0;saved_b<=0;
            weighted_r<=0;weighted_b<=0;target_g<=0;tolerance<=0;update_stage<=0;
        end else begin
            if(I_tuser) begin
                if(WB_ENABLE && active && complete && !bad && pending && !interrupted_tail) begin
                    gain_r<=next_gain_r;gain_b<=next_gain_b;
                end
                active<=1;bad<=interrupted_tail;drop_frame<=interrupted_tail;
                complete<=0;pending<=0;update_stage<=0;
                groups_seen<=I_tvalid ? 1 : 0;
                line_groups<=I_tlast ? 0 : (I_tvalid ? 1 : 0);
                lines_seen<=I_tlast ? 1 : 0;
                neutral_count<=I_tvalid ? add_count : 0;
                sum_r<=I_tvalid ? add_r : 0;sum_g<=I_tvalid ? add_g : 0;sum_b<=I_tvalid ? add_b : 0;
                if(geometry_bad)bad<=1;
            end else begin
                if(geometry_bad)begin bad<=1;pending<=0;end
                if(I_tvalid && active) begin
                    if(groups_seen<TOTAL+1)groups_seen<=groups_seen+1'b1;
                    if(line_groups<GROUPS+1)line_groups<=line_groups+1'b1;
                    if(groups_seen<TOTAL) begin
                        neutral_count<=neutral_count+add_count;
                        sum_r<=sum_r+add_r;sum_g<=sum_g+add_g;sum_b<=sum_b+add_b;
                    end
                end
                if(I_tlast && active) begin
                    line_groups<=0;
                    if(lines_seen<IMG_HEIGHT+1)lines_seen<=lines_seen+1'b1;
                end
                if(ending && !bad && !geometry_bad) begin
                    complete<=1;
                    if(neutral_count+(I_tvalid ? add_count : 0)>=MIN_NEUTRAL) begin
                        saved_r<=sum_r+(I_tvalid ? add_r : 0);
                        saved_g<=sum_g+(I_tvalid ? add_g : 0);
                        saved_b<=sum_b+(I_tvalid ? add_b : 0);
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
    initial begin
        if(IMG_WIDTH%4!=0 || GROUPS<64 || IMG_HEIGHT<1 || IMG_WIDTH>8192 || IMG_HEIGHT>1024 ||
           TOTAL>262144 || MIN_NEUTRAL<1 || MIN_NEUTRAL_VALUE<0 || MAX_NEUTRAL_VALUE>255 ||
           GAIN_MIN<1 || GAIN_MIN>256 || GAIN_MAX<256 || GAIN_MAX>511)
            $error("pixel14_color_pipeline parameter error");
    end
endmodule
