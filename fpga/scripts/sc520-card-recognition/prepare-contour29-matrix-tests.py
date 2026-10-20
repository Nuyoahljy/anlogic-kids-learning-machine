"""Scale only the whole-matrix watchdog; keep the per-frame 1.2M bound."""
from pathlib import Path
R = Path(__file__).resolve().parents[3]
source = R / "fpga/sim/sc520-contour29/tb_contour29_scenes.sv"
target = source.with_name("tb_contour29_matrix.sv")
text = source.read_text(encoding="utf-8").replace("tb_contour29_scenes", "tb_contour29_matrix")
assert text.count("#2000000000;") == 1
text = text.replace("#2000000000;", "#(64'd12000000000);")
with target.open("x", encoding="utf-8", newline="\n") as stream:
    stream.write(text)
print(target)
