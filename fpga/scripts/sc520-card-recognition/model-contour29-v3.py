"""T029 v3 keeps full-glyph color coverage and rejects repaired-edge ambiguity."""
from pathlib import Path
import importlib.util
import numpy as np

S = Path(__file__).parent
spec = importlib.util.spec_from_file_location("contour29_v2", S / "model-contour29-v2.py")
v2 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v2)
base = v2.base


def near_square(mask):
    b = base.base.bbox(mask)
    if not b:
        return False
    width, height = b[2] - b[0] + 1, b[3] - b[1] + 1
    return width * 5 >= height * 4 and height * 5 >= width * 4


def recognize(rgb, bank, margin=16, edge_dn=8, recovery_margin=16):
    result = v2.recognize(rgb, bank, margin=margin, edge_dn=edge_dn, recovery_margin=recovery_margin)
    body = result["contour"]
    original_bits = result["full_shape"]["shape_bits"]
    labels = v2.v1.labels(rgb)
    counts = np.bincount(labels[result["glyph"]], minlength=4)[1:]
    winner = int(counts.argmax()) + 1
    count = int(counts[winner - 1])
    full_color_good = bool(count >= 12 and count * 3 >= int(result["glyph"].sum()) * 2 and
                           all(count >= 2 * int(n) for i, n in enumerate(counts) if i != winner - 1))
    b = base.base.bbox(body["mask"])
    changed = body["mask"] & ~body["seed"]
    boundary_repair = bool(b and (changed[b[1], b[0]:b[2] + 1].any() or
                                 changed[b[3], b[0]:b[2] + 1].any() or
                                 changed[b[1]:b[3] + 1, b[0]].any() or
                                 changed[b[1]:b[3] + 1, b[2]].any()))
    aspect_consistent = near_square(body["mask"]) and near_square(body["seed"])
    recover_circle = bool(result["body_circle"] <= 20 and aspect_consistent and not boundary_repair and
                           result["body_circle"] < result["body_ellipse"])
    candidate = original_bits
    recovered = False
    conflict = False
    if body["valid"] and full_color_good and winner == body["dominant"]:
        body_bits = result["contour_shape"]["shape_bits"]
        if recover_circle:
            body_bits = 1
        if body_bits in (1, 2, 4):
            if original_bits and original_bits != body_bits:
                conflict = True
            elif not original_bits:
                evidence = result["body_circle"] if body_bits == 1 else min(result["contour_shape"]["distances"])
                if not result["card"]["valid"] or evidence + recovery_margin < result["card"]["best"]:
                    candidate = body_bits
                    recovered = True
    block_valid = bool(result["present"] and not result["clipped"] and not result["paper_route"] and
                       full_color_good and candidate in (1, 2, 4) and not conflict)
    block_item = (winner - 1) * 3 + candidate.bit_length() if block_valid else 0
    card_valid = bool(result["card"]["valid"] and not original_bits and not block_item and not conflict and
                      not result["negative_only"] and result["card"]["best"] + margin < result["geometry"])
    # This baseline is the strict old model, without contour priority or new
    # negative families. Real old RTL remains a separate independent check.
    legacy_block = ((winner - 1) * 3 + original_bits.bit_length()
                    if full_color_good and original_bits in (1, 2, 4) and result["present"] and
                    not result["clipped"] and not result["paper_route"] else 0)
    legacy_card = result["card"]["item"] if original_bits == 0 else 0
    result.update(full_color_good=full_color_good, block_item=block_item,
                  card_item=result["card"]["item"] if card_valid else 0,
                  item=block_item or (result["card"]["item"] if card_valid else 0),
                  legacy_item=legacy_block or legacy_card, recovered=recovered, conflict=conflict,
                  boundary_repair=boundary_repair, aspect_consistent=aspect_consistent,
                  circle_recovery_evidence=recover_circle)
    return result
