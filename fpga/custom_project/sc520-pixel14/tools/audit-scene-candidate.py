"""Candidate-level scene audit, reusing immutable physical CDC parsers only.

This does not call old audit main functions or their old owned-source
protection policy. Old 0109 snapshots/bit and external vendor sources remain
strictly protected; task-owned scene/ISP/OSD sources may evolve before freeze.
"""
from pathlib import Path
import argparse,importlib.util,json,re,xml.etree.ElementTree as ET

HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[3]
LEGACY_HASHES={
 'audit-build.py':'74613AA08F06DAD9F8E822EE3FC1F642F2B9111680AEAFB55EF3D25D73274C0B',
 'audit-candidate.py':'722FA109E72E9B000B2CC85C4DE2B30D69400DECE1931594F823DEFBC0FF7A97',
 'audit-recovery.py':'CE9BB31D112B207D984AA171C3518F454F657663E4728EC2F2469B910D486B94'}
def load(name,file):
    spec=importlib.util.spec_from_file_location(name,HERE/file);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
base=load('scene_build_parser','audit-scene-build.py')
phys=load('scene_physical_parser','audit-recovery.py')
old=load('scene_cdc_parser','audit-candidate.py')

def cdc_audit(run):
    for name,value in LEGACY_HASHES.items():assert base.sha(HERE/name)==value,('Legacy audit changed',name)
    phy=run/'td_project/camera_to_dsi_display_Runs/phy_1';analysis=run/'analysis'
    cells=phys.slices(phys.read(phy/'pixel14-phy_1-netlist.v'))
    pairs=[]
    for direction in ['forward','backward']:
        for signal in ['req','ack']:
            prefix=f'u_p14_pipeline/{direction}/{signal}'
            pairs.append((f'{direction}-{signal}',prefix+'_meta',prefix+'_sync'))
    for prefix,name in [('u_p14_diag_cdc','diagnostic'),('u_p14_i2c_cdc','i2c')]:
        for signal in ['req','ack']:pairs.append((name+'-'+signal,prefix+'/'+signal+'_meta',prefix+'/'+signal+'_sync'))
    pairs += [(f'key-{i}',f'u_quiz_keys/keys_sync_meta[{i}]',f'u_quiz_keys/keys_sync_safe[{i}]') for i in range(4)]
    pairs += [('staging-fault','u_p14_pipeline/staging_fault_meta','u_p14_pipeline/staging_fault_sync'),
      ('config-done','S_p14_cfg_done[0]','u_p14_provenance/cfg_done'),('config-error','S_p14_cfg_error[0]','u_p14_provenance/cfg_error'),
      ('i2c-busy','u_uicfgcs520/busy_meta','u_uicfgcs520/busy_sync'),('i2c-error','u_uicfgcs520/error_meta','u_uicfgcs520/error_sync')]
    synchronizers=[]
    for name,source,destination in pairs:
        paths=phys.timing_paths(analysis/(name+'.rpt'),cells)
        assert len(paths)==2 and {p['Check'] for p in paths}=={'setup','hold'},name
        for p in paths:
            assert p['SourceNet']==source and p['DestinationNet']==destination,(name,p)
            assert p['FromClock']==p['ToClock'] and p['SlackNs']>=0,(name,p)
            destination_cell=p['End'].rsplit('.',1)[0]
            destination_q=[pin for pin in ('oqa','oqb') if cells[destination_cell][1].get(pin)==p['DestinationNet']]
            assert len(destination_q)==1,('Synchronizer destination Q unresolved',name,p)
            p['DestinationQ']=destination_cell+'.'+destination_q[0]
            if name.startswith('i2c-'):assert p['FromClock']==('HDMI_PIXEL_CLK' if name=='i2c-req' else 'pll_clk_24m')
            if p['Check']=='setup':assert p['BudgetNs']==2.0 and 0<=p['DelayNs']<2.0,(name,p)
        synchronizers.append({'Name':name,'Paths':paths,'TwoNsConstraintApplied':True})
    assert len(synchronizers)==17
    periods={'MIPI_RX_BYTE_CLK':9.660,'HDMI_PIXEL_CLK':13.333,'pll_clk_24m':42.000}
    original=old.clock_periods(base.read(phy/'final_timing.rpt'))
    for k,v in periods.items():assert original.get(k)=={v},(k,original.get(k))
    for filename,names in [('original-clocks.rpt',{'sys_clk_50m','mipi_rx_ck_pad'}),('analysis-clocks.rpt',set(periods))]:
        actual={g.attrib['name'] for g in ET.fromstring(base.read(analysis/filename)).iter('clock_group')};assert actual==names,(filename,actual)
    mailboxes=[]
    specifications=[('business','u_p14_pipeline/forward','payload-objects.txt','payload-routing.rpt',('MIPI_RX_BYTE_CLK','HDMI_PIXEL_CLK'),132),
      ('diagnostic','u_p14_diag_cdc','diagnostic-objects.txt','diagnostic-routing.rpt',('MIPI_RX_BYTE_CLK','HDMI_PIXEL_CLK'),256),
      ('i2c','u_p14_i2c_cdc','i2c-objects.txt','i2c-routing.rpt',('pll_clk_24m','HDMI_PIXEL_CLK'),32)]
    for name,prefix,objects,report,clock_pair,declared_width in specifications:
        assert old.clock_periods(base.read(analysis/report))=={k:{periods[k]} for k in clock_pair}
        found=old.mailbox_audit(name,prefix,old.object_names(analysis/objects,phys),analysis/report,cells,phys,clock_pair)
        assert all(0<=b<declared_width for b in found['RetainedLogicalBits'])
        found['DeclaredWidth']=declared_width
        found['OptimizedLogicalBits']=sorted(set(range(declared_width))-set(found['RetainedLogicalBits']))
        found['OptimizationNote']='Every retained source Q bit and both measured directions are required. Constant/optimized bits are explicitly listed; software/RTL validation remains necessary for their intended semantics.'
        found['ReportedPathCount']=found['Bits']*2+found['ExcludedPaths']
        found['AsynchronousPathsSkipped']=0
        found['PackedSameDomainPathsRetainedInEvidence']=True
        mailboxes.append(found)
    assert 'set_max_delay' not in base.read(analysis/'analysis-exceptions.rpt')
    return {'Synchronizers':synchronizers,'Mailboxes':mailboxes,'ReconstructedClockPeriodsNs':periods,
      'AsynchronousSetupHoldSignoffClaimed':False,'MetastabilityMTBFClaimed':False,
      'Artifacts':[base.artifact(p) for p in sorted(analysis.iterdir()) if p.is_file()]}

def preservation_audit(root=ROOT):
    baseline=root/'evidence/sc520-card-recognition/builds/6a50b10a';delivery=root/'evidence/sc520-card-recognition/delivery-0109/manifest.json'
    manifest=json.loads(base.read(delivery));protected=[]
    expected='3A7CD3912C0C72FC6553382E2FB00B61F3A432B251C1C236A35BDFE1FAC7D3F8'
    for p in [Path(manifest['Bit']['Path']),Path(manifest['OriginalBit'])]:
        assert base.sha(p)==expected,('0109 baseline bit changed',p);protected.append(base.artifact(p))
    assert base.sha(manifest['BuildAudit']['Path'])==manifest['BuildAudit']['SHA256']
    prior=json.loads(base.read(baseline/'inputs.json'));snapshots=[];vendor=[]
    for item in prior['Files']:
        if item.get('Snapshot'):
            assert base.sha(item['Snapshot'])==item['SnapshotSHA256'],item['Snapshot'];snapshots.append(base.artifact(item['Snapshot']))
        else:
            # Only external source paths are required to retain their old
            # bytes. The task's live files are checked against the NEW build.
            p=Path(item['Path']).resolve()
            if not p.is_relative_to(root.resolve()):
                assert base.sha(p)==item['SHA256'],('External vendor baseline changed',p);vendor.append(base.artifact(p))
    # Exact latest shared records are the authority for coordinator-owned
    # documentation, including D-025. No directory-wide hash exemption.
    workspace=Path('E:/juan/FPGA');main=workspace/'anlogic-kids-learning-machine'
    names=['AGENTS.md','PROJECT_MEMORY.md','PLAN.md','TASKS.md','DECISIONS.md','docs/03-interface-contracts.md','docs/10-active-coordination.md']
    paths={str((main/name).resolve()).casefold():main/name for name in names};latest={}
    for p in (workspace/'workspace-records').glob('*.json'):
        data=json.loads(base.read(p));stamp=data['UpdatedAt']
        for change in data['Changes']:
            key=str(Path(change['Path']).resolve()).casefold()
            if key in paths and change.get('SHA256') and (key not in latest or stamp>latest[key][0]):latest[key]=(stamp,p,change['SHA256'])
    documentation=[]
    # The original interface may predate SHA-bearing registration; retain its
    # exact previous Protected hash instead of silently accepting the file.
    initial=json.loads(base.read(root/'evidence/sc520-card-recognition/pixel14-baseline.json'))['Protected']
    initial_by_path={str(Path(x['Path']).resolve()).casefold():x for x in initial}
    for key,p in paths.items():
        if key in latest:
            stamp,record,digest=latest[key];assert base.sha(p)==digest,(p,record)
            documentation.append({'Document':base.artifact(p),'Record':base.artifact(record),'UpdatedAt':stamp})
        else:
            assert key in initial_by_path and base.sha(p)==initial_by_path[key]['SHA256'],('Unregistered documentation version',p)
            documentation.append({'Document':base.artifact(p),'Baseline':'pixel14-baseline.json'})
    assert 'D-025' in base.read(main/'DECISIONS.md'),'Rotation decision not found in current coordinator record'
    return {'Baseline0109Bits':protected,'Baseline0109SnapshotsChecked':len(snapshots),'ExternalVendorFilesChecked':len(vendor),
      'BaselineSnapshots':snapshots,'ExternalVendorSources':vendor,'CoordinatorDocuments':documentation,
      'Policy':'Live task-owned files must match the new build input manifest; they are not required to equal old items14/pixel14 source hashes.'}

def audit(run,bindings=None,historical=False,profile='scene'):
    basic=base.audit_build(run,profile,bindings,historical);cdc=cdc_audit(run);preserved=preservation_audit()
    if not historical:assert basic['BaseQualified'],('Unreviewed ROM address/select mappings',basic['UnreviewedAddressOrSelectMappings'])
    return {**basic,**cdc,**preserved,'CandidateQualified':not historical,'HardwareValidated':False,
      'AuditPrograms':[base.artifact(HERE/name) for name in ['audit-scene-build.py','audit-scene-candidate.py',*LEGACY_HASHES]],
      'Limits':'No board, CRC/ECC-content, DDR-frame identity, or MTBF proof. CDC data propagation uses an external 10ns bound; asynchronous phase slack is not signoff.'}

if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('run',type=Path);ap.add_argument('--output',type=Path,required=True)
    ap.add_argument('--bindings',type=Path);ap.add_argument('--historical',action='store_true');ap.add_argument('--profile',choices=['scene','legacy'],default='scene');ap.add_argument('--cdc-only',action='store_true')
    a=ap.parse_args();bindings=json.loads(base.read(a.bindings)) if a.bindings else None
    report=cdc_audit(a.run.resolve()) if a.cdc_only else audit(a.run.resolve(),bindings,a.historical,a.profile)
    if a.cdc_only:report.update(CandidateQualified=False,HardwareValidated=False,ParserExerciseOnly=True)
    base.emit(a.output,report);print(json.dumps({'Output':str(a.output),'Synchronizers':len(report['Synchronizers']),'MailboxBits':{m['Name']:m['Bits'] for m in report['Mailboxes']},'CandidateQualified':report['CandidateQualified']}))
