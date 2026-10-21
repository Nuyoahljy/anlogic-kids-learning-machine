"""Execute one separately main-approved D0291 synthesis/route; bitgen is prohibited."""
from pathlib import Path
import argparse
import ctypes
import datetime as dt
import hashlib
import json
import re
import subprocess
import sys

REPO = Path(__file__).resolve().parents[3]
TOOL = Path("D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/bin/td_commands_prompt.exe")
TOOL_SHA = "E2E04ADA5E256DCCD017240C0F4DCFACE7F96DCA67CDE0E56E606AC0E02F827A"
ORIGINAL_SOFTWARE = REPO / "evidence/sc520-contour29/software-v1.json"
ORIGINAL_SOFTWARE_SHA = "890456358DECFE262EF3086843063FD4006A24340461F1333C0274096036DDC7"
R4_SNAPSHOT = REPO / "evidence/sc520-contour29/interruption-r4-20261021-1715/run-files.json"
R4_SNAPSHOT_SHA = "1DE04CEC57DEA6DF5BE300CB50F9BED9E991A2DF5984BD0B863788CBDC7497FE"


def now():
    return dt.datetime.now(dt.timezone(dt.timedelta(hours=8))).isoformat()


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def artifact(path):
    path = Path(path).resolve(strict=True)
    return dict(Path=str(path), SHA256=hashlib.sha256(path.read_bytes()).hexdigest().upper(), Bytes=path.stat().st_size)


def check(row):
    actual = artifact(row["Path"])
    if actual["SHA256"] != row["SHA256"] or ("Bytes" in row and actual["Bytes"] != row["Bytes"]):
        raise RuntimeError("Changed approved artifact: " + row["Path"])
    return actual


def save(path, value):
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write("\n")


def verify_inputs(run):
    manifest = read(run / "inputs.json")
    if manifest["Candidate"] != "D0291" or manifest["HardwareValidated"] or manifest["BitGenerationAllowed"]:
        raise RuntimeError("Wrong input manifest")
    for row in manifest["Files"]:
        check(row)
        if row.get("Snapshot"):
            check(dict(Path=row["Snapshot"], SHA256=row["SnapshotSHA256"]))
    if len(manifest["GeometryROM"]["Copies"]) != 5:
        raise RuntimeError("Five exact geometry ROM search locations required")
    for path in manifest["GeometryROM"]["Copies"]:
        check(dict(Path=path, SHA256=manifest["GeometryROM"]["SHA256"]))
    profile = read(run / "profile.json")
    if profile["TestOnly"] or profile["TRACKS"] or profile["BitGenerationAllowed"] or profile["HardwareValidated"]:
        raise RuntimeError("Hardware-default unconfigured audio profile required")


def changed_inputs(run):
    changed = []
    for row in read(run / "inputs.json")["Files"]:
        pairs = [(row["Path"], row["SHA256"])]
        if row.get("Snapshot"):
            pairs.append((row["Snapshot"], row["SnapshotSHA256"]))
        for path, expected in pairs:
            if not Path(path).is_file() or artifact(path)["SHA256"] != expected:
                changed.append(path)
    return sorted(set(changed))


def verify_baselines():
    check(dict(Path=str(ORIGINAL_SOFTWARE), SHA256=ORIGINAL_SOFTWARE_SHA))
    original = read(ORIGINAL_SOFTWARE)
    for row in original["SourceFreeze"]:
        check(row)
    protected = original["FrozenBaselineProtection"]
    check(protected)
    rows = read(protected["Path"])["Files"]
    if len(rows) != 3165:
        raise RuntimeError("Expected all 3165 old D0270/D0261 protected files")
    for row in rows:
        check(row)
    check(dict(Path=str(R4_SNAPSHOT), SHA256=R4_SNAPSHOT_SHA))
    r4_rows = read(R4_SNAPSHOT)
    if len(r4_rows) != 138:
        raise RuntimeError("Expected all 138 observed r4 files")
    for row in r4_rows:
        check(row)


def main():
    if sys.flags.optimize:
        raise RuntimeError("Python -O/-OO is prohibited for this build pipeline")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--approval", type=Path, required=True)
    parser.add_argument("--approval-sha", required=True)
    parser.add_argument("--run-directory", type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch("[A-Fa-f0-9]{64}", args.approval_sha):
        raise RuntimeError("Explicit approval SHA required")
    check(dict(Path=str(args.approval), SHA256=args.approval_sha.upper()))
    approved = read(args.approval)
    if approved.get("Stage") != "software_accepted" or approved.get("Candidate") != "D0291" or approved.get("BuildAllowed") is not True:
        raise RuntimeError("D0291 needs separate main software acceptance; D084 implementation approval is not execution permission")
    if any(approved.get(name) is not False for name in ("BitGenerationAllowed", "DownloadAllowed", "FlashAllowed", "HardwareValidated")):
        raise RuntimeError("Wrong build/bit/hardware approval boundary")
    run = args.run_directory.resolve(strict=True)
    if not run.is_relative_to(REPO / "evidence/sc520-contour29-retime/builds"):
        raise RuntimeError("Unexpected build directory")
    if any((run / name).exists() for name in ("started.json", "result.json", "failure.json")):
        raise RuntimeError("Never reexecute an existing run")
    for name in ("SoftwareReview", "IndependentReview", "SoftwareManifest", "Preparation", "Program", "Preparer", "Tool"):
        check(approved[name])
    if Path(approved["Preparation"]["Path"]).resolve() != run / "preparation.json":
        raise RuntimeError("Approval must bind this exact prepared directory")
    if approved["Program"] != artifact(__file__) or approved["Tool"] != artifact(TOOL) or artifact(TOOL)["SHA256"] != TOOL_SHA:
        raise RuntimeError("Exact approved builder/TD executable required")
    if Path(approved["Preparer"]["Path"]).resolve() != Path(__file__).with_name("prepare-contour29-retime.py").resolve():
        raise RuntimeError("Wrong preparer")
    software = read(approved["SoftwareManifest"]["Path"])
    if not software["SoftwareQualified"] or software["Candidate"] != "D0291":
        raise RuntimeError("Unqualified candidate")
    for group in ("SourceFreeze", "OriginalBaselineSourceFreeze"):
        if not software.get(group):
            raise RuntimeError("Missing " + group)
        for row in software[group]:
            check(row)
    if software["OriginalSoftware"] != artifact(ORIGINAL_SOFTWARE) or software["FrozenBaselineProtection"] != read(ORIGINAL_SOFTWARE)["FrozenBaselineProtection"]:
        raise RuntimeError("Candidate software must explicitly bind the original software/protection table")
    verify_baselines()
    preparation = read(run / "preparation.json")
    if preparation["Candidate"] != "D0291" or preparation["TDStarted"]:
        raise RuntimeError("Wrong preparation lineage")
    for row in preparation["PreparedFiles"]:
        check(row)
    if subprocess.run(["git", "-C", str(REPO), "merge-base", "--is-ancestor", approved["SourceCommit"], "HEAD"]).returncode:
        raise RuntimeError("Accepted source commit is not current ancestry")
    if subprocess.check_output(["git", "-C", str(REPO), "branch", "--show-current"], text=True).strip() != "task/sc520-color-integration":
        raise RuntimeError("Wrong branch")
    verify_inputs(run)
    consoles = subprocess.check_output(["powershell.exe", "-NoProfile", "-Command",
        "@(Get-CimInstance Win32_Process | Where-Object {$_.Name -match '^td.*\\.exe$' -and $_.Name -ne 'td.exe'}) | ForEach-Object {$_.ProcessId}"], text=True).strip()
    if consoles:
        raise RuntimeError("TD console already active; ownership review required")
    if list(run.rglob("*.db")) or list(run.rglob("*.bit")) or list(run.rglob(".*.f")):
        raise RuntimeError("Prepared full build must not inherit databases/markers/bit")
    occupied = ctypes.windll.kernel32.GetLogicalDrives()
    drive = next((letter + ":" for letter in "TSRQ" if not occupied & (1 << (ord(letter)-65))), None)
    if not drive:
        raise RuntimeError("No free task drive; never reuse preserved U")
    subprocess.run(["subst.exe", drive, str(run)], check=True)
    result = dict(Candidate="D0291", Owner="Codex /root/contour29_reconcile",
                  Approval=str(args.approval.resolve()), ApprovalSHA256=args.approval_sha.upper(),
                  ApprovalArtifact=artifact(args.approval), SourceCommit=approved["SourceCommit"],
                  Tool=str(TOOL), ToolSHA256=TOOL_SHA, ToolArtifact=artifact(TOOL), StartedAt=now(), Stages=[],
                  TemporaryMapping=dict(Drive=drive, Target=str(run), Released=False),
                  Complete=False, TestOnly=False, ChangedInputs=None, BitFilesFound=None,
                  TimingQualified=False, BitGenerationAllowed=False,
                  DownloadAllowed=False, FlashAllowed=False, HardwareValidated=False)
    child = None
    try:
        save(run / "started.json", result)
        for stage in ("syn_1", "phy_1"):
            verify_inputs(run)
            verify_baselines()
            stage_dir = run / f"td_project/camera_to_dsi_display_Runs/{stage}"
            launcher = run / (stage + ".launch.tcl")
            launcher.write_text("""if {[catch {
 source settings.cfg
 if {$device_name ne "ph1_35p.db" || $package_name ne "PH1P35MDG324" || $speed != 3} {error "Wrong D0291 device"}
 if {"STAGE" eq "phy_1" && ($start_step ne "opt_place" || $end_step ne "opt_route")} {error "D0291 requires full new place/route"}
 proc bitgen {args} {error "D0291 bitgen prohibited"}
 source camera_to_dsi_display.tcl
 write_verilog pixel14-STAGE-netlist.v
 report_clock_summary -file pixel14-clocks.rpt
 report_timing_exception -file pixel14-exceptions.rpt
 if {"STAGE" eq "phy_1"} {source ../../../overlay/report-pixel14-cdc.tcl}
} message]} {puts stderr $message;exit 1}
puts "PIXEL14_STAGE_OK STAGE"
exit 0
""".replace("STAGE", stage), encoding="ascii", newline="\n")
            marker = stage_dir / (".opt_gate.end.f" if stage == "syn_1" else ".opt_route.end.f")
            stage_start = dt.datetime.now(dt.timezone.utc)
            command = [str(TOOL), drive + "/" + launcher.name]
            cwd = drive + f"/td_project/camera_to_dsi_display_Runs/{stage}"
            stdout_path, stderr_path = run / (stage + ".stdout.log"), run / (stage + ".stderr.log")
            with stdout_path.open("xb") as stdout, stderr_path.open("xb") as stderr:
                child = subprocess.Popen(command, cwd=cwd,
                                         stdout=stdout, stderr=stderr, creationflags=subprocess.CREATE_NO_WINDOW)
                save(run / (stage + ".process.json"), dict(PID=child.pid, Command=command, Cwd=cwd, StartedAt=now()))
                print(f"D0291_TD {stage} PID={child.pid}", flush=True)
                code = child.wait()
            text = stdout_path.read_text(errors="replace")
            fresh = marker.is_file() and marker.stat().st_mtime >= stage_start.timestamp()
            database = stage_dir / ("camera_to_dsi_display_gate.db" if stage == "syn_1" else "camera_to_dsi_display_pr.db")
            database_fresh = database.is_file() and database.stat().st_size > 0 and database.stat().st_mtime >= stage_start.timestamp()
            native = dict(Stage=stage, PID=child.pid, ExitCode=code, StartedAtUtc=stage_start.isoformat(),
                          FinishedAtUtc=dt.datetime.now(dt.timezone.utc).isoformat(), MarkerFresh=fresh,
                          Command=command, Cwd=cwd,
                          Stdout=artifact(stdout_path), Stderr=artifact(stderr_path),
                          Database=artifact(database) if database.is_file() else None, DatabaseFresh=database_fresh)
            result["Stages"].append(native)
            save(run / (stage + ".native.json"), native)
            verify_baselines()
            if code or not fresh or stderr_path.stat().st_size or re.search(r"\bERROR\b", text) or f"PIXEL14_STAGE_OK {stage}" not in text:
                raise RuntimeError(stage + " native/marker/log qualification failed")
            if not database_fresh:
                raise RuntimeError("Missing/freshness failure on " + str(database))
            if stage == "syn_1":
                audit = Path(__file__).with_name("audit-contour29-reset.py")
                audit_cmd = [sys.executable, "-B", "-X", "utf8", str(audit), str(run), "--output", str(run / "reset-synthesis.json")]
                with (run / "reset-audit.stdout.log").open("xb") as stdout, (run / "reset-audit.stderr.log").open("xb") as stderr:
                    audit_code = subprocess.run(audit_cmd, stdout=stdout, stderr=stderr, creationflags=subprocess.CREATE_NO_WINDOW).returncode
                if audit_code or not read(run / "reset-synthesis.json")["Qualified"]:
                    raise RuntimeError("New synthesis reset audit failed")
        verify_inputs(run)
        verify_baselines()
        if list(run.rglob("*.bit")):
            raise RuntimeError("Unexpected bit before physical review")
        result["Complete"] = True
    except BaseException as error:
        result["Failure"] = repr(error)
        raise
    finally:
        try:
            result["ChangedInputs"] = changed_inputs(run)
            result["BitFilesFound"] = [str(p) for p in run.rglob("*.bit")]
            if result["ChangedInputs"] or result["BitFilesFound"]:
                result["Complete"] = False
        except BaseException as comparison_error:
            result["InputComparisonFailure"] = repr(comparison_error)
            result["Complete"] = False
        live = child is not None and child.poll() is None
        if live:
            result["NativeStillRunning"] = True
            result["TemporaryMapping"]["PreservedForActiveNative"] = True
        else:
            mappings = subprocess.check_output(["subst.exe"], text=True).splitlines()
            if drive + "\\: => " + str(run) in mappings:
                subprocess.run(["subst.exe", drive, "/D"], check=True)
                result["TemporaryMapping"]["Released"] = True
            else:
                result["TemporaryMapping"]["ChangedByOtherProcess"] = True
            result["FinishedAt"] = now()
            save(run / "stages.json", result["Stages"])
        save(run / "result.json", result)
    return 0 if result["Complete"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
