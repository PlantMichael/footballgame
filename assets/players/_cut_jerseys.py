# Cuts a new jersey colour's bodies out of its three sprite sheets and fits
# each one EXACTLY onto the matching blue body: same canvas size, same
# silhouette box, same place in the canvas. That keeps every head rig in
# assets/players/rigs/ (built on the blue canvases) valid for every colour,
# and makes the colours interchangeable on the field.
#
# The sheets follow the blue ones' layout (assets/bodiesfront.png,
# bodiesback.png, bodiesleftside.png). Each blue body_NN.png is found on its
# blue sheet, the shape in the same spot on the new colour's sheet is cut
# out, and it's stretched to the blue body's box - which also shortens the
# skinny bodies, drawn a little taller on the new sheets. Front views get the
# blue art's skin-tone neck patch (and its _dark/_pale variants) laid in
# behind them.
#
# Run from the project root, e.g.:
#   python assets/players/_cut_jerseys.py green assets/jerseysgreenfront.png assets/jersyesgreenback.png assets/jerseysgreenleft.png
# Writes assets/players/<colour>/<view>/body_NN[_dark|_pale].png. Then add
# the colour to JerseyDB.COLORS.  (needs numpy, scipy, Pillow)
import glob
import os
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

BLUE_SHEETS = {"front": "assets/bodiesfront.png", "back": "assets/bodiesback.png",
               "left": "assets/bodiesleftside.png"}
SKIN = np.array([255, 197, 136])
INK = np.array([8, 8, 10], dtype=np.uint8)
BG_LIGHT = 232       # a sheet pixel at least this light on every channel is paper
MIN_AREA = 3000


def paper_mask(rgb):
    """Paper = light pixels connected to the sheet's border (so the white
    collar trim and sleeve stripes, walled in by the outline, are kept)."""
    light = rgb.min(axis=2) >= BG_LIGHT
    lab, _ = ndimage.label(light)
    edge = np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))
    return np.isin(lab, edge[edge > 0])


def shapes(sheet_path):
    """[(bbox slices, rgba crop, class map crop)] for every body on a sheet."""
    rgb = np.asarray(Image.open(sheet_path).convert("RGB")).astype(np.int32)
    paper = paper_mask(rgb)
    fg = ~paper
    lab, n = ndimage.label(fg)
    out = []
    for i, sl in enumerate(ndimage.find_objects(lab)):
        if sl is None:
            continue
        mask = lab[sl] == i + 1
        if mask.sum() < MIN_AREA:
            continue
        # Pad so the soft outer edge comes along.
        y0, y1 = max(sl[0].start - 3, 0), min(sl[0].stop + 3, rgb.shape[0])
        x0, x1 = max(sl[1].start - 3, 0), min(sl[1].stop + 3, rgb.shape[1])
        crop = rgb[y0:y1, x0:x1]
        m = (lab[y0:y1, x0:x1] == i + 1)
        # Anti-aliased rim: paper-side pixels touching the shape take alpha
        # from how dark they are, re-inked black (no white halo).
        near = ndimage.binary_dilation(m, iterations=2) & ~m
        a = np.zeros(m.shape, np.float32)
        a[m] = 1.0
        a[near] = np.clip((250.0 - crop[near].min(axis=1)) / 130.0, 0.0, 1.0)
        rgba = np.zeros(m.shape + (4,), np.uint8)
        rgba[..., :3] = crop.astype(np.uint8)
        rgba[near, :3] = INK
        rgba[..., 3] = (a * 255).astype(np.uint8)
        out.append({"box": (y0, y1, x0, x1), "rgba": rgba,
                    "center": ((y0 + y1) / 2.0, (x0 + x1) / 2.0)})
    return out


def classes(rgba):
    """0 transparent, 1 fabric/outline, 2 white trim - for shape matching
    that also tells a V-neck front from a round-collar back."""
    c = np.zeros(rgba.shape[:2], np.uint8)
    solid = rgba[..., 3] > 127
    c[solid] = 1
    c[solid & (rgba[..., :3].min(axis=2) > 200)] = 2
    return c


def tight(rgba):
    ys, xs = np.where(rgba[..., 3] > 0)
    return ys.min(), ys.max() + 1, xs.min(), xs.max() + 1


def match_score(cut_cls, cand_rgba):
    y0, y1, x0, x1 = tight(cand_rgba)
    cand = Image.fromarray(classes(cand_rgba[y0:y1, x0:x1]))
    cand = np.asarray(cand.resize((cut_cls.shape[1], cut_cls.shape[0]), Image.NEAREST))
    return float((cand == cut_cls).mean())


def main():
    colour, front, back, left = sys.argv[1:5]
    new_sheets = {"front": front, "back": back, "left": left}
    for view, blue_sheet in BLUE_SHEETS.items():
        blue_shapes = shapes(blue_sheet)
        new_shapes = shapes(new_sheets[view])
        os.makedirs(f"assets/players/{colour}/{view}", exist_ok=True)
        for path in sorted(glob.glob(f"assets/players/{view}/body_[0-9][0-9].png")):
            name = os.path.basename(path)[:-4]
            cut = np.asarray(Image.open(path).convert("RGBA"))
            cy0, cy1, cx0, cx1 = tight(cut)
            cut_cls = classes(cut[cy0:cy1, cx0:cx1])
            # Where this body sits on the blue sheet...
            scores = [match_score(cut_cls, s["rgba"]) for s in blue_shapes]
            src = blue_shapes[int(np.argmax(scores))]
            # ...and the shape in the same spot on the new colour's sheet.
            dists = [np.hypot(s["center"][0] - src["center"][0], s["center"][1] - src["center"][1])
                     for s in new_shapes]
            new = new_shapes[int(np.argmin(dists))]
            ny0, ny1, nx0, nx1 = tight(new["rgba"])
            body = Image.fromarray(new["rgba"][ny0:ny1, nx0:nx1])
            body = body.resize((cx1 - cx0, cy1 - cy0), Image.LANCZOS)
            canvas = Image.new("RGBA", (cut.shape[1], cut.shape[0]), (0, 0, 0, 0))
            canvas.paste(body, (cx0, cy0))
            out = np.asarray(canvas).copy()

            variants = {"": None}
            if view == "front":
                # The blue art's neck patch, laid in behind the new jersey.
                skin = (np.abs(cut[..., :3].astype(np.int32) - SKIN).max(axis=2) <= 40) & (cut[..., 3] > 250)
                skin = ndimage.binary_dilation(skin, iterations=2) & (cut[..., 3] > 0)
                for suffix in ("_dark", "_pale"):
                    vpath = f"assets/players/{view}/{name}{suffix}.png"
                    if os.path.exists(vpath) and skin.any():
                        v = np.asarray(Image.open(vpath).convert("RGB"))
                        core = (np.abs(cut[..., :3].astype(np.int32) - SKIN).max(axis=2) <= 40) & (cut[..., 3] > 250)
                        vals, counts = np.unique(v[core].reshape(-1, 3), axis=0, return_counts=True)
                        variants[suffix] = vals[np.argmax(counts)]
                variants[""] = SKIN
            for suffix, tone in variants.items():
                img = out.copy()
                if tone is not None and view == "front":
                    under = np.zeros_like(img)
                    under[skin, :3] = tone
                    under[skin, 3] = 255
                    img = np.asarray(Image.alpha_composite(Image.fromarray(under), Image.fromarray(img)))
                dst = f"assets/players/{colour}/{view}/{name}{suffix}.png"
                Image.fromarray(img).save(dst, optimize=True)
            print(view, name, "score %.2f" % max(scores), "size", cut.shape[1], "x", cut.shape[0])


main()
