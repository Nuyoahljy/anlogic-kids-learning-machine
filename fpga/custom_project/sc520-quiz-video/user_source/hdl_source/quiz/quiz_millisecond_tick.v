// One clock-domain enable. Independent of video VS/DE and frame arrivals.
module quiz_millisecond_tick #(parameter integer CLOCK_HZ=75000000)(
    input wire clk, rst_n, output reg tick_1ms
);
    localparam integer DIVISOR=CLOCK_HZ/1000;
    localparam integer WIDTH=DIVISOR<2 ? 1 : $clog2(DIVISOR);
    reg [WIDTH-1:0] count;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin count<=0; tick_1ms<=0; end
        else begin
            tick_1ms<=0;
            if(count==DIVISOR-1) begin count<=0; tick_1ms<=1; end
            else count<=count+1'b1;
        end
    end
    // synthesis translate_off
    initial if(CLOCK_HZ<1000 || CLOCK_HZ%1000!=0) $fatal(1,"CLOCK_HZ must be a positive multiple of 1000");
    // synthesis translate_on
endmodule
