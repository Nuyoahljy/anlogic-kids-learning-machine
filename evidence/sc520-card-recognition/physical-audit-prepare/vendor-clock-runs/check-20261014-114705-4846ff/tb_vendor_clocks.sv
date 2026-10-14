`timescale 1ns/1ps
module tb_vendor_clocks;
reg clk0=0,clk1=0;always #5 clk0=~clk0;always #7 clk1=~clk1;
wire global_clock,local_clock;
PH1P_PHY_GCLK g(.clkin({clk1,clk0}),.cen(2'b00),.drct(2'b11),.seln(2'b10),.clkout(global_clock));
PH1P_PHY_SCLK_V2 #(.BYPASS("DISABLE")) s(.clkin(global_clock),.clkout(local_clock));
integer checks=0,errors=0,i;reg test_done=0;reg [3:0] combinations=0;
task ck;begin
 checks=checks+2;combinations[{clk1,clk0}]=1;
 if(global_clock!==clk0)begin errors=errors+1;$display("GCLK mismatch %0t %b %b",$time,global_clock,clk0);end
 if(local_clock!==clk0)begin errors=errors+1;$display("SCLK mismatch %0t %b %b",$time,local_clock,clk0);end
end endtask
initial begin
 #201;
 for(i=0;i<128;i=i+1)begin @(posedge clk0);#1;ck;@(negedge clk0);#1;ck;end
 if(combinations!==4'b1111)errors=errors+1;
 test_done=1;$display("CLOCK_DONE checks=%0d errors=%0d combinations=%b",checks,errors,combinations);$finish;
end
initial begin #10000;$display("CLOCK_WATCHDOG");$finish;end
endmodule
