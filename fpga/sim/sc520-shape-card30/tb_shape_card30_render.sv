`timescale 1ns/1ps
module tb_shape_card30_render;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,in_frame_start=0,in_de=0,in_hsync=0,in_vsync=0,mode_request=0;
    reg [10:0] in_x=0;reg [9:0] in_y=0;reg [23:0] in_rgb=0;
    reg [27:0] business_state=0;reg [191:0] recognition_packet=0;
    reg recognition_fresh=1,recognition_fault=0;reg [7:0] recognition_age=0;
    wire out_frame_start,out_de,out_hsync,out_vsync,out_mode,out_panel_active,out_diag_active,out_logo_active;
    wire [10:0] out_x;wire [9:0] out_y;wire [23:0] out_rgb;
    pixel30_compositor dut(.*);
    integer errors=0,checks=0,scenarios=0,pixels=0,inject=0,n,fd,actual_fd,case_index=0;
    reg test_done=0;string assets;
    reg [23:0] golden[0:921599],missing_diagnostic[0:55295];
    reg diag_probe=0;integer missing_pixels=0;
    reg [25:0] timing[0:5];reg [25:0] expected_timing;
    integer valid_count=0;reg latched_mode=0;
    task ck(input bit ok,input string message);
        begin checks++;if(!ok)begin errors++;if(errors<20)$display("FAIL render case%0d xy%0d,%0d %s",scenarios,out_x,out_y,message);end end
    endtask
    function [23:0] stripe(input integer x);
        case(x/320)0:stripe=24'hc04020;1:stripe=24'hc0b030;2:stripe=24'h3050c0;default:stripe=24'h607080;endcase
    endfunction
    always @(posedge clk)begin
        if(in_frame_start)latched_mode=mode_request;
        expected_timing={in_frame_start,in_de,in_hsync,in_vsync,latched_mode,in_x,in_y};
        for(integer i=5;i>0;i--)timing[i]=timing[i-1];
        timing[0]=expected_timing;
        #1;
        if(rst_n)begin
            valid_count++;
            if(valid_count>=6)begin
                ck({out_frame_start,out_de,out_hsync,out_vsync,out_mode,out_x,out_y}===timing[5],"all timing and coordinate sidebands N+5");
                if(!out_de)ck(out_rgb==0&&!out_panel_active&&!out_diag_active&&!out_logo_active,"blanking suppresses pixels and overlays");
                if(out_de && actual_fd)begin
                    pixels++;
                    ck(out_rgb===golden[out_y*1280+out_x],"literal independent expected pixel");
                    ck(out_panel_active==(out_x>=32&&out_x<1248&&((out_y>=8&&out_y<112)||(out_y>=608&&out_y<712))),
                        "panel extent and sideband");
                    ck(out_diag_active==(out_x>=32&&out_x<800&&out_y>=520&&out_y<592),"diagnostic extent and sideband");
                    ck(!out_logo_active || (out_x>=1008&&out_x<1154&&out_y>=24&&out_y<118),"Logo only actual region");
                    $fdisplay(actual_fd,"%06X",out_rgb);
                    if(inject && pixels==1)ck(out_rgb==24'habcdef,"negative pixel oracle");
                end
                if(out_de && diag_probe)begin
                    missing_pixels++;
                    ck(out_rgb===missing_diagnostic[(out_y-520)*768+out_x-32],"every unavailable diagnostic pixel literal NA/safety");
                end
            end
        end else valid_count=0;
    end
    task idle;
        begin in_de=0;in_frame_start=0;in_hsync=0;in_vsync=0;repeat(8)@(negedge clk);end
    endtask
    task fs;
        begin in_frame_start=1;@(negedge clk);in_frame_start=0;repeat(2)@(negedge clk);end
    endtask
    task unavailable_char(input integer row,col,input [7:0] expected);
        begin
            in_x=32+col*8;in_y=520+row*12;repeat(3)@(negedge clk);
            ck(dut.diagnostic_panel.character==expected,"literal unavailable diagnostic character");
        end
    endtask
    initial begin
        n=$value$plusargs("INJECT_FAULT=%d",inject);
        if(!$value$plusargs("ASSET_ROOT=%s",assets))$fatal(1,"asset root");
        repeat(4)@(negedge clk);rst_n=1;
        fd=$fopen({assets,"/render-cases.txt"},"r");if(!fd)$fatal(1,"render cases");
        for(case_index=0;case_index<4;case_index++)begin
            idle();
            n=$fscanf(fd,"%h %h %h %d %d %d\n",business_state,recognition_packet,recognition_age,
                mode_request,recognition_fresh,recognition_fault);
            ck(n==6,"four fixed fixture cases");
            $readmemh($sformatf("%s/golden-%0d.mem",assets,case_index),golden);
            actual_fd=$fopen($sformatf("actual-%0d.mem",case_index),"w");if(!actual_fd)$fatal(1,"actual image");
            scenarios++;fs();
            for(integer y=0;y<720;y++)begin
                for(integer x=0;x<1280;x++)begin
                    in_x=x;in_y=y;in_rgb=stripe(x);in_de=1;in_hsync=0;in_vsync=0;@(negedge clk);
                end
                in_de=0;in_hsync=1;repeat(3)@(negedge clk);
            end
            idle();$fclose(actual_fd);actual_fd=0;
        end
        $fclose(fd);ck(pixels==3686400,"four complete 720p images");
        scenarios++;
        recognition_packet[186]=1;recognition_packet[33]=1;recognition_packet[36]=0;
        recognition_fresh=1;recognition_fault=0;business_state[11:8]=1;business_state[0]=1;fs();
        ck(dut.trusted&&dut.status[11:8]==1,"healthy frame snapshot trusted");
        recognition_packet[43:40]=2;business_state[11:8]=2;recognition_age=99;mode_request=~mode_request;
        @(negedge clk);ck(dut.status[11:8]==1&&dut.age==18,"new healthy class and age await FS");
        recognition_packet[33]=0;@(negedge clk);ck(!dut.trusted&&dut.status[11:8]==0&&dut.usable,"unhealthy fresh packet immediately drops business only");
        recognition_packet[33]=1;@(negedge clk);ck(!dut.trusted&&dut.status[11:8]==0,"midframe trust cannot revive");
        fs();ck(dut.trusted&&dut.status[11:8]==2&&dut.age==99,"next FS adopts recovered class and age");
        recognition_packet[36]=1;@(negedge clk);ck(!dut.trusted&&dut.usable,"revoke1 fresh preserves raw diagnostic");
        fs();ck(dut.snapshot[36]&&!dut.trusted&&dut.usable,"invalid fresh snapshot retains real raw fields");
        recognition_packet[36]=0;recognition_packet[186]=0;@(negedge clk);ck(!dut.trusted,"identity unknown immediate business revoke");
        recognition_packet[186]=1;recognition_fault=1;@(negedge clk);ck(!dut.usable,"transport fault invalidates diagnostic");
        recognition_fault=0;@(negedge clk);ck(!dut.usable,"transport recovery cannot revive until FS");
        fs();ck(dut.usable&&dut.trusted,"next FS recovers available transport");
        recognition_fresh=0;@(negedge clk);ck(!dut.usable&&!dut.trusted,"stale packet drops all availability");
        unavailable_char(0,7,"N");unavailable_char(0,8,"A");
        unavailable_char(0,17,"N");unavailable_char(0,18,"A");
        unavailable_char(0,21,"N");unavailable_char(0,22,"A");
        unavailable_char(0,25,"0");unavailable_char(0,28,"1");
        unavailable_char(0,31,"N");unavailable_char(0,32,"A");
        unavailable_char(0,39,"N");unavailable_char(0,40,"A");
        unavailable_char(1,2,"N");unavailable_char(1,3,"A");
        unavailable_char(2,2,"N");unavailable_char(2,3,"A");
        unavailable_char(3,2,"N");unavailable_char(3,3,"A");
        unavailable_char(4,2,"N");unavailable_char(4,3,"A");
        unavailable_char(5,3,"N");unavailable_char(5,4,"A");
        unavailable_char(5,9,"N");unavailable_char(5,10,"A");unavailable_char(5,14,"0");
        $readmemh({assets,"/missing-diagnostic.mem"},missing_diagnostic);
        diag_probe=1;
        for(integer y=520;y<592;y++)for(integer x=32;x<800;x++)begin
            in_x=x;in_y=y;in_rgb=stripe(x);in_de=1;@(negedge clk);
        end
        idle();diag_probe=0;ck(missing_pixels==55296,"complete unavailable diagnostic patch");
        recognition_fresh=1;@(negedge clk);ck(!dut.usable,"fresh recovery remains sticky to FS");
        fs();ck(dut.usable,"fresh packet after FS restored");
        idle();rst_n=0;@(negedge clk);ck(!out_de&&out_rgb==0&&!dut.snapshot_fresh,"reset clears pipeline and snapshot");
        test_done=1;$display("RESULT render errors=%0d checks=%0d scenarios=%0d pixels=%0d",errors,checks,scenarios,pixels);$finish;
    end
endmodule
