const fs = require('fs');
const zlib = require('zlib');

function paeth(a, b, c) {
  const p = a + b - c;
  const pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
  if (pa <= pb && pa <= pc) return a;
  if (pb <= pc) return b;
  return c;
}

function decodePng(path) {
  const buf = fs.readFileSync(path);
  let off = 8;
  const width = buf.readUInt32BE(16);
  const height = buf.readUInt32BE(20);
  const bitdepth = buf.readUInt8(24);
  const colortype = buf.readUInt8(25);
  const interlace = buf.readUInt8(28);
  if (bitdepth !== 8 || colortype !== 6 || interlace !== 0) {
    throw new Error('unsupported png format ' + path + ' bd=' + bitdepth + ' ct=' + colortype + ' il=' + interlace);
  }
  const idatChunks = [];
  off = 8;
  while (off < buf.length) {
    const len = buf.readUInt32BE(off);
    const type = buf.toString('ascii', off + 4, off + 8);
    const data = buf.slice(off + 8, off + 8 + len);
    if (type === 'IDAT') idatChunks.push(data);
    off += 8 + len + 4;
  }
  const raw = zlib.inflateSync(Buffer.concat(idatChunks));
  const bpp = 4; // RGBA 8-bit
  const stride = width * bpp;
  const pixels = Buffer.alloc(stride * height);
  let rawOff = 0;
  for (let y = 0; y < height; y++) {
    const filter = raw[rawOff]; rawOff += 1;
    const rowStart = y * stride;
    const prevRowStart = (y - 1) * stride;
    for (let x = 0; x < stride; x++) {
      const val = raw[rawOff + x];
      const a = x >= bpp ? pixels[rowStart + x - bpp] : 0;
      const b = y > 0 ? pixels[prevRowStart + x] : 0;
      const c = (x >= bpp && y > 0) ? pixels[prevRowStart + x - bpp] : 0;
      let out;
      switch (filter) {
        case 0: out = val; break;
        case 1: out = (val + a) & 0xff; break;
        case 2: out = (val + b) & 0xff; break;
        case 3: out = (val + Math.floor((a + b) / 2)) & 0xff; break;
        case 4: out = (val + paeth(a, b, c)) & 0xff; break;
        default: throw new Error('bad filter ' + filter);
      }
      pixels[rowStart + x] = out;
    }
    rawOff += stride;
  }
  return { width, height, pixels, bpp };
}

function alphaAt(img, x, y) {
  const idx = (y * img.width + x) * img.bpp + 3;
  return img.pixels[idx];
}

function analyze(path) {
  const img = decodePng(path);
  const { width, height } = img;
  // topmost opaque row per column
  const topRow = new Array(width).fill(-1);
  for (let x = 0; x < width; x++) {
    for (let y = 0; y < height; y++) {
      if (alphaAt(img, x, y) > 10) { topRow[x] = y; break; }
    }
  }
  // overall topmost opaque row (shoulder apex)
  let overallTop = height;
  for (let x = 0; x < width; x++) if (topRow[x] >= 0) overallTop = Math.min(overallTop, topRow[x]);
  // center band deepest top (collar/neck notch bottom)
  const cLo = Math.floor(width * 0.35), cHi = Math.ceil(width * 0.65);
  let notchRow = -1;
  for (let x = cLo; x <= cHi && x < width; x++) {
    if (topRow[x] > notchRow) notchRow = topRow[x];
  }
  // full-width deepest top, excluding a 10% margin on each side (corners)
  const fLo = Math.floor(width * 0.10), fHi = Math.ceil(width * 0.90);
  let fullNotchRow = -1, fullNotchCol = -1;
  for (let x = fLo; x <= fHi && x < width; x++) {
    if (topRow[x] > fullNotchRow) { fullNotchRow = topRow[x]; fullNotchCol = x; }
  }
  // bottom-most opaque row (hem)
  let overallBottom = -1;
  for (let x = 0; x < width; x++) {
    for (let y = height - 1; y >= 0; y--) {
      if (alphaAt(img, x, y) > 10) { overallBottom = Math.max(overallBottom, y); break; }
    }
  }
  return { width, height, overallTop, notchRow, overallBottom,
    overallTopFrac: overallTop / height,
    notchFrac: notchRow >= 0 ? notchRow / height : -1,
    bottomFrac: overallBottom / height,
    fullNotchFrac: fullNotchRow >= 0 ? fullNotchRow / height : -1,
    fullNotchColFrac: fullNotchCol >= 0 ? fullNotchCol / width : -1 };
}

const views = ['front', 'back', 'left'];
for (const view of views) {
  for (let i = 1; i <= 9; i++) {
    const p = `${view}/body_${String(i).padStart(2, '0')}.png`;
    if (!fs.existsSync(p)) continue;
    const r = analyze(p);
    console.log(`${p}: ${r.width}x${r.height} top=${r.overallTopFrac.toFixed(3)} notch=${r.notchFrac.toFixed(3)} fullNotch=${r.fullNotchFrac.toFixed(3)}@${r.fullNotchColFrac.toFixed(2)} bottom=${r.bottomFrac.toFixed(3)}`);
  }
}
