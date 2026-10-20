"""Synthetic T029 proposal model; no camera RGB is inferred from photographs."""
from __future__ import annotations

from collections import deque
import importlib.util
from pathlib import Path
import numpy as np

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("contour29_base", HERE / "scene-rotation-model.py")
base = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(base)


def labels(rgb):
    values = np.asarray(rgb, dtype=np.int16)
    winner = values.argmax(axis=-1)
    top = values.max(axis=-1)
    second = np.sort(values, axis=-1)[..., -2]
    total = values.sum(axis=-1)
    good = (total > 0) & ((top - second) * 100 >= total * 3)
    # The fixed SC520 profile maps G-leading pixels to the yellow class.
    return np.where(good, winner + 1, 0).astype(np.uint8)


def flood(barrier):
    barrier = np.asarray(barrier, dtype=bool)
    height, width = barrier.shape
    outside = np.zeros_like(barrier)
    queue = deque()
    for y, x in np.argwhere(~barrier):
        if y in (0, height - 1) or x in (0, width - 1):
            outside[y, x] = True
            queue.append((int(y), int(x)))
    while queue:
        y, x = queue.popleft()
        for sy, sx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= sy < height and 0 <= sx < width and not barrier[sy, sx] and not outside[sy, sx]:
                outside[sy, sx] = True
                queue.append((sy, sx))
    return ~outside


def scene(rgb):
    """Independent array implementation of the frozen chroma-envelope scene."""
    rgb = np.asarray(rgb, dtype=np.uint8)
    height, width = rgb.shape[:2]
    border = np.zeros((height, width), dtype=bool)
    border[[0, -1], :] = True
    border[:, [0, -1]] = True
    center = np.sort(rgb[border] // 16, axis=0)[(int(border.sum()) - 1) // 2].astype(np.int16) * 16 + 8
    signed = rgb.astype(np.int16)
    chroma = signed[..., (0, 2)] - signed[..., 1, None]
    low = chroma[border].min(axis=0) - 4
    high = chroma[border].max(axis=0) + 4
    similar = (np.abs(signed - center).max(axis=-1) <= 48) & ((chroma >= low) & (chroma <= high)).all(axis=-1)
    raw = flood(~similar)
    occupancy = base.despeckle(raw)
    glyph = base.despeckle(raw & base.threshold(rgb))
    bounds = base.base.bbox(occupancy)
    occupied = bool(occupancy.sum() >= 12 and bounds and bounds[2] - bounds[0] >= 2 and bounds[3] - bounds[1] >= 2)
    qualified = int((border & similar).sum()) * 4 >= int(border.sum()) * 3
    clipped = bool(not qualified or occupied and (occupancy[0].any() or occupancy[-1].any() or
                                                  occupancy[:, 0].any() or occupancy[:, -1].any()))
    paper = int((occupancy & ~base.threshold(rgb)).sum())
    paper_route = occupied and int(glyph.sum()) >= 12 and paper * 4 > int(occupancy.sum())
    return dict(scene=occupancy, glyph=glyph, mask=base.normalize(glyph) if not clipped else np.zeros((32, 32), bool),
                present=occupied or not qualified, clipped=clipped, paper_route=bool(paper_route),
                chroma=chroma, low=low, high=high, rgb=rgb)


def contour(result, edge_dn=8):
    rgb = result["rgb"]
    color = labels(rgb)
    distinct = ((result["chroma"] < result["low"]) | (result["chroma"] > result["high"])).any(axis=-1)
    seed = result["glyph"] & (color != 0) & distinct
    seed_color = np.where(seed, color, 0)
    bridged = seed.copy()
    height, width = seed.shape
    repairs = 0
    for y in range(1, height - 1):
        for x in range(1, width - 1):
            if seed[y, x]:
                continue
            for dy, dx in ((0, 1), (1, 0)):
                first = seed_color[y - dy, x - dx]
                if first and first == seed_color[y + dy, x + dx]:
                    center = result["chroma"][y, x]
                    delta = max(int(np.abs(center - result["chroma"][y - dy, x - dx]).max()),
                                int(np.abs(center - result["chroma"][y + dy, x + dx]).max()))
                    if delta >= edge_dn:
                        bridged[y, x] = True
                        repairs += 1
                        break
    filled = flood(bridged)
    edge_contact = bool(filled[0].any() or filled[-1].any() or filled[:, 0].any() or filled[:, -1].any())
    counts = np.bincount(color[seed], minlength=4)[1:]
    dominant = int(counts.argmax()) + 1
    count = int(counts[dominant - 1])
    area = int(filled.sum())
    valid = bool(area >= 12 and count >= 12 and count * 3 >= area * 2 and
                 all(count >= 2 * int(n) for i, n in enumerate(counts) if i != dominant - 1) and
                 not edge_contact and result["present"] and not result["clipped"] and not result["paper_route"])
    return dict(seed=seed, mask=filled, normalized=base.normalize(filled), repairs=repairs,
                area=area, dominant=dominant, dominant_count=count, valid=valid)


def recognize(rgb, bank, margin=24, edge_dn=8):
    result = scene(rgb)
    full_shape = base.shape_classify(result["mask"])
    card = base.classify(result["mask"], bank, result["present"])
    body = contour(result, edge_dn)
    body_shape = base.shape_classify(body["normalized"])
    full_bits = full_shape["shape_bits"]
    body_bits = body_shape["shape_bits"] if body["valid"] else 0
    conflict = bool(full_bits and body_bits and full_bits != body_bits)
    shape_bits = body_bits if body["valid"] else full_bits
    single = shape_bits in (1, 2, 4)
    full_color = labels(rgb)[result["glyph"]]
    counts = np.bincount(full_color, minlength=4)[1:]
    winner = int(counts.argmax()) + 1
    count = int(counts[winner - 1])
    color_good = bool(count >= 12 and count * 3 >= int(result["glyph"].sum()) * 2 and
                      all(count >= 2 * int(n) for i, n in enumerate(counts) if i != winner - 1))
    block_valid = bool(result["present"] and not result["clipped"] and not result["paper_route"] and
                       color_good and single and not conflict)
    block_item = (winner - 1) * 3 + shape_bits.bit_length() if block_valid else 0
    geometry = min(full_shape["distances"] + (body_shape["distances"] if body["valid"] else []))
    card_valid = bool(card["valid"] and full_bits == 0 and not body_bits and not conflict and
                      card["best"] + margin < geometry)
    item = block_item or card["item"] if card_valid else block_item
    result.update(contour=body, full_shape=full_shape, contour_shape=body_shape, card=card,
                  geometry=geometry, conflict=conflict, color_good=color_good,
                  block_item=block_item, card_item=card["item"] if card_valid else 0, item=item)
    return result
