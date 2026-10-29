"""Prepare the frozen I0310R4C ZIP in a new directory without running FPGA tools."""
import argparse
import hashlib
import io
import json
import posixpath
import re
import stat
import zipfile
from datetime import datetime, timedelta, timezone
from pathlib import Path, PurePosixPath
import xml.etree.ElementTree as ET


ARCHIVE_SHA = "ADEF639CB90DC41A1C23595ADC2D20978C881C7ADBD7A5D4F6A172312A05E96A"
OLD_BASE = "E:/juan/FPGA/worktrees/anlogic-kids-learning-machine/sc520-system-integration/evidence/sc520-system-integration"
OLD_ROOT = OLD_BASE + "/j319"
HEADER = "owned/fpga/rtl/sc520-shape-card30/recognition30_packet.vh"
HEADER_SHA = "D4D30699B37C96042FCFA0EAF40940AACCCF6E20124105A7F10E38B3DC21EA93"
AL = "td/camera_to_dsi_display.al"
PRJ = "td/syn_1/camera_to_dsi_display.prj"
CFG = "td/syn_1/settings.cfg"
TOP = "owned/fpga/custom_project/sc520-system-integration/overlay/design_top_wrapper.v"
JOIN = "owned/fpga/rtl/sc520-shape-card30/items30_result_join.v"
PIPE30 = "owned/fpga/rtl/sc520-shape-card30/pixel30_pipeline.v"
PIPE301 = "owned/fpga/rtl/sc520-system-integration/pixel301_pipeline.v"
EDIT_RULES = {
    AL: (OLD_ROOT, 164),
    PRJ: (OLD_ROOT, 164),
    CFG: (OLD_ROOT, 5),
    TOP: (OLD_ROOT, 4),
    JOIN: (OLD_BASE + "/j309", 1),
    PIPE30: (OLD_BASE + "/j305", 1),
    PIPE301: (OLD_ROOT, 1),
}
ROM = {
    "TEMPLATE_FILE": "owned/assets/templates/sc520-card-recognition/rotation-v1/templates.mem",
    "GEOMETRY_FILE": "owned/assets/templates/sc520-contour29/contour29-shapes.mem",
    "LOGO_INDEX_FILE": "owned/assets/sc520-system-integration-i0304/anlogic_logo_tile4_map.mem",
    "LOGO_PALETTE_FILE": "owned/assets/sc520-system-integration-i0304/anlogic_logo_tile4_dict.mem",
}


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha(raw):
    return hashlib.sha256(raw).hexdigest().upper()


def json_bytes(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def write_new(path, raw):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as stream:
        stream.write(raw)


def safe_member(entry):
    name = entry.filename
    path = PurePosixPath(name)
    require(
        not entry.is_dir()
        and entry.orig_filename == name
        and not path.is_absolute()
        and path.as_posix() == name
        and all(part not in (".", "..") and part == part.rstrip(" .") for part in path.parts)
        and "\\" not in name
        and ":" not in name
        and not stat.S_ISLNK(entry.external_attr >> 16),
        "Unsafe archive member: " + name,
    )


def load_snapshot(raw_zip):
    require(sha(raw_zip) == ARCHIVE_SHA, "Not the pinned I0310R4C source ZIP")
    with zipfile.ZipFile(io.BytesIO(raw_zip)) as package:
        infos = package.infolist()
        names = [entry.filename for entry in infos]
        require(len(names) == len({name.casefold() for name in names}) == 361,
                "Wrong or duplicate ZIP member inventory")
        for entry in infos:
            safe_member(entry)
        content = {name: package.read(name) for name in names}
    inventory = json.loads(content["snapshot-manifest.json"])
    require(inventory["Version"] == "I0310R4C", "Wrong snapshot version")
    files = inventory["Files"]
    require(len(files) == 360 and set(files) == set(content) - {"snapshot-manifest.json"},
            "Snapshot manifest does not cover exactly 360 source files")
    for rel, binding in files.items():
        require(len(content[rel]) == binding["Bytes"] and sha(content[rel]) == binding["SHA256"],
                "Snapshot member binding mismatch: " + rel)
        require(binding["Path"] == OLD_ROOT + "/" + rel, "Unexpected original source role: " + rel)
    require(sha(content[HEADER]) == HEADER_SHA and len(content[HEADER]) == 917,
            "The pinned legacy header alias is inapplicable")
    return content, inventory


def adapt_sources(content, project):
    buffers, edits, mapping = {}, [], []
    for member, original in content.items():
        is_source = member != "snapshot-manifest.json"
        target = project / member if is_source else project.parent / "archive" / member
        derived = original
        if member in EDIT_RULES:
            prefix, expected = EDIT_RULES[member]
            old, new = prefix.encode("ascii"), project.as_posix().encode("ascii")
            require(new not in original, "New output prefix already occurs in source: " + member)
            require(original.count(old) == expected, "Unexpected replacement count: " + member)
            derived = original.replace(old, new)
            require(derived.replace(new, old) == original, "Non-path bytes changed: " + member)
            edits.append({
                "File": member, "OldPrefix": prefix, "NewPrefix": new.decode("ascii"),
                "Replacements": expected, "OriginalSHA256": sha(original),
                "DerivedSHA256": sha(derived), "ReverseReplacementExact": True,
            })
        require(target.is_relative_to(project.parent), "Output path leaves its directory")
        buffers[target] = derived
        mapping.append({
            "Member": member, "Output": target.relative_to(project.parent).as_posix(),
            "OriginalSHA256": sha(original), "DerivedSHA256": sha(derived),
            "OriginalBytes": len(original), "DerivedBytes": len(derived),
            "PathAdapted": derived != original,
            "Role": "prepared-project" if is_source else "historical-manifest",
        })
    require(len(edits) == sum(row["PathAdapted"] for row in mapping) == 7,
            "The adaptation escaped the seven-file allowlist")
    return buffers, edits, mapping


def validate_references(project, buffers, source_files):
    """Resolve against planned bytes before creating any destination directory."""
    def inside_file(value, parent=project):
        path = Path(value)
        resolved = path.resolve() if path.is_absolute() else (parent / path).resolve()
        require(resolved.is_relative_to(project) and resolved in buffers,
                "Reference is absent or leaves the prepared project: " + value)
        return resolved

    def text(rel):
        return buffers[project / rel].decode("utf-8-sig")

    refs_by_file = {}
    for rel in (AL, PRJ):
        # TD property names contain "::", so its project documents are not XML.
        refs = re.findall(r'<File\s+Path="([^"]+)"', text(rel))
        require(len(refs) == 164, "Unexpected formal project reference count: " + rel)
        refs_by_file[rel] = [inside_file(value) for value in refs]
    require(refs_by_file[AL] == refs_by_file[PRJ], "AL/PRJ reference order differs")
    formal = refs_by_file[PRJ]
    require(len(set(formal)) == len(formal), "Duplicate formal project reference")
    hdl = [path for path in formal if path.suffix.lower() in (".v", ".sv", ".vhd")]
    require(len(hdl) == 153, "Unexpected formal HDL inventory")
    xml_files = [path for path in formal if path.suffix.lower() == ".xml"]
    xml_refs, xml_loads = [], []
    run_dir = (project / "td/syn_1").as_posix()
    for path in xml_files:
        relative = posixpath.relpath(path.as_posix(), run_dir)
        unnormalized = run_dir + "/" + relative
        xml_loads.append({
            "XML": path.as_posix(), "UnnormalizedLoadPath": unnormalized,
            "Characters": len(unnormalized),
        })
        for element in ET.fromstring(buffers[path]).iter():
            if element.tag.split("}")[-1] == "file":
                for child in element:
                    if child.tag.split("}")[-1] == "name" and child.text:
                        xml_refs.append(inside_file(child.text, path.parent))
    require(len(xml_files) == 8 and len(xml_refs) == 58, "Unexpected IP XML fileset closure")
    longest = max(row["Characters"] for row in xml_loads)
    require(longest < 260, "TD IP XML load path reaches " + str(longest)
            + " characters (must be below 260); choose a shorter --output directory")
    ipc = [path for path in formal if path.suffix.lower() == ".ipc"]
    require(len(ipc) == 1, "Unexpected legacy IPC inventory")
    divider = ET.fromstring(buffers[ipc[0]]).find("GeneratedFiles/GateVerilog")
    require(divider is not None and divider.text is not None, "Missing divider generated output")
    inside_file(divider.text, ipc[0].parent)
    for parameter, rel in ROM.items():
        values = re.findall(r'\.' + parameter + r'\("([^"]+)"\)', text(TOP))
        require(len(values) == 1 and inside_file(values[0]) == project / rel,
                "Unexpected top-level ROM binding: " + parameter)
    for rel in (JOIN, PIPE30, PIPE301):
        includes = re.findall(r'^`include\s+"([^"]+)"', text(rel), re.MULTILINE)
        require(len(includes) == 1 and inside_file(includes[0]) == project / HEADER,
                "Unexpected task header reference: " + rel)
    settings_refs = re.findall(r"[A-Za-z]:/[^\s\"{}]+", text(CFG))
    require(len(settings_refs) == 5, "Unexpected settings dependency count")
    for value in settings_refs:
        inside_file(value)
    # Preserve original vendor comments, encodings and conditional include paths.
    for rel in source_files:
        for line in buffers[project / rel].splitlines():
            if not line.lstrip().startswith(b"//"):
                require(OLD_BASE.encode("ascii") not in line, "Active old build path remains: " + rel)
    require(b".SHAPE_ENABLE(0),.TRACK_ENABLE(1)" in buffers[project / TOP],
            "Frozen five-card production configuration changed")
    return {
        "FormalCompileEntries": len(hdl), "ProjectReferencesPerFile": len(formal),
        "IPXMLFiles": len(xml_files), "IPFilesetReferences": len(xml_refs),
        "LegacyIPCOutputs": 1, "ROMReferences": len(ROM), "TaskHeaderReferences": 3,
        "SettingsReferences": len(settings_refs),
        "MaxUnnormalizedIPXMLLoadPathChars": longest, "UnnormalizedIPXMLLoadPaths": xml_loads,
    }


def prepare(archive, output):
    archive = archive.resolve(strict=True)
    output = output.resolve()
    require(not output.exists(), "Output already exists; choose a new directory")
    require(re.fullmatch(r"[A-Za-z]:/[A-Za-z0-9_./-]+", output.as_posix()),
            "Use an absolute Windows output path with only ASCII letters/digits, /, _, -, and .")
    project = output / "project"
    raw_zip = archive.read_bytes()
    content, inventory = load_snapshot(raw_zip)
    buffers, edits, mapping = adapt_sources(content, project)
    closure = validate_references(project, buffers, inventory["Files"])
    protected = [
        rel for rel in inventory["Files"]
        if rel.endswith((".sdc", ".adc")) or "/PLL/" in rel
    ]
    for rel in protected:
        require(buffers[project / rel] == content[rel], "Constraint/PLL bytes changed: " + rel)
    output.mkdir(parents=True, exist_ok=False)
    try:
        for target, raw in buffers.items():
            write_new(target, raw)
        for target, raw in buffers.items():
            require(target.read_bytes() == raw, "Written output mismatch: " + str(target))
        require(archive.read_bytes() == raw_zip, "Source ZIP changed during preparation")
        path_map = {
            "Version": "I0310R4C-portable-preparation-v1", "ProjectRoot": project.as_posix(),
            "LegacyHeaderAliases": {
                "ArchiveMember": HEADER, "SHA256": HEADER_SHA, "Bytes": 917,
                "OldBuilds": ["j309", "j305"], "OriginalSourcePathsOpened": False,
            },
            "Edits": edits, "Files": mapping,
        }
        write_new(output / "path-map.json", json_bytes(path_map))
        result = {
            "Version": "I0310R4C-portable-preparation-v1", "Prepared": True,
            "At": datetime.now(timezone(timedelta(hours=8))).isoformat(),
            "Owner": "Codex /root/portable_builder",
            "Archive": {"Path": archive.as_posix(), "SHA256": ARCHIVE_SHA, "Bytes": len(raw_zip)},
            "PrepareScriptSHA256": sha(Path(__file__).read_bytes()),
            "Output": output.as_posix(), "OpenProject": (project / AL).as_posix(),
            "ArchiveMembersVerified": len(content), "ProjectFiles": len(inventory["Files"]),
            "ArchivedFiles": 1, "PathAdaptedFiles": len(edits), "UnchangedProjectFiles": 353,
            "ConstraintAndPLLFilesUnchanged": len(protected),
            "AllWrittenBytesVerified": True, "NonPathBytesUnchanged": True,
            "SourceArchiveUnchanged": True, "OriginalSourcePathsOpened": False,
            "PathMapSHA256": sha((output / "path-map.json").read_bytes()),
            "LongestPreparedFilePath": max(len(path.as_posix()) for path in buffers),
            "ProductionConfiguration": {"ShapeEnable": False, "TrackEnable": True, "CardClasses": 5},
            "TDVersionRequired": "6.2.1 Engineer 6.2.168.116",
            "NativeToolExecuted": False, "ProjectOpenedInTD": False,
            "SynthesisVerified": False, "NewBitstreamGenerated": False, "HardwareValidated": False,
            **closure,
        }
        write_new(output / "preparation-result.json", json_bytes(result))
        return result
    except Exception as error:
        write_new(output / "failure.json", json_bytes({
            "Prepared": False, "Error": str(error), "PartialOutputPreserved": True,
        }))
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True, help="A directory that does not exist")
    args = parser.parse_args()
    print(json.dumps(prepare(args.archive, args.output), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
