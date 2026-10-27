// Knight's Tour — premium chess Lottie generator (Skottie-safe)
import fs from 'fs';

const W = 512, H = 512, FR = 60, OP = 300;
const CELL = 80, BASE = 96;            // 5x5 grid centered in 512
const px = (c, r) => [BASE + c * CELL, BASE + r * CELL];

// Brand
const CYAN = [0.0588, 0.7059, 0.8980]; // #0FB4E5  (accent slot default)
const BG   = [0.0471, 0.0471, 0.0549]; // #0C0C0E
const CORE = [0.72, 0.97, 1.0];        // bright comet core

// A real knight's tour fragment — every step is a legal L-move
const TOUR = [[0,0],[2,1],[4,0],[3,2],[4,4],[2,3],[0,4],[1,2]];
const NODES = TOUR.map(([c,r]) => px(c,r));

// Timeline
const T_INTRO = 36;        // grid + glow fade-in
const T_START = 42;        // comet begins
const MOVE_DUR = 30;       // frames per knight move
const N_MOVES = NODES.length - 1;
const T_END = T_START + N_MOVES * MOVE_DUR;  // comet arrives at last node
const T_HOLD = T_END + 22;                   // full trail glows
const T_FADE = OP;                           // everything dissolves -> loop

// ---- ease helpers ----
const eOut = { x: [0.33], y: [0] }, eIn = { x: [0.66], y: [1] };
const smooth = (t, s) => ({ t, s, i: eIn, o: eOut });
const linK  = (t, s) => ({ t, s, i: { x:[0.5],y:[0.5] }, o: { x:[0.5],y:[0.5] } });
const last  = (t, s) => ({ t, s });
const dist = (a, b) => Math.hypot(a[0]-b[0], a[1]-b[1]);

// ---- build the polyline (node, corner, node, corner, ...) ----
const verts = [{ p: NODES[0], t: T_START, cum: 0 }];
let cum = 0;
for (let m = 0; m < N_MOVES; m++) {
  const A = NODES[m], B = NODES[m+1];
  const dx = B[0]-A[0], dy = B[1]-A[1];
  const corner = Math.abs(dx) >= Math.abs(dy) ? [B[0], A[1]] : [A[0], B[1]]; // L: long axis first
  const dAC = dist(A, corner), dCB = dist(corner, B), dAB = dAC + dCB;
  const startF = T_START + m * MOVE_DUR;
  const cornerF = startF + MOVE_DUR * (dAC / dAB);
  const endF = startF + MOVE_DUR;
  cum += dAC; verts.push({ p: corner, t: cornerF, cum });
  cum += dCB; verts.push({ p: B, t: endF, cum });
}
const TOTAL = cum;

// comet position keyframes: ease (hop) at real nodes, glide through corners
const cometKeys = verts.map((v, i) => {
  const isNode = (i === 0) || (i % 2 === 0);
  if (i === verts.length - 1) return last(Math.round(v.t), [...v.p, 0]);
  return (isNode ? smooth : linK)(Math.round(v.t), [...v.p, 0]);
});

// trim-end keyframes (arc-length synced so the line draws exactly under the comet)
const trimKeys = [
  { t: 0, s: [0], i: eIn, o: eOut },
  ...verts.map((v, i) => {
    const val = [ (v.cum / TOTAL) * 100 ];
    if (i === verts.length - 1) return last(Math.round(v.t), val);
    return { t: Math.round(v.t), s: val, i: { x:[0.5],y:[0.5] }, o: { x:[0.5],y:[0.5] } };
  }),
];

// ---------- shape factories ----------
const tr = (p=[0,0], extra={}) => ({ ty:'tr', p:{a:0,k:p}, a:{a:0,k:[0,0]}, s:{a:0,k:[100,100]}, r:{a:0,k:0}, o:{a:0,k:100}, ...extra });
const fillSid = (sid) => ({ ty:'fl', c:{ sid }, o:{a:0,k:100} });
const fillRGBA = (rgb,a=1,o=100) => ({ ty:'fl', c:{a:0,k:[...rgb,a]}, o:{a:0,k:o} });
const strokeSid = (sid, w) => ({ ty:'st', c:{ sid }, o:{a:0,k:100}, w:{a:0,k:w}, lc:2, lj:2, ml:4 });
const ellip = (s) => ({ ty:'el', p:{a:0,k:[0,0]}, s:{a:0,k:[s,s]} });

const grp = (it, nm='g') => ({ ty:'gr', nm, it });

function shapeLayer(nm, shapes, ks={}, ip=0, op=OP) {
  return { ty:4, nm, ip, op, st:0,
    ks:{ o:ks.o??{a:0,k:100}, r:ks.r??{a:0,k:0}, p:ks.p??{a:0,k:[256,256,0]},
         a:ks.a??{a:0,k:[0,0,0]}, s:ks.s??{a:0,k:[100,100,100]} },
    shapes };
}

const layers = [];

// ===== comet tail echoes (under core) =====
function echo(offset, size, op) {
  const keys = cometKeys.map(k => {
    const t = Math.min(OP, k.t + offset);
    return k.i ? { ...k, t } : { t, s: k.s };
  });
  return shapeLayer(`tail+${offset}`,
    [ grp([ ellip(size), fillSid('accentColor'),
            tr([0,0],{ o:{a:0,k:op} }) ]) ],
    { p:{a:1,k:keys},
      o:{a:1,k:[ {t:T_START-2,s:[0],i:eIn,o:eOut}, {t:T_START+offset+2,s:[op]},
                 {t:T_END+offset,s:[op],i:eIn,o:eOut}, last(T_END+offset+14,[0]) ]} },
    0, OP);
}
layers.push(echo(10, 16, 22));
layers.push(echo(5, 22, 30));

// ===== comet halo =====
layers.push(shapeLayer('comet-halo',
  [ grp([ ellip(46), fillSid('accentColor'), tr([0,0],{ o:{a:0,k:38} }) ]) ],
  { p:{a:1,k:cometKeys},
    o:{a:1,k:[ {t:T_START-3,s:[0],i:eIn,o:eOut}, {t:T_START+3,s:[55]},
               {t:T_HOLD,s:[55],i:eIn,o:eOut}, last(OP,[0]) ]} }));

// ===== comet core =====
layers.push(shapeLayer('comet-core',
  [ grp([ ellip(15), fillRGBA(CORE,1),
          grp([ ellip(7) ], 'spark'), fillRGBA([1,1,1],1),
          tr() ]) ],
  { p:{a:1,k:cometKeys},
    o:{a:1,k:[ {t:T_START-2,s:[0],i:eIn,o:eOut}, {t:T_START+2,s:[100]},
               {t:T_HOLD,s:[100],i:eIn,o:eOut}, last(OP,[0]) ]} }));

// ===== trail line (single polyline, trim drawn-on, glow via double stroke) =====
const linePts = verts.map(v => v.p);
const pathObj = { ty:'sh', ks:{ a:0, k:{
  c:false,
  v: linePts,
  i: linePts.map(()=>[0,0]),
  o: linePts.map(()=>[0,0]),
} } };
const trimMod = { ty:'tm', s:{a:0,k:0}, e:{a:1,k:trimKeys}, o:{a:0,k:0}, m:1 };
// soft wide glow stroke
layers.push(shapeLayer('trail-glow',
  [ grp([ pathObj, trimMod, strokeSid('accentColor', 14), tr() ]) ],
  { p:{a:0,k:[0,0,0]},
    o:{a:1,k:[ {t:T_START,s:[28],i:eIn,o:eOut}, {t:T_HOLD,s:[28],i:eIn,o:eOut}, last(OP,[0]) ]} }));
// crisp core stroke
layers.push(shapeLayer('trail-line',
  [ grp([ pathObj, trimMod, strokeSid('accentColor', 3.5), tr() ]) ],
  { p:{a:0,k:[0,0,0]},
    o:{a:1,k:[ {t:T_START,s:[100],i:eIn,o:eOut}, {t:T_HOLD,s:[100],i:eIn,o:eOut}, last(OP,[0]) ]} }));

// ===== per-node arrival: bright dot + expanding ring =====
NODES.forEach((n, i) => {
  const arrive = Math.round(T_START + i * MOVE_DUR);
  // bright landed dot
  layers.push(shapeLayer(`node-dot-${i}`,
    [ grp([ ellip(13), fillSid('accentColor'), tr() ]) ],
    { p:{a:0,k:[...n,0]},
      o:{a:1,k:[ {t:Math.max(0,arrive-1),s:[0],i:eIn,o:eOut}, {t:arrive+6,s:[100]},
                 {t:T_HOLD,s:[100],i:eIn,o:eOut}, last(OP,[0]) ]} }));
  // expanding shockwave ring
  layers.push(shapeLayer(`node-ring-${i}`,
    [ grp([ ellip(20), strokeSid('accentColor', 2.5), tr() ]) ],
    { p:{a:0,k:[...n,0]},
      s:{a:1,k:[ {t:arrive,s:[30,30,100],i:eIn,o:eOut}, last(arrive+26,[210,210,100]) ]},
      o:{a:1,k:[ {t:arrive,s:[85],i:eIn,o:eOut}, last(arrive+26,[0]) ]} }));
});

// ===== faint board: 5x5 dim node grid =====
const gridIt = [];
for (let c = 0; c < 5; c++) for (let r = 0; r < 5; r++) {
  const [x,y] = px(c,r);
  gridIt.push(grp([ ellip(7), fillRGBA(CYAN, 1), tr([x-256, y-256]) ], `d${c}${r}`));
}
layers.push(shapeLayer('grid',
  [ grp(gridIt, 'grid-all') ],
  { p:{a:0,k:[256,256,0]},
    o:{a:1,k:[ {t:0,s:[0],i:eIn,o:eOut}, last(T_INTRO,[22]) ]} }));

// ===== center radial glow (depth) =====
layers.push(shapeLayer('center-glow',
  [ grp([
      ellip(460),
      { ty:'gf', t:2,
        s:{a:0,k:[0,0]}, e:{a:0,k:[230,0]},
        g:{ p:2, k:{ a:0, k:[ 0, ...CYAN, 1, ...CYAN, /*alpha*/ 0, 1, 1, 0 ] } },
        o:{a:0,k:100} },
      tr() ]) ],
  { p:{a:0,k:[256,256,0]},
    s:{a:1,k:[ {t:0,s:[92,92,100],i:eIn,o:eOut}, {t:150,s:[104,104,100],i:eIn,o:eOut}, last(OP,[92,92,100]) ]},
    o:{a:1,k:[ {t:0,s:[0],i:eIn,o:eOut}, {t:T_INTRO+10,s:[60]},
               {t:150,s:[78],i:eIn,o:eOut}, {t:OP,s:[60]} ]} }));

// ===== required background =====
layers.push(shapeLayer('background',
  [ grp([ { ty:'rc', p:{a:0,k:[256,256]}, s:{a:0,k:[W,H]}, r:{a:0,k:0} },
          fillSid('bgColor'), tr() ]) ],
  { p:{a:0,k:[0,0,0]} }));

const doc = {
  v:'5.7.0', fr:FR, ip:0, op:OP, w:W, h:H, nm:'Knight Tour', assets:[],
  slots: {
    accentColor: { p:{ a:0, k:[...CYAN, 1] } },
    bgColor:     { p:{ a:0, k:[...BG, 1] } },
  },
  layers,
};

fs.writeFileSync('public/lottie.json', JSON.stringify(doc));
const controls = { controls: [
  { sid:'accentColor', label:'Accent (trail / pieces)' },
  { sid:'bgColor', label:'Background color' },
] };
fs.writeFileSync('public/controls.json', JSON.stringify(controls, null, 2));
console.log('moves', N_MOVES, 'verts', verts.length, 'layers', layers.length,
  'T_END', T_END, 'T_HOLD', T_HOLD, 'bytes', fs.statSync('public/lottie.json').size);
