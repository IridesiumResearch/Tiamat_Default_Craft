<!-- SPDX-FileCopyrightText: Iridesium -->
<!-- SPDX-License-Identifier: GPL-3.0-only -->

# Exports

What Tiamat Default Craft (`tiamat_default_craft`) deliberately offers other
mods. This is the document `LICENSE.EXCEPTION` names as "the Exports": a mod
that reaches this one only through what is listed here, the engine's
scripting API or the network protocol is an independent work. A mod that
copies or adapts this mod's code or assets is not, and stays under the GPL.

An interface this mod offers in fact is an export whether or not it is listed
here, so this file changes in the same commit as any change to one.

## The exported table

`game.exports("tiamat_default_craft")` answers it to a mod that lists this
one in `depends` or `optional_depends`. Source:
`mods/tiamat_default_craft/exports.lua`.

None of the functions raise: anything malformed answers `nil` and a reason
a person can read. The tables they answer are plain data, and yours to
keep.

### Recipes and stations

| Field | Shape | What it does |
|---|---|---|
| `version` | integer, `1` | Bumped only when a change would break a reader. |
| `register(spec)` | `{ id, station, inputs, tools?, heat?, ticks?, outputs, requires?, name?, first?, conserve? }` | Registers a recipe. Answers `true`. |
| `register_group(name, members)` | `"#log"`, `{ "mod:thing", ... }` | Adds to a group, making it if new. Additive: nobody can take a member out. |
| `register_station(spec)` | `{ id, name?, slots?, heat?, fuels?, block?, lit_block?, inventory? }` | Registers a station: where recipes are made. |
| `register_fuel(material, heat, ticks)` | a qualified id or a `#group`; a tier 1..9; ticks per 27 units | What burns, how hot and for how long. |
| `recipes(station?)` | a station id, or nothing for all | Every recipe (or a station's), sorted by id, as `{ id, name, station, inputs = { { name, units } }, tools = { { name, wear } }, heat, ticks, outputs = { { name, units } }, requires }`. |
| `can(uuid, recipe_id, container?)` | a UUID in hex; a recipe id; a container name | Whether that player could make it now: `true`, or `nil` and why. |
| `perform(uuid, recipe_id, container?)` | the same | Makes it: `true` and `{ { material, units } }`, or `nil` and why, with everything taken put back. |
| `in_group(group, name)` | `"#log"`, `"mod:thing"` | Whether a group holds a name. |

**Registration** — `register`, `register_group`, `register_station`,
`register_fuel` and the subscribers — is while mods load, in your
`init.lua`, as the engine's own registries are. After that they answer
`nil, "... while mods load"`.

**A recipe's fields.**

- `id` is qualified with your mod's id, `"my_mod:elixir"`: the registry
  cannot see which mod is calling it, so it is told.
- `station` is a registered station's id. This mod's are `"hand"` (from the
  player's own inventory) and, as they land, `"workbench"`, `"campfire"`,
  `"kiln"`, `"bloomery"`, `"anvil"` and `"sluice"`. Name yours with your
  mod's id in front, `"my_mod:alembic"`.
- `inputs` and `outputs` are lists of `{ "mod:thing", count = n }` or
  `{ "mod:thing", units = n }`. `outputs` may be empty: a recipe that makes
  nothing, whose product is what its `on_crafted` subscribers make of it (a
  study, which the progress mod pays in insight). `count` is items, 27 units each (charter
  rule 5); inside, everything is units. An input may name a `"#group"`,
  which any member satisfies, in any mix. At most 16 inputs and 8 outputs.
- `tools` are present and not consumed: `"mod:thing"`, a `"#group"`, or
  `{ "mod:thing", wear = n }` (default 1). A tool is looked for in the
  station's tool slots, then its input slots, then the player's own
  inventory, and any `detail` will do — a tool's detail is its serial.
- `heat` is the tier a station must be burning at, 0 (the default) to 9,
  and only at a station registered with `heat = true`.
- `ticks` is how long a station takes, 20 to a second; 0 is at once.
- `requires` is a progression node id, answered by the gate.
- `first` names the event `on_first` hears the first time a player makes
  it; the default is `"craft:<recipe id>"`.
- `conserve = true` holds the recipe to taking and giving the same number
  of units, and refuses it otherwise.

**A stack with a shape or a `detail` is never an ingredient.** A carved
block or a named thing is somebody's particular thing, and a recipe must not
melt it down (the engine's own rule for `game.take`).

**A station's fields.** `slots` names a container's roles as one-based slot
numbers — `{ input = { from = 1, to = 9 }, output = 10 }`, or `{ input = 2,
fuel = 1, tool = 3, output = 4 }` — and must have `input` and `output`. A
station with no slots works from the player's own inventory and says so
with `inventory = true`. `heat = true` makes it burn; `fuels` is the list
of the only fuels it takes. `block` and `lit_block` are the blocks it is
in the world.

**A station with a `block` is a station in the world**, whoever registered
it. This mod makes its container when the block is placed (named
`tiamat_default_craft:<station>:x,y,z`), opens it with a screen of the
station's recipes when the block is used — one player at a time — and
hands its contents to whoever digs it. An alembic is a station record, a
block and some recipes; register them and it works.

**A station with `heat = true` burns**, and must have a `fuel` slot. It is
lit with this mod's fire striker once there is fuel in it; from then it
burns its fuel 27 units at a time (each fuel's heat and ticks from
`register_fuel`) until the fuel slot is empty, and while it burns it makes,
on its own, the first of its recipes (by id) that its input slots, its tool
slots and its heat satisfy, taking the recipe's `ticks` to do it. It makes
things as the player who lit it — the gate and the firsts are theirs — but
uses only what is in it: a crucible or a mould belongs in its tool slot.
The kiln is one; an alembic registered with `heat = true`, a fuel slot and
a block is another, with nothing more to write.

**A station with `boost = { tool, heat }`** burns at `heat` while that
tool (or a member of that group) is in its tool slot: the bloomery's
bellows. **`refuse_fuel`** is the sentence a strike says when its fuel
slot holds something it will not burn.

**A station with `forge = true` is worked by blows.** Its recipes carry
`strikes` (1..100) and must name the hammer they take in `tools`; a player
chooses one on its screen, puts the work on it, and uses it with that
hammer in hand, once a blow. The recipe is made on the last blow, the held
hammer taking the wear. Changing the work or the choice starts the count
over. The anvil is one.

**A station with `auto = true`** makes things on its own, driven by
something other than fuel in a slot (the campfire, which fire.lua burns);
its recipes are not pressed. A heat station is `auto` too. A station that
makes things on its own tries its recipes most particular first — most
inputs and tools, then by id — so a stew (meat, fruit, a pot) is made from
what would otherwise only roast.

**`perform`** takes from the container's input slots and gives to its output
slots when a container is named, and from and to the player's own
inventory when the station has no slots. It is one transaction: if any
ingredient is short, or the outputs do not fit, everything goes back to the
slot it came from.

### Tools and dig classes

| Field | Shape | What it does |
|---|---|---|
| `register_tool(spec)` | `{ id, type, tier, uses, digs?, name? }` | Your item, gated and worn by this mod. `id` is an item YOUR mod registered; `digs = true` says you also registered an engine tool of the same id, which this mod then puts in the hand of whoever holds the item (if `game.set_tool` refuses it, the holder gets the hand). `type` is a word (`"pick"`, `"drill"`), `tier` 0..9, `uses` before it wears out (0 never). |
| `classify(block, class)` | a qualified block id; a class id | Puts a block in a class. |
| `register_class(spec)` | `{ id, types, tier, refusals? }` | A class of your own: the tool types that may break it (`"hand"` for a bare hand, `"any"` for everything), the least tier, and `refusals = { hand?, type?, tier? }`, the sentences a refusal says. |
| `tool_of(uuid)` | a UUID in hex | The tool a player holds, `{ id, type, tier, uses, wear }`, or nil. |
| `wear(uuid, amount)` | a UUID; a whole number | Charges uses to the tool a player holds, as a spell that uses a chisel might. At its last use it is taken away and the player told. Answers whether there was a tool to charge. |

**The classes this mod ships:** `loose` (anything), `cracked` (hand, maul,
pick, chisel), `wood` (hand, axe, chisel), `hardwood` (axe or chisel, tier
1), `rock` (pick or chisel, tier 1), `hard_rock` (pick or chisel, tier 2).
Every solid block of the world is in one; a block in none is diggable by
anything. A dig is refused as it begins (`register_on_dig_start`), with one
sentence saying why. In a Creative world (Life's `mode`) nothing is refused
and nothing wears.

**Tools carry a serial.** Every tool this mod makes — from a recipe, or a
tool registered with `register_tool` coming out of `perform` — is given a
`detail` of `"t=<serial>"`, so no two stack, and its wear rides in the same
detail — `"t=<serial>;w=<uses>"`, with `c=<hundredths>` for a chisel's
carried fraction — rewritten in the slot the tool lies in, so it travels
with the tool. Read a tool's wear from its detail, or ask `tool_of`. A tool
of yours that reaches a player with no detail is given a serial the first
time it wears.

### Fire

| Field | Shape | What it does |
|---|---|---|
| `is_burning(pos)` | `{ x, y, z, domain? }`, whole blocks | Whether a fire this mod lit burns there. |
| `add_fuel_at(pos, ticks)` | the same; 1..72000 | Adds fuel to a fire this mod lit, up to an hour. Answers whether there was one. |
| `register_cracked(material, twin)` | two qualified block ids | `material` cracks into `twin` beside a burning fire, as the world's rock does. Register the twin yourself — breakable by hand, and dropping what it should: this mod gives the world's rock back for its own twins only. |

### Progression

| Field | Shape | What it does |
|---|---|---|
| `set_requires(recipe_id, node)` | a recipe id; a node id | Puts a requirement on a recipe that has none, while mods load: how a world option elsewhere gates this mod's recipes. Answers `true`, or `nil` and why (no such recipe; it already requires one). |
| `set_effects(fn)` | `fn(uuid, prefix) -> { ["craft.<name>"] = delta }` | The numbers progression nodes change, read where each is used (below). One owner: the first to set it keeps it. A function answering nothing reads as no effects. |
| `set_gate(fn)` | `fn(uuid, node) -> boolean` | The gate every `requires` is asked through. One owner: the first to set it keeps it. With none, everything is open; a gate that answers nothing (its mod faulted) is read as open, so a broken progress mod never stops the world making anything. |
| `on_crafted(fn)` | `fn(uuid, recipe_id, outputs)` | Hears every recipe made. |
| `on_first(fn)` | `fn(uuid, event)` | Hears the first time a player does something, once per player for ever: `"craft:<recipe id>"`, or the recipe's own `first`; `"fire:lit"`; `"fireset:<rock>"` (`"fireset:copper_ore"`) the first time a fire a player lit cracks each kind of rock; `"fire:kiln"` (a kiln's first firing), `"fire:charcoal"`, `"smelt:<metal>"` (copper, tin, silver, gold, lead, bronze), `"cast:bronze_<tool>"`, `"cast:copper_pot"`, `"haft:bronze_<tool>"`, `"cook:meat"`, `"cook:stew"`, `"cook:bread"`, `"wash:tin"`, `"craft:anvil"`, `"cast:bronze_tuyere"`, `"smelt:iron"`, `"forge:iron_bar"`, `"forge:iron_<tool>"`, `"forge:iron_hammer"` (the first, with bronze), `"haft:iron_<tool>"`, `"forge:iron_plate"`, `"forge:iron_nails"`, `"forge:iron_chain"`, `"forge:iron_hinge"`, `"craft:iron_frame"`, `"cast:bronze_gear"`, `"smelt:glass"`, `"bloom:iron"`, `"wash:gold"` — the list below, frozen. |
| `on_tool_broken(fn)` | `fn(uuid, tool_id)` | Hears a tool wear out in somebody's hands (step 2). |

### The numbers `set_effects` moves

Each is an integer delta, summed by the owner, read at the moment it is
used and never stored.

| Key | What it moves |
|---|---|
| `craft.fireset_ticks` | Ticks of burning before a fire the player lit cracks the rock round it (600). |
| `craft.charcoal_yield` | Charcoal from a log in the kiln: three units a point, so 3 is a third more. |
| `craft.fuel_percent` | How long each fuel lasts in a kiln the player lit, per cent. |
| `craft.sluice_gold_period` | Washes to a gold flake in a sluice the player placed (9). |
| `craft.mould_pours` | Pours before a mould cracks (4). |
| `craft.uses_percent.wood`, `.bronze`, `.iron` | Uses a tool of that tier lasts, per cent. |
| `craft.smelt_ore_units` | Ore an ingot of copper or tin, or a bloom (per 27 of it), takes. |
| `craft.bloom_ticks` | Ticks a bloom takes in the bloomery (2,400). |
| `craft.anvil_strikes` | Blows every anvil recipe takes. |
| `craft.chisel_wear_percent` | Wear a chisel takes per use, per cent; the fraction is carried. |

### The first events, frozen

What `on_first` hears. These names are kept; a new one may be added, and
none is renamed or removed without bumping `version`.

- `fire:lit`, `fire:kiln` (a kiln's first firing), `fire:charcoal`,
  `fireset:<rock>` (`stone`, `slate`, `calcite`, `dark_basalt`,
  `copper_ore`, `iron_ore`, `coal`).
- `smelt:<metal>` (`copper`, `tin`, `silver`, `gold`, `lead`, `bronze`),
  `smelt:glass`, `bloom:iron`.
- `cast:bronze_<tool>`, `cast:copper_pot`, `cast:bronze_tuyere`,
  `cast:bronze_gear`.
- `haft:bronze_<tool>`, `haft:iron_<tool>`.
- `forge:iron_bar`, `forge:iron_<tool>`, `forge:iron_hammer` (the first,
  with bronze), `forge:iron_plate`, `forge:iron_nails`, `forge:iron_chain`,
  `forge:iron_hinge`.
- `wash:tin`, `wash:gold`; `cook:meat`, `cook:stew`, `cook:bread`.
- `craft:<recipe id>` for every other recipe, among them
  `craft:tiamat_default_craft:workbench`, `...:chest`, `...:bloomery`,
  `...:stone_anvil`, `...:sluice`, `...:torch`, `...:iron_frame`.

## Identifiers it registers

All are namespaced `tiamat_default_craft:` by the engine.

- **Items:** `stick`, `tinder`, `cord`, `haft`, `bark_strip`, `ash`, the
  parts `iron_plate`, `iron_nails`, `iron_chain`, `iron_hinge`,
  `iron_frame`, `bronze_gear`, `unfired_mould_gear`, `tin_grain`, `gold_flake`,
  `iron_bloom`, `iron_bar`, `iron_<tool>_head` (as the bronze heads),
  `bronze_tuyere`, `copper_nozzle`, `unfired_mould_tuyere`, `charred_meat`, `charcoal`, `fired_clay`,
  `unfired_crucible`, the ingots (`copper_ingot`, `tin_ingot`,
  `bronze_ingot`, `silver_ingot`, `gold_ingot`, `lead_ingot`), the unfired
  moulds (`unfired_mould_<shape>`, for pick, axe, spade, chisel, hammer,
  knife, sickle, hoe and pot), the cast heads (`bronze_<tool>_head`, the
  same less the pot), and the tools: `crucible`, the moulds
  (`mould_<shape>`, the tuyere's included, worn out after four pours),
  `bellows`, `fire_striker`, `fire_striker`, `digging_stick`,
  `ironwood_digging_stick`, `wooden_maul`, `ironwood_maul`, `wooden_wedge`,
  `ironwood_wedge`, `copper_pot`, and in bronze and iron each (`bronze_*`,
  `iron_*`) `spade`, `axe`, `pick`, `chisel`, `hammer`, `knife`, `sickle`,
  `hoe`.
- **Engine tools:** `hand` (the default), and every tool above that digs:
  the digging sticks, spades, mauls, axes, picks and chisels (the chisels
  with the sub-node brush).
- **Blocks:** `mudbrick`, `brick` (class `rock`: a pick's), `glass`
  (transparent), `iron_lantern` (never burns out), `torch`, `spent_torch` (a torch burned out by a random tick;
  it drops its stick), `plank`, `workbench`, `chest`, `sluice`, `bloomery`,
  `bloomery_lit`, `stone_anvil`, `unfired_kiln`, `kiln`,
  `kiln_lit`, `unlit_campfire`, `campfire_lit` (the lit fire in a world
  without Life; with Life, a lit fire is Life's `campfire`), and the cracked
  rocks `cracked_stone`, `cracked_slate`, `cracked_calcite`,
  `cracked_dark_basalt`, `cracked_copper_ore`, `cracked_iron_ore`,
  `cracked_coal` (each only when the world's rock exists).
- **Recipes:** by hand, `bark_strip` (a log → four), `torch` (a stick, a
  bark strip, a tinder → two), `stick` (any `#log` → four sticks), `tinder` (a
  third of a block of `#tinder`), `fire_striker` (two flint),
  `unlit_campfire` (three sticks, two logs, a tinder), `cord` (a bramble →
  two), `workbench` (four logs, four cord). At the workbench: `plank` (a log
  → four, with a `#wedge`), `haft`, `digging_stick`, `wooden_wedge`,
  `wooden_maul`, the three in ironwood, `chest` (nine `#plank`, two cord),
  `unfired_kiln` (nine wet clay, nine cobbles), `unfired_crucible`, the
  unfired moulds, and hafting (`bronze_<tool>`: a head and a haft, or a
  stick for the chisel and knife). In the kiln: `charcoal` (a log, heat 1),
  `fired_clay`, `crucible`, the moulds (heat 1), the ingots from 27 units of
  ore with a crucible (heat 2), `bronze_ingot` (nine copper, one tin → ten),
  the heads (bronze ingots poured into a mould: 3 for a pick, axe or spade,
  2 for a hammer, sickle or hoe, 1 for a chisel or knife) and `copper_pot`
  (three copper ingots, the pot mould).
- **Washing:** `sluice` at the workbench (four `#plank`, two cord); in a
  sluice standing in water, `wash` (27 units of gravel → 24 of sand and a
  tin grain, every ten seconds, and a gold flake every ninth wash, by a
  counter); in the kiln, `tin_from_grains` and `gold_from_flakes` (nine →
  an ingot, with a crucible, heat 2).
- **Iron:** at the workbench `bloomery` (nine fired clay, nine stone, a
  bronze tuyere), `bellows` (four `#plank`, four cord, a copper nozzle) and
  `stone_anvil` (a block of granite, with a `#chisel` that wears ten); in
  the kiln `bronze_tuyere` and `copper_nozzle` (the tuyere mould); in the
  bloomery at heat 3, `iron_bloom` (54 units of iron ore and 27 of
  charcoal, two minutes); on the anvil `iron_bar` (a bloom, any `#hammer`,
  three blows), `iron_<tool>_head` (bars as the bronze heads take ingots,
  the iron hammer, five blows) and `first_iron_hammer_head` (the bronze
  hammer, eight blows, wear two); hafting `iron_<tool>` at the workbench.
- **After the loop:** on the anvil with the iron hammer, `iron_plate` (5
  blows), `iron_nails` (3), `iron_chain` (6), `iron_hinge` (4), each a bar
  into one part and held to conserving units; at the workbench
  `iron_frame` (four plates, a nails, a `#hammer` at hand), `mudbrick` (wet
  clay and a tinder), `unfired_mould_gear` and `iron_lantern` (a plate, a
  glass, a torch); in the kiln at heat 2 `brick` (a mudbrick), `glass`
  (white sand and nine units of `#ash`), `mould_gear` (heat 1) and
  `bronze_gear` (a bronze ingot in the gear mould). A campfire that burns
  out leaves an ash in its box.
- **Cooking** (Life's food, when Life is here): on a campfire,
  `spit_roast` (raw meat → cooked, 15 s), `stew` (raw meat and a `#fruit`,
  with a copper pot → hot stew, 30 s), `dry_clay` (wet clay → the world's
  dry clay, 10 s); cooked meat left over a burning fire a minute more chars.
  In the kiln at heat 1, `oven_roast` and `bread` (three wheat → a loaf).
- **Fuels:** logs, planks and sticks (heat 1, 40 s a block); the world's
  coal (heat 2, 90 s); charcoal (heat 2, 60 s).
- **Stations:** `hand`, `workbench` (slots 1–9 in, 10 out), `kiln` (fuel
  1, in 2–3, tool 4, out 5; it burns), `campfire` (in 1–2, a pot 3, out
  4; it cooks while a fire this mod lit burns), `sluice` (in 1, out
  2–4; refused where no water touches it), `bloomery` (as the kiln; charcoal
  only; bellows in the tool slot burn it white), and `anvil` (in 1, out 2;
  worked by blows).
- **Containers:** `tiamat_default_craft:<station>:x,y,z` for every station
  block placed, this mod's or another's, and `tiamat_default_craft:chest:x,y,z`
  (27 slots) for a chest; `<domain>@` before the position off the overworld.
- **Sounds and cues:** `tool_break`, `anvil_ring`, `sizzle`, `craft`, each
  a sound bound to the cue of its name (`craft` to Tiamat Default UI's own
  craft sound when that mod is here). Bind your own sounds to these cues to
  re-skin them.
- **HUD script:** `hud.lua`, with no reserve: five wear pips past the
  hotbar's right end and a red bar under the crosshair.
- **Dialogs:** `station` (a station's or a chest's screen) and `hand`.
- **Actions:** `craft` (default key V): the Craft tab on the interface's
  screen, or a dialog of its own without it.
- **Tabs:** `tiamat_default_craft:hand`, "Craft", on Tiamat Default UI's screen.
- **Groups:** `#ash`, this mod's ash and the world's volcanic ash;
  `#hammer` and `#chisel`, the bronze and iron ones; `#fruit`, Life's apples and berries; `#plank`, this mod's plank and the world's three; `#wedge`,
  the two wedges; `#log`, the world's thirteen logs; `#tinder`, its dry grass,
  needles, moss, lichen and heather.

## Commands it accepts

Chat words, said by a player and swallowed. For anyone: `recipes
[station]` lists what could be made by hand from what the player carries,
and `craft <recipe> [times]` makes it. A sentence that only begins with
one of them is chat. For operators, and everyone in a Creative world:
`toolkit`, one of every tool.

## Data it stores or sends

To its own HUD script only: `wear` (per mille of the held tool left, or -1)
and `warn` (whether it can break what the crosshair is on). `game.storage`
is private to this mod: it keeps each
player's firsts (`first:<uuid>:<event>`), the tool serial counter
(`serial`), who placed each station (`placer:<container>`), each fire it lit
(`fire:<domain>@x,y,z`), each furnace's fire and work
(`furnace:<container>`), each fire's cooking (`cook:<container>`), each sluice's washing
(`sluice:<container>`) and each anvil's choice and blows
(`anvil:<container>`). Stations themselves are found by the engine's
container listing, and a tool's wear rides on the tool.

## What it reads from other mods

Not exports, listed so the direction is clear: it names the blocks of
`tiamat_default_world` in its recipes, groups and dig classes when that mod
is loaded; it tells `tiamat_default_life` which of its tools are weapons
(`add_weapon`), sickles (`add_harvest_tool`) and hoes (`add_tilling_tool`),
lights Life's `campfire` block and makes its own fire and its burning kiln and
bloomery warm through `add_contact_fire` and `add_heat_source`, makes its charred meat food
through `add_food`, cooks Life's raw meat, fruit and wheat into Life's own
cooked meat, hot stew and bread, and reads Life's world option
`mode`; and it adds a tab to `tiamat_default_ui`'s screen with `add_tab`,
opens it with `open`, and borrows its `theme`'s fonts and colours for its
own dialogs.
