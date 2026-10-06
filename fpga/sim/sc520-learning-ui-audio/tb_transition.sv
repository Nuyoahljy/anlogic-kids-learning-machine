`timescale 1ns/1ps
// Real camera pixels drive the full learning wrapper. Coordinates below come
// from the generated square, never from DUT coordinates used as a golden image.
module tb_transition;
    localparam WIDTH=384, HEIGHT=240, BASE_X=100, BASE_Y=160, SIDE=32;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0,in_vsync=0,in_hsync=0,in_de=0;
    reg [23:0] in_rgb=24'h808080;
    wire out_vsync,out_hsync,out_de;
    wire [23:0] out_rgb;
    integer errors=0,checks=0,frames=0,checked_pixels=0,checked_cycles=0;
    integer auto_events=0,cancel_events=0,mapping_checks=0,bbox_checks=0;
    integer frame_index=-1,camera_frame=-10,x,y,j,source_color,source_x;
    integer expected_item,expected_box,expected_left,expected_count,prior_color,prior_x;
    reg [2:0] de_history=0,vs_history=0,hs_history=0;
    reg test_done=0;

    hdmi_learning #(.FRAME_WIDTH(WIDTH),.FRAME_HEIGHT(HEIGHT),
        .X_MIN(16),.X_MAX(367),.Y_MIN(144),.Y_MAX(223),
        .SCENE_FRAMES(1),.DEMO_X(BASE_X),.DEMO_Y(BASE_Y),.DEMO_SCALE_SHIFT(0)) dut(.*);

    function automatic integer color_for_frame(input integer f);
        if(f>=0 && f<5) color_for_frame=1;
        else if(f>=5 && f<15) color_for_frame=2;
        else if(f>=20 && f<25) color_for_frame=3;
        else color_for_frame=0;
    endfunction
    function automatic integer x_for_frame(input integer f);
        x_for_frame=(f>=10 && f<15)?BASE_X+60:BASE_X;
    endfunction
    function automatic [23:0] camera_pixel(input integer px,py,cf);
        integer c,l;
        begin
            c=color_for_frame(cf);l=x_for_frame(cf);
            if(c==0 || px<l || px>=l+SIDE || py<BASE_Y || py>=BASE_Y+SIDE)
                camera_pixel=24'h808080;
            else case(c)
                1:camera_pixel=24'hff0000;
                2:camera_pixel=24'hffff00;
                3:camera_pixel=24'h0000ff;
            endcase
        end
    endfunction
    task check(input reg condition,input string label);
        begin
            checks=checks+1;
            if(condition!==1'b1) begin
                errors=errors+1;
                if(errors<=30)$display("FAIL t=%0t camera_frame=%0d %s",$time,camera_frame,label);
            end
        end
    endtask

    always @(posedge clk) begin
        if(!rst_n) begin de_history=0;vs_history=0;hs_history=0;end
        else begin
            de_history={de_history[1:0],in_de};
            vs_history={vs_history[1:0],in_vsync};
            hs_history={hs_history[1:0],in_hsync};
            #1;
            checked_cycles=checked_cycles+1;
            // The full pixel golden is covered by the separate full regression.
            check({out_de,out_vsync,out_hsync}==={de_history[2],vs_history[2],hs_history[2]},"video latency remains three cycles");
            if(out_de) checked_pixels=checked_pixels+1;
        end
    end
    always @(negedge clk) begin
        // Camera frame zero includes the intentional demo-to-camera flush.
        if(rst_n && camera_frame>=1) begin
            if(dut.audio_event!=0) begin
                auto_events=auto_events+1;
                $display("OBSERVED_AUTO camera_frame=%0d event=%0d item=%0d",camera_frame,dut.audio_event,dut.audio_item);
                check(dut.audio_event==1,"automatic event kind");
                check((camera_frame==3 && dut.audio_item==2) ||
                      (camera_frame==23 && dut.audio_item==8),"only first red and blue after removal may auto-announce");
            end
            if(dut.cancel_audio) begin
                cancel_events=cancel_events+1;
                $display("OBSERVED_CANCEL camera_frame=%0d candidate_valid=%0d",camera_frame,dut.candidate_valid);
                check(!dut.candidate_valid,"continuous valid candidate must not cancel");
                check(camera_frame==18,"real blank cancels after the expected absence qualification");
            end
        end
    end

    initial begin
        repeat(4)@(negedge clk);rst_n=1;
        for(frame_index=0;frame_index<35;frame_index=frame_index+1) begin
            camera_frame=frame_index-10;
            @(negedge clk);in_vsync=1;
            repeat(64)@(negedge clk);
            check(dut.demo_mode===(frame_index<10),"one-frame startup scenes exit at frame ten");
            if(camera_frame>=0) begin
                prior_color=color_for_frame(camera_frame-1);
                prior_x=x_for_frame(camera_frame-1);
                if(camera_frame>=1) begin
                    check(dut.candidate_valid===(prior_color!=0),"candidate presence matches previous real camera image");
                    if(prior_color!=0) begin
                        check(dut.candidate_color===prior_color[1:0],"raw candidate color");
                        check(dut.candidate_left==prior_x && dut.candidate_right==prior_x+SIDE-1 &&
                            dut.candidate_top==BASE_Y && dut.candidate_bottom==BASE_Y+SIDE-1,"independent raw bbox x/y/w/h");
                        bbox_checks=bbox_checks+1;
                    end
                end
                expected_item=0;expected_box=0;expected_left=BASE_X;expected_count=0;
                if(camera_frame>=3 && camera_frame<=5) begin
                    expected_item=2;expected_box=1;expected_count=camera_frame;
                end else if(camera_frame>=8 && camera_frame<=10) begin
                    expected_item=5;expected_box=1;expected_count=camera_frame-5;
                end else if(camera_frame>=13 && camera_frame<=16) begin
                    expected_box=1;expected_left=BASE_X+60;
                    if(camera_frame<=15) begin expected_item=5;expected_count=camera_frame-10;end
                end else if(camera_frame>=23) begin
                    expected_item=8;expected_box=1;expected_count=camera_frame-20;
                end
                check(dut.display_valid===(expected_item!=0) && dut.display_item==expected_item,
                    $sformatf("display follows stable new ID: expected%0d got%0d valid%0d",expected_item,dut.display_item,dut.display_valid));
                mapping_checks=mapping_checks+1;
                check(dut.box_valid===expected_box[0],"stable bbox valid qualification");
                if(expected_box!=0) begin
                    check(dut.box_left==expected_left && dut.box_right==expected_left+SIDE-1 &&
                        dut.box_top==BASE_Y && dut.box_bottom==BASE_Y+SIDE-1,"independent stable bbox x/y/w/h");
                    bbox_checks=bbox_checks+1;
                end
                if(expected_item!=0) begin
                    check(dut.det_bbox_x==expected_left/4 && dut.det_bbox_y==BASE_Y/4 &&
                        dut.det_bbox_w==SIDE/4 && dut.det_bbox_h==SIDE/4,"independent adapted bbox 320x180 cells");
                    check(dut.det_stable_count==expected_count,"stable count matches qualified input history");
                end
                if(camera_frame==14) begin
                    check(auto_events==1,"three continuous target segments total one automatic event");
                    check(cancel_events==0,"three continuous target segments have no cancellation");
                end
                if(camera_frame==19) begin
                    check(cancel_events==1,"true blank interval cancels exactly once");
                    check(dut.audio_status==0,"true blank flush returns simulated audio to idle");
                end
            end
            in_vsync=0;repeat(16)@(negedge clk);
            for(y=0;y<HEIGHT;y=y+1) begin
                for(x=0;x<WIDTH;x=x+1) begin
                    in_de=1;in_hsync=0;
                    in_rgb=frame_index<10?24'h214365:camera_pixel(x,y,camera_frame);
                    @(negedge clk);
                end
                in_de=0;in_hsync=1;repeat(8)@(negedge clk);in_hsync=0;
            end
            frames=frames+1;
        end
        repeat(8)@(negedge clk);
        check(auto_events==2,"total automatic events exactly two");
        check(cancel_events==1,"total real-removal cancellations exactly one");
        check(dut.display_valid && dut.display_item==8,"final blue square UI");
        check(dut.audio_status==2,"final blue square mock playback active");
        rst_n=0;repeat(4)@(negedge clk);
        check(dut.display_valid==0 && dut.display_item==0 && dut.audio_status==0,"reset clears UI and audio");
        test_done=1;
        $display("TRANSITION_RESULT done=%0d errors=%0d checks=%0d frames=%0d pixels=%0d cycles=%0d auto_events=%0d cancel_events=%0d mapping_checks=%0d bbox_checks=%0d",test_done,errors,checks,frames,checked_pixels,checked_cycles,auto_events,cancel_events,mapping_checks,bbox_checks);
        $stop;
    end
endmodule
