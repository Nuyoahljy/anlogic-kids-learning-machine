"""Check preserved reset FFs, their exact Q/D topology and partition loads."""
from pathlib import Path
import argparse, collections, hashlib, importlib.util, json, re

ROOT=Path(__file__).resolve().parents[3]
LEGACY=ROOT/'fpga/custom_project/sc520-pixel14/tools/audit-scene-build.py'
spec=importlib.util.spec_from_file_location('timing23_netlist',LEGACY)
base=importlib.util.module_from_spec(spec);spec.loader.exec_module(base)

def gate_cells(text):
    result={}
    for m in re.finditer(r'\b(AL_MAP_\w+)\s*(?:#\((.*?)\))?\s+(\\\S+|\w+)\s*\((.*?)\);',text,re.S):
        params=dict(re.findall(r'\.(\w+)\("([^"]*)"\)',re.sub(r'//[^\n]*','',m[2] or '')))
        ports={p:base.net(v) for p,v in re.findall(r'\.(\w+)\(([^()]*)\)',m[4])}
        name=base.net(m[3]);assert name not in result,name
        result[name]={'Primitive':m[1],'Params':params,'Ports':ports}
    return result

def audit(run):
    netlist=run/'td_project/camera_to_dsi_display_Runs/syn_1/pixel14-syn_1-netlist.v'
    cells=gate_cells(base.read(netlist));prefix='u_p14_pipeline/'
    registers=[(n,c) for n,c in cells.items() if c['Primitive'].startswith('AL_MAP_SEQ')]
    def driver(q):
        matches=[(n,c) for n,c in registers if c['Ports'].get('q')==q]
        assert len(matches)==1,('Reset Q not unique',q,matches)
        return matches[0]
    first=driver(prefix+'capture_reset[0]')
    names=[prefix+'capture_reset[1]']+[prefix+f'capture_release[{i}]' for i in range(9)]
    branches=[driver(q) for q in names]
    assert first[1]['Ports']['d']=="1'b1"
    expected={'CEMUX':'1','CLKMUX':'SIG','DFFMODE':'FF','REGSET':'RESET','SRMODE':'ASYNC','SRMUX':'INV'}
    for n,c in [first,*branches]:
        assert c['Params']==expected,(n,c['Params'])
        assert c['Ports']['clk']==first[1]['Ports']['clk'] and c['Ports']['sr']==first[1]['Ports']['sr']
    for n,c in branches:assert c['Ports']['d']==names[0].replace('[1]','[0]'),(n,c)
    loads=collections.defaultdict(list)
    outputs={'q','o','c','sum','co'}
    for n,c in cells.items():
        for port,net in c['Ports'].items():
            if port not in outputs and net in names:
                loads[net].append({'Cell':n,'Port':port,'Primitive':c['Primitive']})
    expected_fragments={0:'/capture/',1:'/scene_mode$scene/',2:'/glyph_color_mode$blocks/',3:'/shape_mode$shape_guard/',
        4:'/guarded_block_confirmation$block_confirmation/',5:'/confirmation/',6:'/rotation_mode$matcher/',
        7:'/color_observation$observer/diagnostics/',8:'/color_observation$observer/joiner/'}
    rows=[]
    for i,q in enumerate(names):
        consumers=loads[q]
        assert consumers,('Empty reset branch',q)
        if i:
            fragment=expected_fragments[i-1]
            assert all(fragment in x['Cell'] for x in consumers),('Reset partition crossed',q,consumers[:10])
        n,c=branches[i]
        rows.append({'LogicalQ':q,'Cell':n,**c,'FanoutPins':len(consumers),'Consumers':consumers})
    return {'Qualified':True,'Stage':'synthesis only','Netlist':base.artifact(netlist),
        'FirstStage':{'Cell':first[0],**first[1]},'SecondStageCount':10,'AdditionalSecondStages':9,
        'Branches':rows,'MaximumBranchFanout':max(r['FanoutPins'] for r in rows),
        'OriginalWorstPhysicalFanout':2448,'TimingQualified':False,'HardwareValidated':False,
        'Program':base.artifact(__file__),'Parser':base.artifact(LEGACY)}

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('run',type=Path);ap.add_argument('--output',type=Path,required=True);a=ap.parse_args()
    r=audit(a.run.resolve());base.emit(a.output,r)
    print(json.dumps({'Qualified':True,'Branches':r['SecondStageCount'],'MaximumFanout':r['MaximumBranchFanout']}))
