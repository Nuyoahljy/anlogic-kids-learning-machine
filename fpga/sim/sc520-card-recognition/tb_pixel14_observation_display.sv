`timescale 1ns/1ps
module tb_pixel14_observation_display;
  reg clk=0;always #5 clk=~clk;
  reg rst_n=0,frame_start=0,fresh=1;
  reg [10:0] pixel_x=0;reg [9:0] pixel_y=0;
  reg [799:0] packet=0;
  reg [7:0] age_ms=8'h12,business_flags=8'h43;
  reg [255:0] diagnostic=0;reg [31:0] i2c_diagnostic=32'h01413e02;
  wire active;wire [23:0] rgb;
  pixel14_color_diag_osd #(.VERSION(16'h0116)) dut(.*);
  integer errors=0,checks=0,scenarios=0,injected=0,inject_fault=0,unused,x,y,r,c,dy,i,fd;
  reg test_done=0,ref_fresh=1;
  reg [799:0] initial_packet;
  reg [255:0] initial_capture;
  string lines[0:5];reg [7:0] ch;reg [4:0] dots;reg region,cm,pm,on;reg [23:0] want,paint;
  task ck(input bit ok,input string message);begin checks++;if(!ok)begin errors++;if(errors<8)$display("FAIL display x=%0d y=%0d %s",x,y,message);end end endtask
    function [4:0] ref_glyph;
        input [7:0] ch;
        input [2:0] row;
        reg [34:0] bitmap;
        begin
            case(ch)
                "0":bitmap=35'b01110_10001_10011_10101_11001_10001_01110;
                "1":bitmap=35'b00100_01100_00100_00100_00100_00100_01110;
                "2":bitmap=35'b01110_10001_00001_00010_00100_01000_11111;
                "3":bitmap=35'b11110_00001_00001_01110_00001_00001_11110;
                "4":bitmap=35'b00010_00110_01010_10010_11111_00010_00010;
                "5":bitmap=35'b11111_10000_10000_11110_00001_00001_11110;
                "6":bitmap=35'b01110_10000_10000_11110_10001_10001_01110;
                "7":bitmap=35'b11111_00001_00010_00100_01000_01000_01000;
                "8":bitmap=35'b01110_10001_10001_01110_10001_10001_01110;
                "9":bitmap=35'b01110_10001_10001_01111_00001_00001_01110;
                "A":bitmap=35'b01110_10001_10001_11111_10001_10001_10001;
                "B":bitmap=35'b11110_10001_10001_11110_10001_10001_11110;
                "C":bitmap=35'b01111_10000_10000_10000_10000_10000_01111;
                "D":bitmap=35'b11110_10001_10001_10001_10001_10001_11110;
                "E":bitmap=35'b11111_10000_10000_11110_10000_10000_11111;
                "F":bitmap=35'b11111_10000_10000_11110_10000_10000_10000;
                "G":bitmap=35'b01111_10000_10000_10111_10001_10001_01111;
                "H":bitmap=35'b10001_10001_10001_11111_10001_10001_10001;
                "I":bitmap=35'b01110_00100_00100_00100_00100_00100_01110;
                "L":bitmap=35'b10000_10000_10000_10000_10000_10000_11111;
                "N":bitmap=35'b10001_11001_11001_10101_10011_10011_10001;
                "Q":bitmap=35'b01110_10001_10001_10001_10101_10010_01101;
                "R":bitmap=35'b11110_10001_10001_11110_10100_10010_10001;
                "Y":bitmap=35'b10001_10001_01010_00100_00100_00100_00100;
                "M":bitmap=35'b10001_11011_10101_10101_10001_10001_10001;
                "P":bitmap=35'b11110_10001_10001_11110_10000_10000_10000;
                "S":bitmap=35'b01111_10000_10000_01110_00001_00001_11110;
                "T":bitmap=35'b11111_00100_00100_00100_00100_00100_00100;
                "U":bitmap=35'b10001_10001_10001_10001_10001_10001_01110;
                "V":bitmap=35'b10001_10001_10001_10001_10001_01010_00100;
                "W":bitmap=35'b10001_10001_10001_10101_10101_11011_10001;
                "X":bitmap=35'b10001_10001_01010_00100_01010_10001_10001;
                "O":bitmap=35'b01110_10001_10001_10001_10001_10001_01110;
                "/":bitmap=35'b00001_00001_00010_00100_01000_10000_10000;
                ",":bitmap=35'b00000_00000_00000_00000_00100_00100_01000;
                "=":bitmap=35'b00000_11111_00000_11111_00000_00000_00000;
                default:bitmap=0;
            endcase
            case(row)
                0:ref_glyph=bitmap[34:30];1:ref_glyph=bitmap[29:25];2:ref_glyph=bitmap[24:20];
                3:ref_glyph=bitmap[19:15];4:ref_glyph=bitmap[14:10];5:ref_glyph=bitmap[9:5];
                6:ref_glyph=bitmap[4:0];default:ref_glyph=0;
            endcase
        end
    endfunction


  task reference;
    begin
      region=x>=32 && x<800 && y>=520 && y<592;
      cm=x>=634 && x<646 && y>=354 && y<366 && (x==634 || x==645 || y==354 || y==365);
      pm=x>=190 && x<202 && y>=142 && y<154 && (x==190 || x==201 || y==142 || y==153);
      want=0;
      if(region)begin
        r=(y-520)/12;dy=(y-520)%12;c=(x-32)/8;
        ch=c<lines[r].len() ? lines[r].getc(c):8'h20;dots=ref_glyph(ch,dy);
        on=(x-32)%8<5 && dy<7 && dots[4-((x-32)%8)];
        want=on ? (ref_fresh?24'hffff80:24'hff9c9c):24'h101820;
      end else if(cm)want=24'h00ffff;else if(pm)want=24'hff00ff;
    end
  endtask
  task scan(input integer y0,input integer y1,input bit save_image);
    begin
      for(y=y0;y<=y1;y++)for(x=0;x<1280;x++)begin
        @(negedge clk);pixel_x=x;pixel_y=y;
        // Change all live payload fields mid-frame. Published text must keep
        // the initial snapshot until the next frame_start, including lower rows.
        if(x==0 && y==550)begin packet=~packet;age_ms=255;diagnostic=~diagnostic;i2c_diagnostic=0;end
        @(posedge clk);#1;reference;
        if(inject_fault && !injected && x==32 && y==520)begin force dut.rgb=24'h000001;injected=1;#1;end
        ck(active===(region||cm||pm),"diagnostic region and sample-window borders");
        ck(rgb===want,"independent literal text/hex fields and sampled pixel positions");
        if(inject_fault && injected)release dut.rgb;
        if(save_image)begin
          paint=active ? rgb:{8'(x/5+30),8'(y/4+45),8'h50};
          $fwrite(fd,"%c%c%c",paint[23:16],paint[15:8],paint[7:0]);
        end
      end
    end
  endtask
  initial begin
    unused=$value$plusargs("INJECT_FAULT=%d",inject_fault);
    lines[0]="D0116 F12345678 V1 A12 X00 E0040 B43 Q01413E02 GR0FF GB102 N00ABC0 W1 T1";
    lines[1]="C0A08080 C19F8080 C2B79D9D P0F0E8E0 P1EFF0E2 P2F4F5EA C280,168 P0C4,094";
    lines[2]="MC09E7E7E MC19B7E7E MC2B69B9B MP0E8E0D8 MP1E7E8DA MP2EEEFE4 0=RAW 1=WB 2=TONE";
    lines[3]="R00001 /00004 /00007 Y00002 /00005 /00008 B00003 /00006 /00009 RAW THRESHOLD COUNTS";
    lines[4]="S0456 G0033 P0123 V35 RB2 SH5 D013 /045 /089 BC03 CC00 I2 M021 /050 /3AA ";
    lines[5]="LC010203040506 HC0A0B0C0D0E0F C46500 R38400 I38400 H0330 L02D0 Y02D0 ";
    packet[31:0]=32'h12345678;packet[780]=1;
    packet[175:32]={24'hf4f5ea,24'heff0e2,24'hf0e8e0,24'hb79d9d,24'h9f8080,24'ha08080};
    packet[319:176]={24'heeefe4,24'he7e8da,24'he8e0d8,24'hb69b9b,24'h9b7e7e,24'h9e7e7e};
    for(i=0;i<6;i++)begin packet[320+i*7+:7]=i+1;packet[362+i*7+:7]=i+10;end
    packet[412:404]=255;packet[421:413]=258;packet[442:422]=21'h00abc0;
    for(i=0;i<9;i++)packet[443+i*20+:20]=i+1;
    packet[638:623]=16'h0456;packet[654:639]=16'h0033;packet[670:655]=16'h0123;
    packet[678:671]=8'h35;packet[682:679]=2;packet[685:683]=5;
    packet[718:686]={11'h089,11'h045,11'h013};packet[726:719]=3;packet[734:727]=0;packet[738:735]=2;
    packet[749:739]=11'h021;packet[760:750]=11'h050;packet[771:761]=11'h3aa;
    diagnostic[239:224]=16'h0040;diagnostic[223:208]=16'h0330;
    diagnostic[191:160]=32'h46500;diagnostic[159:128]=32'h38400;diagnostic[127:96]=32'h38400;
    diagnostic[95:80]=16'h02d0;diagnostic[79:64]=16'h02d0;
    initial_packet=packet;initial_capture=diagnostic;
    scenarios++;repeat(4)@(negedge clk);rst_n=1;frame_start=1;@(negedge clk);frame_start=0;
    fd=$fopen("observation-panel.ppm","wb");$fwrite(fd,"P6\n1280 720\n255\n");scan(0,719,1);$fclose(fd);
    scenarios++;fresh=0;ref_fresh=0;lines[0]="D0116 F12345678 V0 A12 X00 E0040 B43 Q01413E02 GR0FF GB102 N00ABC0 W1 T1";
    scan(520,591,0);
    scenarios++;fresh=1;scan(520,531,0); // A new arrival cannot revalidate the old frame snapshot.
    scenarios++;@(negedge clk);packet=initial_packet;diagnostic=initial_capture;age_ms=8'h12;i2c_diagnostic=32'h01413e02;frame_start=1;
    @(negedge clk);frame_start=0;ref_fresh=1;lines[0]="D0116 F12345678 V1 A12 X00 E0040 B43 Q01413E02 GR0FF GB102 N00ABC0 W1 T1";scan(520,531,0);
    scenarios++;@(negedge clk);rst_n=0;#1;ck(!active && rgb==0,"asynchronous reset removes diagnostic pixels");
    test_done=1;$display("DONE observation display checks=%0d errors=%0d",checks,errors);$finish;
  end
  initial begin #20000000;$display("WATCHDOG observation display");$finish;end
endmodule
