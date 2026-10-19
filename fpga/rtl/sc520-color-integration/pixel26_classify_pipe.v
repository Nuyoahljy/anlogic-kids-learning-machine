// Exact normalized classification, two capture-clock layers. All controls are
// delayed alongside this result by pixel26_block_recognizer_piped.
module pixel26_classify_pipe(input wire clk,rst_n,flush,input wire [23:0] in_rgb,
    output reg [1:0] color_id);
    wire [7:0] r=in_rgb[23:16],g=in_rgb[15:8],b=in_rgb[7:0];
    wire [7:0] cr=g>b ? g:b,cg=r>b ? r:b,cb=r>g ? r:g;
    reg [7:0] dr,dg,db;reg [9:0] sum;
    wire [14:0] er={7'd0,dr},eg={7'd0,dg},eb={7'd0,db};
    wire [14:0] mr=(er<<6)+(er<<5)+(er<<2),mg=(eg<<6)+(eg<<5)+(eg<<2),mb=(eb<<6)+(eb<<5)+(eb<<2);
    wire [11:0] es={2'b0,sum};wire [11:0] threshold=(es<<1)+es;
    always @(posedge clk or negedge rst_n)
        if(!rst_n)begin dr<=0;dg<=0;db<=0;sum<=0;color_id<=0;end
        else if(flush)begin dr<=0;dg<=0;db<=0;sum<=0;color_id<=0;end
        else begin
            dr<=r>=cr ? r-cr:8'd0;dg<=g>=cg ? g-cg:8'd0;db<=b>=cb ? b-cb:8'd0;
            sum<={2'b0,r}+{2'b0,g}+{2'b0,b};
            color_id<=sum==0 ? 2'd0:mr>=threshold ? 2'd1:mg>=threshold ? 2'd2:mb>=threshold ? 2'd3:2'd0;
        end
endmodule
