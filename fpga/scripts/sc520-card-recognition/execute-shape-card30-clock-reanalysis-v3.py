"""Run one separately approved read-only clock analysis, never synthesize/export DB."""
from datetime import datetime, timezone, timedelta
from decimal import Decimal, InvalidOperation
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tkinter
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[3]
PREP = ROOT / "evidence/sc520-shape-card30/clock-reanalysis-prepared-20261022-1610-v3"
TOOL = Path("D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe")
TOOL_SHA = "E2E04ADA5E256DCCD017240C0F4DCFACE7F96DCA67CDE0E56E606AC0E02F827A"
BINDINGS = ("Program", "Preparation", "IndependentPreparationReview", "MainSynthesisApproval", "NativeSynthesisResult", "PriorClockAnalysis", "SoftwareFreeze", "Tool")
EXPECTED_PERIODS = {"MIPI_RX_BYTE_CLK": Decimal("9.660"), "HDMI_PIXEL_CLK": Decimal("13.468")}
EXPECTED_QUERIES = {
    "capture_port": ("ports", ["capture_clk"]),
    "display_port": ("ports", ["display_clk"]),
    "capture_clock": ("clocks", ["MIPI_RX_BYTE_CLK"]),
    "display_clock": ("clocks", ["HDMI_PIXEL_CLK"]),
    "all_clocks": ("clocks", sorted(EXPECTED_PERIODS)),
}


def now():
    return datetime.now(timezone(timedelta(hours=8))).isoformat()


def artifact(path):
    path = Path(path).resolve(strict=True)
    return dict(Path=str(path), SHA256=hashlib.sha256(path.read_bytes()).hexdigest().upper(), Bytes=path.stat().st_size)


def check(row):
    current = artifact(row["Path"])
    if current != row:
        raise RuntimeError("Changed input: " + row["Path"])
    return current


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def save(path, value):
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write("\n")


def protected_rows(prep):
    return prep["PreparedFiles"] + prep["OriginalHistory"] + prep["FrozenInputs"] + prep["References"] + [
        prep[name] for name in ("Program", "Executor", "OriginalDatabase", "DatabaseCopy", "NativeSynthesisResult", "PriorClockAnalysis", "FrozenGateNetlist", "MainSynthesisApproval", "SoftwareFreeze", "Tool")]


def check_histories(prep):
    for inventory in prep["HistoryInventories"]:
        actual = [artifact(path) for path in sorted(Path(inventory["Root"]).rglob("*")) if path.is_file()]
        if actual != inventory["Files"]:
            raise RuntimeError("Protected history inventory changed: " + inventory["Root"])


def query_objects(text):
    """Read exact -o responses, never interpret UID strings as collections.

    TD documentation shows printed `ports:`/`clocks:`. Some command bindings
    also return the names; preserve both and reject contradictory names. Empty
    or numeric-zero return status is not an object count or name proof.
    """
    interp = tkinter.Tcl()
    lines = text.splitlines()
    rows = {}
    for label, (kind, expected) in EXPECTED_QUERIES.items():
        begin, end = "SHAPE30_QUERY_BEGIN " + label, "SHAPE30_QUERY_END " + label
        if lines.count(begin) != 1 or lines.count(end) != 1:
            raise ValueError("Missing/duplicate query section: " + label)
        start, finish = lines.index(begin), lines.index(end)
        if start >= finish:
            raise ValueError("Out-of-order query section: " + label)
        section = lines[start + 1:finish]
        returned = [line for line in section if line.startswith("SHAPE30_QUERY_RETURN ")]
        if len(returned) != 1:
            raise ValueError("Unique query return record required: " + label)
        try:
            fields = interp.splitlist(returned[0])
            if len(fields) != 3 or fields[:2] != ("SHAPE30_QUERY_RETURN", label):
                raise ValueError("Malformed query return: " + label)
            raw_return = fields[2]
            return_names = list(interp.splitlist(raw_return))
            printed = [re.fullmatch(r"\s*" + kind + r"\s*:\s*(.*?)\s*", line, re.IGNORECASE) for line in section]
            printed = [list(interp.splitlist(match.group(1))) for match in printed if match]
        except tkinter.TclError as error:
            raise ValueError("Unreadable query list: " + label) from error
        if len(printed) > 1:
            raise ValueError("Duplicate printed query response: " + label)
        candidates = printed[:]
        if return_names not in ([], ["0"]):
            candidates.append(return_names)
        if not candidates or any(sorted(names) != sorted(expected) for names in candidates):
            raise ValueError("Query does not resolve exactly expected names: " + label)
        rows[label] = dict(Names=sorted(expected), RawReturn=raw_return, PrintedNames=printed,
                           Evidence="Exact readable -o names; no UID or llength inference")
    markers = [line for line in lines if line.startswith("SHAPE30_QUERY_BEGIN ") or line.startswith("SHAPE30_QUERY_END ")]
    if len(markers) != 2 * len(EXPECTED_QUERIES):
        raise ValueError("Unexpected query sections")
    return rows


def timing_clocks(text):
    sections = text.split("Clock Summary\n")
    if len(sections) != 2:
        raise ValueError("Timing report must contain one Clock Summary")
    table = sections[1].split("Notes", 1)[0]
    lines = table.splitlines()
    header_indices = [i for i, line in enumerate(lines)
                      if line.split()[:4] == ["Name", "Type", "Rise(ns)", "Fall(ns)"]]
    if len(header_indices) != 1:
        raise ValueError("Unique detailed timing clock table required")
    identifiers = {}
    for line in lines[:header_indices[0]]:
        fields = line.split()
        if not fields or not fields[0].endswith(":") or fields[0] == "Clock-Id:":
            continue
        if len(fields) != 4:
            raise ValueError("Malformed clock identity row")
        identifier = fields[0][:-1]
        name = fields[3]
        if identifier in identifiers or name not in EXPECTED_PERIODS or name in identifiers.values():
            raise ValueError("Unexpected or duplicate clock identity")
        identifiers[identifier] = name
    if set(identifiers.values()) != set(EXPECTED_PERIODS):
        raise ValueError("Clock identities must resolve exactly the two original names")
    header = lines[header_indices[0]].split()
    if "C-Period(ns)" not in header:
        raise ValueError("Clock period column missing")
    rows = {}
    for line in lines[header_indices[0] + 1:]:
        if not line.strip() or set(line.strip()) == {"-"}:
            continue
        fields = line.split()
        if len(fields) != len(header):
            raise ValueError("Malformed detailed clock row")
        row = dict(zip(header, fields))
        identifier = row["Name"]
        if identifier not in identifiers:
            raise ValueError("Unknown detailed clock ID")
        name = identifiers[identifier]
        if name in rows:
            raise ValueError("Duplicate clock row")
        try:
            period = Decimal(row["C-Period(ns)"])
        except InvalidOperation as error:
            raise ValueError("Invalid clock period") from error
        if name not in EXPECTED_PERIODS or not period.is_finite() or period != EXPECTED_PERIODS[name]:
            raise ValueError("Unexpected clock name/period: " + name)
        rows[name] = dict(ClockName=name, **row)
    if set(rows) != set(EXPECTED_PERIODS):
        raise ValueError("Detailed timing table must contain only the two original clocks")
    return rows


def xml_clocks(text):
    try:
        root = ET.fromstring(text)
    except ET.ParseError as error:
        raise ValueError("Malformed clock XML") from error
    if root.tag != "clock_summary" or [child.tag for child in root] != ["groups"]:
        raise ValueError("Unexpected clock XML structure")
    groups = root[0]
    if groups.get("size") != "2" or len(groups) != 2 or any(child.tag != "clock_group" for child in groups):
        raise ValueError("Clock XML must contain exactly two groups")
    rows = {}
    for group in groups:
        name = group.get("name")
        if name not in EXPECTED_PERIODS or name in rows or group.get("size") != "1" or len(group):
            raise ValueError("Unexpected or duplicate clock XML group")
        try:
            endpoints, clocks, nonclocks = (int(group.attrib[key]) for key in ("endpoints", "clocks", "nonclocks"))
        except (KeyError, ValueError) as error:
            raise ValueError("Invalid clock XML endpoints") from error
        if endpoints <= 0 or clocks <= 0 or endpoints != clocks or nonclocks != 0:
            raise ValueError("Clock XML has unresolved/nonclock endpoints")
        rows[name] = dict(group.attrib)
    if set(rows) != set(EXPECTED_PERIODS):
        raise ValueError("Clock XML missing original clock")
    return rows


def critical_lines(text):
    return re.findall(r"^.*(?:CRITICAL[- _]WARNING|\bERROR\b).*$", text, re.MULTILINE | re.IGNORECASE)


def verify_prepared():
    prep = read(PREP / "preparation.json")
    if prep["Stage"] != "clock_reanalysis_prepared_no_execution_permission" or prep["TDStarted"] or any(
            prep[name] for name in ("AnalysisAllowed", "SynthesisAllowed", "RouteAllowed", "BitgenAllowed")):
        raise RuntimeError("Not an untouched read-only preparation")
    for row in protected_rows(prep):
        check(row)
    check_histories(prep)
    if prep.get("Version") != 3 or prep["PriorClockAnalysis"]["SHA256"] != "210DBC3740EF7A5BF8B3A7326AF23C3D941FCBAF00066D929DE0473C8E9C7F07":
        raise RuntimeError("Wrong v3 failure lineage")
    if prep["Executor"] != artifact(__file__) or prep["Tool"] != artifact(TOOL) or prep["Tool"]["SHA256"] != TOOL_SHA:
        raise RuntimeError("Executor or TD version changed")
    if prep["OriginalDatabase"]["SHA256"] != "4EA4A9251296A733DB8A588B570BCABC1B44AE1D491F221BCD47986AC9B5E2A6":
        raise RuntimeError("Wrong original gate DB")
    return prep


def main():
    if sys.flags.optimize:
        raise RuntimeError("Checks cannot be disabled")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify-prepared", action="store_true")
    parser.add_argument("--approval", type=Path)
    parser.add_argument("--approval-sha")
    args = parser.parse_args()
    if args.verify_prepared:
        verify_prepared()
        print("T030_CLOCK_PREPARATION_VERIFIED_NO_TD")
        return 0
    if not args.approval or not args.approval_sha:
        parser.error("Separate exact read-only approval required")
    approval_artifact = artifact(args.approval)
    if approval_artifact["SHA256"] != args.approval_sha.upper():
        raise RuntimeError("Approval SHA mismatch")
    approved = read(args.approval)
    if approved.get("Stage") != "clock_reanalysis_only_approved" or approved.get("Candidate") != "D0300" or approved.get("AnalysisAllowed") is not True or any(
            approved.get(name) is not False for name in ("SynthesisAllowed", "RouteAllowed", "BitgenAllowed", "HardwareAllowed")):
        raise RuntimeError("Read-only analysis permission only")
    if approved.get("Version") != 3:
        raise RuntimeError("Exact v3 approval required")
    for name in BINDINGS:
        check(approved[name])
    if approved["Program"] != artifact(__file__) or approved["Preparation"] != artifact(PREP / "preparation.json") or approved["Tool"] != artifact(TOOL):
        raise RuntimeError("Approval does not bind current exact program/preparation/tool")
    if any((PREP / name).exists() for name in ("started.json", "process.json", "native.json", "result.json", "stdout.log", "analysis.complete", "clocks.rpt", "gate.timing")):
        raise RuntimeError("Never reuse an attempted directory")
    prep = verify_prepared()
    for name in ("MainSynthesisApproval", "NativeSynthesisResult", "PriorClockAnalysis", "SoftwareFreeze"):
        if approved[name] != prep[name]:
            raise RuntimeError("Wrong synthesis/software lineage")
    if approved.get("SourceCommit") != prep["SourceCommit"] or subprocess.check_output(
            ["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip() != prep["SourceCommit"]:
        raise RuntimeError("Source checkpoint changed")
    if subprocess.check_output(["git", "-C", str(ROOT), "branch", "--show-current"], text=True).strip() != "task/sc520-color-integration":
        raise RuntimeError("Wrong branch")
    active = subprocess.check_output(["powershell.exe", "-NoProfile", "-Command",
        "@(Get-CimInstance Win32_Process | Where-Object {$_.Name -match '^td.*\\.exe$' -and $_.Name -ne 'td.exe'}) | ForEach-Object {$_.ProcessId}"], text=True).strip()
    if active:
        raise RuntimeError("Active TD console needs ownership review")
    command = [TOOL.as_posix(), (PREP / "analysis.tcl").as_posix()]
    started = now()
    report = dict(Stage="read_only_clock_reanalysis", Candidate="D0300", Owner="Codex /root/shape30_clock_resume",
                  Approval=approval_artifact, Preparation=approved["Preparation"], Program=artifact(__file__),
                  Tool=artifact(TOOL), OriginalDatabase=prep["OriginalDatabase"], DatabaseCopy=prep["DatabaseCopy"],
                  NativeSynthesisResult=prep["NativeSynthesisResult"], PriorClockAnalysis=prep["PriorClockAnalysis"], Version=3,
                  StartedAt=started, ParentPID=os.getpid(),
                  Command=command, WorkingDirectory=str(PREP), SynthesisAllowed=False, RouteAllowed=False,
                  BitgenAllowed=False, TimingQualified=False, ResourceAccepted=False, HardwareValidated=False)
    save(PREP / "started.json", report)
    process = None
    code = None
    try:
        with (PREP / "stdout.log").open("xb") as stdout, (PREP / "stderr.log").open("xb") as stderr:
            process = subprocess.Popen(command, cwd=PREP, stdout=stdout, stderr=stderr, creationflags=subprocess.CREATE_NO_WINDOW)
            save(PREP / "process.json", dict(PID=process.pid, ParentPID=os.getpid(), CreatedObservedAt=now(), Command=command))
            print(json.dumps(dict(Run=str(PREP), PID=process.pid)), flush=True)
            code = process.wait()
    except BaseException as error:
        report["ExecutionError"] = dict(Type=type(error).__name__, Message=str(error))
    finally:
        errors = []

        def inspect(label, action, default):
            try:
                return action()
            except (OSError, RuntimeError, ValueError) as error:
                errors.append(dict(Check=label, Type=type(error).__name__, Message=str(error)))
                return default

        live = process is not None
        native = dict(StartedAt=started, PID=process.pid if process is not None else None)
        if process is not None:
            live = inspect("NativePoll", lambda: process.poll() is None, True)
            if not live:
                code = process.returncode
                native.update(FinishedAt=now(), ExitCode=code)
                inspect("NativeRecord", lambda: save(PREP / "native.json", native), None)
        rows = protected_rows(prep) + [approved[name] for name in BINDINGS] + [approval_artifact]
        changed = []
        for row in rows:
            if inspect("BoundInput:" + row["Path"], lambda row=row: check(row), None) is None:
                changed.append(row["Path"])
        history_ok = inspect("CompleteHistoryInventories", lambda: check_histories(prep) or True, False)
        output_paths = inspect("OutputInventory", lambda: sorted(path for path in PREP.rglob("*") if path.is_file()), [])
        report["Outputs"] = []
        for path in output_paths:
            item = inspect("OutputArtifact:" + str(path), lambda path=path: artifact(path), None)
            if item is not None:
                report["Outputs"].append(item)
        unexpected_database = [str(path) for path in output_paths if path.suffix.lower() in (".db", ".bit") and path != Path(prep["DatabaseCopy"]["Path"])]
        text = inspect("StdoutRead", lambda: (PREP / "stdout.log").read_text(errors="replace"), "")
        stderr_text = inspect("StderrRead", lambda: (PREP / "stderr.log").read_text(errors="replace"), "")
        critical = [dict(Stream=stream, Text=line) for stream, contents in (("stdout", text), ("stderr", stderr_text))
                    for line in critical_lines(contents)]
        token = "SHAPE30_CLOCK_REANALYSIS_COMPLETED"
        marker_text = inspect("MarkerRead", lambda: (PREP / "analysis.complete").read_text(encoding="ascii").strip(), "")
        start_seconds = datetime.fromisoformat(started).timestamp()
        reports_fresh = all(inspect("Fresh:" + name, lambda name=name:
            (PREP / name).stat().st_size > 0 and (PREP / name).stat().st_mtime >= start_seconds, False)
            for name in ("clocks.rpt", "gate.timing", "analysis.complete"))
        timing = inspect("TimingRead", lambda: (PREP / "gate.timing").read_text(errors="replace"), "")
        timing_rows = inspect("StructuredTimingClocks", lambda: timing_clocks(timing), None)
        clock_xml = inspect("ClockXMLRead", lambda: (PREP / "clocks.rpt").read_text(errors="replace"), "")
        xml_rows = inspect("StructuredXMLClocks", lambda: xml_clocks(clock_xml), None)
        queries = inspect("ReadablePortAndClockQueries", lambda: query_objects(text), None)
        report.update(Native=native, LiveNativePreserved=live, ChangedInputs=sorted(set(changed)), ValidationErrors=errors,
                      UnexpectedDatabaseOrBitFiles=unexpected_database, CriticalWarnings=critical,
                      CompletedToken=token in text.splitlines(), MarkerToken=marker_text == token,
                      ReportsFresh=reports_fresh, TimingClockRows=timing_rows, XMLClockGroups=xml_rows,
                      QueryObjects=queries, CompleteHistoryInventoriesUnchanged=history_ok,
                      OriginalClocksAndPeriodsVerified=timing_rows is not None and xml_rows is not None and queries is not None,
                      AnalysisCompleted=code == 0 and not live and "ExecutionError" not in report and token in text.splitlines()
                      and marker_text == token and reports_fresh and timing_rows is not None and xml_rows is not None
                      and queries is not None and history_ok and not changed and not critical and not unexpected_database and not errors)
        save(PREP / "result.json", report)
    print(json.dumps(dict(Run=str(PREP), NativeExitCode=code, LiveNativePreserved=live, AnalysisCompleted=report["AnalysisCompleted"])))
    return 0 if report["AnalysisCompleted"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
