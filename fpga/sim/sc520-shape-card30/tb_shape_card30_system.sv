`timescale 1ns/1ps
`include "recognition30_packet.vh"
module tb_shape_card30_system;
    reg clk=0;always #6.6665 clk=~clk;
    reg rst_n=0,tick_1ms=0,flush=0,transport_revoke=0,packet_in_event=0;
    reg [191:0] packet_in=0;
    reg key_mode_pulse=0,key_replay_pulse=0,key_skip_pulse=0,key_reset_pulse=0;
    reg audio_idle=1,audio_fault=1;
    wire detectors_flush,obs_event,obs_healthy,obs_present,obs_valid,obs_revoke,obs_conflict,timed_out;
    wire [3:0] obs_item;
    wire [31:0] obs_frame_id;
    wire obs_source_test;
    wire [7:0] obs_count;
    wire [1:0] mode,phase;
    wire [3:0] score,question_index,target_item,display_item;
    wire quiz_active,answer_valid,answer_correct,display_source_test,armed;
    wire [2:0] feedback,audio_event_kind;
    wire audio_event_valid,audio_cancel;
    wire [3:0] audio_event_item;
    wire [27:0] render_state;
    wire [191:0] recognition_packet;
    wire packet_event,packet_fresh,packet_fault;
    wire [7:0] packet_age;
    items30_system #(.TIMEOUT_MS(100),.FEEDBACK_TICKS(2)) dut(.*);
    integer errors=0,checks=0,scenarios=0;
    reg test_done=0,negative=0;
    task ck(input bit value,input string message);
        begin checks++;if(!value)begin errors++;$display("FAIL system %s",message);end end
    endtask
    task make_packet(input reg [31:0] tag,input bit source,input bit healthy,
                     input bit present,input bit valid,input reg [3:0] item);
        begin
            packet_in=0;
            packet_in[`R30_ID]=tag;packet_in[`R30_SOURCE]=source;
            packet_in[`R30_HEALTHY]=healthy;packet_in[`R30_PRESENT]=present;
            packet_in[`R30_VALID]=valid;packet_in[`R30_REVOKE]=!healthy;
            packet_in[`R30_ITEM]=valid?item:0;packet_in[`R30_COUNT]=valid?3:0;
            packet_in[`R30_RAW_ITEM]=valid?item:0;packet_in[`R30_AVAILABLE]=7;
            packet_in[`R30_ARBITRATED]=1;packet_in[`R30_ID_KNOWN]=1;
            packet_in[`R30_PACKET_REV]=1;packet_in[`R30_CATALOG_REV]=1;
            packet_in[`R30_CIRCLE]=29;packet_in[`R30_SQUARE]=45;packet_in[`R30_TRIANGLE]=61;
            packet_in[`R30_CARD_BEST]=17;packet_in[`R30_CARD_SECOND]=70;packet_in[`R30_FOREGROUND]=164;
        end
    endtask
    task send;
        begin
            @(negedge clk);packet_in_event=1;
            @(posedge clk);#1;
            @(negedge clk);packet_in_event=0;
        end
    endtask
    task tick(input integer count);
        begin for(integer i=0;i<count;i++)begin
            @(negedge clk);tick_1ms=1;@(negedge clk);tick_1ms=0;
        end end
    endtask
    task clear_epoch;
        begin @(negedge clk);flush=1;@(negedge clk);flush=0;end
    endtask
    initial begin
        negative=$test$plusargs("NEGATIVE");
        repeat(5)@(negedge clk);rst_n=1;repeat(4)@(negedge clk);
        scenarios++;make_packet(1,0,1,1,1,10);send;
        ck(obs_event&&obs_healthy&&obs_valid&&obs_item==10&&obs_count==3,"healthy packet business and updated confirmation");
        ck(recognition_packet===packet_in&&packet_fresh&&!packet_fault,"all192 bits preserved at consumer");
        repeat(4)@(negedge clk);
        ck(!obs_event&&packet_fresh,"held payload is not a repeated observation");
        tick(99);
        ck(packet_fresh&&packet_age==99&&!timed_out,"exact pre-timeout age99");
        tick(1);
        ck(!packet_fresh&&timed_out&&obs_revoke&&!obs_valid&&obs_item==0,"100ms withdraws trust");
        scenarios++;make_packet(1,0,1,1,1,10);send;
        ck(obs_revoke&&!obs_valid&&!packet_fresh,"same tag remains stale after timeout");
        make_packet(2,0,1,1,0,0);send;
        ck(obs_healthy&&obs_present&&!obs_valid&&obs_item==0&&packet_fresh,"healthy unknown stays present and fresh");
        make_packet(3,0,0,1,0,0);send;
        ck(obs_revoke&&!obs_healthy&&packet_fresh,"fresh invalid packet is never healthy");
        make_packet(3,0,1,1,1,11);send;
        ck(obs_revoke&&!obs_valid,"invalid observed identity cannot replay healthy");
        make_packet(4,0,1,1,1,11);send;
        ck(obs_valid&&obs_item==11,"new identity recovers after unhealthy frame");
        scenarios++;make_packet(1,1,1,1,1,12);send;
        ck(obs_revoke&&!obs_valid&&detectors_flush,"first source switch rejected and requests clear");
        make_packet(1,1,1,1,1,12);send;
        ck(obs_revoke&&!obs_valid,"source-switch tag replay rejected");
        make_packet(2,1,1,1,1,12);send;
        ck(obs_valid&&obs_source_test&&obs_item==12,"newer source frame recovers");
        make_packet(4,0,1,1,1,13);send;
        ck(obs_revoke&&!obs_valid,"old source history retained when switching back");
        make_packet(5,0,1,1,1,13);send;
        ck(obs_revoke&&!obs_valid,"first newer switch-back consumed but revoked");
        make_packet(6,0,1,1,1,13);send;
        ck(obs_valid&&!obs_source_test&&obs_item==13,"newer switch-back frame recovers");
        scenarios++;make_packet(7,0,1,1,1,4);send;
        ck(obs_revoke&&!obs_valid,"retired class4 structurally rejected");
        ck(obs_frame_id==7&&recognition_packet[`R30_ID]==7&&!obs_source_test&&
            recognition_packet[`R30_ID_KNOWN],"fault observation identity matches current bad packet");
        make_packet(7,0,1,1,1,14);send;
        ck(obs_revoke&&!obs_valid,"malformed known identity cannot replay");
        make_packet(8,0,1,1,1,14);send;
        ck(obs_valid&&obs_item==14,"next legal identity recovers");
        make_packet(9,0,0,1,0,0);
        packet_in[`R30_ID_KNOWN]=0;packet_in[`R30_AVAILABLE]=0;
        packet_in[`R30_ARBITRATED]=0;
        packet_in[`R30_CIRCLE]=2047;packet_in[`R30_SQUARE]=2047;packet_in[`R30_TRIANGLE]=2047;
        packet_in[`R30_CARD_BEST]=2047;packet_in[`R30_CARD_SECOND]=2047;packet_in[`R30_FOREGROUND]=2047;send;
        ck(obs_revoke&&!obs_valid,"unknown identity revokes");
        ck(obs_frame_id==0&&!obs_source_test,"unknown identity cannot expose previous observation ID");
        make_packet(9,0,1,1,1,1);send;
        ck(obs_valid&&obs_item==1,"unknown identity does not advance history");
        scenarios++;clear_epoch;make_packet(32'hfffffffe,0,1,1,1,2);send;
        ck(obs_valid,"external flush allows new epoch");
        make_packet(32'hffffffff,0,1,1,1,2);send;ck(obs_valid,"last32bit tag accepted");
        make_packet(0,0,1,1,1,2);send;ck(obs_valid,"monotonic wrap to zero accepted");
        make_packet(32'h80000000,0,1,1,1,2);send;ck(obs_revoke,"half-range advance rejected");
        scenarios++;clear_epoch;make_packet(1,0,1,0,0,0);send;
        ck(obs_healthy&&!obs_present&&!obs_valid,"real empty can rearm");
        scenarios++;make_packet(2,0,1,1,0,0);packet_in[`R30_COUNT]=1;send;
        ck(obs_revoke&&!obs_valid&&!packet_fresh,"unknown raw candidate cannot carry confirmation count");
        make_packet(3,0,1,1,0,0);packet_in[`R30_RAW_ITEM]=1;send;
        ck(obs_revoke&&!obs_valid,"positive raw candidate must carry first confirmation count");
        scenarios++;make_packet(4,0,0,1,0,0);packet_in[`R30_AVAILABLE]=6;
        packet_in[`R30_ARBITRATED]=0;packet_in[`R30_SCENE_COUNT]=23;send;
        ck(obs_revoke&&!packet_fresh&&recognition_packet[`R30_SCENE_COUNT]==0&&
            recognition_packet[`R30_GLYPH_COUNT]==0,"unavailable scene fields must be canonical");
        scenarios++;make_packet(5,0,1,1,1,2);send;
        @(negedge clk);transport_revoke=1;
        @(negedge clk);#1;
        ck(obs_revoke&&!obs_valid&&obs_frame_id==0&&!obs_source_test&&
            !recognition_packet[`R30_ID_KNOWN],"transport fault clears stale observation identity");
        transport_revoke=0;
        if(negative)ck(obs_item==15,"intentional checker negative");
        test_done=1;
        $display("RESULT chain_system errors=%0d checks=%0d scenarios=%0d done=%0d",errors,checks,scenarios,test_done);
        $finish;
    end
    initial begin #1000000;$display("WATCHDOG chain_system");$finish;end
endmodule
