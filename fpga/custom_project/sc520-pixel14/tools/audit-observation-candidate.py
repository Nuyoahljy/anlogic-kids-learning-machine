"""D036 exact-build ROM, four-mailbox, freshness and retained I2C timing audit."""
from pathlib import Path
import argparse,collections,importlib.util,json,re
HERE=Path(__file__).resolve().parent
def load(name,file):
    spec=importlib.util.spec_from_file_location(name,HERE/file);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
scl=load('observation_scl','audit-scl-candidate.py');scene=scl.scene;base=scene.base;phys=scene.phys;old=scene.old;ROOT=scene.ROOT


def preservation_review(review_path):
    # Preserve the historical auditor. New main records use lowercase hex;
    # SHA256 case changes representation only, never the compared file bytes.
    baseline=ROOT/'evidence/sc520-card-recognition/builds/6a50b10a'
    previous=json.loads(base.read(baseline/'inputs.json'));snapshots=[];vendor=[]
    for item in previous['Files']:
        if item.get('Snapshot'):
            assert base.sha(item['Snapshot'])==item['SnapshotSHA256'].upper(),item['Snapshot']
            snapshots.append(base.artifact(item['Snapshot']))
        elif not Path(item['Path']).resolve().is_relative_to(ROOT):
            assert base.sha(item['Path'])==item['SHA256'].upper(),item['Path'];vendor.append(base.artifact(item['Path']))
    oldbit=baseline/'td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display.bit'
    assert base.sha(oldbit)=='3A7CD3912C0C72FC6553382E2FB00B61F3A432B251C1C236A35BDFE1FAC7D3F8'
    review=json.loads(base.read(review_path));main=Path('E:/juan/FPGA/anlogic-kids-learning-machine')
    expected={str((main/p).resolve()).casefold() for p in ['AGENTS.md','PROJECT_MEMORY.md','PLAN.md','TASKS.md','DECISIONS.md','docs/03-interface-contracts.md','docs/10-active-coordination.md']}
    assert len(review['Documents'])==len(expected)
    assert {str(Path(x['Path']).resolve()).casefold() for x in review['Documents']}==expected
    for x in review['Documents']:
        assert base.sha(x['Path'])==x['SHA256'].upper() and base.sha(x['RecordPath'])==x['RecordSHA256'].upper(),x
        assert base.sha(x['Snapshot'])==x['SHA256'].upper(),x
        record=json.loads(base.read(x['RecordPath']));assert record['Task']=='sc520-main-coordination'
        match=[c for c in record['Changes'] if Path(c['Path']).resolve()==Path(x['Path']).resolve()]
        assert len(match)==1 and match[0].get('SHA256') and match[0]['SHA256'].upper()==x['SHA256'].upper(),x
    return {'Baseline0109Bit':base.artifact(oldbit),'Baseline0109Snapshots':snapshots,'ExternalVendorSources':vendor,
      'CoordinatorDocumentReview':base.artifact(review_path),'CoordinatorDocuments':[
        {**base.artifact(x['Snapshot']),'RuntimeSourcePath':x['Path'],'ObservedSHA256':x['SHA256'].upper(),
         'AuthorityRecord':base.artifact(x['RecordPath'])} for x in review['Documents']]}

def extra_pair(run,cells,label,prefix):
    paths=phys.timing_paths(run/'analysis'/(label+'.rpt'),cells)
    assert len(paths)==2 and {p['Check'] for p in paths}=={'setup','hold'},label
    for p in paths:
        assert p['SourceNet']==prefix+'_meta' and p['DestinationNet']==prefix+'_sync',p
        assert p['FromClock']==p['ToClock'] and p['SlackNs']>=0,p
        if p['Check']=='setup':assert p['BudgetNs']==2 and p['DelayNs']<2,p
    return {'Name':label,'Paths':paths}

def color_mailbox(run,cells):
    path=run/'analysis/color-routing.rpt';objects=old.object_names(run/'analysis/color-objects.txt',phys)
    sources=[re.fullmatch(r'(u_p14_pipeline/.+transport/link)/held_data\[(\d+)\]',name) for name in objects['FROM']]
    sources=[x for x in sources if x];prefixes={x[1] for x in sources};assert len(prefixes)==1,prefixes;prefix=prefixes.pop()
    expected={int(x[2]) for x in sources};assert len(expected)>100 and max(expected)<800
    retained={int(m[1]) for _,ports in cells.values() for pin in ('oqa','oqb') if (m:=re.fullmatch(re.escape(prefix)+r'/held_data\[(\d+)\]',ports.get(pin,'')))}
    assert retained==expected
    paths=old.payload_paths(path,cells,phys,('MIPI_RX_BYTE_CLK','HDMI_PIXEL_CLK'))
    crossed=[p for p in paths if p['FromClock']!=p['ToClock']];same=[p for p in paths if p['FromClock']==p['ToClock']]
    mapping={};frame_aliases=set()
    for check in ('setup','hold'):
        seen=set()
        for p in [x for x in crossed if x['Check']==check]:
            match=re.fullmatch(re.escape(prefix)+r'/held_data\[(\d+)\]',p['SourceNet']);assert match,p
            bit=int(match[1]);assert bit not in seen;seen.add(bit)
            allowed={prefix+f'/dst_data[{bit}]',f'u_p14_pipeline/color_diag_packet[{bit}]',
                f'S_p14_color_packet[{bit}]',f'u_p14_diag_osd/packet[{bit}]',prefix.rsplit('/link',1)[0]+f'/packet_out[{bit}]'}
            # This route names the 32 held frame-ID destination Qs after the
            # bridge output. The frozen RTL passes [771:0] through unchanged;
            # reason/complete bits have local logic and are not covered here.
            if bit<32:
                alias=prefix.rsplit('/link',1)[0]+f'/display_packet[{bit}]'
                allowed.add(alias)
                if p['DestinationNet']==alias:
                    assert 'assign display_packet={packet_out[799:781],current_good,current_reason,packet_out[771:0]};' in base.read(run/'rtl/pixel14_observation_bridge.v')
                    frame_aliases.add(bit)
            assert p['DestinationNet'] in allowed and p['SourceNet'] in objects['FROM'] and p['DestinationNet'] in objects['TO'],(bit,p,allowed)
            assert 0<=p['DelayNs']<10,p
            mapping.setdefault(str(bit),{})[check]=p
        assert seen==expected,(check,expected-seen)
    for bit,p in mapping.items():
        for field in ['SourceQ','SourceNet','DestinationQ','DestinationNet','End']:assert p['setup'][field]==p['hold'][field],(bit,field)
    return {'Name':'color-observation','Prefix':prefix,'DeclaredBits':800,'RetainedBits':sorted(expected),
        'OptimizedBits':sorted(set(range(800))-expected),'Bits':len(expected),'Paths':mapping,
        'MaximumDataPathNs':max(p['DelayNs'] for p in crossed),'CrossedPaths':len(crossed),
        'SameDomainPackedPaths':same,'AsynchronousPathsSkipped':0,'ExactFrameIdOutputAliases':sorted(frame_aliases)},prefix

def audit(run,bindings,coordinator):
    result=base.audit_build(run,'scene',bindings,False);assert result['BaseQualified']
    result.update(scene.cdc_audit(run))
    phy=run/'td_project/camera_to_dsi_display_Runs/phy_1';text=base.read(phy/'pixel14-phy_1-netlist.v');cells=phys.slices(text);buffers=base.routed_clock_buffers(text)
    mailbox,prefix=color_mailbox(run,cells)
    extra=[extra_pair(run,cells,'color-'+signal,prefix+'/'+signal) for signal in ('req','ack')]
    for label,start,end in [('i2c-reset','reset_pipe[0]','reset_pipe[1]'),('i2c-sda','sda_meta','sda_sync')]:
        rows=phys.timing_paths(run/'analysis'/(label+'.rpt'),cells);assert len(rows)==2
        assert {p['Check'] for p in rows}=={'setup','hold'}
        for p in rows:
            assert p['SourceNet']=='u_uicfgcs520/u_i2c/'+start and p['DestinationNet']=='u_uicfgcs520/u_i2c/'+end,p
            assert p['FromClock']==p['ToClock']=='pll_clk_24m' and p['SlackNs']>=0,p
            if p['Check']=='setup':assert p['BudgetNs']==2 and p['DelayNs']<2
        extra.append({'Name':label,'Paths':rows})
    decl=base.declarations(text);pll=[]
    for m in re.finditer(r'PH1P_PHY_PLL_V2\s*#\((.*?)\)\s+(\\\S+|\w+)\s*\((.*?)\);',text,re.S):
        if base.net(m[2])=='u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL':
            ports=dict(re.findall(r'\.(\w+)\(([^()]*)\)',m[3]));pll.append(base.bits(ports['clkc'],decl)[1])
    assert len(pll)==1,'Parent PLL output not uniquely resolved'
    registers=[]
    for name,(params,ports) in cells.items():
        q={pin:ports[pin] for pin in ['oqa','oqb'] if ports.get(pin,'').startswith('u_uicfgcs520/u_i2c/') or ports.get(pin,'').startswith('O_cam_scl')}
        if not q and not name.startswith('u_uicfgcs520/u_i2c/'):continue
        if 'clk' not in ports:
            assert not q,('I2C Q cell has no clock pin',name,q)
            continue
        node=ports['clk'];chain=[]
        while node in buffers:chain.append(buffers[node]);node=buffers[node]['Input']
        assert node==pll[0],('I2C state has non-parent clock',name,node,pll[0])
        registers.append({'Cell':name,'Q':q,'ClockRoot':node,'ClockChain':chain})
    assert len(registers)>30 and len({r['ClockRoot'] for r in registers})==1
    assert 'u_uicfgcs520/u_i2c/scl_clk' not in base.read(phy/'route_clock_utilization.txt')
    core=[]
    for name in ['i2c-core-inbound.rpt','i2c-core-outbound.rpt']:core+=scl.path_records(run/'analysis'/name)
    assert {r['Cell'] for r in registers}<={p['End'].rsplit('.',1)[0] for p in core}
    for p in core:assert p['FromClock']==p['ToClock']=='pll_clk_24m' and p['SlackNs']>=0 and p['TargetEdge']=='rising'
    assert {p['Check'] for p in core}=={'setup','hold','recovery','removal'}
    baseline=ROOT/'evidence/sc520-card-recognition/builds/6a50b113'
    for name in ['uii2c.v','uicfgcs520.v']:assert base.sha(run/'overlay'/name)==base.sha(baseline/'overlay'/name)
    for name in ['block_frame_recognizer.v','pixel14_rotation_matcher.v','pixel14_block_shape_guard.v','pixel14_block_filter.v','card_result_filter.v','items14_quiz_control.v','items14_result_join.v']:
        assert base.sha(run/'rtl'/name)==base.sha(baseline/'rtl'/name),name
    assert base.sha(run/'templates.mem')==base.sha(baseline/'templates.mem')
    top=base.read(run/'overlay/design_top_wrapper.v')
    assert '.COLOR_DIAGNOSTICS(1)' in top and '.COLOR_CORRECTION(0)' not in top and '.WB_ENABLE(0)' not in top
    result.update(preservation_review(coordinator))
    return {**result,'CandidateQualified':True,'HardwareValidated':False,'FullSystemTimingSignoff':False,
      'ColorMailbox':mailbox,'AdditionalSynchronizers':extra,'TotalSynchronizerPairs':21,
      'ParentPLLClockNet':pll[0],'I2CCells':registers,'I2CTimingRecords':core,'I2CMinimumSlackNs':{k:min(p['SlackNs'] for p in core if p['Check']==k) for k in ['setup','hold','recovery','removal']},
      'I2CAndCoreClassificationUnchangedFrom113':True,'Program':base.artifact(__file__),
      'AuditPrograms':[base.artifact(HERE/name) for name in ['audit-scl-candidate.py','audit-scene-build.py','audit-scene-candidate.py',*scene.LEGACY_HASHES]],
      'Limits':'Diagnostic candidate only, no color correction claim. External SDA/RC/output-enable propagation, sensor electrical timing, CRC/ECC content, exact DDR frame identity and MTBF remain unverified. Asynchronous payload paths use an independently checked10ns propagation bound, not asynchronous setup/hold signoff.'}

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('run',type=Path);ap.add_argument('--bindings',type=Path,required=True);ap.add_argument('--coordinator-review',type=Path,required=True);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args()
    r=audit(a.run.resolve(),json.loads(base.read(a.bindings)),a.coordinator_review);base.emit(a.output,r)
    print(json.dumps({'Output':str(a.output),'Qualified':True,'ColorBits':r['ColorMailbox']['Bits'],'MaxColorDelay':r['ColorMailbox']['MaximumDataPathNs'],'SyncPairs':21,'Timing':r['TimingNs']}))
