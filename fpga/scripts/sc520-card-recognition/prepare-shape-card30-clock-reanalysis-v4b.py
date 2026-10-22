"""Prepare a read-only timing view of the same gate DB; never invoke TD."""
from datetime import datetime, timezone, timedelta
from pathlib import Path
import hashlib
import json
import re
import shutil
import tkinter

ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "evidence/sc520-shape-card30/synthesis-prepared-20261022-1255-v4"
OUT = ROOT / "evidence/sc520-shape-card30/clock-reanalysis-prepared-20261022-1805-v4b"
EXECUTOR = Path(__file__).with_name("execute-shape-card30-clock-reanalysis-v4b.py")
FREEZE = ROOT / "evidence/sc520-shape-card30/software-final-20261022-1206/source-freeze.json"
APPROVAL = Path("E:/juan/FPGA/learning/sc520-shape-card30/main-review/synthesis-only-approved-20261022-v4.json")
TOOL = Path("D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe")
PREVIOUS = ROOT / "evidence/sc520-shape-card30/clock-reanalysis-prepared-20261022-1610-v3"
MANUAL = Path("D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/doc/SWUG/SWUG105_TCL_Command_User_Guide.pdf")


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
    histories = [SOURCE, ROOT / "evidence/sc520-shape-card30/clock-reanalysis-prepared-20261022-1345-v1", ROOT / "evidence/sc520-shape-card30/clock-reanalysis-prepared-20261022-1405-v2", PREVIOUS, ROOT / "evidence/sc520-shape-card30/clock-reanalysis-prepared-20261022-1750-v4"]
    inventories = [dict(Root=str(folder.resolve()), Files=[artifact(path) for path in sorted(folder.rglob("*")) if path.is_file()]) for folder in histories]
    previous = [row for inventory in inventories[1:] for row in inventory["Files"]]
    prior_result = artifact(PREVIOUS / "result.json")
    if prior_result["SHA256"] != "12B6A2876460E4DB114222B6D7C8E7A91D6C6BB49DDA0A8EC54757B4D95B7D52":
        raise RuntimeError("Prior failed analysis changed")
    netlist = artifact(SOURCE / "shape30_gate.v")
    netlist_text = Path(netlist["Path"]).read_text(encoding="utf-8")
    for port in ("capture_clk", "display_clk"):
        if len(re.findall(r"^\s*input\s+" + port + r"\s*;", netlist_text, re.MULTILINE)) != 1:
            raise RuntimeError("Exact input port not present in frozen gate netlist: " + port)
    inputs = freeze["CompileOrder"] + freeze["AssetsAndContract"] + freeze["Testbenches"] + freeze["Tools"] + [freeze["SharedVerificationReference"]]
    for row in inputs:
        if artifact(row["Path"]) != row:
            raise RuntimeError("Frozen software changed")
    references = [
        artifact("D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/doc/scripts/DefaultFlow.tcl"),
        artifact("D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/doc/scripts/SynIpFlow.tcl"),
        artifact(Path(__file__).with_name("probe-i2c-io.py")),
        artifact(MANUAL),
        *[artifact(Path("E:/juan/FPGA/learning/sc520-shape-card30/review/help-only-20261022-174204") / n) for n in ("result.json", "stdout.log", "summary.json")],
        *[artifact(Path(__file__).with_name(s + "-shape-card30-clock-reanalysis-v3.py")) for s in ("prepare", "execute", "test")],
        *[artifact(Path(__file__).with_name(stem + "-shape-card30-clock-reanalysis.py")) for stem in ("prepare", "execute", "test")],
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
update_timing -mode basic
source {SDC_PATH}
update_timing -mode basic
report_clock_summary -file clocks.rpt
report_timing_summary -file gate.timing
foreach {label command} {
    capture_port {get_ports capture_clk}
    display_port {get_ports display_clk}
    capture_clock {get_clocks MIPI_RX_BYTE_CLK}
    display_clock {get_clocks HDMI_PIXEL_CLK}
    all_clocks {get_clocks *}
} {
    puts "SHAPE30_QUERY_BEGIN $label"
    set query_result [eval $command]
    puts [list SHAPE30_QUERY_RETURN $label $query_result]
    puts "SHAPE30_QUERY_END $label"
}
set marker [open analysis.complete w]
puts $marker "SHAPE30_CLOCK_REANALYSIS_COMPLETED"
close $marker
} failure]} {puts stderr $failure;exit 1}
puts "SHAPE30_CLOCK_REANALYSIS_COMPLETED"
exit 0
""".replace("DB_PATH", (OUT / "shape30_gate.db").as_posix()).replace("SDC_PATH", (OUT / "clocks.sdc").as_posix())
    (OUT / "analysis.tcl").write_text(script, encoding="ascii", newline="\n")
    stub_runs = []
    for failure in (None, "import_db", "source", "initialize_timing", "refresh_timing", "report_clock_summary", "report_timing_summary", "get_ports", "get_clocks"):
        interp = tkinter.Tcl()
        calls = []

        def stub(*args, command):
            calls.append([command, *args])
            if command == failure:
                raise tkinter.TclError("injected failure")
            if command == "update_timing":
                count = sum(call[0] == "update_timing" for call in calls)
                if failure == "initialize_timing" and count == 1 or failure == "refresh_timing" and count == 2:
                    raise tkinter.TclError("injected initialization/refresh failure")
            if command == "source":
                interp.eval(sdc)
            if command == "get_ports":
                return args[-1]
            if command == "get_clocks":
                return "MIPI_RX_BYTE_CLK HDMI_PIXEL_CLK" if args[-1] == "*" else args[-1]
            return "stub_fd" if command == "open" else ""

        for command in ("import_device", "import_db", "source", "get_ports", "get_clocks", "create_clock",
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
            key_calls = [call[0] for call in calls if call[0] in ("import_db", "update_timing", "source", "report_clock_summary", "report_timing_summary")]
            assert key_calls == ["import_db", "update_timing", "source", "update_timing", "report_clock_summary", "report_timing_summary"]
            assert [call for call in calls if call[0] == "update_timing"] == [["update_timing", "-mode", "basic"]] * 2
            assert [call for call in calls if call[0] == "get_clocks"] == [
                ["get_clocks", "MIPI_RX_BYTE_CLK"], ["get_clocks", "HDMI_PIXEL_CLK"], ["get_clocks", "*"]]
            assert [call for call in calls if call[0] == "create_clock"] == [
                ["create_clock", "-name", "MIPI_RX_BYTE_CLK", "-period", "9.660", "capture_clk"],
                ["create_clock", "-name", "HDMI_PIXEL_CLK", "-period", "13.468", "display_clk"]]
        stub_runs.append(dict(InjectedFailure=failure, ExpectedExit=expected, Calls=calls, Simulated=True))
    copied = artifact(OUT / "shape30_gate.db")
    assert copied["SHA256"] == database["SHA256"] and copied["Bytes"] == database["Bytes"]
    assert history == [artifact(path) for path in sorted(SOURCE.iterdir()) if path.is_file()]
    assert all(artifact(row["Path"]) == row for row in previous)
    for inventory in inventories:
        assert inventory["Files"] == [artifact(path) for path in sorted(Path(inventory["Root"]).rglob("*")) if path.is_file()]
    report = dict(Stage="clock_reanalysis_prepared_no_execution_permission", Candidate="D0300",
                  At=datetime.now(timezone(timedelta(hours=8))).isoformat(), Owner="Codex /root main tooling successor",
                  Program=artifact(__file__), Executor=artifact(EXECUTOR), OriginalDatabase=database,
                  DatabaseCopy=copied, NativeSynthesisResult=native_result, MainSynthesisApproval=artifact(APPROVAL),
                  SoftwareFreeze=artifact(FREEZE), FrozenInputs=inputs, OriginalHistory=history + previous,
                  Version=4, PriorClockAnalysis=prior_result, HistoryInventories=inventories, FrozenGateNetlist=netlist,
                  RuntimeEvidenceAndPriorManual=dict(Manual=artifact(MANUAL), PrintedPages=[33, 38, 78],
                                       Query="Actual binary help and v3 runtime show no -o support; require exact returned readable names, never assume opaque UID cardinality",
                                       Initialization="import_db and update_timing basic; Tcl source executes original two clock lines explicitly, then refresh. Native effect is pending.",
                                       Qualification="First save full clock/timing reports; then exact report and readable-query validation in executor; no runtime semantics claimed from stubs"),
                  References=references, Tool=artifact(TOOL), TclStubRuns=stub_runs,
                  CapturePeriodNS=9.660, DisplayPeriodNS=13.468, SourceCommit="1f0a6b72fabe3289d3f5d9f80a9f861570c15a7b",
                  Scope="Only disposable source/update_timing reports on same gate DB. No new synthesis/DB export/optimization/route/bit. Original default-clock failure preserved.",
                  TDStarted=False, AnalysisAllowed=False, SynthesisAllowed=False, RouteAllowed=False, BitgenAllowed=False,
                  PreparedFiles=[artifact(path) for path in sorted(OUT.iterdir()) if path.is_file()])
    save(OUT / "preparation.json", report)
    print(json.dumps(artifact(OUT / "preparation.json")))


if __name__ == "__main__":
    main()
