`timescale 1ns/1ps
// Independent directed contract checks. No hierarchical DUT state is inspected.
module tb_events;
    reg clk=0;
    always #5 clk=~clk;
    integer errors=0, checks=0, adapter_cases=0, event_cases=0, parameter_cases=0;
    integer mapping_mask=0, auto_events=0, replay_events=0, cancel_events=0;
    reg test_done=0;
    reg ar=0, af=0, sample=0, box_valid=0;
    reg [1:0] box_color=0, shape_color=0, shape=0;
    reg [10:0] left=0, right=0;
    reg [9:0] top=0,bottom=0;
    reg [7:0] box_count=0,shape_count=0;
    wire au,ap,av;
    wire [3:0] ai;
    wire [9:0] ax,ay,aw,ah;
    wire [7:0] ac;
    detection_adapter adapter(.clk(clk),.rst_n(ar),.flush(af),.sample(sample),
        .box_valid(box_valid),.box_color(box_color),.shape_color(shape_color),.shape(shape),
        .left(left),.right(right),.top(top),.bottom(bottom),.box_count(box_count),
        .shape_count(shape_count),.det_update(au),.present(ap),.det_valid(av),.item_id(ai),
        .bbox_x(ax),.bbox_y(ay),.bbox_w(aw),.bbox_h(ah),.stable_count(ac));

    reg er=0,ef=0,eu=0,ep=0,ev=0,rr=0;
    reg [3:0] ei=0;
    wire dv,cp;
    wire [3:0] di,ati;
    wire [2:0] ae;
    learning_events events(.clk(clk),.rst_n(er),.flush(ef),.det_update(eu),.present(ep),
        .det_valid(ev),.item_id(ei),.replay_pulse(rr),.display_valid(dv),.display_item(di),
        .audio_event(ae),.audio_item_id(ati),.cancel_pulse(cp));

    reg pr=0,pf=0,pu=0,pp=0,pv=0,preplay=0;
    reg [3:0] pi=0;
    wire [5:0] pdv,pcp;
    wire [3:0] pdi[0:5],pai[0:5];
    wire [2:0] pae[0:5];
    genvar g;
    generate for(g=0;g<6;g=g+1) begin: parameters
        localparam R=(g==0)?1:(g==1)?2:(g==2)?3:(g==3)?255:(g==4)?0:256;
        learning_events #(.REMOVE_FRAMES(R)) dut(.clk(clk),.rst_n(pr),.flush(pf),
            .det_update(pu),.present(pp),.det_valid(pv),.item_id(pi),.replay_pulse(preplay),
            .display_valid(pdv[g]),.display_item(pdi[g]),.audio_event(pae[g]),
            .audio_item_id(pai[g]),.cancel_pulse(pcp[g]));
    end endgenerate

    task check(input reg condition,input string label);
        begin
            checks=checks+1;
            if(condition!==1'b1) begin
                errors=errors+1;
                $display("FAIL t=%0t %s",$time,label);
            end
        end
    endtask

    integer exu=0,expres=0,exv=0,exi=0,exx=0,exy=0,exw=0,exh=0,exc=0;
    task adapter_tick(input integer reset_n,fl,s,bv,bc,sc,sh,l,r,t,b,ct,st,input string label);
        integer accepted,cell_left,cell_right,cell_top,cell_bottom;
        begin
            @(negedge clk);
            ar=reset_n;af=fl;sample=s;box_valid=bv;box_color=bc;shape_color=sc;shape=sh;
            left=l;right=r;top=t;bottom=b;box_count=ct;shape_count=st;
            if(!reset_n || fl) begin
                exu=0;expres=0;exv=0;exi=0;exx=0;exy=0;exw=0;exh=0;exc=0;
            end else begin
                exu=s;
                if(s) begin
                    // Reference uses integer cell coverage and item-id arithmetic.
                    accepted=bv && bc>=1 && bc<=3 && bc==sc && sh>=1 && sh<=3 &&
                        ct>=3 && st>=3 && l<=r && t<=b && r<=1279 && b<=719;
                    expres=bv; exv=accepted; exi=0;exx=0;exy=0;exw=0;exh=0;exc=0;
                    if(accepted) begin
                        exi=(bc-1)*3+sh;
                        cell_left=l/4;cell_right=r/4;cell_top=t/4;cell_bottom=b/4;
                        exx=cell_left;exy=cell_top;exw=cell_right-cell_left+1;exh=cell_bottom-cell_top+1;
                        if(ct<st) exc=ct; else exc=st;
                        mapping_mask=mapping_mask | (1<<(exi-1));
                    end
                end
            end
            @(posedge clk);#1;
            adapter_cases=adapter_cases+1;
            check(au===exu[0],{label," det_update"});
            check(ap===expres[0],{label," present"});
            check(av===exv[0],{label," det_valid"});
            check(ai===exi[3:0],{label," item_id"});
            check(ax===exx[9:0] && ay===exy[9:0] && aw===exw[9:0] && ah===exh[9:0],{label," bbox"});
            check(ac===exc[7:0],{label," stable_count"});
        end
    endtask

    task event_tick(input integer reset_n,fl,u,p,v,id,replay,vd,idd,event_id,audio_id,cancel,
                    input string label);
        begin
            @(negedge clk);er=reset_n;ef=fl;eu=u;ep=p;ev=v;ei=id;rr=replay;
            @(posedge clk);#1;
            event_cases=event_cases+1;
            check(dv===vd[0] && di===idd[3:0],{label," display"});
            check(ae===event_id[2:0] && ati===audio_id[3:0],{label," audio"});
            if(ae!==event_id[2:0] || ati!==audio_id[3:0])
                $display("DETAIL expected event=%0d id=%0d observed event=%0d id=%0d",event_id,audio_id,ae,ati);
            check(cp===cancel[0],{label," cancel"});
            if(ae==1) auto_events=auto_events+1;
            if(ae==5) replay_events=replay_events+1;
            if(cp==1) cancel_events=cancel_events+1;
        end
    endtask

    task parameter_tick(input integer reset_n,fl,u,p,v,id,replay);
        begin
            @(negedge clk);pr=reset_n;pf=fl;pu=u;pp=p;pv=v;pi=id;preplay=replay;
            @(posedge clk);#1;
        end
    endtask
    task parameter_check(input integer idx,vd,id,event_id,audio_id,cancel,input string label);
        begin
            parameter_cases=parameter_cases+1;
            check(pdv[idx]===vd[0] && pdi[idx]===id[3:0],$sformatf("%s parameter=%0d display",label,idx));
            check(pae[idx]===event_id[2:0] && pai[idx]===audio_id[3:0],$sformatf("%s parameter=%0d audio",label,idx));
            check(pcp[idx]===cancel[0],$sformatf("%s parameter=%0d cancel",label,idx));
        end
    endtask

    integer c,s,k,j,n,threshold,seed=32'h4c454152,unused;
    integer rc,rsc,rs,rl,rright,rt,rb,rcount,rscount,rbv;
    initial begin
        unused=$urandom(seed);
        adapter_tick(0,1,1,1,1,1,1,0,1279,0,719,255,255,"reset beats flush/sample");
        for(c=1;c<=3;c=c+1) for(s=1;s<=3;s=s+1)
            adapter_tick(1,0,1,1,c,c,s,103,410,57,220,3,4,$sformatf("mapping %0d/%0d",c,s));
        adapter_tick(1,0,1,1,3,3,3,0,1279,0,719,255,255,"full-screen inclusive bounds");
        adapter_tick(1,0,1,1,1,1,1,1279,1279,719,719,9,6,"bottom-right single pixel");
        adapter_tick(1,0,1,1,1,1,1,3,4,3,4,3,3,"cross-cell two pixels");
        adapter_tick(1,0,1,1,1,1,1,4,7,4,7,3,3,"one exact grid cell");
        adapter_tick(1,0,0,0,0,0,0,0,0,0,0,0,0,"sample low holds result");
        adapter_tick(1,0,1,0,1,1,1,0,10,0,10,3,3,"no box");
        adapter_tick(1,0,1,1,1,2,1,0,10,0,10,3,3,"mismatched color remains present");
        adapter_tick(1,0,1,1,1,1,0,0,10,0,10,3,3,"unknown shape remains present");
        adapter_tick(1,0,1,1,0,0,1,0,10,0,10,3,3,"unknown color");
        adapter_tick(1,0,1,1,1,1,1,0,10,0,10,2,3,"box count below threshold");
        adapter_tick(1,0,1,1,1,1,1,0,10,0,10,3,2,"shape count below threshold");
        adapter_tick(1,0,1,1,1,1,1,11,10,0,10,3,3,"reversed x");
        adapter_tick(1,0,1,1,1,1,1,0,10,11,10,3,3,"reversed y");
        adapter_tick(1,0,1,1,1,1,1,0,1280,0,10,3,3,"right out of range");
        adapter_tick(1,0,1,1,1,1,1,0,10,0,720,3,3,"bottom out of range");
        adapter_tick(1,1,1,1,2,2,2,0,1279,0,719,255,255,"flush beats valid sample");
        adapter_tick(1,0,0,1,2,2,2,0,1279,0,719,255,255,"flush result holds without sample");
        for(c=0;c<4;c=c+1) for(s=0;s<4;s=s+1) for(k=0;k<4;k=k+1)
            adapter_tick(1,0,1,1,c,s,k,7,100,11,105,3,255,"exhaustive color/shape triples");
        for(k=0;k<512;k=k+1) begin
            rc=$urandom_range(0,3);rsc=$urandom_range(0,3);rs=$urandom_range(0,3);
            rl=$urandom_range(0,1300);rright=$urandom_range(0,1300);
            rt=$urandom_range(0,750);rb=$urandom_range(0,750);
            rcount=$urandom_range(0,255);rscount=$urandom_range(0,255);rbv=$urandom_range(0,1);
            adapter_tick(1,0,k%5!=0,rbv,rc,rsc,rs,rl,rright,rt,rb,rcount,rscount,"seeded mixed adapter inputs");
        end
        adapter_tick(0,0,0,0,0,0,0,0,0,0,0,0,0,"adapter reset after traffic");
        check(mapping_mask==511,"all nine item IDs observed");

        event_tick(0,1,1,1,1,1,1,0,0,0,0,0,"reset wins all competing inputs");
        event_tick(1,0,0,0,0,0,1,0,0,0,0,0,"empty replay ignored");
        event_tick(1,0,1,1,0,0,0,0,0,0,0,0,"unqualified first presence");
        event_tick(1,0,1,1,1,1,0,1,1,1,1,0,"first stable enters session");
        for(k=0;k<6;k=k+1) event_tick(1,0,1,1,1,1,0,1,1,0,0,0,"continued same ID suppressed");
        event_tick(1,0,0,0,0,0,0,1,1,0,0,0,"no det_update holds UI");
        event_tick(1,0,0,0,0,0,1,1,1,5,1,0,"replay current UI without update");
        event_tick(1,0,0,0,0,0,0,1,1,0,0,0,"replay one-cycle event");
        event_tick(1,0,1,1,0,0,0,0,0,0,0,0,"unknown transient clears UI only");
        event_tick(1,0,0,1,0,0,1,0,0,0,0,0,"unknown replay ignored");
        event_tick(1,0,1,1,1,1,0,1,1,0,0,0,"stable after unknown no auto retrigger");
        for(k=2;k<=9;k=k+1) event_tick(1,0,1,1,1,k,0,1,k,0,0,0,"direct ID changes UI only");
        event_tick(1,0,1,1,1,2,1,1,2,5,2,0,"replay selects same-cycle new ID");
        event_tick(1,0,1,0,0,0,1,0,0,0,0,0,"one missing frame and replay ignored");
        event_tick(1,0,0,0,0,0,1,0,0,0,0,0,"no update cannot advance removal");
        event_tick(1,0,1,1,1,2,0,1,2,0,0,0,"return after one miss stays announced");
        event_tick(1,0,1,0,0,0,0,0,0,0,0,0,"removal first sample");
        event_tick(1,0,1,0,0,0,0,0,0,0,0,1,"removal second sample cancels once");
        event_tick(1,0,1,0,0,0,0,0,0,0,0,0,"continued absence no repeated cancel");
        event_tick(1,0,1,1,1,2,0,1,2,1,2,0,"return after removal new announcement");
        for(k=10;k<=15;k=k+1) event_tick(1,0,1,1,1,k,1,0,0,0,0,0,"invalid or card ID rejected");
        event_tick(1,0,1,1,1,0,1,0,0,0,0,0,"zero ID rejected despite det_valid");
        event_tick(1,0,1,1,1,3,0,1,3,0,0,0,"illegal IDs cannot rearm session");
        event_tick(1,1,1,1,1,4,1,0,0,0,0,1,"flush wins detection and replay");
        event_tick(1,0,0,0,0,0,0,0,0,0,0,0,"flush cancel pulse expires");
        event_tick(1,0,1,1,1,4,1,1,4,1,4,0,"first automatic event wins simultaneous replay after flush");
        event_tick(1,0,1,1,1,4,0,1,4,0,0,0,"first automatic event marks announced");
        event_tick(0,1,1,1,1,8,1,0,0,0,0,0,"reset wins active session and flush");
        event_tick(1,0,1,1,1,8,1,1,8,1,8,0,"first automatic event wins simultaneous replay after reset");
        event_tick(1,0,1,0,1,8,1,0,0,0,0,0,"present low invalidates valid flag and replay");
        event_tick(1,0,1,0,1,8,1,0,0,0,0,1,"absent valid flag still cancels session");
        event_tick(1,0,1,1,1,8,0,1,8,1,8,0,"return after absence rearmed");
        event_tick(0,0,0,0,0,0,0,0,0,0,0,0,"event reset after traffic");

        parameter_tick(0,1,1,1,1,7,1);
        for(j=0;j<6;j=j+1) parameter_check(j,0,0,0,0,0,"parameter reset dominates");
        parameter_tick(1,0,1,1,1,7,0);
        for(j=0;j<6;j=j+1)
            if(j<4) parameter_check(j,1,7,1,7,0,"parameter session entry");
            else parameter_check(j,0,0,0,0,1,"invalid parameter fails closed");
        for(n=1;n<=256;n=n+1) begin
            parameter_tick(1,0,1,0,0,0,0);
            for(j=0;j<6;j=j+1) begin
                threshold=(j==0)?1:(j==1)?2:(j==2)?3:255;
                parameter_check(j,0,0,0,0,j>=4 || n==threshold,"parameter removal boundary");
            end
            // Gap cycles must neither increase absent_frames nor repeat cancel.
            parameter_tick(1,0,0,0,0,0,0);
            for(j=0;j<6;j=j+1) parameter_check(j,0,0,0,0,j>=4,"parameter no-update gap");
        end
        parameter_tick(1,0,1,1,1,6,0);
        for(j=0;j<6;j=j+1)
            if(j<4) parameter_check(j,1,6,1,6,0,"parameter return after removal");
            else parameter_check(j,0,0,0,0,1,"invalid parameter stays closed");
        parameter_tick(1,1,1,1,1,6,1);
        for(j=0;j<6;j=j+1) parameter_check(j,0,0,0,0,1,"parameter flush priority");
        parameter_tick(0,1,1,1,1,6,1);
        for(j=0;j<6;j=j+1) parameter_check(j,0,0,0,0,0,"parameter final reset");
        if($test$plusargs("negative_control")) check(ai===4'd9,"injected incorrect checker expectation after reset");
        test_done=1;
        $display("EVENTS_RESULT done=%0d errors=%0d checks=%0d adapter_cases=%0d event_cases=%0d parameter_cases=%0d mapping_mask=%0d auto_events=%0d replay_events=%0d cancel_events=%0d",test_done,errors,checks,adapter_cases,event_cases,parameter_cases,mapping_mask,auto_events,replay_events,cancel_events);
    end
endmodule
