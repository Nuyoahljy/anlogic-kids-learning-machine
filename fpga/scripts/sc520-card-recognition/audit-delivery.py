"""Read back final run evidence, protected inputs and immutable data manifests."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone, timedelta
import hashlib
import json
from pathlib import Path
import sys

REPO = Path(__file__).resolve().parents[3]
TASK = "sc520-card-recognition"

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()

def read(path):
    return json.loads(path.read_text(encoding="utf-8"))

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=REPO / "evidence" / TASK / "validation.json")
    args = parser.parse_args()
    if args.output.exists():
        parser.error("choose a new output path; existing evidence is never overwritten")
    evidence = REPO / "evidence" / TASK
    expected = {("matcher", "normal"), ("filter", "normal"), ("pipeline", "normal"),
                ("matcher", "negative"), ("pipeline", "negative"), ("matcher", "watchdog")}
    selected, history = {}, []
    for run in sorted((evidence / "runs").iterdir()):
        manifest = run / "run-manifest.json"
        if not manifest.exists():
            history.append({"Path": str(run), "Status": "incomplete snapshot, no simulation result"})
            continue
        data = read(manifest)
        history.append({"Path": str(run), "Qualified": data["Qualified"],
                        "NativeExitCode": data["NativeExitCode"], "Summary": data["Summary"]})
        key = (data["Test"], data["Mode"])
        if data["Qualified"] and key in expected:
            selected[key] = (manifest, data)
    assert set(selected) == expected, ("missing qualified tests", expected - set(selected))
    runs = []
    for key in sorted(expected):
        manifest, data = selected[key]
        assert data["InputsUnchanged"] and not data["TimedOut"]
        for item in data["Inputs"]:
            expected_sha = item["sha256_before"]
            assert expected_sha == item["sha256_after"] == item["snapshot_sha256"]
            assert sha(Path(item["path"])) == expected_sha, item["path"]
            assert sha(Path(item["snapshot"])) == expected_sha, item["snapshot"]
        for item in data["Outputs"]:
            assert sha(Path(item["path"])) == item["sha256"], item["path"]
        summary = data["Summary"]
        assert read(manifest.parent / "summary.json") == summary
        mode = key[1]
        assert data["NativeExitCode"] == {"normal": 0, "negative": 1, "watchdog": 2}[mode]
        assert summary["done"] == (0 if mode == "watchdog" else 1)
        assert summary["errors"] == (1 if mode == "negative" else 0)
        assert summary["injected"] == (1 if mode == "negative" else 0)
        runs.append({"Test": key[0], "Mode": mode, "Manifest": str(manifest),
                     "ManifestSHA256": sha(manifest), "NativeExitCode": data["NativeExitCode"],
                     "Summary": summary, "InputsRechecked": len(data["Inputs"]),
                     "OutputsRechecked": len(data["Outputs"]), "ElapsedSeconds": data["ElapsedSeconds"]})
    protected = read(evidence / "baseline.json")["Protected"]
    for item in protected:
        assert sha(Path(item["Path"])) == item["SHA256"], item["Path"]
    asset_base = REPO / "assets/templates" / TASK
    datasets = []
    for dataset in ("prep-v1", "prep-v1-r2", "prep-v1-max40"):
        root = asset_base / dataset
        entries = read(root / "manifest.json")["files"]
        for item in entries:
            path = root / item["path"]
            assert sha(path) == item["sha256"].upper() and path.stat().st_size == item["bytes"], str(path)
        datasets.append({"Dataset": dataset, "ManifestSHA256": sha(root / "manifest.json"), "FilesRechecked": len(entries)})
    qa = read(asset_base / "qa-max40/validation.json")
    assert qa["status"] == "pass" and qa["structural_checks_passed"] == 8 and qa["vectors_checked"] == 69
    assert qa["script_sha256"].upper() == sha(Path(__file__).with_name("test-template-data.py"))
    assert qa["dataset_manifest_sha256"].upper() == sha(asset_base / "prep-v1-max40/manifest.json")
    policy = read(asset_base / "policy-comparison.json")
    chosen = next(x for x in policy["policies"] if x["max_distance"] == 40 and not x["ratio_distance_times4_lte_template_fg"])
    normal = [x["Summary"] for x in runs if x["Mode"] == "normal"]
    report = {
        "Task": TASK, "Status": "software_verified_pending_main_review",
        "RecordedAt": datetime.now(timezone(timedelta(hours=8))).isoformat(timespec="seconds"),
        "Command": [sys.executable, *sys.argv], "AuditScriptSHA256": sha(Path(__file__)),
        "BaseCommit": read(evidence / "baseline.json")["BaseCommit"],
        "Scope": "独立模板、RTL与软件像素验证；未综合、未生成bit、未相机或实物验收",
        "Runs": runs, "NormalTotals": {"scenarios": sum(x["scenarios"] for x in normal),
                                           "checks": sum(x["checks"] for x in normal), "errors": 0},
        "DataQA": {"Report": str(asset_base / "qa-max40/validation.json"), "SHA256": sha(asset_base / "qa-max40/validation.json"),
                   "StructuralGroupsPassed": 8, "VectorsChecked": 69, "RGBFaultInjectionsDetected": 69},
        "Datasets": datasets, "DevelopmentPolicy": chosen,
        "ProtectedFilesRechecked": protected, "HistoricalRuns": history,
        "HistoricalPreRunnerRuns": [{"Path": str(p), "Status": "vmap失败，未编译或仿真；保留，不计通过"}
                                     for p in sorted((evidence / "sim").iterdir())],
        "Limitations": ["开发图稿同源且本组参与调参，不是留出准确率", "默认720p配置尚未综合/实测",
                        "固定ROI、固定尺度；多数平移和全部偏暗样本拒识", "需要上层停流超时flush",
                        "ID仅标记，不验证递增；EOF后至少一个额外空拍", "未接九类仲裁、文字、题序或真实音频"]}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes((json.dumps(report, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
    print(json.dumps({"status": report["Status"], "output": str(args.output), "normal": report["NormalTotals"],
                      "qualified_runs": len(runs), "protected_files": len(protected)}, ensure_ascii=False))

if __name__ == "__main__":
    main()
