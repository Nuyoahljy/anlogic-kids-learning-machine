"""T029 v4 distinguishes enclosed damage from exterior glyph appendages."""
from pathlib import Path
import importlib.util
import numpy as np

S = Path(__file__).parent
spec = importlib.util.spec_from_file_location("contour29_v3", S / "model-contour29-v3.py")
v3 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v3)
base = v3.base


def recognize(rgb, bank, margin=16, edge_dn=8, recovery_margin=16):
    result = v3.recognize(rgb, bank, margin=margin, edge_dn=edge_dn, recovery_margin=recovery_margin)
    exterior_residual = result["glyph"] & ~result["contour"]["mask"]
    exterior_count = int(exterior_residual.sum())
    # The existing minimum meaningful component area is twelve samples.
    # Do not erase a substantial exterior glyph to create a basic geometry.
    exterior_qualified = exterior_count < 12
    full_negative_conflict = result["full_ellipse"] <= 20
    if result["recovered"] and (not exterior_qualified or full_negative_conflict):
        result["block_item"] = 0
        result["card_item"] = 0
        result["item"] = 0
        result["recovered"] = False
    result.update(exterior_residual=exterior_residual, exterior_count=exterior_count,
                  exterior_qualified=exterior_qualified, full_negative_conflict=full_negative_conflict)
    return result
