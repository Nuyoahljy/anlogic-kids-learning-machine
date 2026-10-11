"""Recheck the fixed items14 delivery's snapshots, protected files and font assets."""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import argparse
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[3]
EVIDENCE = ROOT / "evidence/sc520-card-recognition"
SELECTED = (
    "i14-join-normal-20261011-195454-0894c967",
    "i14-join-negative-20261011-195454-1cc73c58",
    "i14-join-watchdog-20261011-195454-6ac0d14c",
    "i14-control-normal-20261011-195930-501a69e4",
    "i14-control-negative-20261011-195930-6a371c82",
    "i14-control-watchdog-20261011-195930-3c8aa81b",
    "i14-display-normal-20261011-195708-23601829",
    "i14-display-negative-20261011-195708-f57ea198",
    "i14-display-watchdog-20261011-195708-0b5d4910",
    "i14-system-normal-20261011-200510-a8bfce47",
    "i14-system-negative-20261011-200510-759ae5e5",
    "i14-system-watchdog-20261011-200510-9651af58",
)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="optional new audit JSON; existing file is never overwritten")
    args = parser.parse_args()
    reports = []
    checks = scenarios = 0
    for name in SELECTED:
        path = EVIDENCE / "runs" / name / "run-manifest.json"
        data = read(path)
        assert data["Qualified"] and data["InputsUnchanged"] and not data["TimedOut"], str(path)
        s, mode, code = data["Summary"], data["Mode"], data["NativeExitCode"]
        expected = {"normal": (0, 1, 0, 0), "negative": (1, 1, 1, 1), "watchdog": (2, 0, 0, 0)}[mode]
        assert (code, s["done"], s["errors"], s["injected"]) == expected, name
        for item in data["Inputs"]:
            assert (item["sha256_before"] == item["sha256_after"] == item["snapshot_sha256"] ==
                    digest(item["path"]) == digest(item["snapshot"])), item["path"]
        for item in data["Outputs"]:
            assert digest(item["path"]) == item["sha256"], item["path"]
        transcript = (path.parent / "transcript.log").read_text(encoding="utf-8", errors="replace")
        assert not any(token in transcript for token in ("** Error:", "** Fatal:", "WATCHDOG")), name
        if mode == "normal":
            checks += s["checks"]
            scenarios += s["scenarios"]
        reports.append({"Manifest": str(path), "SHA256": digest(path), "Test": data["Test"],
                        "Mode": mode, "NativeExitCode": code, "Summary": s,
                        "InputsChecked": len(data["Inputs"]), "OutputsChecked": len(data["Outputs"])})
    baseline = read(EVIDENCE / "items14-baseline.json")
    for item in baseline["Protected"]:
        assert digest(item["Path"]) == item["SHA256"], item["Path"]
    assets = ROOT / "assets/templates/sc520-card-recognition/items14"
    font = read(assets / "font-manifest.json")
    for item in font["outputs"]:
        assert digest(ROOT / item["path"]) == item["sha256"], item["path"]
    for item in font["previews"]:
        assert digest(assets / item["path"]) == item["sha256"], item["path"]
    assert digest(font["font_path"]) == font["font_sha256"]
    text = read(assets / "text-manifest.json")
    assert [item["item_id"] for item in text["items"]] == list(range(1, 15))
    assert [item["name"] for item in text["items"]][-5:] == ["苹果", "香蕉", "汽车", "星星", "雨伞"]
    links = []
    for name in ("items14-control.md", "items14-display.md", "items14-integration.md"):
        doc = ROOT / "hardware/sc520-card-recognition" / name
        for target in re.findall(r"\]\(([^)]+)\)", doc.read_text(encoding="utf-8")):
            if target.startswith(("http:", "https:", "#")):
                continue
            path = (doc.parent / target.strip("<>").split("#")[0]).resolve()
            # The report may be created by this invocation after all checks.
            if args.output and path == args.output.resolve():
                continue
            assert path.exists(), str(path)
            links.append(str(path))
    report = {"Task": "sc520-card-recognition", "Stage": "items14_result_level",
              "Status": "software_verified_pending_main_review",
              "RecordedAt": datetime.now(timezone(timedelta(hours=8))).isoformat(timespec="seconds"),
              "BaseCommit": baseline["BaseCommit"], "AuditScriptSHA256": digest(__file__),
              "NormalScenarios": scenarios, "NormalChecks": checks, "NormalErrors": 0,
              "Runs": reports, "ProtectedFilesChecked": len(baseline["Protected"]),
              "BaselinePath": str(EVIDENCE / "items14-baseline.json"),
              "BaselineSHA256": digest(EVIDENCE / "items14-baseline.json"),
              "FontGlyphs": font["glyph_count"], "FontOutputsChecked": len(font["outputs"]),
              "PreviewHashesChecked": len(font["previews"]), "LinksChecked": links,
              "VisualReview": "Root viewed apple and unhealthy originals plus all-seven contact sheet; text and separated panels visible; software preview only",
              "Scope": "Completed-frame result records through local join/control/OSD and audio event outputs; no camera, TD, UART or board verification",
              "History": "Early control normal incorrectly enabled injection via test$plusargs; retained and replaced by final numeric parsing runs. Early system eight-case runs retained. Ten-case suite adds quiz queued-answer and TEST timeout OSD cases; final revision compares the unhealthy name field rather than a shared prefix. items14-validation.json is a superseded audit of the earlier TB; this revision is authoritative for current source.",
              "Limits": ["Frame tags and health must be generated by the actual capture adapters",
                         "Sustained DDR replay with newly minted tags is not detected",
                         "100 real milliseconds, ROM inference, timing closure and physical readability unverified",
                         "No real audio transport or card optical accuracy verification"]}
    if args.output:
        with args.output.open("x", encoding="utf-8", newline="\n") as out:
            json.dump(report, out, ensure_ascii=False, indent=2)
            out.write("\n")
    print(json.dumps({"normal_scenarios": scenarios, "normal_checks": checks,
                      "runs": len(reports), "protected": len(baseline["Protected"]),
                      "font_outputs": len(font["outputs"]), "previews": len(font["previews"])}))


if __name__ == "__main__":
    main()
