`timescale 1ns/1ps
module tb_pattern;
    reg [10:0] pixel_x;
    reg [9:0] pixel_y;
    reg [1:0] shape,color;
    reg [15:0] scene_frame;
    wire [23:0] rgb;
    integer errors=0,checks=0,shape_index,color_index,phase,xpos,ypos,local_x,local_y,half_width;
    reg test_done=0,hit;
    reg [23:0] expected;
    demo_pattern dut(.*);
    initial begin
        for(phase=0;phase<2;phase=phase+1)
            for(shape_index=0;shape_index<4;shape_index=shape_index+1)
                for(color_index=0;color_index<4;color_index=color_index+1)
                    for(ypos=278;ypos<410;ypos=ypos+1)
                        for(xpos=558;xpos<707;xpos=xpos+1)begin
                            scene_frame=phase*60;shape=shape_index;color=color_index;pixel_x=xpos;pixel_y=ypos;
                            local_x=xpos-560-phase*15;local_y=ypos-280;
                            hit=local_x>=0&&local_x<128&&local_y>=0&&local_y<128;
                            if(hit)begin
                                if(shape_index==1)begin
                                    half_width=$rtoi($sqrt(256.0-(15.5-local_y/4)*(15.5-local_y/4))+0.5);
                                    hit=local_x/4>=16-half_width&&local_x/4<16+half_width;
                                end else if(shape_index==3)hit=local_x/4>=15-(local_y/8)&&local_x/4<=16+(local_y/8);
                                else if(shape_index!=2)hit=0;
                            end
                            expected=!hit||color_index==0?24'h808080:color_index==1?24'hff0000:color_index==2?24'hffff00:24'h0000ff;
                            #1;checks=checks+1;if(rgb!==expected)begin errors=errors+1;if(errors<8)$display("ERROR pattern xy=%0d,%0d shape=%0d",xpos,ypos,shape_index);end
                        end
        test_done=1;$display("RESULT pattern errors=%0d checks=%0d",errors,checks);$stop;
    end
endmodule
