"""Audit a completed board-fix build and both routed bundled-data mailboxes."""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import argparse
import importlib.util
import json
import re


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).with_name(filename))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def payload_paths(path, cells, phys):
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
            assert record["FromClock"] in ("MIPI_RX_BYTE_CLK", "HDMI_PIXEL_CLK"), record
            record["ExcludedReason"] = "Same-clock packed-cell path, not asynchronous payload"
            result.append(record)
            continue
        assert (record["FromClock"], record["ToClock"]) == ("MIPI_RX_BYTE_CLK", "HDMI_PIXEL_CLK"), record
        data = block[block.index("clk2q"):].split("Arrival", 1)[0]
        q_pin = re.search(r"(?m)^clk2q.*pin:\s*(\S+)", data)[1]
        q_cell, q_port = q_pin.rsplit(".", 1)
        d_cell, d_port = record["End"].rsplit(".", 1)
        source_net = cells[q_cell][1][q_port]
        registered = re.findall(r"(?m)^.*\(reg\).*net:\s*([^,]+)", data)
        if registered:
            destination_net = phys.net(registered[-1])
        else:
            params, ports = cells[d_cell]
            candidates = [ports["oq" + half.lower()] for half in "AB"
                          if params.get("REG" + half + "_SD") == d_port.upper()]
            assert len(candidates) == 1, (record["End"], params)
            destination_net = candidates[0]
        assert source_net in phys.net(data), (path, source_net)
        record.update(SourceQ=q_pin, SourceNet=source_net, DestinationNet=destination_net)
        result.append(record)
    assert result, path
    return result


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
    for signal in ("req", "ack"):
        logical = "u_p14_diag_cdc/" + signal
        pairs.append(("diagnostic-" + signal, logical + "_meta", logical + "_sync"))
    pairs += [(f"key-{i}", f"u_quiz_keys/keys_sync_meta[{i}]", f"u_quiz_keys/keys_sync_safe[{i}]") for i in range(4)]
    pairs += [("staging-fault", "u_p14_pipeline/staging_fault_meta", "u_p14_pipeline/staging_fault_sync"),
              ("config-done", "S_p14_cfg_done[0]", "u_p14_provenance/cfg_done"),
              ("config-error", "S_p14_cfg_error[0]", "u_p14_provenance/cfg_error")]
    synchronizers = []
    for name, source, destination in pairs:
        paths = phys.timing_paths(analysis / (name + ".rpt"), cells)
        assert len(paths) == 2 and {p["Check"] for p in paths} == {"setup", "hold"}, name
        for p in paths:
            assert p["SourceNet"] == source and p["DestinationNet"] == destination, (name, p)
            assert p["FromClock"] == p["ToClock"] and p["SlackNs"] >= 0, (name, p)
            if p["Check"] == "setup":
                assert p["BudgetNs"] == 2.0 and p["DelayNs"] < 2.0, (name, p)
        synchronizers.append({"Name": name, "Paths": paths, "TwoNsConstraintApplied": True})
    mailboxes = []
    for name, prefix, object_file, report_file in [
        ("business", "u_p14_pipeline/forward", "payload-objects.txt", "payload-routing.rpt"),
        ("diagnostic", "u_p14_diag_cdc", "diagnostic-objects.txt", "diagnostic-routing.rpt")]:
        expected = {int(i) for i in re.findall(r"held_data\[(\d+)\]", phys.read(analysis / object_file).splitlines()[0])}
        assert len(expected) >= 32
        all_paths = payload_paths(analysis / report_file, cells, phys)
        selected = [p for p in all_paths if p["FromClock"] == "MIPI_RX_BYTE_CLK" and
                    p["ToClock"] == "HDMI_PIXEL_CLK" and p["SourceNet"].startswith(prefix + "/held_data[")]
        assert len(selected) == sum(p["FromClock"] != p["ToClock"] for p in all_paths), name
        mapping = {}
        for check in ("setup", "hold"):
            chosen = [p for p in selected if p["Check"] == check]
            bits = set()
            for p in chosen:
                bit = int(re.search(r"held_data\[(\d+)\]", p["SourceNet"])[1])
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
                assert p["DestinationNet"] in allowed, (name, bit, p)
                assert p["DelayNs"] < 10.0, (name, p)
                mapping.setdefault(str(bit), {})[check] = p
            assert bits == expected, (name, check, expected - bits, bits - expected)
            assert len({p["End"] for p in chosen}) == len(expected)
        mailboxes.append({"Name": name, "Bits": len(expected), "Paths": mapping,
                          "ExcludedPaths": len(all_paths) - len(selected),
                          "ExcludedPathDetails": [p for p in all_paths if p["FromClock"] == p["ToClock"]],
                          "MaximumDataPathNs": max(p["DelayNs"] for p in selected if p["Check"] == "setup"),
                          "ExternalPropagationLimitNs": 10.0,
                          "SynchronousSetupHoldQualification": False})
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
