"""Snapshot scene RTL, independent fixture vectors and native ModelSim results."""
from __future__ import annotations
import argparse
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import time
import uuid

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("scene_sim_common", HERE / "simulate.py")
common = importlib.util.module_from_spec(spec)
spec.loader.exec_module(common)
REPO = common.REPO


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--asset-root", type=Path, default=REPO / "assets/templates/sc520-card-recognition/scene-v2")
    parser.add_argument("--all", action="store_true", help="Check every fixture rather than rtl_default subset")
    parser.add_argument("--limit", type=int, default=0, help="Smoke-test first N selected fixtures; control tests still run")
    parser.add_argument("--normal-size", type=int, default=20)
    parser.add_argument("--model", type=Path, help="Oracle module; default follows the selected fixture manifest")
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--negative", action="store_true")
    modes.add_argument("--watchdog-probe", action="store_true")
    parser.add_argument("--simulator", type=Path, default=Path("D:/modeltech64_10.7/win64/vsim.exe"))
    parser.add_argument("--timeout-seconds", type=int, default=900)
    args = parser.parse_args()
    assets = args.asset_root.resolve()
    ini = args.simulator.resolve().parent.parent / "modelsim.ini"
    if not args.simulator.is_file() or not ini.is_file():
        parser.error("ModelSim and its installation modelsim.ini must exist")
    fixture_manifest = json.loads((assets / "manifest.json").read_text(encoding="utf-8"))
    recorded_outputs = {item["path"].replace("\\", "/"): item["sha256"].upper()
                        for item in fixture_manifest["outputs"]}
    fixtures = json.loads((assets / "fixtures.json").read_text(encoding="utf-8"))
    selected = [r for r in fixtures if args.all or r.get("rtl_default", r.get("system_default", False))]
    if args.limit:
        selected = selected[:args.limit]
    if not selected:
        parser.error("no selected fixtures")
    manifest_scripts = {Path(item["path"]).name: item for item in fixture_manifest["scripts"]}
    model_name = "scene-rotation-model.py" if "scene-rotation-model.py" in manifest_scripts else "scene-model.py"
    model_path = args.model.resolve() if args.model else HERE / model_name
    model_dependencies = [HERE / "scene-model.py"] if model_path.name == "scene-rotation-model.py" else []
    model_spec = importlib.util.spec_from_file_location("scene_model", model_path)
    model = importlib.util.module_from_spec(model_spec)
    model_spec.loader.exec_module(model)
    rtl = REPO / "fpga/rtl/sc520-card-recognition/pixel14/pixel14_scene_preprocess.v"
    tb = REPO / "fpga/sim/sc520-card-recognition/tb_pixel14_scene.sv"
    mode = "negative" if args.negative else "watchdog" if args.watchdog_probe else "normal"
    tag = common.now().replace("-", "").replace(":", "").replace("T", "-")[:15]
    run = REPO / "evidence/sc520-card-recognition/runs" / f"scene-{mode}-{tag}-{uuid.uuid4().hex[:8]}"
    snap = run / "inputs"
    snap.mkdir(parents=True, exist_ok=False)
    inputs = []

    def copy(path, name=None):
        dest = snap / (name or path.name)
        before = common.digest(path)
        if path.is_relative_to(assets) and path.name != "manifest.json":
            recorded = recorded_outputs.get(path.relative_to(assets).as_posix())
            if recorded is None or before != recorded:
                raise RuntimeError(f"fixture file does not match generator manifest: {path}")
        dest.write_bytes(path.read_bytes())
        if common.digest(dest) != before or common.digest(path) != before:
            raise RuntimeError(f"input changed while snapshotting: {path}")
        inputs.append({"path": str(path), "snapshot": str(dest), "sha256_before": before})
        return dest

    for path in (rtl, tb, Path(__file__), HERE / "simulate.py", model_path, *model_dependencies, assets / "fixtures.json", assets / "manifest.json"):
        copy(path)
    lines, vector_records = [], []
    for rec in selected:
        prefix = rec["prefix"]
        # Existing generator references are the oracle. Reading PNG is only a
        # fallback for broad fixtures where the generator omitted large mems.
        original = assets / "vectors" / prefix
        rgb_path = Path(str(original) + ".rgb.mem")
        replay_path = Path(str(original) + ".replay.mem")
        mask_path = Path(str(original) + ".mask.mem")
        if all(path.is_file() for path in (rgb_path, replay_path, mask_path)):
            for path in (rgb_path, replay_path, mask_path):
                copy(path)
        else:
            import numpy as np
            from PIL import Image
            for dependency in [model_path, *model_dependencies]:
                entry = manifest_scripts.get(dependency.name)
                if entry is None or common.digest(dependency) != entry["sha256"].upper():
                    raise RuntimeError("fallback vector generation requires exact manifested model versions")
            image_path = Path(str(original) + ".png")
            copy(image_path)
            frame = np.asarray(Image.open(image_path).convert("RGB"))
            result = model.analyze(model.sample_frame(frame))
            for key in ("present", "scene_count", "glyph_count", "background_rgb"):
                if result[key] != rec["expected"][key]:
                    raise RuntimeError(f"current model does not reproduce manifest {prefix}:{key}")
            for name, arr in (("rgb", frame), ("replay", result["replay_rgb"])):
                (snap / f"{prefix}.{name}.mem").write_text("".join(f"{int(r):02x}{int(g):02x}{int(b):02x}\n" for r, g, b in arr.reshape(-1, 3)), encoding="ascii")
            (snap / f"{prefix}.mask.mem").write_text("".join(f"{int(bit):x}\n" for bit in result["mask"].flat), encoding="ascii")
        exp = rec["expected"]
        card = rec.get("card", exp.get("card_raw"))
        block_item = rec.get("block_item", exp.get("block_item", 0))
        bg = "".join(f"{int(c):02x}" for c in exp["background_rgb"])
        lines.append(f"{prefix} {int(exp['present'])} {exp['scene_count']} {exp['glyph_count']} {int(card['valid'])} {card['item']} {card['best']} {card['second']} {card['foreground']} {block_item} {bg} {exp.get('paper_count', -1)} {int(exp.get('paper_route', False))}\n")
        vector_records.append({"prefix": prefix, "category": rec["category"], "truth_satisfied": rec["truth_satisfied"], "expected": exp})
    (snap / "fixtures.txt").write_text("".join(lines), encoding="ascii")
    local_ini = run / "modelsim.ini"
    local_ini.write_bytes(ini.read_bytes())
    q = common.tcl_path
    command_text = f'''onerror {{quit -force -code 2}}
onbreak {{resume}}
if {{[catch {{
vlib work
vmap work work
vlog {q(snap / rtl.name)}
vlog -sv {q(snap / tb.name)}
vsim -voptargs=+acc -wlf wave.wlf work.tb_pixel14_scene -gNORMAL_SIZE={args.normal_size} +ASSET_ROOT={str(snap).replace(chr(92), '/')} +INJECT_FAULT={int(args.negative)}
onfinish stop
{'run 500 ns' if args.watchdog_probe else 'run -all'}
}} failure]}} {{puts stderr $failure; quit -force -code 2}}
set fd [open summary.json w]
puts $fd [format {{{{"errors":%d,"checks":%d,"scenarios":%d,"done":%d,"injected":%d,"max_latency":%d,"max_single_latency":%d,"fixtures":%d}}}} [examine -radix decimal /tb_pixel14_scene/errors] [examine -radix decimal /tb_pixel14_scene/checks] [examine -radix decimal /tb_pixel14_scene/scenarios] [examine -radix unsigned /tb_pixel14_scene/test_done] [examine -radix decimal /tb_pixel14_scene/injected] [examine -radix decimal /tb_pixel14_scene/max_latency] [examine -radix decimal /tb_pixel14_scene/max_single_latency] [examine -radix decimal /tb_pixel14_scene/fixture_count]]
close $fd
if {{![examine -radix unsigned /tb_pixel14_scene/test_done]}} {{quit -force -code 2}}
if {{[examine -radix decimal /tb_pixel14_scene/errors] != 0}} {{quit -force -code 1}}
quit -force -code 0
'''
    script = run / "launch.do"
    script.write_text(command_text, encoding="utf-8")
    command = [str(args.simulator), "-modelsimini", str(local_ini), "-c", "-l", "transcript.log", "-do", f"do {q(script)}"]
    report = {"Task": "sc520-card-recognition", "Owner": "01a13561-2629-7fa2-86a0-4087ad34cc7c /root/scene_rtl", "StartedAt": common.now(), "Mode": mode,
              "Command": command, "WorkingDirectory": str(run), "Inputs": inputs, "Fixtures": vector_records,
              "NormalSize": args.normal_size, "AllFixtures": args.all, "TimeoutSeconds": args.timeout_seconds,
              "Scope": "Task-local RGB raster extraction, integer model equivalence and fail-closed capture sequencing; synthetic fixtures only; no board or camera accuracy claim"}
    common.save(run / "run-start.json", report)
    started = time.monotonic()
    code, timed_out = None, False
    with (run / "stdout.log").open("wb") as stdout, (run / "stderr.log").open("wb") as stderr:
        process = subprocess.Popen(command, cwd=run, stdout=stdout, stderr=stderr)
        report["PID"] = process.pid
        try:
            code = process.wait(timeout=args.timeout_seconds)
        except subprocess.TimeoutExpired:
            timed_out = True
            subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], capture_output=True)
            code = process.wait()
    summary_path = run / "summary.json"
    summary = json.loads(summary_path.read_text()) if summary_path.exists() else None
    qualified = (not timed_out and summary is not None and
                 ((args.watchdog_probe and code == 2 and summary["done"] == 0) or
                  (args.negative and code == 1 and summary["done"] == 1 and summary["errors"] == 1 and summary["injected"] == 1) or
                  (not args.watchdog_probe and not args.negative and code == 0 and summary["done"] == 1 and summary["errors"] == 0)))
    unchanged = all(common.digest(Path(item["path"])) == item["sha256_before"] and common.digest(Path(item["snapshot"])) == item["sha256_before"] for item in inputs)
    report.update({"CompletedAt": common.now(), "ElapsedSeconds": round(time.monotonic()-started, 3), "ProcessExitCode": code,
                   "TimedOut": timed_out, "Summary": summary, "InputsUnchanged": unchanged, "Qualified": qualified and unchanged,
                   "Artifacts": [{"path": str(path), "sha256": common.digest(path), "bytes": path.stat().st_size}
                                 for path in sorted(run.rglob("*")) if path.is_file() and "work" not in path.parts and path.suffix != ".wlf"]})
    common.save(run / "run-manifest.json", report)
    print(json.dumps({"run": str(run), "qualified": report["Qualified"], "summary": summary, "exit": code, "seconds": report["ElapsedSeconds"]}, ensure_ascii=False))
    return 0 if report["Qualified"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
