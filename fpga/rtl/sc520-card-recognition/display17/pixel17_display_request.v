// Consume the existing debounced pulses; never generate business events.
// next_request is used at frame start, so a K3/K4 on that edge is effective.
module pixel17_display_request(
    input wire clk,rst_n,
    input wire [1:0] business_mode,
    input wire key_mode_pulse,key_skip_pulse,key_reset_pulse,
    output reg requested,
    output wire next_request
);
    assign next_request=key_reset_pulse ? 1'b0 :
        (!key_mode_pulse && key_skip_pulse && business_mode<2) ? !requested:requested;
    always @(posedge clk or negedge rst_n)
        if(!rst_n)requested<=0;else requested<=next_request;
endmodule
