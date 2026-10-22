// Scan one sampled angle/scale variant at a time, five classes in parallel.
// Each ROM word holds class bits 0..4. Address=variant*400+y*20+x.
// Capture remains the 32x32 contract with a centered 20x20 active area.
module pixel30_rotation_matcher #(
    parameter TEMPLATE_FILE="templates.mem",
    parameter integer VARIANTS=1,
    parameter integer MAX_DISTANCE=40,MIN_MARGIN=24,MIN_FG=16,MAX_FG=400,ENABLE_OUTPUT=0
) (
    input wire clk,rst_n,flush,frame_start,sample_valid,
    input wire [9:0] sample_index,
    input wire sample_foreground,frame_end,frame_good,frame_present,
    input wire [31:0] frame_id,
    input wire frame_source_test,
    output reg out_frame,out_healthy,out_present,out_valid,
    output reg [3:0] out_item,
    output reg [3:0] out_raw_winner,
    output reg [10:0] out_best,out_second,out_fg_count,
    output reg [31:0] out_frame_id,
    output reg out_source_test
);
    localparam integer WORDS=400*VARIANTS,AW=$clog2(WORDS);
    localparam [3:0] IDLE=0,CAPTURE=1,SCAN=2,DRAIN=3,RANK_START=4,RANK=5,MARGIN=6,EMIT=7;
    reg [3:0] state;
    reg [4:0] template_mem[0:WORDS-1];
    reg captured_mask[0:399];
    reg [AW-1:0] rom_address;
    reg [8:0] mask_address;
    reg [4:0] template_q;
    reg mask_q,read_valid,read_last,read_final;
    wire active_cell=sample_index[4:0]>=6 && sample_index[4:0]<26 &&
                     sample_index[9:5]>=6 && sample_index[9:5]<26;
    wire [8:0] write_address=(sample_index[9:5]-6)*20+(sample_index[4:0]-6);
    reg [10:0] sample_count,foreground_count;
    reg frame_bad,saved_good,saved_present,saved_source;
    reg [31:0] saved_id;
    reg [10:0] distance[0:4],class_best[0:4];
    reg [2:0] rank_index;
    reg [10:0] best,second,margin;
    reg [3:0] best_item;
    reg accepted;
    integer c;
    // No reset on either memory: the mask is fully written before a good scan.
    always @(posedge clk)begin
        if(rst_n && !flush && state==CAPTURE && sample_valid && !frame_start &&
           sample_count<1024 && active_cell)captured_mask[write_address]<=sample_foreground;
        if(state==SCAN)begin template_q<=template_mem[rom_address];mask_q<=captured_mask[mask_address];end
    end
    initial begin
        $readmemh(TEMPLATE_FILE,template_mem);
    end
    // synthesis translate_off
    integer verify;
    initial begin
        if(VARIANTS<1 || VARIANTS>256 || MAX_DISTANCE<0 || MAX_DISTANCE>400 || MIN_MARGIN<0 ||
           MIN_MARGIN>400 || MIN_FG<1 || MAX_FG>400 || MIN_FG>MAX_FG)
            $fatal(1,"pixel14_rotation_matcher invalid parameters");
        #0;
        for(verify=0;verify<WORDS;verify=verify+1)
            if((^template_mem[verify])===1'bx)$fatal(1,"rotation template missing word %0d",verify);
    end
    // synthesis translate_on
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;rom_address<=0;mask_address<=0;read_valid<=0;read_last<=0;read_final<=0;
            sample_count<=0;foreground_count<=0;frame_bad<=0;saved_good<=0;saved_present<=1;saved_source<=0;saved_id<=0;
            rank_index<=0;best<=1025;second<=1025;margin<=0;best_item<=0;accepted<=0;
            out_frame<=0;out_healthy<=0;out_present<=1;out_valid<=0;out_item<=0;
            out_raw_winner<=0;
            out_best<=0;out_second<=0;out_fg_count<=0;out_frame_id<=0;out_source_test<=0;
            for(c=0;c<5;c=c+1)begin distance[c]<=0;class_best[c]<=1025;end
        end else if(flush)begin
            state<=IDLE;read_valid<=0;sample_count<=0;foreground_count<=0;frame_bad<=0;
            out_frame<=0;out_healthy<=0;out_present<=1;out_valid<=0;out_item<=0;
            out_raw_winner<=0;
            out_best<=0;out_second<=0;out_fg_count<=0;
        end else begin
            out_frame<=0;read_valid<=0;
            if(frame_start)begin
                state<=CAPTURE;sample_count<=0;foreground_count<=0;
                frame_bad<=state!=IDLE || sample_valid || frame_end;
            end else if(frame_end)begin
                saved_good<=state==CAPTURE && frame_good && !frame_bad && sample_count==1024 && !sample_valid;
                saved_present<=frame_present;saved_source<=frame_source_test;saved_id<=frame_id;
                rom_address<=0;mask_address<=0;
                for(c=0;c<5;c=c+1)begin distance[c]<=0;class_best[c]<=1025;end
                if(state==CAPTURE && frame_good && !frame_bad && sample_count==1024 && !sample_valid)
                    state<=SCAN;
                else begin best<=1025;second<=1025;best_item<=0;state<=MARGIN;end
            end else case(state)
                CAPTURE: if(sample_valid)begin
                    if(sample_count>=1024 || {1'b0,sample_index}!=sample_count ||
                       (!active_cell && sample_foreground))frame_bad<=1;
                    if(sample_count<1025)sample_count<=sample_count+1'b1;
                    if(sample_count<1024)foreground_count<=foreground_count+sample_foreground;
                end
                SCAN,DRAIN: begin
                    if(sample_valid)begin
                        saved_good<=0;best<=1025;second<=1025;best_item<=0;state<=MARGIN;read_valid<=0;
                    end else begin
                        if(state==SCAN)begin
                            read_valid<=1;read_last<=mask_address==399;read_final<=rom_address==WORDS-1;
                            if(rom_address==WORDS-1)state<=DRAIN;
                            else begin
                                rom_address<=rom_address+1'b1;
                                mask_address<=mask_address==399 ? 0 : mask_address+1'b1;
                            end
                        end
                        if(read_valid)begin
                            for(c=0;c<5;c=c+1)begin
                                if(read_last)begin
                                    if(distance[c]+(mask_q^template_q[c])<class_best[c])
                                        class_best[c]<=distance[c]+(mask_q^template_q[c]);
                                    distance[c]<=0;
                                end else distance[c]<=distance[c]+(mask_q^template_q[c]);
                            end
                            if(read_final)state<=RANK_START;
                        end
                    end
                end
                RANK_START: begin rank_index<=0;best<=1025;second<=1025;best_item<=0;state<=RANK;end
                RANK: begin
                    if(class_best[rank_index]<best)begin
                        second<=best;best<=class_best[rank_index];best_item<=10+rank_index;
                    end else if(class_best[rank_index]<second)second<=class_best[rank_index];
                    if(rank_index==4)state<=MARGIN;else rank_index<=rank_index+1'b1;
                end
                MARGIN: begin
                    margin<=second-best;
                    accepted<=saved_good && saved_present && ENABLE_OUTPUT!=0 && foreground_count>=MIN_FG &&
                              foreground_count<=MAX_FG && best<=MAX_DISTANCE && second>best;
                    state<=EMIT;
                end
                EMIT: begin
                    state<=IDLE;out_frame<=1;out_healthy<=saved_good;
                    out_present<=saved_good ? saved_present : 1'b1;
                    out_valid<=accepted && margin>=MIN_MARGIN;
                    out_item<=accepted && margin>=MIN_MARGIN ? best_item : 0;
                    out_raw_winner<=best_item;
                    out_best<=best;out_second<=second;out_fg_count<=foreground_count;
                    out_frame_id<=saved_id;out_source_test<=saved_source;
                end
                default: begin end
            endcase
        end
    end
endmodule
