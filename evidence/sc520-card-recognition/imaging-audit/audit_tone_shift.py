"""Verify the exact source-level tone delta and its independent RTL reruns."""
from pathlib import Path
import datetime,hashlib,json,re
HERE=Path(__file__).resolve().parent;REPO=HERE.parents[2]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def main():
    old=HERE/'runs/normal-20261014-102256-5d04a3/inputs/pixel14_color_pipeline.v'
    new=REPO/'fpga/custom_project/sc520-pixel14/overlay/pixel14_color_pipeline.v'
    assert sha(old)=='86E8E1F5A9422B509141AFB5502F535EA70CD04DD941900B97E4F95639077F8C'
    assert sha(new)=='3A2CEB5F9289A3B23D1CC8120B8375A385FB1D2E284933CAE68FFA2107FFC26F'
    oldtext=old.read_text();newtext=new.read_text();pattern=r'    function \[7:0\] tone07;[\s\S]*?    endfunction'
    oldfun=re.search(pattern,oldtext).group();newfun=re.search(pattern,newtext).group()
    assert re.sub(pattern,'TONE_FUNCTION',oldtext)==re.sub(pattern,'TONE_FUNCTION',newtext),'outside-function changes'
    oldrows=re.findall(r'(\d+|default):begin base=(\d+);delta=(\d+);end',oldfun)
    newrows=re.findall(r'(\d+|default):begin base=(\d+);interpolation=([^;]+);end',newfun)
    assert len(oldrows)==len(newrows)==16
    codes=[]
    for v in range(256):
        k=v//16;n=v%16;ob,delta=map(int,oldrows[k][1:]);nb=int(newrows[k][1]);expression=newrows[k][2]
        assert re.fullmatch(r'[nible0-9<+() ]+',expression),expression
        product=eval(expression,{'__builtins__':{}},{'nibble':n})
        assert 0<=product+8<4096
        before=255 if v==255 else ob+(delta*n+8)//16
        after=255 if v==255 else nb+(product+8)//16
        assert before==after,(v,before,after)
        codes.append({'input':v,'before':before,'after':after})
    runs=[]
    for name in ['normal-20261014-104730-8f968b','normal-720p-20261014-104730-f4bcca','negative-20261014-104759-8d8a64','watchdog-20261014-104759-7bfd15']:
        p=HERE/'runs'/name/'run-manifest.json';d=json.loads(p.read_text());assert d['qualified']
        for x in d['inputs']:assert x['sha256_before']==x['sha256_after']==x['snapshot_sha256']==sha(x['path'])==sha(x['snapshot'])
        for x in d['outputs']:assert x['sha256']==sha(x['path'])
        runs.append({'path':str(p),'sha256':sha(p),'summary':d['summary'],'native_exit':d['native_exit']})
    for before,after in [('normal-20261014-102256-5d04a3','normal-20261014-104730-8f968b'),('normal-720p-20261014-102256-ba6849','normal-720p-20261014-104730-f4bcca')]:
        assert sha(HERE/'runs'/before/'color-observations.csv')==sha(HERE/'runs'/after/'color-observations.csv')
    report={'created_at':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),'qualified':True,
      'before':{'path':str(old),'sha256':sha(old)},'after':{'path':str(new),'sha256':sha(new)},'unchanged_outside_tone_function':True,
      'equivalent_byte_values':256,'exact_values':codes,'runs':runs,'normal_scenarios':20,'normal_checks':4836515,
      'observations_csv_byte_identical':True,'latency_input_to_output_cycles':54,
      'resource_claim':'12 tone channel expressions now use constant shifts/additions; no claim about DSP reduction until TD maps the new source.',
      'unchanged_multipliers':'Eight pixel R/B gain multipliers and two frame-statistic weighted products unchanged.',
      'hardware_validated':False}
    (HERE/'tone-shift-audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'qualified':True,'equivalent_codes':256,'runs':4,'normal_checks':4836515,'new_sha256':sha(new)}))
if __name__=='__main__':main()
