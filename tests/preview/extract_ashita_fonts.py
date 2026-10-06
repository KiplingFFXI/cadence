"""Pulls the fonts Ashita embeds (ImGui base85 + stb-compressed TTFs) out of Ashita.dll."""
import re, sys, os

def in2(b, x): return (b[x] << 8) + b[x + 1]
def in3(b, x): return (b[x] << 16) + in2(b, x + 1)
def in4(b, x): return (b[x] << 24) + in3(b, x + 1)

def stb_decompress(src):
    assert in4(src, 0) == 0x57bC0000 and in4(src, 4) == 0
    olen = in4(src, 8)
    out = bytearray()
    i = 16
    def match(dist, n):
        s = len(out) - dist
        if dist >= n:
            out.extend(out[s:s + n])
        else:
            for k in range(n): out.append(out[s + k])
    while True:
        c = src[i]
        if c >= 0x20:
            if c >= 0x80: match(src[i + 1] + 1, c - 0x80 + 1); i += 2
            elif c >= 0x40: match(in2(src, i) - 0x4000 + 1, src[i + 2] + 1); i += 3
            else:
                n = c - 0x20 + 1; out += src[i + 1:i + 1 + n]; i += 1 + n
        else:
            if c >= 0x18: match(in3(src, i) - 0x180000 + 1, src[i + 3] + 1); i += 4
            elif c >= 0x10: match(in3(src, i) - 0x100000 + 1, in2(src, i + 3) + 1); i += 5
            elif c >= 0x08:
                n = in2(src, i) - 0x0800 + 1; out += src[i + 2:i + 2 + n]; i += 2 + n
            elif c == 0x07:
                n = in2(src, i + 1) + 1; out += src[i + 3:i + 3 + n]; i += 3 + n
            elif c == 0x06: match(in3(src, i + 1) + 1, src[i + 4] + 1); i += 5
            elif c == 0x04: match(in3(src, i + 1) + 1, in2(src, i + 4) + 1); i += 6
            elif c == 0x05 and src[i + 1] == 0xfa: break
            else: raise ValueError('bad stb token 0x%x' % c)
    assert len(out) == olen, (len(out), olen)
    return bytes(out)

def decode85(s):
    def d(c): return c - 36 if c >= 0x5C else c - 35
    out = bytearray()
    for k in range(0, len(s) - len(s) % 5, 5):
        tmp = d(s[k]) + 85 * (d(s[k + 1]) + 85 * (d(s[k + 2]) + 85 * (d(s[k + 3]) + 85 * d(s[k + 4]))))
        out += tmp.to_bytes(4, 'little')
    return bytes(out)

def font_names(ttf):
    # The name table holds the family (1) and the full name (4).
    num = in2(ttf, 4)
    for t in range(num):
        rec = 12 + 16 * t
        if ttf[rec:rec + 4] == b'name':
            off = in4(ttf, rec + 8)
            count, str_off = in2(ttf, off + 2), in2(ttf, off + 4)
            names = {}
            for r in range(count):
                p = off + 6 + 12 * r
                pid, nid, ln, so = in2(ttf, p), in2(ttf, p + 6), in2(ttf, p + 8), in2(ttf, p + 10)
                raw = ttf[off + str_off + so: off + str_off + so + ln]
                names.setdefault(nid, raw.decode('utf-16-be', 'ignore') if pid in (0, 3) else raw.decode('latin-1'))
            return names
    return {}

if __name__ == '__main__':
    dll = sys.argv[1] if len(sys.argv) > 1 else r'C:/Games/PhoenixXI/Ashita.dll'
    out_dir = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(os.path.abspath(__file__)), 'fonts')
    os.makedirs(out_dir, exist_ok=True)
    data = open(dll, 'rb').read()
    for m in re.finditer(rb"7\]\)#######[\x21-\x7e]{1000,}", data):
        ttf = stb_decompress(decode85(m.group()))
        names = font_names(ttf)
        family = names.get(4) or names.get(1) or 'font_%x' % m.start()
        fname = re.sub(r'[^A-Za-z0-9_-]+', '_', family) + '.ttf'
        open(os.path.join(out_dir, fname), 'wb').write(ttf)
        print('%s: %d bytes, family=%r full=%r' % (fname, len(ttf), names.get(1), names.get(4)))
