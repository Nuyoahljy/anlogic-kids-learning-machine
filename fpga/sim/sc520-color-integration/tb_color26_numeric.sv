`timescale 1ns/1ps
module tb_color26_numeric;
 integer errors=0,checks=0,scenarios=0,injected=0,inject_fault=0,n,fd,i,code,requests=0;
 reg test_done=0;reg [23:0] rgb=0;wire [1:0] cid;wire [23:0] enhanced;
 reg [51:0] vector;reg clk=0,rst=1,cam=0,done=0;reg [3:0] keys=15;
 wire req,applied;wire [15:0] ae,ag;
 always #5 clk=~clk;
 pixel26_color_classify classify(.in_rgb(rgb),.color_id(cid));
 pixel26_saturation saturation(.in_rgb(rgb),.out_rgb(enhanced));
 pixel26_fixed_exposure exposure(.I_clk(clk),.I_rst(rst),.I_btn(keys),.I_ae_cfg_done(done),.I_cam_cfg_done(cam),.O_ae_req(req),.O_ae(ae),.O_ag(ag),.O_applied(applied));
 always @(posedge clk)begin #1;if(req)requests++;end
 task ck(input bit good,input string what);begin checks++;if(!good)begin errors++;if(errors<15)$display("FAIL %s rgb=%h cid=%d sat=%h",what,rgb,cid,enhanced);end end endtask
 string root_path;
 initial begin
  code=$value$plusargs("INJECT_FAULT=%d",inject_fault);
  if(!$value$plusargs("ASSET_ROOT=%s",root_path))$fatal(1,"asset root missing");
  scenarios++;fd=$fopen({root_path,"/numeric.mem"},"r");if(!fd)$fatal(1,"vectors missing");n=0;
  while(!$feof(fd))begin
   code=$fscanf(fd,"%h\n",vector);
   if(code==1)begin
    rgb=vector[49:26];#2;
    if(inject_fault && n==17)begin force saturation.out_rgb=24'h010203;injected=1;#0.1;end
    ck(cid===vector[25:24],"field/rational classification oracle");ck(enhanced===vector[23:0],"wide signed saturation oracle");
    if(inject_fault && n==17)release saturation.out_rgb;n++;
   end
  end
  $fclose(fd);ck(n==163335,"all expected field/random/boundary vectors consumed");
  scenarios++;repeat(3)@(negedge clk);rst=0;repeat(10)@(negedge clk);ck(!req&&!applied&&requests==0,"no config before initialization");
  cam=1;repeat(5)@(negedge clk);ck(requests==0,"wait for initial AE ready");done=1;
  repeat(5)@(negedge clk);ck(requests==1&&!applied&&ae==1800&&ag==144,"one grouped write and no premature applied");
  done=0;repeat(5)@(negedge clk);ck(!applied,"AE write incomplete remains unqualified");done=1;repeat(5)@(negedge clk);ck(applied,"AE busy-to-done qualifies fixed config");
  for(i=0;i<16;i++)begin keys=i;repeat(5)@(negedge clk);ck(ae==1800&&ag==144&&requests==1&&applied,"all keys cannot change fixed calibration");end
  rst=1;repeat(3)@(negedge clk);ck(!applied,"reset revokes calibration");rst=0;repeat(5)@(negedge clk);ck(requests==2&&!applied,"reset starts another actual grouped write");
  test_done=1;$display("DONE numeric vectors=%d checks=%d errors=%d",n,checks,errors);$finish;
 end
 initial begin #10000000;$fatal(1,"numeric watchdog");end
endmodule
