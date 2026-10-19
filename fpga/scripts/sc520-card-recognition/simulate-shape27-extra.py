"""Run extra tests without mutating the runner belonging to in-flight snapshots."""
from pathlib import Path
R=Path(__file__).resolve().parents[3]
original=Path(__file__).with_name('simulate-shape27.py')
text=original.read_text()
text=text.replace("choices=['pipeline','reset','scenes','core']","choices=['lifecycle','render','pairing']")
text=text.replace("if a.test in ['scenes','scenes_bg']:","if a.test=='lifecycle':")
text=text.replace("refs+=list((R/'evidence/sc520-color-integration/fixtures').glob('*.mem'))",
    "refs+=list((R/('evidence/sc520-shape27/render-fixtures' if a.test=='render' else 'evidence/sc520-color-integration/fixtures')).glob('*.mem'))")
text=text.replace("sources=rtl+[tb,Path(__file__).resolve(),HERE/'run-shape27.do']+refs",
    "sources=rtl+[tb,Path(__file__).resolve(),HERE/'simulate-shape27.py',HERE/'run-shape27.do']+refs")
scope={'__name__':'__main__','__file__':str(Path(__file__).resolve())}
exec(compile(text,str(original),'exec'),scope)
