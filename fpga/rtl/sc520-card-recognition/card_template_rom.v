// Task-local synchronous ROM. Address y*32+x; bits 0..4 are item IDs 10..14.
// The file contains exactly 1024 hexadecimal words, each holding five bits.
module card_template_rom #(
    parameter TEMPLATE_FILE = "templates.mem"
) (
    input wire clk,
    input wire en,
    input wire [9:0] addr,
    output reg [4:0] data
);
    reg [4:0] template_mem [0:1023];
    // synthesis translate_off
    integer verify_index;
    // synthesis translate_on
    initial begin
        $readmemh(TEMPLATE_FILE, template_mem);
        // synthesis translate_off
        for (verify_index = 0; verify_index < 1024; verify_index = verify_index + 1)
            if ((^template_mem[verify_index]) === 1'bx)
                $fatal(1, "card_template_rom missing or unknown template word %0d", verify_index);
        // synthesis translate_on
    end
    always @(posedge clk)
        if (en) data <= template_mem[addr];
endmodule
