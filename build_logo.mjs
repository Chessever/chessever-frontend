// ChessEver animated logo generator -> public/lottie.json
import { writeFileSync } from 'fs';

const FR = 60, OP = 180, W = 512, H = 512;
const eo = { x: [0.34], y: [0] };   // out handle (ease)
const ei = { x: [0.66], y: [1] };   // in handle (ease)

// build a keyframe list; every kf except last gets ease handles
function kf(list) {
  return list.map((k, idx) =>
    idx === list.length - 1
      ? { t: k.t, s: k.s }
      : { t: k.t, s: k.s, o: eo, i: ei }
  );
}

// ---- square layer factory ----------------------------------------------
function square(nm, delay, fx, fy, cx, cy, rr) {
  return {
    ty: 4, nm, ip: 0, op: OP, st: 0,
    ks: {
      o: { a: 1, k: kf([
        { t: delay, s: [0] },
        { t: delay + 16, s: [100] },
        { t: 150, s: [100] },
        { t: 178, s: [0] },
      ]) },
      r: { a: 1, k: kf([
        { t: delay, s: [rr] },
        { t: delay + 20, s: [-rr * 0.22] },
        { t: delay + 30, s: [0] },
        { t: 158, s: [0] },
        { t: 180, s: [rr] },
      ]) },
      p: { a: 1, k: kf([
        { t: delay, s: [cx, cy, 0] },
        { t: delay + 28, s: [fx, fy, 0] },
        { t: 158, s: [fx, fy, 0] },
        { t: 180, s: [cx, cy, 0] },
      ]) },
      a: { a: 0, k: [0, 0, 0] },
      s: { a: 1, k: kf([
        { t: delay, s: [30, 30, 100] },
        { t: delay + 20, s: [113, 113, 100] },
        { t: delay + 30, s: [100, 100, 100] },
        { t: 78, s: [100, 100, 100] },
        { t: 110, s: [105, 105, 100] },
        { t: 142, s: [100, 100, 100] },
        { t: 158, s: [100, 100, 100] },
        { t: 180, s: [36, 36, 100] },
      ]) },
    },
    shapes: [{
      ty: 'gr', nm: nm + '-g', it: [
        { ty: 'rc', p: { a: 0, k: [0, 0] }, s: { a: 0, k: [150, 150] }, r: { a: 0, k: 34 } },
        { ty: 'fl', c: { sid: 'logoColor' }, o: { a: 0, k: 100 } },
        { ty: 'tr', p: { a: 0, k: [0, 0] }, a: { a: 0, k: [0, 0] }, s: { a: 0, k: [100, 100] }, r: { a: 0, k: 0 }, o: { a: 0, k: 100 } },
      ],
    }],
  };
}

// ---- king layer ---------------------------------------------------------
const king = {
  ty: 4, nm: 'king', ip: 0, op: OP, st: 0,
  ks: {
    o: { a: 1, k: kf([
      { t: 0, s: [0] }, { t: 46, s: [0] }, { t: 62, s: [100] },
      { t: 150, s: [100] }, { t: 176, s: [0] },
    ]) },
    r: { a: 0, k: 0 },
    p: { a: 1, k: kf([
      { t: 62, s: [256, 256, 0] },
      { t: 104, s: [256, 250, 0] },
      { t: 146, s: [256, 256, 0] },
    ]) },
    a: { a: 0, k: [0, 0, 0] },
    s: { a: 1, k: kf([
      { t: 46, s: [0, 0, 100] },
      { t: 60, s: [122, 122, 100] },
      { t: 70, s: [100, 100, 100] },
      { t: 150, s: [100, 100, 100] },
      { t: 180, s: [0, 0, 100] },
    ]) },
  },
  shapes: [{
    ty: 'gr', nm: 'king-g', it: [
      // crown cross
      { ty: 'rc', p: { a: 0, k: [0, -58] }, s: { a: 0, k: [8, 22] }, r: { a: 0, k: 2 } },
      { ty: 'rc', p: { a: 0, k: [0, -60] }, s: { a: 0, k: [22, 8] }, r: { a: 0, k: 2 } },
      // head
      { ty: 'el', p: { a: 0, k: [0, -42] }, s: { a: 0, k: [26, 26] } },
      // collar
      { ty: 'rc', p: { a: 0, k: [0, -26] }, s: { a: 0, k: [28, 9] }, r: { a: 0, k: 4 } },
      // goblet body
      { ty: 'sh', ks: { a: 0, k: {
        c: true,
        v: [[-11,-22],[-23,12],[-13,26],[-21,46],[21,46],[13,26],[23,12],[11,-22]],
        i: [[0,0],[-1,-7],[-5,-3],[-4,-7],[0,0],[-4,3],[2,7],[3,7]],
        o: [[-3,7],[2,7],[4,3],[0,0],[4,-7],[5,-3],[-1,-7],[0,0]],
      } } },
      // base foot
      { ty: 'rc', p: { a: 0, k: [0, 50] }, s: { a: 0, k: [46, 12] }, r: { a: 0, k: 4 } },
      { ty: 'fl', c: { sid: 'kingColor' }, o: { a: 0, k: 100 } },
      { ty: 'tr', p: { a: 0, k: [0, 0] }, a: { a: 0, k: [0, 0] }, s: { a: 0, k: [100, 100] }, r: { a: 0, k: 0 }, o: { a: 0, k: 100 } },
    ],
  }],
};

// ---- glow ring (move-pulse) --------------------------------------------
const ring = {
  ty: 4, nm: 'glow-ring', ip: 0, op: OP, st: 0,
  ks: {
    o: { a: 1, k: kf([
      { t: 0, s: [0] }, { t: 62, s: [0] }, { t: 72, s: [55] }, { t: 108, s: [0] },
      { t: 120, s: [0] }, { t: 130, s: [55] }, { t: 166, s: [0] },
    ]) },
    r: { a: 0, k: 0 },
    p: { a: 0, k: [256, 256, 0] },
    a: { a: 0, k: [0, 0, 0] },
    s: { a: 1, k: kf([
      { t: 62, s: [40, 40, 100] },
      { t: 108, s: [178, 178, 100] },
      { t: 120, s: [40, 40, 100] },
      { t: 166, s: [178, 178, 100] },
    ]) },
  },
  shapes: [{
    ty: 'gr', nm: 'ring-g', it: [
      { ty: 'el', p: { a: 0, k: [0, 0] }, s: { a: 0, k: [150, 150] } },
      { ty: 'st', c: { sid: 'glowColor' }, o: { a: 0, k: 100 }, w: { a: 0, k: 7 }, lc: 2, lj: 1 },
      { ty: 'tr', p: { a: 0, k: [0, 0] }, a: { a: 0, k: [0, 0] }, s: { a: 0, k: [100, 100] }, r: { a: 0, k: 0 }, o: { a: 0, k: 100 } },
    ],
  }],
};

// ---- background ---------------------------------------------------------
const background = {
  ty: 4, nm: 'background', ip: 0, op: OP, st: 0,
  ks: {
    o: { a: 0, k: 100 }, p: { a: 0, k: [256, 256, 0] }, a: { a: 0, k: [0, 0, 0] },
    s: { a: 0, k: [100, 100, 100] }, r: { a: 0, k: 0 },
  },
  shapes: [{
    ty: 'gr', it: [
      { ty: 'rc', p: { a: 0, k: [0, 0] }, s: { a: 0, k: [512, 512] }, r: { a: 0, k: 0 } },
      { ty: 'fl', c: { sid: 'bgColor' }, o: { a: 0, k: 100 } },
      { ty: 'tr', p: { a: 0, k: [0, 0] }, a: { a: 0, k: [0, 0] }, s: { a: 0, k: [100, 100] }, r: { a: 0, k: 0 }, o: { a: 0, k: 100 } },
    ],
  }],
};

const doc = {
  v: '5.7.0', fr: FR, ip: 0, op: OP, w: W, h: H, nm: 'chessever-logo', assets: [],
  slots: {
    bgColor:   { p: { a: 0, k: [0.039, 0.055, 0.071, 1] } },
    logoColor: { p: { a: 0, k: [0.059, 0.706, 0.898, 1] } },
    kingColor: { p: { a: 0, k: [0.18, 0.82, 0.96, 1] } },
    glowColor: { p: { a: 0, k: [0.059, 0.706, 0.898, 1] } },
  },
  layers: [
    king,
    ring,
    square('sq-TL', 0,  155, 155, 238, 238, -16),
    square('sq-TR', 6,  357, 155, 274, 238,  16),
    square('sq-BL', 12, 155, 357, 238, 274,  16),
    square('sq-BR', 18, 357, 357, 274, 274, -16),
    background,
  ],
};

writeFileSync(new URL('./public/lottie.json', import.meta.url), JSON.stringify(doc));
console.log('wrote public/lottie.json — layers:', doc.layers.length);
