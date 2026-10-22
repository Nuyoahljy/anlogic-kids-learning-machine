`timescale 1ns/1ps
module tb_shape_card30_matcher;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,flush=0,frame_start=0,sample_valid=0,sample_foreground=0,frame_end=0,frame_good=1,frame_present=1;
    reg [9:0] sample_index=0;reg [31:0] frame_id=0;reg frame_source_test=0;
    wire out_frame,out_healthy,out_present,out_valid,out_source_test;
    wire [3:0] out_item,out_raw_winner;wire [10:0] out_best,out_second,out_fg_count;wire [31:0] out_frame_id;
    wire old_frame,old_healthy,old_present,old_valid,old_source;
    wire [3:0] old_item;wire [10:0] old_best,old_second,old_fg;wire [31:0] old_id;
    string assets;reg [4:0] bank[0:102399];reg mask[0:1023];
    pixel30_rotation_matcher #(.VARIANTS(256),.ENABLE_OUTPUT(1)) dut(.*);
    pixel14_rotation_matcher #(.VARIANTS(256),.ENABLE_OUTPUT(1)) original(
        .clk(clk),.rst_n(rst_n),.flush(flush),.frame_start(frame_start),.sample_valid(sample_valid),
        .sample_index(sample_index),.sample_foreground(sample_foreground),.frame_end(frame_end),.frame_good(frame_good),
        .frame_present(frame_present),.frame_id(frame_id),.frame_source_test(frame_source_test),
        .out_frame(old_frame),.out_healthy(old_healthy),.out_present(old_present),.out_valid(old_valid),
        .out_item(old_item),.out_best(old_best),.out_second(old_second),.out_fg_count(old_fg),
        .out_frame_id(old_id),.out_source_test(old_source));
    integer errors=0,checks=0,scenarios=0,cycles=0,inject=0,n;reg test_done=0;
    integer class_distance[0:4],ranking_best,ranking_second,winner,fg,variant_distance,expected_fg;
    reg write_event;reg [8:0] write_address_seen;reg write_bit;
    reg emit_event;reg [3:0] raw_seen;
    reg [399:0] tie_mask=400'b1011001001110001001011000101101000111111010010101000011100100000001101101110011010111111100011000110111100010011110010100011000101001111100011001011011011001000111100111111011001001001010111001011000110101101001100101010011101101001000110010111001000011100011101010110111110111000100110000011001001100100110101111111010111010111101001101101111010010100001010111000111001010000001101110110110010111011;
    task ck(input bit ok,input string message);
        begin checks++;if(!ok)begin errors++;if(errors<20)$display("FAIL matcher case%0d %s",scenarios,message);end end
    endtask
    always @(posedge clk)begin
        write_event=rst_n && !flush && dut.state==1 && sample_valid && !frame_start &&
            dut.sample_count<1024 && dut.active_cell;
        write_address_seen=dut.write_address;write_bit=sample_foreground;
        emit_event=rst_n && !flush && !frame_start && !frame_end && dut.state==7;
        raw_seen=dut.best_item;
        #1;
        if(rst_n)begin
            ck({out_frame,out_healthy,out_present,out_valid,out_item,out_best,out_second,out_fg_count,out_frame_id,out_source_test}===
               {old_frame,old_healthy,old_present,old_valid,old_item,old_best,old_second,old_fg,old_id,old_source},"all original outputs every clock");
            ck({dut.state,dut.rom_address,dut.mask_address,dut.read_valid,dut.read_last,dut.read_final,dut.sample_count,
                dut.foreground_count,dut.frame_bad,dut.saved_good,dut.saved_present,dut.saved_source,dut.saved_id,
                dut.rank_index,dut.best,dut.second,dut.margin,dut.best_item,dut.accepted}===
               {original.state,original.rom_address,original.mask_address,original.read_valid,original.read_last,original.read_final,
                original.sample_count,original.foreground_count,original.frame_bad,original.saved_good,original.saved_present,
                original.saved_source,original.saved_id,original.rank_index,original.best,original.second,original.margin,
                original.best_item,original.accepted},"original control and rank every clock");
            for(integer c=0;c<5;c++)ck(dut.distance[c]===original.distance[c] && dut.class_best[c]===original.class_best[c],"every parallel score");
            if(dut.state==2)ck({dut.template_q,dut.mask_q}==={original.template_q,original.mask_q},"identical memory read data");
            if(write_event)ck(dut.captured_mask[write_address_seen]===write_bit &&
                original.captured_mask[write_address_seen]===write_bit,"capture memory write event and bit");
            if(emit_event)ck(out_frame && out_raw_winner===raw_seen,"raw winner is original EMIT rank");
            if(flush)ck(!out_frame && out_raw_winner==0,"flush immediately clears raw output");
        end
    end
    task make_mask(input integer kind,cls,variant);
        begin
            for(integer i=0;i<1024;i++)begin
                if(i%32>=6 && i%32<26 && i/32>=6 && i/32<26)
                    mask[i]=kind==0 ? bank[variant*400+(i/32-6)*20+i%32-6][cls] :
                        kind==1 ? 0 : kind==2 ? ((i%32+i/32)%2==0) :
                        tie_mask[399-(i/32-6)*20-(i%32-6)];
                else mask[i]=0;
            end
            fg=0;for(integer i=0;i<1024;i++)fg+=mask[i];
            for(integer c=0;c<5;c++)begin
                class_distance[c]=1025;
                for(integer v=0;v<256;v++)begin
                    variant_distance=0;
                    for(integer i=0;i<400;i++)variant_distance+=mask[(i/20+6)*32+i%20+6]^bank[v*400+i][c];
                    if(variant_distance<class_distance[c])class_distance[c]=variant_distance;
                end
            end
            ranking_best=1025;ranking_second=1025;winner=0;
            for(integer c=0;c<5;c++)begin
                if(class_distance[c]<ranking_best)begin ranking_second=ranking_best;ranking_best=class_distance[c];winner=10+c;end
                else if(class_distance[c]<ranking_second)ranking_second=class_distance[c];
            end
        end
    endtask
    task capture(input integer protocol);
        integer length;
        begin
            frame_id++;frame_source_test=scenarios[0];
            frame_start=1;sample_valid=protocol==5;@(negedge clk);frame_start=0;sample_valid=0;
            length=protocol==1 ? 1023:protocol==2 ? 1025:1024;
            for(integer i=0;i<length;i++)begin
                sample_valid=1;sample_index=protocol==3 && i==213 ? 212:i%1024;
                sample_foreground=protocol==4 && i==0 ? 1:mask[i%1024];@(negedge clk);
            end
            expected_fg=fg+(protocol==4 ? 1:0);
            if(protocol==1)expected_fg-=mask[1023];
            if(protocol==0 || protocol==7)
                for(integer i=0;i<400;i++)ck(dut.captured_mask[i]===mask[(i/20+6)*32+i%20+6] &&
                    original.captured_mask[i]===mask[(i/20+6)*32+i%20+6],"entire captured mask before scan");
            sample_valid=protocol==6;frame_end=1;@(negedge clk);frame_end=0;sample_valid=0;
        end
    endtask
    task send(input integer kind,cls,variant,input bit good,present,input integer protocol);
        bit healthy;
        begin
            scenarios++;frame_good=good;frame_present=present;make_mask(kind,cls,variant);
            capture(protocol);
            if(protocol==7)begin repeat(17)@(negedge clk);sample_valid=1;@(negedge clk);sample_valid=0;end
            if(protocol==8)begin frame_start=1;@(negedge clk);frame_start=0;frame_end=1;@(negedge clk);frame_end=0;expected_fg=0;end
            healthy=good && protocol==0;
            cycles=0;while(!out_frame && cycles<120000)begin @(negedge clk);cycles++;end
            ck(out_frame && out_raw_winner==(healthy?winner:0),"raw winner independent of qualified item");
            ck(out_best==(healthy?ranking_best:1025) && out_second==(healthy?ranking_second:1025) &&
                out_fg_count==expected_fg,"rank independently recomputed");
            ck(out_healthy==healthy && out_present==(healthy?present:1),"original health/presence");
            if(kind==3)ck(ranking_best==182 && ranking_second==182 && winner==10 &&
                !out_valid && out_item==0 && out_raw_winner==10,"proven class tie keeps first raw rank but rejects");
            if(inject && scenarios==1)ck(out_raw_winner==0,"negative raw winner oracle");
            repeat(3)@(negedge clk);
        end
    endtask
    task interrupt_at(input integer target_state,input bit reset_it);
        begin
            scenarios++;frame_good=1;frame_present=1;make_mask(0,4,201);capture(0);
            cycles=0;while(dut.state!=target_state && cycles<120000)begin @(negedge clk);cycles++;end
            ck(dut.state==target_state,"interrupt reaches requested scan/rank/emit state");
            if(reset_it)rst_n=0;else flush=1;
            @(negedge clk);ck(dut.state==0 && !out_frame && out_raw_winner==0,"interrupt revokes pending frame");
            rst_n=1;flush=0;
            repeat(4)begin @(negedge clk);ck(!out_frame,"no late frame after interrupt");end
        end
    endtask
    initial begin
        if(!$value$plusargs("ASSET_ROOT=%s",assets))$fatal(1,"asset root");
        n=$value$plusargs("INJECT_FAULT=%d",inject);
        $readmemh({assets,"/templates.mem"},bank);
        for(integer i=0;i<102400;i++)ck(dut.template_mem[i]===original.template_mem[i] && bank[i]===original.template_mem[i],"entire original ROM");
        repeat(4)@(negedge clk);rst_n=1;
        for(integer c=0;c<5;c++)send(0,c,c*37,1,1,0);
        send(1,0,0,1,0,0);send(2,0,0,1,1,0);send(0,0,0,0,1,0);
        frame_start=1;@(negedge clk);frame_start=0;sample_valid=1;sample_index=0;
        @(negedge clk);flush=1;@(negedge clk);ck(out_raw_winner==0 && !out_frame,"flush during capture");
        flush=0;sample_valid=0;send(0,4,201,1,1,0);
        rst_n=0;@(negedge clk);ck(out_raw_winner==0,"reset raw winner");rst_n=1;
        send(0,0,0,1,1,0);
        send(3,0,0,1,1,0);
        for(integer p=1;p<=8;p++)send(0,0,0,1,1,p);
        scenarios++;frame_id++;frame_end=1;@(negedge clk);frame_end=0;
        cycles=0;while(!out_frame && cycles<20)begin @(negedge clk);cycles++;end
        ck(out_frame && !out_healthy && out_present && !out_valid && out_raw_winner==0,"end without start is unhealthy");
        repeat(3)@(negedge clk);
        interrupt_at(2,0);interrupt_at(5,0);interrupt_at(7,0);
        interrupt_at(2,1);interrupt_at(5,1);interrupt_at(7,1);
        send(0,2,174,1,1,0);
        test_done=1;$display("RESULT matcher errors=%0d checks=%0d scenarios=%0d",errors,checks,scenarios);$finish;
    end
endmodule
