"""Placeholder background art for the road and shop scenes.

Stdlib-only (zlib + struct, same pipeline as make_placeholders.py): writes one
1280x720 PNG per scene into assets/backgrounds/. Each is a simple two-color
vertical gradient with a horizon band, distinct per scene, so the screens read
differently long before real art exists. Dropping real paintings at the same
paths is a no-code swap (the scenes load these paths by convention):

    assets/backgrounds/road.png              <- RoadScene.BACKGROUND_PATH
    assets/backgrounds/shop_<shop id>.png    <- ShopScene.BACKGROUND_PATTERN

Run:  python tools/make_backgrounds.py
"""

import os
import struct
import zlib

WIDTH, HEIGHT = 1280, 720
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "backgrounds")

# name -> (top color, bottom color) as RGB 0-255. Kept dim so the built-in Dim
# overlay + white UI text stay readable on top.
BACKGROUNDS = {
    "road": ((96, 110, 130), (74, 62, 44)),            # grey sky over a dirt track
    "shop_grocer": ((70, 96, 58), (40, 56, 34)),       # market greens
    "shop_apothecary": ((84, 66, 104), (44, 34, 58)),  # herbal purples
    "shop_blacksmith": ((66, 58, 56), (96, 44, 30)),   # soot over forge embers
}


def lerp(a, b, t):
    return int(a + (b - a) * t)


def make_rows(top, bottom):
    rows = []
    for y in range(HEIGHT):
        t = y / (HEIGHT - 1)
        # A slightly sharper blend around two-thirds down fakes a horizon line.
        shaped = t * t * (3 - 2 * t)
        r = lerp(top[0], bottom[0], shaped)
        g = lerp(top[1], bottom[1], shaped)
        b = lerp(top[2], bottom[2], shaped)
        rows.append(bytes((r, g, b)) * WIDTH)
    return rows


def write_png(path, rows):
    raw = b"".join(b"\x00" + row for row in rows)  # filter byte 0 per scanline

    def chunk(tag, data):
        payload = tag + data
        return struct.pack(">I", len(data)) + payload + struct.pack(
            ">I", zlib.crc32(payload) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", WIDTH, HEIGHT, 8, 2, 0, 0, 0)  # 8-bit RGB
    with open(path, "wb") as handle:
        handle.write(b"\x89PNG\r\n\x1a\n")
        handle.write(chunk(b"IHDR", header))
        handle.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        handle.write(chunk(b"IEND", b""))


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, (top, bottom) in BACKGROUNDS.items():
        path = os.path.join(OUT_DIR, name + ".png")
        write_png(path, make_rows(top, bottom))
        print("wrote", os.path.relpath(path))


if __name__ == "__main__":
    main()
