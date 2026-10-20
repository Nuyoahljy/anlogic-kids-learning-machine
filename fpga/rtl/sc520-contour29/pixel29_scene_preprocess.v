// T029 keeps the complete-glyph/background path and adds a bounded color
// contour pass. flags/fifo are reused after filtering; clean_mask stays 2-bit.
// Four same-frame normalized masks are emitted to the new geometry guard.
// The original capture health, paper/clip/presence and image latency stay local.
module pixel29_scene_preprocess #(
    parameter integer FRAME_WIDTH=320, FRAME_HEIGHT=180,
    parameter integer ROI_X=40, ROI_Y=30,
    parameter integer GRID_WIDTH=120, GRID_HEIGHT=60, SAMPLE_STEP=2,
    parameter integer BG_TOLERANCE=48, MIN_COMPONENT_PIXELS=12,
    parameter integer NORMAL_SIZE=20
) (
    input wire clk,rst_n,flush,
    input wire in_valid,in_sof,in_eol,
    input wire [10:0] in_x,
    input wire [9:0] in_y,
    input wire [23:0] in_rgb,
    input wire in_frame_end,in_frame_good,
    input wire [31:0] in_frame_id,
    input wire in_source_test,
    output reg replay_valid,replay_sof,replay_eol,
    output reg replay_glyph, // same-cycle filtered glyph, with existing scene eligibility gates
    output reg [10:0] replay_x,
    output reg [9:0] replay_y,
    output reg [23:0] replay_rgb,
    output reg replay_end,replay_good,replay_present,
    output reg [31:0] replay_id,
    output reg replay_source,
    output reg card_start,card_valid,
    output reg [9:0] card_index,
    output reg card_fg,card_end,card_good,card_present,
    output reg contour_fg,contour_axis_fg,full_axis_fg,
    output reg contour_qualified,contour_aspect_good,contour_boundary_repair,contour_exterior_ok,
    output reg [1:0] contour_color,
    output reg [31:0] card_id,
    output reg card_source,
    output reg out_revoke,
    output reg [15:0] dbg_scene_count,dbg_glyph_count,dbg_paper_count,
    output reg dbg_scene_event,
    output reg [3:0] dbg_scene_flags
);
    localparam integer N=GRID_WIDTH*GRID_HEIGHT;
    localparam integer AW=$clog2(N), CW=$clog2(N+1);
    localparam integer BORDER_PIXELS=2*GRID_WIDTH+2*GRID_HEIGHT-4;
    localparam integer NORMAL_ORIGIN=(32-NORMAL_SIZE)/2;
    localparam [6:0] NORMAL_DENOM=2*NORMAL_SIZE;
    localparam [6:0] P_IDLE=0,P_HIST=1,P_CLEAR=2,P_SEED=3,
        P_SEED_WAIT=4,P_SEED_CHECK=5,P_POP=6,P_POP_WAIT=7,P_POP_LOAD=8,
        P_NEIGHBOR=9,P_NEIGHBOR_WAIT=10,P_NEIGHBOR_CHECK=11,
        P_FILTER_BEGIN=12,P_FILTER_READ=13,P_FILTER_WAIT=14,P_FILTER_CHECK=15,
        P_FILTER_STORE=16,P_FINAL=17,P_REPLAY_READ=18,P_REPLAY_WAIT=19,
        P_REPLAY_EMIT=20,P_REPLAY_END=21,P_CARD_START=22,P_CARD_CALC=23,
        P_CARD_DIV=24,P_CARD_ADDR=25,P_CARD_WAIT=26,P_CARD_EMIT=27,
        P_CARD_END=28,P_FINISH=29,P_CARD_MUL=30,P_CARD_DIV_STEP=31,
        P_CT_SEED=32,P_CT_SEED_W0=33,P_CT_SEED_W1=34,P_CT_SEED_W2=35,P_CT_SEED_CHECK=36,
        P_CT_CENTER=37,P_CT_CENTER_WAIT=38,P_CT_CENTER_CHECK=39,
        P_CT_NEIGHBOR=40,P_CT_NW0=41,P_CT_NW1=42,P_CT_NW2=43,P_CT_NCHECK=44,P_CT_STORE=45,
        P_CT_CLEAR=46,P_CT_CLEAR_WAIT=47,P_CT_CLEAR_STORE=48,
        P_CT_SUM=49,P_CT_SUM_WAIT=50,P_CT_SUM_CHECK=51,P_CT_FINAL=52,P_CT_NORM_STORE=53;

    // Constant multipliers are expressed as shifts/adds deliberately. TD 6.2.1
    // mapped even y*120 and center*20 to DSP macros in the first candidate.
    function [AW-1:0] grid_address;
        input [10:0] x;
        input [9:0] y;
        reg [AW-1:0] total,term;
        integer bit_index;
        begin
            total=0;term=y;
            for(bit_index=0;bit_index<12;bit_index=bit_index+1)
                if((GRID_WIDTH>>bit_index)&1) total=total+(term<<bit_index);
            grid_address=total+x;
        end
    endfunction
    function signed [23:0] normal_base;
        input signed [13:0] center;
        reg signed [23:0] total,term;
        integer bit_index;
        begin
            total=0;term={{10{center[13]}},center};
            for(bit_index=0;bit_index<6;bit_index=bit_index+1)
                if((NORMAL_SIZE>>bit_index)&1) total=total+(term<<<bit_index);
            normal_base=total;
        end
    endfunction

    reg [23:0] rgb_bank0[0:N-1],rgb_bank1[0:N-1];
    reg [1:0] flags[0:N-1]; // bit 1 visited, bit 0 border-connected background
    reg [1:0] clean_mask[0:N-1]; // bit 1 glyph, bit 0 scene occupancy
    reg [AW-1:0] fifo[0:N-1];
    reg [15:0] hist_r0[0:15],hist_g0[0:15],hist_b0[0:15];
    reg [15:0] hist_r1[0:15],hist_g1[0:15],hist_b1[0:15];
    reg ready0,ready1,capture_active,capture_bank,process_bank;
    // All extrema belong to the same complete capture bank as RGB/histograms.
    reg signed [8:0] min_rg0,max_rg0,min_bg0,max_bg0;
    reg signed [8:0] min_rg1,max_rg1,min_bg1,max_bg1;
    wire signed [8:0] sample_rg=$signed({1'b0,in_rgb[23:16]})-$signed({1'b0,in_rgb[15:8]});
    wire signed [8:0] sample_bg=$signed({1'b0,in_rgb[7:0]})-$signed({1'b0,in_rgb[15:8]});
    wire signed [8:0] border_min_rg=process_bank ? min_rg1:min_rg0;
    wire signed [8:0] border_max_rg=process_bank ? max_rg1:max_rg0;
    wire signed [8:0] border_min_bg=process_bank ? min_bg1:min_bg0;
    wire signed [8:0] border_max_bg=process_bank ? max_bg1:max_bg0;
    reg [31:0] id0,id1,capture_id,capture_pixels;
    reg source0,source1,capture_source;
    reg [CW-1:0] capture_samples;
    reg [10:0] expected_x;
    reg [9:0] expected_y;
    reg [6:0] state;
    reg engine_fault,fault_reported;

    wire free0=!ready0 && !(state!=P_IDLE && !process_bank);
    wire free1=!ready1 && !(state!=P_IDLE && process_bank);
    wire new_sof=in_valid && in_sof;
    wire start_ok=new_sof && !capture_active && (free0 || free1) && !in_frame_end;
    wire selected_bank=start_ok ? !free0 : capture_bank;
    wire streaming=capture_active || start_ok;
    wire [31:0] current_pixels=start_ok ? 32'd0 : capture_pixels;
    wire raster_fault=(in_sof && !in_valid) || (in_eol && !in_valid) ||
        (new_sof && !start_ok) ||
        (capture_active && (in_frame_id!=capture_id || in_source_test!=capture_source)) ||
        (in_valid && (!streaming ||
            in_x!=(start_ok ? 11'd0 : expected_x) ||
            in_y!=(start_ok ? 10'd0 : expected_y) ||
            in_eol!=(in_x==FRAME_WIDTH-1) || current_pixels>=FRAME_WIDTH*FRAME_HEIGHT ||
            (!start_ok && (in_frame_id!=capture_id || in_source_test!=capture_source)))) ||
        (in_frame_end && (!capture_active || in_valid || in_sof || in_eol || !in_frame_good ||
            capture_pixels!=FRAME_WIDTH*FRAME_HEIGHT || capture_samples!=N ||
            in_frame_id!=capture_id || in_source_test!=capture_source));
    wire take_sample=in_valid && streaming &&
        in_x>=ROI_X && in_x<ROI_X+GRID_WIDTH*SAMPLE_STEP &&
        in_y>=ROI_Y && in_y<ROI_Y+GRID_HEIGHT*SAMPLE_STEP &&
        (in_x-ROI_X)%SAMPLE_STEP==SAMPLE_STEP/2 &&
        (in_y-ROI_Y)%SAMPLE_STEP==SAMPLE_STEP/2;
    wire [10:0] sample_x=(in_x-ROI_X)/SAMPLE_STEP;
    wire [9:0] sample_y=(in_y-ROI_Y)/SAMPLE_STEP;
    wire [AW-1:0] sample_address=grid_address(sample_x,sample_y);
    wire sample_border=sample_x==0 || sample_y==0 ||
        sample_x==GRID_WIDTH-1 || sample_y==GRID_HEIGHT-1;

    reg [AW-1:0] rgb_address,flag_address,mask_address,fifo_address;
    reg [23:0] rgb_q0,rgb_q1;
    wire [23:0] rgb_q=process_bank ? rgb_q1 : rgb_q0;
    reg [1:0] flag_q,mask_q;
    reg [AW-1:0] fifo_q;

    reg [4:0] hist_bin;
    reg [15:0] sum_r,sum_g,sum_b;
    reg found_r,found_g,found_b;
    reg [7:0] background_r,background_g,background_b;
    wire [15:0] hr=process_bank ? hist_r1[hist_bin[3:0]] : hist_r0[hist_bin[3:0]];
    wire [15:0] hg=process_bank ? hist_g1[hist_bin[3:0]] : hist_g0[hist_bin[3:0]];
    wire [15:0] hb=process_bank ? hist_b1[hist_bin[3:0]] : hist_b0[hist_bin[3:0]];
    function background_like;
        input [23:0] rgb;
        reg [8:0] dr,dg,db;
        reg signed [9:0] rg,bg,low_rg,high_rg,low_bg,high_bg;
        begin
            dr=rgb[23:16]>=background_r ? {1'b0,rgb[23:16]}-{1'b0,background_r} : {1'b0,background_r}-{1'b0,rgb[23:16]};
            dg=rgb[15:8]>=background_g ? {1'b0,rgb[15:8]}-{1'b0,background_g} : {1'b0,background_g}-{1'b0,rgb[15:8]};
            db=rgb[7:0]>=background_b ? {1'b0,rgb[7:0]}-{1'b0,background_b} : {1'b0,background_b}-{1'b0,rgb[7:0]};
            rg=$signed({2'b00,rgb[23:16]})-$signed({2'b00,rgb[15:8]});
            bg=$signed({2'b00,rgb[7:0]})-$signed({2'b00,rgb[15:8]});
            low_rg=$signed({border_min_rg[8],border_min_rg})-10'sd4;
            high_rg=$signed({border_max_rg[8],border_max_rg})+10'sd4;
            low_bg=$signed({border_min_bg[8],border_min_bg})-10'sd4;
            high_bg=$signed({border_max_bg[8],border_max_bg})+10'sd4;
            background_like=dr<=BG_TOLERANCE && dg<=BG_TOLERANCE && db<=BG_TOLERANCE &&
                rg>=low_rg && rg<=high_rg && bg>=low_bg && bg<=high_bg;
        end
    endfunction
    function glyph_pixel;
        input [23:0] rgb;
        reg [7:0] r,g,b,lo,hi;
        begin
            r=rgb[23:16];g=rgb[15:8];b=rgb[7:0];
            lo=r<g ? (r<b ? r:b) : (g<b ? g:b);
            hi=r>g ? (r>b ? r:b) : (g>b ? g:b);
            glyph_pixel=lo<180 || ({1'b0,hi}-{1'b0,lo})>=40;
        end
    endfunction

    reg [AW-1:0] scan_address,node_address,pending_address;
    reg [10:0] scan_x,node_x;
    reg [9:0] scan_y,node_y;
    reg [CW-1:0] fifo_head,fifo_tail;
    reg [1:0] neighbor;
    reg [3:0] filter_neighbor,scene_neighbors,glyph_neighbors;
    reg center_scene,center_glyph;
    reg [15:0] scene_count,glyph_count,background_seed_count,paper_count;
    reg [10:0] scene_left,scene_right,glyph_left,glyph_right;
    reg [9:0] scene_top,scene_bottom,glyph_top,glyph_bottom;
    reg scene_present,scene_clipped,paper_route;
    reg [11:0] glyph_width,glyph_height,glyph_side;
    reg [9:0] normalize_index;
    reg signed [23:0] numerator_x,numerator_y;
    reg [15:0] normalized_x,normalized_y;
    reg [5:0] mul_factor_x,mul_factor_y;
    reg [2:0] mul_step;
    reg signed [23:0] mul_term;
    reg [23:0] dividend_x,dividend_y;
    reg [6:0] remainder_x,remainder_y;
    reg [4:0] div_step;
    wire [6:0] trial_x={remainder_x[5:0],dividend_x[23]};
    wire [6:0] trial_y={remainder_y[5:0],dividend_y[23]};
    wire quotient_x=trial_x>=NORMAL_DENOM;
    wire quotient_y=trial_y>=NORMAL_DENOM;
    integer neighbor_x,neighbor_y,neighbor_linear;
    integer filter_x,filter_y,filter_linear;
    always @* begin
        neighbor_x=node_x;neighbor_y=node_y;
        case(neighbor)
            0: neighbor_x=node_x-1;
            1: neighbor_x=node_x+1;
            2: neighbor_y=node_y-1;
            default: neighbor_y=node_y+1;
        endcase
        neighbor_linear=grid_address(neighbor_x[10:0],neighbor_y[9:0]);
        filter_x=scan_x+(filter_neighbor%3)-1;
        filter_y=scan_y+(filter_neighbor/3)-1;
        filter_linear=grid_address(filter_x[10:0],filter_y[9:0]);
    end
    wire filtered_scene=center_scene && scene_neighbors>=3;
    wire filtered_glyph=center_glyph && glyph_neighbors>=3;
    wire has_object=scene_count>=MIN_COMPONENT_PIXELS &&
        scene_right>=scene_left+2 && scene_bottom>=scene_top+2;
    wire border_uncertain=background_seed_count*4<BORDER_PIXELS*3;
    // Reuse flags/fifo after the old filter. clean_mask stays two bits wide.
    reg ct_flood,ct_center_seed,ct_repair_boundary;
    reg signed [8:0] ct_center_rg,ct_center_bg;
    reg [3:0] ct_neighbor_seed,ct_neighbor_edge;
    reg [1:0] ct_neighbor_color[0:3];
    reg [15:0] ct_seed_count[0:2],ct_body_area,ct_exterior;
    reg [10:0] ct_left,ct_right;
    reg [9:0] ct_top,ct_bottom;
    reg [11:0] ct_width,ct_height,ct_side;
    reg [1:0] ct_norm_kind;
    reg ct_norm_bit,ct_full_fg,ct_body_fg,ct_body_axis_fg;
    reg signed [23:0] ct_mul_term_y;
    wire [1:0] ct_label;
    pixel26_classify_pipe ct_classifier(.clk(clk),.rst_n(rst_n),.flush(flush),.in_rgb(rgb_q),.color_id(ct_label));
    wire signed [8:0] ct_rg=$signed({1'b0,rgb_q[23:16]})-$signed({1'b0,rgb_q[15:8]});
    wire signed [8:0] ct_bg=$signed({1'b0,rgb_q[7:0]})-$signed({1'b0,rgb_q[15:8]});
    wire signed [9:0] ct_low_rg=$signed({border_min_rg[8],border_min_rg})-10'sd4;
    wire signed [9:0] ct_high_rg=$signed({border_max_rg[8],border_max_rg})+10'sd4;
    wire signed [9:0] ct_low_bg=$signed({border_min_bg[8],border_min_bg})-10'sd4;
    wire signed [9:0] ct_high_bg=$signed({border_max_bg[8],border_max_bg})+10'sd4;
    wire ct_distinct=$signed({ct_rg[8],ct_rg})<ct_low_rg || $signed({ct_rg[8],ct_rg})>ct_high_rg ||
        $signed({ct_bg[8],ct_bg})<ct_low_bg || $signed({ct_bg[8],ct_bg})>ct_high_bg;
    wire ct_seed=mask_q[1] && ct_label!=0 && ct_distinct;
    wire signed [9:0] ct_delta_rg=$signed({ct_rg[8],ct_rg})-$signed({ct_center_rg[8],ct_center_rg});
    wire signed [9:0] ct_delta_bg=$signed({ct_bg[8],ct_bg})-$signed({ct_center_bg[8],ct_center_bg});
    wire ct_edge=ct_delta_rg>=10'sd8 || ct_delta_rg<=-10'sd8 || ct_delta_bg>=10'sd8 || ct_delta_bg<=-10'sd8;
    wire ct_bridge=(ct_neighbor_seed[0] && ct_neighbor_seed[1] &&
        ct_neighbor_color[0]==ct_neighbor_color[1] && (ct_neighbor_edge[0] || ct_neighbor_edge[1])) ||
        (ct_neighbor_seed[2] && ct_neighbor_seed[3] &&
        ct_neighbor_color[2]==ct_neighbor_color[3] && (ct_neighbor_edge[2] || ct_neighbor_edge[3]));
    reg [1:0] ct_winner;
    reg [15:0] ct_winning_area;
    always @* begin
        ct_winner=0;ct_winning_area=0;
        if(ct_seed_count[0]>=12 && {1'b0,ct_seed_count[0]}>={ct_seed_count[1],1'b0} &&
            {1'b0,ct_seed_count[0]}>={ct_seed_count[2],1'b0})begin ct_winner=1;ct_winning_area=ct_seed_count[0];end
        else if(ct_seed_count[1]>=12 && {1'b0,ct_seed_count[1]}>={ct_seed_count[0],1'b0} &&
            {1'b0,ct_seed_count[1]}>={ct_seed_count[2],1'b0})begin ct_winner=2;ct_winning_area=ct_seed_count[1];end
        else if(ct_seed_count[2]>=12 && {1'b0,ct_seed_count[2]}>={ct_seed_count[0],1'b0} &&
            {1'b0,ct_seed_count[2]}>={ct_seed_count[1],1'b0})begin ct_winner=3;ct_winning_area=ct_seed_count[2];end
    end
    wire [17:0] ct_triple={1'b0,ct_winning_area,1'b0}+{2'b00,ct_winning_area};
    wire [17:0] ct_double={1'b0,ct_body_area,1'b0};
    wire ct_body_kind=ct_norm_kind==1 || ct_norm_kind==2;
    wire [10:0] ct_norm_left=ct_body_kind ? ct_left:glyph_left;
    wire [9:0] ct_norm_top=ct_body_kind ? ct_top:glyph_top;
    wire [10:0] ct_norm_right=ct_body_kind ? ct_right:glyph_right;
    wire [9:0] ct_norm_bottom=ct_body_kind ? ct_bottom:glyph_bottom;
    wire [11:0] ct_norm_width=ct_body_kind ? ct_width:glyph_width;
    wire [11:0] ct_norm_height=ct_body_kind ? ct_height:glyph_height;
    wire ct_axis=ct_norm_kind==2 || ct_norm_kind==3;
    wire [11:0] ct_span_x=ct_axis ? ct_norm_width:ct_body_kind ? ct_side:glyph_side;
    wire [11:0] ct_span_y=ct_axis ? ct_norm_height:ct_body_kind ? ct_side:glyph_side;
    reg flag_we,mask_we,fifo_we;
    reg [AW-1:0] flag_write_address,fifo_write_data;
    reg [1:0] flag_write_data;
    // The TD 6.2.1 RAM extractor must see one synchronous read register per
    // array and one write address/data port. A mux before the RGB read register
    // mapped both banks to DRAM in 110; multiple state-case writes mapped flags
    // to registers. Keep port selection outside these simple memory processes.
    always @* begin
        flag_we=0;mask_we=0;fifo_we=0;
        flag_write_address=scan_address;flag_write_data=0;fifo_write_data=scan_address;
        case(state)
            P_CLEAR: flag_we=1;
            P_SEED_CHECK: begin
                flag_we=1;flag_write_data=ct_flood ? {~flag_q[0],flag_q[0]} :
                    background_like(rgb_q) ? 2'b11 : 2'b10;
                fifo_we=(ct_flood ? !flag_q[0]:background_like(rgb_q)) && fifo_tail<N;
            end
            P_NEIGHBOR_CHECK: begin
                flag_we=!flag_q[1] && (!ct_flood || !flag_q[0]);flag_write_address=pending_address;
                flag_write_data=ct_flood ? 2'b10:background_like(rgb_q) ? 2'b11 : 2'b10;
                fifo_we=!flag_q[1] && (ct_flood ? !flag_q[0]:background_like(rgb_q)) && fifo_tail<N;
                fifo_write_data=pending_address;
            end
            P_FILTER_STORE: mask_we=1;
            P_CT_SEED_CHECK: begin flag_we=1;flag_write_data={ct_seed,ct_seed};end
            P_CT_STORE: begin flag_we=1;flag_write_data={ct_center_seed,ct_center_seed || ct_bridge};end
            P_CT_CLEAR_STORE: begin flag_we=1;flag_write_data={1'b0,flag_q[0]};end
            default: begin end
        endcase
    end
    wire memory_enable=rst_n && !flush && !raster_fault && !engine_fault;
    always @(posedge clk) begin
        rgb_q0<=rgb_bank0[rgb_address];
        if(memory_enable && take_sample && !selected_bank) rgb_bank0[sample_address]<=in_rgb;
    end
    always @(posedge clk) begin
        rgb_q1<=rgb_bank1[rgb_address];
        if(memory_enable && take_sample && selected_bank) rgb_bank1[sample_address]<=in_rgb;
    end
    always @(posedge clk) begin
        flag_q<=flags[flag_address];
        if(memory_enable && flag_we) flags[flag_write_address]<=flag_write_data;
    end
    always @(posedge clk) begin
        mask_q<=clean_mask[mask_address];
        if(memory_enable && mask_we) clean_mask[scan_address]<={filtered_glyph,filtered_scene};
    end
    always @(posedge clk) begin
        fifo_q<=fifo[fifo_address];
        if(memory_enable && fifo_we) fifo[fifo_tail[AW-1:0]]<=fifo_write_data;
    end

    task next_scan;
        begin
            scan_address<=scan_address+1'b1;
            if(scan_x==GRID_WIDTH-1) begin scan_x<=0;scan_y<=scan_y+1'b1;end
            else scan_x<=scan_x+1'b1;
        end
    endtask
    task next_neighbor;
        begin
            if(neighbor==3) state<=P_POP;
            else begin neighbor<=neighbor+1'b1;state<=P_NEIGHBOR;end
        end
    endtask
    task next_filter_neighbor;
        begin
            if(filter_neighbor==8) state<=P_FILTER_STORE;
            else begin filter_neighbor<=filter_neighbor+1'b1;state<=P_FILTER_READ;end
        end
    endtask
    task next_card_sample;
        begin
            if(normalize_index==1023) state<=P_CARD_END;
            else begin normalize_index<=normalize_index+1'b1;state<=P_CARD_CALC;end
        end
    endtask
    task next_contour_neighbor;
        begin
            if(neighbor==3)state<=P_CT_STORE;
            else begin neighbor<=neighbor+1'b1;state<=P_CT_NEIGHBOR;end
        end
    endtask

    integer k;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            ready0<=0;ready1<=0;capture_active<=0;capture_bank<=0;process_bank<=0;
            min_rg0<=0;max_rg0<=0;min_bg0<=0;max_bg0<=0;
            min_rg1<=0;max_rg1<=0;min_bg1<=0;max_bg1<=0;
            id0<=0;id1<=0;source0<=0;source1<=0;capture_id<=0;capture_source<=0;
            capture_pixels<=0;capture_samples<=0;expected_x<=0;expected_y<=0;
            state<=P_IDLE;engine_fault<=0;fault_reported<=0;
            rgb_address<=0;flag_address<=0;mask_address<=0;fifo_address<=0;
            hist_bin<=0;sum_r<=0;sum_g<=0;sum_b<=0;found_r<=0;found_g<=0;found_b<=0;
            background_r<=0;background_g<=0;background_b<=0;
            scan_address<=0;scan_x<=0;scan_y<=0;node_address<=0;node_x<=0;node_y<=0;pending_address<=0;
            fifo_head<=0;fifo_tail<=0;neighbor<=0;filter_neighbor<=0;scene_neighbors<=0;glyph_neighbors<=0;
            center_scene<=0;center_glyph<=0;scene_count<=0;glyph_count<=0;background_seed_count<=0;paper_count<=0;
            scene_left<=0;scene_right<=0;scene_top<=0;scene_bottom<=0;
            glyph_left<=0;glyph_right<=0;glyph_top<=0;glyph_bottom<=0;scene_present<=0;scene_clipped<=0;paper_route<=0;
            glyph_width<=0;glyph_height<=0;glyph_side<=0;normalize_index<=0;
            numerator_x<=0;numerator_y<=0;normalized_x<=0;normalized_y<=0;
            mul_factor_x<=0;mul_factor_y<=0;mul_step<=0;mul_term<=0;
            dividend_x<=0;dividend_y<=0;remainder_x<=0;remainder_y<=0;div_step<=0;
            replay_valid<=0;replay_sof<=0;replay_eol<=0;replay_glyph<=0;replay_x<=0;replay_y<=0;replay_rgb<=24'hffffff;
            replay_end<=0;replay_good<=0;replay_present<=1;replay_id<=0;replay_source<=0;
            card_start<=0;card_valid<=0;card_index<=0;card_fg<=0;card_end<=0;
            card_good<=0;card_present<=1;card_id<=0;card_source<=0;
            contour_fg<=0;contour_axis_fg<=0;full_axis_fg<=0;contour_qualified<=0;
            contour_aspect_good<=0;contour_boundary_repair<=0;contour_exterior_ok<=0;contour_color<=0;
            ct_flood<=0;ct_center_seed<=0;ct_repair_boundary<=0;ct_center_rg<=0;ct_center_bg<=0;
            ct_neighbor_seed<=0;ct_neighbor_edge<=0;ct_body_area<=0;ct_exterior<=0;
            ct_left<=0;ct_right<=0;ct_top<=0;ct_bottom<=0;ct_width<=0;ct_height<=0;ct_side<=0;
            ct_norm_kind<=0;ct_norm_bit<=0;ct_full_fg<=0;ct_body_fg<=0;ct_body_axis_fg<=0;ct_mul_term_y<=0;
            for(k=0;k<3;k=k+1)ct_seed_count[k]<=0;
            for(k=0;k<4;k=k+1)ct_neighbor_color[k]<=0;
            out_revoke<=0;dbg_scene_count<=0;dbg_glyph_count<=0;dbg_paper_count<=0;dbg_scene_event<=0;dbg_scene_flags<=0;
            for(k=0;k<16;k=k+1) begin
                hist_r0[k]<=0;hist_g0[k]<=0;hist_b0[k]<=0;
                hist_r1[k]<=0;hist_g1[k]<=0;hist_b1[k]<=0;
            end
        end else begin
            dbg_scene_event<=0;
            replay_valid<=0;replay_sof<=0;replay_eol<=0;replay_glyph<=0;replay_end<=0;
            card_start<=0;card_valid<=0;card_end<=0;out_revoke<=0;
            if(flush || raster_fault || engine_fault) begin
                ready0<=0;ready1<=0;capture_active<=0;capture_pixels<=0;capture_samples<=0;
                min_rg0<=0;max_rg0<=0;min_bg0<=0;max_bg0<=0;
                min_rg1<=0;max_rg1<=0;min_bg1<=0;max_bg1<=0;
                expected_x<=0;expected_y<=0;state<=P_IDLE;engine_fault<=0;
                replay_good<=0;replay_present<=1;card_good<=0;card_present<=1;
                ct_flood<=0;contour_qualified<=0;contour_exterior_ok<=0;contour_color<=0;
                scene_present<=0;scene_clipped<=0;paper_route<=0;dbg_scene_count<=0;dbg_glyph_count<=0;
                out_revoke<=!flush && !fault_reported;
                fault_reported<=!flush;
            end else begin
                if(start_ok) begin
                    capture_active<=1;capture_bank<=selected_bank;capture_id<=in_frame_id;
                    capture_source<=in_source_test;capture_pixels<=0;capture_samples<=0;fault_reported<=0;
                    if(selected_bank) begin
                        id1<=in_frame_id;source1<=in_source_test;
                        for(k=0;k<16;k=k+1) begin hist_r1[k]<=0;hist_g1[k]<=0;hist_b1[k]<=0;end
                    end else begin
                        id0<=in_frame_id;source0<=in_source_test;
                        for(k=0;k<16;k=k+1) begin hist_r0[k]<=0;hist_g0[k]<=0;hist_b0[k]<=0;end
                    end
                end
                if(in_valid) begin
                    capture_pixels<=current_pixels+1'b1;
                    if(in_x==FRAME_WIDTH-1) begin expected_x<=0;expected_y<=in_y+1'b1;end
                    else begin expected_x<=in_x+1'b1;expected_y<=in_y;end
                    if(take_sample) begin
                        capture_samples<=(start_ok ? 0 : capture_samples)+1'b1;
                        if(sample_border) begin
                            if(selected_bank) begin
                                if(start_ok || capture_samples==0 || sample_rg<min_rg1)min_rg1<=sample_rg;
                                if(start_ok || capture_samples==0 || sample_rg>max_rg1)max_rg1<=sample_rg;
                                if(start_ok || capture_samples==0 || sample_bg<min_bg1)min_bg1<=sample_bg;
                                if(start_ok || capture_samples==0 || sample_bg>max_bg1)max_bg1<=sample_bg;
                            end else begin
                                if(start_ok || capture_samples==0 || sample_rg<min_rg0)min_rg0<=sample_rg;
                                if(start_ok || capture_samples==0 || sample_rg>max_rg0)max_rg0<=sample_rg;
                                if(start_ok || capture_samples==0 || sample_bg<min_bg0)min_bg0<=sample_bg;
                                if(start_ok || capture_samples==0 || sample_bg>max_bg0)max_bg0<=sample_bg;
                            end

                            if(selected_bank) begin
                                hist_r1[in_rgb[23:20]]<=(start_ok ? 0 : hist_r1[in_rgb[23:20]])+1'b1;
                                hist_g1[in_rgb[15:12]]<=(start_ok ? 0 : hist_g1[in_rgb[15:12]])+1'b1;
                                hist_b1[in_rgb[7:4]]<=(start_ok ? 0 : hist_b1[in_rgb[7:4]])+1'b1;
                            end else begin
                                hist_r0[in_rgb[23:20]]<=(start_ok ? 0 : hist_r0[in_rgb[23:20]])+1'b1;
                                hist_g0[in_rgb[15:12]]<=(start_ok ? 0 : hist_g0[in_rgb[15:12]])+1'b1;
                                hist_b0[in_rgb[7:4]]<=(start_ok ? 0 : hist_b0[in_rgb[7:4]])+1'b1;
                            end
                        end
                    end
                end
                if(in_frame_end) begin
                    capture_active<=0;
                    if(capture_bank) ready1<=1; else ready0<=1;
                end

                case(state)
                    P_IDLE: if(ready0 || ready1) begin
                        process_bank<=!ready0;
                        if(ready0) begin
                            ready0<=0;replay_id<=id0;card_id<=id0;replay_source<=source0;card_source<=source0;
                        end else begin
                            ready1<=0;replay_id<=id1;card_id<=id1;replay_source<=source1;card_source<=source1;
                        end
                        replay_good<=0;card_good<=0;replay_present<=1;card_present<=1;
                        hist_bin<=0;sum_r<=0;sum_g<=0;sum_b<=0;found_r<=0;found_g<=0;found_b<=0;
                        fifo_head<=0;fifo_tail<=0;background_seed_count<=0;state<=P_HIST;
                        ct_flood<=0;contour_qualified<=0;contour_color<=0;
                    end
                    P_HIST: begin
                        sum_r<=sum_r+hr;sum_g<=sum_g+hg;sum_b<=sum_b+hb;
                        // Lower median: cumulative count reaches the one-based
                        // rank (BORDER_PIXELS+1)/2, including an even split.
                        if(!found_r && sum_r+hr>=(BORDER_PIXELS+1)/2) begin background_r<={hist_bin[3:0],4'h8};found_r<=1;end
                        if(!found_g && sum_g+hg>=(BORDER_PIXELS+1)/2) begin background_g<={hist_bin[3:0],4'h8};found_g<=1;end
                        if(!found_b && sum_b+hb>=(BORDER_PIXELS+1)/2) begin background_b<={hist_bin[3:0],4'h8};found_b<=1;end
                        if(hist_bin==15) begin scan_address<=0;scan_x<=0;scan_y<=0;state<=P_CLEAR;end
                        else hist_bin<=hist_bin+1'b1;
                    end
                    P_CLEAR: begin
                        if(scan_address==N-1) begin scan_address<=0;scan_x<=0;scan_y<=0;state<=P_SEED;end
                        else scan_address<=scan_address+1'b1;
                    end
                    P_SEED: begin
                        if(scan_x==0 || scan_y==0 || scan_x==GRID_WIDTH-1 || scan_y==GRID_HEIGHT-1) begin
                            rgb_address<=scan_address;flag_address<=scan_address;state<=P_SEED_WAIT;
                        end else begin
                            if(scan_address==N-1) state<=P_POP;
                            else next_scan;
                        end
                    end
                    P_SEED_WAIT: state<=P_SEED_CHECK;
                    P_SEED_CHECK: begin
                        if(ct_flood ? !flag_q[0]:background_like(rgb_q)) begin
                            if(!ct_flood)background_seed_count<=background_seed_count+1'b1;
                            if(fifo_tail>=N) engine_fault<=1;
                            else fifo_tail<=fifo_tail+1'b1;
                        end
                        if(scan_address==N-1) state<=P_POP;
                        else begin next_scan;state<=P_SEED;end
                    end
                    P_POP: begin
                        if(fifo_head<fifo_tail) begin fifo_address<=fifo_head[AW-1:0];state<=P_POP_WAIT;end
                        else if(ct_flood)begin
                            scan_address<=0;scan_x<=0;scan_y<=0;ct_body_area<=0;ct_exterior<=0;state<=P_CT_SUM;
                        end else begin
                            scan_address<=0;scan_x<=0;scan_y<=0;scene_count<=0;glyph_count<=0;paper_count<=0;
                            scene_left<=GRID_WIDTH-1;scene_right<=0;scene_top<=GRID_HEIGHT-1;scene_bottom<=0;
                            glyph_left<=GRID_WIDTH-1;glyph_right<=0;glyph_top<=GRID_HEIGHT-1;glyph_bottom<=0;
                            state<=P_FILTER_BEGIN;
                        end
                    end
                    P_POP_WAIT: state<=P_POP_LOAD;
                    P_POP_LOAD: begin
                        node_address<=fifo_q;node_x<=fifo_q%GRID_WIDTH;node_y<=fifo_q/GRID_WIDTH;
                        fifo_head<=fifo_head+1'b1;neighbor<=0;state<=P_NEIGHBOR;
                    end
                    P_NEIGHBOR: begin
                        if(neighbor_x<0 || neighbor_y<0 || neighbor_x>=GRID_WIDTH || neighbor_y>=GRID_HEIGHT)
                            next_neighbor;
                        else begin
                            pending_address<=neighbor_linear;flag_address<=neighbor_linear;rgb_address<=neighbor_linear;
                            state<=P_NEIGHBOR_WAIT;
                        end
                    end
                    P_NEIGHBOR_WAIT: state<=P_NEIGHBOR_CHECK;
                    P_NEIGHBOR_CHECK: begin
                        if(!flag_q[1]) begin
                            if(ct_flood ? !flag_q[0]:background_like(rgb_q)) begin
                                if(fifo_tail>=N) engine_fault<=1;
                                else fifo_tail<=fifo_tail+1'b1;
                            end
                        end
                        next_neighbor;
                    end
                    P_FILTER_BEGIN: begin
                        filter_neighbor<=0;scene_neighbors<=0;glyph_neighbors<=0;center_scene<=0;center_glyph<=0;
                        state<=P_FILTER_READ;
                    end
                    P_FILTER_READ: begin
                        if(filter_x<0 || filter_y<0 || filter_x>=GRID_WIDTH || filter_y>=GRID_HEIGHT)
                            next_filter_neighbor;
                        else begin
                            flag_address<=filter_linear;rgb_address<=filter_linear;state<=P_FILTER_WAIT;
                        end
                    end
                    P_FILTER_WAIT: state<=P_FILTER_CHECK;
                    P_FILTER_CHECK: begin
                        if(!flag_q[0]) scene_neighbors<=scene_neighbors+1'b1;
                        if(!flag_q[0] && glyph_pixel(rgb_q)) glyph_neighbors<=glyph_neighbors+1'b1;
                        if(filter_neighbor==4) begin center_scene<=!flag_q[0];center_glyph<=!flag_q[0] && glyph_pixel(rgb_q);end
                        next_filter_neighbor;
                    end
                    P_FILTER_STORE: begin
                        if(filtered_scene && !center_glyph) paper_count<=paper_count+1'b1;
                        if(filtered_scene) begin
                            scene_count<=scene_count+1'b1;
                            if(scan_x<scene_left) scene_left<=scan_x;
                            if(scan_x>scene_right) scene_right<=scan_x;
                            if(scan_y<scene_top) scene_top<=scan_y;
                            if(scan_y>scene_bottom) scene_bottom<=scan_y;
                        end
                        if(filtered_glyph) begin
                            glyph_count<=glyph_count+1'b1;
                            if(scan_x<glyph_left) glyph_left<=scan_x;
                            if(scan_x>glyph_right) glyph_right<=scan_x;
                            if(scan_y<glyph_top) glyph_top<=scan_y;
                            if(scan_y>glyph_bottom) glyph_bottom<=scan_y;
                        end
                        if(scan_address==N-1)begin
                            scan_address<=0;scan_x<=0;scan_y<=0;
                            ct_left<=GRID_WIDTH-1;ct_right<=0;ct_top<=GRID_HEIGHT-1;ct_bottom<=0;
                            for(k=0;k<3;k=k+1)ct_seed_count[k]<=0;
                            ct_repair_boundary<=0;state<=P_CT_SEED;
                        end
                        else begin next_scan;state<=P_FILTER_BEGIN;end
                    end
                    P_CT_SEED: begin
                        rgb_address<=scan_address;mask_address<=scan_address;state<=P_CT_SEED_W0;
                    end
                    P_CT_SEED_W0: state<=P_CT_SEED_W1;
                    P_CT_SEED_W1: state<=P_CT_SEED_W2;
                    P_CT_SEED_W2: state<=P_CT_SEED_CHECK;
                    P_CT_SEED_CHECK: begin
                        if(ct_seed)begin
                            ct_seed_count[ct_label-1]<=ct_seed_count[ct_label-1]+1'b1;
                            if(scan_x<ct_left)ct_left<=scan_x;
                            if(scan_x>ct_right)ct_right<=scan_x;
                            if(scan_y<ct_top)ct_top<=scan_y;
                            if(scan_y>ct_bottom)ct_bottom<=scan_y;
                        end
                        if(scan_address==N-1)begin scan_address<=0;scan_x<=0;scan_y<=0;state<=P_CT_CENTER;end
                        else begin next_scan;state<=P_CT_SEED;end
                    end
                    P_CT_CENTER: begin flag_address<=scan_address;rgb_address<=scan_address;state<=P_CT_CENTER_WAIT;end
                    P_CT_CENTER_WAIT: state<=P_CT_CENTER_CHECK;
                    P_CT_CENTER_CHECK: begin
                        ct_center_seed<=flag_q[1];ct_center_rg<=ct_rg;ct_center_bg<=ct_bg;
                        ct_neighbor_seed<=0;ct_neighbor_edge<=0;neighbor<=0;node_x<=scan_x;node_y<=scan_y;
                        state<=flag_q[1] ? P_CT_STORE:P_CT_NEIGHBOR;
                    end
                    P_CT_NEIGHBOR: begin
                        if(neighbor_x<0 || neighbor_y<0 || neighbor_x>=GRID_WIDTH || neighbor_y>=GRID_HEIGHT)begin
                            ct_neighbor_seed[neighbor]<=0;ct_neighbor_edge[neighbor]<=0;ct_neighbor_color[neighbor]<=0;
                            next_contour_neighbor;
                        end else begin
                            flag_address<=neighbor_linear;rgb_address<=neighbor_linear;state<=P_CT_NW0;
                        end
                    end
                    P_CT_NW0: state<=P_CT_NW1;
                    P_CT_NW1: state<=P_CT_NW2;
                    P_CT_NW2: state<=P_CT_NCHECK;
                    P_CT_NCHECK: begin
                        ct_neighbor_seed[neighbor]<=flag_q[1] && ct_label!=0;
                        ct_neighbor_color[neighbor]<=ct_label;ct_neighbor_edge[neighbor]<=ct_edge;
                        next_contour_neighbor;
                    end
                    P_CT_STORE: begin
                        if(!ct_center_seed && ct_bridge && (scan_x==ct_left || scan_x==ct_right || scan_y==ct_top || scan_y==ct_bottom))
                            ct_repair_boundary<=1;
                        if(scan_address==N-1)begin scan_address<=0;scan_x<=0;scan_y<=0;state<=P_CT_CLEAR;end
                        else begin next_scan;state<=P_CT_CENTER;end
                    end
                    P_CT_CLEAR: begin flag_address<=scan_address;state<=P_CT_CLEAR_WAIT;end
                    P_CT_CLEAR_WAIT: state<=P_CT_CLEAR_STORE;
                    P_CT_CLEAR_STORE: begin
                        if(scan_address==N-1)begin
                            scan_address<=0;scan_x<=0;scan_y<=0;fifo_head<=0;fifo_tail<=0;ct_flood<=1;state<=P_SEED;
                        end else begin next_scan;state<=P_CT_CLEAR;end
                    end
                    P_CT_SUM: begin flag_address<=scan_address;mask_address<=scan_address;state<=P_CT_SUM_WAIT;end
                    P_CT_SUM_WAIT: state<=P_CT_SUM_CHECK;
                    P_CT_SUM_CHECK: begin
                        if(!flag_q[1])ct_body_area<=ct_body_area+1'b1;
                        if(mask_q[1] && flag_q[1])ct_exterior<=ct_exterior+1'b1;
                        if(scan_address==N-1)state<=P_CT_FINAL;
                        else begin next_scan;state<=P_CT_SUM;end
                    end
                    P_CT_FINAL: begin
                        ct_width<=ct_left<=ct_right ? ct_right-ct_left+1'b1:0;
                        ct_height<=ct_top<=ct_bottom ? ct_bottom-ct_top+1'b1:0;
                        ct_side<=(ct_right-ct_left>=ct_bottom-ct_top ? ct_right-ct_left+1'b1:ct_bottom-ct_top+1'b1);
                        contour_qualified<=ct_winner!=0 && ct_body_area>=12 && ct_winning_area<=ct_body_area &&
                            ct_triple>=ct_double && has_object && !border_uncertain &&
                            !(scene_left==0 || scene_top==0 || scene_right==GRID_WIDTH-1 || scene_bottom==GRID_HEIGHT-1) &&
                            !(glyph_count>=MIN_COMPONENT_PIXELS && {paper_count,2'b00}>{2'b00,scene_count});
                        contour_aspect_good<=ct_left<=ct_right && ct_top<=ct_bottom &&
                            (ct_right-ct_left+1)*5>=(ct_bottom-ct_top+1)*4 &&
                            (ct_bottom-ct_top+1)*5>=(ct_right-ct_left+1)*4;
                        contour_boundary_repair<=ct_repair_boundary;contour_exterior_ok<=ct_exterior<12;contour_color<=ct_winner;
                        state<=P_FINAL;
                    end
                    P_FINAL: begin
                        // Any denoised object touching the sampled operation
                        // boundary is present but has unknown identity. Blank
                        // classifier rasters keep frame health separate from
                        // clipping and cannot release the quiz empty gate.
                        scene_clipped<=border_uncertain || (has_object && (scene_left==0 || scene_top==0 ||
                            scene_right==GRID_WIDTH-1 || scene_bottom==GRID_HEIGHT-1));
                        // Bright neutral paper around a colored/dark printed
                        // glyph selects the card path. It remains present and
                        // healthy even when the card template rejects it.
                        paper_route<=has_object && glyph_count>=MIN_COMPONENT_PIXELS &&
                            {paper_count,2'b00}>{2'b00,scene_count};
                        scene_present<=has_object || border_uncertain;
                        replay_present<=has_object || border_uncertain;
                        card_present<=has_object || border_uncertain;
                        dbg_scene_count<=scene_count;dbg_glyph_count<=glyph_count;dbg_paper_count<=paper_count;
                        dbg_scene_event<=1;
                        dbg_scene_flags<={border_uncertain,
                          has_object && glyph_count>=MIN_COMPONENT_PIXELS && {paper_count,2'b00}>{2'b00,scene_count},
                          border_uncertain || (has_object && (scene_left==0 || scene_top==0 || scene_right==GRID_WIDTH-1 || scene_bottom==GRID_HEIGHT-1)),
                          has_object || border_uncertain};
                        glyph_width<=glyph_count==0 ? 0 : glyph_right-glyph_left+1;
                        glyph_height<=glyph_count==0 ? 0 : glyph_bottom-glyph_top+1;
                        glyph_side<=glyph_count==0 ? 0 :
                            (glyph_right-glyph_left>=glyph_bottom-glyph_top ? glyph_right-glyph_left+1 : glyph_bottom-glyph_top+1);
                        scan_address<=0;scan_x<=0;scan_y<=0;state<=P_REPLAY_READ;
                    end
                    P_REPLAY_READ: begin rgb_address<=scan_address;mask_address<=scan_address;state<=P_REPLAY_WAIT;end
                    P_REPLAY_WAIT: state<=P_REPLAY_EMIT;
                    P_REPLAY_EMIT: begin
                        replay_valid<=1;replay_sof<=scan_address==0;replay_eol<=scan_x==GRID_WIDTH-1;
                        replay_glyph<=scene_present && !scene_clipped && !paper_route && mask_q[1];
                        replay_x<=scan_x;replay_y<=scan_y;replay_rgb<=scene_present && !scene_clipped && !paper_route && mask_q[0] ? rgb_q : 24'hffffff;
                        if(scan_address==N-1) state<=P_REPLAY_END;
                        else begin next_scan;state<=P_REPLAY_READ;end
                    end
                    P_REPLAY_END: begin replay_end<=1;replay_good<=1;state<=P_CARD_START;end
                    P_CARD_START: begin card_start<=1;normalize_index<=0;ct_norm_kind<=0;state<=P_CARD_CALC;end
                    P_CARD_CALC: begin
                        if(scene_clipped || (ct_body_kind ? ct_body_area==0:glyph_count==0) ||
                            normalize_index[4:0]<NORMAL_ORIGIN || normalize_index[4:0]>=NORMAL_ORIGIN+NORMAL_SIZE ||
                            normalize_index[9:5]<NORMAL_ORIGIN || normalize_index[9:5]>=NORMAL_ORIGIN+NORMAL_SIZE) begin
                            ct_norm_bit<=0;state<=P_CT_NORM_STORE;
                        end else begin
                            numerator_x<=normal_base($signed({2'b00,ct_norm_left,1'b0})+$signed({2'b00,ct_norm_width})-$signed({2'b00,ct_span_x}));
                            numerator_y<=normal_base($signed({3'b000,ct_norm_top,1'b0})+$signed({2'b00,ct_norm_height})-$signed({2'b00,ct_span_y}));
                            mul_factor_x<=((normalize_index[4:0]-NORMAL_ORIGIN)<<1)|6'd1;
                            mul_factor_y<=((normalize_index[9:5]-NORMAL_ORIGIN)<<1)|6'd1;
                            mul_term<={12'd0,ct_span_x};ct_mul_term_y<={12'd0,ct_span_y};mul_step<=0;state<=P_CARD_MUL;
                        end
                    end
                    P_CARD_MUL: begin
                        if(mul_factor_x[0]) numerator_x<=numerator_x+mul_term;
                        if(mul_factor_y[0]) numerator_y<=numerator_y+ct_mul_term_y;
                        mul_factor_x<=mul_factor_x>>1;mul_factor_y<=mul_factor_y>>1;
                        mul_term<=mul_term<<<1;ct_mul_term_y<=ct_mul_term_y<<<1;
                        if(mul_step==5) state<=P_CARD_DIV;else mul_step<=mul_step+1'b1;
                    end
                    P_CARD_DIV: begin
                        if(numerator_x<0 || numerator_y<0) begin
                            ct_norm_bit<=0;state<=P_CT_NORM_STORE;
                        end else begin
                            dividend_x<=numerator_x;dividend_y<=numerator_y;
                            remainder_x<=0;remainder_y<=0;normalized_x<=0;normalized_y<=0;
                            div_step<=23;state<=P_CARD_DIV_STEP;
                        end
                    end
                    P_CARD_DIV_STEP: begin
                        dividend_x<={dividend_x[22:0],1'b0};dividend_y<={dividend_y[22:0],1'b0};
                        remainder_x<=quotient_x ? trial_x-NORMAL_DENOM : trial_x;
                        remainder_y<=quotient_y ? trial_y-NORMAL_DENOM : trial_y;
                        normalized_x<={normalized_x[14:0],quotient_x};normalized_y<={normalized_y[14:0],quotient_y};
                        if(div_step==0) state<=P_CARD_ADDR;else div_step<=div_step-1'b1;
                    end
                    P_CARD_ADDR: begin
                        if(normalized_x<ct_norm_left || normalized_x>ct_norm_right || normalized_y<ct_norm_top || normalized_y>ct_norm_bottom) begin
                            ct_norm_bit<=0;state<=P_CT_NORM_STORE;
                        end else begin
                            mask_address<=grid_address(normalized_x[10:0],normalized_y[9:0]);
                            flag_address<=grid_address(normalized_x[10:0],normalized_y[9:0]);state<=P_CARD_WAIT;
                        end
                    end
                    P_CARD_WAIT: state<=P_CARD_EMIT;
                    P_CARD_EMIT: begin ct_norm_bit<=ct_body_kind ? !flag_q[1]:mask_q[1];state<=P_CT_NORM_STORE;end
                    P_CT_NORM_STORE: begin
                        case(ct_norm_kind)
                            0: ct_full_fg<=ct_norm_bit;
                            1: ct_body_fg<=ct_norm_bit;
                            2: ct_body_axis_fg<=ct_norm_bit;
                            default: begin end
                        endcase
                        if(ct_norm_kind==3)begin
                            card_valid<=1;card_index<=normalize_index;card_fg<=ct_full_fg;
                            contour_fg<=ct_body_fg;contour_axis_fg<=ct_body_axis_fg;full_axis_fg<=ct_norm_bit;
                            ct_norm_kind<=0;next_card_sample;
                        end else begin ct_norm_kind<=ct_norm_kind+1'b1;state<=P_CARD_CALC;end
                    end
                    P_CARD_END: begin card_end<=1;card_good<=1;state<=P_FINISH;end
                    P_FINISH: state<=P_IDLE;
                    default: engine_fault<=1;
                endcase
            end
        end
    end

    // synthesis translate_off
    initial begin
        if(FRAME_WIDTH<1 || FRAME_WIDTH>2048 || FRAME_HEIGHT<1 || FRAME_HEIGHT>1024 ||
            GRID_WIDTH<3 || GRID_WIDTH>2048 || GRID_HEIGHT<3 || GRID_HEIGHT>1024 || N>65535 ||
            SAMPLE_STEP<1 || ROI_X<0 || ROI_Y<0 ||
            ROI_X+GRID_WIDTH*SAMPLE_STEP>FRAME_WIDTH || ROI_Y+GRID_HEIGHT*SAMPLE_STEP>FRAME_HEIGHT ||
            BG_TOLERANCE<0 || BG_TOLERANCE>255 || MIN_COMPONENT_PIXELS<1 || MIN_COMPONENT_PIXELS>N ||
            NORMAL_SIZE<4 || NORMAL_SIZE>32 || NORMAL_SIZE%2!=0)
            $fatal(1,"pixel14_scene_preprocess invalid geometry or thresholds");
    end
    // synthesis translate_on
endmodule
