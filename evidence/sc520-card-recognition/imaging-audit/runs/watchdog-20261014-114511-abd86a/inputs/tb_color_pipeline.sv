`timescale 1ns/1ps
module tb_color_pipeline #(parameter FULL=0);
  localparam W=FULL ? 1280 : 256,H=FULL ? 720 : 4,G=W/4,N=G*H;
  reg clk=0; always #5 clk=~clk;
  reg rst_n=0,sof=0,valid=0,eol=0;
  reg [95:0] rgb=0;
  wire [95:0] legacy_rgb,wb_rgb,tone_rgb,bypass_rgb,full_rgb;
  wire lv,wv,tv,bv,fv,le,we,te,be,fe,ls,ws,ts,bs,fs;
  wire ready;
  integer errors=0,checks=0,scenarios=0,injected=0;
  reg test_done=0;
  integer nlegacy,ncandidate,ntone,nbypass,nfull;
  integer x,y,l,i,fd,case_id=0,cycles=0,first_input=-1,first_output=-1;
  integer r,g,b,mn,mx;
  integer old_r,old_b;
  reg [95:0] expected[0:N-1];
  reg [95:0] first_legacy,last_legacy;
  reg [23:0] legacy_repeat_a,legacy_repeat_b;
  reg [8:0] frozen_r,frozen_b;
  reg frozen_set=0;
  reg complete_previous=0,pending_previous=0;
  integer complete_cycle=-1,pending_cycle=-1,end_input_cycle=-1;
  awb #(.IMG_WIDTH(W),.IMG_HEIGHT(H)) legacy(
    .I_clk(clk),.I_rst_n(rst_n),.I_tlast(eol),.I_tuser(sof),.I_tdata(rgb),.I_tvalid(valid),
    .I_tready(),.O_tlast(le),.O_tuser(ls),.O_tdata(legacy_rgb),.O_tvalid(lv),.O_tready(1'b1));
  pixel14_color_pipeline #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.MIN_NEUTRAL(16),.TONE_ENABLE(0)) wb(
    .I_clk(clk),.I_rst_n(rst_n),.I_tlast(eol),.I_tuser(sof),.I_tdata(rgb),.I_tvalid(valid),
    .I_tready(),.O_tlast(we),.O_tuser(ws),.O_tdata(wb_rgb),.O_tvalid(wv),.O_tready(1'b1));
  pixel14_color_pipeline #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.MIN_NEUTRAL(16),.WB_ENABLE(0)) tone(
    .I_clk(clk),.I_rst_n(rst_n),.I_tlast(eol),.I_tuser(sof),.I_tdata(rgb),.I_tvalid(valid),
    .I_tready(),.O_tlast(te),.O_tuser(ts),.O_tdata(tone_rgb),.O_tvalid(tv),.O_tready(1'b1));
  pixel14_color_pipeline #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.MIN_NEUTRAL(16),.WB_ENABLE(0),.TONE_ENABLE(0)) bypass(
    .I_clk(clk),.I_rst_n(rst_n),.I_tlast(eol),.I_tuser(sof),.I_tdata(rgb),.I_tvalid(valid),
    .I_tready(ready),.O_tlast(be),.O_tuser(bs),.O_tdata(bypass_rgb),.O_tvalid(bv),.O_tready(1'b1));
  pixel14_color_pipeline #(.IMG_WIDTH(W),.IMG_HEIGHT(H),.MIN_NEUTRAL(16)) full(
    .I_clk(clk),.I_rst_n(rst_n),.I_tlast(eol),.I_tuser(sof),.I_tdata(rgb),.I_tvalid(valid),
    .I_tready(),.O_tlast(fe),.O_tuser(fs),.O_tdata(full_rgb),.O_tvalid(fv),.O_tready(1'b1));

  task check(input bit ok,input string what);
    begin checks++; if(!ok)begin errors++; if(errors<20)$display("ERROR case=%0d %s",case_id,what);end end
  endtask
  function [7:0] curve(input [7:0] v);
    integer knots[0:16]; integer k;
    begin
      knots[0]=0;knots[1]=37;knots[2]=60;knots[3]=79;knots[4]=97;knots[5]=113;
      knots[6]=129;knots[7]=143;knots[8]=157;knots[9]=171;knots[10]=184;
      knots[11]=197;knots[12]=209;knots[13]=221;knots[14]=233;knots[15]=244;knots[16]=255;
      k=v/16;curve=v==255 ? 255 : knots[k]+((knots[k+1]-knots[k])*(v%16)+8)/16;
    end
  endfunction
  function [23:0] corrected(input [23:0] v,input integer gr,input integer gb,input bit t);
    integer ar,ag,ab;
    begin
      ar=(v[23:16]*gr)/256;ag=v[15:8];ab=(v[7:0]*gb)/256;
      if(ar>255)ar=255;if(ab>255)ab=255;
      corrected=t ? {curve(ar[7:0]),curve(ag[7:0]),curve(ab[7:0])} : {ar[7:0],ag[7:0],ab[7:0]};
    end
  endfunction
  always @(posedge clk)begin
    cycles++;
    #1;
    if(rst_n) begin
      if(wb.complete && !complete_previous)complete_cycle=cycles;
      if(wb.pending && !pending_previous)pending_cycle=cycles;
      complete_previous=wb.complete;pending_previous=wb.pending;
      check(ls===sof && ws===sof && ts===sof && bs===sof && fs===sof,"early SOF remains ahead of all data");
      if(bv)begin
        if(first_output<0)first_output=cycles;
        check(nbypass<N,"no extra bypass group");
        if(nbypass<N)check(bypass_rgb===expected[nbypass],"exact byte/lane bypass");
        check(be===((nbypass%G)==G-1),"EOL accompanies final bypass group");
        nbypass++;
      end
      if(tv)begin
        if(ntone<N)for(integer j=0;j<4;j++)check(tone_rgb[j*24+:24]===corrected(expected[ntone][j*24+:24],256,256,1),"tone all-lane reference");
        check(te===((ntone%G)==G-1),"tone EOL alignment");ntone++;
      end
      if(wv)begin
        if(!frozen_set)begin frozen_r=wb.gain_r;frozen_b=wb.gain_b;frozen_set=1;end
        check(wb.gain_r==frozen_r && wb.gain_b==frozen_b,"whole frame gain stability");
        if(ncandidate<N)for(integer j=0;j<4;j++)check(wb_rgb[j*24+:24]===corrected(expected[ncandidate][j*24+:24],frozen_r,frozen_b,0),"WB all-lane reference");
        check(we===((ncandidate%G)==G-1),"WB EOL alignment");ncandidate++;
      end
      if(fv)begin
        if(nfull<N)for(integer j=0;j<4;j++)check(full_rgb[j*24+:24]===corrected(expected[nfull][j*24+:24],full.gain_r,full.gain_b,1),"full all-lane reference");
        check(fe===((nfull%G)==G-1),"full EOL alignment");nfull++;
      end
      if(lv)begin
        if(nlegacy==0)first_legacy=legacy_rgb;
        if(nlegacy==G-1)legacy_repeat_a=legacy_rgb[23:0];
        if(nlegacy==3*G-1)legacy_repeat_b=legacy_rgb[23:0];
        last_legacy=legacy_rgb;nlegacy++;
      end
      if(!bv)check(bypass_rgb===0 && !be,"blank outputs zero and no EOL");
    end else begin complete_previous=0;pending_previous=0;end
  end
  task tick(input bit s,input bit v,input bit e,input [95:0] d);
    begin @(negedge clk);sof=s;valid=v;eol=e;rgb=d; end
  endtask
  task reset_all;
    begin
      @(negedge clk);rst_n=0;sof=0;valid=0;eol=0;rgb=0;
      repeat(5)@(negedge clk);rst_n=1;
      nlegacy=0;ncandidate=0;ntone=0;nbypass=0;nfull=0;first_input=-1;first_output=-1;
      frozen_r=256;frozen_b=256;
      frozen_set=0;
      complete_cycle=-1;pending_cycle=-1;end_input_cycle=-1;
    end
  endtask
  task make_uniform(input [23:0] color);
    begin for(integer q=0;q<N;q++)expected[q]={4{color}};end
  endtask
  task send_frame(input bit simultaneous,input integer missing_eol);
    integer expected_neutral,expected_r,expected_g,expected_b;
    integer rr,gg,bb,low,high;
    begin
      scenarios++;case_id++;
      nlegacy=0;ncandidate=0;ntone=0;nbypass=0;nfull=0;first_input=-1;first_output=-1;
      frozen_set=0;
      complete_cycle=-1;pending_cycle=-1;end_input_cycle=-1;
      if(!simultaneous)begin tick(1,0,0,0);tick(0,0,0,0);repeat(8)tick(0,0,0,0);end
      for(integer yy=0;yy<H;yy++)begin
        for(integer xx=0;xx<G;xx++)begin
          tick(simultaneous && yy==0 && xx==0,1,xx==G-1 && yy!=missing_eol && missing_eol!=-2,expected[yy*G+xx]);
          if(first_input<0)first_input=cycles+1;
          if(yy==H-1 && xx==G-1 && missing_eol==-1)end_input_cycle=cycles+1;
        end
        tick(0,0,missing_eol==-2,0);
        if(yy==H-1 && missing_eol==-2)end_input_cycle=cycles+1;
        repeat(80)tick(0,0,0,0);
      end
      repeat(8)tick(0,0,0,0);
      check(nbypass==N && ntone==N && ncandidate==N && nfull==N,"exact complete output frame group counts");
      expected_neutral=0;expected_r=0;expected_g=0;expected_b=0;
      for(integer q=0;q<N;q++)for(integer j=0;j<4;j++)begin
        rr=expected[q][j*24+16+:8];gg=expected[q][j*24+8+:8];bb=expected[q][j*24+:8];
        low=rr<gg ? rr : gg;if(bb<low)low=bb;
        high=rr>gg ? rr : gg;if(bb>high)high=bb;
        if(low>=64 && high<=247 && high-low<=high/4)begin
          expected_neutral++;expected_r+=rr;expected_g+=gg;expected_b+=bb;
        end
      end
      check(wb.neutral_count==expected_neutral && wb.sum_r==expected_r && wb.sum_g==expected_g && wb.sum_b==expected_b,"all first/last lanes included in exact statistics after drain");
      if(missing_eol<0)begin
        check(complete_cycle-end_input_cycle==4,"statistics complete exactly four cycles after input EOL");
        if(expected_neutral>=16)check(pending_cycle-end_input_cycle==6,"WB pending exactly six cycles after final input EOL");
      end
      $fwrite(fd,"%0d,%0d,%0d,%0d,%0d,%0d,%h,%h,%0d,%0d\n",case_id,N,nlegacy,nbypass,first_output-first_input,frozen_r,first_legacy[23:0],last_legacy[23:0],wb.neutral_count,wb.bad);
    end
  endtask
  initial begin
    fd=$fopen("color-observations.csv","w");
    $fwrite(fd,"case,input_groups,legacy_groups,candidate_groups,candidate_input_to_output_cycles,gain_r,legacy_first_rgb,legacy_last_rgb,neutral_samples,malformed\n");
    if(FULL)begin
      reset_all();make_uniform(24'h789680);send_frame(0,-1);
      check(wb.neutral_count==921600 && wb.sum_r==110592000 && wb.sum_g==138240000 && wb.sum_b==117964800,"720p full-range count and accumulator precision");
      tick(1,0,0,0);repeat(5)tick(0,0,0,0);#6;
      check(wb.gain_r==257 && wb.gain_b==257,"720p completed frame atomically commits at following SOF");
      $fclose(fd);test_done=1;$display("COLOR_DONE scenarios=%0d checks=%0d errors=%0d",scenarios,checks,errors);$finish;
    end
    reset_all();make_uniform(24'hdc281e);send_frame(0,-1);
    check(wb.gain_r==256 && wb.gain_b==256 && wb.neutral_count==0,"red-only frame cannot whiten itself");
    check(last_legacy[23:16]<=45 && last_legacy[15:8]==40 && last_legacy[7:0]<=45,"legacy red frame reproduces gray/dark output");
    send_frame(1,-1);check(wb.gain_r==256 && wb.gain_b==256,"no-reference frame freezes gain at next SOF");
    reset_all();make_uniform(24'h1e28dc);send_frame(0,-1);
    check(last_legacy[7:0]<=45 && last_legacy[15:8]==40,"legacy blue frame reproduces gray/dark output");
    reset_all();make_uniform(24'hdcc828);send_frame(0,-1);
    check(last_legacy[7:0]>=190,"legacy yellow boosts blue and loses chroma");
    reset_all();make_uniform(24'hdc281e);
    for(i=G;i<2*G;i++)expected[i]={4{24'ha0a0a0}};
    for(i=3*G;i<4*G;i++)expected[i]={4{24'ha0a0a0}};
    send_frame(0,-1);
    check(legacy_repeat_a[23:16]!=legacy_repeat_b[23:16],"legacy same red patch depends on preceding rows");
    $fwrite(fd,"prefix_repeat_rgb,%h,%h\n",legacy_repeat_a,legacy_repeat_b);
    reset_all();
    for(i=0;i<N;i++)for(l=0;l<4;l++)expected[i][l*24+:24]={8'(i*4+l),8'(i*4+l+83),8'(i*4+l+167)};
    send_frame(1,-1);
    check(curve(0)==0 && curve(255)==255,"tone black/white endpoints");
    for(i=1;i<256;i++)check(curve(i)>=curve(i-1),"tone monotonic across all byte values");
    check(curve(160)==184 && curve(128)==157,"tone moves gray160 above foreground threshold180 but gray128 remains below");
    reset_all();make_uniform(24'h789680);send_frame(0,-1);
    send_frame(1,-1);check(wb.gain_r==257 && wb.gain_b==257,"trusted neutral full frame adjusts before data even with SOF and first group together");
    make_uniform(24'hdc281e);send_frame(0,-1);old_r=wb.gain_r;old_b=wb.gain_b;
    send_frame(0,-1);check(wb.gain_r==old_r && wb.gain_b==old_b,"color-only frame holds prior calibration");
    make_uniform(24'h789680);send_frame(0,1);old_r=wb.gain_r;old_b=wb.gain_b;
    send_frame(0,-1);check(wb.gain_r==old_r && wb.gain_b==old_b,"malformed missing EOL cannot update calibration");
    reset_all();make_uniform(24'h789680);send_frame(0,-2);
    check(!wb.bad && wb.complete,"EOL on first blank after full line is accepted");
    tick(0,0,1,0);tick(0,0,0,0);old_r=wb.gain_r;old_b=wb.gain_b;
    send_frame(0,-1);check(wb.gain_r==old_r && wb.gain_b==old_b,"extra EOL after complete frame invalidates pending calibration");
    reset_all();for(i=0;i<N;i++)expected[i]={24'hdc281e,24'hc0c0c0,24'h1e28dc,24'h789680};
    send_frame(0,-1);check(wb.neutral_count==512,"all four lanes participate in neutral selection");
    old_r=wb.gain_r;old_b=wb.gain_b;repeat(200)tick(0,0,0,0);
    check(wb.gain_r==old_r && wb.gain_b==old_b,"complete frame with no following SOF holds applied gains");
    reset_all();make_uniform(24'hffffff);send_frame(0,-1);send_frame(0,-1);
    check(wb.neutral_count==0 && wb.gain_r==256 && wb.gain_b==256,"clipped white excluded from WB reference");
    reset_all();make_uniform(24'h202020);send_frame(0,-1);
    check(wb.neutral_count==0,"dark neutral excluded from WB reference");
    reset_all();make_uniform(24'hc0c0c0);
    force wb.gain_r=384;force wb.gain_b=384;send_frame(0,-1);release wb.gain_r;release wb.gain_b;
    check(frozen_r==384,"saturation corner exercised at explicit maximum injected gains");
    // New SOF while a delayed old line is still draining must discard the
    // incoming frame; provenance will observe the missing complete raster.
    reset_all();make_uniform(24'h789680);tick(1,0,0,0);tick(0,0,0,0);
    for(i=0;i<G;i++)tick(0,1,i==G-1,expected[i]);
    tick(1,0,0,0);tick(0,0,0,0);repeat(80)tick(0,0,0,0);
    check(wb.drop_frame && wb.bad && !wb.pending,"early SOF rejects old tail and freezes calibration");
    old_r=wb.gain_r;old_b=wb.gain_b;repeat(200)tick(0,0,0,0);
    check(wb.gain_r==old_r && wb.gain_b==old_b && !wv,"stopped/incomplete stream never authorizes an update");
    if($value$plusargs("INJECT_FAULT=%d",injected) && injected!=0)begin force bypass.O_tdata=96'h1;#1;check(bypass_rgb==0,"negative output fault");release bypass.O_tdata;end
    $fclose(fd);test_done=1;$display("COLOR_DONE scenarios=%0d checks=%0d errors=%0d",scenarios,checks,errors);$finish;
  end
  initial begin #50000000;errors++;$display("WATCHDOG");$finish;end
endmodule
