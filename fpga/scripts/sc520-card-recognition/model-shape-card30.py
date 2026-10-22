"""T030 complete-glyph scoring models; no color-body, bridge, or shape recovery."""
from pathlib import Path
import importlib.util
import numpy as np

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("shape_card30_frozen_scene", HERE / "model-contour29.py")
frozen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(frozen)
base = frozen.base
ITEMS = (0, 1, 2, 3, 10, 11, 12, 13, 14)
MARGINS = (0, 4, 8, 12, 16, 24)


def scene(frame):
    """Reuse only the independent D0261 chroma-envelope scene array oracle."""
    rgb = np.asarray(frame, dtype=np.uint8)
    if rgb.shape == (180, 320, 3):
        rgb = base.sample_frame(rgb)
    if rgb.shape != (60, 120, 3):
        raise ValueError("Expected full bp raster or sampled 120x60 grid")
    return frozen.scene(rgb)


def normalize_axes(mask):
    result = np.zeros((32, 32), dtype=bool)
    bounds = base.base.bbox(mask)
    if bounds is not None:
        left, top, right, bottom = bounds
        width, height = right-left+1, bottom-top+1
        for y in range(20):
            for x in range(20):
                result[y+6, x+6] = mask[top+(2*y+1)*height//40, left+(2*x+1)*width//40]
    return result


def geometry_bank():
    y, x = np.mgrid[:20, :20]
    dx, dy = 2*x+1-20, 2*y+1-20
    basic = np.asarray((dx*dx+dy*dy <= 400, np.ones((20, 20), bool),
                        2*np.abs(dx) <= 2*y+1))
    negatives = []
    for ratio in (0.6, 0.8):
        for angle in range(0, 180, 30):
            a = np.deg2rad(angle)
            u = dx/20*np.cos(a)+dy/20*np.sin(a)
            v = -dx/20*np.sin(a)+dy/20*np.cos(a)
            negatives.append(u*u+(v/ratio)**2 <= 1)
    aliases = np.asarray((dx*dx+dy*dy <= 400, dx*dx+dy*dy <= 361))
    return basic, np.asarray(negatives), aliases


BASIC, ELLIPSES, CIRCLE_ALIASES = geometry_bank()


def scores(mask, bank, *, present=True, clipped=False, glyph=None):
    """Distances all refer to the entire glyph; colors are never examined."""
    mask = np.asarray(mask, dtype=bool)
    if mask.shape != (32, 32):
        raise ValueError("Expected 32x32 normalized complete glyph")
    active = mask[6:26, 6:26]
    shape = np.count_nonzero(BASIC != active, axis=(1, 2)).astype(int).tolist()
    card_distances = np.count_nonzero(bank != active, axis=(2, 3)).min(axis=1).astype(int).tolist()
    ranked = sorted(range(5), key=lambda index: (card_distances[index], index))
    best, second = card_distances[ranked[0]], card_distances[ranked[1]]
    foreground = int(mask.sum())
    ellipse = int(np.count_nonzero(ELLIPSES != active, axis=(1, 2)).min())
    axis = normalize_axes(glyph) if glyph is not None else normalize_axes(mask)
    axis_circle = int(np.count_nonzero(CIRCLE_ALIASES != axis[6:26, 6:26], axis=(1, 2)).min())
    return dict(ShapeDistances=shape, CardDistances=card_distances, CardBest=best,
                CardSecond=second, CardWinner=ranked[0]+10,
                CardQualified=bool(present and not clipped and 16 <= foreground <= 850 and
                                   best <= 40 and second-best >= 24),
                Foreground=foreground, Present=bool(present), Clipped=bool(clipped),
                FullEllipseDistance=ellipse, FullAxisCircleDistance=axis_circle)


def arbitrate(score, margin, model):
    if margin not in MARGINS or model not in ("A", "B-full-negative", "B-axis-negative"):
        raise ValueError("Unapproved model/margin experiment")
    if not score["Present"] or score["Clipped"]:
        return 0
    distances = score["ShapeDistances"]
    bits = [index for index, distance in enumerate(distances) if distance <= 20]
    shape = bits[0]+1 if len(bits) == 1 else 0
    shape_best = min(distances)
    # A tie never becomes a positive class, even at cross-family margin zero.
    if shape and score["CardBest"] > shape_best+margin:
        return shape
    card_competitor = shape_best
    if model != "A":
        card_competitor = min(card_competitor, score["FullEllipseDistance"])
    if model == "B-axis-negative" and score["FullAxisCircleDistance"] <= 20:
        card_competitor = min(card_competitor, score["FullAxisCircleDistance"])
    if score["CardQualified"] and card_competitor > score["CardBest"]+margin:
        return score["CardWinner"]
    return 0


def legacy_color_model(result, bank):
    """Disclosed D0261 array model, not a new execution of the old RTL."""
    shape = base.shape_classify(result["mask"])
    card = base.classify(result["mask"], bank, result["present"])
    replay = np.where((result["scene"] & result["present"] & ~np.asarray(result["clipped"]) &
                       ~np.asarray(result["paper_route"]))[..., None], result["rgb"], 255).astype(np.uint8)
    labels = frozen.labels(replay)
    synthetic = np.full_like(replay, 255)
    for label, rgb in enumerate(((215, 61, 60), (245, 205, 45), (50, 112, 205)), 1):
        synthetic[labels == label] = rgb
    raw = base.base.block_classify(synthetic, result["present"])
    block = raw if raw and shape["shape_bits"] & (1 << ((raw-1) % 3)) else 0
    card_item = card["item"] if shape["shape_bits"] == 0 else 0
    return 0 if block and card_item else block or card_item
