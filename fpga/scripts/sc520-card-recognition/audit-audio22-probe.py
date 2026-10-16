"""Exact routed T022 test-profile audit. Never qualifies a downloadable image."""
from pathlib import Path
import argparse,importlib.util,json,re
ROOT=Path(__file__).resolve().parents[3];E=ROOT/'evidence/sc520-card-recognition'
LEGACY=ROOT/'fpga/custom_project/sc520-pixel14/tools'
def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
observation=load('audio22_observation',LEGACY/'audit-observation-candidate.py')
base=observation.base;scene=observation.scene;phys=observation.phys
original_logical=base.logical_roms
def logical_roms(run,profile):
    result=original_logical(run,profile)
    font={int(a):int(b,16) for a,b in re.findall(r"rom\[12'd(\d+)\]=16'h([0-9a-fA-F]+)",base.read(run/'rtl/pixel22_font_rom.v'))}
    assert set(font)==set(range(4096)) and all((x&1)==0 for x in font.values())
    result['font'].update(Words=[font[a] for a in range(4096)],Instance=r'^u_p17_display/panel/font/',Output=r'^u_p17_display/panel/font_bits\[(\d+)\]$')
    for kind,file,width,instance in [('logo-index','anlogic_logo_index.mem',10,r'^u_p17_display/logo/ramread0_'),('logo-palette','anlogic_logo_palette.mem',24,r'^u_p17_display/logo/ramread1_')]:
        words=[int(x,16) for x in base.read(run/file).split()];assert len(words)==(16384 if width==10 else 1024)
        result[kind]={'Words':words,'Width':width,'Instance':instance,'Output':r'(?!)','ConstantZeroBits':[]}
    return result
def profile_review(run):
    paths=[ROOT/'assets/templates/sc520-card-recognition/audio22/hardware-default.json',ROOT/'assets/templates/sc520-card-recognition/audio22/offline-test.json',run/'profile.json']
    hardware,test,actual=[json.loads(base.read(p)) for p in paths]
    assert not hardware['TestOnly'] and hardware['TRACKS']==[]
    assert all(hardware[x]==0 and test[x]==1 for x in ('MAP_VERIFIED','STATUS_VERIFIED','MODE_VERIFIED'))
    assert test==actual and test['TestOnly'] and test['TRACKS']==list(range(0x1201,0x1224))
    assert all(not p['BitGenerationAllowed'] and not p['HardwareValidated'] for p in (hardware,test,actual))
    inputs=json.loads(base.read(run/'inputs.json'))
    top=next(x for x in inputs['Files'] if x.get('Snapshot') and Path(x['Snapshot']).name=='design_top_wrapper.v'
             and Path(x['Path']).resolve()==(ROOT/'fpga/custom_project/sc520-audio22/overlay/design_top_wrapper.v').resolve())
    text=base.read(top['Path'])
    assert 'AUDIO_MAP_VERIFIED=0,AUDIO_STATUS_VERIFIED=0,AUDIO_MODE_VERIFIED=0' in text and "AUDIO_TRACKS=560'd0" in text
    expected=text.replace('AUDIO_MAP_VERIFIED=0,AUDIO_STATUS_VERIFIED=0,AUDIO_MODE_VERIFIED=0','AUDIO_MAP_VERIFIED=1,AUDIO_STATUS_VERIFIED=1,AUDIO_MODE_VERIFIED=1')
    expected=expected.replace("AUDIO_TRACKS=560'd0","AUDIO_TRACKS=560'h"+''.join(f'{x:04X}' for x in reversed(test['TRACKS'])))
    for item in inputs['Files']:
        if item.get('Snapshot') and Path(item['Snapshot']).name in ('templates.mem','anlogic_logo_index.mem','anlogic_logo_palette.mem'):
            expected=expected.replace(Path(item['Path']).as_posix(),Path(item['Snapshot']).as_posix())
    expected='// TEST ONLY SYNTHETIC MAPPING. NO BITGEN OR HARDWARE QUALIFICATION.\n'+expected
    assert expected==base.read(run/'overlay/design_top_wrapper.v'),'Unexpected change beyond the declared test profile/path substitutions'
    for token in ['.audio_idle(S_a22_idle),.audio_fault(S_a22_fault)', '.audio_event_valid(S_a22_event)', '.audio_cancel(S_a22_cancel)',
                  '.reset_n(S_rst_n && S_hdmi_rst_n)', '.rst_n(S_rst_n && S_hdmi_rst_n)', '.tick_1ms(S_p14_tick)', '.audio_state(S_a22_state)', '.RENDER_ENABLE(0)']:
        assert token in text,token
    previous_sdc=base.read(ROOT/'fpga/custom_project/sc520-pixel17/overlay/pixel14.sdc')
    current_sdc=base.read(run/'overlay/pixel14.sdc')
    assert current_sdc.startswith(previous_sdc),'Original video/CDC constraints were changed'
    extra=[x.strip() for x in current_sdc[len(previous_sdc):].splitlines() if x.strip() and not x.lstrip().startswith('#')]
    expected_constraints=[
        'set_false_path -from [get_ports {I_audio_rx}] -to [get_regs {u_a22_audio/bridge/player/link/rx_meta}]',
        'set_false_path -from [get_ports {I_audio_busy}] -to [get_regs {u_a22_audio/bridge/player/core/busy_meta}]',
        'set_max_delay -from [get_regs {u_a22_audio/bridge/player/link/rx_meta}] -to [get_regs {u_a22_audio/bridge/player/link/rx_sync}] 2.000',
        'set_max_delay -from [get_regs {u_a22_audio/bridge/player/core/busy_meta}] -to [get_regs {u_a22_audio/bridge/player/core/busy_safe}] 2.000',
        'set_max_delay -from [get_regs {u_a22_audio/reset_pipe[0]}] -to [get_regs {u_a22_audio/reset_pipe[1]}] 2.000']
    assert extra==expected_constraints,extra
    return {'Profiles':[base.artifact(p) for p in paths],'HardwareDefaultDisabled':True,'SyntheticTestMappingOnly':True,'TopProfileTransformationChecked':True,
            'OriginalVideoConstraintsPreserved':True,'ExactAddedAudioConstraints':extra,'ExternalAudioTimingInvented':False}
def inherited_stage_identity(expected,actual):
    assert set(expected)==set(actual),'Inherited stage fields changed'
    adjusted=[]
    for key,value in expected.items():
        if value==actual[key]:continue
        assert key in ('StartedAtUtc','FinishedAtUtc'),('Inherited stage changed',key)
        def precise_utc(text):
            m=re.fullmatch(r'(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d{1,7}))?Z',text)
            assert m,('Not an exact UTC timestamp',text)
            return m[1],(m[2] or '').rstrip('0')
        # ConvertFrom-Json/ConvertTo-Json can trim fractional trailing zeros.
        # Compare the exact decimal instant; never truncate 100ns precision.
        assert precise_utc(value)==precise_utc(actual[key]),('Inherited timestamp changed',key)
        adjusted.append({'Field':key,'Original':value,'Reserialized':actual[key]})
    return adjusted

def recovery_review(run):
    path=run/'resume.json'
    if not path.exists():return {}
    r=json.loads(base.read(path));parent=Path(r['ParentRun'])
    assert parent==(ROOT/'evidence/sc520-card-recognition/builds/6a50b220').resolve()
    assert Path(r['ResumeRun'])==run and not r['SynthesisReexecuted'] and not r['PlacementReexecuted'] and r['RoutingReexecuted']
    assert r['TestOnly'] and not r['BitGenerationAllowed'] and not r['HardwareValidated']
    for x in r['CopiedFiles']:
        assert Path(x['Source']).is_relative_to(parent) and Path(x['Path']).is_relative_to(run)
        assert Path(x['Source']).relative_to(parent)==Path(x['Path']).relative_to(run)
        assert base.sha(x['Source'])==base.sha(x['Path'])==x['SHA256'],x
    assert any(Path(x['Path']).name=='camera_to_dsi_display_place.db' for x in r['CopiedFiles'])
    for key in ('ParentPhysicalStdout','ParentStages'):
        assert base.sha(r[key]['Path'])==r[key]['SHA256']
    settings=r['Settings']
    assert base.sha(settings['Source'])==settings['SourceSHA256'] and base.sha(settings['Path'])==settings['SHA256']
    assert base.read(settings['Source']).replace('set start_step opt_place','set start_step opt_route')==base.read(settings['Path'])
    phy=run/'td_project/camera_to_dsi_display_Runs/phy_1'
    assert not (phy/'.opt_place.begin.f').exists() and not (parent/'result.json').exists()
    assert base.sha(run/'inputs.json')==base.sha(parent/'inputs.json')
    inherited=json.loads(base.read(parent/'stages.json'))
    single_object=isinstance(inherited,dict)
    if single_object:inherited=[inherited]
    actual=json.loads(base.read(run/'stages.json'))
    assert len(inherited)==1 and len(actual)==2 and inherited[0]['Stage']=='syn_1' and inherited[0]['ExitCode']==0
    serialization=inherited_stage_identity(inherited[0],actual[0])
    return {'Recovery':base.artifact(path),'InheritedPlacement':str(parent),'SynthesisReexecuted':False,
            'PlacementReexecuted':False,'RecoveryFilesChecked':len(r['CopiedFiles']),
            'OriginalSingleStageObject':single_object,'ExactUtcSerializationAdjustments':serialization}
def probe_build(run,profile,bindings,historical):
    assert not historical
    result=json.loads(base.read(run/'result.json'));assert not result['ChangedInputs'] and result['TestOnly'] and not result['BitGenerationAllowed']
    assert [(x['Stage'],x['ExitCode'],x['MarkerFresh']) for x in result['Stages']]==[('syn_1',0,True),('phy_1',0,True)]
    assert not list(run.rglob('*.bit')) and not list((ROOT/'fpga/custom_project/sc520-audio22').rglob('*.bit'))
    phy=run/'td_project/camera_to_dsi_display_Runs/phy_1'
    assert (phy/'.opt_route.end.f').exists() and not (phy/'.bitgen.begin.f').exists()
    assert 'set end_step opt_route' in base.read(phy/'settings.cfg')
    assert 'proc bitgen_fun {} {error "T022 forbids bitgen"}' in base.read(phy/'camera_to_dsi_display.tcl')
    roms=base.rom_audit(run,'scene',True,bindings);assert len(roms['ROMs'])==39 and not roms['UnreviewedAddressOrSelectMappings']
    timing=base.read(phy/'camera_to_dsi_display_pr.timing')
    metrics={k:float(re.search(r'\b'+k+r':\s*(-?[0-9.]+)ns',timing)[1]) for k in ('SWNS','STNS','HWNS','HTNS')}
    assert metrics['SWNS']>=0 and metrics['HWNS']>=0 and metrics['STNS']==metrics['HTNS']==0,metrics
    area=base.read(phy/'camera_to_dsi_display_phy.area');resources=base.resource_report(area);assert not resources['OverCapacity']
    pins=[]
    for port,ball,direction in [('I_quiz_keys_n[0]','D5','INPUT'),('I_quiz_keys_n[1]','A9','INPUT'),('I_quiz_keys_n[2]','B9','INPUT'),('I_quiz_keys_n[3]','C7','INPUT'),('O_audio_tx','C18','OUTPUT'),('I_audio_rx','D15','INPUT'),('I_audio_busy','E12','INPUT')]:
        m=re.search(re.escape(port)+r'\s+'+direction+r'\s+(\S+)\s+(\S+)',area);assert m and m.groups()==(ball,'LVCMOS33'),(port,m.groups() if m else None)
        pins.append({'Port':port,'Ball':ball,'Direction':direction,'TestCandidateOnly':port.startswith(('O_audio','I_audio'))})
    logs=[base.read(run/(stage+'.stdout.log')) for stage in ('syn_1','phy_1')]
    errors=[line for text in logs for line in text.splitlines() if re.search(r'\bERROR:|unknown module|black.?box',line,re.I)];assert not errors,errors
    warnings=[line for text in logs for line in text.splitlines() if 'CRITICAL-WARNING' in line]
    return {'AuditedAt':base.now(),'Run':str(run),'Profile':'T022 SYNTHETIC TEST ONLY',**base.validate_inputs(run),**roms,**profile_review(run),**recovery_review(run),
        'TimingNs':metrics,'Resources':resources,'KeyAndTestIO':pins,'CriticalWarnings':warnings,'BaseQualified':True,'CandidateQualified':False,
        'HardwareValidated':False,'BitGenerationAllowed':False,'BitFilesFound':[],
        'BuildEvidence':[base.artifact(p) for p in [run/'inputs.json',run/'result.json',run/'stages.json',phy/'camera_to_dsi_display_pr.db',phy/'final_timing.rpt',phy/'camera_to_dsi_display_phy.area']]}
def audio_paths(run):
    phy=run/'td_project/camera_to_dsi_display_Runs/phy_1';text=base.read(phy/'pixel14-phy_1-netlist.v');cells=phys.slices(text)
    buffers=base.routed_clock_buffers(text);decl=base.declarations(text)
    roots=[]
    for m in re.finditer(r'PH1P_PHY_PLL_V2\s*#\((.*?)\)\s+(\\\S+|\w+)\s*\((.*?)\);',text,re.S):
        if base.net(m[2])=='u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL':
            ports=dict(re.findall(r'\.(\w+)\(([^()]*)\)',m[3]));roots.append(base.bits(ports['clkc'],decl)[4])
    assert len(roots)==1
    registers=[]
    for name,(params,ports) in cells.items():
        q={p:ports[p] for p in ('oqa','oqb') if ports.get(p,'').startswith('u_a22_audio/')}
        if not q and not name.startswith('u_a22_audio/'):continue
        if 'clk' not in ports:assert not q;continue
        node=ports['clk'];chain=[]
        while node in buffers:chain.append(buffers[node]);node=buffers[node]['Input']
        assert node==roots[0],('Audio register not on actual HDMI clock',name,node)
        registers.append({'Cell':name,'Q':q,'ClockRoot':node,'ClockChain':chain})
    assert len(registers)>100,len(registers)
    witnesses={kind:[r for r in registers if fragment in r['Cell']] for kind,fragment in [('queue','/bridge/queue/'),('uart','/bridge/player/link/'),('player','/bridge/player/core/')]}
    assert all(len(x)>10 for x in witnesses.values()),{k:len(v) for k,v in witnesses.items()}
    sync=[]
    for label,src,dst in [('audio-rx','bridge/player/link/rx_meta','bridge/player/link/rx_sync'),('audio-busy','bridge/player/core/busy_meta','bridge/player/core/busy_safe'),('audio-reset','reset_pipe[0]','reset_pipe[1]')]:
        paths=phys.timing_paths(run/'analysis'/(label+'.rpt'),cells)
        assert len(paths)==2 and {x['Check'] for x in paths}=={'setup','hold'}
        for p in paths:
            assert p['SourceNet']=='u_a22_audio/'+src and p['DestinationNet']=='u_a22_audio/'+dst,p
            assert p['FromClock']==p['ToClock']=='HDMI_PIXEL_CLK' and p['SlackNs']>=0,p
            if p['Check']=='setup':assert p['BudgetNs']==2 and 0<=p['DelayNs']<2,p
        sync.append({'Name':label,'Paths':paths})
    paths=[]
    for name in ('audio-inbound.rpt','audio-outbound.rpt'):paths+=observation.scl.path_records(run/'analysis'/name)
    assert {r['Cell'] for r in registers}<={p['End'].rsplit('.',1)[0] for p in paths},'Incomplete internal audio endpoint coverage'
    for p in paths:assert p['FromClock']==p['ToClock']=='HDMI_PIXEL_CLK' and p['SlackNs']>=0,p
    assert {p['Check'] for p in paths}=={'setup','hold','recovery','removal'}
    return {'AudioRegisters':registers,'ActiveAudioWitnessCounts':{k:len(v) for k,v in witnesses.items()},'AudioSynchronizers':sync,
        'AudioTimingRecords':paths,'AudioMinimumSlackNs':{k:min(x['SlackNs'] for x in paths if x['Check']==k) for k in ('setup','hold','recovery','removal')}}
def main():
    ap=argparse.ArgumentParser();ap.add_argument('run',type=Path);ap.add_argument('--bindings',required=True,type=Path)
    ap.add_argument('--coordinator-review',required=True,type=Path);ap.add_argument('--software',required=True,type=Path);ap.add_argument('--output',required=True,type=Path);a=ap.parse_args()
    assert not a.output.exists();run=a.run.resolve()
    base.logical_roms=logical_roms;base.audit_build=probe_build
    report=observation.audit(run,json.loads(base.read(a.bindings)),a.coordinator_review)
    report.update(audio_paths(run));report['LegacySynchronizerPairs']=report['TotalSynchronizerPairs'];report['TotalSynchronizerPairs']+=3
    start=json.loads(base.read(E/'audio22/start.json'))
    for item in start['Protected']+start['Imports']:assert base.sha(item['Path'])==item['SHA256'],item['Path']
    soft=json.loads(base.read(a.software));assert soft['Qualified'] and soft['PositiveScenarios']==44
    def refs(obj):
        if isinstance(obj,dict):
            if 'Path' in obj and 'SHA256' in obj:assert base.sha(obj['Path'])==obj['SHA256'],obj['Path']
            for v in obj.values():refs(v)
        elif isinstance(obj,list):
            for v in obj:refs(v)
    refs(soft)
    report.update({'ProbeQualified':True,'CandidateQualified':False,'BitGenerationAllowed':False,'Downloadable':False,
       'HardwareValidated':False,'FullSystemTimingSignoff':False,'Program':base.artifact(__file__),
       'ProtectedCount':len(start['Protected']),'Start':base.artifact(E/'audio22/start.json'),'Software':base.artifact(a.software),
       'SourceAudioCommit':start['AudioCommit'],'Imports':start['Imports'],
       'Limits':'Synthetic test-profile internal qualification only. Candidate balls not a wiring guide; no bitgen, no delivery. External TX/RX/BUSY timing, connectors, voltage, media mapping, real BUSY and board behavior remain unqualified. Fault-idle does not certify silence. Optical correction unchanged.'})
    base.emit(a.output,report)
    print(json.dumps({'ProbeQualified':True,'Downloadable':False,'Timing':report['TimingNs'],'AudioCells':len(report['AudioRegisters']),'SyncPairs':report['TotalSynchronizerPairs']}))
if __name__=='__main__':main()
