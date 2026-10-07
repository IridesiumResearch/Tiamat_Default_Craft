# SPDX-FileCopyrightText: Iridesium
# SPDX-License-Identifier: GPL-3.0-only
"""Placeholder models for the stations whose look is no cube.

Each is a handful of boxes, in the style of the campfire's low-poly voxels,
coloured from one shared palette (models/stations.png): blocked out to read
as what it is, and meant to be replaced by a hand-made model the way the
campfire was. A model named in HAND_MADE is never written here.

Model space is the engine's: cells, three to a block, origin at the bottom
centre of the block, +Y up, +Z forward. A block is x and z in -1.5..1.5 and
y in 0..3. The shape each block occupies is in materials.lua beside it.

stdlib only. Writes models/<id>.glb and models/stations.png.
"""

import json
import struct
import zlib
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "mods" / "tiamat_default_craft" / "models"

# Replaced by hand: never overwritten here.
HAND_MADE = set()

PALETTE = {
    "granite": (128, 124, 118), "granite_dark": (94, 90, 86),
    "iron": (86, 88, 94), "iron_dark": (54, 56, 62),
    "wood": (128, 90, 52), "wood_dark": (92, 63, 36), "plank": (166, 124, 78),
    "clay_wet": (122, 104, 88), "cobble": (110, 108, 104),
    "clay": (170, 98, 64), "clay_dark": (122, 68, 46),
    "soot": (38, 32, 28), "glow": (255, 160, 50), "glow_core": (255, 226, 140),
    "glass": (236, 210, 140), "bronze": (178, 122, 62),
}
NAMES = list(PALETTE)


def anvil(face, dark):
    return [
        (-1.2, 0.0, -0.9, 1.2, 0.6, 0.9, dark),     # foot
        (-0.6, 0.6, -0.5, 0.6, 1.6, 0.5, face),     # waist
        (-1.4, 1.6, -0.7, 1.1, 2.3, 0.7, face),     # face
        (1.1, 1.75, -0.35, 1.5, 2.15, 0.35, dark),  # horn
    ]


def workbench():
    legs = [(x, z) for x in (-1.4, 1.0) for z in (-1.4, 1.0)]
    return [(-1.5, 2.4, -1.5, 1.5, 3.0, 1.5, "plank"),
            (-1.3, 0.8, -1.3, 1.3, 1.0, 1.3, "wood")] + [
        (x, 0.0, z, x + 0.4, 2.4, z + 0.4, "wood_dark") for x, z in legs]


def sluice():
    boxes = [(-1.5, 0.0, -1.5, 1.5, 0.4, 1.5, "plank"),
             (-1.5, 0.4, -1.5, -1.2, 1.6, 1.5, "wood"),
             (1.2, 0.4, -1.5, 1.5, 1.6, 1.5, "wood")]
    return boxes + [(-1.2, 0.4, z - 0.12, 1.2, 0.65, z + 0.12, "wood_dark") for z in (-0.9, 0.0, 0.9)]


def lantern():
    posts = [(x, z) for x in (-0.6, 0.45) for z in (-0.6, 0.45)]
    return [(-0.6, 0.0, -0.6, 0.6, 0.2, 0.6, "iron_dark"),
            (-0.45, 0.2, -0.45, 0.45, 1.25, 0.45, "glass"),
            (-0.65, 1.25, -0.65, 0.65, 1.45, 0.65, "iron_dark"),
            (-0.1, 1.45, -0.1, 0.1, 1.9, 0.1, "iron")] + [
        (x, 0.2, z, x + 0.15, 1.25, z + 0.15, "iron") for x, z in posts]


def kiln(body, base, lit):
    mouth = "glow" if lit else "soot"
    boxes = [(-1.5, 0.0, -1.5, 1.5, 1.0, 1.5, base),
             (-1.2, 1.0, -1.2, 1.2, 2.0, 1.2, body),
             (-0.8, 2.0, -0.8, 0.8, 2.6, 0.8, body),
             (-0.3, 2.6, -0.3, 0.3, 3.0, 0.3, "clay_dark"),
             (-0.5, 0.1, 1.5, 0.5, 0.8, 1.55, mouth)]
    if lit:
        boxes.append((-0.2, 2.95, -0.2, 0.2, 3.0, 0.2, "glow_core"))
    return boxes


def bloomery(lit):
    boxes = [(-1.2, 0.0, -1.2, 1.2, 0.9, 1.2, "clay"),
             (-0.9, 0.9, -0.9, 0.9, 2.6, 0.9, "clay"),
             (-1.0, 2.6, -1.0, 1.0, 3.0, 1.0, "clay_dark"),
             (0.9, 0.4, -0.15, 1.5, 0.7, 0.15, "bronze"),
             (-0.4, 0.1, 1.2, 0.4, 0.7, 1.25, "glow" if lit else "soot")]
    if lit:
        boxes.append((-0.6, 2.95, -0.6, 0.6, 3.0, 0.6, "glow_core"))
    return boxes


MODELS = {
    "stone_anvil": anvil("granite", "granite_dark"),
    "iron_anvil": anvil("iron", "iron_dark"),
    "workbench": workbench(),
    "sluice": sluice(),
    "iron_lantern": lantern(),
    "unfired_kiln": kiln("clay_wet", "cobble", False),
    "kiln": kiln("clay", "clay", False),
    "kiln_lit": kiln("clay", "clay", True),
    "bloomery": bloomery(False),
    "bloomery_lit": bloomery(True),
}

# Each face of a box: its normal, and its four corners as (x, y, z) picks of
# (low, high) per axis, counter-clockwise seen from outside.
FACES = [
    ((1, 0, 0), [(1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)]),
    ((-1, 0, 0), [(0, 0, 1), (0, 1, 1), (0, 1, 0), (0, 0, 0)]),
    ((0, 1, 0), [(0, 1, 0), (0, 1, 1), (1, 1, 1), (1, 1, 0)]),
    ((0, -1, 0), [(0, 0, 1), (0, 0, 0), (1, 0, 0), (1, 0, 1)]),
    ((0, 0, 1), [(1, 0, 1), (1, 1, 1), (0, 1, 1), (0, 0, 1)]),
    ((0, 0, -1), [(0, 0, 0), (0, 1, 0), (1, 1, 0), (1, 0, 0)]),
]


def mesh(boxes):
    pos, nor, uv, idx = [], [], [], []
    for x0, y0, z0, x1, y1, z1, colour in boxes:
        u = (NAMES.index(colour) + 0.5) / len(NAMES)
        lo, hi = (x0, y0, z0), (x1, y1, z1)
        for normal, corners in FACES:
            base = len(pos)
            for c in corners:
                pos.append(tuple((lo, hi)[c[a]][a] for a in range(3)))
                nor.append(normal)
                uv.append((u, 0.5))
            idx += [base, base + 1, base + 2, base, base + 2, base + 3]
    return pos, nor, uv, idx


def glb(boxes):
    pos, nor, uv, idx = mesh(boxes)
    blob = b"".join(struct.pack("<fff", *p) for p in pos)
    n_off = len(blob)
    blob += b"".join(struct.pack("<fff", *n) for n in nor)
    t_off = len(blob)
    blob += b"".join(struct.pack("<ff", *t) for t in uv)
    i_off = len(blob)
    blob += b"".join(struct.pack("<H", i) for i in idx)
    blob += b"\x00" * (-len(blob) % 4)
    lo = [min(p[a] for p in pos) for a in range(3)]
    hi = [max(p[a] for p in pos) for a in range(3)]
    doc = {
        "asset": {"version": "2.0", "generator": "tiamat_default_craft tools/make_models.py"},
        "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0}],
        "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2}, "indices": 3}]}],
        "buffers": [{"byteLength": len(blob)}],
        "bufferViews": [
            {"buffer": 0, "byteOffset": 0, "byteLength": n_off, "target": 34962},
            {"buffer": 0, "byteOffset": n_off, "byteLength": t_off - n_off, "target": 34962},
            {"buffer": 0, "byteOffset": t_off, "byteLength": i_off - t_off, "target": 34962},
            {"buffer": 0, "byteOffset": i_off, "byteLength": 2 * len(idx), "target": 34963},
        ],
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": len(pos), "type": "VEC3", "min": lo, "max": hi},
            {"bufferView": 1, "componentType": 5126, "count": len(nor), "type": "VEC3"},
            {"bufferView": 2, "componentType": 5126, "count": len(uv), "type": "VEC2"},
            {"bufferView": 3, "componentType": 5123, "count": len(idx), "type": "SCALAR"},
        ],
    }
    text = json.dumps(doc, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    body = struct.pack("<I4s", len(text), b"JSON") + text + struct.pack("<I4s", len(blob), b"BIN\x00") + blob
    return struct.pack("<4sII", b"glTF", 2, 12 + len(body)) + body


def png(pixels):
    raw = b"\x00" + bytes(v for p in pixels for v in (*p, 255))

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", len(pixels), 1, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "stations.png").write_bytes(png([PALETTE[n] for n in NAMES]))
    written = 0
    for name, boxes in sorted(MODELS.items()):
        if name in HAND_MADE:
            continue
        (OUT / (name + ".glb")).write_bytes(glb(boxes))
        written += 1
    print(f"wrote {written} models and stations.png to {OUT}, kept {len(HAND_MADE)} made by hand")


if __name__ == "__main__":
    main()
