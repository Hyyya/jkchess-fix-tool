#!/usr/bin/env python3
# 将纯品红背景的 RGB PNG 抠成透明背景(白色主体保留)，输出 RGBA PNG
# 用法: chroma_key.py in.png out.png [fuzz]
import sys, zlib, struct

def read_png(path):
    data = open(path, 'rb').read()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', 'not a png'
    pos = 8; idat = b''; w = h = bd = ct = None
    while pos < len(data):
        ln = struct.unpack('>I', data[pos:pos+4])[0]
        typ = data[pos+4:pos+8]; chunk = data[pos+8:pos+8+ln]
        if typ == b'IHDR':
            w, h, bd, ct = struct.unpack('>IIBB', chunk[:10])
        elif typ == b'IDAT':
            idat += chunk
        elif typ == b'IEND':
            break
        pos += 12 + ln
    if bd != 8: raise SystemExit('only 8-bit depth supported')
    if ct not in (0, 2, 6): raise SystemExit('colortype %d unsupported' % ct)
    return w, h, ct, zlib.decompress(idat)

def unfilter(w, h, ct, raw):
    ch = {0:1, 2:3, 6:4}[ct]
    stride = w * ch
    out = bytearray()
    prev = bytearray(stride)
    p = 0
    for y in range(h):
        ft = raw[p]; p += 1
        line = bytearray(raw[p:p+stride]); p += stride
        if ft == 1:
            for i in range(ch, stride): line[i] = (line[i] + line[i-ch]) & 255
        elif ft == 2:
            for i in range(stride): line[i] = (line[i] + prev[i]) & 255
        elif ft == 3:
            for i in range(stride):
                a = line[i-ch] if i >= ch else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 255
        elif ft == 4:
            for i in range(stride):
                a = line[i-ch] if i >= ch else 0
                b = prev[i]; c = prev[i-ch] if i >= ch else 0
                pa = abs(b-c); pb = abs(a-c); pc = abs(a+b-2*c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        out += line
        prev = line
    return bytes(out)

def main():
    inp, outp = sys.argv[1], sys.argv[2]
    fuzz = float(sys.argv[3]) if len(sys.argv) > 3 else 60.0
    w, h, ct, raw = read_png(inp)
    rgb = unfilter(w, h, ct, raw)
    ch = {0:1, 2:3, 6:4}[ct]
    # 生成 RGBA
    rgba = bytearray()
    for i in range(w*h):
        if ch == 1:
            g = rgb[i]; r = g; b = g
        elif ch == 3:
            r, g, b = rgb[i*3], rgb[i*3+1], rgb[i*3+2]
        else:
            r, g, b, a = rgb[i*4], rgb[i*4+1], rgb[i*4+2], rgb[i*4+3]
            if a < 128:  # 已有低透明则保持透明
                rgba += bytes([0,0,0,0]); continue
        # 品红距离
        d = ((r-255)**2 + (g-0)**2 + (b-255)**2) ** 0.5
        alpha = 0 if d <= fuzz else 255
        rgba += bytes([r, g, b, alpha])
    # 写 PNG(RGBA)
    def chunk(typ, data):
        c = typ + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    ihdr = struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)
    raw2 = bytearray()
    stride = w*4
    for y in range(h):
        raw2 += b'\x00' + bytes(rgba[y*stride:(y+1)*stride])
    idat = zlib.compress(bytes(raw2))
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr) + chunk(b'IDAT', idat) + chunk(b'IEND', b'')
    open(outp, 'wb').write(png)
    # 统计
    tot = w*h; transparent = sum(1 for i in range(0, len(rgba), 4) if rgba[i+3] == 0)
    print('size=%dx%d alpha=True transparent_ratio=%.1f%%' % (w, h, 100.0*transparent/tot))

if __name__ == '__main__':
    main()
