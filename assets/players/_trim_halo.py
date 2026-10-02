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
# The recoloured jerseys (_cut_jerseys.py) also carry fully OPAQUE paper-white
# pixels hugging the outside of the outline, which the alpha test above never
# sees. For those, light pixels touching the transparent outside are peeled
# off a layer at a time; the black outline stops the peel, so the collar and
# sleeve trim inside it are never reached.
PEEL_PASSES = 3
PEEL_LUM = 60
SPECK_PX = 30

# Blue art is assets/players/<view>/, every other jersey colour one level
# deeper in assets/players/<colour>/<view>/ (JerseyDB).
paths = glob.glob("assets/players/*/body*.png") + glob.glob("assets/players/*/*/body*.png")
for path in sorted(paths):
    img = np.asarray(Image.open(path).convert("RGBA")).copy()
    lum = img[..., :3].astype(np.float32).mean(axis=2)
    if path.replace("\\", "/").count("/") > 3:   # assets/players/<colour>/<view>/
        for _ in range(PEEL_PASSES):
            outside = ndimage.binary_dilation(img[..., 3] == 0) & (img[..., 3] > 0)
            peel = outside & (lum > PEEL_LUM)
            if not peel.any():
                break
            img[peel] = 0
        # Stray specks the peel left floating off the body.
        labels, n = ndimage.label(img[..., 3] > 0)
        if n > 1:
            sizes = ndimage.sum(np.ones_like(labels), labels, range(1, n + 1))
            img[np.isin(labels, np.flatnonzero(sizes < SPECK_PX) + 1)] = 0
    alpha = img[..., 3]
    rim = ndimage.binary_dilation(alpha == 0, iterations=RIM_PX) & (alpha > 0) & (alpha < 250)
    light = rim & (lum > 60)
    drop = light & (alpha < DROP_BELOW)
    img[drop] = 0
    ink = light & ~drop
    img[ink, :3] = INK
    Image.fromarray(img, "RGBA").save(path, optimize=True)
    print(path, "dropped", int(drop.sum()), "inked", int(ink.sum()))
