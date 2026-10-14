"""Qualify the color statistics retiming; keep failed111 and probe limits."""
from pathlib import Path
import datetime,hashlib,json,re
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[2]
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def artifact(p):return {'Path':str(p),'SHA256':sha(p),'Bytes':Path(p).stat().st_size}
def main():
    current=ROOT/'fpga/custom_project/sc520-pixel14/overlay/pixel14_color_pipeline.v'
    baseline=ROOT/'evidence/sc520-card-recognition/builds/6a50b111/rtl/pixel14_color_pipeline.v'
    assert sha(current)=='5020B23A8126103E0D1D5C9BB67DC8C93F55ED1C95B775FC1894B4D813420F31'
    assert sha(baseline)=='3A2CEB5F9289A3B23D1CC8120B8375A385FB1D2E284933CAE68FFA2107FFC26F'
    before=baseline.read_text();after=current.read_text()
    anchor='    // The two input registers and the original 50-cycle line RAM retain'
    assert before[before.index(anchor):]==after[after.index(anchor):],'Pixel delay/tone/gain multiply/saturation/output section changed'
    function=r'    function \[7:0\] tone07;[\s\S]*?    endfunction'
    tone=re.search(function,after).group();assert tone==re.search(function,before).group()
    old_tone=json.loads((HERE/'tone-shift-audit.json').read_text());assert old_tone['equivalent_byte_values']==256
    runs=[]
    names=['normal-20261014-114124-e263ba','normal-720p-20261014-114124-768d85','negative-20261014-114511-1290b3','watchdog-20261014-114511-abd86a']
    for name in names:
        p=HERE/'runs'/name/'run-manifest.json';r=json.loads(p.read_text());assert r['qualified']
        for x in r['inputs']:assert x['sha256_before']==x['sha256_after']==x['snapshot_sha256']==sha(x['path'])==sha(x['snapshot'])
        for x in r['outputs']:assert sha(x['path'])==x['sha256']
        runs.append(artifact(p)|{'Summary':r['summary'],'NativeExit':r['native_exit']})
    kernel=HERE/'color-timing/probe-20261014-113926-99a1d5'
    probe=json.loads((kernel/'timing-audit.json').read_text())
    assert probe['NativeExit']==0 and probe['InputsUnchanged'] and probe['TimingNs']['SWNS']==1.035
    for x in probe['Artifacts']:assert sha(x['Path'])==x['SHA256']
    text=(kernel/'final_timing.rpt').read_text();negative=[]
    for b in re.split(r'(?m)^Slack\s+:',text)[1:]:
        slack=float(b.strip().split('ns')[0])
        if slack<0:
            row={'SlackNs':slack}
            for key in ['Begin Point','End Point','Check Type']:row[key]=re.search(r'(?m)^'+key+r'\s+:\s*(.*)',b)[1]
            negative.append(row)
    assert negative and all(x['Begin Point'].split()[0].startswith(('pixel_byte[','rst_n')) for x in negative)
    correction=ROOT/'evidence/sc520-card-recognition/physical-audit-prepare/candidate111-cdc-check-v2.json'
    corrected=json.loads(correction.read_text());assert len(corrected['Synchronizers'])==17
    assert [(m['Bits'],m['ExcludedPaths']) for m in corrected['Mailboxes']]==[(80,46),(175,465),(28,56)]
    report={'CreatedAt':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
      'FunctionalQualified':True,'CurrentRTL':artifact(current),'Baseline111RTL':artifact(baseline),
      'PixelSectionByteIdentical':True,'ToneFunctionByteIdentical':True,'Tone256CodeEquivalenceRetained':artifact(HERE/'tone-shift-audit.json'),
      'StatisticsStages':['per-lane min/max','neutral selection','two-lane sums','four-lane sums'],
      'StatisticsCompleteCyclesAfterFinalInputEOL':4,'StatisticsPendingCyclesAfterFinalInputEOL':6,
      'GainCommitCyclesAfterRawSOF':4,'InputToPixelOutputCycles':54,'Runs':runs,
      'NormalScenarios':20,'NormalChecks':4836551,'NormalErrors':0,
      'IndependentCoreTiming':artifact(kernel/'timing-audit.json'),'IndependentCoreSetupWNSNs':1.035,
      'IndependentCoreOverallTimingQualified':False,'ReportedNegativeHoldRemovalPaths':negative,
      'CDCEchoCorrectionEvidence':artifact(correction),
      'ReportedNegativePathLimit':'The ten printed worst hold/removal checks start at external bench pixel_byte/rst_n. This is not proof that every unreported internal hold path passes. Full112 has separate final qualification.',
      'CandidateQualified':False,'HardwareValidated':False,
      'Limits':['Statistics qualification still checks RGB geometry only, not CSI content CRC/ECC.','111 negative-timing bit/DB remain historical.','The old physical-audit handoff inference from an empty echo -from/-to was corrected by scene_rtl: actual111 CDC reports contain all17 chains and80/175/28 payload bits.']}
    (HERE/'stats-pipeline-audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'FunctionalQualified':True,'NormalChecks':4836551,'RTL_SHA256':sha(current),'CoreSetupWNSNs':1.035,'CoreOverallTimingQualified':False}))
if __name__=='__main__':main()
