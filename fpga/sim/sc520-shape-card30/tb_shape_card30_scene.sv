`timescale 1ns/1ps
module tb_shape_card30_scene;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,flush=0,in_valid=0,in_sof=0,in_eol=0,in_frame_end=0,in_frame_good=1,in_source_test=0;
    reg [10:0] in_x=0;reg [9:0] in_y=0;reg [23:0] in_rgb=0;reg [31:0] in_frame_id=0;
    wire replay_valid,replay_sof,replay_eol,replay_end,replay_good,replay_present,replay_source;
    wire [10:0] replay_x;wire [9:0] replay_y;wire [23:0] replay_rgb;wire [31:0] replay_id;
    wire card_start,card_valid,card_fg,card_end,card_good,card_present,card_source,out_revoke;
    wire [9:0] card_index;wire [31:0] card_id;
    wire axis_start,axis_valid,axis_end,axis_fg;wire [9:0] axis_index;
    wire [11:0] glyph_bbox_width,glyph_bbox_height;wire [7:0] glyph_y_min,glyph_y_max;wire glyph_y_available;
    wire [15:0] dbg_scene_count,dbg_glyph_count,dbg_paper_count;wire dbg_scene_event;wire [3:0] dbg_scene_flags;
    pixel30_scene_preprocess dut(.*);
    integer errors=0,checks=0,scenarios=0,full_samples=0,axis_samples=0,replay_samples=0,max_cycles=0;
    reg test_done=0;reg full_mask[0:1023],axis_mask[0:1023];reg [23:0] raster[0:57599];
    reg [15:0] expected_scene[0:3];reg protocol_revoke=0;integer scene_events=0;
    string assets,prefix;integer fd,n,circle,square,triangle,ellipse,axis_d,present,clip,ymin,ymax,w,h,available,item,cycles,inject=0;
    task ck(input bit ok,input string message);
        begin checks++;if(!ok)begin errors++;if(errors<20)$display("FAIL case=%0d cycle=%0d %s",scenarios,cycles,message);end end
    endtask
    always @(posedge clk)begin
        #1;
        if(rst_n)begin
            if(out_revoke)protocol_revoke=1;
            if(dbg_scene_event)scene_events++;
            if(card_valid)begin
                ck(card_index==full_samples && card_fg===full_mask[card_index],"original full mask/index");
                ck(card_id==in_frame_id && !card_source,"full identity");full_samples++;
            end
            if(axis_valid)begin
                ck(axis_index==axis_samples && axis_fg===axis_mask[axis_index],"axis mask/index");
                ck(card_id==in_frame_id && !card_source,"axis identity");axis_samples++;
            end
            if(replay_valid)replay_samples++;
        end
    end
    initial begin
        if(!$value$plusargs("ASSET_ROOT=%s",assets))$fatal(1,"assets required");
        n=$value$plusargs("INJECT_FAULT=%d",inject);
        repeat(5)@(negedge clk);rst_n=1;
        fd=$fopen({assets,"/cases.txt"},"r");if(!fd)$fatal(1,"cases missing");
        while(!$feof(fd))begin
            n=$fscanf(fd,"%s %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
                prefix,circle,square,triangle,ellipse,axis_d,present,clip,ymin,ymax,w,h,available,item);
            if(n==14)begin
                scenarios++;in_frame_id++;full_samples=0;axis_samples=0;replay_samples=0;protocol_revoke=0;scene_events=0;
                $readmemh({assets,"/",prefix,".rgb.mem"},raster);
                $readmemh({assets,"/",prefix,".full.mem"},full_mask);
                $readmemh({assets,"/",prefix,".axis.mem"},axis_mask);
                $readmemh({assets,"/",prefix,".scene.mem"},expected_scene);
                $display("CASE scene %0d %s",scenarios,prefix);
                for(integer y=0;y<180;y++)for(integer x=0;x<320;x++)begin
                    in_valid=1;in_sof=x==0 && y==0;in_eol=x==319;in_x=x;in_y=y;in_rgb=raster[y*320+x];@(negedge clk);
                end
                in_valid=0;in_sof=0;in_eol=0;in_frame_end=1;@(negedge clk);in_frame_end=0;
                cycles=0;while(!axis_end && cycles<1200000)begin @(negedge clk);cycles++;end
                ck(cycles<1200000,"two-pass processing within unchanged deadline");
                if(cycles>max_cycles)max_cycles=cycles;
                ck(full_samples==1024 && axis_samples==1024 && replay_samples==7200,"complete full/axis/replay streams");
                ck(card_good && card_present==present,"good frame occupancy independent of class");
                ck(!protocol_revoke && scene_events==1,"one scene completion and no protocol revoke");
                ck(dbg_scene_count==expected_scene[0] && dbg_glyph_count==expected_scene[1] &&
                   dbg_paper_count==expected_scene[2] && dbg_scene_flags==expected_scene[3][3:0],
                   "actual filtered scene/glyph/paper counts and all four flags");
                if(inject && scenarios==1)begin force dut.glyph_y_max=0;#1;end
                ck(glyph_y_available==available && glyph_y_min==ymin && glyph_y_max==ymax,"Y extrema use only actual filtered center RGB");
                ck(glyph_bbox_width==w && glyph_bbox_height==h,"same complete glyph bbox dimensions");
                if(inject && scenarios==1)release dut.glyph_y_max;
                repeat(12)@(negedge clk);
            end
        end
        $fclose(fd);test_done=1;
        $display("RESULT scene errors=%0d checks=%0d scenarios=%0d max_cycles=%0d",errors,checks,scenarios,max_cycles);$finish;
    end
endmodule
