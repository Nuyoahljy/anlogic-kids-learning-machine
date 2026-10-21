`timescale 1ns/1ps
module tb_contour29_retime;
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
  pixel29_scene_preprocess reference(
    .clk(clk),.rst_n(rst_n),.flush(flush),.in_valid(in_valid),.in_sof(in_sof),.in_eol(in_eol),
    .in_x(in_x),.in_y(in_y),.in_rgb(in_rgb),.in_frame_end(in_frame_end),.in_frame_good(in_frame_good),
    .in_frame_id(in_frame_id),.in_source_test(in_source_test));
  reg [23:0] raster[0:57599];reg [3:0] expected_norm[0:1023];
  longint unsigned checks=0,cycles_seen=0,ram_writes=0,output_cycles=0;
  integer errors=0,scenarios=0,samples=0,replay_samples=0,max_cycles=0,known_misses=0;
  integer seed_checks=0,edge_checks=0,first_seed=0,last_seed=0,address_switches=0;
  reg test_done=0,fixture_active=0,checking=1;
  integer fd,fields,metadata,want_present,truth,contract_item,x,y,cycles,op,target;
  integer state_hits[0:53],abort_hits[0:2][0:53];
  reg [12:0] previous_rgb_address=0;
  reg [31:0] rng=32'h54a92b17;
  reg [23:0] probe_rgb=0;
  reg signed [8:0] probe_center=0,probe_low=0,probe_high=0;
  integer value_index,kind,axis,boundary_case,boundary_index;
  integer seed_axis_hits[0:1],edge_axis_hits[0:1];
  integer distinct_boundary_hits[0:1][0:5],edge_boundary_hits[0:1][0:5];
  string assets,case_file,prefix,suite;
  task ck(input bit condition,input string message);
    begin
      checks++;
      if(!condition)begin
        errors++;
        if(errors<=12)$display("FAIL suite=%s case=%0d cycle=%0d state=%0d addr=%0d rgb=%h distinct=%b/%b edge=%b/%b %s",
          suite,scenarios,cycles_seen,reference.state,reference.rgb_address,reference.rgb_q,
          reference.ct_distinct,dut.ct_distinct_q,reference.ct_edge,dut.ct_edge_q,message);
        if(errors>=12)begin test_done=1;$finish;end
      end
    end
  endtask
  // Before NBA: compare the transactions actually sampled by synchronous RAMs.
  always @(posedge clk)begin
    cycles_seen++;
    if(checking)begin
      ck(reference.memory_enable===dut.memory_enable,"memory enable");
      ck({reference.memory_enable && reference.take_sample && !reference.selected_bank,
          reference.memory_enable && reference.take_sample && reference.selected_bank,
          reference.memory_enable && reference.flag_we,reference.memory_enable && reference.mask_we,
          reference.memory_enable && reference.fifo_we}===
         {dut.memory_enable && dut.take_sample && !dut.selected_bank,
          dut.memory_enable && dut.take_sample && dut.selected_bank,
          dut.memory_enable && dut.flag_we,dut.memory_enable && dut.mask_we,
          dut.memory_enable && dut.fifo_we},"all effective RAM write enables");
      if(reference.memory_enable)begin
        if(reference.take_sample)begin
          ck({reference.selected_bank,reference.sample_address}==={dut.selected_bank,dut.sample_address},"RGB write bank/address; data is shared in_rgb");
          ram_writes++;
        end
        if(reference.flag_we)begin
          ck({reference.flag_write_address,reference.flag_write_data}==={dut.flag_write_address,dut.flag_write_data},"flag RAM write address/data");
          ram_writes++;
        end
        if(reference.mask_we)begin
          ck({reference.scan_address,reference.filtered_glyph,reference.filtered_scene}===
             {dut.scan_address,dut.filtered_glyph,dut.filtered_scene},"mask RAM write address/data");
          ram_writes++;
        end
        if(reference.fifo_we)begin
          ck({reference.fifo_tail[12:0],reference.fifo_write_data}==={dut.fifo_tail[12:0],dut.fifo_write_data},"FIFO write address/data");
          ram_writes++;
        end
        if(reference.state==36)begin
          ck(reference.ct_distinct===dut.ct_distinct_q,"registered distinct matches original consuming cycle");
          seed_checks++;if(reference.scan_address==0)first_seed++;if(reference.scan_address==7199)last_seed++;
          if(suite=="boundary")begin
            seed_axis_hits[axis]++;
            if(boundary_case==0)begin
              case(value_index)
                -5: distinct_boundary_hits[axis][0]++;
                -4: distinct_boundary_hits[axis][1]++;
                -3: distinct_boundary_hits[axis][2]++;
                 3: distinct_boundary_hits[axis][3]++;
                 4: distinct_boundary_hits[axis][4]++;
                 5: distinct_boundary_hits[axis][5]++;
              endcase
            end
          end
        end
        if(reference.state==44)begin
          ck(reference.ct_edge===dut.ct_edge_q,"registered edge matches original consuming cycle");
          edge_checks++;
          if(suite=="boundary")begin
            edge_axis_hits[axis]++;
            if(boundary_case==0)begin
              case(value_index)
                -9: edge_boundary_hits[axis][0]++;
                -8: edge_boundary_hits[axis][1]++;
                -7: edge_boundary_hits[axis][2]++;
                 7: edge_boundary_hits[axis][3]++;
                 8: edge_boundary_hits[axis][4]++;
                 9: edge_boundary_hits[axis][5]++;
              endcase
            end
          end
        end
      end
    end
    #1;
    if(checking)begin
      output_cycles++;
      ck({reference.rgb_q0,reference.rgb_q1,reference.flag_q,reference.mask_q,reference.fifo_q}===
         {dut.rgb_q0,dut.rgb_q1,dut.flag_q,dut.mask_q,dut.fifo_q},"all synchronous RAM read registers including matching X values");
      ck({reference.replay_valid,reference.replay_sof,reference.replay_eol,reference.replay_glyph,
          reference.replay_x,reference.replay_y,reference.replay_rgb,reference.replay_end,reference.replay_good,
          reference.replay_present,reference.replay_id,reference.replay_source,reference.card_start,
          reference.card_valid,reference.card_index,reference.card_fg,reference.card_end,reference.card_good,
          reference.card_present,reference.contour_fg,reference.contour_axis_fg,reference.full_axis_fg,
          reference.contour_qualified,reference.contour_aspect_good,reference.contour_boundary_repair,
          reference.contour_exterior_ok,reference.contour_color,reference.card_id,reference.card_source,
          reference.out_revoke,reference.dbg_scene_count,reference.dbg_glyph_count,reference.dbg_paper_count,
          reference.dbg_scene_event,reference.dbg_scene_flags}===
         {dut.replay_valid,dut.replay_sof,dut.replay_eol,dut.replay_glyph,dut.replay_x,dut.replay_y,
          dut.replay_rgb,dut.replay_end,dut.replay_good,dut.replay_present,dut.replay_id,dut.replay_source,
          dut.card_start,dut.card_valid,dut.card_index,dut.card_fg,dut.card_end,dut.card_good,dut.card_present,
          dut.contour_fg,dut.contour_axis_fg,dut.full_axis_fg,dut.contour_qualified,dut.contour_aspect_good,
          dut.contour_boundary_repair,dut.contour_exterior_ok,dut.contour_color,dut.card_id,dut.card_source,
          dut.out_revoke,dut.dbg_scene_count,dut.dbg_glyph_count,dut.dbg_paper_count,dut.dbg_scene_event,dut.dbg_scene_flags},
          "all external outputs after NBA, including invalid-cycle payloads");
      ck({reference.state,reference.ready0,reference.ready1,reference.capture_active,reference.capture_bank,
          reference.process_bank,reference.engine_fault,reference.fault_reported,reference.rgb_address,
          reference.flag_address,reference.mask_address,reference.fifo_address,reference.scan_address,
          reference.scan_x,reference.scan_y,reference.fifo_head,reference.fifo_tail,reference.neighbor,
          reference.capture_pixels,reference.capture_samples,reference.scene_count,reference.glyph_count,
          reference.paper_count,reference.ct_body_area,reference.ct_exterior,reference.ct_seed_count[0],
          reference.ct_seed_count[1],reference.ct_seed_count[2],reference.ct_left,reference.ct_right,
          reference.ct_top,reference.ct_bottom,reference.ct_neighbor_seed,reference.ct_neighbor_edge,
          reference.ct_neighbor_color[0],reference.ct_neighbor_color[1],reference.ct_neighbor_color[2],
          reference.ct_neighbor_color[3],reference.ct_center_rg,reference.ct_center_bg}===
         {dut.state,dut.ready0,dut.ready1,dut.capture_active,dut.capture_bank,dut.process_bank,
          dut.engine_fault,dut.fault_reported,dut.rgb_address,dut.flag_address,dut.mask_address,dut.fifo_address,
          dut.scan_address,dut.scan_x,dut.scan_y,dut.fifo_head,dut.fifo_tail,dut.neighbor,dut.capture_pixels,
          dut.capture_samples,dut.scene_count,dut.glyph_count,dut.paper_count,dut.ct_body_area,dut.ct_exterior,
          dut.ct_seed_count[0],dut.ct_seed_count[1],dut.ct_seed_count[2],dut.ct_left,dut.ct_right,dut.ct_top,
          dut.ct_bottom,dut.ct_neighbor_seed,dut.ct_neighbor_edge,dut.ct_neighbor_color[0],
          dut.ct_neighbor_color[1],dut.ct_neighbor_color[2],dut.ct_neighbor_color[3],dut.ct_center_rg,dut.ct_center_bg},
          "original state, bank ownership, addresses and result accumulators");
      if(rst_n && reference.state<=53)state_hits[reference.state]++;
      if(previous_rgb_address!=reference.rgb_address)address_switches++;
      previous_rgb_address=reference.rgb_address;
    end
    if(fixture_active && rst_n)begin
      if(replay_valid)begin ck(replay_id==in_frame_id && !replay_source,"replay identity");replay_samples++;end
      if(card_valid)begin
        ck(card_id==in_frame_id && !card_source,"normalized identity");
        ck(card_index==samples,"monotonic normalized index");
        ck({full_axis_fg,contour_axis_fg,contour_fg,card_fg}===expected_norm[card_index],"original independent four-mask expectation");
        samples++;
      end
      ck(!out_revoke,"healthy fixture does not revoke");
    end
  end
  task clear_inputs;
    begin in_valid=0;in_sof=0;in_eol=0;in_frame_end=0;in_frame_good=1;in_source_test=0;end
  endtask
  task reset_scene;
    begin
      @(negedge clk);clear_inputs;flush=0;#2;rst_n=0;#1;
      ck(dut.ct_distinct_q===0 && dut.ct_edge_q===0,"asynchronous predicate reset");
      repeat(3)@(negedge clk);rst_n=1;repeat(2)@(negedge clk);
    end
  endtask
  task send_frame;
    begin
      in_frame_id++;
      for(y=0;y<180;y++)for(x=0;x<320;x++)begin
        in_valid=1;in_sof=x==0 && y==0;in_eol=x==319;in_x=x;in_y=y;in_rgb=raster[y*320+x];
        @(negedge clk);
      end
      clear_inputs;in_frame_end=1;@(negedge clk);in_frame_end=0;
    end
  endtask
  task wait_complete;
    begin
      cycles=0;while(!card_end && cycles<1200000)begin @(negedge clk);cycles++;end
      ck(cycles<1200000,"unchanged single-frame completion budget");
      if(cycles>max_cycles)max_cycles=cycles;
      repeat(12)@(negedge clk);
    end
  endtask
  initial begin
    if(!$value$plusargs("ASSET_ROOT=%s",assets))$fatal(1,"ASSET_ROOT required");
    if(!$value$plusargs("SUITE=%s",suite))suite="fixtures";
    if(!$value$plusargs("CASE_FILE=%s",case_file))case_file="all-cases.txt";
    for(integer s=0;s<=53;s++)begin state_hits[s]=0;for(integer a=0;a<3;a++)abort_hits[a][s]=0;end
    for(integer a=0;a<2;a++)begin
      seed_axis_hits[a]=0;edge_axis_hits[a]=0;
      for(integer b=0;b<6;b++)begin distinct_boundary_hits[a][b]=0;edge_boundary_hits[a][b]=0;end
    end
    repeat(5)@(negedge clk);rst_n=1;
    if(suite=="fixtures")begin
      fd=$fopen({assets,"/",case_file},"r");if(!fd)$fatal(1,"case file missing");
      while(!$feof(fd))begin
        fields=$fscanf(fd,"%s %d %d %d %d\n",prefix,metadata,want_present,truth,contract_item);
        if(fields==5)begin
          scenarios++;$display("CASE %0d %s truth=%0d contract=%0d",scenarios,prefix,truth,contract_item);
          if(truth!=0 && contract_item==0)known_misses++;
          $readmemh({assets,"/",prefix,".rgb.mem"},raster);
          $readmemh({assets,"/",prefix,".norm.mem"},expected_norm);
          samples=0;replay_samples=0;fixture_active=1;send_frame;
          cycles=0;while(!card_end && cycles<1200000)begin @(negedge clk);cycles++;end
          ck(cycles<1200000,"unchanged fixture wait budget");
          if(cycles>max_cycles)max_cycles=cycles;
          ck(samples==1024 && replay_samples==7200,"complete replay and normalized streams");
          ck(card_good && card_present==want_present && card_id==in_frame_id,"scene health/presence");
          ck({contour_color,contour_exterior_ok,contour_boundary_repair,contour_aspect_good,contour_qualified}==metadata[5:0],"original metadata expectation");
          repeat(12)@(negedge clk);fixture_active=0;
        end
      end
      $fclose(fd);ck(seed_checks>0 && edge_checks>0 && first_seed==scenarios && last_seed==scenarios && address_switches>scenarios,"first/last samples and real address changes covered");
    end else if(suite=="stress")begin
      $readmemh({assets,"/c062.rgb.mem"},raster);
      for(op=0;op<3;op++)for(target=32;target<=53;target++)begin
        scenarios++;reset_scene;send_frame;
        cycles=0;while(reference.state!=target && cycles<1200000)begin @(negedge clk);cycles++;end
        ck(cycles<1200000,"target CT state reached");abort_hits[op][target]++;
        if(op==0)begin #2;rst_n=0;#1;ck(dut.ct_distinct_q===0 && dut.ct_edge_q===0,"CT-state async reset");@(negedge clk);rst_n=1;end
        if(op==1)flush=1;
        if(op==2)in_frame_end=1;
        @(negedge clk);clear_inputs;flush=0;
        ck(dut.state==0 && dut.ct_distinct_q===0 && dut.ct_edge_q===0,"CT-state abort clears both predicates");
        repeat(3)@(negedge clk);
      end
      // Deterministic random legal partial captures followed by protocol faults.
      for(op=0;op<24;op++)begin
        scenarios++;reset_scene;in_frame_id++;
        for(x=0;x<96;x++)begin
          rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
          in_valid=1;in_sof=x==0;in_eol=0;in_x=x;in_y=0;in_rgb=rng[23:0];@(negedge clk);
        end
        case(op%6)
          0: in_frame_id++;
          1: in_source_test=1;
          2: in_x=200;
          3: begin in_valid=0;in_eol=1;end
          4: begin in_valid=0;in_frame_end=1;in_frame_good=0;end
          5: flush=1;
        endcase
        @(negedge clk);clear_inputs;flush=0;repeat(3)@(negedge clk);
        ck(dut.state==0 && !dut.capture_active,"random partial-frame fault revokes capture");
      end
      reset_scene;send_frame;wait_complete;
      ck(card_good,"healthy frame recovers after all aborts");
      for(op=0;op<3;op++)for(target=32;target<=53;target++)
        ck(abort_hits[op][target]==1,"all CT states exercise reset/flush/bad-frame abort");
    end else if(suite=="boundary")begin
      // Diagnostic state/RGB forces are symmetric; this is separate from RGB fixture coverage.
      reset_scene;
      force reference.process_bank=0;force dut.process_bank=0;
      force reference.rgb_q0=probe_rgb;force dut.rgb_q0=probe_rgb;
      force reference.min_rg0=axis==0 ? probe_low:0;force dut.min_rg0=axis==0 ? probe_low:0;
      force reference.max_rg0=axis==0 ? probe_high:0;force dut.max_rg0=axis==0 ? probe_high:0;
      force reference.min_bg0=axis==1 ? probe_low:0;force dut.min_bg0=axis==1 ? probe_low:0;
      force reference.max_bg0=axis==1 ? probe_high:0;force dut.max_bg0=axis==1 ? probe_high:0;
      force reference.ct_center_rg=axis==0 ? probe_center:0;force dut.ct_center_rg=axis==0 ? probe_center:0;
      force reference.ct_center_bg=axis==1 ? probe_center:0;force dut.ct_center_bg=axis==1 ? probe_center:0;
      force reference.mask_q=2'b10;force dut.mask_q=2'b10;
      force reference.flag_q=2'b10;force dut.flag_q=2'b10;
      force reference.ct_label=1;force dut.ct_label=1;
      for(axis=0;axis<2;axis++)for(kind=0;kind<2;kind++)for(boundary_case=0;boundary_case<3;boundary_case++)
      for(value_index=-255;value_index<=255;value_index++)begin
        scenarios++;
        @(negedge clk);
        probe_low=kind==0 && boundary_case==1 ? -9'sd255:0;
        probe_high=kind==0 && boundary_case==2 ? 9'sd255:0;
        probe_center=kind==1 && boundary_case==1 ? -9'sd255:kind==1 && boundary_case==2 ? 9'sd255:0;
        probe_rgb=24'h000000;
        if(kind==0)begin force reference.state=33;force dut.state=33;end
        else begin force reference.state=41;force dut.state=41;end
        @(negedge clk);release reference.state;release dut.state;
        @(negedge clk);
        if(axis==0)probe_rgb=value_index>=0 ? {value_index[7:0],8'd0,8'd0}:{8'd0,8'(-value_index),8'(-value_index)};
        else probe_rgb=value_index>=0 ? {8'd0,8'd0,value_index[7:0]}:{8'(-value_index),8'(-value_index),8'd0};
        repeat(3)@(negedge clk);
        checking=0;force reference.state=0;force dut.state=0;@(negedge clk);
        release reference.state;release dut.state;checking=1;
      end
      release reference.process_bank;release dut.process_bank;release reference.rgb_q0;release dut.rgb_q0;
      release reference.min_rg0;release dut.min_rg0;release reference.max_rg0;release dut.max_rg0;
      release reference.min_bg0;release dut.min_bg0;release reference.max_bg0;release dut.max_bg0;
      release reference.ct_center_rg;release dut.ct_center_rg;release reference.ct_center_bg;release dut.ct_center_bg;
      release reference.mask_q;release dut.mask_q;release reference.flag_q;release dut.flag_q;
      release reference.ct_label;release dut.ct_label;
      for(axis=0;axis<2;axis++)begin
        ck(seed_axis_hits[axis]==1533 && edge_axis_hits[axis]==1533,"both signed axes actually consumed all -255..255 RGB differences under three extrema/center settings");
        for(boundary_index=0;boundary_index<6;boundary_index++)begin
          ck(distinct_boundary_hits[axis][boundary_index]==1,"strict +/-4 threshold endpoint and adjacent values consumed");
          ck(edge_boundary_hits[axis][boundary_index]==1,"inclusive +/-8 edge endpoint and adjacent values consumed");
        end
        $display("BOUNDARY axis=%0d seed=%0d edge=%0d distinct=%0d,%0d,%0d,%0d,%0d,%0d edgepoints=%0d,%0d,%0d,%0d,%0d,%0d",
          axis,seed_axis_hits[axis],edge_axis_hits[axis],
          distinct_boundary_hits[axis][0],distinct_boundary_hits[axis][1],distinct_boundary_hits[axis][2],
          distinct_boundary_hits[axis][3],distinct_boundary_hits[axis][4],distinct_boundary_hits[axis][5],
          edge_boundary_hits[axis][0],edge_boundary_hits[axis][1],edge_boundary_hits[axis][2],
          edge_boundary_hits[axis][3],edge_boundary_hits[axis][4],edge_boundary_hits[axis][5]);
      end
    end else $fatal(1,"unknown suite");
    test_done=1;
    $display("RESULT errors=%0d checks=%0d scenarios=%0d cycles=%0d ram_writes=%0d seed_checks=%0d edge_checks=%0d first_seed=%0d last_seed=%0d address_switches=%0d max_cycles=%0d known_misses=%0d",
      errors,checks,scenarios,cycles_seen,ram_writes,seed_checks,edge_checks,first_seed,last_seed,address_switches,max_cycles,known_misses);
    for(integer s=32;s<=53;s++)$display("COVER state=%0d visits=%0d reset=%0d flush=%0d badframe=%0d",s,state_hits[s],abort_hits[0][s],abort_hits[1][s],abort_hits[2][s]);
    $finish;
  end
endmodule

config retime_config;
  design work.tb_contour29_retime;
  default liblist work baseline candidate;
  instance tb_contour29_retime.reference use baseline.pixel29_scene_preprocess;
  instance tb_contour29_retime.dut use candidate.pixel29_scene_preprocess;
endconfig
