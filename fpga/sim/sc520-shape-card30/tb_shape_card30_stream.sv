`timescale 1ns/1ps
`include "recognition30_packet.vh"
module tb_shape_card30_stream;
    reg capture_clk=0,display_clk=0;
    always #4.83 capture_clk=~capture_clk;
    always #6.6665 display_clk=~display_clk;
    reg rst_n=0,in_frame_start=0,in_source_test=0,in_valid=0,in_eol=0;
    reg [31:0] in_frame_id=0,in_done_id=0;
    reg [95:0] in_rgb96=0;
    reg in_frame_done=0,in_frame_good=1,in_done_source_test=0,in_revoke=0;
    reg tick_1ms=0,flush=0,key_mode_pulse=0,key_replay_pulse=0,key_skip_pulse=0,key_reset_pulse=0;
    reg audio_idle=1,audio_fault=1;
    reg video_frame_start=0,video_vsync=0,video_hsync=0,video_de=0;
    reg [10:0] pixel_x=0;reg [9:0] pixel_y=0;reg [23:0] video_rgb=0;
    wire out_vsync,out_hsync,out_de;wire [23:0] out_rgb;
    wire obs_event,obs_healthy,obs_present,obs_valid,obs_revoke,obs_conflict,timed_out;
    wire [3:0] obs_item,score,question_index,target_item,display_item;
    wire [31:0] obs_frame_id;wire obs_source_test;wire [7:0] obs_count;
    wire [1:0] mode,phase;wire quiz_active,answer_valid,answer_correct,display_source_test,armed;
    wire [2:0] feedback,audio_event_kind;wire audio_event_valid,audio_cancel;wire [3:0] audio_event_item;
    wire link_fault,quarantined;wire [27:0] render_state;wire [191:0] recognition_packet;
    wire recognition_event,recognition_fresh,recognition_fault;wire [7:0] recognition_age;
`ifdef CHAIN_RENDER
    pixel30_pipeline #(.RENDER_ENABLE(1)) dut(.*);
    reg [9:0] expected_logo_index[0:16383];
    reg [23:0] expected_logo_palette[0:1023];
    reg logo_index_equal=1,logo_palette_equal=1;
`else
    pixel30_pipeline #(.RENDER_ENABLE(0)) dut(.*);
`endif
    reg [23:0] raster[0:57599];
    reg [191:0] expected_packet[0:38];
    reg [47:0] expected_descriptor[0:38];
    reg [23:0] expected_distance[0:38];
    reg [47:0] observed_descriptor[0:38];
    reg [23:0] observed_distance[0:38];
    integer errors=0,checks=0,scenarios=0,normal_events=0,revoke_events=0;
    integer cycles=0,tick_div=0,last_tag=0,max_post_eof=0,max_fifo=0;
    integer eof_cycle[0:60],wait_cycles=0,before_revoke=0,startup_revokes=0,total_frames=4;
    reg test_done=0,negative=0,full_fps=0,matrix=0,stress=0,saw_overlap=0;
    task ck(input bit value,input string message);
        begin checks++;if(!value)begin errors++;$display("FAIL stream t=%0t %s",$time,message);end end
    endtask
    always @(posedge capture_clk)begin
        cycles++;
        if(rst_n&&dut.scene.capture_active&&dut.scene.state!=0&&
            dut.scene.capture_bank!=dut.scene.process_bank)saw_overlap=1;
        if(dut.scene.fifo_tail>max_fifo)max_fifo=dut.scene.fifo_tail;
        if(matrix&&dut.axis_end&&dut.sc_id>=1&&dut.sc_id<=39)
            observed_descriptor[dut.sc_id-1]={7'd0,dut.bbox_height,dut.bbox_width,dut.ymax,dut.ymin,dut.y_available};
        if(matrix&&dut.shape_event&&dut.shape_id>=1&&dut.shape_id<=39)
            observed_distance[dut.shape_id-1]={2'd0,dut.axis_circle,dut.ellipse};
    end
    always @(posedge display_clk)begin
        tick_1ms<=0;
        if(!rst_n)tick_div<=0;
        else if(tick_div==74999)begin tick_div<=0;tick_1ms<=1;end
        else tick_div<=tick_div+1;
        #1;
        if(rst_n)begin
            if(obs_revoke)begin revoke_events++;$display("REVOKE stream id=%0d cycle=%0d fault=%0d quarantine=%0d",
                obs_frame_id,cycles,link_fault,quarantined);end
            if(obs_event&&obs_healthy&&!obs_revoke&&!stress)begin
                normal_events++;last_tag=obs_frame_id;
                ck(obs_frame_id==normal_events&&obs_source_test==0,"one ordered event per raw capture identity");
                if(matrix)begin
                    ck(obs_frame_id>=1&&obs_frame_id<=39,"matrix event has an expected frozen identity");
                    if(obs_frame_id>=1&&obs_frame_id<=39)begin
                        ck({obs_present,obs_valid,obs_item,obs_count}===
                            {expected_packet[obs_frame_id-1][`R30_PRESENT],
                             expected_packet[obs_frame_id-1][`R30_VALID],
                             expected_packet[obs_frame_id-1][`R30_ITEM],
                             expected_packet[obs_frame_id-1][`R30_COUNT]},
                            "frozen C item and updated three-frame confirmation business outputs");
                        ck(recognition_packet===expected_packet[obs_frame_id-1],
                            $sformatf("all192 bits against frozen C id=%0d actual=%048h expected=%048h",
                                      obs_frame_id,recognition_packet,expected_packet[obs_frame_id-1]));
                        ck(observed_descriptor[obs_frame_id-1]===expected_descriptor[obs_frame_id-1],
                            "actual glyph Y extrema/bbox/availability equal frozen RGB descriptor");
                        ck(observed_distance[obs_frame_id-1]===expected_distance[obs_frame_id-1],
                            "actual axis-circle and full-ellipse scores equal frozen RGB oracle");
                    end
                end else begin
                    ck(obs_present&&obs_count==obs_frame_id&&obs_valid==(obs_frame_id>=3)&&
                        obs_item==(obs_frame_id>=3?1:0),"one filter confirms exactly on third real frame");
                    ck(recognition_packet[`R30_ID]==obs_frame_id&&recognition_packet[`R30_COUNT]==obs_count&&
                        recognition_packet[`R30_ITEM]==obs_item&&recognition_packet[`R30_RAW_ITEM]==1&&
                        recognition_packet[`R30_AVAILABLE]==7&&recognition_packet[`R30_ARBITRATED],
                        "packet confirmation and complete metadata belong to same transaction");
                    ck(recognition_packet[`R30_FOREGROUND]==dut.send_packet[`R30_FOREGROUND],
                        "real matcher foreground preserved in packet");
                end
                if(cycles-eof_cycle[obs_frame_id]>max_post_eof)max_post_eof=cycles-eof_cycle[obs_frame_id];
                ck(cycles-eof_cycle[obs_frame_id]<1200000,"EOF-to-business fits fixed1.2M capture-cycle budget");
            end
        end
    end
    task send_frame(input integer tag,input integer blank);
        reg [23:0] value;
        begin
            @(negedge capture_clk);in_frame_id=tag;in_frame_start=1;
            @(negedge capture_clk);in_frame_start=0;
            for(integer y=0;y<720;y++)begin
                for(integer x=0;x<320;x++)begin
                    value=raster[(y/4)*320+x];in_valid=1;in_eol=x==319;in_rgb96={4{value}};
                    @(negedge capture_clk);
                end
                in_valid=0;in_eol=0;
                if(y==719)begin
                    in_frame_done=1;in_done_id=tag;eof_cycle[tag]=cycles;
                    @(negedge capture_clk);in_frame_done=0;
                end
                repeat(blank)@(negedge capture_clk);
            end
            repeat(8)@(negedge capture_clk);
        end
    endtask
    initial begin
        negative=$test$plusargs("NEGATIVE");full_fps=$test$plusargs("FULL_FPS");matrix=$test$plusargs("MATRIX");
        if(matrix)begin
            total_frames=39;
            $readmemh("matrix.expected.mem",expected_packet);
            $readmemh("matrix.descriptor.mem",expected_descriptor);
            $readmemh("matrix.distance.mem",expected_distance);
        end else $readmemh("c062.rgb.mem",raster);
        repeat(8)@(negedge capture_clk);rst_n=1;repeat(30)@(negedge capture_clk);
        startup_revokes=revoke_events;
        scenarios++;ck(startup_revokes==1,"single startup withdrawal before producer");
`ifdef CHAIN_RENDER
        scenarios++;
        $readmemh("anlogic_logo_index.mem",expected_logo_index);
        $readmemh("anlogic_logo_palette.mem",expected_logo_palette);
        for(integer i=0;i<16384;i++)
            if($isunknown(dut.render.compositor.logo.index_rom[i])||
               dut.render.compositor.logo.index_rom[i]!==expected_logo_index[i])logo_index_equal=0;
        for(integer i=0;i<1024;i++)
            if($isunknown(dut.render.compositor.logo.palette_rom[i])||
               dut.render.compositor.logo.palette_rom[i]!==expected_logo_palette[i])logo_palette_equal=0;
        ck(logo_index_equal,"full pipeline default Logo index loads all16384 actual frozen words");
        ck(logo_palette_equal,"full pipeline default Logo palette loads all1024 actual frozen words");
        @(negedge display_clk);video_frame_start=1;video_de=1;pixel_x=700;pixel_y=400;video_rgb=24'h808080;
        @(negedge display_clk);video_frame_start=0;
        repeat(12)@(negedge display_clk);
        ck(out_de&&out_rgb===24'h808080,"full enabled renderer produces actual unoccluded camera pixel");
        video_de=0;
`endif
        for(integer tag=1;tag<=total_frames;tag++)begin
            if(matrix&&(tag-1)%3==0)begin
                scenarios++;
                $readmemh($sformatf("m%0d.rgb.mem",(tag-1)/3),raster);
            end
            send_frame(tag,full_fps?2076:0);
            if(!full_fps)begin
                wait_cycles=0;
                while(normal_events<tag&&wait_cycles<1200000)begin @(negedge capture_clk);wait_cycles++;end
                ck(normal_events==tag,"drained raw frame completes within fixed budget");
                repeat(20)@(negedge capture_clk);
            end
        end
        wait_cycles=0;
        while(normal_events<total_frames&&wait_cycles<1200000)begin @(negedge capture_clk);wait_cycles++;end
        ck(normal_events==total_frames&&last_tag==total_frames,"all real complete raw captures delivered");
        ck(revoke_events==startup_revokes&&!link_fault&&!quarantined,"supported capture interval has no fault");
        if(matrix)ck(obs_valid&&obs_item==1&&obs_count==3,
                     "three complete frames recover confirmation after unknown/empty/clipped/Y-rejected inputs");
        if(full_fps)ck(saw_overlap&&max_fifo<=7200,"60fps opposite bank overlap and bounded FIFO");
        scenarios++;stress=1;before_revoke=revoke_events;
        for(integer tag=total_frames+1;tag<=total_frames+5;tag++)send_frame(tag,0);
        repeat(200)@(negedge display_clk);
        ck(revoke_events>before_revoke&&!obs_valid,"overspeed explicitly withdraws previously confirmed class");
        scenarios++;@(negedge capture_clk);in_revoke=1;
        repeat(10)@(negedge capture_clk);in_revoke=0;
        repeat(30)@(negedge display_clk);ck(!obs_valid,"capture revoke crosses safety clear path");
        if(negative)ck(obs_valid,"intentional checker negative");
        test_done=1;
        $display("METRICS stream events=%0d revokes=%0d max_post_eof=%0d max_fifo=%0d overlap=%0d full_fps=%0d",
            normal_events,revoke_events,max_post_eof,max_fifo,saw_overlap,full_fps);
        $display("RESULT chain_stream errors=%0d checks=%0d scenarios=%0d done=%0d",errors,checks,scenarios,test_done);
        $finish;
    end
    initial begin #(64'd1000000000);$display("WATCHDOG chain_stream");$finish;end
endmodule
