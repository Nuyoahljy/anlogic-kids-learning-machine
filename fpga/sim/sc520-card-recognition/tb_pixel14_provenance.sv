`timescale 1ns/1ps
module tb_pixel14_provenance;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,csi_sof=0,csi_eof=0,csi_valid=0,hs_valid=0,lane_error=0;
    reg raw_sof=0,raw_eof=0,raw_valid=0,isp_sof=0,isp_valid=0,isp_eol=0,cfg_done=1,cfg_error=0;
    reg [15:0] csi_length=0;
    wire frame_start,frame_done,frame_good,revoke;wire [31:0] frame_id,done_id;
    pixel14_capture_provenance #(.FRAME_WIDTH(64),.FRAME_HEIGHT(4),.DRAIN_IDLE_CYCLES(4),.FRAME_TIMEOUT_CYCLES(1000)) dut(.*);
    integer errors=0,checks=0,scenarios=0,injected=0,inject_fault=0,unused;
    integer starts=0,dones=0,goods=0,revokes=0,y,j,before_good,before_done,before_revoke;
    reg test_done=0;
    reg v_hs=0;reg [15:0] v_data=0;
    wire v_sof,v_eof,v_valid;wire [31:0] v_csi_data;wire [15:0] v_length;
    wire v_raw_sof,v_raw_eof,v_raw_valid;wire [39:0] v_raw_data;
    reg v_isp_sof=0,v_isp_valid=0,v_isp_eol=0;
    wire v_start,v_done,v_good,v_revoke;wire [31:0] v_id,v_done_id;
    integer v_goods=0,v_csi_words=0,v_raw_groups=0,v_eofs=0,v_old_goods,gap,k;
    csi_unpacket_2lane vendor_csi(.I_clk(clk),.I_rst_n(rst_n),.I_hs_valid(v_hs),.I_hs_data(v_data),
        .O_csi_frame_start(v_sof),.O_csi_frame_end(v_eof),.O_csi_valid(v_valid),.O_csi_hs(),
        .O_csi_data(v_csi_data),.O_data_length(v_length));
    raw10_unpacket_2lane vendor_raw(.I_clk(clk),.I_rst_n(rst_n),.I_csi_frame_start(v_sof),
        .I_csi_frame_end(v_eof),.I_csi_valid(v_valid),.I_csi_data(v_csi_data),.I_camera_black_level(10'd0),
        .O_raw10_frame_start(v_raw_sof),.O_raw10_frame_end(v_raw_eof),.O_raw10_valid(v_raw_valid),.O_raw10_data(v_raw_data));
    pixel14_capture_provenance #(.FRAME_WIDTH(64),.FRAME_HEIGHT(4),.DRAIN_IDLE_CYCLES(4),.FRAME_TIMEOUT_CYCLES(1000)) vendor_dut(
        .clk(clk),.rst_n(rst_n),.csi_sof(v_sof),.csi_eof(v_eof),.csi_length(v_length),
        .csi_valid(v_valid),.hs_valid(v_hs),.lane_error(1'b0),.raw_sof(v_raw_sof),.raw_eof(v_raw_eof),.raw_valid(v_raw_valid),
        .isp_sof(v_isp_sof),.isp_valid(v_isp_valid),.isp_eol(v_isp_eol),.cfg_done(1'b1),.cfg_error(1'b0),
        .frame_start(v_start),.frame_id(v_id),.frame_done(v_done),.frame_good(v_good),.done_id(v_done_id),.revoke(v_revoke));
    always @(posedge clk) if(rst_n) begin
        if(v_valid)v_csi_words++;
        if(v_raw_valid)v_raw_groups++;
        if(v_eof)begin v_eofs++;ck(!v_hs,"vendor short EOF observer sees ended HS burst");end
        if(v_good)v_goods++;
    end
    task ck(input bit pass,input string text);
        begin checks++;if(!pass)begin errors++;$display("ERROR provenance %0d %s",scenarios,text);end end
    endtask
    task step;begin @(negedge clk);end endtask
    always @(posedge clk) if(rst_n) begin
        if(frame_start)begin starts++;ck(frame_id!=0,"true CSI identity");end
        if(revoke)revokes++;
        if(frame_done)begin
            dones++;ck(!isp_valid&&!isp_eol&&!isp_sof,"done on blank cycle");
            ck(done_id==frame_id,"done bound to same identity");
            if(frame_good)begin
                goods++;
                if(inject_fault && injected==0)begin
                    force dut.frame_good=0;injected=1;#0.01;
                    ck(frame_good===1'b1,"real qualified-good output injection");release dut.frame_good;
                end
            end
        end
    end
    task reset_all;
        begin rst_n=0;csi_sof=0;csi_eof=0;csi_valid=0;csi_length=0;hs_valid=0;lane_error=0;
            raw_sof=0;raw_eof=0;raw_valid=0;isp_sof=0;isp_valid=0;isp_eol=0;cfg_done=1;cfg_error=0;
            repeat(4)step();rst_n=1;step();end
    endtask
    task camera(input integer defect);
        begin
            csi_sof=1;step();csi_sof=0;raw_sof=1;step();raw_sof=0;isp_sof=1;step();isp_sof=0;
            for(y=0;y<4;y++)begin
                for(j=0;j<43-((defect==1 && y==1)?1:0);j++)begin
                    hs_valid=1;csi_length=j>=2 ? ((defect==2 && y==1)?39:40):0;
                    csi_valid=j>=3 && j<=41 && j%2==1 && !(defect==3 && y==1 && j==5);
                    step();
                end
                hs_valid=0;csi_valid=0;csi_length=0;repeat(3)step();
                for(j=0;j<16-((defect==4 && y==1)?1:0);j++)begin raw_valid=1;step();end
                raw_valid=0;repeat(3)step();
            end
            if(defect!=8)begin csi_eof=1;step();csi_eof=0;raw_eof=1;step();raw_eof=0;end
            repeat(3)step();
        end
    endtask
    task pixels(input integer defect);
        begin
            for(j=0;j<64-((defect==5)?1:0)+((defect==9)?1:0);j++)begin
                isp_valid=1;isp_eol=j%16==15;
                if(defect==6 && j==12)isp_eol=1;
                if(defect==7 && j==12)cfg_error=1;
                step();
            end
            isp_valid=0;isp_eol=0;repeat(12)step();
        end
    endtask
    task v_short(input reg [7:0] dtype);
        begin v_hs=1;v_data={dtype,8'd0};step();v_data=0;step();v_hs=0;step();end
    endtask
    task closing_fault(input integer kind);
        begin
            for(j=0;j<64;j++)begin isp_valid=1;isp_eol=j%16==15;step();end
            isp_valid=0;isp_eol=0;
            while(!frame_done)step();
            case(kind)
                0:raw_sof=1;
                1:raw_eof=1;
                2:csi_eof=1;
                3:csi_length=40;
            endcase
            #0.01;ck(frame_done && !frame_good,"new closing-edge fault rejects same-cycle good");
            step();raw_sof=0;raw_eof=0;csi_eof=0;csi_length=0;repeat(4)step();
        end
    endtask
    task v_camera(input integer packet_gap,input bit truncate_line);
        begin
            v_short(0);repeat(5)step();v_isp_sof=1;step();v_isp_sof=0;
            for(k=0;k<4;k++)begin
                v_hs=1;v_data=16'h2b50;step();v_data=0;step();
                for(j=0;j<40-((truncate_line&&k==2)?1:0);j++)begin v_data=16'h8080;step();end
                v_data=0;step();v_hs=0;repeat(packet_gap)step();
            end
            v_short(1);repeat(16)step();
            for(j=0;j<64;j++)begin v_isp_valid=1;v_isp_eol=j%16==15;step();end
            v_isp_valid=0;v_isp_eol=0;repeat(12)step();
        end
    endtask
    integer defect;
    initial begin
        unused=$value$plusargs("INJECT_FAULT=%d",inject_fault);
        for(defect=0;defect<=9;defect++)begin
            scenarios++;reset_all();before_good=goods;before_done=dones;before_revoke=revokes;
            camera(defect);pixels(defect);
            if(defect==0)begin ck(goods==before_good+1,"complete physical frame accepted");ck(dones==before_done+1,"one completion");end
            else begin
                ck(goods==before_good,"fault never qualified by complete ISP output");
                repeat(1010)step();ck(revokes>before_revoke,"fault or missing EOF revoked by deadline");
            end
        end
        scenarios++;reset_all();before_good=goods;camera(0);
        csi_sof=1;step();csi_sof=0;pixels(0);ck(goods==before_good,"overlap cannot relabel old ISP");
        scenarios++;camera(0);pixels(0);ck(goods==before_good+1,"recovery at independent SOF");
        scenarios++;reset_all();before_good=goods;isp_sof=1;step();isp_sof=0;pixels(0);
        ck(goods==before_good,"ISP-only frame never establishes capture provenance");
        for(defect=0;defect<4;defect++)begin
            scenarios++;reset_all();before_good=goods;before_done=dones;before_revoke=revokes;
            camera(0);closing_fault(defect);
            ck(goods==before_good && dones==before_done+1,"closing fault emits bad completion only");
            ck(revokes>before_revoke,"closing fault also revokes prior business result");
        end
        for(gap=1;gap<=8;gap*=2)begin
            scenarios++;reset_all();v_csi_words=0;v_raw_groups=0;v_eofs=0;v_old_goods=v_goods;
            v_camera(gap,0);
            $display("VENDOR gap=%0d csi=%0d raw=%0d eof=%0d good=%0d",gap,v_csi_words,v_raw_groups,v_eofs,v_goods-v_old_goods);
            ck(v_csi_words==80 && v_raw_groups==64 && v_eofs==1,"actual vendor decoded all payload groups and EOF");
            ck(v_goods==v_old_goods+1,"actual vendor framing qualifies one capture");
        end
        scenarios++;reset_all();v_old_goods=v_goods;v_camera(1,1);
        ck(v_goods==v_old_goods,"actual truncated HS burst cannot be hidden by full ISP raster");
        $display("PROVENANCE_COMPLETE scenarios=%0d checks=%0d errors=%0d",scenarios,checks,errors);
        test_done=1;$finish;
    end
    initial begin #2000000;$display("PROVENANCE_WATCHDOG");$finish;end
endmodule
