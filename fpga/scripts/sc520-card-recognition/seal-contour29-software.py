"""Seal selected real RTL runs; truth accuracy and contract checks stay separate."""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import csv
import hashlib
import json

R = Path(__file__).resolve().parents[3]
E = R / "evidence/sc520-contour29"


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest().upper()


def artifact(path):
    path = Path(path).resolve(strict=True)
    return dict(Path=str(path), SHA256=sha(path), Bytes=path.stat().st_size)


def verify_run(name, code=0, done=1, errors=0):
    path = E / "runs" / name / "run-manifest.json"
    run = read(path)
    assert run["NativeExitCode"] == code and run["Summary"]["done"] == done
    assert run["Summary"]["errors"] == errors and run["InputsUnchanged"]
    for item in run["Inputs"]:
        assert sha(item["Path"]) == item["SHA256"] == sha(item["Snapshot"]), item["Path"]
    for item in run["Outputs"]:
        assert sha(item["Path"]) == item["SHA256"], item["Path"]
    return dict(Run=artifact(path), Summary=run["Summary"], ExpectedNativeExitCode=code,
                Inputs=len(run["Inputs"]), Qualified=run["Qualified"])


def final_csv(run):
    path = Path(run["Run"]["Path"]).parent / "scene-results.csv"
    with path.open(newline="") as stream:
        values = [{key: value.strip() for key, value in row.items()} for row in csv.DictReader(stream)]
    assert len(values) == run["Summary"]["scenarios"] * 3
    final = {row["case"]: row for row in values if row["frame"] == "2"}
    assert len(final) == run["Summary"]["scenarios"]
    return path, final


def compare_truth(folder, newer, legacy):
    manifest_path = E / folder / "manifest.json"
    manifest = read(manifest_path)
    new_path, new = final_csv(newer)
    old_path, old = final_csv(legacy)
    rows = []
    new_inputs = read(newer["Run"]["Path"])["Inputs"]
    old_inputs = read(legacy["Run"]["Path"])["Inputs"]
    for case in manifest["Cases"]:
        prefix = case["Prefix"]
        assert prefix in new and prefix in old
        rgb = case["RGB"]
        assert sha(rgb["Path"]) == rgb["SHA256"]
        for inputs in (new_inputs, old_inputs):
            entry = next(item for item in inputs if Path(item["Path"]) == Path(rgb["Path"]))
            assert entry["SHA256"] == rgb["SHA256"] == sha(entry["Snapshot"])
        truth = case["TruthItem"]
        actual_new, actual_old = int(new[prefix]["item"]), int(old[prefix]["item"])
        assert actual_new == case["ExpectedContractItem"], prefix
        rows.append(dict(Name=case["Name"], Prefix=prefix, TruthItem=truth,
                         NewActualItem=actual_new, LegacyActualItem=actual_old,
                         NewValid=int(new[prefix]["valid"]), LegacyValid=int(old[prefix]["valid"]),
                         RGB=rgb, TruthSource=case.get("Source"),
                         NewMiss=truth != 0 and actual_new == 0,
                         NewFalseClass=actual_new not in (0, truth),
                         LegacyMiss=truth != 0 and actual_old == 0,
                         LegacyFalseClass=actual_old not in (0, truth),
                         NewlyLostCorrect=actual_old == truth and actual_new != truth))
    return dict(TruthManifest=artifact(manifest_path), NewCSV=artifact(new_path), LegacyCSV=artifact(old_path),
                Rows=rows, Summary=dict(Cases=len(rows),
                    NewTruthMismatches=sum(r["NewActualItem"] != r["TruthItem"] for r in rows),
                    LegacyTruthMismatches=sum(r["LegacyActualItem"] != r["TruthItem"] for r in rows),
                    NewMisses=sum(r["NewMiss"] for r in rows), NewFalseClasses=sum(r["NewFalseClass"] for r in rows),
                    NewlyLostCorrect=sum(r["NewlyLostCorrect"] for r in rows)))


def main():
    names = [
        "scene-normal-20261020-203300-2ea453",
        "scenes-normal-20261020-204052-e4f963",
        "lifecycle-normal-20261020-204052-ca29ea",
        "render-normal-20261020-204736-9f9378",
        "pairing-normal-20261020-205052-d37a8b",
        "reset-normal-20261020-205453-5dc78b",
        "matrix-normal-20261020-210516-2df5bf",
        "matrix-normal-20261020-210517-1a7c81",
        "fpsverify-normal-20261020-211636-2637d3",
        "pipeline-normal-20261020-211345-ece283",
    ]
    runs = [verify_run(name) for name in names]
    guards = [verify_run("reset-negative-20261020-211345-064eef", 1, 1, 1),
              verify_run("reset-watchdog-20261020-211345-adee8a", 2, 0, 0)]
    legacy_new = verify_run("matrix-legacy-20261020-210516-d45b5e", 1, 1, 69)
    legacy_retained = verify_run("matrix-legacy-20261020-210517-9b7337", 1, 1, 8)
    comparisons = [compare_truth("new-system-v1", runs[6], legacy_new),
                   compare_truth("retained-system-v1", runs[7], legacy_retained)]
    assert comparisons[0]["Summary"]["NewMisses"] == 46
    assert comparisons[0]["Summary"]["NewFalseClasses"] == 0
    assert comparisons[1]["Summary"]["NewTruthMismatches"] == 8
    assert all(row["Summary"]["NewlyLostCorrect"] == 0 for row in comparisons)
    protection = read(E / "protected-baselines.json")
    for row in protection["Files"]:
        assert sha(row["Path"]) == row["SHA256"], row["Path"]
    source = []
    for folder in ("fpga/rtl/sc520-contour29", "fpga/sim/sc520-contour29",
                   "fpga/custom_project/sc520-contour29/overlay", "assets/templates/sc520-contour29"):
        source += [p for p in (R / folder).rglob("*") if p.is_file() and p.name != ".gitattributes"]
    source += [p for p in (R / "fpga/scripts/sc520-card-recognition").glob("*contour29*") if p.is_file()]
    frozen = [artifact(p) for p in sorted(set(source))]
    rejected = []
    for path in sorted((E / "runs").glob("*/run-manifest.json")):
        run = read(path)
        if run["Qualified"] or path.parent.name.startswith("matrix-legacy-20261020-21051"):
            continue
        rejected.append(dict(Run=artifact(path), NativeExitCode=run["NativeExitCode"],
                             Summary=run["Summary"], Complete=bool(run["Summary"] and run["Summary"]["done"])))
    fps_log = E / "runs/fpsverify-normal-20261020-211636-2637d3/stdout.log"
    assert "startup_revokes=1 supported_revokes=0" in fps_log.read_text(errors="replace")
    report = dict(At=datetime.now(timezone(timedelta(hours=8))).isoformat(),
        Task="sc520-contour29", Candidate="D0290", Owner="Codex /root/shape27_delivery",
        SoftwareQualified=True, MainAccepted=False, BitGenerationAllowed=False, HardwareValidated=False,
        SourceFreeze=frozen, Runs=runs, RunnerGuards=guards,
        FrozenBaselineProtection=artifact(E / "protected-baselines.json"),
        LegacySameTruthCompleteFailures=[legacy_new, legacy_retained], ActualTruthComparisons=comparisons,
        Summary=dict(NormalRuns=len(runs), Scenarios=sum(r["Summary"]["scenarios"] for r in runs),
                     Checks=sum(r["Summary"]["checks"] for r in runs), Errors=0),
        RejectedHistory=rejected,
        PreparationFailure=dict(RunDirectory=str(E / "runs/render-normal-20261020-204052-95a2b7"),
            Reason="Duplicate old/new golden-0.mem snapshot names rejected before ModelSim startup; subsequent aux entry excludes old golden files."),
        StreamEvidence=dict(VerifiedLog=artifact(fps_log), PeriodCycles="720*2396+11",
            CapturePeriodNs=9.66, NormalFrames=4, StartupRevokes=1, SupportedRevokes=0,
            MaximumPostEOFClocks=841578, MaximumFIFO=6403, OppositeBankOverlap=True, OverspeedExplicitlyRevokes=True,
            DiagnosticFailure=artifact(E / "runs/fpsdiag-normal-20261020-211314-036d20/run-manifest.json")),
        NormEncoding=dict(Bit0="full glyph longest-side", Bit1="color body longest-side",
                          Bit2="color body independent axes", Bit3="full glyph independent axes"),
        KnownMisses=dict(NewSyntheticCircleMisses=46, IndependentGray25StressMiss=1,
                         RetainedOldTruthMismatches=8),
        Disclosure=[
            "Normal-run errors=0 is implementation-contract checking, not zero recognition error. CSV-to-immutable-Truth comparisons above retain 46 new-circle misses and 8 inherited old mismatches.",
            "Three inherited yellow examples contain RGB(245,205,45), so the frozen R-leading profile classifies red; equal R=G would be unknown. No color-profile fix is included.",
            "Five gain65_before card fixtures remain unknown in both old and new designs.",
            "Full glyph color MIN_AREA remains16; body/scene meaningful area is12. Early proposal models used12; RTL recovery still requires the unchanged full raw_valid.",
            "Only circles are newly recoverable. Radius19 is an explicit new sampling alias, shape/card thresholds and class margin are otherwise retained.",
            "Neutral exterior appendages/shadows and unclosed damage can remain unknown. Synthetic RGB does not reconstruct user screen photographs.",
            "D distances remain full-glyph distances, SH can contain the new recovery-circle qualification, and negative-only ellipse bits never become public SH.",
            "Two inherited ModelSim warnings concern an intentionally unused capture block_roi_fg_count output. No warning is silently represented as zero.",
            "Model v1-v3, prior global-watchdog interruptions and startup-count FPS failures remain retained; guards and failures are excluded from normal summary.",
            "No TD, bitgen, download, Flash, stable merge or hardware recognition qualification is claimed by this software manifest.",
        ])
    output = E / "software-v1.json"
    with output.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(report, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
    print(json.dumps(dict(Manifest=artifact(output), Summary=report["Summary"],
                          SourceFreeze=len(frozen), TruthComparisons=[r["Summary"] for r in comparisons])))


if __name__ == "__main__":
    main()
