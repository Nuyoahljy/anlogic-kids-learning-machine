"""CLI rejection and fully stubbed exception-control-flow tests, never invoke TD."""
from pathlib import Path
from unittest.mock import patch
import importlib.util
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
PROGRAM = Path(__file__).with_name("execute-shape-card30-synthesis.py")
OUT = ROOT / "evidence/sc520-shape-card30/synthesis-executor-preflight-20261022-1255-v4"


def main():
    OUT.mkdir(exist_ok=False)
    spec = importlib.util.spec_from_file_location("shape30_executor_preflight", PROGRAM)
    executor = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(executor)
    prefix = [sys.executable, "-B", "-X", "utf8", str(PROGRAM)]
    approval = Path("E:/juan/FPGA/learning/sc520-shape-card30/rtl-implementation-approved.json")
    correct_sha = executor.artifact(approval)["SHA256"]
    cases = [
        ("help", prefix + ["--help"], 0),
        ("verify-prepared", prefix + ["--verify-prepared"], 0),
        ("wrong-stage", prefix + ["--approval", str(approval), "--approval-sha", correct_sha], 1),
        ("wrong-sha", prefix + ["--approval", str(approval), "--approval-sha", "0" * 64], 1),
        ("optimized", [sys.executable, "-O", str(PROGRAM), "--verify-prepared"], 1),
    ]
    before = [executor.artifact(p) for p in sorted(executor.PREP.iterdir()) if p.is_file()]
    cli = []
    for name, command, expected in cases:
        process = subprocess.run(command, capture_output=True, text=True, encoding="utf-8")
        assert process.returncode == expected, (name, process.returncode)
        (OUT / (name + ".stdout.txt")).write_text(process.stdout, encoding="utf-8")
        (OUT / (name + ".stderr.txt")).write_text(process.stderr, encoding="utf-8")
        cli.append(dict(Name=name, Command=command, ExitCode=process.returncode))
    assert before == [executor.artifact(p) for p in sorted(executor.PREP.iterdir()) if p.is_file()]
    simulated = []
    for case in ("spawn-fail", "wait-live", "wait-exited", "poll-fail", "input-missing", "tool-missing", "output-missing"):
        folder = OUT / case
        folder.mkdir()
        bindings = {name: dict(Path=str(folder / (name + ".bound")), SHA256="SIMULATED", Bytes=1)
                    for name in ("Program", "Preparation", "SoftwareFreeze", "MainSoftwareReview",
                                 "IndependentSoftwareReview", "WrapperVerification", "IndependentPreparationReview", "Tool")}
        # Every cryptographic/input/process/git result below is simulated.
        dummy = dict(Path=str(folder / "input.bound"), SHA256="SIMULATED", Bytes=1)
        freeze = dict(CompileOrder=[], AssetsAndContract=[], Testbenches=[], Tools=[], SharedVerificationReference=dummy)
        prep = dict(SourceFreeze=bindings["SoftwareFreeze"], SourceCopies=[dict(Source=dummy, Snapshot=dummy)],
                    PreparedFiles=[])
        approved = dict(Stage="synth_only_approved", Candidate="D0300", SynthesisAllowed=True,
                        RouteAllowed=False, BitgenAllowed=False, HardwareAllowed=False, SourceCommit="SIMULATED", **bindings)
        calls = []
        records = {}
        validation_phase = False

        def fake_artifact(path):
            nonlocal validation_phase
            path = Path(path)
            if validation_phase and (case == "tool-missing" and path == executor.TOOL or
                                     case == "output-missing" and path.name == "gone.out"):
                raise FileNotFoundError("simulated disappeared artifact")
            for value in bindings.values():
                if str(path) == value["Path"]:
                    return value
            if path == PROGRAM:
                return bindings["Program"]
            if path == executor.TOOL:
                return bindings["Tool"]
            if path.name == "preparation.json":
                return bindings["Preparation"]
            return dict(Path=str(path), SHA256="SIMULATED", Bytes=1)

        def fake_check(row):
            if validation_phase and case == "input-missing":
                raise FileNotFoundError("simulated missing frozen input")
            return row

        def fake_read(path):
            if Path(path).name == "approval.json":
                return approved
            if str(path) == bindings["WrapperVerification"]["Path"]:
                return dict(Qualified=True, InputsUnchanged=True, ToolUnchanged=True, Preparation=bindings["Preparation"])
            if str(path) == bindings["SoftwareFreeze"]["Path"]:
                return freeze
            raise RuntimeError("Unexpected simulated read")

        def fake_save(path, value):
            nonlocal validation_phase
            records[Path(path).name] = json.loads(json.dumps(value))
            if Path(path).name == "process.json":
                validation_phase = True

        class FakeProcess:
            pid = 900001
            returncode = None

            def wait(self):
                if case == "wait-live":
                    raise RuntimeError("simulated wait error, still running")
                self.returncode = 0
                if case == "wait-exited":
                    raise RuntimeError("simulated wait error, exited")
                return 0

            def poll(self):
                if case == "poll-fail":
                    raise OSError("simulated poll unavailable")
                return self.returncode

        def fake_popen(*args, **kwargs):
            calls.append("simulated-Popen")
            if case == "spawn-fail":
                raise OSError("simulated spawn failure")
            if case == "output-missing":
                (folder / "gone.out").write_text("simulated", encoding="ascii")
            return FakeProcess()

        def fake_output(command, **kwargs):
            if command[0] == "git":
                if "rev-parse" in command:
                    return "SIMULATED\n"
                if "branch" in command:
                    return "task/sc520-color-integration\n"
            return ""

        with patch.object(executor, "PREP", folder), patch.object(executor, "artifact", fake_artifact), \
             patch.object(executor, "read", fake_read), patch.object(executor, "check", fake_check), \
             patch.object(executor, "save", fake_save), patch.object(executor, "verify_prepared", lambda: (prep, freeze)), \
             patch.object(executor.subprocess, "Popen", fake_popen), \
             patch.object(executor.subprocess, "check_output", fake_output), \
             patch.object(sys, "argv", [str(PROGRAM), "--approval", str(folder / "approval.json"), "--approval-sha", "SIMULATED"]):
            status = executor.main()
        assert status == 1 and "result.json" in records
        result = records["result.json"]
        assert not result["SynthesisCompleted"]
        if case in ("wait-live", "poll-fail"):
            assert result["LiveNativePreserved"] and "FinishedAt" not in result["Native"]
        if case == "spawn-fail":
            assert result["Native"]["PID"] is None and "FinishedAt" not in result["Native"]
        if case in ("input-missing", "tool-missing", "output-missing", "poll-fail"):
            assert result["ValidationErrors"]
        simulated.append(dict(Name=case, Simulated=True, FakePID=900001, Calls=calls, Records=records))
    report = dict(Program=executor.artifact(PROGRAM), TestProgram=executor.artifact(__file__),
                  CLI=cli, CLIInputsUnchanged=True, SimulatedExceptionCases=simulated,
                  AllPassed=True, Scope="Actual CLI rejection/prepared verification; exception crypto/input/git/Popen fully stubbed.",
                  TDStarted=False, SubstInvoked=False, SynthesisAllowed=False)
    (OUT / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(dict(Run=str(OUT), CLITests=len(cli), SimulatedExceptionTests=len(simulated), AllPassed=True)))


if __name__ == "__main__":
    main()
