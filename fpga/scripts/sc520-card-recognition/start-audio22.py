"""Freeze D0116/D0117 evidence and import only exact accepted audio Git blobs."""
from pathlib import Path
import datetime,hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[3];E=ROOT/'evidence/sc520-card-recognition'
BASE='fe5173964657dacc9c6723fe00e7ed5975901462';AUDIO='3287af4ad8943e43f2dcd0d13c7b253dffd7e4b3'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def art(p):return {'Path':str(p.resolve()),'SHA256':sha(p),'Bytes':p.stat().st_size}
def git(*a):return subprocess.check_output(['git',*a],cwd=ROOT)
def main():
    assert git('rev-parse','HEAD').decode().strip()==BASE
    assert git('branch','--show-current').decode().strip()=='task/sc520-card-recognition'
    main_start=Path('E:/juan/FPGA/learning/sc520-contest-roadmap/t022-start-20261016.json')
    original=json.loads(main_start.read_text(encoding='utf-8-sig'))
    for x in original['ProtectedDeliveries']:assert sha(x['Path'])==x['SHA256']
    protected=set()
    for name in ['builds/6a50b116','builds/6a50b117','builds/phy117-v1','delivery-0116','delivery-0117','display17']:
        protected.update(p.resolve() for p in (E/name).rglob('*') if p.is_file())
    previous=json.loads((E/'display17/start.json').read_text(encoding='utf-8-sig'))
    protected.update(Path(x['Path']).resolve() for x in previous['Protected'])
    soft=json.loads((E/'display17/software-validation-v1.json').read_text(encoding='utf-8-sig'))
    for row in soft['Runs']:
        protected.update(p.resolve() for p in Path(row['Path']).parent.rglob('*') if p.is_file())
    proof=[art(p) for p in sorted(protected)]
    imports=[]
    names=['dfr0534_link.v','dfr0534_player.v','dfr0534_player_core.v','dfr0534_track_map.v',
           't020/dfr0534_items14_audio.v','t020/t020_audio_queue.v']
    pairs=[('fpga/rtl/sc520-dfr0534/'+n,'fpga/rtl/sc520-card-recognition/audio22/imported/'+Path(n).name) for n in names]
    pairs += [('fpga/sim/sc520-dfr0534/t020/dfr0534_uart_model.sv','fpga/sim/sc520-card-recognition/audio22/dfr0534_uart_model.sv')]
    for source,name in pairs:
        data=git('show',AUDIO+':'+source);target=ROOT/name;assert not target.exists(),target
        target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
        imports.append({**art(target),'SourceCommit':AUDIO,'SourcePath':source,'GitBlob':git('rev-parse',AUDIO+':'+source).decode().strip()})
    project=ROOT/'fpga/custom_project/sc520-audio22'
    for source in sorted((ROOT/'fpga/custom_project/sc520-pixel17/overlay').iterdir()):
        if source.is_file():
            target=project/'overlay'/source.name;assert not target.exists();target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(source.read_bytes())
    output=E/'audio22/start.json';output.parent.mkdir(parents=True,exist_ok=True);assert not output.exists()
    report={'At':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),'BaseCommit':BASE,'AudioCommit':AUDIO,
       'MainStart':art(main_start),'Protected':proof,'Imports':imports,'BitGenerationAllowed':False,'HardwareValidated':False}
    with output.open('x',encoding='utf-8') as f:json.dump(report,f,ensure_ascii=False,indent=2);f.write('\n')
    print(json.dumps({'Protected':len(proof),'Imported':len(imports),'Output':str(output)}))
if __name__=='__main__':main()
