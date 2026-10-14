# Scene-v1 synthetic assets

Existing prep-v1-max40 rendered artwork is hashed in manifest.json. White paper is pasted onto dark or bounded textured backgrounds; white-background cards retain the original white surround.

Templates use the original 256x256 RGB artwork, a 3x3 center-preserving denoiser and the exact 28-pixel centered inclusive-bbox normalization. Test images are independently resized before the real bp-grid sampling. MAX_DISTANCE=40 and MIN_MARGIN=24 remain fixed.

The border uses each channel's lower median of 16-level bins; a bin is represented by nibble*16+8. Exterior background is four-connected and within RGB L-infinity distance 48. Occupancy needs 12 denoised cells and a 3x3 bbox.

fixtures.json separates intended truth from the actual model result. A false truth_satisfied remains a documented development limitation, never relabelled as a successful classification. fixtures.txt selects default RTL cases; all numeric checks use model expectations.

{
  "empty": {
    "count": 7,
    "truth_satisfied": 7
  },
  "noise": {
    "count": 3,
    "truth_satisfied": 3
  },
  "shadow": {
    "count": 3,
    "truth_satisfied": 3
  },
  "card": {
    "count": 135,
    "truth_satisfied": 27
  },
  "block": {
    "count": 27,
    "truth_satisfied": 27
  },
  "unknown": {
    "count": 3,
    "truth_satisfied": 3
  },
  "outside": {
    "count": 1,
    "truth_satisfied": 1
  },
  "edge": {
    "count": 1,
    "truth_satisfied": 1
  }
}

No camera capture or board measurements are included.
