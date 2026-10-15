"""Scene-build ROM/bit/input/STA audit. Never writes a historical build.

The general INIT decoder is independent of logical ROM packing. Logical
bindings record every physical output bit and word-address pin. Large banks
whose select/mux cone has not been reviewed are deliberately not qualified.
"""
from pathlib import Path
import argparse,collections,datetime,hashlib,json,math,re

def read(p):return Path(p).read_text(encoding='utf-8-sig',errors='replace')
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def artifact(p):
    p=Path(p).resolve();return {'Path':str(p),'Bytes':p.stat().st_size,'SHA256':sha(p)}
def net(s):return re.sub(r'[\\\s]','',s)
def now():return datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat()
def emit(p,x):
    p=Path(p).resolve();p.parent.mkdir(parents=True,exist_ok=True)
    with p.open('x',encoding='utf-8',newline='\n') as f:json.dump(x,f,ensure_ascii=False,indent=2);f.write('\n')

def init_decode(values,width):
    """Logical width 5n interleaves four data bits and one INITP bit.

    Widths 1/2 use the 16K data array only. Width40 has eight such groups;
    its physical output-half order must be explicitly supplied to port_bits.
    """
    assert width in (1,2,5,10,20,40),width
    required={f'INIT_{i:02X}' for i in range(64)}|{f'INITP_{i:02X}' for i in range(16)}
    assert set(values)==required,'Incomplete or extra INIT/INITP fields'
    data=sum(int(values[f'INIT_{i:02X}'],16)<<(256*i) for i in range(64))
    parity=sum(int(values[f'INITP_{i:02X}'],16)<<(256*i) for i in range(16))
    if width<=2:return [(data>>(a*width))&((1<<width)-1) for a in range(16384//width)]
    groups=width//5;db=groups*4
    result=[]
    for a in range(4096//groups):
        d=(data>>(a*db))&((1<<db)-1);p=(parity>>(a*groups))&((1<<groups)-1)
        result.append(sum((((d>>(4*g))&15)|(((p>>g)&1)<<4))<<(5*g) for g in range(groups)))
    return result

def declarations(text):
    found={}
    for m in re.finditer(r'(?m)^\s*(?:wire|reg|input|output|inout)\s+(?:\[(\d+):(\d+)\]\s+)?(\\\S+|[A-Za-z_$][\w$]*)\s*;',text):
        hi,lo=m.group(1,2);found[net(m[3])]=(int(hi),int(lo)) if hi is not None else None
    return found
def split_top(s):
    result=[];start=0;depth=0
    for i,c in enumerate(s):
        if c=='{':depth+=1
        elif c=='}':depth-=1
        elif c==',' and depth==0:result.append(s[start:i]);start=i+1
    result.append(s[start:]);return result
def bits(s,decl):
    """Expand a Verilog concatenation to individual pins, least-significant first."""
    s=s.strip()
    if s.startswith('{'):
        assert s.endswith('}'),s
        inner=s[1:-1].strip();repeat=re.fullmatch(r'(\d+)\{(.*)\}',inner,re.S)
        if repeat:return bits('{'+repeat[2]+'}',decl)*int(repeat[1])
        return [b for part in reversed(split_top(inner)) for b in bits(part,decl)]
    m=re.fullmatch(r"(\d+)'([bhdo])([0-9A-Fa-f_xXzZ]+)",s)
    if m:
        assert not re.search('[xXzZ]',m[3]),('Unknown constant',s)
        n=int(m[3].replace('_',''),{'b':2,'h':16,'d':10,'o':8}[m[2]])
        return [str((n>>i)&1) for i in range(int(m[1]))]
    m=re.fullmatch(r'(\\\S+|[A-Za-z_$][\w$/.]*)(?:\s+)?(?:\[(\d+)(?::(\d+))?\])?',s)
    assert m,('Unsupported pin expression',s)
    name=net(m[1]);hi,lo=m.group(2,3)
    if hi is not None:
        hi=int(hi);lo=int(lo) if lo is not None else hi
        return [f'{name}[{i}]' for i in range(lo,hi+1)] if hi>=lo else [f'{name}[{i}]' for i in range(lo,hi-1,-1)]
    if name in decl and decl[name] is not None:
        hi,lo=decl[name];return [f'{name}[{i}]' for i in range(lo,hi+1)]
    return [name]

def memories(text):
    decl=declarations(text);result=[]
    for m in re.finditer(r'PH1P_PHY_ERAM_V2\s*#\((.*?)\)\s+(\\\S+|\w+)\s*\((.*?)\);',text,re.S):
        values=dict(re.findall(r"\.(INITP?_[0-9A-F]{2})\(256'h([0-9A-Fa-f]+)\)",m[1]))
        if not values:continue
        params=dict(re.findall(r'\.(\w+)\("([^"]*)"\)',m[1]))
        ports={key:value.strip() for key,value in re.findall(r'\.(\w+)\(([^()]*)\)',m[3])}
        sig=hashlib.sha256(json.dumps({'Init':values,'WidthA':params.get('DATA_WIDTH_A'),'WidthB':params.get('DATA_WIDTH_B'),'Mode':params.get('MODE')},sort_keys=True).encode()).hexdigest().upper()
        result.append({'Name':net(m[2]),'Params':params,'Ports':ports,'Values':values,'Signature':sig,'Declarations':decl})
    return result

def port_bits(memory,port='b',wide_order=None):
    p=memory['Ports'];decl=memory['Declarations'];width=int(memory['Params']['DATA_WIDTH_'+port.upper()])
    def part(name):return bits(p.get(name,"16'b0" if not name.endswith('extra') else "4'b0"),decl)
    if width<=20:
        d=part('do'+port);extra=part('do'+port+'_extra')
        if width<=2:return d[:width]
        return [extra[g] if k==4 else d[g*4+k] for g in range(width//5) for k in range(5)]
    assert port=='b' and memory['Params'].get('MODE')=='PDP20K','Only verified PDP20K read-B width40 layout is supported'
    if wide_order is None:wide_order=['a','b']
    assert wide_order==['a','b'],'Vendor-model verified width40 order is low20 A, high20 B'
    result=[]
    for half in wide_order:
        d=part('do'+half);extra=part('do'+half+'_extra')
        result += [extra[g] if k==4 else d[g*4+k] for g in range(4) for k in range(5)]
    return result

def word_address_bits(memory,port='b'):
    width=int(memory['Params']['DATA_WIDTH_'+port.upper()]);db=width if width<=2 else width*4//5
    shift=int(math.log2(db));pins=bits(memory['Ports']['addr'+port],memory['Declarations'])
    assert len(pins)==14,(memory['Name'],len(pins),pins)
    assert all(b in ('0','1') for b in pins[:shift]),('Unused byte-address pins must be constant',memory['Name'])
    return pins[shift:]

def routed_clock_buffers(text):
    """Resolve exact inserted SCLK and fixed-input-0 GCLK configurations."""
    result={}
    for m in re.finditer(r'PH1P_PHY_SCLK_V2\s*#\((.*?)\)\s+(\\\S+|\w+)\s*\((.*?)\);',text,re.S):
        params=dict(re.findall(r'\.(\w+)\("([^"]*)"\)',re.sub(r'//[^\n]*','',m[1])))
        ports={k:net(v) for k,v in re.findall(r'\.(\w+)\(([^()]*)\)',m[3])}
        assert set(ports)=={'clkin','clkout'},('Unexpected SCLK control ports',net(m[2]),ports)
        assert params=={'BYPASS':'DISABLE'},('Unreviewed SCLK mode',net(m[2]),params)
        assert ports['clkout'] not in result,('Multiply-driven clock buffer',ports['clkout'])
        result[ports['clkout']]={'Input':ports['clkin'],'Instance':net(m[2]),'Primitive':'PH1P_PHY_SCLK_V2','Params':params}
    decl=declarations(text)
    for m in re.finditer(r'PH1P_PHY_GCLK\s+(?://[^\n]*\n\s*)*(\\\S+|\w+)\s*\((.*?)\);',text,re.S):
        ports={k:v.strip() for k,v in re.findall(r'\.(\w+)\(([^()]*)\)',m[2])}
        assert set(ports)=={'clkin','clkout','cen','drct','seln'},('Unreviewed GCLK ports',net(m[1]),ports)
        controls={key:bits(ports[key],decl) for key in ('cen','drct','seln')}
        assert controls=={'cen':['0','0'],'drct':['1','1'],'seln':['0','1']},('GCLK is not fixed input0',net(m[1]),controls)
        inputs=bits(ports['clkin'],decl);outputs=bits(ports['clkout'],decl)
        assert len(inputs)==2 and len(outputs)==1 and not inputs[0].startswith('open_n')
        assert outputs[0] not in result,('Multiply-driven GCLK output',outputs[0])
        result[outputs[0]]={'Input':inputs[0],'Instance':net(m[1]),'Primitive':'PH1P_PHY_GCLK','FixedControlsLSB':controls}
    return result

def routed_rom_controls(gate,route,clock_buffers):
    """Carry reviewed gate bank-select/control bindings through routing.

    INIT equality alone does not prove that the routed ROM still has the same
    CS, read mode, enable, or reset. Unconnected pin labels may be renamed;
    clocks may pass through explicit SCLK instances, recorded edge by edge.
    """
    gp,rp=gate['Params'],route['Params']
    metadata={'RID','WID','READBACK'}
    assert {k:v for k,v in gp.items() if k not in metadata}=={k:v for k,v in rp.items() if k not in metadata},('Routed ROM functional parameters changed',gate['Name'])
    for key in ('RID','WID'):
        if key in rp:assert re.fullmatch(r'0[Xx][0-9a-fA-F]+',rp[key]),('Invalid routed RAM metadata',key,rp[key])
    if 'READBACK' in rp:assert rp['READBACK']=='DISABLE',('Unexpected readback configuration',gate['Name'])
    assert set(gate['Ports'])==set(route['Ports']),('Routed ROM port set changed',gate['Name'])
    clocks={};checked={}
    for port in gate['Ports']:
        before=bits(gate['Ports'][port],gate['Declarations']);after=bits(route['Ports'][port],route['Declarations'])
        assert len(before)==len(after),(gate['Name'],port,'port width changed')
        if port in ('clka','clkb'):
            assert len(before)==1
            node=after[0];trail=[];visited=set()
            while node!=before[0]:
                assert node not in visited and node in clock_buffers,('Unresolved routed ROM clock source',gate['Name'],port,before,after,trail)
                visited.add(node);edge=clock_buffers[node];trail.append({'Output':node,**edge});node=edge['Input']
            clocks[port]={'GateClockNet':before[0],'RoutedClockNet':after[0],'InsertedBuffers':trail}
        else:
            for i,(a,b) in enumerate(zip(before,after)):
                if a.startswith('open_n'):assert b.startswith('open_n'),('Unused ROM pin became driven',gate['Name'],port,i,a,b)
                else:assert a==b,('Routed ROM data/address/control connection changed',gate['Name'],port,i,a,b)
            checked[port]=[x for x in before if not x.startswith('open_n')]
    return {'FunctionalParametersMatched':True,'ConnectedPinBindings':checked,'ClockConnections':clocks}

def logical_roms(run,profile):
    font={int(a):int(b,16) for a,b in re.findall(r"rom\[12'd(\d+)\]=16'h([0-9A-Fa-f]+)",read(run/'rtl/items14_font_rom.v'))}
    assert set(font)==set(range(4096))
    roms={'font':{'Words':[font[a] for a in range(4096)],'Width':16,'Instance':r'/system/panel/font/',
                   'Output':r'/system/panel/font_bits\[(\d+)\]$', 'ConstantZeroBits':[0]}}
    template=[int(x,16) for x in read(run/'templates.mem').split()]
    if profile=='legacy':
        assert len(template)==1024
        width=max(template).bit_length();assert width in (5,10,15,20)
        roms['template']={'Words':template,'Width':width,'Instance':r'/matcher/templates/','Output':r'/matcher/templates/data\[(\d+)\]$','ConstantZeroBits':[]}
    else:
        assert len(template)%400==0 and 1<=len(template)//400<=256 and all(0<=v<32 for v in template)
        roms['rotation']={'Words':template,'Width':5,'Instance':r'[/\$](?:rotation_matcher|matcher)/.*(?:template|ramread)',
                          'Output':r'/(?:template_q|template_mem[^/]*|template_data)\[(\d+)\]$','ConstantZeroBits':[]}
        shape=[]
        shape_source=run/'rtl/pixel14_block_shape_guard.v';assert shape_source.exists()
        for a in range(1024):
            x=a%32-6;y=a//32-6;v=0
            if 0<=x<20 and 0<=y<20:
                dx=2*x+1-20;dy=2*y+1-20
                v=int(dx*dx+dy*dy<=400)|2|(int(2*abs(dx)<=2*y+1)<<2)
            shape.append(v)
        roms['shape']={'Words':shape,'Width':3,'Instance':r'[/\$](?:shape_guard|block_shape_guard)/.*(?:templates|ramread)',
                      'Output':r'/(?:template_bits|templates/data)\[(\d+)\]$','ConstantZeroBits':[]}
    return roms

def rom_audit(run,profile='scene',routed=True,bindings=None):
    syn=run/'td_project/camera_to_dsi_display_Runs/syn_1/pixel14-syn_1-netlist.v'
    route=run/'td_project/camera_to_dsi_display_Runs/phy_1/pixel14-phy_1-netlist.v'
    syn_text=read(syn);route_text=read(route) if routed else ''
    sms=memories(syn_text);pms=memories(route_text) if routed else []
    clock_buffers=routed_clock_buffers(route_text) if routed else {}
    signatures=collections.Counter(m['Signature'] for m in pms)
    used=collections.Counter();expected=logical_roms(run,profile);reports=[];unreviewed=[]
    binding_rows=(bindings or {}).get('Bindings',{})
    if bindings:
        assert bindings['SynNetlistSHA256']==sha(syn),'ROM binding was reviewed for a different netlist'
        proof=bindings['Proof'];assert sha(proof['Path'])==proof['SHA256']
        evidence=json.loads(read(proof['Path']))
        assert evidence['Verified'] and evidence['SynNetlistSHA256']==sha(syn)
        for source in evidence['Sources']:assert sha(source['Path'])==source['SHA256'],source['Path']
    for kind,spec in expected.items():
        coverage=[0]*len(spec['Words']);seen=[]
        for mem in sms:
            if not re.search(spec['Instance'],mem['Name']):continue
            if mem['Params'].get('WEAMUX')!='0' or mem['Params'].get('WEBMUX')!='0':continue
            row=binding_rows.get(mem['Name'],{});port=row.get('Port','b')
            pins=port_bits(mem,port,row.get('WideOutputOrder'));address=word_address_bits(mem,port)
            mapping={}
            for physical,signal in enumerate(pins):
                match=re.search(spec['Output'],signal)
                if match:mapping[physical]=int(match[1])
            if row:
                assert row['Kind']==kind and row['OutputPinsLSB']==pins and row['WordAddressPinsLSB']==address
                mapping={int(k):v for k,v in row['LogicalOutputBits'].items()}
            assert mapping,('Unresolved ROM output mapping; add reviewed exact binding',mem['Name'],pins)
            assert len(set(mapping.values()))==len(mapping) and all(0<=b<spec['Width'] for b in mapping.values())
            words=init_decode(mem['Values'],int(mem['Params']['DATA_WIDTH_'+port.upper()]));depth=len(words)
            candidate_bases=[]
            for base in range(0,len(spec['Words']),depth):
                if all(all(((words[a]>>pb)&1)==((spec['Words'][base+a]>>lb)&1) for pb,lb in mapping.items())
                       for a in range(min(depth,len(spec['Words'])-base))):candidate_bases.append(base)
            if row:assert row['LogicalBase'] in candidate_bases;base=row['LogicalBase']
            else:
                assert len(candidate_bases)==1,('Ambiguous/wrong ROM data bank',mem['Name'],candidate_bases)
                base=candidate_bases[0]
            checked=min(depth,len(spec['Words'])-base)
            for a in range(checked):
                mask=sum(1<<b for b in mapping.values());assert not coverage[base+a]&mask,('Duplicate logical ROM bit coverage',kind,base+a)
                coverage[base+a]|=mask
            # Content identifies a bank, but does not prove that its high-bit
            # chip select/mux is driven by that bank's address. Bind/review it.
            needs_review=len(spec['Words'])>depth or kind=='shape' or profile=='scene'
            reviewed=bool(row and row.get('AddressAndSelectReviewed') and row.get('Evidence'))
            if reviewed:
                for item in row['Evidence']:assert item==bindings['Proof'] and sha(item['Path'])==item['SHA256']
            if needs_review and not reviewed:unreviewed.append(mem['Name'])
            used[mem['Signature']]+=1
            routed_controls=None
            if routed:
                assert used[mem['Signature']]<=signatures[mem['Signature']],('Routed signature multiplicity missing',mem['Name'])
                actual=[r for r in pms if r['Name']==mem['Name'] and r['Signature']==mem['Signature']]
                assert len(actual)==1,('Routed ROM instance/signature changed',mem['Name'])
                rpins=port_bits(actual[0],port,row.get('WideOutputOrder'))
                assert all(rpins[i]==pin for i,pin in enumerate(pins) if not pin.startswith('open_n')),('Routed output wiring changed',mem['Name'],pins,rpins)
                assert word_address_bits(actual[0],port)==address,('Routed ROM address wiring changed',mem['Name'])
                routed_controls=routed_rom_controls(mem,actual[0],clock_buffers)
            entry={'Kind':kind,'GateInstance':mem['Name'],'Primitive':'PH1P_PHY_ERAM_V2','Width':int(mem['Params']['DATA_WIDTH_'+port.upper()]),
                'LogicalBase':base,'WordsChecked':checked,'LogicalOutputBits':mapping,'OutputPinsLSB':pins,'WordAddressPinsLSB':address,
                'Signature':mem['Signature'],'RoutedSignatureCount':signatures[mem['Signature']],
                'AddressAndSelectReviewed':reviewed,'Evidence':row.get('Evidence',[]),'RoutedControlBindings':routed_controls}
            reports.append(entry);seen.append(mem['Name'])
        assert seen,('No physical ROM found',kind)
        expected_mask=(1<<spec['Width'])-1
        for bit in spec['ConstantZeroBits']:
            assert all((word>>bit)&1==0 for word in spec['Words'])
            # The known all-zero font column is optimized away, not silently
            # treated as a missing initialized storage column.
            expected_mask &= ~(1<<bit)
        assert all(c==expected_mask for c in coverage),('Incomplete ROM logical coverage',kind,collections.Counter(coverage))
        if kind=='font':assert len(seen)==3,('Expected three font ROM planes',seen)
    return {'ROMs':reports,'UnreviewedAddressOrSelectMappings':unreviewed,
            'LogicalWords':{k:len(s['Words']) for k,s in expected.items()},'SynNetlist':artifact(syn),
            'RoutedNetlist':artifact(route) if routed else None,'RoutedSignaturesChecked':routed}

def validate_inputs(run,strict_current=True):
    manifest=json.loads(read(run/'inputs.json'));different=[];checked=0
    for item in manifest['Files']:
        p=Path(item['Path']);checked+=1
        if not p.exists() or sha(p)!=item['SHA256']:different.append(str(p))
        if item.get('Snapshot'):assert sha(item['Snapshot'])==item['SnapshotSHA256'],item['Snapshot']
        elif strict_current:assert p.exists() and sha(p)==item['SHA256'],('Unsealed external input changed',str(p))
    if strict_current:assert not different,('Current build inputs changed',different)
    return {'InputsChecked':checked,'CurrentSourceDifferences':different,'SnapshotHashesMatched':True}

def resource_report(text):
    values={};limits={}
    for key,value,limit in re.findall(r'(?m)^\s*#([\w *]+?)\s+(\d+)(?:\s+out of\s+(\d+))?\s*(?:[0-9.]+%)?\s*$',text):
        key=key.strip();values[key]=int(value)
        if limit:limits[key]=int(limit)
    assert values and 'dsp' in values and 'eram' in values
    over={k:{'Used':values[k],'Available':v} for k,v in limits.items() if values[k]>v}
    return {'Used':values,'Available':limits,'OverCapacity':over}

def audit_build(run,profile='scene',bindings=None,historical=False):
    phy=run/'td_project/camera_to_dsi_display_Runs/phy_1';result=json.loads(read(run/'result.json'))
    assert not result['ChangedInputs']
    assert [(x['Stage'],x['ExitCode'],x['MarkerFresh']) for x in result['Stages']]==[('syn_1',0,True),('phy_1',0,True)]
    inputs=validate_inputs(run,not historical);roms=rom_audit(run,profile,True,bindings)
    text=read(phy/'camera_to_dsi_display_pr.timing')
    metrics={k:float(re.search(r'\b'+k+r':\s*(-?[0-9.]+)ns',text)[1]) for k in ['SWNS','STNS','HWNS','HTNS']}
    assert metrics['SWNS']>=0 and metrics['HWNS']>=0 and metrics['STNS']==metrics['HTNS']==0,metrics
    area=read(phy/'camera_to_dsi_display_phy.area');resources=resource_report(area)
    assert 'slice*' in resources['Available'] or 'slice' in resources['Available'],'Missing physical slice capacity'
    assert not resources['OverCapacity'],resources
    keys=[]
    for i,location in enumerate(['D5','A9','B9','C7']):
        m=re.search(r'I_quiz_keys_n\['+str(i)+r'\]\s+INPUT\s+(\S+)\s+(\S+)\s+\S+\s+\S+\s+(\S+)',area)
        assert m and m.groups()==(location,'LVCMOS33','PULLUP');keys.append({'Index':i,'Ball':location,'Direction':'INPUT','IOStandard':'LVCMOS33','Pull':'PULLUP'})
    errors=[];warnings=[]
    for stage in ['syn_1','phy_1']:
        log=read(run/(stage+'.stdout.log'))
        errors += [line for line in log.splitlines() if re.search(r'\bERROR:|unknown module|black.?box',line,re.I)]
        warnings += [line for line in log.splitlines() if 'CRITICAL-WARNING' in line]
    assert not errors,errors
    assert sha(result['Bit'])==result['SHA256'] and Path(result['Bit']).stat().st_size==result['Bytes']
    return {'AuditedAt':now(),'Run':str(run),'Profile':profile,'HistoricalReadOnly':historical,
       **inputs,**roms,'TimingNs':metrics,'Resources':resources,'KeyIO':keys,'CriticalWarnings':warnings,'Bit':artifact(result['Bit']),
       'BaseQualified':not historical and not roms['UnreviewedAddressOrSelectMappings'],
       'CandidateQualified':False,'HardwareValidated':False,'Limits':'CDC is a separate check. Unreviewed bank select/address mapping prevents scene qualification.'}

if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('run',type=Path);ap.add_argument('--output',required=True,type=Path)
    ap.add_argument('--profile',choices=['scene','legacy'],default='scene');ap.add_argument('--rom-only',action='store_true');ap.add_argument('--syn-only',action='store_true');ap.add_argument('--historical',action='store_true');ap.add_argument('--bindings',type=Path)
    args=ap.parse_args();bindings=json.loads(read(args.bindings)) if args.bindings else None
    report=rom_audit(args.run.resolve(),args.profile,not args.syn_only,bindings) if args.rom_only else audit_build(args.run.resolve(),args.profile,bindings,args.historical)
    if args.rom_only:report.update(CandidateQualified=False,HardwareValidated=False,DecoderExerciseOnly=True)
    emit(args.output,report);print(json.dumps({'Output':str(args.output),'ROMs':len(report['ROMs']),'BaseQualified':report.get('BaseQualified',False),'PendingBindings':len(report['UnreviewedAddressOrSelectMappings'])}))
