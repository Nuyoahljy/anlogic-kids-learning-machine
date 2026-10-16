"""Prove three exact routed address-Q replacements with unmodified TD models."""
from pathlib import Path
import argparse
import datetime
import hashlib
import json
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[3]
MODEL = Path('D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release')
VSIM = Path('D:/modeltech64_10.7/win64/vsim.exe')
PREFIX = 'u_p14_pipeline/scene_mode$scene/'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def artifact(path):
    path = Path(path).resolve()
    return {'Path': str(path), 'SHA256': sha(path), 'Bytes': path.stat().st_size}


def net(text):
    return re.sub(r'[\\\s]', '', text)


def cells(text, primitive):
    result = {}
    for m in re.finditer(primitive + r'\s*#\((.*?)\)\s+(\\\S+|\w+)\s*\((.*?)\);', text, re.S):
        params = {k: v.strip() for k, v in re.findall(
            r'\.(\w+)\(("[^"]*"|[^()]*)\)', re.sub(r'//[^\n]*', '', m[1]))}
        ports = {k: net(v) for k, v in re.findall(r'\.(\w+)\(([^()]*)\)', m[3])}
        name = net(m[2])
        assert name not in result
        result[name] = {'Name': name, 'Primitive': primitive, 'Params': params,
                        'Ports': ports, 'Raw': m[0]}
    return result


def instance(cell, label, mapping):
    assert set(cell['Ports'].values()) <= set(mapping), (cell['Name'], cell['Ports'])
    return cell['Primitive'] + ' #(\n' + ',\n'.join(
        ' .' + k + '(' + v + ')' for k, v in cell['Params'].items()) + '\n) ' + label + '(\n' + ',\n'.join(
        ' .' + k + '(' + mapping[v] + ')' for k, v in cell['Ports'].items()) + '\n);\n'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('build', type=Path)
    ap.add_argument('--tag', required=True)
    ap.add_argument('--mode', choices=('normal', 'negative', 'watchdog'), default='normal')
    args = ap.parse_args()
    build = args.build.resolve()
    run = ROOT / 'evidence/sc520-card-recognition/timing23/address-proofs' / args.tag / args.mode
    assert not run.exists(), run
    syn = build / 'td_project/camera_to_dsi_display_Runs/syn_1/pixel14-syn_1-netlist.v'
    route = build / 'td_project/camera_to_dsi_display_Runs/phy_1/pixel14-phy_1-netlist.v'
    inputs = [artifact(p) for p in (syn, route, Path(__file__), VSIM, VSIM.parent.parent / 'modelsim.ini')]
    st, rt = syn.read_text(encoding='utf-8-sig'), route.read_text(encoding='utf-8-sig')
    seqs, luts = cells(st, 'AL_MAP_SEQ_GSR'), cells(st, 'AL_MAP_LUT2')
    physical, buffers = cells(rt, 'PH1P_PHY_LSLICE'), cells(rt, 'PH1P_PHY_SCLK_V2')
    selected, pairs, leaves = [], [], set()
    reset, ce = 'u_p14_pipeline/capture_release[1]', PREFIX + 'card_valid_n'
    output_pins = {'oqa', 'oqb', 'ofa', 'ofb', 'co'}
    for bit, suffix in ((5, '_dup_4'), (6, '_dup_6'), (8, '_dup_3')):
        canonical = PREFIX + f'card_index[{bit}]'
        gate = [c for c in seqs.values() if c['Ports'].get('q') == canonical]
        routed = [c for c in physical.values() if c['Ports'].get('oqa') == canonical + suffix]
        assert len(gate) == len(routed) == 1
        gate, routed = gate[0], routed[0]
        lut = [c for c in luts.values() if c['Ports'].get('o') == gate['Ports']['d']]
        assert len(lut) == 1
        lut = lut[0]
        assert gate['Params'] == {'CEMUX': '"SIG"', 'CLKMUX': '"SIG"', 'DFFMODE': '"FF"',
                                  'REGSET': '"RESET"', 'SRMODE': '"ASYNC"', 'SRMUX': '"INV"'}
        assert gate['Ports']['sr'] == routed['Ports']['asr'] == reset
        assert gate['Ports']['ce'] == routed['Ports']['cea'] == ce
        for key, value in {'ASRMUX': '"INV"', 'CEAMUX': '"SIG"', 'CLKMUX': '"SIG"',
                           'LATCHMODE': '"DFF"', 'LUTMODE': '"DLUT5"', 'OQAMUX': '"QA"',
                           'REGA_REGSET_ASYNC': '"RESET"', 'REGA_SD': '"LUT5A"',
                           'SSRMUX': '"0"', 'SSROVERCE': '"ENABLE"'}.items():
            assert routed['Params'][key] == value, (routed['Name'], key)
        assert lut['Ports']['a'] == PREFIX + 'engine_fault_reg_syn_29'
        assert lut['Ports']['b'] == PREFIX + f'normalize_index[{bit}]'
        assert lut['Params'] == {'EQN': '"(B*~A)"', 'INIT': "4'h4"}
        for cell in (gate, lut, routed):
            for pin, signal in cell['Ports'].items():
                if pin not in output_pins | {'q', 'o', 'clk', 'asr', 'sr', 'ce', 'cea'}:
                    if signal != gate['Ports']['d']:
                        leaves.add(signal)
        pairs.append({'Bit': bit, 'Canonical': canonical, 'Routed': canonical + suffix,
                      'Gate': gate, 'LUT': lut, 'Physical': routed})
        selected += [gate, lut, routed]
    gate_clocks = {p['Gate']['Ports']['clk'] for p in pairs}
    route_clocks = {p['Physical']['Ports']['clk'] for p in pairs}
    assert len(gate_clocks) == len(route_clocks) == 1
    gate_clock, route_clock = gate_clocks.pop(), route_clocks.pop()
    clock = [c for c in buffers.values() if c['Ports'].get('clkout') == route_clock]
    assert len(clock) == 1 and clock[0]['Ports'] == {'clkin': gate_clock, 'clkout': route_clock}
    assert clock[0]['Params'] == {'BYPASS': '"DISABLE"'}
    selected.append(clock[0])
    leaves = sorted(leaves)
    assert len(leaves) <= 12 and all(not x.startswith("1'b") for x in leaves), leaves
    leaf_mapping = {signal: f'leaves[{i}]' for i, signal in enumerate(leaves)}
    body = ''
    for i, p in enumerate(pairs):
        mapping = dict(leaf_mapping)
        mapping.update({reset: 'rst_n', ce: 'ce', gate_clock: 'clk', route_clock: 'rclk',
                        p['Gate']['Ports']['d']: f'd_gate[{i}]', p['Canonical']: f'q_gate[{i}]',
                        p['Routed']: f'q_route[{i}]'})
        for pin, signal in p['Physical']['Ports'].items():
            if pin in output_pins and signal != p['Routed']:
                mapping[signal] = f'unused_{i}_{pin}'
                body += f'wire unused_{i}_{pin};\n'
        body += instance(p['LUT'], f'gate_lut_{i}', mapping)
        body += instance(p['Gate'], f'gate_ff_{i}', mapping)
        body += instance(p['Physical'], f'route_ff_{i}', mapping)
    body += instance(clock[0], 'physical_clock', {gate_clock: 'clk', route_clock: 'rclk'})
    normalize = [leaves.index(PREFIX + f'normalize_index[{p["Bit"]}]') for p in pairs]
    fault = leaves.index(PREFIX + 'engine_fault_reg_syn_29')
    preset = ''.join(f'leaves[{i}]=p;' for i in normalize)
    equations = ''.join(f'ck(20,d_gate[{j}],leaves[{i}]&~leaves[{fault}]);' for j, i in enumerate(normalize))
    expected = ''.join(f'expected[{j}]=rv ? (cv ? (leaves[{i}]&~leaves[{fault}]) : prev[0]) : 0;' for j, i in enumerate(normalize))
    tb = f'''`timescale 1ns/1ps
module tb_address;
reg clk=0,rst_n=1,ce=0;reg [{len(leaves)-1}:0] leaves=0;
wire rclk;wire [2:0] q_gate,q_route,d_gate;
reg [5:0] startup;reg [2:0] expected;
integer errors=0,checks=0,rows=0,prev,rv,cv,v,i,injected=0;
reg test_done=0;
{body}
task ck(input integer id,input got,input want);begin
 checks=checks+1;if(got!==want)begin errors=errors+1;
 if(errors<5)$display("MISMATCH id=%0d t=%0t got=%b want=%b",id,$time,got,want);end
end endtask
task allq(input integer id,input [2:0] want);begin
 for(i=0;i<3;i=i+1)begin ck(id+i,q_gate[i],want[i]);ck(id+3+i,q_route[i],want[i]);end
end endtask
task tick;begin #1;clk=1;#1;clk=0;#1;end endtask
task preset(input p);begin rst_n=1;ce=1;clk=0;leaves=0;{preset}tick;allq(10,{{3{{p}}}});end endtask
initial begin
 #1;startup={{q_gate,q_route}};$display("STARTUP_UNQUALIFIED %b",startup);
 #99;rst_n=0;#1;allq(1,0);rst_n=1;#1;
 for(prev=0;prev<2;prev=prev+1)
 for(rv=0;rv<2;rv=rv+1)
 for(cv=0;cv<2;cv=cv+1)
 for(v=0;v<{1<<len(leaves)};v=v+1)begin
  preset(prev[0]);leaves=v;ce=cv;rst_n=rv;#1;
  {equations}
  expected=rv ? {{3{{prev[0]}}}} : 0;allq(30,expected);
  #1;clk=1;#1;{expected}allq(40,expected);ck(46,rclk,clk);
  #1;clk=0;#1;allq(50,expected);ck(56,rclk,clk);rows=rows+1;
 end
 for(v=0;v<2;v=v+1)begin
  preset(1);ce=0;clk=v;#1;allq(60,7);rst_n=0;#1;allq(70,0);rst_n=1;#1;allq(80,0);
 end
 if({int(args.mode=='negative')})begin
  injected=1;force q_route[0]=1'b1;#1;ck(90,q_route[0],1'b0);release q_route[0];
 end
 test_done=1;$display("ADDRESS_DONE checks=%0d rows=%0d errors=%0d injected=%0d",checks,rows,errors,injected);$finish;
end
endmodule
'''
    run.mkdir(parents=True)
    model_names = ['common/al_map_seq.v', 'common/al_map_lut.v', 'common/al_phy_glbl.v',
                   'ph1p/ph1p_phy_gsr.v', 'ph1p/ph1p_phy_lslice.v', 'ph1p/ph1p_phy_sclk_v2.v']
    for name in model_names:
        shutil.copyfile(MODEL / name, run / Path(name).name)
        inputs.append({**artifact(MODEL / name), 'Snapshot': artifact(run / Path(name).name)})
    shutil.copyfile(VSIM.parent.parent / 'modelsim.ini', run / 'modelsim.ini')
    (run / 'tb_address.sv').write_text(tb, encoding='ascii')
    raw_cells = run / 'exact-cells.v.txt'
    raw_cells.write_text('\n\n'.join(c['Raw'] for c in selected), encoding='utf-8')
    duration = '500 ns' if args.mode == 'watchdog' else '1 ms'
    do = f'''onerror {{quit -force -code 3}}
vlib work
vmap work work
vlog al_phy_glbl.v al_map_seq.v al_map_lut.v ph1p_phy_gsr.v ph1p_phy_lslice.v ph1p_phy_sclk_v2.v
vlog -sv tb_address.sv
vsim -voptargs=+acc -wlf wave.wlf work.tb_address work.PH1P_PHY_GSR work.glbl
onfinish stop
run {duration}
set fd [open summary.json w]
puts $fd [format {{{{"errors":%d,"checks":%d,"rows":%d,"injected":%d,"done":%d}}}} [examine -radix decimal /tb_address/errors] [examine -radix decimal /tb_address/checks] [examine -radix decimal /tb_address/rows] [examine -radix decimal /tb_address/injected] [examine -radix unsigned /tb_address/test_done]]
close $fd
if {{![examine -radix unsigned /tb_address/test_done]}} {{quit -force -code 2}}
if {{[examine -radix decimal /tb_address/errors]}} {{quit -force -code 1}}
quit -force -code 0
'''
    (run / 'run.do').write_text(do, encoding='ascii')
    command = [str(VSIM), '-modelsimini', str(run / 'modelsim.ini'), '-c',
               '-l', 'transcript.log', '-do', 'do run.do']
    with (run / 'stdout.log').open('wb') as out, (run / 'stderr.log').open('wb') as err:
        process = subprocess.run(command, cwd=run, stdout=out, stderr=err, timeout=90,
                                 creationflags=subprocess.CREATE_NO_WINDOW)
    summary = json.loads((run / 'summary.json').read_text()) if (run / 'summary.json').exists() else None
    expected_exit = {'normal': 0, 'negative': 1, 'watchdog': 2}[args.mode]
    qualified = process.returncode == expected_exit and summary is not None
    if qualified:
        qualified = (summary['errors'] == int(args.mode == 'negative') and
                     summary['injected'] == int(args.mode == 'negative') and
                     summary['done'] == int(args.mode != 'watchdog'))
        if args.mode != 'watchdog':
            qualified &= summary['rows'] == 8 * (1 << len(leaves))
    assert inputs[0]['SHA256'] == sha(syn) and inputs[1]['SHA256'] == sha(route)
    report = {'At': datetime.datetime.now().astimezone().isoformat(), 'Verified': bool(qualified),
              'Mode': args.mode, 'NativeExit': process.returncode, 'Command': command, 'Summary': summary,
              'Inputs': inputs, 'LeafSignals': leaves, 'Pairs': [
                  {'Bit': p['Bit'], 'Canonical': p['Canonical'], 'Routed': p['Routed']} for p in pairs],
              'ExactCells': [{k: v for k, v in c.items() if k != 'Raw'} for c in selected],
              'ResetPrecondition': 'Common capture_release[1] asserted after configuration-model release. '
                                  'Before-reset startup is recorded and unqualified.',
              'Scope': 'Local Q transition proof for all connected independent data leaves, both previous states, '
                       'CE/reset states, rising/falling/no-edge hold and async assertion. Unmodified vendor models. '
                       'No SDF, whole-netlist equivalence, MTBF, bitgen or hardware qualification.',
              'Artifacts': [artifact(p) for p in sorted(run.iterdir()) if p.is_file()
                            and p.name not in ('wave.wlf', 'modelsim.ini')]}
    (run / 'proof.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'Run': str(run), 'Verified': qualified, 'NativeExit': process.returncode, 'Summary': summary}))
    raise SystemExit(0 if qualified else 1)


if __name__ == '__main__':
    main()
