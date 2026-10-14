"""Review exact candidate critical warnings against the preserved0109 baseline."""
from pathlib import Path
import argparse,collections,importlib.util,json,re
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2]
spec=importlib.util.spec_from_file_location('warning_audit_base',ROOT/'fpga/custom_project/sc520-pixel14/tools/audit-scene-build.py')
base=importlib.util.module_from_spec(spec);spec.loader.exec_module(base)
spec=importlib.util.spec_from_file_location('warning_phy_parser',ROOT/'fpga/custom_project/sc520-pixel14/tools/audit-recovery.py')
phys=importlib.util.module_from_spec(spec);spec.loader.exec_module(phys)

def warnings(run):
    lines=[]
    for stage in ('syn_1','phy_1'):
        for line in base.read(run/(stage+'.stdout.log')).splitlines():
            if 'CRITICAL-WARNING' in line:lines.append(line)
    return lines
def canonical(line):return re.sub(r'/builds/[a-f0-9]{8}/','/builds/<run>/',line)

def local_rows(log):
    tail=log.split('CTS Local Wire Summary',1)[1].split('PHY-5088',1)[0]
    rows=[]
    for line in tail.splitlines():
        if '|' not in line:continue
        fields=[x.strip() for x in line.split('|')]
        if len(fields)==6 and fields[4].strip() in ['u_uicfgcs520/u_i2c/scl_clk'] or ('O_cam_24m_' in line and '|' in line):
            rows.append(line)
    return rows

def main():
    ap=argparse.ArgumentParser();ap.add_argument('run',type=Path);ap.add_argument('--output',required=True,type=Path);a=ap.parse_args()
    run=a.run.resolve();old=ROOT/'evidence/sc520-card-recognition/builds/6a50b10a'
    current_warnings=warnings(run);old_warnings=warnings(old)
    assert collections.Counter(map(canonical,current_warnings))==collections.Counter(map(canonical,old_warnings)),'New or changed critical warning requires explicit review'
    phy=run/'td_project/camera_to_dsi_display_Runs/phy_1';netlist=phy/'pixel14-phy_1-netlist.v'
    cells=phys.slices(base.read(netlist));unused=[];log=base.read(run/'phy_1.stdout.log')
    for direction in ('forward','backward'):
        for signal in ('fault_meta','fault_sync'):
            target=f'u_p14_pipeline/{direction}/{signal}'
            assert not [(name,pin) for name,(_,ports) in cells.items() for pin in ('oqa','oqb') if ports.get(pin)==target],('Removed CDC constraint actually has physical register',target)
            unused.append(target)
        assert f'PIXEL14_CDC_OPTIMIZED_CONSTANT {direction} fault' in log
    clock_report=phy/'route_clock_utilization.txt';text=base.read(clock_report)
    stem='u_uicfgcs520/u_i2c/scl_clk_created_gclkinst.clkout'
    # The same pin occurs in the 13-column global resource table and again
    # in its per-clock detail table. Bind the named resource columns only.
    rows=[line for line in text.splitlines() if stem in line and
          len(line.split('|')[1:-1])==13]
    assert len(rows)==1,rows
    fields=[x.strip() for x in rows[0].split('|')[1:-1]]
    assert fields[3]==stem and fields[8]==fields[9]=='25' and fields[10]==fields[11]=='',('SCL coverage status changed; inspect the new report',rows)
    old_clock=old/'td_project/camera_to_dsi_display_Runs/phy_1/route_clock_utilization.txt'
    old_rows=[line for line in base.read(old_clock).splitlines() if stem in line and
              len(line.split('|')[1:-1])==13]
    assert len(old_rows)==1
    old_fields=[x.strip() for x in old_rows[0].split('|')[1:-1]]
    assert old_fields[3]==stem and old_fields[8]==old_fields[9]=='27' and old_fields[10]==old_fields[11]==''
    manifest=json.loads(base.read(run/'inputs.json'));prior=json.loads(base.read(old/'inputs.json'))
    current=[x for x in manifest['Files'] if x['Path'].replace('\\','/').endswith('/uics500_cfg/uii2c.v')]
    previous=[x for x in prior['Files'] if x['Path'].replace('\\','/').endswith('/uics500_cfg/uii2c.v')]
    assert len(current)==len(previous)==1 and current[0]['SHA256']==previous[0]['SHA256']
    assert base.sha(current[0]['Path'])==current[0]['SHA256']
    output={'AuditedAt':base.now(),'Run':str(run),'CriticalWarningsReviewed':True,'Identical0109WarningMultiset':True,
        'CriticalWarnings':current_warnings,'OptimizedAwayFaultRegisters':unused,
        'MixedClockDataUse':['u_uicfgcs520/u_i2c/scl_clk','O_cam_24m_syn_3'],
        'CurrentLocalRoutingRows':local_rows(log),'BaselineLocalRoutingRows':local_rows(base.read(old/'phy_1.stdout.log')),
        'InheritedUnconstrainedClockBranch':{'Clock':'u_uicfgcs520/u_i2c/scl_clk','CurrentRow':rows[0],'BaselineRow':old_rows[0],
            'Source':base.artifact(current[0]['Path']),'ClockAndPeriodColumnsBlank':True,'CompleteSTAClaimed':False,
            'CurrentPhysicalClockLoads':25,'BaselinePhysicalClockLoads':27,
            'CountMeaning':'Clock loads in route_clock_utilization, not a logical flip-flop count.'},
        'QualificationBoundary':'Current original constrained STA and17 synchronizers/three payload mailboxes are audited. Matching historical warnings does not qualify the unclocked I2C SCL branch or external camera IO timing. No FPGA source, constraint, report, database, or bit was changed.',
        'Evidence':[base.artifact(p) for p in [netlist,clock_report,old_clock,run/'syn_1.stdout.log',run/'phy_1.stdout.log',old/'syn_1.stdout.log',old/'phy_1.stdout.log',run/'inputs.json',old/'inputs.json']],
        'Program':base.artifact(Path(__file__).resolve())}
    base.emit(a.output,output);print(json.dumps({'Output':str(a.output),'Warnings':len(current_warnings),'Matched0109':True,'InheritedSCLCoverageGap':True}))
if __name__=='__main__':main()
