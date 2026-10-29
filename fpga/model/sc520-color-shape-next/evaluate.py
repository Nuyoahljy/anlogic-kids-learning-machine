"""Fixed, dependency-free RGB color model for the SC520 color-shape experiment.

This tool deliberately evaluates color votes independently of shape identity.
It reads the immutable 320x180 RGB .mem fixtures from the predecessor tree,
samples the same 120x60 centers used by scene-model.py, and writes a new
machine-readable model report and RTL vector catalog. No RTL, TD, or hardware
tool is invoked.
"""
from __future__ import annotations

import hashlib
import json
import math
import platform
import struct
import sys
import argparse
from collections import Counter
from datetime import datetime, timezone, timedelta
from pathlib import Path

HERE = Path(__file__).resolve()
NEW_ROOT = HERE.parents[3]
OLD_ROOT = NEW_ROOT.parent / "sc520-color-integration"
OLD_MANIFEST = OLD_ROOT / "evidence/sc520-shape27/fixtures/manifest.json"
OLD_SCOPE = Path("E:/juan/FPGA/learning/sc520-shape-card30/truth-mapping-contract.md")
OUT = NEW_ROOT / "evidence/sc520-color-shape-next/model-v1"

def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()

def binding(path: Path) -> dict:
    return {"Path": str(path.resolve()), "SHA256": sha(path), "Bytes": path.stat().st_size}

def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)

def parse_mem(path: Path) -> list[tuple[int, int, int]]:
    words = path.read_text(encoding="ascii").split()
    require(len(words) == 180 * 320, f"Expected 57600 RGB words: {path}")
    rows = []
    for word in words:
        value = int(word, 16)
        require(0 <= value <= 0xFFFFFF, f"Bad RGB word {word}: {path}")
        rows.append((value >> 16, (value >> 8) & 0xFF, value & 0xFF))
    return rows

def sample_120x60(pixels: list[tuple[int, int, int]]) -> list[tuple[int, int, int]]:
    # scene-model.py uses frame[ROI_Y+1::2, ROI_X+1::2], ROI=(40,30).
    return [pixels[(30 + 1 + 2 * y) * 320 + (40 + 1 + 2 * x)]
            for y in range(60) for x in range(120)]

def border_reference(grid: list[tuple[int, int, int]]) -> tuple[int, int, int]:
    border = []
    for y in range(60):
        for x in range(120):
            if y in (0, 59) or x in (0, 119):
                border.append(grid[y * 120 + x])
    return Counter(border).most_common(1)[0][0]

def color_id(rgb: tuple[int, int, int]) -> int:
    r, g, b = rgb
    hi, lo = max(rgb), min(rgb)
    if hi < 32 or hi - lo < 24:
        return 0
    if r > 2 * g and r > 2 * b:
        return 1
    if b > 2 * r and b > 2 * g:
        return 3
    if min(r, g) >= 2 * b and max(r, g) <= 2 * min(r, g):
        return 2
    return 0

def oracle_color_id(rgb: tuple[int, int, int]) -> int:
    """Independent arithmetic oracle for canonical vectors."""
    r, g, b = (int(value) for value in rgb)
    hi = max(r, g, b)
    lo = min(r, g, b)
    if hi < 32 or hi - lo < 24:
        return 0
    red = r > 2 * g and r > 2 * b
    blue = b > 2 * r and b > 2 * g
    yellow = min(r, g) >= 2 * b and max(r, g) <= 2 * min(r, g)
    if red and not blue and not yellow:
        return 1
    if yellow and not red and not blue:
        return 2
    if blue and not red and not yellow:
        return 3
    return 0

def votes(grid: list[tuple[int, int, int]]) -> dict:
    background = border_reference(grid)
    mask = [rgb != background for rgb in grid]
    counts = [0, 0, 0, 0]
    classified = 0
    for rgb, active in zip(grid, mask):
        if not active:
            continue
        cid = color_id(rgb)
        if cid:
            counts[cid] += 1
            classified += 1
    total = sum(mask)
    winner = max((1, 2, 3), key=lambda cid: (counts[cid], -cid)) if classified else 0
    winner_count = counts[winner] if winner else 0
    unique = winner and all(winner == cid or counts[winner] > counts[cid] for cid in (1, 2, 3))
    qualified = bool(total and unique and 3 * winner_count >= 2 * total and
                    all(winner_count >= 2 * counts[cid] for cid in (1, 2, 3) if cid != winner))
    return {
        "BackgroundRGB": list(background),
        "GlyphPixels": total,
        "ClassifiedPixels": classified,
        "Counts": counts[1:],
        "Winner": winner,
        "WinnerCount": winner_count,
        "UniqueWinner": bool(unique),
        "Qualified": qualified,
        "Reason": ("qualified" if qualified else
                   "no_active_glyph" if not total else
                   "no_classified_color" if not classified else
                   "tie_or_margin"),
    }

def reference_color(name: str, item: int) -> tuple[int | None, str]:
    if name.startswith(("empty_", "gray", "sparse_red", "half_color", "gray_external", "clipped")):
        return None, "source fixture is unknown/negative or grayscale"
    if name == "square_external":
        return 1, "generator explicitly paints the full square red"
    if name.startswith("card_"):
        return None, "card fixture is outside color-shape classifier scope"
    if name.startswith("block_"):
        parts = name.split("_")
        base = int(parts[1])
        original = (base - 1) // 3 + 1
        if "gray" in name:
            return original, "source block color retained; gray replacement is a mixed-color diagnostic"
        if "wrong" in name:
            return original, "source block color retained; wrong-color replacement is a mixed-color diagnostic"
        return original, "source block catalog color"
    return None, "unclassified fixture name"

def canonical_vectors() -> list[dict]:
    rows = []
    samples = [
        ("red", (255, 0, 0), 1), ("yellow", (255, 255, 0), 2),
        ("green", (0, 255, 0), 0), ("blue", (0, 0, 255), 3),
        ("cyan", (0, 255, 255), 0), ("magenta", (255, 0, 255), 0),
        ("gray", (96, 96, 96), 0), ("white", (255, 255, 255), 0),
        ("red_equal_boundary", (200, 100, 100), 0),
        ("red_strict", (201, 80, 80), 1),
        ("blue_strict", (80, 80, 201), 3),
        ("yellow_2x_boundary", (200, 200, 100), 2),
        ("yellow_equal_boundary", (200, 100, 50), 2),
        ("red_equal_goes_yellow", (100, 50, 0), 2),
        ("red_strict_pass", (101, 50, 0), 1),
        ("yellow_unbalanced", (255, 200, 120), 0),
    ]
    for name, rgb, expected in samples:
        cid = color_id(rgb)
        oracle = oracle_color_id(rgb)
        rows.append({"Name": name, "RGB": list(rgb), "ExpectedColor": expected,
                     "PredictedColor": cid, "OracleColor": oracle,
                     "RuleMatchesOracle": cid == oracle, "Pass": cid == expected and cid == oracle})
    return rows

def vote_vectors() -> list[dict]:
    def row(name: str, pixels: list[int], expected: int) -> dict:
        counts = [0, 0, 0]
        for cid in pixels:
            if cid:
                counts[cid - 1] += 1
        total = len(pixels)
        winner = max(range(3), key=lambda i: (counts[i], -i)) + 1
        unique = counts[winner - 1] > max(counts[:winner - 1] + counts[winner:])
        qualified = bool(unique and 3 * counts[winner - 1] >= 2 * total and
                         all(counts[winner - 1] >= 2 * counts[i] for i in range(3) if i != winner - 1))
        predicted = winner if qualified else 0
        return {"Name": name, "ColorIDs": pixels, "Counts": counts,
                "ExpectedColor": expected, "PredictedColor": predicted,
                "Qualified": qualified, "Pass": predicted == expected}
    return [
        row("two_thirds_red", [1, 1, 1, 1, 1, 1, 0, 0, 0], 1),
        row("just_under_two_thirds_red", [1, 1, 1, 1, 1, 0, 0, 0, 0], 0),
        row("two_to_one_yellow_blue", [2, 2, 2, 2, 1, 1], 2),
        row("two_votes_two_unknown_reject", [2, 2, 0, 0], 0),
        row("three_votes_one_each_reject", [3, 1, 1, 0, 0], 0),
        row("two_to_one_red_unknown_accept", [1, 1, 0], 1),
        row("four_to_one_red_unknown_accept", [1, 1, 1, 1, 2, 3], 1),
        row("fifty_fifty_red_blue", [1, 1, 1, 3, 3, 3], 0),
        row("single_blue_speck", [0, 0, 0, 0, 3], 0),
        row("two_to_one_red_yellow", [1, 1, 1, 1, 2, 2], 1),
        row("all_unknown_reject", [0, 0, 0, 0], 0),
        row("gray_like_one_third_reject", [1, 0, 0], 0),
    ]

def old_fixture_report() -> tuple[list[dict], list[dict]]:
    manifest = json.loads(OLD_MANIFEST.read_text(encoding="utf-8-sig"))
    rows = []
    input_bindings = [binding(OLD_MANIFEST)]
    for case in manifest["Cases"]:
        path = Path(case["Path"])
        require(path.exists(), f"Missing immutable fixture: {path}")
        before = binding(path)
        input_bindings.append(before)
        grid = sample_120x60(parse_mem(path))
        result = votes(grid)
        expected, expected_reason = reference_color(case["Name"], int(case["Item"]))
        predicted = result["Winner"] if result["Qualified"] else 0
        rows.append({
            "Name": case["Name"], "Item": case["Item"], "SourceTruth": case["Item"],
            "ExpectedColor": expected, "ExpectedReason": expected_reason,
            "PredictedColor": predicted, "Pass": expected is None or predicted == expected,
            "Reason": result["Reason"], "Counts": result["Counts"],
            "GlyphPixels": result["GlyphPixels"], "ClassifiedPixels": result["ClassifiedPixels"],
            "Qualified": result["Qualified"], "Source": before,
        })
        after = binding(path)
        require(before == after, f"Input changed during evaluation: {path}")
    return rows, input_bindings

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=None,
                        help="new output directory; an existing directory must be empty")
    parser.add_argument("--run-id", default=None,
                        help="optional ASCII suffix; writes beside model-v1 as model-v1-<run-id>")
    args = parser.parse_args()
    require(not (args.output and args.run_id), "Use either --output or --run-id, not both")
    out = (args.output if args.output else
           (OUT if not args.run_id else OUT.with_name(OUT.name + "-" + args.run_id))).resolve()
    if out.exists():
        require(out.is_dir() and not any(out.iterdir()),
                f"Refusing to overwrite existing output: {out}")
    else:
        out.mkdir(parents=True)
    canonical = canonical_vectors()
    boundary = vote_vectors()
    old_rows, inputs = old_fixture_report()
    require(all(row["Pass"] for row in canonical), "Canonical classifier vector failed")
    require(all(row["Pass"] for row in boundary), "Vote vector failed")
    tool = binding(HERE)
    now = datetime.now(timezone(timedelta(hours=8))).isoformat()
    report = {
        "Stage": "model_v1_fixed_rgb_color_votes",
        "At": now,
        "Owner": "Codex /root/media_audit",
        "Rule": {
            "HighMinimum": 32, "ChromaMinimum": 24,
            "Red": "R > 2G and R > 2B",
            "Blue": "B > 2R and B > 2G",
            "Yellow": "min(R,G) >= 2B and max(R,G) <= 2*min(R,G)",
            "Vote": "unique winner; 3*winner >= 2*glyph; winner >= 2*each other color",
            "ColorID": "0 unknown, 1 red, 2 yellow, 3 blue",
        },
        "Tool": tool,
        "Command": [sys.executable, *sys.argv],
        "Python": {"Executable": sys.executable, "Version": sys.version, "Platform": platform.platform()},
        "Inputs": inputs,
        "CanonicalVectors": canonical,
        "VoteVectors": boundary,
        "OldFixtureManifest": binding(OLD_MANIFEST),
        "OldFixtureRows": old_rows,
        "OldFixtureSummary": {
            "Cases": len(old_rows),
            "Qualified": sum(int(row["Qualified"]) for row in old_rows),
            "UnknownExpected": sum(int(row["ExpectedColor"] is None) for row in old_rows),
            "KnownReferencePass": sum(int(row["ExpectedColor"] is not None and row["Pass"]) for row in old_rows),
            "KnownReferenceFail": sum(int(row["ExpectedColor"] is not None and not row["Pass"]) for row in old_rows),
        },
        "ShapeBoundary": "No shape identity is inferred. Any later item=(color,shape) result is conditional on a separately verified same-frame shape result.",
        "HardwareValidated": False,
    }
    vectors = {
        "Schema": "sc520-color-shape-next.color-vote-v1",
        "ColorRule": report["Rule"],
        "CanonicalVectors": canonical,
        "VoteVectors": boundary,
        "OldFixtureRows": [
            {"Name": row["Name"], "ExpectedColor": row["ExpectedColor"],
             "PredictedColor": row["PredictedColor"], "Counts": row["Counts"],
             "GlyphPixels": row["GlyphPixels"], "Qualified": row["Qualified"]}
            for row in old_rows
        ],
    }
    (out / "model.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (out / "vectors.json").write_text(json.dumps(vectors, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"Model": binding(out / "model.json"), "Vectors": binding(out / "vectors.json"),
                      "OldCases": len(old_rows), "Canonical": len(canonical), "VoteVectors": len(boundary)},
                     ensure_ascii=False))

if __name__ == "__main__":
    main()
