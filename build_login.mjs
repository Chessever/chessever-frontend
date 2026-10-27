// ChessEver LOGIN logo variant -> assets/lottie/chessever_logo.json
// IMPORTANT: targets the Flutter `lottie` (Dart) runtime, NOT Skottie.
//  - NO slots / "sid" (Dart lottie can't parse them -> RangeError). Inline colors.
//  - NO background layer -> fully transparent, blur shows through.
//  - BLACK king on a CYAN center tile (matches assets/pngs/chessever.png)
//  - assemble ONCE then a calm idle loop (frames 70..180), no disassemble
import { writeFileSync } from 'fs';

const OUT = '/Users/berkay/projects/chessever-frontend/assets/lottie/chessever_logo.json';
const FR = 60, OP = 180, W = 512, H = 512;
const CYAN = [0.059, 0.706, 0.898, 1];
const BLACK = [0.05, 0.05, 0.06, 1];
const eo = { x: [0.34], y: [0] };
const ei = { x: [0.66], y: [1] };
const kf = (l) => l.map((k, i) => i === l.length - 1 ? { t: k.t, s: k.s } : { t: k.t, s: k.s, o: eo, i: ei });
const fill = (c) => ({ ty: 'fl', c: { a: 0, k: c }, o: { a: 0, k: 100 } });

function square(nm, delay, fx, fy, cx, cy, rr) {
  return {
    ty: 4, nm, ip: 0, op: OP, st: 0,
    ks: {
      o: { a: 1, k: kf([{ t: delay, s: [0] }, { t: delay + 16, s: [100] }, { t: 180, s: [100] }]) },
      r: { a: 1, k: kf([{ t: delay, s: [rr] }, { t: delay + 20, s: [-rr * 0.22] }, { t: delay + 30, s: [0] }, { t: 180, s: [0] }]) },
      p: { a: 1, k: kf([{ t: delay, s: [cx, cy, 0] }, { t: delay + 28, s: [fx, fy, 0] }, { t: 180, s: [fx, fy, 0] }]) },
      a: { a: 0, k: [0, 0, 0] },
      s: { a: 1, k: kf([
        { t: delay, s: [30, 30, 100] }, { t: delay + 20, s: [113, 113, 100] }, { t: delay + 30, s: [100, 100, 100] },
        { t: 78, s: [100, 100, 100] }, { t: 110, s: [105, 105, 100] }, { t: 144, s: [100, 100, 100] }, { t: 180, s: [100, 100, 100] },
      ]) },
    },
    shapes: [{ ty: 'gr', nm: nm + '-g', it: [
      { ty: 'rc', p: { a: 0, k: [0, 0] }, s: { a: 0, k: [150, 150] }, r: { a: 0, k: 34 } },
      fill(CYAN),
      { ty: 'tr', p: { a: 0, k: [0, 0] }, a: { a: 0, k: [0, 0] }, s: { a: 0, k: [100, 100] }, r: { a: 0, k: 0 }, o: { a: 0, k: 100 } },
    ] }],
  };
}

const tile = {
  ty: 4, nm: 'center-tile', ip: 0, op: OP, st: 0,
  ks: {
    o: { a: 1, k: kf([{ t: 0, s: [0] }, { t: 38, s: [0] }, { t: 54, s: [100] }, { t: 180, s: [100] }]) },
    r: { a: 0, k: 0 }, p: { a: 0, k: [256, 256, 0] }, a: { a: 0, k: [0, 0, 0] },
    s: { a: 1, k: kf([
      { t: 38, s: [0, 0, 100] }, { t: 52, s: [118, 118, 100] }, { t: 62, s: [100, 100, 100] },
      { t: 110, s: [104, 104, 100] }, { t: 144, s: [100, 100, 100] }, { t: 180, s: [100, 100, 100] },
    ]) },
  },
  shapes: [{ ty: 'gr', it: [
    { ty: 'rc', p: { a: 0, k: [0, 0] }, s: { a: 0, k: [104, 104] }, r: { a: 0, k: 26 } },
    fill(CYAN),
    { ty: 'tr', p: { a: 0, k: [0, 0] }, a: { a: 0, k: [0, 0] }, s: { a: 0, k: [100, 100] }, r: { a: 0, k: 0 }, o: { a: 0, k: 100 } },
  ] }],
};

const king = {
  ty: 4, nm: 'king', ip: 0, op: OP, st: 0,
  ks: {
    o: { a: 1, k: kf([{ t: 0, s: [0] }, { t: 48, s: [0] }, { t: 64, s: [100] }, { t: 180, s: [100] }]) },
    r: { a: 0, k: 0 },
    p: { a: 1, k: kf([{ t: 64, s: [256, 256, 0] }, { t: 108, s: [256, 251, 0] }, { t: 152, s: [256, 256, 0] }, { t: 180, s: [256, 256, 0] }]) },
    a: { a: 0, k: [0, 0, 0] },
    s: { a: 1, k: kf([{ t: 48, s: [0, 0, 100] }, { t: 62, s: [122, 122, 100] }, { t: 72, s: [100, 100, 100] }, { t: 180, s: [100, 100, 100] }]) },
  },
  shapes: [{ ty: 'gr', nm: 'king-g', it: [
    { ty: 'rc', p: { a: 0, k: [0, -58] }, s: { a: 0, k: [8, 22] }, r: { a: 0, k: 2 } },
    { ty: 'rc', p: { a: 0, k: [0, -60] }, s: { a: 0, k: [22, 8] }, r: { a: 0, k: 2 } },
    { ty: 'el', p: { a: 0, k: [0, -42] }, s: { a: 0, k: [26, 26] } },
    { ty: 'rc', p: { a: 0, k: [0, -26] }, s: { a: 0, k: [28, 9] }, r: { a: 0, k: 4 } },
    { ty: 'sh', ks: { a: 0, k: {
      c: true,
      v: [[-11,-22],[-23,12],[-13,26],[-21,46],[21,46],[13,26],[23,12],[11,-22]],
      i: [[0,0],[-1,-7],[-5,-3],[-4,-7],[0,0],[-4,3],[2,7],[3,7]],
      o: [[-3,7],[2,7],[4,3],[0,0],[4,-7],[5,-3],[-1,-7],[0,0]],
    } } },
    { ty: 'rc', p: { a: 0, k: [0, 50] }, s: { a: 0, k: [46, 12] }, r: { a: 0, k: 4 } },
    fill(BLACK),
    { ty: 'tr', p: { a: 0, k: [0, 0] }, a: { a: 0, k: [0, 0] }, s: { a: 0, k: [100, 100] }, r: { a: 0, k: 0 }, o: { a: 0, k: 100 } },
  ] }],
};

const ring = {
  ty: 4, nm: 'glow-ring', ip: 0, op: OP, st: 0,
  ks: {
    o: { a: 1, k: kf([{ t: 0, s: [0] }, { t: 74, s: [0] }, { t: 84, s: [50] }, { t: 130, s: [0] }, { t: 180, s: [0] }]) },
    r: { a: 0, k: 0 }, p: { a: 0, k: [256, 256, 0] }, a: { a: 0, k: [0, 0, 0] },
    s: { a: 1, k: kf([{ t: 74, s: [50, 50, 100] }, { t: 130, s: [185, 185, 100] }, { t: 180, s: [50, 50, 100] }]) },
  },
  shapes: [{ ty: 'gr', it: [
    { ty: 'el', p: { a: 0, k: [0, 0] }, s: { a: 0, k: [150, 150] } },
    { ty: 'st', c: { a: 0, k: CYAN }, o: { a: 0, k: 100 }, w: { a: 0, k: 7 }, lc: 2, lj: 1 },
    { ty: 'tr', p: { a: 0, k: [0, 0] }, a: { a: 0, k: [0, 0] }, s: { a: 0, k: [100, 100] }, r: { a: 0, k: 0 }, o: { a: 0, k: 100 } },
  ] }],
};

const doc = {
  v: '5.7.0', fr: FR, ip: 0, op: OP, w: W, h: H, nm: 'chessever-login', assets: [],
  layers: [
    king, ring,
    square('sq-TL', 0,  155, 155, 238, 238, -16),
    square('sq-TR', 6,  357, 155, 274, 238,  16),
    square('sq-BL', 12, 155, 357, 238, 274,  16),
    square('sq-BR', 18, 357, 357, 274, 274, -16),
    tile,
  ],
};

writeFileSync(OUT, JSON.stringify(doc));
console.log('wrote', OUT, '— no slots, inline colors, no bg layer');
