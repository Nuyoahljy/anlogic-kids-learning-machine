"""Compare T029 candidates on frozen fixtures and every existing card template."""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import argparse
import hashlib
import importlib.util
import json

import numpy as np
from PIL import Image, ImageDraw

R = Path(__file__).resolve().parents[3]
S = Path(__file__).parent
spec = importlib.util.spec_from_file_location("contour29", S / "model-contour29.py")
model = importlib.util.module_from_spec(spec)
spec.loader.exec_module(model)
A = R / "assets/templates/sc520-card-recognition/rotation-v1"


def artifact(path):
    path = Path(path).resolve(strict=True)
    return dict(Path=str(path), SHA256=hashlib.sha256(path.read_bytes()).hexdigest().upper(),
                Bytes=path.stat().st_size)


def read_rgb(path):
    if path.suffix == ".png":
        return np.asarray(Image.open(path).convert("RGB"))
    words = np.loadtxt(path, dtype=np.uint32, converters=lambda x: int(x, 16)).reshape(180, 320)
    return np.stack((words >> 16, (words >> 8) & 255, words & 255), axis=-1).astype(np.uint8)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--output", type=Path, required=True)
    args = ap.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    bank_path = A / "templates.mem"
    bank = model.base.read_bank(bank_path)
    rows = []
    for entry in json.loads((A / "fixtures.json").read_text()):
        path = A / "vectors" / (entry["prefix"] + ".rgb.mem")
        if not path.exists():
            path = path.with_suffix("").with_suffix(".png")
        rgb = model.base.sample_frame(read_rgb(path))
        result = model.recognize(rgb, bank)
        rows.append(dict(Name=entry["prefix"], Truth=entry["truth_item"], Source=artifact(path),
                         FullDistances=result["full_shape"]["distances"], CardBest=result["card"]["best"],
                         CardItem=result["card"]["item"], Geometry=result["geometry"],
                         CardGap=result["geometry"] - result["card"]["best"],
                         CandidateItem=result["item"], ContourValid=result["contour"]["valid"],
                         ContourDistances=result["contour_shape"]["distances"],
                         ContourRepairs=result["contour"]["repairs"]))
    template_rows = []
    for ci in range(5):
        for variant in range(bank.shape[1]):
            mask = np.zeros((32, 32), bool)
            mask[6:26, 6:26] = bank[ci, variant]
            shape = model.base.shape_classify(mask)
            card = model.base.classify(mask, bank)
            template_rows.append(dict(Item=ci + 10, Variant=variant,
                                      Geometry=min(shape["distances"]), CardBest=card["best"],
                                      Gap=min(shape["distances"]) - card["best"]))
    yy, xx = np.mgrid[:60, :120]
    synthetic = []
    images = []
    for ratio in (100, 90, 80, 70, 60):
        mask = ((xx - 60) / 16) ** 2 + ((yy - 30) / (16 * ratio / 100)) ** 2 <= 1
        for damage in ("plain", "holes", "shadow", "one_gap"):
            rgb = np.full((60, 120, 3), 240, np.uint8)
            rgb[mask] = (180, 60, 60)
            if damage == "holes":
                rgb[mask & (((xx + 3 * yy) % 5) == 0)] = (96, 96, 96)
            if damage == "shadow":
                rgb[(xx >= 66) & (xx <= 82) & (yy >= 23) & (yy <= 41) & ~mask] = (140, 140, 140)
            if damage == "one_gap":
                rgb[mask & (xx == 60)] = 240
            result = model.recognize(rgb, bank)
            row = dict(Name=f"ellipse_{ratio}_{damage}", Truth=1 if ratio >= 90 else 0,
                       Synthetic=True, CandidateItem=result["item"], CardRaw=result["card"]["item"],
                       CardBest=result["card"]["best"], Geometry=result["geometry"],
                       FullDistances=result["full_shape"]["distances"],
                       ContourDistances=result["contour_shape"]["distances"],
                       ContourValid=result["contour"]["valid"], Repairs=result["contour"]["repairs"])
            synthetic.append(row)
            if ratio in (100, 70) and damage in ("plain", "shadow", "one_gap"):
                tiles = [Image.fromarray(rgb), Image.fromarray(np.uint8(result["glyph"]) * 255).convert("RGB"),
                         Image.fromarray(np.uint8(result["contour"]["mask"]) * 255).convert("RGB")]
                strip = Image.new("RGB", (360, 80), "white")
                for i, tile in enumerate(tiles):
                    strip.paste(tile, (i * 120, 20))
                ImageDraw.Draw(strip).text((2, 2), row["Name"] + f" result={row['CandidateItem']} rawcard={row['CardRaw']}", fill="black")
                images.append(strip)
    montage = Image.new("RGB", (720, 80 * ((len(images) + 1) // 2)), "white")
    for i, strip in enumerate(images):
        montage.paste(strip, ((i % 2) * 360, (i // 2) * 80))
    montage.resize((1440, montage.height * 2), Image.Resampling.NEAREST).save(args.output / "synthetic-samples.png")
    margins = []
    for margin in (0, 8, 12, 16, 24):
        margins.append(dict(Margin=margin,
                            TemplatesRejected=sum(row["Gap"] <= margin for row in template_rows),
                            OldTrueCardsRejected=sum(row["Truth"] >= 10 and row["CardItem"] == row["Truth"] and
                                                     row["CardGap"] <= margin for row in rows)))
    report = dict(CreatedAt=datetime.now(timezone(timedelta(hours=8))).isoformat(),
                  Owner="Codex /root/shape27_delivery", Program=artifact(__file__),
                  Model=artifact(S / "model-contour29.py"), Bank=artifact(bank_path),
                  OriginalFixtureCount=len(rows), TemplateCount=len(template_rows),
                  CandidateThresholds=dict(EdgeDN=8, MaximumGapCells=1, CardGeometryMargin=24),
                  MarginSweep=margins, FrozenFixtures=rows, Templates=template_rows, Synthetic=synthetic,
                  Limits="Proposal model only; synthetic RGB is not reconstructed from user photographs. No RTL/TD/bitgen/hardware qualification.")
    (args.output / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(dict(OriginalFixtures=len(rows), Templates=len(template_rows), MarginSweep=margins,
                         SyntheticWrong=sum(row["CandidateItem"] != row["Truth"] for row in synthetic))))


if __name__ == "__main__":
    main()
