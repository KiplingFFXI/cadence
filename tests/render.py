"""
Draws what cadence's timers put on screen to PNGs, from the draw-list calls a shots_*.lua script
records. The PNGs go to out/.

    python render.py shots_presets.lua
"""
import os, sys, tempfile
from PIL import Image, ImageDraw, ImageFont
from run import runtime
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'out')
# A game screenshot to draw the timers over. Without one they go on a plain dark background.
BACKDROP = os.environ.get('CADENCE_BACKDROP', '')
FONT = r'C:\Windows\Fonts\seguisb.ttf'
# ImGui sizes a font by its ascent plus descent, PIL by its em. This is Segoe UI's em over the two.
RATIO = 2048 / (2210 + 514)
_fonts = {}
def pil_font(px):
    key = round(px * RATIO * 4) / 4
    if key not in _fonts: _fonts[key] = ImageFont.truetype(FONT, key)
    return _fonts[key]
def measure(text, px):
    return pil_font(px).getlength(text)
def color(v):
    v = int(v) & 0xFFFFFFFF
    r = v & 255; g = (v >> 8) & 255; b = (v >> 16) & 255; a = (v >> 24) & 255
    return (r, g, b, a)

def render(calls, out, crop=None, backdrop=BACKDROP):
    if os.path.exists(backdrop):
        base = Image.open(backdrop).convert('RGBA')
    else:
        base = Image.new('RGBA', (1920, 1080), (38, 34, 52, 255))
    layer = Image.new('RGBA', base.size, (0, 0, 0, 0))
    clips = [(0, 0, base.size[0], base.size[1])]
    LEFT, RIGHT = (16 | 64), (32 | 128)
    def corners_for(flags):
        flags = flags or 0
        if flags == 0 or (flags & 0xF0) == 0:
            return (True, True, True, True)
        return (bool(flags & 16), bool(flags & 32), bool(flags & 128), bool(flags & 64))
    def clamp(r, w, h, flags):
        # ImGui's PathRect clamp caps rounding at half the side when both corners on it are rounded, else at
        # the side, minus 1.
        flags = flags or 0
        if (flags & 0xF0) == 0:
            flags |= 0xF0
        top, bottom, left, right = 16 | 32, 64 | 128, 16 | 64, 32 | 128
        fx = 0.5 if ((flags & top) == top or (flags & bottom) == bottom) else 1.0
        fy = 0.5 if ((flags & left) == left or (flags & right) == right) else 1.0
        return min(r, abs(w) * fx - 1, abs(h) * fy - 1)
    for c in calls:
        name = c[0]
        if name == 'dl:PushClipRect':
            p1, p2 = c[1], c[2]
            cx0, cy0, cx1, cy1 = clips[-1]
            clips.append((max(cx0, p1[1]), max(cy0, p1[2]), min(cx1, p2[1]), min(cy1, p2[2])))
            continue
        if name == 'dl:PopClipRect':
            clips.pop()
            continue
        ov = Image.new('RGBA', base.size, (0, 0, 0, 0))
        d = ImageDraw.Draw(ov)
        if name == 'dl:AddRectFilled':
            p1, p2, col = c[1], c[2], c[3]
            r = c[4] if len(c) > 4 and c[4] else 0
            fl = c[5] if len(c) > 5 else 0
            r = clamp(r, p2[1] - p1[1], p2[2] - p1[2], fl) if r else 0
            box = [p1[1], p1[2], p2[1] - 1, p2[2] - 1]
            if r and r >= 0.5:
                d.rounded_rectangle(box, radius=round(r), fill=color(col), corners=corners_for(fl))
            else:
                d.rectangle(box, fill=color(col))
        elif name == 'dl:AddRect':
            p1, p2, col = c[1], c[2], c[3]
            r = c[4] if len(c) > 4 and c[4] else 0
            r = clamp(r, p2[1] - p1[1] - 1, p2[2] - p1[2] - 1, c[5] if len(c) > 5 else 0) if r else 0
            box = [p1[1], p1[2], p2[1] - 1, p2[2] - 1]
            if r and r >= 0.5:
                d.rounded_rectangle(box, radius=round(r), outline=color(col), width=1,
                                    corners=corners_for(c[5] if len(c) > 5 else 0))
            else:
                d.rectangle(box, outline=color(col), width=1)
        elif name == 'dl:AddRectFilledMultiColor':
            p1, p2, ul, ur = c[1], c[2], color(c[3]), color(c[4])
            x0, y0, x1, y1 = int(p1[1]), int(p1[2]), int(p2[1]), int(p2[2])
            w = max(1, x1 - x0)
            for i in range(w):
                t = i / max(1, w - 1)
                col = tuple(int(ul[k] + (ur[k] - ul[k]) * t) for k in range(4))
                d.line([(x0 + i, y0), (x0 + i, y1 - 1)], fill=col)
        elif name == 'dl:AddLine':
            p1, p2, col = c[1], c[2], c[3]
            d.line([(p1[1], p1[2]), (p2[1], p2[2])], fill=color(col), width=int(c[4]) if len(c) > 4 and c[4] else 1)
        elif name == 'dl:AddText':
            px, pos, col, text = c[2], c[3], c[4], c[5]
            d.text((pos[1], pos[2]), text, font=pil_font(px), fill=color(col))
        cx0, cy0, cx1, cy1 = clips[-1]
        mask = Image.new('L', base.size, 0)
        ImageDraw.Draw(mask).rectangle([cx0, cy0, cx1 - 1, cy1 - 1], fill=255)
        clipped = Image.new('RGBA', base.size, (0, 0, 0, 0))
        clipped.paste(ov, (0, 0), mask)
        layer = Image.alpha_composite(layer, clipped)
    img = Image.alpha_composite(base, layer)
    if crop: img = img.crop(crop)
    img.convert('RGB').save(out)

if __name__ == '__main__':
    # Files the addon writes go in a folder of their own, deleted when this ends.
    install = tempfile.TemporaryDirectory(prefix='cadence_shots_', ignore_cleanup_errors=True)
    L = runtime(install.name)
    L.globals().MOCK.measure = measure
    script = open(os.path.join(HERE, sys.argv[1]), encoding='utf-8').read()
    result = L.execute(script)
    shots = L.globals().SHOTS
    for name in list(shots.keys()):
        shot = shots[name]
        calls = []
        for i in range(1, len(shot.calls) + 1):
            call = shot.calls[i]
            items = []
            for j in range(1, len(call) + 1):
                v = call[j]
                if hasattr(v, 'values') and not isinstance(v, (str, bytes)):
                    try: v = {k: v[k] for k in (1, 2)}
                    except Exception: pass
                items.append(v)
            calls.append(items)
        crop = tuple(shot.crop[k] for k in (1,2,3,4)) if shot.crop else None
        os.makedirs(OUT, exist_ok=True)
        render(calls, os.path.join(OUT, f'shot_{name}.png'), crop)
        print('rendered', name, len(calls))
