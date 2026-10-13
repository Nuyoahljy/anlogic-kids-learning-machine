`timescale 1ns/1ps
module tb_pixel14_provenance;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,csi_sof=0,csi_eof=0,csi_valid=0,hs_valid=0,lane_error=0;
    reg raw_sof=0,raw_eof=0,raw_valid=0,isp_sof=0,isp_valid=0,isp_eol=0,cfg_done=1,cfg_error=0;
    reg [15:0] csi_length=0;
    wire frame_start,frame_done,frame_good,revoke;wire [31:0] frame_id,done_id;
    wire [255:0] diagnostic;
    pixel14_capture_provenance #(.FRAME_WIDTH(64),.FRAME_HEIGHT(4),.DRAIN_IDLE_CYCLES(4),.FRAME_TIMEOUT_CYCLES(1000)) dut(.*);
    integer errors=0,checks=0,scenarios=0,injected=0,inject_fault=0,unused;
    integer starts=0,dones=0,goods=0,revokes=0,y,j,before_good,before_done,before_revoke;
    reg test_done=0;
    reg v_hs=0;reg [15:0] v_data=0;
    wire v_sof,v_eof,v_valid;wire [31:0] v_csi_data;wire [15:0] v_length;
    wire v_raw_sof,v_raw_eof,v_raw_valid;wire [39:0] v_raw_data;
    reg v_isp_sof=0,v_isp_valid=0,v_isp_eol=0;
    wire v_start,v_done,v_good,v_revoke;wire [31:0] v_id,v_done_id;
    wire [255:0] v_diagnostic;
    integer v_goods=0,v_csi_words=0,v_raw_groups=0,v_eofs=0,v_old_goods,gap,k;
    integer v_raw_eofs=0,v_isp_groups=0,v_payload_mismatches=0;
    integer v_dones=0,v_revokes=0,v_eof_while_hs=0,v_hs_words=0,v_hs_min=0,v_hs_max=0;
    integer v_old_dones,v_old_revokes,tail;
    reg v_hs_previous=0;
    reg [7:0] v_burst_type=0;
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
        .frame_start(v_start),.frame_id(v_id),.frame_done(v_done),.frame_good(v_good),.done_id(v_done_id),.revoke(v_revoke),
        .diagnostic(v_diagnostic));
    always @(posedge clk) if(rst_n) begin
        if(v_valid)begin
            v_csi_words++;
            if(v_csi_data!==32'h80808080)v_payload_mismatches++;
        end
        if(v_raw_valid)v_raw_groups++;
        if(v_raw_eof)v_raw_eofs++;
        if(v_isp_valid)v_isp_groups++;
        // The parser publishes a short-packet EOF after decoding its header;
        // it does not wait for the aligned HS window to end.
        if(v_eof)begin v_eofs++;if(v_hs)v_eof_while_hs++;end
        if(v_good)v_goods++;
        if(v_done)v_dones++;
        if(v_revoke)v_revokes++;
        if(v_hs)begin
            if(!v_hs_previous)begin v_hs_words=1;v_burst_type=v_data[15:8];end
            else v_hs_words++;
        end else if(v_hs_previous && v_burst_type==8'h2b)begin
            if(v_hs_min==0 || v_hs_words<v_hs_min)v_hs_min=v_hs_words;
            if(v_hs_words>v_hs_max)v_hs_max=v_hs_words;
        end
        v_hs_previous=v_hs;
    end
    task ck(input bit pass,input string text);
        begin checks++;if(!pass)begin errors++;$display("ERROR provenance %0d %s",scenarios,text);end end
    endtask
    // Public diagnostic layout: version, errors, H, F, C, R, I,
    // CSI lines, ISP lines, age, observed SOFs, healthy completions.
    // Expected counts come from this bench's transmitted frame, not DUT state.
    task diagnostic_full_frame(input reg [255:0] value,input integer expected_h);
        begin
            ck(value[255:240]===16'h0107,"diagnostic format version");
            ck(value[191:160]===32'd80,"diagnostic CSI count matches 4 times 20 transmitted words");
            ck(value[159:128]===32'd64,"diagnostic RAW count matches 4 times 16 groups");
            ck(value[127:96]===32'd64,"diagnostic ISP count matches 4 times 16 groups");
            ck(value[95:80]===16'd4 && value[79:64]===16'd4,"diagnostic carries four CSI and ISP lines");
            ck(value[223:208]==expected_h,"diagnostic H matches transmitted long-packet HS window");
            ck(value[63:32]>0 && value[63:32]<1000,"completed frame age precedes the configured deadline");
        end
    endtask
    task diagnostic_healthy(input reg [255:0] value,input integer expected_h,input bit eof_during_hs);
        begin
            diagnostic_full_frame(value,expected_h);
            ck(value[239:224]===16'd0,"healthy completed frame has no diagnostic error bits");
            ck(value[207]===eof_during_hs,"diagnostic F high bit records HS at the actual EOF event");
            ck(value[31:16]===16'd1 && value[15:0]===16'd1,"one transmitted SOF and one healthy completion");
        end
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
            v_hs=0;v_data=0;v_isp_sof=0;v_isp_valid=0;v_isp_eol=0;v_hs_previous=0;
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
    task v_short(input reg [7:0] dtype,input integer trail_words);
        integer n;
        begin
            v_hs=1;v_data={dtype,8'd0};step();v_data=0;step();
            // Extra aligned-valid words follow the complete short header.
            // No long-packet length or payload is added by this stimulus.
            for(n=0;n<trail_words;n++)begin v_data=16'hffff;step();end
            v_hs=0;v_data=0;step();
        end
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
    task v_packets(input integer packet_gap,input bit truncate_line,
                   input integer short_tail,input integer long_tail,
                   input bit omit_crc,input integer declared_words);
        integer n;
        reg [15:0] byte_count;
        begin
            byte_count=declared_words*2;
            v_short(0,short_tail);repeat(5)step();v_isp_sof=1;step();v_isp_sof=0;
            for(k=0;k<4;k++)begin
                v_hs=1;v_data={8'h2b,byte_count[7:0]};step();v_data={byte_count[15:8],8'd0};step();
                for(j=0;j<declared_words-((truncate_line&&k==2)?1:0);j++)begin v_data=16'h8080;step();end
                if(!(omit_crc && k==2))begin v_data=0;step();end
                // The declared RAW10 payload and CRC placeholder have ended.
                // These words extend only the aligned HS window, not WC.
                for(n=0;n<long_tail;n++)begin v_data=16'hffff;step();end
                v_hs=0;v_data=0;repeat(packet_gap)step();
            end
        end
    endtask
    task v_pixels;
        begin
            for(j=0;j<64;j++)begin v_isp_valid=1;v_isp_eol=j%16==15;step();end
            v_isp_valid=0;v_isp_eol=0;repeat(12)step();
        end
    endtask
    task v_camera(input integer packet_gap,input bit truncate_line,
                  input integer short_tail,input integer long_tail,
                  input bit omit_crc,input integer declared_words);
        begin
            v_packets(packet_gap,truncate_line,short_tail,long_tail,omit_crc,declared_words);
            v_short(1,short_tail);repeat(16)step();v_pixels();
        end
    endtask
    task reset_vendor_case;
        begin
            reset_all();v_csi_words=0;v_raw_groups=0;v_eofs=0;v_eof_while_hs=0;
            v_raw_eofs=0;v_isp_groups=0;v_payload_mismatches=0;
            v_hs_words=0;v_hs_min=0;v_hs_max=0;
            v_old_goods=v_goods;v_old_dones=v_dones;v_old_revokes=v_revokes;
        end
    endtask
    task vendor_drained_eof_tail;
        integer n;
        begin
            // Complete all declared pixels and allow twelve blank cycles
            // before EOF. Only the still-open EOF HS window can delay close.
            reset_vendor_case();v_packets(1,0,0,0,0,40);v_pixels();
            ck(v_csi_words==80 && v_raw_groups==64 && v_isp_groups==64,
               "CSI, RAW and ISP payloads are complete before EOF begins");
            ck(v_eofs==0 && v_raw_eofs==0 && v_dones==v_old_dones,
               "fully drained ISP alone cannot complete without EOF");
            v_hs=1;v_data={8'h01,8'd0};step();v_data=0;step();
            for(n=0;n<16;n++)begin
                v_data=16'hffff;step();
                ck(!v_done && !v_good && v_dones==v_old_dones,
                   "drained frame cannot complete while EOF HS tail remains high");
            end
            ck(v_eofs==1 && v_raw_eofs==1 && v_eof_while_hs==1,
               "both real parser EOF events arrive while drained frame is held by HS");
            ck(v_revokes==v_old_revokes,"waiting for EOF HS tail does not revoke a healthy frame");
            v_hs=0;v_data=0;#0.01;
            ck(v_done && v_good,"drained frame becomes good as the EOF HS window closes");
            step();repeat(12)step();
            ck(v_dones==v_old_dones+1 && v_goods==v_old_goods+1,
               "EOF HS release causes exactly one healthy completion");
            ck(!v_done && !v_good && v_revokes==v_old_revokes,
               "closed frame stays inactive without duplicate completion or revoke");
            diagnostic_healthy(v_diagnostic,43,1);
            $display("VENDOR_DRAINED_EOF_TAIL tail=16 csi=%0d raw=%0d isp=%0d eof=%0d raw_eof=%0d done=%0d good=%0d",
                v_csi_words,v_raw_groups,v_isp_groups,v_eofs,v_raw_eofs,v_dones-v_old_dones,v_goods-v_old_goods);
        end
    endtask
    task vendor_damage_tail(input bit truncate_line,input bit omit_crc,input integer long_tail);
        integer missing_words;
        begin
            missing_words=truncate_line+omit_crc;
            reset_vendor_case();v_camera(1,truncate_line,0,long_tail,omit_crc,40);
            $display("VENDOR_DAMAGE_TAIL truncated=%0d omit_crc=%0d tail=%0d csi=%0d raw=%0d payload_mismatches=%0d hs_min=%0d hs_max=%0d done=%0d good=%0d errors=%h",
                truncate_line,omit_crc,long_tail,v_csi_words,v_raw_groups,v_payload_mismatches,
                v_hs_min,v_hs_max,v_dones-v_old_dones,v_goods-v_old_goods,v_diagnostic[239:224]);
            ck(v_hs_min==43+long_tail-missing_words && v_hs_max==43+long_tail,
               "damaged line HS length reflects omitted words and explicitly sent tail");
            ck(v_eofs==1 && v_raw_eofs==1 && v_dones==v_old_dones+1,
               "damaged input still presents one decoded EOF pair and one completion");
            if(long_tail<missing_words)begin
                ck(v_goods==v_old_goods && v_revokes>v_old_revokes,
                   "insufficient tail cannot hide the short total HS window");
                ck(v_diagnostic[229],"short damaged HS window retains length-error bit 5");
            end else begin
                // Detection limit: the vendor parser checks neither CRC value
                // nor pixel content. A CRC placeholder can occupy a missing
                // payload position, and tail words can fill remaining slots.
                // Acceptance here documents the limitation, not integrity.
                ck(v_csi_words==80 && v_raw_groups==64,"replacement words preserve declared decoded group counts");
                ck(truncate_line ? v_payload_mismatches>0 : v_payload_mismatches==0,
                   "independent payload comparison exposes truncated pixel data despite complete counts");
                ck(v_goods==v_old_goods+1 && v_revokes==v_old_revokes,
                   "known no-CRC-value-validation limit accepts replacement words with enough HS coverage");
                ck(v_diagnostic[239:224]===16'd0,
                   "count-only diagnostic does not claim to detect replaced CRC or payload values");
                diagnostic_full_frame(v_diagnostic,43+long_tail);
            end
        end
    endtask
    task vendor_counts(input integer short_tail,input integer long_tail);
        begin
            $display("VENDOR_TAIL short=%0d long=%0d csi=%0d raw=%0d eof=%0d eof_hs=%0d hs_min=%0d hs_max=%0d good=%0d done=%0d revoke_cycles=%0d",
                short_tail,long_tail,v_csi_words,v_raw_groups,v_eofs,v_eof_while_hs,v_hs_min,v_hs_max,
                v_goods-v_old_goods,v_dones-v_old_dones,v_revokes-v_old_revokes);
            ck(v_csi_words==80 && v_raw_groups==64 && v_eofs==1,"HS tail leaves exact declared CSI/RAW payload and one EOF");
            ck(v_eof_while_hs==(short_tail!=0),"short EOF decode precedes window end when a tail is present");
            ck(v_hs_min==43+long_tail && v_hs_max==43+long_tail,"long HS window counts payload, header, CRC and explicit tail separately");
            diagnostic_full_frame(v_diagnostic,43+long_tail);
            ck(v_diagnostic[207]==(v_eof_while_hs!=0),"diagnostic EOF-HS bit agrees with independently observed vendor EOF");
        end
    endtask
    integer defect;
    reg [255:0] completed_diagnostic;
    initial begin
        unused=$value$plusargs("INJECT_FAULT=%d",inject_fault);
        for(defect=0;defect<=9;defect++)begin
            scenarios++;reset_all();before_good=goods;before_done=dones;before_revoke=revokes;
            camera(defect);pixels(defect);
            if(defect==0)begin
                ck(goods==before_good+1,"complete physical frame accepted");ck(dones==before_done+1,"one completion");
                diagnostic_healthy(diagnostic,43,0);
            end
            else begin
                ck(goods==before_good,"fault never qualified by complete ISP output");
                repeat(1010)step();ck(revokes>before_revoke,"fault or missing EOF revoked by deadline");
                if(defect==7)ck(diagnostic[225],"configuration-error stimulus is visible as error bit 1");
                if(defect==5 || defect==8)ck(diagnostic[237],"missing ISP tail or missing EOF records timeout bit 13");
            end
        end
        scenarios++;reset_all();before_good=goods;camera(0);
        csi_sof=1;step();csi_sof=0;pixels(0);ck(goods==before_good,"overlap cannot relabel old ISP");
        scenarios++;camera(0);pixels(0);ck(goods==before_good+1,"recovery at independent SOF");
        scenarios++;reset_all();before_good=goods;isp_sof=1;step();isp_sof=0;pixels(0);
        ck(goods==before_good,"ISP-only frame never establishes capture provenance");
        ck(diagnostic[238],"orphan ISP frame remains visible as error bit 14 without a CSI frame");
        for(defect=0;defect<4;defect++)begin
            scenarios++;reset_all();before_good=goods;before_done=dones;before_revoke=revokes;
            camera(0);closing_fault(defect);
            ck(goods==before_good && dones==before_done+1,"closing fault emits bad completion only");
            ck(revokes>before_revoke,"closing fault also revokes prior business result");
            ck(diagnostic[236],"closing-edge violation is retained in completion error bit 12");
            case(defect)
                0:ck(diagnostic[231],"duplicate RAW SOF identifies error bit 7");
                1:ck(diagnostic[233],"duplicate RAW EOF identifies error bit 9");
                2:ck(diagnostic[232],"duplicate CSI EOF identifies error bit 8");
                3:ck(diagnostic[228],"new packet after EOF identifies error bit 4");
            endcase
        end
        for(gap=1;gap<=8;gap*=2)begin
            scenarios++;reset_vendor_case();
            v_camera(gap,0,0,0,0,40);
            $display("VENDOR gap=%0d csi=%0d raw=%0d eof=%0d good=%0d",gap,v_csi_words,v_raw_groups,v_eofs,v_goods-v_old_goods);
            ck(v_csi_words==80 && v_raw_groups==64 && v_eofs==1,"actual vendor decoded all payload groups and EOF");
            ck(v_goods==v_old_goods+1,"actual vendor framing qualifies one capture");
            diagnostic_healthy(v_diagnostic,43,0);
        end
        scenarios++;reset_vendor_case();v_camera(1,1,0,0,0,40);
        ck(v_goods==v_old_goods,"actual truncated HS burst cannot be hidden by full ISP raster");
        ck(v_diagnostic[229],"truncated long HS window identifies error bit 5");
        // The root-selected experimental long-packet tolerance is 16 words.
        // This is an interface candidate to confirm with board observations,
        // not an assertion about a CSI-2 standard maximum.
        for(tail=1;tail<=16;tail*=2)begin
            scenarios++;reset_vendor_case();v_camera(1,0,tail,0,0,40);
            vendor_counts(tail,0);
            ck(v_goods==v_old_goods+1,"complete vendor frame with short-packet HS tail remains healthy");
            ck(v_diagnostic[239:224]===16'd0 && v_diagnostic[15:0]===16'd1,"allowed short tail is informational, not an error");
        end
        for(tail=1;tail<=16;tail*=2)begin
            scenarios++;reset_vendor_case();v_camera(1,0,0,tail,0,40);
            vendor_counts(0,tail);
            ck(v_goods==v_old_goods+1,"complete vendor payload with bounded post-CRC HS tail remains healthy");
            ck(v_diagnostic[239:224]===16'd0 && v_diagnostic[15:0]===16'd1,"allowed long tail is informational, not an error");
        end
        for(tail=17;tail<=32;tail+=15)begin
            scenarios++;reset_vendor_case();v_camera(1,0,0,tail,0,40);
            vendor_counts(0,tail);
            ck(v_goods==v_old_goods && v_revokes>v_old_revokes,"long HS tail exceeding experimental 16-word limit is rejected");
            ck(v_diagnostic[229],"excessive long HS tail identifies error bit 5");
        end
        scenarios++;reset_vendor_case();v_camera(1,0,0,0,1,40);
        ck(v_goods==v_old_goods && v_revokes>v_old_revokes,"missing CRC placeholder cannot be accepted as a short tail");
        ck(v_diagnostic[229],"missing CRC placeholder identifies a short HS window");
        scenarios++;vendor_drained_eof_tail();
        for(tail=1;tail<=2;tail++)begin
            scenarios++;vendor_damage_tail(0,1,tail);
            scenarios++;vendor_damage_tail(1,0,tail);
        end
        for(tail=0;tail<=2;tail++)begin
            scenarios++;vendor_damage_tail(1,1,tail);
        end
        scenarios++;reset_vendor_case();v_camera(1,0,0,0,0,50);
        $display("VENDOR_EXCESS wc_words=50 csi=%0d raw=%0d eof=%0d good=%0d",v_csi_words,v_raw_groups,v_eofs,v_goods-v_old_goods);
        ck(v_csi_words==100 && v_raw_groups==80 && v_eofs==1,"larger declared payload produces real extra CSI/RAW groups");
        ck(v_goods==v_old_goods && v_revokes>v_old_revokes,"real payload overrun is rejected independently of HS tail allowance");
        ck(v_diagnostic[228],"larger declared payload identifies wrong-WC error bit 4");
        scenarios++;reset_all();before_good=goods;camera(0);pixels(0);
        completed_diagnostic=diagnostic;
        camera(0);
        ck(diagnostic[223:32]===completed_diagnostic[223:32],"incomplete next frame cannot replace saved completed-frame counts");
        ck(diagnostic[31:16]===16'd2 && diagnostic[15:0]===16'd1,"live SOF count advances independently of saved completion");
        pixels(0);
        ck(goods==before_good+2 && diagnostic[15:0]===16'd2,"second complete frame updates healthy total once");
        scenarios++;reset_all();before_good=goods;camera(0);
        force dut.diagnostic=256'hffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
        pixels(0);
        ck(goods==before_good+1,"forcing diagnostic output cannot change functional frame qualification");
        release dut.diagnostic;#0.01;
        diagnostic_healthy(diagnostic,43,0);
        $display("PROVENANCE_COMPLETE scenarios=%0d checks=%0d errors=%0d",scenarios,checks,errors);
        test_done=1;$finish;
    end
    initial begin #2000000;$display("PROVENANCE_WATCHDOG");$finish;end
endmodule
