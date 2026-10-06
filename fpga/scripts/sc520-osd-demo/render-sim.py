import argparse
import json
from pathlib import Path
from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument("simulation_directory", type=Path)
parser.add_argument("output_directory", type=Path)
args = parser.parse_args()
args.output_directory.mkdir(parents=True, exist_ok=True)
frames = {4: "test-red-circle", 36: "test-yellow-square", 68: "test-blue-triangle", 83: "camera-synthetic-square", 86: "camera-synthetic-empty"}
records = []
for frame, name in frames.items():
    source = args.simulation_directory / f"frame-{frame}.ppm"
    image = Image.open(source)
    image.load()
    if image.size != (1280, 720) or image.mode != "RGB":
        raise ValueError(f"Invalid simulation raster: {source}")
    target = args.output_directory / f"{name}.png"
    image.save(target)
    records.append({"frame": frame, "source": str(source.resolve()), "png": str(target.resolve()), "kind": "RTL simulation, not hardware evidence"})
(args.output_directory / "manifest.json").write_text(json.dumps(records, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"RENDERED {len(records)} simulation rasters")
