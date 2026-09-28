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

**Every ask has landed.** 2 to 7 in engine c83fbc9, 8 and 9 in engine
cbbbc5e. None is adopted in the mod yet; the table says what each would
replace.

| Item | State | In this mod |
|---|---|---|
| 9 reading one slot of a player's view | Landed, engine cbbbc5e. | not yet adopted: the anvil is still a station you open and strike. | the anvil takes its work from its own container, struck with a hammer, not from the off-hand (step 8). |
| 8 a use at a block reaching the block's handler first | Landed, engine cbbbc5e. | not yet adopted: a fire is still opened with an empty hand. | a fire is opened with an empty hand and food is put in its box, not held over it (step 6). |
| 7 a drop of another mod's material | Landed, engine c83fbc9. | not yet adopted: a cracked block still drops nothing and hands the rock over. |
| 6 a material's tags and hardness | Landed, engine c83fbc9. | not yet adopted: the dig classes are still a table. |
| 5 enumerating containers | Landed, engine c83fbc9. | not yet adopted: stations still keep their own index. |
| 4 a give into one slot of a player's view | Landed, engine c83fbc9. | not yet adopted: wear still lives in storage. |
| 3 a drop that depends on the tool | Landed, engine c83fbc9. | nothing needs it yet. |
| 2 a tool's speed per material | Landed, engine c83fbc9. | not yet adopted: a tool digs at one speed. |
| 1 a dig-start hook | Landed, engine ddc4fee. | the tool gate refuses as the dig starts (step 2). |
| 0 the default tool is the lowest id | Landed, engine ddc4fee. | the hand is this mod's without a fight; `conflicts = ["core_tools"]` stays for the reference chisel. |

## 9. Reading one slot of a player's view (2026-09-28): LANDED 2026-09-28 (engine cbbbc5e)

`game.slot(player, view, n)`, one-based, answering what `game.held` answers
or nil. With ask 4's `slot` on `take` and `give`, the anvil can read slot
28 (the off-hand), take the bloom from it and give the bar back into it.
The history follows.

**Wanted.** The stack in one slot of a player's view, and a take from that
slot alone: `game.slot(player, "player:main", 28)` answering `{ material,
units, shape, detail }` or nil, and `game.take(player, { ..., slot = 28 })`.
Slot 28 of `player:main` is the off-hand.

**Why the mod cannot.** The brief's anvil is worked in the world: the
hammer in the main hand, the bloom or bar in the off-hand, a right-click
a blow. `game.held` answers the main hand only, and `game.inventory`
answers a view CONSOLIDATED, one entry per material, cut and detail, with
no slot in it — so there is no way to ask what is in the off-hand, and a
`game.take` of a bar takes bars from wherever they are, not from the hand
the player is holding it in. A HUD script is told `state.offhand`, which
proves the engine has the answer; the server-side API does not ask it.

**Meanwhile.** The anvil is a station with a container: the work goes on it
through its screen, where the player also chooses what to forge, and each
use with a hammer in hand is a blow (`anvil.lua`). It works; it is a screen
where the brief wanted a gesture.

**Smallest change.** A slot-addressed read of a view, and `slot` on
`game.take` (ask 4 asks the same of `game.give`). With both, the anvil
reads the off-hand, takes the bloom from it, and gives the bar back into it.

## 8. A use at a block reaching the block's handler first (2026-09-28): LANDED 2026-09-28 (engine cbbbc5e)

`game.register_on_use(fn, { materials = { ... } })`, the first form asked
for: a handler with a list is asked about a use at one of those blocks
before any handler without one, and about no other block. A bare id is
the mod's own; `anywhere = true` beside it still hears uses at nothing.
The history follows.

**Wanted.** A player holding raw meat right-clicks a burning campfire and
the meat goes over the fire — the gesture the brief designed cooking
around (§6.2). More generally: a use AT a block reaches the handler of
THAT block before handlers that act on whatever is held, wherever it is.

**Why the mod cannot.** `register_on_use` callbacks are asked in mod load
order and the first to handle a use stops the rest. Life loads before
this mod (Craft names Life in `optional_depends`, on purpose, to read its
exports) and registers `{ anywhere = true }` to eat food held at any block
or at the sky; so meat held at a fire is eaten before this mod hears of the
use. Neither order is wrong for its own mod, and a mod cannot reorder the
chain: loading Craft first would cost it Life's exports, and asking Life to
look at every block for somebody else's cooking surface is a list that
never ends.

**Meanwhile.** A fire has a container: used with an empty hand it opens,
food is put on it through the screen, and it cooks while it burns
(`cooking.lua`). Nothing contends with Life's eating; the gesture is lost.

**Smallest change.** Either of:

- a use handler registered for particular materials —
  `game.register_on_use(fn, { materials = { "tiamat_default_craft:campfire_lit", ... } })` —
  asked, in load order among themselves, before any handler without a
  material list, so the block that was clicked answers first and a held
  item's handler hears only what no block claimed; or
- a pass order on the option, `{ before_anywhere = true }`, for a callback
  that only ever handles uses at blocks it owns.

The first needs no mod to know about any other, and is what a door, a
lever or a cooking surface all want.

## 7. A drop of another mod's material (2026-09-28): LANDED 2026-09-28 (engine c83fbc9)

A `drops` key may name any qualified id, resolved once every mod has
registered; and `drops` is now applied at all (it never was). The history
follows.

**Wanted.** `register_block{ drops = { ["tiamat_default_world:stone"] = 27 } }`
on this mod's `cracked_stone`: fire-cracked rock yields the rock it was.

**Why the mod cannot.** `drops` keys are qualified against the registering
mod and a foreign namespace is refused at registration ("may not register
into namespace"). That rule is right for REGISTERING into another mod's
namespace and wrong for NAMING one: a drop is a reference, and the world's
stone exists. So the cracked blocks drop nothing and `on_dig_complete`
gives the digger the rock — one unit per cell the dig took — which goes
straight into the inventory, never onto the ground, where a mod watching
drops will not see it.

**Smallest change.** Let a `drops` key name any qualified id, resolved when
every mod has registered, as `absorbs.becomes` already is.

## 6. A material's tags and hardness, read back (2026-09-26): LANDED 2026-09-28 (engine c83fbc9)

`game.hardness(material)` and `game.tags(material)`; `tags` on
`register_block` is kept. The history follows.

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

## 5. Enumerating containers (2026-09-26): LANDED 2026-09-28 (engine c83fbc9)

`game.containers(prefix)`. The history follows.

**Wanted.** `game.containers(prefix)`: the names of the containers that
exist, starting with a prefix.

**Why the mod cannot.** A kiln burns on the tick whether or not anybody is
looking, so the tick has to know where every kiln is. Containers persist
with the world and their names say where they are, but nothing lists them,
so the mod keeps its own index of station positions in `game.storage` —
a second record of a fact the engine already holds, which drifts the first
time the two disagree (a kiln placed by a stamped plan, say).

**Smallest change.** A listing by prefix; the engine already keys them by name.

## 4. A give into one slot of a player's view (2026-09-26): LANDED 2026-09-28 (engine c83fbc9)

`slot` on `game.give` and `game.take`, one-based; into a named slot the
stack goes whole or not at all. The history follows.

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

## 3. A drop that depends on the tool (2026-09-26): LANDED 2026-09-28 (engine c83fbc9)

`on_dig_complete` may answer `{ drops = { ["mod:id"] = units } }` for that
dig alone. The history follows.

**Wanted.** A way for `on_dig_complete` to say what a dig yields — rubble by
hand, ore by pick.

**Why the mod cannot.** `drops` is fixed at registration; the hook can
refuse a dig but not change its yield. The design works round it: a block is
refused to the wrong tool rather than yielding less.

**Smallest change.** A `drops` table in the hook's answer, in units,
checked for conservation like any other.

## 2. A tool's speed per material (2026-09-26): LANDED 2026-09-28 (engine c83fbc9)

`register_tool{ speeds = { ["mod:block"] = n } }`. The history follows.

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
