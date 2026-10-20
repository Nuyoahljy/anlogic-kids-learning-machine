"""Keep original truths while evaluating the explicit T029 v2 decision regions."""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import importlib.util
import json
import hashlib

import numpy as np
from PIL import Image, ImageDraw

R = Path(__file__).resolve().parents[3]
S = Path(__file__).parent
spec = importlib.util.spec_from_file_location("contour29_v2", S / "model-contour29-v2.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
spec1 = importlib.util.spec_from_file_location("evaluate29_v1", S / "evaluate-contour29.py")
old = importlib.util.module_from_spec(spec1)
spec1.loader.exec_module(old)
A = old.A
OUT = R / "evidence/sc520-contour29/model-v2"


def score(rgb, bank, name, truth, **extra):
    r = m.recognize(rgb, bank)
    full_bits = r["full_shape"]["shape_bits"]
    old_prediction = m.v1.recognize(rgb, bank, margin=-1025)
    # v1 with no effective competition is the old full-mask SH0/card route.
    legacy = old_prediction["block_item"] or (r["card"]["item"] if full_bits == 0 else 0)
    return dict(Name=name, Truth=truth, LegacyModelItem=legacy, CandidateItem=r["item"],
                RawCard=r["card"]["item"], CardBest=r["card"]["best"], FullShapeBits=full_bits,
                FullDistances=r["full_shape"]["distances"], BodyDistances=r["contour_shape"]["distances"],
                FullCircle=r["full_circle"], BodyCircle=r["body_circle"],
                FullEllipse=r["full_ellipse"], BodyEllipse=r["body_ellipse"],
                BodyValid=r["contour"]["valid"], NearSquare=r["near_square"],
                Recovered=r["recovered"], NegativeOnly=r["negative_only"], Conflict=r["conflict"],
                **extra), r


def main():
    OUT.mkdir(parents=True, exist_ok=False)
    bank = m.base.read_bank(A / "templates.mem")
    rows = []
    for entry in json.loads((A / "fixtures.json").read_text()):
        path = A / "vectors" / (entry["prefix"] + ".rgb.mem")
        if not path.exists():
            path = path.with_suffix("").with_suffix(".png")
        row, _ = score(m.base.sample_frame(old.read_rgb(path)), bank, entry["prefix"], entry["truth_item"],
                       Source=old.artifact(path), Required=entry.get("required"),
                       OriginalCategory=entry["category"])
        rows.append(row)
    templates = []
    for ci in range(5):
        for vi, body in enumerate(bank[ci]):
            mask = np.zeros((32, 32), bool)
            mask[6:26, 6:26] = body
            templates.append(dict(Item=ci + 10, Variant=vi,
                                  AxisCircle=m.circle_axis_score(mask), Ellipse=m.ellipse_score(mask)))
    synthetic = []
    panels = []
    yy, xx = np.mgrid[:60, :120]
    for ratio in (100, 90, 80, 70, 60):
        for angle in (0, 15, 30, 45, 60, 75, 90):
            a = np.deg2rad(angle)
            u = (xx - 60) * np.cos(a) + (yy - 30) * np.sin(a)
            v = -(xx - 60) * np.sin(a) + (yy - 30) * np.cos(a)
            silhouette = (u / 16) ** 2 + (v / (16 * ratio / 100)) ** 2 <= 1
            for damage in ("plain", "holes", "shadow", "one_gap"):
                rgb = np.full((60, 120, 3), 240, np.uint8)
                rgb[silhouette] = (180, 60, 60)
                if damage == "holes":
                    rgb[silhouette & ((xx + 3 * yy) % 5 == 0)] = (96, 96, 96)
                if damage == "shadow":
                    rgb[(xx >= 66) & (xx <= 82) & (yy >= 23) & (yy <= 41) & ~silhouette] = (140, 140, 140)
                if damage == "one_gap":
                    rgb[silhouette & (xx == 60)] = 240
                truth = 1 if ratio >= 90 else 0
                name = f"ellipse_{ratio}_{angle}_{damage}"
                row, result = score(rgb, bank, name, truth, Synthetic=True)
                synthetic.append(row)
                if ratio in (100, 80) and angle == 0 and damage in ("plain", "shadow", "one_gap"):
                    panel = Image.new("RGB", (480, 85), "white")
                    ImageDraw.Draw(panel).text((2, 2), name + f" legacy={row['LegacyModelItem']} new={row['CandidateItem']}", fill="black")
                    panel.paste(Image.fromarray(rgb), (0, 23))
                    for i, mask in enumerate((result["glyph"], result["contour"]["mask"], result["mask"])):
                        panel.paste(Image.fromarray(np.uint8(mask) * 255).convert("RGB"), ((i + 1) * 120, 23))
                    panels.append(panel)
    montage = Image.new("RGB", (960, 85 * ((len(panels) + 1) // 2)), "white")
    for i, panel in enumerate(panels):
        montage.paste(panel, ((i % 2) * 480, (i // 2) * 85))
    montage.resize((1920, montage.height * 2), Image.Resampling.NEAREST).save(OUT / "synthetic-samples.png")
    regression = [r for r in rows if r["LegacyModelItem"] == r["Truth"] and r["CandidateItem"] != r["Truth"]]
    report = dict(CreatedAt=datetime.now(timezone(timedelta(hours=8))).isoformat(),
                  Owner="Codex /root/shape27_delivery", Model=old.artifact(S / "model-contour29-v2.py"),
                  PriorModel=old.artifact(S / "model-contour29.py"), Program=old.artifact(__file__),
                  Parameters=dict(EdgeDN=8, GapCells=1, CardCanonicalMargin=16, RecoveryMargin=16,
                                  ShapeDistance=20, CardDistance=40, CardClassMargin=24,
                                  CircleAliases=[19, 20], NegativeEllipseAspects=[.6, .8],
                                  NegativeEllipseAngles=list(range(0, 180, 30)),
                                  PublicCircleAspect="width*5>=height*4 and height*5>=width*4"),
                  Disclosure="Radius19 is an additional sampling-alias template, not an unchanged shape20 boundary; its effect is measured explicitly. Ellipse family is rejection-only, never a public circle bit.",
                  Summary=dict(OriginalFixtures=len(rows), Templates=len(templates),
                               OldCorrectLost=len(regression),
                               NewTemplateEllipseRejects=sum(min(r["AxisCircle"], r["Ellipse"]) <= 20 for r in templates),
                               Synthetic=len(synthetic), SyntheticWrong=sum(r["CandidateItem"] != r["Truth"] for r in synthetic),
                               SyntheticWrongCard=sum(r["CandidateItem"] >= 10 for r in synthetic),
                               Recovered=sum(r["Recovered"] and r["CandidateItem"] == r["Truth"] for r in synthetic)),
                  OriginalFixtures=rows, Regressions=regression, Templates=templates, Synthetic=synthetic,
                  Limits="Model only. Fixed truths retained; synthetic circles/ellipses do not reconstruct field photos. Worst case latency/resource and complete RTL qualification are not yet verified.")
    (OUT / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report["Summary"]))


if __name__ == "__main__":
    main()
