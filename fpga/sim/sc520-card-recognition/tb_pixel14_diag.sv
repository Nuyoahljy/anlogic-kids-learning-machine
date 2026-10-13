`timescale 1ns/1ps
module tb_pixel14_diag;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,frame_start=0;
    reg [10:0] pixel_x=0;reg [9:0] pixel_y=0;
    reg [255:0] diagnostic=0;reg [7:0] business_flags=0;
    wire active;wire [23:0] rgb;
    pixel14_diag_osd dut(.*);
    integer errors=0,checks=0,scenarios=0,injected=0,inject_fault=0,unused;
    reg test_done=0;
    task ck(input bit pass,input string message);
        begin checks++;if(!pass)begin errors++;$display("ERROR diag %s",message);end end
    endtask
    task point(input integer x,input integer y,input bit a,input reg [23:0] color);
        begin
            @(negedge clk);pixel_x=x;pixel_y=y;
            @(posedge clk);#1;ck(active===a,"region/one clock alignment");
            ck(rgb===color,"selected public glyph pixel");
        end
    endtask
    task latch;
        begin @(negedge clk);frame_start=1;@(negedge clk);frame_start=0;end
    endtask
    initial begin
        unused=$value$plusargs("INJECT_FAULT=%d",inject_fault);
        repeat(80)@(negedge clk);rst_n=1;
        diagnostic={16'h0107,16'h0002,16'h0324,16'h8003,
            16'h0004,16'h6500,16'h0003,16'h8400,16'h0003,16'h8400,
            16'h02d0,16'h02d0,16'h0010,16'h0000,16'h002a,16'h001b};
        business_flags=8'h43;latch();
        scenarios++;
        point(31,520,0,0);point(32,519,0,0);point(800,520,0,0);point(32,592,0,0);
        point(799,591,1,24'h101820);
        scenarios++;
        // D top row is 11110; each bit occupies two horizontal pixels.
        point(32,520,1,24'hffff80);point(39,520,1,24'hffff80);
        point(40,520,1,24'h101820);point(42,520,1,24'h101820);
        // Header is D0107: the zero top row starts with an unlit pixel.
        point(48,520,1,24'h101820);point(50,520,1,24'hffff80);
        // The last error digit is '2': middle row 00100 has its center on.
        point(196,528,1,24'hffff80);point(192,528,1,24'h101820);
        scenarios++;
        // Changing input metadata mid-display-frame must not change characters.
        diagnostic[227:224]=4'h1;business_flags=0;
        point(194,520,1,24'hffff80); // old digit 2: 01110
        latch();point(194,520,1,24'h101820); // new digit 1: 00100
        point(196,520,1,24'hffff80);
        scenarios++;
        // C at row 1 and L at row 2 have different bottom rows.
        point(32,544,1,24'h101820);point(34,544,1,24'hffff80);
        point(32,568,1,24'hffff80);point(40,580,1,24'hffff80);
        point(32,582,1,24'h101820);
        scenarios++;
        @(negedge clk);pixel_x=0;pixel_y=0;
        #1;ck(active===1,"output retains preceding pixel until next edge");
        @(posedge clk);#1;ck(active===0 && rgb===0,"output advances together");
        if(inject_fault)begin
            force dut.active=1;injected=1;#1;ck(active===0,"real active output fault detected");release dut.active;
        end
        scenarios++;
        @(negedge clk);rst_n=0;#1;ck(active===0 && rgb===0,"asynchronous reset clears pixel output");
        $display("DIAG_COMPLETE scenarios=%0d checks=%0d errors=%0d",scenarios,checks,errors);
        test_done=1;$finish;
    end
    initial begin #200000;$display("DIAG_WATCHDOG");$finish;end
endmodule
