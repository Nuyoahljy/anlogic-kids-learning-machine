`timescale 1ns/1ps
module tb_block_shape_guard;
  reg clk=0;always #5 clk=~clk;
  reg rst_n=0,flush=0,start=0,valid=0,fg=0,ending=0,good=1,present=1,source=0;
  reg [9:0] index=0;reg [31:0] id=0;
  wire done,healthy,out_source;wire [2:0] shapes;wire [31:0] out_id;
  wire [10:0] dc,ds,dt;
  integer errors=0,checks=0,scenarios=0,injected=0;
  reg test_done=0;
  reg mask[0:1023];integer f,rc,ncases,ci,i,k,expected_bits,ec,es,et,bitvalue;
  integer fault_mode;reg [31:0] original_id;reg original_source;
  pixel14_block_shape_guard dut(.clk(clk),.rst_n(rst_n),.flush(flush),.frame_start(start),
    .sample_valid(valid),.sample_index(index),.sample_foreground(fg),.frame_end(ending),
    .frame_good(good),.frame_present(present),.frame_id(id),.frame_source_test(source),
    .out_frame(done),.out_healthy(healthy),.shape_ok(shapes),.out_frame_id(out_id),.out_source_test(out_source),
    .distance_circle(dc),.distance_square(ds),.distance_triangle(dt));
  task check(input bit ok,input string why);
    begin checks++;if(!ok)begin errors++;if(errors<15)$display("ERROR case=%0d %s",scenarios,why);end end
  endtask
  task tick(input bit s,input bit v,input integer idx,input bit p,input bit e);
    begin @(negedge clk);start=s;valid=v;index=idx;fg=p;ending=e;#6;end
  endtask
  task finish_frame(input bit expect_health,input [2:0] expect_shape,input bit compare_dist);
    begin
      tick(0,0,0,0,1);check(!done,"end waits for synchronous ROM final accumulation");
      tick(0,0,0,0,0);
      check(done && healthy===expect_health && shapes===expect_shape,"one-cycle-after-end atomic shape result");
      check(out_id==original_id && out_source===original_source,"frame identity/source is from capture start");
      if(compare_dist)begin check(dc==ec,"circle Hamming all 1024 bits");check(ds==es,"square Hamming all 1024 bits");check(dt==et,"triangle Hamming all 1024 bits");end
      tick(0,0,0,0,0);check(!done,"done is exactly one cycle");
    end
  endtask
  task begin_frame;
    begin id=id+1;source=~source;original_id=id;original_source=source;good=1;present=1;tick(1,0,0,0,0);end
  endtask
  task send_mask(input integer count,input integer bad_mode);
    begin
      for(integer j=0;j<count;j++)begin
        if(bad_mode==2 && j==512)id=id+100;
        if(bad_mode==3 && j==512)source=~source;
        tick(0,1,(bad_mode==1 && j==512) ? 511 : j,mask[j%1024],0);
        if(j%67==0)tick(0,0,0,0,0);
      end
    end
  endtask
  initial begin
    repeat(5)@(negedge clk);rst_n=1;
    f=$fopen("cases.txt","r");check(f!=0,"open independent model cases");rc=$fscanf(f,"%d",ncases);check(rc==1 && ncases>200,"model case count");
    for(ci=0;ci<ncases;ci++)begin
      rc=$fscanf(f,"%d %d %d %d %d",k,expected_bits,ec,es,et);check(rc==5 && k==ci,"case header intact");
      for(i=0;i<1024;i++)begin rc=$fscanf(f,"%d",bitvalue);check(rc==1,"1024 explicit samples");mask[i]=bitvalue!=0;end
      scenarios++;begin_frame();send_mask(1024,0);finish_frame(1,expected_bits[2:0],1);
    end
    $fclose(f);
    // Square is a transparent protocol oracle (400 foreground, 624 padding).
    for(i=0;i<1024;i++)mask[i]=(i%32>=6 && i%32<26 && i/32>=6 && i/32<26);
    scenarios++;begin_frame();send_mask(1023,0);finish_frame(0,0,0);
    scenarios++;begin_frame();send_mask(1025,0);finish_frame(0,0,0);
    scenarios++;begin_frame();send_mask(1024,1);finish_frame(0,0,0);
    scenarios++;begin_frame();send_mask(1024,2);finish_frame(0,0,0);
    scenarios++;begin_frame();send_mask(1024,3);finish_frame(0,0,0);
    scenarios++;begin_frame();send_mask(1024,0);good=0;finish_frame(0,0,0);
    scenarios++;begin_frame();send_mask(1024,0);present=0;finish_frame(1,0,0);
    scenarios++;begin_frame();send_mask(1023,0);tick(0,1,1023,mask[1023],1);
    tick(0,0,0,0,0);check(done && !healthy && shapes==0,"last sample with END is malformed");tick(0,0,0,0,0);
    scenarios++;begin_frame();send_mask(90,0);begin_frame();send_mask(1024,0);finish_frame(0,0,0);
    scenarios++;begin_frame();send_mask(70,0);flush=1;tick(0,0,0,0,0);flush=0;
    check(!done && !healthy && shapes==0,"flush clears pending qualification");finish_frame(0,0,0);
    scenarios++;id=id+1;original_id=id;original_source=source;good=1;present=1;
    finish_frame(0,0,0);
    scenarios++;begin_frame();send_mask(1024,0);tick(0,0,0,0,1);
    // Minimum supported inter-frame spacing: the next SOF coincides with
    // publication of the previous completed record, preserving both tags.
    id=id+1;source=~source;tick(1,0,0,0,0);
    check(done && healthy && shapes==2 && out_id==original_id && out_source==original_source,"new SOF during prior DRAIN preserves prior result");
    original_id=id;original_source=source;send_mask(1024,0);finish_frame(1,2,0);
    scenarios++;begin_frame();send_mask(100,0);repeat(100)tick(0,0,0,0,0);
    check(!done,"stream stop does not publish a shape");flush=1;tick(0,0,0,0,0);flush=0;
    fault_mode=0;rc=$value$plusargs("INJECT_FAULT=%d",fault_mode);
    if(fault_mode)begin force dut.shape_ok=7;#1;injected=1;check(shapes==0,"actual output injection detected");release dut.shape_ok;end
    test_done=1;$display("GUARD_DONE scenarios=%0d checks=%0d errors=%0d",scenarios,checks,errors);$finish;
  end
  initial begin #20000000;errors++;$display("WATCHDOG");$finish;end
endmodule
