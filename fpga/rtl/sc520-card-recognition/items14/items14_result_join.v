// Task-local result-record join, not a pixel/camera adapter. Same persistent clk.
// Every payload belongs to its event; a detector's held result is never paired.
module items14_result_join #(
    parameter integer TIMEOUT_MS=100
) (
    input wire clk,rst_n,tick_1ms,flush,block_revoke,card_revoke,
    input wire block_event,block_healthy,block_present,block_valid,
    input wire [3:0] block_item,
    input wire [31:0] block_frame_id,
    input wire block_source_test,
    input wire [7:0] block_count,
    input wire card_event,card_healthy,card_present,card_valid,
    input wire [3:0] card_item,
    input wire [31:0] card_frame_id,
    input wire card_source_test,
    input wire [7:0] card_count,
    output wire detectors_flush,
    output reg out_event,out_healthy,out_present,out_valid,out_revoke,out_conflict,
    output reg [3:0] out_item,
    output reg [31:0] out_frame_id,
    output reg out_source_test,
    output reg [7:0] out_count,
    output reg timed_out
);
    localparam integer TW=TIMEOUT_MS<2 ? 1 : $clog2(TIMEOUT_MS);
    localparam [TW-1:0] LAST_TICK=TIMEOUT_MS-1;
    reg [TW-1:0] age;
    reg block_pending,card_pending,clear_seen,history_valid,last_source;
    reg [31:0] last_id;
    // Stored records are already structurally healthy and legal.
    reg bp,bv,bs,cp,cv,cs;
    reg [3:0] bi,ci;
    reg [31:0] bt,ct;
    reg [7:0] bc,cc;
    wire have_block=block_pending || block_event;
    wire have_card=card_pending || card_event;
    wire p_block=block_pending ? bp : block_present;
    wire v_block=block_pending ? bv : block_valid;
    wire s_block=block_pending ? bs : block_source_test;
    wire [3:0] i_block=block_pending ? bi : block_item;
    wire [31:0] t_block=block_pending ? bt : block_frame_id;
    wire [7:0] c_block=block_pending ? bc : block_count;
    wire p_card=card_pending ? cp : card_present;
    wire v_card=card_pending ? cv : card_valid;
    wire s_card=card_pending ? cs : card_source_test;
    wire [3:0] i_card=card_pending ? ci : card_item;
    wire [31:0] t_card=card_pending ? ct : card_frame_id;
    wire [7:0] c_card=card_pending ? cc : card_count;
    wire external_clear=flush || block_revoke || card_revoke;
    wire bad_block=block_event && (!block_healthy ||
        (block_valid && (!block_present || block_item<1 || block_item>9)));
    wire bad_card=card_event && (!card_healthy ||
        (card_valid && (!card_present || card_item<10 || card_item>14)));
    wire overflow_now=(block_pending && block_event) || (card_pending && card_event);
    wire pair_ready=have_block && have_card;
    wire [31:0] advance=t_block-last_id;
    // Forward distances 1..2^31-1 are accepted, including FFFFFFFF -> 0.
    // Internal faults do not erase history and let replayed tags become fresh.
    wire old_pair=history_valid && (s_block!=last_source || advance==0 || advance[31]);
    wire pair_fault=pair_ready && (t_block!=t_card || s_block!=s_card || old_pair);
    wire fault_now=external_clear || bad_block || bad_card || overflow_now || pair_fault;
    wire good_pair=pair_ready && !fault_now;
    wire conflict_now=good_pair && v_block && v_card;
    wire timeout_now=rst_n && !flush && !timed_out && !good_pair &&
                     tick_1ms && age==LAST_TICK;
    // Both detectors must sample this same-domain clear; frame tags must survive
    // internal clears. Only an explicit external flush begins a new tag epoch.
    assign detectors_flush=flush || block_revoke || card_revoke ||
                           (rst_n && (bad_block || bad_card || overflow_now ||
                                      pair_fault || conflict_now || timeout_now));
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            age<=0;timed_out<=0;block_pending<=0;card_pending<=0;clear_seen<=0;
            history_valid<=0;last_id<=0;last_source<=0;
            bp<=0;bv<=0;bs<=0;bi<=0;bt<=0;bc<=0;
            cp<=0;cv<=0;cs<=0;ci<=0;ct<=0;cc<=0;
            out_event<=0;out_healthy<=0;out_present<=1;out_valid<=0;
            out_revoke<=0;out_conflict<=0;out_item<=0;out_frame_id<=0;
            out_source_test<=0;out_count<=0;
        end else begin
            out_event<=0;out_revoke<=0;out_conflict<=0;
            clear_seen<=external_clear;
            if(flush) begin
                age<=0;timed_out<=0;history_valid<=0;
            end else if(good_pair) begin
                age<=0;timed_out<=0;history_valid<=1;
                last_id<=t_block;last_source<=s_block;
            end else if(timeout_now) timed_out<=1;
            else if(tick_1ms && !timed_out) age<=age+1'b1;

            if(fault_now || timeout_now) begin
                block_pending<=0;card_pending<=0;
                out_event<=!external_clear || !clear_seen;
                out_revoke<=!external_clear || !clear_seen;
                out_healthy<=0;out_present<=1;out_valid<=0;out_item<=0;out_count<=0;
            end else if(good_pair) begin
                block_pending<=0;card_pending<=0;
                out_event<=1;out_healthy<=1;
                out_present<=p_block || p_card;
                out_frame_id<=t_block;out_source_test<=s_block;
                out_conflict<=conflict_now;out_revoke<=conflict_now;
                out_valid<=!conflict_now && (v_block || v_card);
                out_item<=conflict_now ? 4'd0 : v_block ? i_block : v_card ? i_card : 4'd0;
                out_count<=conflict_now ? 8'd0 : v_block ? c_block : v_card ? c_card : 8'd0;
            end else begin
                if(block_event) begin
                    block_pending<=1;bp<=block_present;bv<=block_valid;bs<=block_source_test;
                    bi<=block_item;bt<=block_frame_id;bc<=block_count;
                end
                if(card_event) begin
                    card_pending<=1;cp<=card_present;cv<=card_valid;cs<=card_source_test;
                    ci<=card_item;ct<=card_frame_id;cc<=card_count;
                end
            end
        end
    end
    // synthesis translate_off
    initial if(TIMEOUT_MS<1) $fatal(1,"items14_result_join TIMEOUT_MS must be positive");
    // synthesis translate_on
endmodule
