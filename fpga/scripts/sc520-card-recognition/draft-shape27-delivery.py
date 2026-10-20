"""Write a factual build-in-progress delivery draft; never assign bit qualification."""
from pathlib import Path
from datetime import datetime,timezone,timedelta
import hashlib,json,subprocess
R=Path(__file__).resolve().parents[3]
E=R/'evidence/sc520-shape27'
run=E/'builds/6a50b270'
def artifact(p):
    p=Path(p)
    return {'Path':str(p),'SHA256':hashlib.sha256(p.read_bytes()).hexdigest().upper(),'Bytes':p.stat().st_size}
approval=Path('E:/juan/FPGA/learning/sc520-shape27/main-review/software-approved.json')
a=json.loads(approval.read_text())
assert a['BuildAllowed'] and not a['BitGenerationAllowed'] and a['BuildRun']=='6a50b270'
inputs=json.loads((run/'inputs.json').read_text())
assert len(inputs['Files'])==396 and len(inputs['ManifestSources'])==121
m=json.loads((E/'software-v1.json').read_text())
for item in m['SourceFreeze']:
    assert artifact(item['Path'])['SHA256']==item['SHA256'],item['Path']
report={
    'CreatedAt':datetime.now(timezone(timedelta(hours=8))).isoformat(),
    'Owner':'Codex /root/shape27_impl_resume','Candidate':'D0270',
    'State':'software_accepted_build_in_progress','Draft':True,
    'Purpose':'Future user-controlled SRAM validation on a white substrate',
    'ProductionSourceCommit':a['SourceCommit'],
    'CurrentGitHead':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
    'Approval':artifact(approval),
    'SoftwareManifest':artifact(E/'software-v1.json'),
    'MainSoftwareReview':artifact(a['SoftwareReview']['Path']),
    'IndependentSoftwareReview':artifact(a['IndependentReview']['Path']),
    'FrozenD0261Protection':artifact(E/'protected-d0261.json'),
    'Build':{'RunId':'6a50b270','Inputs':artifact(run/'inputs.json'),
        'Started':artifact(run/'started.json'),'InputCount':396,'ProjectReferenceCount':121},
    'PhysicalReview':None,'RouteDatabase':None,'Bit':None,
    'PhysicalQualified':False,'BitGenerationAllowed':False,'DownloadAllowed':False,
    'FlashAllowed':False,'HardwareValidated':False,
    'GuideDraft':artifact(R/'hardware/sc520-shape27/d0270-sram-guide.md'),
    'NextStep':'Wait for native route completion, independent new physical review and main acceptance; bitgen needs a separate SHA-bound approval.',
}
p=E/'delivery-draft.json'
with p.open('x',encoding='utf-8',newline='\n') as f:json.dump(report,f,ensure_ascii=False,indent=2);f.write('\n')
print(json.dumps({'Draft':artifact(p),'PhysicalQualified':False,'BitGenerationAllowed':False}))
