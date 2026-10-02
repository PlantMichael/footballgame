# Cuts the bowl logos out of their white paper: assets/bowl.png ->
# assets/bowl_cut.png, same size and 3x2 layout (BowlDB slices both the same
# way), with the paper made transparent. Paper = light pixels connected to
# the sheet's border, so the white lettering and footballs inside each logo -
# walled in by its black outline - are kept. The anti-aliased rim just
# outside the outline fades out rather than leaving a white fringe.
# Run from the project root:  python assets/_cut_bowls.py
import numpy as np
from PIL import Image
from scipy import ndimage

SRC = "assets/bowl.png"
DST = "assets/bowl_cut.png"
PAPER_MIN = 200     # every channel at least this light counts as paper
RIM_PX = 2          # how far past the paper the soft edge reaches
INK = np.array([10, 10, 12], dtype=np.float32)

img = np.asarray(Image.open(SRC).convert("RGBA")).astype(np.float32)
rgb = img[..., :3]
light = (rgb >= PAPER_MIN).all(axis=2)

# Flood from the border through light pixels only.
labels, _ = ndimage.label(light)
border = set(np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]])))
border.discard(0)
paper = np.isin(labels, list(border))

alpha = np.where(paper, 0.0, 255.0)
# Soft edge: pixels just inside the cut get alpha from how dark they are, and
# are re-inked toward the outline colour so no light halo survives.
rim = ndimage.binary_dilation(paper, iterations=RIM_PX) & ~paper
lum = rgb.mean(axis=2)
edge_a = np.clip((255.0 - lum) / (255.0 - 90.0), 0.0, 1.0) * 255.0
alpha = np.where(rim, np.minimum(alpha, edge_a), alpha)
ink_mix = np.clip(lum / 255.0, 0.0, 1.0)[..., None]
rgb = np.where(rim[..., None], rgb * (1.0 - ink_mix) + INK * ink_mix, rgb)

out = np.dstack([rgb, alpha]).clip(0, 255).astype(np.uint8)
Image.fromarray(out, "RGBA").save(DST, optimize=True)
print(DST, "paper px", int(paper.sum()), "rim px", int(rim.sum()))
