// Explicit test-boundary models, not vendor physical/IP qualification.
// The actual unmodified awb.v and signal_delay.v are compiled by the runner.
// Divider is unsigned 48/32 with the documented PIPLE=50 latency.
module divider(input clk,rst,start,input [31:0] denominator,input [47:0] numerator,
               output [47:0] quotient,output [31:0] remainder,output done);
  reg [47:0] q[0:49];reg [31:0] r[0:49];reg [49:0] v;
  integer i;
  always @(posedge clk)begin
    if(rst)begin v<=0;for(i=0;i<50;i=i+1)begin q[i]<=0;r[i]<=0;end end
    else begin
      v<={v[48:0],start};q[0]<=denominator ? numerator/denominator : 48'hffffffffffff;
      r[0]<=denominator ? numerator%denominator : 0;
      for(i=1;i<50;i=i+1)begin q[i]<=q[i-1];r[i]<=r[i-1];end
    end
  end
  assign quotient=q[49];assign remainder=r[49];assign done=v[49];
endmodule
module blk_mem_gen_awb_delay_signal(input clka,wea,input [10:0] addra,input [95:0] dia,
  input clkb,input [10:0] addrb,output reg [95:0] dob);
  reg [95:0] mem[0:2047];
  always @(posedge clka)if(wea)mem[addra]<=dia;
  always @(posedge clkb)dob<=mem[addrb];
endmodule
