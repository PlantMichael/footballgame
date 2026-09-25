# Bakes a black outline into every head sprite, matching the thickness of the
# black outline on the body art once both are drawn at their in-game sizes.
# Reads the original canvases in assets/ and writes same-size copies here,
# which is what HeadArtDB and the body rig scenes use. Also writes
# faces.json: where the round face sits on each canvas, so a head with hair
# (or anything else) sticking out past the circle is sized by its face and
# lets the rest overflow, rather than being squashed to fit a square. Run from the project
# root after changing any head art:  python assets/heads_outlined/_outline_heads.py
# (needs numpy, scipy, Pillow)
import glob, json, os
import numpy as np
from PIL import Image
from scipy import ndimage

HEADS = ["headforward", "headback", "headleft", "headright",
         "head2front", "head2back", "head2left", "head2right",
         "runnadballfront", "runnadballback", "runnadballleft", "runnadballright",
         "rockstonehead", "rockstoneheadback", "rockstoneheadleft", "rockstoneheadright",
         "cursedplayerfront", "cursedplayerback", "cursedplayerleft", "cursedplayerright",
         "amillionbuggsfront", "amillionbuggsback", "amillionbuggsleft", "amillionbuggsright"]

# The body sprites carry a ~6.5px black outline, and a head is drawn at about
# 0.18x its source size relative to them - so ~36px on a 496px-tall head.
# Expressed as a fraction of the head's own height so heads cropped at other
# sizes get the same on-screen thickness.
OUTLINE_FRAC = 36.0 / 496.0
INK = np.array([10, 8, 8], dtype=np.float32)

def face_box(solid):
    """Canvas-space [x, y, w, h] of the round face. Fit a circle to the left
    and right edges of the bottom third of the silhouette - hair and other
    extras sit on top, so the bottom is pure face."""
    ys = np.where(solid.any(axis=1))[0]
    top, bottom = ys.min(), ys.max()
    pts = []
    for y in range(int(bottom - (bottom - top) * 0.33), bottom - 2):
        xs = np.where(solid[y])[0]
        if xs.size:
            pts.append((xs.min(), y))
            pts.append((xs.max(), y))
    pts = np.array(pts, dtype=np.float64)
    # Algebraic circle fit: x^2 + y^2 + D x + E y + F = 0.
    A = np.column_stack([pts[:, 0], pts[:, 1], np.ones(len(pts))])
    b = -(pts[:, 0] ** 2 + pts[:, 1] ** 2)
    D, E, F = np.linalg.lstsq(A, b, rcond=None)[0]
    cx, cy = -D / 2, -E / 2
    r = np.sqrt(cx * cx + cy * cy - F)
    return [round(cx - r, 1), round(cy - r, 1), round(2 * r, 1), round(2 * r, 1)]


faces = {}
for name in HEADS:
    src = f"assets/{name}.png"
    if not os.path.exists(src):
        continue
    img = np.asarray(Image.open(src).convert("RGBA")).astype(np.float32)
    alpha = img[..., 3]
    solid = alpha > 127
    ys = np.where(solid.any(axis=1))[0]
    faces[name] = face_box(solid)
    # Thickness scales with the face, not the whole silhouette - hair on
    # top shouldn't make the outline heavier.
    thickness = OUTLINE_FRAC * faces[name][3]
    # Distance from each solid pixel in to the silhouette's edge: everything
    # within `thickness` of it becomes ink, with a one-pixel soft inner edge.
    dist = ndimage.distance_transform_edt(solid)
    ink = np.clip(thickness + 0.5 - dist, 0.0, 1.0)[..., None]
    rgb = img[..., :3] * (1.0 - ink) + INK * ink
    # The antialiased fringe outside the solid mask is ink too.
    fringe = (alpha > 0) & ~solid
    rgb[fringe] = INK
    out = np.dstack([rgb, alpha]).astype(np.uint8)
    Image.fromarray(out, "RGBA").save(f"assets/heads_outlined/{name}.png", optimize=True)
    print(name, round(thickness, 1))

with open("assets/heads_outlined/faces.json", "w", newline="\n") as f:
    json.dump(faces, f, indent="\t")
    f.write("\n")
