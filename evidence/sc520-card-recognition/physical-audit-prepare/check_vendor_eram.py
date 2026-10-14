"""Read every initialized word through the unmodified TD6.2.1 ERAM model."""
from pathlib import Path
import datetime,hashlib,importlib.util,json,random,shutil,subprocess,uuid
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2]
spec=importlib.util.spec_from_file_location('vendor_eram_decode',ROOT/'fpga/custom_project/sc520-pixel14/tools/audit-scene-build.py');audit=importlib.util.module_from_spec(spec);spec.loader.exec_module(audit)
MODEL=Path('D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/ph1p')
VSIM=Path('D:/modeltech64_10.7/win64/vsim.exe')
def main():
    run=HERE/'vendor-eram-runs'/('check-'+datetime.datetime.now().strftime('%Y%m%d-%H%M%S')+'-'+uuid.uuid4().hex[:6]);run.mkdir(parents=True)
    rng=random.Random(5200109);values={**{f'INIT_{i:02X}':f'{rng.getrandbits(256):064X}' for i in range(64)},**{f'INITP_{i:02X}':f'{rng.getrandbits(256):064X}' for i in range(16)}}
    params=',\n'.join(f".{k}(256'h{v})" for k,v in values.items())
    lines=['`timescale 1ns/1ps','module tb_vendor_eram;','reg clk=0;always #5 clk=~clk;','integer index=0,errors=0,checks=0;reg test_done=0;integer i;']
    widths=[1,2,5,10,20,40]
    for w in widths:
        words=audit.init_decode(values,w);(run/f'expected{w}.mem').write_text('\n'.join(f'{x:010X}' for x in words)+'\n')
        shift=(w if w<5 else w*4//5).bit_length()-1
        lines += [f'wire [15:0] da{w},db{w};wire [3:0] pa{w},pb{w};wire [13:0] address{w}=(index<<{shift}) | {((1<<shift)-1)};',
          f'reg [39:0] expected{w}[0:{len(words)-1}]; initial $readmemh("expected{w}.mem",expected{w});',
          'PH1P_PHY_ERAM_V2 #('+f'.MODE("{"PDP20K" if w==40 else "DP20K"}"),.DATA_WIDTH_A("{w}"),.DATA_WIDTH_B("{w}"),'+
          '.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WEAMUX("0"),.WEBMUX("0"),.RSTAMUX("0"),.RSTBMUX("0"),.CSA0("1"),.CSA1("1"),.CSA2("1"),.CSB0("1"),.CSB1("1"),.CSB2("1"),'+params+')',
          f'ram{w}(.clka({"1\'b0" if w==40 else "clk"}),.clkb(clk),.addra(address{w}),.addrb(address{w}),.wea(1\'b0),.web(1\'b0),.orsta(1\'b0),.orstb(1\'b0),.ocea(1\'b1),.oceb(1\'b1),.csa(3\'b111),.csb(3\'b111),.dia(16\'d0),.dib(16\'d0),.dia_extra(4\'d0),.dib_extra(4\'d0),.doa(da{w}),.dob(db{w}),.doa_extra(pa{w}),.dob_extra(pb{w}));']
        if w<=2:expression=f'db{w}[{w-1}:0]'
        elif w<=20:expression='{'+','.join(f'pb{w}[{g}],db{w}[{4*g+3}:{4*g}]' for g in reversed(range(w//5)))+'}'
        else:expression='{'+','.join(f'{p}40[{g}],d{h}40[{4*g+3}:{4*g}]' for h,p in [('b','pb'),('a','pa')] for g in reversed(range(4)))+'}'
        lines.append(f'wire [{w-1}:0] got{w}={expression};')
    lines += ['initial begin #101;','for(i=0;i<16384;i=i+1)begin @(negedge clk);index=i;@(posedge clk);#1;']
    for w in widths:
        n=16384//w if w<5 else 20480//w
        lines += [f'if(i<{n})begin checks=checks+1;if(got{w}!==expected{w}[i][{w-1}:0])begin errors=errors+1;if(errors<12)$display("ERAM_MISMATCH width={w} address=%0d got=%h expected=%h",i,got{w},expected{w}[i]);end end']
    lines += ['end','test_done=1;$display("ERAM_DONE checks=%0d errors=%0d",checks,errors);$finish;end','initial begin #1000000;errors=errors+1;$display("WATCHDOG");$finish;end','endmodule']
    (run/'tb_vendor_eram.sv').write_text('\n'.join(lines)+'\n')
    for name in ['ph1p_phy_eram_v2.v','ph1p_phy_gsr.v']:shutil.copyfile(MODEL/name,run/name)
    shutil.copyfile(VSIM.parent.parent/'modelsim.ini',run/'modelsim.ini')
    do='''onerror {quit -force -code 2}
vlib work
vmap work work
vlog ph1p_phy_gsr.v ph1p_phy_eram_v2.v
vlog -sv tb_vendor_eram.sv
vsim -voptargs=+acc -wlf wave.wlf work.tb_vendor_eram work.PH1P_PHY_GSR
onfinish stop
run -all
set errors [examine -radix decimal /tb_vendor_eram/errors]
set checks [examine -radix decimal /tb_vendor_eram/checks]
set done [examine -radix unsigned /tb_vendor_eram/test_done]
set f [open summary.json w]
puts $f [format {{"errors":%d,"checks":%d,"done":%d}} $errors $checks $done]
close $f
if {!$done} {quit -force -code 2}
if {$errors} {quit -force -code 1}
quit -force -code 0
'''
    (run/'run.do').write_text(do);cmd=[str(VSIM),'-modelsimini',str(run/'modelsim.ini'),'-c','-l','transcript.log','-do','do run.do']
    with (run/'stdout.log').open('wb') as out,(run/'stderr.log').open('wb') as err:p=subprocess.run(cmd,cwd=run,stdout=out,stderr=err,timeout=120)
    summary=json.loads((run/'summary.json').read_text()) if (run/'summary.json').exists() else None
    report={'Command':cmd,'NativeExit':p.returncode,'Summary':summary,'Inputs':[audit.artifact(MODEL/n) for n in ['ph1p_phy_eram_v2.v','ph1p_phy_gsr.v']],
      'Parser':audit.artifact(ROOT/'fpga/custom_project/sc520-pixel14/tools/audit-scene-build.py'),'PhysicalWidth40Order':'low20=doa/doa_extra; high20=dob/dob_extra; PDP20K read clock B, inactive write clock A',
      'Qualified':p.returncode==0 and summary and summary['done']==1 and summary['errors']==0 and summary['checks']==32256,
      'HardwareValidated':False,'Scope':'Unmodified TD vendor functional ERAM model, randomized INIT and INITP, every initialized address at widths1/2/5/10/20/40.'}
    report['Artifacts']=[audit.artifact(q) for q in sorted(run.iterdir()) if q.is_file() and q.name not in ['wave.wlf','modelsim.ini']]
    audit.emit(run/'vendor-model-audit.json',report);print(json.dumps({'Run':str(run),'Qualified':report['Qualified'],'NativeExit':p.returncode,'Summary':summary}))
    return 0 if report['Qualified'] else 1
if __name__=='__main__':raise SystemExit(main())
