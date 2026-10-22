`timescale 1ns/1ps
module tb_shape_card30_scores;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,flush=0,full_start=0,full_valid=0,full_end=0,axis_start=0,axis_valid=0,axis_end=0;
    reg [9:0] sample_index=0;reg sample_fg=0,frame_good=1,frame_present=1;
    reg [31:0] frame_id=0;reg frame_source=0;
    wire out_frame,out_healthy,out_present,out_source;wire [31:0] out_id;
    wire [10:0] circle_distance,square_distance,triangle_distance,ellipse_distance,axis_circle_distance;
    pixel30_shape_scores dut(.*);
    integer errors=0,checks=0,scenarios=0;reg test_done=0;
    reg full_mask[0:1023],axis_mask[0:1023];
    reg [10:0] expected_distances[0:16];
    string assets,prefix;integer fd,n,circle,square,triangle,ellipse,axis_d,present,clip,ymin,ymax,w,h,available,item,cycles,inject=0;
    task ck(input bit ok,input string message);
        begin checks++;if(!ok)begin errors++;$display("FAIL case=%0d %s",scenarios,message);end end
    endtask
    initial begin
        if(!$value$plusargs("ASSET_ROOT=%s",assets))$fatal(1,"assets required");
        n=$value$plusargs("INJECT_FAULT=%d",inject);
        repeat(4)@(negedge clk);rst_n=1;
        fd=$fopen({assets,"/cases.txt"},"r");if(!fd)$fatal(1,"cases missing");
        while(!$feof(fd))begin
            n=$fscanf(fd,"%s %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
                prefix,circle,square,triangle,ellipse,axis_d,present,clip,ymin,ymax,w,h,available,item);
            if(n==14)begin
                scenarios++;frame_id++;frame_present=present;
                $readmemh({assets,"/",prefix,".full.mem"},full_mask);
                $readmemh({assets,"/",prefix,".axis.mem"},axis_mask);
                $readmemh({assets,"/",prefix,".distances.mem"},expected_distances);
                full_start=1;@(negedge clk);full_start=0;
                for(integer i=0;i<1024;i++)begin
                    full_valid=1;sample_index=i;sample_fg=full_mask[i];@(negedge clk);
                end
                full_valid=0;full_end=1;@(negedge clk);full_end=0;
                axis_start=1;@(negedge clk);axis_start=0;
                for(integer i=0;i<1024;i++)begin
                    axis_valid=1;sample_index=i;sample_fg=axis_mask[i];@(negedge clk);
                end
                axis_valid=0;axis_end=1;@(negedge clk);axis_end=0;
                cycles=0;while(!out_frame && cycles<8)begin @(negedge clk);cycles++;end
                ck(out_frame && out_healthy && out_id==frame_id && out_present==present,"complete identity/health");
                if(inject && scenarios==1)begin force dut.circle_distance=2047;#1;end
                ck(circle_distance==circle && square_distance==square && triangle_distance==triangle,"three original full distances");
                ck(ellipse_distance==ellipse && axis_circle_distance==axis_d,"12 negative/2 axis distance minima");
                for(integer d=0;d<15;d++)ck(dut.distances[d]==expected_distances[d],"every full counter from actual mask/ROM");
                ck(dut.axis0==expected_distances[15] && dut.axis1==expected_distances[16],"both axis counters individually");
                if(inject && scenarios==1)release dut.circle_distance;
                repeat(3)@(negedge clk);
            end
        end
        $fclose(fd);test_done=1;
        $display("RESULT scores errors=%0d checks=%0d scenarios=%0d",errors,checks,scenarios);$finish;
    end
endmodule
