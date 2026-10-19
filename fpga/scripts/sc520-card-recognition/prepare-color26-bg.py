"""Generate T026 from a separately owned overlay, using the proven TD dialect writer."""
from pathlib import Path
import argparse
SOURCE=Path(__file__).with_name('prepare-timing23.py')
text=SOURCE.read_text(encoding='utf-8')
text=text.replace("PROJECT=REPO/'fpga/custom_project/sc520-timing23'","PROJECT=REPO/'fpga/custom_project/sc520-color26-bg'")
text=text.replace("sources += sorted((RTL/'timing23').glob('*.v'))","sources += sorted((RTL/'timing23').glob('*.v'))\n    sources += sorted((REPO/'fpga/rtl/sc520-color-integration').glob('*.v'))")
text=text.replace("('prepare-timing23.py','build-timing23.ps1','audit-timing23-reset.py')","('prepare-color26-bg.py','build-color26-bg.ps1','prepare-timing23.py','audit-timing23-reset.py')")
text=text.replace("('offline-test.json' if snapshot else 'hardware-default.json')","'hardware-default.json'")
start=text.index("    if snapshot:\n        assert profile['TestOnly']")
end=text.index("    save(destination/'profile.json'",start)
text=text[:start]+"    assert not profile['TestOnly'] and profile['TRACKS']==[]\n"+text[end:]
text=text.replace('T023 forbids bitgen','T026 forbids bitgen until main review')
text=text.replace('01a144c7-e802-7272-a29d-a8159f5ec84b /root T023','01a15235-d7ad-7531-b390-c5fd0941eea0 /root/color26_impl T026')
# Execute the exact inherited writer in this module's directory; the inherited
# input is itself copied and SHA-bound in every build. No legacy file is edited.
scope={'__name__':'color26_writer','__file__':str(__file__)}
exec(compile(text,str(SOURCE),'exec'),scope)
if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--snapshot',type=Path);a=ap.parse_args()
    target=a.snapshot or scope['PROJECT']
    if a.snapshot:target.mkdir(parents=True,exist_ok=False)
    scope['make'](target,bool(a.snapshot))
