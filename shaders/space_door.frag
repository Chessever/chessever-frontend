#version 460 core

// My Space door art: square pixel blocks read from a tiny data texture.
//
// Data texture layout (width = max(cols, 10), height = rows * 3 + 1),
// sampled at texel centres with nearest filtering:
//   rows [0, rows)          rgb = block colour, a = 1 when the block exists
//   rows [rows, 2 rows)     r = opacity, g = fx * 40 / 255, b = phase, a = 1
//   rows [2 rows, 3 rows)   r = period / 8 s, g = opacity dip (0 = the fx's own)
//   row  3 rows             texel i     = ember i colour
//                           texel 5 + i = ember i (opacity, phase, period / 8)
// fx: 0 still (takes the glint), 1 pulse, 2 flicker, 3 drift down.
//
// Every uniform below is read, so none is stripped and the Dart-side float
// indices (see PixelArtView) stay valid.

#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec4 uGrid;       // 0-3   origin x, origin y, cell size, device pixel ratio
uniform vec4 uDims;       // 4-7   cols, rows, gap, corner radius
uniform vec4 uTex;        // 8-11  texture w, texture h, ember count, ember rise
uniform vec4 uAnim;       // 12-15 time s, still (0/1), glint (0 off, 1 light, 2 ink), drift amplitude
uniform vec4 uGlint;      // 16-19 art x, art y, art w + art h, ember radius
uniform vec4 uSpark0;     // 20-23 x, y, block, cyan (0/1); block 0 = off
uniform vec4 uSpark1;     // 24-27
uniform vec4 uSpark2;     // 28-31
uniform vec4 uEmber0;     // 32-35 x, y, size, unused; size 0 = off
uniform vec4 uEmber1;     // 36-39
uniform vec4 uEmber2;     // 40-43
uniform vec4 uEmber3;     // 44-47
uniform vec4 uEmber4;     // 48-51
uniform vec4 uScan;       // 52-55 y, x0, x1, thickness; thickness 0 = off
uniform vec4 uScanColor;  // 56-59 r, g, b, pulse period s
uniform sampler2D uData;

out vec4 fragColor;

const vec3 kCyan = vec3(0.0588, 0.7059, 0.8980);
// PixelPalette.light.blackPiece (#0E1A1C): the ink a paper glint deepens to.
const vec3 kInk = vec3(0.0549, 0.1020, 0.1098);

vec4 fetchData(float x, float y) {
  return texture(uData, (vec2(x, y) + 0.5) / uTex.xy);
}

// Eased triangle: 0 at the cycle start, 1 half way, back to 0. Matches a CSS
// ease-in-out keyframe that goes out and back (or an `alternate` loop whose
// period is twice the CSS duration).
float wave(float period, float phase, float t) {
  float ph = fract(t / max(period, 0.001) + phase);
  float tri = 1.0 - abs(2.0 * ph - 1.0);
  return tri * tri * (3.0 - 2.0 * tri);
}

// Anti-aliased coverage of a rounded box.
float boxCoverage(vec2 p, vec2 lo, vec2 size, float r, float aa) {
  vec2 hs = size * 0.5;
  float rr = min(r, min(hs.x, hs.y));
  vec2 q = abs(p - (lo + hs)) - (hs - rr);
  float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rr;
  return clamp(0.5 - d / aa, 0.0, 1.0);
}

// Premultiplied source-over.
vec4 over(vec4 dst, vec3 rgb, float a) {
  return vec4(rgb * a, a) + dst * (1.0 - a);
}

vec4 ember(vec4 acc, vec2 p, vec4 e, float i, float t, float still, float aa) {
  if (e.z <= 0.0) {
    return acc;
  }
  float row = uTex.y - 1.0;
  vec4 col = fetchData(i, row);
  vec4 meta = fetchData(i + 5.0, row);
  float rise = still > 0.5 ? 0.0 : uTex.w * wave(meta.b * 8.0, meta.g, t);
  float cov = boxCoverage(p, e.xy - vec2(0.0, rise), vec2(e.z), uGlint.w, aa);
  return over(acc, col.rgb, cov * meta.r);
}

// A five-block "+" that twinkles: scale .35 -> 1 -> .8 -> .35 and opacity
// .25 -> 1 -> .85 -> .25 at 0 / 45 / 60 / 100 %.
vec4 sparkle(vec4 acc, vec2 p, vec4 s, float i, float t, float still, float aa) {
  if (s.z <= 0.0) {
    return acc;
  }
  float scale = 1.0;
  float op = 1.0;
  if (still < 0.5) {
    float ph = fract((t - i * 0.9) / (2.6 + i * 0.7));
    if (ph < 0.45) {
      float e = smoothstep(0.0, 1.0, ph / 0.45);
      scale = mix(0.35, 1.0, e);
      op = mix(0.25, 1.0, e);
    } else if (ph < 0.6) {
      float e = smoothstep(0.0, 1.0, (ph - 0.45) / 0.15);
      scale = mix(1.0, 0.8, e);
      op = mix(1.0, 0.85, e);
    } else {
      float e = smoothstep(0.0, 1.0, (ph - 0.6) / 0.4);
      scale = mix(0.8, 0.35, e);
      op = mix(0.85, 0.25, e);
    }
  }
  float b = s.z;
  vec2 centre = s.xy + b * 0.5;
  vec2 q = centre + (p - centre) / scale;
  float qaa = aa / scale;
  float r = min(0.4, b * 0.2);
  float across = boxCoverage(q, s.xy - vec2(b, 0.0), vec2(3.0 * b, b), r, qaa);
  float down = boxCoverage(q, s.xy - vec2(0.0, b), vec2(b, 3.0 * b), r, qaa);
  float cov = max(across, down);
  vec2 d = abs(q - centre);
  float blockOp = (d.x <= b * 0.5 && d.y <= b * 0.5) ? 0.95 : 0.55;
  vec3 rgb = s.w > 0.5 ? kCyan : vec3(1.0);
  return over(acc, rgb, cov * op * blockOp);
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  float t = uAnim.x;
  float still = uAnim.y;
  float aa = 1.0 / max(uGrid.w, 1.0);
  vec4 acc = vec4(0.0);

  float cell = uGrid.z;
  float cols = uDims.x;
  float rows = uDims.y;
  float gap = uDims.z;
  vec2 g = (p - uGrid.xy) / cell;
  float col = floor(g.x);
  float baseRow = floor(g.y);

  // Blocks. The block above is checked too, because a drifting block can
  // slide down into this row; it is drawn first so this row sits on top.
  if (col >= 0.0 && col < cols) {
    for (int k = 0; k < 2; k++) {
      float row = baseRow - 1.0 + float(k);
      if (row >= 0.0 && row < rows) {
        vec4 c = fetchData(col, row);
        if (c.a > 0.5) {
          vec4 f = fetchData(col, row + rows);
          float fx = floor(f.g * 255.0 / 40.0 + 0.5);
          if (k == 1 || fx == 3.0) {
            vec4 timing = fetchData(col, row + 2.0 * rows);
            float period = timing.r * 8.0;
            // A cell may set a shallower dip (paper fire); 0 keeps the design.
            float dip = timing.g;
            float op = f.r;
            float dy = 0.0;
            vec3 rgb = c.rgb;
            vec2 lo = uGrid.xy + vec2(col, row) * cell + gap * 0.5;
            if (still < 0.5) {
              float w = wave(period, f.b, t);
              if (fx == 1.0) {
                op *= 1.0 - (dip > 0.0 ? dip : 0.45) * w;
              } else if (fx == 2.0) {
                op *= 1.0 - (dip > 0.0 ? dip : 0.38) * w;
              } else if (fx == 3.0) {
                dy = uAnim.w * w;
              } else if (uAnim.z > 0.5) {
                // Diagonal glint: 0 -> 1 -> 0 over the first 12 % of a 5.5 s
                // cycle, delayed along x + y.
                float delay = ((lo.x - uGlint.x) + (lo.y - uGlint.y)) /
                    max(uGlint.z, 1.0) * 1.4;
                float gp = fract((t - delay) / 5.5);
                float lift = 0.0;
                if (gp < 0.05) {
                  lift = gp / 0.05;
                } else if (gp < 0.12) {
                  lift = 1.0 - (gp - 0.05) / 0.07;
                }
                if (uAnim.z > 1.5) {
                  // Paper: brightening would fade ink into the page, so the
                  // glint deepens toward ink and only ever gains contrast.
                  rgb = mix(rgb, kInk, 0.4 * lift);
                } else {
                  // Dark tile: brightness 1 -> 1.85 -> 1.
                  rgb = min(rgb * (1.0 + 0.85 * lift), vec3(1.0));
                }
              }
            }
            float cov = boxCoverage(
                p, lo + vec2(0.0, dy), vec2(cell - gap), uDims.w, aa);
            acc = over(acc, rgb, cov * op);
          }
        }
      }
    }
  }

  acc = ember(acc, p, uEmber0, 0.0, t, still, aa);
  acc = ember(acc, p, uEmber1, 1.0, t, still, aa);
  acc = ember(acc, p, uEmber2, 2.0, t, still, aa);
  acc = ember(acc, p, uEmber3, 3.0, t, still, aa);
  acc = ember(acc, p, uEmber4, 4.0, t, still, aa);

  acc = sparkle(acc, p, uSpark0, 0.0, t, still, aa);
  acc = sparkle(acc, p, uSpark1, 1.0, t, still, aa);
  acc = sparkle(acc, p, uSpark2, 2.0, t, still, aa);

  if (uScan.w > 0.0) {
    float op = still > 0.5 ? 1.0 : 1.0 - 0.45 * wave(uScanColor.w, 0.0, t);
    float cx = (uScan.y + uScan.z) * 0.5;
    float hl = (uScan.z - uScan.y) * 0.5;
    vec2 d = vec2(max(abs(p.x - cx) - hl, 0.0), p.y - uScan.x);
    float cov = clamp(0.5 - (length(d) - uScan.w * 0.5) / aa, 0.0, 1.0);
    acc = over(acc, uScanColor.rgb, cov * op);
  }

  fragColor = acc;
}
