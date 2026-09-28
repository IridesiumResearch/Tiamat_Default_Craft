<!-- SPDX-FileCopyrightText: Iridesium -->
<!-- SPDX-License-Identifier: GPL-3.0-only -->

# Asks of the sibling mods

What this mod needs from the OTHER default mods — the world, Life and the
interface — as `docs/engine-asks.md` holds what it needs from the engine.
Each says what was wanted, what stands in for it today, and the smallest
change that would answer it. Newest first within each mod.

## Tiamat Default Life

Life answered the first plan's asks before this mod existed: `add_food`,
`add_weapon`, `add_drop`, `add_feed`, `add_crop`, `add_harvest_tool`,
`add_tilling_tool` and `drop` are all exported (its `docs/exports.md`), and
its animals drop hide, bone and sinew. Its own asks of this mod (its
`docs/sibling-asks.md`, C1 the kitchen and C2 leather, cord and cloth) are
this mod's to build.

### L3. Who cooks (2026-09-26): SETTLED, built 2026-09-28

Life's roadmap once said "X while looking at a campfire cooks what you
hold". Cooking is this mod's (brief §6.2): the campfire, the kiln as an
oven, the pot and the stew, all handing out Life's own food items so its X
key eats them. Life's C1 says the same from its side.

Built as a box on the fire rather than a use of it: Life's use handler
eats any food in the hand at any block, and loads first, so meat in hand at
a fire is eaten before this mod hears of it. That is right and nothing is
asked of Life; a fire opens with an empty hand instead. Life's C1 is
answered for bread (the kiln, from wheat) and hot stew (a fire and a
copper pot); cured meat waits on a salt recipe.

### L1, L2, L4, L5: LANDED

`add_food` (L1), `add_weapon` (L2), `drop` (L4), and hide, bone and sinew
from the animals (L5). This mod will register its bronze and iron tools as
weapons, its charred meat and cured food as food, and its farm tools
through `add_tilling_tool` and `add_harvest_tool`, as the steps land.

## Tiamat Default Progress

Its asks of this mod (its `docs/sibling-asks.md`, C1 to C5), answered
2026-09-28, and three things back.

### C1 to C5: ANSWERED 2026-09-28

- **C5, a recipe that makes nothing:** `outputs = {}` is accepted, and
  `perform` hears it in `on_crafted` with an empty list; a `conserve` one is
  refused. The thirteen studies register.
- **C4, the iron frame:** `tiamat_default_craft:iron_frame`, as asked
  (step 10).
- **C3, the first events:** listed and frozen in `docs/exports.md`. Two
  names moved to Progress's: the bloom is `bloom:iron` (it was
  `smelt:iron`), and the anvil is `craft:tiamat_default_craft:stone_anvil`
  (it was `craft:anvil`); `wash:gold` is new.
- **C2, the effects:** every key read where it is used (the table in
  `docs/exports.md`) — through `set_effects`, below, not `effects_of`.
- **C1, gating from outside:** `set_requires(recipe_id, node)`, while mods
  load, on a recipe with no requirement.

### P1. Hand in `effects_of` (2026-09-28): OPEN, one line

**Wanted.** `craft.set_effects(function(uuid, prefix) return effects_of(uuid, prefix) end)`
at Progress's load, beside its `set_gate`.

**Why.** Progress lists Craft in `optional_depends`, so it loads after
Craft, and Craft cannot read an export of a mod that is not its
dependency; naming Progress back would be a cycle. So Craft takes the
function the way it takes the gate. Until it is called, every effect reads
0 — nothing breaks, nothing moves.

### P2. `study_iron` names an ingot that does not exist (2026-09-28): OPEN

**Wanted.** `tiamat_default_craft:iron_bar` (or `iron_bloom`) in
`study_iron`'s input. Iron is bloomed and wrought here, never an ingot; the
recipe registers and is logged as unmakeable the first time it is asked.

### P3. The charcoal clamp's sentence (2026-09-28): OPEN, words only

**Wanted.** Its text says "27 logs yields 12 charcoal, not 9", from the
brief's draft. Craft makes a charcoal of a log, one for one, and reads
`charcoal_yield` as three units a point: the node's `3` is a third more —
the brief's own ratio — which is "a log gives a third more charcoal".

## Tiamat Default World

### W4. White sand for glass (2026-09-26): OPEN, for step 10

**Wanted.** Confirmation that `white_sand` is the sand glass is made from.
Glass is after the loop; nothing waits on it yet.

### W3. Pitchblende (2026-09-26): OPEN, for the tech tree

**Wanted.** A `pitchblende` vein at 1,200 blocks and deeper, beside lead and
silver, where it really occurs. It is the one ore of the Schism design with
no block in the world. Nothing in this mod needs it; the tech tree's fission
does. (Zinc is not asked for: bronze gears stand in for brass ones.)

### W2. Tags on the world's blocks (2026-09-26): OPEN, nice to have

**Wanted.** `tags = { "ore" }`, `{ "rock" }`, `{ "log" }` on the world's
blocks, so that engine ask 6 — reading tags back — would have something to
read, and the dig classes could become a rule rather than a table.

### W1. Nothing required

This mod names the world's blocks and adds no planks per tree, on purpose:
it registers one generic `plank`, and the world keeps its rule of one of
each.

## Tiamat Default UI

### U3. The carved mask from the shape crafter (2026-09-26): OPEN, later

**Wanted.** The shape crafter's `chiselled` mask exported to a listener, so a
glyph registry (Schism §7.1, reserved here as `register_glyph`) could read
what a player carved.

### U2. An item grid on another mod's tab (2026-09-26): OPEN

**Wanted.** Confirmation that an `item_grid` naming a container works on a
tab another mod added, in a real window. The interface's README says the
path is untested. The Craft tab needs it for the workbench (step 4).

### U1. A dialog in the theme (2026-09-26): OPEN

**Wanted.** An `open_dialog_in_theme(player, form, tree)` helper, so a
station's own dialog wears the interface's frame without re-implementing it
from `theme` and `widgets`. A recipe export is NOT asked for: recipes live
in this mod's registry.
