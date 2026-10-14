"""Preparation tests, never a substitute for auditing candidate111 outputs."""
from pathlib import Path
import hashlib,importlib.util,json,datetime,copy
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2]
TOOLS=ROOT/'fpga/custom_project/sc520-pixel14/tools'
spec=importlib.util.spec_from_file_location('scene_parser_test',TOOLS/'audit-scene-build.py');audit=importlib.util.module_from_spec(spec);spec.loader.exec_module(audit)
def zeros():return {**{f'INIT_{i:02X}':'0'*64 for i in range(64)},**{f'INITP_{i:02X}':'0'*64 for i in range(16)}}
def bit(values,prefix,index):
    values[f'{prefix}_{index//256:02X}']=f'{1<<(index%256):064X}'
def main():
    checks=[]
    def ok(name,condition):
        assert condition,name;checks.append(name)
    # Basis probes cross INIT segment, word and parity boundaries. Expected
    # nonzero logical position is computed independently from the pin grouping.
    for width in [1,2,5,10,20,40]:
        decoded=audit.init_decode(zeros(),width);ok(f'width{width}_zero_and_depth',not any(decoded) and len(decoded)==(16384//width if width<5 else 20480//width))
        db=width if width<5 else 4*(width//5)
        for physical in [0,1,3,4,15,16,255,256,16383]:
            values=zeros();bit(values,'INIT',physical);got=audit.init_decode(values,width)
            address,offset=divmod(physical,db);logical=offset if width<5 else offset+offset//4
            nonzero=[(i,v) for i,v in enumerate(got) if v]
            ok(f'width{width}_data_basis{physical}',nonzero==[(address,1<<logical)])
        for physical in [0,1,3,4,255,256,4095]:
            values=zeros();bit(values,'INITP',physical);got=audit.init_decode(values,width)
            nonzero=[(i,v) for i,v in enumerate(got) if v]
            expected=[] if width<5 else [(physical//(width//5),1<<(5*(physical%(width//5))+4))]
            ok(f'width{width}_parity_basis{physical}',nonzero==expected)
    value=zeros();del value['INITP_0F']
    try:audit.init_decode(value,5);raise RuntimeError('missing field accepted')
    except AssertionError:checks.append('missing_INITP_rejected')
    ok('concatenation_slice_and_constants',audit.bits("{2'b00,foo[3:0],2'b11}",{'foo':(3,0)})==['1','1','foo[0]','foo[1]','foo[2]','foo[3]','0','0'])
    ok('escaped_identifier_with_literal_brackets',audit.bits('\\path/pixel_y[2]_syn_2 ',{})==['path/pixel_y[2]_syn_2'])
    ok('escaped_bus_slice',audit.bits('\\path/data [3:1]',{})==['path/data[1]','path/data[2]','path/data[3]'])
    mem={'Params':{'DATA_WIDTH_B':'20'},'Ports':{'dob':'data[15:0]','dob_extra':'extra[3:0]'},'Declarations':{}}
    ok('twenty_bit_output_parity_interleave',audit.port_bits(mem)==['data[0]','data[1]','data[2]','data[3]','extra[0]','data[4]','data[5]','data[6]','data[7]','extra[1]','data[8]','data[9]','data[10]','data[11]','extra[2]','data[12]','data[13]','data[14]','data[15]','extra[3]'])
    mem['Params']['DATA_WIDTH_B']='40';mem['Ports'].update(doa='a[15:0]',doa_extra='ap[3:0]')
    try:audit.port_bits(mem);raise RuntimeError('ambiguous width40 accepted')
    except AssertionError:checks.append('width40_unreviewed_port_order_rejected')
    mem['Params']['MODE']='PDP20K'
    p=audit.port_bits(mem,wide_order=['a','b']);ok('width40_explicit_halves',len(p)==40 and p[0]=='a[0]' and p[19]=='ap[3]' and p[20]=='data[0]' and p[39]=='extra[3]')
    over=audit.resource_report('#slice 44101 out of 21216\n#reg 28129\n#eram 50 out of 108\n#dsp 41 out of 40\n')
    ok('over_capacity_not_qualified',set(over['OverCapacity'])=={'slice','dsp'})
    legacy=json.loads((HERE/'legacy0109-rom-check.json').read_text());twenty=json.loads((HERE/'failed110-rom-check.json').read_text())
    ok('actual0109_four_roms',len(legacy['ROMs'])==4 and sum(r['WordsChecked'] for r in legacy['ROMs'])==13312)
    ok('actual110_template20',len(twenty['ROMs'])==4 and [r['Width'] for r in twenty['ROMs'] if r['Kind']=='template']==[20])
    cdc=json.loads((HERE/'legacy0109-cdc-check.json').read_text())
    original=json.loads((ROOT/'evidence/sc520-card-recognition/builds/6a50b10a/candidate-audit.json').read_text())
    ok('legacy_CDC_bit_counts_agree_with_sealed_original',[(x['Name'],x['Bits']) for x in cdc['Mailboxes']]==[(x['Name'],x['Bits']) for x in original['Mailboxes']])
    for a,b in zip(cdc['Mailboxes'],original['Mailboxes']):
        ok(a['Name']+'_source_destination_path_mapping_equal',a['Paths']==b['Paths'])
    full=json.loads((HERE/'legacy0109-full-check.json').read_text())
    ok('historical_never_requalified',full['CandidateQualified'] is False and full['HistoricalReadOnly'] is True)
    ok('0109_snapshot_vendor_current_coordinator_checked',full['Baseline0109SnapshotsChecked']>0 and full['ExternalVendorFilesChecked']>0 and len(full['CoordinatorDocuments'])==7)
    report={'CreatedAt':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),'PreparationTestsPassed':len(checks),'Checks':checks,
      'Evidence':[audit.artifact(HERE/n) for n in ['legacy0109-rom-check.json','failed110-rom-check.json','legacy0109-cdc-check.json','legacy0109-full-check.json']],
      'Programs':[audit.artifact(TOOLS/n) for n in ['audit-scene-build.py','audit-scene-candidate.py','audit-build.py','audit-candidate.py','audit-recovery.py']],
      'CandidateQualified':False,'HardwareValidated':False,
      'Limit':'Widths1/2/10/40 basis tests exercise the documented INIT organization. Real nonzero ROM content comparisons cover widths5 and20 here; new physical bank select, width40 half order and routed aliases remain candidate-specific.'}
    audit.emit(HERE/'parser-tests-v2.json',report);print(json.dumps({'passed':len(checks),'candidate_qualified':False}))
if __name__=='__main__':main()
