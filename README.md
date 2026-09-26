<!-- SPDX-FileCopyrightText: Iridesium -->
<!-- SPDX-License-Identifier: GPL-3.0-only -->

# Tiamat Default Craft

The crafting layer of the default game: recipes, a chest, a kiln for the
world's ores, cooking, and tools with wear. The mod itself is
`mods/tiamat_default_craft/`; this repository sits beside the engine
(`Tiamat`) and its four siblings, and the engine's `bundle.toml` pins the
commit a release carries.

A Tiamat mod, started from the engine's template. It registers one of each
kind of thing the API offers — a block, a tool, a sound, an action, a dialog,
an entity — so every part has a worked example beside it. Keep what you need.

## What is here

| File | What |
|---|---|
| `mod.toml` | The manifest: id, name, version, licence, and what this mod depends on or conflicts with. |
| `init.lua` | Runs once at load. Everything is registered here; the hooks it installs run for ever after. |
| `textures/block.png` | The beacon's face, 16 by 16. |
| `sounds/ping.wav` | The beacon's sound. WAV or Ogg Vorbis. |
| `../../stubs/game.lua` | The whole mod API as editor annotations, vendored from the engine. Documentation and completion in one file. |
| `../../AGENTS.md` | How to write a mod, for an AI coding assistant and the person supervising it. |
| `../../.luarc.json` | Points a Lua language server at `stubs/`. |

## Try it

Check it without starting a server — a second, no world left behind:

```sh
server --check-mods <the directory this mod is in>
```

It prints the mods it found in load order and every block they registered;
a mod with a mistake in it is named, with the line.

Then put this directory in the server's mods directory (`mods_path` in the
server's config; `game/` in the engine repository) and start the server. In
the world: dig anything with the hand, place a beacon, use it, and press the
wave key (J unless you moved it) for the dialog.

## Your editor

Any editor with the Lua language server reads `.luarc.json` and gets
completion, signatures and types for every `game.*` call from `stubs/game.lua`.
The stubs are kept in step with the engine by its CI, so when you update the
engine, copy its `api/stubs/game.lua` over yours.

## Where to read next

- `AGENTS.md` — the rules that fail quietly when broken, and the shape of every
  kind of thing a mod can register.
- `stubs/game.lua` — every function, with the reason it behaves as it does.
- The engine repository's `game/` directory — reference mods, each the
  smallest thing that proves one mechanism.

## Licence

GPL-3.0-only, © Iridesium, with an Additional Permission under GPLv3 §7 in
`LICENSE.EXCEPTION` (version 1.0, 24 September 2026): a mod that interacts
with Tiamat Default Craft only through its exports, the engine's scripting API or
the network protocol is an independent work and may be licensed however
its author likes. Copying or adapting this mod's code or assets is not
covered by that permission and stays under the GPL. `docs/exports.md`
lists the exports; the engine's `MOD-LICENSING.md` has the plain-language
version and a matrix of what needs which permission. Third-party assets
are listed in `docs/assets.md` with their own licences. Contributions are
taken under the Developer Certificate of Origin with authors retaining
copyright; see `CONTRIBUTING.md`.
