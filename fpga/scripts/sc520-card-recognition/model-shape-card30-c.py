"""One fixed, main-scoped offline C candidate; no parameter search."""
from pathlib import Path
import hashlib
import importlib.util
import numpy as np

HERE = Path(__file__).resolve().parent
ORIGINAL = HERE / "model-shape-card30.py"
ORIGINAL_SHA = "F7A24536888460EA15EFB92043EF27D091A6E189B81446C483B667E442052EA5"
if hashlib.sha256(ORIGINAL.read_bytes()).hexdigest().upper() != ORIGINAL_SHA:
    raise RuntimeError("Frozen A/B model changed")
spec = importlib.util.spec_from_file_location("shape30_c_frozen_ab", ORIGINAL)
ab = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ab)


def describe(scene):
    grid = scene["rgb"].astype(np.uint16)
    # Maximum intermediate is 1020: the planned RTL expression needs ten bits.
    total = grid[..., 0]+2*grid[..., 1]+grid[..., 2]
    if total.max() > 1020:
        raise RuntimeError("Invalid RGB sum")
    y = total >> 2
    values = y[scene["glyph"]]
    bounds = ab.base.base.bbox(scene["glyph"])
    width, height = (bounds[2]-bounds[0]+1, bounds[3]-bounds[1]+1) if bounds else (0, 0)
    return dict(GeometryAvailable=bool(len(values) and width and height),
                GlyphYMinimum=int(values.min()) if len(values) else None,
                GlyphYMaximum=int(values.max()) if len(values) else None,
                GlyphYSpan=int(values.max())-int(values.min()) if len(values) else None,
                Width=width if bounds else None, Height=height if bounds else None)


def decide(score, descriptor, *, normalized_template=False):
    raw_circle, square, triangle = score["ShapeDistances"]
    available = bool(not normalized_template and descriptor.get("GeometryAvailable"))
    width, height = descriptor.get("Width"), descriptor.get("Height")
    axis_eligible = bool(available and width and height and min(width, height)*8 >= max(width, height)*7)
    effective_circle = min(raw_circle, score["FullAxisCircleDistance"]) if axis_eligible else raw_circle
    effective = [effective_circle, square, triangle]
    # Full-shape and negative evidence stay in card competition after a Y veto.
    competitor = min(*effective, score["FullEllipseDistance"])
    y_allowed = bool(available and descriptor["GlyphYSpan"] <= 64)
    positive_bits = [index for index, distance in enumerate(effective) if distance <= 20]
    shape_best = min(effective)
    negative_allows_geometry = score["FullEllipseDistance"] > shape_best+8
    shape = positive_bits[0]+1 if y_allowed and negative_allows_geometry and len(positive_bits) == 1 else 0
    card_maximum = 32 if score["CardWinner"] == 10 else 40
    card = bool(score["CardQualified"] and score["CardBest"] <= card_maximum)
    item, reason = 0, "unknown_score_or_competition"
    if not score["Present"]:
        reason = "healthy_empty"
    elif score["Clipped"]:
        reason = "clipped_or_background_uncertain"
    elif shape and score["CardBest"] > shape_best+8:
        item, reason = shape, "unique_geometry_wins_fixed_margin8"
    elif card and competitor > score["CardBest"]+8:
        item, reason = score["CardWinner"], "card_wins_fixed_margin8"
    return dict(Item=item, Reason=reason, GeometryAvailable=available,
                RawCircleDistance=raw_circle, EffectiveCircleDistance=effective_circle,
                EffectiveShapeDistances=effective, AxisCircleEligible=axis_eligible,
                FullAxisCircleDistance=score["FullAxisCircleDistance"],
                GeometryYSpanAvailable=available, GeometryYSpan=descriptor.get("GlyphYSpan") if available else None,
                GeometryYRejected=bool(available and descriptor["GlyphYSpan"] > 64),
                DistanceOnlyShapeBits=sum(1 << index for index in positive_bits) if available else 0,
                PositiveShapeBits=sum(1 << index for index in positive_bits) if y_allowed and negative_allows_geometry else 0,
                NegativeEvidenceRejectsGeometry=bool(available and not negative_allows_geometry),
                GeometryCandidate=shape, CardMaximumDistance=card_maximum,
                CardQualifiedAfterAppleLimit=card, CardCompetitorDistance=competitor,
                TemplateOnlyWithoutRGB=normalized_template)
