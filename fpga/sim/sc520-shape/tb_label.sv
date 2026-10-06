`timescale 1ns/1ps
module tb_label;
    reg [10:0] pixel_x=0;
    reg [9:0] pixel_y=0;
    reg box_valid=0;
    reg [1:0] shape=0,color=0;
    wire active;
    wire [23:0] rgb;
    integer errors=0,checked=0,shape_index,color_index,xpos,ypos;
    reg test_done=0;
    reg [34:0] bitmap [0:3];
    reg expected_active,lit;
    reg [23:0] ink;
    shape_label dut(.*);
    initial begin
        bitmap[0]=35'b01110_10001_00001_00010_00100_00000_00100;
        bitmap[1]=35'b01111_10000_10000_10000_10000_10000_01111;
        bitmap[2]=35'b01111_10000_10000_01110_00001_00001_11110;
        bitmap[3]=35'b11111_00100_00100_00100_00100_00100_00100;
        for(shape_index=0;shape_index<4;shape_index=shape_index+1)
            for(color_index=1;color_index<=3;color_index=color_index+1)
                for(ypos=0;ypos<100;ypos=ypos+1)
                    for(xpos=0;xpos<100;xpos=xpos+1)begin
                        pixel_x=xpos;pixel_y=ypos;shape=shape_index;color=color_index;box_valid=1;#1;
                        expected_active=xpos>=32&&xpos<72&&ypos>=32&&ypos<88;
                        if(active!==expected_active)errors=errors+1;
                        if(expected_active)begin
                            lit=bitmap[shape_index][34-((ypos-32)/8)*5-(xpos-32)/8];
                            ink=shape_index==0?24'hffffff:color_index==1?24'hff0000:color_index==2?24'hffff00:24'h0000ff;
                            if(rgb!==(lit?ink:24'h202020))errors=errors+1;
                        end
                        checked=checked+1;
                    end
        box_valid=0;pixel_x=32;pixel_y=32;#1;if(active)errors=errors+1;
        test_done=1;$display("RESULT label errors=%0d checked=%0d",errors,checked);$stop;
    end
endmodule
