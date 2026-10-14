"""Reread the final color/statistics and actual color-to-business evidence."""
import argparse
import csv
from datetime import datetime,timezone,timedelta
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
E=ROOT/'evidence/sc520-card-recognition'


def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def art(p):p=Path(p).resolve();return {'Path':str(p),'SHA256':sha(p),'Bytes':p.stat().st_size}
def field(d,a,b):return d[a] if a in d else d[b]


def verify_run(path):
    d=read(path);mode=field(d,'Mode','mode');s=field(d,'Summary','summary')
    assert field(d,'Qualified','qualified') and field(d,'InputsUnchanged','inputs_unchanged'),path
    code=field(d,'NativeExitCode','native_exit')
    if mode=='watchdog':assert code==2 and s['done']==0 and s['errors']==0,path
    else:assert code==int(mode=='negative') and s['done']==1 and s['errors']==s['injected']==int(mode=='negative'),path
    inputs=field(d,'Inputs','inputs');outputs=field(d,'Outputs','outputs')+d.get('GeneratedInputs',[])
    for x in inputs:
        h=x['sha256_before'].upper()
        assert sha(x['path'])==sha(x['snapshot'])==x['sha256_after'].upper()==x['snapshot_sha256'].upper()==h,x
    for x in outputs:assert sha(x['path'])==x['sha256'].upper(),x
    return {**art(path),'Mode':mode,'Summary':s,'NativeExitCode':code,
            'InputsChecked':len(inputs),'OutputsChecked':len(outputs),'Command':field(d,'Command','command')}


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--run',type=Path,action='append',required=True)
    ap.add_argument('--output',type=Path,required=True)
    args=ap.parse_args();assert not args.output.exists()
    runs=[verify_run(p) for p in args.run]
    assert {x['Mode'] for x in runs}=={'normal','negative','watchdog'} and len(runs)==3
    normal=[Path(x['Path']).parent for x in runs if x['Mode']=='normal'][0]
    rows=list(csv.DictReader((normal/'observations.csv').open(encoding='utf-8')))
    assert len(rows)==24
    for row in rows:
        assert all(int(row[k])==v for k,v in {'input_groups':230400,'output_groups':230400,'output_lines':720,
            'latency_clocks':54,'gain_r':256,'gain_b':256}.items()),row
    for c in range(5):
        assert int(rows[(c+1)*3]['item'])==10+c and int(rows[(c+1)*3]['stable_count'])==3
    assert all(int(row['score'])==1 and int(row['answers'])==1 for row in rows[-3:])
    baseline=E/'runs/p14-color-scene-normal-20261014-112236-86c86046/observations.csv'
    assert baseline.read_bytes()==(normal/'observations.csv').read_bytes(),'statistics staging changed output observations'
    stats_path=E/'imaging-audit/stats-pipeline-audit.json';stats=read(stats_path)
    assert stats['FunctionalQualified'] and stats['PixelSectionByteIdentical'] and stats['ToneFunctionByteIdentical']
    assert stats['InputToPixelOutputCycles']==54 and stats['StatisticsCompleteCyclesAfterFinalInputEOL']==4
    assert stats['StatisticsPendingCyclesAfterFinalInputEOL']==6 and stats['GainCommitCyclesAfterRawSOF']==4
    for key in ['CurrentRTL','Baseline111RTL','Tone256CodeEquivalenceRetained']:
        item=stats[key];assert sha(item['Path'])==item['SHA256'],item
    stats_runs=[verify_run(x['Path']) for x in stats['Runs']]
    assert len(stats_runs)==4 and {x['Mode'] for x in stats_runs}=={'normal','normal-720p','negative','watchdog'}
    current=Path(stats['CurrentRTL']['Path']).read_text(encoding='utf-8')
    old=Path(stats['Baseline111RTL']['Path']).read_text(encoding='utf-8')
    anchor='    // The two input registers and the original 50-cycle line RAM retain'
    assert current.split(anchor)[1]==old.split(anchor)[1]
    result={'CreatedAt':datetime.now(timezone(timedelta(hours=8))).isoformat(),'Qualified':True,
        'Scope':'Functional verification only; the standalone timing probe retains external input hold/removal failures. Full board timing is a separate candidate audit.',
        'CurrentRTL':art(stats['CurrentRTL']['Path']),'StatisticsAudit':art(stats_path),'StandaloneRuns':stats_runs,
        'ActualColorSceneRuns':runs,'Observations':art(normal/'observations.csv'),'Baseline111Observations':art(baseline),
        'PixelObservationsByteIdentical':True,'Full720pFrames':24,'AllFiveDarkCardsConfirmedOnThirdFrame':True,
        'RetainedObjectAnswers':1,'StatisticsPipelineCycles':4,'PixelPipelineCycles':54,'HardwareValidated':False,'AuditTool':art(__file__)}
    args.output.parent.mkdir(parents=True,exist_ok=True)
    with args.output.open('x',encoding='utf-8') as f:json.dump(result,f,ensure_ascii=False,indent=2);f.write('\n')
    print(json.dumps({'output':str(args.output),'qualified':True,'frames':24,'runs':len(runs)+len(stats_runs)}))


if __name__=='__main__':main()
