"""Direct T030 snapshots and ModelSim tests; no TD or text-exec adapter chain."""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import argparse
import hashlib
import importlib.util
import json
import subprocess
import time
import uuid

REPO = Path(__file__).resolve().parents[3]
RTL = REPO / "fpga/rtl/sc520-shape-card30"
SIM = Path("D:/modeltech64_10.7/win64/vsim.exe")
EVIDENCE = REPO / "evidence/sc520-shape-card30"
APPROVAL = Path("E:/juan/FPGA/learning/sc520-shape-card30/rtl-implementation-approved.json")


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def artifact(path):
    return dict(Path=str(path), SHA256=sha(path), Bytes=Path(path).stat().st_size)


def save(path, value):
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write("\n")


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    if not __debug__:
        raise RuntimeError("Do not disable source checks")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--test", choices=("scene", "scores", "pairing", "system", "stream", "render", "matcher", "filter", "quiz"), required=True)
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--negative", action="store_true")
    args = parser.parse_args()
    tool = artifact(SIM)
    accepted = json.loads(APPROVAL.read_text(encoding="utf-8-sig"))
    assert accepted["Decision"] == "D090" and accepted["SynthesisAllowed"] is False
    for key in ("Model", "ModelReport", "IndependentFinalReview", "PacketContract"):
        assert sha(accepted[key]["Path"]) == accepted[key]["SHA256"]
    timestamp = datetime.now(timezone(timedelta(hours=8)))
    run = EVIDENCE / "runs" / (args.test + ("-negative-" if args.negative else "-normal-") +
                              timestamp.strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:6])
    inputs = run / "inputs"
    inputs.mkdir(parents=True, exist_ok=False)
    rows = []

    def copy(path, name=None):
        path = Path(path)
        target = inputs / (name or path.name)
        target.parent.mkdir(parents=True, exist_ok=True)
        assert not target.exists(), target
        target.write_bytes(path.read_bytes())
        rows.append({**artifact(path), "Snapshot": str(target), "SnapshotSHA256": sha(target)})
        return target
    source_names = {
        "scene": ("pixel30_scene_preprocess.v",),
        "scores": ("pixel30_shape_scores.v",),
        "matcher": ("pixel30_rotation_matcher.v",),
        "filter": ("items30_result_filter.v",),
        "quiz": ("items30_question_bank.v", "items30_quiz_control.v"),
        "pairing": ("pixel30_arbitrate.v", "items30_result_filter.v"),
        "render": ("items30_content.v", "pixel30_panel.v", "pixel30_compositor.v"),
    }
    sources = [RTL / name for name in source_names.get(args.test, ())]
    assert sources, "System/stream are owned by simulate-shape-card30-chain.py"
    base = REPO / "fpga/rtl/sc520-card-recognition"
    dependencies = [base / "pixel14/pixel14_rotation_matcher.v"] if args.test == "matcher" else []
    if args.test == "render":
        dependencies = [base / "items14/items14_content.v", base / "items14/items14_font_rom.v",
                        base / "display17/sc520_logo_pipeline.v"]
        dependencies += [REPO / "fpga/rtl/sc520-color-integration" / name for name in
                         ("pixel26_processing_display.v", "pixel26_color_classify.v", "pixel26_saturation.v")]
    for path in dependencies:
        if path.exists():
            sources.append(path)
    for path in sources:
        copy(path)
    for path in RTL.glob("*.vh"):
        copy(path)
    tb = copy(REPO / f"fpga/sim/sc520-shape-card30/tb_shape_card30_{args.test}.sv")
    copy(Path(__file__).resolve())
    copy(APPROVAL)
    geometry = copy(REPO / "assets/templates/sc520-contour29/contour29-shapes.mem")
    if args.test == "matcher":
        copy(REPO / "assets/templates/sc520-card-recognition/rotation-v1/templates.mem")
        copy(Path("E:/juan/FPGA/learning/sc520-shape-card30/resume-20261022-approved.json"))
    if args.test == "render":
        for name in ("anlogic_logo_index.mem", "anlogic_logo_palette.mem"):
            copy(REPO / "assets/templates/sc520-card-recognition/display17" / name)
        copy(REPO / "assets/templates/sc520-card-recognition/display17/font-extension.json")
        copy(REPO / "assets/templates/sc520-card-recognition/display17/anlogic_logo_rgba.png")
        copy(REPO / "fpga/sim/sc520-card-recognition/tb_pixel14_observation_display.sv", "tiny-reference.sv")
        renderer = copy(Path(__file__).with_name("generate-shape-card30-render.py"))
        load("shape30_literal_renderer", renderer).generate(inputs)
    if args.test in ("scores", "scene"):
        c = load("shape30_test_frozen_c", Path(__file__).with_name("model-shape-card30-c.py"))
        tools = load("shape30_test_frozen_tools", Path(__file__).with_name("evaluate-shape-card30.py"))
        for path in (Path(__file__).with_name("model-shape-card30-c.py"),
                     Path(__file__).with_name("model-shape-card30.py"),
                     Path(__file__).with_name("evaluate-shape-card30.py"),
                     Path(__file__).with_name("model-contour29.py"),
                     Path(__file__).with_name("scene-rotation-model.py"), Path(__file__).with_name("scene-model.py")):
            copy(path)
        final_report = json.loads((EVIDENCE / "model-c-v1/report.json").read_text())
        assert sha(final_report["Scores"]["Path"]) == final_report["Scores"]["SHA256"]
        copy(EVIDENCE / "model-c-v1/report.json", "model-c-report.json")
        copy(final_report["Scores"]["Path"], "model-c-scores.json")
        copy(REPO / "assets/templates/sc520-card-recognition/rotation-v1/templates.mem")
        corpus = json.loads(Path(final_report["Scores"]["Path"]).read_text())["Rows"]
        if args.test == "scene":
            corpus = [row for row in corpus if row["InputKind"] == "RGB"]
        assert len(corpus) == (973 if args.test == "scene" else 2253), "Frozen full corpus cardinality"
        if not args.all:
            names = ("block_1_plain", "block_2_plain", "block_3_plain", "card_10", "gray", "sparse_red",
                     "h_circle_gray_r14_a0", "h_square_green_r17_a0", "h_triangle_cyan_r14_a0",
                     "r143_card_10_gain65_before")
            corpus = [next(row for row in corpus if row["Name"] == name) for name in names]
        bank = c.ab.base.read_bank(REPO / "assets/templates/sc520-card-recognition/rotation-v1/templates.mem")
        case_lines = []
        copied_rgb = set()
        for number, row in enumerate(corpus):
            prefix = f"v{number:04d}"
            if row["InputKind"] == "NormalizedTemplate":
                import numpy as np
                full = np.zeros((32, 32), dtype=bool)
                full[6:26, 6:26] = bank[row["TemplateClass"], row["Variant"]]
                axis = c.ab.normalize_axes(full)
                y_min, y_max, width, height, available = 0, 0, 0, 0, 0
            else:
                assert sha(row["Source"]["Path"]) == row["Source"]["SHA256"]
                if row["Source"]["Path"] not in copied_rgb:
                    copy(row["Source"]["Path"], "rgb-sources/" + str(len(copied_rgb)) + Path(row["Source"]["Path"]).suffix)
                    copied_rgb.add(row["Source"]["Path"])
                rgb = tools.read_rgb(row["Source"]["Path"])
                scene = c.ab.scene(rgb)
                full = scene["mask"]
                axis = c.ab.normalize_axes(scene["glyph"])
                desc = c.describe(scene)
                y_min = desc["GlyphYMinimum"] or 0
                y_max = desc["GlyphYMaximum"] or 0
                width, height = desc["Width"] or 0, desc["Height"] or 0
                available = int(desc["GeometryAvailable"])
                (inputs / (prefix + ".rgb.mem")).write_text(
                    "".join("%02X%02X%02X\n" % tuple(pixel) for pixel in rgb.reshape(-1, 3)), encoding="ascii")
            for suffix, bits in (("full", full), ("axis", axis)):
                (inputs / (prefix + "." + suffix + ".mem")).write_text(
                    "".join(str(int(value))+"\n" for value in bits.flat), encoding="ascii")
            import numpy as np
            bank_bits = np.concatenate((c.ab.BASIC, c.ab.ELLIPSES), axis=0)
            individual = np.count_nonzero(bank_bits != full[6:26, 6:26], axis=(1, 2)).tolist()
            individual += np.count_nonzero(c.ab.CIRCLE_ALIASES != axis[6:26, 6:26], axis=(1, 2)).tolist()
            (inputs / (prefix + ".distances.mem")).write_text(
                "".join("%03X\n" % value for value in individual), encoding="ascii")
            score = row["Score"]
            line = [prefix, *score["ShapeDistances"], score["FullEllipseDistance"],
                    score["FullAxisCircleDistance"], int(score["Present"]), int(score["Clipped"]),
                    y_min, y_max, width, height, available, row["CDecision"]["Item"]]
            case_lines.append(" ".join(map(str, line))+"\n")
            if args.test == "scene":
                sampled = scene["rgb"]
                border = np.zeros(scene["scene"].shape, dtype=bool)
                border[[0, -1], :] = True
                border[:, [0, -1]] = True
                signed = sampled.astype(np.int16)
                center = np.sort(sampled[border] // 16, axis=0)[(int(border.sum()) - 1) // 2].astype(np.int16) * 16 + 8
                similar = (np.abs(signed-center).max(axis=-1) <= 48) & (
                    (scene["chroma"] >= scene["low"]) & (scene["chroma"] <= scene["high"])).all(axis=-1)
                uncertain = int((border & similar).sum()) * 4 < int(border.sum()) * 3
                counts = [int(scene["scene"].sum()), int(scene["glyph"].sum()),
                          int((scene["scene"] & ~c.ab.base.threshold(sampled)).sum())]
                flags = (int(uncertain) << 3) | (int(scene["paper_route"]) << 2) | (int(scene["clipped"]) << 1) | int(scene["present"])
                (inputs / (prefix + ".scene.mem")).write_text(
                    "".join("%04X\n" % value for value in (*counts, flags)), encoding="ascii")
        (inputs / "cases.txt").write_text("".join(case_lines), encoding="ascii")
    # All generated vector bytes are frozen before simulation.
    generated = [artifact(path) for path in sorted(inputs.rglob("*")) if path.is_file()]
    (run / "modelsim.ini").write_bytes((SIM.parent.parent / "modelsim.ini").read_bytes())
    q = lambda path: "{" + str(path).replace("\\", "/") + "}"
    top = "tb_shape_card30_" + args.test
    script = "\n".join([
        "onerror {quit -force -code 2}", "onbreak {resume}",
        f"file copy {q(geometry)} contour29-shapes.mem",
        *([f"file copy {q(inputs / 'templates.mem')} templates.mem"] if args.test == "matcher" else []),
        *([f"file copy {q(inputs / name)} {name}" for name in ("anlogic_logo_index.mem", "anlogic_logo_palette.mem")]
          if args.test == "render" else []),
        "vlib work", "vmap work work",
        "set sources [list " + " ".join(q(inputs / path.name) for path in sources) + "]",
        "vlog +incdir+" + inputs.as_posix() + " {*}$sources",
        f"vlog -sv +incdir+{inputs.as_posix()} {q(tb)}",
        f"vsim -voptargs=+acc -wlf wave.wlf work.{top} +ASSET_ROOT={inputs.as_posix()} +INJECT_FAULT={int(args.negative)}",
        "onfinish stop", "run -all",
        f"set errors [examine -radix decimal /{top}/errors]",
        f"set checks [examine -radix decimal /{top}/checks]",
        f"set scenarios [examine -radix decimal /{top}/scenarios]",
        f"set done [examine -radix unsigned /{top}/test_done]",
        "set fd [open summary.json w]",
        'puts $fd [format {{"errors":%s,"checks":%s,"scenarios":%s,"done":%s}} $errors $checks $scenarios $done]',
        "close $fd", "if {!$done} {quit -force -code 2}", "if {$errors!=0} {quit -force -code 1}",
        "quit -force -code 0", "",
    ])
    (run / "run.do").write_text(script, encoding="utf-8")
    command = [str(SIM), "-modelsimini", str(run / "modelsim.ini"), "-c", "-l", "transcript.log",
               "-do", "source " + q(run / "run.do")]
    report = dict(Task="sc520-shape-card30", Candidate="D0300", Owner="Codex /root/shape30_detector_finish", Tool=tool,
                  Test=args.test, All=args.all, Negative=args.negative, Inputs=rows, GeneratedInputs=generated,
                  Command=command, WorkingDirectory=str(run), StartedAt=timestamp.isoformat(),
                  SynthesisAllowed=False, HardwareValidated=False)
    save(run / "run-start.json", report)
    start = time.monotonic()
    with (run / "stdout.log").open("xb") as stdout, (run / "stderr.log").open("xb") as stderr:
        process = subprocess.Popen(command, cwd=run, stdout=stdout, stderr=stderr, creationflags=subprocess.CREATE_NO_WINDOW)
        report["PID"] = process.pid
        print(json.dumps(dict(Run=str(run), PID=process.pid)), flush=True)
        try:
            code = process.wait(timeout=1800)
        except subprocess.TimeoutExpired:
            subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], capture_output=True)
            code = process.wait()
            report["TimedOut"] = True
    summary = json.loads((run / "summary.json").read_text()) if (run / "summary.json").exists() else None
    unchanged = all(sha(row["Path"]) == row["SHA256"] and sha(row["Snapshot"]) == row["SnapshotSHA256"] for row in rows)
    unchanged = unchanged and all(sha(row["Path"]) == row["SHA256"] for row in generated)
    expected_scenarios = len(corpus) if args.test in ("scores", "scene") else {
        "matcher": 27, "filter": 300, "quiz": 16, "render": 5}.get(args.test)
    expected_checks = {
        "scores": 19 * expected_scenarios if args.test == "scores" else 0,
        "scene": 4103 * expected_scenarios if args.test == "scene" else 0,
        "matcher": 12597049 + int(args.negative), "filter": 1501 + int(args.negative),
        "quiz": 114 + int(args.negative), "render": 18560290 + int(args.negative),
    }.get(args.test)
    tool_unchanged = sha(SIM) == tool["SHA256"] and SIM.stat().st_size == tool["Bytes"]
    qualified = bool(summary and summary["done"] == 1 and summary["scenarios"] > 0 and summary["checks"] > 0
                     and (expected_scenarios is None or summary["scenarios"] == expected_scenarios)
                     and (expected_checks is None or summary["checks"] == expected_checks)
                     and unchanged and tool_unchanged and not report.get("TimedOut") and
                     (code == 1 and summary["errors"] == 1 if args.negative else code == 0 and summary["errors"] == 0))
    if args.test == "render" and summary:
        import numpy as np
        from PIL import Image
        image_checks = []
        for case in range(4):
            actual = np.fromiter((int(v, 16) for v in (run / f"actual-{case}.mem").read_text().split()), dtype=np.uint32)
            expected = np.fromiter((int(v, 16) for v in (inputs / f"golden-{case}.mem").read_text().split()), dtype=np.uint32)
            assert actual.size == expected.size == 921600
            mismatch = int(np.count_nonzero(actual != expected))
            image_checks.append(dict(Case=case, Pixels=int(actual.size), Mismatches=mismatch))
            rgb = np.stack(((actual >> 16) & 255, (actual >> 8) & 255, actual & 255), axis=1).astype(np.uint8).reshape(720, 1280, 3)
            Image.fromarray(rgb).save(run / f"actual-{case}.png")
        report["ImageChecks"] = image_checks
        qualified = qualified and all(row["Mismatches"] == 0 for row in image_checks)
    report.update(NativeExitCode=code, Summary=summary, ExpectedScenarios=expected_scenarios, ExpectedChecks=expected_checks,
                  Qualified=qualified, InputsUnchanged=unchanged, ToolUnchanged=tool_unchanged,
                  ElapsedSeconds=time.monotonic()-start)
    report["Outputs"] = [artifact(path) for path in sorted(run.iterdir()) if path.is_file() and path.suffix != ".wlf"]
    save(run / "run-manifest.json", report)
    print(json.dumps(dict(Run=str(run), Qualified=qualified, NativeExitCode=code, Summary=summary)), flush=True)
    return 0 if qualified else 1


if __name__ == "__main__":
    raise SystemExit(main())
