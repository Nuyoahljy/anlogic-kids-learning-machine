"""Audit a completed I2C-fix build and its three routed data mailboxes.

The 0107 audit script is archived separately; this version requires the new
I2C reports and must not regenerate a historical candidate audit.
"""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import argparse
import importlib.util
import json
import re
import xml.etree.ElementTree as ET


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def clock_periods(text):
    result = {}
    for name, period in re.findall(r"triggered by clock (\S+)\s+\{[^}]*period=([0-9.]+)", text):
        result.setdefault(name, set()).add(float(period))
    assert result, "No timing-path clock periods"
    return result


def object_names(path, phys):
    result = {}
    for line in phys.read(path).splitlines():
        label, count, values = line.split(" ", 2)
        assert label in ("FROM", "TO") and label not in result, (path, label)
        names = [braced or plain for braced, plain in re.findall(r"\{([^{}]+)\}|([^\s{}]+)", values)]
        assert len(names) == int(count) and len(set(names)) == len(names), (path, label)
        result[label] = set(names)
    assert set(result) == {"FROM", "TO"}, path
    return result


def payload_paths(path, cells, phys, clock_pair):
    """Separate packed same-clock paths before decoding mailbox data inputs.

    TD get_regs expands a packed cell to unrelated registers and enables.
    These paths remain in the evidence, but are not mailbox data paths.
    Every asynchronous path must still decode and match an expected bit.
    """
    result = []
    for block in re.split(r"(?m)^Slack\s+:", phys.read(path))[1:]:
        def field(label):
            match = re.search(r"(?m)^" + re.escape(label) + r"\s+:\s*(.*)$", block)
            assert match, (path, label)
            return match[1]
        start, end = field("Begin Point"), field("End Point")
        record = {
            "Check": field("Check Type"), "FromClock": re.search(r"clock (\S+)", start)[1],
            "ToClock": re.search(r"clock (\S+)", end)[1],
            "Begin": start.split()[0], "End": end.split()[0],
            "DelayNs": float(field("Data Path Delay").split("ns", 1)[0]),
            "BudgetNs": float(field("Budget").split("ns", 1)[0]),
            "SlackNs": float(block.strip().split("ns", 1)[0]),
        }
        assert record["Check"] in ("setup", "hold"), record
        if record["FromClock"] == record["ToClock"]:
            assert record["FromClock"] in clock_pair, record
            record["ExcludedReason"] = "Same-clock packed-cell path, not asynchronous payload"
            result.append(record)
            continue
        assert (record["FromClock"], record["ToClock"]) == clock_pair, record
        data = block[block.index("clk2q"):].split("Arrival", 1)[0]
        q_pin = re.search(r"(?m)^clk2q.*pin:\s*(\S+)", data)[1]
        q_cell, q_port = q_pin.rsplit(".", 1)
        d_cell, d_port = record["End"].rsplit(".", 1)
        assert q_port in ("oqa", "oqb"), q_pin
        source_net = cells[q_cell][1][q_port]
        params, ports = cells[d_cell]
        registered = re.findall(r"(?m)^.*\(reg\).*net:\s*([^,]+)", data)
        if registered:
            destination_net = phys.net(registered[-1])
            candidates = ["oq" + half.lower() for half in "AB"
                          if ports.get("oq" + half.lower()) == destination_net]
        else:
            candidates = ["oq" + half.lower() for half in "AB"
                          if params.get("REG" + half + "_SD") == d_port.upper()]
            assert len(candidates) == 1, (record["End"], params)
            destination_net = ports[candidates[0]]
        assert len(candidates) == 1, (record["End"], destination_net, params)
        assert source_net in phys.net(data), (path, source_net)
        record.update(SourceQ=q_pin, SourceNet=source_net, DestinationNet=destination_net,
                      DestinationQ=d_cell + "." + candidates[0])
        result.append(record)
    assert result, path
    return result


def mailbox_audit(name, prefix, objects, report_path, cells, phys, clock_pair):
    expected = {int(match[1]) for value in objects["FROM"]
                if (match := re.fullmatch(re.escape(prefix) + r"/held_data\[(\d+)\]", value))}
    retained = {int(match[1]) for _, ports in cells.values() for pin in ("oqa", "oqb")
                if (match := re.fullmatch(re.escape(prefix) + r"/held_data\[(\d+)\]", ports.get(pin, "")))}
    assert expected and expected == retained, (name, expected, retained)
    all_paths = payload_paths(report_path, cells, phys, clock_pair)
    selected = [p for p in all_paths if (p["FromClock"], p["ToClock"]) == clock_pair and
                p["SourceNet"].startswith(prefix + "/held_data[")]
    assert len(selected) == sum(p["FromClock"] != p["ToClock"] for p in all_paths), name
    mapping = {}
    for check in ("setup", "hold"):
        chosen = [p for p in selected if p["Check"] == check]
        bits = set()
        for p in chosen:
            bit = int(re.fullmatch(re.escape(prefix) + r"/held_data\[(\d+)\]", p["SourceNet"])[1])
            assert bit not in bits, (name, bit)
            bits.add(bit)
            aliases = {}
            if name == "business":
                aliases = {90 + i: f"u_p14_pipeline/system/joiner/block_item[{i}]" for i in range(4)}
                aliases.update({41 + i: f"u_p14_pipeline/system/joiner/card_item[{i}]" for i in range(4)})
                aliases.update({95: "u_p14_pipeline/system/joiner/block_present", 94: "u_p14_pipeline/system/joiner/block_valid", 46: "u_p14_pipeline/system/joiner/card_present"})
            allowed = {prefix + f"/dst_data[{bit}]"}
            if bit in aliases:
                allowed.add(aliases[bit])
            if name == "diagnostic":
                allowed.update({f"S_p14_diag_display[{bit}]", f"u_p14_diag_osd/diagnostic[{bit}]"})
            if name == "i2c":
                allowed.add(f"S_p14_i2c_capture[{bit}]")
            assert p["SourceNet"] in objects["FROM"], (name, bit, p)
            assert p["DestinationNet"] in allowed & objects["TO"], (name, bit, p)
            assert 0 <= p["DelayNs"] < 10.0, (name, p)
            mapping.setdefault(str(bit), {})[check] = p
        assert bits == expected, (name, check, expected - bits, bits - expected)
        assert len({p["SourceQ"] for p in chosen}) == len(expected)
        assert len({p["DestinationQ"] for p in chosen}) == len(expected)
        assert len({p["End"] for p in chosen}) == len(expected)
    for bit, checks in mapping.items():
        assert all(checks["setup"][key] == checks["hold"][key]
                   for key in ("SourceQ", "SourceNet", "DestinationQ", "DestinationNet", "End")), (name, bit)
    return {"Name": name, "ClockPair": list(clock_pair), "Bits": len(expected),
            "RetainedLogicalBits": sorted(expected), "Paths": mapping,
            "ExcludedPaths": len(all_paths) - len(selected),
            "ExcludedPathDetails": [p for p in all_paths if p["FromClock"] == p["ToClock"]],
            "MaximumDataPathNs": max(p["DelayNs"] for p in selected if p["Check"] == "setup"),
            "ExternalPropagationLimitNs": 10.0, "SynchronousSetupHoldQualification": False}


def main(run):
    common = module("p14_base_audit", "audit-build.py")
    phys = module("p14_physical_parser", "audit-recovery.py")
    root = Path(__file__).resolve().parents[4]
    output = run / "candidate-audit.json"
    assert not output.exists(), "Candidate audit is immutable"
    result = json.loads(phys.read(run / "result.json"))
    assert not result["ChangedInputs"]
    assert [(s["Stage"], s["ExitCode"], s["MarkerFresh"]) for s in result["Stages"]] == [
        ("syn_1", 0, True), ("phy_1", 0, True)]
    # Shared ROM decoder checks every initialized word and routed signatures.
    # Preserve an earlier base audit if a physical check needs repair/retry.
    if not (run / "audit.json").exists():
        common.audit(run)
    base = json.loads(phys.read(run / "audit.json"))
    assert not base["CurrentSourceDifferences"] and not base["SnapshotDifferences"]
    assert base["TimingNonnegative"] and not base["UnknownModulesOrToolErrors"]
    for item in base["Artifacts"]:
        assert phys.sha(item["Path"]) == item["SHA256"], item["Path"]
    inputs = json.loads(phys.read(run / "inputs.json"))
    for item in inputs["Files"]:
        assert phys.sha(item["Path"]) == item["SHA256"], item["Path"]
        if item.get("Snapshot"):
            assert phys.sha(item["Snapshot"]) == item["SnapshotSHA256"], item["Snapshot"]
    phy = run / "td_project/camera_to_dsi_display_Runs/phy_1"
    cells = phys.slices(phys.read(phy / "pixel14-phy_1-netlist.v"))
    analysis = run / "analysis"
    pairs = []
    for direction in ("forward", "backward"):
        for signal in ("req", "ack"):
            logical = "u_p14_pipeline/" + direction + "/" + signal
            pairs.append((direction + "-" + signal, logical + "_meta", logical + "_sync"))
    for prefix, name in (("u_p14_diag_cdc", "diagnostic"), ("u_p14_i2c_cdc", "i2c")):
        for signal in ("req", "ack"):
            logical = prefix + "/" + signal
            pairs.append((name + "-" + signal, logical + "_meta", logical + "_sync"))
    pairs += [(f"key-{i}", f"u_quiz_keys/keys_sync_meta[{i}]", f"u_quiz_keys/keys_sync_safe[{i}]") for i in range(4)]
    pairs += [("staging-fault", "u_p14_pipeline/staging_fault_meta", "u_p14_pipeline/staging_fault_sync"),
              ("config-done", "S_p14_cfg_done[0]", "u_p14_provenance/cfg_done"),
              ("config-error", "S_p14_cfg_error[0]", "u_p14_provenance/cfg_error"),
              ("i2c-busy", "u_uicfgcs520/busy_meta", "u_uicfgcs520/busy_sync"),
              ("i2c-error", "u_uicfgcs520/error_meta", "u_uicfgcs520/error_sync")]
    synchronizers = []
    for name, source, destination in pairs:
        paths = phys.timing_paths(analysis / (name + ".rpt"), cells)
        assert len(paths) == 2 and {p["Check"] for p in paths} == {"setup", "hold"}, name
        for p in paths:
            assert p["SourceNet"] == source and p["DestinationNet"] == destination, (name, p)
            assert p["FromClock"] == p["ToClock"] and p["SlackNs"] >= 0, (name, p)
            if name.startswith("i2c-"):
                expected_clock = "MIPI_RX_BYTE_CLK" if name == "i2c-req" else "pll_clk_24m"
                assert p["FromClock"] == expected_clock, (name, p)
            if p["Check"] == "setup":
                assert p["BudgetNs"] == 2.0 and p["DelayNs"] < 2.0, (name, p)
        synchronizers.append({"Name": name, "Paths": paths, "TwoNsConstraintApplied": True})
    required_periods = {"MIPI_RX_BYTE_CLK": 9.660, "HDMI_PIXEL_CLK": 13.333, "pll_clk_24m": 42.000}
    original_periods = clock_periods(phys.read(phy / "final_timing.rpt"))
    for name, period in required_periods.items():
        assert original_periods.get(name) == {period}, (name, original_periods.get(name))
    # The original XML lists root clock groups, not their derived clocks.
    # Derived names/periods are checked above against routed timing paths.
    for filename, expected_names in (
        ("original-clocks.rpt", {"sys_clk_50m", "mipi_rx_ck_pad"}),
        ("analysis-clocks.rpt", set(required_periods))):
        names = {group.attrib["name"] for group in ET.fromstring(phys.read(analysis / filename)).iter("clock_group")}
        assert names == expected_names, (filename, names)
    mailboxes = []
    for name, prefix, object_file, report_file, clock_pair in [
        ("business", "u_p14_pipeline/forward", "payload-objects.txt", "payload-routing.rpt", ("MIPI_RX_BYTE_CLK", "HDMI_PIXEL_CLK")),
        ("diagnostic", "u_p14_diag_cdc", "diagnostic-objects.txt", "diagnostic-routing.rpt", ("MIPI_RX_BYTE_CLK", "HDMI_PIXEL_CLK")),
        ("i2c", "u_p14_i2c_cdc", "i2c-objects.txt", "i2c-routing.rpt", ("pll_clk_24m", "MIPI_RX_BYTE_CLK"))]:
        periods = clock_periods(phys.read(analysis / report_file))
        assert periods == {clock: {required_periods[clock]} for clock in clock_pair}, (name, periods)
        mailboxes.append(mailbox_audit(name, prefix, object_names(analysis / object_file, phys),
                                       analysis / report_file, cells, phys, clock_pair))
    assert "set_max_delay" not in phys.read(analysis / "analysis-exceptions.rpt")
    history = json.loads(phys.read(root / "evidence/sc520-card-recognition/pixel14-boardfix-baseline.json"))
    for item in [history["OldBit"], *history["ProtectedHistory"]]:
        assert phys.sha(item["Path"]) == item["SHA256"], item["Path"]
    protected = json.loads(phys.read(root / "evidence/sc520-card-recognition/pixel14-baseline.json"))["Protected"]
    for item in protected:
        assert phys.sha(item["Path"]) == item["SHA256"], item["Path"]
    report = {"VerifiedAt": datetime.now(timezone(timedelta(hours=8))).isoformat(timespec="seconds"),
              "Run": str(run), "CandidateQualified": True, "HardwareValidated": False,
              "Bit": phys.artifact(result["Bit"]), "TimingNs": base["MetricsNs"], "Resources": base["Resources"],
              "ROMs": base["ROMs"], "KeyIO": base["KeyIO"], "Synchronizers": synchronizers, "Mailboxes": mailboxes,
              "ReconstructedClockPeriodsNs": required_periods, "OriginalClockPeriodsMatched": True,
              "ProtectedFiles": len(protected), "ProtectedHistoryFiles": len(history["ProtectedHistory"]),
              "InputsChecked": len(inputs["Files"]),
              "Artifacts": [phys.artifact(p) for p in [run / "audit.json", run / "inputs.json", run / "result.json", Path(__file__), Path(__file__).with_name("audit-recovery.py"), Path(__file__).with_name("audit-build.py"), *analysis.glob("*")]],
              "Limits": "Actual bundled-data propagation is compared externally with 10 ns; derived asynchronous phase slack is not CDC signoff. No MTBF or CRC/ECC value proof. HS tail repair matches reproduced software failure; actual board recovery remains unverified."}
    with output.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(report, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
    print(json.dumps({"audit": str(output), "qualified": True, "timing": report["TimingNs"],
                      "mailboxes": [{k: m[k] for k in ("Name", "Bits", "MaximumDataPathNs")} for m in mailboxes]}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run", type=Path)
    main(parser.parse_args().run.resolve())
