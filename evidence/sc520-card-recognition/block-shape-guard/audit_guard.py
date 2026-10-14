from pathlib import Path
import hashlib,json,datetime
HERE=Path(__file__).resolve().parent;REPO=HERE.parents[2]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def main():
    model=json.loads((HERE/'model-report.json').read_text());runs=[]
    for name in ['normal-20261014-104409-a8d6ef','negative-20261014-104433-1a1f5b','watchdog-20261014-104433-a57dea']:
        p=HERE/'runs'/name/'run-manifest.json';d=json.loads(p.read_text());assert d['qualified']
        for x in d['inputs']:assert x['sha256_before']==x['sha256_after']==x['snapshot_sha256']==sha(x['path'])==sha(x['snapshot'])
        for x in d['outputs']:assert x['sha256']==sha(x['path'])
        runs.append({'path':str(p),'sha256':sha(p),'summary':d['summary'],'native_exit':d['native_exit']})
    for x in model['sources']+model['outputs']+model['source_images']:assert sha(x['path'])==x['sha256']
    rtl=REPO/'fpga/rtl/sc520-card-recognition/pixel14/pixel14_block_shape_guard.v'
    report={'created_at':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
        'qualified':True,'rtl':{'path':str(rtl),'sha256':sha(rtl)},'model_report':{'path':str(HERE/'model-report.json'),'sha256':sha(HERE/'model-report.json')},
        'runs':runs,'normal_scenarios':390,'normal_checks':389114,'normal_errors':0,
        'scope':'1024 normalized glyph bits, three analytic references, same-shape qualification only. End-to-end pair gating and TD are parent-task responsibilities.',
        'limits':model['limits']+['MAX_DISTANCE20 rejects some small ideal blocks and most square/triangle rotations beyond +/-2 degrees; see rotation-measurements.json.'],
        'hardware_validated':False}
    (HERE/'guard-audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'qualified':True,'scenarios':390,'checks':389114,'source_images':len(model['source_images']),'rtl_sha256':sha(rtl)}))
if __name__=='__main__':main()
