"""Derive an independent T026 candidate without editing historical T023 inputs."""
from pathlib import Path
import hashlib,json,re
R=Path(__file__).resolve().parents[3]
P=R/'fpga/custom_project/sc520-color26'
OLD=R/'fpga/custom_project/sc520-timing23'
RTL=R/'fpga/rtl/sc520-color-integration'
def put(p,s):
    p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s,encoding='utf-8',newline='\n')
def once(s,a,b):
    assert s.count(a)==1,(a,s.count(a));return s.replace(a,b)
assert not P.exists() and not RTL.exists()
for p in (OLD/'overlay').iterdir():
    s=p.read_text(encoding='utf-8')
    if p.name=='design_top_wrapper.v':
        s=s.replace('T022 hardware-default','T026 hardware-default')
        s=once(s,'    input wire I_audio_rx,I_audio_busy,\n    output wire O_audio_tx,\n','')
        s=once(s,'.uart_rx(I_audio_rx),.busy_async(I_audio_busy),.uart_tx(O_audio_tx)',".uart_rx(1'b1),.busy_async(1'b0),.uart_tx()")
        s=s.replace('ae_set u_ae_set','pixel26_fixed_exposure u_ae_set').replace('pixel23_pipeline #','pixel26_pipeline #').replace('pixel23_compositor #','pixel26_compositor #').replace("16'h0220","16'h0260")
        s=s.replace('E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-card-recognition/',R.as_posix()+'/')
    elif p.name=='isp_top.v':s=s.replace('pixel14_color_pipeline #','pixel26_color_pipeline #')
    elif p.name=='pixel14_color_pipeline.v':
        s=s.replace('module pixel14_color_pipeline','module pixel26_color_pipeline')
        s=once(s,'reg [8:0] gain_r,gain_b,next_gain_r,next_gain_b;','wire [8:0] gain_r=9\'d304,gain_b=9\'d333;\n    reg [8:0] next_gain_r,next_gain_b;')
        s=once(s,'gain_r<=256;gain_b<=256;next_gain_r<=256;next_gain_b<=256;','next_gain_r<=304;next_gain_b<=333;')
        s=once(s,'gain_r<=next_gain_r;gain_b<=next_gain_b;','// Fixed field WB; neutral statistics never change gains.')
        s='// T026: fixed Q8 WB 304/256/333, stage2 tone1. Original 54-cycle path.\n'+s
    elif p.name=='pin.adc':
        s='\n'.join(x for x in s.splitlines() if not any(t in x for t in ('O_audio_tx','I_audio_rx','I_audio_busy','TEST ONLY')))+'\n'
    elif p.name=='pixel14.sdc':
        s='\n'.join(x for x in s.splitlines() if not any(t in x for t in ('I_audio_rx','I_audio_busy','u_a22_audio/bridge/player/link/rx_','u_a22_audio/bridge/player/core/busy_')))+'\n'
    elif p.name=='report-pixel14-cdc.tcl':
        start=s.index('foreach pair {{{u_a22_audio/bridge/player/link/rx_meta}')
        end=s.index('set audio_regs',start)
        s=s[:start]+s[start:end].replace('{{{u_a22_audio/bridge/player/link/rx_meta} {u_a22_audio/bridge/player/link/rx_sync} audio-rx} {{u_a22_audio/bridge/player/core/busy_meta} {u_a22_audio/bridge/player/core/busy_safe} audio-busy} ', '{')+s[end:]
        s=s.replace('if {[llength $audio_regs]<100} {error "Active audio path unexpectedly optimized away"}','# Hardware profile is unconfigured; constant RX/BUSY are not asynchronous inputs.')
    put(P/'overlay'/p.name,s)
for source,target in [('pixel14/block_frame_recognizer.v','pixel26_block_recognizer.v'),('timing23/pixel23_pipeline.v','pixel26_pipeline.v'),('timing23/pixel23_compositor.v','pixel26_compositor.v'),('display17/sc520_processing_display.v','pixel26_processing_display.v')]:
    s=(R/'fpga/rtl/sc520-card-recognition'/source).read_text(encoding='utf-8')
    for a,b in [('block_frame_recognizer','pixel26_block_recognizer'),('pixel23_pipeline','pixel26_pipeline'),('pixel23_compositor','pixel26_compositor'),('sc520_processing_display','pixel26_processing_display'),('sc520_color_classify','pixel26_color_classify')]:s=s.replace(a,b)
    if target=='pixel26_block_recognizer.v':
        start=s.index('    wire [8:0] r=');end=s.index('    wire start_ok=',start)
        s=s[:start]+'''    wire roi=in_x>=X_MIN && in_x<=X_MAX && in_y>=Y_MIN && in_y<=Y_MAX;
    wire [1:0] color;
    pixel26_color_classify classify(.in_rgb(in_rgb),.color_id(color));
'''+s[end:]
    if target=='pixel26_processing_display.v':
        s=once(s,'    wire [23:0] segmented_rgb', '''    wire [23:0] enhanced_rgb;
    pixel26_saturation enhance(.in_rgb(in_rgb),.out_rgb(enhanced_rgb));
    wire [23:0] segmented_rgb''')
        s=once(s,'? segmented_rgb : in_rgb;','? segmented_rgb : enhanced_rgb;')
    if target=='pixel26_compositor.v':s=s.replace("16'h0220","16'h0260")
    put(RTL/target,s)
put(P/'.gitattributes','* -text\n')
put(RTL/'.gitattributes','* -text\n')
print('T026_INDEPENDENT_SOURCES_CREATED')
