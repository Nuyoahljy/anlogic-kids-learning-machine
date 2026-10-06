`timescale 1ns/1ps
module tb_classifier;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0,in_frame=0,in_valid=0;
    reg [1:0] in_color=1;
    reg [21:0] in_area=0;
    reg [10:0] in_left=400,in_right=439;
    reg [9:0] in_top=200,in_bottom=239;
    wire out_frame;
    wire [1:0] out_shape,out_color;
    wire [23:0] out_box_area;
    integer errors=0,checked=0,fill_index,color_index,width_index;
    reg test_done=0;
    shape_classifier dut(.*);
    task automatic fail(input string message);
        begin errors=errors+1;if(errors<=8)$display("ERROR classifier %s checked=%0d",message,checked);end
    endtask
    task automatic sample(input integer width,height,area,input bit valid,input integer xpos,ypos,
                          input integer color,input integer expected_shape);
        integer cycle;
        begin
            @(negedge clk);in_frame=1;in_valid=valid;in_left=xpos;in_right=xpos+width-1;
            in_top=ypos;in_bottom=ypos+height-1;in_area=area;in_color=color;
            @(posedge clk);#1;if(out_frame)fail("early strobe");
            @(negedge clk);in_frame=0;in_area=0;
            for(cycle=1;cycle<=14;cycle=cycle+1)begin
                @(posedge clk);#1;
                if(out_frame!==(cycle==14))fail("latency mismatch");
            end
            if(out_shape!==expected_shape || out_box_area!==width*height)fail("shape/product");
            if(expected_shape!=0 && out_color!==color)fail("color metadata");
            @(posedge clk);#1;if(out_frame)fail("strobe length");
            checked=checked+1;
        end
    endtask
    initial begin
        repeat(3)@(negedge clk);rst_n=1;
        for(color_index=1;color_index<=3;color_index=color_index+1)begin
            sample(40,40,1256,1,400,200,color_index,1);
            sample(40,40,1600,1,400,200,color_index,2);
            sample(40,40,800,1,400,200,color_index,3);
        end
        for(fill_index=0;fill_index<=130;fill_index=fill_index+1)
            sample(128,128,128*fill_index,1,400,200,1,
                fill_index>=116&&fill_index<=128?2:fill_index>=88&&fill_index<=110?1:fill_index>=51&&fill_index<=80?3:0);
        sample(23,23,529,1,400,200,1,0);
        sample(24,24,576,1,400,200,1,2);
        sample(40,40,1600,0,400,200,1,0);
        sample(40,40,1600,1,400,200,0,0);
        sample(40,40,1600,1,320,200,1,0);
        sample(40,40,1600,1,920,200,1,0);
        sample(40,40,1600,1,400,120,1,0);
        sample(40,40,1600,1,400,560,1,0);
        sample(40,80,1600,1,400,200,1,3);
        sample(40,81,1620,1,400,200,1,0);
        sample(70,40,1400,1,400,200,1,3);
        sample(71,40,1420,1,400,200,1,0);
        sample(40,50,1570,1,400,200,1,1);
        sample(40,51,1601,1,400,200,1,0);
        sample(638,478,304964,1,321,121,1,0);
        @(negedge clk);in_frame=1;in_valid=1;
        @(negedge clk);in_frame=0;repeat(4)@(negedge clk);rst_n=0;#1;
        if(out_frame||out_shape||out_color||out_box_area)fail("reset during multiplication");
        @(negedge clk);rst_n=1;sample(40,40,1600,1,400,200,1,2);
        test_done=1;$display("RESULT classifier errors=%0d checked=%0d",errors,checked);$stop;
    end
endmodule
