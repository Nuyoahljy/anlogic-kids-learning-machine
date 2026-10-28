"""Generate one explicitly approved I0310R4C candidate in an exclusive b320 copy.

No route, placement, synthesis, debugger insertion, download, or Flash operation.
Requires exact --runner-sha, --manifest-sha, --route-result-sha, and --approval-sha from Root.
"""
import argparse
import hashlib
import json
import os
import re
import sys
import time
import traceback
from datetime import datetime, timedelta, timezone
from pathlib import Path

WORK = Path("E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-system-integration")
EV = WORK / "evidence/sc520-system-integration"
RUN = EV / "b320"
ROUTE = EV / "r320"
MANIFEST = EV / "j319/preparation-result.json"
APPROVAL = Path("E:/juan/FPGA/learning/sc520-system-integration/i0310r4c-bitgen-approved-20261028.json")
HELPER = WORK / "fpga/scripts/sc520-system-integration-i0303/owned_process.py"
TOOL = Path("D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe")
SELF = WORK / "fpga/scripts/sc520-system-integration-i0310-r4c/run-bitgen.py"
FIXED = {
    HELPER: "E7FFB6CC52723E251F51228F467CAF4561F94B58892D4FE9A044628AFADB6357",
    TOOL: "E2E04ADA5E256DCCD017240C0F4DCFACE7F96DCA67CDE0E56E606AC0E02F827A",
}
BUDGET = 600
BIT_NAMES = {"i0310r4c_candidate.bit", "i0310r4c_candidate_compress.bit"}


def stamp():
    return datetime.now(timezone(timedelta(hours=8))).isoformat()


def no_reparse(path):
    if not path.is_absolute():
        raise RuntimeError("Absolute path required")
    for part in [path] + list(path.parents):
        info = part.lstat()
        if part.is_symlink() or getattr(info, "st_file_attributes", 0) & 0x400:
            raise RuntimeError("Reparse path refused: " + str(part))


def identity(path, raw=None):
    no_reparse(path)
    data = path.read_bytes() if raw is None else raw
    return {"Path": path.as_posix(), "SHA256": hashlib.sha256(data).hexdigest().upper(), "Bytes": len(data)}


def checked(row):
    if (not isinstance(row, dict) or not isinstance(row.get("Path"), str)
            or not re.fullmatch(r"[0-9A-F]{64}", str(row.get("SHA256", "")))
            or type(row.get("Bytes")) is not int or row["Bytes"] < 0):
        raise RuntimeError("Invalid file binding")
    if identity(Path(row["Path"])) != row:
        raise RuntimeError("Input differs: " + row["Path"])
    return row


def exact(path, sha):
    if not re.fullmatch(r"[0-9A-Fa-f]{64}", sha):
        raise RuntimeError("Invalid exact hash")
    row = identity(path)
    if row["SHA256"] != sha.upper():
        raise RuntimeError("Exact hash differs: " + str(path))
    return row


def save(path, value):
    if path.parent != RUN:
        raise RuntimeError("Output outside b320")
    no_reparse(RUN)
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
    return identity(path)


def approve(document, manifest_row, route_row, runner_row):
    if (document.get("Operation") != "I0310R4C candidate bitgen once"
            or document.get("BitgenAllowed") is not True
            or document.get("HardwareActionsAllowed") is not False
            or document.get("OutputRoot") != RUN.as_posix()
            or document.get("Manifest") != manifest_row
            or document.get("RouteResult") != route_row
            or document.get("Runner") != runner_row):
        raise RuntimeError("Approval does not bind this exact candidate operation")


def launcher():
    root = RUN.as_posix()
    return ("\n".join([
        "proc i0310r4c_bitgen_once {} {",
        "cd {" + root + "}",
        "set channel [open {" + root + "/bitgen.started} {WRONLY CREAT EXCL}]",
        "puts $channel [pid]; close $channel",
        "foreach command {route opt_route route_clock place opt_place elaborate optimize_rtl optimize_gate pack clear_sdc read_sdc read_adc read_hdl insert_debugger setup_debugger import_chipprobe_config compile_probe launch_runs export_db} {",
        '  proc $command {args} {error "Outside I0310R4C candidate bitgen scope"}',
        "}",
        "import_device ph1_35p.db -package PH1P35MDG324 -speed 3",
        "open_project {" + root + "/camera_to_dsi_display.prj} -noanalyze",
        "cd {" + root + "}",
        "import_db {" + root + "/camera_to_dsi_display_route.db}",
        "commit_param -step bitgen",
        "bitgen -bit {" + root + "/i0310r4c_candidate.bit}",
        "export_bitgen_param -file {" + root + "/bitgen-parameters.txt}",
        "set channel [open {" + root + "/bitgen.finished} {WRONLY CREAT EXCL}]",
        "puts $channel I0310R4C_BITGEN_NATIVE_COMPLETE; close $channel",
        "}",
        "if {[catch {i0310r4c_bitgen_once} reason]} {puts stderr $reason; puts stderr $::errorInfo; exit 1}",
        "puts I0310R4C_BITGEN_NATIVE_COMPLETE",
        "exit 0", "",
    ])).encode("ascii")


def execute(args):
    if Path(__file__).resolve() != SELF or sys.platform != "win32" or sys.version_info[:2] != (3, 12):
        raise RuntimeError("Exact runner path and Windows CPython 3.12 required")
    runner_row = exact(SELF, args.runner_sha)
    manifest_row = exact(MANIFEST, args.manifest_sha)
    route_row = exact(ROUTE / "route-result.json", args.route_result_sha)
    approval_row = exact(APPROVAL, args.approval_sha)
    approve(json.loads(APPROVAL.read_bytes()), manifest_row, route_row, runner_row)
    fixed_rows = [exact(path, sha) for path, sha in FIXED.items()]
    manifest = json.loads(MANIFEST.read_bytes())
    route = json.loads((ROUTE / "route-result.json").read_bytes())
    timing = route.get("TimingObservation", {})
    if (route.get("Stage") != "route" or route.get("ExecutionComplete") is not True
            or route.get("Failure") or route.get("ChangedInputs")
            or timing.get("Confidence") != "Routed" or timing.get("Corners") != "Both"
            or timing.get("NonnegativeUnderCurrentConstraints") is not True
            or route.get("AreaObservation", {}).get("Fits") is not True
            or route.get("DebuggerMode") != "no-chip-debugger"):
        raise RuntimeError("r320 is not the reviewed completed candidate")
    if manifest.get("Version") != "I0310R4C" or manifest.get("Prepared") is not True:
        raise RuntimeError("Wrong prepared source manifest")
    output_rows = list(route["OutputFiles"].values())
    if any(Path(row["Path"]).parent != ROUTE / "td/pl_1" for row in output_rows):
        raise RuntimeError("Unexpected route output path")
    originals = [ROUTE / "td/pl_1" / name for name in ("camera_to_dsi_display_route.db", "camera_to_dsi_display.prj")]
    if any(identity(path) not in output_rows for path in originals) or identity(originals[0]) != route["Database"]:
        raise RuntimeError("Route DB/project is not bound by completed output")
    rows = manifest["Inputs"] + list(manifest["Files"].values()) + output_rows + fixed_rows + [manifest_row, runner_row, route_row, approval_row]
    unique = {}
    for row in rows:
        if row["Path"] in unique and row != unique[row["Path"]]:
            raise RuntimeError("Conflicting protected binding")
        unique[row["Path"]] = row
    rows = list(unique.values())
    for row in rows:
        checked(row)
    helper_raw = HELPER.read_bytes()
    if hashlib.sha256(helper_raw).hexdigest().upper() != FIXED[HELPER]:
        raise RuntimeError("Helper changed during read")
    helper = {"__name__": "i0310r4c_bitgen_owned_process", "__file__": HELPER.as_posix()}
    exec(compile(helper_raw, HELPER.as_posix(), "exec"), helper)
    no_reparse(EV)
    RUN.mkdir()  # Exclusive: failure artifacts and an earlier run are never reused.
    result = {"At": stamp(), "BitgenExecutionComplete": False, "Native": None,
              "Failure": None, "ChangedInputs": [], "OutputFiles": {}, "Bitstreams": [],
              "HardwareValidated": False, "Downloaded": False, "FlashWritten": False}
    try:
        for original in originals:
            copied = RUN / original.name
            with copied.open("xb") as stream:
                stream.write(original.read_bytes())
            row = identity(copied)
            if (row["SHA256"], row["Bytes"]) != (identity(original)["SHA256"], identity(original)["Bytes"]):
                raise RuntimeError("Copied input differs")
            rows.append(row)
        script = RUN / "bitgen.launch.tcl"
        with script.open("xb") as stream:
            stream.write(launcher())
        rows.append(identity(script))
        command = [TOOL.as_posix(), script.as_posix()]
        save(RUN / "bitgen-request.json", {"At": stamp(), "Approval": approval_row,
             "RouteResult": route_row, "Runner": runner_row, "Protected": rows,
             "Command": command, "Cwd": RUN.as_posix(), "BudgetSeconds": BUDGET})
        for row in rows:
            checked(row)
        with (RUN / "native.stdout.log").open("xb") as stdout, (RUN / "native.stderr.log").open("xb") as stderr:
            start = time.monotonic()
            native = helper["run_owned_process"](command, RUN, stdout, stderr, BUDGET,
                os.environ.copy(), lambda row: save(RUN / "native.started.json", row),
                on_created=lambda row: save(RUN / "native.created.json", row),
                wall_deadline=start + BUDGET)
            elapsed = time.monotonic() - start
        result["Native"] = native
        result["ObservedHelperSeconds"] = elapsed
        save(RUN / "native.process.json", native)
        if (native.get("NativeExit") != 0 or native.get("NaturalNativeExit") is not True
                or native.get("TreeCleanVerified") is not True or native.get("TimedOut") is not False
                or native.get("TerminationRequested") is not False or native.get("Error")
                or native.get("CleanupErrors") or native.get("FinalAccounting", {}).get("ActiveProcesses") != 0
                or not 0 <= elapsed < BUDGET):
            raise RuntimeError("Bitgen native lifecycle/deadline failed")
        log = (RUN / "native.stdout.log").read_text(encoding="utf-8", errors="replace")
        if ((RUN / "native.stderr.log").stat().st_size
                or re.search(r"(?m)^[A-Z]+-\d+\s+(?:ERROR|FATAL)\b", log)
                or "I0310R4C_BITGEN_NATIVE_COMPLETE" not in log.splitlines()
                or (RUN / "bitgen.finished").read_text(encoding="ascii").strip() != "I0310R4C_BITGEN_NATIVE_COMPLETE"):
            raise RuntimeError("Bitgen diagnostic/completion failed")
        for name in ("i0310r4c_candidate.bit", "bitgen-parameters.txt"):
            if not (RUN / name).is_file() or (RUN / name).stat().st_size == 0:
                raise RuntimeError("Missing nonempty candidate or parameter export")
        result["Bitstreams"] = [identity(path) for path in sorted(RUN.glob("*.bit"))]
        if any(Path(row["Path"]).name not in BIT_NAMES for row in result["Bitstreams"]):
            raise RuntimeError("Unexpected bitstream filename")
        result["BitgenExecutionComplete"] = True
    except BaseException as error:
        result["Failure"] = f"{type(error).__name__}: {error}"
        result["Traceback"] = traceback.format_exc()
    finally:
        for row in rows:
            try:
                checked(row)
            except BaseException as error:
                result["ChangedInputs"].append({"Path": row["Path"], "Error": str(error)})
        try:
            result["OutputFiles"] = {path.relative_to(RUN).as_posix(): identity(path) for path in sorted(RUN.rglob("*")) if path.is_file()}
        except BaseException as error:
            result["OutputInventoryError"] = str(error)
        if result["ChangedInputs"] or result["Failure"] or result.get("OutputInventoryError"):
            result["BitgenExecutionComplete"] = False
        result["CompletedAt"] = stamp()
        saved = save(RUN / "bitgen-result.json", result)
    print(json.dumps({"BitgenExecutionComplete": result["BitgenExecutionComplete"],
          "Failure": result["Failure"], "ChangedInputs": len(result["ChangedInputs"]), "Result": saved}))
    return 0 if result["BitgenExecutionComplete"] else 1


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runner-sha", required=True)
    parser.add_argument("--manifest-sha", required=True)
    parser.add_argument("--route-result-sha", required=True)
    parser.add_argument("--approval-sha", required=True)
    sys.exit(execute(parser.parse_args()))
