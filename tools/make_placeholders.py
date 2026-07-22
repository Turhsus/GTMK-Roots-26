"""Generate placeholder colored-rect item art into assets/items/.

Placeholders follow the art spec in MVP.md 8.1: authored at 2x (192 px per
96 px cell), transparent PNG, one cell-shaped block per occupied cell, pivot at
the bounding box's top-left. Swapping in real art = drop <id>.png in the same
folder; no code change.

Run:  python tools/make_placeholders.py
Stdlib only (zlib + struct), so it needs neither Pillow nor Godot.
"""

import struct
import zlib
from pathlib import Path

SOURCE_CELL = 192  # 96 px cell authored at 2x
MARGIN = 10  # transparent gutter so neighbouring items stay readable
BORDER = 8

ASSETS = Path(__file__).resolve().parent.parent / "assets" / "items"

# id: (shape offsets, fill colour). Shapes match the MVP.md 8.2 starter list.
ITEMS = {
    "bread":     ([(0, 0), (1, 0)],                 (198, 140, 83)),
    "waterskin": ([(0, 0), (0, 1)],                 (94, 150, 168)),
    "sword":     ([(0, 0), (0, 1), (0, 2)],         (168, 172, 182)),
    "shield":    ([(0, 0), (1, 0), (0, 1), (1, 1)], (126, 143, 178)),
    "torch":     ([(0, 0), (0, 1)],                 (214, 143, 74)),
    "rope":      ([(0, 0), (1, 0)],                 (176, 152, 108)),
    "potion":    ([(0, 0)],                         (186, 106, 148)),
    "map":       ([(0, 0), (1, 0)],                 (206, 190, 150)),
    "blanket":   ([(0, 0), (1, 0), (0, 1), (1, 1)], (176, 122, 128)),
    "lantern":   ([(0, 0)],                         (222, 186, 96)),
    "apple":     ([(0, 0)],                         (188, 92, 84)),
    "spellbook": ([(0, 0), (1, 0), (0, 1), (1, 1)], (120, 110, 168)),
    "boots":     ([(0, 0), (1, 0)],                 (140, 106, 84)),
    "whistle":   ([(0, 0)],                         (170, 178, 160)),
}


def shade(color, factor):
    return tuple(max(0, min(255, int(channel * factor))) for channel in color)


def write_png(path, width, height, pixels):
    """pixels: bytearray of RGBA rows, width * height * 4."""
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)  # filter type 0 (None)
        raw += pixels[y * stride:(y + 1) * stride]

    def chunk(tag, data):
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )


def make_item(item_id, shape, color):
    cols = max(x for x, _ in shape) + 1
    rows = max(y for _, y in shape) + 1
    width, height = cols * SOURCE_CELL, rows * SOURCE_CELL
    pixels = bytearray(width * height * 4)  # transparent

    fill = color + (255,)
    border = shade(color, 0.62) + (255,)

    for cell_x, cell_y in shape:
        left = cell_x * SOURCE_CELL + MARGIN
        top = cell_y * SOURCE_CELL + MARGIN
        right = (cell_x + 1) * SOURCE_CELL - MARGIN
        bottom = (cell_y + 1) * SOURCE_CELL - MARGIN
        for y in range(top, bottom):
            edge_row = y < top + BORDER or y >= bottom - BORDER
            for x in range(left, right):
                edge = edge_row or x < left + BORDER or x >= right - BORDER
                offset = (y * width + x) * 4
                pixels[offset:offset + 4] = bytes(border if edge else fill)

    write_png(ASSETS / f"{item_id}.png", width, height, pixels)
    return cols, rows


def main():
    ASSETS.mkdir(parents=True, exist_ok=True)
    for item_id, (shape, color) in sorted(ITEMS.items()):
        cols, rows = make_item(item_id, shape, color)
        print(f"{item_id}.png  {cols}x{rows} cells  {cols * SOURCE_CELL}x{rows * SOURCE_CELL} px")


if __name__ == "__main__":
    main()
