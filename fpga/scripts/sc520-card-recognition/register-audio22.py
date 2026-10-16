"""Register this task's batches, without modifying other owners' records."""
from pathlib import Path
import argparse,datetime,hashlib,json,subprocess,uuid
ROOT=Path(__file__).resolve().parents[3]
WORKSPACE=Path('E:/juan/FPGA')
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--owner',required=True);ap.add_argument('--summary',required=True);ap.add_argument('--validation',required=True)
    ap.add_argument('--next',required=True);ap.add_argument('--files',nargs='*',default=[]);ap.add_argument('--dirs',nargs='*',default=[])
    a=ap.parse_args();now=datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8)))
    ident=now.strftime('%Y%m%d-%H%M%S')+'-sc520-audio22-'+uuid.uuid4().hex[:6]
    dest=WORKSPACE/'workspace-records'/(ident+'.json');changes=[];registered=set()
    for previous in (WORKSPACE/'workspace-records').glob('*.json'):
        record=json.loads(previous.read_text(encoding='utf-8-sig'))
        registered.update(str(Path(x['Path']).resolve()).casefold() for x in record['Changes'])
    for name in a.files+a.dirs:
        p=(ROOT/name).resolve();assert p.is_relative_to(ROOT) and p.exists(),p
        row={'Path':p.as_posix(),'Action':('modified' if str(p).casefold() in registered else 'added') if p.is_file() else 'generated',
             'Purpose':a.summary+'; '+p.relative_to(ROOT).as_posix(),'Status':'T022开发/离线验证；非硬件放行'}
        if p.is_file():row['SHA256']=sha(p)
        changes.append(row)
    changes.append({'Path':dest.as_posix(),'Action':'added','Purpose':'本批独立登记','Status':'真实时间'})
    record={'Id':ident,'UpdatedAt':now.isoformat(),'Task':'sc520-card-recognition',
       'Owner':a.owner,'Workdir':ROOT.as_posix(),
       'Summary':a.summary,'Validation':a.validation,'NextStep':a.next,'Changes':changes}
    with dest.open('x',encoding='utf-8') as f:json.dump(record,f,ensure_ascii=False,indent=2);f.write('\n')
    print(dest)
    subprocess.run(['pwsh','-File',str(WORKSPACE/'anlogic-kids-learning-machine/tools/update-workspace-index.ps1')],check=True)
if __name__=='__main__':main()
