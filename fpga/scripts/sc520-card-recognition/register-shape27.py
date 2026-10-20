"""Register only T027-owned sources, branch log, and evidence directory."""
from pathlib import Path
from datetime import datetime,timezone,timedelta
import argparse,json,subprocess,uuid
R=Path(__file__).resolve().parents[3];W=Path('E:/juan/FPGA')
ap=argparse.ArgumentParser();ap.add_argument('--summary',required=True);ap.add_argument('--validation',required=True);a=ap.parse_args()
now=datetime.now(timezone(timedelta(hours=8)));tag=now.strftime('%Y%m%d-%H%M%S')+'-sc520-shape27-'+uuid.uuid4().hex[:6]
p=W/'workspace-records'/f'{tag}.json';files=[]
for folder in ['fpga/rtl/sc520-shape27','fpga/sim/sc520-shape27','hardware/sc520-shape27','fpga/custom_project/sc520-shape27/overlay']:
 files+=list((R/folder).rglob('*'))
files+=list((R/'fpga/scripts/sc520-card-recognition').glob('*shape27*'))
files+=[R/'fpga/custom_project/sc520-shape27/.gitattributes',R/'memory/branches/sc520-color-integration.md']
for folder in ['evidence/sc520-shape27/fixtures','evidence/sc520-shape27/render-fixtures']:
 files+=list((R/folder).glob('*'))
files+=list((R/'evidence/sc520-shape27').glob('*'))
files+=list((R/'evidence/sc520-shape27/runs').glob('*/run-manifest.json'))
files+=list((R/'evidence/sc520-shape27/runs').glob('*/summary.json'))
for name in ['inputs.json','started.json','stages.json','result.json','failure.json','reset-synthesis.json']:
 files+=list((R/'evidence/sc520-shape27/builds').glob('*/'+name))
files=list(dict.fromkeys(files))
changes=[{'Path':str(f),'Action':'modified' if f.name=='sc520-color-integration.md' else 'observed','Purpose':'T027任务独立源/测试/工程/工具当前字节；不改冻结D0261','Status':'开发中/待主审核'} for f in files if f.is_file()]
for folder in ['fpga/custom_project/sc520-shape27/td_project','evidence/sc520-shape27']:
 if (R/folder).exists():changes.append({'Path':str(R/folder),'Action':'generated','Purpose':'T027独立生成输出；命令、SHA、原生状态和结果见各run-manifest/inputs/result','Status':'见本记录验证，硬件未验证'})
changes.append({'Path':str(p),'Action':'added','Purpose':'本批独立登记','Status':'真实时间登记'})
p.write_text(json.dumps({'Id':tag,'UpdatedAt':now.isoformat(),'Task':'sc520-shape27','Owner':'Codex /root/shape27_impl_resume','Workdir':str(R),'Summary':a.summary,'Validation':a.validation,'NextStep':'主审核软件后启动唯一TD，物理审核后另放行bit；硬件待验证','Changes':changes},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
for args in [[],['-Check']]:subprocess.run(['pwsh','-File',str(W/'anlogic-kids-learning-machine/tools/update-workspace-index.ps1'),*args],check=True)
print(tag)
