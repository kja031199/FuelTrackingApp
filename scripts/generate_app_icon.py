#!/usr/bin/env python3
"""Generate the FuelTracker app icon: a fuel droplet with an orange "fuel
level" on a blue gradient, in the app's economy-blue / price-orange palette.

Pure standard library — renders 1024x1024 with signed-distance-field anti-
aliasing and writes an RGB (no alpha channel) PNG, which is what iOS/watchOS
app icons require. Re-run to tweak the design:

    python3 scripts/generate_app_icon.py out.png
"""
import math
import struct
import sys
import zlib

SIZE = 1024

# Palette
BG_TOP = (46, 125, 240)      # #2E7DF0  bright economy-blue
BG_BOTTOM = (16, 63, 134)    # #103F86  deep blue
DROP = (255, 255, 255)       # white droplet body
FUEL = (255, 159, 10)        # #FF9F0A  price-orange "fuel level"

# Droplet geometry (in 1024 space)
CX, CY, R = 512.0, 624.0, 252.0   # bulb circle
AX, AY = 512.0, 244.0             # apex (top point)
FILL_Y = 548.0                    # orange fills below this line

# Bounding box of the glyph, to skip SDF work on the plain background.
BX0, BY0, BX1, BY1 = 250, 236, 774, 884


def lerp(a, b, t):
    return (a[0] + (b[0] - a[0]) * t,
            a[1] + (b[1] - a[1]) * t,
            a[2] + (b[2] - a[2]) * t)


def clamp01(t):
    return 0.0 if t < 0.0 else (1.0 if t > 1.0 else t)


def _tangent_points():
    d = CY - AY
    beta = math.asin(R / d)
    length = math.sqrt(d * d - R * R)
    dl = (-math.sin(beta), math.cos(beta))
    dr = (math.sin(beta), math.cos(beta))
    tl = (AX + length * dl[0], AY + length * dl[1])
    tr = (AX + length * dr[0], AY + length * dr[1])
    return tl, tr


TL, TR = _tangent_points()
TRI = ((AX, AY), TL, TR)   # apex, left tangent, right tangent


def sd_triangle(px, py):
    # Inigo Quilez's triangle SDF (negative inside).
    (ax, ay), (bx, by), (cx, cy) = TRI
    e0 = (bx - ax, by - ay); e1 = (cx - bx, cy - by); e2 = (ax - cx, ay - cy)
    v0 = (px - ax, py - ay); v1 = (px - bx, py - by); v2 = (px - cx, py - cy)

    def pq(v, e):
        t = clamp01((v[0] * e[0] + v[1] * e[1]) / (e[0] * e[0] + e[1] * e[1]))
        return (v[0] - e[0] * t, v[1] - e[1] * t)

    pq0 = pq(v0, e0); pq1 = pq(v1, e1); pq2 = pq(v2, e2)
    s = 1.0 if (e0[0] * e2[1] - e0[1] * e2[0]) > 0 else -1.0
    dx = min(pq0[0] * pq0[0] + pq0[1] * pq0[1],
             pq1[0] * pq1[0] + pq1[1] * pq1[1],
             pq2[0] * pq2[0] + pq2[1] * pq2[1])
    dy = min(s * (v0[0] * e0[1] - v0[1] * e0[0]),
             s * (v1[0] * e1[1] - v1[1] * e1[0]),
             s * (v2[0] * e2[1] - v2[1] * e2[0]))
    return -math.sqrt(dx) * (1.0 if dy >= 0 else -1.0)


def render():
    rows = []
    for y in range(SIZE):
        t = y / (SIZE - 1)
        bg = lerp(BG_TOP, BG_BOTTOM, t)
        bg_bytes = (int(bg[0] + 0.5), int(bg[1] + 0.5), int(bg[2] + 0.5))
        row = bytearray()
        in_band = BY0 <= y <= BY1
        yc = y + 0.5
        for x in range(SIZE):
            if not in_band or not (BX0 <= x <= BX1):
                row += bytes(bg_bytes)
                continue
            xc = x + 0.5
            # Union the circle and triangle as independently anti-aliased
            # coverages (max), so there's no seam where the circle's arc runs
            # inside the triangle.
            cov = clamp01(0.5 - (math.hypot(xc - CX, yc - CY) - R))
            if cov < 1.0:
                cov = max(cov, clamp01(0.5 - sd_triangle(xc, yc)))
            if cov <= 0.0:
                row += bytes(bg_bytes)
                continue
            fuel_cov = clamp01(0.5 + (yc - FILL_Y))   # orange below the fill line
            body = lerp(DROP, FUEL, fuel_cov)
            col = lerp(bg, body, cov)
            row += bytes((int(col[0] + 0.5), int(col[1] + 0.5), int(col[2] + 0.5)))
        rows.append(bytes(row))
    return rows


def write_png(path, rows):
    raw = bytearray()
    for row in rows:
        raw.append(0)          # filter: None
        raw += row

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data +
                struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    ihdr = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)  # color type 2 = RGB
    png = (b"\x89PNG\r\n\x1a\n" +
           chunk(b"IHDR", ihdr) +
           chunk(b"IDAT", zlib.compress(bytes(raw), 9)) +
           chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "AppIcon.png"
    write_png(out, render())
    print(f"wrote {out} ({SIZE}x{SIZE}, RGB no-alpha)")
