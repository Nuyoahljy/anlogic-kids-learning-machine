reg clk=0; always #5 clk=~clk;
reg rst_n=0,in_vsync=0,in_hsync=0,in_de=0;
reg [23:0] in_rgb=24'h808080;
wire out_vsync,out_hsync,out_de;
wire [23:0] out_rgb;
reg test_done=0;
integer errors=0,frames=0,checked_pixels=0,checked_cycles=0,class_checks=0;
integer frame_index=-1,xpos,ypos,blank_index,local_frame,expected_scene,camera_frame;
integer drive_x=0,drive_y=0,delayed_x[0:2],delayed_y[0:2];
integer saved_frame=-1,snapshot=0;
reg expected_demo;
reg [1:0] generated_shape,generated_color,known_shape,known_color;
reg wanted_box;
reg [2:0] de_history=0,vs_history=0,hs_history=0;
reg negative;
hdmi_osd_demo #(.FRAME_WIDTH(WIDTH),.FRAME_HEIGHT(HEIGHT),.X_MIN(ROI_LEFT),.X_MAX(ROI_RIGHT),.Y_MIN(ROI_TOP),.Y_MAX(ROI_BOTTOM),.SCENE_FRAMES(8),.DEMO_X(TARGET_X),.DEMO_Y(TARGET_Y),.DEMO_SCALE_SHIFT(SCALE)) dut(.*);
`include "font_reference.svh"
function automatic [23:0] source_pixel(input integer horizontal,vertical,input bit demo,input integer shape_code,color_code,age);
    integer local_horizontal,local_vertical,half_width,column,row;
    reg hit;
    begin
        local_horizontal=horizontal-TARGET_X-(demo?((age/4)%16):0);
        local_vertical=vertical-TARGET_Y;
        column=local_horizontal/(1<<SCALE);row=local_vertical/(1<<SCALE);
        hit=local_horizontal>=0&&local_horizontal<(32<<SCALE)&&local_vertical>=0&&local_vertical<(32<<SCALE);
        if(hit)begin
            if(shape_code==1)begin
                half_width=$rtoi($sqrt(256.0-(15.5-row)*(15.5-row))+0.5);
                hit=column>=16-half_width&&column<16+half_width;
            end else if(shape_code==3)hit=column>=15-row/2&&column<=16+row/2;
            else if(shape_code!=2)hit=0;
        end
        source_pixel=!hit?24'h808080:color_code==1?24'hff0000:color_code==2?24'hffff00:24'h0000ff;
    end
endfunction
function automatic integer expected_glyph(input integer text_line,text_column);
    integer name_shape,name_color;
    begin
        expected_glyph=0;
        name_shape=text_line==1?generated_shape:known_shape;
        name_color=text_line==1?generated_color:known_color;
        if(text_line==0)begin
            case(text_column)
                0:expected_glyph=expected_demo?1:5;
                1:expected_glyph=expected_demo?2:6;
                2:expected_glyph=3;
                3:expected_glyph=4;
            endcase
        end else begin
            if(text_column==0)expected_glyph=text_line==1?8:10;
            else if(text_column==1)expected_glyph=text_line==1?9:11;
            else if(text_line==1&&!expected_demo)begin
                case(text_column)2:expected_glyph=5;3:expected_glyph=6;4:expected_glyph=7;endcase
            end else if(text_line==1&&generated_shape==0)begin
                case(text_column)2:expected_glyph=28;3:expected_glyph=29;endcase
            end else if(text_line==2&&!wanted_box)begin
                case(text_column)2:expected_glyph=25;3:expected_glyph=26;4:expected_glyph=27;endcase
            end else if(name_shape==0)begin
                case(text_column)2:expected_glyph=22;3:expected_glyph=23;4:expected_glyph=24;endcase
            end else begin
                if(text_column==2)expected_glyph=11+name_color;
                else if(text_column==3)expected_glyph=15;
                else if(name_shape==1)begin
                    case(text_column)4:expected_glyph=16;5:expected_glyph=17;endcase
                end else if(name_shape==2)begin
                    case(text_column)4:expected_glyph=18;5:expected_glyph=19;6:expected_glyph=17;endcase
                end else begin
                    case(text_column)4:expected_glyph=20;5:expected_glyph=21;6:expected_glyph=17;endcase
                end
            end
        end
    end
endfunction
function automatic [23:0] rendered_pixel(input integer horizontal,vertical);
    integer text_line,text_column,name_color,name_shape;
    reg [15:0] glyph_row;
    reg [23:0] ink,source_rgb;
    reg in_roi,on_box;
    begin
        source_rgb=source_pixel(horizontal,vertical,expected_demo,generated_shape,generated_color,local_frame);
        in_roi=horizontal>=ROI_LEFT&&horizontal<=ROI_RIGHT&&vertical>=ROI_TOP&&vertical<=ROI_BOTTOM;
        on_box=dut.box_valid&&horizontal>=dut.box_left&&horizontal<=dut.box_right&&vertical>=dut.box_top&&vertical<=dut.box_bottom&&
            (horizontal-dut.box_left<2||dut.box_right-horizontal<2||vertical-dut.box_top<2||dut.box_bottom-vertical<2);
        rendered_pixel=source_rgb;
        if(on_box)rendered_pixel=24'h00ffff;
        if(in_roi&&(horizontal==ROI_LEFT||horizontal==ROI_RIGHT||vertical==ROI_TOP||vertical==ROI_BOTTOM))rendered_pixel=24'hff0000;
        if(horizontal>=32&&horizontal<320&&vertical>=16&&vertical<112)begin
            text_line=(vertical-16)/32;text_column=(horizontal-32)/32;
            glyph_row=reference_font(expected_glyph(text_line,text_column),((vertical-16)%32)/2);
            ink=24'hffffff;
            name_color=text_line==1?generated_color:known_color;
            name_shape=text_line==1?generated_shape:known_shape;
            if(text_line==0)ink=expected_demo?24'hffff00:24'h00ffff;
            else if((text_line==1&&expected_demo&&name_shape!=0)||(text_line==2&&wanted_box&&name_shape!=0))
                ink=name_color==1?24'hff0000:name_color==2?24'hffff00:24'h0000ff;
            if(text_line>0&&text_column<2)ink=24'hffffff;
            rendered_pixel=glyph_row[15-((horizontal-32)%32)/2]?ink:24'h202020;
        end
    end
endfunction
task automatic fail(input string message);
    begin errors=errors+1;if(errors<=12)$display("ERROR demo frame=%0d xy=%0d,%0d %s",frame_index,delayed_x[2],delayed_y[2],message);end
endtask
always @(posedge clk)begin
    if(!rst_n)begin
        de_history=0;vs_history=0;hs_history=0;
    end else begin
        de_history={de_history[1:0],in_de};vs_history={vs_history[1:0],in_vsync};hs_history={hs_history[1:0],in_hsync};
        delayed_x[2]=delayed_x[1];delayed_x[1]=delayed_x[0];delayed_x[0]=drive_x;
        delayed_y[2]=delayed_y[1];delayed_y[1]=delayed_y[0];delayed_y[0]=drive_y;
        #1;checked_cycles=checked_cycles+1;
        if({out_de,out_vsync,out_hsync}!=={de_history[2],vs_history[2],hs_history[2]})fail("sync latency");
        if(out_de)begin
            checked_pixels=checked_pixels+1;
            if(out_rgb!==rendered_pixel(delayed_x[2],delayed_y[2]))fail("output RGB / OSD / source mux");
            if(SNAPSHOTS&&(frame_index==4||frame_index==36||frame_index==68||frame_index==83||frame_index==86))begin
                if(saved_frame!=frame_index)begin
                    if(snapshot!=0)$fclose(snapshot);
                    snapshot=$fopen($sformatf("frame-%0d.ppm",frame_index),"wb");
                    $fwrite(snapshot,"P6\n%0d %0d\n255\n",WIDTH,HEIGHT);saved_frame=frame_index;
                end
                $fwrite(snapshot,"%c%c%c",out_rgb[23:16],out_rgb[15:8],out_rgb[7:0]);
            end
        end else if(out_rgb!==0)fail("blanking RGB");
    end
end
initial begin
    negative=$test$plusargs("negative_control");
    repeat(4)@(negedge clk);rst_n=1;
    for(frame_index=0;frame_index<88;frame_index=frame_index+1)begin
        expected_demo=frame_index<80;expected_scene=expected_demo?frame_index/8:9;
        local_frame=expected_demo?frame_index%8:0;camera_frame=frame_index-80;
        generated_shape=expected_demo?(expected_scene<9?expected_scene%3+1:0):(camera_frame<4?2:0);
        generated_color=expected_demo?(expected_scene<9?expected_scene/3+1:0):1;
        known_shape=expected_demo?(local_frame>=3?generated_shape:0):(camera_frame==3||camera_frame==4?2:0);
        known_color=known_shape!=0?(expected_demo?generated_color:1):0;
        wanted_box=expected_demo?(local_frame>=3&&expected_scene<9):(camera_frame>=3&&camera_frame<=5);
        @(negedge clk);in_vsync=1;repeat(64)@(negedge clk);
        class_checks=class_checks+1;
        if(dut.demo_mode!==expected_demo||dut.scene!==expected_scene)fail("mode / scene");
        if(dut.stable_shape!==known_shape||dut.box_valid!==wanted_box)fail($sformatf("classification got shape%0d box%0d expected shape%0d box%0d",dut.stable_shape,dut.box_valid,known_shape,wanted_box));
        if(known_shape!=0&&dut.stable_shape_color!==known_color)fail("detected color");
        if(wanted_box&&(dut.box_left<TARGET_X-3||dut.box_left>TARGET_X+4||dut.box_right-dut.box_left+1!=(32<<SCALE)))fail("box location / width");
        repeat(VSYNC_CYCLES-64)@(negedge clk);in_vsync=0;repeat(VBLANK_CYCLES-VSYNC_CYCLES)@(negedge clk);
        for(ypos=0;ypos<HEIGHT;ypos=ypos+1)begin
            for(xpos=0;xpos<WIDTH;xpos=xpos+1)begin
                in_de=1;in_hsync=0;drive_x=xpos;drive_y=ypos;
                in_rgb=expected_demo?24'h214365:source_pixel(xpos,ypos,0,generated_shape,1,0);
                if(negative&&frame_index==0&&ypos==HEIGHT-1&&xpos>=8&&xpos<12)force dut.out_rgb=24'h123456;
                else release dut.out_rgb;
                @(negedge clk);
            end
            in_de=0;in_hsync=1;repeat(HBLANK)@(negedge clk);in_hsync=0;
        end
        frames=frames+1;
    end
    repeat(8)@(negedge clk);
    if(snapshot!=0)$fclose(snapshot);
    rst_n=0;repeat(4)@(negedge clk);
    if(dut.demo_mode!==1||dut.scene!==0||dut.box_valid!==0||dut.stable_shape!==0)fail("reset restarts demo and clears detection");
    test_done=1;$display("RESULT %s errors=%0d frames=%0d pixels=%0d cycles=%0d classes=%0d",TEST_NAME,errors,frames,checked_pixels,checked_cycles,class_checks);$stop;
end
