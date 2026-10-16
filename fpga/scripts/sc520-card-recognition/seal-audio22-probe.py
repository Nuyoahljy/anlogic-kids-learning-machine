"""Seal a qualified offline integration report; never copy or publish a bit."""
from pathlib import Path
import argparse,datetime,hashlib,json
ROOT=Path(__file__).resolve().parents[3];E=ROOT/'evidence/sc520-card-recognition'
def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def art(p):p=Path(p).resolve();return {'Path':str(p),'SHA256':sha(p),'Bytes':p.stat().st_size}
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--probe',required=True,type=Path);ap.add_argument('--software',required=True,type=Path);a=ap.parse_args()
    out=E/'audio22/integration-manifest-v1.json';assert not out.exists()
    r=read(a.probe);s=read(a.software);run=Path(r['Run'])
    assert r['ProbeQualified'] and not r['CandidateQualified'] and not r['Downloadable'] and not r['BitGenerationAllowed']
    assert not r['HardwareValidated'] and r['TotalSynchronizerPairs']==24 and len(r['ROMs'])==39
    assert not list(run.rglob('*.bit')) and not list((ROOT/'fpga/custom_project/sc520-audio22').rglob('*.bit'))
    assert s['Qualified'] and s['PositiveScenarios']==44 and s['PositiveChecks']==12199365
    start=read(E/'audio22/start.json')
    for x in start['Protected']+start['Imports']:assert sha(x['Path'])==x['SHA256'],x['Path']
    old=read(E/'delivery-0117/manifest.json')['Resources']['Used']
    delta={k:r['Resources']['Used'][k]-old[k] for k in ('lut6','reg','slice','eram','dsp')}
    m={'CreatedAt':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
       'Task':'D051/T022','Status':'离线集成探针完成，等待主审核；无下载镜像','BaseCommit':start['BaseCommit'],'AudioSourceCommit':start['AudioCommit'],
       'Run':str(run),'Probe':art(a.probe),'Software':art(a.software),'Guide':art(ROOT/'hardware/sc520-card-recognition/audio22-integration.md'),
       'Start':art(E/'audio22/start.json'),'Imports':start['Imports'],'HardwareDefault':s['HardwareDefault'],'SyntheticTestProfile':s['SyntheticTestProfile'],
       'Resources':r['Resources'],'ResourceDeltaFrom0117':delta,'TimingNs':r['TimingNs'],'TotalSynchronizerPairs':24,
       'AudioCells':len(r['AudioRegisters']),'AudioMinimumSlackNs':r['AudioMinimumSlackNs'],
       'MailboxBits':{**{x['Name']:x['Bits'] for x in r['Mailboxes']},'color':r['ColorMailbox']['Bits']},
       'DisplayLayers':6,'SampleToOutputEdges':5,'FrameStateBits':31,'AudioStateBits':'[30:28]','BusinessStateBits':'[27:0]',
       'Preview':[x['Preview'] for x in s['FullFrames']],'Program':art(__file__),
       'BitGenerationAllowed':False,'BitFilesFound':[],'Downloadable':False,'HardwareValidated':False,'FullSystemTimingSignoff':False,'Limits':r['Limits']}
    with out.open('x',encoding='utf-8') as f:json.dump(m,f,ensure_ascii=False,indent=2);f.write('\n')
    print(json.dumps({'Manifest':str(out),'Downloadable':False,'ResourceDelta':delta}))
if __name__=='__main__':main()
