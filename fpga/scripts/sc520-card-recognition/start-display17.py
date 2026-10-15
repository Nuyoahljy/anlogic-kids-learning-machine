"""One-time T017 protection snapshot and exact Git-blob dependency import."""
from pathlib import Path
import datetime,hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[3]
BASE='68e2b4d01485fa1b3049d81e98a09c2e3dc98a94'
DISPLAY='edaced3542a4a056aa90397aefadb45e279e69e2'
def sha(data):return hashlib.sha256(data).hexdigest().upper()
def art(p):return {'Path':str(p),'Bytes':p.stat().st_size,'SHA256':sha(p.read_bytes())}
def git(*args):return subprocess.check_output(['git',*args],cwd=ROOT)
def main():
    assert git('rev-parse','HEAD').decode().strip()==BASE
    evidence=ROOT/'evidence/sc520-card-recognition/display17';evidence.mkdir(exist_ok=False)
    protected=[]
    for directory in [ROOT/'evidence/sc520-card-recognition/builds/6a50b116',ROOT/'evidence/sc520-card-recognition/delivery-0116',Path('E:/juan/FPGA/learning/sc520-validation/evidence/d0116-two-photo-20261015-193259')]:
        protected.extend(art(p) for p in sorted(directory.rglob('*')) if p.is_file())
    current=[]
    for rel in git('ls-files','fpga/rtl/sc520-card-recognition','fpga/custom_project/sc520-pixel14','assets/templates/sc520-card-recognition').decode().splitlines():
        p=ROOT/rel
        if p.is_file():current.append(art(p))
    imports=[]
    names=['sc520_processing_display.v','sc520_color_classify.v','sc520_logo_pipeline.v']
    mapping={f'fpga/rtl/sc520-processing-display/{n}':f'fpga/rtl/sc520-card-recognition/display17/{n}' for n in names}
    for n in ['anlogic_logo_index.mem','anlogic_logo_palette.mem','anlogic_logo_reference.mem','anlogic_logo_rgba.png','logo_manifest.json','logo_rom_manifest.json']:
        mapping['assets/sc520-processing-display/'+n]='assets/templates/sc520-card-recognition/display17/'+n
    for source,target in mapping.items():
        data=git('show',DISPLAY+':'+source);p=ROOT/target;p.parent.mkdir(parents=True,exist_ok=True)
        assert not p.exists();p.write_bytes(data)
        imports.append({**art(p),'SourceCommit':DISPLAY,'SourcePath':source,'SourceBlob':git('rev-parse',DISPLAY+':'+source).decode().strip()})
    project=ROOT/'fpga/custom_project/sc520-pixel17/overlay';project.mkdir(parents=True,exist_ok=False)
    for p in sorted((ROOT/'fpga/custom_project/sc520-pixel14/overlay').iterdir()):
        if p.is_file():(project/p.name).write_bytes(p.read_bytes())
    record={'At':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),'BaseCommit':BASE,'DisplayCommit':DISPLAY,'Protected':protected,'StartingSources':current,'Imports':imports,'Scope':'Only T017 renderer/key adaptation. D0116 build/delivery and actual photographs protected byte-for-byte.'}
    (evidence/'start.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'protected':len(protected),'starting_sources':len(current),'imports':len(imports)}))
if __name__=='__main__':main()
