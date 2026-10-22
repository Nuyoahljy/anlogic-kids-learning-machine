"""Execute exactly one separately approved T030 module synthesis; never place/route/bit."""
from datetime import datetime, timezone, timedelta
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
PREP = ROOT / "evidence/sc520-shape-card30/synthesis-prepared-20261022-1255-v4"
TOOL = Path("D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe")
TOOL_SHA = "E2E04ADA5E256DCCD017240C0F4DCFACE7F96DCA67CDE0E56E606AC0E02F827A"


def now():
    return datetime.now(timezone(timedelta(hours=8))).isoformat()


def artifact(path):
    path = Path(path).resolve(strict=True)
    return dict(Path=str(path), SHA256=hashlib.sha256(path.read_bytes()).hexdigest().upper(),
                Bytes=path.stat().st_size)


def check(row):
    current = artifact(row["Path"])
    if current["SHA256"] != row["SHA256"] or current["Bytes"] != row["Bytes"]:
        raise RuntimeError("Changed bound input: " + row["Path"])
    return current


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def save(path, value):
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write("\n")


def verify_prepared():
    prep = read(PREP / "preparation.json")
    if prep["Stage"] != "synthesis_prepared_no_execution_permission" or prep["TDStarted"]:
        raise RuntimeError("Not an untouched T030 preparation")
    if prep["SynthesisAllowed"] or prep["RouteAllowed"] or prep["BitgenAllowed"]:
        raise RuntimeError("Preparation cannot authorize execution")
    for row in prep["PreparedFiles"]:
        check(row)
    for pair in prep["SourceCopies"]:
        check(pair["Source"])
        check(pair["Snapshot"])
    check(prep["SourceFreeze"])
    freeze = read(prep["SourceFreeze"]["Path"])
    for row in freeze["CompileOrder"] + freeze["AssetsAndContract"] + freeze["Testbenches"] + freeze["Tools"] + [freeze["SharedVerificationReference"]]:
        check(row)
    if artifact(TOOL)["SHA256"] != TOOL_SHA or artifact(TOOL) != prep["Tool"]:
        raise RuntimeError("Only the bound TD6.2.1 executable is allowed")
    if list(PREP.glob("*.bit")) or list(PREP.glob("*.db")):
        raise RuntimeError("Do not reuse a preparation with generated artifacts")
    return prep, freeze


def main():
    if sys.flags.optimize:
        raise RuntimeError("Do not disable source checks")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify-prepared", action="store_true")
    parser.add_argument("--approval", type=Path)
    parser.add_argument("--approval-sha")
    args = parser.parse_args()
    if args.verify_prepared:
        verify_prepared()
        print("T030_PREPARED_INPUTS_VERIFIED_NO_TD")
        return 0
    if not args.approval or not args.approval_sha:
        parser.error("Execution needs a separate approval and exact approval SHA")
    if artifact(args.approval)["SHA256"] != args.approval_sha.upper():
        raise RuntimeError("Approval SHA does not match")
    approved = read(args.approval)
    if approved.get("Stage") != "synth_only_approved" or approved.get("Candidate") != "D0300":
        raise RuntimeError("D090 implementation and software-only approvals do not permit synthesis")
    if approved.get("SynthesisAllowed") is not True or any(
            approved.get(name) is not False for name in ("RouteAllowed", "BitgenAllowed", "HardwareAllowed")):
        raise RuntimeError("Separate synthesis-only approval required")
    for name in ("Program", "Preparation", "SoftwareFreeze", "MainSoftwareReview",
                 "IndependentSoftwareReview", "WrapperVerification", "IndependentPreparationReview", "Tool"):
        if name not in approved:
            raise RuntimeError("Missing approval binding: " + name)
        check(approved[name])
    if approved["Program"] != artifact(__file__) or approved["Tool"] != artifact(TOOL):
        raise RuntimeError("Approval must bind this exact executor/tool")
    if approved["Preparation"] != artifact(PREP / "preparation.json"):
        raise RuntimeError("Approval must bind the exact prepared directory")
    if any((PREP / name).exists() for name in ("started.json", "result.json", "native.json")):
        raise RuntimeError("Never execute a previous attempt again")
    prep, freeze = verify_prepared()
    if approved["SoftwareFreeze"] != prep["SourceFreeze"]:
        raise RuntimeError("Wrong software source freeze")
    wrapper_report = read(approved["WrapperVerification"]["Path"])
    if not wrapper_report["Qualified"] or not wrapper_report["InputsUnchanged"] or not wrapper_report["ToolUnchanged"]:
        raise RuntimeError("Wrapper simulation is not qualified")
    if wrapper_report["Preparation"] != approved["Preparation"]:
        raise RuntimeError("Wrapper verification used a different preparation")
    commit = approved.get("SourceCommit")
    if not commit or subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip() != commit:
        raise RuntimeError("Current HEAD must be the separately accepted source checkpoint")
    if subprocess.check_output(["git", "-C", str(ROOT), "branch", "--show-current"], text=True).strip() != "task/sc520-color-integration":
        raise RuntimeError("Wrong source branch")
    for row in freeze["CompileOrder"] + freeze["AssetsAndContract"]:
        relative = Path(row["Path"]).relative_to(ROOT).as_posix()
        blob = subprocess.check_output(["git", "-C", str(ROOT), "show", commit + ":" + relative])
        if hashlib.sha256(blob).hexdigest().upper() != row["SHA256"]:
            raise RuntimeError("Committed input is not the frozen source: " + relative)
    active = subprocess.check_output(["powershell.exe", "-NoProfile", "-Command",
        "@(Get-CimInstance Win32_Process | Where-Object {$_.Name -match '^td.*\\.exe$' -and $_.Name -ne 'td.exe'}) | ForEach-Object {$_.ProcessId}"],
        text=True).strip()
    if active:
        raise RuntimeError("A TD console is already active; ownership review required")
    started = now()
    command = [TOOL.as_posix(), (PREP / "synthesis-only.tcl").as_posix()]
    report = dict(Candidate="D0300", Owner="Codex /root/shape30_detector_finish",
                  Approval=artifact(args.approval), Preparation=approved["Preparation"],
                  SourceCommit=commit, Tool=artifact(TOOL), Program=artifact(__file__),
                  StartedAt=started, ParentPID=os.getpid(), Command=command, WorkingDirectory=str(PREP),
                  RouteAllowed=False, BitgenAllowed=False, HardwareValidated=False)
    process = None
    code = None
    save(PREP / "started.json", report)
    try:
        with (PREP / "stdout.log").open("xb") as stdout, (PREP / "stderr.log").open("xb") as stderr:
            process = subprocess.Popen(command, cwd=PREP, stdout=stdout, stderr=stderr,
                                       creationflags=subprocess.CREATE_NO_WINDOW)
            save(PREP / "process.json", dict(PID=process.pid, ParentPID=os.getpid(), CreatedObservedAt=now(), Command=command))
            print(json.dumps(dict(Run=str(PREP), PID=process.pid)), flush=True)
            code = process.wait()
    except BaseException as error:
        report["ExecutionError"] = dict(Type=type(error).__name__, Message=str(error))
    finally:
        native = dict(StartedAt=started, PID=process.pid if process is not None else None)
        validation_errors = []
        live = process is not None
        if process is not None:
            try:
                live = process.poll() is None
            except BaseException as error:
                validation_errors.append(dict(Check="NativePoll", Type=type(error).__name__, Message=str(error)))
        if process is not None and not live:
            code = process.returncode
            native.update(FinishedAt=now(), ExitCode=code)
            if not (PREP / "native.json").exists():
                try:
                    save(PREP / "native.json", native)
                except OSError as error:
                    validation_errors.append(dict(Check="NativeRecord", Type=type(error).__name__, Message=str(error)))
        report["LiveNativePreserved"] = live
        changed = []
        rows = prep["PreparedFiles"] + [row for pair in prep["SourceCopies"] for row in (pair["Source"], pair["Snapshot"])]
        rows += freeze["CompileOrder"] + freeze["AssetsAndContract"] + freeze["Testbenches"] + freeze["Tools"] + [freeze["SharedVerificationReference"]]
        rows += [approved[name] for name in ("Program", "Preparation", "SoftwareFreeze", "MainSoftwareReview",
                                           "IndependentSoftwareReview", "WrapperVerification", "IndependentPreparationReview", "Tool")]
        for row in rows:
            try:
                check(row)
            except (OSError, RuntimeError) as error:
                changed.append(row["Path"])
                validation_errors.append(dict(Check="BoundInput", Path=row["Path"], Type=type(error).__name__, Message=str(error)))
        database = PREP / "shape30_gate.db"
        marker = PREP / "synthesis.complete"
        stdout_file = PREP / "stdout.log"
        start_seconds = datetime.fromisoformat(started).timestamp()
        def inspect(label, action, default):
            try:
                return action()
            except (OSError, RuntimeError, ValueError) as error:
                validation_errors.append(dict(Check=label, Type=type(error).__name__, Message=str(error)))
                return default
        completed_token = inspect("StdoutToken", lambda:
            "SHAPE30_SYNTHESIS_COMPLETED" in stdout_file.read_text(errors="replace").splitlines(), False)
        gate_artifact = inspect("GateDatabase", lambda: artifact(database), None)
        gate_fresh = inspect("GateFresh", lambda: database.stat().st_size > 0 and database.stat().st_mtime >= start_seconds, False)
        marker_artifact = inspect("CompletionMarker", lambda: artifact(marker), None)
        marker_fresh = inspect("MarkerFresh", lambda: marker.stat().st_mtime >= start_seconds, False)
        marker_token = inspect("MarkerToken", lambda: marker.read_text(encoding="ascii").strip() == "SHAPE30_SYNTHESIS_COMPLETED", False)
        forbidden = inspect("BitInventory", lambda: [str(path) for path in PREP.rglob("*.bit")], ["inventory-unavailable"])
        tool_unchanged = inspect("ToolUnchanged", lambda: artifact(TOOL) == report["Tool"], False)
        report.update(Native=native, ChangedInputs=sorted(set(changed)), ToolUnchanged=tool_unchanged,
                      CompletedToken=completed_token, GateFresh=gate_fresh, MarkerFresh=marker_fresh, MarkerToken=marker_token,
                      GateDatabase=gate_artifact, CompletionMarker=marker_artifact, BitFilesFound=forbidden,
                      SynthesisCompleted=code == 0 and not live and "ExecutionError" not in report and
                      completed_token and gate_fresh and marker_fresh and marker_token and
                      not changed and not forbidden and tool_unchanged and not validation_errors)
        report["Outputs"] = []
        paths = inspect("OutputInventory", lambda: sorted(PREP.iterdir()), [])
        for path in paths:
            if path.is_file():
                value = inspect("OutputArtifact:" + str(path), lambda path=path: artifact(path), None)
                if value is not None:
                    report["Outputs"].append(value)
        report["ValidationErrors"] = validation_errors
        if validation_errors:
            report["SynthesisCompleted"] = False
        save(PREP / "result.json", report)
    print(json.dumps(dict(Run=str(PREP), NativeExitCode=code, LiveNativePreserved=live, SynthesisCompleted=report["SynthesisCompleted"])))
    return 0 if report["SynthesisCompleted"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
