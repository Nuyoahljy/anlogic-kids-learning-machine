"""Run exactly one Root-approved I0310R4C stage; never chains stages or generates bitstreams.
Required: --stage synthesis|placement|route --manifest-sha SHA --runner-sha SHA.
Placement/route also require --parent-result-sha SHA of the completed preceding stage.
The exact runner SHA and explicit stage invocation are Root's separate stage release.
"""
import argparse, hashlib, json, os, re, sys, time, traceback
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
EV = ROOT / "evidence/sc520-system-integration"
STAGES = {
    "synthesis": ("j319", "syn_1", "opt_gate", "gate", "Synthesized", 1200),
    "placement": ("q320", "pl_1", "opt_place", "place", "Placed", 1200),
    "route": ("r320", "pl_1", "opt_route", "route", "Routed", 7200),
}
SEED = 1
SEED_SOURCE = Path("D:/Anlogic/TD_6.2.1_Engineer_6.2.168.116/doc/scripts/MultiSeed.tcl")
SEED_SOURCE_SHA = "7A34989A626419FA97B15E9E69FBB42DB1232D0E757E799A85740ADC96E899E2"
STRATEGY = {"Name": "single-placement-seed", "RequestedPlacementSeed": SEED,
            "SynthesisRoot": "j319", "PlacementRoot": "q320", "RouteRoot": "r320",
            "OtherStrategyChanges": [], "Source": SEED_SOURCE.as_posix(), "SourceSHA256": SEED_SOURCE_SHA}
D = "u_ph1p35_324_ddr_wrapper/u_ddr2/"
M = "u_mipi_dphy_rx_ph1p_mipiio_wrapper/u_ph1p_mipiio_rx_wrapper/u_PH1P_LOGIC_DPHY_MIPI_RX."
CLOCKS = {"MIPI_RX_BYTE_CLK": 9.660, "HDMI_PIXEL_CLK": 13.333, "HDMI_SERIAL_CLK": 2.666,
          "pll_clk_24m": 42.000, "sys_clk_50m": 20.000, "pll_clk_100m": 10.000,
          D + "usr_clk": 15.000, D + "mcu_clk": 39.374, D + "ctl_clk": 15.000,
          D + "ddr_clk": 3.750, D + "ref_clk": 15.000, "mipi_rx_ck_pad": 2.415,
          M + "tif_c16_in": 9.660, M + "io_clk_pad_p": 2.415}

def digest(data): return hashlib.sha256(data).hexdigest().upper()

def read_hash(path, sha):
    raw = path.read_bytes()
    if not re.fullmatch(r"[0-9A-Fa-f]{64}", sha) or digest(raw) != sha.upper():
        raise RuntimeError("Exact SHA mismatch: " + str(path))
    return raw

def timing_observation(path, confidence):
    text = path.read_text(encoding="utf-8", errors="strict")
    if not re.search(r"Confidence\s*:\s*" + confidence + r"\b", text) or "Both (Slow and Fast)" not in text:
        raise RuntimeError("Wrong timing stage/corners")
    names = dict(re.findall(r"(?m)^\s*(clk\d+):\s+[0-9.]+\s+\d+\s+([^\r\n]+)", text))
    periods = {}
    for line in text.splitlines():
        match = re.match(r"^\s*(clk\d+)\s+", line)
        if not match or match[1] not in names: continue
        values = [float(x) for x in line.split() if re.fullmatch(r"[+-]?\d+(?:\.\d+)?", x)]
        if len(values) >= 3: periods[names[match[1]].strip()] = values[2]
    if set(periods) != set(CLOCKS) or any(abs(periods[n] - CLOCKS[n]) > .001 for n in CLOCKS):
        raise RuntimeError("The complete 14-clock identity/period table changed")
    values = {}
    for key in ("SWNS", "STNS", "HWNS", "HTNS"):
        match = re.search(r"\b" + key + r":\s*([+-]?[0-9.]+)ns", text)
        if not match: raise RuntimeError("Missing timing metric " + key)
        values[key] = float(match[1])
    return {"Confidence": confidence, "Corners": "Both", "Clocks": periods, **values,
            "NonnegativeUnderCurrentConstraints": values["SWNS"] >= 0 and values["HWNS"] >= 0 and values["STNS"] == 0 and values["HTNS"] == 0}

def area_observation(path):
    text = path.read_text(encoding="utf-8", errors="strict"); resources = {}
    for name in ("slice", "eram", "dsp"):
        match = re.search(r"(?m)^#" + name + r"\*?\s+(\d+)\s+out of\s+(\d+)", text)
        if not match: raise RuntimeError("Missing resource count " + name)
        resources[name] = {"Used": int(match[1]), "Available": int(match[2])}
    return {"Resources": resources, "Fits": all(r["Used"] <= r["Available"] for r in resources.values())}

def physical_launcher(stage, cwd, db):
    if stage not in ("placement", "route"): raise RuntimeError("Physical launcher only accepts placement or route")
    opt, label, mode = ("opt_place", "place", "manhattan") if stage == "placement" else ("opt_route", "route", "route")
    forbidden = "route elaborate optimize_rtl optimize_gate" if stage == "placement" else "place opt_place elaborate optimize_rtl optimize_gate"
    prefix = cwd.as_posix()
    seed_commands = ([f"set_param place seed {SEED}"] if stage == "placement" else [])
    seed_report = (["report_param -detail -stage place -file {" + prefix + "/i0310r4c-seed-parameters.rpt}"]
                   if stage == "placement" else [])
    lines = ["proc i0310_physical_stage {} {", "source {" + prefix + "/settings.cfg}",
             'if {$device_name ne "ph1_35p.db" || $package_name ne "PH1P35MDG324" || $speed ne "3" || $run_type ne "phy" || $diagnostic_only ne "true"} {error "Wrong I0310R4C physical settings"}',
             f'if {{$start_step ne "{opt}" || $end_step ne "{opt}"}} {{error "Wrong isolated physical stage"}}',
             "foreach command {" + forbidden + ' bitgen insert_debugger clear_sdc read_sdc read_adc} {proc $command {args} {error "Outside this I0310R4C stage"}}',
             "cd {" + prefix + "}", f'if {{[file exists .{opt}.begin.f] || [file exists .{opt}.end.f] || [file exists .stop.f]}} {{error "Consumed native stage"}}',
             f'set i0310_fd [open .{opt}.begin.f {{WRONLY CREAT EXCL}}]; puts $i0310_fd [pid]; close $i0310_fd',
             "import_device $device_name -package $package_name -speed $speed",
             "open_project {" + prefix + "/camera_to_dsi_display.prj} -noanalyze",
             "cd {" + prefix + "}", "import_db {" + db.as_posix() + "}",
             *seed_commands, "commit_param -step " + label, *seed_report, label, "update_timing -mode " + mode,
             "report_timing_summary -file {" + prefix + "/i0310r4c-timing.rpt}",
             "report_area -io_info -file {" + prefix + "/i0310r4c-area.rpt}",
             "flow_status -file {" + prefix + "/i0310r4c-flow.status}",
             "report_clock_utilization -file {" + prefix + "/i0310r4c-clock-utilization.rpt}",
             "report_clock_summary -file {" + prefix + "/i0310r4c-clocks.rpt}",
             "report_timing_exception -file {" + prefix + "/i0310r4c-exceptions.rpt}",
             "report_timing_ignored -file {" + prefix + "/i0310r4c-ignored.rpt}",
             "export_db {" + prefix + f"/camera_to_dsi_display_{label}.db}}",
             f"export_flow_status -s {opt} -e {opt}",
             f"set i0310_fd [open .{opt}.end.f {{WRONLY CREAT EXCL}}]; close $i0310_fd", "}",
             'if {[catch {i0310_physical_stage} reason]} {puts stderr $reason; exit 1}',
             'puts "I0310R4C_' + stage.upper() + '_NATIVE_COMPLETE"', "exit 0", ""]
    return "\n".join(lines).encode("ascii")

def execute(args):
    if args.stage not in STAGES: raise RuntimeError("Unknown stage")
    runner = Path(__file__).resolve(); runner_bytes = read_hash(runner, args.runner_sha)
    manifest_path = EV / "j319/preparation-result.json"
    manifest_bytes = read_hash(manifest_path, args.manifest_sha); manifest = json.loads(manifest_bytes)
    if manifest.get("Version") != "I0310R4C" or manifest.get("Prepared") is not True or manifest.get("DebuggerMode") != "no-chip-debugger":
        raise RuntimeError("Wrong prepared candidate")
    if [manifest.get(k) for k in ("PhysicalSourceFiles", "SourceRoles", "CompileCount")] != [355, 353, 153]:
        raise RuntimeError("Prepared counts differ")
    prepare_path = runner.with_name("prepare-build.py")
    entry = next(r for r in manifest["Scripts"] if Path(r["Path"]).resolve() == prepare_path)
    library_bytes = read_hash(prepare_path, entry["SHA256"])
    lib = {"__name__": "i0310_prepared_support", "__file__": str(prepare_path)}
    exec(compile(library_bytes, str(prepare_path), "exec"), lib)
    bind, check, save, write = (lib[n] for n in ("binding", "read_bound", "save", "write"))
    inputs = manifest["Inputs"] + list(manifest["Files"].values()) + [bind(manifest_path, manifest_bytes), bind(runner, runner_bytes)]
    source_bytes = read_hash(SEED_SOURCE, SEED_SOURCE_SHA)
    inputs += [bind(SEED_SOURCE, source_bytes)]
    for row in inputs: check(row)
    root_name, run_name, opt, label, confidence, budget = STAGES[args.stage]
    stage_root = EV / root_name; cwd = stage_root / "td" / run_name
    if manifest["Budgets"][args.stage] != budget: raise RuntimeError("Budget differs from reviewed maximum")
    parent_db = None
    if args.stage != "synthesis":
        if not args.parent_result_sha: raise RuntimeError("An exact parent result SHA is required")
        previous = "synthesis" if args.stage == "placement" else "placement"
        parent_root = EV / STAGES[previous][0]; parent_result = parent_root / (previous + "-result.json")
        parent_bytes = read_hash(parent_result, args.parent_result_sha); parent = json.loads(parent_bytes)
        if parent.get("Stage") != previous or parent.get("ExecutionComplete") is not True: raise RuntimeError("Parent stage did not complete")
        if args.stage == "route" and parent.get("PhysicalStrategy") != STRATEGY:
            raise RuntimeError("Parent placement does not identify the reviewed seed-1 strategy")
        inputs += [bind(parent_result, parent_bytes)] + list(parent["OutputFiles"].values())
        parent_db = parent_root / "td" / STAGES[previous][1] / ("camera_to_dsi_display_" + STAGES[previous][3] + ".db")
        if parent["Database"] != bind(parent_db): raise RuntimeError("Parent database identity differs")
        for row in inputs: check(row)
        stage_root.mkdir()  # Exclusive; a failed physical root is never reused.
        donor = "q310" if args.stage == "placement" else "r310"
        settings_path = EV / donor / "td/pl_1/settings.cfg"
        settings = check(next(r for r in manifest["Inputs"] if Path(r["Path"]).resolve() == settings_path.resolve()))
        for old, new in (("j309", "j319"), ("q310", "q320"), ("r310", "r320")):
            settings = settings.replace((EV / old).as_posix().encode(), (EV / new).as_posix().encode())
        project_row = manifest["Files"]["td/syn_1/camera_to_dsi_display.prj"]
        inputs += [write(cwd / "camera_to_dsi_display.prj", check(project_row)), write(cwd / "settings.cfg", settings),
                   write(cwd / "stage.launch.tcl", physical_launcher(args.stage, cwd, parent_db))]
    elif args.parent_result_sha:
        raise RuntimeError("Synthesis must not accept an old parent DB/result")
    launcher = cwd / ("synth.launch.tcl" if args.stage == "synthesis" else "stage.launch.tcl")
    if (cwd / ("." + opt + ".begin.f")).exists() or (cwd / ("." + opt + ".end.f")).exists():
        raise RuntimeError("Consumed stage output")
    command = [lib["TOOL"].as_posix(), launcher.as_posix()]
    request = {"At": datetime.now().astimezone().isoformat(), "Stage": args.stage, "Command": command,
               "Cwd": cwd.as_posix(), "BudgetSeconds": budget, "Manifest": bind(manifest_path), "Runner": bind(runner, runner_bytes),
               "PhysicalStrategy": STRATEGY, "Protected": inputs}
    save(stage_root / (args.stage + "-request.json"), request)
    result = {"Stage": args.stage, "Runner": bind(runner, runner_bytes), "PhysicalStrategy": STRATEGY,
              "SeedParametersReport": None, "SeedValueReviewed": False, "ExecutionComplete": False, "Native": None, "Failure": None,
              "ChangedInputs": [], "OutputFiles": {}, "Database": None, "TimingObservation": None,
              "DebuggerMode": "no-chip-debugger", "ClockQualified": False, "CDCQualified": False,
              "TimingQualified": False, "BitgenAllowed": False, "HardwareValidated": False}
    try:
        helper_row = next(r for r in inputs if Path(r["Path"]).resolve() == lib["HELPER"].resolve())
        helper = {"__name__": "i0310_owned_process", "__file__": helper_row["Path"]}
        exec(compile(check(helper_row), helper_row["Path"], "exec"), helper)
        for row in inputs: check(row)
        start = time.monotonic()
        with (cwd / "native.stdout.log").open("xb") as stdout, (cwd / "native.stderr.log").open("xb") as stderr:
            native = helper["run_owned_process"](command, cwd, stdout, stderr, budget, os.environ.copy(),
                lambda row: save(cwd / "native.started.json", row),
                on_created=lambda row: save(cwd / "native.created.json", row), wall_deadline=start + budget)
        result["Native"] = native; save(cwd / "native.process.json", native)
        if native["NativeExit"] != 0 or not native["NaturalNativeExit"] or not native["TreeCleanVerified"] or native["Error"] or native["TimedOut"] or native["CleanupErrors"]:
            raise RuntimeError("Native stage/lifecycle failed")
        log = (cwd / "native.stdout.log").read_text(encoding="utf-8", errors="replace")
        if "I0310R4C_" + args.stage.upper() + "_NATIVE_COMPLETE" not in log.splitlines(): raise RuntimeError("Missing completion token")
        if re.search(r"(?m)^[A-Z]+-\d+\s+(?:ERROR|FATAL)\b", log): raise RuntimeError("Native diagnostic error")
        required = ["camera_to_dsi_display_" + label + ".db", "i0310r4c-timing.rpt", "i0310r4c-clocks.rpt", "i0310r4c-exceptions.rpt", "i0310r4c-ignored.rpt"]
        required += (["camera_to_dsi_display_gate.area", "gate_flow.status", "i0310r4c-synthesis-netlist.v"] if args.stage == "synthesis"
                     else ["i0310r4c-area.rpt", "i0310r4c-flow.status", "i0310r4c-clock-utilization.rpt"])
        if args.stage == "placement": required.append("i0310r4c-seed-parameters.rpt")
        if any(not (cwd / n).is_file() or (cwd / n).stat().st_size == 0 for n in required): raise RuntimeError("Missing new DB/report")
        if not (cwd / ("." + opt + ".begin.f")).exists() or not (cwd / ("." + opt + ".end.f")).exists(): raise RuntimeError("Missing stage begin/end markers")
        result["TimingObservation"] = timing_observation(cwd / "i0310r4c-timing.rpt", confidence)
        area_name = "camera_to_dsi_display_gate.area" if args.stage == "synthesis" else "i0310r4c-area.rpt"
        result["AreaObservation"] = area_observation(cwd / area_name)
        if args.stage == "placement":
            result["SeedParametersReport"] = bind(cwd / "i0310r4c-seed-parameters.rpt")
        if list(cwd.rglob("*.bit")): raise RuntimeError("Unexpected bitstream output")
        result["Database"] = bind(cwd / required[0]); result["ExecutionComplete"] = True
    except BaseException as error:
        result["Failure"] = f"{type(error).__name__}: {error}"; result["Traceback"] = traceback.format_exc()
    finally:
        for row in inputs:
            try: check(row)
            except BaseException as error: result["ChangedInputs"].append({"Path": row["Path"], "Error": str(error)})
        if result["ChangedInputs"]: result["ExecutionComplete"] = False
        result["OutputFiles"] = {p.relative_to(cwd).as_posix(): bind(p) for p in sorted(cwd.rglob("*")) if p.is_file()}
        result["At"] = datetime.now().astimezone().isoformat()
        saved = save(stage_root / (args.stage + "-result.json"), result)
    print(json.dumps({"ExecutionComplete": result["ExecutionComplete"], "Failure": result["Failure"], "ChangedInputs": len(result["ChangedInputs"]), "Result": saved}))
    return 0 if result["ExecutionComplete"] else 1

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", choices=STAGES, required=True)
    parser.add_argument("--manifest-sha", required=True); parser.add_argument("--runner-sha", required=True)
    parser.add_argument("--parent-result-sha")
    sys.exit(execute(parser.parse_args()))
