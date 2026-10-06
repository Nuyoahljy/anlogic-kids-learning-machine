"""Convert complete RTL PPM snapshots without redrawing their contents."""
from pathlib import Path
import argparse
import hashlib
import json
from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument('--run-directory', type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[3]
summary = json.loads((args.run_directory / 'summary.json').read_text(encoding='utf-8-sig'))
assert summary['testcase'] == 'full' and summary['done'] == 1 and summary['errors'] == 0
output = root / 'evidence/sc520-learning-ui-audio/previews' / args.run_directory.name
output.mkdir(parents=True, exist_ok=True)
names = {4: 'test-red-circle', 36: 'test-yellow-square', 68: 'test-blue-triangle',
         83: 'camera-synthetic-square', 86: 'camera-synthetic-empty'}
records = []
for frame, name in names.items():
    ppm = args.run_directory / f'frame-{frame}.ppm'
    png = output / (name + '.png')
    with Image.open(ppm) as image:
        assert image.size == (1280, 720)
        image.save(png)
    records.append(dict(Frame=frame, Input=str(ppm), InputSHA256=hashlib.sha256(ppm.read_bytes()).hexdigest().upper(),
                        Output=str(png), OutputSHA256=hashlib.sha256(png.read_bytes()).hexdigest().upper(),
                        Kind='RTL pixels, including synthetic camera input; not a board photograph'))
(output / 'manifest.json').write_text(json.dumps(records, ensure_ascii=False, indent=2), encoding='utf-8')
print(output)
