"""Immutable fixed-label T029 fixtures; damaged shapes are synthetic, not photos."""
from pathlib import Path
import hashlib
import importlib.util
import json
import numpy as np

R = Path(__file__).resolve().parents[3]
S = Path(__file__).parent
spec = importlib.util.spec_from_file_location("contour29_final", S / "model-contour29-final.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
spec = importlib.util.spec_from_file_location("contour29_fixture_utils", S / "evaluate-contour29.py")
e = importlib.util.module_from_spec(spec)
spec.loader.exec_module(e)
OUT = R / "evidence/sc520-contour29/fixtures-v1"


def main():
    OUT.mkdir(parents=True, exist_ok=False)
    bank = m.base.read_bank(e.A / "templates.mem")
    cases = []

    def add(name, full, truth, source=None, smoke=False):
        grid = m.base.sample_frame(full)
        result = m.recognize(grid, bank)
        prefix = f"c{len(cases):03d}"
        path = OUT / (prefix + ".rgb.mem")
        path.write_text("".join("%02X%02X%02X\n" % tuple(p) for p in full.reshape(-1, 3)), encoding="ascii")
        clipped = result["clipped"]
        full_mask = result["mask"]
        body_mask = result["contour"]["normalized"] if not clipped else np.zeros((32, 32), bool)
        body_axis = m.v4.v3.v2.normalize_axes(result["contour"]["mask"]) if not clipped else np.zeros((32, 32), bool)
        full_axis = m.v4.v3.v2.normalize_axes(result["glyph"]) if not clipped else np.zeros((32, 32), bool)
        words = full_mask.astype(np.uint8) | body_mask.astype(np.uint8) << 1 | body_axis.astype(np.uint8) << 2 | full_axis.astype(np.uint8) << 3
        (OUT / (prefix + ".norm.mem")).write_text("".join(f"{int(v):X}\n" for v in words.flat), encoding="ascii")
        bounds = m.base.base.bbox(result["contour"]["mask"])
        near = bool(bounds and (bounds[2] - bounds[0] + 1) * 5 >= (bounds[3] - bounds[1] + 1) * 4 and
                    (bounds[3] - bounds[1] + 1) * 5 >= (bounds[2] - bounds[0] + 1) * 4)
        packed = (int(result["contour"]["valid"]) | int(near) << 1 |
                  int(result["boundary_repair"]) << 2 | int(result["exterior_qualified"]) << 3 |
                  int(result["contour"]["dominant"] if result["contour"]["dominant_count"] >= 12 else 0) << 4)
        # A no-winning-color state is zero even if argmax chose a tied bucket.
        colors = m.v4.v3.v2.v1.labels(grid)
        counts = np.bincount(colors[result["contour"]["seed"]], minlength=4)[1:]
        winner = next((i + 1 for i, n in enumerate(counts) if n >= 12 and
                       all(n >= 2 * other for j, other in enumerate(counts) if i != j)), 0)
        packed = (packed & 15) | winner << 4
        cases.append(dict(Prefix=prefix, Name=name, TruthItem=truth, ExpectedContractItem=result["item"],
                          KnownMiss=truth != 0 and result["item"] == 0, Present=bool(result["present"]),
                          ContourMetadata=packed, Synthetic=source is None, Source=e.artifact(source) if source else None,
                          Smoke=smoke, RGB=e.artifact(path), Norm=e.artifact(OUT / (prefix + ".norm.mem"))))

    old = R / "evidence/sc520-shape27/fixtures"
    for case in json.loads((old / "manifest.json").read_text())["Cases"]:
        add(case["Name"], e.read_rgb(Path(case["Path"])), case["Item"], Path(case["Path"]),
            smoke=case["Name"] in ("block_1_plain", "block_2_plain", "block_3_plain", "card_10", "card_11",
                                   "gray", "sparse_red", "empty_white", "clipped"))
    yy, xx = np.mgrid[:60, :120]
    for ratio in (100, 90, 80, 70, 60):
        for angle in (0, 15, 30, 45, 60, 75, 90):
            radians = np.deg2rad(angle)
            u = (xx - 60) * np.cos(radians) + (yy - 30) * np.sin(radians)
            v = -(xx - 60) * np.sin(radians) + (yy - 30) * np.cos(radians)
            mask = (u / 16) ** 2 + (v / (16 * ratio / 100)) ** 2 <= 1
            for damage in ("plain", "holes", "shadow", "one_gap"):
                grid = np.full((60, 120, 3), 240, np.uint8)
                grid[mask] = (180, 60, 60)
                if damage == "holes":
                    grid[mask & ((xx + 3 * yy) % 5 == 0)] = (96, 96, 96)
                if damage == "shadow":
                    grid[(xx >= 66) & (xx <= 82) & (yy >= 23) & (yy <= 41) & ~mask] = (140, 140, 140)
                if damage == "one_gap":
                    grid[mask & (xx == 60)] = 240
                full = np.full((180, 320, 3), 240, np.uint8)
                full[30:150, 40:280] = np.repeat(np.repeat(grid, 2, axis=0), 2, axis=1)
                add(f"ellipse_{ratio}_{angle}_{damage}", full, 1 if ratio >= 90 else 0,
                    smoke=angle == 0 and ratio in (100, 80))
    for subset in ("all", "smoke"):
        selected = [case for case in cases if subset == "all" or case["Smoke"]]
        (OUT / (subset + "-cases.txt")).write_text(
            "".join(f"{c['Prefix']} {c['ContourMetadata']} {int(c['Present'])} {c['TruthItem']} {c['ExpectedContractItem']}\n"
                    for c in selected), encoding="ascii")
    (OUT / "manifest.json").write_text(json.dumps(dict(Owner="Codex /root/shape27_delivery",
        Model=e.artifact(S / "model-contour29-final.py"), Generator=e.artifact(__file__),
        Cases=cases, KnownMisses=[c["Name"] for c in cases if c["KnownMiss"]],
        Limits="ExpectedContractItem is the disclosed conservative contract. TruthItem is preserved separately; known misses do not become successful recognition."), indent=2) + "\n", encoding="utf-8")
    print(json.dumps(dict(Cases=len(cases), Smoke=sum(c["Smoke"] for c in cases),
                         KnownMisses=sum(c["KnownMiss"] for c in cases))))


if __name__ == "__main__":
    main()
