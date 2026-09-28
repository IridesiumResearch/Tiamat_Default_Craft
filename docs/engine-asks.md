<!-- SPDX-FileCopyrightText: Iridesium -->
<!-- SPDX-License-Identifier: GPL-3.0-only -->

# Engine asks from the Craft mod

What the crafting layer has needed from the engine, found by planning and
building it. Each entry says what was wanted, why the mod cannot do it, and
the smallest engine change that would. Newest first. Landed items stay here,
marked, as the record; the open ones are copied, without the history, to the
engine's `docs/engine-asks/tiamat_default_craft.md`, so the engine side
finds every mod's open asks in one place.

Numbered as the brief (`docs/brief.md` §11) numbered them, from its audit of
the engine on 2026-09-26; 0 was found and answered the same day.

## Where these stand (2026-09-28)

| Item | State | In this mod |
|---|---|---|
| 6 a material's tags and hardness | Open. | the dig classes are a table beside the world's blocks (step 2). |
| 5 enumerating containers | Open. | stations keep an index of where they are in storage (step 4). |
| 4 a give into one slot of a player's view | Open. | a tool's wear lives in storage, keyed on its serial, not in its `detail` (step 2). |
| 3 a drop that depends on the tool | Open. | nothing drops by tool; a cracked block drops the ore it was (step 3). |
| 2 a tool's speed per material | Open. | a tool digs everything it may dig at one speed (step 2). |
| 1 a dig-start hook | Landed, engine ddc4fee. | the tool gate refuses as the dig starts (step 2). |
| 0 the default tool is the lowest id | Landed, engine ddc4fee. | the hand is this mod's without a fight; `conflicts = ["core_tools"]` stays for the reference chisel. |

## 6. A material's tags and hardness, read back (2026-09-26): OPEN

**Wanted.** `game.tags(material)` and `game.hardness(material)`, answering
what the block's registration said.

**Why the mod cannot.** Registration is write-only: the world declares its
rocks' hardness and could declare `tags = { "ore" }`, and no mod can read
either back. So the dig classes — which blocks want a pick, which want iron —
are a table in this mod naming the world's blocks one by one, and a block a
third mod adds is unclassed (diggable by anything) until somebody writes it
into the table through `classify`.

**Smallest change.** Two read-only lookups by numeric material. With the
world tagging its blocks (`docs/sibling-asks.md` W2) the table could become a
rule.

## 5. Enumerating containers (2026-09-26): OPEN

**Wanted.** `game.containers(prefix)`: the names of the containers that
exist, starting with a prefix.

**Why the mod cannot.** A kiln burns on the tick whether or not anybody is
looking, so the tick has to know where every kiln is. Containers persist
with the world and their names say where they are, but nothing lists them,
so the mod keeps its own index of station positions in `game.storage` —
a second record of a fact the engine already holds, which drifts the first
time the two disagree (a kiln placed by a stamped plan, say).

**Smallest change.** A listing by prefix; the engine already keys them by name.

## 4. A give into one slot of a player's view (2026-09-26): OPEN

**Wanted.** `game.give(player, { ..., slot = n })`, or a way to replace the
stack in one slot.

**Why the mod cannot.** A tool's wear belongs on the stack, in its
`detail`, where it would travel with the tool into a chest and out again.
But changing a `detail` is a take and a give, and the give lands wherever
the engine puts it — not necessarily the hotbar slot the player is holding,
so every dig would move the pick out of their hand. The wear lives in
`game.storage` under the tool's serial instead, which costs a storage key
per tool ever made.

**Smallest change.** A `slot` on `game.give` (and on `game.take`), as the
container calls already have.

## 3. A drop that depends on the tool (2026-09-26): OPEN

**Wanted.** A way for `on_dig_complete` to say what a dig yields — rubble by
hand, ore by pick.

**Why the mod cannot.** `drops` is fixed at registration; the hook can
refuse a dig but not change its yield. The design works round it: a block is
refused to the wrong tool rather than yielding less.

**Smallest change.** A `drops` table in the hook's answer, in units,
checked for conservation like any other.

## 2. A tool's speed per material (2026-09-26): OPEN

**Wanted.** `register_tool{ speeds = { ["mod:block"] = 2.5 } }`, or a speed
callback.

**Why the mod cannot.** Dig time is the block's hardness over the tool's one
`speed_multiplier`. A bronze pick is fast on rock and ought to be slow on
earth, and it digs both at one speed. The dig classes decide WHETHER; only
the engine could decide how fast per material.

**Smallest change.** An optional per-material table on the tool.

## 1. A dig-start hook: LANDED 2026-09-26 (engine ddc4fee)

A veto on digs, and nothing else, fired after the player had waited out the
dig. `game.register_on_dig_start` is asked the tick a dig begins, with the
same ladder, so "that wants a pick" reaches the player as they start.

## 0. The default tool is the lowest id: LANDED 2026-09-26 (engine ddc4fee)

`core_tools:hand` sorted before any hand this mod could name. The default is
now the lowest id among mods that are not reference mods, so a real mod's
hand wins whatever the ids. `conflicts = ["core_tools"]` stays in
`mod.toml` for the reference chisel and its `chisel_mode` action: this
mod's chisel is a craftable tool that wears, and a free one on the tool
key would go round it.
