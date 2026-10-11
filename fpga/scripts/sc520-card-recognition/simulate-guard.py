"""Snapshot and test the standalone frame guard; never touches a board or old runs."""
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
spec = importlib.util.spec_from_file_location("card_sim_common", HERE / "simulate.py")
common = importlib.util.module_from_spec(spec)
spec.loader.exec_module(common)
REPO = common.REPO


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--negative", action="store_true")
    modes.add_argument("--watchdog-probe", action="store_true")
    parser.add_argument("--simulator", type=Path, default=Path("D:/modeltech64_10.7/win64/vsim.exe"))
    args = parser.parse_args()
    ini = args.simulator.resolve().parent.parent / "modelsim.ini"
    if not args.simulator.is_file() or not ini.is_file():
        parser.error("ModelSim executable and installation modelsim.ini are required")
    rtl = [REPO / "fpga/rtl/sc520-card-recognition" / name for name in
           ("card_frame_guard.v", "card_result_filter.v")]
    tb = REPO / "fpga/sim/sc520-card-recognition/tb_card_guard.sv"
    macro = HERE / "run-sim.do"
    sources = [*rtl, tb, Path(__file__).resolve(), HERE / "simulate.py", macro]
    if not all(path.is_file() for path in sources):
        parser.error("guard source, testbench or runner dependency is missing")
    mode = "negative" if args.negative else ("watchdog" if args.watchdog_probe else "normal")
    tag = common.now().replace("-", "").replace(":", "").replace("T", "-")[:15]
    run = REPO / "evidence/sc520-card-recognition/runs" / f"guard-{mode}-{tag}-{uuid.uuid4().hex[:8]}"
    run.mkdir(parents=True, exist_ok=False)
    snapshot = run / "inputs"
    snapshot.mkdir()
    inputs = []
    for path in sources:
        dest = snapshot / path.name
        before = common.digest(path)
        dest.write_bytes(path.read_bytes())
        if common.digest(dest) != before:
            raise RuntimeError(f"source changed while taking snapshot: {path}")
        inputs.append({"path": str(path), "snapshot": str(dest), "sha256_before": before})
    local_ini = run / "modelsim.ini"
    local_ini.write_bytes(ini.read_bytes())
    quote = common.tcl_path
    command_text = ("set card_top tb_card_guard; set card_sources [list " +
                    " ".join(quote(snapshot / path.name) for path in rtl) + "]; " +
                    f"set card_tb {quote(snapshot / tb.name)}; set card_assets {quote(snapshot)}; " +
                    f"set card_negative {int(args.negative)}; set card_probe {int(args.watchdog_probe)}; " +
                    f"source {quote(snapshot / macro.name)}")
    command = [str(args.simulator), "-modelsimini", str(local_ini), "-c", "-l", "transcript.log", "-do", command_text]
    report = {"Task": "sc520-card-recognition", "Owner": "2026-10-11 continuation /root",
              "StartedAt": common.now(), "Mode": mode, "Command": command,
              "WorkingDirectory": str(run), "Inputs": inputs, "TimeoutSeconds": 90,
              "SimulatorIni": {"path": str(ini), "sha256": common.digest(ini)},
              "Scope": "Standalone guard and actual result filter; synthetic ticks; no pixel, TD or hardware verification"}
    common.save(run / "run-start.json", report)
    started = time.monotonic()
    code, timed_out, summary = None, False, None
    try:
        with (run / "stdout.log").open("wb") as stdout, (run / "stderr.log").open("wb") as stderr:
            process = subprocess.Popen(command, cwd=run, stdout=stdout, stderr=stderr)
            report["PID"] = process.pid
            try:
                code = process.wait(timeout=90)
            except subprocess.TimeoutExpired:
                timed_out = True
                if sys.platform == "win32":
                    stopped = subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], capture_output=True)
                    report["TimeoutTerminationExit"] = stopped.returncode
                else:
                    process.kill()
                code = process.wait(timeout=10)
        if (run / "summary.json").exists():
            summary = json.loads((run / "summary.json").read_text(encoding="utf-8"))
    except Exception as exc:
        report["RunError"] = f"{type(exc).__name__}: {exc}"
    for item in inputs:
        path = Path(item["path"])
        item["sha256_after"] = common.digest(path) if path.exists() else None
        item["snapshot_sha256"] = common.digest(Path(item["snapshot"]))
    unchanged = all(x["sha256_before"] == x["sha256_after"] == x["snapshot_sha256"] for x in inputs)
    transcript = (run / "transcript.log").read_text(encoding="utf-8", errors="replace") if (run / "transcript.log").exists() else ""
    clean = not any(token in transcript for token in ("** Error:", "** Fatal:", "WATCHDOG", "CARD_PARAMETER_ERROR"))
    qualified = not timed_out and unchanged and clean and "RunError" not in report and isinstance(summary, dict)
    if qualified:
        if args.watchdog_probe:
            qualified = code == 2 and summary.get("done") == 0 and summary.get("errors") == 0
        else:
            qualified = (summary.get("done") == 1 and summary.get("checks", 0) > 0 and
                         summary.get("scenarios", 0) > 0 and code == int(args.negative) and
                         summary.get("errors") == int(args.negative) and summary.get("injected") == int(args.negative))
    report.update(FinishedAt=common.now(), ElapsedSeconds=time.monotonic()-started,
                  NativeExitCode=code, TimedOut=timed_out, InputsUnchanged=unchanged,
                  Summary=summary, Qualified=bool(qualified))
    report["Outputs"] = [{"path": str(path), "sha256": common.digest(path)} for path in sorted(run.iterdir())
                         if path.is_file() and path.name not in ("wave.wlf", "modelsim.ini")]
    common.save(run / "run-manifest.json", report)
    print(json.dumps({"run": str(run), "qualified": bool(qualified), "native_exit": code, "summary": summary}))
    return 0 if qualified else 1


if __name__ == "__main__":
    raise SystemExit(main())
