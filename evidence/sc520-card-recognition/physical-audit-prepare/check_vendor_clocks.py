"""Exercise the exact fixed-clock buffer configurations with TD vendor models."""
from pathlib import Path
from datetime import datetime,timedelta,timezone
import hashlib,json,shutil,subprocess,uuid

HERE=Path(__file__).resolve().parent
MODEL=Path('D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/ph1p')
VSIM=Path('D:/modeltech64_10.7/win64/vsim.exe')
def digest(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def artifact(p):return {'Path':str(Path(p).resolve()),'SHA256':digest(p),'Bytes':Path(p).stat().st_size}

def main():
    stamp=datetime.now(timezone(timedelta(hours=8))).strftime('%Y%m%d-%H%M%S')
    run=HERE/'vendor-clock-runs'/('check-'+stamp+'-'+uuid.uuid4().hex[:6]);run.mkdir(parents=True,exist_ok=False)
    models=['ph1p_phy_gclk.v','ph1p_phy_sclk_v2.v','ph1p_phy_gsr.v']
    for name in models:shutil.copyfile(MODEL/name,run/name)
    shutil.copyfile(VSIM.parent.parent/'modelsim.ini',run/'modelsim.ini')
    (run/'tb_vendor_clocks.sv').write_text('''`timescale 1ns/1ps
module tb_vendor_clocks;
reg clk0=0,clk1=0;always #5 clk0=~clk0;always #7 clk1=~clk1;
wire global_clock,local_clock;
PH1P_PHY_GCLK g(.clkin({clk1,clk0}),.cen(2'b00),.drct(2'b11),.seln(2'b10),.clkout(global_clock));
PH1P_PHY_SCLK_V2 #(.BYPASS("DISABLE")) s(.clkin(global_clock),.clkout(local_clock));
integer checks=0,errors=0,i;reg test_done=0;reg [3:0] combinations=0;
task ck;begin
 checks=checks+2;combinations[{clk1,clk0}]=1;
 if(global_clock!==clk0)begin errors=errors+1;$display("GCLK mismatch %0t %b %b",$time,global_clock,clk0);end
 if(local_clock!==clk0)begin errors=errors+1;$display("SCLK mismatch %0t %b %b",$time,local_clock,clk0);end
end endtask
initial begin
 #201;
 for(i=0;i<128;i=i+1)begin @(posedge clk0);#1;ck;@(negedge clk0);#1;ck;end
 if(combinations!==4'b1111)errors=errors+1;
 test_done=1;$display("CLOCK_DONE checks=%0d errors=%0d combinations=%b",checks,errors,combinations);$finish;
end
initial begin #10000;$display("CLOCK_WATCHDOG");$finish;end
endmodule
''',encoding='ascii')
    (run/'run.do').write_text('''onerror {quit -force -code 2}
vlib work
vmap work work
vlog ph1p_phy_gsr.v ph1p_phy_gclk.v ph1p_phy_sclk_v2.v
vlog -sv tb_vendor_clocks.sv
vsim -voptargs=+acc -wlf wave.wlf work.tb_vendor_clocks work.PH1P_PHY_GSR
onfinish stop
run -all
set errors [examine -radix decimal /tb_vendor_clocks/errors]
set checks [examine -radix decimal /tb_vendor_clocks/checks]
set done [examine -radix unsigned /tb_vendor_clocks/test_done]
set fd [open summary.json w]
puts $fd [format {{"errors":%d,"checks":%d,"done":%d}} $errors $checks $done]
close $fd
if {!$done} {quit -force -code 2}
if {$errors} {quit -force -code 1}
quit -force -code 0
''',encoding='ascii')
    cmd=[str(VSIM),'-modelsimini',str(run/'modelsim.ini'),'-c','-l','transcript.log','-do','do run.do']
    with (run/'stdout.log').open('wb') as out,(run/'stderr.log').open('wb') as err:
        process=subprocess.run(cmd,cwd=run,stdout=out,stderr=err,timeout=60)
    summary=json.loads((run/'summary.json').read_text()) if (run/'summary.json').exists() else None
    qualified=process.returncode==0 and summary=={'errors':0,'checks':512,'done':1}
    report={'CreatedAt':datetime.now(timezone(timedelta(hours=8))).isoformat(),'Command':cmd,'NativeExit':process.returncode,
            'Summary':summary,'Qualified':qualified,'Inputs':[artifact(MODEL/name) for name in models],
            'Program':artifact(__file__),'Scope':'Unmodified TD6.2.1 functional GCLK/SCLK models. Fixed GCLK cen00/drct11/seln10 selects input0; SCLK ce omitted as routed netlist and BYPASS DISABLE. Not physical clock timing proof.',
            'Artifacts':[artifact(p) for p in sorted(run.iterdir()) if p.is_file() and p.name not in ['wave.wlf','modelsim.ini']]}
    (run/'vendor-clock-audit.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'Run':str(run),'Qualified':qualified,'Summary':summary,'NativeExit':process.returncode}))
    return 0 if qualified else 1
if __name__=='__main__':raise SystemExit(main())
