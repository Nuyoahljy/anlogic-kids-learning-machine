"""D0291 explicit snapshot source selection; original sources and runs stay unchanged."""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import argparse
import hashlib
import json
import re
import subprocess
import time
import uuid

REPO = Path(__file__).resolve().parents[3]
OLD_SCENE = REPO / "fpga/rtl/sc520-contour29/pixel29_scene_preprocess.v"
NEW_SCENE = REPO / "fpga/rtl/sc520-contour29-retime/pixel29_scene_preprocess.v"
TB = REPO / "fpga/sim/sc520-contour29-retime/tb_contour29_retime.sv"
CLASSIFIER = REPO / "fpga/rtl/sc520-color-integration/pixel26_classify_pipe.v"
SOFTWARE = REPO / "evidence/sc520-contour29/software-v1.json"
SIMULATOR = Path("D:/modeltech64_10.7/win64/vsim.exe")
APPROVAL = Path("E:/juan/FPGA/learning/sc520-contour29/main-review/retime-software-implementation-approved.json")


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def artifact(path):
    return {"Path": str(path), "SHA256": sha(path), "Bytes": path.stat().st_size}


def save(path, value):
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write("\n")


def quote(path):
    return "{" + str(path).replace("\\", "/") + "}"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--test", required=True, choices=[
        "miter-fixtures", "miter-stress", "miter-boundary",
        "scene", "scenes", "lifecycle", "pairing", "render", "reset",
        "matrix", "fpsverify", "pipeline"])
    parser.add_argument("--smoke", action="store_true")
    parser.add_argument("--mutant-w0", action="store_true")
    parser.add_argument("--original-run", type=Path)
    args = parser.parse_args()
    assert not args.mutant_w0 or args.test.startswith("miter-")
    approval = json.loads(APPROVAL.read_text(encoding="utf-8-sig"))
    assert approval["Stage"] == "retime_software_implementation_approved"
    assert approval["Candidate"] == "D0291" and approval["TDAllowed"] is False
    assert Path(approval["AllowedNewScene"]).resolve() == NEW_SCENE.resolve()
    software = json.loads(SOFTWARE.read_text(encoding="utf-8-sig"))
    for row in software["SourceFreeze"]:
        assert sha(row["Path"]) == row["SHA256"], row["Path"]
    baseline = None
    if not args.test.startswith("miter-"):
        candidates = []
        for entry in software["Runs"]:
            row = entry["Run"]
            assert sha(row["Path"]) == row["SHA256"]
            report = json.loads(Path(row["Path"]).read_text(encoding="utf-8-sig"))
            if report["Test"] == args.test:
                candidates.append(Path(row["Path"]))
        selected = args.original_run.resolve() if args.original_run else candidates[0]
        assert selected in [Path(r["Run"]["Path"]).resolve() for r in software["Runs"]]
        baseline = json.loads(selected.read_text(encoding="utf-8-sig"))
        assert baseline["Test"] == args.test and baseline["Qualified"] and baseline["NativeExitCode"] == 0
    now = datetime.now(timezone(timedelta(hours=8)))
    name = args.test + ("-mutant-w0" if args.mutant_w0 else "-normal")
    run = REPO / "evidence/sc520-contour29-retime/runs" / (
        name + "-" + now.strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:6])
    snapshot = run / "inputs"
    snapshot.mkdir(parents=True, exist_ok=False)
    inputs = []

    def copy_input(path, folder="", name=None):
        path = Path(path)
        target = snapshot / folder / (name or path.name)
        assert not target.exists(), target
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(path.read_bytes())
        inputs.append({**artifact(path), "Snapshot": str(target), "SnapshotSHA256": sha(target)})
        return target

    runner_snapshot = copy_input(Path(__file__).resolve())
    copy_input(APPROVAL)
    copy_input(SOFTWARE)
    top = "tb_contour29_retime" if args.test.startswith("miter-") else "tb_contour29_" + args.test
    commands = []
    if args.test.startswith("miter-"):
        reference = copy_input(OLD_SCENE, "baseline")
        candidate = copy_input(NEW_SCENE, "candidate")
        classifier = copy_input(CLASSIFIER)
        tb = copy_input(TB)
        fixtures = REPO / "evidence/sc520-contour29/fixtures-v1"
        for path in sorted(fixtures.glob("*.mem")) + sorted(fixtures.glob("*-cases.txt")):
            copy_input(path)
        if args.mutant_w0:
            text = candidate.read_text(encoding="utf-8")
            for old, new in [
                ("P_CT_SEED_W0: state<=P_CT_SEED_W1;",
                 "P_CT_SEED_W0: begin ct_distinct_q<=ct_distinct;state<=P_CT_SEED_W1;end"),
                ("P_CT_SEED_W2: begin ct_distinct_q<=ct_distinct;state<=P_CT_SEED_CHECK;end",
                 "P_CT_SEED_W2: state<=P_CT_SEED_CHECK;"),
                ("P_CT_NW0: state<=P_CT_NW1;",
                 "P_CT_NW0: begin ct_edge_q<=ct_edge;state<=P_CT_NW1;end"),
                ("P_CT_NW2: begin ct_edge_q<=ct_edge;state<=P_CT_NCHECK;end",
                 "P_CT_NW2: state<=P_CT_NCHECK;"),
            ]:
                assert text.count(old) == 1
                text = text.replace(old, new)
            candidate.write_text(text, encoding="utf-8", newline="\n")
            for item in inputs:
                if item["Snapshot"] == str(candidate):
                    item["DerivedMutation"] = "Only test snapshot: sample both predicates prematurely at W0/NW0"
                    item["SnapshotSHA256"] = sha(candidate)
        commands += [
            "vlib baseline", "vmap baseline baseline", "vlib candidate", "vmap candidate candidate",
            f"vlog -work baseline {quote(classifier)} {quote(reference)}",
            f"vlog -work candidate {quote(classifier)} {quote(candidate)}",
            f"vlog -sv {quote(tb)}",
        ]
        suite = args.test.removeprefix("miter-")
        case_file = "smoke-cases.txt" if args.smoke else "all-cases.txt"
        commands.append(f"vsim -voptargs=+acc -wlf wave.wlf work.retime_config +ASSET_ROOT={snapshot.as_posix()} +CASE_FILE={case_file} +SUITE={suite}")
    else:
        copy_input(selected, "baseline-run")
        rtl = []
        tb_snapshot = None
        replacement_count = 0
        for item in baseline["Inputs"]:
            original = Path(item["Path"])
            assert sha(original) == item["SHA256"], original
            if original.resolve() == OLD_SCENE.resolve():
                original = NEW_SCENE
                replacement_count += 1
            target = copy_input(original)
            if target.name == top + ".sv":
                tb_snapshot = target
            elif target.suffix in (".v", ".sv"):
                rtl.append(target)
        assert replacement_count == 1 and tb_snapshot, "Exactly one scene replacement and original testbench required"
        for name in ("contour29-shapes.mem", "templates.mem", "anlogic_logo_index.mem", "anlogic_logo_palette.mem"):
            if (snapshot / name).exists():
                commands.append(f"file copy {quote(snapshot / name)} {name}")
        commands += [
            "set selected_sources [list " + " ".join(quote(p) for p in rtl) + "]",
            "vlog {*}$selected_sources",
            f"vlog -sv +incdir+{snapshot.as_posix()} {quote(tb_snapshot)}",
            f"vsim -voptargs=+acc -wlf wave.wlf work.{top} +ASSET_ROOT={snapshot.as_posix()} +CASE_FILE={'all-cases.txt' if args.test == 'scene' else 'cases.txt'} +INJECT_FAULT=0",
        ]
    (run / "modelsim.ini").write_bytes((SIMULATOR.parent.parent / "modelsim.ini").read_bytes())
    script = "\n".join([
        "onerror {quit -force -code 2}", "onbreak {resume}",
        "vlib work", "vmap work work", *commands, "onfinish stop", "run -all",
        f"set errors [examine -radix decimal /{top}/errors]",
        f"set checks [examine -radix decimal /{top}/checks]",
        f"set scenarios [examine -radix decimal /{top}/scenarios]",
        f"set done [examine -radix unsigned /{top}/test_done]",
        "set fd [open summary.json w]",
        'puts $fd [format {{"errors":%s,"checks":%s,"scenarios":%s,"done":%s}} $errors $checks $scenarios $done]',
        "close $fd", "if {!$done} {quit -force -code 2}",
        "if {$errors!=0} {quit -force -code 1}", "quit -force -code 0", "",
    ])
    (run / "run.do").write_text(script, encoding="utf-8")
    command = [str(SIMULATOR), "-modelsimini", str(run / "modelsim.ini"), "-c", "-l", "transcript.log", "-do", "source " + quote(run / "run.do")]
    report = dict(Task="sc520-contour29-retime", Candidate="D0291", Owner="Codex /root/contour29_reconcile",
                  Test=args.test, MutantW0=args.mutant_w0, Command=command, Inputs=inputs, StartedAt=now.isoformat(),
                  WorkingDirectory=str(run), Approval=artifact(APPROVAL), OriginalSoftware=artifact(SOFTWARE),
                  OriginalRun=artifact(selected) if baseline else None, TDAllowed=False,
                  BitGenerationAllowed=False, HardwareValidated=False)
    save(run / "run-start.json", report)
    start = time.monotonic()
    with (run / "stdout.log").open("xb") as stdout, (run / "stderr.log").open("xb") as stderr:
        process = subprocess.Popen(command, cwd=run, stdout=stdout, stderr=stderr, creationflags=subprocess.CREATE_NO_WINDOW)
        report["PID"] = process.pid
        print(json.dumps({"Run": str(run), "PID": process.pid}), flush=True)
        try:
            code = process.wait(timeout=1800)
        except subprocess.TimeoutExpired:
            subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], capture_output=True)
            code = process.wait()
            report["TimedOut"] = True
    summary = json.loads((run / "summary.json").read_text()) if (run / "summary.json").exists() else None
    unchanged = all(sha(i["Path"]) == i["SHA256"] and sha(i["Snapshot"]) == i["SnapshotSHA256"] for i in inputs)
    transcript = (run / "transcript.log").read_text(errors="replace") if (run / "transcript.log").exists() else ""
    warning_lines = [line for line in transcript.splitlines() if "** Warning:" in line]
    expected_negative = args.mutant_w0
    qualified = bool(summary and summary["done"] == 1 and summary["checks"] > 0 and summary["scenarios"] > 0
                     and unchanged and not report.get("TimedOut") and
                     (code == 1 and summary["errors"] > 0 and "FAIL" in transcript if expected_negative
                      else code == 0 and summary["errors"] == 0))
    report.update(NativeExitCode=code, Summary=summary, Qualified=qualified, InputsUnchanged=unchanged,
                  Warnings=warning_lines, ElapsedSeconds=time.monotonic()-start,
                  FinishedAt=datetime.now(timezone(timedelta(hours=8))).isoformat())
    report["Outputs"] = [artifact(p) for p in sorted(run.rglob("*")) if p.is_file() and
                         p.parent == run and p.suffix != ".wlf"]
    save(run / "run-manifest.json", report)
    print(json.dumps({"Run": str(run), "Qualified": qualified, "NativeExitCode": code, "Summary": summary}), flush=True)
    return 0 if qualified else 1


if __name__ == "__main__":
    raise SystemExit(main())
