"""Freeze one new C holdout before scoring the fixed C rule on old and new inputs."""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import argparse
import csv
import hashlib
import importlib.util
import json
import sys
import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parents[3]
SCRIPTS = Path(__file__).parent
EVIDENCE = REPO / "evidence/sc520-shape-card30"
MODEL = SCRIPTS / "model-shape-card30-c.py"
CONTRACT = Path("E:/juan/FPGA/learning/sc520-shape-card30/model-c-evaluation-scope.md")
TRUTH = EVIDENCE / "inputs-v2/truth-manifest.json"
TRUTH_SHA = "97BF961A8AFF619200556A6904DB21DFDE4E83A610B2F45C93999FA0FF2FA361"
OLD_REPORT = EVIDENCE / "model-v1/report.json"
OLD_REPORT_SHA = "B94DBFE4B4F8D2FE918EE343FBB20882F565738A1093B2CE79EBC6AB9CE3D845"
MEASUREMENTS = EVIDENCE / "model-v1-analysis/fullglyph-measurements.json"
MEASUREMENTS_SHA = "0D7F06CC24D7A593289E426C2619EA62B96E5DD32C65F0E1391A3F63FCCD68A8"


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


c = load("shape30_fixed_c", MODEL)
tools = load("shape30_c_frozen_runner", SCRIPTS / "evaluate-shape-card30.py")
if tools.artifact(SCRIPTS / "evaluate-shape-card30.py")["SHA256"] != "AA3BBEAF36AC8EB441BE84C2D8EC386EF6EF8C8CFABB3D3EBF64B3B5ACE6A2D3":
    raise RuntimeError("Frozen original runner changed")


def now():
    return datetime.now(timezone(timedelta(hours=8))).isoformat()


def source_bindings():
    tools.check(dict(Path=str(TRUTH), SHA256=TRUTH_SHA))
    tools.check(dict(Path=str(OLD_REPORT), SHA256=OLD_REPORT_SHA))
    tools.check(dict(Path=str(MEASUREMENTS), SHA256=MEASUREMENTS_SHA))
    truth, old = tools.read(TRUTH), tools.read(OLD_REPORT)
    for row in (truth["Bank"], truth["Model"], truth["Program"], truth["OriginalGeometryROM"],
                old["Scores"], old["ScoreCSV"]):
        tools.check(row)
    for row in truth["ImportedOracleSources"]+truth["ConstructionProofs"]:
        tools.check(row)
    return truth, old


def freeze(output):
    truth, old = source_bindings()
    physical_source = SCRIPTS / "generate-rotation-fixtures.py"
    physical = load("shape30_holdout_original_physical_frame", physical_source)
    output.mkdir(parents=True, exist_ok=False)
    rgb_directory = output / "rgb"
    rgb_directory.mkdir()
    cases = []

    def add(name, group, frame, item, construction):
        path = rgb_directory / (name+".rgb.mem")
        with path.open("x", encoding="ascii", newline="\n") as stream:
            stream.write("".join("%02X%02X%02X\n" % tuple(pixel) for pixel in frame.reshape(-1, 3)))
        cases.append(dict(Index=len(cases), Group=group, Name=name, InputKind="RGB",
                          SourceCatalog="shape3-cards5-v1-holdout", SourceTruth=item,
                          TaskCatalog="shape3-cards5-v1", TaskTruth=item, Source=tools.artifact(path),
                          SourceFileSHA256=tools.artifact(path)["SHA256"],
                          DecodedRGBSHA256=hashlib.sha256(frame.tobytes()).hexdigest().upper(),
                          Construction=construction, ExpectedPresent=True,
                          MappingReason="Fixed main-scoped holdout construction before C scoring",
                          CandidateScoresUsedToSelectInput=False))

    y, x = np.mgrid[:60, :120]
    palette = dict(gray=(64, 64, 64), green=(40, 130, 70), cyan=(30, 140, 140))
    for shape, item in (("circle", 1), ("square", 2), ("triangle", 3)):
        for color, rgb in palette.items():
            for radius in (14, 17):
                for angle in (0, 30, 60, 90):
                    a = np.deg2rad(angle)
                    u = (x-60)*np.cos(a)+(y-30)*np.sin(a)
                    v = -(x-60)*np.sin(a)+(y-30)*np.cos(a)
                    if shape == "circle":
                        mask = (x-60)**2+(y-30)**2 <= radius**2
                    elif shape == "square":
                        mask = (np.abs(u) <= radius) & (np.abs(v) <= radius)
                    else:
                        mask = (v >= -radius) & (v <= radius) & (2*np.abs(u) <= v+radius)
                    grid = np.full((60, 120, 3), 240, dtype=np.uint8)
                    grid[mask] = rgb
                    add(f"h_{shape}_{color}_r{radius}_a{angle}", "holdout-geometry",
                        tools.full_raster(grid), item,
                        dict(Geometry=shape, RGB=list(rgb), Radius=radius, Angle=angle,
                             CircleRasterRule="integer (x-60)^2+(y-30)^2 <= radius^2; angle never changes circle pixels",
                             OtherShapeRasterRule="same explicit rotated u/v analytic shape as prior; positive truth retained at all angles"))
    for ratio in (70, 82, 86):
        for angle in (0, 30, 60, 90):
            for color, rgb in (("gray", (64, 64, 64)), ("red", (180, 60, 60))):
                a = np.deg2rad(angle)
                u = (x-60)*np.cos(a)+(y-30)*np.sin(a)
                v = -(x-60)*np.sin(a)+(y-30)*np.cos(a)
                mask = (u/17)**2+(v/(17*ratio/100))**2 <= 1
                grid = np.full((60, 120, 3), 240, dtype=np.uint8)
                grid[mask] = rgb
                add(f"h_negative_ellipse{ratio}_{color}_a{angle}", "holdout-negative",
                    tools.full_raster(grid), 0,
                    dict(Geometry="noncircle ellipse", Ratio=ratio, Angle=angle, Radius=17,
                         RGB=list(rgb), Rule="Fixed rejection truth, never changed to circle from C output"))
    for shape in ("ring", "cross", "circle_appendage"):
        for color, rgb in (("gray", (64, 64, 64)), ("red", (180, 60, 60))):
            disk = (x-60)**2+(y-32)**2 <= 16**2
            if shape == "ring":
                mask = disk & ((x-60)**2+(y-32)**2 >= 9**2)
            elif shape == "cross":
                mask = ((np.abs(x-60) <= 5) & (np.abs(y-30) <= 18)) | (
                        (np.abs(x-60) <= 18) & (np.abs(y-30) <= 5))
            else:
                mask = disk | ((np.abs(x-60) <= 2) & (y >= 6) & (y <= 20))
            grid = np.full((60, 120, 3), 240, dtype=np.uint8)
            grid[mask] = rgb
            add(f"h_negative_{shape}_{color}", "holdout-negative", tools.full_raster(grid), 0,
                dict(Geometry=shape, RGB=list(rgb), Rule="Explicit noncanonical full silhouette, fixed unknown"))
    cards = []
    for item, name in ((10, "apple"), (11, "banana"), (12, "car"), (13, "star"), (14, "umbrella")):
        path = REPO / "assets/templates/sc520-card-recognition/prep-v1-max40/rendered" / f"card_{item}_{name}_256.png"
        source = Image.open(path).convert("RGB")
        cards.append(tools.artifact(path))
        for angle in (11, 79, 157, 257):
            for size in (49, 67):
                for gain in (1.0, 0.8):
                    frame, recipe = physical.physical_frame(source, angle, size, "white", position=1, phase=0)
                    if gain != 1.0:
                        frame = np.clip(np.floor(frame.astype(np.float64)*gain), 0, 255).astype(np.uint8)
                    add(f"h_card_{item}_a{angle}_s{size}_g{int(gain*100)}", "holdout-card", frame, item,
                        dict(SourceArt=tools.artifact(path), PhysicalFrameProgram=tools.artifact(physical_source),
                             PhysicalRecipe=recipe, Gain=gain,
                             PhotometricRule="Original full-raster floor(RGB*gain); source paper/background white before gain",
                             Resize="LANCZOS", Rotation="BICUBIC expand RGBA, alpha threshold128",
                             ScoringNotUsed=True))
    counts = {group: sum(row["Group"] == group for row in cases) for group in sorted({row["Group"] for row in cases})}
    if counts != {"holdout-card": 80, "holdout-geometry": 72, "holdout-negative": 30}:
        raise RuntimeError("Exact prior holdout Cartesian product required")
    manifest = dict(At=now(), Candidate="D0300", Stage="C_holdout_truth_frozen_before_candidate_scoring",
                    MainScope=tools.artifact(CONTRACT), Program=tools.artifact(__file__), Model=tools.artifact(MODEL),
                    OriginalTruth=tools.artifact(TRUTH), OriginalModelReport=tools.artifact(OLD_REPORT),
                    OriginalMeasurements=tools.artifact(MEASUREMENTS),
                    FrozenOriginalSources=[truth["Model"], truth["Program"], truth["Bank"], truth["OriginalGeometryROM"]],
                    PhysicalConstructionSources=[tools.artifact(SCRIPTS / name) for name in (
                        "generate-rotation-fixtures.py", "experiment-scene-rotation.py", "generate-scene-fixtures.py",
                        "scene-rotation-model.py", "scene-model.py")],
                    SourceCardArt=cards, Cases=cases, GroupCounts=counts, ScoresComputed=False,
                    FixedCandidateParameters=dict(YSpanMaximum=64, AspectMinTimes8GEmaxTimes7=True,
                        ShapeMaximum=20, AppleMaximum=32, OtherCardMaximum=40,
                        CardClassMargin=24, CrossFamilyMargin=8,
                        GeometryNegativeMargin=8, GeometryNegativeComparison="fullEllipse > min(effective3)+8"),
                    TemplateMode="Original1280 without RGB has no Y/bbox/positive-geometry eligibility. Original raw geometry distances remain negative card competitors.",
                    ScopeLimit="One fixed hypothesis fitted to seen stress evidence; this holdout is a new offline test, not field validation.",
                    RTLExecuted=False, TDExecuted=False, HardwareValidated=False)
    tools.save(output / "truth-manifest.json", manifest)
    print(json.dumps(dict(TruthManifest=tools.artifact(output / "truth-manifest.json"),
                          GroupCounts=counts, ScoresComputed=False)), flush=True)


def evaluate(inputs, output):
    truth, old = source_bindings()
    held = tools.read(inputs)
    if held["Stage"] != "C_holdout_truth_frozen_before_candidate_scoring" or held["ScoresComputed"]:
        raise RuntimeError("Freeze and independently review holdout first")
    for row in (held["Program"], held["Model"], held["MainScope"], held["OriginalTruth"],
                held["OriginalModelReport"], held["OriginalMeasurements"]):
        tools.check(row)
    for row in held["FrozenOriginalSources"]+held["PhysicalConstructionSources"]+held["SourceCardArt"]:
        tools.check(row)
    output.mkdir(parents=True, exist_ok=False)
    score_document = tools.read(old["Scores"]["Path"])
    descriptors = tools.read(MEASUREMENTS)["Rows"]
    keyed = {(row["Group"], row["Name"], row["Source"]["SHA256"]): row for row in descriptors}
    if len(keyed) != 791:
        raise RuntimeError("All original791 RGB measurement records required")
    rows = []
    for row in score_document["Rows"]:
        if row["InputKind"] == "NormalizedTemplate":
            descriptor = dict(GeometryAvailable=False, GlyphYMinimum=None, GlyphYMaximum=None,
                              GlyphYSpan=None, Width=None, Height=None)
        else:
            measured = keyed[(row["Group"], row["Name"], row["Source"]["SHA256"])]
            descriptor = dict(GeometryAvailable=bool(measured["GlyphCount"] and measured["Width"] and measured["Height"]),
                              GlyphYMinimum=measured["GlyphYMinimum"], GlyphYMaximum=measured["GlyphYMaximum"],
                              GlyphYSpan=measured["GlyphYSpan"], Width=measured["Width"], Height=measured["Height"])
            if measured["AxisCircleDistance"] != row["Score"]["FullAxisCircleDistance"]:
                raise RuntimeError("Original axis measurement mismatch")
        result = {**row, "CDescriptor": descriptor,
                  "CDecision": c.decide(row["Score"], descriptor, normalized_template=row["InputKind"] == "NormalizedTemplate")}
        rows.append(result)
    bank = c.ab.base.read_bank(truth["Bank"]["Path"])
    for case in held["Cases"]:
        tools.check(case["Source"])
        full = tools.read_rgb(case["Source"]["Path"])
        if hashlib.sha256(full.tobytes()).hexdigest().upper() != case["DecodedRGBSHA256"]:
            raise RuntimeError("Holdout pixels changed")
        scene = c.ab.scene(full)
        score = c.ab.scores(scene["mask"], bank, present=scene["present"], clipped=scene["clipped"], glyph=scene["glyph"])
        descriptor = c.describe(scene)
        rows.append({**case, "Score": score, "CDescriptor": descriptor, "CDecision": c.decide(score, descriptor),
                     "MaskSHA256": hashlib.sha256(scene["mask"].astype(np.uint8).tobytes()).hexdigest().upper(),
                     "SourceSet": "new_prior_frozen_holdout"})
    groups = {}
    for group in sorted({row["Group"] for row in rows}):
        selected = [row for row in rows if row["Group"] == group]
        groups[group] = tools.summary(selected, [row["CDecision"]["Item"] for row in selected])
    regressions = []
    for row in rows:
        if row.get("OriginalD0261ModelItem") == row["SourceTruth"] and row["TaskTruth"] >= 10 and row["CDecision"]["Item"] != row["TaskTruth"]:
            regressions.append(dict(Group=row["Group"], Name=row["Name"], Source=row["Source"],
                                    Truth=row["TaskTruth"], CDecision=row["CDecision"], Score=row["Score"]))
    tools.save(output / "scores.json", dict(HoldoutTruth=tools.artifact(inputs), Rows=rows))
    with (output / "scores.csv").open("x", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(["group", "name", "source_truth", "task_truth", "C_item", "raw_circle", "effective_circle",
                         "axis_eligible", "Y_available", "Y_span", "Y_reject_geometry", "card_maximum", "card_competitor"])
        for row in rows:
            d = row["CDecision"]
            writer.writerow([row["Group"], row["Name"], row["SourceTruth"], row["TaskTruth"], d["Item"],
                             d["RawCircleDistance"], d["EffectiveCircleDistance"], d["AxisCircleEligible"],
                             d["GeometryYSpanAvailable"], d["GeometryYSpan"], d["GeometryYRejected"],
                             d["CardMaximumDistance"], d["CardCompetitorDistance"]])
    # Both immutable sets are checked again after scoring.
    for case in truth["Cases"]+held["Cases"]:
        tools.check(case["Source"])
    result = dict(At=now(), Candidate="D0300", Stage="fixed_C_offline_evaluation", Program=tools.artifact(__file__),
                  Model=tools.artifact(MODEL), MainScope=tools.artifact(CONTRACT), OriginalTruth=tools.artifact(TRUTH),
                  OriginalModelReport=tools.artifact(OLD_REPORT), OriginalMeasurements=tools.artifact(MEASUREMENTS),
                  HoldoutTruth=tools.artifact(inputs), Scores=tools.artifact(output / "scores.json"),
                  ScoreCSV=tools.artifact(output / "scores.csv"), GroupCounts={group: row["Cases"] for group, row in groups.items()},
                  Groups=groups, OriginalCorrectCardRegressions=regressions,
                  SourceInputsUnchanged=True, ParameterConfigurations=1, MainAccepted=False,
                  ModelAccepted=False, RTLExecuted=False, TDExecuted=False, HardwareValidated=False,
                  CostMechanism="Full-only geometry/negative16bit ROM, one ERAM; full-axis second pass adds cycles; no colorbody/bridge. Y extrema are scalar regs; sums need10bits; aspect products widened shifts/adds, no DSP assumption.",
                  Limits="One prior fixed candidate, no threshold search. Template-only1280 have unavailable Y/bbox/positive geometry and are not RGB recognition tests. Original groups overlap; all source truth and prior failures retained.")
    tools.save(output / "report.json", result)
    print(json.dumps(dict(Report=tools.artifact(output / "report.json"), Groups={
        group: {key: row[key] for key in ("Cases", "Correct", "WrongClass", "Miss", "UnknownFalseAccept", "FalseApple")}
        for group, row in groups.items()}, OriginalCorrectCardRegressions=len(regressions))), flush=True)


def main():
    if sys.flags.optimize:
        raise RuntimeError("Do not disable C audit with -O")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--phase", choices=("freeze", "evaluate"), required=True)
    parser.add_argument("--inputs", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to(EVIDENCE):
        raise RuntimeError("New task-local directory required")
    if args.phase == "freeze":
        freeze(output)
    else:
        if not args.inputs:
            raise RuntimeError("Prior holdout truth manifest required")
        evaluate(args.inputs.resolve(strict=True), output)


if __name__ == "__main__":
    main()
