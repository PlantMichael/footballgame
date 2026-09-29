# Cuts the floating hand out of each skin-tone hand canvas in assets/ and
# bakes a black outline into it, the same way _outline_heads.py does for the
# heads - so hands, heads and bodies all read with the same ink line on the
# field. Hands are drawn at about HAND_OF_FACE times a head's face size, so
# the outline is thicker (as a fraction of the hand) to come out the same
# on-screen weight. Run from the project root after changing hand art:
#   python assets/hands/_outline_hands.py
# (needs numpy, scipy, Pillow)
import numpy as np
from PIL import Image
from scipy import ndimage

# Source canvas in assets/ -> output here. field_view.gd's HAND_TEX table
# points at the outputs; hand_light matches head "1"'s skin, hand_dark
# head "2"'s.
HANDS = {"hands": "hand_light", "hands2": "hand_dark"}

# Must match field_view.gd's HAND_OF_FACE. Heads carry 36px of ink per 496px
# face (see _outline_heads.py's OUTLINE_FRAC).
HAND_OF_FACE = 0.62
OUTLINE_FRAC = 36.0 / 496.0 / HAND_OF_FACE
INK = np.array([10, 8, 8], dtype=np.float32)
PAD = 4
OUT_SIZE = 128

for src, dst in HANDS.items():
    img = np.asarray(Image.open(f"assets/{src}.png").convert("RGBA")).astype(np.float32)
    alpha = img[..., 3]
    solid = alpha > 127
    ys, xs = np.where(solid)
    top, bottom, left, right = ys.min(), ys.max(), xs.min(), xs.max()
    thickness = OUTLINE_FRAC * (bottom - top + 1)
    dist = ndimage.distance_transform_edt(solid)
    ink = np.clip(thickness + 0.5 - dist, 0.0, 1.0)[..., None]
    rgb = img[..., :3] * (1.0 - ink) + INK * ink
    fringe = (alpha > 0) & ~solid
    rgb[fringe] = INK
    out = np.dstack([rgb, alpha]).astype(np.uint8)
    crop = Image.fromarray(out, "RGBA").crop((left - PAD, top - PAD, right + PAD + 1, bottom + PAD + 1))
    crop = crop.resize((OUT_SIZE, OUT_SIZE), Image.LANCZOS)
    crop.save(f"assets/hands/{dst}.png", optimize=True)
    print(dst, round(thickness, 1), crop.size)
