#!/usr/bin/env python3
"""Losslessly convert actual ModelSim PPM outputs and bind both file hashes.

Works for OSD strips and later full-frame PPMs without cropping, resizing,
recolouring or inventing a camera image. Requires Pillow for image decoding.
"""
import argparse
from datetime import datetime, timedelta, timezone
import hashlib
from io import BytesIO
import json
from pathlib import Path
import re
import sys
import PIL
from PIL import Image


def sha(data):
    return hashlib.sha256(data).hexdigest().upper()


def output_name(source):
    # ModelSim 10.7 formats %02d with a leading space for one-digit cases.
    # Keep the original evidence filename untouched; normalise only PNG names.
    match = re.fullmatch(r"quiz-osd-\s*(\d+)", source.stem)
    if match:
        return f"quiz-osd-{int(match.group(1)):02d}.png"
    stem = re.sub(r"[^A-Za-z0-9_.-]+", "_", source.stem)
    if not stem:
        raise ValueError(f"Cannot derive an ASCII preview filename: {source}")
    return stem + ".png"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-directory", type=Path, required=True)
    parser.add_argument("--output-directory", type=Path, required=True)
    args = parser.parse_args()
    source_dir = args.run_directory.resolve()
    output_dir = args.output_directory.resolve()
    if not source_dir.is_dir():
        parser.error("Actual simulation run directory does not exist")
    if source_dir == output_dir:
        parser.error("Keep previews separate from immutable simulation outputs")
    sources = sorted(source_dir.glob("*.ppm"))
    if not sources:
        parser.error("No actual PPM outputs found")
    names = [output_name(source) for source in sources]
    if len(set(names)) != len(names):
        parser.error("Preview filename normalisation would collide")
    entries = []
    output_dir.mkdir(parents=True, exist_ok=True)
    for source, name in zip(sources, names):
        source_bytes = source.read_bytes()
        with Image.open(BytesIO(source_bytes)) as decoded:
            decoded.load()
            image = decoded.convert("RGB")
        png_buffer = BytesIO()
        image.save(png_buffer, format="PNG", optimize=False)
        png_bytes = png_buffer.getvalue()
        # The decoded output must preserve every source RGB pixel exactly.
        with Image.open(BytesIO(png_bytes)) as roundtrip:
            roundtrip.load()
            if roundtrip.size != image.size or roundtrip.convert("RGB").tobytes() != image.tobytes():
                raise ValueError(f"Lossless pixel comparison failed: {source}")
        destination = output_dir / name
        if destination.exists():
            if destination.read_bytes() != png_bytes:
                raise FileExistsError(f"Refusing to replace a different preview: {destination}")
        else:
            with destination.open("xb") as out:
                out.write(png_bytes)
        if source.read_bytes() != source_bytes:
            raise ValueError(f"PPM changed during conversion: {source}")
        entries.append({
            "Input": str(source), "InputBytes": len(source_bytes), "InputSHA256": sha(source_bytes),
            "Output": str(destination), "OutputBytes": len(png_bytes), "OutputSHA256": sha(png_bytes),
            "Width": image.width, "Height": image.height, "RGBPixelsEqual": True,
            "Interpretation": "top_0_119_and_bottom_600_719_strips" if image.size == (1280, 240) else "unaltered_full_image",
        })
    run_manifest = source_dir / "run-manifest.json"
    manifest = {
        "GeneratedAt": datetime.now(timezone(timedelta(hours=8))).isoformat(),
        "Owner": "sc520-quiz-video /root/preview_keys",
        "SourceRun": str(source_dir),
        "SourceRunManifest": str(run_manifest) if run_manifest.exists() else None,
        "SourceRunManifestSHA256": sha(run_manifest.read_bytes()) if run_manifest.exists() else None,
        "Generator": str(Path(__file__).resolve()), "GeneratorSHA256": sha(Path(__file__).read_bytes()),
        "Python": sys.version, "Pillow": PIL.__version__,
        "Transform": "PPM decode to RGB and PNG encode only; no resize, crop, drawing or colour editing",
        "PhysicalHardwareEvidence": False, "Files": entries,
    }
    destination = output_dir / "preview-manifest.json"
    destination.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"PREVIEW_CONVERTED count={len(entries)} pixels_equal=true manifest={destination}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
