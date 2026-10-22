"""Prepare and verify a complete observable T030 synthesis-only project; never run TD."""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import hashlib
import json
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[3]
FREEZE = ROOT / "evidence/sc520-shape-card30/software-final-20261022-1206/source-freeze.json"
OUT = ROOT / "evidence/sc520-shape-card30/synthesis-prepared-20261022-1255-v4"


def artifact(path):
    path = Path(path)
    return dict(Path=str(path), SHA256=hashlib.sha256(path.read_bytes()).hexdigest().upper(), Bytes=path.stat().st_size)


def main():
    if not __debug__:
        raise RuntimeError("Source checks cannot be disabled")
    freeze = json.loads(FREEZE.read_text(encoding="utf-8"))
    for row in freeze["CompileOrder"] + freeze["AssetsAndContract"]:
        if artifact(row["Path"]) != row:
            raise RuntimeError("Changed software input: " + row["Path"])
    OUT.mkdir(exist_ok=False)
    copied = []
    for row in freeze["CompileOrder"] + freeze["AssetsAndContract"]:
        source = Path(row["Path"])
        target = OUT / source.name
        if target.exists():
            raise RuntimeError("Input basename collision")
        target.write_bytes(source.read_bytes())
        copied.append(dict(Source=row, Snapshot=artifact(target)))
    wrapper_source = ROOT / "hardware/sc520-shape-card30/synthesis-wrapper.v"
    wrapper = OUT / wrapper_source.name
    wrapper_text = wrapper_source.read_text(encoding="ascii")
    for name in ("templates.mem", "contour29-shapes.mem", "anlogic_logo_index.mem", "anlogic_logo_palette.mem"):
        assert wrapper_text.count('="' + name + '"') == 1
        wrapper_text = wrapper_text.replace('="' + name + '"', '="' + (OUT / name).as_posix() + '"')
    wrapper.write_text(wrapper_text, encoding="ascii", newline="\n")
    copied.append(dict(Source=artifact(wrapper_source), Snapshot=artifact(wrapper)))
    project = ET.Element("Project", Version="3", Minor="2")
    for name, text in (("TD_Encoding", "UTF-8"), ("TD_Version", "6.2.168116"), ("Name", "shape30")):
        ET.SubElement(project, name).text = text
    hardware = ET.SubElement(project, "HardWare")
    for name, text in (("Family", "PH1"), ("Device", "PH1P35MDG324"), ("Speed", "-3")):
        ET.SubElement(hardware, name).text = text
    verilog = ET.SubElement(ET.SubElement(project, "Source_Files"), "Verilog")
    names = [Path(row["Path"]).name for row in freeze["CompileOrder"]] + [wrapper.name]
    for number, name in enumerate(names):
        info = ET.SubElement(ET.SubElement(verilog, "File", Path=(OUT / name).as_posix()), "FileInfo")
        for key, value in (("UsedInSyn", "true"), ("UsedInP&R", "true"), ("BelongTo", "design_1"), ("CompileOrder", str(number + 1))):
            ET.SubElement(info, "Attr", Name=key, Val=value)
    top = ET.SubElement(project, "TOP_MODULE")
    for name, text in (("LABEL", "shape30_synthesis_wrapper"), ("MODULE", "shape30_synthesis_wrapper"), ("CREATEINDEX", "user")):
        ET.SubElement(top, name).text = text
    filesets = ET.SubElement(project, "FileSets")
    for name, kind in (("design_1", "DesignFiles"), ("constraint_1", "ConstrainFiles")):
        ET.SubElement(filesets, "FileSet", Name=name, Type=kind)
    ET.SubElement(project, "Property")
    ET.SubElement(project, "Device_Settings")
    ET.indent(project)
    (OUT / "shape30.prj").write_text(ET.tostring(project, encoding="unicode") + "\n", encoding="utf-8")
    script = """if {[catch {
import_device ph1_35p.db -package PH1P35MDG324 -speed 3
open_project shape30.prj
commit_param -step design
elaborate -top shape30_synthesis_wrapper
create_clock -name MIPI_RX_BYTE_CLK -period 9.660 [get_ports capture_clk]
create_clock -name HDMI_PIXEL_CLK -period 13.468 [get_ports display_clk]
export_db shape30_elaborate.db
commit_param -step rtl
optimize_rtl
report_area -file shape30_rtl.area
export_db shape30_rtl.db
commit_param -step gate
optimize_gate -packarea shape30_gate.area
legalize_phy_inst
update_timing
report_area -file shape30_gate_full.area
report_timing_summary -file shape30_gate.timing
report_clock_summary -file shape30_clocks.rpt
export_db shape30_gate.db
write_verilog shape30_gate.v
set marker [open synthesis.complete w]
puts $marker "SHAPE30_SYNTHESIS_COMPLETED"
close $marker
} failure]} {puts stderr $failure;exit 1}
puts "SHAPE30_SYNTHESIS_COMPLETED"
exit 0
"""
    (OUT / "synthesis-only.tcl").write_text(script, encoding="ascii")
    # Preparation validates Tcl structure and command selection without a TD process.
    import tkinter
    stub_runs = []
    for failure in (None, "optimize_gate", "write_verilog"):
        interp = tkinter.Tcl()
        calls = []
        for command in ("import_device", "open_project", "commit_param", "elaborate", "create_clock",
                        "get_ports", "export_db", "optimize_rtl", "report_area", "optimize_gate",
                        "legalize_phy_inst", "update_timing", "report_timing_summary",
                        "report_clock_summary", "write_verilog", "open", "close"):
            def stub(*args, command=command):
                calls.append([command, *args])
                if command == failure:
                    raise tkinter.TclError("injected stub failure")
                return "stub_fd" if command == "open" else ""
            interp.createcommand(command, stub)
        interp.createcommand("puts", lambda *args: calls.append(["puts", *args]) or "")
        interp.createcommand("record_exit", lambda *args: calls.append(["exit", *args]) or "")
        interp.eval('proc exit {code} {record_exit $code;error "STUB_TERMINATED_$code"}')
        try:
            interp.eval(script)
            raise RuntimeError("Stub exit must terminate")
        except tkinter.TclError as error:
            assert str(error) == f"STUB_TERMINATED_{int(failure is not None)}"
        assert calls[-1] == ["exit", str(int(failure is not None))]
        assert sum(call[0] == "create_clock" for call in calls) == 2
        assert not any(call[0] in ("place", "route", "opt_place", "opt_route", "bitgen") for call in calls)
        if failure:
            assert ["puts", "SHAPE30_SYNTHESIS_COMPLETED"] not in calls
            assert not any(call[0] == "open" for call in calls)
        else:
            assert ["puts", "SHAPE30_SYNTHESIS_COMPLETED"] in calls
        stub_runs.append(dict(InjectedFailure=failure, Calls=calls, ExpectedExit=int(failure is not None)))
    report = dict(Stage="synthesis_prepared_no_execution_permission", Candidate="D0300",
                  At=datetime.now(timezone(timedelta(hours=8))).isoformat(), SourceFreeze=artifact(FREEZE),
                  Program=artifact(__file__), Wrapper=artifact(wrapper_source), SourceCopies=copied,
                  Tool=artifact("D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe"),
                  PipelineInputBits=228, IndependentlyLoadedInputBits=225, ProbeInputBits=70,
                  ProbeOutputBits=67, NominalProbeIOBits=137, PipelineOutputBits=349, ObservationDataBits=64,
                  ObservationPhaseBits=3, Chunks=6, FinalChunkPaddingBits=35,
                  Hardware="PH1P35MDG324 speed-3", CapturePeriodNS=9.660, DisplayPeriodNS=13.468,
                  TclStubRuns=stub_runs, TclOnlyStubValidated=True,
                  WrapperMaterialization="Exactly four ROM defaults point to explicit absolute frozen files in this preparation; all logic/ports unchanged.",
                  Note="Stub Tcl is not TD. Resource probe225 input registers/chunk writes are not production timing; all pipeline bits dynamic. No ADC/SDC/active board/profile; no synth/place/route/bit/subst.",
                  TDStarted=False, SynthesisAllowed=False, RouteAllowed=False, BitgenAllowed=False,
                  PreparedFiles=[artifact(path) for path in sorted(OUT.iterdir()) if path.is_file()])
    (OUT / "preparation.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(artifact(OUT / "preparation.json")))


if __name__ == "__main__":
    main()
