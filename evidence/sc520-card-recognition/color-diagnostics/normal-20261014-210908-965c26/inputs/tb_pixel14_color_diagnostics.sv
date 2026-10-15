`timescale 1ns/1ps
module color_diag_case #(
    parameter integer CASE_ID=0, W=16, H=8, MSB=1, OFFSET=0, FULL=0,
    parameter integer CX=FULL ? 636:1+OFFSET, CY=FULL ? 356:1,
    parameter integer CW=FULL ? 8:3, CH=FULL ? 8:3,
    parameter integer PX=FULL ? 192:10+OFFSET, PY=FULL ? 144:5,
    parameter integer PW=FULL ? 8:3, PH=FULL ? 8:3,
    parameter integer AX=FULL ? 160:1, AY=FULL ? 120:1,
    parameter integer AW=FULL ? 960:14, AH=FULL ? 480:6,
    parameter integer CB=$clog2(W*H+1), RB=$clog2((CW*CH>PW*PH ? CW*CH:PW*PH)+1), SB=RB+8
)(output reg done,output integer errors,checks,scenarios,injected);
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,flush=0,in_valid=0,in_sof=0,in_eol=0,in_frame_done=0,in_frame_good=1;
    reg [31:0] in_frame_id=0,in_done_id=0;
    reg [95:0] in_pre_wb=0,in_post_wb=0,in_post_tone=0;
    reg [8:0] in_gain_r=256,in_gain_b=256;
    reg [20:0] in_neutral_count=0;
    wire out_valid,out_trusted,out_reject;
    wire [7:0] out_reject_reason;
    wire [31:0] out_frame_id;
    wire [8:0] out_gain_r,out_gain_b;
    wire [20:0] out_neutral_count;
    wire [CB-1:0] out_class_pixels;
    wire [9*CB-1:0] out_color_hits;
    wire [2*RB-1:0] out_roi_pixels;
    wire [6*RB-1:0] out_roi_lowclip,out_roi_highclip;
    wire [18*SB-1:0] out_roi_rgb_sum;
    wire [143:0] out_sample_rgb;
    wire [1:0] out_sample_present;
    wire [47:0] out_sample_xy;
    pixel14_color_diagnostics #(.FRAME_WIDTH(W),.FRAME_HEIGHT(H),.CLASS_X(AX),.CLASS_Y(AY),.CLASS_W(AW),.CLASS_H(AH),
        .CENTER_X(CX),.CENTER_Y(CY),.CENTER_W(CW),.CENTER_H(CH),.PAPER_X(PX),.PAPER_Y(PY),.PAPER_W(PW),.PAPER_H(PH),.LANE0_MSB(MSB)) dut(.*);
    integer publications=0,rejections=0,inject_mode=0;
    integer ref_class,ref_hits[0:8],ref_roi[0:1],ref_low[0:5],ref_high[0:5],ref_sum[0:17];
    reg [143:0] ref_samples;

    task automatic check(input bit condition,input string what);
        begin checks=checks+1;if(!condition)begin errors=errors+1;$display("DIAG_ERROR case=%0d %s t=%0t",CASE_ID,what,$time);end end
    endtask
    // Independent palette: these are synthetic, already aligned stage triples.
    // They are not measurements and do not simulate the production WB/tone.
    function automatic [23:0] value(input integer st,input integer x,input integer y,input integer pattern);
        integer sel;
        begin
            sel=(x+3*y+pattern)%8;
            case(sel)
                0:case(st)0:value={8'd160,8'd128,8'd128};1:value={8'd128,8'd128,8'd128};2:value={8'd157,8'd157,8'd157};endcase
                1:case(st)0:value={8'd200,8'd30,8'd20};1:value={8'd160,8'd30,8'd20};2:value={8'd180,8'd50,8'd40};endcase
                2:case(st)0:value={8'd200,8'd180,8'd60};1:value={8'd160,8'd180,8'd60};2:value={8'd170,8'd190,8'd80};endcase
                3:case(st)0:value={8'd40,8'd60,8'd200};1:value={8'd50,8'd60,8'd150};2:value={8'd65,8'd80,8'd170};endcase
                4:case(st)0:value=24'hfcfcfc;1:value=24'hf7f7f7;2:value=24'hffffff;endcase
                5:case(st)0:value=24'h000000;1:value=24'h080808;2:value=24'h090909;endcase
                6:case(st)0:value={8'd80,8'd48,8'd48};1:value={8'd79,8'd47,8'd47};2:value={8'd112,8'd80,8'd80};endcase
                7:case(st)0:value={8'd176,8'd144,8'd96};1:value={8'd176,8'd144,8'd96};2:value={8'd180,8'd150,8'd110};endcase
            endcase
        end
    endfunction
    task automatic reference_pixel(input integer x,input integer y,input integer pattern);
        integer st,q,r,g,b,j;
        reg [23:0] v;
        bit a,t;
        begin
            a=x>=AX && x<AX+AW && y>=AY && y<AY+AH;
            if(a)ref_class++;
            for(st=0;st<3;st++)begin
                v=value(st,x,y,pattern);r=v[23:16];g=v[15:8];b=v[7:0];
                if(a)begin
                    if(r>=80 && r-g>=32 && r-b>=32)ref_hits[st*3]++;
                    if(r>=96 && g>=80 && b<=96 && r-g<=80 && g-r<=80 && r-b>=32 && g-b>=24)ref_hits[st*3+1]++;
                    if(b>=80 && b-r>=24 && b-g>=24)ref_hits[st*3+2]++;
                end
                for(q=0;q<2;q++)begin
                    t=q==0 ? (x>=CX && x<CX+CW && y>=CY && y<CY+CH):(x>=PX && x<PX+PW && y>=PY && y<PY+PH);
                    if(t)begin
                        if(st==0)ref_roi[q]++;
                        if(r<=8 || g<=8 || b<=8)ref_low[q*3+st]++;
                        if(r>=247 || g>=247 || b>=247)ref_high[q*3+st]++;
                        ref_sum[(q*3+st)*3]+=r;ref_sum[(q*3+st)*3+1]+=g;ref_sum[(q*3+st)*3+2]+=b;
                    end
                    if((q==0 && x==CX+CW/2 && y==CY+CH/2) || (q==1 && x==PX+PW/2 && y==PY+PH/2))
                        ref_samples[(q*3+st)*24+:24]=v;
                end
            end
        end
    endtask
    task automatic step(input bit valid_,input bit sof_,input bit eol_,input bit done_,input bit good_,input bit flush_,
                        input integer id_,input integer did_,input integer gr_,input integer gb_,input integer nc_,
                        input [287:0] data_);
        begin
            @(negedge clk);
            in_valid=valid_;in_sof=sof_;in_eol=eol_;in_frame_done=done_;in_frame_good=good_;flush=flush_;
            in_frame_id=id_;in_done_id=did_;in_gain_r=gr_;in_gain_b=gb_;in_neutral_count=nc_;
            {in_post_tone,in_post_wb,in_pre_wb}=data_;
            @(posedge clk);#1;
            if(out_valid)publications++;
            if(out_reject)rejections++;
            if(out_valid)check(out_trusted,"published result has trusted qualifier");
        end
    endtask
    task automatic blank;
        begin step(0,0,0,0,1,0,32'hdecafbad,0,511,511,0,288'hffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);end
    endtask
    task automatic compare_snapshot(input integer id_,input integer gr_,input integer gb_,input integer nc_);
        integer i;
        begin
            if(CASE_ID==0 && inject_mode && !injected)begin
                force dut.out_frame_id=32'habadd00d;injected=1;
            end
            check(out_frame_id==id_,"frame ID exact");
            if(CASE_ID==0 && inject_mode && injected)release dut.out_frame_id;
            check(out_gain_r==gr_ && out_gain_b==gb_,"gains use first valid, remain frame-associated");
            check(out_neutral_count==nc_,"neutral count uses tagged done snapshot");
            check(out_class_pixels==ref_class,"class region includes every pixel once");
            check(out_sample_present==3,"both fixed-coordinate samples present");
            check(out_sample_rgb===ref_samples,"three-stage samples have exact RGB and lane");
            check(out_sample_xy[11:0]==CX+CW/2 && out_sample_xy[23:12]==CY+CH/2 &&
                  out_sample_xy[35:24]==PX+PW/2 && out_sample_xy[47:36]==PY+PH/2,"sample coordinates are explicit");
            for(i=0;i<9;i++)check(out_color_hits[i*CB+:CB]==ref_hits[i],$sformatf("color count %0d expected %0d actual %0d",i,ref_hits[i],out_color_hits[i*CB+:CB]));
            for(i=0;i<2;i++)check(out_roi_pixels[i*RB+:RB]==ref_roi[i],"ROI denominator exact");
            for(i=0;i<6;i++)begin
                check(out_roi_lowclip[i*RB+:RB]==ref_low[i],"inclusive low clip count");
                check(out_roi_highclip[i*RB+:RB]==ref_high[i],"inclusive high clip count");
            end
            for(i=0;i<18;i++)check(out_roi_rgb_sum[i*SB+:SB]==ref_sum[i],"ROI RGB sum exact");
        end
    endtask
    // bad=0/1 good first-valid/blank-SOF; 2 external bad; 3 wrong done ID;
    // 4 early SOF; 5 missed EOL; 6 early EOL; 7 changed frame ID;
    // 8 changed gain; 9 done with final valid; 10 extra group;
    // 11 incomplete done; 12 mid-frame flush; 13 pending flush; 14 pending SOF.
    task automatic frame(input integer id_,input integer bad,input integer pattern);
        integer y,g,l,s,j,n,pubs,rej,gr,gb,nc,mid;
        reg [287:0] bus;
        bit fs,le,fd;
        begin
            scenarios++;pubs=publications;rej=rejections;gr=192+id_%100;gb=256+id_%100;nc=(W*H)/3+id_;
            ref_class=0;ref_samples=0;
            for(j=0;j<9;j++)ref_hits[j]=0;
            for(j=0;j<2;j++)ref_roi[j]=0;
            for(j=0;j<6;j++)begin ref_low[j]=0;ref_high[j]=0;end
            for(j=0;j<18;j++)ref_sum[j]=0;
            if(bad==1)begin
                // SOF gain differs deliberately; first valid determines applied gain.
                step(0,1,0,0,1,0,id_,id_,100,101,0,0);blank();
            end
            n=0;mid=(W/4)*H/2;
            for(y=0;y<H;y++)for(g=0;g<W/4;g++)begin
                bus=0;
                for(l=0;l<4;l++)begin
                    for(s=0;s<3;s++)bus[s*96+(MSB ? 3-l:l)*24+:24]=value(s,g*4+l,y,pattern);
                    reference_pixel(g*4+l,y,pattern);
                end
                if(!FULL && n%11==3)blank();
                if(bad==12 && n==mid)step(0,0,0,0,1,1,id_,id_,gr,gb,nc,0);
                if(bad==11 && n==mid)step(0,0,0,1,1,0,id_,id_,gr,gb,nc,0);
                fs=(n==0 && bad!=1) || (bad==4 && n==mid);
                le=g==W/4-1;
                if(bad==5 && n==W/4-1)le=0;
                if(bad==6 && n==0)le=1;
                fd=bad==9 && n==(W/4)*H-1;
                step(1,fs,le,fd,1,0,id_+((bad==7 && n==mid) ? 1:0),id_,gr+((bad==8 && n==mid) ? 1:0),gb,nc,bus);
                n++;
            end
            if(bad==10)step(1,0,0,0,1,0,id_,id_,gr,gb,nc,0);
            step(0,0,0,1,bad!=2,0,id_,id_+(bad==3 ? 1:0),gr,gb,nc,0);
            check(publications==pubs,"done cycle does not publish before accumulator drain");
            if(bad==13)step(0,0,0,0,1,1,id_,id_,gr,gb,nc,0);
            else if(bad==14)step(0,1,0,0,1,0,id_+1,id_+1,gr,gb,nc,0);
            else blank();
            if(bad<=1)begin
                check(publications==pubs+1 && out_valid && out_trusted,"one complete frame publication");
                compare_snapshot(id_,gr,gb,nc);
                check(rejections==rej,"healthy frame has no rejection");
            end else begin
                check(publications==pubs && !out_valid && !out_trusted,"bad/flush frame never publishes trusted stats");
                if(bad!=13)check(rejections>rej,"malformed frame has rejection evidence");
            end
            blank();check(!out_valid,"publication is a single-clock pulse");
        end
    endtask
    integer b;
    initial begin
        done=0;errors=0;checks=0;scenarios=0;injected=0;
        if(!$value$plusargs("INJECT_FAULT=%d",inject_mode))inject_mode=0;
        repeat(3)@(posedge clk);@(negedge clk);rst_n=1;
        blank();
        frame(100+CASE_ID*100,0,CASE_ID);
        frame(101+CASE_ID*100,1,CASE_ID+3);
        if(CASE_ID==0)begin
            for(b=2;b<=14;b++)begin
                frame(102+b,b,b);
                frame(202+b,0,b+1); // Fresh SOF after every fault must recover without mixed data.
            end
            scenarios++;
            step(1,0,0,0,1,0,500,500,256,256,0,0);
            check(out_reject && !out_trusted && out_reject_reason[1],"orphan group is rejected");
            blank();
            step(0,0,1,0,1,0,500,500,256,256,0,0);
            check(out_reject && out_reject_reason[2],"EOL without valid rejected");
            blank();frame(501,1,5);
            scenarios++;
            // Reset while a held good result exists retracts trust and payload.
            @(negedge clk);rst_n=0;#1;check(!out_trusted && !out_valid && out_sample_present==0,"reset revokes held result");
            @(negedge clk);rst_n=1;blank();frame(502,0,6);
        end
        done=1;
        $display("DIAG_CASE_DONE case=%0d W=%0d H=%0d msb=%0d checks=%0d errors=%0d scenes=%0d",CASE_ID,W,H,MSB,checks,errors,scenarios);
    end
endmodule

module tb_pixel14_color_diagnostics;
    wire [4:0] finished;
    wire integer e0,e1,e2,e3,e4,c0,c1,c2,c3,c4,s0,s1,s2,s3,s4,i0,i1,i2,i3,i4;
    color_diag_case #(.CASE_ID(0),.OFFSET(0)) w0(finished[0],e0,c0,s0,i0);
    color_diag_case #(.CASE_ID(1),.OFFSET(1)) w1(finished[1],e1,c1,s1,i1);
    color_diag_case #(.CASE_ID(2),.OFFSET(2),.MSB(0)) w2(finished[2],e2,c2,s2,i2);
    color_diag_case #(.CASE_ID(3),.OFFSET(3)) w3(finished[3],e3,c3,s3,i3);
    color_diag_case #(.CASE_ID(4),.W(1280),.H(720),.FULL(1)) w4(finished[4],e4,c4,s4,i4);
    wire [31:0] errors=e0+e1+e2+e3+e4,checks=c0+c1+c2+c3+c4,scenarios=s0+s1+s2+s3+s4,injected=i0+i1+i2+i3+i4;
    wire test_done=&finished;
    initial begin wait(test_done);#1;$display("RESULT diagnostics checks=%0d errors=%0d scenarios=%0d injected=%0d",checks,errors,scenarios,injected);$finish;end
    initial begin #100000000;$fatal(1,"diagnostics TB watchdog");end
endmodule
