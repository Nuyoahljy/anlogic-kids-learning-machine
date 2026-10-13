`timescale 1ns/1ps
module tb_pixel14_diag;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,frame_start=0;
    reg [10:0] pixel_x=0;reg [9:0] pixel_y=0;
    reg [255:0] diagnostic=0;reg [7:0] business_flags=0;
    reg [31:0] i2c_diagnostic=0;
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
    task q_digit(input integer index,input reg [34:0] bitmap);
        integer row,col;
        begin
            for(row=0;row<7;row++)for(col=0;col<5;col++)
                point(32+16*(29+index)+2*col,520+2*row,1,
                    bitmap[34-5*row-col] ? 24'hffff80 : 24'h101820);
        end
    endtask
    initial begin
        unused=$value$plusargs("INJECT_FAULT=%d",inject_fault);
        repeat(80)@(negedge clk);rst_n=1;
        diagnostic={16'h0109,16'h0002,16'h0324,16'h8003,
            16'h0004,16'h6500,16'h0003,16'h8400,16'h0003,16'h8400,
            16'h02d0,16'h02d0,16'h0010,16'h0000,16'h002a,16'h001b};
        i2c_diagnostic=32'h12345678;
        business_flags=8'h43;latch();
        scenarios++;
        point(31,520,0,0);point(32,519,0,0);point(800,520,0,0);point(32,592,0,0);
        point(799,591,1,24'h101820);
        scenarios++;
        // D top row is 11110; each bit occupies two horizontal pixels.
        point(32,520,1,24'hffff80);point(39,520,1,24'hffff80);
        point(40,520,1,24'h101820);point(42,520,1,24'h101820);
        // Header is D0109: the zero top row starts with an unlit pixel.
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
        q_digit(0,35'b00100_01100_00100_00100_00100_00100_01110);
        q_digit(1,35'b01110_10001_00001_00010_00100_01000_11111);
        q_digit(2,35'b11110_00001_00001_01110_00001_00001_11110);
        q_digit(3,35'b00010_00110_01010_10010_11111_00010_00010);
        q_digit(4,35'b11111_10000_10000_11110_00001_00001_11110);
        q_digit(5,35'b01110_10000_10000_11110_10001_10001_01110);
        q_digit(6,35'b11111_00001_00010_00100_01000_01000_01000);
        q_digit(7,35'b01110_10001_10001_01110_10001_10001_01110);
        // Mid-frame context changes are invisible until the next snapshot.
        i2c_diagnostic=0;
        q_digit(0,35'b00100_01100_00100_00100_00100_00100_01110);
        latch();q_digit(0,35'b01110_10001_10011_10101_11001_10001_01110);
        scenarios++;
        // Camera diagnostic may remain at reset while the independent I2C path reports failure.
        diagnostic=0;i2c_diagnostic=32'h03133107;latch();
        q_digit(0,35'b01110_10001_10011_10101_11001_10001_01110);
        q_digit(1,35'b11110_00001_00001_01110_00001_00001_11110);
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
