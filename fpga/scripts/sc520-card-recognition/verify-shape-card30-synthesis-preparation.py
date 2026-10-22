"""Verify the prepared wrapper with ModelSim only; TD is never invoked."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[3]
PREP = ROOT / "evidence/sc520-shape-card30/synthesis-prepared-20261022-1255-v4"
VSIM = Path("D:/modeltech64_10.7/win64/vsim.exe")


def artifact(path):
    path = Path(path)
    return dict(Path=str(path), SHA256=hashlib.sha256(path.read_bytes()).hexdigest().upper(), Bytes=path.stat().st_size)


def main():
    if not __debug__:
        raise RuntimeError("Source checks cannot be disabled")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--negative", action="store_true")
    args = parser.parse_args()
    OUT = ROOT / ("evidence/sc520-shape-card30/synthesis-wrapper-test-20261022-1255-v4-final-"
                  + ("negative" if args.negative else "normal"))
    expected_errors = int(args.negative)
    expected_checks = 15181 + expected_errors
    preparation = json.loads((PREP / "preparation.json").read_text(encoding="utf-8"))
    for row in preparation["PreparedFiles"]:
        assert artifact(row["Path"]) == row
    OUT.mkdir(exist_ok=False)
    copies = []
    program = artifact(__file__)
    shutil.copyfile(Path(__file__), OUT / Path(__file__).name)
    for row in preparation["PreparedFiles"]:
        source = Path(row["Path"])
        target = OUT / source.name
        shutil.copyfile(source, target)
        copies.append(dict(Source=row, Snapshot=artifact(target)))
    tb = ROOT / "fpga/sim/sc520-shape-card30/tb_shape_card30_synthesis_wrapper.sv"
    shutil.copyfile(tb, OUT / tb.name)
    copies.append(dict(Source=artifact(tb), Snapshot=artifact(OUT / tb.name)))
    shutil.copyfile(VSIM.parent.parent / "modelsim.ini", OUT / "modelsim.ini")
    sources = [Path(row["Source"]["Path"]).name for row in preparation["SourceCopies"] if Path(row["Source"]["Path"]).suffix == ".v"]
    top = "tb_shape_card30_synthesis_wrapper"
    script = "\n".join([
        "onerror {quit -force -code 2}", "onbreak {resume}", "vlib work", "vmap work work",
        "vlog +incdir+. " + " ".join("{" + name + "}" for name in sources),
        f"vlog -sv {{{tb.name}}}", f"vsim -voptargs=+acc work.{top} +INJECT_FAULT={expected_errors}",
        "onfinish stop", "run -all",
        f"set errors [examine -radix decimal /{top}/errors]",
        f"set checks [examine -radix decimal /{top}/checks]",
        f"set scenarios [examine -radix decimal /{top}/scenarios]",
        f"set done [examine -radix unsigned /{top}/test_done]",
        "set fd [open summary.json w]",
        'puts $fd [format {{"errors":%s,"checks":%s,"scenarios":%s,"done":%s}} $errors $checks $scenarios $done]',
        "close $fd",
        f"if {{$errors!={expected_errors} || $checks!={expected_checks} || $scenarios!=1 || !$done}} {{quit -force -code 2}}",
        f"quit -force -code {expected_errors}", "",
    ])
    (OUT / "run.do").write_text(script, encoding="ascii")
    command = [str(VSIM), "-modelsimini", str(OUT / "modelsim.ini"), "-c", "-l", "transcript.log",
               "-do", "source {" + (OUT / "run.do").as_posix() + "}"]
    tool = artifact(VSIM)
    with (OUT / "stdout.log").open("xb") as stdout, (OUT / "stderr.log").open("xb") as stderr:
        code = subprocess.run(command, cwd=OUT, stdout=stdout, stderr=stderr,
                              creationflags=subprocess.CREATE_NO_WINDOW).returncode
    summary = json.loads((OUT / "summary.json").read_text()) if (OUT / "summary.json").is_file() else None
    unchanged = all(artifact(row["Source"]["Path"]) == row["Source"] and
                    artifact(row["Snapshot"]["Path"]) == row["Snapshot"] for row in copies)
    qualified = (code == expected_errors and unchanged and artifact(VSIM) == tool
                 and artifact(__file__) == program
                 and summary == dict(errors=expected_errors, checks=expected_checks, scenarios=1, done=1))
    report = dict(Candidate="D0300", Owner="Codex /root/shape30_detector_finish", Preparation=artifact(PREP / "preparation.json"),
                  Program=program, ProgramUnchanged=artifact(__file__)==program,
                  Tool=tool, Command=command, NativeExitCode=code, Summary=summary, SourceCopies=copies,
                  ToolUnchanged=artifact(VSIM) == tool, InputsUnchanged=unchanged, Qualified=qualified,
                  NegativeChecker=args.negative, ExpectedNativeExitCode=expected_errors,
                  Scope="Plain-Verilog full pipeline RENDER_ENABLE1/ROTATION_VARIANTS256; all225 input bits walking1/walking0, four-chunk preservation/hold/reset; all349 literal outputs walking1/walking0 through every six uncompressed64bit phase chunks",
                  TDStarted=False, SynthesisAllowed=False, RouteAllowed=False, BitgenAllowed=False)
    (OUT / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(dict(Run=str(OUT), Qualified=qualified, NativeExitCode=code, Summary=summary)))
    return 0 if qualified else 1


if __name__ == "__main__":
    raise SystemExit(main())
