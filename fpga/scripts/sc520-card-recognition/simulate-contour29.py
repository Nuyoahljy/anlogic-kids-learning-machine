"""T029 snapshot runner; raw native failures and prior inputs are never rewritten."""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import argparse
import hashlib
import json
import subprocess
import time
import uuid

R = Path(__file__).resolve().parents[3]
S = Path(__file__).parent


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--test", choices=["scene", "scenes", "reset", "pipeline", "render", "lifecycle", "pairing"], required=True)
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--legacy", action="store_true")
    ap.add_argument("--negative", action="store_true")
    ap.add_argument("--watchdog-probe", action="store_true")
    args = ap.parse_args()
    rtl = sorted((R / "fpga/rtl/sc520-contour29").glob("*.v"))
    rtl += [R / "fpga/rtl/sc520-color-integration/pixel26_classify_pipe.v"]
    if args.test != "scene":
        rtl = sorted((R / "fpga/rtl/sc520-color-integration").glob("*.v")) + sorted((R / "fpga/rtl/sc520-shape27").glob("*.v")) + rtl[:-1]
        base = R / "fpga/rtl/sc520-card-recognition"
        for folder in ["items14", "display17", "audio22", "audio22/imported", "pixel14", "color_diag", "timing23"]:
            rtl += sorted((base / folder).glob("*.v"))
        rtl += [base / name for name in ["card_matcher.v", "card_template_rom.v", "card_result_filter.v"]]
        rtl += [R / "fpga/sim/sc520-card-recognition/audio22/dfr0534_uart_model.sv"]
    tb = R / "fpga/sim/sc520-contour29" / f"tb_contour29_{args.test}.sv"
    fixture = R / "evidence/sc520-contour29/fixtures-v1"
    refs = [R / "assets/templates/sc520-contour29/contour29-shapes.mem"]
    refs += list(fixture.glob("*.mem")) + list(fixture.glob("*-cases.txt"))
    if args.test != "scene":
        refs += [R / "assets/templates/sc520-card-recognition/rotation-v1/templates.mem"]
        refs += list((R / "assets/templates/sc520-card-recognition/display17").glob("anlogic_logo*.mem"))
    files = list(dict.fromkeys(rtl + [tb, Path(__file__).resolve()] + refs))
    now = datetime.now(timezone(timedelta(hours=8)))
    mode = "legacy" if args.legacy else "negative" if args.negative else "watchdog" if args.watchdog_probe else "normal"
    run = R / "evidence/sc520-contour29/runs" / (args.test + "-" + mode + "-" + now.strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:6])
    snap = run / "inputs"
    snap.mkdir(parents=True)
    items = []
    for path in files:
        target = snap / path.name
        assert not target.exists(), target
        target.write_bytes(path.read_bytes())
        items.append(dict(Path=str(path), Snapshot=str(target), SHA256=sha(path)))
    simulator = Path("D:/modeltech64_10.7/win64/vsim.exe")
    (run / "modelsim.ini").write_bytes((simulator.parent.parent / "modelsim.ini").read_bytes())
    quote = lambda p: "{" + str(p).replace("\\", "/") + "}"
    script = f"""onerror {{quit -force -code 2}}
onbreak {{resume}}
foreach name {{contour29-shapes.mem templates.mem anlogic_logo_index.mem anlogic_logo_palette.mem}} {{
  if {{[file exists [file join {quote(snap)} $name]]}} {{file copy [file join {quote(snap)} $name] $name}}
}}
vlib work
vmap work work
set contour_sources [list {" ".join(quote(snap / p.name) for p in rtl)}]
vlog {{*}}$contour_sources
vlog -sv {"+define+LEGACY_D0270" if args.legacy else ""} {quote(snap / tb.name)}
vsim -voptargs=+acc -wlf wave.wlf work.tb_contour29_{args.test} +ASSET_ROOT={str(snap).replace(chr(92), "/")} +CASE_FILE={"all" if args.all else "smoke"}-cases.txt +INJECT_FAULT={int(args.negative)}
onfinish stop
{"run 500 ns" if args.watchdog_probe else "run -all"}
set errors [examine -radix decimal /tb_contour29_{args.test}/errors]
set checks [examine -radix decimal /tb_contour29_{args.test}/checks]
set scenarios [examine -radix decimal /tb_contour29_{args.test}/scenarios]
set done [examine -radix unsigned /tb_contour29_{args.test}/test_done]
set fd [open summary.json w]
puts $fd [format {{{{"errors":%d,"checks":%d,"scenarios":%d,"done":%d}}}} $errors $checks $scenarios $done]
close $fd
if {{!$done}} {{quit -force -code 2}}
if {{$errors!=0}} {{quit -force -code 1}}
quit -force -code 0
"""
    (run / "run.do").write_text(script, encoding="utf-8")
    command = [str(simulator), "-modelsimini", str(run / "modelsim.ini"), "-c", "-l", "transcript.log",
               "-do", "source " + quote(run / "run.do")]
    report = dict(Task="sc520-contour29", Owner="Codex /root/shape27_delivery", Test=args.test, Mode=mode,
                  Command=command, Inputs=items, WorkingDirectory=str(run), StartedAt=now.isoformat(),
                  HardwareValidated=False)
    save(run / "run-start.json", report)
    start = time.monotonic()
    with (run / "stdout.log").open("wb") as stdout, (run / "stderr.log").open("wb") as stderr:
        proc = subprocess.Popen(command, cwd=run, stdout=stdout, stderr=stderr,
                                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        report["PID"] = proc.pid
        try:
            code = proc.wait(timeout=1800)
        except subprocess.TimeoutExpired:
            subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"], capture_output=True)
            code = proc.wait()
            report["TimedOut"] = True
    summary = json.loads((run / "summary.json").read_text()) if (run / "summary.json").exists() else None
    unchanged = all(sha(item["Path"]) == item["SHA256"] == sha(item["Snapshot"]) for item in items)
    qualified = bool(summary and unchanged and not report.get("TimedOut") and summary["checks"] > 0 and summary["scenarios"] > 0)
    if qualified:
        qualified = (code == 2 and summary["done"] == 0 and summary["errors"] == 0) if args.watchdog_probe else (
            code == int(args.negative) and summary["done"] == 1 and summary["errors"] == int(args.negative))
    report.update(NativeExitCode=code, Summary=summary, InputsUnchanged=unchanged, Qualified=qualified,
                  ElapsedSeconds=time.monotonic() - start)
    report["Outputs"] = [dict(Path=str(p), SHA256=sha(p)) for p in sorted(run.iterdir()) if p.is_file() and p.suffix != ".wlf"]
    save(run / "run-manifest.json", report)
    print(json.dumps(dict(Run=str(run), Qualified=qualified, NativeExitCode=code, Summary=summary)))
    return 0 if qualified else 1


if __name__ == "__main__":
    raise SystemExit(main())
