"""Strict current-source selection and readback for T018 I2C regressions."""
from pathlib import Path
from datetime import datetime,timezone,timedelta
import hashlib,json,argparse
ROOT=Path(__file__).resolve().parents[3]
E=ROOT/'evidence/sc520-card-recognition'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def art(p):return {'Path':str(Path(p).resolve()),'SHA256':sha(p)}
def current(r):
    return r.get('Qualified') and r.get('InputsUnchanged') and not r.get('TimedOut') and all(sha(x['path'])==x['sha256_before'].upper() for x in r['Inputs'])
def verify(path,r):
    for x in r['Inputs']:
        h=x['sha256_before'].upper();assert h==sha(x['path'])==sha(x['snapshot'])==x['sha256_after'].upper()==x['snapshot_sha256'].upper(),x
    for x in r['Outputs']:assert sha(x['path'])==x['sha256'].upper(),x
    s=r['Summary'];n=bool(r.get('CheckerNegative',False) or r.get('Mode')=='negative');w=bool(r.get('WatchdogProbe',False) or r.get('Mode')=='watchdog')
    assert r['NativeExitCode']==(2 if w else int(n)) and s['test_done']==int(not w) and s['errors']==int(n)
    return {**art(path),'Mode':r['Mode'],'Negative':n,'Watchdog':w,'Summary':s,'Command':r['Command'],'InputsChecked':len(r['Inputs']),'OutputsChecked':len(r['Outputs'])}
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--output',type=Path,required=True);a=ap.parse_args();assert not a.output.exists()
    modes=['normal','id-nack','init-nack','ae-nack','id-reject','id-stuck','init-stuck','ae-stuck','id-wrong','id-alt','ae-snapshot','timeout']
    candidates=[]
    for path in (E/'i2c-runs').glob('*/run-manifest.json'):
        r=read(path)
        if r.get('ClockDivider')==239 and any(Path(x['path'])==ROOT/'fpga/custom_project/sc520-pixel14/overlay/uii2c.v' for x in r['Inputs']) and current(r):candidates.append((path,r))
    selected=[]
    for mode,negative,watchdog in [(m,False,False) for m in modes]+[('normal',True,False),('normal',False,True)]:
        found=[(p,r) for p,r in candidates if r['Mode']==mode and r['CheckerNegative']==negative and r['WatchdogProbe']==watchdog]
        assert found,(mode,negative,watchdog)
        p,r=max(found,key=lambda v:v[1]['FinishedAt']);selected.append(verify(p,r))
    ce=[]
    for mode in ['normal','negative','watchdog']:
        found=[]
        for p in (E/'scl-coverage').glob('ce-tests-'+mode+'-*/run-manifest.json'):
            r=read(p)
            if current(r):found.append((p,r))
        assert found,mode
        p,r=max(found,key=lambda v:v[1]['FinishedAt']);ce.append(verify(p,r))
    positive=[x for x in selected if not x['Negative'] and not x['Watchdog']]
    n=ce[0]['Summary'];assert n['request_phase_coverage']==n['same_edge_phase_coverage']==240 and n['reset_release_offsets']==42
    assert n['completed_transactions']==488 and n['abort_cases']==8 and n['external_slave_clears']==n['stuck_cases']==3
    assert n['min_low_ns']>=4700 and n['min_high_ns']>=4000 and n['min_setup_ns']>=250 and n['max_data_valid_ns']<=3450
    old=read(E/'delivery-0112/manifest.json');assert sha(old['Bit']['Path'])==old['Bit']['SHA256']
    output={'CreatedAt':datetime.now(timezone(timedelta(hours=8))).isoformat(),'Qualified':True,
      'ConfigRuns':selected,'PhaseAndResetRuns':ce,'PositiveConfigChecks':sum(x['Summary']['checks'] for x in positive),
      'PositiveCEChecks':n['checks'],'PositiveConfigModes':len(positive),'CECompletedTransactions':488,'CECases':n['cases'],
      'I2CSource':art(ROOT/'fpga/custom_project/sc520-pixel14/overlay/uii2c.v'),'D0112Preserved':art(old['Bit']['Path']),
      'Limitations':['Pin timing uses modeled rise1000ns/fall300ns and slave data-valid3450ns. Board RC/pad loading not measured.',
         'Three aborted-slave cases require an explicitly modeled external sensor reset; autonomous bus clear and clock stretching are not implemented.',
         'Same-parent-edge request can be accepted one whole bus period later than the former derived-clock delta-cycle model, while request/payload protocol remains correct.',
         'Software pass does not establish real sensor communication or correct imaging.'], 'Program':art(__file__)}
    a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(output,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'output':str(a.output),'qualified':True,'config_runs':len(selected),'ce_runs':len(ce),'config_checks':output['PositiveConfigChecks'],'ce_checks':n['checks']}))
if __name__=='__main__':main()
