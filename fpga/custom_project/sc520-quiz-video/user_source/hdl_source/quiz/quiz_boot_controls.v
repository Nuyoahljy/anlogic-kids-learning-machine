// Clearly labeled simulated controls: two one-shot mode pulses after reset.
// Hardware candidate enters quiz automatically; no physical key mapping added.
module quiz_boot_controls #(parameter integer CLOCK_HZ=75000000)(
    input wire clk,rst_n, output reg key_mode_pulse
);
    reg [1:0] reset_pipe;
    always @(posedge clk or negedge rst_n)
        if(!rst_n) reset_pipe<=0; else reset_pipe<={reset_pipe[0],1'b1};
    wire tick;
    reg [11:0] elapsed_ms;
    quiz_millisecond_tick #(.CLOCK_HZ(CLOCK_HZ)) timer(clk,reset_pipe[1],tick);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin elapsed_ms<=0; key_mode_pulse<=0; end
        else begin
            key_mode_pulse<=0;
            if(tick && elapsed_ms<2001) begin
                elapsed_ms<=elapsed_ms+1'b1;
                if(elapsed_ms==999 || elapsed_ms==1999) key_mode_pulse<=1;
            end
        end
    end
endmodule
