"""Array oracle for the SC520 scene candidate; no RTL internals or camera claims.

The scene-v2 encoding has twenty active cells centered in the unchanged 32x32
interface. Its three templates per class model sampling aliases, not new labels.
The 40-bit threshold is therefore 40/400 active bits, not scene-v1's 40/784.
"""
from __future__ import annotations

from collections import deque
import numpy as np

GRID_WIDTH, GRID_HEIGHT = 120, 60
ROI_X, ROI_Y, SAMPLE_STEP = 40, 30, 2
NORMALIZED_SIDE = 20
TEMPLATES_PER_CLASS = 3


def threshold(rgb):
    rgb = np.asarray(rgb, dtype=np.int16)
    return (rgb.min(axis=-1) < 180) | (rgb.max(axis=-1) - rgb.min(axis=-1) >= 40)


def despeckle(mask):
    mask = np.asarray(mask, dtype=bool)
    padded = np.pad(mask.astype(np.uint8), 1)
    count = np.zeros(mask.shape, dtype=np.uint8)
    for y in range(3):
        for x in range(3):
            count += padded[y:y + mask.shape[0], x:x + mask.shape[1]]
    return mask & (count >= 3)


def bbox(mask):
    yy, xx = np.nonzero(mask)
    return None if not len(xx) else (int(xx.min()), int(yy.min()), int(xx.max()), int(yy.max()))


def normalize(mask, active_side=NORMALIZED_SIDE):
    """Center the inclusive bbox in active_side cells using integer floor.

    active_side=28 is retained only for replaying the frozen scene-v1 diagnosis.
    """
    mask = np.asarray(mask, dtype=bool)
    bounds = bbox(mask)
    result = np.zeros((32, 32), dtype=bool)
    if bounds is None:
        return result
    xmin, ymin, xmax, ymax = bounds
    width, height = xmax - xmin + 1, ymax - ymin + 1
    longest = max(width, height)
    if active_side < 1 or active_side > 32 or active_side % 2:
        raise ValueError("active normalization side must be even and in 2..32")
    padding = (32 - active_side) // 2
    for gy in range(padding, padding + active_side):
        ny = active_side * (2 * ymin + height - longest) + (2 * (gy - padding) + 1) * longest
        sy = ny // (2 * active_side)
        for gx in range(padding, padding + active_side):
            nx = active_side * (2 * xmin + width - longest) + (2 * (gx - padding) + 1) * longest
            sx = nx // (2 * active_side)
            if nx >= 0 and ny >= 0 and xmin <= sx <= xmax and ymin <= sy <= ymax:
                result[gy, gx] = mask[sy, sx]
    return result


def analyze(rgb, *, active_side=NORMALIZED_SIDE, conservative_guards=True):
    """Border median, exterior flood fill, independent occupancy/glyph denoising."""
    rgb = np.asarray(rgb, dtype=np.uint8)
    height, width, channels = rgb.shape
    if channels != 3 or height < 3 or width < 3:
        raise ValueError("scene raster must have three channels and at least 3x3 cells")
    border = np.zeros((height, width), dtype=bool)
    border[0, :] = border[-1, :] = True
    border[:, 0] = border[:, -1] = True
    bins = rgb[border] // 16
    # The lower median is deliberate for an even number of border cells.
    center = np.sort(bins, axis=0)[(len(bins) - 1) // 2].astype(np.int16) * 16 + 8
    similar = np.abs(rgb.astype(np.int16) - center).max(axis=-1) <= 48
    connected = np.zeros((height, width), dtype=bool)
    queue = deque()
    for y, x in np.argwhere(border & similar):
        connected[y, x] = True
        queue.append((int(y), int(x)))
    while queue:
        y, x = queue.popleft()
        for sy, sx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= sy < height and 0 <= sx < width and similar[sy, sx] and not connected[sy, sx]:
                connected[sy, sx] = True
                queue.append((sy, sx))
    raw_scene = ~connected
    scene = despeckle(raw_scene)
    glyph = despeckle(raw_scene & threshold(rgb))
    bounds = bbox(scene)
    occupied = bool(scene.sum() >= 12 and bounds and bounds[2] - bounds[0] + 1 >= 3 and bounds[3] - bounds[1] + 1 >= 3)
    border_similar = int(np.count_nonzero(border & similar))
    border_count = int(border.sum())
    background_qualified = border_similar * 4 >= border_count * 3
    edge_contact = bool(occupied and (scene[0].any() or scene[-1].any() or scene[:, 0].any() or scene[:, -1].any()))
    admitted = not conservative_guards or (background_qualified and not edge_contact)
    # A frame with untrustworthy spatial separation remains a healthy unknown;
    # it cannot be used as evidence that a previously scored object was removed.
    present = occupied or (conservative_guards and not background_qualified)
    # Suppress residual colored speckles when occupancy is below its admission floor.
    replay = np.where((scene & present & admitted)[..., None], rgb, 255).astype(np.uint8)
    normalized = normalize(glyph, active_side) if admitted else np.zeros((32, 32), dtype=bool)
    return {"background_rgb": center.tolist(), "scene": scene, "glyph": glyph,
            "connected_background": connected, "present": present, "scene_count": int(scene.sum()),
            "glyph_count": int(glyph.sum()), "scene_bbox": bounds, "glyph_bbox": bbox(glyph),
            "border_similar": border_similar, "border_count": border_count,
            "background_qualified": bool(background_qualified), "edge_contact": edge_contact,
            "recognition_admitted": bool(admitted),
            "mask": normalized, "replay_rgb": replay}


def sample_frame(frame):
    frame = np.asarray(frame, dtype=np.uint8)
    if frame.shape != (180, 320, 3):
        raise ValueError("scene input must be the real 320x180 bp raster")
    return frame[ROI_Y + 1:ROI_Y + GRID_HEIGHT * 2:2,
                 ROI_X + 1:ROI_X + GRID_WIDTH * 2:2].copy()


def classify(mask, templates, present=True):
    mask = np.asarray(mask, dtype=bool)
    templates = np.asarray(templates, dtype=bool)
    if templates.shape == (5, 32, 32):
        templates = templates[:, None]
    if templates.ndim != 4 or templates.shape[0] != 5 or templates.shape[2:] != (32, 32):
        raise ValueError("templates must be [5, variants, 32, 32]")
    variant_distances = np.count_nonzero(mask != templates, axis=(2, 3))
    distance = variant_distances.min(axis=1).astype(int).tolist()
    order = sorted(range(5), key=lambda i: (distance[i], i))
    best, second = distance[order[0]], distance[order[1]]
    foreground = int(mask.sum())
    valid = bool(present and 16 <= foreground <= 850 and best <= 40 and second - best >= 24)
    return {"distances": distance, "variant_distances": variant_distances.astype(int).tolist(),
            "best": best, "second": second, "foreground": foreground,
            "valid": valid, "item": order[0] + 10 if valid else 0}


def block_classify(rgb, present):
    """Independent geometry calculation for the task's existing block classifier."""
    rgb = np.asarray(rgb, dtype=np.int16)
    red, green, blue = (rgb[..., i] for i in range(3))
    masks = [(red >= 80) & (red >= green + 32) & (red >= blue + 32),
             (red >= 96) & (green >= 80) & (blue <= 96) & (red <= green + 80) &
             (green <= red + 80) & (red >= blue + 32) & (green >= blue + 24),
             (blue >= 80) & (blue >= red + 24) & (blue >= green + 24)]
    masks[0] &= ~masks[1]
    masks[2] &= ~(masks[0] | masks[1])
    areas = [int(mask.sum()) for mask in masks]
    for color, area in enumerate(areas):
        if area < 12 or any(area < 2 * other for i, other in enumerate(areas) if i != color):
            continue
        xmin, ymin, xmax, ymax = bbox(masks[color])
        w, h = xmax - xmin + 1, ymax - ymin + 1
        box = w * h
        if not present or xmin == 0 or ymin == 0 or xmax == rgb.shape[1] - 1 or ymax == rgb.shape[0] - 1 or w < 3 or h < 3:
            return 0
        near_square = w * 5 >= h * 4 and h * 5 >= w * 4
        shape = 2 if near_square and area * 128 >= box * 116 else 1 if near_square and box * 88 <= area * 128 <= box * 110 else 3 if w * 2 >= h and w * 4 <= h * 7 and box * 51 <= area * 128 <= box * 80 else 0
        return color * 3 + shape if shape else 0
    return 0
