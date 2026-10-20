"""Create independent T029 regression copies once; never overwrite any test."""
from pathlib import Path
import json
import hashlib
import re
import numpy as np
from PIL import Image

R = Path(__file__).resolve().parents[3]
S = Path(__file__).parent


def new(path, text):
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        stream.write(text)


def artifact(path):
    return dict(Path=str(path), SHA256=hashlib.sha256(path.read_bytes()).hexdigest().upper())


def main():
    for name in ("scenes", "reset", "pipeline", "lifecycle", "render"):
        source = R / "fpga/sim/sc520-shape27" / f"tb_shape27_{name}.sv"
        text = source.read_text(encoding="utf-8")
        text = text.replace("tb_shape27_", "tb_contour29_").replace("LEGACY_D0261", "LEGACY_D0270")
        text = text.replace("pixel26_bg_pipeline #", "pixel27_pipeline #").replace("pixel27_pipeline #", "pixel29_pipeline #")
        if "`ifdef LEGACY_D0270" in text:
            text = text.replace("`ifdef LEGACY_D0270\n  pixel29_pipeline #", "`ifdef LEGACY_D0270\n  pixel27_pipeline #")
        text = text.replace("D0270", "D0290").replace("16'h0270", "16'h0290")
        # The macro spelling remains the original baseline identity.
        text = text.replace("LEGACY_D0290", "LEGACY_D0270")
        new(R / "fpga/sim/sc520-contour29" / f"tb_contour29_{name}.sv", text)
    source = S / "simulate-contour29.py"
    text = source.read_text(encoding="utf-8")
    text = text.replace('    ap.add_argument("--all", action="store_true")',
                        '    ap.add_argument("--all", action="store_true")\n    ap.add_argument("--scene-dir", type=Path)')
    text = text.replace('    fixture = R / "evidence/sc520-contour29/fixtures-v1"',
                        '    fixture = args.scene_dir or R / "evidence/sc520-shape27/fixtures"')
    text = text.replace('    refs = [R / "assets/templates/sc520-contour29/contour29-shapes.mem"]',
                        '''    if args.test == "reset":
        rtl += [R / "fpga/custom_project/sc520-contour29/overlay/pixel14_color_pipeline.v",
                R.parent / "sc520-fixed-roi/fpga/custom_project/sc520-board-keys/user_source/hdl_source/signal_delay.v",
                R / "evidence/sc520-card-recognition/imaging-audit/ip_behavioral_models.sv"]
    refs = [R / "assets/templates/sc520-contour29/contour29-shapes.mem", S / "simulate-contour29.py"]
    refs += list((R / "evidence/sc520-color-integration/fixtures").glob("*.mem"))
    refs += list((R / "assets/templates/sc520-card-recognition/rotation-v1/vectors").glob("r000_empty_dark.rgb.mem"))
    refs += list((R / "assets/templates/sc520-card-recognition/rotation-v1/vectors").glob("r003_card_10_angle_0.rgb.mem"))
    refs += [R / "assets/templates/sc520-card-recognition/items14/items14_text_reference.svh"]
    if args.test == "render":
        refs += list((R / "evidence/sc520-contour29/render-fixtures").glob("*.mem"))''')
    text = text.replace('+ list(fixture.glob("*-cases.txt"))', '+ list(fixture.glob("*.txt"))')
    text = text.replace('{"+define+LEGACY_D0270" if args.legacy else ""} {quote(snap / tb.name)}',
                        '{"+define+LEGACY_D0270" if args.legacy else ""} +incdir+{str(snap).replace(chr(92), "/")} {quote(snap / tb.name)}')
    text = text.replace('+CASE_FILE={"all" if args.all else "smoke"}-cases.txt', '+CASE_FILE=cases.txt')
    # Keep a small wrapper that binds this exact parent source in each run.
    prefix = '"""T029 complete-system runner derived from the snapshot unit runner."""\n'
    prefix += "from pathlib import Path\n"
    prefix += "SOURCE=Path(__file__).with_name('simulate-contour29.py')\n"
    prefix += "original=SOURCE.read_text(encoding='utf-8')\n"
    prefix += "adapted=" + repr(text) + "\n"
    prefix += "scope={'__name__':'__main__','__file__':str(Path(__file__).resolve())}\n"
    prefix += "exec(compile(adapted,str(SOURCE),'exec'),scope)\n"
    new(S / "simulate-contour29-system.py", prefix)

    out = R / "evidence/sc520-contour29/render-fixtures"
    out.mkdir(parents=True, exist_ok=False)
    old = R / "evidence/sc520-shape27/render-fixtures"
    glyph7 = np.array([[c == "1" for c in row] for row in
                       ("11111", "00001", "00010", "00100", "01000", "01000", "01000")])
    glyph9 = np.array([[c == "1" for c in row] for row in
                       ("01110", "10001", "10001", "01111", "00001", "00001", "01110")])
    records = []
    for i in range(4):
        path = old / f"golden-{i}.mem"
        values = np.loadtxt(path, dtype=np.uint32, converters=lambda x: int(x, 16)).reshape(720, 1280)
        slot = values[520:527, 56:61].copy()
        colors = np.unique(slot[glyph7])
        assert len(colors) == 1
        assert np.all(slot[~glyph7] == 0x101820)
        values[520:527, 56:61] = np.where(glyph9, colors[0], 0x101820)
        target = out / f"golden-{i}.mem"
        new(target, "".join(f"{int(v):06X}\n" for v in values.flat))
        rgb = np.stack((values >> 16, values >> 8 & 255, values & 255), -1).astype(np.uint8)
        Image.fromarray(rgb).save(out / f"golden-{i}.png")
        records.append(dict(Source=artifact(path), Output=artifact(target),
                            ChangedRegion="literal D0270 -> D0290: character index3 x56..60 y520..526 only"))
    new(out / "manifest.json", json.dumps(dict(Generator=artifact(Path(__file__).resolve()),
        Reference="Frozen approved four complete frames, independently checked old7/new9 literal bitmaps. No DUT render output used.",
        TinyGlyphReference=artifact(R / "fpga/sim/sc520-card-recognition/tb_pixel14_observation_display.sv"),
        Files=records), indent=2) + "\n")
    print(json.dumps(dict(Tests=5, SystemRunnerCreated=True, GoldenFrames=4)))


if __name__ == "__main__":
    main()
