// Per-class template variants. Word bit = class * VARIANTS + variant.
// One synchronous read; 1024 words retain the 32x32 normalized sample contract.
module pixel14_card_template_rom #(
    parameter TEMPLATE_FILE="templates.mem",
    parameter integer VARIANTS=1
) (
    input wire clk,en,
    input wire [9:0] addr,
    output reg [5*VARIANTS-1:0] data
);
    reg [5*VARIANTS-1:0] template_mem [0:1023];
    // synthesis translate_off
    integer i;
    // synthesis translate_on
    initial begin
        $readmemh(TEMPLATE_FILE,template_mem);
        // synthesis translate_off
        if(VARIANTS<1 || VARIANTS>9) $fatal(1,"pixel14 template variant count invalid");
        for(i=0;i<1024;i=i+1)
            if((^template_mem[i])===1'bx) $fatal(1,"pixel14 missing template word %0d",i);
        // synthesis translate_on
    end
    always @(posedge clk) if(en) data<=template_mem[addr];
endmodule
