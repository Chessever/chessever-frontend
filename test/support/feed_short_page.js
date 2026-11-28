// The Shorts players' page (feedShortPlayerHtml) keeps a Short playing by
// itself: a play that is not taken is asked again, one refused with sound
// plays muted and asks for its sound back, a Short the viewer paused stays
// paused. Its script is run here against a stand-in for YouTube's player,
// on a clock the scenes move by hand.
//
// Run by test/feed_short_page_script_test.dart, which writes the page to a
// file and hands its path over.

const fs = require('fs');
const vm = require('vm');
const assert = require('assert');

const page = fs.readFileSync(process.argv[2], 'utf8');
const script = page.match(/<script>([\s\S]*?)<\/script>/)[1];

function world(policy = {}) {
  let now = 0, seq = 0;
  const timers = new Map();
  const messages = [];
  const env = { policy, player: null, messages };
  const setT = (fn, ms) => { const id = ++seq; timers.set(id, { at: now + ms, fn, every: 0 }); return id; };
  const setI = (fn, ms) => { const id = ++seq; timers.set(id, { at: now + ms, fn, every: ms }); return id; };
  const clear = (id) => { timers.delete(id); };
  env.advance = (ms) => {
    const end = now + ms;
    for (;;) {
      let next = null, nextId = null;
      for (const [id, t] of timers) if (t.at <= end && (next === null || t.at < next.at)) { next = t; nextId = id; }
      if (!next) break;
      now = next.at;
      if (next.every) next.at = now + next.every; else timers.delete(nextId);
      next.fn();
    }
    now = end;
  };
  class Player {
    constructor(el, opts) {
      this.opts = opts; this.videoId = opts.videoId; this.state = 5; this.m = false; this.calls = [];
      env.player = this;
      setT(() => opts.events.onReady({}), 300);
    }
    getPlayerState() { return this.state; }
    isMuted() { return this.m; }
    mute() { this.calls.push('mute'); this.m = true; }
    unMute() { this.calls.push('unMute'); this.m = false; if (policy.unmutePauses && this.state === 1) this.set(2); }
    playVideo() {
      this.calls.push('play');
      if (policy.blockAll) return;
      if (policy.blockSound && !this.m) { if (policy.fireBlocked) setT(() => this.opts.events.onAutoplayBlocked({}), 50); return; }
      if (this.state === 1) return;
      this.set(3);
      setT(() => { if (this.state === 3) this.set(1); }, policy.buffer ?? 200);
    }
    pauseVideo() { this.calls.push('pause'); if (this.state === 1 || this.state === 3) this.set(2); }
    stopVideo() { this.calls.push('stop'); this.set(-1); }
    cueVideoById(id) { this.calls.push('cue:' + id); this.videoId = id; this.set(5); }
    loadVideoById(id) { this.calls.push('load:' + id); this.videoId = id; this.state = 5; this.playVideo(); }
    seekTo(t) { this.calls.push('seek:' + t); }
    set(s) { this.state = s; this.opts.events.onStateChange({ data: s }); }
  }
  const sandbox = {
    ChessShort: { postMessage: (m) => messages.push(JSON.parse(m)) },
    setTimeout: setT, clearTimeout: clear, setInterval: setI,
    Date: { now: () => now }, JSON, Object, YT: { Player },
  };
  sandbox.window = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(script, sandbox);
  env.order = (id, on, snd) => sandbox.chessShort(id, on, snd);
  env.apiReady = () => sandbox.onYouTubeIframeAPIReady();
  env.types = () => messages.map((m) => m.type);
  env.last = (type) => [...messages].reverse().find((m) => m.type === type);
  env.plays = () => env.player.calls.filter((c) => c === 'play').length;
  return env;
}
const results = [];
function scene(name, fn) { try { fn(); results.push('ok   ' + name); } catch (e) { results.push('FAIL ' + name + '\n     ' + e.message); process.exitCode = 1; } }

scene('says ready once the API is up, makes no player before a Short is named', () => {
  const w = world(); w.apiReady();
  assert.deepStrictEqual(w.types(), ['ready']); assert.strictEqual(w.player, null);
});
scene('plays the Short in view with sound', () => {
  const w = world(); w.apiReady(); w.order('a', true, true);
  assert.strictEqual(w.player.videoId, 'a'); assert.strictEqual(w.player.opts.playerVars.autoplay, 0);
  assert.strictEqual(w.player.opts.playerVars.origin, 'https://embed.test.example.com');
  assert.strictEqual(w.player.opts.playerVars.playsinline, 1);
  w.advance(600);
  assert.strictEqual(w.player.state, 1); assert.strictEqual(w.player.m, false);
  assert.strictEqual(w.last('playing').id, 'a'); assert.strictEqual(w.last('sound'), undefined);
  w.advance(20000); assert.strictEqual(w.plays(), 1, 'no further play once it plays');
});
scene('a Short only held is cued, never played', () => {
  const w = world(); w.apiReady(); w.order('a', false, true); w.advance(5000);
  assert.strictEqual(w.plays(), 0); assert.strictEqual(w.player.state, 5); assert.strictEqual(w.last('playing'), undefined);
  w.order('a', true, true); w.advance(400);
  assert.strictEqual(w.player.state, 1); assert.strictEqual(w.last('playing').id, 'a');
});
scene('sound refused without a word: plays muted, sound stays off', () => {
  const w = world({ blockSound: true, unmutePauses: true }); w.apiReady(); w.order('a', true, true);
  w.advance(1700); assert.strictEqual(w.player.state, 5, 'the play with sound was not taken');
  w.advance(200); assert.strictEqual(w.player.state, 3, 'asked again muted after 1.5s');
  w.advance(300); assert.strictEqual(w.player.state, 1); assert.strictEqual(w.player.m, true);
  w.advance(4000);
  assert.strictEqual(w.player.state, 1, 'still playing after the sound was asked back');
  assert.strictEqual(w.player.m, true); assert.deepStrictEqual(w.last('sound'), { type: 'sound', id: 'a', on: false });
  const plays = w.plays(); w.advance(20000); assert.strictEqual(w.plays(), plays, 'settled');
});
scene('sound refused, said so by the player: falls back at once', () => {
  const w = world({ blockSound: true, fireBlocked: true, unmutePauses: true }); w.apiReady(); w.order('a', true, true);
  w.advance(300 + 50 + 250);
  assert.strictEqual(w.player.state, 1, 'playing well before the 1.5s wait'); assert.strictEqual(w.player.m, true);
});
scene('sound refused only at the start: it is back once the picture moves', () => {
  const w = world({ blockSound: true }); w.apiReady(); w.order('a', true, true);
  w.advance(2200); assert.strictEqual(w.player.state, 1); assert.strictEqual(w.player.m, true);
  w.advance(2000);
  assert.strictEqual(w.player.state, 1); assert.strictEqual(w.player.m, false);
  assert.deepStrictEqual(w.last('sound'), { type: 'sound', id: 'a', on: true });
});
scene('told to start muted: never asks for sound', () => {
  const w = world(); w.apiReady(); w.order('a', true, false); w.advance(5000);
  assert.strictEqual(w.player.state, 1); assert.strictEqual(w.player.m, true);
  assert(!w.player.calls.includes('unMute')); assert.strictEqual(w.last('sound'), undefined);
});
scene('a Short the viewer paused stays paused, the same order said again too', () => {
  const w = world(); w.apiReady(); w.order('a', true, true); w.advance(600);
  w.player.set(2); assert.strictEqual(w.last('idle').state, 2);
  const plays = w.plays(); w.advance(15000); w.order('a', true, true); w.order('a', true, false); w.advance(15000);
  assert.strictEqual(w.plays(), plays); assert.strictEqual(w.player.state, 2);
});
scene('left and come back to: paused, then playing again from where it was', () => {
  const w = world(); w.apiReady(); w.order('a', true, true); w.advance(600);
  w.order('a', false, true); assert.strictEqual(w.player.state, 2);
  w.advance(9000); assert.strictEqual(w.player.state, 2);
  w.order('a', true, true); w.advance(400);
  assert.strictEqual(w.player.state, 1); assert(!w.player.calls.some((c) => c.startsWith('load:') || c.startsWith('cue:')), 'no reload');
});
scene('takes the next Short in the same player: cued, then played', () => {
  const w = world(); w.apiReady(); w.order('a', true, true); w.advance(600);
  w.order('b', false, true);
  assert.strictEqual(w.player.calls.at(-1), 'cue:b'); assert.strictEqual(w.player.state, 5);
  w.advance(3000); assert.strictEqual(w.player.state, 5, 'a cued Short does not start by itself');
  w.order('b', true, true); w.advance(400);
  assert.strictEqual(w.player.state, 1); assert.strictEqual(w.last('playing').id, 'b');
});
scene('another Short straight into view: loaded and playing', () => {
  const w = world(); w.apiReady(); w.order('a', true, true); w.advance(600);
  w.order('b', true, true); assert(w.player.calls.includes('load:b'));
  w.advance(400); assert.strictEqual(w.player.state, 1); assert.strictEqual(w.last('playing').id, 'b');
});
scene('a Short that ends starts over while in view', () => {
  const w = world(); w.apiReady(); w.order('a', true, true); w.advance(600);
  w.player.set(0); assert(w.player.calls.includes('seek:0')); w.advance(400);
  assert.strictEqual(w.player.state, 1);
});
scene('a Short starting while out of view is stopped', () => {
  const w = world(); w.apiReady(); w.order('a', false, true); w.advance(600);
  w.player.set(1); assert.strictEqual(w.player.state, 2); assert.strictEqual(w.last('playing'), undefined);
});
scene('the viewer muting, then unmuting, a Short is reported', () => {
  const w = world(); w.apiReady(); w.order('a', true, true); w.advance(4000);
  w.player.m = true; w.advance(1500); assert.deepStrictEqual(w.last('sound'), { type: 'sound', id: 'a', on: false });
  w.player.m = false; w.advance(1500); assert.deepStrictEqual(w.last('sound'), { type: 'sound', id: 'a', on: true });
});
scene('parked: the video is let go', () => {
  const w = world(); w.apiReady(); w.order('a', true, true); w.advance(600);
  w.order(null, false, true); assert(w.player.calls.includes('stop'));
  w.order('c', false, true); assert.strictEqual(w.player.calls.at(-1), 'cue:c');
});
scene('nothing plays at all: asked a bounded number of times, then stalled', () => {
  const w = world({ blockAll: true }); w.apiReady(); w.order('a', true, true); w.advance(60000);
  assert.strictEqual(w.last('stalled').id, 'a'); assert(w.plays() <= 8, 'plays ' + w.plays());
  const plays = w.plays(); w.advance(60000); assert.strictEqual(w.plays(), plays);
});
scene('a slow start is waited for, not asked again', () => {
  const w = world({ buffer: 9000 }); w.apiReady(); w.order('a', true, true); w.advance(8000);
  assert.strictEqual(w.plays(), 1); assert.strictEqual(w.player.m, false);
  w.advance(2000); assert.strictEqual(w.player.state, 1); assert.strictEqual(w.last('sound'), undefined);
});
scene('a YouTube error names its Short', () => {
  const w = world(); w.apiReady(); w.order('a', true, true); w.advance(600);
  w.player.opts.events.onError({ data: 150 });
  assert.deepStrictEqual(w.last('error'), { type: 'error', id: 'a', code: 150 });
});
console.log(results.join('\n'));
