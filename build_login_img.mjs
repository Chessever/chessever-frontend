// ChessEver LOGIN logo -> assets/lottie/chessever_logo.json
// 1:1 identical to assets/pngs/chessever.png: embeds the REAL trimmed logo
// artwork as a Lottie image asset (no vector approximation). Animation lives
// purely on the layer transform -> tasteful, never distorts the mark.
//   entrance: soft spring pop (fade + scale overshoot + tiny rotate) ONCE
//   idle:     calm breathing + gentle float, loops from frame ~48
import { readFileSync, writeFileSync } from 'fs';

const MARK = '/Users/berkay/projects/chessever-frontend/assets/pngs/chessever.png'; // full original
const OUT = '/Users/berkay/projects/chessever-frontend/assets/lottie/chessever_logo.json';
const IW = 1180, IH = 624;             // native artwork size (matches old login image aspect)
const W = 1180, H = 680;               // comp adds vertical pad so breathing never clips
const CX = W / 2, CY = H / 2;
const FR = 60, OP = 180;
const eo = { x: [0.34], y: [0] };
const ei = { x: [0.66], y: [1] };
const kf = (l) => l.map((k, i) => i === l.length - 1 ? { t: k.t, s: k.s } : { t: k.t, s: k.s, o: eo, i: ei });

const b64 = readFileSync(MARK).toString('base64');

const doc = {
  v: '5.7.0', fr: FR, ip: 0, op: OP, w: W, h: H, nm: 'chessever-login',
  assets: [
    { id: 'logo', w: IW, h: IH, u: '', p: 'data:image/png;base64,' + b64, e: 1 },
  ],
  layers: [
    {
      ty: 2, refId: 'logo', nm: 'logo', ip: 0, op: OP, st: 0,
      ks: {
        o: { a: 1, k: kf([{ t: 0, s: [0] }, { t: 28, s: [100] }, { t: 180, s: [100] }]) },
        r: { a: 1, k: kf([{ t: 0, s: [-6] }, { t: 40, s: [1.5] }, { t: 54, s: [0] }, { t: 180, s: [0] }]) },
        p: { a: 1, k: kf([
          { t: 0, s: [CX, CY, 0] }, { t: 48, s: [CX, CY, 0] },
          { t: 110, s: [CX, CY - 6, 0] }, { t: 172, s: [CX, CY, 0] }, { t: 180, s: [CX, CY, 0] },
        ]) },
        a: { a: 0, k: [IW / 2, IH / 2, 0] },
        s: { a: 1, k: kf([
          { t: 0, s: [62, 62, 100] }, { t: 34, s: [104, 104, 100] }, { t: 48, s: [100, 100, 100] },
          { t: 110, s: [102.5, 102.5, 100] }, { t: 170, s: [100, 100, 100] }, { t: 180, s: [100, 100, 100] },
        ]) },
      },
    },
  ],
};

writeFileSync(OUT, JSON.stringify(doc));
console.log('wrote', OUT, '— embedded real artwork', IW + 'x' + IH, 'b64 KB ~', Math.round(b64.length / 1024));
