`timescale 1ns/1ps
module tb_contour29_scene;
  reg clk=0;always #5 clk=~clk;
  reg rst_n=0,flush=0,in_valid=0,in_sof=0,in_eol=0,in_frame_end=0,in_frame_good=1,in_source_test=0;
  reg [10:0] in_x=0;reg [9:0] in_y=0;
  reg [23:0] in_rgb=0;reg [31:0] in_frame_id=0;
  wire replay_valid,replay_sof,replay_eol,replay_glyph,replay_end,replay_good,replay_present,replay_source;
  wire [10:0] replay_x;wire [9:0] replay_y;wire [23:0] replay_rgb;wire [31:0] replay_id;
  wire card_start,card_valid,card_fg,card_end,card_good,card_present,card_source,out_revoke;
  wire [9:0] card_index;wire [31:0] card_id;
  wire contour_fg,contour_axis_fg,full_axis_fg,contour_qualified,contour_aspect_good,contour_boundary_repair,contour_exterior_ok;
  wire [1:0] contour_color;
  wire [15:0] dbg_scene_count,dbg_glyph_count,dbg_paper_count;wire dbg_scene_event;wire [3:0] dbg_scene_flags;
  pixel29_scene_preprocess dut(.*);
  reg [23:0] raster[0:57599];reg [3:0] expected_norm[0:1023];
  integer errors=0,checks=0,scenarios=0,injected=0,samples=0,replay_samples=0,max_cycles=0,known_misses=0;
  reg test_done=0;integer fd,fields,metadata,want_present,truth,contract_item,x,y,cycles;
  string assets,case_file,prefix;
  task ck(input bit condition,input string message);
    begin checks++;if(!condition)begin errors++;if(errors<25)$display("FAIL case=%0d time=%0t %s",scenarios,$time,message);end end
  endtask
  always @(posedge clk)begin
    #1;
    if(rst_n)begin
      if(replay_valid)begin
        ck(replay_id==in_frame_id && !replay_source,"replay identity");
        replay_samples++;
      end
      if(card_valid)begin
        ck(card_id==in_frame_id && !card_source,"normalized identity");
        ck(card_index==samples,"monotonic normalized index");
        ck({full_axis_fg,contour_axis_fg,contour_fg,card_fg}===expected_norm[card_index],"four normalized masks match independent array calculation");
        samples++;
      end
      ck(!out_revoke,"healthy fixture does not revoke");
    end
  end
  initial begin
    if(!$value$plusargs("ASSET_ROOT=%s",assets))$fatal(1,"ASSET_ROOT required");
    if(!$value$plusargs("CASE_FILE=%s",case_file))case_file="smoke-cases.txt";
    repeat(5)@(negedge clk);rst_n=1;fd=$fopen({assets,"/",case_file},"r");
    if(!fd)$fatal(1,"case file missing");
    while(!$feof(fd))begin
      fields=$fscanf(fd,"%s %d %d %d %d\n",prefix,metadata,want_present,truth,contract_item);
      if(fields==5)begin
        scenarios++;$display("CASE %0d %s truth=%0d contract=%0d",scenarios,prefix,truth,contract_item);
        if(truth!=0 && contract_item==0)known_misses++;
        $readmemh({assets,"/",prefix,".rgb.mem"},raster);
        $readmemh({assets,"/",prefix,".norm.mem"},expected_norm);
        samples=0;replay_samples=0;in_frame_id++;
        for(y=0;y<180;y++)for(x=0;x<320;x++)begin
          in_valid=1;in_sof=x==0 && y==0;in_eol=x==319;in_x=x;in_y=y;in_rgb=raster[y*320+x];
          @(negedge clk);
        end
        in_valid=0;in_sof=0;in_eol=0;in_frame_end=1;
        @(negedge clk);in_frame_end=0;cycles=0;
        while(!card_end && cycles<1200000)begin @(negedge clk);cycles++;end
        if(cycles>max_cycles)max_cycles=cycles;
        ck(cycles<1200000,"processing completes within existing frame wait bound");
        ck(samples==1024 && replay_samples==7200,"complete replay and normalized streams");
        ck(card_good && card_present==want_present && card_id==in_frame_id,"full scene health and presence");
        ck({contour_color,contour_exterior_ok,contour_boundary_repair,contour_aspect_good,contour_qualified}==metadata[5:0],"contour metadata");
        repeat(12)@(negedge clk);
      end
    end
    $fclose(fd);test_done=1;
    $display("RESULT errors=%0d checks=%0d scenarios=%0d max_cycles=%0d known_misses=%0d",errors,checks,scenarios,max_cycles,known_misses);
    $finish;
  end
endmodule
