"""Read-only STA experiment on the retained112 routed database; no bitgen/export."""
from pathlib import Path
from datetime import datetime,timezone,timedelta
import hashlib,json,subprocess,uuid

ROOT=Path(__file__).resolve().parents[3]
OLD=ROOT/'evidence/sc520-card-recognition/builds/6a50b112'
TOOL=Path('D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe')
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def main():
    stamp=datetime.now(timezone(timedelta(hours=8))).strftime('%Y%m%d-%H%M%S')
    run=ROOT/'evidence/sc520-card-recognition/scl-coverage'/('constraint-probe-'+stamp+'-'+uuid.uuid4().hex[:6]);run.mkdir(parents=True)
    db=OLD/'td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display_pr.db'
    sdc=OLD/'overlay/pixel14.sdc'
    hashes={str(p):sha(p) for p in [db,sdc,Path(__file__)]}
    script='''if {[catch {
import_device ph1_35p.db -package PH1P35MDG324 -speed 3
import_db {@DB@}
read_sdc {@SDC@}
help create_generated_clock
report_clock_summary -file original-clocks.rpt
set source_pin [get_pins {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[1]}]
set scl_net [get_nets {u_uicfgcs520/u_i2c/scl_clk_syn_105}]
puts "SCL_SOURCE $source_pin SCL_NET $scl_net"
if {[llength $source_pin]!=1 || [llength $scl_net]!=1} {error "clock source/target not unique"}
create_generated_clock -name I2C_SCL -source $source_pin -edges {237 475 713} $scl_net
update_timing -mode final
report_clock_summary -file augmented-clocks.rpt
set regs [get_regs {u_uicfgcs520/u_i2c/*}]
set fd [open i2c-registers.txt w];puts $fd $regs;close $fd
report_timing_path -to $regs -ep_num 400 -path_num 2 -file i2c-inbound.rpt
report_timing_path -from $regs -ep_num 400 -path_num 2 -file i2c-outbound.rpt
report_timing_exception -file augmented-exceptions.rpt
report_timing_ignored -file augmented-ignored.rpt
} msg]} {puts stderr $msg;exit 1}
puts "SCL_PROBE_DONE"
exit 0
'''.replace('@DB@',db.as_posix()).replace('@SDC@',sdc.as_posix())
    (run/'probe.tcl').write_text(script,encoding='utf-8')
    command=[str(TOOL),(run/'probe.tcl').as_posix()]
    with (run/'stdout.log').open('wb') as out,(run/'stderr.log').open('wb') as err:
        p=subprocess.run(command,cwd=run,stdout=out,stderr=err,timeout=180)
    assert all(sha(p)==h for p,h in hashes.items()),'Frozen input mutation'
    result={'CreatedAt':datetime.now(timezone(timedelta(hours=8))).isoformat(),'Command':command,'ExitCode':p.returncode,
            'Inputs':hashes,'SourceDivider':237,'HalfPeriodParentClocks':119,'ParentPeriodNs':42,'GeneratedEdges':[237,475,713],
            'ExternalSCLDelayParentClocks':90,'NoBitOrDatabaseModified':True,'HardwareValidated':False}
    (run/'result.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'run':str(run),'exit_code':p.returncode}));return p.returncode
if __name__=='__main__':raise SystemExit(main())
