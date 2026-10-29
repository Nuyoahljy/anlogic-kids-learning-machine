"""Prepare or execute one create-only, bounded color-vote ModelSim run.

The default only prepares frozen inputs. Native execution requires both
--execute and --allow-native. The checker negative control deliberately
changes one TB expectation; it must return a nonzero wrapper exit code.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path


RUNNER = Path(__file__).resolve()
ROOT = RUNNER.parents[3]
WORKSPACE = Path("E:/juan/FPGA").resolve()
DUT = ROOT / "fpga/rtl/sc520-color-shape-next/pixel311_color_vote.v"
TB = ROOT / "fpga/sim/sc520-color-shape-next/tb_color_vote.sv"
MODEL = ROOT / "fpga/model/sc520-color-shape-next/evaluate.py"
MODEL_OUTPUT = ROOT / "evidence/sc520-color-shape-next/model-v1-current-20261029-1118"
VECTORS = MODEL_OUTPUT / "vectors.json"
MODEL_REPORT = MODEL_OUTPUT / "model.json"
DEFAULT_VSIM = Path("D:/modeltech64_10.7/win64/vsim.exe")
MAX_RUNTIME = 180
EXPECTED_RULE = {
    "HighMinimum": 32,
    "ChromaMinimum": 24,
    "Red": "R > 2G and R > 2B",
    "Blue": "B > 2R and B > 2G",
    "Yellow": "min(R,G) >= 2B and max(R,G) <= 2*min(R,G)",
    "Vote": "unique winner; 3*winner >= 2*glyph; winner >= 2*each other color",
    "ColorID": "0 unknown, 1 red, 2 yellow, 3 blue",
}
RESULT_RE = re.compile(
    r"^\s*(?:#\s*)?RESULT errors=(?P<errors>\d+) checks=(?P<checks>\d+) "
    r"events=(?P<events>\d+) revokes=(?P<revokes>\d+) "
    r"canonical=(?P<canonical>\d+) votes=(?P<votes>\d+) "
    r"supplemental=(?P<supplemental>\d+)\s*$",
    re.MULTILINE,
)
PASS_RE = re.compile(r"^\s*(?:#\s*)?PASS color vote\s*$", re.MULTILINE)
FAIL_RE = re.compile(
    r"\b(?:FAIL|FATAL|WATCHDOG)\b|^\s*(?:#\s*)?\*\*\s*Error\b",
    re.IGNORECASE,
)
ERROR_COUNT_RE = re.compile(r"\bErrors?\s*[:=]\s*(\d+)", re.IGNORECASE)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def binding(path: Path) -> dict:
    data = path.read_bytes()
    return {
        "Path": path.resolve().as_posix(),
        "SHA256": hashlib.sha256(data).hexdigest().upper(),
        "Bytes": len(data),
    }


def same_bytes(left: dict, right: dict) -> bool:
    return left["SHA256"] == right["SHA256"] and left["Bytes"] == right["Bytes"]


def write_json(path: Path, value: dict) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n",
                    encoding="utf-8", newline="\n")


def oracle_color(rgb: list[int]) -> int:
    r, g, b = rgb
    if max(rgb) < 32 or max(rgb) - min(rgb) < 24:
        return 0
    matches = [
        (1, r > 2 * g and r > 2 * b),
        (2, min(r, g) >= 2 * b and max(r, g) <= 2 * min(r, g)),
        (3, b > 2 * r and b > 2 * g),
    ]
    winners = [color for color, match in matches if match]
    require(len(winners) <= 1, "Canonical rule is not mutually exclusive")
    return winners[0] if winners else 0


def validate_vectors(vectors: dict, report: dict, model_binding: dict) -> None:
    tool = report["Tool"]
    require(Path(tool["Path"]).resolve() == MODEL.resolve() and
            same_bytes(tool, model_binding),
            "Model report Tool must bind the current evaluate.py path/SHA256/Bytes")
    require(vectors["Schema"] == "sc520-color-shape-next.color-vote-v1",
            "Unsupported vector schema")
    require(vectors["ColorRule"] == report["Rule"] == EXPECTED_RULE,
            "Frozen color rule differs from the approved fixed model")
    canonical = vectors["CanonicalVectors"]
    votes = vectors["VoteVectors"]
    require(canonical == report["CanonicalVectors"] and votes == report["VoteVectors"],
            "Vector arrays must exactly match the frozen model report")
    require(len(canonical) == 16 and len(votes) == 12,
            "Expected all 16 canonical and 12 vote vectors")
    names = []
    for row in canonical:
        name = row["Name"]
        names.append(name)
        require(re.fullmatch(r"[A-Za-z0-9_]+", name) is not None, "Unsafe vector name")
        rgb = row["RGB"]
        require(len(rgb) == 3 and all(type(value) is int and 0 <= value <= 255
                                    for value in rgb), "Invalid canonical RGB")
        expected = oracle_color(rgb)
        require(row["ExpectedColor"] == row["PredictedColor"] ==
                row["OracleColor"] == expected and
                row["Pass"] is True and row["RuleMatchesOracle"] is True,
                "Canonical model/oracle disagreement: " + name)
    for row in votes:
        name = row["Name"]
        names.append(name)
        require(re.fullmatch(r"[A-Za-z0-9_]+", name) is not None, "Unsafe vector name")
        ids = row["ColorIDs"]
        require(1 <= len(ids) <= 16 and
                all(type(color) is int and 0 <= color <= 3 for color in ids),
                "Vote vector must contain 1..16 two-bit colors")
        counts = [ids.count(color) for color in (1, 2, 3)]
        winner = max(counts)
        qualified = (counts.count(winner) == 1 and 3 * winner >= 2 * len(ids)
                     and all(winner >= 2 * count for count in counts
                             if count != winner))
        expected = counts.index(winner) + 1 if qualified else 0
        require(row["Counts"] == counts and
                row["ExpectedColor"] == row["PredictedColor"] == expected and
                row["Qualified"] == qualified and row["Pass"] is True,
                "Vote model/oracle disagreement: " + name)
    require(len(names) == len(set(names)), "Duplicate frozen vector names")


def vector_include(vectors: dict, vector_hash: str) -> str:
    lines = ["// Generated only from the frozen vectors.json.",
             "// SHA256 " + vector_hash]
    for index, row in enumerate(vectors["CanonicalVectors"]):
        r, g, b = row["RGB"]
        rgb = (r << 16) | (g << 8) | b
        lines.append(
            f'run_canonical("{row["Name"]}", 32\'h{0xC1000000 + index:08X}, '
            f'1\'b{index % 2}, 24\'h{rgb:06X}, 2\'d{row["ExpectedColor"]});'
        )
    for index, row in enumerate(vectors["VoteVectors"]):
        packed = sum(color << (2 * i) for i, color in enumerate(row["ColorIDs"]))
        red, yellow, blue = row["Counts"]
        lines.append(
            f'run_vote("{row["Name"]}", 32\'h{0xD2000000 + index:08X}, '
            f'1\'b{index % 2}, {len(row["ColorIDs"])}, 32\'h{packed:08X}, '
            f'{red}, {yellow}, {blue}, 2\'d{row["ExpectedColor"]});'
        )
    return "\n".join(lines) + "\n"


def inspect_logs(stdout: str, stderr: str, transcript: str) -> dict:
    reports = {}
    failures = []
    for name, text in (("stdout", stdout), ("stderr", stderr),
                       ("transcript", transcript)):
        results = [{key: int(value) for key, value in match.groupdict().items()}
                   for match in RESULT_RE.finditer(text)]
        passes = len(PASS_RE.findall(text))
        reports[name] = {"Results": results, "PassMarkers": passes}
        for line in text.splitlines():
            if FAIL_RE.search(line) or any(int(value) != 0
                                          for value in ERROR_COUNT_RE.findall(line)):
                failures.append({"Log": name, "Line": line})
        if name != "stderr":
            if len(results) != 1 or passes != 1:
                failures.append({"Log": name, "Line": "Require exactly one RESULT and PASS"})
            elif not (results[0]["errors"] == 0 and results[0]["checks"] > 0 and
                      results[0]["events"] > 0 and results[0]["revokes"] > 0 and
                      results[0]["canonical"] == 16 and results[0]["votes"] == 12 and
                      results[0]["supplemental"] == 4):
                failures.append({"Log": name, "Line": "RESULT errors/coverage rejected"})
    if reports["stdout"]["Results"] != reports["transcript"]["Results"]:
        failures.append({"Log": "both", "Line": "stdout/transcript RESULT mismatch"})
    injection = any("INJECT_CHECKER_FAILURE" in row["Line"] for row in failures)
    error_results = any(row["errors"] > 0 for report in reports.values()
                        for row in report["Results"])
    return {
        "ReportSuccess": not failures,
        "Logs": reports,
        "Failures": failures,
        "CheckerFailureObserved": injection and error_results,
    }


def protection_after(inputs: list[dict], tools: list[dict],
                     controls: list[dict]) -> dict:
    checked_inputs = []
    checked_tools = []
    checked_controls = []
    failures = []
    for row in inputs:
        after = {"Role": row["Role"]}
        for kind in ("Source", "FrozenCopy"):
            try:
                current = binding(Path(row[kind]["Path"]))
                after[kind] = current
                after[kind + "Unchanged"] = current == row[kind]
            except OSError as error:
                after[kind + "Unchanged"] = False
                after[kind + "Error"] = str(error)
            if not after[kind + "Unchanged"]:
                failures.append(row["Role"] + " " + kind + " changed")
        checked_inputs.append(after)
    for rows, checked in ((tools, checked_tools), (controls, checked_controls)):
        for before in rows:
            try:
                current = binding(Path(before["Path"]))
                unchanged = current == before
                checked.append({"Before": before, "After": current,
                                "Unchanged": unchanged})
            except OSError as error:
                unchanged = False
                checked.append({"Before": before, "Unchanged": False,
                                "Error": str(error)})
            if not unchanged:
                failures.append("Changed protected file: " + before["Path"])
    return {"Inputs": checked_inputs, "Tools": checked_tools,
            "Controls": checked_controls, "AllUnchanged": not failures,
            "Failures": failures}


def as_text(value: str | bytes | None) -> str:
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return value or ""


def stop_owned_tree(process: subprocess.Popen, taskkill: Path | None) -> dict:
    cleanup = {"OwnedPID": process.pid, "Attempted": False}
    if process.poll() is not None:
        cleanup["RootAlreadyExited"] = True
        return cleanup
    cleanup["Attempted"] = True
    if os.name == "nt":
        require(taskkill is not None, "Owned-process cleanup tool is missing")
        command = [str(taskkill), "/PID", str(process.pid), "/T", "/F"]
        cleanup["Command"] = command
        try:
            result = subprocess.run(command, text=True, capture_output=True,
                                    encoding="utf-8", errors="replace", timeout=10)
            cleanup.update({"ExitCode": result.returncode,
                            "Stdout": result.stdout, "Stderr": result.stderr})
        except subprocess.TimeoutExpired as error:
            cleanup.update({"TimedOut": True, "Stdout": as_text(error.stdout),
                            "Stderr": as_text(error.stderr)})
    else:
        os.killpg(process.pid, signal.SIGKILL)
        cleanup["Signal"] = "SIGKILL owned new process group"
    return cleanup


def prepare(output: Path, vsim: Path, execute: bool, allow_native: bool,
            vectors_path: Path = VECTORS, model_report: Path = MODEL_REPORT,
            inject_checker_failure: bool = False) -> dict:
    output = output.resolve()
    vsim = vsim.resolve()
    require(not output.exists(), "Output already exists; choose a new directory")
    require(output != WORKSPACE and WORKSPACE in output.parents,
            "Output must remain inside the shared workspace")
    if execute:
        require(allow_native, "Native execution requires explicit --allow-native")
    sources = [
        ("DUT", DUT), ("TB", TB), ("Runner", RUNNER), ("Model", MODEL),
        ("ModelReport", model_report.resolve()), ("Vectors", vectors_path.resolve()),
    ]
    source_bindings = []
    for role, path in sources:
        require(path.is_file(), "Missing frozen input: " + str(path))
        source_bindings.append((role, path, binding(path)))
    vectors = json.loads(vectors_path.read_text(encoding="utf-8-sig"))
    report = json.loads(model_report.read_text(encoding="utf-8-sig"))
    validate_vectors(vectors, report, next(item[2] for item in source_bindings
                                          if item[0] == "Model"))
    tool_paths = [Path(sys.executable).resolve()]
    native_tools = [vsim, vsim.with_name("vlog.exe"), vsim.with_name("vlib.exe")]
    for path in native_tools:
        if execute:
            require(path.is_file(), "Missing native tool: " + str(path))
        if path.is_file():
            tool_paths.append(path)
    taskkill = None
    if os.name == "nt":
        taskkill_name = shutil.which("taskkill.exe")
        if execute:
            require(taskkill_name is not None, "Cannot protect owned process timeout")
        if taskkill_name:
            taskkill = Path(taskkill_name).resolve()
            tool_paths.append(taskkill)
    tools_before = [binding(path) for path in tool_paths]

    input_dir = output / "input"
    result_dir = output / "result"
    output.mkdir(parents=True, exist_ok=False)
    input_dir.mkdir()
    inputs = []
    for role, source, before in source_bindings:
        filename = {"ModelReport": "model-report.json", "Vectors": "vectors.json"}.get(
            role, source.name)
        destination = input_dir / filename
        shutil.copyfile(source, destination)
        frozen = binding(destination)
        require(same_bytes(before, frozen) and binding(source) == before,
                "Input changed while freezing: " + str(source))
        inputs.append({"Role": role, "Source": before, "FrozenCopy": frozen})
    include = input_dir / "model_vectors.svh"
    include.write_text(vector_include(vectors, next(item[2]["SHA256"]
                                                   for item in source_bindings
                                                   if item[0] == "Vectors")),
                       encoding="ascii", newline="\n")
    define = " +define+INJECT_CHECKER_FAILURE" if inject_checker_failure else ""
    compile_do = (
        "onerror {quit -f -code 2}\n"
        "onbreak {quit -f -code 3}\n"
        f'puts [exec "{native_tools[2].as_posix()}" work 2>@1]\n'
        f'puts [exec "{native_tools[1].as_posix()}" -sv{define} '
        f'"+incdir+{input_dir.as_posix()}" -work work '
        f'"{(input_dir / DUT.name).as_posix()}" '
        f'"{(input_dir / TB.name).as_posix()}" 2>@1]\n'
    )
    run_do = (
        "onerror {quit -f -code 2}\n"
        "onbreak {quit -f -code 3}\n"
        "vsim -voptargs=+acc work.tb_color_vote\n"
        "run -all\n"
        "quit -f -code 0\n"
    )
    compile_path = output / "compile.do"
    run_path = output / "run.do"
    compile_path.write_text(compile_do, encoding="utf-8", newline="\n")
    run_path.write_text(run_do, encoding="utf-8", newline="\n")
    controls_before = [binding(path) for path in (include, compile_path, run_path)]
    manifest = {
        "Version": "sc520-color-shape-next-color-vote-run-v2",
        "At": datetime.now(timezone(timedelta(hours=8))).isoformat(),
        "Root": ROOT.as_posix(), "Output": output.as_posix(),
        "InputsBefore": inputs, "ToolsBefore": tools_before,
        "ControlsBefore": controls_before,
        "NativeRequested": execute, "NativeAllowed": allow_native,
        "InjectCheckerFailure": inject_checker_failure,
        "Coverage": {"Canonical": 16, "Vote": 12, "SupplementalThreshold": 4},
        "TimeoutSeconds": MAX_RUNTIME, "NativeToolExecuted": False,
        "ReportSuccess": False, "Accepted": False, "WrapperExitCode": 0,
        "Result": None,
    }
    manifest_path = output / "run-manifest.json"
    manifest["ProtectionAfter"] = protection_after(inputs, tools_before, controls_before)
    write_json(manifest_path, manifest)
    require(manifest["ProtectionAfter"]["AllUnchanged"], "Preparation input protection failed")
    if not execute:
        return manifest

    result_dir.mkdir()
    env = os.environ.copy()
    env["MTI_VCO_MODE"] = "0"
    command = [str(vsim), "-c", "-l", str(result_dir / "transcript.log"),
               "-do", f'do "{compile_path.as_posix()}"; do "{run_path.as_posix()}"']
    manifest["Command"] = command
    manifest["NativeLaunchAt"] = datetime.now(timezone(timedelta(hours=8))).isoformat()
    write_json(manifest_path, manifest)
    started = time.monotonic()
    process = None
    stdout = ""
    stderr = ""
    timed_out = False
    cleanup = None
    launch_error = None
    interrupted = False
    try:
        options = {"creationflags": subprocess.CREATE_NEW_PROCESS_GROUP} if os.name == "nt" else {
            "start_new_session": True}
        process = subprocess.Popen(command, cwd=output, env=env, text=True,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   encoding="utf-8", errors="replace", **options)
        manifest["NativeToolExecuted"] = True
        manifest["OwnedPID"] = process.pid
        write_json(manifest_path, manifest)
        try:
            stdout, stderr = process.communicate(timeout=MAX_RUNTIME)
        except subprocess.TimeoutExpired as error:
            timed_out = True
            stdout, stderr = as_text(error.stdout), as_text(error.stderr)
            cleanup = stop_owned_tree(process, taskkill)
            try:
                stdout, stderr = process.communicate(timeout=10)
            except subprocess.TimeoutExpired as remainder:
                stdout, stderr = as_text(remainder.stdout), as_text(remainder.stderr)
                launch_error = "Owned process pipes did not close after timeout cleanup"
    except KeyboardInterrupt:
        interrupted = True
        launch_error = "Interrupted while running the owned ModelSim process"
    except Exception as error:
        launch_error = str(error)
    finally:
        if process is not None and process.poll() is None:
            cleanup = stop_owned_tree(process, taskkill)
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                launch_error = "Owned ModelSim process survived bounded cleanup"
        if process is not None:
            for pipe in (process.stdout, process.stderr):
                if pipe is not None:
                    pipe.close()
    (result_dir / "stdout.log").write_text(stdout, encoding="utf-8", newline="\n")
    (result_dir / "stderr.log").write_text(stderr, encoding="utf-8", newline="\n")
    transcript_path = result_dir / "transcript.log"
    transcript = transcript_path.read_text(encoding="utf-8", errors="replace") \
        if transcript_path.is_file() else ""
    log_result = inspect_logs(stdout, stderr, transcript)
    protection = protection_after(inputs, tools_before, controls_before)
    native_exit = process.returncode if process is not None else None
    accepted = (native_exit == 0 and not timed_out and launch_error is None and
                log_result["ReportSuccess"] and protection["AllUnchanged"] and
                not inject_checker_failure)
    wrapper_exit = 0 if accepted else 130 if interrupted else 124 if timed_out else 1
    result = {
        "Command": command, "OwnedPID": process.pid if process else None,
        "NativeExitCode": native_exit, "WrapperExitCode": wrapper_exit,
        "TimedOut": timed_out, "ElapsedSeconds": time.monotonic() - started,
        "LaunchOrCleanupError": launch_error, "OwnedTreeCleanup": cleanup,
        "ReportSuccess": log_result["ReportSuccess"], "Accepted": accepted,
        "CheckerFailureExpected": inject_checker_failure,
        "CheckerFailureObserved": log_result["CheckerFailureObserved"],
        "LogAnalysis": log_result,
        "Logs": [str(result_dir / "stdout.log"), str(result_dir / "stderr.log"),
                 str(transcript_path)],
    }
    manifest.update({"Result": result, "ProtectionAfter": protection,
                     "ReportSuccess": result["ReportSuccess"], "Accepted": accepted,
                     "WrapperExitCode": wrapper_exit})
    write_json(result_dir / "acceptance.json", result)
    write_json(manifest_path, manifest)
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--vsim", type=Path, default=DEFAULT_VSIM)
    parser.add_argument("--vectors", type=Path, default=VECTORS)
    parser.add_argument("--model-report", type=Path, default=MODEL_REPORT)
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--allow-native", action="store_true")
    parser.add_argument("--inject-checker-failure", action="store_true")
    args = parser.parse_args()
    try:
        manifest = prepare(args.output, args.vsim, args.execute, args.allow_native,
                           args.vectors, args.model_report, args.inject_checker_failure)
        print(json.dumps(manifest, ensure_ascii=False, indent=2))
        return manifest["WrapperExitCode"]
    except Exception as error:
        print("ERROR " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
