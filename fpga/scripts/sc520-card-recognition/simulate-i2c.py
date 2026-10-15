"""Run real SC520 configuration RTL against a pin-only open-drain sensor model."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone, timedelta
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import uuid

REPO = Path(__file__).resolve().parents[3]
VENDOR = REPO.parent / "sc520-fixed-roi/fpga/custom_project/sc520-board-keys/user_source/hdl_source"


def now():
    return datetime.now(timezone(timedelta(hours=8))).isoformat(timespec="seconds")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def save(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def quote(path):
    return "{" + path.as_posix() + "}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config-source", type=Path, default=VENDOR / "uics520_cfg/uicfgcs520.v")
    parser.add_argument("--i2c-source", type=Path, default=VENDOR / "uics500_cfg/uii2c.v")
    modes = ("normal", "id-nack", "init-nack", "ae-nack", "id-reject", "id-stuck", "init-stuck", "ae-stuck", "id-wrong", "id-alt", "ae-snapshot", "timeout")
    parser.add_argument("--mode", choices=modes, default="normal")
    parser.add_argument("--expect-recovery", action="store_true")
    probes = parser.add_mutually_exclusive_group()
    probes.add_argument("--checker-negative", action="store_true")
    probes.add_argument("--watchdog-probe", action="store_true")
    parser.add_argument("--clk-div", type=int, default=23)
    parser.add_argument("--simulator", type=Path, default=Path("D:/modeltech64_10.7/win64/vsim.exe"))
    parser.add_argument("--timeout-seconds", type=int, default=180)
    args = parser.parse_args()
    if modes.index(args.mode) >= 5 and not args.expect_recovery:
        parser.error("extended recovery modes require --expect-recovery and the candidate config source")
    config = args.config_source.resolve()
    rtl = [config, args.i2c_source.resolve()] + [VENDOR / "uics520_cfg" / name for name in
            ("uics520reg_720p60.v", "uics520regAE.v", "SC520GainTbl.v")]
    tb = REPO / "fpga/sim/sc520-card-recognition/tb_pixel14_i2c.sv"
    sources = [*rtl, tb, Path(__file__).resolve()]
    ini = args.simulator.resolve().parent.parent / "modelsim.ini"
    if not all(path.is_file() for path in [*sources, args.simulator, ini]):
        parser.error("required simulation input is missing")
    stamp = datetime.now(timezone(timedelta(hours=8))).strftime("%Y%m%d-%H%M%S")
    run = REPO / "evidence/sc520-card-recognition/i2c-runs" / f"{args.mode}-{stamp}-{uuid.uuid4().hex[:8]}"
    snapshot = run / "inputs"
    snapshot.mkdir(parents=True, exist_ok=False)
    inputs = []
    for source in sources:
        dest = snapshot / source.name
        before = digest(source)
        shutil.copyfile(source, dest)
        if digest(dest) != before:
            raise RuntimeError(f"input changed during snapshot: {source}")
        inputs.append({"path": str(source), "snapshot": str(dest), "sha256_before": before})
    table = (snapshot / "uics520reg_720p60.v").read_text(encoding="utf-8")
    entries = re.findall(r"9'd(\d+):\s*REG_DATA\s*=\s*\{16'h([0-9a-fA-F]{4}),\s*8'h([0-9a-fA-F]{2})\}", table)
    if [int(x[0]) for x in entries] != list(range(165)):
        raise RuntimeError("expected exact 165-entry literal SC520 initialization table")
    (run / "expected-init.mem").write_text("".join(address + value + "\n" for _, address, value in entries), encoding="ascii")
    shutil.copyfile(ini, run / "modelsim.ini")
    mode = modes.index(args.mode)
    fields = ("errors", "checks", "test_done", "rx_bytes", "tx_bytes", "ack_count", "nack_count", "master_nacks",
              "init_writes", "ae_writes", "injected", "sticky_seen", "reset_gap_cycles", "cfg_done", "ae_done", "iic_error", "sensor_id",
              "starts", "stops", "write_count", "accepted_writes")
    if args.expect_recovery:
        fields += ("diagnostic", "errors_while_incomplete", "retry_gap_cycles", "premature_clear")
    defines = ("+define+I2C_CANDIDATE " if args.expect_recovery else "") + ("+define+I2C_TIMEOUT_PROBE " if args.mode == "timeout" else "")
    macro = ["onerror {quit -force -code 2}", "onbreak {resume}", "vlib work", "vmap work work",
             "vlog " + " ".join(quote(snapshot / source.name) for source in rtl),
             "vlog -sv " + defines + quote(snapshot / tb.name),
             f"vsim -voptargs=+acc -wlf wave.wlf work.tb_pixel14_i2c -gCLK_DIV={args.clk_div} +MODE={mode} +EXPECT_RECOVERY={int(args.expect_recovery)} +CHECKER_NEGATIVE={int(args.checker_negative)}",
             "onfinish stop", "run 500 ns" if args.watchdog_probe else "run -all", "set fd [open summary.json w]", "set pieces [list]"]
    for field in fields:
        macro += [f"set {field} [examine -radix unsigned /tb_pixel14_i2c/{field}]",
                  f'lappend pieces "\\\"{field}\\\":${field}"']
    macro += ['puts $fd "{[join $pieces ,]}"', "close $fd", "if {!$test_done} {quit -force -code 2}",
              "if {$errors != 0} {quit -force -code 1}", "quit -force -code 0"]
    (run / "run.do").write_text("\n".join(macro) + "\n", encoding="ascii")
    command = [str(args.simulator), "-modelsimini", str(run / "modelsim.ini"), "-c", "-l", "transcript.log", "-do", "source " + quote(run / "run.do")]
    report = {"Task": "sc520-card-recognition", "Owner": "/root/i2c_bus_tests", "StartedAt": now(),
              "Mode": args.mode, "ExpectRecovery": args.expect_recovery, "ClockDivider": args.clk_div,
              "CheckerNegative": args.checker_negative, "WatchdogProbe": args.watchdog_probe,
              "Command": command, "RunnerCommand": [sys.executable, *sys.argv], "WorkingDirectory": str(run),
              "Inputs": inputs, "SimulatorIni": {"path": str(ini), "sha256": digest(ini)},
              "Scope": "Real controller and configuration tables; pin-only open-drain slave, no physical camera/board test"}
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
    tool_error = any(token in transcript for token in ("** Error:", "** Fatal:", "I2C_TIMEOUT cfg="))
    expected_code = 2 if args.watchdog_probe else (1 if args.checker_negative else 0)
    expected_done = 0 if args.watchdog_probe else 1
    expected_errors = 1 if args.checker_negative else 0
    qualified = not timed_out and unchanged and not tool_error and code == expected_code and summary is not None and summary.get("test_done") == expected_done and summary.get("errors") == expected_errors
    report.update(FinishedAt=now(), ElapsedSeconds=time.monotonic()-started, NativeExitCode=code,
                  TimedOut=timed_out, InputsUnchanged=unchanged, Summary=summary, Qualified=bool(qualified))
    report["Outputs"] = [{"path": str(path), "sha256": digest(path)} for path in sorted(run.iterdir())
                         if path.is_file() and path.name not in ("wave.wlf", "modelsim.ini")]
    save(run / "run-manifest.json", report)
    print(json.dumps({"run": str(run), "qualified": bool(qualified), "native_exit": code, "summary": summary}))
    return 0 if qualified else 1


if __name__ == "__main__":
    raise SystemExit(main())
