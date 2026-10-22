"""Freeze construction-based T030 truths first, then export same-input score sweeps."""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import argparse
import csv
import hashlib
import importlib.util
import json
import sys

import numpy as np
from PIL import Image, ImageDraw

REPO = Path(__file__).resolve().parents[3]
SCRIPTS = Path(__file__).parent
ASSETS = REPO / "assets/templates/sc520-card-recognition/rotation-v1"
EVIDENCE = REPO / "evidence/sc520-shape-card30"
MODEL = SCRIPTS / "model-shape-card30.py"
CATALOG = "shape3-cards5-v1"
WHITELIST = Path("E:/juan/FPGA/learning/sc520-shape-card30/review/tasktruth-whitelist-v1.json")
WHITELIST_SHA = "F078FB542694107B0BE5274F65E57EAB170A91CF4A9362A1B14BD5908BA06E4C"
spec = importlib.util.spec_from_file_location("shape_card30_model", MODEL)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


def artifact(path):
    path = Path(path).resolve(strict=True)
    return dict(Path=str(path), SHA256=hashlib.sha256(path.read_bytes()).hexdigest().upper(), Bytes=path.stat().st_size)


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def check(row):
    actual = artifact(row["Path"])
    if actual["SHA256"] != row["SHA256"] or ("Bytes" in row and actual["Bytes"] != row["Bytes"]):
        raise RuntimeError("Frozen input changed: " + row["Path"])
    return actual


def save(path, value):
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write("\n")


def read_rgb(path):
    path = Path(path)
    if path.suffix == ".png":
        return np.asarray(Image.open(path).convert("RGB"))
    words = np.asarray([int(word, 16) for word in path.read_text().split()], dtype=np.uint32).reshape(180, 320)
    return np.stack((words >> 16, (words >> 8) & 255, words & 255), axis=-1).astype(np.uint8)


def full_raster(grid):
    result = np.full((180, 320, 3), 240, dtype=np.uint8)
    result[30:150, 40:280] = np.repeat(np.repeat(grid, 2, axis=0), 2, axis=1)
    return result


def freeze(output):
    output.mkdir(parents=True, exist_ok=False)
    rgb_directory = output / "synthetic-rgb"
    rgb_directory.mkdir()
    # These proofs are read before any candidate score is computed.
    square_generator = SCRIPTS / "setup-shape27-tests.py"
    rotation_generator = SCRIPTS / "generate-rotation-fixtures.py"
    scene_generator = SCRIPTS / "generate-scene-fixtures.py"
    square_source = square_generator.read_text(encoding="utf-8")
    scene_source = scene_generator.read_text(encoding="utf-8")
    if "Extra negatives anchored to square silhouette" not in square_source or (
            'if shape=="circle":d.ellipse((132,64,187,117),fill=fill)' not in scene_source):
        raise RuntimeError("Reviewed construction proof changed")
    proofs = [artifact(path) for path in (square_generator, rotation_generator, scene_generator)]
    shape_cases = read(REPO / "evidence/sc520-shape27/fixtures/manifest.json")["Cases"]
    rotations = read(ASSETS / "fixtures.json")
    gray_names = ("gray", "sparse_red", "half_color", "gray_external")
    check(dict(Path=str(WHITELIST), SHA256=WHITELIST_SHA))
    approved_whitelist = read(WHITELIST)
    whitelist = {row["DecodedRGBSHA256"]: row for row in approved_whitelist["MainApprovedCases"]}
    if len(whitelist) != 5:
        raise RuntimeError("Exactly the five approved construction pixel hashes are required")
    decisions = []
    for case in shape_cases:
        if case["Name"] in gray_names:
            actual = check(dict(Path=case["Path"], SHA256=case["SHA256"]))
            reason = "Reviewed generator anchors this complete silhouette to item2 square; color-only rejection is retired."
            if case["Name"] == "gray_external":
                reason += " Three isolated 2x2 noise patches are explicitly disclosed, not relabeled from output."
            pixel_sha = hashlib.sha256(read_rgb(actual["Path"]).tobytes()).hexdigest().upper()
            if whitelist[pixel_sha]["TaskTruth"] != 2:
                raise RuntimeError("Square construction does not match the approved decoded RGB")
            decisions.append(dict(Name=case["Name"], Source=actual, SourceTruth=0, TaskTruth=2,
                                  ConstructionProgram=artifact(square_generator), EvidenceLines="31..41",
                                  Evidence="Extra negatives anchored to square silhouette; item==2 full mask",
                                  MappingReason=reason))
    gray_circle = next(case for case in rotations if case["prefix"] == "r153_unknown_gray_circle")
    circle_path = ASSETS / "vectors" / (gray_circle["prefix"] + ".rgb.mem")
    if not circle_path.exists():
        circle_path = circle_path.with_suffix("").with_suffix(".png")
    actual = artifact(circle_path)
    reason = "Reviewed upstream construction draws a complete neutral circle; old0 was a color-catalog refusal."
    pixel_sha = hashlib.sha256(read_rgb(actual["Path"]).tobytes()).hexdigest().upper()
    if whitelist[pixel_sha]["TaskTruth"] != 1:
        raise RuntimeError("Gray circle does not match the approved decoded RGB")
    decisions.append(dict(Name=gray_circle["prefix"], Source=actual, SourceTruth=0, TaskTruth=1,
                          ConstructionProgram=artifact(scene_generator), ImportProgram=artifact(rotation_generator),
                          EvidenceLines="generate-scene-fixtures.py 143..149; generate-rotation-fixtures.py 125..128",
                          Evidence="Gray shapes cannot get a block-color label; ellipse(132,64,187,117) imported as unknown_gray_circle",
                          MappingReason=reason))
    if len(decisions) != 5:
        raise RuntimeError("Only the five explicitly approved gray-construction exceptions may change old0")
    cases = []

    def add(group, name, truth, rgb, metadata, source_catalog="color9-cards5-v1", construction=""):
        source = artifact(rgb)
        pixel_sha = hashlib.sha256(read_rgb(rgb).tobytes()).hexdigest().upper()
        if source_catalog == CATALOG:
            task, reason = truth, "New synthetic construction truth fixed before scoring."
        elif truth in range(1, 10):
            task, reason = (truth-1) % 3+1, "Explicit color9-to-shape3 catalog mapping; original truth retained."
        elif truth in range(10, 15):
            task, reason = truth, "Existing picture-card label unchanged."
        elif truth == 0 and pixel_sha in whitelist:
            task, reason = whitelist[pixel_sha]["TaskTruth"], whitelist[pixel_sha]["TaskTruthReason"]
        else:
            task, reason = 0, "Original unknown/empty/clipped/noncanonical construction remains rejection truth."
        cases.append(dict(Index=len(cases), Group=group, Name=name, InputKind="RGB",
                          SourceCatalog=source_catalog, SourceTruth=truth, TaskCatalog=CATALOG,
                          TaskTruth=task, Source=source, SourceMetadata=metadata,
                          DecodedRGBSHA256=pixel_sha, SourceFileSHA256=source["SHA256"],
                          MappingReason=reason, OldRejectReason="Color-only refusal" if truth == 0 and task else "",
                          ConstructionDecision=whitelist[pixel_sha] if truth == 0 and task and source_catalog != CATALOG else None,
                          Construction=construction, ExpectedPresent=metadata.get("Present", metadata.get("truth_present"))))

    old_meta = ASSETS / "fixtures.json"
    for case in rotations:
        path = ASSETS / "vectors" / (case["prefix"] + ".rgb.mem")
        if not path.exists():
            path = path.with_suffix("").with_suffix(".png")
        add("old182", case["prefix"], case["truth_item"], path,
            dict(Manifest=artifact(old_meta), Category=case["category"], Recipe=case["recipe"],
                 truth_present=case["truth_present"]))
    for name, group in (("retained-system-v1", "retained203"), ("new-system-v1", "new202")):
        manifest = REPO / "evidence/sc520-contour29" / name / "manifest.json"
        for case in read(manifest)["Cases"]:
            source = check(case["RGB"])
            add(group, case["Name"], case["TruthItem"], Path(source["Path"]),
                dict(Manifest=artifact(manifest), Present=case["Present"], OriginalSource=case["Source"]))
    # T02762 is a separate provenance group; shared RGB is not counted as independent physical evidence.
    shape_manifest = REPO / "evidence/sc520-shape27/fixtures/manifest.json"
    for case in shape_cases:
        add("retained62", case["Name"], case["Item"], Path(case["Path"]),
            dict(Manifest=artifact(shape_manifest), Recipe=case["Recipe"], Present=case["Present"]))
    y, x = np.mgrid[:60, :120]
    palette = {"red": (180, 60, 60), "yellow": (140, 180, 50), "blue": (50, 65, 180),
               "gray": (96, 96, 96), "green": (40, 150, 60)}

    def synthetic(name, grid, truth, construction):
        path = rgb_directory / (name + ".rgb.mem")
        rgb = full_raster(grid)
        with path.open("x", encoding="ascii") as stream:
            stream.write("".join("%02X%02X%02X\n" % tuple(pixel) for pixel in rgb.reshape(-1, 3)))
        add("new-geometry", name, truth, path, dict(Generator=artifact(__file__), Present=True),
            source_catalog=CATALOG, construction=construction)

    for shape, item in (("circle", 1), ("square", 2), ("triangle", 3)):
        for color, rgb in palette.items():
            for radius in (12, 18):
                for angle in (0, 15, 45, 90):
                    a = np.deg2rad(angle)
                    u = (x-60)*np.cos(a)+(y-30)*np.sin(a)
                    v = -(x-60)*np.sin(a)+(y-30)*np.cos(a)
                    mask = u*u+v*v <= radius*radius if shape == "circle" else (
                        (np.abs(u) <= radius) & (np.abs(v) <= radius) if shape == "square" else
                        (v >= -radius) & (v <= radius) & (2*np.abs(u) <= v+radius))
                    grid = np.full((60, 120, 3), 240, dtype=np.uint8)
                    grid[mask] = rgb
                    synthetic(f"{shape}_{color}_r{radius}_a{angle}", grid, item,
                              dict(Geometry=shape, Item=item, RGB=list(rgb), Radius=radius, Angle=angle,
                                   Rule="Complete analytic silhouette; no color qualification. Rotation failures remain misses."))
    for ratio in (60, 80):
        for angle in (0, 15, 45, 90):
            for color, rgb in (("red", palette["red"]), ("gray", palette["gray"])):
                a = np.deg2rad(angle)
                u = (x-60)*np.cos(a)+(y-30)*np.sin(a)
                v = -(x-60)*np.sin(a)+(y-30)*np.cos(a)
                mask = (u/17)**2+(v/(17*ratio/100))**2 <= 1
                grid = np.full((60, 120, 3), 240, dtype=np.uint8)
                grid[mask] = rgb
                synthetic(f"negative_ellipse_{ratio}_{angle}_{color}", grid, 0,
                          dict(Geometry="noncircle ellipse", Ratio=ratio, Angle=angle, RGB=list(rgb),
                               Rule="Fixed rejection truth, never recovered as circle."))
    for name in ("ring", "cross", "circle_appendage"):
        for color, rgb in (("red", palette["red"]), ("gray", palette["gray"])):
            disk = (x-60)**2+(y-32)**2 <= 16**2
            mask = disk & ((x-60)**2+(y-32)**2 >= 9**2) if name == "ring" else (
                ((np.abs(x-60) <= 5) & (np.abs(y-30) <= 18)) |
                ((np.abs(x-60) <= 18) & (np.abs(y-30) <= 5)) if name == "cross" else
                disk | ((np.abs(x-60) <= 2) & (y >= 6) & (y <= 20)))
            grid = np.full((60, 120, 3), 240, dtype=np.uint8)
            grid[mask] = rgb
            synthetic(f"negative_{name}_{color}", grid, 0,
                      dict(Geometry=name, RGB=list(rgb), Rule="Noncanonical full silhouette; fixed unknown."))
    bank_path = ASSETS / "templates.mem"
    for item in range(10, 15):
        for variant in range(256):
            cases.append(dict(Index=len(cases), Group="templates1280", Name=f"template_{item}_{variant}",
                              InputKind="NormalizedTemplate", SourceCatalog="cards5-rotation256-v1",
                              SourceTruth=item, TaskCatalog=CATALOG, TaskTruth=item,
                              Source=artifact(bank_path), TemplateClass=item-10, Variant=variant,
                              MappingReason="Same original normalized card template and class; no RGB scene claim.",
                              OldRejectReason="", Construction=dict(TemplateClass=item-10, Variant=variant),
                              ExpectedPresent=True))
    manifest = dict(At=datetime.now(timezone(timedelta(hours=8))).isoformat(), Task="sc520-shape-card30",
                    Stage="task_truth_frozen_before_candidate_scoring", Candidate="D0300", TaskCatalog=CATALOG,
                    Program=artifact(__file__), Model=artifact(MODEL), ConstructionProofs=proofs,
                    IndependentPriorConstructionWhitelist=artifact(WHITELIST),
                    ApprovedOldUnknownExceptions=decisions,
                    ImportedOracleSources=[artifact(SCRIPTS / name) for name in (
                        "model-contour29.py", "scene-rotation-model.py", "scene-model.py")],
                    OriginalGeometryROM=artifact(REPO / "assets/templates/sc520-contour29/contour29-shapes.mem"),
                    Bank=artifact(bank_path), Cases=cases,
                    GroupCounts={group: sum(case["Group"] == group for case in cases)
                                 for group in sorted({case["Group"] for case in cases})},
                    MappingPolicy="SourceTruth/Catalog/fileSHA immutable. Five approved decoded-RGB construction exceptions only; repeated decoded pixel SHA inherits the same mapping. New synthetic labels set before scores.",
                    ScoresComputed=False, RTLExecuted=False, TDExecuted=False, HardwareValidated=False)
    save(output / "truth-manifest.json", manifest)
    print(json.dumps(dict(TruthManifest=artifact(output / "truth-manifest.json"),
                          GroupCounts=manifest["GroupCounts"], ScoresComputed=False)), flush=True)


def summary(rows, predictions):
    confusion = {str(truth): {str(prediction): 0 for prediction in m.ITEMS} for truth in m.ITEMS}
    for row, item in zip(rows, predictions):
        confusion[str(row["TaskTruth"])][str(item)] += 1
    classes = {}
    for truth in m.ITEMS:
        pairs = [(row, item) for row, item in zip(rows, predictions) if row["TaskTruth"] == truth]
        classes[str(truth)] = dict(Total=len(pairs), Correct=sum(item == truth for _, item in pairs),
                                  Miss=sum(item == 0 for _, item in pairs) if truth else 0,
                                  WrongClass=sum(item not in (0, truth) for _, item in pairs) if truth else 0,
                                  FalseAccept=sum(item != 0 for _, item in pairs) if not truth else 0)
    return dict(Cases=len(rows), Correct=sum(row["TaskTruth"] == item for row, item in zip(rows, predictions)),
                WrongClass=sum(row["TaskTruth"] != 0 and item not in (0, row["TaskTruth"]) for row, item in zip(rows, predictions)),
                Miss=sum(row["TaskTruth"] != 0 and item == 0 for row, item in zip(rows, predictions)),
                UnknownFalseAccept=sum(row["TaskTruth"] == 0 and item != 0 for row, item in zip(rows, predictions)),
                FalseApple=sum(item == 10 and row["TaskTruth"] != 10 for row, item in zip(rows, predictions)),
                PerClass=classes, Confusion=confusion)


def evaluate(inputs, output):
    manifest = read(inputs)
    if manifest["ScoresComputed"] or manifest["Stage"] != "task_truth_frozen_before_candidate_scoring":
        raise RuntimeError("Freeze construction truth before scoring")
    check(manifest["Program"])
    check(manifest["Model"])
    check(manifest["Bank"])
    for row in manifest["ImportedOracleSources"] + manifest["ConstructionProofs"]:
        check(row)
    output.mkdir(parents=True, exist_ok=False)
    bank = m.base.read_bank(manifest["Bank"]["Path"])
    rows, cache = [], {}
    for case in manifest["Cases"]:
        check(case["Source"])
        key = (case["InputKind"], case["Source"]["SHA256"], case.get("TemplateClass"), case.get("Variant"))
        if key not in cache:
            if case["InputKind"] == "NormalizedTemplate":
                mask = np.zeros((32, 32), dtype=bool)
                mask[6:26, 6:26] = bank[case["TemplateClass"], case["Variant"]]
                score = m.scores(mask, bank, glyph=mask)
                data = dict(Score=score, MaskSHA256=hashlib.sha256(mask.astype(np.uint8).tobytes()).hexdigest().upper(),
                            GlyphSHA256=None, SceneSHA256=None, SceneCount=None, GlyphCount=None,
                            OriginalD0261ModelItem=case["SourceTruth"], LegacyIsModel=True)
            else:
                scene = m.scene(read_rgb(case["Source"]["Path"]))
                score = m.scores(scene["mask"], bank, present=scene["present"], clipped=scene["clipped"], glyph=scene["glyph"])
                data = dict(Score=score, MaskSHA256=hashlib.sha256(scene["mask"].astype(np.uint8).tobytes()).hexdigest().upper(),
                            GlyphSHA256=hashlib.sha256(scene["glyph"].astype(np.uint8).tobytes()).hexdigest().upper(),
                            SceneSHA256=hashlib.sha256(scene["scene"].astype(np.uint8).tobytes()).hexdigest().upper(),
                            SceneCount=int(scene["scene"].sum()), GlyphCount=int(scene["glyph"].sum()),
                            OriginalD0261ModelItem=m.legacy_color_model(scene, bank), LegacyIsModel=True)
            cache[key] = data
        result = {**case, **cache[key]}
        result["Predictions"] = {
            f"{model}:m{margin}": m.arbitrate(result["Score"], margin, model)
            for model in ("A", "B-full-negative", "B-axis-negative") for margin in m.MARGINS}
        rows.append(result)
        if len(rows) % 100 == 0:
            print(json.dumps(dict(Scored=len(rows), Total=len(manifest["Cases"]), UniqueInputs=len(cache))), flush=True)
        if len(rows) == len(manifest["Cases"]) or manifest["Cases"][len(rows)]["Group"] != case["Group"]:
            selected = [row for row in rows if row["Group"] == case["Group"]]
            print(json.dumps(dict(GroupComplete=case["Group"], Cases=len(selected),
                                  ModelA=[dict(Margin=margin, Summary=summary(
                                      selected, [row["Predictions"][f"A:m{margin}"] for row in selected]))
                                          for margin in m.MARGINS])), flush=True)
    sweeps = []
    for model in ("A", "B-full-negative", "B-axis-negative"):
        for margin in m.MARGINS:
            key = f"{model}:m{margin}"
            grouped = {}
            for group in manifest["GroupCounts"]:
                selected = [row for row in rows if row["Group"] == group]
                grouped[group] = summary(selected, [row["Predictions"][key] for row in selected])
            sweeps.append(dict(Model=model, CrossFamilyMargin=margin, Groups=grouped,
                               Combined=summary(rows, [row["Predictions"][key] for row in rows])))
    save(output / "scores.json", dict(TruthManifest=artifact(inputs), Rows=rows))
    with (output / "scores.csv").open("x", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(["group", "name", "source_sha", "source_truth", "task_truth", "present", "clipped",
                         "circle", "square", "triangle", "card_best", "card_second", "card_winner",
                         "ellipse_negative", "axis_circle_negative", "original_d0261_model", "model", "margin", "item"])
        for row in rows:
            score = row["Score"]
            for model in ("A", "B-full-negative", "B-axis-negative"):
                for margin in m.MARGINS:
                    writer.writerow([row["Group"], row["Name"], row["Source"]["SHA256"], row["SourceTruth"], row["TaskTruth"],
                                     score["Present"], score["Clipped"], *score["ShapeDistances"],
                                     score["CardBest"], score["CardSecond"], score["CardWinner"],
                                     score["FullEllipseDistance"], score["FullAxisCircleDistance"],
                                     row["OriginalD0261ModelItem"], model, margin, row["Predictions"][f"{model}:m{margin}"]])
    # Cross-check the retained full-geometry constants against all 1024 ROM words.
    words = np.asarray([int(word, 16) for word in Path(manifest["OriginalGeometryROM"]["Path"]).read_text().split()], dtype=np.uint16).reshape(32, 32)
    expected = np.zeros((32, 32), dtype=np.uint16)
    for index, bits in enumerate(m.BASIC):
        expected[6:26, 6:26] |= bits.astype(np.uint16) << index
    expected[6:26, 6:26] |= m.CIRCLE_ALIASES[1].astype(np.uint16) << 3
    for index, bits in enumerate(m.ELLIPSES):
        expected[6:26, 6:26] |= bits.astype(np.uint16) << (4+index)
    if not np.array_equal(words, expected):
        raise RuntimeError("Full-only negative geometry differs from frozen 16-bit ROM")
    for case in manifest["Cases"]:
        check(case["Source"])
    report = dict(At=datetime.now(timezone(timedelta(hours=8))).isoformat(), Candidate="D0300", TaskCatalog=CATALOG,
                  Program=artifact(__file__), Model=artifact(MODEL), TruthManifest=artifact(inputs),
                  Scores=artifact(output / "scores.json"), ScoreCSV=artifact(output / "scores.csv"),
                  FixedThresholds=dict(ShapeMaximum=20, CardMaximum=40, CardClassMargin=24,
                                       CrossFamilyMargins=list(m.MARGINS)),
                  ModelCosts={
                      "A": dict(NormalizedMasks=1, BasicShapeCounters=3, AdditionalERAM=0, BodyOrRecovery=False),
                      "B-full-negative": dict(NormalizedMasks=1, FullGeometryCounters=16, GeometryROM="same frozen16bit/1024word ROM, one ERAM", BodyOrRecovery=False),
                      "B-axis-negative": dict(NormalizedMasks=2, FullGeometryCounters=16, AxisNegativeCounters=2,
                                              GeometryROM="same16bit ROM, one ERAM; second full-glyph normalization only", BodyOrRecovery=False)},
                  GroupCounts=manifest["GroupCounts"], UniqueScoredInputs=len(cache), GeometryROMWordsCompared=1024,
                  Sweep=sweeps, SelectedModel=None, MainAccepted=False, SourceInputsUnchanged=True,
                  RTLExecuted=False, TDExecuted=False, HardwareValidated=False,
                  Limits="Offline fixed-input proposal only. Combined totals include overlapping provenance groups and template training examples; they are not independent field trials. OriginalD0261ModelItem is array-model evidence, not a new RTL execution. No threshold selected from outputs without main review.")
    save(output / "report.json", report)
    print(json.dumps(dict(Report=artifact(output / "report.json"), Cases=len(rows), UniqueInputs=len(cache),
                          Summary=[dict(Model=row["Model"], Margin=row["CrossFamilyMargin"],
                                        Wrong=row["Combined"]["WrongClass"], Miss=row["Combined"]["Miss"],
                                        UnknownFalseAccept=row["Combined"]["UnknownFalseAccept"],
                                        FalseApple=row["Combined"]["FalseApple"]) for row in sweeps])), flush=True)


def main():
    if sys.flags.optimize:
        raise RuntimeError("Do not disable model audit assertions with -O")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--phase", choices=("freeze", "evaluate"), required=True)
    parser.add_argument("--inputs", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to(EVIDENCE):
        raise RuntimeError("Use a new task-local evidence directory")
    if args.phase == "freeze":
        freeze(output)
    else:
        if not args.inputs:
            raise RuntimeError("Frozen truth manifest required")
        evaluate(args.inputs.resolve(strict=True), output)


if __name__ == "__main__":
    main()
