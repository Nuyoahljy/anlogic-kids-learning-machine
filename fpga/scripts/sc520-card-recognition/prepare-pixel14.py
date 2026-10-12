"""Prepare a small TD overlay; vendor/IP files remain referenced in the sealed old project."""
from pathlib import Path
import argparse, datetime, hashlib, json, re, shutil, xml.etree.ElementTree as ET

REPO=Path(__file__).resolve().parents[3]
OLD=REPO.parent/'sc520-fixed-roi/fpga/custom_project/sc520-board-keys'
PROJECT=REPO/'fpga/custom_project/sc520-pixel14'
RTL=REPO/'fpga/rtl/sc520-card-recognition'

def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def save(p,v):
    p.parent.mkdir(parents=True,exist_ok=True)
    p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def write(p,s):
    p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s,encoding='utf-8')
def once(s,a,b):
    assert s.count(a)==1,(a,s.count(a));return s.replace(a,b)

INTEGRATION='''
    // Real acquisition provenance is independent of DDR/display refresh.
    wire S_p14_start,S_p14_done,S_p14_good,S_p14_revoke;
    wire [31:0] S_p14_id,S_p14_done_id;
    reg [1:0] S_p14_cfg_done,S_p14_cfg_error;
    always @(posedge S_csi_rx_clk or negedge S_rst_n)
        if(!S_rst_n) begin S_p14_cfg_done<=0;S_p14_cfg_error<=0;end
        else begin
            S_p14_cfg_done<={S_p14_cfg_done[0],S_cam_cfg_done};
            S_p14_cfg_error<={S_p14_cfg_error[0],S_cam_i2c_error};
        end
    pixel14_capture_provenance u_p14_provenance(
        .clk(S_csi_rx_clk),.rst_n(S_rst_n),.csi_sof(S_csi_frame_start),.csi_eof(S_csi_frame_end),
        .csi_length(S_csi_data_length),.csi_valid(S_csi_valid),.hs_valid(S_hs_rx_valid),
        .lane_error(S_lane_error_any),.raw_sof(S_raw10_frame_start),.raw_eof(S_raw10_frame_end),
        .raw_valid(S_raw10_valid),.isp_sof(S_p14_rgb_sof),.isp_valid(S_p14_rgb_valid),.isp_eol(S_p14_rgb_eol),
        .cfg_done(S_p14_cfg_done[1]),.cfg_error(S_p14_cfg_error[1]),
        .frame_start(S_p14_start),.frame_id(S_p14_id),.frame_done(S_p14_done),
        .frame_good(S_p14_good),.done_id(S_p14_done_id),.revoke(S_p14_revoke));

    wire S_p14_tick;
    quiz_millisecond_tick #(.CLOCK_HZ(75000000)) u_p14_tick(
        .clk(S_hdmi_pixel_clk),.rst_n(S_hdmi_rst_n),.tick_1ms(S_p14_tick));
    reg S_p14_vs_d,S_p14_de_d,S_p14_pending;
    reg [10:0] S_p14_next_x;
    reg [9:0] S_p14_next_y;
    wire S_p14_display_sof=S_hdmi_out_vsync && !S_p14_vs_d;
    wire [10:0] S_p14_x=S_p14_pending ? 11'd0 : S_p14_next_x;
    wire [9:0] S_p14_y=S_p14_pending ? 10'd0 : S_p14_next_y;
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n)
        if(!S_hdmi_rst_n) begin
            S_p14_vs_d<=0;S_p14_de_d<=0;S_p14_pending<=1;S_p14_next_x<=0;S_p14_next_y<=0;
        end else begin
            S_p14_vs_d<=S_hdmi_out_vsync;S_p14_de_d<=S_hdmi_out_de;
            if(S_p14_display_sof) begin S_p14_pending<=1;S_p14_next_x<=0;S_p14_next_y<=0;end
            else if(S_hdmi_out_de) begin
                S_p14_pending<=0;
                if(S_p14_x==1279)begin S_p14_next_x<=0;S_p14_next_y<=S_p14_y+1'b1;end
                else S_p14_next_x<=S_p14_x+1'b1;
            end
        end
    pixel14_pipeline #(.ENABLE_OUTPUT(1),.TEMPLATE_FILE("PIXEL14_TEMPLATE_FILE")) u_p14_pipeline(
        .rst_n(S_rst_n && S_hdmi_rst_n),.capture_clk(S_csi_rx_clk),.display_clk(S_hdmi_pixel_clk),
        .in_frame_start(S_p14_start),.in_frame_id(S_p14_id),.in_source_test(1'b0),
        .in_valid(S_p14_rgb_valid),.in_eol(S_p14_rgb_eol),.in_rgb96(S_p14_rgb_data),
        .in_frame_done(S_p14_done),.in_frame_good(S_p14_good),.in_done_id(S_p14_done_id),
        .in_done_source_test(1'b0),.in_revoke(S_p14_revoke),.tick_1ms(S_p14_tick),.flush(1'b0),
        .key_mode_pulse(S_quiz_key_mode),.key_replay_pulse(S_quiz_key_replay),
        .key_skip_pulse(S_quiz_key_skip),.key_reset_pulse(S_quiz_key_reset),
        .audio_idle(1'b1),.audio_fault(1'b0),
        .video_frame_start(S_p14_display_sof),.pixel_x(S_p14_x),.pixel_y(S_p14_y),
        .video_vsync(S_hdmi_out_vsync),.video_hsync(S_hdmi_out_hsync),.video_de(S_hdmi_out_de),
        .video_rgb(S_hdmi_out_data),.out_vsync(S_roi_vsync),.out_hsync(S_roi_hsync),
        .out_de(S_roi_de),.out_rgb(S_roi_data));
'''

def create_overlay():
    assert not PROJECT.exists(),'Refuse to overwrite existing overlay; edit its owned files directly'
    top=(OLD/'user_source/hdl_source/design_top_wrapper.v').read_text(encoding='utf-8-sig')
    top=once(top,'isp_top u_isp_top (','wire [95:0] S_p14_rgb_data;\nwire S_p14_rgb_sof,S_p14_rgb_eol,S_p14_rgb_valid;\nisp_top u_isp_top (')
    top=once(top,'.O_tdata         (S_ISP_O_tdata ),','.O_tdata         (S_ISP_O_tdata ),\n.O_rgb96_data(S_p14_rgb_data),.O_rgb96_sof(S_p14_rgb_sof),\n.O_rgb96_eol(S_p14_rgb_eol),.O_rgb96_valid(S_p14_rgb_valid),')
    start=top.index('    hdmi_quiz #(');end=top.index('    hdmi_tx u_hdmi_tx(',start)
    template=(REPO/'assets/templates/sc520-card-recognition/prep-v1-max40/templates.mem').as_posix()
    top=top[:start]+INTEGRATION.replace('PIXEL14_TEMPLATE_FILE',template)+'\n'+top[end:]
    write(PROJECT/'overlay/design_top_wrapper.v',top)
    isp=(OLD/'user_source/hdl_source/isp/isp_top.v').read_text(encoding='utf-8-sig')
    isp=once(isp,'module isp_top (','module isp_top (\n    output wire [95:0] O_rgb96_data,\n    output wire O_rgb96_sof,O_rgb96_eol,O_rgb96_valid,')
    isp=once(isp,'  assign awb_O_tready = O_tready;','  assign O_rgb96_data=awb_O_tdata;\n  assign O_rgb96_sof=awb_O_tuser;\n  assign O_rgb96_eol=awb_O_tlast;\n  assign O_rgb96_valid=awb_O_tvalid;\n  assign awb_O_tready = O_tready;')
    write(PROJECT/'overlay/isp_top.v',isp)
    shutil.copyfile(OLD/'user_source/constraints_source/pin.adc',PROJECT/'overlay/pin.adc')
    shutil.copyfile(OLD/'td_project/camera_to_dsi_display.sdc',PROJECT/'overlay/pixel14.sdc')

def make(destination,snapshot=False):
    destination=destination.resolve()
    sources=sorted((RTL/'pixel14').glob('*.v'))+sorted((RTL/'items14').glob('*.v'))+[RTL/n for n in ('card_template_rom.v','card_result_filter.v')]
    mapping={}
    records=[]
    if snapshot:
        for name in ('prepare-pixel14.py','build-pixel14.ps1'):
            p=Path(__file__).with_name(name);q=destination/'tools'/name
            q.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,q)
            records.append({'Path':str(p),'Snapshot':str(q),'SHA256':sha(p)})
        for p in sources:
            q=destination/'rtl'/p.name;q.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,q)
            mapping[p.resolve()]=q;records.append({'Path':str(p),'Snapshot':str(q),'SHA256':sha(p)})
        for p in (PROJECT/'overlay').glob('*'):
            q=destination/'overlay'/p.name;q.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(p,q)
            records.append({'Path':str(p),'Snapshot':str(q),'SHA256':sha(p)})
    else: mapping={p.resolve():p.resolve() for p in sources}
    overlay=destination/'overlay'
    template=REPO/'assets/templates/sc520-card-recognition/prep-v1-max40/templates.mem'
    if snapshot:
        target=destination/'templates.mem';shutil.copyfile(template,target)
        records.append({'Path':str(template),'Snapshot':str(target),'SHA256':sha(template)})
        template=target
        p=overlay/'design_top_wrapper.v'
        original_template=(REPO/'assets/templates/sc520-card-recognition/prep-v1-max40/templates.mem').as_posix()
        write(p,p.read_text(encoding='utf-8').replace(original_template,template.as_posix()))
    replacement={
        (OLD/'user_source/hdl_source/design_top_wrapper.v').resolve():overlay/'design_top_wrapper.v',
        (OLD/'user_source/hdl_source/isp/isp_top.v').resolve():overlay/'isp_top.v',
        (OLD/'user_source/constraints_source/pin.adc').resolve():overlay/'pin.adc',
        (OLD/'td_project/camera_to_dsi_display.sdc').resolve():overlay/'pixel14.sdc'}
    refs=set()
    def xml(source,target):
        # TD writes a proprietary XML-like dialect with bare '&' and '::'.
        raw=source.read_text(encoding='utf-8-sig').replace('&','&amp;').replace('::','__TD_COLON__')
        root=ET.fromstring(raw);tree=ET.ElementTree(root)
        for group in root.find('Source_Files'):
            for file in list(group):
                original=(source.parent/file.attrib['Path']).resolve()
                rel=original.relative_to(OLD).as_posix()
                if any('/'+d+'/' in '/'+rel for d in ('roi','learning','quiz')) and original.name not in ('quiz_key_inputs.v','quiz_millisecond_tick.v'):
                    group.remove(file);continue
                resolved=replacement.get(original,original)
                assert resolved.is_file(),resolved
                file.attrib['Path']=resolved.as_posix();refs.add(resolved)
        group=root.find('Source_Files/Verilog')
        for i,p in enumerate(sources):
            p=mapping[p.resolve()];refs.add(p)
            el=ET.SubElement(group,'File',{'Path':p.as_posix()});info=ET.SubElement(el,'FileInfo')
            for k,v in [('UsedInSyn','true'),('UsedInP&R','true'),('BelongTo','design_1'),('CompileOrder',str(200+i))]:ET.SubElement(info,'Attr',{'Name':k,'Val':v})
        ET.indent(tree)
        write(target,ET.tostring(root,encoding='unicode').replace('&amp;','&').replace('__TD_COLON__','::'))
    xml(OLD/'td_project/camera_to_dsi_display.al',destination/'td_project/camera_to_dsi_display.al')
    for stage in ('syn_1','phy_1'):
        oldrun=OLD/f'td_project/camera_to_dsi_display_Runs/{stage}'
        run=destination/f'td_project/camera_to_dsi_display_Runs/{stage}'
        xml(oldrun/'camera_to_dsi_display.prj',run/'camera_to_dsi_display.prj')
        settings=(oldrun/'settings.cfg').read_text(encoding='utf-8-sig')
        settings=settings.replace('../../../user_source/constraints_source/pin.adc',(overlay/'pin.adc').as_posix())
        settings=settings.replace('../../camera_to_dsi_display.sdc',(overlay/'pixel14.sdc').as_posix())
        settings=settings.replace('../../../user_source/',(OLD/'user_source').as_posix()+'/')
        write(run/'settings.cfg',settings)
        shutil.copyfile(oldrun/'camera_to_dsi_display.tcl',run/'camera_to_dsi_display.tcl')
    # Include collateral IP netlists, include files and ADC/SDC inputs in hashes.
    external=set(refs)
    for base in (OLD/'user_source',OLD/'td_project/al_ip'):
        external.update(p for p in base.rglob('*') if p.is_file() and p.suffix.lower() not in ('.bit','.db','.log','.wlf'))
    for p in sorted(external):
        records.append({'Path':str(p),'SHA256':sha(p)})
    for r in records:
        if 'Snapshot' in r:r['SnapshotSHA256']=sha(r['Snapshot'])
    result={'CreatedAt':datetime.datetime.now().astimezone().isoformat(),'Owner':'SC520 recovery /root/build_impl',
        'SourceProject':str(OLD),'Project':str(destination),'Snapshot':snapshot,'Files':records,
        'ManifestSources':[str(p) for p in sorted(refs)],'HardwareValidated':False}
    save(destination/'inputs.json',result)
    print(f'PIXEL14_PREPARED project={destination} refs={len(refs)} hashes={len(records)}')

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--snapshot',type=Path);args=ap.parse_args()
    if args.snapshot:
        assert PROJECT.exists();args.snapshot.mkdir(parents=True,exist_ok=False);make(args.snapshot,True)
    else:
        if not PROJECT.exists():create_overlay()
        make(PROJECT)
