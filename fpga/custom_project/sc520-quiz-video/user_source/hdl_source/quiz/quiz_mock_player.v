// Silent simulation transport, synthesized only to exercise the control/display.
// No UART, GPIO, DAC or audible output. Ready/ACK/track-end/stop are distinct.
module quiz_mock_player #(parameter integer PLAY_TICKS=120)(
    input wire clk,rst_n,tick_1ms,
    input wire req_valid,
    input wire [2:0] req_kind,
    input wire [3:0] req_item,
    input wire [15:0] req_tag,
    output wire req_ready,
    output reg device_busy,
    input wire stop_valid,
    input wire [15:0] stop_tag,
    output reg rsp_valid,
    output reg [15:0] rsp_tag,
    output reg [1:0] rsp_code
);
    reg [15:0] active_tag;
    reg [31:0] elapsed;
    reg ack_pending,stop_seen;
    assign req_ready=!device_busy && !stop_valid && !ack_pending;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            device_busy<=0; rsp_valid<=0; rsp_tag<=0; rsp_code<=0;
            active_tag<=0; elapsed<=0; ack_pending<=0; stop_seen<=0;
        end else begin
            rsp_valid<=0;
            if(!stop_valid) stop_seen<=0;
            if(stop_valid && !stop_seen) begin
                device_busy<=0; ack_pending<=0; elapsed<=0;
                rsp_valid<=1; rsp_tag<=stop_tag; rsp_code<=3; stop_seen<=1;
            end else if(ack_pending) begin
                rsp_valid<=1; rsp_tag<=active_tag; rsp_code<=2; ack_pending<=0;
            end else if(req_valid && req_ready) begin
                active_tag<=req_tag; device_busy<=1; elapsed<=0; ack_pending<=1;
            end else if(device_busy && tick_1ms) begin
                if(elapsed>=PLAY_TICKS-1) begin
                    device_busy<=0; rsp_valid<=1; rsp_tag<=active_tag; rsp_code<=0;
                end else elapsed<=elapsed+1'b1;
            end
        end
    end
endmodule
