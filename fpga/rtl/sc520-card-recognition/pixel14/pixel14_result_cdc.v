// Atomic bundled-data mailbox. Both domains share the same asynchronous reset;
// reset release is synchronized locally. Payload remains stable until the
// destination acknowledgement has crossed back. Physical CDC constraints and
// metastability analysis remain board-integration requirements.
module pixel14_result_cdc #(
    parameter integer WIDTH = 112
) (
    input wire rst_n,
    input wire src_clk, src_valid,
    input wire [WIDTH-1:0] src_data,
    output wire src_ready,
    output reg src_fault,
    input wire dst_clk,
    output reg dst_valid,
    output reg [WIDTH-1:0] dst_data,
    output wire dst_fault
);
    reg [1:0] src_reset, dst_reset;
    always @(posedge src_clk or negedge rst_n)
        if (!rst_n) src_reset <= 0;
        else src_reset <= {src_reset[0],1'b1};
    always @(posedge dst_clk or negedge rst_n)
        if (!rst_n) dst_reset <= 0;
        else dst_reset <= {dst_reset[0],1'b1};
    reg request, acknowledge;
    reg [WIDTH-1:0] held_data;
    reg ack_meta, ack_sync, req_meta, req_sync;
    reg fault_meta, fault_sync;
    assign src_ready = src_reset[1] && !src_fault && request == ack_sync;
    assign dst_fault = fault_sync;
    always @(posedge src_clk or negedge rst_n) begin
        if (!rst_n) begin
            ack_meta <= 0; ack_sync <= 0;
        end else if (!src_reset[1]) begin
            ack_meta <= 0; ack_sync <= 0;
        end else begin
            ack_meta <= acknowledge; ack_sync <= ack_meta;
        end
    end
    always @(posedge src_clk or negedge rst_n) begin
        if (!rst_n) begin
            request <= 0; held_data <= 0; src_fault <= 0;
        end else if (!src_reset[1]) begin
            request <= 0; held_data <= 0; src_fault <= 0;
        end else if (src_valid) begin
            if (src_ready) begin
                held_data <= src_data;
                request <= !request;
            end else begin
                // No overwrite or silently skipped frame. A producer that
                // cannot obey ready permanently withdraws trust until reset.
                src_fault <= 1;
            end
        end
    end
    always @(posedge dst_clk or negedge rst_n) begin
        if (!rst_n) begin
            req_meta <= 0; req_sync <= 0;
            fault_meta <= 0; fault_sync <= 0;
        end else if (!dst_reset[1]) begin
            req_meta <= 0; req_sync <= 0;
            fault_meta <= 0; fault_sync <= 0;
        end else begin
            req_meta <= request; req_sync <= req_meta;
            fault_meta <= src_fault; fault_sync <= fault_meta;
        end
    end
    always @(posedge dst_clk or negedge rst_n) begin
        if (!rst_n) begin
            acknowledge <= 0; dst_valid <= 0; dst_data <= 0;
        end else if (!dst_reset[1]) begin
            acknowledge <= 0; dst_valid <= 0; dst_data <= 0;
        end else begin
            dst_valid <= 0;
            if (req_sync != acknowledge) begin
                acknowledge <= req_sync;
                if (!fault_sync) begin
                    dst_data <= held_data;
                    dst_valid <= 1;
                end
            end
        end
    end
endmodule
