"""Measure D0113 I2C pad propagation in a disposable timing view (no bitgen)."""
from pathlib import Path
from datetime import datetime,timezone,timedelta
import hashlib,json,subprocess,uuid
ROOT=Path(__file__).resolve().parents[3]
TOOL=Path('D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe')
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def main():
    build=ROOT/'evidence/sc520-card-recognition/builds/6a50b113'
    run=ROOT/'evidence/sc520-card-recognition/scl-coverage'/('io-probe-'+datetime.now().strftime('%Y%m%d-%H%M%S')+'-'+uuid.uuid4().hex[:6]);run.mkdir(parents=True)
    db=build/'td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display_pr.db';sdc=build/'overlay/pixel14.sdc'
    protected={str(p):sha(p) for p in [db,sdc,Path(__file__).resolve()]}
    script='''if {[catch {
import_device ph1_35p.db -package PH1P35MDG324 -speed 3
import_db {@DB@}
read_sdc {@SDC@}
update_timing -mode final
set parent_clock [get_clocks pll_clk_24m]
set scl_port [get_ports O_cam_scl]
set sda_port [get_ports IO_cam_sda]
if {[llength $parent_clock]!=1 || [llength $scl_port]!=1 || [llength $sda_port]!=1} {error "I2C measurement endpoints not resolved"}
# Zero external delay creates reportable output endpoints for MEASUREMENT.
# These commands are not sensor timing constraints and do not alter the bit.
set_output_delay -clock $parent_clock -max 0 $scl_port
set_output_delay -clock $parent_clock -min 0 $scl_port
set_output_delay -clock $parent_clock -max 0 $sda_port
set_output_delay -clock $parent_clock -min 0 $sda_port
set sda_enable [get_pins {IO_cam_sda_syn_2.ts}]
if {[llength $sda_enable]!=1} {error "Open-drain pad enable not resolved"}
# The data pin is tied low. Report the actual output-enable cone explicitly;
# TD does not include the tri-state control as an output-delay endpoint.
set_max_delay -from [get_regs {u_uicfgcs520/u_i2c/*}] -to $sda_enable 100.0
update_timing -mode final
report_timing_path -to [get_ports O_cam_scl] -ep_num 4 -path_num 20 -file scl-pad.rpt
report_timing_path -to [get_ports IO_cam_sda] -ep_num 4 -path_num 20 -file sda-pad.rpt
report_timing_path -to $sda_enable -ep_num 4 -path_num 20 -file sda-enable.rpt
report_timing_exception -file probe-exceptions.rpt
} msg]} {puts stderr $msg;exit 1}
puts "I2C_IO_PROBE_DONE"
exit 0
'''.replace('@DB@',db.as_posix()).replace('@SDC@',sdc.as_posix())
    (run/'probe.tcl').write_text(script,encoding='utf-8')
    command=[str(TOOL),(run/'probe.tcl').as_posix()]
    with (run/'stdout.log').open('wb') as out,(run/'stderr.log').open('wb') as err:r=subprocess.run(command,cwd=run,stdout=out,stderr=err,timeout=180)
    assert all(sha(p)==h for p,h in protected.items())
    has_paths=all((run/name).exists() and 'Data Path Delay' in (run/name).read_text(encoding='utf-8',errors='replace') for name in ['scl-pad.rpt','sda-enable.rpt'])
    result={'CreatedAt':datetime.now(timezone(timedelta(hours=8))).isoformat(),'Command':command,'ExitCode':r.returncode,'NonemptyPathReports':has_paths,'ProtectedInputs':protected,
      'NoDatabaseOrBitModified':True,'Purpose':'Routed SCL FF-to-pad and SDA FF-to-tristate-enable propagation measurements only. Artificial zero-output-delay/100ns-enable endpoints are measurement aids, not external sensor constraints. SDA enable-to-pad analog propagation, RC rise/fall, pullups and board loading are not established.'}
    (run/'result.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8');print(json.dumps({'run':str(run),'exit_code':r.returncode,'nonempty':has_paths}));return 0 if r.returncode==0 and has_paths else 1
if __name__=='__main__':raise SystemExit(main())
