"""Measure T029 v4 on fixed old labels and internal-versus-exterior damage."""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import importlib.util
import json
import numpy as np
from PIL import Image, ImageDraw

R = Path(__file__).resolve().parents[3]
S = Path(__file__).parent
spec = importlib.util.spec_from_file_location("contour29_v4", S / "model-contour29-v4.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
spec = importlib.util.spec_from_file_location("contour29_eval1", S / "evaluate-contour29.py")
e = importlib.util.module_from_spec(spec)
spec.loader.exec_module(e)
OUT = R / "evidence/sc520-contour29/model-v4"


def make_row(rgb, bank, name, truth, **extra):
    r = m.recognize(rgb, bank)
    return dict(Name=name, Truth=truth, CandidateItem=r["item"], LegacyModelItem=r["legacy_item"],
                CardRaw=r["card"]["item"], CardBest=r["card"]["best"],
                FullShapeBits=r["full_shape"]["shape_bits"], FullDistances=r["full_shape"]["distances"],
                BodyCircle=r["body_circle"], BodyEllipse=r["body_ellipse"], FullEllipse=r["full_ellipse"],
                BodyValid=r["contour"]["valid"], FullColorCoverage=r["full_color_good"],
                ExteriorResidual=r["exterior_count"], ExteriorQualified=r["exterior_qualified"],
                BoundaryRepair=r["boundary_repair"], Recovered=r["recovered"],
                NegativeOnly=r["negative_only"], **extra), r


def main():
    OUT.mkdir(parents=True, exist_ok=False)
    bank = m.base.read_bank(e.A / "templates.mem")
    original, synthetic, retained27 = [], [], []
    for entry in json.loads((e.A / "fixtures.json").read_text()):
        path = e.A / "vectors" / (entry["prefix"] + ".rgb.mem")
        if not path.exists():
            path = path.with_suffix("").with_suffix(".png")
        row, _ = make_row(m.base.sample_frame(e.read_rgb(path)), bank, entry["prefix"], entry["truth_item"],
                          Source=e.artifact(path), OriginalCategory=entry["category"])
        original.append(row)
    for entry in json.loads((R / "evidence/sc520-shape27/fixtures/manifest.json").read_text())["Cases"]:
        path = Path(entry["Path"])
        row, _ = make_row(m.base.sample_frame(e.read_rgb(path)), bank, entry["Name"], entry["Item"],
                          Source=e.artifact(path))
        retained27.append(row)
    yy, xx = np.mgrid[:60, :120]
    sample_panels = []
    for ratio in (100, 90, 80, 70, 60):
        for angle in (0, 15, 30, 45, 60, 75, 90):
            a = np.deg2rad(angle)
            u = (xx - 60) * np.cos(a) + (yy - 30) * np.sin(a)
            v = -(xx - 60) * np.sin(a) + (yy - 30) * np.cos(a)
            mask = (u / 16) ** 2 + (v / (16 * ratio / 100)) ** 2 <= 1
            for damage in ("plain", "holes", "shadow", "one_gap"):
                rgb = np.full((60, 120, 3), 240, np.uint8)
                rgb[mask] = (180, 60, 60)
                if damage == "holes":
                    rgb[mask & ((xx + 3 * yy) % 5 == 0)] = (96, 96, 96)
                if damage == "shadow":
                    rgb[(xx >= 66) & (xx <= 82) & (yy >= 23) & (yy <= 41) & ~mask] = (140, 140, 140)
                if damage == "one_gap":
                    rgb[mask & (xx == 60)] = 240
                name = f"ellipse_{ratio}_{angle}_{damage}"
                row, result = make_row(rgb, bank, name, 1 if ratio >= 90 else 0, Synthetic=True)
                synthetic.append(row)
                if ratio in (100, 80) and angle == 0 and damage in ("plain", "shadow", "one_gap"):
                    panel = Image.new("RGB", (480, 85), "white")
                    ImageDraw.Draw(panel).text((2, 2), name + f" old={row['LegacyModelItem']} new={row['CandidateItem']}", fill="black")
                    panel.paste(Image.fromarray(rgb), (0, 23))
                    for i, mask_value in enumerate((result["glyph"], result["contour"]["mask"], result["exterior_residual"])):
                        panel.paste(Image.fromarray(np.uint8(mask_value) * 255).convert("RGB"), ((i + 1) * 120, 23))
                    sample_panels.append(panel)
    for radius in (3, 5, 9, 13, 17):
        rgb = np.full((60, 120, 3), 240, np.uint8)
        gray = ((xx - 60) / 20) ** 2 + ((yy - 30) / 17) ** 2 <= 1
        color = ((xx - 60) ** 2 + (yy - 30) ** 2 <= radius ** 2) & gray
        rgb[gray] = (96, 96, 96)
        rgb[color] = (180, 60, 60)
        row, _ = make_row(rgb, bank, f"gray_large_red_radius_{radius}", 0, Synthetic=True,
                          RedFraction=float(color.sum() / gray.sum()))
        synthetic.append(row)
    # Appendages remain foreground evidence even when neutral, and cannot be
    # silently discarded by the color-body branch.
    for length in (3, 6, 10):
        rgb = np.full((60, 120, 3), 240, np.uint8)
        disk = (xx - 60) ** 2 + (yy - 32) ** 2 <= 14 ** 2
        rgb[disk] = (180, 60, 60)
        rgb[32 - 14 - length:32 - 12, 58:62] = (80, 80, 80)
        row, _ = make_row(rgb, bank, f"circle_with_neutral_appendage_{length}", 0, Synthetic=True)
        synthetic.append(row)
    templates = []
    for ci, group in enumerate(bank):
        for vi, bits in enumerate(group):
            mask = np.zeros((32, 32), bool)
            mask[6:26, 6:26] = bits
            templates.append(dict(Item=ci + 10, Variant=vi,
                                  AxisCircle=m.v3.v2.circle_axis_score(mask),
                                  Ellipse=m.v3.v2.ellipse_score(mask)))
    montage = Image.new("RGB", (960, 85 * ((len(sample_panels) + 1) // 2)), "white")
    for i, panel in enumerate(sample_panels):
        montage.paste(panel, ((i % 2) * 480, (i // 2) * 85))
    montage.resize((1920, montage.height * 2), Image.Resampling.NEAREST).save(OUT / "synthetic-samples.png")
    regressions = [r for r in original if r["LegacyModelItem"] == r["Truth"] and r["CandidateItem"] != r["Truth"]]
    report = dict(At=datetime.now(timezone(timedelta(hours=8))).isoformat(),
                  Owner="Codex /root/shape27_delivery", Program=e.artifact(__file__),
                  Model=e.artifact(S / "model-contour29-v4.py"),
                  Parameters=dict(FullGlyphCoverage="original >=2/3 and 2x each other color",
                                  BodyCoverage="additional >=2/3 and same winner", ExternalRemainderMaximum=11,
                                  EdgeDN=8, OneCellBridge=True, CircleAliasRadii=[19, 20],
                                  ShapeDistance=20, CardDistance=40, CardClassMargin=24,
                                  RecoveryMargin=16, CanonicalCardMargin=16,
                                  NonCircleEllipseAspects=[.6, .8], NonCircleEllipseAngles=list(range(0, 180, 30))),
                  Summary=dict(OriginalFixtures=len(original), T027Fixtures=len(retained27), Templates=len(templates),
                               OriginalOldCorrectLost=len(regressions),
                               T027Wrong=sum(r["CandidateItem"] != r["Truth"] for r in retained27),
                               TemplateNegativeRejects=sum(min(r["AxisCircle"], r["Ellipse"]) <= 20 for r in templates),
                               SyntheticCount=len(synthetic),
                               SyntheticFalseClass=sum(r["CandidateItem"] not in (0, r["Truth"]) for r in synthetic),
                               SyntheticMissed=sum(r["Truth"] != 0 and r["CandidateItem"] == 0 for r in synthetic),
                               SyntheticWrongCard=sum(r["CandidateItem"] >= 10 for r in synthetic),
                               CorrectRecoveries=sum(r["Recovered"] and r["CandidateItem"] == r["Truth"] for r in synthetic)),
                  OriginalFixtures=original, RetainedT027=retained27, Templates=templates,
                  Synthetic=synthetic, Regressions=regressions,
                  Limits="Model only; fixed labels retained. Neutral exterior extensions deliberately cause unknown; no claim that all shadows or all physical circles are recovered. New sampling alias is explicit. Old model still needs real RTL baseline corroboration.")
    (OUT / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report["Summary"]))


if __name__ == "__main__":
    main()
