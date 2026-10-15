`timescale 1ns/1ps
module tb_pixel14_color_taps;
  localparam W=256,H=16,G=64,N=G*H;
  reg clk=0;always #5 clk=~clk;
  reg rst_n=0,sof=0,v=0,eol=0;
  reg [95:0] rgb=0;
  reg [31:0] tag=0;
  wire [95:0] out_rgb,pre,post,old_rgb;
  wire valid,last,user,old_valid,old_last,old_user;
  wire [8:0] gr,gb;
  wire [31:0] pixel_id,stats_id;
  wire stats_event,stats_good;wire [20:0] neutral;
  reg done_frame=0,analysis_event=0;
  wire packet_event;wire [799:0] packet;
  pixel14_color_observer #(.FRAME_WIDTH(W),.FRAME_HEIGHT(H),.CLASS_X(0),.CLASS_Y(0),.CLASS_W(W),.CLASS_H(H),
    .CENTER_X(124),.CENTER_Y(4),.PAPER_X(16),.PAPER_Y(4)) observer (
    .clk(clk),.rst_n(rst_n),.flush(1'b0),.frame_start(sof),.frame_id(tag),.valid(valid),.eol(last),
    .pre_wb(pre),.post_wb(post),.post_tone(out_rgb),.pixel_id(pixel_id),.gain_r(gr),.gain_b(gb),
    .stats_event(stats_event),.stats_good(stats_good),.stats_id(stats_id),.neutral_count(neutral),
    .frame_done(done_frame),.frame_good(1'b1),.done_id(tag),.analysis_event(analysis_event),.analysis_good(1'b1),
    .analysis_id(tag),.analysis_data(149'd0),.out_event(packet_event),.out_packet(packet));
  pixel14_color_pipeline #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.MIN_NEUTRAL(16),.DIAGNOSTICS(1)) dut(
    .I_clk(clk),.I_rst_n(rst_n),.I_tlast(eol),.I_tuser(sof),.I_tdata(rgb),.I_tvalid(v),.I_tready(),
    .O_tlast(last),.O_tuser(user),.O_tdata(out_rgb),.O_tvalid(valid),.O_tready(1'b1),.I_diag_frame_id(tag),
    .O_diag_pre_wb(pre),.O_diag_post_wb(post),.O_diag_gain_r(gr),.O_diag_gain_b(gb),.O_diag_pixel_id(pixel_id),
    .O_diag_stats_id(stats_id),.O_diag_stats_done(stats_event),.O_diag_stats_good(stats_good),.O_diag_neutral_count(neutral));
  pixel14_color_pipeline #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.MIN_NEUTRAL(16),.DIAGNOSTICS(0)) baseline(
    .I_clk(clk),.I_rst_n(rst_n),.I_tlast(eol),.I_tuser(sof),.I_tdata(rgb),.I_tvalid(v),.I_tready(),
    .O_tlast(old_last),.O_tuser(old_user),.O_tdata(old_rgb),.O_tvalid(old_valid),.O_tready(1'b1));
  reg [95:0] expected[0:N-1];
  integer errors=0,checks=0,scenarios=0,injected=0,inject_fault=0,unused;
  reg test_done=0,checking=0;
  integer tx=0,rx=0,cycles=0,first_in,first_out,stats_count=0,expected_count=0,frame_tag=0,expected_gr=256,expected_gb=256;
  integer frame,x,y,l,kind,good_expected=1,last_stats_tag=-1,last_stats_good=-1,last_neutral=-1;
  function [7:0] tone(input [7:0] value);
    integer k[0:16],n;begin
      k[0]=0;k[1]=37;k[2]=60;k[3]=79;k[4]=97;k[5]=113;k[6]=129;k[7]=143;k[8]=157;k[9]=171;k[10]=184;k[11]=197;k[12]=209;k[13]=221;k[14]=233;k[15]=244;k[16]=255;
      n=value/16;tone=value==255?255:k[n]+((k[n+1]-k[n])*(value%16)+8)/16;
    end
  endfunction
  function [23:0] wb(input [23:0] value,input integer r_gain,input integer b_gain);
    integer r,b;begin r=value[23:16]*r_gain/256;b=value[7:0]*b_gain/256;wb={8'(r>255?255:r),value[15:8],8'(b>255?255:b)};end
  endfunction
  task ck(input bit ok,input string message);begin checks++;if(!ok)begin errors++;if(errors<12)$display("FAIL taps %s frame=%0d rx=%0d",message,frame_tag,rx);end end endtask
  function integer is_neutral(input [23:0] p);integer r,g,b,hi,lo;begin
    r=p[23:16];g=p[15:8];b=p[7:0];hi=r>g?r:g;if(b>hi)hi=b;lo=r<g?r:g;if(b<lo)lo=b;
    is_neutral=lo>=64 && hi<=247 && hi-lo<=hi/4;
  end endfunction
  function [23:0] window_mean(input integer left,input bit corrected);
    integer yy,xx,rr,gg,bb;reg [23:0] p;
    begin rr=0;gg=0;bb=0;
      for(yy=4;yy<12;yy++)for(xx=left;xx<left+8;xx++)begin
        p=expected[yy*G+xx/4][(3-xx%4)*24+:24];
        if(corrected)p=wb(p,expected_gr,expected_gb);
        rr+=p[23:16];gg+=p[15:8];bb+=p[7:0];
      end
      window_mean={8'(rr/64),8'(gg/64),8'(bb/64)};
    end
  endfunction
  always @(posedge clk)begin
    cycles++;#1;
    if(rst_n)begin
      ck({valid,last,user,out_rgb}==={old_valid,old_last,old_user,old_rgb},"diagnostic taps never alter pixel outputs");
      if(checking)begin
        if(v)begin
          if(tx==0)first_in=cycles;expected[tx]=rgb;tx++;
          for(integer i=0;i<4;i++)expected_count+=is_neutral(rgb[i*24+:24]);
        end
        if(valid)begin
          if(rx==0)first_out=cycles;
          if(inject_fault && !injected && rx==12)begin force dut.O_diag_pre_wb=96'd1;injected=1;#0.01;end
          ck(rx<tx && pre===expected[rx],"preWB retains exact four input pixels");
          if(inject_fault && injected)release dut.O_diag_pre_wb;
          ck(gr==expected_gr && gb==expected_gb && pixel_id==frame_tag,"applied non-unit gains and pixel tag aligned");
          for(integer i=0;i<4;i++)begin
            ck(post[i*24+:24]===wb(expected[rx][i*24+:24],expected_gr,expected_gb),"postWB exact gain and saturation");
            for(integer c=0;c<3;c++)ck(out_rgb[i*24+c*8+:8]===tone(post[i*24+c*8+:8]),"tone belongs to same postWB pixel");
          end
          ck(last==(rx%G==G-1),"last group marker");rx++;
        end
      end
      if(stats_event)begin stats_count++;last_stats_tag=stats_id;last_stats_good=stats_good;last_neutral=neutral;end
    end
  end
  task blank;begin @(negedge clk);sof=0;v=0;eol=0;rgb=0;end endtask
  task reset_all;begin @(negedge clk);rst_n=0;checking=0;sof=0;v=0;eol=0;repeat(4)@(negedge clk);rst_n=1;repeat(5)@(negedge clk);end endtask
  task send_frame(input integer id,input integer mode,input bit bad_id);
    integer old_stats;reg [23:0] p;
    begin
      scenarios++;tx=0;rx=0;expected_count=0;frame_tag=id;tag=id;old_stats=stats_count;checking=1;
      @(negedge clk);sof=1;blank;repeat(6)blank;
      for(y=0;y<H;y++)begin
        for(x=0;x<G;x++)begin
          @(negedge clk);v=1;eol=x==G-1;
          for(l=0;l<4;l++)begin
            p=mode==0 ? 24'h789680 : mode==1 ? {8'(x*4+l),8'(y*40+l*13),8'(255-x*4-l)}:24'hfcfcfc;
            rgb[l*24+:24]=p;
          end
          if(bad_id && y==1)tag=id+1;else tag=id;
        end
        blank;repeat(80)blank;
      end
      repeat(12)blank;checking=0;
      ck(tx==N && rx==N && first_out-first_in==54,"complete frame and54-cycle video latency");
      ck(stats_count==old_stats+1 && last_stats_tag==id && last_stats_good==!bad_id && last_neutral==expected_count,"one final tagged neutral count, bad metadata never marked good");
      if(bad_id)ck(!last_stats_good,"midframe identity change rejected even after tag restoration");
      @(negedge clk);done_frame=1;@(negedge clk);done_frame=0;repeat(4)@(negedge clk);
      analysis_event=1;@(posedge clk);#1;analysis_event=0;
      ck(packet_event && packet[31:0]==id && packet[780]==!bad_id,"observer accepts only the correctly tagged complete statistics");
      if(!bad_id)begin
        ck(packet[412:404]==expected_gr && packet[421:413]==expected_gb && packet[442:422]==expected_count,"non-unit gains and final neutral survive real tap-to-observer join");
        ck(packet[55:32]===expected[8*G+32][95:72] && packet[79:56]===wb(expected[8*G+32][95:72],expected_gr,expected_gb),"same-coordinate non-unit preWB/postWB sample");
        ck(packet[199:176]===window_mean(124,0) && packet[223:200]===window_mean(124,1) && packet[271:248]===window_mean(16,0),"window mean is RRGGBB, independently summed over64pixels");
      end
      repeat(4)@(negedge clk);
    end
  endtask
  initial begin
    unused=$value$plusargs("INJECT_FAULT=%d",inject_fault);reset_all;
    for(frame=0;frame<4;frame++)begin expected_gr=256+frame;expected_gb=256+frame;send_frame(100+frame,0,0);end
    expected_gr=260;expected_gb=260;send_frame(104,1,0); // all four byte lanes and saturation boundaries
    reset_all;expected_gr=256;expected_gb=256;send_frame(200,2,0);send_frame(201,2,1);
    reset_all;send_frame(300,0,0);
    test_done=1;$display("DONE taps scenarios=%0d checks=%0d errors=%0d",scenarios,checks,errors);$finish;
  end
  initial begin #1000000;$display("WATCHDOG taps");$finish;end
endmodule
