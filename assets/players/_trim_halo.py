# Strips the white halo around the body sprites' black outline. The art was
# cut off white paper, so the anti-aliased rim just outside the outline is
# white-ish and semi-transparent, which reads as a light fringe on the field.
# Near-transparent rim pixels are dropped outright (a tighter cut), and the
# rest are re-inked black at their existing alpha, so the edge now fades out
# of the outline instead of glowing. Fully opaque pixels (collar trim, sleeve
# stripes) are never touched, and the canvas size is unchanged so the head
# rigs in assets/players/rigs/ stay aligned. Safe to re-run.
# Run from the project root:  python assets/players/_trim_halo.py
import glob
import numpy as np
from PIL import Image
from scipy import ndimage

DROP_BELOW = 80      # rim alpha under this is cut away entirely
RIM_PX = 3           # how far in from the transparent edge counts as rim
INK = np.array([8, 8, 10], dtype=np.uint8)

for path in sorted(glob.glob("assets/players/*/body*.png")):
    img = np.asarray(Image.open(path).convert("RGBA")).copy()
    alpha = img[..., 3]
    lum = img[..., :3].astype(np.float32).mean(axis=2)
    rim = ndimage.binary_dilation(alpha == 0, iterations=RIM_PX) & (alpha > 0) & (alpha < 250)
    light = rim & (lum > 60)
    drop = light & (alpha < DROP_BELOW)
    img[drop] = 0
    ink = light & ~drop
    img[ink, :3] = INK
    Image.fromarray(img, "RGBA").save(path, optimize=True)
    print(path, "dropped", int(drop.sum()), "inked", int(ink.sum()))
