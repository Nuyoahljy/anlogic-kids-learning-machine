// Display-only x1.25 saturation around Q8 BT.601 luma; nearest DN, clipped.
// n=1280*C-(77R+150G+29B), output=clip(floor((n+512)/1024)).
// All math explicitly sized; no intermediate luma truncation. No registers.
module pixel26_saturation(input wire [23:0] in_rgb,output wire [23:0] out_rgb);
    wire [7:0] r=in_rgb[23:16],g=in_rgb[15:8],b=in_rgb[7:0];
    wire [17:0] weighted=r*18'd77+g*18'd150+b*18'd29;
    function [7:0] channel;
        input [7:0] c;
        input [17:0] y;
        reg signed [19:0] numerator;
        begin
            numerator=$signed({2'b0,c,10'b0})+$signed({4'b0,c,8'b0})-$signed({2'b0,y})+20'sd512;
            channel=numerator<0 ? 8'd0:numerator>=20'sd261120 ? 8'd255:numerator[17:10];
        end
    endfunction
    assign out_rgb={channel(r,weighted),channel(g,weighted),channel(b,weighted)};
endmodule
