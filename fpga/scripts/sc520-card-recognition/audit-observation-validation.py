"""Bind final observer tests to current sources; preserve earlier failed runs."""
from pathlib import Path
from datetime import datetime,timezone,timedelta
import argparse,hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[3];E=ROOT/'evidence/sc520-card-recognition'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def art(p):return {'Path':str(Path(p).resolve()),'SHA256':sha(p)}
def current(r):
    return r.get('Qualified') and r.get('InputsUnchanged') and not r.get('TimedOut') and all(sha(x['path'])==x['sha256_before'].upper() for x in r['Inputs'])
def verify(path,r):
    for x in r['Inputs']:
        h=x['sha256_before'].upper();assert sha(x['snapshot'])==x['snapshot_sha256'].upper()==x['sha256_after'].upper()==sha(x['path'])==h,x
    for x in r['Outputs']+r.get('GeneratedInputs',[]):assert sha(x['path'])==x['sha256'].upper(),x
    s=r['Summary'];m=r['Mode'];assert r['NativeExitCode']==(2 if m=='watchdog' else int(m=='negative'))
    assert s['done']==int(m!='watchdog') and s['errors']==int(m=='negative') and s['injected']==int(m=='negative')
    return {**art(path),'Test':r.get('Test','observation_system' if r.get('ObservationEnabled') else 'color_scene'),
        'Mode':m,'Summary':s,'Command':r['Command'],'InputsChecked':len(r['Inputs']),'OutputsChecked':len(r['Outputs'])}
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--output',required=True,type=Path);a=ap.parse_args();assert not a.output.exists()
    candidates=[]
    for p in (E/'runs').glob('*/run-manifest.json'):
        r=read(p)
        if not r.get('Inputs') or not r.get('Summary'):continue
        if current(r):candidates.append((p,r))
    selected=[]
    for test in ['color_taps','observation','observation_display','observation_system']:
        for mode in ['normal','negative','watchdog']:
            found=[(p,r) for p,r in candidates if r['Mode']==mode and
                   ((test=='observation_system' and r.get('ObservationEnabled')) or r.get('Test')==test)]
            assert found,('missing current run',test,mode)
            p,r=max(found,key=lambda v:v[1]['FinishedAt']);selected.append(verify(p,r))
    matches=[(p,r) for p,r in candidates if r.get('Test')=='scene_system' and r['Mode']=='normal' and r.get('RotationVariants')==256 and not r.get('MatrixOnly')]
    assert matches;p,r=max(matches,key=lambda v:v[1]['FinishedAt']);selected.append(verify(p,r))
    prefix='fpga/custom_project/sc520-pixel14/overlay/pixel14_color_pipeline.v'
    old=subprocess.check_output(['git','show','c74a430:'+prefix],cwd=ROOT).decode('utf-8').replace('\r\n','\n')
    new=(ROOT/prefix).read_text(encoding='utf-8')
    begin='    localparam integer GROUPS';end='    // Diagnostic taps are parallel registers;'
    oldbody=old[old.index(begin):old.index('    initial begin',old.index('    assign O_tdata='))]
    newbody=new[new.index(begin):new.index(end)]
    assert oldbody==newbody,'Existing color computation or original pixel latency changed'
    baseline=E/'builds/6a50b113'
    unchanged=[]
    for name in ['uii2c.v','uicfgcs520.v']:
        p=ROOT/'fpga/custom_project/sc520-pixel14/overlay'/name;assert sha(p)==sha(baseline/'overlay'/name);unchanged.append(art(p))
    for name in ['block_frame_recognizer.v','pixel14_rotation_matcher.v','pixel14_block_shape_guard.v','pixel14_block_filter.v']:
        p=ROOT/'fpga/rtl/sc520-card-recognition/pixel14'/name;assert sha(p)==sha(baseline/'rtl'/name);unchanged.append(art(p))
    template=ROOT/'assets/templates/sc520-card-recognition/rotation-v1/templates.mem';assert sha(template)==sha(baseline/'templates.mem')
    positive=[r for r in selected if r['Mode']=='normal']
    output={'CreatedAt':datetime.now(timezone(timedelta(hours=8))).isoformat(),'Qualified':True,'Runs':selected,
        'PositiveScenarios':sum(r['Summary']['scenarios'] for r in positive),'PositiveChecks':sum(r['Summary']['checks'] for r in positive),
        'OriginalColorBodyByteIdentical':True,'OriginalColorSourceCommit':'c74a430','I2CAndClassifiersUnchanged':unchanged,
        'Template':art(template),'Program':art(__file__),'HardwareValidated':False,
        'Scope':'Default WB/tone observation, real54cycle pixel taps and non-unit gains, tagged join, four-lane full720p, CDC/freshness, incomplete snapshots and literal OSD pixel rendering. No claim that real sensor colors are repaired.'}
    a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(output,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'output':str(a.output),'qualified':True,'runs':len(selected),'checks':output['PositiveChecks'],'scenarios':output['PositiveScenarios']}))
if __name__=='__main__':main()
