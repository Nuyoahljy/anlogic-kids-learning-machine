"""Audit frozen TD output, decode all ROM INIT words, and retain explicit failed timing."""
from pathlib import Path
import argparse, collections, datetime, hashlib, json, re

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def read(p):return Path(p).read_text(encoding='utf-8-sig',errors='replace')
def memories(text):
    found=[]
    for m in re.finditer(r'PH1P_PHY_ERAM_V2\s*#\((.*?)\)\s+(\\\S+|\w+)\s*\((.*?)\);',text,re.S):
        values=dict(re.findall(r'\.(INITP?_[0-9A-F]{2})\(256\'h([0-9A-Fa-f]+)\)',m[1]))
        if not values:continue
        signature=hashlib.sha256(json.dumps(values,sort_keys=True).encode()).hexdigest()
        found.append((m,values,signature))
    return found

def audit(run):
    syn=run/'td_project/camera_to_dsi_display_Runs/syn_1'
    phy=run/'td_project/camera_to_dsi_display_Runs/phy_1'
    result=json.loads(read(run/'result.json'))
    inputs=json.loads(read(run/'inputs.json'))
    gate=syn/'pixel14-syn_1-netlist.v';routed=phy/'pixel14-phy_1-netlist.v'
    gs=read(gate);ps=read(routed)
    font_text=read(run/'rtl/items14_font_rom.v')
    font={int(a):int(b,16) for a,b in re.findall(r"rom\[12'd(\d+)\]=16'h([0-9A-Fa-f]+)",font_text)}
    assert len(font)==4096 and all((v&1)==0 for v in font.values())
    template=[int(v,16) for v in read(run/'templates.mem').split()]
    assert len(template)==1024
    final_signatures=collections.Counter(sig for _,_,sig in memories(ps))
    roms=[]
    for m,values,sig in memories(gs):
        name=m[2]
        if '/matcher/templates/' not in name and '/system/panel/font/' not in name:continue
        is_font='/system/panel/font/' in name
        out=re.search(r'font_bits\s*\[\d+:(\d+)\]',m[3]) if is_font else None
        offset=int(out[1]) if out else 0
        depth=4096 if is_font else 1024
        data=sum(int(values[f'INIT_{i:02X}'],16)<<(256*i) for i in range(64))
        parity=sum(int(values[f'INITP_{i:02X}'],16)<<(256*i) for i in range(16))
        for address in range(depth):
            actual=((data>>(address*4))&15)|(((parity>>address)&1)<<4)
            expected=((font[address]>>offset)&31) if is_font else template[address]
            assert actual==expected,(name,address,actual,expected)
        assert final_signatures[sig]>=1,('ROM INIT missing from routed netlist',name)
        roms.append({'GateInstance':name,'Primitive':'PH1P_PHY_ERAM_V2','DepthChecked':depth,
            'OutputBitOffset':offset,'InitialBitsSHA256':sig,'RoutedInstancesWithIdenticalInit':final_signatures[sig]})
    assert len(roms)==4,roms
    timing=read(phy/'camera_to_dsi_display_pr.timing');area=read(phy/'camera_to_dsi_display_phy.area')
    metrics={key:float(re.search(r'\b'+key+r':\s*(-?[0-9.]+)ns',timing)[1]) for key in ('SWNS','STNS','HWNS','HTNS')}
    keys=[]
    for index,location in enumerate(('D5','A9','B9','C7')):
        row=re.search(r'I_quiz_keys_n\['+str(index)+r'\]\s+INPUT\s+(\S+)\s+(\S+)\s+\S+\s+\S+\s+(\S+)',area)
        assert row and tuple(row.groups())==(location,'LVCMOS33','PULLUP')
        keys.append({'Index':index,'Ball':location,'Direction':'INPUT','IOSTANDARD':'LVCMOS33','Pull':'PULLUP'})
    unknown=[];warnings=[]
    for stage in ('syn_1','phy_1'):
        text=read(run/(stage+'.stdout.log'))
        unknown.extend(line for line in text.splitlines() if re.search(r'\bERROR:|unknown module|black.?box',line,re.I))
        warnings.extend(line for line in text.splitlines() if 'CRITICAL-WARNING' in line)
    assert not unknown,unknown
    changed=[];snapshot_changed=[]
    for f in inputs['Files']:
        if sha(f['Path'])!=f['SHA256']:changed.append(f['Path'])
        if f.get('Snapshot') and sha(f['Snapshot'])!=f['SnapshotSHA256']:snapshot_changed.append(f['Snapshot'])
    assert not snapshot_changed,snapshot_changed
    assert sha(result['Bit'])==result['SHA256']
    details={}
    for name in ('slice','eram','dsp','reg'):
        row=re.search(r'^#'+name+r'\s+(\d+)',area,re.M)
        if row:details[name]=int(row[1])
    artifacts=[run/n for n in ('inputs.json','started.json','stages.json','result.json','syn_1.stdout.log','phy_1.stdout.log')]
    artifacts += [gate,routed,phy/'camera_to_dsi_display_pr.db',phy/'camera_to_dsi_display_pr.timing',phy/'camera_to_dsi_display_phy.area',Path(result['Bit'])]
    if (run/'analysis').exists():artifacts+=list((run/'analysis').glob('*'))
    report={'AuditedAt':datetime.datetime.now().astimezone().isoformat(),'Run':str(run),'Owner':'SC520 recovery /root/build_impl',
        'BitSHA256':result['SHA256'],'MetricsNs':metrics,'Resources':details,'ROMs':roms,'KeyIO':keys,
        'CurrentSourceDifferences':changed,'SnapshotDifferences':snapshot_changed,'UnknownModulesOrToolErrors':unknown,
        'CriticalWarnings':warnings,'TimingNonnegative':metrics['SWNS']>=0 and metrics['HWNS']>=0,
        'HardwareValidated':False,'DownloadQualified':False,
        'Artifacts':[{'Path':str(p),'Bytes':p.stat().st_size,'SHA256':sha(p)} for p in artifacts if p.is_file()],
        'Limitations':'CDC reports require separate endpoint/propagation review; no CRC/ECC computation, DDR display identity, physical audio or board validation.'}
    (run/'audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'Run':str(run),'MetricsNs':metrics,'Resources':details,'ROMs':len(roms),'CurrentSourceDifferences':len(changed)},ensure_ascii=False))

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('run',type=Path);audit(p.parse_args().run.resolve())
