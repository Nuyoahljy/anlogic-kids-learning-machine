"""Bind proven independent oracles to new DUTs and add reset/CDC boundary tests."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3];HERE=Path(__file__).resolve().parent
SIM=ROOT/'fpga/sim/sc520-card-recognition'
def read(p):return p.read_text(encoding='utf-8-sig')
def write(p,s):
    assert not p.exists(),p
    p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s,encoding='utf-8')
for test in ['render','pipeline','business','default']:
    s=read(SIM/f'audio22/tb_audio22_{test}.sv').replace('tb_audio22_','tb_timing23_')
    s=s.replace('pixel22_compositor','pixel23_compositor').replace('pixel14_pipeline #','pixel23_pipeline #')
    write(SIM/f'timing23/tb_timing23_{test}.sv',s)
s=read(SIM/'tb_pixel14_observation_system.sv').replace('tb_pixel14_observation_system','tb_timing23_reset')
s=s.replace('module tb_timing23_reset;', 'module tb_timing23_reset;\n  real release_phase=0.73;')
s=s.replace('pixel14_pipeline #','pixel23_pipeline #')
s=s.replace('repeat(8)@(negedge capture_clk);rst_n=1;settle;',
    'repeat(8)@(negedge capture_clk);#(release_phase);rst_n=1;settle;')
a=s.index('  initial begin\n    unused=');b=s.index('  initial begin #500000000;',a)
s=s[:a]+'''  reg [1:0] expected_release=0;
  reg busy_old=0,color_busy_old=0,request_old=0,color_request_old=0;
  reg [131:0] held_old=0;
  reg [799:0] color_held_old=0;
  integer reset_edges=0,payload_checks=0;
  always @(negedge rst_n)begin
    #0.01;
    ck(dut.capture_reset===0 && dut.capture_release===0,"all capture reset branches assert asynchronously");
    ck(dut.color_observation.observer.joiner.out_packet===0,"observation packet clears without waiting for a clock");
  end
  always @(posedge capture_clk or negedge rst_n)
    if(!rst_n)expected_release<=0;else expected_release<={expected_release[0],1'b1};
  always @(posedge capture_clk)begin
    #0.02;
    if(rst_n)begin
      if(inject_fault && !injected && expected_release[1])begin
        force dut.capture_release[8]=0;injected=1;#0.01;
        ck(dut.capture_release[8]===expected_release[1],"live reset-release corruption is detected");
        release dut.capture_release[8];test_done=1;$fclose(fd);$finish;
      end
      ck(dut.crst===expected_release[1] && dut.capture_release==={9{expected_release[1]}},
         "all ten capture second stages release together at original second edge");
      reset_edges++;
    end
  end
  always @(posedge capture_clk)begin
    #1.1;
    if(!rst_n)begin busy_old=0;color_busy_old=0;end
    else begin
      if(busy_old && request_old===dut.forward.request)begin
        ck(dut.forward.held_data===held_old,"business payload stable throughout outstanding handshake");payload_checks++;
      end
      if(color_busy_old && color_request_old===dut.color_observation.transport.link.request)begin
        ck(dut.color_observation.transport.link.held_data===color_held_old,"800-bit observation payload stable throughout outstanding handshake");payload_checks++;
      end
      busy_old=dut.forward.request!=dut.forward.ack_sync;
      color_busy_old=dut.color_observation.transport.link.request!=dut.color_observation.transport.link.ack_sync;
      request_old=dut.forward.request;color_request_old=dut.color_observation.transport.link.request;
      held_old=dut.forward.held_data;color_held_old=dut.color_observation.transport.link.held_data;
    end
  end
  initial begin
    unused=$value$plusargs("INJECT_FAULT=%d",inject_fault);
    if(!$value$plusargs("ASSET_ROOT=%s",root_path))$fatal(1,"ASSET_ROOT required");
    fd=$fopen("observations.csv","w");
    $fwrite(fd,"tag,kind,input_groups,output_groups,output_lines,latency_clocks,gain_r,gain_b,neutral_samples,item,stable_count,score,answers,post_eof_wait_clocks\\n");
    begin_case("phase0.73 reset and first complete720p four-lane frame");
    reset_all;frame(0,-1);
    begin_case("phase2.17 asynchronous reassertion,first good frame and same-cycle branch release");
    release_phase=2.17;reset_all;frame(2,921600);
    begin_case("phase4.41 release,first good frame and complete source-tag payload");
    release_phase=4.41;reset_all;frame(2,921600);
    begin_case("bad external EOF revokes prior observation,then fresh full-frame recovery");
    prior_answers=revoke_events;tag++;in_frame_id=tag;
    drive(1,0,0,0);drive(0,0,0,0);repeat(8)drive(0,0,0,0);
    for(i=0;i<20;i++)drive(0,1,0,{4{24'ha5a5a5}});
    repeat(100)drive(0,0,0,0);
    in_done_id=tag;in_frame_good=0;in_frame_done=1;
    @(negedge capture_clk);in_frame_done=0;in_frame_good=1;settle;
    ck(revoke_events>prior_answers && !obs_valid,"truncated bad frame cannot retain valid recognition");
    ck(!color_diag_fresh || !color_diag_packet[780],"bad frame cannot retain a trusted observation");
    clear_epoch;frame(2,921600);
    begin_case("metadata mismatch is incomplete,subsequent frame restores identity");
    metadata_fault=1;frame(2,921600);metadata_fault=0;frame(2,921600);
    begin_case("stopped capture expires both recognition and diagnostic validity");
    @(negedge capture_clk);cap_run=0;
    repeat(5)begin @(negedge display_clk);tick_1ms=1;@(negedge display_clk);tick_1ms=0;end
    repeat(8)@(negedge display_clk);ck(!color_diag_fresh && timed_out,"stopped source expires independently");
    begin_case("asynchronous reset while capture stopped clears all branches and payload");
    #2.31;rst_n=0;#0.1;
    ck(dut.capture_release===0 && dut.forward.held_data===0 && dut.color_observation.transport.link.held_data===0,
       "reset assertion does not require a running capture clock");
    cap_run=1;release_phase=1.39;reset_all;frame(2,921600);
    ck(payload_checks>20 && reset_edges>1000000,"meaningful reset-edge and busy-payload coverage");
    $fclose(fd);test_done=1;
    $display("DONE timing23-reset scenarios=%0d frames=%0d checks=%0d reset_edges=%0d payload_checks=%0d errors=%0d",scenarios,frames_sent,checks,reset_edges,payload_checks,errors);$finish;
  end
''' +s[b:]
write(SIM/'timing23/tb_timing23_reset.sv',s)
s=read(HERE/'simulate-audio22.py').replace("choices=('business','render','pipeline')","choices=('render','pipeline','reset','business','default')")
s=s.replace("if args.test in ('business','pipeline'):", "if args.test in ('business','pipeline','default'):")
s=s.replace("    top='tb_audio22_'+args.test", "    rtl+=sorted((base/'timing23').glob('*.v'))\n    top='tb_timing23_'+args.test")
s=s.replace("if args.test=='pipeline':rtl+=","if args.test in ('pipeline','reset'):rtl+=")
s=s.replace("tb=REPO/'fpga/sim/sc520-card-recognition/audio22'", "tb=REPO/'fpga/sim/sc520-card-recognition/timing23'")
s=s.replace("    top='tb_timing23_'+args.test", "    if args.test=='reset':rtl += [REPO/'fpga/custom_project/sc520-timing23/overlay/pixel14_color_pipeline.v', REPO.parent/'sc520-fixed-roi/fpga/custom_project/sc520-board-keys/user_source/hdl_source/signal_delay.v', REPO/'evidence/sc520-card-recognition/imaging-audit/ip_behavioral_models.sv']\n    top='tb_timing23_'+args.test")
s=s.replace("if args.test=='pipeline':references+=", "if args.test in ('pipeline','reset'):references+=")
s=s.replace('f"audio22-{args.test}', 'f"timing23-{args.test}')
s=s.replace('01a14030-32d9-78f2-b274-91a370cc9ff0 /root T022','01a144c7-e802-7272-a29d-a8159f5ec84b /root T023')
s=s.replace('"Scope": "T022', '"Scope": "T023 reset partition and coordinate pipeline; T022')
write(HERE/'simulate-timing23.py',s)
print('Created three T023 testbenches and snapshot runner')
