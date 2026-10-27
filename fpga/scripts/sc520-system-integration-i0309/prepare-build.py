"""I0309 preparation only. Root supplies a SHA-bound JSON: Version, Sources (9 role rows),
ValidationReports (exact result rows). Each row has Path/SHA256/Bytes. No native tool runs.
Usage: python -I -B prepare-build.py --approval ABS_JSON --approval-sha SHA256
"""
import argparse, hashlib, json, os, re
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[3]
EV = ROOT / "evidence/sc520-system-integration"
MOTHER, OUT = EV / "j308", EV / "j309"
MOTHER_SHA = "BF40B3129D613CF47CF99BFEC3F515EC28AF27CC37575C625419EC6CB36B55FE"
SOURCE_ROOTS = ("constraints", "inherited", "owned", "vendor")
RUNTIME = ("td/camera_to_dsi_display.al", "td/syn_1/camera_to_dsi_display.prj",
           "td/syn_1/camera_to_dsi_display.tcl", "td/syn_1/settings.cfg")
ROLES = {
    "arbitrate": ("pixel309_arbitrate.v", "owned/fpga/rtl/sc520-shape-card30/pixel30_arbitrate.v", 427),
    "join": ("pixel309_result_join.v", "owned/fpga/rtl/sc520-shape-card30/items30_result_join.v", 429),
    "qbank": ("pixel309_question_bank.v", "owned/fpga/rtl/sc520-shape-card30/items30_question_bank.v", 430),
    "quiz": ("pixel309_quiz_control.v", "owned/fpga/rtl/sc520-shape-card30/items30_quiz_control.v", 431),
    "system": ("pixel309_system.v", "owned/fpga/rtl/sc520-shape-card30/items30_system.v", 432),
    "compositor": ("pixel309_compositor_track.v", "owned/fpga/rtl/sc520-system-integration/pixel301_compositor.v", 440),
    "pipeline": ("pixel309_pipeline.v", "owned/fpga/rtl/sc520-system-integration/pixel301_pipeline.v", 442),
    "top": ("design_top_wrapper.v", "owned/fpga/custom_project/sc520-system-integration/overlay/design_top_wrapper.v", 1),
    "caption": ("pixel309_track_caption.v", "owned/fpga/rtl/sc520-system-integration-i0309/pixel309_track_caption.v", 440),
}
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
    path = Path(path); path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as stream: stream.write(data)
    return binding(path, data)

def save(path, value):
    return write(path, (json.dumps(value, ensure_ascii=True, indent=2) + "\n").encode("ascii"))

def members(root):
    result = set()
    for current, dirs, names in os.walk(root, followlinks=False):
        for name in dirs + names:
            p = Path(current) / name
            if p.is_symlink() or p.stat().st_file_attributes & 0x400:
                raise RuntimeError("Reparse member: " + str(p))
        result.update((Path(current) / name).relative_to(root).as_posix() for name in names)
    return result

def replace_once(data, old, new):
    if data.count(old) != 1 or new in data:
        raise RuntimeError("Missing/ambiguous path adapter: " + repr(old))
    return data.replace(old, new, 1)

def compile_entries(project, root):
    parsed = ET.fromstring(project.decode("utf-8-sig").replace("&", "&amp;").replace("::", "__TD_COLON__"))
    if parsed.findtext("HardWare/Device") != "PH1P35MDG324" or parsed.findtext("HardWare/Speed") != "-3":
        raise RuntimeError("Wrong production device")
    if parsed.findtext("TOP_MODULE/MODULE") != "design_top_wrapper": raise RuntimeError("Wrong top")
    result = []
    for kind in ("Verilog", "System_Verilog"):
        for node in parsed.findall("Source_Files/" + kind + "/File"):
            attrs = {x.get("Name"): x.get("Val") for x in node.findall("FileInfo/Attr")}
            if attrs.get("UsedInSyn") == "true":
                rel = Path(node.attrib["Path"]).resolve().relative_to(root.resolve()).as_posix()
                result.append({"Relative": rel, "Order": int(attrs["CompileOrder"])})
    if len({r["Relative"] for r in result}) != len(result) or len({r["Order"] for r in result}) != len(result):
        raise RuntimeError("Duplicate compile file/order")
    return result

def project_with_caption(original):
    old, new = MOTHER.as_posix().encode(), OUT.as_posix().encode()
    if old not in original: raise RuntimeError("Project does not name j308")
    shifted = re.sub(rb'(Name="CompileOrder" Val=")([0-9]+)(")',
                     lambda m: m[1] + str(int(m[2]) + (int(m[2]) >= 440)).encode() + m[3], original)
    target = (MOTHER / ROLES["compositor"][1]).as_posix().encode()
    pattern = rb'<File Path="' + re.escape(target) + rb'">.*?</File>'
    blocks = re.findall(pattern, shifted, re.S)
    if len(blocks) != 1: raise RuntimeError("Compositor project slot is not unique")
    caption = blocks[0].replace(target, (MOTHER / ROLES["caption"][1]).as_posix().encode())
    caption = replace_once(caption, b'Name="CompileOrder" Val="441"', b'Name="CompileOrder" Val="440"')
    insertion = caption + b"\n      "
    output = shifted.replace(blocks[0], insertion + blocks[0], 1).replace(old, new)
    inverse = output.replace(new, old).replace(insertion, b"", 1)
    inverse = re.sub(rb'(Name="CompileOrder" Val=")([0-9]+)(")',
                     lambda m: m[1] + str(int(m[2]) - (int(m[2]) >= 441)).encode() + m[3], inverse)
    if inverse != original: raise RuntimeError("Project changed beyond insertion/order/path mapping")
    return output

def synth_launcher():
    return b'''proc i0309_synthesis {} {
source settings.cfg
if {$device_name ne "ph1_35p.db" || $package_name ne "PH1P35MDG324" || $speed ne "3" || $run_type ne "syn" || $start_step ne "read_design" || $end_step ne "opt_gate"} {error "Wrong I0309 synthesis settings"}
foreach command {place route bitgen insert_debugger} {proc $command {args} {error "Outside I0309 synthesis"}}
source camera_to_dsi_display.tcl
write_verilog i0309-synthesis-netlist.v
report_clock_summary -file i0309-clocks.rpt
report_timing_summary -file i0309-timing.rpt
report_timing_exception -file i0309-exceptions.rpt
report_timing_ignored -file i0309-ignored.rpt
}
if {[catch {i0309_synthesis} reason]} {puts stderr $reason; exit 1}
puts "I0309_SYNTHESIS_NATIVE_COMPLETE"
exit 0
'''

def prepare(approval_path, approval_sha):
    if any(os.path.lexists(EV / name) for name in ("j309", "q310", "r310")):
        raise RuntimeError("One of j309/q310/r310 already exists; never reuse output roots")
    approval_row = binding(approval_path)
    if approval_row["SHA256"] != approval_sha.upper(): raise RuntimeError("Approval SHA mismatch")
    approval = json.loads(read_bound(approval_row))
    if approval.get("Version") != "I0309" or set(approval.get("Sources", {})) != set(ROLES):
        raise RuntimeError("Root approval must bind the exact nine I0309 sources")
    if not approval.get("ValidationReports"): raise RuntimeError("Root must bind final source validation reports")
    mother_row = {"Path": (MOTHER / "preparation-result.json").as_posix(), "SHA256": MOTHER_SHA, "Bytes": 974326}
    mother = json.loads(read_bound(mother_row))
    if mother["Version"] != "I0308" or not mother["AcceptedCandidate"] or len(mother["Files"]) != 351 or len(mother["Sources"]) != 151:
        raise RuntimeError("Invalid j308 role/compile baseline")
    inputs = [approval_row, mother_row] + approval["ValidationReports"]
    old_rows = {r["Relative"]: {k: r[k] for k in ("Path", "SHA256", "Bytes")} for r in mother["Generated"]["Files"]}
    source_names = {n for n in old_rows if n.split("/", 1)[0] in SOURCE_ROOTS}
    actual_names = {prefix + "/" + n for prefix in SOURCE_ROOTS for n in members(MOTHER / prefix)}
    if len(source_names) != 353 or actual_names != source_names: raise RuntimeError("353-source inventory differs")
    formal = [Path(r["Snapshot"]).resolve().relative_to(MOTHER.resolve()).as_posix() for r in mother["Files"]]
    if len(set(formal)) != 351 or not set(formal).issubset(source_names): raise RuntimeError("351 formal roles differ")
    if not {v[1] for k, v in ROLES.items() if k != "caption"}.issubset(formal): raise RuntimeError("Replacement outside formal roles")
    buffers = {n: read_bound(old_rows[n]) for n in source_names | set(RUNTIME)}
    inputs += [old_rows[n] for n in sorted(source_names | set(RUNTIME))]
    inputs += mother["InheritedDependencyInputs"]
    adapters = {}
    for role, (filename, relative, slot) in ROLES.items():
        candidate = (ROOT / "fpga/custom_project/sc520-system-integration-i0309/overlay" / filename if role == "top"
                     else ROOT / "fpga/rtl/sc520-system-integration-i0309" / filename)
        selected = approval["Sources"][role]
        if Path(selected["Path"]).resolve() != candidate.resolve(): raise RuntimeError("Redirected role: " + role)
        raw = read_bound(selected); inputs.append(selected)
        module = b"design_top_wrapper" if role == "top" else Path(filename).stem.encode()
        if len(re.findall(rb"(?m)^module\s+" + module + rb"\b", raw)) != 1: raise RuntimeError("Module mismatch: " + role)
        changes = []
        if role in ("pipeline", "join"):
            changes.append((b'`include "recognition30_packet.vh"', b'`include "' + (OUT / HEADER).as_posix().encode() + b'"'))
        if role == "top":
            for parameter, path in ROM.items():
                changes.append((("." + parameter + '("' + Path(path).name + '")').encode(),
                                ("." + parameter + '("' + (OUT / path).as_posix() + '")').encode()))
        adapted = raw
        for old, new in changes: adapted = replace_once(adapted, old, new)
        inverse = adapted
        for old, new in reversed(changes): inverse = replace_once(inverse, new, old)
        if inverse != raw: raise RuntimeError("Non-path candidate rewrite: " + role)
        buffers[relative] = adapted
        adapters[role] = [{"From": a.decode(), "To": b.decode()} for a, b in changes]
    if ROLES["caption"][1] in source_names: raise RuntimeError("Caption already existed")
    changed = {n for n in source_names if binding(MOTHER / n, buffers[n]) != old_rows[n]}
    if changed != {v[1] for k, v in ROLES.items() if k != "caption"}: raise RuntimeError("Delta is not exactly eight replacements")
    original_project = buffers[RUNTIME[1]]
    if buffers[RUNTIME[0]] != original_project: raise RuntimeError("AL/prj baseline bytes differ")
    old_compile = compile_entries(original_project, MOTHER)
    if len(old_compile) != 151: raise RuntimeError("151 baseline compile entries required")
    for role, (_, rel, slot) in ROLES.items():
        if role != "caption" and [r["Order"] for r in old_compile if r["Relative"] == rel] != [slot]:
            raise RuntimeError("Wrong replacement compile slot: " + role)
    project = project_with_caption(original_project)
    buffers[RUNTIME[0]] = buffers[RUNTIME[1]] = project
    for name in RUNTIME[2:]: buffers[name] = buffers[name].replace(MOTHER.as_posix().encode(), OUT.as_posix().encode())
    buffers["td/syn_1/synth.launch.tcl"] = synth_launcher()
    compiled = compile_entries(project, OUT)
    if len(compiled) != 152 or any(r["Relative"] not in buffers for r in compiled): raise RuntimeError("152 compile entries required")
    for name, expected in (("TD", (TOOL, TOOL_SHA)), ("Helper", (HELPER, HELPER_SHA))):
        item = binding(expected[0])
        if item["SHA256"] != expected[1]: raise RuntimeError(name + " changed")
        inputs.append(item)
    # Native runner is reviewed separately; preparation does not depend on its draft.
    scripts = [binding(Path(__file__).resolve())]
    inputs += scripts
    for old_stage in ("q309", "r309"):
        inputs.append(binding(EV / old_stage / "td/pl_1/settings.cfg"))
    for row in inputs: read_bound(row)
    # No output directory exists before all source, project, and dependency checks pass.
    OUT.mkdir()
    for name, data in sorted(buffers.items()): write(OUT / name, data)
    if members(OUT) != set(buffers): raise RuntimeError("Unexpected materialized output member")
    for row in inputs: read_bound(row)
    for name, data in buffers.items():
        if (OUT / name).read_bytes() != data: raise RuntimeError("Output buffer changed: " + name)
    report = {"Version": "I0309", "Prepared": True, "Root": OUT.as_posix(), "Inputs": inputs,
              "Files": {n: binding(OUT / n, data) for n, data in sorted(buffers.items())},
              "SourceApproval": approval_row, "Adapters": adapters, "CompileEntries": compiled,
              "FormalRoles": formal + [ROLES["caption"][1]],
              "PhysicalSourceFiles": 354, "SourceRoles": 352, "CompileCount": 152,
              "ReplacedRoles": 8, "AddedRoles": 1, "UnchangedRoles": 343, "PhysicalUnchangedFiles": 345,
              "ProductionSDCUnchanged": True, "ProductionADCUnchanged": True, "ProductionPLLUnchanged": True,
              "Scripts": scripts, "DebuggerMode": "no-chip-debugger", "ManifestSelfExcluded": True,
              "Budgets": {"synthesis": 1200, "placement": 1200, "route": 7200},
              "SoftwareAcceptedByThisTool": False, "NativeExecuted": False, "BitgenAllowed": False}
    saved = save(OUT / "preparation-result.json", report)
    print(json.dumps({"Prepared": True, "Manifest": saved}))

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--approval", type=Path, required=True)
    parser.add_argument("--approval-sha", required=True)
    args = parser.parse_args()
    if not args.approval.is_absolute(): parser.error("approval must be absolute")
    prepare(args.approval, args.approval_sha)
