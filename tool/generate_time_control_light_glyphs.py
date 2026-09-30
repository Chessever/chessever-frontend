"""Bake the light-theme twins of the time-control glyphs.

usage: python3 tool/generate_time_control_light_glyphs.py <repo_root>
Writes assets/pngs/{rapid,classical,blitz}_light.png next to the originals.
rapid/classical: luminance map white->INK (#0E1A1C, AppColors.light.textPrimary),
black->PAPER (#F4FAF9, AppColors.light.surface); alpha untouched, so the
rabbit cut-out stays transparent and every anti-aliased edge keeps its ramp.
blitz: RGB x0.8 (hue kept) so the bolt clears 3:1 on every mint surface.
"""
import sys, os
from PIL import Image
root = sys.argv[1]
INK = (0x0E, 0x1A, 0x1C); PAPER = (0xF4, 0xFA, 0xF9)
def lum_map(im):
    out = Image.new('RGBA', im.size); px = im.load(); po = out.load()
    for y in range(im.size[1]):
        for x in range(im.size[0]):
            r, g, b, a = px[x, y]
            Y = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
            po[x, y] = tuple(round(PAPER[i] + (INK[i] - PAPER[i]) * Y) for i in range(3)) + (a,)
    return out
def deepen(im, k=0.8):
    out = Image.new('RGBA', im.size); px = im.load(); po = out.load()
    for y in range(im.size[1]):
        for x in range(im.size[0]):
            r, g, b, a = px[x, y]
            po[x, y] = (round(r * k), round(g * k), round(b * k), a)
    return out
d = os.path.join(root, 'assets', 'pngs')
for name, fn in (('rapid', lum_map), ('classical', lum_map), ('blitz', deepen)):
    src = Image.open(os.path.join(d, f'{name}.png')).convert('RGBA')
    dst = fn(src)
    assert dst.size == src.size
    dst.save(os.path.join(d, f'{name}_light.png'), optimize=True)
    print(name, src.size, '->', f'{name}_light.png')
