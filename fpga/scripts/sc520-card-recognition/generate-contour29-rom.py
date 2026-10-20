"""Generate the disclosed 16-bit geometry ROM; never overwrite an existing ROM."""
from pathlib import Path
import hashlib
import importlib.util
import json
import numpy as np

R = Path(__file__).resolve().parents[3]
S = Path(__file__).parent
spec = importlib.util.spec_from_file_location("contour29_rom_model", S / "model-contour29-v2.py")
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
out = R / "assets/templates/sc520-contour29/contour29-shapes.mem"
assert not out.exists()
words = np.zeros((32, 32), dtype=np.uint16)
yy, xx = np.mgrid[:20, :20]
dx, dy = 2 * xx + 1 - 20, 2 * yy + 1 - 20
words[6:26, 6:26] |= (dx * dx + dy * dy <= 400).astype(np.uint16)
words[6:26, 6:26] |= np.uint16(2)
words[6:26, 6:26] |= (2 * np.abs(dx) <= 2 * yy + 1).astype(np.uint16) << 2
words[6:26, 6:26] |= (dx * dx + dy * dy <= 361).astype(np.uint16) << 3
for i, mask in enumerate(m.ELLIPSES):
    words[6:26, 6:26] |= mask.astype(np.uint16) << (4 + i)
with out.open("x", encoding="ascii", newline="\n") as stream:
    stream.write("".join(f"{int(word):04X}\n" for word in words.flat))
print(json.dumps(dict(Path=str(out), Words=1024, Width=16,
                      SHA256=hashlib.sha256(out.read_bytes()).hexdigest().upper())))
