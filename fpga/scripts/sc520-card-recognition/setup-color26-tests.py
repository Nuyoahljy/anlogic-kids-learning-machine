"""Prepare independent test derivatives; production historic RTL/goldens remain immutable."""
from pathlib import Path
import re
R=Path(__file__).resolve().parents[3]
S=Path(__file__).resolve().parent
def put(p,s):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(s,encoding='utf-8',newline='\n')
build=(S/'build-timing23.ps1').read_text(encoding='utf-8').replace('prepare-timing23.py','prepare-color26.py').replace('evidence/sc520-card-recognition/builds/','evidence/sc520-color-integration/builds/').replace('01a144c7-e802-7272-a29d-a8159f5ec84b /root T023','01a15235-d7ad-7531-b390-c5fd0941eea0 /root/color26_impl T026').replace('T023','T026').replace('TestOnly=$true','TestOnly=$false')
put(S/'build-color26.ps1',build)
for name in ('pipeline','reset'):
    p=R/'fpga/sim/sc520-card-recognition/timing23'/f'tb_timing23_{name}.sv'
    s=p.read_text(encoding='utf-8').replace('tb_timing23_','tb_color26_').replace('pixel23_pipeline','pixel26_pipeline').replace('pixel14_color_pipeline','pixel26_color_pipeline')
    put(R/'fpga/sim/sc520-color-integration'/f'tb_color26_{name}.sv',s)
print('T026_TEST_DERIVATIVES_PREPARED')
