"""Frozen T029 RTL scope: recovery is circle-only; prior model files stay intact."""
from pathlib import Path
import importlib.util

S = Path(__file__).parent
spec = importlib.util.spec_from_file_location("contour29_v4", S / "model-contour29-v4.py")
v4 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v4)
base = v4.base


def recognize(rgb, bank):
    result = v4.recognize(rgb, bank)
    if result["recovered"] and (not result["circle_recovery_evidence"] or
                                (result["block_item"] - 1) % 3 != 0):
        result.update(block_item=0, card_item=0, item=0, recovered=False)
    return result
