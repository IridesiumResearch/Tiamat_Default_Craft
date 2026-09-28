<!-- SPDX-FileCopyrightText: Iridesium -->
<!-- SPDX-License-Identifier: GPL-3.0-only -->

# Tiamat Default Craft

The crafting layer for the [Tiamat](https://github.com/IridesiumResearch/Tiamat-Voxel-Game)
voxel engine, and the first loop a player climbs: **gather → fire → smelt →
cast or forge → dig faster, deeper**. Recipes and the stations that run
them, a chest, fire, cooking, and tools that wear.

The ladder is not Minecraft's. There are no stone tools and no diamond
tools: it runs **wood → bronze → iron**, and it is climbed the way people
climbed it. Fire cracks rock before any pick does, copper is found green on
the surface, tin is washed out of river gravel, bronze is cast into clay
moulds, and iron is bloomed and hammered.

Written against the engine's public Lua API and nothing else. The rules that
shape it are in [`AGENTS.md`](AGENTS.md) (vendored from the engine's `api/`),
and [`stubs/game.lua`](stubs/game.lua) is the API itself. The design is
[`docs/brief.md`](docs/brief.md).

## Where it is

Built in the brief's order (§12), each step shipping on its own:

| Step | What | State |
|---|---|---|
| 1 | The recipe, station and fuel registry, `perform` with rollback, exported | **done** |
| 2 | Tools: the hand, held → tool sync, dig classes, wear | **done** |
| 3 | Fire: the unlit campfire, the striker, fuel, fire-setting | **done** |
| 4 | Workbench, the Craft tab, the chest | **done** |
| 5 | The kiln: heat, ceramics, charcoal, copper, tin, bronze, casting | **done** |
| 6 | Cooking | **done** |
| 7 | The sluice | **done** |
| 8 | Bloomery, bellows, anvil: iron | **done** |
| 9 | Torch, HUD, sounds, the ladder written down (`0.2.0`) | next |
| 10 | After the loop: parts, brick, glass, lantern (`0.3.0`) | |

Today a player can start from nothing: break flint out by hand, rub
tinder from dry grass, split sticks from a log, lay a campfire and strike it
alight (`craft fire_striker`, `craft tinder`, `craft stick`, `craft
unlit_campfire`). A burning fire cracks the rock around it in thirty
seconds, and cracked rock and ore come away by hand, whole. Feed it logs
or it goes out. Cord from brambles and a workbench of logs, by hand; at
the bench, planks split with a wedge, hafts, digging sticks, mauls, and a
chest. V opens the Craft tab (the interface's, when it is here). A kiln of wet clay
and cobbles, fired by its first fire, turns logs to charcoal at red heat,
and at orange heat (coal or charcoal) smelts ore in a crucible, alloys nine
of copper to one of tin, and casts bronze heads into clay moulds that crack
after four pours; a head and a haft at the workbench are a bronze tool.
**Wood → fire → bronze is a complete loop.** A fire opens with an empty
hand: meat put on it roasts (and chars if left), meat and fruit in a copper
pot become Life's hot stew, and the kiln bakes Life's bread from wheat. A sluice of planks stood in a
river washes gravel into sand and tin grains, and now and then a flake of
gold, so bronze does not wait on a deep mine. Iron is bloomed: a bloomery of
fired clay and stone with a bronze tuyere, charcoal only, burns white with
bellows, and ore and charcoal become a bloom; on an anvil squared from
granite with a bronze chisel, a bloom is beaten into a wrought bar, and bars
into iron heads with an iron hammer — the first of which is forged with
bronze. Every tool of the ladder exists and works — typed, tiered and worn,
with a sentence for each refusal — and every one is made in the world now; `toolkit` is only for trying them. Bare hands move
earth, sand, clay and soft logs; rock wants a bronze pick, and the hard
rocks iron. Another mod can register stations, recipes, tools and dig
classes, and make them.

## Layout

```
mods/tiamat_default_craft/   the mod (this is what the engine loads)
  mod.toml                   manifest
  init.lua                   load order only
  config.lua                 every number a designer might turn
  util.lua                   helpers with no opinion about the game
  hooks.lua                  one engine registration per hook, many subscribers
  registry.lua               recipes, groups, stations, fuels, the gate; perform
  materials.lua              the items and blocks this mod registers
  tools.lua                  the hand, the tools, held → tool, dig classes, wear
  fire.lua                   campfires: lighting, fuel, burning out, fire-setting
  screens.lua                dialog trees, in Tiamat Default UI's look when present
  stations.lua               stations and chests in the world; the Craft tab and V
  furnace.lua                stations that burn: lighting, fuel, heat, jobs
  cooking.lua                what a campfire cooks
  sluice.lua                 tin washed out of river gravel
  anvil.lua                  iron worked by blows
  recipes.lua                this mod's own stations and recipes, as data
  commands.lua               chat words: `recipes`, `craft`
  exports.lua                what other mods may call (docs/exports.md)
  textures/*.png             placeholders from tools/make_textures.py
tests/native/                the mod run through the engine's real script VM
tools/make_textures.py       the placeholder pictures (stdlib Python only)
docs/brief.md                the design
docs/exports.md              what this mod exports: the licence boundary
docs/engine-asks.md          what this mod needed from the engine and could not get
docs/sibling-asks.md         what it needs from World, Life and the interface
```

## Try it

Check it without starting a server — a second, no world left behind:

```sh
cargo run -p server -- --check-mods <a mods directory holding this mod>
```

from the engine's checkout. Beside the other default mods it loads after
the interface, the world and Life, and before the weather, and the engine's
reference `core_tools` stands aside for it.

The native check runs the mod through the engine's real script VM, with a
fake server around it and fixture mods that stand in for the progress and
magic mods. From this repository's root, with the engine checked out beside
it as `../Tiamat`:

```sh
cargo run --manifest-path tests/native/Cargo.toml
```

In a world, V opens the Craft tab, `recipes` in chat lists what you could make by hand from what
you carry, and `craft <recipe> [times]` makes it. An operator's `toolkit`
gives one of every tool.

## Where this departs from the brief

The brief (`docs/brief.md`) is kept as written; where building it found
something it did not know, the code follows the engine and the siblings,
and the change is recorded here.

- **The tool gate is on `register_on_dig_start`**, which landed the day the
  brief was written: a wrong tool is refused as the dig begins.
- **Flint is `cracked`, not `rock`.** The first fire is struck with flint,
  and fire is how the hand gets past rock; flint wanting a pick would make
  the loop impossible to start. It has no cracked twin.
- **Class types are lists.** `wood` takes a hand, an axe or a chisel,
  `cracked` a hand, maul, pick or chisel, and the chisel carves what a pick
  or axe of its tier may break. A spade on a log is refused ("That wants an
  axe."), a pick on earth is not.
- **Bronze and iron sickles and hoes**, which the brief left for later: Life
  now farms, and its exports ask for the farm tools in bronze and iron.
- **The campfire is made by hand**, not at the workbench: fire comes before
  the workshop on the ladder, and the workbench is step 4.
- **A cracked block drops nothing and the digger is handed the rock**,
  because the engine lets a block drop only its own mod's materials (engine
  ask 7).
- **Hafts and cord.** A haft (two sticks and a cord) is what a maul, and
  later every metal head, is fitted to; cord is twisted from bramble.
- **Station screens are the engine's widgets with the interface's fonts
  and colours**, not its builders: what those answer is a read-only view
  that cannot be sent inside another mod's tree.
- **The kiln has two input slots** (copper and tin go in together): fuel 1,
  in 2–3, tool 4, out 5.
- **One log is one charcoal and one wet clay one fired clay.** The brief's
  "27 log units → 9 charcoal" reads as either; one for one keeps charcoal
  worth making (it burns hotter, not longer) and nothing in the loop
  cheaper than it should be.
- **A burning station runs whatever its contents make**, first recipe by
  id, rather than a player choosing: pressing a recipe on its screen says
  so. Any station registered with `heat = true` burns the same way.
- **Cooking is a box on the fire, not a use of it.** Life hears every use
  first and eats whatever food is in the hand, which is right for eating and
  leaves nothing to cook with. A fire opens with an empty hand; what is put
  on it cooks while it burns. Stew is Life's hot stew, made on a fire with a
  copper pot rather than with the pot in the off-hand.
- **The kiln bakes Life's bread**, three wheat to a loaf: Life's kitchen ask
  (its C1) wants a source for bread, and the kiln is the oven.
- **A station that works on its own tries its most particular recipe
  first**, so a stew is made from what would also roast.
- **A sluice has three out slots** (sand, tin, gold) rather than one, and
  the gold's ninth wash is a counter kept with the world, never a roll.
- **The anvil is a station you strike.** The work goes on it through its
  screen, where the player also chooses what to forge, and each use with a
  hammer in hand is a blow, rather than the ingredient in the off-hand: the
  mod API reads a player's inventory whole, with no slot to name the
  off-hand by.
- **The tuyere and the bellows' copper nozzle are cast** in one tuyere mould,
  from bronze and copper.
- **Every head has a mould**, the sickle and hoe included, and the pot's
  mould casts the copper pot.
- **Fire-setting reaches one block further through open air**, so a face
  dug back keeps cracking. Quenching with water is not built.

## Pictures, and replacing them

Every texture is a placeholder: a flat colour, and for an item one shape on
a clear ground, drawn by `tools/make_textures.py` in the world's muted
palette. To use your own, drop a PNG of the same name into
`mods/tiamat_default_craft/textures/`; the engine serves textures itself, so
there is nothing to hash. Running the generator again overwrites the
placeholders, so keep yours out of its list (`ITEMS` in the script) or do
not run it.

## For other mods

`game.exports("tiamat_default_craft")`, for a mod that lists this one in
`depends` or `optional_depends`, is the recipe registry: register a station
and recipes into it, make them with `perform`, set the progression gate,
and hear what players make. [`docs/exports.md`](docs/exports.md) is the
list and the contract. Nothing raises: a malformed call answers `nil` and
a reason.

## Out of scope

Stone tools and diamond tools, never. Steel (the tech tree's, from coke).
Uses for silver, gold, lead, crystal, diamond, orichalcum and the world's
`metal` — mined and kept for the trees. Insight, research and the Fork
(the progress mod). Farming, which is Life's: Craft adds bronze and iron
farm tools through Life's exports, nothing more. Items lying on the ground.
Shaped (grid-position) recipes: a recipe is a multiset.

## Licence

GPL-3.0-only, © Iridesium, with an Additional Permission under GPLv3 §7 in
`LICENSE.EXCEPTION` (version 1.0, 24 September 2026): a mod that interacts
with Tiamat Default Craft only through its exports, the engine's scripting
API or the network protocol is an independent work and may be licensed
however its author likes. Copying or adapting this mod's code or assets is
not covered by that permission and stays under the GPL.
[`docs/exports.md`](docs/exports.md) lists the exports; the engine's
`MOD-LICENSING.md` has the plain-language version and a matrix of what
needs which permission. Third-party assets are listed in `docs/assets.md`
with their own licences. Contributions are taken under the Developer
Certificate of Origin with authors retaining copyright; see
`CONTRIBUTING.md`.
