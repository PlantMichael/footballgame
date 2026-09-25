// Paints a flat skin-tone fill into the open V-notch of a front body sprite,
// matching what was hand-painted into body_05/body_09 (RGB 255,197,136).
//
// Finds the notch as a single CONTIGUOUS run of columns around the deepest
// point of the dip, expanding outward only while the silhouette stays
// elevated above its immediate flanking height, and stops the instant it
// drops back down - rather than scanning a fixed-width band for "anything
// above the shoulder baseline". A fixed band mis-fires on sprites whose
// shoulders taper smoothly into the notch with no flat plateau (body_08):
// the gradual slope near the band's edges still reads as "above baseline"
// and gets filled too, so the skin patch ends up wider than the head sprite
// that sits on top of it and pokes out past both sides as stray flaps.
// Growing outward from the peak stops right at the notch's own edges,
// wherever they happen to fall, matching how narrow and centered the
// hand-painted fill on body_05/09 is.
const { decodePng, encodePng } = require('./_pnglib.js');

const SKIN = [255, 197, 136, 255];
const ALPHA_THRESH = 10;
const MARGIN = 3;

function fillCollar(path, outPath) {
  const img = decodePng(path);
  const { width, height, pixels } = img;
  const alphaAt = (x, y) => pixels[(y * width + x) * 4 + 3];

  const topRow = new Array(width).fill(-1);
  for (let x = 0; x < width; x++) {
    for (let y = 0; y < height; y++) {
      if (alphaAt(x, y) > ALPHA_THRESH) { topRow[x] = y; break; }
    }
  }

  const bandLo = Math.floor(width * 0.25), bandHi = Math.ceil(width * 0.75);
  let baseline = height;
  for (let x = bandLo; x <= bandHi && x < width; x++) {
    if (topRow[x] >= 0) baseline = Math.min(baseline, topRow[x]);
  }

  // The peak search band is deliberately tighter than the baseline band: a
  // sprite whose shoulders taper smoothly into the notch, with no flat
  // plateau (body_06/08), has topRow values on the OUTER part of the wider
  // band that are higher than the shallow notch's own peak - the true
  // collar dip loses to the sleeve taper. Every sprite's actual notch
  // center falls well inside the middle third, so restrict peak-finding to
  // that and let it stay a local maximum rather than an edge artifact.
  const peakLo = Math.floor(width * 0.35), peakHi = Math.ceil(width * 0.65);
  let peakX = peakLo, peakVal = -1;
  for (let x = peakLo; x <= peakHi && x < width; x++) {
    if (topRow[x] > peakVal) { peakVal = topRow[x]; peakX = x; }
  }

  // Expansion from the peak still needs a hard width cap: on body_06 the
  // taper's topRow values stay above threshold continuously all the way to
  // the sprite's outer edge (they only ever go up further out), so an
  // unbounded "keep going while above threshold" walk would run straight
  // off the true notch and paint half the shoulder.
  const threshold = baseline + MARGIN;
  const maxHalfWidth = Math.round(width * 0.21);
  let lo = peakX;
  while (lo - 1 >= 0 && peakX - (lo - 1) <= maxHalfWidth && topRow[lo - 1] >= threshold) lo--;
  let hi = peakX;
  while (hi + 1 < width && (hi + 1) - peakX <= maxHalfWidth && topRow[hi + 1] >= threshold) hi++;

  let filled = 0;
  for (let x = lo; x <= hi; x++) {
    if (topRow[x] < 0) continue;
    for (let y = baseline; y < topRow[x]; y++) {
      const i = (y * width + x) * 4;
      if (pixels[i + 3] <= ALPHA_THRESH) {
        pixels[i] = SKIN[0]; pixels[i + 1] = SKIN[1]; pixels[i + 2] = SKIN[2]; pixels[i + 3] = SKIN[3];
        filled++;
      }
    }
  }

  encodePng(outPath, width, height, pixels);
  return { width, height, baseline, notchCols: [lo, hi], filled };
}

module.exports = { fillCollar };

if (require.main === module) {
  const [inPath, outPath] = process.argv.slice(2);
  console.log(fillCollar(inPath, outPath));
}
