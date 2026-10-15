`timescale 1ns/1ps
module tb_duplicate_q;
reg clk=0,rst_n=1,ce=0;reg [7:0] leaves=0;
wire rclk,q_gate,q_dup3,q_dup4,d_gate,d_route,qa3,qa4;
integer errors=0,checks=0,rows=0,comb_rows=0,prev,rv,cv,v,pol;
reg test_done=0;reg expected;
AL_MAP_LUT2 #(
 .EQN("(B*~A)"),
 .INIT(4'h4)
) gate_lut(
 .a(leaves[0]),
 .b(leaves[1]),
 .o(d_gate)
);
AL_MAP_SEQ_GSR #(
 .CEMUX("SIG"),
 .CLKMUX("SIG"),
 .DFFMODE("FF"),
 .REGSET("RESET"),
 .SRMODE("ASYNC"),
 .SRMUX("INV")
) gate_ff(
 .ce(ce),
 .clk(clk),
 .d(d_gate),
 .sr(rst_n),
 .q(q_gate)
);
PH1P_PHY_SCLK_V2 #(
 .BYPASS("DISABLE")
) route_buffer(
 .clkin(clk),
 .clkout(rclk)
);
PH1P_PHY_LSLICE #(
 .ASRMUX("INV"),
 .CEAMUX("1"),
 .CEBMUX("SIG"),
 .CLKMUX("SIG"),
 .INIT_LUT5A(32'b11001100000010101010101010101010),
 .LATCHMODE("DFF"),
 .LUT5A_SD0("IMA"),
 .LUT5A_SD1("IMF"),
 .LUTMODE("DLUT5"),
 .OFA_SD("LUT5A"),
 .OQAMUX("QA"),
 .OQBMUX("QB"),
 .REGA_REGSET_ASYNC("RESET"),
 .REGA_REGSET_SYNC("RESET"),
 .REGA_SD("LUT5A"),
 .REGB_REGSET_ASYNC("RESET"),
 .REGB_REGSET_SYNC("RESET"),
 .REGB_SD("IMB"),
 .SSRMUX("0"),
 .SSROVERCE("ENABLE")
) route_dup3(
 .asr(rst_n),
 .ceb(ce),
 .clk(rclk),
 .ia(leaves[3]),
 .ib(leaves[4]),
 .id(leaves[5]),
 .ima(leaves[6]),
 .imb(d_route),
 .imf(leaves[7]),
 .oqa(qa3),
 .oqb(q_dup3)
);
PH1P_PHY_LSLICE #(
 .ASRMUX("INV"),
 .CEAMUX("SIG"),
 .CEBMUX("SIG"),
 .CLKMUX("SIG"),
 .INIT_LUT5A(32'b01010101010101010000000000000000),
 .INIT_LUT5B(32'b01010101010101010000000000000000),
 .LATCHMODE("DFF"),
 .LUT5A_SD1("IMF"),
 .LUTMODE("DLUT5"),
 .OFA_SD("LUT5A"),
 .OFB_SD("LUTX"),
 .OQAMUX("QA"),
 .OQBMUX("QB"),
 .REGA_REGSET_ASYNC("RESET"),
 .REGA_REGSET_SYNC("RESET"),
 .REGA_SD("LUT5A"),
 .REGB_REGSET_ASYNC("RESET"),
 .REGB_REGSET_SYNC("RESET"),
 .REGB_SD("LUT6"),
 .SSRMUX("0"),
 .SSROVERCE("ENABLE")
) route_dup4(
 .asr(rst_n),
 .cea(ce),
 .ceb(ce),
 .clk(rclk),
 .ia(leaves[0]),
 .ie(leaves[1]),
 .imf(leaves[2]),
 .ofb(d_route),
 .oqa(qa4),
 .oqb(q_dup4)
);

task ck(input integer id,input got,input want);begin
 checks=checks+1;
 if(got!==want)begin errors=errors+1;if(errors<12)$display("MISMATCH id=%0d time=%0t got=%b want=%b leaves=%h ce=%b rst=%b prev=%0d",id,$time,got,want,leaves,ce,rst_n,prev);end
end endtask
task allq(input integer id,input want);begin ck(id,q_gate,want);ck(id+1,q_dup3,want);ck(id+2,q_dup4,want);end endtask
task tick;begin #1;clk=1;#1;clk=0;#1;end endtask
task preset(input p);begin
 rst_n=1;ce=1;clk=0;leaves=0;leaves[1]=p;leaves[2]=p;tick;allq(10,p);
end endtask
initial begin
 // Vendor configuration models assert their own power-up reset. Check zero
 // at 1ns, but compare normal transitions only after both done_gwe intervals.
 #1;allq(1,0);#24;rst_n=0;#1;allq(4,0);rst_n=1;#1;
 for(prev=0;prev<2;prev=prev+1)
 for(rv=0;rv<2;rv=rv+1)
 for(cv=0;cv<2;cv=cv+1)
 for(v=0;v<256;v=v+1)begin
   preset(prev[0]);
   leaves=v;ce=cv;rst_n=rv;#1;
   ck(20,d_gate,leaves[1]&~leaves[0]);ck(21,d_route,d_gate);comb_rows=comb_rows+1;
   expected=rv ? prev[0] : 1'b0;allq(30,expected);
   #1;clk=1;#1;
   expected=rv ? (cv ? (leaves[1]&~leaves[0]) : prev[0]) : 1'b0;
   allq(40,expected);ck(43,rclk,clk);
   #1;clk=0;#1;allq(50,expected);ck(53,rclk,clk);
   rows=rows+1;
 end
 // Async assertion at both clock levels, with CE=0 and a loaded one.
 for(pol=0;pol<2;pol=pol+1)begin
   preset(1);ce=0;clk=pol;#1;allq(60,1);
   rst_n=0;#1;allq(70,0);rst_n=1;#1;allq(80,0);
 end
 test_done=1;$display("DUPLICATE_Q_DONE rows=%0d comb_rows=%0d checks=%0d errors=%0d",rows,comb_rows,checks,errors);$finish;
end
initial begin #100000; $display("DUPLICATE_Q_WATCHDOG");$finish;end
endmodule
