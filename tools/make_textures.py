# SPDX-FileCopyrightText: Iridesium
# SPDX-License-Identifier: GPL-3.0-only
"""Generates the placeholder textures for mods/tiamat_default_craft/textures.

A flat colour for a block, the Spindle's convention: variation across a
surface is the renderer's (the block's tint), never baked into the picture.
An item is flat colours in one silhouette on a clear ground, so a pick reads
as a pick in a slot: a wooden haft and a head in the metal it is made of.
Every picture here is meant to be replaced; the README says how.

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
IRONWOOD = (44, 38, 34)
IRONWOOD_EDGE = (74, 64, 56)
BRONZE = (178, 142, 72)
BRONZE_DARK = (128, 98, 46)
IRON = (122, 132, 148)
IRON_DARK = (82, 90, 104)
COPPER = (176, 102, 62)
COPPER_DARK = (118, 70, 44)

METALS = {
    "bronze": (BRONZE, BRONZE_DARK),
    "iron": (IRON, IRON_DARK),
    "copper": (COPPER, COPPER_DARK),
    "wooden": (WOOD, WOOD_DARK),
    "ironwood": (IRONWOOD, IRONWOOD_EDGE),
}


def png(pixels):
    """RGBA rows of (r, g, b, a) tuples, as PNG bytes."""
    raw = b"".join(b"\x00" + b"".join(bytes(p) for p in row) for row in pixels)

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


class Canvas:
    def __init__(self):
        self.p = [[(0, 0, 0, 0) for _ in range(SIZE)] for _ in range(SIZE)]

    def dot(self, x, y, colour):
        if 0 <= x < SIZE and 0 <= y < SIZE:
            self.p[y][x] = colour + (255,)

    def line(self, x0, y0, x1, y1, colour, width=1):
        """A straight run of pixels, `width` wide across x."""
        steps = max(abs(x1 - x0), abs(y1 - y0), 1)
        for i in range(steps + 1):
            x = x0 + (x1 - x0) * i // steps
            y = y0 + (y1 - y0) * i // steps
            for w in range(width):
                self.dot(x + w, y, colour)

    def rect(self, x0, y0, x1, y1, colour):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.dot(x, y, colour)


def haft(c, wood, top=(11, 4), foot=(3, 13)):
    """A handle from the bottom left up towards the top right."""
    light, dark = wood
    c.line(foot[0], foot[1], top[0], top[1], light, 2)
    c.line(foot[0], foot[1] + 1, top[0], top[1] + 1, dark)


def pick(metal, wood=METALS["wooden"]):
    c = Canvas()
    haft(c, wood)
    light, dark = metal
    # A curved head across the top of the haft.
    c.line(5, 3, 9, 2, light, 2)
    c.line(9, 2, 13, 4, light, 2)
    c.line(13, 4, 14, 7, dark)
    c.line(5, 3, 4, 5, dark)
    return c.p


def axe(metal, wood=METALS["wooden"]):
    c = Canvas()
    haft(c, wood)
    light, dark = metal
    c.rect(10, 2, 13, 7, light)
    c.line(14, 2, 14, 8, dark)
    c.line(10, 8, 13, 8, dark)
    return c.p


def spade(metal, wood=METALS["wooden"]):
    c = Canvas()
    light, dark = metal
    c.line(7, 1, 7, 9, wood[0], 2)
    c.line(6, 1, 9, 1, wood[1])
    c.rect(5, 10, 10, 13, light)
    c.line(6, 14, 9, 14, dark)
    return c.p


def digging_stick(wood):
    c = Canvas()
    light, dark = wood
    c.line(3, 13, 12, 3, light, 2)
    c.line(3, 14, 12, 4, dark)
    c.dot(13, 2, light)
    return c.p


def maul(wood):
    c = Canvas()
    haft(c, METALS["wooden"])
    light, dark = wood
    c.rect(9, 1, 14, 6, light)
    c.line(9, 7, 14, 7, dark)
    return c.p


def wedge(wood):
    c = Canvas()
    light, dark = wood
    for row in range(4, 13):
        half = (row - 4) // 2
        c.line(8 - half, row, 8 + half, row, light)
    c.line(4, 13, 12, 13, dark)
    return c.p


def chisel(metal):
    c = Canvas()
    c.line(3, 13, 8, 8, WOOD, 2)
    c.line(9, 7, 13, 3, metal[0], 2)
    c.line(13, 2, 14, 3, metal[1])
    return c.p


def hammer(metal):
    c = Canvas()
    haft(c, METALS["wooden"])
    light, dark = metal
    c.rect(9, 2, 14, 5, light)
    c.line(9, 6, 14, 6, dark)
    return c.p


def knife(metal):
    c = Canvas()
    c.line(3, 13, 6, 10, WOOD, 2)
    light, dark = metal
    c.line(7, 9, 13, 3, light, 2)
    c.line(7, 10, 13, 4, dark)
    return c.p


def sickle(metal):
    c = Canvas()
    c.line(4, 14, 6, 11, WOOD, 2)
    light, dark = metal
    points = [(6, 10), (5, 8), (5, 6), (6, 4), (8, 3), (10, 3), (12, 4), (13, 6)]
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        c.line(x0, y0, x1, y1, light, 2)
    c.dot(13, 7, dark)
    return c.p


def hoe(metal):
    c = Canvas()
    haft(c, METALS["wooden"], top=(12, 3))
    light, dark = metal
    c.rect(11, 3, 14, 4, light)
    c.rect(13, 5, 14, 7, light)
    c.dot(14, 8, dark)
    return c.p


def pot(metal):
    c = Canvas()
    light, dark = metal
    c.line(3, 5, 12, 5, dark)
    for row in range(6, 12):
        inset = max(0, row - 9)
        c.line(3 + inset, row, 12 - inset, row, light)
    c.line(6, 12, 9, 12, dark)
    c.dot(2, 6, dark)
    c.dot(13, 6, dark)
    return c.p


def rod(wood):
    """A stick: a rod from the bottom left to the top right."""
    c = Canvas()
    light, dark = wood
    c.line(2, 13, 13, 2, light, 2)
    c.line(2, 14, 13, 3, dark)
    return c.p


def tinder():
    c = Canvas()
    straw, dry = (196, 170, 104), (150, 124, 70)
    for i, (x0, y0, x1, y1) in enumerate([(3, 12, 9, 5), (5, 13, 12, 7), (4, 10, 13, 10), (7, 13, 6, 4), (9, 12, 12, 4)]):
        c.line(x0, y0, x1, y1, straw if i % 2 == 0 else dry)
    return c.p


def striker():
    c = Canvas()
    flint, edge = (64, 62, 70), (110, 108, 118)
    c.rect(3, 6, 8, 11, flint)
    c.line(3, 5, 8, 5, edge)
    c.rect(9, 7, 13, 10, flint)
    c.line(9, 6, 13, 6, edge)
    for x, y in [(8, 3), (10, 2), (9, 4)]:
        c.dot(x, y, (250, 200, 90))
    return c.p


def campfire(lit):
    """Crossed logs on a ring of stones, alight or not. Clear round it: the
    block is cutout, and the gaps are where the ground shows."""
    c = Canvas()
    c.line(2, 13, 13, 9, WOOD, 2)
    c.line(2, 9, 13, 13, WOOD_DARK, 2)
    for x in range(1, 15, 3):
        c.rect(x, 14, x + 1, 15, (110, 108, 104))
    if lit:
        for row, (half, colour) in enumerate([(1, (255, 236, 150)), (2, (250, 160, 30)), (3, (236, 88, 20)),
                                             (3, (236, 88, 20)), (2, (250, 160, 30)), (1, (236, 88, 20))]):
            y = 10 - row
            c.line(8 - half, y, 7 + half, y, colour)
        c.dot(7, 3, (236, 88, 20))
    else:
        c.rect(6, 9, 9, 10, (180, 164, 120))
    return c.p


# The world's rocks (its tools/make_textures.py), for their cracked twins.
ROCKS = {
    "stone": (112, 110, 104),
    "slate": (72, 78, 90),
    "calcite": (204, 202, 194),
    "dark_basalt": (44, 44, 48),
    "copper_ore": (140, 96, 66),
    "iron_ore": (122, 96, 86),
    "coal": (34, 32, 34),
}


def cracked(colour):
    """A whole block of the rock's colour, crazed with darker cracks."""
    c = Canvas()
    c.rect(0, 0, SIZE - 1, SIZE - 1, colour)
    dark = tuple(max(0, v * 45 // 100) for v in colour)
    for x0, y0, x1, y1 in [(0, 3, 7, 7), (7, 7, 15, 5), (7, 7, 5, 15), (10, 0, 12, 6), (12, 11, 15, 13), (2, 11, 5, 13)]:
        c.line(x0, y0, x1, y1, dark)
    return c.p


PLANK = (170, 128, 80)
PLANK_DARK = (126, 92, 56)


def planks():
    """A whole block of boards: three planks and their seams."""
    c = Canvas()
    c.rect(0, 0, SIZE - 1, SIZE - 1, PLANK)
    for y in (0, 5, 10, 15):
        c.line(0, y, SIZE - 1, y, PLANK_DARK)
    for x, y in ((6, 1), (12, 6), (3, 11)):
        c.line(x, y, x, y + 3, PLANK_DARK)
    return c.p


def workbench():
    """A plank top with the grain showing, over a log-dark frame."""
    c = Canvas()
    c.rect(0, 0, SIZE - 1, SIZE - 1, WOOD_DARK)
    c.rect(0, 0, SIZE - 1, 5, PLANK)
    c.line(0, 6, SIZE - 1, 6, (60, 42, 26))
    c.rect(2, 7, 4, SIZE - 1, WOOD)
    c.rect(11, 7, 13, SIZE - 1, WOOD)
    c.line(5, 10, 10, 10, (196, 170, 104))
    return c.p


def chest():
    c = Canvas()
    c.rect(0, 0, SIZE - 1, SIZE - 1, PLANK)
    c.line(0, 5, SIZE - 1, 5, PLANK_DARK)
    c.line(0, 6, SIZE - 1, 6, PLANK_DARK)
    for y in (0, 10, 15):
        c.line(0, y, SIZE - 1, y, PLANK_DARK)
    c.rect(7, 5, 8, 8, (196, 170, 104))
    return c.p


def cord():
    c = Canvas()
    straw, dark = (176, 150, 96), (120, 98, 60)
    for i in range(12):
        x = 2 + i
        y = 8 + (2 if i % 4 < 2 else -2) // 2
        c.dot(x, y, straw)
        c.dot(x, y + 1, dark if i % 2 else straw)
    c.line(2, 4, 4, 7, straw)
    c.line(13, 10, 14, 13, straw)
    return c.p


def haft_item():
    c = Canvas()
    c.line(3, 13, 12, 4, WOOD, 2)
    c.line(3, 14, 12, 5, WOOD_DARK)
    for x, y in ((6, 10), (7, 9), (8, 8)):
        c.dot(x, y, (176, 150, 96))
    return c.p


ITEMS = {
    "stick": lambda: rod(METALS["wooden"]),
    "plank": planks,
    "workbench": workbench,
    "chest": chest,
    "cord": cord,
    "haft": haft_item,
    "tinder": tinder,
    "fire_striker": striker,
    "unlit_campfire": lambda: campfire(False),
    "campfire_lit": lambda: campfire(True),
    "digging_stick": lambda: digging_stick(METALS["wooden"]),
    "ironwood_digging_stick": lambda: digging_stick(METALS["ironwood"]),
    "wooden_maul": lambda: maul(METALS["wooden"]),
    "ironwood_maul": lambda: maul(METALS["ironwood"]),
    "wooden_wedge": lambda: wedge(METALS["wooden"]),
    "ironwood_wedge": lambda: wedge(METALS["ironwood"]),
    "copper_pot": lambda: pot(METALS["copper"]),
}
for metal in ("bronze", "iron"):
    colours = METALS[metal]
    ITEMS[metal + "_pick"] = (lambda m: lambda: pick(m))(colours)
    ITEMS[metal + "_axe"] = (lambda m: lambda: axe(m))(colours)
    ITEMS[metal + "_spade"] = (lambda m: lambda: spade(m))(colours)
    ITEMS[metal + "_chisel"] = (lambda m: lambda: chisel(m))(colours)
    ITEMS[metal + "_hammer"] = (lambda m: lambda: hammer(m))(colours)
    ITEMS[metal + "_knife"] = (lambda m: lambda: knife(m))(colours)
    ITEMS[metal + "_sickle"] = (lambda m: lambda: sickle(m))(colours)
    ITEMS[metal + "_hoe"] = (lambda m: lambda: hoe(m))(colours)
for rock, colour in ROCKS.items():
    ITEMS["cracked_" + rock] = (lambda col: lambda: cracked(col))(colour)


# The kiln's things -----------------------------------------------------------

CLAY_WET = (132, 118, 104)
CLAY_FIRED = (178, 104, 70)
CLAY_FIRED_DARK = (128, 70, 46)
INGOTS = {
    "copper": COPPER, "tin": (196, 200, 204), "bronze": BRONZE,
    "silver": (214, 218, 224), "gold": (224, 186, 70), "lead": (96, 100, 112),
}


def ingot(colour):
    c = Canvas()
    dark = tuple(v * 70 // 100 for v in colour)
    light = tuple(min(255, v + 40) for v in colour)
    for row in range(6, 12):
        inset = 1 if row == 6 else 0
        c.line(2 + inset, row, 13 - inset, row, colour)
    c.line(3, 6, 12, 6, light)
    c.line(2, 12, 13, 12, dark)
    return c.p


def lump(colour, edge):
    c = Canvas()
    for row, (x0, x1) in enumerate([(6, 9), (4, 11), (3, 12), (3, 12), (4, 11), (5, 10)]):
        c.line(x0, row + 5, x1, row + 5, colour)
    c.line(5, 11, 10, 11, edge)
    return c.p


def pot_shape(colour, edge):
    c = Canvas()
    for row in range(5, 13):
        inset = abs(row - 8) // 2
        c.line(4 + inset, row, 11 - inset, row, colour)
    c.line(5, 4, 10, 4, edge)
    return c.p


def head_of(draw):
    """A tool's picture without its wooden haft: the cast head alone."""
    pixels = draw()
    wood = {WOOD + (255,), WOOD_DARK + (255,)}
    return [[(0, 0, 0, 0) if px in wood else px for px in row] for row in pixels]


def mould(shape_draw, clay, edge):
    """A slab of clay with the head's shape pressed into it."""
    c = Canvas()
    c.rect(1, 2, 14, 13, clay)
    c.line(1, 13, 14, 13, edge)
    head = head_of(shape_draw)
    for y in range(SIZE):
        for x in range(SIZE):
            if head[y][x][3] and 2 <= y <= 12 and 1 <= x <= 14:
                c.p[y][x] = edge + (255,)
    return c.p


def kiln_block(lit):
    c = Canvas()
    c.rect(0, 0, SIZE - 1, SIZE - 1, CLAY_FIRED if lit is not None else CLAY_WET)
    edge = CLAY_FIRED_DARK if lit is not None else (98, 86, 74)
    for y in (4, 9, 14):
        c.line(0, y, SIZE - 1, y, edge)
    c.rect(5, 9, 10, 13, (40, 30, 26))
    if lit:
        c.rect(6, 11, 9, 13, (250, 160, 30))
        c.line(7, 10, 8, 10, (255, 236, 150))
    return c.p


HEAD_SHAPES = {
    "pick": lambda: pick(METALS["bronze"]),
    "axe": lambda: axe(METALS["bronze"]),
    "spade": lambda: spade(METALS["bronze"]),
    "chisel": lambda: chisel(METALS["bronze"]),
    "hammer": lambda: hammer(METALS["bronze"]),
    "knife": lambda: knife(METALS["bronze"]),
    "sickle": lambda: sickle(METALS["bronze"]),
    "hoe": lambda: hoe(METALS["bronze"]),
    "pot": lambda: pot(METALS["copper"]),
}

ITEMS["charcoal"] = lambda: lump((38, 34, 34), (20, 18, 18))
ITEMS["charred_meat"] = lambda: lump((62, 40, 30), (30, 20, 16))
ITEMS["tin_grain"] = lambda: lump((70, 72, 78), (40, 42, 46))
ITEMS["gold_flake"] = lambda: lump((224, 186, 70), (160, 126, 40))


def sluice():
    c = Canvas()
    c.rect(0, 0, SIZE - 1, SIZE - 1, PLANK)
    for y in (3, 7, 11):
        c.line(1, y, 14, y, PLANK_DARK)
    c.line(0, 15, 15, 15, (80, 110, 150))
    c.line(0, 14, 15, 14, (110, 140, 180))
    return c.p


ITEMS["sluice"] = sluice


def torch(lit):
    """A stick standing in the middle of a clear block, a flame on it or a
    charred head: the block is cutout, so the clear part is not drawn."""
    c = Canvas()
    c.rect(7, 6, 8, 15, WOOD)
    c.line(7, 15, 8, 15, WOOD_DARK)
    c.rect(6, 5, 9, 6, (150, 120, 80))
    if lit:
        c.rect(7, 2, 8, 4, (250, 160, 30))
        c.rect(7, 1, 8, 2, (255, 236, 150))
        c.dot(6, 3, (236, 88, 20))
        c.dot(9, 3, (236, 88, 20))
    else:
        c.rect(6, 4, 9, 5, (40, 34, 30))
    return c.p


def bark():
    c = Canvas()
    c.line(3, 12, 12, 3, (96, 72, 50), 3)
    c.line(4, 12, 12, 4, (70, 52, 36))
    return c.p


def masonry(colour, mortar):
    c = Canvas()
    c.rect(0, 0, SIZE - 1, SIZE - 1, colour)
    for y in (3, 7, 11, 15):
        c.line(0, y, SIZE - 1, y, mortar)
    for row, y0 in enumerate((0, 4, 8, 12)):
        for x in ((5, 13) if row % 2 == 0 else (1, 9)):
            c.line(x, y0, x, y0 + 2, mortar)
    return c.p


def glass_block():
    c = Canvas()
    edge = (200, 220, 226)
    for y in range(SIZE):
        for x in range(SIZE):
            c.p[y][x] = (190, 214, 222, 60)
    for i in range(SIZE):
        for x, y in ((i, 0), (i, 15), (0, i), (15, i)):
            c.p[y][x] = edge + (200,)
    c.line(3, 6, 6, 3, (240, 248, 250))
    return c.p


def lantern():
    c = Canvas()
    iron, dark = IRON, IRON_DARK
    c.rect(4, 3, 11, 14, dark)
    c.rect(5, 5, 10, 12, (250, 190, 80))
    c.rect(7, 7, 8, 11, (255, 236, 150))
    c.line(4, 2, 11, 2, iron)
    c.line(7, 0, 8, 0, iron)
    c.line(4, 15, 11, 15, iron)
    return c.p


def gear(colour, dark):
    c = Canvas()
    for y in range(SIZE):
        for x in range(SIZE):
            dx, dy = x - 7.5, y - 7.5
            r2 = dx * dx + dy * dy
            if 9 < r2 < 30:
                c.p[y][x] = colour + (255,)
    for x, y in ((7, 1), (8, 1), (7, 14), (8, 14), (1, 7), (1, 8), (14, 7), (14, 8),
                 (3, 3), (12, 3), (3, 12), (12, 12)):
        c.dot(x, y, dark)
    return c.p


def plate():
    c = Canvas()
    c.rect(2, 5, 13, 11, IRON)
    c.line(2, 11, 13, 11, IRON_DARK)
    return c.p


def nails():
    c = Canvas()
    for x in (4, 7, 10):
        c.line(x, 4, x, 12, IRON)
        c.line(x - 1, 4, x + 1, 4, IRON_DARK)
    return c.p


def chain():
    c = Canvas()
    for i, (x, y) in enumerate(((2, 11), (5, 8), (8, 5), (11, 2))):
        c.rect(x, y, x + 3, y + 3, IRON if i % 2 == 0 else IRON_DARK)
        c.p[y + 1][x + 1] = (0, 0, 0, 0)
        c.p[y + 2][x + 2] = (0, 0, 0, 0)
    return c.p


def hinge():
    c = Canvas()
    c.rect(2, 4, 7, 12, IRON)
    c.rect(8, 4, 13, 12, IRON_DARK)
    c.line(7, 3, 7, 13, (60, 64, 72))
    return c.p


def frame():
    c = Canvas()
    c.rect(1, 1, 14, 14, IRON)
    c.rect(4, 4, 11, 11, (0, 0, 0))
    for y in range(4, 12):
        for x in range(4, 12):
            c.p[y][x] = (0, 0, 0, 0)
    for x, y in ((2, 2), (13, 2), (2, 13), (13, 13)):
        c.dot(x, y, IRON_DARK)
    return c.p


ITEMS["mudbrick"] = lambda: masonry((150, 120, 88), (112, 88, 62))
ITEMS["brick"] = lambda: masonry((160, 78, 58), (196, 182, 164))
ITEMS["glass"] = glass_block
ITEMS["iron_lantern"] = lantern
ITEMS["bronze_gear"] = lambda: gear(BRONZE, BRONZE_DARK)
ITEMS["iron_plate"] = plate
ITEMS["iron_nails"] = nails
ITEMS["iron_chain"] = chain
ITEMS["iron_hinge"] = hinge
ITEMS["iron_frame"] = frame
ITEMS["ash"] = lambda: lump((150, 148, 144), (110, 108, 104))
ITEMS["unfired_mould_gear"] = lambda: mould(lambda: gear(BRONZE, BRONZE_DARK), CLAY_WET, (98, 86, 74))
ITEMS["mould_gear"] = lambda: mould(lambda: gear(BRONZE, BRONZE_DARK), CLAY_FIRED, CLAY_FIRED_DARK)
def needle():
    c = Canvas()
    c.line(3, 13, 12, 4, (228, 222, 204))
    c.dot(12, 3, (200, 194, 176))
    c.dot(4, 12, (160, 150, 130))
    return c.p


def fabric(colour, dark):
    c = Canvas()
    c.rect(2, 4, 13, 12, colour)
    for y in (6, 9):
        c.line(2, y, 13, y, dark)
    c.line(13, 4, 13, 12, dark)
    return c.p


ITEMS["cured_meat"] = lambda: lump((150, 70, 60), (100, 44, 36))
ITEMS["leather"] = lambda: fabric((140, 96, 58), (98, 66, 40))
ITEMS["cloth"] = lambda: fabric((222, 214, 196), (180, 170, 150))
ITEMS["bone_needle"] = needle
ITEMS["iron_anvil"] = lambda: [[(px[0] * 70 // 150, px[1] * 80 // 138, px[2] * 100 // 132, px[3]) if px[3] else px for px in row] for row in anvil()]
ITEMS["torch"] = lambda: torch(True)
ITEMS["spent_torch"] = lambda: torch(False)
ITEMS["bark_strip"] = bark


def tuyere(colour, dark):
    c = Canvas()
    for row in range(5, 11):
        width = 10 - (row - 5)
        c.line(2, row, 2 + width, row, colour)
    c.line(2, 11, 8, 11, dark)
    c.dot(13, 8, dark)
    return c.p


def bellows():
    c = Canvas()
    c.rect(2, 4, 10, 11, PLANK)
    for y in (6, 9):
        c.line(3, y, 9, y, PLANK_DARK)
    c.line(11, 7, 14, 7, COPPER, 2)
    c.line(0, 7, 1, 7, WOOD_DARK)
    return c.p


def bloomery_block(lit):
    c = Canvas()
    c.rect(0, 0, SIZE - 1, SIZE - 1, CLAY_FIRED)
    c.rect(0, 0, SIZE - 1, 3, (112, 110, 104))
    for y in (7, 11):
        c.line(0, y, SIZE - 1, y, CLAY_FIRED_DARK)
    c.rect(6, 12, 9, 15, (40, 30, 26))
    c.rect(12, 8, 14, 9, BRONZE)
    if lit:
        c.rect(7, 13, 8, 15, (255, 236, 150))
    return c.p


def anvil():
    c = Canvas()
    c.rect(0, 0, SIZE - 1, SIZE - 1, (150, 138, 132))
    c.rect(0, 0, SIZE - 1, 3, (178, 168, 160))
    c.line(0, 4, SIZE - 1, 4, (98, 90, 86))
    c.rect(4, 5, 11, SIZE - 1, (132, 122, 116))
    return c.p


ITEMS["bronze_tuyere"] = lambda: tuyere(BRONZE, BRONZE_DARK)
ITEMS["copper_nozzle"] = lambda: tuyere(COPPER, COPPER_DARK)
ITEMS["bellows"] = bellows
ITEMS["bloomery"] = lambda: bloomery_block(False)
ITEMS["bloomery_lit"] = lambda: bloomery_block(True)
ITEMS["stone_anvil"] = anvil
ITEMS["iron_bloom"] = lambda: lump((92, 80, 76), (54, 46, 44))
ITEMS["iron_bar"] = lambda: ingot(IRON)
ITEMS["unfired_mould_tuyere"] = lambda: mould(lambda: tuyere(BRONZE, BRONZE_DARK), CLAY_WET, (98, 86, 74))
ITEMS["mould_tuyere"] = lambda: mould(lambda: tuyere(BRONZE, BRONZE_DARK), CLAY_FIRED, CLAY_FIRED_DARK)
IRON_SHAPES = {
    "pick": lambda: pick(METALS["iron"]),
    "axe": lambda: axe(METALS["iron"]),
    "spade": lambda: spade(METALS["iron"]),
    "chisel": lambda: chisel(METALS["iron"]),
    "hammer": lambda: hammer(METALS["iron"]),
    "knife": lambda: knife(METALS["iron"]),
    "sickle": lambda: sickle(METALS["iron"]),
    "hoe": lambda: hoe(METALS["iron"]),
}
for shape, draw in IRON_SHAPES.items():
    ITEMS["iron_" + shape + "_head"] = (lambda d: lambda: head_of(d))(draw)
ITEMS["fired_clay"] = lambda: lump(CLAY_FIRED, CLAY_FIRED_DARK)
ITEMS["unfired_crucible"] = lambda: pot_shape(CLAY_WET, (98, 86, 74))
ITEMS["crucible"] = lambda: pot_shape(CLAY_FIRED, CLAY_FIRED_DARK)
ITEMS["unfired_kiln"] = lambda: kiln_block(None)
ITEMS["kiln"] = lambda: kiln_block(False)
ITEMS["kiln_lit"] = lambda: kiln_block(True)
for metal, colour in INGOTS.items():
    ITEMS[metal + "_ingot"] = (lambda col: lambda: ingot(col))(colour)
for shape, draw in HEAD_SHAPES.items():
    ITEMS["unfired_mould_" + shape] = (lambda d: lambda: mould(d, CLAY_WET, (98, 86, 74)))(draw)
    ITEMS["mould_" + shape] = (lambda d: lambda: mould(d, CLAY_FIRED, CLAY_FIRED_DARK))(draw)
    if shape != "pot":
        ITEMS["bronze_" + shape + "_head"] = (lambda d: lambda: head_of(d))(draw)


# Drawn by hand, and never overwritten by a placeholder: add a name here
# when its picture is replaced with real art.
HAND_DRAWN = {
    "stick", "stone_anvil", "tin_grain", "tin_ingot", "tinder", "torch",
    "unfired_crucible", "unfired_kiln", "workbench", "wooden_maul", "wooden_wedge",
    "unfired_mould_axe", "unfired_mould_chisel", "unfired_mould_gear", "unfired_mould_hammer",
    "unfired_mould_hoe", "unfired_mould_knife", "unfired_mould_pick", "unfired_mould_pot",
    "unfired_mould_sickle", "unfired_mould_spade", "unfired_mould_tuyere",
}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    written = 0
    for name, draw in sorted(ITEMS.items()):
        if name in HAND_DRAWN:
            continue
        (OUT / (name + ".png")).write_bytes(png(draw()))
        written += 1
    print(f"wrote {written} textures to {OUT}, kept {len(HAND_DRAWN)} drawn by hand")


if __name__ == "__main__":
    main()
