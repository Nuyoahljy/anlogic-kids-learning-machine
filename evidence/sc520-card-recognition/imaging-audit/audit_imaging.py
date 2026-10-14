"""Bind the imaging audit to baseline sources, current candidate and exact runs."""
from pathlib import Path
import csv, datetime, hashlib, json, math, re
HERE=Path(__file__).resolve().parent
REPO=HERE.parents[2]
BASE=REPO/'evidence/sc520-card-recognition/builds/6a50b10a'
OLD=REPO.parent/'sc520-fixed-roi/fpga/custom_project/sc520-board-keys/user_source/hdl_source'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def save(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def info(p):return {'path':str(p),'sha256':sha(p),'bytes':p.stat().st_size}
def main():
    baseline=json.loads((BASE/'inputs.json').read_text())
    paths=[OLD/'uiisp_beta/ae_set.v',OLD/'uics520_cfg/uics520reg_720p60.v',OLD/'uics520_cfg/SC520GainTbl.v',
      OLD/'uics520_cfg/uics520regAE.v',OLD/'isp/raw10_unpacket_2lane.v',OLD/'isp/demosaic_4x_2_0/mipi_to_raw_converter.v',
      OLD/'isp/demosaic_4x_2_0/demosaic.v',OLD/'isp/demosaic_4x_2_0/bilinear_interpolation.v',OLD/'isp/data128_96/data128_96.v',
      OLD/'awb.v',OLD/'signal_delay.v',OLD/'data_96bit_to_128bit.v',OLD/'video_in.v',OLD/'video_out.v',OLD/'hdmi_tx.v',
      OLD.parent/'ip_source/divider/divider.ipc']
    entries=[]
    for p in paths:
        matches=[x for x in baseline['Files'] if Path(x['Path']).resolve()==p.resolve()]
        assert matches, p
        assert all(x['SHA256']==sha(p) for x in matches),p
        entries.append(info(p)|{'matches_0109_build_hash':True})
    snapshots=[]
    for name in ('isp_top.v','design_top_wrapper.v','uicfgcs520.v'):
        matches=[x for x in baseline['Files'] if Path(x['Path']).name==name and 'Snapshot' in x]
        assert len(matches)==1,(name,len(matches))
        p=Path(matches[0]['Snapshot']);assert sha(p)==matches[0]['SnapshotSHA256']
        snapshots.append(info(p)|{'source_path':matches[0]['Path'],'source_sha256':matches[0]['SHA256'],
            'snapshot_sha256':matches[0]['SnapshotSHA256'],'note':'Build preparation remaps template paths in top-level snapshot; validate its separately recorded snapshot hash.'})
    runs=['normal-20261014-102256-5d04a3','normal-720p-20261014-102256-ba6849',
          'negative-20261014-102333-ce70a4','watchdog-20261014-102333-73814b']
    results=[]
    for name in runs:
        p=HERE/'runs'/name/'run-manifest.json';d=json.loads(p.read_text())
        assert d['qualified'],name
        for x in d['inputs']:
            assert x['sha256_before']==x['sha256_after']==x['snapshot_sha256']==sha(x['snapshot'])==sha(x['path']),(name,x['path'])
        for x in d['outputs']:assert x['sha256']==sha(x['path']),(name,x['path'])
        results.append(info(p)|{'native_exit':d['native_exit'],'summary':d['summary'],'inputs':len(d['inputs']),'outputs':len(d['outputs'])})
    knots=[0,37,60,79,97,113,129,143,157,171,184,197,209,221,233,244,255]
    curve=[255 if v==255 else knots[v//16]+((knots[v//16+1]-knots[v//16])*(v%16)+8)//16 for v in range(256)]
    assert curve[0]==0 and curve[-1]==255 and all(b>=a for a,b in zip(curve,curve[1:]))
    rows=[]
    for v,out in enumerate(curve):
        rows.append({'input':v,'output':out,'power07_ideal':255*(v/255)**0.7,'dark_before':v<180,'dark_after':out<180})
    with (HERE/'tone-curve.csv').open('w',newline='',encoding='utf-8') as f:
        writer=csv.DictWriter(f,fieldnames=rows[0].keys());writer.writeheader();writer.writerows(rows)
    candidate=REPO/'fpga/custom_project/sc520-pixel14/overlay/pixel14_color_pipeline.v'
    assert sha(candidate)=='86E8E1F5A9422B509141AFB5502F535EA70CD04DD941900B97E4F95639077F8C'
    report={'created_at':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
      'owner':'/root/imaging_audit','baseline_head':'3089ae8ee0daa6ffdbb581179eb2453d6c4fef5a','baseline_build':'6a50b10a / D0109',
      'baseline_manifest':info(BASE/'inputs.json'),'baseline_sources':entries,'baseline_owned_snapshots':snapshots,
      'sensor_datasheet':info(Path('E:/juan/FPGA/Data/HX1P35A_Contest_202606/SC520CS摄像头资料/SC520CS-03_数据手册_V1.6.pdf')),
      'candidate':info(candidate),'runs':results,'normal_total_scenarios':20,'normal_total_checks':4836515,
      'tone_curve':info(HERE/'tone-curve.csv'),'tone_max_absolute_error_vs_power07':max(abs(x['output']-x['power07_ideal']) for x in rows),
      'tone_dark_threshold180_first_non_dark_input':next(v for v,out in enumerate(curve) if out>=180),
      'photometry':{'active_initial_exposure_half_lines':1991,'vts':1000,'requested_analog_gain_register':'0x0f (16x)',
        'requested_digital_gain_registers':['0x00','0x80'],'has_image_feedback_ae':False,'hardware_register_readback_observed':False},
      'legacy_observations':[{'input':[220,40,30],'output':[40,40,39]}, {'input':[30,40,220],'output':[39,40,40]},
          {'input':[220,200,40],'output_last':[199,200,199]},
          {'same_red_input_two_rows':[220,40,30],'earlier_output':[40,40,39],'later_output':[88,40,32]}],
      'limits':['Actual awb.v/signal_delay.v with explicit behavioral unsigned divider and dual-port RAM models; not vendor IP timing qualification.',
        '720p is a synthetic pre-AWB RGB frame; no optical camera, RAW-to-RGB numerical demosaic qualification, DDR/HDMI PHY or hardware validation.',
        'WB structural qualification counts RGB groups and line markers only; CSI/ECC/CRC/config faults with identical RGB geometry are outside this module.',
        'No camera photos, captured pixel histograms, exposure readback, illuminance, color chart, sensor CCM or monitor RGB range measurement was available.',
        'Inherited signal_delay assumes contiguous line payload; arbitrary valid bubbles/backpressure are not supported.'],
      'hardware_validated':False}
    save(HERE/'imaging-audit.json',report)
    print(json.dumps({'qualified':True,'baseline_sources':len(entries),'baseline_snapshots':len(snapshots),'runs':len(results),
        'normal_checks':report['normal_total_checks'],'candidate_sha256':sha(candidate),'tone_threshold':report['tone_dark_threshold180_first_non_dark_input']}))
if __name__=='__main__':main()
