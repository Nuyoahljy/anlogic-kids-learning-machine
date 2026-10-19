"""Register this task's source and generated batches in the shared root index."""
from pathlib import Path
from datetime import datetime,timezone,timedelta
import argparse,json,subprocess,uuid
R=Path(__file__).resolve().parents[3];W=Path('E:/juan/FPGA')
ap=argparse.ArgumentParser();ap.add_argument('--summary',required=True);ap.add_argument('--validation',required=True);a=ap.parse_args()
now=datetime.now(timezone(timedelta(hours=8)));tag=now.strftime('%Y%m%d-%H%M%S')+'-sc520-color26-'+uuid.uuid4().hex[:6]
p=W/'workspace-records'/f'{tag}.json';files=[]
for folder in ['fpga/rtl/sc520-color-integration','fpga/sim/sc520-color-integration','hardware/sc520-color-integration']:
 files+=list((R/folder).glob('*'))
files+=list((R/'fpga/custom_project/sc520-color26/overlay').glob('*'))
files+=list((R/'fpga/custom_project/sc520-color26-bg/overlay').glob('*'))
files+=list((R/'fpga/scripts/sc520-card-recognition').glob('*color26*'))
files+=[R/'fpga/custom_project/sc520-color26/.gitattributes',R/'fpga/custom_project/sc520-color26-bg/.gitattributes',R/'memory/branches/sc520-color-integration.md']
files+=list((R/'evidence/sc520-color-integration').glob('*.json'))+[R/'evidence/sc520-color-integration/.gitignore']
changes=[{'Path':str(f),'Action':'modified' if f.name=='sc520-color-integration.md' else 'observed','Purpose':'T026独立候选源/测试/工具，当前工作字节；不覆写历史','Status':'开发中/待主审核'} for f in files if f.is_file()]
for folder in ['fpga/custom_project/sc520-color26/td_project','fpga/custom_project/sc520-color26-bg/td_project','evidence/sc520-color-integration']:
 if (R/folder).exists():changes.append({'Path':str(R/folder),'Action':'generated','Purpose':'本批独立工程/测试/构建输出；确切命令、输入与结果SHA见run-manifest/inputs/result','Status':'见验证字段，硬件未验证'})
changes.append({'Path':str(p),'Action':'added','Purpose':'本批独立登记','Status':'真实时间登记'})
p.write_text(json.dumps({'Id':tag,'UpdatedAt':now.isoformat(),'Task':'sc520-color-integration','Owner':'01a15235-d7ad-7531-b390-c5fd0941eea0 /root/color26_impl','Workdir':str(R),'Summary':a.summary,'Validation':a.validation,'NextStep':'主审核独立源/软件/物理证据，bitgen须另行放行；硬件/音频实测待验证','Changes':changes},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
for args in [[],['-Check']]:subprocess.run(['pwsh','-File',str(W/'anlogic-kids-learning-machine/tools/update-workspace-index.ps1'),*args],check=True)
print(tag)
