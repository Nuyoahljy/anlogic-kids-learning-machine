"""Create-only final software/source evidence, never invoke synthesis or hardware."""
from datetime import datetime, timezone, timedelta
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[3]
EVIDENCE = ROOT / "evidence/sc520-shape-card30"


def artifact(path):
    path = Path(path)
    return dict(Path=str(path), SHA256=hashlib.sha256(path.read_bytes()).hexdigest().upper(),
                Bytes=path.stat().st_size)


def main():
    output = EVIDENCE / "software-final-20261022-1206"
    output.mkdir(exist_ok=False)
    ordered = [
        "fpga/rtl/sc520-card-recognition/pixel14/capture_rgb96.v",
        "fpga/rtl/sc520-card-recognition/pixel14/pixel14_result_cdc.v",
        *["fpga/rtl/sc520-shape-card30/" + name for name in (
            "pixel30_scene_preprocess.v", "pixel30_shape_scores.v", "pixel30_rotation_matcher.v",
            "pixel30_arbitrate.v", "items30_result_filter.v", "items30_result_join.v",
            "items30_question_bank.v", "items30_quiz_control.v", "items30_system.v")],
    ]
    ordered += [
        "fpga/rtl/sc520-card-recognition/items14/items14_content.v",
        "fpga/rtl/sc520-card-recognition/items14/items14_font_rom.v",
        "fpga/rtl/sc520-shape-card30/items30_content.v",
        *["fpga/rtl/sc520-color-integration/" + name for name in (
            "pixel26_color_classify.v", "pixel26_saturation.v", "pixel26_processing_display.v")],
        "fpga/rtl/sc520-shape-card30/pixel30_panel.v",
        "fpga/rtl/sc520-card-recognition/display17/sc520_logo_pipeline.v",
        "fpga/rtl/sc520-shape-card30/pixel30_compositor.v",
        "fpga/rtl/sc520-shape-card30/pixel30_pipeline.v",
    ]
    assert len(ordered) == 21 and len(set(ordered)) == 21
    assets = [
        "fpga/rtl/sc520-shape-card30/recognition30_packet.vh",
        "assets/templates/sc520-card-recognition/rotation-v1/templates.mem",
        "assets/templates/sc520-contour29/contour29-shapes.mem",
        *["assets/templates/sc520-card-recognition/display17/" + name for name in (
            "font-extension.json", "anlogic_logo_rgba.png", "anlogic_logo_index.mem", "anlogic_logo_palette.mem")],
        "assets/templates/sc520-shape-card30/item_catalog.json",
        "hardware/sc520-shape-card30/recognition-interface.json",
        "hardware/sc520-shape-card30/synthesis-plan.md",
    ]
    tests = sorted((ROOT / "fpga/sim/sc520-shape-card30").glob("*.sv"))
    tools = [ROOT / "fpga/scripts/sc520-card-recognition" / name for name in (
        "simulate-shape-card30.py", "generate-shape-card30-render.py",
        "simulate-shape-card30-chain.py", "freeze-shape-card30-software.py")]
    selected = [
        "scene-normal-20261022-110258-4e9e1a", "scores-normal-20261022-110258-723053",
        "render-normal-20261022-120053-1352fe", "render-negative-20261022-120053-0db9de",
        "matcher-normal-20261022-120112-c80897", "matcher-negative-20261022-120113-246a22",
        "filter-normal-20261022-120119-f4f6b6", "filter-negative-20261022-120119-497337",
        "quiz-normal-20261022-120122-58a6a1", "quiz-negative-20261022-120122-339750",
        "scores-normal-20261022-120126-303ab4", "scores-negative-20261022-120126-e9a3ab",
        "scene-normal-20261022-120133-36ea76", "scene-negative-20261022-120133-773325",
    ]
    verified = []
    for name in selected:
        path = EVIDENCE / "runs" / name / "run-manifest.json"
        report = json.loads(path.read_text(encoding="utf-8"))
        assert report["Qualified"] and report["InputsUnchanged"]
        assert report["NativeExitCode"] == int(report["Negative"])
        assert report["Summary"]["errors"] == int(report["Negative"])
        current_changes = []
        for row in report["Inputs"]:
            assert artifact(row["Snapshot"])["SHA256"] == row["SnapshotSHA256"]
            if artifact(row["Path"])["SHA256"] != row["SHA256"]:
                assert report["All"] and Path(row["Path"]).name == "simulate-shape-card30.py"
                current_changes.append(dict(Path=row["Path"], Note="Runner subsequently hardened; original execution snapshot preserved. RTL/TB/model/asset unchanged."))
        for row in report["GeneratedInputs"]:
            assert artifact(row["Path"])["SHA256"] == row["SHA256"]
        if "Tool" in report:
            assert report["ToolUnchanged"] and artifact(report["Tool"]["Path"])["SHA256"] == report["Tool"]["SHA256"]
        verified.append(dict(Report=artifact(path), Summary=report["Summary"],
                             Full=report["All"], Negative=report["Negative"],
                             SubsequentOriginalChanges=current_changes,
                             ToolBindingAvailable="Tool" in report))
    manifest = dict(
        Stage="software_candidate_frozen_pending_independent_and_main_review",
        Candidate="D0300", Owner="Codex /root/shape30_detector_finish",
        At=datetime.now(timezone(timedelta(hours=8))).isoformat(),
        BaseCommit="67b5448876a5d99989c1279e92c60ffb9288dfd5",
        TaskRTLCount=13, SharedRuntimeRTLCount=8,
        SharedVerificationReference=artifact(ROOT / "fpga/rtl/sc520-card-recognition/pixel14/pixel14_rotation_matcher.v"),
        CompileOrder=[artifact(ROOT / path) for path in ordered],
        AssetsAndContract=[artifact(ROOT / path) for path in assets],
        Testbenches=[artifact(path) for path in tests],
        Tools=[artifact(path) for path in tools], SelectedDetectorRuns=verified,
        LinkFinal=artifact(EVIDENCE / "chain-runs/link-final-20261022-1202.json"),
        DisplayInspection=dict(
            Run="render-normal-20261022-120053-1352fe", FourImagesPixels=3686400,
            UnavailableDiagnosticPixels=55296, Mismatches=0, VisualInspectedCases=[0, 1, 2, 3],
            EquivalentImagesActuallyViewedRun="render-normal-20261022-114735-33ab1f",
            Note="Final images independently compared byte-identical below; initial reference failures preserved."),
        HistoricalFailuresPreserved=[
            "scores-normal-20261022-094106-935477",
            "render-normal-20261022-114007-0f94d8",
            "render-normal-20261022-115537-8ccf36",
            "render-negative-20261022-115537-7c16eb"],
        KnownLimits="Frozen C only white background, upright geometry and tested scales. Original 17 shadow/near-circle, 50 new pose, 30 holdout pose, one holdout apple and five dark-card misses remain. Not field acceptance.",
        SynthesisAllowed=False, RouteAllowed=False, BitgenAllowed=False, HardwareValidated=False)
    for case in range(4):
        viewed = EVIDENCE / f"runs/render-normal-20261022-114735-33ab1f/actual-{case}.png"
        final = EVIDENCE / f"runs/render-normal-20261022-120053-1352fe/actual-{case}.png"
        assert artifact(viewed)["SHA256"] == artifact(final)["SHA256"]
    with (output / "source-freeze.json").open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(manifest, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
    print(json.dumps(artifact(output / "source-freeze.json")))


if __name__ == "__main__":
    main()
