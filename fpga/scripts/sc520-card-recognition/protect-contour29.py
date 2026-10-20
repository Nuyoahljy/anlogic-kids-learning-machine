"""Freeze and later recheck old D0270/D0261 source, evidence, databases and bits."""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import argparse
import hashlib
import json
import subprocess

R = Path(__file__).resolve().parents[3]
E = R / "evidence/sc520-contour29"
W = Path("E:/juan/FPGA")


def artifact(path):
    path = Path(path).resolve(strict=True)
    with path.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest().upper()
    return dict(Path=str(path), SHA256=digest, Bytes=path.stat().st_size)


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    output = E / "protected-baselines.json"
    if args.check:
        report = read(output)
        for row in report["Files"]:
            assert artifact(row["Path"]) == row, row["Path"]
        print(json.dumps(dict(ProtectedFilesUnchanged=len(report["Files"]))))
        return
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=R, text=True).strip()
    assert head == "4a9b0b36f74a5025d7796ceabc1d9f4a3c542bed"
    paths = {}

    def add(row):
        actual = artifact(row["Path"])
        assert actual["SHA256"] == row["SHA256"].upper(), row["Path"]
        if "Bytes" in row:
            assert actual["Bytes"] == row["Bytes"], row["Path"]
        paths[actual["Path"]] = actual

    def walk(value):
        if isinstance(value, dict):
            if isinstance(value.get("Path"), str) and isinstance(value.get("SHA256"), str):
                add(value)
            for child in value.values():
                walk(child)
        elif isinstance(value, list):
            for child in value:
                walk(child)

    entries = [
        R / "evidence/sc520-shape27/software-v1.json",
        R / "evidence/sc520-shape27/protected-d0261.json",
        R / "evidence/sc520-shape27/delivery-manifest.json",
        W / "learning/sc520-shape27/main-review/physical-r2-final/review.json",
        W / "learning/sc520-shape27/main-review/software-02/review.json",
        W / "learning/sc520-shape27/delivery-review/final-v1.json",
    ]
    for path in entries:
        add(artifact(path))
        walk(read(path))
    inputs = read(R / "evidence/sc520-shape27/builds/6a50b270-phy-r2/inputs.json")
    assert len(inputs["Files"]) == 396
    for row in inputs["Files"]:
        add(row)
        if "Snapshot" in row:
            add({"Path": row["Snapshot"], "SHA256": row["SnapshotSHA256"]})
    E.mkdir(parents=True, exist_ok=True)
    report = dict(At=datetime.now(timezone(timedelta(hours=8))).isoformat(),
                  Owner="Codex /root/shape27_delivery", ProductionBaseCommit=head,
                  Program=artifact(__file__), NewTask="T029/sc520-contour29/D0290",
                  FrozenD0270InputCount=396, Files=sorted(paths.values(), key=lambda row: row["Path"]),
                  Limits="Only hash-bound old sources/evidence are frozen; branch log and new T029 files are not baseline.")
    with output.open("x", encoding="utf-8") as stream:
        json.dump(report, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
    print(json.dumps(dict(ProtectedBaselineFiles=len(paths), Output=str(output))))


if __name__ == "__main__":
    main()
