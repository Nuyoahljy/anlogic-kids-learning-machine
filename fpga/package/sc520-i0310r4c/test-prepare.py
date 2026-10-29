"""Check archive/path refusal guards without changing a prepared project."""
import argparse
import importlib.util
from pathlib import Path
import zipfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--prepared", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    script = Path(__file__).with_name("prepare.py")
    spec = importlib.util.spec_from_file_location("r4c_prepare_guard_target", script)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    prepared = args.prepared.resolve(strict=True)
    report = args.report.resolve()
    module.require(not report.exists() and not report.is_relative_to(prepared),
                   "Report must be a new file outside the prepared project")
    module.require((prepared / "preparation-result.json").is_file(),
                   "Expected an existing successful preparation")
    raw = args.archive.read_bytes()
    content, inventory = module.load_snapshot(raw)
    checks = []

    def rejects(name, operation, expected):
        try:
            operation()
        except RuntimeError as error:
            module.require(expected in str(error), "Unexpected refusal: " + str(error))
            checks.append(name)
        else:
            raise AssertionError(name + " unexpectedly accepted")

    rejects("corrupt ZIP rejected before unzip",
            lambda: module.load_snapshot(bytes([raw[0] ^ 1]) + raw[1:]), "Not the pinned")
    for unsafe in ("../outside.v", "/outside.v", "C:/outside.v",
                   "safe/../../outside.v", "safe\\outside.v"):
        rejects("unsafe ZIP member " + unsafe,
                lambda value=unsafe: module.safe_member(zipfile.ZipInfo(value)), "Unsafe archive")
    base = Path("E:/x")
    buffers, _, _ = module.adapt_sources(content, base)
    closure = module.validate_references(base, buffers, inventory["Files"])
    constant = closure["MaxUnnormalizedIPXMLLoadPathChars"] - len(base.as_posix())
    project259 = Path("E:/" + "x" * (259 - constant - 3))
    buf259, _, _ = module.adapt_sources(content, project259)
    module.require(
        module.validate_references(project259, buf259, inventory["Files"])
        ["MaxUnnormalizedIPXMLLoadPathChars"] == 259,
        "259-character path did not pass",
    )
    checks.append("259-character TD IP XML load path accepted without writes")
    project260 = Path(str(project259) + "x")
    buf260, _, _ = module.adapt_sources(content, project260)
    rejects("260-character TD IP XML load path rejected without writes",
            lambda: module.validate_references(project260, buf260, inventory["Files"]),
            "must be below 260")
    missing_rom = dict(buffers)
    missing_rom.pop(base / module.ROM["TEMPLATE_FILE"])
    rejects("missing runtime ROM rejected",
            lambda: module.validate_references(base, missing_rom, inventory["Files"]),
            "Reference is absent")
    missing_header = dict(buffers)
    missing_header.pop(base / module.HEADER)
    rejects("missing aliased header rejected",
            lambda: module.validate_references(base, missing_header, inventory["Files"]),
            "Reference is absent")

    def inventory_of(root):
        return {
            path.relative_to(root).as_posix(): module.sha(path.read_bytes())
            for path in root.rglob("*") if path.is_file()
        }

    before = inventory_of(prepared)
    rejects("existing output refused",
            lambda: module.prepare(args.archive, prepared), "Output already exists")
    module.require(before == inventory_of(prepared) and len(before) == 363,
                   "Existing prepared output changed")
    checks.append("all 363 existing output bytes and membership unchanged")
    module.require(module.sha(args.archive.read_bytes()) == module.ARCHIVE_SHA,
                   "Source ZIP changed")
    checks.append("source ZIP still pinned")
    result = {
        "At": module.datetime.now(module.timezone(module.timedelta(hours=8))).isoformat(),
        "Owner": "Codex /root/portable_builder",
        "PrepareScriptSHA256": module.sha(script.read_bytes()),
        "GuardScriptSHA256": module.sha(Path(__file__).read_bytes()),
        "ArchiveSHA256": module.ARCHIVE_SHA,
        "PreparedResult": prepared.joinpath("preparation-result.json").as_posix(),
        "PreparedResultSHA256": module.sha((prepared / "preparation-result.json").read_bytes()),
        "TestsPassed": len(checks), "Checks": checks,
        "PreparedOutputUnchanged": True, "NativeToolExecuted": False,
        "ReportIsOnlyWrittenFile": True,
    }
    module.write_new(report, module.json_bytes(result))
    print(module.json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
