// Pixel14-specific timing implementation. The protected card_matcher stays
// unchanged. Capture and rank use separate registers: ranking the completed
// frame does not prevent capture of the next frame after the usual drain gap.
module pixel14_card_matcher #(
    parameter TEMPLATE_FILE="templates.mem",
    parameter integer MAX_DISTANCE=40,MIN_MARGIN=24,MIN_FG=16,MAX_FG=850,ENABLE_OUTPUT=0,
    parameter integer TEMPLATES_PER_CLASS=1
) (
    input wire clk,rst_n,flush,frame_start,sample_valid,
    input wire [9:0] sample_index,
    input wire sample_foreground,frame_end,frame_good,frame_present,
    input wire [31:0] frame_id,
    input wire frame_source_test,
    output reg out_frame,out_healthy,out_present,out_valid,
    output reg [3:0] out_item,
    output reg [10:0] out_best,out_second,out_fg_count,
    output reg [31:0] out_frame_id,
    output reg out_source_test
);
    localparam [1:0] IDLE=0,CAPTURE=1,DRAIN=2;
    reg [1:0] state;
    localparam integer TEMPLATE_COUNT=5*TEMPLATES_PER_CLASS;
    reg [10:0] sample_count,foreground_count,distance[0:TEMPLATE_COUNT-1];
    reg frame_bad,pending_valid,pending_foreground,saved_good,saved_present,saved_source;
    reg [31:0] saved_id;
    wire rom_en=state==CAPTURE && sample_valid && !frame_start && !flush && rst_n && sample_count<1024;
    wire [TEMPLATE_COUNT-1:0] template_bits;
    pixel14_card_template_rom #(.TEMPLATE_FILE(TEMPLATE_FILE),.VARIANTS(TEMPLATES_PER_CLASS)) templates(
        .clk(clk),.en(rom_en),.addr(sample_index),.data(template_bits));
    integer c;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;sample_count<=0;foreground_count<=0;frame_bad<=0;
            pending_valid<=0;pending_foreground<=0;saved_good<=0;saved_present<=1;saved_source<=0;saved_id<=0;
            for(c=0;c<TEMPLATE_COUNT;c=c+1)distance[c]<=0;
        end else if(flush)begin
            state<=IDLE;sample_count<=0;foreground_count<=0;frame_bad<=0;pending_valid<=0;
            saved_good<=0;saved_present<=1;
            for(c=0;c<TEMPLATE_COUNT;c=c+1)distance[c]<=0;
        end else begin
            pending_valid<=0;
            if(frame_start)begin
                state<=CAPTURE;frame_bad<=state!=IDLE || sample_valid || frame_end;
                sample_count<=0;foreground_count<=0;
                for(c=0;c<TEMPLATE_COUNT;c=c+1)distance[c]<=0;
            end else if(state==CAPTURE)begin
                if(pending_valid)begin
                    for(c=0;c<TEMPLATE_COUNT;c=c+1)distance[c]<=distance[c]+(pending_foreground^template_bits[c]);
                    foreground_count<=foreground_count+pending_foreground;
                end
                if(sample_valid)begin
                    if(sample_count>=1024 || {1'b0,sample_index}!=sample_count)frame_bad<=1;
                    if(sample_count<1025)sample_count<=sample_count+1'b1;
                    pending_valid<=rom_en;pending_foreground<=sample_foreground;
                end
                if(frame_end)begin
                    saved_good<=frame_good && !frame_bad && sample_count==1024 && !sample_valid;
                    saved_present<=frame_present;saved_source<=frame_source_test;saved_id<=frame_id;
                    pending_valid<=0;state<=DRAIN;
                end
            end else if(state==DRAIN)state<=IDLE;
            else if(frame_end)begin
                saved_good<=0;saved_present<=1;saved_source<=frame_source_test;saved_id<=frame_id;
                foreground_count<=0;state<=DRAIN;
                for(c=0;c<TEMPLATE_COUNT;c=c+1)distance[c]<=0;
            end
        end
    end
    reg [1:0] rank_state;
    reg [$clog2(TEMPLATE_COUNT)-1:0] rank_index;
    reg [2:0] rank_class;
    reg [3:0] rank_variant;
    reg [10:0] rank_distance[0:TEMPLATE_COUNT-1],rank_foreground,best,second,margin,class_best;
    wire [10:0] class_distance=rank_distance[rank_index]<class_best ? rank_distance[rank_index] : class_best;
    reg [3:0] best_item;
    reg rank_good,rank_present,rank_source,threshold_ok;
    reg [31:0] rank_id;
    integer j;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            rank_state<=0;rank_index<=0;rank_class<=0;rank_variant<=0;class_best<=1025;
            rank_foreground<=0;best<=1025;second<=1025;margin<=0;best_item<=0;
            rank_good<=0;rank_present<=1;rank_source<=0;rank_id<=0;threshold_ok<=0;
            out_frame<=0;out_healthy<=0;out_present<=1;out_valid<=0;out_item<=0;
            out_best<=0;out_second<=0;out_fg_count<=0;out_frame_id<=0;out_source_test<=0;
            for(j=0;j<TEMPLATE_COUNT;j=j+1)rank_distance[j]<=0;
        end else if(flush)begin
            rank_state<=0;out_frame<=0;out_healthy<=0;out_present<=1;out_valid<=0;out_item<=0;
            out_best<=0;out_second<=0;out_fg_count<=0;
        end else begin
            out_frame<=0;
            if(state==DRAIN && !frame_start)begin
                if(rank_state!=0)begin
                    // No silently overwritten pending result. This cannot
                    // occur at supported image sample rates, but is fail-closed.
                    rank_state<=0;out_frame<=1;out_healthy<=0;out_present<=1;out_valid<=0;out_item<=0;
                    out_frame_id<=saved_id;out_source_test<=saved_source;out_best<=0;out_second<=0;out_fg_count<=0;
                end else begin
                    rank_state<=1;rank_index<=0;rank_class<=0;rank_variant<=0;class_best<=1025;
                    best<=1025;second<=1025;best_item<=0;
                    rank_good<=saved_good && !sample_valid && !frame_end;
                    rank_present<=saved_present;rank_source<=saved_source;rank_id<=saved_id;
                    rank_foreground<=foreground_count;
                    for(j=0;j<TEMPLATE_COUNT;j=j+1)rank_distance[j]<=distance[j];
                end
            end else if(rank_state==1)begin
                // Margin is between DIFFERENT classes, never two variants of
                // the same class. Rank serially to avoid a long comparator tree.
                if(rank_variant==TEMPLATES_PER_CLASS-1)begin
                    if(class_distance<best)begin
                        second<=best;best<=class_distance;best_item<=10+rank_class;
                    end else if(class_distance<second)second<=class_distance;
                    class_best<=1025;rank_variant<=0;
                    if(rank_class==4)rank_state<=2;
                    else begin rank_class<=rank_class+1'b1;rank_index<=rank_index+1'b1;end
                end else begin
                    class_best<=class_distance;rank_variant<=rank_variant+1'b1;rank_index<=rank_index+1'b1;
                end
            end else if(rank_state==2)begin
                margin<=second-best;
                threshold_ok<=rank_good && rank_present && ENABLE_OUTPUT!=0 &&
                    rank_foreground>=MIN_FG && rank_foreground<=MAX_FG && best<=MAX_DISTANCE && second>best;
                rank_state<=3;
            end else if(rank_state==3)begin
                rank_state<=0;out_frame<=1;out_healthy<=rank_good;out_present<=rank_good ? rank_present : 1'b1;
                out_valid<=threshold_ok && margin>=MIN_MARGIN;
                out_item<=threshold_ok && margin>=MIN_MARGIN ? best_item : 0;
                out_best<=best;out_second<=second;out_fg_count<=rank_foreground;
                out_frame_id<=rank_id;out_source_test<=rank_source;
            end
        end
    end
    // synthesis translate_off
    initial if(MAX_DISTANCE<0 || MAX_DISTANCE>1024 || MIN_MARGIN<0 || MIN_MARGIN>1024 ||
        MIN_FG<0 || MIN_FG>MAX_FG || MAX_FG>1024 || (ENABLE_OUTPUT!=0 && ENABLE_OUTPUT!=1) ||
        TEMPLATES_PER_CLASS<1 || TEMPLATES_PER_CLASS>9)
        $fatal(1,"pixel14_card_matcher invalid parameters");
    // synthesis translate_on
endmodule
