// Once-per-frame shared engine. Unreset memories are seeded before any use.
module pixel310_spatial_cal #(
    parameter integer STABLE_FRAMES=16,MAX_CAL_FRAMES=600,ANCHOR_TOLERANCE=8
)(
    input wire clk,rst_n,restart,enable,frame_sof,allow_commit,
    input wire stats_event,stats_good,
    input wire [215:0] means,
    input wire [62:0] high_counts,
    output reg [242:0] coefficients,
    output reg locked,failed,
    output wire [5:0] status
);
    localparam IDLE=0,QUALIFY=1,STORE=2,LOAD_NODE=3,DIV_START=4,DIVIDE=5;
    (* ram_style="distributed" *) reg [7:0] anchors[0:26];
    (* ram_style="distributed" *)
    reg [11:0] sums[0:26];
    reg [7:0] stable_count;
    reg [9:0] age;
    reg [2:0] state;
    reg [4:0] index;
    reg [3:0] node;
    reg [1:0] component;
    reg [7:0] node_min,node_max,node_r,node_g,node_b;
    reg frame_valid,frame_stable,seed;
    reg [4:0] bit_index;
    reg [15:0] numerator,quotient;
    reg [7:0] divisor;
    reg [8:0] remainder;
    reg [242:0] pending_coefficients;
    reg pending,pending_fail;
    wire [8:0] shifted_remainder={remainder[7:0],numerator[bit_index]};
    wire subtract=shifted_remainder>={1'b0,divisor};
    wire [15:0] next_quotient=quotient | (subtract ? (16'd1<<bit_index):16'd0);
    wire [23:0] node_means[0:8];
    wire [6:0] node_high[0:8];
    genvar g;
    generate for(g=0;g<9;g=g+1)begin: fixed_words
        assign node_means[g]=means[g*24+:24];
        assign node_high[g]=high_counts[g*7+:7];
    end endgenerate
    wire [23:0] current_means=node_means[node];
    wire [7:0] value=component==0 ? current_means[23:16]:
                     component==1 ? current_means[15:8]:current_means[7:0];
    wire [7:0] anchor=anchors[index];
    wire [11:0] sum=sums[index];
    wire [7:0] average=(sum+12'd8)>>4;
    wire [7:0] low=component==0 || value<node_min ? value:node_min;
    wire [7:0] high=component==0 || value>node_max ? value:node_max;
    wire valid_value=value>=32 && value<=240;
    wire stable_value={1'b0,value}+ANCHOR_TOLERANCE>={1'b0,anchor} &&
                      {1'b0,anchor}+ANCHOR_TOLERANCE>={1'b0,value};
    wire valid_node=component!=2 || ({1'b0,high}<={low,1'b0} && node_high[node]==0);
    wire valid_final=frame_valid && valid_value && valid_node;
    wire stable_final=frame_stable && stable_value;
    wire [7:0] rg=node_r<node_g ? node_r:node_g;
    wire [7:0] target=rg<node_b ? rg:node_b;
    wire [7:0] channel_mean=component==0 ? node_r:component==1 ? node_g:node_b;
    assign status={3'd0,enable && !locked && !failed,failed,locked};
    always @(posedge clk)begin
        if(!restart && state==STORE && enable && !frame_sof)begin
            sums[index]<=seed ? {4'd0,value}:sum+value;
            if(seed)anchors[index]<=value;
        end
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            coefficients<={27{9'd256}};pending_coefficients<={27{9'd256}};
            locked<=0;failed<=0;pending<=0;pending_fail<=0;
            stable_count<=0;age<=0;state<=IDLE;index<=0;node<=0;component<=0;bit_index<=0;
            node_min<=0;node_max<=0;node_r<=0;node_g<=0;node_b<=0;
            frame_valid<=0;frame_stable<=0;seed<=0;
            numerator<=0;quotient<=0;divisor<=1;remainder<=0;
        end else if(restart)begin
            coefficients<={27{9'd256}};pending_coefficients<={27{9'd256}};
            locked<=0;failed<=0;pending<=0;pending_fail<=0;
            stable_count<=0;age<=0;state<=IDLE;index<=0;node<=0;component<=0;bit_index<=0;
            node_min<=0;node_max<=0;node_r<=0;node_g<=0;node_b<=0;
            frame_valid<=0;frame_stable<=0;seed<=0;
            numerator<=0;quotient<=0;divisor<=1;remainder<=0;
        end else if(!enable)begin
            if(frame_sof && allow_commit)begin coefficients<={27{9'd256}};locked<=0;failed<=0;end
            pending<=0;pending_fail<=0;
            stable_count<=0;age<=0;state<=IDLE;
        end else if(frame_sof && !allow_commit && !locked && !failed)begin
            stable_count<=0;pending<=0;pending_fail<=0;state<=IDLE;
        end else if(frame_sof && allow_commit && pending && !locked && !failed)begin
            pending<=0;state<=IDLE;
            if(pending_fail)begin coefficients<={27{9'd256}};failed<=1;end
            else begin coefficients<=pending_coefficients;locked<=1;end
        end else if(!locked && !failed && !pending)begin
            if(stats_event)begin
                if(age<MAX_CAL_FRAMES)age<=age+1'b1;
                if(age>=MAX_CAL_FRAMES-1)begin
                    pending<=1;pending_fail<=1;state<=IDLE;stable_count<=0;
                end else if(state!=IDLE || !stats_good)begin
                    state<=IDLE;stable_count<=0;
                end else begin
                    state<=QUALIFY;index<=0;node<=0;component<=0;
                    frame_valid<=1;frame_stable<=1;node_min<=0;node_max<=0;
                end
            end else case(state)
                QUALIFY:begin
                    frame_valid<=valid_final;frame_stable<=stable_final;node_min<=low;node_max<=high;
                    if(index==26)begin
                        if(!valid_final)begin state<=IDLE;stable_count<=0;end
                        else begin
                            seed<=stable_count==0 || !stable_final;
                            state<=STORE;index<=0;node<=0;component<=0;
                        end
                    end else begin
                        index<=index+1'b1;
                        if(component==2)begin component<=0;node<=node+1'b1;end
                        else component<=component+1'b1;
                    end
                end
                STORE:begin
                    if(index==26)begin
                        index<=0;node<=0;component<=0;
                        stable_count<=seed ? 1:stable_count+1'b1;
                        if(!seed && stable_count==15)state<=LOAD_NODE;
                        else state<=IDLE;
                    end else begin
                        index<=index+1'b1;
                        if(component==2)begin component<=0;node<=node+1'b1;end
                        else component<=component+1'b1;
                    end
                end
                LOAD_NODE:begin
                    if(component==0)node_r<=average;
                    else if(component==1)node_g<=average;
                    else node_b<=average;
                    if(component==2)begin component<=0;index<=index-2;state<=DIV_START;end
                    else begin component<=component+1'b1;index<=index+1'b1;end
                end
                DIV_START:begin
                    numerator<={target,8'd0}+{9'd0,channel_mean[7:1]};
                    divisor<=channel_mean;quotient<=0;remainder<=0;bit_index<=15;state<=DIVIDE;
                end
                DIVIDE:begin
                    remainder<=subtract ? shifted_remainder-{1'b0,divisor}:shifted_remainder;
                    quotient<=next_quotient;
                    if(bit_index==0)begin
                        if(next_quotient<128 || next_quotient>256 || divisor==0)begin
                            pending<=1;pending_fail<=1;state<=IDLE;
                        end else begin
                            // Process channels in ascending order. After27
                            // shifts channel0 is the least-significant word.
                            pending_coefficients<={next_quotient[8:0],pending_coefficients[242:9]};
                            if(index==26)begin pending<=1;pending_fail<=0;state<=IDLE;end
                            else begin
                                index<=index+1'b1;
                                if(component==2)begin node<=node+1'b1;component<=0;state<=LOAD_NODE;end
                                else begin component<=component+1'b1;state<=DIV_START;end
                            end
                        end
                    end else bit_index<=bit_index-1'b1;
                end
            endcase
        end
    end
    // synthesis translate_off
    initial if(STABLE_FRAMES!=16 || MAX_CAL_FRAMES<18 || MAX_CAL_FRAMES>1023 ||
               ANCHOR_TOLERANCE<0 || ANCHOR_TOLERANCE>16)
        $fatal(1,"pixel282_spatial_cal unsupported calibration contract");
    // synthesis translate_on
endmodule
