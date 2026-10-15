`timescale 1ns/1ps
// Isolated C-002 reproduction, not a board candidate. All four combinations
// use the NEW color module; none takes the legacy isp_top COLOR_CORRECTION=0 path.
module tb_pixel14_color_contract;
  reg clk=0;always #4.83 clk=~clk;
  reg rst_n=0,sof=0,valid=0,eol=0,frame_end=0;
  reg [95:0] rgb=0;
  reg [31:0] tag=0;
  wire [95:0] out_rgb[0:3];
  wire [3:0] ov,oe,os;
  wire [8:0] gr[0:3],gb[0:3];
  wire [20:0] neutrals[0:3];
  wire [19:0] reds[0:3],yellows[0:3],blues[0:3];
  reg [8:0] group_count=0;
  integer errors=0,checks=0,scenarios=0,injected=0,inject_fault=0,unused,fd;
  reg test_done=0;
  integer c,f,x,y,m;
  reg [23:0] target;
  reg [23:0] observed[0:3];
  genvar i;
  generate for(i=0;i<4;i=i+1)begin:modes
    pixel14_color_pipeline #(.IMG_WIDTH(256),.IMG_HEIGHT(4),.MIN_NEUTRAL(16),
      .WB_ENABLE(i%2),.TONE_ENABLE(i/2)) color (
      .I_clk(clk),.I_rst_n(rst_n),.I_tlast(eol),.I_tuser(sof),.I_tdata(rgb),.I_tvalid(valid),
      .I_tready(),.O_tlast(oe[i]),.O_tuser(os[i]),.O_tdata(out_rgb[i]),.O_tvalid(ov[i]),.O_tready(1'b1));
    block_frame_recognizer #(.FRAME_WIDTH(64),.FRAME_HEIGHT(4),.X_MIN(0),.X_MAX(63),.Y_MIN(0),.Y_MAX(3),.CONFIRM_FRAMES(1)) classify (
      .clk(clk),.rst_n(rst_n),.flush(1'b0),.in_valid(ov[i]),.in_sof(ov[i]&&group_count==0),
      .in_eol(oe[i]),.in_x({5'd0,group_count[5:0]}),.in_y({8'd0,group_count[7:6]}),.in_rgb(out_rgb[i][95:72]),
      .in_frame_end(frame_end),.in_frame_good(1'b1),.in_frame_present(1'b1),.in_frame_id(tag),.in_source_test(1'b0),
      .out_frame(),.out_healthy(),.out_present(),.out_valid(),.out_item(),.out_frame_id(),.out_source_test(),.stable_count(),.out_revoke());
    assign gr[i]=color.gain_r;assign gb[i]=color.gain_b;assign neutrals[i]=color.neutral_count;
    assign reds[i]=classify.area[0];assign yellows[i]=classify.area[1];assign blues[i]=classify.area[2];
  end endgenerate
  task ck(input bit ok,input string label);begin checks++;if(!ok)begin errors++;$display("FAIL contract %0d %s",tag,label);end end endtask
  always @(posedge clk)begin
    #1;
    if(!rst_n || sof)group_count=0;
    else if(ov[0])begin
      ck(ov==4'b1111 && oe=={4{oe[0]}},"four actual pipelines have aligned valid/EOL");
      if(group_count==64)for(integer k=0;k<4;k++)observed[k]=out_rgb[k][95:72];
      group_count=group_count+1;
    end
  end
  task reset_color;
    begin @(negedge clk);rst_n=0;sof=0;valid=0;eol=0;frame_end=0;repeat(5)@(negedge clk);rst_n=1;repeat(5)@(negedge clk);end
  endtask
  task send_frame;
    reg [23:0] p;
    begin
      @(negedge clk);tag++;sof=1;
      @(negedge clk);sof=0;
      for(y=0;y<4;y++)begin
        for(x=0;x<64;x++)begin
          // 75% low-saturation target plus25% clipped white paper.
          p=x<48 ? target:24'hfcfcfc;rgb={4{p}};valid=1;eol=x==63;@(negedge clk);
        end
        valid=0;eol=0;rgb=0;repeat(80)@(negedge clk);
      end
      repeat(8)@(negedge clk);frame_end=1;@(negedge clk);frame_end=0;repeat(10)@(negedge clk);
      ck(group_count==256,"all output groups observed");
      for(m=0;m<4;m++)begin
        ck(neutrals[m]==768,"colored pixels enter neutral statistics and bright white is excluded");
        $fdisplay(fd,"%0d,%0d,%0d,%0d,%06h,%0d,%0d,%0d,%0d,%0d,%0d",c,f,m,tag,observed[m],gr[m],gb[m],neutrals[m],reds[m],yellows[m],blues[m]);
      end
    end
  endtask
  initial begin
    unused=$value$plusargs("INJECT_FAULT=%d",inject_fault);
    fd=$fopen("color-contract.csv","w");$fdisplay(fd,"color,frame,mode,tag,rgb,gain_r,gain_b,neutral_count,red_hits,yellow_hits,blue_hits");
    for(c=0;c<3;c++)begin
      scenarios++;reset_color;
      target=c==0 ? 24'ha08080 : c==1 ? 24'h808060:24'h686880;
      for(f=1;f<=100;f++)begin
        send_frame;
        ck((c==0 ? reds[0]:c==1 ? yellows[0]:blues[0])==192,"raw RGB is accepted by the real color gates");
        if(f==1)begin
          ck((c==0 ? reds[2]:c==1 ? yellows[2]:blues[2])==0,"tone alone destroys this original color gate");
          if(c==0)ck(observed[2]==24'hb89d9d,"actual tone red counterexample160/128/128 ->184/157/157");
        end
      end
      ck((c==0 ? reds[1]:c==1 ? yellows[1]:blues[1])==0,"WB alone loses class after non-unit convergence");
      ck((c==0 ? gr[1]<256:gb[1]!=256),"non-unit WB gain exercised");
      ck((c==0 ? reds[3]:c==1 ? yellows[3]:blues[3])==0,"combined WB/tone also loses class");
    end
    if(inject_fault)begin
      force modes[0].color.O_tdata=96'd1;#1;injected=1;
      ck(out_rgb[0]==0,"blank actual output fault is detected");release modes[0].color.O_tdata;
    end
    $fclose(fd);test_done=1;$display("CONTRACT_REPRO_DONE checks=%0d errors=%0d",checks,errors);$finish;
  end
  initial begin #10000000;$display("WATCHDOG contract");$finish;end
endmodule
