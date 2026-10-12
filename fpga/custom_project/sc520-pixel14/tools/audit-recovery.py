"""Qualify the existing 106 bit without rewriting its failed build history.

The payload limit is an external assertion on routed data-path measurements,
not a claim that TD applied the attempted 10 ns exception. No TD process runs.
"""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import argparse
import collections
import hashlib
import importlib.util
import json
import re


def read(path):
    return Path(path).read_text(encoding="utf-8-sig", errors="replace")


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def net(value):
    return re.sub(r"[\\\s]", "", value)


def artifact(path):
    path = Path(path).resolve()
    return {"Path": str(path), "Bytes": path.stat().st_size, "SHA256": sha(path)}


def slices(text):
    result = {}
    pattern = r"PH1P_PHY_LSLICE\s*#\((.*?)\)\s+(\\\S+|\w+)\s*\((.*?)\);"
    for match in re.finditer(pattern, text, re.S):
        params = dict(re.findall(r'\.(\w+)\("([^"]*)"\)', match[1]))
        ports = {key: net(value) for key, value in re.findall(r"\.(\w+)\(([^()]*)\)", match[3])}
        result[net(match[2])] = (params, ports)
    assert result, "No routed LSLICE cells"
    return result


def timing_paths(path, cells):
    result = []
    for block in re.split(r"(?m)^Slack\s+:", read(path))[1:]:
        def field(label):
            match = re.search(r"(?m)^" + re.escape(label) + r"\s+:\s*(.*)$", block)
            assert match, (path, label)
            return match[1]

        start, end = field("Begin Point"), field("End Point")
        data = block[block.index("clk2q"):].split("Arrival", 1)[0]
        q_pin = re.search(r"(?m)^clk2q.*pin:\s*(\S+)", data)[1]
        q_cell, q_port = q_pin.rsplit(".", 1)
        d_pin = end.split()[0]
        d_cell, d_port = d_pin.rsplit(".", 1)
        source_net = cells[q_cell][1][q_port]
        registered = re.findall(r"(?m)^.*\(reg\).*net:\s*([^,]+)", data)
        if registered:
            destination_net = net(registered[-1])
        else:
            params, ports = cells[d_cell]
            candidates = [ports["oq" + half.lower()] for half in "AB"
                          if params.get("REG" + half + "_SD") == d_port.upper()]
            assert len(candidates) == 1, (d_pin, params)
            destination_net = candidates[0]
        assert source_net in net(data), (path, source_net)
        result.append({
            "Check": field("Check Type"), "FromClock": re.search(r"clock (\S+)", start)[1],
            "ToClock": re.search(r"clock (\S+)", end)[1],
            "Begin": start.split()[0], "End": d_pin, "SourceQ": q_pin,
            "SourceNet": source_net, "DestinationNet": destination_net,
            "DelayNs": float(field("Data Path Delay").split("ns", 1)[0]),
            "BudgetNs": float(field("Budget").split("ns", 1)[0]),
            "SlackNs": float(block.strip().split("ns", 1)[0]),
        })
    assert result, path
    return result


def audit(run, analysis_run, output):
    root = Path(__file__).resolve().parents[4]
    assert run.name == "6a50b106" and analysis_run.name == "cdc106-v3"
    assert output.resolve().parent == run.resolve(), "Output must stay in the audited run"
    assert not output.exists(), "Choose a new --output filename; preserve earlier audits"
    syn = run / "td_project/camera_to_dsi_display_Runs/syn_1"
    phy = run / "td_project/camera_to_dsi_display_Runs/phy_1"
    analysis = analysis_run / "analysis"
    stages = json.loads(read(run / "stages.json"))
    failure = json.loads(read(run / "failure.json"))
    assert [(s["Stage"], s["ExitCode"]) for s in stages] == [("syn_1", 0), ("phy_1", 1)]
    assert failure["Message"] == "TD phy_1 failed" and failure["Stages"] == stages
    expected_error = "CDC register resolution failed: u_p14_pipeline/forward/fault_meta u_p14_pipeline/forward/fault_sync"
    assert read(run / "phy_1.stderr.log").strip() == expected_error
    assert not read(run / "syn_1.stderr.log").strip()
    phy_log = read(run / "phy_1.stdout.log")
    assert 'finish command "bitgen -bit camera_to_dsi_display.bit"' in phy_log
    all_logs = read(run / "syn_1.stdout.log") + phy_log
    errors = [s for s in all_logs.splitlines() if re.search(r"\bERROR:|unknown module|black.?box", s, re.I)]
    assert not errors, errors
    post_log = read(analysis_run / "stdout.log")
    assert "PIXEL14_POSTHOC_CDC_OK" in post_log and not read(analysis_run / "stderr.log").strip()
    assert "camera_to_dsi_display_pr.db" in read(analysis_run / "query.tcl")

    inputs = json.loads(read(run / "inputs.json"))
    source_changes = []
    snapshots = 0
    allowed_helper = root / "fpga/custom_project/sc520-pixel14/overlay/report-pixel14-cdc.tcl"
    for row in inputs["Files"]:
        current = sha(row["Path"])
        if current != row["SHA256"]:
            assert Path(row["Path"]).resolve() == allowed_helper.resolve(), row["Path"]
            source_changes.append({"Path": row["Path"], "OriginalSHA256": row["SHA256"],
                                   "CurrentSHA256": current, "Role": "post-bitgen report helper only"})
        if row.get("Snapshot"):
            snapshots += 1
            assert sha(row["Snapshot"]) == row["SnapshotSHA256"], row["Snapshot"]
    assert len(source_changes) == 1

    bit = phy / "camera_to_dsi_display.bit"
    assert sha(bit) == "3909C31AA81D7EB5C3153EFC2DBAC6D54C655A82A698107AA08CB0B14AFC0ABD"
    assert bit.stat().st_size == 1789539
    timing = read(phy / "final_timing.rpt")
    metrics = {key: float(re.search(r"\b" + key + r":\s*(-?[0-9.]+)ns", timing)[1])
               for key in ("SWNS", "STNS", "HWNS", "HTNS")}
    assert metrics == {"SWNS": 0.105, "STNS": 0.0, "HWNS": 0.020, "HTNS": 0.0}
    assert "Tang Dynasty v6.2.168116" in timing and "STA coverage        : 96.12%" in timing
    area = read(phy / "camera_to_dsi_display_phy.area")
    resources = {}
    for name in ("slice", "eram", "dsp", "reg"):
        match = re.search(r"^#" + name + r"\s+(\d+)", area, re.M)
        if match:
            resources[name] = int(match[1])
    keys = []
    for index, ball in enumerate(("D5", "A9", "B9", "C7")):
        match = re.search(r"I_quiz_keys_n\[" + str(index) + r"\]\s+INPUT\s+(\S+)\s+(\S+)\s+\S+\s+\S+\s+(\S+)", area)
        assert match and match.groups() == (ball, "LVCMOS33", "PULLUP")
        keys.append({"Index": index, "Ball": ball, "Direction": "INPUT", "IOStandard": "LVCMOS33", "Pull": "PULLUP"})

    gate_path = syn / "pixel14-syn_1-netlist.v"
    route_path = phy / "pixel14-phy_1-netlist.v"
    gate, routed = read(gate_path), read(route_path)
    spec = importlib.util.spec_from_file_location("pixel14_build_audit", Path(__file__).with_name("audit-build.py"))
    common = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(common)
    font = {int(a): int(b, 16) for a, b in re.findall(r"rom\[12'd(\d+)\]=16'h([0-9A-Fa-f]+)", read(run / "rtl/items14_font_rom.v"))}
    template = [int(word, 16) for word in read(run / "templates.mem").split()]
    assert len(font) == 4096 and len(template) == 1024 and all((v & 1) == 0 for v in font.values())
    signatures = collections.Counter(sig for _, _, sig in common.memories(routed))
    roms = []
    for match, values, signature in common.memories(gate):
        name = match[2]
        if "/matcher/templates/" not in name and "/system/panel/font/" not in name:
            continue
        is_font = "/system/panel/font/" in name
        offset_match = re.search(r"font_bits\s*\[\d+:(\d+)\]", match[3]) if is_font else None
        offset = int(offset_match[1]) if offset_match else 0
        depth = 4096 if is_font else 1024
        data = sum(int(values[f"INIT_{i:02X}"], 16) << (256 * i) for i in range(64))
        parity = sum(int(values[f"INITP_{i:02X}"], 16) << (256 * i) for i in range(16))
        for address in range(depth):
            actual = ((data >> (address * 4)) & 15) | (((parity >> address) & 1) << 4)
            expected = ((font[address] >> offset) & 31) if is_font else template[address]
            assert actual == expected, (name, address)
        assert signatures[signature] >= 1
        roms.append({"Instance": name, "WordsChecked": depth, "BitOffset": offset,
                     "RoutedInitSignature": signature, "RoutedMatches": signatures[signature]})
    assert len(roms) == 4

    cells = slices(routed)
    pairs = []
    prefix = "u_p14_pipeline/"
    for direction in ("forward", "backward"):
        for signal in ("req", "ack"):
            logical = prefix + direction + "/" + signal
            pairs.append((direction + "-" + signal, logical + "_meta", logical + "_sync", True))
    for index in range(4):
        pairs.append((f"key-{index}", f"u_quiz_keys/keys_sync_meta[{index}]", f"u_quiz_keys/keys_sync_safe[{index}]", True))
    pairs.extend([("staging-fault", prefix + "staging_fault_meta", prefix + "staging_fault_sync", False),
                  ("config-done", "S_p14_cfg_done[0]", "u_p14_provenance/cfg_done", False),
                  ("config-error", "S_p14_cfg_error[0]", "u_p14_provenance/cfg_error", False)])
    top_source = net(read(run / "overlay/design_top_wrapper.v"))
    assert ".cfg_done(S_p14_cfg_done[1])" in top_source
    assert ".cfg_error(S_p14_cfg_error[1])" in top_source
    sync_results = []
    for name, source, destination, constrained in pairs:
        paths = timing_paths(analysis / (name + ".rpt"), cells)
        assert len(paths) == 2 and {p["Check"] for p in paths} == {"setup", "hold"}, name
        for path in paths:
            assert path["SourceNet"] == source and path["DestinationNet"] == destination, (name, path)
            assert path["FromClock"] == path["ToClock"] and path["SlackNs"] >= 0, (name, path)
        setup = next(p for p in paths if p["Check"] == "setup")
        hold = next(p for p in paths if p["Check"] == "hold")
        assert setup["DelayNs"] < 2.0
        assert (setup["BudgetNs"] == 2.0) == constrained
        sync_results.append({"Name": name, "Setup": setup, "Hold": hold,
                             "TwoNsConstraintApplied": constrained, "ObservedDelayBelowTwoNs": True})
    assert "PIXEL14_CDC_OPTIMIZED_CONSTANT forward fault" in post_log
    assert "PIXEL14_CDC_OPTIMIZED_CONSTANT backward fault" in post_log

    all_payload = timing_paths(analysis / "payload-max10.rpt", cells)
    cross = [p for p in all_payload if p["FromClock"] == "MIPI_RX_BYTE_CLK" and p["ToClock"] == "HDMI_PIXEL_CLK"]
    extra = [p for p in all_payload if p not in cross]
    assert len(cross) == 160 and len(extra) == 38
    assert all(p["FromClock"] == p["ToClock"] == "MIPI_RX_BYTE_CLK" for p in extra)
    from_line, to_line = read(analysis / "payload-objects.txt").splitlines()
    expected_bits = {int(i) for i in re.findall(r"held_data\[(\d+)\]", from_line)}
    assert len(expected_bits) == 80 and from_line.startswith("FROM 80 ") and to_line.startswith("TO 160 ")
    aliases = {90 + i: f"u_p14_pipeline/system/joiner/block_item[{i}]" for i in range(4)}
    aliases.update({41 + i: f"u_p14_pipeline/system/joiner/card_item[{i}]" for i in range(4)})
    aliases.update({95: "u_p14_pipeline/system/joiner/block_present", 94: "u_p14_pipeline/system/joiner/block_valid", 46: "u_p14_pipeline/system/joiner/card_present"})
    by_bit = {}
    for check in ("setup", "hold"):
        selected = [p for p in cross if p["Check"] == check]
        assert len(selected) == 80 and len({p["End"] for p in selected}) == 80
        bits = set()
        for path in selected:
            match = re.fullmatch(r"u_p14_pipeline/forward/held_data\[(\d+)\]", path["SourceNet"])
            assert match, path
            bit_index = int(match[1])
            assert bit_index not in bits
            bits.add(bit_index)
            assert path["DestinationNet"] == aliases.get(bit_index, f"u_p14_pipeline/forward/dst_data[{bit_index}]"), path
            assert path["DelayNs"] < 10.0, path
            if check == "setup":
                assert path["BudgetNs"] == 0.110
            by_bit.setdefault(bit_index, {})[check] = path
        assert bits == expected_bits
    max_delay = max(p["DelayNs"] for p in cross if p["Check"] == "setup")
    assert max_delay == 1.397
    assert "set_max_delay" not in read(analysis / "analysis-exceptions.rpt")

    protected = json.loads(read(root / "evidence/sc520-card-recognition/pixel14-baseline.json"))["Protected"]
    for row in protected:
        assert sha(row["Path"]) == row["SHA256"], row["Path"]
    paths = [run / n for n in ("inputs.json", "started.json", "stages.json", "failure.json", "syn_1.stdout.log", "syn_1.stderr.log", "phy_1.stdout.log", "phy_1.stderr.log")]
    paths += [gate_path, route_path, phy / "camera_to_dsi_display_pr.db", phy / "final_timing.rpt", phy / "camera_to_dsi_display_phy.area", bit]
    paths += list(analysis.glob("*")) + [analysis_run / n for n in ("query.tcl", "stdout.log", "stderr.log")]
    paths += [Path(__file__), Path(__file__).with_name("audit-build.py"), allowed_helper]
    report = {
        "SchemaVersion": 1, "AuditedAt": datetime.now(timezone(timedelta(hours=8))).isoformat(timespec="seconds"),
        "Owner": "SC520 recovery /root; independent read-only review /root/review_compact",
        "Run": str(run), "AnalysisRun": str(analysis_run), "RecoveryQualified": True,
        "AutomaticBuildSucceeded": False, "OriginalStageExitCodes": {s["Stage"]: s["ExitCode"] for s in stages},
        "OriginalPostBitgenFailure": expected_error, "CandidateBit": artifact(bit),
        "HardwareValidated": False, "DownloadPerformed": False, "FlashWritten": False,
        "TimingNs": metrics, "STAcoveragePercent": 96.12, "Resources": resources, "ROMs": roms, "KeyIO": keys,
        "InputRecordsChecked": len(inputs["Files"]), "SnapshotsChecked": snapshots,
        "CurrentImplementationInputsUnchanged": True, "ReportHelperChanges": source_changes,
        "ProtectedFilesChecked": len(protected), "Synchronizers": sync_results,
        "CDC": {"SourceRegisters": 80, "ExpandedDestinationCollection": 160,
                "MatchedPayloadBits": 80, "MatchedSetupPaths": 80, "MatchedMinPaths": 80,
                "ExcludedSameDomainSetupPaths": 19, "ExcludedSameDomainMinPaths": 19,
                "MaxObservedDataPathNs": max_delay, "ObservedUpperBoundNs": 10.0,
                "PayloadTenNsExceptionApplied": False, "AsynchronousSetupHoldSignoffClaimed": False,
                "PayloadByBit": {str(k): v for k, v in sorted(by_bit.items())},
                "GenericFaultSynchronizers": "Both optimized away as constant; actual staging fault separately checked",
                "Method": "Reconstructed actual physical clock pins at 9.660/13.333 ns without blanket clock-group cuts. Compare only routed Data Path Delay against external 10 ns upper bound; phase-derived slack is not a CDC pass/fail metric."},
        "CriticalWarnings": [s for s in all_logs.splitlines() if "CRITICAL-WARNING" in s],
        "Artifacts": [artifact(p) for p in paths],
        "Limits": ["Recovery audit records existing artifacts now; original failure and snapshots remain unchanged.",
                   "This report qualifies this exact routed bit as a review candidate, not all future builds.",
                   "No metastability MTBF proof; staging/config observed below 2 ns under original clock-period constraints.",
                   "No CSI CRC/ECC numeric checking, exact DDR display-frame identity, physical audio or board validation."]}
    with output.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(report, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
    print(json.dumps({"Output": str(output), "RecoveryQualified": True, "TimingNs": metrics,
                      "PayloadBits": 80, "MaxPayloadDelayNs": max_delay, "ROMs": len(roms),
                      "ProtectedFiles": len(protected), "Resources": resources}, ensure_ascii=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run", type=Path)
    parser.add_argument("analysis_run", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    audit(args.run.resolve(), args.analysis_run.resolve(),
          (args.output or args.run / "recovery-audit.json").resolve())
