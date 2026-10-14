"""Prove candidate-specific ROM bank selects and mux bit mapping from syn RTL."""
from pathlib import Path
import argparse,functools,importlib.util,json,re
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2]
spec=importlib.util.spec_from_file_location('scene_binding_base',ROOT/'fpga/custom_project/sc520-pixel14/tools/audit-scene-build.py');audit=importlib.util.module_from_spec(spec);spec.loader.exec_module(audit)

def cells(text,kind):
    result={}
    for m in re.finditer(kind+r'\s*#\((.*?)\)\s+(\\\S+|\w+)\s*\((.*?)\);',text,re.S):
        params=dict(re.findall(r'\.(\w+)\("([^"]*)"\)',re.sub(r'//[^\n]*','',m[1])))
        for k,w,radix,v in re.findall(r"\.(\w+)\((\d+)'([bh])([0-9a-fA-F]+)\)",m[1]):params[k]=int(v,2 if radix=='b' else 16)
        ports={k:audit.net(v) for k,v in re.findall(r'\.(\w+)\(([^()]*)\)',m[3])}
        result[audit.net(m[2])]=(params,ports)
    return result

def main():
    ap=argparse.ArgumentParser();ap.add_argument('run',type=Path);ap.add_argument('--tag',required=True);a=ap.parse_args();run=a.run.resolve()
    gate=run/'td_project/camera_to_dsi_display_Runs/syn_1/pixel14-syn_1-netlist.v';before=audit.sha(gate);text=audit.read(gate)
    memories=audit.memories(text);decl=audit.declarations(text)
    graph={};lut_instances={}
    for n in range(1,7):
        for name,(params,ports) in cells(text,f'AL_MAP_LUT{n}').items():
            if not all(x in ports for x in 'abcdef'[:n]):continue
            graph[ports['o']]=(params['INIT'],[ports[x] for x in 'abcdef'[:n]]);lut_instances[ports['o']]=name
    seq=cells(text,'AL_MAP_SEQ_GSR');slices=cells(text,'PH1P_PHY_LSLICE')
    def evaluate(node,env,trail=None):
        if node in env:return env[node]
        if node in ('0','1',"1'b0","1'b1"):return int(node[-1])
        assert node in graph,('Unresolved combinational proof leaf',node)
        init,inputs=graph[node];value=(init>>sum(evaluate(x,env)<<i for i,x in enumerate(inputs)))&1
        env[node]=value;return value
    prefix='u_p14_pipeline/rotation_mode$matcher/'
    bankroms=[m for m in memories if m['Name'].startswith(prefix+'ramread0_')]
    assert len(bankroms)==25,('Unexpected rotation ROM count',len(bankroms))
    expected=[int(x,16) for x in audit.read(run/'templates.mem').split()];assert len(expected)==102400
    baseline=ROOT/'evidence/sc520-card-recognition/builds/6a50b10a/td_project/camera_to_dsi_display_Runs/syn_1/pixel14-syn_1-netlist.v'
    old_fonts={m['Name']:m for m in audit.memories(audit.read(baseline)) if '/system/panel/font/' in m['Name']}
    rows={};bankinfo=[];proofs=[]
    for m in bankroms:
        assert m['Params']['DATA_WIDTH_B']=='5' and m['Params']['WEAMUX']==m['Params']['WEBMUX']=='0'
        words=audit.init_decode(m['Values'],5);candidates=[b for b in range(25) if words==expected[4096*b:4096*(b+1)]]
        assert len(candidates)==1,(m['Name'],candidates);bank=candidates[0]
        outputs=audit.port_bits(m);assert len(outputs)==5 and all(x.startswith(prefix+'ramread0_syn_') for x in outputs)
        addresses=audit.word_address_bits(m)
        want=[prefix+f'mask_address[{i}]' for i in range(4)]+[prefix+f'rom_address[{i}]' for i in range(4,12)]
        assert addresses==want,(m['Name'],addresses)
        # RTL clears both counters, increments rom_address each scan, and
        # wraps mask_address at399. 400 is a multiple of16, so low4 are equal.
        rtl=audit.read(run/'rtl/pixel14_rotation_matcher.v')
        assert 'mask_address==399 ? 0 : mask_address+1' in rtl and 'rom_address<=rom_address+1' in rtl
        assert all((word%400)&15==word&15 for word in range(102400))
        active=[]
        for group in range(32):
            for scan in [0,1]:
                env={prefix+f'rom_address[{i}]':(group>>(i-12))&1 for i in range(12,17)}
                env[prefix+'state_reg_syn_1[3]']=scan
                for port in ['a','b']:
                    signals=audit.bits(m['Ports']['cs'+port],decl);selected=1
                    for bit,signal in enumerate(signals):
                        mode=m['Params']['CS'+port.upper()+str(bit)]
                        selected &= int(mode) if mode in ('0','1') else evaluate(signal,env.copy())^(mode=='INV')
                    assert selected==int(scan and group==bank),(m['Name'],port,group,scan,selected,bank)
                if scan and group==bank:active.append(group)
        rows[m['Name']]={'Kind':'rotation','Port':'b','LogicalBase':bank*4096,'LogicalOutputBits':{str(i):i for i in range(5)},
           'OutputPinsLSB':outputs,'WordAddressPinsLSB':addresses,'AddressAndSelectReviewed':True}
        bankinfo.append({'Bank':bank,'Instance':m['Name'],'OutputPinsLSB':outputs,'SelectedHighAddress':active})
    assert sorted(b['Bank'] for b in bankinfo)==list(range(25))
    # Prove the five registered high-address select bits capture12..16 during
    # SCAN and hold outside it. These are the mux controls one cycle after ROM.
    for i in range(5):
        target=prefix+f'rom_address[12]_syn_55[{i}]'
        matches=[(name,p,q) for name,(p,q) in seq.items() if q.get('q')==target];assert len(matches)==1
        name,params,ports=matches[0];assert params['CEMUX']=='1' and params['SRMUX']=='0'
        for address in [0,1]:
            for scan in [0,1]:
                for old in [0,1]:
                    env={prefix+f'rom_address[{12+i}]':address,prefix+'state_reg_syn_1[3]':scan,target:old}
                    assert evaluate(ports['d'],env)==(address if scan else old)
        proofs.append({'RegisteredSelect':target,'Cell':name,'SourceBit':12+i,'TruthRows':8})
    # The final mux was absorbed into the first distance-adder LUT5B. Prove
    # its actual INIT table gives mask XOR selected class bit, including both
    # values of every unselected-bank background. No name-only bit inference.
    mux_checks=0
    for col in range(5):
        key=prefix+f'class_best[0]_b{27+col}[0]'
        candidates=[(name,p,q) for name,(p,q) in slices.items() if q.get('ic')==key+'_syn_16' and q.get('ie')==key+'_syn_10']
        assert len(candidates)==1,(col,candidates)
        name,p,q=candidates[0]
        assert q['ia']==prefix+'rom_address[12]_syn_55[3]' and q['imb']==prefix+'mask_q' and q['imf']==prefix+f'distance[{col}][0]'
        assert p['LUT5B_SD2']=='IMB' and p['LUT5A_SD1']=='IMF' and p['INIT_LUT5A']==0xffff0000 and p['FCIMUX']=='0'
        for bank in range(25):
            for selected in [0,1]:
                for background in [0,1]:
                    env={prefix+f'rom_address[12]_syn_55[{i}]':(bank>>i)&1 for i in range(5)}
                    for row in bankinfo:
                        for bit,signal in enumerate(row['OutputPinsLSB']):env[signal]=selected if row['Bank']==bank and bit==col else background
                    c=evaluate(q['ic'],env.copy());e=evaluate(q['ie'],env.copy())
                    for mask in [0,1]:
                        for unused_b in [0,1]:
                            index=((bank>>3)&1)|(unused_b<<1)|(c<<2)|(mask<<3)|(e<<4)
                            assert ((p['INIT_LUT5B']>>index)&1)==(mask^selected),(col,bank,selected,background,mask)
                            mux_checks+=1
        proofs.append({'ClassBit':col,'FinalAdderCell':name,'INIT_LUT5B':p['INIT_LUT5B'],'Output':q['ofb'],'Operation':'distance LSB + (mask XOR same class template bit)'})
    # Font address binding is bit-for-bit the accepted0109 physical wiring;
    # glyph contents may change and are checked separately against111 source.
    for m in memories:
        if '/system/panel/font/' in m['Name']:
            old=old_fonts[m['Name']];assert audit.word_address_bits(m)==audit.word_address_bits(old)
            pins=audit.port_bits(m);mapping={str(i):int(re.search(r'font_bits\[(\d+)\]$',x)[1]) for i,x in enumerate(pins)}
            rows[m['Name']]={'Kind':'font','Port':'b','LogicalBase':0,'LogicalOutputBits':mapping,'OutputPinsLSB':pins,
                'WordAddressPinsLSB':audit.word_address_bits(m),'AddressAndSelectReviewed':True}
            assert all(m['Params']['CS'+port+str(i)]=='1' for port in ['A','B'] for i in range(3))
    shape=[m for m in memories if '/shape_mode$shape_guard/templates/' in m['Name']];assert len(shape)==1
    m=shape[0];pins=audit.port_bits(m);addresses=audit.word_address_bits(m)
    assert addresses==[f'u_p14_pipeline/scene_mode$scene/card_index[{i}]' for i in range(10)]+['0','0']
    mapping={str(i):int(match[1]) for i,x in enumerate(pins) if (match:=re.search(r'/templates/data\[(\d+)\]$',x))}
    assert mapping=={'0':0,'1':1,'2':2}
    assert m['Params']['CSB0']==m['Params']['CSB1']=='1' and m['Params']['CSB2']=='SIG'
    assert audit.bits(m['Ports']['csb'],decl)[2]=='u_p14_pipeline/shape_mode$shape_guard/rom_enable'
    rows[m['Name']]={'Kind':'shape','Port':'b','LogicalBase':0,'LogicalOutputBits':mapping,'OutputPinsLSB':pins,
        'WordAddressPinsLSB':addresses,'AddressAndSelectReviewed':True}
    assert len(rows)==29
    assert audit.sha(gate)==before,'Netlist changed during proof'
    proof={'Verified':True,'SynNetlistSHA256':before,'BankCount':25,'WordsCompared':102400,'ClassBits':5,
      'BankSelectTruthRows':25*32*2*2,'MuxTruthRows':mux_checks,'RegisteredSelectTruthRows':40,'Banks':sorted(bankinfo,key=lambda x:x['Bank']),
      'Proofs':proofs,'FontAddressBaseline':audit.artifact(baseline),'Sources':[audit.artifact(p) for p in [gate,run/'templates.mem',run/'rtl/pixel14_rotation_matcher.v',run/'rtl/pixel14_block_shape_guard.v',Path(__file__).resolve()]],
      'Scope':'Syn-netlist exact INIT words, physical address order, read bank chip selects, high-address selector registration and five class-bit mux/arithmetic LUT tables. Routed signatures and timing remain separate.'}
    proofpath=HERE/f'rom-binding-proof-{a.tag}.json';audit.emit(proofpath,proof)
    for row in rows.values():row['Evidence']=[audit.artifact(proofpath)]
    document={'SynNetlistSHA256':before,'Proof':audit.artifact(proofpath),'Bindings':rows}
    audit.emit(HERE/f'rom-bindings-{a.tag}.json',document)
    print(json.dumps({'Verified':True,'Bindings':len(rows),'Banks':25,'Words':102400,'MuxTruthRows':mux_checks,'Proof':str(proofpath)}))
if __name__=='__main__':main()
