`timescale 1ns/1ps
module tb_color26_scene_oracle;
 reg clk=0,rst_n=0,flush=0,in_valid=0,in_sof=0,in_eol=0,in_frame_end=0,in_frame_good=1,in_source_test=0;
 reg [10:0] in_x=0;reg [9:0] in_y=0;reg [23:0] in_rgb=0;reg [31:0] in_frame_id=0;
 wire replay_valid,replay_sof,replay_eol,replay_end,replay_good,replay_present,replay_source;
 wire [10:0] replay_x;wire [9:0] replay_y;wire [23:0] replay_rgb;wire [31:0] replay_id;
 wire card_start,card_valid,card_fg,card_end,card_good,card_present,card_source,out_revoke;
 wire [9:0] card_index;wire [31:0] card_id;wire [15:0] dbg_scene_count,dbg_glyph_count,dbg_paper_count;wire dbg_scene_event;wire [3:0] dbg_scene_flags;
 pixel26_scene_preprocess dut(.*);
 always #4.83 clk=~clk;
 integer errors=0,checks=0,scenarios=0,injected=0,inject_fault=0,ignored,fd,outfd,fields,x,y,i,wait_cycles;
 integer want_present,want_scene,want_glyph,want_paper,replays=0,cards=0;
 reg test_done=0,active=0,ended=0;reg [23:0] raster[0:57599],expected_replay[0:7199];reg expected_mask[0:1023];string root_path,prefix;
 task ck(input bit good,input string why);begin checks++;if(!good)begin errors++;if(errors<20)$display("FAIL case=%d %s",scenarios,why);end end endtask
 always @(posedge clk)begin #1;if(active)begin
  ck(!out_revoke,"valid complete source never revokes");
  if(replay_valid)begin
   ck(replay_id==in_frame_id && replay_source==in_source_test,"replay tag and source");
   ck(replay_x==replays%120&&replay_y==replays/120&&replay_sof==(replays==0)&&replay_eol==(replays%120==119),"all replay raster markers");
   ck(replay_rgb===expected_replay[replays],"complete scene RGB replay equals independent oracle");replays++;
  end
  if(card_valid)begin
   if(inject_fault && !injected && cards==53)begin force dut.card_fg=~expected_mask[cards];injected=1;#0.01;end
   ck(card_index==cards&&card_fg===expected_mask[cards],"all1024 normalized mask bits equal independent oracle");
   if(inject_fault && injected)release dut.card_fg;cards++;
  end
  if(card_end)begin
   ck(card_good&&card_present==want_present&&card_id==in_frame_id,"qualified card status");
   ck(replays==7200&&cards==1024,"complete replay/mask lengths");
   ck(dbg_scene_count==want_scene&&dbg_glyph_count==want_glyph&&dbg_paper_count==want_paper,"scene glyph and paper exact counts");ended=1;
  end
 end end
 initial begin
  ignored=$value$plusargs("INJECT_FAULT=%d",inject_fault);if(!$value$plusargs("ASSET_ROOT=%s",root_path))$fatal(1,"ASSET_ROOT required");
  fd=$fopen({root_path,"/oracle-cases.txt"},"r");if(!fd)$fatal(1,"oracle cases missing");
  outfd=$fopen("oracle-results.csv","w");$fwrite(outfd,"case,replay,mask,scene,glyph,paper,errors\n");
  repeat(4)@(negedge clk);rst_n=1;
  while(!$feof(fd))begin
   fields=$fscanf(fd,"%s %d %d %d %d\n",prefix,want_present,want_scene,want_glyph,want_paper);
   if(fields==5)begin
    scenarios++;$display("CASE oracle %d %s",scenarios,prefix);
    $readmemh({root_path,"/",prefix,".rgb.mem"},raster);$readmemh({root_path,"/",prefix,".replay.mem"},expected_replay);$readmemh({root_path,"/",prefix,".mask.mem"},expected_mask);
    @(negedge clk);in_frame_id++;in_source_test=scenarios[0];active=1;ended=0;replays=0;cards=0;
    for(y=0;y<180;y++)for(x=0;x<320;x++)begin
     in_x=x;in_y=y;in_valid=1;in_sof=(x==0&&y==0);in_eol=(x==319);in_rgb=raster[y*320+x];@(negedge clk);
    end
    in_valid=0;in_sof=0;in_eol=0;in_frame_end=1;@(negedge clk);in_frame_end=0;
    wait_cycles=0;while(!ended&&wait_cycles<1200000)begin @(negedge clk);wait_cycles++;end
    ck(ended,"bounded scene completion");active=0;
    $fwrite(outfd,"%s,%d,%d,%d,%d,%d,%d\n",prefix,replays,cards,dbg_scene_count,dbg_glyph_count,dbg_paper_count,errors);
    repeat(8)@(negedge clk);
   end else if(fields!=-1)$fatal(1,"invalid oracle case row");
  end
  $fclose(fd);$fclose(outfd);test_done=1;$display("DONE scene oracle cases=%d checks=%d errors=%d",scenarios,checks,errors);$finish;
 end
 initial begin #3000000000;$display("WATCHDOG scene oracle");$finish;end
endmodule
