# SPDX-FileCopyrightText: Iridesium
# SPDX-License-Identifier: GPL-3.0-only
"""Generates the placeholder sounds for mods/tiamat_default_craft/sounds.

Four short clips, synthesised: a tool breaking (a crack of noise and a
falling knock), an anvil ringing (a struck bar's partials, decaying), meat
sizzling (a hiss that crackles), and a craft (a soft wooden knock). Each is
bound to a cue of the same name, so a sound pack replaces one by binding
its own, and the files are meant to be replaced.

Standard library only; the noise is a fixed LCG, so the bytes are the same
on every machine. WAV straight from `wave`, one fmt chunk and nothing
trailing, which is what the engine's strict reader wants. Run from the
repository root:

    python tools/make_sounds.py
"""
import math
import struct
import wave
from pathlib import Path

RATE = 22050
OUT = Path(__file__).resolve().parent.parent / "mods" / "tiamat_default_craft" / "sounds"


def noise(seed):
    state = seed & 0xFFFFFFFF
    while True:
        state = (state * 1664525 + 1013904223) & 0xFFFFFFFF
        yield state / 2147483648.0 - 1.0


def write(name, samples):
    OUT.mkdir(parents=True, exist_ok=True)
    peak = max(1e-9, max(abs(s) for s in samples))
    frames = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s / peak * 0.8)) * 32767)) for s in samples)
    with wave.open(str(OUT / (name + ".wav")), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(frames)


def tool_break():
    n = noise(7)
    out = []
    for i in range(int(RATE * 0.45)):
        t = i / RATE
        crack = next(n) * math.exp(-t * 40.0)
        knock = math.sin(2 * math.pi * (220 - 120 * t) * t) * math.exp(-t * 9.0) * 0.6
        out.append(crack + knock)
    return out


def anvil_ring():
    out = []
    partials = [(1180.0, 1.0, 3.0), (2710.0, 0.5, 4.5), (4380.0, 0.3, 7.0), (590.0, 0.25, 2.2)]
    n = noise(11)
    for i in range(int(RATE * 1.4)):
        t = i / RATE
        s = sum(a * math.sin(2 * math.pi * f * t) * math.exp(-t * d) for f, a, d in partials)
        s += next(n) * math.exp(-t * 90.0) * 0.8
        out.append(s)
    return out


def sizzle():
    n = noise(23)
    out = []
    prev = 0.0
    for i in range(int(RATE * 0.9)):
        t = i / RATE
        raw = next(n)
        hiss = raw - prev * 0.6
        prev = raw
        env = min(1.0, t * 20.0) * math.exp(-t * 2.2)
        pop = (1.0 if (i * 7919) % 2203 < 18 else 0.0) * next(n)
        out.append(hiss * env * 0.5 + pop * env)
    return out


def craft():
    out = []
    n = noise(31)
    for i in range(int(RATE * 0.22)):
        t = i / RATE
        out.append(math.sin(2 * math.pi * 330 * t) * math.exp(-t * 30.0) + next(n) * math.exp(-t * 120.0) * 0.4)
    return out


SOUNDS = {"tool_break": tool_break, "anvil_ring": anvil_ring, "sizzle": sizzle, "craft": craft}


def main():
    for name, make in sorted(SOUNDS.items()):
        write(name, make())
    print(f"wrote {len(SOUNDS)} sounds to {OUT}")


if __name__ == "__main__":
    main()
