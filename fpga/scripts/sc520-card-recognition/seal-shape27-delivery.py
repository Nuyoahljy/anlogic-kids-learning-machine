"""Bind the D0270 bit to its frozen source, route, reviews, and raw bitgen."""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import argparse
import hashlib
import json
import subprocess

R = Path(__file__).resolve().parents[3]
E = R / "evidence/sc520-shape27"
W = Path("E:/juan/FPGA")
COMMIT = "b7247b8d8963ff60bd8a2f710a174e5434531b33"
DB_SHA = "7755E6390D684DA939D01EB3851716425F92385C556E24570B0CE779C3F4B05B"
APPROVAL_SHA = "0CA624635EC084899E94441FDE0F31B2177A4084F2A007B5D80832A36BDED229"
BIT_SHA = "0B6EA91C2396C31DC8F73AC8C5921E528F8F43E758CF445F1CC71DE99B60672B"
RUN = E / "builds/6a50b270-phy-r2"
ORIGINAL = E / "builds/6a50b270"


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def artifact(path):
    path = Path(path).resolve(strict=True)
    with path.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha256").hexdigest().upper()
    return {"Path": str(path), "SHA256": digest, "Bytes": path.stat().st_size}


def collect(approval_path, bitgen):
    checked = {}

    def check(row):
        path = str(Path(row["Path"]).resolve(strict=True))
        actual = checked.setdefault(path, artifact(path))
        assert actual["SHA256"] == row["SHA256"].upper(), path
        if "Bytes" in row:
            assert actual["Bytes"] == row["Bytes"], path
        return actual

    def check_tree(value):
        if isinstance(value, dict):
            if isinstance(value.get("Path"), str) and isinstance(value.get("SHA256"), str):
                check(value)
            for child in value.values():
                check_tree(child)
        elif isinstance(value, list):
            for child in value:
                check_tree(child)

    approval_path = approval_path.resolve(strict=True)
    approval = read(approval_path)
    assert artifact(approval_path)["SHA256"] == APPROVAL_SHA
    assert approval["Stage"] == "bitgen_approved" and approval["PhysicalAcceptedByMain"]
    assert approval["SourceCommit"] == COMMIT
    assert approval["Purpose"] == "SRAM validation only" and approval["BitGenerationAllowed"]
    assert not approval["DownloadAllowed"] and not approval["FlashAllowed"]
    assert not approval["HardwareValidated"]
    check_tree(approval)
    assert Path(approval["BuildInputs"]["Path"]) == RUN / "inputs.json"
    assert approval["RouteDatabase"]["SHA256"] == DB_SHA
    assert Path(approval["RouteDatabase"]["Path"]) == RUN / "td_project/camera_to_dsi_display_Runs/phy_1/camera_to_dsi_display_pr.db"

    main_review = read(approval["PhysicalReview"]["Path"])
    assert main_review["EvidenceIntegrityPassed"] and main_review["SourceCommit"] == COMMIT
    assert main_review["SynthesisExecutedInThisAttempt"] is False
    assert len(main_review["IndependentChecksPassed"]) == 14
    assert main_review["Timing"]["TimingNs"] == {"SWNS": .103, "STNS": 0., "HWNS": .02, "HTNS": 0.}
    for row in main_review["UniqueFiles"]:
        check(row)
    software_approval = read(W / "learning/sc520-shape27/main-review/software-approved.json")
    check_tree(software_approval)
    software = read(E / "software-v1.json")
    assert software["SoftwareQualified"] and len(software["SourceFreeze"]) == 16
    for row in software["SourceFreeze"]:
        check(row)
        relative = Path(row["Path"]).relative_to(R).as_posix()
        blob = subprocess.check_output(["git", "show", COMMIT + ":" + relative], cwd=R)
        assert hashlib.sha256(blob).hexdigest().upper() == row["SHA256"], relative

    inputs = read(RUN / "inputs.json")
    assert len(inputs["Files"]) == 396 and len(inputs["ManifestSources"]) == 121
    for row in inputs["Files"]:
        check(row)
        if "Snapshot" in row:
            check({"Path": row["Snapshot"], "SHA256": row["SnapshotSHA256"]})
    old = read(E / "protected-d0261.json")
    assert old["FrozenBuildInputCount"] == 388 and old["AllCurrentAndSnapshotHashesVerified"]
    check_tree(old)

    retry = read(RUN / "result.json")
    stages = read(RUN / "stages.json")
    assert retry["Complete"] and retry["NativeExitCode"] == 0
    assert retry["OriginalAndFrozenInputsUnchanged"] and not retry["LogErrors"]
    assert retry["RequiredOutputsPresent"] and retry["CompletionMarkers"]
    assert len(stages) == 2 and stages[0]["ExecutedInThisAttempt"] is False
    assert stages[1]["ExecutedInThisAttempt"] is True
    for key, value in read(ORIGINAL / "stages.json").items():
        assert stages[0][key] == value
    check_tree(read(RUN / "preparation.json"))
    check_tree(retry)

    bitgen = bitgen.resolve(strict=True)
    assert bitgen == E / "bitgen-d0270-v1"
    result = read(bitgen / "result.json")
    assert result["Complete"] and result["NativeExitCode"] == 0
    assert result["InputsUnchanged"] and result["DatabaseImportSucceeded"]
    assert not result["LogErrors"] and result["TemporaryMapping"]["Released"]
    assert not result["HardwareValidated"] and not result["DownloadExecuted"] and not result["FlashExecuted"]
    generator = R / "fpga/scripts/sc520-card-recognition/generate-shape27-bit.py"
    assert artifact(generator)["SHA256"] == result["GeneratorSHA256"]
    assert (bitgen / "approval.json").read_bytes() == approval_path.read_bytes()
    for path, digest in result["ProtectedInputs"].items():
        check({"Path": path, "SHA256": digest})
    stdout = (bitgen / "stdout.log").read_text(encoding="utf-8", errors="replace")
    assert "ERROR" not in stdout and (bitgen / "stderr.log").stat().st_size == 0
    assert "Import design success TD_VERSION=6.2.168116" in stdout
    assert "Generate bitstream completely" in stdout
    assert "MAIN_APPROVED_D0270_BITGEN_COMPLETE" in stdout
    assert DB_SHA == artifact(approval["RouteDatabase"]["Path"])["SHA256"]
    script = (bitgen / "bitgen.tcl").read_text(encoding="ascii")
    assert "bitgen -bit sc520-d0270.bit" in script
    assert not any(command in script for command in ("opt_route", "opt_place", "export_db", "program", "download"))
    bit = check(result["Bit"])
    assert bit["Bytes"] == 1789539 and bit["SHA256"] == BIT_SHA
    assert list(bitgen.glob("*.bit")) == [Path(bit["Path"])]

    probes = []
    for name, count in (("endpoint-probe-r2-02", 1009), ("endpoint-probe-r2-03", 128)):
        path = E / name / "result.json"
        probe = read(path)
        assert probe["Complete"] and probe["NativeExitCode"] == 0
        assert probe["FrozenInputsUnchanged"] and not probe["ChangedProtectedFiles"]
        assert not probe["Errors"] and probe["StderrEmpty"] and not probe["BitFilesFound"]
        assert probe["OriginalTimingMarker"] and probe["ProbeCompleteMarker"]
        check_tree(probe)
        probes.append({"Result": artifact(path), "RequestedQueries": count,
                       "NativeStartedAt": probe["StartedAt"], "NativeFinishedAt": probe["NativeFinishedAt"]})

    top = R / "fpga/custom_project/sc520-shape27/overlay/design_top_wrapper.v"
    top_text = top.read_text(encoding="utf-8")
    assert ".VERSION(16'h0270)" in top_text
    assert ".diagnostic({16'h0270," in top_text
    subprocess.run(["git", "merge-base", "--is-ancestor", COMMIT, "HEAD"], cwd=R, check=True)
    subprocess.run(["git", "diff", "--quiet", COMMIT, "--", "fpga/rtl", "fpga/custom_project"], cwd=R, check=True)
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=R, text=True).strip()
    guide = R / "hardware/sc520-shape27/d0270-sram-guide.md"
    return {
        "CreatedAt": datetime.now(timezone(timedelta(hours=8))).isoformat(),
        "Owner": "Codex /root/shape27_delivery", "Candidate": "D0270",
        "State": "bit_generated_waiting_main_final_acceptance",
        "ProductionSourceCommit": COMMIT, "GitHeadAtSeal": head,
        "Program": artifact(__file__), "BitgenApproval": artifact(approval_path),
        "SoftwareManifest": artifact(E / "software-v1.json"),
        "MainSoftwareReview": check(software_approval["SoftwareReview"]),
        "IndependentSoftwareReview": check(software_approval["IndependentReview"]),
        "MainPhysicalReview": check(approval["PhysicalReview"]),
        "IndependentPhysicalReview": check(approval["IndependentPhysicalReview"]),
        "FrozenD0261Protection": artifact(E / "protected-d0261.json"),
        "FrozenSourceCount": len(software["SourceFreeze"]),
        "OldProtectedFileCount": len(old["Files"]),
        "BuildInputs": check(approval["BuildInputs"]),
        "RouteDatabase": check(approval["RouteDatabase"]),
        "VersionEvidence": {"DisplayTag": "D0270", "TopLevel": artifact(top),
                            "CompositorVersion": "16'h0270", "DiagnosticVersion": "16'h0270",
                            "Basis": "Frozen source plus build inputs and approved routed DB; not the bit filename."},
        "BuildProvenance": {
            "OriginalSynthesisRun": str(ORIGINAL), "RetryRun": str(RUN),
            "OriginalStages": artifact(ORIGINAL / "stages.json"),
            "RetryPreparation": artifact(RUN / "preparation.json"),
            "RetryStages": artifact(RUN / "stages.json"),
            "RetryResult": artifact(RUN / "result.json"),
            "SynthesisExecutedInRetry": False, "PlacementAndRouteExecutedInRetry": True,
            "Basis": "Original 2026-10-19 gate DB copied byte for byte; retry reran only placement and route.",
        },
        "TimingNs": main_review["Timing"]["TimingNs"],
        "EndpointProbeHistory": probes,
        "BitGeneration": {
            "Result": artifact(bitgen / "result.json"), "Script": artifact(bitgen / "bitgen.tcl"),
            "ApprovalCopy": artifact(bitgen / "approval.json"), "Stdout": artifact(bitgen / "stdout.log"),
            "Stderr": artifact(bitgen / "stderr.log"), "Generator": artifact(generator),
            "ToolSHA256": result["ToolSHA256"], "ProtectedInputCount": len(result["ProtectedInputs"]),
            "TemporaryMapping": result["TemporaryMapping"], "InputsUnchanged": True,
        },
        "Bit": bit, "Guide": artifact(guide),
        "PreservedHistoricalDraft": artifact(E / "delivery-draft.json"),
        "VerifiedUniqueFilesAtSeal": len(checked), "HardwareValidated": False,
        "DownloadExecuted": False, "FlashExecuted": False, "StableBaselineMerged": False,
        "UserSRAMExecutionGate": "Main D081 final acceptance is required before the user executes PROGRAM_SRAM.",
        "Limits": [
            "Fixed white surface, existing uneven white borders, actual fourteen classes and lighting/placement require user validation.",
            "The bitgen approval grants generation only; it does not permit this computer to download or write Flash.",
            "Three audio VERIFIED gates remain zero, TRACKS empty, and no unverified audio pads are exposed.",
            "Native build and software reports retain their original stage flags and failure history.",
            "Independent delivery QA must reference this manifest in one direction; this manifest does not reference that QA.",
            "Git holds selected manifests and text logs; local bit, route DB, snapshots and caches require separate SHA-verified transfer.",
        ],
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--approval", type=Path, required=True)
    parser.add_argument("--bitgen-dir", type=Path, default=E / "bitgen-d0270-v1")
    parser.add_argument("--output", type=Path, default=E / "delivery-manifest.json")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    report = collect(args.approval, args.bitgen_dir)
    if args.check:
        saved = read(args.output)
        for key, value in report.items():
            if key not in ("CreatedAt", "GitHeadAtSeal"):
                assert saved[key] == value, key
        print(json.dumps({"ManifestVerified": True, "Bit": report["Bit"],
                          "VerifiedUniqueFiles": report["VerifiedUniqueFilesAtSeal"]}))
    else:
        with args.output.open("x", encoding="utf-8", newline="\n") as stream:
            json.dump(report, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
        print(json.dumps({"Manifest": artifact(args.output), "Bit": report["Bit"]}))


if __name__ == "__main__":
    main()
