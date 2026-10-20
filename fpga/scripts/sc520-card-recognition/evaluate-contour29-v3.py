"""Measure exact v3 decision changes, including sparse color on a gray glyph."""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import importlib.util
import json
import numpy as np
from PIL import Image

R = Path(__file__).resolve().parents[3]
S = Path(__file__).parent
spec = importlib.util.spec_from_file_location("contour29_v3", S / "model-contour29-v3.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
spec = importlib.util.spec_from_file_location("contour29_eval1", S / "evaluate-contour29.py")
e = importlib.util.module_from_spec(spec)
spec.loader.exec_module(e)
OUT = R / "evidence/sc520-contour29/model-v3"


def row(rgb, bank, name, truth, **extra):
    result = m.recognize(rgb, bank)
    return dict(Name=name, Truth=truth, CandidateItem=result["item"], LegacyModelItem=result["legacy_item"],
                CardBest=result["card"]["best"], CardRaw=result["card"]["item"],
                FullShapeBits=result["full_shape"]["shape_bits"], FullDistances=result["full_shape"]["distances"],
                BodyDistances=result["contour_shape"]["distances"], BodyCircle=result["body_circle"],
                BodyEllipse=result["body_ellipse"], BodyValid=result["contour"]["valid"],
                FullColorCoverage=result["full_color_good"], BoundaryRepair=result["boundary_repair"],
                AspectConsistent=result["aspect_consistent"], Recovered=result["recovered"],
                NegativeOnly=result["negative_only"], **extra)


def main():
    OUT.mkdir(parents=True, exist_ok=False)
    bank = m.base.read_bank(e.A / "templates.mem")
    original = []
    for entry in json.loads((e.A / "fixtures.json").read_text()):
        path = e.A / "vectors" / (entry["prefix"] + ".rgb.mem")
        if not path.exists():
            path = path.with_suffix("").with_suffix(".png")
        original.append(row(m.base.sample_frame(e.read_rgb(path)), bank, entry["prefix"], entry["truth_item"],
                            Source=e.artifact(path), OriginalCategory=entry["category"]))
    synthetic = []
    yy, xx = np.mgrid[:60, :120]
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
                synthetic.append(row(rgb, bank, f"ellipse_{ratio}_{angle}_{damage}",
                                     1 if ratio >= 90 else 0, Synthetic=True))
    for area_width in (3, 5, 9, 13, 17):
        rgb = np.full((60, 120, 3), 240, np.uint8)
        gray = ((xx - 60) / 20) ** 2 + ((yy - 30) / 17) ** 2 <= 1
        rgb[gray] = (96, 96, 96)
        color = ((xx - 60) ** 2 + (yy - 30) ** 2 <= area_width ** 2) & gray
        rgb[color] = (180, 60, 60)
        synthetic.append(row(rgb, bank, f"gray_large_red_radius_{area_width}", 0,
                             Synthetic=True, RedFraction=float(color.sum() / gray.sum())))
    templates = []
    for ci, group in enumerate(bank):
        for vi, bits in enumerate(group):
            mask = np.zeros((32, 32), bool)
            mask[6:26, 6:26] = bits
            templates.append(dict(Item=ci + 10, Variant=vi, AxisCircle=m.v2.circle_axis_score(mask),
                                  Ellipse=m.v2.ellipse_score(mask)))
    regressions = [r for r in original if r["LegacyModelItem"] == r["Truth"] and r["CandidateItem"] != r["Truth"]]
    report = dict(At=datetime.now(timezone(timedelta(hours=8))).isoformat(),
                  Owner="Codex /root/shape27_delivery", Program=e.artifact(__file__),
                  Model=e.artifact(S / "model-contour29-v3.py"), PriorModel=e.artifact(S / "model-contour29-v2.py"),
                  OriginalFixtures=original, Synthetic=synthetic, Templates=templates, Regressions=regressions,
                  Summary=dict(OriginalFixtures=len(original), TemplateCount=len(templates),
                               OriginalOldCorrectLost=len(regressions),
                               TemplateNegativeRejects=sum(min(r["AxisCircle"], r["Ellipse"]) <= 20 for r in templates),
                               SyntheticCount=len(synthetic),
                               SyntheticFalseClass=sum(r["CandidateItem"] not in (0, r["Truth"]) for r in synthetic),
                               SyntheticMissed=sum(r["Truth"] != 0 and r["CandidateItem"] == 0 for r in synthetic),
                               SyntheticWrongCard=sum(r["CandidateItem"] >= 10 for r in synthetic),
                               SyntheticCorrectRecovered=sum(r["Recovered"] and r["CandidateItem"] == r["Truth"] for r in synthetic)),
                  Parameters=dict(FullGlyphColorCoverage="original >=2/3 and 2x other color retained",
                                  BodyCoverage="additional >=2/3 and same winner required",
                                  ShapeDistance=20, AliasRadii=[19, 20], CardDistance=40, CardClassMargin=24,
                                  CanonicalCompetitionMargin=16, RecoveryMargin=16,
                                  EllipseNegativeAngles=list(range(0, 180, 30)), EllipseNegativeAspects=[.6, .8],
                                  Recovery="body+seed aspect4/5..5/4, no repair at extremal boundary, circle alias distance strictly beats negative ellipse"),
                  Limits="Model-only. All truths fixed before running. Radius19 is a new sampling alias. False classes and missed recoveries remain separate. Baseline model is not a substitute for real old RTL.")
    (OUT / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report["Summary"]))


if __name__ == "__main__":
    main()
