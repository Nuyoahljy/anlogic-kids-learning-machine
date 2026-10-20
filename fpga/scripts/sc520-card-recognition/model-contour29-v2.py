"""T029 v2 model with explicit sampling aliases and rejection-only ellipses."""
from pathlib import Path
import importlib.util
import numpy as np

S = Path(__file__).parent
spec = importlib.util.spec_from_file_location("contour29_v1", S / "model-contour29.py")
v1 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v1)
base = v1.base


def normalize_axes(mask):
    result = np.zeros((32, 32), bool)
    bounds = base.base.bbox(mask)
    if bounds:
        left, top, right, bottom = bounds
        width, height = right - left + 1, bottom - top + 1
        for y in range(20):
            for x in range(20):
                result[6 + y, 6 + x] = mask[top + (2 * y + 1) * height // 40,
                                          left + (2 * x + 1) * width // 40]
    return result


def ellipse_templates():
    yy, xx = np.mgrid[:20, :20]
    x = (2 * xx + 1 - 20) / 20.
    y = (2 * yy + 1 - 20) / 20.
    rows = []
    for ratio in (.6, .8):
        for angle in range(0, 180, 30):
            radians = np.deg2rad(angle)
            u = x * np.cos(radians) + y * np.sin(radians)
            v = -x * np.sin(radians) + y * np.cos(radians)
            rows.append(u * u + (v / ratio) ** 2 <= 1)
    return np.asarray(rows)


ELLIPSES = ellipse_templates()
yy, xx = np.mgrid[:20, :20]
RADIUS_SQUARED = (2 * xx + 1 - 20) ** 2 + (2 * yy + 1 - 20) ** 2
CIRCLE_ALIASES = np.asarray([RADIUS_SQUARED <= radius * radius for radius in (19, 20)])


def ellipse_score(mask):
    return int(np.count_nonzero(ELLIPSES != np.asarray(mask)[6:26, 6:26], axis=(1, 2)).min())


def circle_axis_score(mask):
    return int(np.count_nonzero(CIRCLE_ALIASES != normalize_axes(mask)[6:26, 6:26], axis=(1, 2)).min())


def recognize(rgb, bank, margin=16, edge_dn=8, recovery_margin=16):
    result = v1.scene(rgb)
    full_shape = base.shape_classify(result["mask"])
    card = base.classify(result["mask"], bank, result["present"])
    body = v1.contour(result, edge_dn)
    body_shape = base.shape_classify(body["normalized"])
    bounds = base.base.bbox(body["mask"])
    width = bounds[2] - bounds[0] + 1 if bounds else 0
    height = bounds[3] - bounds[1] + 1 if bounds else 0
    near_square = bool(width and height and width * 5 >= height * 4 and height * 5 >= width * 4)
    body_circle = circle_axis_score(body["mask"])
    full_circle = circle_axis_score(result["glyph"])
    full_ellipse = ellipse_score(result["mask"])
    body_ellipse = ellipse_score(body["normalized"])
    original_bits = full_shape["shape_bits"]
    color_counts = np.bincount(v1.labels(rgb)[result["glyph"]], minlength=4)[1:]
    winner = int(color_counts.argmax()) + 1
    color_count = int(color_counts[winner - 1])
    full_color_good = bool(color_count >= 12 and color_count * 3 >= int(result["glyph"].sum()) * 2 and
                           all(color_count >= 2 * int(n) for i, n in enumerate(color_counts) if i != winner - 1))
    candidate_bits = original_bits
    recovered = False
    conflict = False
    if body["valid"]:
        body_bits = body_shape["shape_bits"]
        if near_square and body_circle <= 20:
            body_bits = 1
        if body_bits in (1, 2, 4):
            if original_bits and original_bits != body_bits:
                conflict = True
            elif original_bits == 0:
                # A closer valid card remains an ambiguity; body geometry is
                # never sufficient by itself to override missing card details.
                evidence_distance = body_circle if body_bits == 1 else min(body_shape["distances"])
                if not card["valid"] or evidence_distance + recovery_margin < card["best"]:
                    candidate_bits = body_bits
                    winner = body["dominant"]
                    full_color_good = True
                    recovered = True
    block_valid = bool(result["present"] and not result["clipped"] and not result["paper_route"] and
                       full_color_good and candidate_bits in (1, 2, 4) and not conflict)
    block_item = (winner - 1) * 3 + candidate_bits.bit_length() if block_valid else 0
    # Axis-normal ellipse evidence is rejection-only outside the near-square
    # recovery boundary; no negative-family bit becomes a public shape bit.
    negative_only = bool(full_circle <= 20 or full_ellipse <= 20 or
                         body["valid"] and (body_circle <= 20 or body_ellipse <= 20))
    geometry = min(full_shape["distances"] + (body_shape["distances"] if body["valid"] else []))
    card_valid = bool(card["valid"] and not original_bits and not block_item and not conflict and
                      not negative_only and card["best"] + margin < geometry)
    result.update(contour=body, full_shape=full_shape, contour_shape=body_shape,
                  card=card, geometry=geometry, full_color_good=full_color_good,
                  block_item=block_item, card_item=card["item"] if card_valid else 0,
                  item=block_item or (card["item"] if card_valid else 0),
                  negative_only=negative_only, full_circle=full_circle, body_circle=body_circle,
                  full_ellipse=full_ellipse, body_ellipse=body_ellipse,
                  near_square=near_square, recovered=recovered, conflict=conflict)
    return result
