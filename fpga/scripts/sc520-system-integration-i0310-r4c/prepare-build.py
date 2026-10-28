"""Prepare one explicit-restart I0310R4C project from the exact I0309 manifest.

Root supplies a SHA-bound approval containing Version=I0310R4C, exactly nine
Sources (top, pipeline, compositor, awb, adc, sdc, isp, color, spatial), and ValidationReports.
This program never starts TD and never reuses a pre-existing j319 root.
"""
import argparse
import hashlib
import json
import os
import re
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[3]
EV = ROOT / "evidence/sc520-system-integration"
MOTHER, OUT = EV / "j309", EV / "j319"
MOTHER_SHA = "12F2216F5983B67093163DACB87B7313796371810BDF0F540F9E0280EDB80898"
SOURCE_ROOTS = ("constraints", "inherited", "owned", "vendor")
RUNTIME = ("td/camera_to_dsi_display.al", "td/syn_1/camera_to_dsi_display.prj",
           "td/syn_1/camera_to_dsi_display.tcl", "td/syn_1/settings.cfg")
REPLACEMENTS = {
    "top": ("fpga/custom_project/sc520-system-integration-i0310/overlay/design_top_wrapper.v",
            "owned/fpga/custom_project/sc520-system-integration/overlay/design_top_wrapper.v", "design_top_wrapper"),
    "pipeline": ("fpga/rtl/sc520-system-integration-i0310-r4c/pixel310_pipeline.v",
                 "owned/fpga/rtl/sc520-system-integration/pixel301_pipeline.v", "pixel310_pipeline"),
    "compositor": ("fpga/rtl/sc520-system-integration-i0310/pixel310_compositor_track.v",
                   "owned/fpga/rtl/sc520-system-integration/pixel301_compositor.v", "pixel310_compositor_track"),
    "adc": ("fpga/custom_project/sc520-system-integration-i0310/constraints/pin.adc",
            "constraints/pin.adc", None),
    "sdc": ("fpga/custom_project/sc520-system-integration-i0310/constraints/production.sdc",
            "constraints/production.sdc", None),
    "isp": ("fpga/custom_project/sc520-system-integration-i0310/overlay/isp310_top.v",
            "owned/fpga/custom_project/sc520-system-integration/overlay/isp_top.v", "isp310_top"),
    "color": ("fpga/rtl/sc520-system-integration-i0310/pixel310_color_pipeline.v",
              "owned/fpga/custom_project/sc520-system-integration/overlay/pixel14_color_pipeline.v", "pixel310_color_pipeline"),
    "spatial": ("fpga/rtl/sc520-system-integration-i0310/pixel310_spatial_cal.v",
                "inherited/rtl/pixel282_spatial_cal.v", "pixel310_spatial_cal"),
}
AWB_SOURCE = "fpga/rtl/sc520-system-integration-i0310/pixel310_awb_retrigger.v"
AWB_RELATIVE = "owned/fpga/rtl/sc520-system-integration-i0310/pixel310_awb_retrigger.v"
HEADER = "owned/fpga/rtl/sc520-shape-card30/recognition30_packet.vh"
ROM = {
    "TEMPLATE_FILE": "owned/assets/templates/sc520-card-recognition/rotation-v1/templates.mem",
    "GEOMETRY_FILE": "owned/assets/templates/sc520-contour29/contour29-shapes.mem",
    "LOGO_INDEX_FILE": "owned/assets/sc520-system-integration-i0304/anlogic_logo_tile4_map.mem",
    "LOGO_PALETTE_FILE": "owned/assets/sc520-system-integration-i0304/anlogic_logo_tile4_dict.mem",
}
TOOL = Path("D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe")
TOOL_SHA = "E2E04ADA5E256DCCD017240C0F4DCFACE7F96DCA67CDE0E56E606AC0E02F827A"
HELPER = ROOT / "fpga/scripts/sc520-system-integration-i0303/owned_process.py"
HELPER_SHA = "E7FFB6CC52723E251F51228F467CAF4561F94B58892D4FE9A044628AFADB6357"


def binding(path, data=None):
    path = Path(path).resolve()
    data = path.read_bytes() if data is None else data
    return {"Path": path.as_posix(), "SHA256": hashlib.sha256(data).hexdigest().upper(), "Bytes": len(data)}


def read_bound(row):
    path = Path(row["Path"])
    if not path.is_absolute() or path.is_symlink() or path.stat().st_file_attributes & 0x400:
        raise RuntimeError("Non-absolute/reparse input: " + str(path))
    data = path.read_bytes()
    if binding(path, data) != row:
        raise RuntimeError("Input identity mismatch: " + str(path))
    return data


def write(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as stream:
        stream.write(data)
    return binding(path, data)


def save(path, value):
    return write(path, (json.dumps(value, ensure_ascii=True, indent=2) + "\n").encode("ascii"))


def members(root):
    result = set()
    for current, dirs, names in os.walk(root, followlinks=False):
        for name in dirs + names:
            item = Path(current) / name
            if item.is_symlink() or item.stat().st_file_attributes & 0x400:
                raise RuntimeError("Reparse member: " + str(item))
        result.update((Path(current) / name).relative_to(root).as_posix() for name in names)
    return result


def replace_once(data, old, new):
    if data.count(old) != 1 or new in data:
        raise RuntimeError("Missing/ambiguous adapter: " + repr(old))
    return data.replace(old, new, 1)


def compile_entries(project, root):
    parsed = ET.fromstring(project.decode("utf-8-sig").replace("&", "&amp;").replace("::", "__TD_COLON__"))
    if parsed.findtext("HardWare/Device") != "PH1P35MDG324" or parsed.findtext("HardWare/Speed") != "-3":
        raise RuntimeError("Wrong production device")
    if parsed.findtext("TOP_MODULE/MODULE") != "design_top_wrapper":
        raise RuntimeError("Wrong top")
    result = []
    for kind in ("Verilog", "System_Verilog"):
        for node in parsed.findall("Source_Files/" + kind + "/File"):
            attrs = {x.get("Name"): x.get("Val") for x in node.findall("FileInfo/Attr")}
            if attrs.get("UsedInSyn") == "true":
                relative = Path(node.attrib["Path"]).resolve().relative_to(root.resolve()).as_posix()
                result.append({"Relative": relative, "Order": int(attrs["CompileOrder"])})
    if len({r["Relative"] for r in result}) != len(result) or len({r["Order"] for r in result}) != len(result):
        raise RuntimeError("Duplicate compile file/order")
    return result


def project_with_awb(original):
    old_root, new_root = MOTHER.as_posix().encode(), OUT.as_posix().encode()
    if old_root not in original or new_root in original:
        raise RuntimeError("Project root adapter is ambiguous")
    awb_path = (OUT / AWB_RELATIVE).as_posix().encode()
    if awb_path in original or b'Name="CompileOrder" Val="453"' in original:
        raise RuntimeError("AWB compile slot already exists")
    marker = b"    </Verilog>"
    if original.count(marker) != 1:
        raise RuntimeError("Verilog project section is not unique")
    block = (b'      <File Path="' + awb_path + b'">\n'
             b'        <FileInfo>\n'
             b'          <Attr Name="UsedInSyn" Val="true" />\n'
             b'          <Attr Name="UsedInP&R" Val="true" />\n'
             b'          <Attr Name="BelongTo" Val="design_1" />\n'
             b'          <Attr Name="CompileOrder" Val="453" />\n'
             b'        </FileInfo>\n'
             b'      </File>\n')
    output = original.replace(old_root, new_root).replace(marker, block + marker, 1)
    inverse = output.replace(block, b"", 1).replace(new_root, old_root)
    if inverse != original:
        raise RuntimeError("Project changed beyond root mapping and AWB insertion")
    return output


def synth_launcher():
    return b'''proc i0310r4c_synthesis {} {
source settings.cfg
if {$device_name ne "ph1_35p.db" || $package_name ne "PH1P35MDG324" || $speed ne "3" || $run_type ne "syn" || $start_step ne "read_design" || $end_step ne "opt_gate"} {error "Wrong I0310R4C synthesis settings"}
foreach command {place route bitgen insert_debugger} {proc $command {args} {error "Outside I0310R4C synthesis"}}
source camera_to_dsi_display.tcl
write_verilog i0310r4c-synthesis-netlist.v
report_clock_summary -file i0310r4c-clocks.rpt
report_timing_summary -file i0310r4c-timing.rpt
report_timing_exception -file i0310r4c-exceptions.rpt
report_timing_ignored -file i0310r4c-ignored.rpt
}
if {[catch {i0310r4c_synthesis} reason]} {puts stderr $reason; exit 1}
puts "I0310R4C_SYNTHESIS_NATIVE_COMPLETE"
exit 0
'''


def prepare(approval_path, approval_sha):
    if any(os.path.lexists(EV / name) for name in ("j319", "q320", "r320", "b320")):
        raise RuntimeError("One of j319/q320/r320/b320 already exists")
    approval_row = binding(approval_path)
    if approval_row["SHA256"] != approval_sha.upper():
        raise RuntimeError("Approval SHA mismatch")
    approval = json.loads(read_bound(approval_row))
    if approval.get("Version") != "I0310R4C" or set(approval.get("Sources", {})) != set(REPLACEMENTS) | {"awb"}:
        raise RuntimeError("Approval must bind nine exact I0310R4C sources")
    if not approval.get("ValidationReports"):
        raise RuntimeError("Validation reports are required")
    mother_row = {"Path": (MOTHER / "preparation-result.json").as_posix(),
                  "SHA256": MOTHER_SHA, "Bytes": 292216}
    mother = json.loads(read_bound(mother_row))
    if (mother.get("Version"), mother.get("Prepared"), len(mother.get("Files", {})),
            mother.get("PhysicalSourceFiles"), mother.get("SourceRoles"), mother.get("CompileCount")) != (
            "I0309", True, 359, 354, 352, 152):
        raise RuntimeError("Wrong I0309 preparation baseline")
    inputs = [approval_row, mother_row] + approval["ValidationReports"]
    buffers = {}
    for relative, row in mother["Files"].items():
        buffers[relative] = read_bound(row)
        inputs.append(row)
    source_names = {name for name in buffers if name.split("/", 1)[0] in SOURCE_ROOTS}
    if len(source_names) != 354:
        raise RuntimeError("I0309 physical source inventory differs")
    adapters = {}
    for role, (candidate_relative, output_relative, module) in REPLACEMENTS.items():
        candidate = ROOT / candidate_relative
        selected = approval["Sources"][role]
        if Path(selected["Path"]).resolve() != candidate.resolve():
            raise RuntimeError("Redirected role: " + role)
        raw = read_bound(selected)
        inputs.append(selected)
        if module and len(re.findall(rb"(?m)^module\s+" + module.encode() + rb"\b", raw)) != 1:
            raise RuntimeError("Module mismatch: " + role)
        changes = []
        if role == "pipeline":
            changes.append((b'`include "recognition30_packet.vh"',
                            b'`include "' + (OUT / HEADER).as_posix().encode() + b'"'))
        if role == "top":
            for parameter, relative in ROM.items():
                changes.append((("." + parameter + '("' + Path(relative).name + '")').encode(),
                                ("." + parameter + '("' + (OUT / relative).as_posix() + '")').encode()))
        adapted = raw
        for old, new in changes:
            adapted = replace_once(adapted, old, new)
        inverse = adapted
        for old, new in reversed(changes):
            inverse = replace_once(inverse, new, old)
        if inverse != raw:
            raise RuntimeError("Non-path candidate rewrite: " + role)
        if output_relative not in buffers:
            raise RuntimeError("Replacement is absent from I0309: " + output_relative)
        buffers[output_relative] = adapted
        adapters[role] = [{"From": a.decode(), "To": b.decode()} for a, b in changes]
    awb_selected = approval["Sources"]["awb"]
    awb_candidate = ROOT / AWB_SOURCE
    if Path(awb_selected["Path"]).resolve() != awb_candidate.resolve():
        raise RuntimeError("Redirected role: awb")
    awb_raw = read_bound(awb_selected)
    inputs.append(awb_selected)
    if len(re.findall(rb"(?m)^module\s+pixel310_awb_retrigger\b", awb_raw)) != 1:
        raise RuntimeError("AWB module mismatch")
    if AWB_RELATIVE in buffers:
        raise RuntimeError("AWB source already exists")
    buffers[AWB_RELATIVE] = awb_raw

    original_project = buffers[RUNTIME[1]]
    if buffers[RUNTIME[0]] != original_project:
        raise RuntimeError("AL/prj baseline bytes differ")
    mother_compiled = compile_entries(original_project, MOTHER)
    if len(mother_compiled) != 152 or max(r["Order"] for r in mother_compiled) != 452:
        raise RuntimeError("I0309 compile inventory differs")
    project = project_with_awb(original_project)
    buffers[RUNTIME[0]] = buffers[RUNTIME[1]] = project
    for name in RUNTIME[2:]:
        buffers[name] = buffers[name].replace(MOTHER.as_posix().encode(), OUT.as_posix().encode())
    buffers["td/syn_1/synth.launch.tcl"] = synth_launcher()
    compiled = compile_entries(project, OUT)
    if len(compiled) != 153 or {r["Order"] for r in compiled} != {r["Order"] for r in mother_compiled} | {453}:
        raise RuntimeError("Expected 153 compile entries ending at order453")
    if [r for r in compiled if r["Relative"] == AWB_RELATIVE] != [{"Relative": AWB_RELATIVE, "Order": 453}]:
        raise RuntimeError("AWB compile entry differs")
    if any(r["Relative"] not in buffers for r in compiled):
        raise RuntimeError("Compile entry lacks prepared bytes")
    for label, (path, expected_sha) in (("TD", (TOOL, TOOL_SHA)), ("Helper", (HELPER, HELPER_SHA))):
        row = binding(path)
        if row["SHA256"] != expected_sha:
            raise RuntimeError(label + " changed")
        inputs.append(row)
    scripts = [binding(Path(__file__).resolve())]
    inputs += scripts
    for donor in ("q310", "r310"):
        inputs.append(binding(EV / donor / "td/pl_1/settings.cfg"))
    for row in inputs:
        read_bound(row)
    OUT.mkdir()
    for name, data in sorted(buffers.items()):
        write(OUT / name, data)
    if members(OUT) != set(buffers):
        raise RuntimeError("Unexpected output member")
    for row in inputs:
        read_bound(row)
    for name, data in buffers.items():
        if (OUT / name).read_bytes() != data:
            raise RuntimeError("Output changed: " + name)
    report = {
        "Version": "I0310R4C", "Prepared": True, "Root": OUT.as_posix(), "Inputs": inputs,
        "Files": {name: binding(OUT / name, data) for name, data in sorted(buffers.items())},
        "SourceApproval": approval_row, "Adapters": adapters, "CompileEntries": compiled,
        "FormalRoles": mother["FormalRoles"] + [AWB_RELATIVE],
        "PhysicalSourceFiles": 355, "SourceRoles": 353, "CompileCount": 153,
        "ReplacedPhysicalFiles": 8, "AddedPhysicalFiles": 1,
        "ProductionSDCChangedByApproval": True, "ProductionADCChangedByApproval": True,
        "ProductionPLLUnchanged": True, "Scripts": scripts, "DebuggerMode": "no-chip-debugger",
        "ManifestSelfExcluded": True, "Budgets": {"synthesis": 1200, "placement": 1200, "route": 7200},
        "SoftwareAcceptedByThisTool": False, "NativeExecuted": False,
        "BitgenAllowed": False, "HardwareValidated": False,
    }
    saved = save(OUT / "preparation-result.json", report)
    print(json.dumps({"Prepared": True, "Manifest": saved}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--approval", type=Path, required=True)
    parser.add_argument("--approval-sha", required=True)
    args = parser.parse_args()
    if not args.approval.is_absolute():
        parser.error("approval must be absolute")
    prepare(args.approval, args.approval_sha)
