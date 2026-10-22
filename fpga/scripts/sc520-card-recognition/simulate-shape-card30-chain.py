"""Snapshot and run the actual RGB96/192-bit capture-to-business chain."""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import importlib.util
import json
import re
import shutil
import subprocess
import uuid
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
VSIM = Path("D:/modeltech64_10.7/win64/vsim.exe")
RTL = ROOT / "fpga/rtl/sc520-shape-card30"
SIM = ROOT / "fpga/sim/sc520-shape-card30"
SCRIPTS = ROOT / "fpga/scripts/sc520-card-recognition"
MATRIX_SELECTION = [
    ("retained62", name) for name in
    ("block_1_plain", "block_2_plain", "block_3_plain", "card_10", "card_11",
     "card_12", "card_13", "card_14", "empty_white", "clipped")
] + [("old182", "r135_legacy_686_unknown_ring_white"), ("old182", "r143_card_10_gain65_before")]
MATRIX_SELECTION += [("retained62", "block_1_plain")]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def artifact(path):
    return {"Path": path.as_posix(), "SHA256": hashlib.sha256(path.read_bytes()).hexdigest().upper(),
            "Bytes": path.stat().st_size}


def matrix_vectors(run, freeze):
    import numpy as np

    c = load("chain_frozen_c", SCRIPTS / "model-shape-card30-c.py")
    tools = load("chain_rgb_reader", SCRIPTS / "evaluate-shape-card30.py")
    approval = Path("E:/juan/FPGA/learning/sc520-shape-card30/rtl-implementation-approved.json")
    accepted = json.loads(approval.read_text(encoding="utf-8-sig"))
    if accepted["Decision"] != "D090" or accepted["SynthesisAllowed"]:
        raise RuntimeError("Unexpected software approval")
    for key in ("Model", "ModelReport", "PacketContract"):
        if artifact(Path(accepted[key]["Path"]))["SHA256"] != accepted[key]["SHA256"]:
            raise RuntimeError("Frozen approval changed: " + key)
    model_report_path = ROOT / "evidence/sc520-shape-card30/model-c-v1/report.json"
    model_report = json.loads(model_report_path.read_text(encoding="utf-8"))
    scores_path = Path(model_report["Scores"]["Path"])
    if artifact(scores_path)["SHA256"] != model_report["Scores"]["SHA256"]:
        raise RuntimeError("Frozen C score corpus changed")
    rows = json.loads(scores_path.read_text(encoding="utf-8"))["Rows"]
    freeze(approval, "software-approval.json")
    freeze(Path(accepted["PacketContract"]["Path"]), "packet-contract.md")
    freeze(model_report_path, "model-c-report.json")
    freeze(scores_path, "model-c-scores.json")
    for name in ("model-shape-card30-c.py", "model-shape-card30.py", "evaluate-shape-card30.py",
                 "model-contour29.py", "scene-rotation-model.py", "scene-model.py"):
        freeze(SCRIPTS / name, "model/" + name)
    bank = c.ab.base.read_bank(ROOT / "assets/templates/sc520-card-recognition/rotation-v1/templates.mem")
    packets, descriptors, distances, selected = [], [], [], []
    for index, (group, name) in enumerate(MATRIX_SELECTION):
        row = next(row for row in rows if row["Group"] == group and row["Name"] == name)
        source = Path(row["Source"]["Path"])
        if artifact(source)["SHA256"] != row["Source"]["SHA256"]:
            raise RuntimeError("Frozen matrix RGB changed: " + name)
        freeze(source, f"rgb-sources/m{index:02d}" + source.suffix)
        rgb = tools.read_rgb(source)
        if hashlib.sha256(rgb.tobytes()).hexdigest().upper() != row["DecodedRGBSHA256"]:
            raise RuntimeError("Decoded matrix RGB mismatch: " + name)
        scene = c.ab.scene(rgb)
        score = c.ab.scores(scene["mask"], bank, present=scene["present"],
                            clipped=scene["clipped"], glyph=scene["glyph"])
        desc = c.describe(scene)
        decision = c.decide(score, desc)
        if score != row["Score"] or decision != row["CDecision"]:
            raise RuntimeError("Frozen C decision mismatch: " + name)
        if int(scene["scene"].sum()) != row["SceneCount"] or int(scene["glyph"].sum()) != row["GlyphCount"]:
            raise RuntimeError("Frozen scene counts mismatch: " + name)
        sampled = scene["rgb"]
        border = np.zeros(scene["scene"].shape, dtype=bool)
        border[[0, -1], :] = True
        border[:, [0, -1]] = True
        center = np.sort(sampled[border] // 16, axis=0)[(int(border.sum()) - 1) // 2].astype(np.int16) * 16 + 8
        similar = (np.abs(sampled.astype(np.int16) - center).max(axis=-1) <= 48) & (
            (scene["chroma"] >= scene["low"]) & (scene["chroma"] <= scene["high"])).all(axis=-1)
        uncertain = int((border & similar).sum()) * 4 < int(border.sum()) * 3
        if uncertain:
            raise RuntimeError("Selected fixed-C case has unmodeled uncertain border")
        raw = decision["Item"]
        if (index < 8 or index == 12) and raw != row["TaskTruth"]:
            raise RuntimeError("Positive matrix fixture does not cover its original class")
        if 8 <= index < 12 and raw != 0:
            raise RuntimeError("Negative matrix selection no longer rejects")
        if index == 11 and (row["TaskTruth"] != 10 or not decision["GeometryYRejected"]):
            raise RuntimeError("Keep the original Y-rejected apple miss")
        (run / f"m{index}.rgb.mem").write_text(
            "".join("%02X%02X%02X\n" % tuple(pixel) for pixel in rgb.reshape(-1, 3)), encoding="ascii")
        # Reason bits retain the approved distinctions between ambiguity and distance refusal.
        geometry_conflict = (decision["DistanceOnlyShapeBits"] != 0 and
                             (decision["GeometryCandidate"] == 0 or decision["NegativeEvidenceRejectsGeometry"]))
        family_conflict = bool(decision["GeometryCandidate"] or decision["CardQualifiedAfterAppleLimit"])
        reason = 8 if score["Clipped"] else (
            (32 | (16 if geometry_conflict or family_conflict else 0)) if score["Present"] and not raw else 0)
        base = 0
        fields = [(32, 1, 0), (33, 1, 1), (34, 1, int(score["Present"])), (36, 1, 0),
                  (37, 1, int(score["Clipped"])), (38, 1, 0), (39, 1, int(scene["paper_route"])),
                  (44, 4, decision["GeometryCandidate"]), (48, 4, score["CardWinner"]),
                  (52, 3, decision["PositiveShapeBits"]),
                  (55, 1, int(decision["CardQualifiedAfterAppleLimit"])),
                  (64, 16, row["SceneCount"]), (80, 16, row["GlyphCount"]), (96, 4, raw),
                  (100, 3, 7), (103, 1, 1), (104, 8, reason),
                  (112, 11, score["ShapeDistances"][0]), (123, 11, score["ShapeDistances"][1]),
                  (134, 11, score["ShapeDistances"][2]), (145, 11, score["CardBest"]),
                  (156, 11, score["CardSecond"]), (167, 11, score["Foreground"]),
                  (178, 4, 1), (182, 4, 1), (186, 1, 1)]
        for offset, width, value in fields:
            if not 0 <= value < (1 << width):
                raise RuntimeError("Expected packet field overflow")
            base |= value << offset
        descriptor = (int(desc["GeometryAvailable"]) | ((desc["GlyphYMinimum"] or 0) << 1) |
                      ((desc["GlyphYMaximum"] or 0) << 9) | ((desc["Width"] or 0) << 17) |
                      ((desc["Height"] or 0) << 29))
        distance = score["FullEllipseDistance"] | (score["FullAxisCircleDistance"] << 11)
        for repeat in range(1, 4):
            tag = len(packets) + 1
            count = repeat if raw else 0
            confirmed = repeat == 3 and raw != 0
            packets.append(base | tag | (int(confirmed) << 35) | ((raw if confirmed else 0) << 40) | (count << 56))
            descriptors.append(descriptor)
            distances.append(distance)
        selected.append({"Case": index, "FrozenRow": row, "RecomputedDescriptor": desc,
                         "BorderUncertain": uncertain, "ExpectedReason": reason,
                         "ExpectedPacketBaseHex": f"{base:048X}", "Frames": 3})
    (run / "matrix.expected.mem").write_text("".join(f"{packet:048X}\n" for packet in packets), encoding="ascii")
    (run / "matrix.descriptor.mem").write_text("".join(f"{value:012X}\n" for value in descriptors), encoding="ascii")
    (run / "matrix.distance.mem").write_text("".join(f"{value:06X}\n" for value in distances), encoding="ascii")
    (run / "matrix-selection.json").write_text(json.dumps(selected, indent=2) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--test", choices=["system", "stream"], required=True)
    parser.add_argument("--negative", action="store_true")
    parser.add_argument("--full-fps", action="store_true")
    parser.add_argument("--matrix", action="store_true")
    parser.add_argument("--render-enable", action="store_true")
    args = parser.parse_args()
    if (args.full_fps or args.matrix or args.render_enable) and args.test != "stream":
        parser.error("--full-fps, --matrix and --render-enable apply only to stream")
    expected_checks = (32 if args.test == "system" else
                       (280 if args.full_fps else 318) if args.matrix else
                       (26 if args.full_fps else 29)) + int(args.negative) + 3 * int(args.render_enable)
    expected_scenarios = (9 if args.test == "system" else (16 if args.matrix else 3)) + int(args.render_enable)
    now = dt.datetime.now(dt.timezone(dt.timedelta(hours=8)))
    run = ROOT / "evidence/sc520-shape-card30/chain-runs" / (
        f"{args.test}-{'negative' if args.negative else 'normal'}-"
        f"{now:%Y%m%d-%H%M%S}-{uuid.uuid4().hex[:6]}")
    run.mkdir(parents=True)
    program = artifact(Path(__file__))
    tool = artifact(VSIM)
    sources = [
        ROOT / "fpga/rtl/sc520-card-recognition/pixel14/capture_rgb96.v",
        ROOT / "fpga/rtl/sc520-card-recognition/pixel14/pixel14_result_cdc.v",
        RTL / "pixel30_scene_preprocess.v", RTL / "pixel30_shape_scores.v",
        RTL / "pixel30_rotation_matcher.v", RTL / "pixel30_arbitrate.v",
        RTL / "items30_result_filter.v", RTL / "items30_result_join.v",
        RTL / "items30_question_bank.v", RTL / "items30_quiz_control.v",
        RTL / "items30_system.v", RTL / "pixel30_pipeline.v",
        SIM / f"tb_shape_card30_{args.test}.sv",
    ]
    if args.render_enable:
        sources[-1:-1] = [
            RTL / "items30_content.v", RTL / "pixel30_panel.v", RTL / "pixel30_compositor.v",
            ROOT / "fpga/rtl/sc520-card-recognition/items14/items14_content.v",
            ROOT / "fpga/rtl/sc520-card-recognition/items14/items14_font_rom.v",
            ROOT / "fpga/rtl/sc520-card-recognition/display17/sc520_logo_pipeline.v",
            *[ROOT / "fpga/rtl/sc520-color-integration" / name for name in
              ("pixel26_processing_display.v", "pixel26_color_classify.v", "pixel26_saturation.v")],
        ]
    (run / "sources").mkdir()
    frozen = []
    def freeze(source, name):
        target = run / name
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.exists():
            raise RuntimeError("Do not overwrite snapshots")
        shutil.copyfile(source, target)
        frozen.append({"Source": artifact(source), "Snapshot": artifact(target)})

    for source in sources:
        target = run / "sources" / source.name
        shutil.copyfile(source, target)
        frozen.append({"Source": artifact(source), "Snapshot": artifact(target)})
    header = RTL / "recognition30_packet.vh"
    shutil.copyfile(header, run / "sources" / header.name)
    frozen.append({"Source": artifact(header), "Snapshot": artifact(run / "sources" / header.name)})
    assets = {
        "templates.mem": ROOT / "assets/templates/sc520-card-recognition/rotation-v1/templates.mem",
        "contour29-shapes.mem": ROOT / "assets/templates/sc520-contour29/contour29-shapes.mem",
        "c062.rgb.mem": ROOT / "evidence/sc520-contour29/fixtures-v1/c062.rgb.mem",
    }
    for name, source in assets.items():
        shutil.copyfile(source, run / name)
        frozen.append({"Source": artifact(source), "Snapshot": artifact(run / name)})
    if args.matrix:
        matrix_vectors(run, freeze)
    if args.render_enable:
        for name in ("anlogic_logo_index.mem", "anlogic_logo_palette.mem"):
            freeze(ROOT / "assets/templates/sc520-card-recognition/display17" / name, name)
    top = f"tb_shape_card30_{args.test}"
    shutil.copyfile(Path(__file__), run / "sources" / Path(__file__).name)
    frozen.append({"Source": program, "Snapshot": artifact(run / "sources" / Path(__file__).name)})
    shutil.copyfile(VSIM.parent.parent / "modelsim.ini", run / "modelsim.ini")
    frozen.append({"Source": artifact(VSIM.parent.parent / "modelsim.ini"),
                   "Snapshot": artifact(run / "modelsim.ini")})
    script = [
        "onerror {quit -force -code 2}", "onbreak {resume}", "vlib work",
        "vlog +incdir+sources " + " ".join("{sources/" + p.name + "}" for p in sources[:-1]),
        "vlog -sv " + ("+define+CHAIN_RENDER " if args.render_enable else "")
        + "+incdir+sources {sources/" + sources[-1].name + "}",
        f"vsim -voptargs=+acc work.{top}"
        + (" +NEGATIVE" if args.negative else "")
        + (" +FULL_FPS" if args.full_fps else ""),
        "onfinish stop", "run -all",
        f"set errors [examine -radix decimal /{top}/errors]",
        f"set checks [examine -radix decimal /{top}/checks]",
        f"set scenarios [examine -radix decimal /{top}/scenarios]",
        f"set done [examine -radix unsigned /{top}/test_done]",
        "if {$done!=1 || $checks!=" + str(expected_checks) + " || $scenarios!="
        + str(expected_scenarios) + "} {quit -force -code 2}",
        "if {$errors!=0} {quit -force -code 1}", "quit -force -code 0",
    ]
    if args.matrix:
        script[5] += " +MATRIX"
    (run / "run.do").write_text("\n".join(script) + "\n", encoding="ascii")
    command = [str(VSIM), "-modelsimini", str(run / "modelsim.ini"),
               "-c", "-l", "transcript.log", "-do", "do run.do"]
    generated = [artifact(path) for path in sorted(run.rglob("*")) if path.is_file()]
    start = dt.datetime.now(dt.timezone.utc)
    with (run / "stdout.log").open("w", encoding="utf-8") as stdout, (
        run / "stderr.log").open("w", encoding="utf-8") as stderr:
        result = subprocess.run(command, cwd=run, stdout=stdout, stderr=stderr, timeout=2400,
                                creationflags=subprocess.CREATE_NO_WINDOW)
    log = (run / "transcript.log").read_text(encoding="utf-8", errors="replace")
    matches = re.findall(r"RESULT chain_(system|stream) errors=(\d+) checks=(\d+) scenarios=(\d+) done=(\d+)", log)
    summary = (dict(zip(["Test", "Errors", "Checks", "Scenarios", "Done"], matches[-1]))
               if matches else None)
    unchanged = all(artifact(Path(f["Source"]["Path"]))["SHA256"] == f["Source"]["SHA256"]
                    for f in frozen)
    unchanged = unchanged and all(artifact(Path(f["Path"]))["SHA256"] == f["SHA256"] for f in generated)
    tool_unchanged = artifact(VSIM) == tool
    exact_summary = (len(matches) == 1 and summary["Test"] == args.test
                     and int(summary["Checks"]) == expected_checks
                     and int(summary["Scenarios"]) == expected_scenarios
                     and summary["Done"] == "1" and "WATCHDOG" not in log)
    no_tool_diagnostics = not re.search(r"\*\* (Warning|Error|Fatal):", log)
    qualified = (result.returncode == (1 if args.negative else 0) and summary is not None and summary["Done"] == "1"
                 and exact_summary and unchanged and tool_unchanged and no_tool_diagnostics
                 and int(summary["Errors"]) == int(args.negative))
    report = {
        "Task": "sc520-shape-card30", "Test": args.test,
        "NegativeChecker": args.negative, "FullFPS": args.full_fps, "Matrix": args.matrix,
        "RenderEnabled": args.render_enable, "NoToolDiagnostics": no_tool_diagnostics,
        "StartedAtUtc": start.isoformat(),
        "FinishedAtUtc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "Command": command, "Cwd": run.as_posix(), "ExitCode": result.returncode,
        "Summary": summary, "InputsUnchanged": unchanged, "Qualified": qualified,
        "ExpectedChecks": expected_checks, "ExpectedScenarios": expected_scenarios,
        "ExactSummary": exact_summary, "Tool": tool, "ToolUnchanged": tool_unchanged,
        "SourceFreeze": frozen, "GeneratedFreeze": generated, "Program": program,
        "HardwareRun": False, "SynthesisRun": False,
    }
    (run / "report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"Report": (run / "report.json").as_posix(), "Summary": summary,
                      "Qualified": qualified, "InputsUnchanged": unchanged}, indent=2))
    return 0 if qualified else 1


if __name__ == "__main__":
    raise SystemExit(main())
