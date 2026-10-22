`timescale 1ns/1ps
module tb_shape_card30_filter;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,flush=0,in_frame=0,in_healthy=1,in_present=1,in_valid=1,in_source_test=0;
    reg [3:0] in_item=0;reg [31:0] in_frame_id=0;
    wire out_frame,out_healthy,out_present,out_valid,out_source_test;
    wire [3:0] out_item;wire [31:0] out_frame_id;wire [7:0] stable_count;
    items30_result_filter dut(.*);
    integer errors=0,checks=0,scenarios=0,inject=0,n;reg test_done=0;
    task ck(input bit ok,input string message);
        begin checks++;if(!ok)begin errors++;$display("FAIL filter %s",message);end end
    endtask
    task observe(input integer item,count,input bit source,healthy,present,valid);
        begin
            scenarios++;in_item=item;in_healthy=healthy;in_present=present;in_valid=valid;
            in_source_test=source;in_frame_id++;in_frame=1;@(negedge clk);
            ck(out_frame && out_frame_id==in_frame_id && out_source_test==source,"identity");
            ck(stable_count==count,"updated same-transaction count");
            ck(out_valid==(count>=3) && out_item==(count>=3?item:0),"third-frame confirmation");
            ck(out_healthy==healthy && out_present==(healthy?present:1),"empty/unknown/bad distinct");
            in_frame=0;@(negedge clk);ck(!out_frame,"no held event");
        end
    endtask
    initial begin
        n=$value$plusargs("INJECT_FAULT=%d",inject);
        repeat(4)@(negedge clk);rst_n=1;
        for(integer item=1;item<=14;item++)begin
            if(item<=3||item>=10)begin observe(item,1,0,1,1,1);observe(item,2,0,1,1,1);observe(item,3,0,1,1,1);end
            else observe(item,0,0,1,1,1);
        end
        observe(14,1,1,1,1,1);observe(14,2,1,1,1,1);observe(14,3,1,1,1,1);
        observe(14,1,0,1,1,1);observe(0,0,0,1,1,0);
        observe(1,1,0,1,1,1);observe(0,0,0,1,0,0);
        observe(1,1,0,1,1,1);observe(1,0,0,0,1,1);
        observe(1,1,0,1,1,1);observe(1,0,0,1,1,0);
        observe(2,1,0,1,1,1);
        for(integer count=2;count<=258;count++)observe(2,count>255?255:count,0,1,1,1);
        flush=1;@(negedge clk);ck(!out_frame&&!out_valid&&out_item==0&&stable_count==0,"flush clears immediately");
        flush=0;observe(2,1,0,1,1,1);
        if(inject)ck(stable_count==2,"negative oracle must reject actual first-frame count");
        test_done=1;$display("RESULT filter errors=%0d checks=%0d scenarios=%0d",errors,checks,scenarios);$finish;
    end
endmodule
