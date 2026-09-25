// Makes a skin-tone variant of a front body sprite by swapping every pixel
// that matches the existing collar fill color for a new one, leaving the
// rest of the art (outline, trim, fabric) untouched.
const { decodePng, encodePng } = require('./_pnglib.js');

const SOURCE_SKIN = [255, 197, 136];
const TOLERANCE = 40; // squared-free per-channel distance, catches minor compression drift

function recolor(path, outPath, targetRgb) {
  const img = decodePng(path);
  const { width, height, pixels } = img;
  let swapped = 0;
  for (let i = 0; i < width * height; i++) {
    const o = i * 4;
    if (pixels[o + 3] < 250) continue;
    const dr = Math.abs(pixels[o] - SOURCE_SKIN[0]);
    const dg = Math.abs(pixels[o + 1] - SOURCE_SKIN[1]);
    const db = Math.abs(pixels[o + 2] - SOURCE_SKIN[2]);
    if (dr <= TOLERANCE && dg <= TOLERANCE && db <= TOLERANCE) {
      pixels[o] = targetRgb[0]; pixels[o + 1] = targetRgb[1]; pixels[o + 2] = targetRgb[2];
      swapped++;
    }
  }
  encodePng(outPath, width, height, pixels);
  return { swapped };
}

module.exports = { recolor };

if (require.main === module) {
  const [inPath, outPath, r, g, b] = process.argv.slice(2);
  console.log(recolor(inPath, outPath, [Number(r), Number(g), Number(b)]));
}
