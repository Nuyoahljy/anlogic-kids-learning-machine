"""Independently rehash the final scene RTL simulations and synthesis evidence."""
from __future__ import annotations
from datetime import datetime, timedelta, timezone
import argparse
import hashlib
import json
from pathlib import Path
import re

REPO = Path(__file__).resolve().parents[3]
EVIDENCE = REPO / "evidence/sc520-card-recognition"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def verify(path, digest):
    path = Path(path)
    if not path.is_file() or sha(path) != digest.upper():
        raise RuntimeError(f"missing or changed evidence: {path}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=EVIDENCE / "scene-rtl-validation-v3.json")
    parser.add_argument("--check", action="store_true", help="Read-only check of an already produced aggregate")
    args = parser.parse_args()
    if args.check:
        report = json.loads(args.output.read_text(encoding="utf-8"))
        for item in report["VerifiedFiles"]:
            verify(item["path"], item["sha256"])
        print(json.dumps({"qualified": True, "verified_files": len(report["VerifiedFiles"])}))
        return 0
    if args.output.exists():
        raise RuntimeError("refusing to overwrite an existing validation aggregate")
    runs = [("scene-normal-20261014-110403-4d918084", 0, 1, 0),
            ("scene-negative-20261014-110403-57ba8892", 1, 1, 1),
            ("scene-watchdog-20261014-110403-abcd139d", 2, 0, 0)]
    verified, results = {}, []
    input_count = artifact_count = 0
    for name, code, done, errors in runs:
        path = EVIDENCE / "runs" / name / "run-manifest.json"
        manifest = json.loads(path.read_text(encoding="utf-8"))
        summary = manifest["Summary"]
        if not manifest["Qualified"] or manifest["ProcessExitCode"] != code or summary["done"] != done or summary["errors"] != errors:
            raise RuntimeError(f"unqualified native result: {path}")
        for item in manifest["Inputs"]:
            for key in ("path", "snapshot"):
                verify(item[key], item["sha256_before"])
                verified[item[key]] = item["sha256_before"].upper()
            input_count += 1
        for item in manifest["Artifacts"]:
            verify(item["path"], item["sha256"])
            verified[item["path"]] = item["sha256"].upper()
            artifact_count += 1
        verified[str(path)] = sha(path)
        results.append({"Manifest": str(path), "Mode": manifest["Mode"], "Summary": summary})
    build = EVIDENCE / "builds/scene-serial-math-20261014-105849-d65c67"
    path = build / "run-manifest.json"
    synth = json.loads(path.read_text(encoding="utf-8"))
    if not synth["SynthesisCompleted"] or synth["ExitCode"] != 0:
        raise RuntimeError("final kernel synthesis did not complete")
    for key in ("Source", "Snapshot"):
        verify(synth[key], synth["SourceSHA256"])
        verified[synth[key]] = synth["SourceSHA256"]
    verify(synth["Tool"], synth["ToolSHA256"])
    verified[synth["Tool"]] = synth["ToolSHA256"]
    for item in synth["Artifacts"]:
        verify(item["path"], item["sha256"])
        verified[item["path"]] = item["sha256"].upper()
        artifact_count += 1
    verified[str(path)] = sha(path)
    area = (build / "scene_gate.area").read_text()
    timing = (build / "scene_gate.timing").read_text()
    resources = {key: int(re.search(r"^\s*#" + re.escape(token) + r"\s+(\d+)", area, re.M).group(1))
                 for key, token in (("lut", "lut"), ("registers", "reg"), ("slices", "slice*"),
                                    ("eram", "eram"), ("dsp", "dsp"), ("distributed_ram_lut", "dram lut"))}
    swns = float(re.search(r"SWNS:\s+([-\d.]+)ns", timing).group(1))
    if resources["dsp"] != 0 or resources["distributed_ram_lut"] != 0 or resources["eram"] != 28 or swns <= 0:
        raise RuntimeError("unexpected final resource or synthesis timing result")
    verified[str(Path(__file__).resolve())] = sha(Path(__file__))
    report = {"CreatedAt": datetime.now(timezone(timedelta(hours=8))).isoformat(), "Qualified": True,
              "Owner": "01a13561-2629-7fa2-86a0-4087ad34cc7c /root/scene_rtl", "SourceSHA256": synth["SourceSHA256"],
              "Scope": "182 rotation-v1 images plus 24 controls: scene extraction integer equivalence; synthesis-only kernel with registered wrapper. No board, camera accuracy, final class-join or place/route qualification.",
              "Runs": results, "KernelSynthesis": {"Manifest": str(path), "ResourcesIncludingWrapper": resources,
                  "ClockPeriodNs": 9.660, "SynthesisSWNSNs": swns, "RoutedTimingQualified": False},
              "InputRecordsChecked": input_count, "ArtifactRecordsChecked": artifact_count,
              "VerifiedFiles": [{"path": key, "sha256": value} for key, value in sorted(verified.items())]}
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"qualified": True, "inputs": input_count, "artifacts": artifact_count, "files": len(verified),
                      "resources": resources, "output": str(args.output)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
