# SPDX-FileCopyrightText: Iridesium
# SPDX-License-Identifier: GPL-3.0-only
"""The campfire models, from the hand-made one in art/campfire.glb.

The engine draws one material per model and reads no material colour: a
model is matte white unless it carries UVs and a PNG beside it. The source
is coloured by material (bark, cut wood, three flames and a hot core), so
this bakes those colours into a palette, one pixel a material, and gives
every vertex of a primitive the UV of its material's pixel. The geometry is
not touched.

Writes, into the mod:
  models/campfire_lit.glb     every primitive: the logs and the flames
  models/campfire_unlit.glb   the logs alone (the primitives without emission)
  models/campfire.png         the palette both use

stdlib only: run it again whenever art/campfire.glb changes.
"""

import json
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "art" / "campfire.glb"
OUT = ROOT / "mods" / "tiamat_default_craft" / "models"


def read_glb(path):
    data = path.read_bytes()
    magic, version, _ = struct.unpack_from("<4sII", data, 0)
    assert magic == b"glTF" and version == 2, "not a glTF 2 binary"
    at, doc, blob = 12, None, b""
    while at < len(data):
        length, kind = struct.unpack_from("<I4s", data, at)
        chunk = data[at + 8 : at + 8 + length]
        if kind == b"JSON":
            doc = json.loads(chunk)
        elif kind == b"BIN\x00":
            blob = chunk
        at += 8 + length
    return doc, bytearray(blob)


def write_glb(path, doc, blob):
    text = json.dumps(doc, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    blob = bytes(blob) + b"\x00" * (-len(blob) % 4)
    body = struct.pack("<I4s", len(text), b"JSON") + text + struct.pack("<I4s", len(blob), b"BIN\x00") + blob
    path.write_bytes(struct.pack("<4sII", b"glTF", 2, 12 + len(body)) + body)


def srgb(linear):
    """A glTF colour factor is linear; a PNG is sRGB."""
    c = max(0.0, min(1.0, linear))
    c = c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055
    return round(c * 255)


def png(width, height, pixels):
    raw = b"".join(b"\x00" + bytes(v for p in pixels[y * width : (y + 1) * width] for v in p) for y in range(height))

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def model(doc, blob, keep):
    """A copy of the source holding only the primitives `keep` says, each
    with a TEXCOORD_0 at its material's pixel of the palette."""
    doc = json.loads(json.dumps(doc))
    blob = bytearray(blob)
    width = len(doc["materials"])
    prims = []
    for prim in doc["meshes"][0]["primitives"]:
        material = prim.get("material", 0)
        if not keep(doc["materials"][material]):
            continue
        count = doc["accessors"][prim["attributes"]["POSITION"]]["count"]
        u, v = (material + 0.5) / width, 0.5
        offset = len(blob)
        blob += struct.pack("<ff", u, v) * count
        doc["bufferViews"].append({"buffer": 0, "byteOffset": offset, "byteLength": 8 * count, "target": 34962})
        doc["accessors"].append({"bufferView": len(doc["bufferViews"]) - 1, "componentType": 5126,
                                 "count": count, "type": "VEC2"})
        prim["attributes"]["TEXCOORD_0"] = len(doc["accessors"]) - 1
        prims.append(prim)
    doc["meshes"][0]["primitives"] = prims
    doc["buffers"][0]["byteLength"] = len(blob) + (-len(blob) % 4)
    return doc, blob


def main():
    doc, blob = read_glb(SOURCE)
    OUT.mkdir(parents=True, exist_ok=True)
    colours = []
    for material in doc["materials"]:
        r, g, b, a = material.get("pbrMetallicRoughness", {}).get("baseColorFactor", [1, 1, 1, 1])
        colours.append((srgb(r), srgb(g), srgb(b), 255))
    (OUT / "campfire.png").write_bytes(png(len(colours), 1, colours))
    lit = model(doc, blob, lambda m: True)
    write_glb(OUT / "campfire_lit.glb", *lit)
    unlit = model(doc, blob, lambda m: not any(m.get("emissiveFactor", [0, 0, 0])))
    write_glb(OUT / "campfire_unlit.glb", *unlit)
    print(f"wrote campfire_lit.glb ({len(lit[0]['meshes'][0]['primitives'])} parts), "
          f"campfire_unlit.glb ({len(unlit[0]['meshes'][0]['primitives'])} parts), campfire.png")


if __name__ == "__main__":
    main()
