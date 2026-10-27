import type { Canvas } from "canvaskit-wasm/full";

export const MIN_ZOOM = 0.1;
export const MAX_ZOOM = 32;

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

/**
 * A 2D pan/zoom camera operating in device-pixel space. The mapping from a
 * scene point to a screen point is `screen = scene * zoom + (x, y)`, i.e. a
 * uniform scale followed by a translation — the same model Figma uses.
 */
export class Camera {
  x = 0;
  y = 0;
  zoom = 1;

  reset(): void {
    this.x = 0;
    this.y = 0;
    this.zoom = 1;
  }

  isIdentity(): boolean {
    return this.x === 0 && this.y === 0 && this.zoom === 1;
  }

  panBy(dx: number, dy: number): void {
    this.x += dx;
    this.y += dy;
  }

  /**
   * Multiplies the zoom by `factor` while keeping the screen point (cx, cy)
   * anchored — so the content under the cursor stays put as you zoom.
   */
  zoomAt(factor: number, cx: number, cy: number): void {
    const next = clamp(this.zoom * factor, MIN_ZOOM, MAX_ZOOM);
    const applied = next / this.zoom;
    this.x = cx - (cx - this.x) * applied;
    this.y = cy - (cy - this.y) * applied;
    this.zoom = next;
  }

  /** Pushes the camera transform onto a Skia canvas (call between save/restore). */
  apply(canvas: Canvas): void {
    canvas.translate(this.x, this.y);
    canvas.scale(this.zoom, this.zoom);
  }
}
