# SPDX-FileCopyrightText: Iridesium
# SPDX-License-Identifier: GPL-3.0-only
"""Generates the placeholder textures for mods/tiamat_default_craft/textures.

A flat colour for a block, the Spindle's convention: variation across a
surface is the renderer's (the block's tint), never baked into the picture.
An item is a flat colour in one silhouette on a clear ground, so a stick
reads as a stick in a slot. Every picture here is meant to be replaced; the
README says how.

No dependencies beyond the standard library, and no randomness: the same
bytes on every machine. Run from the repository root:

    python tools/make_textures.py
"""
import struct
import zlib
from pathlib import Path

SIZE = 16
OUT = Path(__file__).resolve().parent.parent / "mods" / "tiamat_default_craft" / "textures"

# The palette, in the world's muted register.
WOOD = (122, 88, 52)
WOOD_DARK = (84, 58, 34)


def png(pixels):
    """RGBA rows of (r, g, b, a) tuples, as PNG bytes."""
    raw = b"".join(b"\x00" + b"".join(bytes(p) for p in row) for row in pixels)

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def clear():
    return [[(0, 0, 0, 0) for _ in range(SIZE)] for _ in range(SIZE)]


def rod(colour, edge, width=2):
    """A rod from the bottom left to the top right, `width` pixels across,
    with a darker lower edge so it reads as round."""
    pixels = clear()
    for i in range(2, SIZE - 2):
        x, y = i, SIZE - 1 - i
        for w in range(width):
            pixels[y][min(SIZE - 1, x + w)] = colour + (255,)
        pixels[min(SIZE - 1, y + 1)][x] = edge + (255,)
    return pixels


ITEMS = {
    "stick": lambda: rod(WOOD, WOOD_DARK),
}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, draw in sorted(ITEMS.items()):
        (OUT / (name + ".png")).write_bytes(png(draw()))
    print(f"wrote {len(ITEMS)} textures to {OUT}")


if __name__ == "__main__":
    main()
