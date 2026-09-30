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

### L9. `steady` on bread and `hearty` on hot stew, in Life's own items (2026-09-28): ANSWERED (Life `da87daf`)

**Wanted.** Life's C1 asked Craft to register bread with `steady` and a
stew with `hearty`. But the bread and hot stew Craft makes are Life's own
items (`tiamat_default_life:bread`, `:hot_stew`), and `add_food` on them
from here would replace Life's whole definition — its food, saturation,
warmth — with numbers this mod has no business choosing. The effects belong
in Life's own `items.lua` definitions of the two.

**Answered** 2026-09-28, in Life `da87daf`: bread gives `steady` and hot
stew `hearty`, in Life's own definitions, with nothing needed from here.

### Life's C1 and C2, its asks of this mod: BUILT 2026-09-28

- **C1, the kitchen:** bread (the kiln, three wheat), hot stew (a fire and
  a copper pot) and cured meat (raw meat and salt at the workbench, this
  mod's own item, food through `add_food`). The buffs are L9, above.
- **C2, leather, cord and cloth:** leather (a hide tanned with two bark
  strips), cord from sinew, cloth from wool, a bone needle, and Life's own
  warm coat, cool cloak and bandages sewn from them; bellows of leather, as
  the brief first had them. Not built: bowstrings (no mod has a bow) and "a
  bed that is not a block" (Life's bed is Life's). Feathers have no use yet.

### L3. Who cooks (2026-09-26): SETTLED, built 2026-09-28

Life's roadmap once said "X while looking at a campfire cooks what you
hold". Cooking is this mod's (brief §6.2): the campfire, the kiln as an
oven, the pot and the stew, all handing out Life's own food items so its X
key eats them. Life's C1 says the same from its side.

Built as the brief had it once the engine allowed (its asks 8 and 10):
this mod's handler for its fires is asked before Life's eating, so meat
held out over a burning fire goes on it, and a fire's box opens with an
empty hand. Nothing was asked of Life. Life's C1 is
answered for bread (the kiln, from wheat) and hot stew (a fire and a
copper pot); cured meat waits on a salt recipe.

### L1, L2, L4, L5: LANDED

`add_food` (L1), `add_weapon` (L2), `drop` (L4), and hide, bone and sinew
from the animals (L5). This mod will register its bronze and iron tools as
weapons, its charred meat and cured food as food, and its farm tools
through `add_tilling_tool` and `add_harvest_tool`, as the steps land.

## Tiamat Default Science and Tiamat Default Magic

Their asks of this mod (each one's `docs/sibling-asks.md`, C-S1 to C-S7 and
C-M1 to C-M10; where the two asked the same thing it was answered once).
Everything is in `docs/exports.md`, and `tests/native/fixtures/frames.lua`
uses each the way they will.

### C-S1 to C-S7, C-M1 and C-M5 to C-M9: ANSWERED 2026-09-30

- **C-S1, a station run by a predicate:** `register_station{ runs =
  fn(container) }`, a speed in per cent; this mod keeps the job and makes
  the recipe. Science's frames need no job loop of their own.
- **C-S2, a boost that needs power:** `boost = { tool, heat, when =
  fn(container) }`; only `true` boosts.
- **C-S3 / C-M1, a glyph as an ingredient or a tool:** `{ glyph, material,
  count }` in `inputs` or `tools`. Carved stacks are still never
  ingredients unless a recipe names their glyph.
- **C-S5 / C-M7, idempotent glyphs:** the same mask with the same id again
  is `true`.
- **C-S6, lighting a fire:** `ignite(pos, uuid)`, for a laid campfire or an
  unlit heat station with fuel in it.
- **C-S7, unattended perform:** `perform(uuid, id, container, { unattended
  = true })`.
- **C-M5, time while unloaded** (as narrowed 2026-09-30): `long = true` on
  a heat station; the missed ticks are worked when it is next loaded, fuel
  permitting. The longer `max_ticks` of the original ask was not built,
  since the narrowing withdrew it.
- **C-M6:** `add_progress(container, ticks)`, at a heat station or a
  running one.
- **C-M8:** `craft.fuel_percent` is read at every heat station a player
  lit, not only the kiln. Progress's kiln node text will want to say so.
- **C-M9:** option (b), `on_crafted` passes the container as a fourth
  argument.

**C-M10, a slow fire,** was withdrawn before it was built, and C-S4 before
that; nothing was done for either.

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

### P1, P2, P3: ANSWERED (Progress ec121b6)

Progress's `craft.lua` calls `set_effects` right after `set_gate`, so node
effects are live; `study_iron` takes one `iron_bloom`; and the charcoal
clamp reads "A log gives a third more charcoal." Nothing either mod asked
of the other is open. The asks as they were:

### P1. Hand in `effects_of` (2026-09-28): ANSWERED

**Wanted.** `craft.set_effects(function(uuid, prefix) return effects_of(uuid, prefix) end)`
at Progress's load, beside its `set_gate`.

**Why.** Progress lists Craft in `optional_depends`, so it loads after
Craft, and Craft cannot read an export of a mod that is not its
dependency; naming Progress back would be a cycle. So Craft takes the
function the way it takes the gate. Until it is called, every effect reads
0 — nothing breaks, nothing moves.

### P2. `study_iron` names an ingot that does not exist (2026-09-28): ANSWERED

**Wanted.** `tiamat_default_craft:iron_bar` (or `iron_bloom`) in
`study_iron`'s input. Iron is bloomed and wrought here, never an ingot; the
recipe registers and is logged as unmakeable the first time it is asked.

### P3. The charcoal clamp's sentence (2026-09-28): ANSWERED

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

### W2. Tags on the world's blocks (2026-09-26): ANSWERED (World 0e5db57)

World tags every block (`blocks.lua`, `TAGS`), most particular word first,
and this mod now classes the world's blocks by them: its table naming them
one by one is gone but for four exceptions, where it reads a block
otherwise than its tags (flint is cracked, bone rock, dead logs and marrow
loose). Committed in World 0e5db57; a World from before it leaves every
block of it unclassed, which this mod says in the log at load.

The ask as it was:

**Wanted.** `tags = { "ore" }`, `{ "rock" }`, `{ "log" }` on the world's
blocks, so that engine ask 6 — reading tags back — would have something to
read, and the dig classes could become a rule rather than a table.

### W1. Nothing required

This mod names the world's blocks and adds no planks per tree, on purpose:
it registers one generic `plank`, and the world keeps its rule of one of
each.

## Tiamat Default UI

### The interface's C1 and C2, its asks of this mod: BUILT 2026-09-29

- **C1, a recipe for the shape crafter:** at the workbench, four planks and
  four cobbles, both within reach of the wood tier. The output is the id the
  interface exports as `shape_crafter`, so the recipe is only there when the
  interface is (`recipes.lua`).
- **C2, the hand tab beside Inventory:** the Craft tab is `order = 20`, the
  place the interface's own Crafting tab had (`stations.lua`).

### U3. The carved mask from the shape crafter (2026-09-26): WITHDRAWN 2026-09-28

The glyph registry (`register_glyph`, `glyph_of`) is built without it: a
block carved in the shape crafter is a stack with a `shape`, which is the
mask, so a glyph is read off the stack a player holds or puts down. Nothing
is needed from the interface. The ask as it was:

**Wanted.** The shape crafter's `chiselled` mask exported to a listener, so a
glyph registry (Schism §7.1, reserved here as `register_glyph`) could read
what a player carved.

### U2. An item grid on another mod's tab (2026-09-26): ANSWERED

**Wanted.** Confirmation that an `item_grid` naming a container works on a
tab another mod added, in a real window. The interface's README says the
path is untested. The Craft tab needs it for the workbench (step 4).

**Answered.** An `item_grid` with `view` set to a container's name passes
through a tab untouched; the interface's native check now carries one
(`addon:bench:1,2,3`) to the engine's checker. The container stays lent to
the player until their screen sends `Closed`, or they leave, so switching
tabs and every redraw keep it open, and shift-click moves between it and
`player:main`. Order: `make_container`, `open_container` (false means
somebody else has it), then `ui.open(player, "<your tab id>")`. Not yet seen
in a real window; the first workbench will be.

### U1. A dialog in the theme (2026-09-26): ANSWERED, nothing to add

**Wanted.** An `open_dialog_in_theme(player, form, tree)` helper, so a
station's own dialog wears the interface's frame without re-implementing it
from `theme` and `widgets`. A recipe export is NOT asked for: recipes live
in this mod's registry.

**Answered.** Any dialog already wears it: the interface's `[theme]` is the
engine's, and the engine frames EVERY sheet with it and sets its fonts, a
station's own `show_dialog` included. For the rest, build the tree with
`ui.widgets` and `ui.theme.colours` and it matches the inventory exactly.
