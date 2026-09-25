// Minimal PNG decode/encode for 8-bit RGBA, no interlace - shared by the
// sprite tooling scripts in this folder (_analyze.js's decoder plus a
// matching encoder, split out so both read and write scripts can use it).
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
  const bpp = 4;
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

const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
    t[n] = c >>> 0;
  }
  return t;
})();

function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const typeBuf = Buffer.from(type, 'ascii');
  const lenBuf = Buffer.alloc(4);
  lenBuf.writeUInt32BE(data.length, 0);
  const crcBuf = Buffer.alloc(4);
  crcBuf.writeUInt32BE(crc32(Buffer.concat([typeBuf, data])), 0);
  return Buffer.concat([lenBuf, typeBuf, data, crcBuf]);
}

function encodePng(path, width, height, pixels) {
  const bpp = 4;
  const stride = width * bpp;
  const raw = Buffer.alloc((stride + 1) * height);
  for (let y = 0; y < height; y++) {
    raw[y * (stride + 1)] = 0; // filter type 0 (None) per row
    pixels.copy(raw, y * (stride + 1) + 1, y * stride, y * stride + stride);
  }
  const idat = zlib.deflateSync(raw, { level: 9 });

  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;   // bit depth
  ihdr[9] = 6;   // color type RGBA
  ihdr[10] = 0;  // compression
  ihdr[11] = 0;  // filter
  ihdr[12] = 0;  // interlace

  const sig = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  const out = Buffer.concat([
    sig,
    chunk('IHDR', ihdr),
    chunk('IDAT', idat),
    chunk('IEND', Buffer.alloc(0)),
  ]);
  fs.writeFileSync(path, out);
}

module.exports = { decodePng, encodePng };
