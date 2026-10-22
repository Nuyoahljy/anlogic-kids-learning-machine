"""Prepare a read-only timing view of the same gate DB; never invoke TD."""
from datetime import datetime, timezone, timedelta
from pathlib import Path
import hashlib
import json
import shutil
import tkinter

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "evidence/sc520-shape-card30/synthesis-prepared-20261022-1255-v4"
OUT = ROOT / "evidence/sc520-shape-card30/clock-reanalysis-prepared-20261022-1405-v2"
EXECUTOR = Path(__file__).with_name("execute-shape-card30-clock-reanalysis.py")
FREEZE = ROOT / "evidence/sc520-shape-card30/software-final-20261022-1206/source-freeze.json"
APPROVAL = Path("E:/juan/FPGA/learning/sc520-shape-card30/main-review/synthesis-only-approved-20261022-v4.json")
TOOL = Path("D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe")


def artifact(path):
    path = Path(path).resolve(strict=True)
    return dict(Path=str(path), SHA256=hashlib.sha256(path.read_bytes()).hexdigest().upper(), Bytes=path.stat().st_size)


def save(path, value):
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write("\n")


def main():
    if not __debug__:
        raise RuntimeError("Checks cannot be disabled")
    database = artifact(SOURCE / "shape30_gate.db")
    if database["SHA256"] != "4EA4A9251296A733DB8A588B570BCABC1B44AE1D491F221BCD47986AC9B5E2A6":
        raise RuntimeError("Only the exact original gate DB may be analyzed")
    native_result = artifact(SOURCE / "result.json")
    if native_result["SHA256"] != "E539F8533BAE38A8BE322F9ADE7A324F1665A4C682A85915EBC2F9B8EDC612D4":
        raise RuntimeError("Native synthesis result changed")
    freeze = json.loads(FREEZE.read_text(encoding="utf-8"))
    history = [artifact(path) for path in sorted(SOURCE.iterdir()) if path.is_file()]
    previous = [artifact(path) for path in sorted((ROOT / "evidence/sc520-shape-card30/clock-reanalysis-prepared-20261022-1345-v1").iterdir()) if path.is_file()]
    inputs = freeze["CompileOrder"] + freeze["AssetsAndContract"] + freeze["Testbenches"] + freeze["Tools"] + [freeze["SharedVerificationReference"]]
    for row in inputs:
        if artifact(row["Path"]) != row:
            raise RuntimeError("Frozen software changed")
    references = [
        artifact("D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/doc/scripts/DefaultFlow.tcl"),
        artifact("D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/doc/scripts/SynIpFlow.tcl"),
        artifact(Path(__file__).with_name("probe-i2c-io.py")),
    ]
    OUT.mkdir(exist_ok=False)
    shutil.copyfile(database["Path"], OUT / "shape30_gate.db")
    sdc = """create_clock -name MIPI_RX_BYTE_CLK -period 9.660 [get_ports {capture_clk}]
create_clock -name HDMI_PIXEL_CLK -period 13.468 [get_ports {display_clk}]
"""
    (OUT / "clocks.sdc").write_text(sdc, encoding="ascii", newline="\n")
    script = """if {[catch {
import_device ph1_35p.db -package PH1P35MDG324 -speed 3
import_db {DB_PATH}
read_sdc {SDC_PATH}
set capture_port [get_ports capture_clk]
set display_port [get_ports display_clk]
set capture_clock [get_clocks MIPI_RX_BYTE_CLK]
set display_clock [get_clocks HDMI_PIXEL_CLK]
set all_clocks [get_clocks *]
if {[llength $capture_port]!=1 || [llength $display_port]!=1 || [llength $capture_clock]!=1 || [llength $display_clock]!=1 || [llength $all_clocks]!=2} {error "Exact two ports and clocks not resolved"}
update_timing
report_clock_summary -file clocks.rpt
report_timing_summary -file gate.timing
set marker [open analysis.complete w]
puts $marker "SHAPE30_CLOCK_REANALYSIS_COMPLETED"
close $marker
} failure]} {puts stderr $failure;exit 1}
puts "SHAPE30_CLOCK_REANALYSIS_COMPLETED"
exit 0
""".replace("DB_PATH", (OUT / "shape30_gate.db").as_posix()).replace("SDC_PATH", (OUT / "clocks.sdc").as_posix())
    (OUT / "analysis.tcl").write_text(script, encoding="ascii", newline="\n")
    stub_runs = []
    for failure in (None, "read_sdc", "duplicate_port", "missing_clock", "update_timing", "report_timing_summary"):
        interp = tkinter.Tcl()
        calls = []

        def stub(*args, command):
            calls.append([command, *args])
            if command == failure:
                raise tkinter.TclError("injected failure")
            if command == "read_sdc":
                interp.eval(sdc)
            if command == "get_ports":
                return "capture_clk duplicate" if failure == "duplicate_port" and args == ("capture_clk",) else args[0]
            if command == "get_clocks":
                if failure == "missing_clock" and args == ("HDMI_PIXEL_CLK",):
                    return ""
                return "MIPI_RX_BYTE_CLK HDMI_PIXEL_CLK" if args == ("*",) else args[0]
            return "stub_fd" if command == "open" else ""

        for command in ("import_device", "import_db", "read_sdc", "get_ports", "get_clocks", "create_clock",
                        "update_timing", "report_clock_summary", "report_timing_summary", "open", "close"):
            interp.createcommand(command, lambda *args, command=command: stub(*args, command=command))
        interp.createcommand("puts", lambda *args: calls.append(["puts", *args]) or "")
        interp.createcommand("record_exit", lambda *args: calls.append(["exit", *args]) or "")
        interp.eval('proc exit {code} {record_exit $code;error "STUB_TERMINATED_$code"}')
        expected = int(failure is not None)
        try:
            interp.eval(script)
            raise RuntimeError("Stub exit did not terminate")
        except tkinter.TclError as error:
            assert str(error) == f"STUB_TERMINATED_{expected}"
        assert calls[-1] == ["exit", str(expected)]
        assert not any(call[0] in ("elaborate", "optimize_rtl", "optimize_gate", "export_db", "write_verilog", "place", "route", "bitgen") for call in calls)
        if failure:
            assert not any(call[0] == "open" for call in calls)
            assert ["puts", "SHAPE30_CLOCK_REANALYSIS_COMPLETED"] not in calls
        else:
            assert [call for call in calls if call[0] == "create_clock"] == [
                ["create_clock", "-name", "MIPI_RX_BYTE_CLK", "-period", "9.660", "capture_clk"],
                ["create_clock", "-name", "HDMI_PIXEL_CLK", "-period", "13.468", "display_clk"]]
        stub_runs.append(dict(InjectedFailure=failure, ExpectedExit=expected, Calls=calls, Simulated=True))
    copied = artifact(OUT / "shape30_gate.db")
    assert copied["SHA256"] == database["SHA256"] and copied["Bytes"] == database["Bytes"]
    assert history == [artifact(path) for path in sorted(SOURCE.iterdir()) if path.is_file()]
    assert all(artifact(row["Path"]) == row for row in previous)
    report = dict(Stage="clock_reanalysis_prepared_no_execution_permission", Candidate="D0300",
                  At=datetime.now(timezone(timedelta(hours=8))).isoformat(), Owner="Codex /root/shape30_detector_finish",
                  Program=artifact(__file__), Executor=artifact(EXECUTOR), OriginalDatabase=database,
                  DatabaseCopy=copied, NativeSynthesisResult=native_result, MainSynthesisApproval=artifact(APPROVAL),
                  SoftwareFreeze=artifact(FREEZE), FrozenInputs=inputs, OriginalHistory=history + previous,
                  References=references, Tool=artifact(TOOL), TclStubRuns=stub_runs,
                  CapturePeriodNS=9.660, DisplayPeriodNS=13.468, SourceCommit="1f0a6b72fabe3289d3f5d9f80a9f861570c15a7b",
                  Scope="Only disposable read_sdc/update_timing reports on same gate DB. No new synthesis/DB export/optimization/route/bit. Original default-clock failure preserved.",
                  TDStarted=False, AnalysisAllowed=False, SynthesisAllowed=False, RouteAllowed=False, BitgenAllowed=False,
                  PreparedFiles=[artifact(path) for path in sorted(OUT.iterdir()) if path.is_file()])
    save(OUT / "preparation.json", report)
    print(json.dumps(artifact(OUT / "preparation.json")))


if __name__ == "__main__":
    main()
