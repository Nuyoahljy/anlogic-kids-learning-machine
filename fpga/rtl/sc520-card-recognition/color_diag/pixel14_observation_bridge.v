// Handshaken stable payload and independent display-clock freshness timeout.
// A source event during a busy handshake queues an explicit incomplete record.
module pixel14_observation_bridge #(
    parameter integer TIMEOUT_MS=100
) (
    input wire rst_n,capture_clk,display_clk,
    input wire src_event,
    input wire [799:0] src_packet,
    input wire tick_1ms,display_revoke,
    output wire [799:0] display_packet,
    output wire fresh,
    output wire fault,
    output wire [7:0] age_ms
);
    reg overrun_pending;
    reg [31:0] overrun_id;
    wire ready,src_fault,event_out,dst_fault;
    wire [799:0] packet_out;
    wire send=ready && (overrun_pending || src_event);
    wire [799:0] invalid_packet={19'd0,1'b0,8'h40,740'd0,overrun_id};
    wire [799:0] send_packet=overrun_pending ? invalid_packet:src_packet;
    always @(posedge capture_clk or negedge rst_n)begin
        if(!rst_n)begin overrun_pending<=0;overrun_id<=0;end
        else begin
            if(send && overrun_pending)overrun_pending<=0;
            if(src_event && (!ready || overrun_pending))begin overrun_pending<=1;overrun_id<=src_packet[31:0];end
        end
    end
    pixel14_result_cdc #(.WIDTH(800)) link (
        .rst_n(rst_n),.src_clk(capture_clk),.src_valid(send),.src_data(send_packet),
        .src_ready(ready),.src_fault(src_fault),.dst_clk(display_clk),
        .dst_valid(event_out),.dst_data(packet_out),.dst_fault(dst_fault));
    reg seen,have_id,packet_good;
    reg [7:0] reason;
    reg [7:0] age_counter;
    reg [31:0] last_id;
    wire [31:0] delta=packet_out[31:0]-last_id;
    wire repeated=packet_out[780] && have_id && (delta==0 || delta[31]);
    assign fault=dst_fault;
    assign fresh=(event_out || (seen && age_counter<TIMEOUT_MS)) && !display_revoke && !dst_fault;
    assign age_ms=event_out ? 8'd0:age_counter;
    // Mailbox dst_data itself is held stable. Avoid duplicating800 data FFs;
    // only the local interpretation/freshness bits need extra registers.
    wire current_good=event_out ? (packet_out[780] && !repeated):packet_good;
    wire [7:0] current_reason=event_out ? (repeated ? 8'h20:packet_out[779:772]):reason;
    assign display_packet={packet_out[799:781],current_good,current_reason,packet_out[771:0]};
    always @(posedge display_clk or negedge rst_n)begin
        if(!rst_n)begin age_counter<=255;seen<=0;have_id<=0;last_id<=0;packet_good<=0;reason<=0;end
        else begin
            if(tick_1ms && age_counter!=255)age_counter<=age_counter+1'b1;
            if(event_out)begin
                seen<=1;age_counter<=0;packet_good<=packet_out[780];reason<=packet_out[779:772];
                if(repeated)begin packet_good<=0;reason<=8'h20;end
                else if(packet_out[780])begin have_id<=1;last_id<=packet_out[31:0];end
            end
            if(display_revoke || dst_fault)begin seen<=0;age_counter<=255;end
        end
    end
    // synthesis translate_off
    initial if(TIMEOUT_MS<1 || TIMEOUT_MS>254)$fatal(1,"observation timeout out of range");
    // synthesis translate_on
endmodule
