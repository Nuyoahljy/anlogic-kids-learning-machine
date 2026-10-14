"""Independent TD6.2.1 placement/routing probe at9.660ns; no bitgen/board."""
from pathlib import Path
import datetime,hashlib,json,re,shutil,subprocess,uuid,xml.etree.ElementTree as ET
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2]
OLD=ROOT.parent/'sc520-fixed-roi/fpga/custom_project/sc520-board-keys/user_source'
TD=Path('D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe')
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def save(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def main():
    run=HERE/'color-timing'/('probe-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S')+'-'+uuid.uuid4().hex[:6]);run.mkdir(parents=True)
    sources=[ROOT/'fpga/custom_project/sc520-pixel14/overlay/pixel14_color_pipeline.v',OLD/'hdl_source/signal_delay.v',
       OLD/'ip_source/blk_mem_gen_awb_delay_signal/blk_mem_gen_awb_delay_signal.v',OLD/'ip_source/blk_mem_gen_awb_delay_signal/ram_f84573da5ab5.v']
    inputs=[]
    for p in sources:
        q=run/p.name;shutil.copyfile(p,q);inputs.append({'Path':str(p),'Snapshot':str(q),'SHA256':sha(p),'SnapshotSHA256':sha(q)})
    top='''module color_timing_top(input wire clk,rst_n,sof,eol,valid,input wire [7:0] pixel_byte,
output reg [7:0] observe,output wire o_valid,o_sof,o_eol);
reg [95:0] pixels;
always @(posedge clk) pixels<={pixels[87:0],pixel_byte};
wire [95:0] rgb;
pixel14_color_pipeline u_color(.I_clk(clk),.I_rst_n(rst_n),.I_tlast(eol),.I_tuser(sof),.I_tdata(pixels),.I_tvalid(valid),
.I_tready(),.O_tlast(o_eol),.O_tuser(o_sof),.O_tdata(rgb),.O_tvalid(o_valid),.O_tready(1'b1));
always @(posedge clk) observe<=rgb[95:88]^rgb[87:80]^rgb[79:72]^rgb[71:64]^rgb[63:56]^rgb[55:48]^
rgb[47:40]^rgb[39:32]^rgb[31:24]^rgb[23:16]^rgb[15:8]^rgb[7:0];
endmodule
'''
    (run/'color_timing_top.v').write_text(top)
    baseline=ROOT/'evidence/sc520-card-recognition/builds/6a50b111/td_project/camera_to_dsi_display_Runs/syn_1'
    raw=(baseline/'camera_to_dsi_display.prj').read_text(encoding='utf-8-sig').replace('camera_to_dsi_display','color_timing').replace('design_top_wrapper','color_timing_top')
    tree=ET.fromstring(raw.replace('&','&amp;').replace('::','__COLON__'))
    src=tree.find('Source_Files');src.clear();verilog=ET.SubElement(src,'Verilog')
    for i,p in enumerate([run/'color_timing_top.v',*[run/x.name for x in sources]]):
        file=ET.SubElement(verilog,'File',{'Path':p.as_posix()});info=ET.SubElement(file,'FileInfo')
        for key,value in [('UsedInSyn','true'),('UsedInP&R','true'),('BelongTo','design_1'),('CompileOrder',str(i+1))]:ET.SubElement(info,'Attr',{'Name':key,'Val':value})
    ET.indent(tree);(run/'color_timing.prj').write_text(ET.tostring(tree,encoding='unicode').replace('&amp;','&').replace('__COLON__','::'))
    (run/'color.sdc').write_text('create_clock -name CORE_CLK -period 9.660 [get_ports clk]\nset_input_delay -clock CORE_CLK 0.000 [get_ports {pixel_byte* sof eol valid rst_n}]\nset_output_delay -clock CORE_CLK 0.000 [all_outputs]\n')
    shutil.copyfile(baseline/'camera_to_dsi_display.tcl',run/'flow.tcl')
    settings=f'''set ADCList {{}}
set SDCList {{{{color.sdc}}}}
set IpADCList {{}}
set IpSDCList {{}}
set area_option -packarea
set device_name ph1_35p.db
set package_name PH1P35MDG324
set prj_name color_timing
set top_model_name color_timing_top
set start_step read_design
set end_step opt_route
set speed 3
set parent .
set run_type phy
set arr_filter false
set arr_pwns 0
set arr_rwns 0
set arr_cong 100
set drHoldFix off
'''
    (run/'settings.cfg').write_text(settings)
    (run/'launch.tcl').write_text('if {[catch {source settings.cfg; source flow.tcl; report_timing_path -ep_num 30 -path_num 1 -file paths.rpt; write_verilog routed.v} msg]} {puts stderr $msg;exit 1}\nputs "COLOR_TIMING_DONE"\nexit 0\n')
    save(run/'inputs.json',{'Inputs':inputs,'Tool':{'Path':str(TD),'SHA256':sha(TD)},'Scope':'Isolated color core with registered serial pixel source and XOR observation,9.660ns, no bitgen. Full integration placement remains separate.'})
    drive=next(d+':' for d in ['U','T','S','R','Q'] if not Path(d+':/').exists())
    subprocess.run(['subst.exe',drive,str(run)],check=True)
    try:
        with (run/'stdout.log').open('wb') as out,(run/'stderr.log').open('wb') as err:
            result=subprocess.run([str(TD),drive+'/launch.tcl'],cwd=drive+'/',stdout=out,stderr=err,creationflags=subprocess.CREATE_NO_WINDOW,timeout=300)
    finally:subprocess.run(['subst.exe',drive,'/d'],check=True)
    timing=(run/'color_timing_pr.timing').read_text(errors='replace') if (run/'color_timing_pr.timing').exists() else ''
    metrics={k:float(re.search(r'\b'+k+r':\s*(-?[0-9.]+)ns',timing)[1]) for k in ['SWNS','STNS','HWNS','HTNS']} if timing else {}
    unchanged=all(sha(x['Path'])==x['SHA256']==sha(x['Snapshot']) for x in inputs)
    report={'NativeExit':result.returncode,'TimingNs':metrics,'InputsUnchanged':unchanged,'Qualified':result.returncode==0 and unchanged and metrics.get('SWNS',-1)>=0 and metrics.get('HWNS',-1)>=0,
       'HardwareValidated':False,'BitGenerated':False,'Scope':'Isolated color-core routed timing, not full111/112 qualification.'}
    report['Artifacts']=[{'Path':str(p),'SHA256':sha(p)} for p in sorted(run.iterdir()) if p.is_file() and p.suffix not in ['.db']]
    save(run/'timing-audit.json',report);print(json.dumps({'Run':str(run),**{k:v for k,v in report.items() if k!='Artifacts'}}))
    return 0 if report['Qualified'] else 1
if __name__=='__main__':raise SystemExit(main())
