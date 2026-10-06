import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageDraw

parser = argparse.ArgumentParser()
parser.add_argument("simulation_directory", type=Path)
args = parser.parse_args()
root = args.simulation_directory.resolve()
summary = json.loads((root / "summary.json").read_text(encoding="utf-8"))
if summary["negative"] != 0 or summary["done"] != 1 or summary["errors"] != 0:
    raise ValueError("Render only a completed passing normal simulation.")
labels = {
    **{i: f"RTL SIMULATION / item {i+1} / TEST INPUT / not hardware evidence" for i in range(9)},
    9: "RTL SIMULATION / item 1 / CAMERA INPUT (synthetic signals) / not hardware evidence",
    25: "RTL SIMULATION / det_valid=0 / NO TARGET / not hardware evidence",
    32: "RTL SIMULATION / item 5 / AUDIO SIMULATION FAULT / not hardware evidence",
}
rows = []
records = []
for index, label in labels.items():
    source = root / f"panel-{index}.ppm"
    raster = Image.open(source)
    raster.load()
    if raster.size != (1280, 128) or raster.mode != "RGB":
        raise ValueError(f"Unexpected simulation raster: {source}")
    target = root / f"panel-{index}.png"
    raster.save(target)
    row = Image.new("RGB", (1280, 152), (238, 242, 245))
    row.paste(raster, (0, 24))
    ImageDraw.Draw(row).text((8, 6), label, fill=(20, 28, 35))
    rows.append(row)
    records.append({"scenario": index, "ppm": str(source), "ppm_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
                    "png": str(target), "png_sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
                    "kind": "RTL simulation, not hardware evidence"})
sheet = Image.new("RGB", (1280, len(rows) * 152))
for index, row in enumerate(rows):
    sheet.paste(row, (0, index * 152))
sheet.save(root / "contact-sheet.png")
(root / "render-manifest.json").write_text(json.dumps(records, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"RENDERED {len(records)} pixel-checked panels and contact-sheet.png")
