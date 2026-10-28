"""Generate one explicitly approved I0310R4C candidate in an exclusive b320 copy.

No route, placement, synthesis, debugger insertion, download, or Flash operation.
Requires exact --runner-sha, --manifest-sha, --route-result-sha, and --approval-sha from Root.
"""
import argparse
import hashlib
import json
import os
import ntpath
import stat
import struct
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
SELF = WORK / "fpga/scripts/sc520-system-integration-i0310-r4c/run-bitgen-v2.py"
FIXED = {
    HELPER: "E7FFB6CC52723E251F51228F467CAF4561F94B58892D4FE9A044628AFADB6357",
    TOOL: "E2E04ADA5E256DCCD017240C0F4DCFACE7F96DCA67CDE0E56E606AC0E02F827A",
}
BUDGET = 600
ROOT_CREATOR_ID = "local/01a18186-78f4-7101-93d9-0f77a7041af9"
ROOT_OWNER = "Codex /root " + ROOT_CREATOR_ID
BIT_NAMES = {"i0310r4c_candidate.bit", "i0310r4c_candidate_compress.bit"}


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def key(path):
    return ntpath.normcase(ntpath.normpath(str(path)))


def json_document(raw):
    def pairs(items):
        result = {}
        for name, value in items:
            require(name not in result, "Duplicate JSON field: " + name)
            result[name] = value
        return result

    def invalid(value):
        raise RuntimeError("Nonfinite JSON constant: " + value)

    result = json.loads(raw, object_pairs_hook=pairs, parse_constant=invalid)
    require(isinstance(result, dict), "Expected JSON object")
    return result


def validate_row(row):
    require(isinstance(row, dict) and set(row) == {"Path", "SHA256", "Bytes"}, "Invalid file binding")
    require(isinstance(row["Path"], str) and ntpath.isabs(row["Path"]) and
            re.fullmatch(r"[A-Za-z]:", ntpath.splitdrive(row["Path"])[0]) and
            ".." not in Path(row["Path"]).parts and ":" not in row["Path"][2:], "Aliased file binding")
    require(isinstance(row["SHA256"], str) and re.fullmatch(r"[0-9A-F]{64}", row["SHA256"]) and
            type(row["Bytes"]) is int and row["Bytes"] >= 0, "Invalid file binding")
    return row


def unique_rows(rows):
    result = {}
    for row in rows:
        validate_row(row)
        canonical = key(row["Path"])
        require(canonical not in result or result[canonical] == row, "Conflicting protected binding")
        result[canonical] = row
    return list(result.values())


def accepted_evidence(document):
    rows = document.get("AcceptedEvidence")
    require(isinstance(rows, list) and bool(rows), "Missing accepted physical evidence")
    unique = unique_rows(rows)
    require(len(unique) == len(rows), "Duplicate accepted physical evidence")
    for row in rows:
        require(row["Bytes"] > 0 and key(row["Path"]) != key(RUN) and
                not key(row["Path"]).startswith(key(RUN) + ntpath.sep),
                "Empty or circular b320 physical evidence")
    return unique


def native_clean(native, command, elapsed, events):
    require(isinstance(native, dict), "Missing native lifecycle")
    for field in ("RootCreated", "RootResumed", "JobAssignedBeforeResume", "JobMembershipVerified",
                  "ExpectedResumeVerified", "NaturalNativeExit", "TreeCleanVerified"):
        require(native.get(field) is True, "Unqualified native lifecycle: " + field)
    require(type(native.get("NativeExit")) is int and native["NativeExit"] == 0 and
            native.get("TimedOut") is False and native.get("TerminationRequested") is False and
            "Error" in native and native["Error"] is None and native.get("CleanupErrors") == [] and
            native.get("StdioUnclosedHandles") == [], "Bitgen native lifecycle failed")
    require(native.get("Command") == command and key(native.get("Cwd", "")) == key(RUN) and
            type(native.get("PID")) is int and native["PID"] > 0 and
            type(native.get("CreationFileTime100ns")) is int and native["CreationFileTime100ns"] > 0,
            "Bitgen native identity differs")
    require(type(native.get("FinalAccounting", {}).get("ActiveProcesses")) is int and
            native["FinalAccounting"]["ActiveProcesses"] == 0 and
            type(elapsed) in (int, float) and 0 <= elapsed < BUDGET and
            events == {"created": 1, "started": 1}, "Bitgen native deadline/publication failed")


def output_bits(native):
    log = (RUN / "native.stdout.log").read_text(encoding="utf-8", errors="strict")
    require((RUN / "native.stderr.log").stat().st_size == 0 and
            not re.search(r"(?im)^\s*(?:[A-Z][A-Z0-9_]*-\d+\s+)?(?:ERROR|FATAL|SEVERE)\b|"
                          r"\b(?:ERROR|FATAL|SEVERE)\s*:", log) and
            "I0310R4C_BITGEN_NATIVE_COMPLETE" in log.splitlines() and
            (RUN / "bitgen.finished").read_text(encoding="ascii").strip() == "I0310R4C_BITGEN_NATIVE_COMPLETE",
            "Bitgen diagnostic/completion failed")
    require((RUN / "bitgen.started").read_text(encoding="ascii").strip() == str(native["PID"]),
            "Bitgen marker PID differs")
    for name in ("i0310r4c_candidate.bit", "bitgen-parameters.txt"):
        require((RUN / name).is_file() and (RUN / name).stat().st_size > 0,
                "Missing nonempty candidate or parameter export")
    bits = [identity(path) for path in sorted(RUN.rglob("*")) if path.suffix.lower() == ".bit"]
    require(all(Path(row["Path"]).parent == RUN and Path(row["Path"]).name in BIT_NAMES and
                row["Bytes"] > 0 for row in bits), "Unexpected or empty bitstream")
    return bits


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
    info = path.lstat()
    require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1, "Nonregular or hard-linked input/output")
    data = path.read_bytes() if raw is None else raw
    return {"Path": path.as_posix(), "SHA256": hashlib.sha256(data).hexdigest().upper(), "Bytes": len(data)}


def checked(row):
    validate_row(row)
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
        json.dump(value, stream, ensure_ascii=False, indent=2, allow_nan=False)
        stream.write("\n")
    return identity(path)


def approve(document, manifest_row, route_row, runner_row):
    if (document.get("Operation") != "I0310R4C candidate bitgen once"
            or document.get("BitgenAllowed") is not True
            or document.get("HardwareActionsAllowed") is not False
            or document.get("OutputRoot") != RUN.as_posix()
            or document.get("Manifest") != manifest_row
            or document.get("RouteResult") != route_row
            or document.get("Runner") != runner_row
            or document.get("RootCreatorID") != ROOT_CREATOR_ID
            or document.get("RootReviewedCode") is not True
            or document.get("RootAcceptedPhysicalEvidence") is not True
            or type(document.get("BudgetSeconds")) is not int or document["BudgetSeconds"] != BUDGET):
        raise RuntimeError("Approval does not bind this exact candidate operation")
    return accepted_evidence(document)


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
    if (Path(__file__).absolute() != SELF or sys.platform != "win32" or sys.version_info[:2] != (3, 12)
            or sys.implementation.name != "cpython" or struct.calcsize("P") != 8):
        raise RuntimeError("Exact runner path and Windows CPython 3.12 required")
    runner_row = exact(SELF, args.runner_sha)
    manifest_row = exact(MANIFEST, args.manifest_sha)
    route_row = exact(ROUTE / "route-result.json", args.route_result_sha)
    approval_row = exact(APPROVAL, args.approval_sha)
    approval = json_document(APPROVAL.read_bytes())
    evidence = approve(approval, manifest_row, route_row, runner_row)
    fixed_rows = [exact(path, sha) for path, sha in FIXED.items()]
    manifest = json_document(MANIFEST.read_bytes())
    route = json_document((ROUTE / "route-result.json").read_bytes())
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
    require(approval.get("Database") == route.get("Database"), "Approval database differs")
    output_rows = list(route["OutputFiles"].values())
    if any(Path(row["Path"]).parent != ROUTE / "td/pl_1" for row in output_rows):
        raise RuntimeError("Unexpected route output path")
    originals = [ROUTE / "td/pl_1" / name for name in ("camera_to_dsi_display_route.db", "camera_to_dsi_display.prj")]
    if any(identity(path) not in output_rows for path in originals) or identity(originals[0]) != route["Database"]:
        raise RuntimeError("Route DB/project is not bound by completed output")
    rows = manifest["Inputs"] + list(manifest["Files"].values()) + output_rows + fixed_rows + [manifest_row, runner_row, route_row, approval_row] + evidence
    rows = unique_rows(rows)
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
              "HardwareValidated": False, "Downloaded": False, "FlashWritten": False,
              "Owner": ROOT_OWNER, "RootCreatorID": ROOT_CREATOR_ID,
              "Approval": approval_row, "Runner": runner_row, "Manifest": manifest_row,
              "RouteResult": route_row, "Database": route["Database"], "AcceptedEvidence": evidence,
              "InputsBefore": rows.copy(), "InputsAfter": []}
    events = {"created": 0, "started": 0}

    def publish(name, row):
        events[name] += 1
        require(events[name] == 1, "Duplicate native publication")
        save(RUN / ("native." + name + ".json"),
             {**row, "Owner": ROOT_OWNER, "RootCreatorID": ROOT_CREATOR_ID})
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
        request_row = save(RUN / "bitgen-request.json", {"At": stamp(), "Approval": approval_row,
             "Owner": ROOT_OWNER, "RootCreatorID": ROOT_CREATOR_ID, "AcceptedEvidence": evidence,
             "Database": route["Database"],
             "RouteResult": route_row, "Runner": runner_row, "Protected": rows,
             "Command": command, "Cwd": RUN.as_posix(), "BudgetSeconds": BUDGET})
        rows.append(request_row)
        result["InputsBefore"] = rows.copy()
        result["Command"] = command
        result["Cwd"] = RUN.as_posix()
        result["BudgetSeconds"] = BUDGET
        for row in rows:
            checked(row)
        with (RUN / "native.stdout.log").open("xb") as stdout, (RUN / "native.stderr.log").open("xb") as stderr:
            start = time.monotonic()
            native = helper["run_owned_process"](command, RUN, stdout, stderr, BUDGET,
                os.environ.copy(), lambda row: publish("started", row),
                on_created=lambda row: publish("created", row),
                wall_deadline=start + BUDGET)
            elapsed = time.monotonic() - start
        result["Native"] = native
        result["ObservedHelperSeconds"] = elapsed
        save(RUN / "native.process.json", {**native, "Owner": ROOT_OWNER, "RootCreatorID": ROOT_CREATOR_ID})
        native_clean(native, command, elapsed, events)
        result["Bitstreams"] = output_bits(native)
        result["BitgenExecutionComplete"] = True
    except BaseException as error:
        result["Failure"] = f"{type(error).__name__}: {error}"
        result["Traceback"] = traceback.format_exc()
    finally:
        for row in rows:
            try:
                checked(row)
                result["InputsAfter"].append(identity(Path(row["Path"])))
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
