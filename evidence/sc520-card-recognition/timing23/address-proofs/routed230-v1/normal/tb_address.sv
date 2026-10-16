`timescale 1ns/1ps
module tb_address;
reg clk=0,rst_n=1,ce=0;reg [10:0] leaves=0;
wire rclk;wire [2:0] q_gate,q_route,d_gate;
reg [5:0] startup;reg [2:0] expected;
integer errors=0,checks=0,rows=0,prev,rv,cv,v,i,injected=0;
reg test_done=0;
AL_MAP_LUT2 #(
 .EQN("(B*~A)"),
 .INIT(4'h4)
) gate_lut_0(
 .a(leaves[1]),
 .b(leaves[4]),
 .o(d_gate[0])
);
AL_MAP_SEQ_GSR #(
 .CEMUX("SIG"),
 .CLKMUX("SIG"),
 .DFFMODE("FF"),
 .REGSET("RESET"),
 .SRMODE("ASYNC"),
 .SRMUX("INV")
) gate_ff_0(
 .ce(ce),
 .clk(clk),
 .d(d_gate[0]),
 .sr(rst_n),
 .q(q_gate[0])
);
PH1P_PHY_LSLICE #(
 .ASRMUX("INV"),
 .CEAMUX("SIG"),
 .CLKMUX("SIG"),
 .INIT_LUT5A(32'b00000000111111110000000000000000),
 .INIT_LUT5B(32'b00000000000000000000110000001100),
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
 .SSRMUX("0"),
 .SSROVERCE("ENABLE")
) route_ff_0(
 .asr(rst_n),
 .cea(ce),
 .clk(rclk),
 .id(leaves[1]),
 .imf(leaves[4]),
 .oqa(q_route[0])
);
wire unused_1_ofb;
AL_MAP_LUT2 #(
 .EQN("(B*~A)"),
 .INIT(4'h4)
) gate_lut_1(
 .a(leaves[1]),
 .b(leaves[5]),
 .o(d_gate[1])
);
AL_MAP_SEQ_GSR #(
 .CEMUX("SIG"),
 .CLKMUX("SIG"),
 .DFFMODE("FF"),
 .REGSET("RESET"),
 .SRMODE("ASYNC"),
 .SRMUX("INV")
) gate_ff_1(
 .ce(ce),
 .clk(clk),
 .d(d_gate[1]),
 .sr(rst_n),
 .q(q_gate[1])
);
PH1P_PHY_LSLICE #(
 .ASRMUX("INV"),
 .CEAMUX("SIG"),
 .CLKMUX("SIG"),
 .INIT_LUT5A(32'b00110011001100110000000000000000),
 .INIT_LUT5B(32'b00000000000000001111111111110000),
 .LATCHMODE("DFF"),
 .LUT5A_SD1("IMF"),
 .LUT5B_SD2("ID"),
 .LUTMODE("DLUT5"),
 .OFA_SD("LUT5A"),
 .OFB_SD("LUTX"),
 .OQAMUX("QA"),
 .OQBMUX("QB"),
 .REGA_REGSET_ASYNC("RESET"),
 .REGA_REGSET_SYNC("RESET"),
 .REGA_SD("LUT5A"),
 .SSRMUX("0"),
 .SSROVERCE("ENABLE")
) route_ff_1(
 .asr(rst_n),
 .cea(ce),
 .clk(rclk),
 .ib(leaves[1]),
 .ic(leaves[0]),
 .id(leaves[2]),
 .ie(leaves[3]),
 .imf(leaves[5]),
 .ofb(unused_1_ofb),
 .oqa(q_route[1])
);
wire unused_2_ofb;
AL_MAP_LUT2 #(
 .EQN("(B*~A)"),
 .INIT(4'h4)
) gate_lut_2(
 .a(leaves[1]),
 .b(leaves[6]),
 .o(d_gate[2])
);
AL_MAP_SEQ_GSR #(
 .CEMUX("SIG"),
 .CLKMUX("SIG"),
 .DFFMODE("FF"),
 .REGSET("RESET"),
 .SRMODE("ASYNC"),
 .SRMUX("INV")
) gate_ff_2(
 .ce(ce),
 .clk(clk),
 .d(d_gate[2]),
 .sr(rst_n),
 .q(q_gate[2])
);
PH1P_PHY_LSLICE #(
 .ASRMUX("INV"),
 .CEAMUX("SIG"),
 .CLKMUX("SIG"),
 .INIT_LUT5A(32'b00000000111111110000000000000000),
 .INIT_LUT5B(32'b00000010000000100000000000000000),
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
 .SSRMUX("0"),
 .SSROVERCE("ENABLE")
) route_ff_2(
 .asr(rst_n),
 .cea(ce),
 .clk(rclk),
 .ia(leaves[10]),
 .ib(leaves[8]),
 .ic(leaves[9]),
 .id(leaves[1]),
 .ie(leaves[7]),
 .imf(leaves[6]),
 .ofb(unused_2_ofb),
 .oqa(q_route[2])
);
PH1P_PHY_SCLK_V2 #(
 .BYPASS("DISABLE")
) physical_clock(
 .clkin(clk),
 .clkout(rclk)
);

task ck(input integer id,input got,input want);begin
 checks=checks+1;if(got!==want)begin errors=errors+1;
 if(errors<5)$display("MISMATCH id=%0d t=%0t got=%b want=%b",id,$time,got,want);end
end endtask
task allq(input integer id,input [2:0] want);begin
 for(i=0;i<3;i=i+1)begin ck(id+i,q_gate[i],want[i]);ck(id+3+i,q_route[i],want[i]);end
end endtask
task tick;begin #1;clk=1;#1;clk=0;#1;end endtask
task preset(input p);begin rst_n=1;ce=1;clk=0;leaves=0;leaves[4]=p;leaves[5]=p;leaves[6]=p;tick;allq(10,{3{p}});end endtask
initial begin
 #1;startup={q_gate,q_route};$display("STARTUP_UNQUALIFIED %b",startup);
 #99;rst_n=0;#1;allq(1,0);rst_n=1;#1;
 for(prev=0;prev<2;prev=prev+1)
 for(rv=0;rv<2;rv=rv+1)
 for(cv=0;cv<2;cv=cv+1)
 for(v=0;v<2048;v=v+1)begin
  preset(prev[0]);leaves=v;ce=cv;rst_n=rv;#1;
  ck(20,d_gate[0],leaves[4]&~leaves[1]);ck(20,d_gate[1],leaves[5]&~leaves[1]);ck(20,d_gate[2],leaves[6]&~leaves[1]);
  expected=rv ? {3{prev[0]}} : 0;allq(30,expected);
  #1;clk=1;#1;expected[0]=rv ? (cv ? (leaves[4]&~leaves[1]) : prev[0]) : 0;expected[1]=rv ? (cv ? (leaves[5]&~leaves[1]) : prev[0]) : 0;expected[2]=rv ? (cv ? (leaves[6]&~leaves[1]) : prev[0]) : 0;allq(40,expected);ck(46,rclk,clk);
  #1;clk=0;#1;allq(50,expected);ck(56,rclk,clk);rows=rows+1;
 end
 for(v=0;v<2;v=v+1)begin
  preset(1);ce=0;clk=v;#1;allq(60,7);rst_n=0;#1;allq(70,0);rst_n=1;#1;allq(80,0);
 end
 if(0)begin
  injected=1;force q_route[0]=1'b1;#1;ck(90,q_route[0],1'b0);release q_route[0];
 end
 test_done=1;$display("ADDRESS_DONE checks=%0d rows=%0d errors=%0d injected=%0d",checks,rows,errors,injected);$finish;
end
endmodule
