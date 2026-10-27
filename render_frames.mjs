// Render specific frames of public/lottie.json to PNG via Skottie (CanvasKit full build)
import { readFileSync, writeFileSync } from 'fs';
import { createRequire } from 'module';
const require = createRequire(import.meta.url);
const CanvasKitInit = require('canvaskit-wasm/bin/full/canvaskit.js');

const SIZE = 512;
const json = readFileSync(new URL('./public/lottie.json', import.meta.url), 'utf8');
const frames = process.argv.slice(2).map(Number);
if (!frames.length) frames.push(0, 40, 65, 110, 150);

const CanvasKit = await CanvasKitInit({
  locateFile: (f) => new URL('./node_modules/canvaskit-wasm/bin/full/' + f, import.meta.url).pathname,
});

const anim = CanvasKit.MakeManagedAnimation(json);
if (!anim) throw new Error('Skottie failed to parse lottie.json');
const fr = anim.fps();
const dur = anim.duration(); // seconds
const totalFrames = Math.round(fr * dur);
console.log('fps', fr, 'duration s', dur.toFixed(2), 'frames', totalFrames);

const surface = CanvasKit.MakeSurface(SIZE, SIZE);
const canvas = surface.getCanvas();
const bounds = CanvasKit.LTRBRect(0, 0, SIZE, SIZE);

for (const f of frames) {
  const t = totalFrames > 0 ? f / totalFrames : 0; // normalized [0,1]
  anim.seek(Math.max(0, Math.min(1, t)));
  canvas.clear(CanvasKit.TRANSPARENT);
  anim.render(canvas, bounds);
  surface.flush();
  const img = surface.makeImageSnapshot();
  const png = img.encodeToBytes();
  const out = new URL(`./frame_${f}.png`, import.meta.url).pathname;
  writeFileSync(out, png);
  img.delete();
  console.log('wrote', out);
}
anim.delete();
surface.delete();
