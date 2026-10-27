"""Pure checks for the release-UI I0310R3 preparation and stage scripts."""
import ast
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
PREP = HERE / "prepare-build.py"
RUN = HERE / "run-stage.py"


def load(path, name):
    raw = path.read_bytes()
    ast.parse(raw, filename=str(path))
    namespace = {"__name__": name, "__file__": str(path)}
    exec(compile(raw, str(path), "exec"), namespace)
    return namespace


def main():
    prep = load(PREP, "i0310_prepare_test")
    ast.parse(RUN.read_bytes(), filename=str(RUN))
    mother = prep["MOTHER"]
    row = prep["binding"](mother / "preparation-result.json")
    assert row["SHA256"] == prep["MOTHER_SHA"] and row["Bytes"] == 292216
    manifest = json.loads((mother / "preparation-result.json").read_bytes())
    assert manifest["Version"] == "I0309" and len(manifest["Files"]) == 359
    original = (mother / "td/syn_1/camera_to_dsi_display.prj").read_bytes()
    project = prep["project_with_awb"](original)
    assert prep["project_with_awb"].__name__ == "project_with_awb"
    assert project.count(b'Name="CompileOrder" Val="453"') == 1
    assert (prep["OUT"] / prep["AWB_RELATIVE"]).as_posix().encode() in project
    assert prep["MOTHER"].as_posix().encode() not in project
    entries = prep["compile_entries"](project, prep["OUT"])
    assert len(entries) == 153
    assert [x for x in entries if x["Order"] == 453] == [
        {"Relative": prep["AWB_RELATIVE"], "Order": 453}]
    assert not prep["OUT"].exists(), "pure checks must not materialize j312"
    print(json.dumps({"PASS": True, "Checks": 12,
                      "PrepareSHA256": hashlib.sha256(PREP.read_bytes()).hexdigest().upper(),
                      "RunStageSHA256": hashlib.sha256(RUN.read_bytes()).hexdigest().upper()}))


if __name__ == "__main__":
    main()
