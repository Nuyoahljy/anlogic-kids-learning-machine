"""Run a snapshotted ModelSim card test in a unique evidence directory."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone, timedelta
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time
import uuid

REPO = Path(__file__).resolve().parents[3]
TASK = "sc520-card-recognition"

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()

def save(path, value):
    path.write_bytes((json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))

def now():
    return datetime.now(timezone(timedelta(hours=8))).isoformat(timespec="milliseconds")

def tcl_path(path):
    value = str(path).replace("\\", "/")
    if any(c in value for c in "{}\n\r"):
        raise ValueError("unsupported Tcl path characters")
    return "{" + value + "}"

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--test", choices=("matcher", "filter", "pipeline"), default="matcher")
    p.add_argument("--negative", action="store_true")
    p.add_argument("--watchdog-probe", action="store_true")
    p.add_argument("--asset-root", type=Path, default=REPO / "assets/templates/sc520-card-recognition/prep-v1-max40")
    p.add_argument("--simulator", type=Path, default=Path("D:/modeltech64_10.7/win64/vsim.exe"))
    p.add_argument("--timeout-seconds", type=int, default=180)
    a = p.parse_args()
    if a.negative and a.test == "filter":
        p.error("negative injection is implemented for matcher and pipeline")
    if a.watchdog_probe and a.negative:
        p.error("watchdog probe and negative injection are separate runs")
    if not 1 <= a.timeout_seconds <= 900:
        p.error("timeout must be 1..900 seconds")
    simulator_ini = a.simulator.resolve().parent.parent / "modelsim.ini"
    if not a.simulator.is_file() or not simulator_ini.is_file():
        p.error("simulator and installation modelsim.ini must exist")
    top = "tb_card_" + a.test
    asset_root = a.asset_root.resolve()
    if not (asset_root / "templates.mem").is_file():
        p.error("asset root must contain templates.mem")
    rtl = sorted((REPO / "fpga/rtl" / TASK).glob("*.v"))
    tb = REPO / "fpga/sim" / TASK / (top + ".sv")
    do_file = Path(__file__).with_name("run-sim.do")
    sources = [*rtl, tb, Path(__file__).resolve(), do_file]
    sources += [x for x in sorted(asset_root.rglob("*")) if x.is_file()]
    if not all(x.is_file() for x in sources):
        p.error("missing source or testbench")
    mode = "watchdog" if a.watchdog_probe else ("negative" if a.negative else "normal")
    tag = datetime.now(timezone(timedelta(hours=8))).strftime("%Y%m%d-%H%M%S")
    run = REPO / "evidence" / TASK / "runs" / f"{a.test}-{mode}-{tag}-{uuid.uuid4().hex[:8]}"
    run.mkdir(parents=True, exist_ok=False)
    # Copy bytes only: the installation ini may be read-only. Never modify it.
    local_ini = run / "modelsim.ini"
    local_ini.write_bytes(simulator_ini.read_bytes())
    snapshot = run / "inputs"
    inputs = []
    destinations = {}
    for path in sources:
        # Keep snapshots short enough for Windows tools with MAX_PATH limits.
        if path.is_relative_to(asset_root):
            dest = snapshot / "assets" / path.relative_to(asset_root)
        elif path in rtl:
            dest = snapshot / "rtl" / path.name
        elif path == tb:
            dest = snapshot / "tb" / path.name
        else:
            dest = snapshot / "scripts" / path.name
        dest.parent.mkdir(parents=True, exist_ok=True)
        before = digest(path)
        shutil.copyfile(path, dest)
        if digest(dest) != before:
            raise RuntimeError("source changed during snapshot: " + str(path))
        inputs.append({"path": str(path), "snapshot": str(dest), "sha256_before": before})
        destinations[path] = dest
    frozen_assets = snapshot / "assets"
    shutil.copyfile(frozen_assets / "templates.mem", run / "templates.mem")
    compile_sources = " ".join(tcl_path(destinations[x]) for x in rtl)
    command_text = (f"set card_top {top}; set card_sources [list {compile_sources}]; "
                    f"set card_tb {tcl_path(destinations[tb])}; "
                    f"set card_assets {tcl_path(frozen_assets)}; set card_negative {int(a.negative)}; "
                    f"set card_probe {int(a.watchdog_probe)}; "
                    f"source {tcl_path(destinations[do_file])}")
    command = [str(a.simulator), "-modelsimini", str(local_ini), "-c", "-l", "transcript.log", "-do", command_text]
    report = {"Task": TASK, "Owner": "01a120ad-c540-7f11-af3b-6360b8cee2e9 /root",
              "StartedAt": now(), "Test": a.test, "Mode": mode, "Command": command,
              "WorkingDirectory": str(run), "TimeoutSeconds": a.timeout_seconds,
              "SimulatorIni": {"path": str(simulator_ini), "sha256": digest(simulator_ini)},
              "Inputs": inputs, "Scope": "RTL and synthetic RGB; no camera, electrical, PHY, TD or board validation"}
    save(run / "run-start.json", report)
    timed_out = False
    exit_code = None
    started = time.monotonic()
    try:
        with (run / "stdout.log").open("wb") as stdout, (run / "stderr.log").open("wb") as stderr:
            process = subprocess.Popen(command, cwd=run, stdout=stdout, stderr=stderr)
            report["PID"] = process.pid
            try:
                exit_code = process.wait(timeout=a.timeout_seconds)
            except subprocess.TimeoutExpired:
                timed_out = True
                # Only stop this runner's child process tree, never another simulation.
                if sys.platform == "win32":
                    stopped = subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], capture_output=True)
                    report["TimeoutTerminationExit"] = stopped.returncode
                else:
                    process.kill()
                try:
                    exit_code = process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    report["TerminationUnconfirmed"] = True
    except Exception as exc:
        report["LaunchError"] = f"{type(exc).__name__}: {exc}"
    for item in inputs:
        path, snap = Path(item["path"]), Path(item["snapshot"])
        item["sha256_after"] = digest(path) if path.exists() else None
        item["snapshot_sha256"] = digest(snap)
    unchanged = all(x["sha256_before"] == x["sha256_after"] == x["snapshot_sha256"] for x in inputs)
    result_path = run / "summary.json"
    summary = json.loads(result_path.read_text(encoding="utf-8")) if result_path.exists() else None
    transcript = (run / "transcript.log").read_text(encoding="utf-8", errors="replace") if (run / "transcript.log").exists() else ""
    error_text = any(x in transcript for x in ("** Error:", "** Fatal:", "CARD_PARAMETER_ERROR", "WATCHDOG"))
    if a.watchdog_probe:
        qualified = (not timed_out and unchanged and not error_text and exit_code == 2 and summary is not None
                     and summary.get("done") == 0 and summary.get("errors") == 0)
    elif a.negative:
        qualified = (not timed_out and unchanged and not error_text and exit_code == 1 and summary is not None
                     and summary.get("done") == 1 and summary.get("errors") == 1 and summary.get("injected") == 1)
    else:
        qualified = (not timed_out and unchanged and not error_text and exit_code == 0 and summary is not None
                     and summary.get("done") == 1 and summary.get("errors") == 0)
    report.update(FinishedAt=now(), ElapsedSeconds=time.monotonic()-started, NativeExitCode=exit_code,
                  TimedOut=timed_out, InputsUnchanged=unchanged, Summary=summary, Qualified=qualified)
    report["Outputs"] = [{"path": str(x), "sha256": digest(x)} for x in sorted(run.iterdir())
                         if x.is_file() and x.name not in ("wave.wlf", "modelsim.ini")]
    save(run / "run-manifest.json", report)
    print(json.dumps({"run": str(run), "qualified": qualified, "native_exit": exit_code, "summary": summary}, ensure_ascii=False))
    return 0 if qualified else 1

if __name__ == "__main__":
    raise SystemExit(main())
