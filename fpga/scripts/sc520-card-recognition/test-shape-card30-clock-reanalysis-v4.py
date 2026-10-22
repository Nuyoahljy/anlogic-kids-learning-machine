"""Test actual read-only CLI guards and simulated exception paths; never run TD."""
from pathlib import Path
from unittest.mock import patch
import importlib.util
import json
import subprocess
import sys
import tkinter

ROOT = Path(__file__).resolve().parents[3]
PROGRAM = Path(__file__).with_name("execute-shape-card30-clock-reanalysis-v4.py")
OUT = ROOT / "evidence/sc520-shape-card30/clock-reanalysis-preflight-20261022-1750-v4"


def main():
    if not __debug__:
        raise RuntimeError("Tests cannot disable checks")
    OUT.mkdir(exist_ok=False)
    spec = importlib.util.spec_from_file_location("shape30_clock_preflight", PROGRAM)
    executor = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(executor)
    valid_timing = """Clock Summary
--------------------
Clock-Id: C-Freq Fanout Clock-Name
clk0: 103.520 4000 MIPI_RX_BYTE_CLK
clk1: 74.250 1500 HDMI_PIXEL_CLK
Name Type Rise(ns) Fall(ns) C-Period(ns) C-Freq(MHz) R-Period(ns) R-Freq(MHz) SWNS(ns) STNS(ns) HWNS(ns) HTNS(ns) Skew(ns) Fanout Max-Level CC-From CC-To
clk0 local 0.000 4.830 9.660 103.520 28.780 34.746 -19.120 -199.604 0.328 0.000 0.000 4000 34 no no
clk1 local 0.000 6.734 13.468 74.250 8.000 125.000 5.468 0.000 0.328 0.000 0.000 1500 12 no no
Notes
Original budget9.660/13.468 and named clocks appear here but cannot replace table validation.
"""
    valid_xml = """<clock_summary><groups size="2">
<clock_group name="MIPI_RX_BYTE_CLK" size="1" endpoints="4000" clocks="4000" nonclocks="0"/>
<clock_group name="HDMI_PIXEL_CLK" size="1" endpoints="1500" clocks="1500" nonclocks="0"/>
</groups></clock_summary>"""
    query_sections = []
    for label, (kind, names) in executor.EXPECTED_QUERIES.items():
        rendered = " ".join(names)
        query_sections.append(f"SHAPE30_QUERY_BEGIN {label}\n{kind}: {rendered}\nSHAPE30_QUERY_RETURN {label} {{{rendered}}}\nSHAPE30_QUERY_END {label}\n")
    valid_queries = "".join(query_sections)
    wrong_period = valid_timing.replace("9.660 103.520 28.780", "20.000 103.520 28.780")
    extra_default = valid_timing.replace("Name Type", "clk2: 50.000 10 DeriveClock\nName Type").replace(
        "Notes\n", "clk2 local 0.000 10.000 20.000 50.000 20.000 50.000 0.000 0.000 0.328 0.000 0.000 10 1 no no\nNotes\n")
    parser_cases = []
    for name, parser, value, expected in (
            ("valid-timing", executor.timing_clocks, valid_timing, True),
            ("wrong-period", executor.timing_clocks, wrong_period, False),
            ("extra-default", executor.timing_clocks, extra_default, False),
            ("duplicate-clock", executor.timing_clocks, valid_timing.replace("clk1: 74.250 1500 HDMI_PIXEL_CLK", "clk1: 74.250 1500 MIPI_RX_BYTE_CLK"), False),
            ("missing-clock", executor.timing_clocks, valid_timing.replace("clk1: 74.250 1500 HDMI_PIXEL_CLK\n", ""), False),
            ("valid-xml", executor.xml_clocks, valid_xml, True),
            ("bad-root", executor.xml_clocks, valid_xml.replace("clock_summary", "root"), False),
            ("extra-group", executor.xml_clocks, valid_xml.replace('size="2"', 'size="3"').replace("</groups>", '<clock_group name="DeriveClock" size="1" endpoints="10" clocks="10" nonclocks="0"/></groups>'), False),
            ("bad-endpoints", executor.xml_clocks, valid_xml.replace('clocks="4000"', 'clocks="0"'), False),
            ("readable-queries", executor.query_objects, valid_queries, True),
            ("readable-printed-status", executor.query_objects, valid_queries.replace("{capture_clk}", "0"), True),
            ("readable-return-only", executor.query_objects, "\n".join(line for line in valid_queries.splitlines() if not line.startswith(("ports:", "clocks:"))), True),
            ("opaque-uid-not-a-list", executor.query_objects, valid_queries.replace("ports: capture_clk", "ports: UID0001").replace("{capture_clk}", "UID0001"), False),
            ("extra-query-clock", executor.query_objects, valid_queries.replace("HDMI_PIXEL_CLK MIPI_RX_BYTE_CLK", "HDMI_PIXEL_CLK MIPI_RX_BYTE_CLK DeriveClock"), False),
            ("duplicate-query-clock", executor.query_objects, valid_queries.replace("HDMI_PIXEL_CLK MIPI_RX_BYTE_CLK", "HDMI_PIXEL_CLK MIPI_RX_BYTE_CLK MIPI_RX_BYTE_CLK"), False),
            ("wrong-query-port", executor.query_objects, valid_queries.replace("ports: capture_clk", "ports: display_clk"), False),
            ("missing-query", executor.query_objects, valid_queries.replace("SHAPE30_QUERY_BEGIN all_clocks", "REMOVED"), False),
            ("contradictory-query", executor.query_objects, valid_queries.replace("{capture_clk}", "{other_clk}"), False),
            ("query-status-alone", executor.query_objects, valid_queries.replace("ports: capture_clk\n", "").replace("{capture_clk}", "0"), False)):
        try:
            parser(value)
            accepted = True
        except ValueError:
            accepted = False
        assert accepted == expected, name
        parser_cases.append(dict(Name=name, ExpectedAccepted=expected, ActualAccepted=accepted))
    assert executor.critical_lines("USR-8122 CRITICAL-WARNING: failure")
    assert executor.critical_lines("ERROR: stdout or stderr error")
    assert not executor.critical_lines("Warning: noncritical observation")
    approval = Path("E:/juan/FPGA/learning/sc520-shape-card30/main-review/synthesis-only-approved-20261022-v4.json")
    prefix = [sys.executable, "-B", "-X", "utf8", str(PROGRAM)]
    cases = [
        ("help", prefix + ["--help"], 0),
        ("verify-prepared", prefix + ["--verify-prepared"], 0),
        ("wrong-stage", prefix + ["--approval", str(approval), "--approval-sha", executor.artifact(approval)["SHA256"]], 1),
        ("wrong-sha", prefix + ["--approval", str(approval), "--approval-sha", "0" * 64], 1),
        ("optimized", [sys.executable, "-O", str(PROGRAM), "--verify-prepared"], 1),
    ]
    original_prep = executor.verify_prepared()
    protected = executor.protected_rows(original_prep) + [executor.artifact(PROGRAM), executor.artifact(executor.PREP / "preparation.json")]
    cli = []
    for name, command, expected in cases:
        process = subprocess.run(command, capture_output=True, text=True, encoding="utf-8")
        assert process.returncode == expected, (name, process.returncode)
        (OUT / (name + ".stdout.txt")).write_text(process.stdout, encoding="utf-8")
        (OUT / (name + ".stderr.txt")).write_text(process.stderr, encoding="utf-8")
        cli.append(dict(Name=name, Command=command, NativeExitCode=process.returncode))
    for row in protected:
        executor.check(row)
    history_folder = OUT / "history-guard"
    history_folder.mkdir()
    (history_folder / "original.txt").write_text("original", encoding="ascii")
    history_prep = dict(HistoryInventories=[dict(Root=str(history_folder), Files=[executor.artifact(history_folder / "original.txt")])])
    executor.check_histories(history_prep)
    (history_folder / "added.txt").write_text("added", encoding="ascii")
    try:
        executor.check_histories(history_prep)
        raise AssertionError("Added historical files must be rejected")
    except RuntimeError:
        pass
    history_tests = [dict(Name="exact-history", Accepted=True), dict(Name="additional-history-file", Accepted=False)]
    simulated = []
    for case in ("spawn-fail", "wait-live", "wait-exited", "poll-fail", "input-missing", "tool-missing",
                 "output-missing", "valid-reports", "wrong-period", "extra-default", "stderr-critical", "missing-query", "wrong-query", "history-changed"):
        folder = OUT / case
        folder.mkdir()
        bindings = {name: dict(Path=str(folder / (name + ".bound")), SHA256="SIMULATED", Bytes=1)
                    for name in executor.BINDINGS}
        dummy = dict(Path=str(folder / "input.bound"), SHA256="SIMULATED", Bytes=1)
        database_copy = dict(Path=str(folder / "shape30_gate.db"), SHA256="SIMULATED", Bytes=1)
        prep = dict(SourceCommit="SIMULATED", OriginalDatabase=dummy, DatabaseCopy=database_copy,
                    MainSynthesisApproval=bindings["MainSynthesisApproval"], NativeSynthesisResult=bindings["NativeSynthesisResult"],
                    PriorClockAnalysis=bindings["PriorClockAnalysis"], SoftwareFreeze=bindings["SoftwareFreeze"])
        approved = dict(Stage="clock_reanalysis_only_approved", Candidate="D0300", AnalysisAllowed=True,
                        SynthesisAllowed=False, RouteAllowed=False, BitgenAllowed=False, HardwareAllowed=False,
                        SourceCommit="SIMULATED", Version=4, **bindings)
        records = {}
        calls = []
        validating = False

        def fake_artifact(path):
            path = Path(path)
            if validating and (case == "tool-missing" and path == executor.TOOL or case == "output-missing" and path.name == "gone.out"):
                raise FileNotFoundError("simulated disappeared artifact")
            for row in bindings.values():
                if str(path) == row["Path"]:
                    return row
            if path == PROGRAM:
                return bindings["Program"]
            if path == executor.TOOL:
                return bindings["Tool"]
            if path.name == "preparation.json":
                return bindings["Preparation"]
            return dict(Path=str(path), SHA256="SIMULATED", Bytes=1)

        def fake_check(row):
            if validating and (case == "input-missing" and row == dummy or case == "tool-missing" and row == bindings["Tool"]):
                raise FileNotFoundError("simulated missing input/tool")
            return row

        def fake_read(path):
            if Path(path).name == "approval.json":
                return approved
            raise RuntimeError("Unexpected simulated read")

        def fake_save(path, value):
            nonlocal validating
            name = Path(path).name
            assert name not in records, "Must not overwrite simulated records"
            records[name] = json.loads(json.dumps(value))
            if name == "process.json":
                validating = True

        class FakeProcess:
            pid = 900002
            returncode = None

            def wait(self):
                if case == "wait-live":
                    raise RuntimeError("simulated wait error with live child")
                self.returncode = 0
                if case == "wait-exited":
                    raise RuntimeError("simulated wait error after exit")
                return 0

            def poll(self):
                if case == "poll-fail":
                    raise OSError("simulated unknown native status")
                return self.returncode

        def fake_popen(*args, **kwargs):
            calls.append("simulated-Popen")
            if case == "spawn-fail":
                raise OSError("simulated spawn failure")
            if case == "output-missing":
                (folder / "gone.out").write_text("SIMULATED", encoding="ascii")
            if case in ("valid-reports", "wrong-period", "extra-default", "stderr-critical", "missing-query", "wrong-query", "history-changed"):
                timing = wrong_period if case == "wrong-period" else extra_default if case == "extra-default" else valid_timing
                (folder / "gate.timing").write_text(timing, encoding="ascii")
                (folder / "clocks.rpt").write_text(valid_xml, encoding="ascii")
                (folder / "analysis.complete").write_text("SHAPE30_CLOCK_REANALYSIS_COMPLETED\n", encoding="ascii")
                queries = "" if case == "missing-query" else valid_queries.replace("ports: capture_clk", "ports: other_clk") if case == "wrong-query" else valid_queries
                kwargs["stdout"].write((queries + "SHAPE30_CLOCK_REANALYSIS_COMPLETED\n").encode("ascii"))
                kwargs["stdout"].flush()
                if case == "stderr-critical":
                    kwargs["stderr"].write(b"USR-8122 CRITICAL-WARNING: SIMULATED stderr failure\n")
                    kwargs["stderr"].flush()
            return FakeProcess()

        def fake_output(command, **kwargs):
            if command[0] == "git":
                return "SIMULATED\n" if "rev-parse" in command else "task/sc520-color-integration\n"
            return ""

        def fake_histories(prep):
            if case == "history-changed":
                raise RuntimeError("simulated changed historical inventory")

        with patch.object(executor, "PREP", folder), patch.object(executor, "artifact", fake_artifact), \
             patch.object(executor, "check", fake_check), patch.object(executor, "read", fake_read), \
             patch.object(executor, "save", fake_save), patch.object(executor, "protected_rows", lambda prep: [dummy]), \
             patch.object(executor, "verify_prepared", lambda: prep), patch.object(executor.subprocess, "Popen", fake_popen), \
             patch.object(executor, "check_histories", fake_histories), \
             patch.object(executor.subprocess, "check_output", fake_output), \
             patch.object(sys, "argv", [str(PROGRAM), "--approval", str(folder / "approval.json"), "--approval-sha", "SIMULATED"]):
            status = executor.main()
        assert status == int(case != "valid-reports") and "result.json" in records
        result = records["result.json"]
        assert result["AnalysisCompleted"] == (case == "valid-reports")
        assert not result["TimingQualified"] and not result["ResourceAccepted"]
        if case == "stderr-critical":
            assert result["CriticalWarnings"] and result["CriticalWarnings"][0]["Stream"] == "stderr"
        if case in ("wrong-period", "extra-default", "missing-query", "wrong-query"):
            assert not result["OriginalClocksAndPeriodsVerified"]
        if case in ("wait-live", "poll-fail"):
            assert result["LiveNativePreserved"] and "FinishedAt" not in result["Native"]
            assert "native.json" not in records
        if case == "spawn-fail":
            assert result["Native"]["PID"] is None and "FinishedAt" not in result["Native"]
        if case in ("input-missing", "tool-missing", "output-missing", "poll-fail"):
            assert result["ValidationErrors"]
        simulated.append(dict(Name=case, Simulated=True, FakePID=900002, Calls=calls, Records=records))
    for row in protected:
        executor.check(row)
    report = dict(Program=executor.artifact(PROGRAM), TestProgram=executor.artifact(__file__),
                  Preparation=executor.artifact(executor.PREP / "preparation.json"), CLI=cli, ProtectedInputs=protected,
                  SimulatedExceptionCases=simulated, StructuredParserTests=parser_cases, InputsUnchanged=True, AllPassed=True,
                  HistoryInventoryTests=history_tests,
                  Scope="5 actual CLI tests; 14 fully simulated crypto/input/Git/Popen paths including reports/query/history rejection; 19 structured parser cases and 2 history inventory cases, no native TD.",
                  TDStarted=False, SubstInvoked=False, AnalysisAllowed=False)
    (OUT / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(dict(Run=str(OUT), CLITests=len(cli), SimulatedExceptionTests=len(simulated), AllPassed=True)))


if __name__ == "__main__":
    main()
