`timescale 1ns/1ps
module tb_learning_osd;
    reg [10:0] pixel_x=0;
    reg [9:0] pixel_y=0;
    reg [3:0] item_id=0;
    reg det_valid=0,demo_mode=0;
    reg [1:0] audio_status=0;
    wire active;
    wire [23:0] rgb;
    reg [1:0] query_line=0;
    reg [5:0] query_char=0;
    wire [7:0] query_glyph;
    wire query_valid;
    reg test_done=0;
    integer errors=0,pixel_checks=0,content_checks=0;
    integer scenario,xpos,ypos,ident,dv,ln,pos,fd,expected_glyph;
    bit expected_active;
    reg [23:0] expected_rgb,visible_rgb;
    learning_osd dut(.*);
    learning_content content_dut(.item_id(item_id),.det_valid(det_valid),
        .line_index(query_line),.char_index(query_char),.glyph(query_glyph),.valid_item(query_valid));
    `include "learning_osd_reference.svh"

    task automatic check_pixel(input integer x, input integer y);
        begin
            pixel_x=x;pixel_y=y;#1;
            expected_active=(x>=32 && x<=1247 && y>=608 && y<=711);
            expected_rgb=learning_reference_rgb(x,y,item_id,det_valid,demo_mode,audio_status);
            if(active !== expected_active || rgb !== expected_rgb) begin
                if(errors<12)$display("PIXEL_MISMATCH scenario=%0d x=%0d y=%0d active=%b/%b rgb=%h/%h",
                    scenario,x,y,active,expected_active,rgb,expected_rgb);
                errors=errors+1;
            end
            pixel_checks=pixel_checks+1;
        end
    endtask
    initial begin
        // Exhaust every content selector, including line 3, invalid and disabled IDs, and trailing characters.
        for(ident=0;ident<16;ident=ident+1)for(dv=0;dv<2;dv=dv+1)
            for(ln=0;ln<4;ln=ln+1)for(pos=0;pos<64;pos=pos+1)begin
                item_id=ident;det_valid=dv;query_line=ln;query_char=pos;#1;
                expected_glyph=learning_expected_glyph(ident,dv,ln,pos);
                if(query_glyph!==expected_glyph[7:0] || query_valid!==(dv!=0 && ident>=1 && ident<=9)) begin
                    if(errors<12)$display("CONTENT_MISMATCH id=%0d valid=%0d line=%0d char=%0d glyph=%0d/%0d",ident,dv,ln,pos,query_glyph,expected_glyph);
                    errors=errors+1;
                end
                content_checks=content_checks+1;
            end
        // A real output fault must reach both the pixel checker and the process exit code.
        if($test$plusargs("negative_control")) force dut.rgb=24'hffffff;
        for(scenario=0;scenario<33;scenario=scenario+1)begin
            if(scenario<18)begin
                item_id=(scenario%9)+1;det_valid=1;demo_mode=scenario<9;audio_status=scenario%4;
            end else if(scenario<25)begin
                item_id=scenario==18 ? 0 : scenario-9;det_valid=1;demo_mode=scenario%2;audio_status=scenario%4;
            end else if(scenario<29)begin
                item_id=9;det_valid=0;demo_mode=scenario%2;audio_status=scenario-25;
            end else begin
                item_id=5;det_valid=1;demo_mode=0;audio_status=scenario-29;
            end
            fd=0;
            if(!$test$plusargs("negative_control") && (scenario<10 || scenario==25 || scenario==32))begin
                fd=$fopen($sformatf("panel-%0d.ppm",scenario),"w");
                if(!fd)begin $display("PPM_OPEN_FAILED");errors=errors+1;end
                else $fwrite(fd,"P3\n1280 128\n255\n");
            end
            // All panel pixels plus its perimeter and the entire bottom strip.
            for(ypos=592;ypos<720;ypos=ypos+1)begin
                for(xpos=0;xpos<1280;xpos=xpos+1)begin
                    check_pixel(xpos,ypos);
                    if(fd)begin
                        visible_rgb=active ? rgb : 24'h344048;
                        $fwrite(fd,"%0d %0d %0d ",visible_rgb[23:16],visible_rgb[15:8],visible_rgb[7:0]);
                    end
                end
                if(fd)$fwrite(fd,"\n");
            end
            if(fd)$fclose(fd);
            // Disjoint ROI/camera area and representable coordinates outside the 720p viewport.
            check_pixel(32,0);check_pixel(160,599);check_pixel(1247,607);
            check_pixel(1248,608);check_pixel(31,608);check_pixel(32,712);
            check_pixel(2047,1023);check_pixel(1280,608);
            $display("CASE scenario=%0d item=%0d valid=%b demo=%b status=%0d",scenario,item_id,det_valid,demo_mode,audio_status);
        end
        test_done=1;
        $display("RESULT learning_osd errors=%0d content_checks=%0d pixel_checks=%0d cases=33",errors,content_checks,pixel_checks);
    end
endmodule
