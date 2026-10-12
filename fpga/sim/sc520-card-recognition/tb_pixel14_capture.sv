`timescale 1ns/1ps
// The golden raster and sample coordinates are generated from public geometry;
// no DUT counters, sampling pointers, health state, or helper functions are read.
module tb_pixel14_capture;
    reg clk=0;
    always #5 clk=~clk;
    integer errors=0,checks=0,scenarios=0,injected=0,inject_fault=0,ignored;
    reg test_done=0;
    reg rst_n[0:1],flush[0:1],fs[0:1],src[0:1],iv[0:1],ie[0:1],fd[0:1],fg[0:1],ds[0:1],ir[0:1];
    reg [31:0] tag[0:1],dt[0:1];
    reg [95:0] rgb[0:1];
    wire cs[0:1],sv[0:1],sf[0:1],ce[0:1],cg[0:1],cp[0:1],csrc[0:1];
    wire [9:0] si[0:1];
    wire [31:0] ct[0:1],bt[0:1];
    wire [19:0] roi_count[0:1],block_roi_count[0:1];
    wire bv[0:1],bs[0:1],be[0:1],bend[0:1],bg[0:1],bp[0:1],bsrc[0:1],rv[0:1];
    wire [10:0] bx[0:1];
    wire [9:0] by[0:1];
    wire [23:0] brgb[0:1];
    integer samples[0:1],blocks[0:1],roi_expected[0:1],block_roi_expected[0:1],sample_lanes[0:1];
    genvar g;
    generate for(g=0;g<2;g=g+1) begin:lane_dut
        capture_rgb96 #(.FRAME_WIDTH(g==0?256:1280),.FRAME_HEIGHT(g==0?256:720),
            .ROI_X(g==0?63:400),.ROI_Y(g==0?61:120),.ROI_SIZE(g==0?128:480),
            .BLOCK_ROI_X(g==0?48:320),.BLOCK_ROI_Y(g==0?48:120),
            .BLOCK_ROI_WIDTH(g==0?160:640),.BLOCK_ROI_HEIGHT(g==0?160:480)) dut (
            .clk(clk),.rst_n(rst_n[g]),.flush(flush[g]),.in_frame_start(fs[g]),
            .in_frame_id(tag[g]),.in_source_test(src[g]),.in_valid(iv[g]),.in_eol(ie[g]),.in_rgb96(rgb[g]),
            .in_frame_done(fd[g]),.in_frame_good(fg[g]),.in_done_id(dt[g]),.in_done_source_test(ds[g]),.in_revoke(ir[g]),
            .card_frame_start(cs[g]),.card_sample_valid(sv[g]),.card_sample_index(si[g]),.card_sample_foreground(sf[g]),
            .card_frame_end(ce[g]),.card_frame_good(cg[g]),.card_frame_present(cp[g]),
            .card_frame_id(ct[g]),.card_source_test(csrc[g]),.roi_fg_count(roi_count[g]),
            .block_valid(bv[g]),.block_sof(bs[g]),.block_eol(be[g]),.block_x(bx[g]),.block_y(by[g]),.block_rgb(brgb[g]),
            .block_frame_end(bend[g]),.block_frame_good(bg[g]),.block_frame_present(bp[g]),.block_roi_fg_count(block_roi_count[g]),
            .block_frame_id(bt[g]),.block_source_test(bsrc[g]),.revoke(rv[g]));
    end endgenerate

    function integer width_of(input integer p);width_of=p==0?256:1280;endfunction
    function integer height_of(input integer p);height_of=p==0?256:720;endfunction
    function integer rx_of(input integer p);rx_of=p==0?63:400;endfunction
    function integer ry_of(input integer p);ry_of=p==0?61:120;endfunction
    function integer size_of(input integer p);size_of=p==0?128:480;endfunction
    function integer brx_of(input integer p);brx_of=p==0?48:320;endfunction
    function integer bry_of(input integer p);bry_of=p==0?48:120;endfunction
    function integer brw_of(input integer p);brw_of=p==0?160:640;endfunction
    function integer brh_of(input integer p);brh_of=p==0?160:480;endfunction
    function [23:0] pixel(input integer x,input integer y,input integer pattern);
        begin
            if(pattern==0) pixel=24'hffffff;
            else if(pattern==2) pixel=x==49 && y==49 ? 24'h000000 : 24'hffffff;
            else case((x+3*y)%8)
                0:pixel=24'hb3b3b3; // gray179: dark
                1:pixel=24'hb4b4b4; // gray180: background
                2:pixel=24'hdcb4b4; // chroma40: foreground
                3:pixel=24'hdbb4b4; // chroma39: background
                4:pixel=24'h14e628; // dark and colored
                5:pixel=24'hffffff;
                6:pixel=24'hb4dcb4; // another channel reaches40
                7:pixel=24'hb4b4db;
            endcase
        end
    endfunction
    function bit golden_fg(input integer x,input integer y,input integer pattern);
        golden_fg=pattern==2 ? x==49 && y==49 : pattern!=0 && ((x+3*y)%2==0);
    endfunction
    task ck(input bit okay,input string label);
        begin checks=checks+1;if(!okay)begin errors=errors+1;$display("ERROR pixel14_capture case=%0d t=%0t %s",scenarios,$time,label);end end
    endtask
    task scenario(input string label);
        begin scenarios=scenarios+1;$display("CASE pixel14_capture %0d %s",scenarios,label);end
    endtask
    task drive_idle(input integer p);
        begin fs[p]=0;iv[p]=0;ie[p]=0;fd[p]=0;flush[p]=0;ir[p]=0;end
    endtask
    task cycle(input integer p);
        begin @(posedge clk);#1;end
    endtask
    task idle(input integer p);
        begin @(negedge clk);drive_idle(p);cycle(p);end
    endtask
    task reset_lane(input integer p);
        begin
            @(negedge clk);drive_idle(p);rst_n[p]=0;tag[p]=0;src[p]=0;dt[p]=0;ds[p]=0;fg[p]=0;rgb[p]=0;
            cycle(p);ck(!cs[p]&&!sv[p]&&!bv[p]&&!ce[p]&&!bend[p]&&!rv[p],"reset creates no observation");
            @(negedge clk);rst_n[p]=1;
        end
    endtask
    task start_frame(input integer p,input logic [31:0] id,input bit source);
        begin
            samples[p]=0;blocks[p]=0;roi_expected[p]=0;block_roi_expected[p]=0;sample_lanes[p]=0;
            @(negedge clk);drive_idle(p);fs[p]=1;tag[p]=id;src[p]=source;cycle(p);
            ck(cs[p]&&!sv[p]&&!bv[p]&&!ce[p]&&!rv[p],"early SOF arms without inventing pixels");
            ck(ct[p]===id && bt[p]===id && csrc[p]===source && bsrc[p]===source,"source identity is locked at start");
        end
    endtask
    task send_group(input integer p,input integer x,input integer y,input integer pattern,input bit start_same_cycle);
        integer k,sx,sy,cell_size,expected_index,expected_lane;
        bit expected_sample,expected_block,forced;
        begin
            cell_size=size_of(p)/32;expected_sample=0;expected_index=0;expected_lane=0;
            // Enumerate the 32 prescribed centers, independently of DUT state.
            if(y>=ry_of(p)+cell_size/2 && y<ry_of(p)+size_of(p) &&
               (y-ry_of(p)-cell_size/2)%cell_size==0) begin
                sy=(y-ry_of(p)-cell_size/2)/cell_size;
                for(k=0;k<32;k=k+1) begin
                    sx=rx_of(p)+k*cell_size+cell_size/2;
                    if(sx>=x && sx<x+4) begin expected_sample=1;expected_index=sy*32+k;expected_lane=sx-x;end
                end
            end
            expected_block=y%4==2;
            @(negedge clk);drive_idle(p);iv[p]=1;ie[p]=x==width_of(p)-4;fs[p]=start_same_cycle;
            rgb[p]={pixel(x,y,pattern),pixel(x+1,y,pattern),pixel(x+2,y,pattern),pixel(x+3,y,pattern)};
            forced=inject_fault!=0 && injected==0 && p==0 && expected_block && x==0;
            if(forced) begin force lane_dut[0].dut.block_rgb=24'h010203;injected=injected+1;end
            cycle(p);
            ck(!rv[p]&&!ce[p]&&!bend[p],"healthy pixels alone do not end or revoke frame");
            ck(sv[p]===expected_sample,"card center sampling strobe");
            if(expected_sample) begin
                ck(si[p]===expected_index[9:0],"card index matches independent 32x32 center");
                ck(sf[p]===golden_fg(x+expected_lane,y,pattern),"card threshold and high-to-low lane selection");
                samples[p]=samples[p]+1;sample_lanes[p]=sample_lanes[p]|(1<<expected_lane);
            end
            ck(bv[p]===expected_block,"one center pixel from each 4x4 block");
            if(expected_block) begin
                ck(bx[p]===x/4 && by[p]===y/4,"downsample coordinates");
                ck(bs[p]===(x==0&&y==2) && be[p]===(x==width_of(p)-4),"downsample SOF and EOL");
                ck(brgb[p]===pixel(x+2,y,pattern),"downsample keeps exact center RGB");
                blocks[p]=blocks[p]+1;
            end else ck(!bs[p]&&!be[p],"downsample markers only accompany a pixel");
            ck(ct[p]===tag[p] && bt[p]===tag[p] && csrc[p]===src[p] && bsrc[p]===src[p],"pixel streams carry locked tag and source");
            for(k=0;k<4;k=k+1) begin
                if(x+k>=rx_of(p) && x+k<rx_of(p)+size_of(p) && y>=ry_of(p) && y<ry_of(p)+size_of(p))
                    roi_expected[p]=roi_expected[p]+golden_fg(x+k,y,pattern);
                if(x+k>=brx_of(p) && x+k<brx_of(p)+brw_of(p) && y>=bry_of(p) && y<bry_of(p)+brh_of(p))
                    block_roi_expected[p]=block_roi_expected[p]+golden_fg(x+k,y,pattern);
            end
            if(forced) release lane_dut[0].dut.block_rgb;
        end
    endtask
    task raster(input integer p,input integer pattern,input bit same_cycle_start);
        integer x,y;
        begin
            for(y=0;y<height_of(p);y=y+1) begin
                for(x=0;x<width_of(p);x=x+4) send_group(p,x,y,pattern,same_cycle_start&&x==0&&y==0);
                // The real AWB emits continuous groups per line, but downstream
                // must also tolerate arbitrary blank cycles between lines.
                if(y%17==0) begin idle(p);ck(!sv[p]&&!bv[p]&&!ce[p]&&!rv[p],"line gap does not manufacture pixels");end
            end
            ck(samples[p]==1024,"exactly1024 samples");
            ck(blocks[p]==width_of(p)*height_of(p)/16,"full reduced raster pixel count");
        end
    endtask
    task close_frame(input integer p,input bit upstream_good,input logic [31:0] done_tag,input bit done_source,
                     input bit expected_good,input bit expected_revoke);
        begin
            @(negedge clk);drive_idle(p);fd[p]=1;fg[p]=upstream_good;dt[p]=done_tag;ds[p]=done_source;cycle(p);
            ck(ce[p]&&bend[p]&&cg[p]===expected_good&&bg[p]===expected_good,"both paths share explicit completion qualification");
            ck(rv[p]===expected_revoke,"completion emits the specified one-shot revoke");
            if(expected_good) begin
                ck(roi_count[p]===roi_expected[p],"all ROI pixels counted, including unsampled lanes");
                ck(cp[p]===(roi_expected[p]!=0),"only healthy empty ROI may report absent");
                ck(block_roi_count[p]===block_roi_expected[p],"full-resolution block ROI includes every lane and row");
                ck(bp[p]===(block_roi_expected[p]!=0),"reduced sampling never establishes absence");
            end else ck(cp[p]&&bp[p],"bad frame is not physical absence");
            idle(p);ck(!ce[p]&&!bend[p]&&!rv[p],"completion and local revoke are one-cycle events");
        end
    endtask

    integer p,k,kind;
    initial begin
        ignored=$value$plusargs("INJECT_FAULT=%d",inject_fault);
        for(p=0;p<2;p=p+1) begin rst_n[p]=0;drive_idle(p);tag[p]=0;src[p]=0;dt[p]=0;ds[p]=0;fg[p]=0;rgb[p]=0;end
        reset_lane(0);reset_lane(1);
        scenario("256x256 cell4 with unaligned ROI, threshold boundaries and early SOF");
        start_frame(0,32'h12345678,1);repeat(4)idle(0);raster(0,1,0);
        scenario("all expected pixels still cannot invent a real capture EOF");
        repeat(20)begin idle(0);ck(!ce[0]&&!bend[0]&&!rv[0],"no external EOF means no completed record");end
        close_frame(0,1,32'h12345678,1,1,0);
        scenario("full1280x720 cell15 exercises all four packed RGB lanes");
        start_frame(1,32'hffffffff,0);raster(1,1,0);ck(sample_lanes[1]==15,"cell15 rotates through all input lanes");
        close_frame(1,1,32'hffffffff,0,1,0);
        scenario("SOF may share the first group; healthy white ROI is absence");
        tag[0]=0;src[0]=0;samples[0]=0;blocks[0]=0;roi_expected[0]=0;block_roi_expected[0]=0;sample_lanes[0]=0;
        raster(0,0,1);close_frame(0,1,0,0,1,0);
        scenario("a tiny foreground point missed by all4x4 centers is still present");
        start_frame(0,1,0);raster(0,2,0);close_frame(0,1,1,0,1,0);
        ck(roi_count[0]==0 && !cp[0] && block_roi_count[0]==1 && bp[0],"point outside card ROI cannot falsely arm absence in block ROI");

        for(kind=0;kind<3;kind=kind+1) begin
            scenario("complete raster cannot override upstream failure or wrong done identity");
            start_frame(0,100+kind,kind==2);raster(0,0,0);
            close_frame(0,kind!=0,kind==1?999:100+kind,0,0,1);
            ck(ct[0]===100+kind && bt[0]===100+kind,"bad done does not relabel current frame");
        end
        scenario("short frame EOF fails immediately");
        start_frame(0,200,0);send_group(0,0,0,0,0);close_frame(0,1,200,0,0,1);
        scenario("blank EOL is a protocol fault, once per frame");
        start_frame(0,201,0);@(negedge clk);drive_idle(0);ie[0]=1;cycle(0);ck(rv[0],"blank EOL immediately revokes");
        @(negedge clk);ie[0]=1;cycle(0);ck(!rv[0],"same bad frame does not repeat local revoke");
        close_frame(0,1,201,0,0,0);
        scenario("wrong line length immediately revokes without padding");
        start_frame(0,202,0);@(negedge clk);drive_idle(0);iv[0]=1;ie[0]=1;rgb[0]=0;cycle(0);
        ck(rv[0]&&!sv[0]&&!bv[0],"premature tlast invalidates its group");close_frame(0,1,202,0,0,0);
        scenario("changing tag or source while active cannot relabel pixels");
        for(kind=0;kind<2;kind=kind+1)begin
            start_frame(0,203+kind,0);@(negedge clk);drive_idle(0);iv[0]=1;tag[0]=kind==0?999:204;src[0]=kind==1;cycle(0);
            ck(rv[0]&&!sv[0]&&!bv[0],"active identity mismatch revokes immediately");
            ck(ct[0]===203+kind && !csrc[0],"original identity retained");close_frame(0,1,203+kind,0,0,0);
        end
        scenario("overlapping start aborts old frame and rejects ambiguous new start");
        start_frame(0,210,1);@(negedge clk);drive_idle(0);fs[0]=1;tag[0]=211;src[0]=0;cycle(0);
        ck(rv[0]&&ce[0]&&bend[0]&&!cg[0]&&!bg[0]&&!cs[0],"overlap is an unhealthy abort, not an accepted new frame");
        ck(ct[0]==210&&csrc[0],"overlap retains old association");idle(0);
        scenario("unframed data is rejected and not counted as a frame");
        reset_lane(0);@(negedge clk);iv[0]=1;cycle(0);ck(rv[0]&&!cs[0]&&!sv[0]&&!bv[0],"orphan input rejected");
        @(negedge clk);cycle(0);ck(!rv[0],"continued orphan data does not repeat local revoke");idle(0);
        scenario("flush cancels synchronously without a revoke feedback loop");
        start_frame(0,220,0);repeat(3)begin @(negedge clk);drive_idle(0);flush[0]=1;cycle(0);ck(!rv[0]&&!ce[0]&&!bend[0]&&!bv[0]&&!sv[0],"held flush is quiet cancellation");end
        idle(0);
        scenario("external revoke may remain asserted and poisons the active frame");
        start_frame(0,221,0);repeat(3)begin @(negedge clk);drive_idle(0);ir[0]=1;cycle(0);ck(rv[0]&&!sv[0]&&!bv[0],"upstream revoke level is preserved");end
        idle(0);ck(!rv[0],"upstream revoke release has no extra event");close_frame(0,1,221,0,0,0);
        scenario("EOF simultaneous with pixels is never a successful close");
        start_frame(0,222,0);@(negedge clk);drive_idle(0);fd[0]=1;fg[0]=1;dt[0]=222;ds[0]=0;iv[0]=1;cycle(0);
        ck(rv[0]&&ce[0]&&bend[0]&&!cg[0]&&!bg[0]&&!sv[0]&&!bv[0],"EOF requires a blank cycle");idle(0);
        scenario("reset during a frame cannot publish partial work");
        start_frame(0,223,0);send_group(0,0,0,1,0);reset_lane(0);
        scenario("fresh complete frame recovers after reset and multiple faults");
        start_frame(0,224,0);raster(0,1,0);close_frame(0,1,224,0,1,0);
        ck(!inject_fault||injected==1,"negative probe forced exactly one actual DUT output");
        test_done=1;$display("RESULT tb_pixel14_capture errors=%0d checks=%0d scenarios=%0d injected=%0d",errors,checks,scenarios,injected);$finish;
    end
    initial begin #100000000;errors=errors+1;$display("WATCHDOG tb_pixel14_capture errors=%0d",errors);$finish;end
endmodule
