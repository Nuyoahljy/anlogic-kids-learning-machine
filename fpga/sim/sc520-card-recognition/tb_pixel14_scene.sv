`timescale 1ns/1ps
// RGB raster -> scene extraction checks. References are external fixture files;
// no DUT memory or internal state is used to predict either output raster.
module tb_pixel14_scene;
  parameter integer NORMAL_SIZE=20;
  reg clk=0; always #5 clk=~clk;
  reg rst_n=0,flush=0,in_valid=0,in_sof=0,in_eol=0;
  reg [10:0] in_x=0; reg [9:0] in_y=0; reg [23:0] in_rgb=0;
  reg in_frame_end=0,in_frame_good=1,in_source_test=0;
  reg [31:0] in_frame_id=0;
  wire replay_valid,replay_sof,replay_eol,replay_end,replay_good,replay_present,replay_source;
  wire [10:0] replay_x; wire [9:0] replay_y; wire [23:0] replay_rgb;
  wire [31:0] replay_id,card_id;
  wire card_start,card_valid,card_fg,card_end,card_good,card_present,card_source,out_revoke;
  wire [9:0] card_index; wire [15:0] dbg_scene_count,dbg_glyph_count;
  pixel14_scene_preprocess #(.NORMAL_SIZE(NORMAL_SIZE)) dut(.*);
  reg [23:0] pixels[0:57599],expected_replay[0:7199];
  reg expected_mask[0:1023];
  integer errors=0,checks=0,scenarios=0,injected=0,inject_fault=0,unused;
  reg test_done=0,check_pixels=0,check_counts=1,multi_check=0;
  integer clock_count=0,finished_at=0,max_latency=0,fixture_count=0;
  integer max_single_latency=0,last_card_tag=0,multi_tag=0,multi_replay_index=0,multi_card_index=0;
  integer eof_at[0:4095];
  integer replay_count=0,card_count=0,starts=0,replay_events=0,card_events=0,revokes=0;
  integer expected_present=0,expected_scene=0,expected_glyph=0,expected_background=0;
  integer expected_paper=-1,expected_paper_route=0;
  integer tag=0,expected_tag=0,expected_source=0;
  integer fd,status,number_of_fields,expect_card_valid,expect_item,expect_best,expect_second,expect_fg,expect_block;
  integer i,j,old_cards,old_replays,old_revokes,deadline;
  string assets,prefix,unused_line;
  task ck(input bit ok,input string msg); begin
    checks++;
    if(!ok) begin errors++; if(errors<=25) $display("FAIL scene case=%0d time=%0t %s",scenarios,$time,msg); end
  end endtask
  task new_case(input string msg); begin scenarios++; $display("CASE scene %0d %s",scenarios,msg); end endtask
  always @(posedge clk) begin
    #1; clock_count++;
    if(out_revoke) revokes++;
    if(replay_valid) begin
      ck(!replay_end,"end is separate from replay pixel");
      if(check_pixels) begin
        ck(replay_count<7200,"replay has exactly 7200 cells");
        if(replay_count<7200) begin
          ck(replay_x==replay_count%120 && replay_y==replay_count/120,"replay coordinates");
          ck(replay_sof==(replay_count==0) && replay_eol==(replay_count%120==119),"replay boundaries");
          if(replay_rgb!==expected_replay[replay_count])
            ck(0,$sformatf("replay RGB address=%0d got=%h want=%h",replay_count,replay_rgb,expected_replay[replay_count]));
          else ck(1,"replay RGB");
        end
        replay_count++;
      end
      if(multi_check) begin
        ck(replay_id==multi_tag || replay_id==multi_tag+1,"bank replay identity");
        ck(replay_x==multi_replay_index%120 && replay_y==multi_replay_index/120,"bank replay coordinates");
        ck(replay_rgb==((replay_x>=50 && replay_x<70 && replay_y>=20 && replay_y<40) ?
          (replay_id==multi_tag ? 24'hff2020 : 24'h2020ff) : 24'hffffff),"processing bank contents are not overwritten by next capture");
        multi_replay_index++;
      end
    end
    if(replay_end) begin
      replay_events++;
      ck(replay_good,"only certified complete frames publish a replay");
      if(check_pixels) begin
        ck(replay_count==7200,"complete replay raster before EOF");
        ck(replay_present==expected_present,"replay occupancy is model result");
        ck(replay_id==expected_tag && replay_source==expected_source,"replay metadata belongs to certified frame");
      end
      if(multi_check) begin
        ck(multi_replay_index==7200 && replay_present,"bank replay complete and present");multi_replay_index=0;
      end
    end
    if(card_start) begin
      starts++; ck(!card_valid && !card_end,"card start is a separate pulse");
    end
    if(card_valid) begin
      ck(!card_end,"card end is separate from final sample");
      if(check_pixels) begin
        ck(card_count<1024 && card_index==card_count,"card indices are ordered and complete");
        if(card_count<1024) begin
          if(card_fg!==expected_mask[card_count])ck(0,$sformatf("normalized card bit address=%0d",card_count));
          else ck(1,"normalized card bit");
        end
        card_count++;
      end
      if(multi_check) begin
        ck(card_index==multi_card_index && card_fg==((card_index%32>=(32-NORMAL_SIZE)/2) &&
          (card_index%32<(32+NORMAL_SIZE)/2) && (card_index/32>=(32-NORMAL_SIZE)/2) &&
          (card_index/32<(32+NORMAL_SIZE)/2)),"bank normalized solid square remains complete");
        multi_card_index++;
      end
      if(inject_fault && injected==0) begin
        force dut.card_index=10'd1023; injected=1; #0.01;
        ck(card_index==0,"real DUT output corruption is detected");
        release dut.card_index;
      end
    end
    if(card_end) begin
      card_events++;
      ck(card_good,"completed card stream retains frame health");
      ck(card_id>last_card_tag,"certified frame tags publish once in capture order");last_card_tag=card_id;
      if(card_id<4096 && clock_count-eof_at[card_id]>max_latency)max_latency=clock_count-eof_at[card_id];
      if(check_pixels && finished_at>0 && clock_count-finished_at>max_single_latency)max_single_latency=clock_count-finished_at;
      if(check_pixels) begin
        ck(card_count==1024,"complete normalized 32 by 32 stream");
        ck(clock_count-finished_at<400000,"unqueued scene processing fits a 400000-clock budget");
        ck(card_present==expected_present,"card presence matches replay presence");
        ck(card_id==expected_tag && card_source==expected_source,"card metadata belongs to certified frame");
        if(check_counts) begin
          ck(dbg_scene_count==expected_scene && dbg_glyph_count==expected_glyph,"denoised counts match external reference");
          ck({dut.background_r,dut.background_g,dut.background_b}==expected_background,"lower border median matches external reference");
          if(expected_paper>=0)ck(dut.paper_count==expected_paper && dut.paper_route==expected_paper_route,"bright paper support and routing match external reference");
        end
      end
      if(multi_check) begin
        ck(multi_card_index==1024 && card_present && dbg_scene_count==400 && dbg_glyph_count==400,"bank metadata and counts");
        multi_card_index=0;
      end
    end
  end
  task idle(input integer clocks); begin
    repeat(clocks) @(negedge clk);
  end endtask
  task clear; begin
    check_pixels=0;multi_check=0;
    @(negedge clk);flush=1;in_valid=0;in_sof=0;in_eol=0;in_frame_end=0;
    idle(3);flush=0;idle(3);
    replay_count=0;card_count=0;finished_at=0;multi_replay_index=0;multi_card_index=0;
  end endtask
  // Defects: coordinate, tag, source, EOL, short raster, bad certificate,
  // overlapping EOF, duplicate SOF, missing first SOF, missing EOF.
  task frame(input integer defect); integer x,y; begin
    tag++; expected_tag=tag; expected_source=in_source_test;
    in_frame_id=tag;
    for(y=0;y<(defect==5?179:180);y++) for(x=0;x<320;x++) begin
      @(negedge clk);in_valid=1;in_sof=x==0 && y==0 && defect!=9;in_eol=x==319;
      in_x=x;in_y=y;in_rgb=pixels[y*320+x];
      if(x==111 && y==71) begin
        if(defect==1) in_x=112;
        if(defect==2) in_frame_id=tag+100;
        if(defect==3) in_source_test=~in_source_test;
        if(defect==4) in_eol=1;
        if(defect==8) in_sof=1;
      end
      if((defect==11 || defect==12) && x==111 && y==71) begin
        @(negedge clk);in_valid=0;in_sof=0;in_eol=0;
        if(defect==11)in_frame_id=tag+100;else in_source_test=~in_source_test;
        @(negedge clk);in_frame_id=tag;
        if(defect==12)in_source_test=~in_source_test;
      end
    end
    @(negedge clk);in_valid=defect==7;in_sof=0;in_eol=0;
    in_frame_end=defect!=10;in_frame_good=defect!=6;
    finished_at=clock_count;
    if(tag<4096)eof_at[tag]=clock_count;
    @(negedge clk);in_valid=0;in_frame_end=0;in_frame_good=1;
  end endtask
  task await_card(input integer target); begin
    deadline=clock_count+1000000;
    while(card_events<target && clock_count<deadline) @(negedge clk);
    ck(card_events==target,"bounded extraction completes exactly once");
    idle(5);
  end endtask
  task white_expected; begin
    for(j=0;j<7200;j++)expected_replay[j]=24'hffffff;
    for(j=0;j<1024;j++)expected_mask[j]=0;
  end endtask
  initial begin
    unused=$value$plusargs("INJECT_FAULT=%d",inject_fault);
    if(!$value$plusargs("ASSET_ROOT=%s",assets)) $fatal(1,"ASSET_ROOT required");
    fd=$fopen({assets,"/fixtures.txt"},"r");if(!fd)$fatal(1,"fixtures.txt missing");
    idle(5);rst_n=1;idle(3);
    while(!$feof(fd)) begin
      number_of_fields=$fscanf(fd,"%s %d %d %d %d %d %d %d %d %d %h %d %d\n",prefix,expected_present,expected_scene,expected_glyph,
        expect_card_valid,expect_item,expect_best,expect_second,expect_fg,expect_block,expected_background,expected_paper,expected_paper_route);
      if(number_of_fields==13) begin
        clear;new_case(prefix);fixture_count++;
        $readmemh({assets,"/",prefix,".rgb.mem"},pixels);
        $readmemh({assets,"/",prefix,".replay.mem"},expected_replay);
        $readmemh({assets,"/",prefix,".mask.mem"},expected_mask);
        check_pixels=1;check_counts=1;old_cards=card_events;old_replays=replay_events;old_revokes=revokes;
        frame(0);await_card(old_cards+1);
        ck(replay_events==old_replays+1 && revokes==old_revokes,"one certified pair and no revoke");
        if(inject_fault && injected!=0) begin $fclose(fd);test_done=1;$finish;end
      end else if(number_of_fields!=-1) $fatal(1,"invalid fixture record");
    end
    $fclose(fd);ck(fixture_count>0,"at least one external fixture checked");
    expected_paper=-1;
    for(i=0;i<57600;i++)pixels[i]=24'h404040;
    white_expected;expected_present=0;expected_scene=0;expected_glyph=0;expected_background=24'h484848;
    for(i=1;i<=12;i++) begin
      clear;new_case($sformatf("raster or identity defect %0d",i));old_cards=card_events;old_replays=replay_events;old_revokes=revokes;
      frame(i);idle(450000);
      ck(card_events==old_cards && replay_events==old_replays,"bad/incomplete input never publishes empty or healthy data");
      ck(i==10 ? revokes==old_revokes : revokes>old_revokes,"explicit defects revoke; silent stop waits for external watchdog");
      clear;check_pixels=1;check_counts=1;old_cards=card_events;frame(0);await_card(old_cards+1);
    end
    clear;new_case("SOF without valid is revoked");old_revokes=revokes;
    @(negedge clk);in_sof=1;idle(1);in_sof=0;idle(3);ck(revokes==old_revokes+1,"invalid SOF pulse revokes once");
    clear;new_case("EOL without valid is revoked");old_revokes=revokes;
    @(negedge clk);in_eol=1;idle(1);in_eol=0;idle(3);ck(revokes==old_revokes+1,"invalid EOL pulse revokes once");
    clear;new_case("extra pixel after certified EOF cancels queued result");old_cards=card_events;old_replays=replay_events;old_revokes=revokes;
    frame(0);@(negedge clk);in_valid=1;in_sof=0;in_eol=0;in_x=0;in_y=0;
    @(negedge clk);in_valid=0;idle(450000);
    ck(revokes==old_revokes+1 && card_events==old_cards && replay_events==old_replays,"late unframed data cannot release an old empty");
    clear;new_case("flush during queued extraction cancels both outputs");old_cards=card_events;old_replays=replay_events;old_revokes=revokes;
    frame(0);idle(3000);clear;idle(450000);
    ck(card_events==old_cards && replay_events==old_replays && revokes==old_revokes,"flush cancels without feedback revoke");
    clear;new_case("two banks retain two certified frames in input order");old_cards=card_events;old_replays=replay_events;old_revokes=revokes;
    multi_tag=tag+1;multi_check=1;
    for(i=0;i<57600;i++)pixels[i]=(i%320>=140 && i%320<180 && i/320>=70 && i/320<110)?24'hff2020:24'h404040;
    frame(0);
    for(i=0;i<57600;i++)pixels[i]=(i%320>=140 && i%320<180 && i/320>=70 && i/320<110)?24'h2020ff:24'h404040;
    frame(0);await_card(old_cards+2);
    ck(replay_events==old_replays+2 && revokes==old_revokes,"two captures publish once each without overwrite");
    clear;new_case("third compact capture overruns fail closed");old_cards=card_events;old_replays=replay_events;old_revokes=revokes;
    frame(0);frame(0);frame(0);idle(450000);
    ck(revokes>old_revokes && card_events==old_cards && replay_events==old_replays,"no queue overwrite or fabricated empty on bank exhaustion");
    clear;new_case("lower median exact even split rejects uncertain boundary");
    for(i=0;i<57600;i++)pixels[i]=(i%320<160)?24'h000000:24'hffffff;
    white_expected;expected_present=1;check_counts=0;check_pixels=1;old_cards=card_events;
    frame(0);await_card(old_cards+1);
    ck({dut.background_r,dut.background_g,dut.background_b}==24'h080808,"even split chooses lower bin rather than upper");
    for(i=89;i<=90;i++) begin
      clear;new_case($sformatf("75 percent border-support threshold with %0d isolated outliers",i));
      for(j=0;j<57600;j++)pixels[j]=24'hffffff;
      status=0;
      for(j=0;j<7200;j++) if((j%120==0 || j%120==119 || j/120==0 || j/120==59) &&
        ((j%120+j/120)%2==0) && status<i) begin
        pixels[(31+2*(j/120))*320+41+2*(j%120)]=0;status++;
      end
      ck(status==i,"exact border-outlier count built independently");
      white_expected;expected_present=i==90;expected_scene=0;expected_glyph=0;expected_background=24'hf8f8f8;
      check_counts=1;check_pixels=1;old_cards=card_events;frame(0);await_card(old_cards+1);
    end
    clear;new_case("bright paper suppresses block pixels while retaining normalized card data");
    for(i=0;i<57600;i++)begin
      pixels[i]=24'h404040;
      if(i%320>=140 && i%320<180 && i/320>=70 && i/320<110)pixels[i]=24'hffffff;
      if(i%320>=150 && i%320<170 && i/320>=80 && i/320<100)pixels[i]=24'hff2020;
    end
    white_expected;
    for(i=0;i<1024;i++)if(i%32>=(32-NORMAL_SIZE)/2 && i%32<(32+NORMAL_SIZE)/2 &&
      i/32>=(32-NORMAL_SIZE)/2 && i/32<(32+NORMAL_SIZE)/2)expected_mask[i]=1;
    expected_present=1;expected_scene=400;expected_glyph=100;expected_background=24'h484848;expected_paper=300;expected_paper_route=1;
    check_counts=1;check_pixels=1;old_cards=card_events;frame(0);await_card(old_cards+1);
    clear;new_case("tiny residual keeps normalized content but never claims presence");
    for(i=0;i<57600;i++)pixels[i]=24'hffffff;
    for(i=58;i<=60;i++)pixels[(31+2*29)*320+41+2*i]=0;
    expected_present=0;expected_scene=1;expected_glyph=1;expected_background=24'hf8f8f8;expected_paper=0;expected_paper_route=0;
    check_counts=1;check_pixels=1;old_cards=card_events;frame(0);await_card(old_cards+1);
    clear;new_case("completed then stopped stream emits no repeated events");
    for(i=0;i<57600;i++)pixels[i]=24'h404040;
    old_cards=card_events;frame(0);await_card(old_cards+1);old_cards=card_events;old_replays=replay_events;idle(500000);
    ck(card_events==old_cards && replay_events==old_replays,"idle source never creates new empty frames");
    $display("SCENE_LATENCY max_after_eof_clocks=%0d max_single_clocks=%0d fixtures=%0d",max_latency,max_single_latency,fixture_count);
    test_done=1;$finish;
  end
  initial begin #(64'd10000000000);$display("SCENE_TEST_WATCHDOG");$finish;end
endmodule
