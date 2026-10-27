const path = require('path');
const fs = require('fs');
const CanvasKitInit = require('canvaskit-wasm/bin/full/canvaskit.js');

const DIR = path.join(__dirname, 'node_modules/canvaskit-wasm/bin/full');
const frames = process.argv.slice(2).map(Number);
const FR = frames.length ? frames : [0, 42, 90, 160, 220, 252, 290];

CanvasKitInit({ locateFile: (f) => path.join(DIR, f) }).then((CK) => {
  const json = fs.readFileSync(path.join(__dirname, 'public/lottie.json'), 'utf8');
  const anim = CK.MakeManagedAnimation(json);
  if (!anim) { console.error('FAILED to parse'); process.exit(1); }
  const W = 512, H = 512;
  const surface = CK.MakeSurface(W, H);
  const canvas = surface.getCanvas();
  for (const f of FR) {
    anim.seekFrame(f);
    canvas.clear(CK.BLACK);
    anim.render(canvas, CK.LTRBRect(0, 0, W, H));
    surface.flush();
    const img = surface.makeImageSnapshot();
    const png = img.encodeToBytes();
    fs.writeFileSync(path.join(__dirname, `frame_${String(f).padStart(3,'0')}.png`), Buffer.from(png));
    img.delete();
    console.log('rendered frame', f);
  }
  anim.delete();
  surface.delete();
});
