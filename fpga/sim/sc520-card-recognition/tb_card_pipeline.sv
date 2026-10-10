`timescale 1ns/1ps
// Tests the complete real RGB/coordinate input, not a bypass of the sampler.
// Supported frame boundary: standalone EOF clock, then at least one additional
// marker-free invalid clock before the next SOF. Results may emerge while the
// first pixels of the next frame are already being accepted.
module tb_card_pipeline;
  reg clk=0;always #5 clk=~clk;
  reg rst_n=0,flush=0,in_valid=0,in_sof=0,in_eol=0,in_frame_end=0,in_source_test=0;
  reg[10:0]in_x=0;reg[9:0]in_y=0;reg[23:0]in_rgb=24'hffffff;reg[31:0]in_frame_id=0;
  wire out_frame,out_healthy,out_present,out_valid,out_source_test;
  wire[3:0]out_item;wire[31:0]out_frame_id;wire[7:0]stable_count;
  wire[10:0]best_distance,second_distance,sample_fg_count;wire[19:0]roi_fg_count;
  integer errors=0,checks=0,scenarios=0;reg test_done=0;
  integer count=0,candidate=0;reg candidate_source=0;
  reg[23:0]rgb_mem[0:16383];reg[4:0]golden_rom[0:1023];reg bits_mem[0:1023];
  integer fg,roi_fg,best,second,winner,distances[0:4],expected_item;
  integer fd,nread,listed_item,listed_best,listed_second,listed_fg,listed_roi,truth;
  integer i,j,k,repeats,vectors=0,inject_fault=0,injected=0,ignored;
  integer clock_count=0,revoke_due=-1,revoke_kind=0,revoke_checks=0;
  integer source_revoke_checks=0,tag_revoke_checks=0;
  integer pair_seen=0,pair_overlap_seen=0;
  integer pair_id[0:1],pair_best[0:1],pair_second[0:1],pair_fg[0:1],pair_roi_fg[0:1];
  integer pair_item[0:1],pair_count[0:1];
  reg pair_source[0:1],pair_eof_sent[0:1],pair_in_second=0;
  string asset_root,stem,first_stem;

  card_recognizer #(.FRAME_WIDTH(320),.FRAME_HEIGHT(180),.ROI_X(96),.ROI_Y(26),.ROI_SIZE(128),
    .ENABLE_OUTPUT(1),.CONFIRM_FRAMES(3),.TEMPLATE_FILE("templates.mem")) dut(.*);
  task ck(input bit ok,input string label);begin checks=checks+1;if(!ok)begin errors=errors+1;$display("ERROR pipeline case=%0d %s",scenarios,label);end end endtask
  task tick;begin @(posedge clk);#1;end endtask
  // Deadlines are armed by known stimulus coordinates below, never DUT signals.
  // Check two complete clocks after the source/tag corruption was presented.
  always @(posedge clk) begin
    clock_count=clock_count+1;
    #2;
    if(revoke_due>=0 && clock_count==revoke_due)begin
      ck(!out_valid,"input fault withdraws old valid result within two clocks");
      ck(!out_healthy,"input fault withdraws old healthy result within two clocks");
      ck(stable_count==0,"input fault clears confirmation count within two clocks");
      revoke_checks=revoke_checks+1;
      if(revoke_kind==11)source_revoke_checks=source_revoke_checks+1;
      if(revoke_kind==12)tag_revoke_checks=tag_revoke_checks+1;
      revoke_due=-1;
    end
  end
  function bit fg_of(input reg[23:0]rgb);
    integer r,g,b,minimum,maximum;
    begin r=rgb[23:16];g=rgb[15:8];b=rgb[7:0];minimum=r;maximum=r;
      if(g<minimum)minimum=g;if(b<minimum)minimum=b;if(g>maximum)maximum=g;if(b>maximum)maximum=b;
      fg_of=(minimum<180)||(maximum-minimum>=40);
    end
  endfunction
  task golden;
    integer x,y,a,bit_index,c;
    bit value;
    begin
      fg=0;roi_fg=0;for(c=0;c<5;c=c+1)distances[c]=0;
      for(a=0;a<16384;a=a+1)if(fg_of(rgb_mem[a]))roi_fg=roi_fg+1;
      for(y=0;y<32;y=y+1)for(x=0;x<32;x=x+1)begin
        bit_index=y*32+x;value=fg_of(rgb_mem[(4*y+2)*128+4*x+2]);fg=fg+value;
        for(c=0;c<5;c=c+1)if(value!=golden_rom[bit_index][c])distances[c]=distances[c]+1;
      end
      winner=0;for(c=1;c<5;c=c+1)if(distances[c]<distances[winner])winner=c;
      best=distances[winner];second=2047;for(c=0;c<5;c=c+1)if(c!=winner && distances[c]<second)second=distances[c];
      expected_item=(roi_fg>0 && fg>=16 && fg<=850 && best<=40 && second>best && second-best>=24)?winner+10:0;
    end
  endtask
  task quiet(input integer cycles);
    integer c;begin
      @(negedge clk);in_valid=0;in_sof=0;in_eol=0;in_frame_end=0;
      for(c=0;c<cycles;c=c+1)begin tick();ck(!out_frame,"no duplicate or unsolicited output");end
    end
  endtask
  task clear_state;
    begin @(negedge clk);flush=1;in_valid=0;in_sof=0;in_eol=0;in_frame_end=0;
      tick();ck(!out_frame && !out_valid,"flush clears output");
      @(negedge clk);flush=0;count=0;candidate=0;candidate_source=0;quiet(4);
    end
  endtask
  task put_pixel(input integer x,input integer y,input integer fault,input bit source);
    integer ix;begin
      in_valid=1;in_x=x;in_y=y;in_sof=(x==0 && y==0);in_eol=(x==319);in_source_test=source;
      if(x>=96 && x<224 && y>=26 && y<154)begin ix=(y-26)*128+x-96;in_rgb=rgb_mem[ix];end
      else in_rgb=24'hffffff;
      if(fault==3 && x==5 && y==3)in_x=4;
      if(fault==4 && x==319 && y==3)in_eol=0;
      if(fault==5 && x==5 && y==3)in_eol=1;
      if(fault==6 && x==0 && y==0)in_sof=0;
      if(fault==7 && x==10 && y==5)in_sof=1;
      if(fault==8 && x==319 && y==179)in_frame_end=1;
      if(fault==11 && y>=80)in_source_test=!source;
      if(fault==12 && x==5 && y==3)in_frame_id=in_frame_id+1;
      if((fault==11 && x==0 && y==80)||(fault==12 && x==5 && y==3))begin
        ck(out_valid && out_healthy && stable_count>=3,"withdrawal test begins with a live confirmed result");
        ck(revoke_due<0,"no overlapping independent withdrawal deadline");
        revoke_kind=fault;revoke_due=clock_count+3;
      end
      tick();ck(!out_frame,"no result before explicit frame completion");@(negedge clk);
    end
  endtask
  task pair_tick;
    integer q;bit ev;
    begin
      tick();
      if(out_frame)begin
        ck(pair_seen<2,"shortest-gap pair emits exactly two records");
        if(pair_seen<2)begin
          q=pair_seen;ev=pair_item[q]!=0 && pair_count[q]>=3;
          ck(pair_eof_sent[q],"pair result follows its own explicit EOF");
          ck(out_frame_id===pair_id[q] && out_source_test===pair_source[q],"shortest-gap result retains frame ID and source");
          ck(out_healthy && out_present===(pair_roi_fg[q]!=0),"shortest-gap frame health and presence");
          ck(out_valid===ev && out_item===(ev?pair_item[q]:0),"shortest-gap classification belongs to the completed frame");
          ck(stable_count===pair_count[q],"shortest-gap confirmation count");
          ck(best_distance===pair_best[q] && second_distance===pair_second[q],"shortest-gap distance metadata association");
          ck(sample_fg_count===pair_fg[q] && roi_fg_count===pair_roi_fg[q],"shortest-gap foreground metadata association");
          if(q==0 && pair_in_second)pair_overlap_seen=pair_overlap_seen+1;
        end
        pair_seen=pair_seen+1;
      end
    end
  endtask
  task pair_pixel(input integer x,input integer y,input bit source);
    integer ix;
    begin
      in_valid=1;in_sof=(x==0 && y==0);in_eol=(x==319);in_frame_end=0;
      in_x=x;in_y=y;in_source_test=source;
      if(x>=96 && x<224 && y>=26 && y<154)begin
        ix=(y-26)*128+x-96;in_rgb=rgb_mem[ix];
      end else in_rgb=24'hffffff;
      pair_tick();@(negedge clk);
    end
  endtask
  task minimum_gap_pair;
    integer x,y,a,wait_cycles;
    begin
      scenarios=scenarios+1;$display("CASE pipeline %0d shortest-supported-EOF-gap",scenarios);
      ck(count==2 && candidate==expected_item && expected_item!=0,"minimum-gap pair starts after two confirmed candidate frames");
      pair_seen=0;pair_overlap_seen=0;pair_in_second=0;
      pair_eof_sent[0]=0;pair_eof_sent[1]=0;
      pair_id[0]=in_frame_id+1;pair_source[0]=0;
      pair_best[0]=best;pair_second[0]=second;pair_fg[0]=fg;pair_roi_fg[0]=roi_fg;
      pair_item[0]=expected_item;pair_count[0]=3;
      @(negedge clk);in_frame_id=pair_id[0];
      for(y=0;y<180;y=y+1)for(x=0;x<320;x=x+1)pair_pixel(x,y,0);
      in_valid=0;in_sof=0;in_eol=0;in_frame_end=1;pair_eof_sent[0]=1;
      pair_tick();@(negedge clk);
      // Exactly one extra marker-free invalid clock; no quiet() helper here.
      in_frame_end=0;pair_tick();@(negedge clk);
      // A white second frame makes diagnostics and source differ from frame A.
      for(a=0;a<16384;a=a+1)rgb_mem[a]=24'hffffff;
      golden();pair_id[1]=pair_id[0]+1;pair_source[1]=1;
      pair_best[1]=best;pair_second[1]=second;pair_fg[1]=fg;pair_roi_fg[1]=roi_fg;
      pair_item[1]=0;pair_count[1]=0;
      in_frame_id=pair_id[1];pair_in_second=1;
      for(y=0;y<180;y=y+1)for(x=0;x<320;x=x+1)pair_pixel(x,y,1);
      in_valid=0;in_sof=0;in_eol=0;in_frame_end=1;pair_eof_sent[1]=1;
      pair_tick();@(negedge clk);in_frame_end=0;
      for(wait_cycles=0;wait_cycles<16;wait_cycles=wait_cycles+1)begin pair_tick();@(negedge clk);end
      ck(pair_seen==2,"both shortest-gap frames publish and neither is swallowed");
      ck(pair_overlap_seen==1,"previous result was checked during next-frame pixel input");
      count=0;candidate=0;candidate_source=0;pair_in_second=0;
      quiet(3);
    end
  endtask
  task send_frame(input integer fault,input integer gap_every,input bit source,input bit healthy);
    integer x,y,n,end_y,id_at_start,delay_count;bit found,ev,expected_present;
    begin
      scenarios=scenarios+1;$display("CASE pipeline %0d fixture=%s fault=%0d",scenarios,stem,fault);
      @(negedge clk);in_frame_id=in_frame_id+1;id_at_start=in_frame_id;in_source_test=source;
      end_y=(fault==9)?17:180;
      for(y=0;y<end_y;y=y+1)for(x=0;x<320;x=x+1)begin
        n=y*320+x;
        if(gap_every>0 && n%gap_every==13)begin
          in_valid=0;in_sof=0;in_eol=0;tick();ck(!out_frame,"valid bubble does not complete frame");@(negedge clk);
        end
        if(fault==10 && x==5 && y==3)begin
          in_valid=0;in_sof=0;in_eol=1;tick();ck(!out_frame,"invalid-cycle EOL does not commit");@(negedge clk);
        end
        if(!(fault==1 && x==5 && y==3))put_pixel(x,y,fault,source);
        if(fault==2 && x==5 && y==3)put_pixel(x,y,0,source);
      end
      in_valid=0;in_sof=0;in_eol=0;in_source_test=source;
      if(fault!=8)begin in_frame_end=1;tick();@(negedge clk);end
      in_frame_end=0;
      if(!healthy)begin count=0;candidate=0;candidate_source=0;end
      else if(expected_item==0)begin count=0;candidate=0;candidate_source=0;end
      else if(candidate!=expected_item || candidate_source!=source || count==0)begin count=1;candidate=expected_item;candidate_source=source;end
      else if(count<255)count=count+1;
      found=0;
      for(delay_count=0;delay_count<16 && !found;delay_count=delay_count+1)begin tick();if(out_frame)found=1;end
      ck(found,"bounded completion event after frame_end");
      if(found)begin
        if(inject_fault && !injected && healthy && count>=3)begin force dut.out_valid=1'b0;injected=1;#1;end
        expected_present=healthy?(roi_fg!=0):1'b1;
        ev=healthy && expected_item!=0 && count>=3;
        ck(out_healthy===healthy,"whole-raster health qualification");
        ck(out_present===expected_present,"all-ROI presence, including unsampled fine lines");
        ck(out_valid===ev,"stable classification matches independent RGB reference");
        ck(out_item===(ev?expected_item:0),"stable logical item");
        ck(stable_count===count,"stable count / bad-frame withdrawal");
        ck(out_frame_id===id_at_start && out_source_test===source,"frame-start metadata retained");
        if(healthy)begin
          ck(best_distance===best,"RGB minimum Hamming distance");ck(second_distance===second,"RGB runner-up distance");
          ck(sample_fg_count===fg,"centre-sample foreground count");ck(roi_fg_count===roi_fg,"full-ROI foreground count");
        end
        if(injected)release dut.out_valid;
      end
      quiet(5);
    end
  endtask
  task empty_frame_end;
    integer delay_count,empty_id;bit found;
    begin
      scenarios=scenarios+1;
      @(negedge clk);in_valid=0;in_sof=0;in_eol=0;in_frame_end=1;
      in_frame_id=in_frame_id+1;empty_id=in_frame_id;in_source_test=0;
      tick();@(negedge clk);in_frame_end=0;found=0;
      for(delay_count=0;delay_count<16 && !found;delay_count=delay_count+1)begin
        tick();if(out_frame)found=1;
      end
      ck(found,"empty EOF produces bounded bad-frame record");
      ck(!out_healthy && out_present && !out_valid && out_item==0 && stable_count==0,"empty EOF cannot preserve stable result or claim empty background");
      ck(out_frame_id==empty_id && !out_source_test,"empty EOF metadata retained");
      count=0;candidate=0;candidate_source=0;quiet(5);
    end
  endtask
  initial begin
    if(!$value$plusargs("ASSET_ROOT=%s",asset_root))asset_root=".";
    ignored=$value$plusargs("INJECT_FAULT=%d",inject_fault);
    $readmemh({asset_root,"/templates.mem"},golden_rom);
    fd=$fopen({asset_root,"/vectors.list"},"r");
    if(!fd)begin errors=errors+1;$display("ERROR missing vectors.list");$finish;end
    repeat(4)tick();@(negedge clk);rst_n=1;quiet(2);
    while(!$feof(fd))begin
      nread=$fscanf(fd,"%s %d %d %d %d %d %d\n",stem,listed_item,listed_best,listed_second,listed_fg,listed_roi,truth);
      if(nread==7)begin
        if(vectors==0)first_stem=stem;
        $readmemh({asset_root,"/vectors/",stem,".rgb.mem"},rgb_mem);
        $readmemh({asset_root,"/vectors/",stem,".bits.mem"},bits_mem);
        golden();
        ck(expected_item==listed_item && best==listed_best && second==listed_second && fg==listed_fg && roi_fg==listed_roi,"independent RGB model agrees with Python fixture metadata");
        for(j=0;j<32;j=j+1)for(i=0;i<32;i=i+1)ck(bits_mem[j*32+i]===fg_of(rgb_mem[(4*j+2)*128+4*i+2]),"RGB/mask fixture agreement");
        clear_state();
        for(repeats=0;repeats<3;repeats=repeats+1)send_frame(0,137,vectors%2,1);
        vectors=vectors+1;
      end else if(nread!=-1)begin errors=errors+1;$display("ERROR malformed vectors.list: fields=%0d",nread);$finish;end
    end
    $fclose(fd);ck(vectors>=5,"at least five real card fixtures exercised");
    stem=first_stem;$readmemh({asset_root,"/vectors/",stem,".rgb.mem"},rgb_mem);golden();
    clear_state();send_frame(0,0,0,1);send_frame(0,0,0,1);minimum_gap_pair();
    stem=first_stem;$readmemh({asset_root,"/vectors/",stem,".rgb.mem"},rgb_mem);golden();
    clear_state();send_frame(0,0,0,1);send_frame(0,0,0,1);send_frame(0,0,0,1);
    empty_frame_end();send_frame(0,0,0,1);
    for(k=1;k<=12;k=k+1)begin clear_state();send_frame(0,0,0,1);send_frame(0,0,0,1);send_frame(0,0,0,1);send_frame(k,97,0,0);send_frame(0,0,0,1);end
    clear_state();send_frame(0,0,0,1);send_frame(0,0,0,1);send_frame(0,0,0,1);send_frame(0,0,1,1);send_frame(0,0,1,1);send_frame(0,0,1,1);
    // A foreground line deliberately runs between all 32 centre sample columns.
    stem="unsampled-one-pixel-line";for(i=0;i<16384;i=i+1)rgb_mem[i]=24'hffffff;
    for(j=0;j<128;j=j+1)rgb_mem[j*128+1]=24'h000000;golden();ck(fg==0 && roi_fg==128,"fine-line fixture independent of sample grid");
    clear_state();send_frame(0,0,0,1);ck(out_present && !out_valid,"fine line is unknown present, never empty");
    // Threshold boundaries: dark below180, min180/chroma39 rejected, chroma40 accepted as foreground.
    stem="threshold-boundaries";for(i=0;i<16384;i=i+1)rgb_mem[i]=24'hb4b4b4;
    rgb_mem[2*128+2]=24'hb3b3b3;rgb_mem[2*128+6]=24'hdbb4b4;rgb_mem[2*128+10]=24'hdcb4b4;
    golden();ck(fg==2 && roi_fg==2,"RGB foreground threshold boundary fixture");clear_state();send_frame(0,0,0,1);
    // Partial frame plus flush must never produce an orphan frame.
    scenarios=scenarios+1;@(negedge clk);in_frame_id=in_frame_id+1;
    for(j=0;j<10;j=j+1)for(i=0;i<320;i=i+1)put_pixel(i,j,0,0);
    clear_state();send_frame(0,0,0,1);
    ck(revoke_due<0 && revoke_checks==2 && source_revoke_checks==1 && tag_revoke_checks==1,"both independent immediate-withdrawal checks executed");
    ck(!inject_fault || injected,"negative test corrupted actual top-level output");
    test_done=1;$display("RESULT tb_card_pipeline errors=%0d checks=%0d scenarios=%0d vectors=%0d injected=%0d revoke_checks=%0d pair_seen=%0d",errors,checks,scenarios,vectors,injected,revoke_checks,pair_seen);$finish;
  end
  initial begin #1000000000;errors=errors+1;$display("WATCHDOG tb_card_pipeline");$finish;end
endmodule
