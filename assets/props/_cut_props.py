# Cuts the four ability props (banana peel, chain, slot machine, beer keg)
# out of assets/assets.png - one opaque RGB sheet on white paper - into
# separate cropped PNGs with transparent backgrounds. Run from the project
# root:  python assets/props/_cut_props.py   (needs numpy, scipy, Pillow)
import numpy as np
from PIL import Image
from scipy import ndimage

src = np.asarray(Image.open("assets/assets.png").convert("RGB")).astype(np.float32)
H, W, _ = src.shape
sat = src.max(axis=2) - src.min(axis=2)
whiteish = (src.min(axis=2) > 232) & (sat < 18)

# Paper = whiteish pixels connected to the canvas border.
lab, _ = ndimage.label(whiteish)
edge_ids = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
paper = np.isin(lab, list(edge_ids))

# Each prop is one big connected blob of non-paper; name it by quadrant.
obj, count = ndimage.label(~paper)
sizes = ndimage.sum(np.ones(obj.shape), obj, range(1, count + 1))
boxes = ndimage.find_objects(obj)
QUADRANTS = {"topleft": "banana_peel", "topright": "chain",
             "bottomleft": "slot_machine", "bottomright": "beer_keg"}

for idx, size in enumerate(sizes, start=1):
    if size < 5000:
        continue
    sl = boxes[idx - 1]
    cy = (sl[0].start + sl[0].stop) / 2
    cx = (sl[1].start + sl[1].stop) / 2
    name = QUADRANTS[("top" if cy < H * 0.4 else "bottom") + ("left" if cx < W / 2 else "right")]
    y0, y1 = max(0, sl[0].start - 4), min(H, sl[0].stop + 4)
    x0, x1 = max(0, sl[1].start - 4), min(W, sl[1].stop + 4)
    rgb = src[y0:y1, x0:x1].copy()
    clear = obj[y0:y1, x0:x1] != idx
    if name == "chain":
        # The holes inside the links are paper too, just not border-connected.
        clear |= whiteish[y0:y1, x0:x1]
    alpha = np.where(clear, 0.0, 1.0)
    # De-matte the rim: those pixels are black outline blended into white
    # paper, so recover coverage from brightness and un-blend the colour.
    rim = (~clear) & ndimage.binary_dilation(clear, iterations=2)
    rim_alpha = np.clip((255.0 - rgb.mean(axis=2)) / (255.0 - 40.0), 0.0, 1.0)
    alpha = np.where(rim, rim_alpha, alpha)
    unblended = np.clip((rgb - (1.0 - alpha[..., None]) * 255.0) / np.maximum(alpha, 1e-3)[..., None], 0, 255)
    rgb = np.where(rim[..., None], unblended, rgb)
    img = Image.fromarray(np.dstack([rgb, alpha * 255.0]).astype(np.uint8), "RGBA")
    img = img.crop(img.getbbox())
    img.thumbnail((256, 256), Image.LANCZOS)
    img.save(f"assets/props/{name}.png", optimize=True)
    print(name, img.size)
