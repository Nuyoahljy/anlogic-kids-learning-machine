"""T018: preserve scene/ROM/CDC checks and prove all retained I2C state is parent-clocked."""
from pathlib import Path
import argparse,collections,importlib.util,json,re
import hashlib
HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('scene_candidate',HERE/'audit-scene-candidate.py');scene=importlib.util.module_from_spec(spec);spec.loader.exec_module(scene)
base=scene.base;phys=scene.phys;ROOT=scene.ROOT

def path_records(path):
    rows=[]
    for block in re.split(r'(?m)^Slack\s*:',base.read(path))[1:]:
        def f(name):return re.search(r'(?m)^'+name+r'\s*:\s*(.*)$',block)[1]
        start,end=f('Begin Point'),f('End Point')
        rows.append({'Check':f('Check Type'),'SlackNs':float(block.split('ns')[0].strip()),
          'FromClock':re.search(r'clock (\S+)',start)[1],'ToClock':re.search(r'clock (\S+)',end)[1],
          'Begin':start.split()[0],'End':end.split()[0],'TargetEdge':'falling' if 'falling edge' in end else 'rising',
          'DelayNs':float(f('Data Path Delay').split('ns')[0]),'BudgetNs':float(f('Budget').split('ns')[0])})
    return rows

def duplicate_address_adapter(run,proof_path):
    proof=json.loads(base.read(proof_path))
    assert proof['Verified'] and proof['NativeExit']==0 and proof['Summary']=={'errors':0,'checks':32796,'rows':2048,'comb_rows':2048,'done':1}
    for item in proof['Inputs']+proof['Artifacts']:
        assert base.sha(item['Path'])==item['SHA256'],item['Path']
    canonical='u_p14_pipeline/scene_mode$scene/card_index[5]'
    duplicate=canonical+'_dup_4'
    assert proof['GateNet']==canonical and duplicate in proof['RoutedEquivalentNets']
    route=run/'td_project/camera_to_dsi_display_Runs/phy_1/pixel14-phy_1-netlist.v'
    syn=run/'td_project/camera_to_dsi_display_Runs/syn_1/pixel14-syn_1-netlist.v'
    assert proof['Inputs'][0]['SHA256']==base.sha(syn) and proof['Inputs'][1]['SHA256']==base.sha(route)
    text=base.read(route);cells=phys.slices(text)
    reset_name='u_p14_diag_cdc/src_reset_reg[0]_syn_2'
    params,ports=cells[reset_name]
    assert ports['oqa']=='u_p14_diag_cdc/src_reset[0]' and ports['oqb']=='u_p14_diag_cdc/src_reset[1]'
    assert ports['ima']=="1'b1" and ports['imb']==ports['oqa'] and params['ASRMUX']=='INV'
    assert params['REGA_REGSET_ASYNC']==params['REGB_REGSET_ASYNC']=='RESET'
    pll=[m for m in re.finditer(r'PH1P_PHY_PLL_V2\s*#\((.*?)\)\s+(\\\S+|\w+)\s*\((.*?)\);',text,re.S)
         if base.net(m[2])=='u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL']
    assert len(pll)==1
    pllports={k:base.net(v) for k,v in re.findall(r'\.(\w+)\(([^()]*)\)',pll[0][3])}
    assert ports['asr']==pllports['lock'],'Common reset is not driven by PLL lock'
    original=base.memories;route_digest=hashlib.sha256(text.encode()).hexdigest()
    adapted=[]
    def parsed_memories(source_text):
        memories=original(source_text)
        if hashlib.sha256(source_text.encode()).hexdigest()!=route_digest:return memories
        for m in memories:
            if m['Name']!='u_p14_pipeline/shape_mode$shape_guard/templates/ramread0_syn_23':continue
            for port in ['addra','addrb']:
                bits=base.bits(m['Ports'][port],m['Declarations'])
                assert bits.count(duplicate)==1
                new=[canonical if x==duplicate else x for x in bits]
                m['Ports'][port]='{'+','.join("1'b"+x if x in ('0','1') else '\\'+x+' ' for x in reversed(new))+'}'
                adapted.append({'ROM':m['Name'],'Port':port,'Before':bits,'After':new})
        return memories
    base.memories=parsed_memories
    return original,adapted,{'Proof':base.artifact(proof_path),'SynNetlist':base.artifact(syn),'RoutedNetlist':base.artifact(route),
      'CanonicalSignal':canonical,'DuplicatedSignal':duplicate,'ResetCell':{'Name':reset_name,'Params':params,'Ports':ports},
      'ResetSource':'PLL lock drives active-low two-register reset chain. Equivalence is claimed only after this reset establishes zero, not during the vendor models configuration window.',
      'WholeNetlistFormalEquivalence':False}

def preservation_with_review(review_path):
    baseline=ROOT/'evidence/sc520-card-recognition/builds/6a50b10a'
    previous=json.loads(base.read(baseline/'inputs.json'));snapshots=[];vendor=[]
    for item in previous['Files']:
        if item.get('Snapshot'):
            assert base.sha(item['Snapshot'])==item['SnapshotSHA256'],item['Snapshot']
            snapshots.append(base.artifact(item['Snapshot']))
        elif not Path(item['Path']).resolve().is_relative_to(ROOT):
            assert base.sha(item['Path'])==item['SHA256'],item['Path'];vendor.append(base.artifact(item['Path']))
    oldbit=baseline/'td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display.bit'
    assert base.sha(oldbit)=='3A7CD3912C0C72FC6553382E2FB00B61F3A432B251C1C236A35BDFE1FAC7D3F8'
    review=json.loads(base.read(review_path));main=Path('E:/juan/FPGA/anlogic-kids-learning-machine')
    expected={str((main/p).resolve()).casefold() for p in ['AGENTS.md','PROJECT_MEMORY.md','PLAN.md','TASKS.md','DECISIONS.md','docs/03-interface-contracts.md','docs/10-active-coordination.md']}
    assert {str(Path(x['Path']).resolve()).casefold() for x in review['Documents']}==expected
    for x in review['Documents']:
        assert base.sha(x['Path'])==x['SHA256'] and base.sha(x['RecordPath'])==x['RecordSHA256'],x
        assert base.sha(x['Snapshot'])==x['SHA256'],x
        record=json.loads(base.read(x['RecordPath']))
        match=[c for c in record['Changes'] if Path(c['Path']).resolve()==Path(x['Path']).resolve()]
        assert len(match)==1 and (not match[0].get('SHA256') or match[0]['SHA256']==x['SHA256']),x
    return {'Baseline0109Bit':base.artifact(oldbit),'Baseline0109Snapshots':snapshots,'ExternalVendorSources':vendor,
      'CoordinatorDocumentReview':base.artifact(review_path),'CoordinatorDocuments':[
          {**base.artifact(x['Snapshot']),'RuntimeSourcePath':x['Path'],'ObservedSHA256':x['SHA256'],
           'AuthorityRecord':base.artifact(x['RecordPath'])} for x in review['Documents']]}

def audit(run,bindings,duplicate_proof,coordinator_review):
    original,adapted,alias=duplicate_address_adapter(run,duplicate_proof)
    try:
        result={**base.audit_build(run,'scene',bindings,False),**scene.cdc_audit(run),**preservation_with_review(coordinator_review)}
        assert result['BaseQualified']
        result.update(CandidateQualified=True,HardwareValidated=False)
    finally:base.memories=original
    assert len(adapted)==2
    alias['InMemoryLogicalAddressBindings']=adapted
    route=run/'td_project/camera_to_dsi_display_Runs/phy_1';text=base.read(route/'pixel14-phy_1-netlist.v')
    cells=phys.slices(text);buffers=base.routed_clock_buffers(text);decl=base.declarations(text)
    prefix='u_uicfgcs520/u_i2c/'
    pll=[]
    for m in re.finditer(r'PH1P_PHY_PLL_V2\s*#\((.*?)\)\s+(\\\S+|\w+)\s*\((.*?)\);',text,re.S):
        if base.net(m[2])=='u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL':
            ports=dict(re.findall(r'\.(\w+)\(([^()]*)\)',m[3]));pll.append(base.bits(ports['clkc'],decl)[1])
    assert len(pll)==1,'Parent PLL output not uniquely resolved'
    enumeration=[]
    for name,(params,ports) in cells.items():
        q={k:ports[k] for k in ('oqa','oqb') if ports.get(k,'').startswith(prefix) or ports.get(k,'').startswith('O_cam_scl')}
        if not q and not name.startswith(prefix):continue
        if 'clk' not in ports:
            assert not q,('I2C Q cell has no clock pin',name,q)
            continue
        clock=ports['clk'];chain=[]
        while clock in buffers:chain.append(buffers[clock]);clock=buffers[clock]['Input']
        assert clock==pll[0],('I2C state has non-parent clock',name,clock)
        enumeration.append({'Cell':name,'OwnedQ':q,'ClockPinNet':ports['clk'],'ResolvedPLLClkC1':clock,'BufferChain':chain})
    assert len(enumeration)>30
    assert 'u_uicfgcs520/u_i2c/scl_clk' not in base.read(route/'route_clock_utilization.txt')
    core=[];files=[]
    for name in ['i2c-core-inbound.rpt','i2c-core-outbound.rpt']:
        p=run/'analysis'/name;rows=path_records(p);assert rows
        for row in rows:
            assert row['FromClock']==row['ToClock']=='pll_clk_24m',row
            assert row['SlackNs']>=0 and row['TargetEdge']=='rising',row
        core.extend(rows);files.append(base.artifact(p))
    grouped=collections.defaultdict(list)
    for r in core:grouped[r['Check']].append(r['SlackNs'])
    assert set(grouped)=={'setup','hold','recovery','removal'},grouped.keys()
    covered={r['End'].rsplit('.',1)[0] for r in core}
    assert {r['Cell'] for r in enumeration}<=covered,('Core cell omitted from reports',{r['Cell'] for r in enumeration}-covered)
    extra=[]
    for name,start,finish in [('i2c-reset',prefix+'reset_pipe[0]',prefix+'reset_pipe[1]'),('i2c-sda',prefix+'sda_meta',prefix+'sda_sync')]:
        paths=phys.timing_paths(run/'analysis'/(name+'.rpt'),cells)
        assert len(paths)==2 and {p['Check'] for p in paths}=={'setup','hold'}
        for p in paths:
            assert p['SourceNet']==start and p['DestinationNet']==finish,p
            assert p['FromClock']==p['ToClock']=='pll_clk_24m' and p['SlackNs']>=0,p
            if p['Check']=='setup':assert p['BudgetNs']==2 and p['DelayNs']<2,p
        extra.append({'Name':name,'Paths':paths})
    old=ROOT/'evidence/sc520-card-recognition/builds/6a50b112';old_bit=json.loads(base.read(old/'result.json'))
    assert base.sha(old_bit['Bit'])=='4C336D57C7D56DA5C132FCA38B75944C898F4D90EBE80D24842AE4DD4F2ADD47'
    # T018 must not change capture, image processing, templates or business.
    unchanged=[]
    for p in (old/'rtl').glob('*.v'):
        q=run/'rtl'/p.name;assert q.exists() and base.sha(q)==base.sha(p),p
        unchanged.append(base.artifact(q))
    assert base.sha(old/'templates.mem')==base.sha(run/'templates.mem')
    project=base.read(run/'td_project/camera_to_dsi_display.al')
    active=re.findall(r'Path="([^"]*/uii2c\.v)"',project)
    assert len(active)==1 and Path(active[0]).resolve()==(run/'overlay/uii2c.v').resolve(),active
    sdc=base.read(run/'overlay/pixel14.sdc')
    new_lines=set(sdc.splitlines())-set(base.read(old/'overlay/pixel14.sdc').splitlines())
    cuts=[x for x in new_lines if x.startswith('set_false_path')]
    assert cuts==['set_false_path -from [get_ports {IO_cam_sda}] -to [get_regs {u_uicfgcs520/u_i2c/sda_meta}]'],cuts
    assert not any('multicycle' in x or x.startswith('create_clock') for x in new_lines),new_lines
    current_critical=[line for name in ['syn_1','phy_1'] for line in base.read(run/(name+'.stdout.log')).splitlines() if 'CRITICAL-WARNING' in line]
    assert not any('scl_clk' in line or 'set_max_delay' in line for line in current_critical),current_critical
    return {**result,'RoutedDuplicateAddressProof':alias,'InheritedSCLClockGapClosed':True,'ParentPLLClockNet':pll[0],'I2CCells':enumeration,
      'I2CTimingFiles':files,'I2CTimingRecords':core,'I2CCheckMinimumSlackNs':{k:min(v) for k,v in grouped.items()},
      'AdditionalSynchronizers':extra,'TotalSynchronizerPairs':19,'SDAFirstStageException':cuts,
      'UnchangedImageRTL':unchanged,'D0112BitPreserved':base.artifact(old_bit['Bit']),
      'CriticalWarnings':current_critical,'Program':base.artifact(__file__),
      'FullSystemTimingSignoff':False,'ExternalTimingBoundary':'SDA synchronizer first stage is asynchronous. RTL tests assume1000ns rise/300ns fall and3450ns slave valid delay. Real pullups/voltage/clock tolerance remain unmeasured; no clock stretching or autonomous stuck-SDA bus clear. No MTBF or full external camera IO timing claim.'}

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('run',type=Path);ap.add_argument('--bindings',required=True,type=Path);ap.add_argument('--duplicate-proof',required=True,type=Path);ap.add_argument('--coordinator-review',required=True,type=Path);ap.add_argument('--output',required=True,type=Path);a=ap.parse_args()
    report=audit(a.run.resolve(),json.loads(base.read(a.bindings)),a.duplicate_proof,a.coordinator_review);base.emit(a.output,report)
    print(json.dumps({'Output':str(a.output),'I2CCells':len(report['I2CCells']),'MinimumSlackNs':report['I2CCheckMinimumSlackNs'],'Pairs':report['TotalSynchronizerPairs'],'Qualified':True}))
