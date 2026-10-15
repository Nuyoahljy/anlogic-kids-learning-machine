"""T-018 单父钟 CE 相位、非零引脚时序及复位恢复独立资格测试。"""
from __future__ import annotations
import argparse
from datetime import datetime, timedelta, timezone
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time
import uuid

REPO = Path(__file__).resolve().parents[3]
TZ = timezone(timedelta(hours=8))


def now():
    return datetime.now(TZ).isoformat(timespec="seconds")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def save(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def quote(path):
    return "{" + path.as_posix() + "}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--i2c-source", type=Path,
                        default=REPO / "fpga/custom_project/sc520-pixel14/overlay/uii2c.v")
    parser.add_argument("--simulator", type=Path, default=Path("D:/modeltech64_10.7/win64/vsim.exe"))
    parser.add_argument("--timeout-seconds", type=int, default=300)
    probes = parser.add_mutually_exclusive_group()
    probes.add_argument("--checker-negative", action="store_true")
    probes.add_argument("--watchdog-probe", action="store_true")
    args = parser.parse_args()
    rtl = args.i2c_source.resolve()
    tb = REPO / "fpga/sim/sc520-card-recognition/tb_pixel14_i2c_ce.sv"
    runner = Path(__file__).resolve()
    simulator = args.simulator.resolve()
    ini = simulator.parent.parent / "modelsim.ini"
    sources = [rtl, tb, runner]
    if not all(path.is_file() for path in [*sources, simulator, ini]):
        parser.error("required source, simulator, or modelsim.ini is missing")
    mode = "watchdog" if args.watchdog_probe else ("negative" if args.checker_negative else "normal")
    run = REPO / "evidence/sc520-card-recognition/scl-coverage" / (
        "ce-tests-" + mode + "-" + datetime.now(TZ).strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:8])
    snapshot = run / "inputs"
    snapshot.mkdir(parents=True, exist_ok=False)
    inputs = []
    for source in sources:
        before = digest(source)
        dest = snapshot / source.name
        shutil.copyfile(source, dest)
        if digest(dest) != before:
            raise RuntimeError("source changed during snapshot: " + str(source))
        inputs.append({"path": str(source), "snapshot": str(dest), "sha256_before": before})
    shutil.copyfile(ini, run / "modelsim.ini")
    fields = ("errors", "checks", "test_done", "injected", "cases", "phase_cases", "same_edge_cases",
              "completed_transactions", "abort_cases", "stuck_cases", "external_slave_clears", "reset_assertions",
              "reset_release_offsets", "request_phase_coverage", "same_edge_phase_coverage", "starts",
              "repeated_starts", "stops", "rx_bytes", "tx_bytes", "ack_count", "master_nacks", "busy_requests",
              "payload_mutations", "high_checks", "low_checks", "setup_checks", "hold_checks", "start_hold_checks",
              "restart_setup_checks", "stop_setup_checks", "min_high_ns", "min_low_ns", "min_setup_ns", "min_hold_ns",
              "max_data_valid_ns", "min_start_hold_ns", "min_restart_setup_ns", "min_stop_setup_ns", "min_bus_free_ns",
              "min_accept_cycles", "max_accept_cycles")
    macro = ["onerror {quit -force -code 2}", "onbreak {resume}", "vlib work", "vmap work work",
             "vlog " + quote(snapshot / rtl.name), "vlog -sv " + quote(snapshot / tb.name),
             "vsim -voptargs=+acc -wlf wave.wlf work.tb_pixel14_i2c_ce "
             + "+CHECKER_NEGATIVE=" + str(int(args.checker_negative)), "onfinish stop",
             "run 500 ns" if args.watchdog_probe else "run -all",
             "set fd [open summary.json w]", "set pieces [list]"]
    for field in fields:
        macro += [f"set {field} [examine -radix unsigned /tb_pixel14_i2c_ce/{field}]",
                  f'lappend pieces "\\\"{field}\\\":${field}"']
    macro += ['puts $fd "{[join $pieces ,]}"', "close $fd", "if {!$test_done} {quit -force -code 2}",
              "if {$errors != 0} {quit -force -code 1}", "quit -force -code 0"]
    (run / "run.do").write_text("\n".join(macro) + "\n", encoding="ascii")
    command = [str(simulator), "-modelsimini", str(run / "modelsim.ini"), "-c", "-l", "transcript.log",
               "-do", "source " + quote(run / "run.do")]
    report = {"Task": "sc520-card-recognition", "Owner": "/root/ce_protocol_tests", "StartedAt": now(),
              "Mode": mode, "ClockDivider": 239, "ParentPeriodNs": 42,
              "Command": command, "RunnerCommand": [sys.executable, *sys.argv], "WorkingDirectory": str(run),
              "Inputs": inputs, "SimulatorIni": {"path": str(ini), "sha256": digest(ini)},
              "Scope": "Pin-only slave; 240 request phases x pre-edge/NBA, 42 reset release offsets, 488 completed transactions, 8 aborts. No board/electrical signoff.",
              "LineModel": {"rise_ns": 1000, "fall_ns": 300, "slave_resolved_data_valid_ns": 3450},
              "Limitations": ["SCL output-only: no clock stretching or arbitration.",
                              "Master abort cannot clear a sensor that holds SDA low; explicit external sensor release is counted.",
                              "Logical net delays do not model board RC thresholds, pad timing, or metastability."]}
    save(run / "run-start.json", report)
    started = time.monotonic()
    code, timed_out = None, False
    try:
        with (run / "stdout.log").open("wb") as stdout, (run / "stderr.log").open("wb") as stderr:
            process = subprocess.Popen(command, cwd=run, stdout=stdout, stderr=stderr)
            report["PID"] = process.pid
            try:
                code = process.wait(timeout=args.timeout_seconds)
            except subprocess.TimeoutExpired:
                timed_out = True
                stopped = subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], capture_output=True)
                report["TimeoutTerminationExit"] = stopped.returncode
                code = process.wait(timeout=10)
    except Exception as exc:
        report["LaunchError"] = f"{type(exc).__name__}: {exc}"
    for item in inputs:
        item["sha256_after"] = digest(Path(item["path"]))
        item["snapshot_sha256"] = digest(Path(item["snapshot"]))
    unchanged = all(item["sha256_before"] == item["sha256_after"] == item["snapshot_sha256"] for item in inputs)
    summary_path = run / "summary.json"
    summary = json.loads(summary_path.read_text(encoding="utf-8")) if summary_path.exists() else None
    transcript_path = run / "transcript.log"
    transcript = transcript_path.read_text(encoding="utf-8", errors="replace") if transcript_path.exists() else ""
    tool_error = any(token in transcript for token in ("** Error:", "** Fatal:", "CE_INCOMPLETE"))
    expected_code = 2 if args.watchdog_probe else (1 if args.checker_negative else 0)
    expected_done = 0 if args.watchdog_probe else 1
    expected_errors = 1 if args.checker_negative else 0
    coverage = args.watchdog_probe or (summary is not None and all((
        summary.get("request_phase_coverage") == 240, summary.get("same_edge_phase_coverage") == 240,
        summary.get("reset_release_offsets") == 42, summary.get("completed_transactions") == 488,
        summary.get("abort_cases") == 8, summary.get("stuck_cases", 0) > 0,
        summary.get("external_slave_clears") == summary.get("stuck_cases"),
        summary.get("injected") == int(args.checker_negative))))
    qualified = (not timed_out and unchanged and not tool_error and code == expected_code and summary is not None
                 and summary.get("test_done") == expected_done and summary.get("errors") == expected_errors and coverage)
    report.update(FinishedAt=now(), ElapsedSeconds=time.monotonic()-started, NativeExitCode=code,
                  TimedOut=timed_out, InputsUnchanged=unchanged, Summary=summary, Qualified=bool(qualified))
    report["Outputs"] = [{"path": str(path), "sha256": digest(path), "bytes": path.stat().st_size}
                         for path in sorted(run.iterdir()) if path.is_file()]
    save(run / "run-manifest.json", report)
    print(json.dumps({"run": str(run), "qualified": bool(qualified), "native_exit": code, "summary": summary}))
    return 0 if qualified else 1


if __name__ == "__main__":
    raise SystemExit(main())
