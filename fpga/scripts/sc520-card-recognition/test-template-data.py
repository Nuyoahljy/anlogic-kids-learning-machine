#!/usr/bin/env python3
"""Independently validate serialized RGB/model fixtures without importing generator."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone, timedelta
import hashlib
import json
from pathlib import Path
import re
import sys
import traceback

from PIL import Image


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def foreground(word: int) -> bool:
    r, g, b = (word >> 16) & 255, (word >> 8) & 255, word & 255
    dark = r < 180 or g < 180 or b < 180
    chromatic = any(a - z >= 40 for a, z in ((r, g), (g, r), (r, b), (b, r), (g, b), (b, g)))
    return dark or chromatic


def bitmask(bits: list[int]) -> int:
    return int("".join(str(x) for x in bits), 2)


def read_words(path: Path, digits: int, count: int) -> list[int]:
    raw = path.read_bytes()
    assert b"\r" not in raw, f"expected LF: {path}"
    lines = raw.decode("ascii").splitlines()
    assert len(lines) == count, (path, len(lines), count)
    assert all(re.fullmatch(rf"[0-9a-f]{{{digits}}}", row) for row in lines), path
    return [int(row, 16) for row in lines]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    out = args.output.resolve()
    if out.exists():
        raise FileExistsError(f"refusing to overwrite: {out}")
    out.mkdir(parents=True)
    checks = []
    root = args.input.resolve()

    def done(name: str, detail: object = None) -> None:
        checks.append({"name": name, "status": "pass", "detail": detail})

    try:
        manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
        declared = set()
        for entry in manifest["files"]:
            path = root / entry["path"]
            assert path.is_relative_to(root)
            assert entry["path"] not in declared
            declared.add(entry["path"])
            assert path.stat().st_size == entry["bytes"], path
            assert digest(path) == entry["sha256"], path
        actual = {p.relative_to(root).as_posix() for p in root.rglob("*") if p.is_file() and p.name != "manifest.json"}
        assert actual == declared, (actual - declared, declared - actual)
        done("all_files_manifest_sha256_and_size", len(declared))

        info = json.loads((root / "templates.json").read_text(encoding="utf-8"))
        words = read_words(root / "templates.mem", 2, 1024)
        assert all(0 <= x <= 31 for x in words)
        templates = []
        for index, entry in enumerate(info["templates"]):
            assert entry["item_id"] == 10 + index
            assert digest(Path(entry["source"])) == entry["source_sha256"]
            image = Image.open(root / entry["rendered_png"]).convert("RGB")
            assert image.size == (256, 256)
            extracted = []
            for y in range(4, 256, 8):
                for x in range(4, 256, 8):
                    r, g, b = image.getpixel((x, y))
                    extracted.append(int(foreground((r << 16) | (g << 8) | b)))
            serialized = [(word >> index) & 1 for word in words]
            assert extracted == serialized
            assert entry["mask_rows"] == ["".join(str(x) for x in serialized[r * 32:(r + 1) * 32]) for r in range(32)]
            assert sum(serialized) == entry["foreground_count"]
            templates.append(bitmask(serialized))
        done("source_hashes_rgb_render_sampling_and_5bit_packing", len(templates))
        pairwise = [[(a ^ b).bit_count() for b in templates] for a in templates]
        assert pairwise == info["pairwise_hamming"]
        done("independent_integer_xor_pairwise_hamming", pairwise)

        vectors = json.loads((root / "vectors.json").read_text(encoding="utf-8"))
        limit = vectors["thresholds"]["max_distance"]
        assert limit in (40, 120), "checker supports recorded 120 baseline and conservative 40 candidate"
        assert vectors["thresholds"] == {"dark_min_exclusive": 180, "chroma_min_inclusive": 40,
                                         "max_distance": limit, "min_margin": 24,
                                         "min_foreground": 16, "max_foreground": 850}
        assert vectors["count"] == 69 == len(vectors["vectors"])
        assert vectors["frame"] == {"width": 320, "height": 180, "roi_x": 96, "roi_y": 26, "roi_size": 128, "sample_step": 4, "sample_offset": 2}
        metadata = read_words(root / "vectors.meta.mem", 8, 69 * 8)
        text_lines = (root / "vectors.list").read_text(encoding="ascii").splitlines()
        assert len(text_lines) == 69
        categories = {}
        outcomes = {"canonical": {}, "synthetic_variations": {}, "negatives": {}}
        center_corruptions_detected = 0
        line_detected = False
        for index, entry in enumerate(vectors["vectors"]):
            pixels = read_words(root / entry["rgb_mem"], 6, 128 * 128)
            serialized_bits = read_words(root / entry["bits_mem"], 1, 1024)
            assert all(x in (0, 1) for x in serialized_bits)
            # Pixel-address arithmetic is independent of generator's image API sampling.
            sampled = [int(foreground(pixels[(row * 4 + 2) * 128 + col * 4 + 2]))
                       for row in range(32) for col in range(32)]
            assert sampled == serialized_bits, entry["id"]
            q = bitmask(sampled)
            all_distances = [(q ^ t).bit_count() for t in templates]
            ranked = sorted((distance, item + 10) for item, distance in enumerate(all_distances))
            best, candidate = ranked[0]
            second = ranked[1][0]
            count = q.bit_count()
            roi_count = sum(foreground(word) for word in pixels)
            accepted = 16 <= count <= 850 and best <= limit and second - best >= 24
            accepted_id = candidate if accepted else 0
            expect = entry["expected"]
            independently_computed = {"distances_item_10_to_14": all_distances, "candidate_item_id": candidate,
                                     "accepted": accepted, "accepted_item_id": accepted_id,
                                     "best_distance": best, "second_distance": second, "margin": second - best,
                                     "foreground_count": count, "roi_foreground_pixels": roi_count}
            assert expect == independently_computed, entry["id"]
            assert metadata[index * 8:index * 8 + 8] == [index, entry["ground_truth_item_id"], candidate, accepted_id, best, second, count, roi_count]
            stem = Path(entry["rgb_mem"]).name.removesuffix(".rgb.mem")
            assert text_lines[index] == f"{stem} {accepted_id} {best} {second} {count} {roi_count} {entry['ground_truth_item_id']}"
            image = Image.open(root / entry["preview_png"]).convert("RGB")
            assert image.size == (128, 128)
            assert all(pixels[y * 128 + x] == sum(value << shift for value, shift in zip(image.getpixel((x, y)), (16, 8, 0))) for y in range(128) for x in range(128))
            truth = entry["ground_truth_item_id"]
            outcome = "correct_accept" if truth and accepted_id == truth else ("reject" if not accepted else ("false_accept" if truth == 0 else "confusion"))
            assert outcome == entry["model_outcome"]
            group = "canonical" if entry["category"] == "canonical" else ("negatives" if truth == 0 else "synthetic_variations")
            outcomes[group][outcome] = outcomes[group].get(outcome, 0) + 1
            category = categories.setdefault(entry["category"], {})
            category[outcome] = category.get(outcome, 0) + 1
            # Negative self-test alters an actual center RGB word while retaining stored bit.
            corrupted = pixels.copy()
            address = 2 * 128 + 2
            corrupted[address] = 0xffffff if sampled[0] else 0x000000
            try:
                assert int(foreground(corrupted[address])) == serialized_bits[0]
            except AssertionError:
                center_corruptions_detected += 1
            if entry["id"] == "between_sample_lines":
                assert count == 0 and roi_count == 4096 and accepted_id == 0
                line_detected = True
        done("all_rgb_bits_distances_gates_metadata_and_png", 69)
        assert center_corruptions_detected == 69
        done("deliberate_center_rgb_corruption_detected", center_corruptions_detected)
        assert line_detected
        done("unsampled_lines_not_mistaken_for_empty_roi", {"sample_fg": 0, "roi_fg": 4096})
        summary = json.loads((root / "model-report.json").read_text(encoding="utf-8"))["summary"]
        assert summary == {"total": 69, **outcomes, "by_category": categories}
        assert outcomes["canonical"] == {"correct_accept": 5}
        assert outcomes["negatives"] == ({"reject": 11, "false_accept": 3} if limit == 120 else {"reject": 14})
        done("semantic_model_outcomes_reported_without_hiding_false_accepts", summary)

        # Test strict and inclusive threshold edges without relying on rendered images.
        edge_cases = {0xb4b4b4: False, 0xb3b4b4: True, 0xb4dbb4: False, 0xb4dcb4: True,
                      0xffffff: False, 0x000000: True, 0xb4b4dc: True, 0xdcb4b4: True}
        for word, expected in edge_cases.items():
            assert foreground(word) == expected, hex(word)
        done("foreground_threshold_boundaries", len(edge_cases))
        report = {"status": "pass", "created_at": datetime.now(timezone(timedelta(hours=8))).isoformat(),
                  "command": [sys.executable, *sys.argv], "script_sha256": digest(Path(__file__)),
                  "dataset": root.as_posix(), "dataset_manifest_sha256": digest(root / "manifest.json"),
                  "checks": checks, "structural_checks_passed": len(checks), "vectors_checked": 69,
                  "model_false_accepts": outcomes["negatives"].get("false_accept", 0), "hardware_validation": "not performed",
                  "note": "结构与软件参考检查通过不代表模型所有负样本都拒识，也不代表实物准确率。"}
        (out / "validation.json").write_bytes((json.dumps(report, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
        print(json.dumps(report, ensure_ascii=False))
    except Exception:
        report = {"status": "failed", "checks_completed": checks, "traceback": traceback.format_exc(), "command": [sys.executable, *sys.argv]}
        (out / "validation.json").write_bytes((json.dumps(report, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
        raise


if __name__ == "__main__":
    main()
