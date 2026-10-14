module color_timing_top(input wire clk,rst_n,sof,eol,valid,input wire [7:0] pixel_byte,
output reg [7:0] observe,output wire o_valid,o_sof,o_eol);
reg [95:0] pixels;
always @(posedge clk) pixels<={pixels[87:0],pixel_byte};
wire [95:0] rgb;
pixel14_color_pipeline u_color(.I_clk(clk),.I_rst_n(rst_n),.I_tlast(eol),.I_tuser(sof),.I_tdata(pixels),.I_tvalid(valid),
.I_tready(),.O_tlast(o_eol),.O_tuser(o_sof),.O_tdata(rgb),.O_tvalid(o_valid),.O_tready(1'b1));
always @(posedge clk) observe<=rgb[95:88]^rgb[87:80]^rgb[79:72]^rgb[71:64]^rgb[63:56]^rgb[55:48]^
rgb[47:40]^rgb[39:32]^rgb[31:24]^rgb[23:16]^rgb[15:8]^rgb[7:0];
endmodule
