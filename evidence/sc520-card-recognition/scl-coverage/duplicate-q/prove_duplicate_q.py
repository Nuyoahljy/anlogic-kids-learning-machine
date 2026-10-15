"""Exact D0113 card_index[5] duplicate-Q proof with unmodified TD models.

This is a local functional cutpoint proof, not netlist-wide equivalence or STA.
Every actual data leaf at the two routed LSLICEs is exhaustively varied; unused
physical pins retain their vendor defaults. No duplicate-name normalization.
"""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import hashlib, itertools, json, re, shutil, subprocess, uuid

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
BUILD = ROOT / 'evidence/sc520-card-recognition/builds/6a50b113'
MODEL = Path('D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release')
VSIM = Path('D:/modeltech64_10.7/win64/vsim.exe')
S = 'u_p14_pipeline/scene_mode$scene/'
B = 'u_p14_pipeline/blocks/'
C = 'u_mipi_dphy_rx_ph1p_mipiio_wrapper/u_ph1p_mipiio_rx_wrapper/'
GATE_CLK = 'u_isp_top/u_demosaic/raw_matrix_3x3_buffer_d/zhenghe_d/blk_mem_gen_zhenghe_d1/ram_d32970204f32_Inst/clkb'
ROUTE_CLK = C + 'bufg_feedback_auto_created_sclk_s_1_r_bk2_sclk_outnet'
RESET = 'u_p14_diag_cdc/src_reset[1]'

def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def artifact(p):
    p = Path(p).resolve()
    return {'Path': str(p), 'SHA256': sha(p), 'Bytes': p.stat().st_size}
def clean(s): return re.sub(r'[\\\s]', '', s)
def cells(text, kind):
    result = {}
    selected = {'AL_MAP_SEQ_GSR': {S+'card_index_reg[5]'}, 'AL_MAP_LUT2': {S+'sel62_syn_2542'},
                'PH1P_PHY_LSLICE': {B+'top_edge_reg[20]_syn_5', S+'card_index_reg[7]_syn_2'},
                'PH1P_PHY_SCLK_V2': {C+'bufg_feedback_auto_created_sclk_s_1_r_bk2'}}[kind]
    for m in re.finditer(kind + r'\s*#\((.*?)\)\s+(\\\S+|\w+)\s*\((.*?)\);', text, re.S):
        name = clean(m[2])
        if name not in selected: continue
        raw = re.sub(r'//[^\n]*', '', m[1])
        params = {k: v.strip() for k, v in re.findall(r'\.(\w+)\(("[^"]*"|[^()]*)\)', raw)}
        ports = {k: clean(v) for k, v in re.findall(r'\.(\w+)\(([^()]*)\)', m[3])}
        assert name not in result
        result[name] = {'Name': name, 'Primitive': kind, 'Params': params, 'Ports': ports,
                        'Line': text[:m.start()].count('\n') + 1, 'Raw': m[0]}
    return result
def inst(cell, label, mapping):
    ports = cell['Ports']
    assert set(ports.values()) <= set(mapping), (cell['Name'], set(ports.values()) - set(mapping))
    return cell['Primitive'] + ' #(\n' + ',\n'.join(' .' + k + '(' + v + ')' for k,v in cell['Params'].items()) + '\n) ' + label + '(\n' + ',\n'.join(' .' + k + '(' + mapping[v] + ')' for k,v in ports.items()) + '\n);\n'

def main():
    syn = BUILD / 'td_project/camera_to_dsi_display_Runs/syn_1/pixel14-syn_1-netlist.v'
    route = BUILD / 'td_project/camera_to_dsi_display_Runs/phy_1/pixel14-phy_1-netlist.v'
    inputs = [artifact(syn), artifact(route)]
    st, rt = syn.read_text(encoding='utf-8-sig'), route.read_text(encoding='utf-8-sig')
    seq = cells(st, 'AL_MAP_SEQ_GSR')[S + 'card_index_reg[5]']
    lut = cells(st, 'AL_MAP_LUT2')[S + 'sel62_syn_2542']
    slices = cells(rt, 'PH1P_PHY_LSLICE')
    dup3 = slices[B + 'top_edge_reg[20]_syn_5']
    dup4 = slices[S + 'card_index_reg[7]_syn_2']
    sclk = cells(rt, 'PH1P_PHY_SCLK_V2')[C + 'bufg_feedback_auto_created_sclk_s_1_r_bk2']
    assert seq['Params'] == {'CEMUX':'"SIG"','CLKMUX':'"SIG"','DFFMODE':'"FF"','REGSET':'"RESET"','SRMODE':'"ASYNC"','SRMUX':'"INV"'}
    assert seq['Ports'] == {'ce':S+'card_valid_n','clk':GATE_CLK,'d':S+'sel62_syn_1382','sr':RESET,'q':S+'card_index[5]'}
    assert lut['Params'] == {'EQN':'"(B*~A)"','INIT':"4'h4"}
    assert lut['Ports'] == {'a':S+'engine_fault_reg_syn_29','b':S+'normalize_index[5]','o':S+'sel62_syn_1382'}
    assert dup3['Ports']['oqb'] == S+'card_index[5]_dup_3'
    assert dup3['Ports']['imb'] == S+'sel62_syn_1382'
    assert dup4['Ports']['oqb'] == S+'card_index[5]_dup_4'
    assert dup4['Ports']['ofb'] == S+'sel62_syn_1382'
    assert dup4['Ports']['ia'] == S+'engine_fault_reg_syn_29'
    assert dup4['Ports']['ie'] == S+'normalize_index[5]'
    for c in (dup3, dup4):
        assert all(c['Params'][k] == v for k,v in {'ASRMUX':'"INV"','CEBMUX':'"SIG"','CLKMUX':'"SIG"','LATCHMODE':'"DFF"','LUTMODE':'"DLUT5"','OQBMUX':'"QB"','REGB_REGSET_ASYNC':'"RESET"','REGB_REGSET_SYNC':'"RESET"','SSRMUX':'"0"','SSROVERCE':'"ENABLE"'}.items())
        assert c['Ports']['asr'] == RESET and c['Ports']['ceb'] == S+'card_valid_n' and c['Ports']['clk'] == ROUTE_CLK
        assert not any(k in c['Params'] for k in ['GSR','TESTMODE','LUT8MODE'])
    assert dup3['Params']['REGB_SD'] == '"IMB"'
    assert dup4['Params']['REGB_SD'] == '"LUT6"'
    assert dup4['Params']['INIT_LUT5B'] == "32'b01010101010101010000000000000000"
    assert dup4['Params']['OFB_SD'] == '"LUTX"'
    assert sclk['Params'] == {'BYPASS':'"DISABLE"'}
    assert sclk['Ports'] == {'clkin':GATE_CLK,'clkout':ROUTE_CLK}
    stamp = datetime.now(timezone(timedelta(hours=8))).strftime('%Y%m%d-%H%M%S')
    run = HERE / ('run-' + stamp + '-' + uuid.uuid4().hex[:6]); run.mkdir(parents=True, exist_ok=False)
    models = ['common/al_map_seq.v','common/al_map_lut.v','common/al_phy_glbl.v','ph1p/ph1p_phy_gsr.v','ph1p/ph1p_phy_lslice.v','ph1p/ph1p_phy_sclk_v2.v']
    for p in models:
        shutil.copyfile(MODEL/p, run/Path(p).name)
        inputs.append(artifact(MODEL/p))
    shutil.copyfile(VSIM.parent.parent/'modelsim.ini', run/'modelsim.ini')
    inputs.append(artifact(__file__))
    selected = [seq, lut, dup3, dup4, sclk]
    (run/'exact-cells.v.txt').write_text('\n\n'.join(x['Raw'] for x in selected), encoding='utf-8')
    (run/'bindings.json').write_text(json.dumps([{k:v for k,v in x.items() if k!='Raw'} for x in selected], indent=2)+'\n',encoding='utf-8')
    mapping = {S+'engine_fault_reg_syn_29':'leaves[0]',S+'normalize_index[5]':'leaves[1]',S+'normalize_index[7]':'leaves[2]',
               B+'top_edge[0][0]':'leaves[3]',S+'replay_y[0]':'leaves[4]',B+'top_edge_reg[23]_syn_24':'leaves[5]',
               B+'bottom_edge_reg[23]_syn_4':'leaves[6]',B+'bottom_edge_reg[23]_syn_116':'leaves[7]',
               RESET:'rst_n',S+'card_valid_n':'ce',GATE_CLK:'clk',ROUTE_CLK:'rclk',S+'card_index[5]':'q_gate',
               S+'card_index[5]_dup_3':'q_dup3',S+'card_index[5]_dup_4':'q_dup4',S+'card_index[7]':'qa4',S+'sel62_syn_1382':'d_gate'}
    # Cut the co-packed A-side feedback leaf to an independent input. This is
    # stronger for QB than assuming any reachable sequence of the A-side FF.
    d3map = dict(mapping); d3map[S+'sel62_syn_1382']='d_route'
    d4map = dict(mapping); d4map[S+'sel62_syn_1382']='d_route'
    d3 = inst(dup3, 'route_dup3', d3map).replace('.oqa(leaves[3])','.oqa(qa3)')
    body = inst(lut,'gate_lut',mapping)+inst(seq,'gate_ff',mapping)+inst(sclk,'route_buffer',mapping)+d3+inst(dup4,'route_dup4',d4map)
    tb = '''`timescale 1ns/1ps
module tb_duplicate_q;
reg clk=0,rst_n=1,ce=0;reg [7:0] leaves=0;
wire rclk,q_gate,q_dup3,q_dup4,d_gate,d_route,qa3,qa4;
integer errors=0,checks=0,rows=0,comb_rows=0,prev,rv,cv,v,pol;
reg test_done=0;reg expected;
''' + body + '''
task ck(input integer id,input got,input want);begin
 checks=checks+1;
 if(got!==want)begin errors=errors+1;if(errors<12)$display("MISMATCH id=%0d time=%0t got=%b want=%b leaves=%h ce=%b rst=%b prev=%0d",id,$time,got,want,leaves,ce,rst_n,prev);end
end endtask
task allq(input integer id,input want);begin ck(id,q_gate,want);ck(id+1,q_dup3,want);ck(id+2,q_dup4,want);end endtask
task tick;begin #1;clk=1;#1;clk=0;#1;end endtask
task preset(input p);begin
 rst_n=1;ce=1;clk=0;leaves=0;leaves[1]=p;leaves[2]=p;tick;allq(10,p);
end endtask
initial begin
 // Vendor configuration models assert their own power-up reset. Check zero
 // at 1ns, but compare normal transitions only after both done_gwe intervals.
 #1;allq(1,0);#24;rst_n=0;#1;allq(4,0);rst_n=1;#1;
 for(prev=0;prev<2;prev=prev+1)
 for(rv=0;rv<2;rv=rv+1)
 for(cv=0;cv<2;cv=cv+1)
 for(v=0;v<256;v=v+1)begin
   preset(prev[0]);
   leaves=v;ce=cv;rst_n=rv;#1;
   ck(20,d_gate,leaves[1]&~leaves[0]);ck(21,d_route,d_gate);comb_rows=comb_rows+1;
   expected=rv ? prev[0] : 1'b0;allq(30,expected);
   #1;clk=1;#1;
   expected=rv ? (cv ? (leaves[1]&~leaves[0]) : prev[0]) : 1'b0;
   allq(40,expected);ck(43,rclk,clk);
   #1;clk=0;#1;allq(50,expected);ck(53,rclk,clk);
   rows=rows+1;
 end
 // Async assertion at both clock levels, with CE=0 and a loaded one.
 for(pol=0;pol<2;pol=pol+1)begin
   preset(1);ce=0;clk=pol;#1;allq(60,1);
   rst_n=0;#1;allq(70,0);rst_n=1;#1;allq(80,0);
 end
 test_done=1;$display("DUPLICATE_Q_DONE rows=%0d comb_rows=%0d checks=%0d errors=%0d",rows,comb_rows,checks,errors);$finish;
end
initial begin #100000; $display("DUPLICATE_Q_WATCHDOG");$finish;end
endmodule
'''
    (run/'tb_duplicate_q.sv').write_text(tb,encoding='ascii')
    do = '''onerror {quit -force -code 2}
vlib work
vmap work work
vlog al_phy_glbl.v al_map_seq.v al_map_lut.v ph1p_phy_gsr.v ph1p_phy_lslice.v ph1p_phy_sclk_v2.v
vlog -sv tb_duplicate_q.sv
vsim -voptargs=+acc -wlf wave.wlf work.tb_duplicate_q work.PH1P_PHY_GSR work.glbl
onfinish stop
run -all
set errors [examine -radix decimal /tb_duplicate_q/errors]
set checks [examine -radix decimal /tb_duplicate_q/checks]
set rows [examine -radix decimal /tb_duplicate_q/rows]
set comb_rows [examine -radix decimal /tb_duplicate_q/comb_rows]
set done [examine -radix unsigned /tb_duplicate_q/test_done]
set fd [open summary.json w]
puts $fd [format {{"errors":%d,"checks":%d,"rows":%d,"comb_rows":%d,"done":%d}} $errors $checks $rows $comb_rows $done]
close $fd
if {!$done} {quit -force -code 2}
if {$errors} {quit -force -code 1}
quit -force -code 0
'''
    (run/'run.do').write_text(do,encoding='ascii')
    cmd=[str(VSIM),'-modelsimini',str(run/'modelsim.ini'),'-c','-l','transcript.log','-do','do run.do']
    with (run/'stdout.log').open('wb') as out,(run/'stderr.log').open('wb') as err:
        process=subprocess.run(cmd,cwd=run,stdout=out,stderr=err,timeout=90)
    summary=json.loads((run/'summary.json').read_text()) if (run/'summary.json').exists() else None
    passed = process.returncode==0 and summary is not None and summary['errors']==0 and summary['done']==1 and summary['rows']==2048 and summary['comb_rows']==2048
    assert inputs[0]['SHA256']==sha(syn) and inputs[1]['SHA256']==sha(route), 'Netlist changed during proof'
    report={'CreatedAt':datetime.now(timezone(timedelta(hours=8))).isoformat(),'Verified':passed,'NativeExit':process.returncode,'Command':cmd,'Summary':summary,'Inputs':inputs,
        'GateNet':S+'card_index[5]','RoutedEquivalentNets':[S+'card_index[5]_dup_3',S+'card_index[5]_dup_4'],
        'ExactCells':[{k:v for k,v in x.items() if k!='Raw'} for x in selected],
        'Equation':'After configuration: Q+ = !src_reset[1] ? 0 : card_valid_n ? (normalize_index[5] & !engine_fault_reg_syn_29) : Q; rising original/buffered clock. Async src_reset[1] falling edge clears Q independently of CE.',
        'ProofDomain':'All 256 combinations of 8 connected data leaves x 2 previous QB values x 2 CE x 2 reset values. Gate LUT and routed OFB compared on all rows. Rising-edge update, falling-edge hold, no-edge hold, async reset at both clock levels. The A-side feedback is cut to an arbitrary leaf, so no reachability assumption about the co-packed A FF is needed.',
        'Initialization':'Unmodified common glbl and physical PH1P_PHY_GSR power-up models give zero at 1ns; transitions start after 25ns. Gate default GSR=DISABLE, INI=0; physical default GSR=ENABLE, async register RESET. Their configuration-release windows differ (common done_gwe 10ns; physical done_gwe/gsrn 20ns). This proof does not assert identical arbitrary user-GSR responses or preconfiguration capture timing; normal reset establishes equal zero states.',
        'Limitations':['Local functional cutpoint equivalence only; not all design signals, not four-state/X propagation proof.','No SDF, setup/hold or recovery/removal margin proof; STA is separate.','No hardware operation, no bit generation, no historical audit modification.'],
        'Artifacts':[artifact(p) for p in sorted(run.iterdir()) if p.is_file() and p.name not in ['wave.wlf','modelsim.ini']]}
    (run/'proof.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'Run':str(run),'Verified':passed,'NativeExit':process.returncode,'Summary':summary},ensure_ascii=False))
    return 0 if passed else 1

if __name__=='__main__': raise SystemExit(main())
