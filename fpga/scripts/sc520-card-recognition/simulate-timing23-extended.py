"""Snapshot the task-local fourteen-item result subsystem tests; no board access."""
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
    parser.add_argument('--test', choices=('business','default'), required=True)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--negative", action="store_true")
    modes.add_argument("--watchdog-probe", action="store_true")
    parser.add_argument("--simulator", type=Path, default=Path("D:/modeltech64_10.7/win64/vsim.exe"))
    args = parser.parse_args()
    ini = args.simulator.resolve().parent.parent / "modelsim.ini"
    if not args.simulator.is_file() or not ini.is_file():
        parser.error("ModelSim executable and installation modelsim.ini are required")
    base=REPO/'fpga/rtl/sc520-card-recognition'
    rtl=sorted((base/'items14').glob('*.v'))+[base/'display17'/n for n in ('sc520_processing_display.v','sc520_color_classify.v','sc520_logo_pipeline.v','pixel17_display_request.v')]+sorted((base/'audio22').glob('*.v'))+sorted((base/'audio22/imported').glob('*.v'))+[base/'color_diag/pixel14_color_diag_osd.v']
    if args.test in ('business','default'):rtl.append(REPO/'fpga/sim/sc520-card-recognition/audio22/dfr0534_uart_model.sv')
    if args.test in ('pipeline','reset'):rtl+=sorted((base/'pixel14').glob('*.v'))+[base/'card_matcher.v',base/'card_template_rom.v',base/'card_result_filter.v']+[p for p in sorted((base/'color_diag').glob('*.v')) if p.name!='pixel14_color_diag_osd.v']
    rtl+=sorted((base/'timing23').glob('*.v'))
    if args.test=='reset':rtl += [REPO/'fpga/custom_project/sc520-timing23/overlay/pixel14_color_pipeline.v', REPO.parent/'sc520-fixed-roi/fpga/custom_project/sc520-board-keys/user_source/hdl_source/signal_delay.v', REPO/'evidence/sc520-card-recognition/imaging-audit/ip_behavioral_models.sv']
    top='tb_timing23_'+args.test
    tb=REPO/'fpga/sim/sc520-card-recognition/timing23'/ (top+'.sv')
    macro=HERE/'run-audio22.do'
    assets=REPO/'assets/templates/sc520-card-recognition/audio22'
    references=sorted(assets.glob('*.mem'))+[REPO/'assets/templates/sc520-card-recognition/display17'/n for n in ('anlogic_logo_index.mem','anlogic_logo_palette.mem')]+[REPO/'assets/templates/sc520-card-recognition/items14/items14_text_reference.svh']
    if args.test in ('pipeline','reset'):references+=[REPO/'assets/templates/sc520-card-recognition/rotation-v1/templates.mem']+[REPO/'assets/templates/sc520-card-recognition/rotation-v1/vectors'/n for n in ('r000_empty_dark.rgb.mem','r003_card_10_angle_0.rgb.mem')]
    sources=[*rtl,tb,Path(__file__).resolve(),HERE/'simulate.py',macro,*references]
    if not all(path.is_file() for path in sources):
        parser.error("items14 source, testbench or runner dependency is missing")
    mode = "negative" if args.negative else ("watchdog" if args.watchdog_probe else "normal")
    tag = common.now().replace("-", "").replace(":", "").replace("T", "-")[:15]
    run = REPO / "evidence/sc520-card-recognition/runs" / f"timing23-{args.test}-{mode}-{tag}-{uuid.uuid4().hex[:8]}"
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
    command_text = (f"set card_top {top}; set card_sources [list " +
                    " ".join(quote(snapshot / path.name) for path in rtl) + "]; " +
                    f"set card_tb {quote(snapshot / tb.name)}; set card_assets {quote(snapshot)}; " +
                    f"set card_negative {int(args.negative)}; set card_probe {int(args.watchdog_probe)}; " +
                    f"source {quote(snapshot / macro.name)}")
    command = [str(args.simulator), "-modelsimini", str(local_ini), "-c", "-l", "transcript.log", "-do", command_text]
    report = {"Task": "sc520-card-recognition", "Owner": "01a144c7-e802-7272-a29d-a8159f5ec84b /root T023",
              "StartedAt": common.now(), "Mode": mode, "Test": args.test, "Command": command,
              "WorkingDirectory": str(run), "Inputs": inputs, "TimeoutSeconds": 900,
              "SimulatorIni": {"path": str(ini), "sha256": common.digest(ini)},
              "Scope": "T023 reset partition and coordinate pipeline; T022 current items14 result-join/business, real UART bridge/peripheral and audio-status renderer; or full720p renderer regression. Synthetic audio profile only."}
    common.save(run / "run-start.json", report)
    started = time.monotonic()
    code, timed_out, summary = None, False, None
    try:
        with (run / "stdout.log").open("wb") as stdout, (run / "stderr.log").open("wb") as stderr:
            process = subprocess.Popen(command, cwd=run, stdout=stdout, stderr=stderr)
            report["PID"] = process.pid
            try:
                code = process.wait(timeout=900)
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
