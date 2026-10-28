"""Pure preparation, stage-isolation and bitgen-binding checks for I0310R4C."""
import argparse
import ast
from datetime import datetime, timedelta, timezone
import hashlib
import json
from pathlib import Path
from types import SimpleNamespace

HERE = Path(__file__).resolve().parent
OLD = HERE.with_name("sc520-system-integration-i0310-r4b")
ROOT = HERE.parents[2]
EV = ROOT / "evidence/sc520-system-integration"


def bind(path):
    raw = path.read_bytes()
    return {"Path": path.resolve().as_posix(), "Bytes": len(raw),
            "SHA256": hashlib.sha256(raw).hexdigest().upper()}


def load(path):
    raw = path.read_bytes()
    ast.parse(raw, filename=str(path))
    namespace = {"__name__": "pure_r4c_test", "__file__": str(path)}
    exec(compile(raw, str(path), "exec"), namespace)
    return namespace


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    old_files = [OLD / name for name in ("prepare-build.py", "run-stage.py", "run-bitgen.py", "run-physical-seed1.py")]
    before_old = [bind(p) for p in old_files]
    before_roots = {name: (EV / name).exists() for name in ("j319", "q320", "r320", "b320", "q318", "r318", "b318")}
    prep, stage, bit = [load(HERE / name) for name in ("prepare-build.py", "run-stage.py", "run-bitgen.py")]
    old_prep, old_stage = [load(OLD / name) for name in ("prepare-build.py", "run-stage.py")]
    checks = []

    def check(name, condition):
        if not condition: raise AssertionError(name)
        checks.append(name)

    def reject(name, callback, substring):
        try:
            callback()
        except RuntimeError as error:
            check(name, substring in str(error))
        else:
            raise AssertionError(name + " did not reject")

    check("prepare j319 from unchanged j309", prep["OUT"] == EV / "j319" and prep["MOTHER"] == old_prep["MOTHER"])
    check("same exact mother hash", prep["MOTHER_SHA"] == old_prep["MOTHER_SHA"] == bind(prep["MOTHER"] / "preparation-result.json")["SHA256"])
    check("exactly nine source roles", len(prep["REPLACEMENTS"]) == 8 and prep["AWB_SOURCE"] == old_prep["AWB_SOURCE"])
    expected_roles = dict(old_prep["REPLACEMENTS"])
    expected_roles["pipeline"] = ("fpga/rtl/sc520-system-integration-i0310-r4c/pixel310_pipeline.v", *expected_roles["pipeline"][1:])
    check("pipeline only author path change", prep["REPLACEMENTS"] == expected_roles)
    check("same pipeline module and snapshot role", prep["REPLACEMENTS"]["pipeline"][1:] == old_prep["REPLACEMENTS"]["pipeline"][1:])
    check("ROM and AWB snapshot contracts unchanged", prep["ROM"] == old_prep["ROM"] and prep["AWB_RELATIVE"] == old_prep["AWB_RELATIVE"])
    check("fixed native tools unchanged", (prep["TOOL"], prep["TOOL_SHA"], prep["HELPER"], prep["HELPER_SHA"]) == (old_prep["TOOL"], old_prep["TOOL_SHA"], old_prep["HELPER"], old_prep["HELPER_SHA"]))
    original = (prep["MOTHER"] / "td/syn_1/camera_to_dsi_display.prj").read_bytes()
    adapted = prep["project_with_awb"](original)
    compiled = prep["compile_entries"](adapted, prep["OUT"])
    check("153 unique compile entries", len(compiled) == 153 and len({r["Relative"] for r in compiled}) == 153)
    check("one new compile slot 453", [r for r in compiled if r["Order"] == 453] == [{"Relative": prep["AWB_RELATIVE"], "Order": 453}])
    check("all project paths move to j319", prep["MOTHER"].as_posix().encode() not in adapted and prep["OUT"].as_posix().encode() in adapted)
    reject("ambiguous path replacement rejected", lambda: prep["replace_once"](b"old old", b"old", b"new"), "Missing/ambiguous")
    reject("duplicate AWB project insertion rejected", lambda: prep["project_with_awb"](adapted), "ambiguous")
    old_approval = Path("E:/juan/FPGA/learning/sc520-system-integration/i0310r4b-preparation-approved-20261027.json")
    reject("old R4B source approval rejected", lambda: prep["prepare"](old_approval, bind(old_approval)["SHA256"]), "nine exact I0310R4C sources")
    reject("wrong source approval SHA rejected", lambda: prep["prepare"](old_approval, "0" * 64), "Approval SHA mismatch")

    check("three exact stage roots", [stage["STAGES"][s][0] for s in ("synthesis", "placement", "route")] == ["j319", "q320", "r320"])
    check("all stage budgets unchanged", [stage["STAGES"][s][-1] for s in stage["STAGES"]] == [old_stage["STAGES"][s][-1] for s in old_stage["STAGES"]])
    check("14 exact clocks unchanged", stage["CLOCKS"] == old_stage["CLOCKS"] and len(stage["CLOCKS"]) == 14)
    for name in ("digest", "read_hash", "timing_observation", "area_observation"):
        trees = [ast.parse((folder / "run-stage.py").read_bytes()) for folder in (OLD, HERE)]
        nodes = [next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == name) for tree in trees]
        check(name + " unchanged", ast.dump(nodes[0]) == ast.dump(nodes[1]))
    check("official seed source exact", bind(stage["SEED_SOURCE"])["SHA256"] == stage["SEED_SOURCE_SHA"])
    for current, out, parent in (("placement", "q320", EV / "j319/td/syn_1/camera_to_dsi_display_gate.db"),
                                 ("route", "r320", EV / "q320/td/pl_1/camera_to_dsi_display_place.db")):
        lines = stage["physical_launcher"](current, EV / out / "td/pl_1", parent).decode("ascii").splitlines()
        check(current + " runs exactly one physical stage", lines.count("place") == (current == "placement") and lines.count("route") == (current == "route"))
        check(current + " exact input database", "import_db {" + parent.as_posix() + "}" in lines)
        check(current + " guards other phases", any("bitgen insert_debugger clear_sdc read_sdc read_adc" in line for line in lines))
        if current == "placement":
            ordered = ["import_db {" + parent.as_posix() + "}", "set_param place seed 1", "commit_param -step place",
                       "report_param -detail -stage place -file {" + (EV / out / "td/pl_1/i0310r4c-seed-parameters.rpt").as_posix() + "}", "place"]
            indices = [lines.index(line) for line in ordered]
            check("import/seed/commit/report/place order", indices == sorted(indices))
            check("only seed setting changed", sum(line.startswith("set_param ") for line in lines) == 1)
        else:
            check("route does not set seed", not any(line.startswith("set_param ") or line.startswith("report_param ") for line in lines))
    reject("physical launcher rejects synthesis", lambda: stage["physical_launcher"]("synthesis", EV, EV), "only accepts placement or route")
    reject("unknown execute stage rejected before reading", lambda: stage["execute"](SimpleNamespace(stage="bitgen")), "Unknown stage")
    reject("wrong stage runner SHA rejected", lambda: stage["execute"](SimpleNamespace(stage="synthesis", runner_sha="0" * 64)), "Exact SHA mismatch")
    failed = stage["timing_observation"](EV / "r317/td/pl_1/i0310r4b-timing.rpt", "Routed")
    check("known negative timing stays rejected", failed["SWNS"] == -1.581 and not failed["NonnegativeUnderCurrentConstraints"])

    check("bitgen exact new roots", bit["RUN"] == EV / "b320" and bit["ROUTE"] == EV / "r320" and bit["MANIFEST"] == EV / "j319/preparation-result.json")
    check("bitgen exact self and current approval", bit["SELF"] == HERE / "run-bitgen.py" and bit["APPROVAL"].name == "i0310r4c-bitgen-approved-20261028.json")
    dummy = [{"Path": str(i), "SHA256": str(i) * 64, "Bytes": i} for i in (1, 2, 3)]
    approved = {"Operation": "I0310R4C candidate bitgen once", "BitgenAllowed": True, "HardwareActionsAllowed": False,
                "OutputRoot": bit["RUN"].as_posix(), "Manifest": dummy[0], "RouteResult": dummy[1], "Runner": dummy[2]}
    bit["approve"](approved, *dummy)
    check("exact synthetic bitgen approval accepted", True)
    for key, replacement in (("Operation", "I0310R3 candidate bitgen once"), ("BitgenAllowed", False),
                              ("HardwareActionsAllowed", True), ("OutputRoot", (EV / "b317").as_posix()),
                              ("Manifest", dummy[1]), ("RouteResult", dummy[0]), ("Runner", dummy[0])):
        wrong = dict(approved); wrong[key] = replacement
        reject("bitgen rejects altered " + key, lambda document=wrong: bit["approve"](document, *dummy), "Approval does not bind")
    reject("bitgen wrong self SHA blocks operation", lambda: bit["execute"](SimpleNamespace(runner_sha="0" * 64)), "Exact hash differs")
    bit_lines = bit["launcher"]().decode("ascii").splitlines()
    check("only one candidate bitgen command", sum(line.startswith("bitgen -bit ") for line in bit_lines) == 1)
    check("bitgen invokes no physical stages", not any(line in ("place", "route", "elaborate", "optimize_rtl", "optimize_gate") for line in bit_lines))
    for filename in ("prepare-build.py", "run-stage.py", "run-bitgen.py"):
        contents = (HERE / filename).read_text(encoding="utf-8")
        check(filename + " no stale production version/root", not any(token in contents for token in ("I0310R3", "i0310r3", "I0310R4B", "i0310r4b", "j316", "q317", "r317", "b317", "q318", "r318", "b318")))
    check("all old tools unchanged", before_old == [bind(p) for p in old_files])
    check("no prepare or physical roots created", before_roots == {name: (EV / name).exists() for name in before_roots})
    report = {"At": datetime.now(timezone(timedelta(hours=8))).isoformat(), "Passed": True,
              "CheckCount": len(checks), "Checks": checks, "NativeExecuted": False, "PrepareExecuted": False,
              "Inputs": [bind(HERE / name) for name in ("prepare-build.py", "run-stage.py", "run-bitgen.py", "test-prepare-build.py")] + before_old + [bind(stage["SEED_SOURCE"]), bind(old_approval)],
              "RootsBefore": before_roots, "Limit": "Pure Python and generated-Tcl review only; source behavior and real TD/seed/timing remain untested here."}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    with args.report.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(report, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
    print(json.dumps({"Passed": True, "Checks": len(checks), "Report": bind(args.report)}))


if __name__ == "__main__":
    main()
