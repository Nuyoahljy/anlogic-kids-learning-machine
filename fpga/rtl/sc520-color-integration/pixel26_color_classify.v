// T026 provisional sensor-domain rule from the fixed final05 field samples.
// 0 unknown, 1 R-largest/red, 2 G-largest/yellow, 3 B-largest/blue.
// Exact rational comparison, no division and no uncalibrated brightness cutoff.
module pixel26_color_classify(input wire [23:0] in_rgb,output wire [1:0] color_id);
    wire [7:0] r=in_rgb[23:16],g=in_rgb[15:8],b=in_rgb[7:0];
    wire [9:0] sum={2'b0,r}+{2'b0,g}+{2'b0,b};
    wire [7:0] competitor_r=g>b ? g:b;
    wire [7:0] competitor_g=r>b ? r:b;
    wire [7:0] competitor_b=r>g ? r:g;
    wire [7:0] dr=r>=competitor_r ? r-competitor_r:8'd0;
    wire [7:0] dg=g>=competitor_g ? g-competitor_g:8'd0;
    wire [7:0] db=b>=competitor_b ? b-competitor_b:8'd0;
    wire [14:0] mr=dr*15'd100,mg=dg*15'd100,mb=db*15'd100;
    wire [11:0] threshold=sum*12'd3;
    assign color_id=sum==0 ? 2'd0 : mr>=threshold ? 2'd1 :
                    mg>=threshold ? 2'd2 : mb>=threshold ? 2'd3 : 2'd0;
endmodule
