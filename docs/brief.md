<!-- SPDX-FileCopyrightText: Iridesium -->
<!-- SPDX-License-Identifier: GPL-3.0-only -->

> **Kept as written (draft 2.1, 2026-09-26).** Three things have moved since,
> and the code follows the engine and the siblings where they disagree with
> this text: engine asks 0 and 1 landed the same day (the default tool is
> the lowest *non-reference* id, and `game.register_on_dig_start` refuses a
> dig as it begins, so the tool gate lives there rather than in
> `on_dig_complete`); Life exported `add_food`, `add_weapon`, `drop` and its
> farm-tool calls, so sibling asks L1, L2 and L4 are answered; and Life now
> farms, with its own hoe and sickle standing in until this mod's bronze and
> iron ones exist. `docs/engine-asks.md` and `docs/sibling-asks.md` keep the
> current state.

# Tiamat_default_craft — build prompt

*Draft 2.1, 2026-09-26. Supersedes draft 1: adds §0.1 (where this mod sits in the long plan), turns the recipe tables into an exported registry (§7.1, §11.5), adds the ore-role table (§3.1), a torch (§7.6), and moves parts, brick, glass and lantern to an after-the-loop milestone (§12 step 10) so the smelt→dig loop ships untouched. Farming is Life's. A brief for an AI coding assistant and the person supervising it. Design and plan only; no code has been written against it yet.*

**Read this whole file before writing a line.** Then read, in this order: the engine's `api/AGENTS.md`, `api/stubs/game.lua` (the whole API — if a function is not in there it does not exist), `game/core_tools/init.lua`, `game/core_gear/init.lua`, and the three sibling mods' `README.md`, `AGENTS.md` and `docs/exports.md`. Every engine fact in this file was audited from those sources on the date above; the stubs win if they disagree.

---

## 0. One paragraph

`tiamat_default_craft` is the fourth default mod for the Tiamat voxel engine. World makes the ground and eleven ores, Life makes the animals and the hunger, the Interface makes the screens. None of them lets a player *make* anything. This mod is the first loop: **gather → fire → smelt → cast or forge → dig faster, deeper**. Its progression is deliberately not Minecraft's. There are no stone tools and no diamond tools. The ladder is **wood → bronze (a soft, mixed metal) → iron**, and it is climbed the way people actually climbed it: fire cracks rock before any pick does, copper is found green on the surface, tin is washed out of river gravel, bronze is *cast* into clay moulds, iron is *bloomed* and *hammered*.

### 0.1 Where this mod sits in the long plan

The long plan is the *Schism* design (`schism_design.md`): a shared ladder T0–T2, then a per-player **Fork** into a magic tree or a tech tree, T3–T7, ending at "make creatures" and "make or remake worlds". Schism was written before any mod existed and imagined six `schism_*` mods. Three of its six now exist under other names, and this mod is the fourth:

| Schism mod | What exists today | Notes |
|---|---|---|
| `schism_core` (blocks, ores, worldgen, sky) | **Tiamat_Default_World** + engine `core_sky` | Done, and far richer than Schism's table (55 biomes, 11 ores + 5 mineral blocks). |
| `schism_core` (stats: hp, hunger) + `schism_cook` (animals, hunger, food, **crops**) | **Tiamat_Default_Life** | Health, hunger, air, temperature, 16 creatures, food, clothing, death, modes. Farming is going into Life next (designer's decision). No mana. |
| `schism_craft` (recipes, workbench, stations, shape crafting) | **Tiamat_Default_UI** owns shape crafting. **This mod** is the rest. | |
| `schism_progress` (insight, node graph, the Fork) | nothing yet | The next mod after this one. |
| `schism_magic`, `schism_tech` | nothing yet | T3–T7. |

**So this mod is Schism's T0–T2 shared ladder, and it must be the recipe backbone the magic and tech mods register into later.** Three consequences shape draft 2:

1. **Recipes are an exported registry, not a private table** (§7.1, §11.5). `schism_magic` will add an alembic and `schism_tech` an assembler; they must be able to say `craft.register_station{...}` and `craft.register{ station = "alembic", ... }` without this mod knowing they exist. Schism's recipe schema (`station, inputs, fuel, ticks, outputs, requires`) is adopted as-is so nothing written against Schism has to change.
2. **Progression is a hook, not a feature.** Every recipe carries an optional `requires = "node.id"`; this mod ships with a gate that answers *true for everything* and exports `set_gate(fn(uuid, node) → bool)` for `schism_progress` to replace. It also exports `on_crafted` / `on_first` subscriber lists so insight can be awarded for first-ever smelts, casts and forgings without this mod knowing what insight is.
3. **The v1 ladder ends exactly at Schism's Fork.** Iron, anvil, and the parts the Fork's Keystone and stations need (iron frame, plates, nails, hinges, gears — §7.4) are in scope. The research table, insight and the Fork itself are not; they are the progress mod's first milestone (Schism M5).

Where draft 1 and Schism disagreed, the newer decision wins and is recorded here: no stone tier (Schism had wood→stone→bronze→iron; the designer has since removed stone); tier gating by **veto** (§5.5) rather than Schism's "dig succeeds but drops nothing", because the engine has no per-tool drop override; iron by **charcoal bloomery**, not Schism's "coal, not charcoal" — coal becomes coke and enters at tech T3 steel, which is both truer and a cleaner tech-tree gate. §3.1 maps Schism's ore table onto World's actual ores.

---

## 1. Repository shape

Match the siblings exactly (see `Tiamat_Default_Life` for the tidiest example).

```
Tiamat_default_craft/
  README.md                       what it is, layout, controls, how to replace the pictures
  AGENTS.md                       vendored verbatim from the engine's api/AGENTS.md
  stubs/game.lua                  vendored verbatim from the engine's api/stubs/game.lua
  LICENSE, LICENSE.EXCEPTION      GPL-3.0-only; the exception names docs/exports.md
  .luarc.json                     points the language server at stubs/
  mods/tiamat_default_craft/
    mod.toml
    init.lua                      load order only: requires the modules below in order
    config.lua                    every number a designer might turn (tiers, times, costs)
    hooks.lua                     ONE engine registration per hook; many subscribers (the engine
                                  refuses a second register_on_* per mod — see §9)
    materials.lua                 blocks and items this mod registers
    recipes.lua                   the recipe tables: workbench, kiln, bloomery, campfire, sluice
    tools.lua                     tool registry, held→tool sync, dig classes, wear
    stations.lua                  workbench, chest, kiln, bloomery, anvil, sluice: place/use/break/tick
    fire.lua                      campfires: lighting, fuel, cooking, fire-setting
    screens.lua                   dialog trees, in Tiamat Default UI's look when present
    hud.lua                       client HUD script: tool wear pips
    textures/*.png                flat-colour placeholders from tools/make_textures.py
    sounds/*.ogg|wav
  tests/native/                   the mod run through the engine's real script VM (copy Life's harness)
  tools/make_textures.py          stdlib Python only
  docs/exports.md                 what this mod exports (the licence boundary)
  docs/engine-asks.md             what this mod needed from the engine and could not get
  docs/sibling-asks.md            what it needs from World / Life / UI (new; see §11)
  docs/progression.md             the player-facing ladder, one page
```

`mod.toml`:

```toml
id = "tiamat_default_craft"
name = "Tiamat Default Craft"
version = "0.1.0"
description = "Workbench, chest, kiln and bloomery; campfire cooking; wood, bronze and iron tools."
license = "GPL-3.0-only"
depends = ["core >=0.1"]
optional_depends = ["tiamat_default_world", "tiamat_default_ui", "tiamat_default_life"]
conflicts = ["core_tools"]
```

Why each line matters:

- **`optional_depends`** does two things: it lets `game.exports(id)` see those mods, and it forces load order. Without it the alphabetical tie-break loads `tiamat_default_craft` *before* `tiamat_default_life` (c < l) and every lookup of Life's ids finds nothing. It is optional so the mod still loads on a bare engine for the test harness.
- **`conflicts = ["core_tools"]`** is not optional. The engine picks the default tool as *the lowest tool id, sorted as a string, among tools marked `default`*. `core_tools:hand` beats `tiamat_default_craft:hand` forever. Because `core_tools` is a reference mod it stands aside instead of failing the load. That also removes the reference chisel and the `chisel_mode` action — this mod re-registers a chisel as a real craftable tool (§5).
- **No `[theme]`.** The last theme in load order wins and this mod loads after the Interface. Same rule Life follows.

Validate with `cargo run -p server -- --check-mods <dir>` constantly; it is the fast loop.

---

## 2. What the engine gives you, and what it does not

This is the audit. Design decisions below are shaped by it; do not re-derive them from another engine's habits.

| Need | What exists | Consequence for this mod |
|---|---|---|
| Items | `game.register_item{ id, name, texture, description }`. That is all four fields. No stack size (always 90), no durability, no tool fields. | Every tool property lives in this mod's tables. |
| Per-stack data | `detail`: a ≤256-byte string the engine never reads. Stacks merge only if material+shape+detail match. Persists through save, network, drop. `take` matches it exactly. | Tool identity goes in `detail`. Wear does **not** (§5.4). |
| Tools | `game.register_tool{ id, name, brush = "block"\|"subnode", speed_multiplier, default }`. A separate registry from items. `get_tool`/`set_tool` per player. Dig time = `hardness / speed_multiplier`. | No dig class, no tier, no per-material speed. Gating is a **veto in `on_dig_complete`** (`return "message"`), which fires after the player has waited the full time. |
| Tool traps | `set_tool` resets the dig in progress *every call*, even with the same id. Client key R cycles **every** registered tool with no inventory check. No hotbar-change hook. | Poll `game.held` in the one tick handler; call `set_tool` only on change; snap back if `get_tool` ≠ expected. |
| Blocks | `register_block{ id, name, description, hardness, dominance, drops, tags, textures{all}, sounds{step}, light_emit, transparent, cutout, passable, friction, ... }`. Numeric ids are per-session; never persist them. | No block metadata / block entities. State = named containers + `game.storage` + material swaps (`set_block`, applied next tick). |
| Containers | `make_container(name, slots)`, `open_container` (one player at a time), `container`, `container_give/take` (return units moved, one-based `slot`), `break_container` (empty while open). Engine saves them. Names are global, not namespaced. | Name them `tiamat_default_craft:<kind>:x,y,z`. No enumeration API: keep an index of station positions in `game.storage`. No slot filters: correct after the `clicked` event. |
| Dialogs | `show_dialog{player, form, tree}`, `update_dialog`, `close_dialog`; widgets incl. `item_grid{view,columns,first,count}`, `item_slot`, `progress{permille}`, `label`, `button`, `dropdown`; events `pressed/clicked/chose/closed`. Player↔container transfer is engine-handled (left/right/shift click). | Stations open their own dialogs from `register_on_use`. Nothing scrolls; ~530×260 body at 800×600. |
| Interaction | `register_on_use(fn(e))` fires on right-click with an empty hand or a non-placeable item; `e.x/y/z` are **cells** (block = `//3`), `e.material`, `e.held`. `register_on_place` gives **block** coords. `looking_at(player)`. | Every station and the campfire are driven from `on_use`. |
| Time | `register_on_tick(fn(dt_ticks))` at 20 Hz. `register_random_tick(material, fn)` ≈ once per 20 min per block. No timers. | One tick function runs every burning kiln, campfire and cooking job from a table. |
| Hooks | Exactly **one** callback per `register_on_*` per mod. | `hooks.lua` fan-out, like the siblings. |
| Persistence | `game.storage.get/set/keys`, scalars only (string/number/boolean). Player's chosen tool is **not** saved. | Encode small records as strings. Re-apply the tool on `register_on_player_join`. |
| Drops | A dropped stack is an entity (`spawn_entity{item=...}`); pickup is mod logic, and Life only picks up entities **it** spawned. | v1 never drops items on the ground. Chest contents and cooked food go straight into the acting player's inventory with `game.give`, which never refuses. |
| Randomness | `game.rng_stream(chunk_pos, name)` — integer draws, deterministic. No `math.random` in simulation (charter rule 1). | Gameplay chance (sluice gold flakes) uses a storage-backed counter, not RNG. Deterministic by construction. |
| Exports | `game.export(tbl)` once; `game.exports(id)` read-only view. | Reading other mods' *ids* is allowed; copying their code/textures is GPL. |
| Feedback | `game.chat_to(player, text)`, `game.cue{cue,pos,radius}` bound to `register_sound`, `emit_particles`, `set_hud(player, ≤32 scalars)`. | Veto messages double as the tutorial. |

Missing and worked around: dig-start hook, per-material tool speed, per-tool drops, block metadata, container enumeration, slot-targeted give to a player view, food/cooking/weapon exports from Life. All are logged in `docs/engine-asks.md` / `docs/sibling-asks.md` (§11).

---

## 3. The world this mod inherits

All ids below are `tiamat_default_world:` unless noted. Hardness is bare-hand seconds.

**Ores** (no `drops`, no `tags`, no dig class anywhere — they drop themselves, 27 units a block):

| Ore | Hardness | From depth | World's own description |
|---|---|---|---|
| `copper_ore` | 1.6 | surface | "Green-crusted rusty veins… the first metal." |
| `iron_ore` | 1.8 | surface | "Dull red-brown bands and lumps." |
| `flint` | 1.4 | surface | "knaps to an edge and strikes a spark" |
| `coal` | 1.2 | 60 blocks | "Black seams, soft and sooty." |
| `tin_ore` | 1.7 | 200 | "with copper it is bronze" |
| `silver_ore` | 2.0 | 200 | |
| `lead_ore` | 1.9 | 420 | |
| `chromium_ore` | 2.4 | 420 | |
| `gold_ore` | 2.2 | 750 | rarer |
| `diamond` | 3.5 | 1,200 | "almost never a whole block" |
| `orichalcum` | 4.0 | 2,000 | lit from within |

Plus `metal` (3.0, quenched lava), `pyrite` (2.2, fool's gold), `crystal` (2.6), `sulfur` (0.5, glows; geyser basins, volcanic foothills, mineral vein tunnels).

### 3.1 Ore roles — Schism's table on World's ores

Schism's principle was "same rock, two readings". World's list is different from Schism's, so this is the mapping every later mod should use. This mod only *smelts* what is marked v1; the rest is reserved and must not be given a throwaway use.

| World block | v1 (this mod) | Shared later | Magic reading | Tech reading | Schism name |
|---|---|---|---|---|---|
| `copper_ore` | copper ingot → pot, nozzle, bronze | wire | — | wire, dynamo | copper |
| `tin_ore` (+ sluice grains) | tin ingot → bronze | — | — | solder | tin |
| `iron_ore` | bloom → bar → tools, parts | Keystone frame | — | steel (with coke) | iron |
| `coal` | kiln fuel only (spoils the bloom) | — | — | **coke** → steel, coal tar → plastic | coal |
| `flint` | fire striker | — | — | — | (new) |
| `salt` | — | curing meat (Life ask) | — | chemistry | saltpeter (partial) |
| `sulfur` | — | — | alchemy | blasting charge, acid | sulfur |
| `silver_ore` | silver ingot (no use) | — | **wards**, foci | catalysts | silver |
| `gold_ore` (+ sluice flakes) | gold ingot (no use) | **Keystone** | foci | conductors | gold |
| `lead_ore` | lead ingot (no use) | — | — | batteries, shielding; **pitchblende stand-in** (see below) | — |
| `chromium_ore` | refused in kiln (“nothing burns hot enough”) | — | — | stainless / arc smelter, T4 | (new) |
| `crystal` | mined with iron, kept | — | mana lenses | oscillators, glass optics | quartz |
| `diamond` | mined with iron, kept | — | — | cutting heads, precision | (new) |
| `orichalcum` | mined with iron, kept | — | **glimmer**: inert until attuned; mana crystals | exotic matter | glimmer |
| `metal` (quenched lava) | mined with iron, kept | — | — | free impure alloy for early tech | — |
| `pyrite` | nothing (a trap; drops itself) | — | — | sulphur source when roasted | — |

Two gaps against Schism: there is no **pitchblende** (fission) and no **zinc** (brass). Recommended: ask World for a `pitchblende` vein at 1,200+ (it belongs with lead and silver, which is where it really occurs), and treat brass as unnecessary — the tech Fork's "brass gears" become **bronze gears**, which this mod can already cast (§7.4). Both are logged in `docs/sibling-asks.md`.

**Rock:** `stone` 1.5, `granite` 2.0, `slate` 1.4, `calcite` 1.1, `dark_basalt` 1.6, `cobbles` 0.8, `lava_rock` 1.3, `pumice` 0.4, sandstones 1.3, `dark_sediment`/`light_sediment` 2.0, `morphic_rock` 3.0, `obsidian` 5.0, `scorch` 3.5, `apex_stone` 5.0.

**Soil and loose:** `dirt` 0.5, `grass` 0.5, `sand`/`white_sand` 0.4, `dark_sand` 0.5, `gravel` 0.6, `wet_clay` 0.5, `dry_clay` 0.8, `mud` 0.4, `volcanic_ash` 0.6, `snow`, `permafrost`.

**Wood:** logs `oak` 1.0, `birch` 0.9, `dead` 0.6, `fir` 1.0, `willow` 0.9, `kapok` 1.0, `juniper` 1.0, `apple` 0.9, `cherry` 0.9, `mangrove` 2.0, `acacia` 2.0, `redwood` 2.0, **`ironwood` 2.2**. Only three plank blocks exist (`willow_planks`, `ironwood_planks`, `kapok_planks`) and World's rule is "one of each, no variants" — **so this mod registers its own generic `plank` and does not ask World for thirteen more.** `bramble` 0.3 (drops itself; Life adds berries).

**Not usable as you'd assume:** `charcoal` is "Charcoal clay", a surface band in the Badlands — not a fuel. This mod registers its own charcoal item. `lava` is a fluid and is air in the block store; only `magma` is a hot block.

**Life** (`tiamat_default_life:`): food items `raw_meat` (3 food, poisons), `cooked_meat` (8 food, well-fed), `hot_stew` (6, warm), `bread`, `apple`, `berries`; the **`campfire` block** (hardness 0.4, always lit, contact fire 1 dmg/20 ticks, heat source 1.0) obtainable today only from the dev `kit` command; exports `add_contact_fire(material, {damage, ticks, after})`, `add_heat_source(material, strength)`, `set_alight(target, ticks)`. Meat is cooked only when a burning creature dies (`cooked_by_fire` config). Life's X key eats **only Life's own items**. Weapons are a private table (`core_gear:sword` = 6). Life's roadmap note says "X while looking at a campfire cooks what you hold" — §6.2 supersedes that; tell them.

**Interface** (`tiamat_default_ui:`): exports `version=1`, `add_tab{id,label,build,on_event,order}`, `add_button`, `open/close/redraw/is_open/current_tab`, `theme{font,text_font,colours,frames}`, `widgets{label,text,hint,button,wide_button,section,slot,box,row,space,well}`, `sizes`. The "shape crafter" is **not a recipe system**: it carves one loose material into a 27-cell shape at one unit per cell. There is no recipe export and no way to add one. The `player:main` view is 27 slots + off-hand (slot 28); hotbar = slots 1–9. Sounds `tiamat_default_ui:click/screen_open/craft` and cue `craft`.

---

## 4. The progression (the design)

### 4.1 Principles

1. **Every tier is earned by a real-world technique, not a better rock.** Fire before picks. Placer tin before deep mines. Casting before forging.
2. **Tools are typed.** A spade moves soil, an axe fells wood, a pick breaks rock, a hammer works metal. The wrong type is refused with a sentence that teaches.
3. **Soft metal wears; iron endures.** Bronze is faster than wood but dies quickly; iron is the first tool you keep.
4. **Nothing is gated behind luck.** Chance is replaced by ratios and counters so the loop is deterministic and testable.
5. **Depth is the reward, not the requirement.** Everything needed for bronze is within 60 blocks of the surface. Iron ore is on the surface; iron's gate is *heat*, not depth.

### 4.2 The ladder, player-facing

```
HANDS ─ dig soil, sand, clay, gravel, brambles, dead logs; break cracked rock
  │     strike a fire with flint on flint
  ▼
FIRE ─ campfire: cook meat, dry clay, and FIRE-SET rock: rock and ore touching a
  │     burning fire crack; cracked rock and ore come away by hand or maul
  ▼
WOOD ─ workbench (logs + cord). Digging stick / spade, maul, wedge (splits logs to
  │     planks), haft. Ironwood makes the lasting versions. Chest.
  ▼
CLAY ─ wet clay → unfired kiln, crucible, moulds. First firing hardens the kiln.
  │     Logs burn in the kiln → CHARCOAL (the hot fuel).
  ▼
BRONZE ─ copper ore (surface, fire-set) + tin grains (sluice river gravel) →
  │     crucible in the kiln → bronze ingot → poured into a clay mould → tool head
  │     → hafted at the workbench. Bronze pick, axe, spade, chisel, knife, sickle, pot.
  │     Bronze digs rock and every ore down to gold. It wears fast.
  ▼
IRON ─ bloomery (fired clay + stone + a bronze tuyere) with bellows; charcoal only
        (coal's sulphur spoils the bloom). Ore → IRON BLOOM (spongy, useless) →
        hammered on the anvil with a bronze hammer → WROUGHT IRON BAR → forged tool
        heads at the anvil with an iron hammer. Iron pick, axe, spade, hammer, chisel.
        Iron digs the hard rocks, obsidian, diamond and orichalcum.
```

Diamond and orichalcum are mined with iron and *kept*. They have no use in v1. That is the hook for the next mod, not a gap.

### 4.3 Dig classes

Every material this mod cares about has a **class**; every tool has a **type** and a **tier**. A dig completes only if the tool's type matches the class's type and its tier ≥ the class's tier. Bare hand is type `hand`, tier 0. Anything not in the table is unclassed and diggable by anything (the engine's default) — so unknown mods' blocks keep working.

| Class | Type needed | Tier | Materials |
|---|---|---|---|
| `loose` | any (hand ok) | 0 | dirt, grass, sand, white/dark sand, gravel, mud, wet/dry clay, volcanic ash, snow, permafrost, bramble, dead_log, pumice, cobbles |
| `cracked` | hand or `maul` | 0 | this mod's `cracked_*` blocks (§4.4) |
| `wood` | `axe` **or hand at ½ tier** | 0 | every log except ironwood and the three 2.0 hardwoods; planks |
| `hardwood` | `axe` | 1 (bronze) | ironwood, mangrove, acacia, redwood logs |
| `rock` | `pick` | 1 (bronze) | stone, granite, slate, calcite, dark_basalt, sandstones, lava_rock, sediments, flint, copper_ore, iron_ore, coal, tin_ore, silver_ore, lead_ore, gold_ore, pyrite, salt |
| `hard_rock` | `pick` | 2 (iron) | morphic_rock, scorch, obsidian, apex_stone, metal, crystal, chromium_ore, diamond, orichalcum, magma |

Granite is deliberately `rock`, not `hard_rock`: at hardness 2.0 it is the slow, expensive stone of the bronze age, and the anvil (§7.4) is made from it — so the first granite you break with a bronze pick is the gate to iron.

"Hand at ½ tier" on `wood` means: the hand may fell soft logs (the bootstrap needs a workbench before an axe exists) — it is just slow, and the veto message says an axe would be faster. **No stone tier exists**: nothing in the table is tier "stone".

Because the engine only knows `speed_multiplier`, speed is per tool, not per material: a bronze pick digs *everything it is allowed to dig* at its multiplier. The class table decides *whether*, the multiplier decides *how fast*. That is acceptable for v1 and is engine ask #1.

### 4.4 Fire-setting

The mechanic that replaces stone picks. A **burning campfire** (this mod's lit campfire, §6.1) heats the six face-adjacent blocks. After `FIRESET_TICKS` (default 30 s = 600 ticks) of continuous burning, each adjacent `rock`-class block whose material has a cracked twin is swapped to it: `stone → tiamat_default_craft:cracked_stone`, `copper_ore → cracked_copper_ore`, and so on. Cracked blocks are class `cracked`, hardness 0.6, and `drops` the *original* material at 27 units — so cracked copper ore yields exactly what a pick would. Then the fire keeps cracking the next layer as the player digs in. Realistic, slow, and it makes surface copper reachable with nothing but wood and fire.

Cracked twins to register in v1: `stone`, `slate`, `calcite`, `dark_basalt`, `cobbles`-free (already loose), `copper_ore`, `iron_ore`, `flint`, `coal`. Not granite or anything `hard_rock` — fire-setting does not crack the hard rocks; that is what bronze and iron are for. Textures: the parent's flat colour with a darker crack overlay from `make_textures.py`.

Implementation: `fire.lua` keeps `burning[pos_key] = { since_tick, fuel_ticks, heat_ticks }` for fires *this mod lit*, persisted as one storage string per fire; the tick handler walks it, and every `FIRESET_TICKS` calls `game.get_block` on the six neighbours and `game.set_block` on the ones with a twin. Quenching: a `water` fluid neighbour (`game.get_fluid`) halves `FIRESET_TICKS` — the historical trick — cheap to add, optional.

---

## 5. Tools

### 5.1 The set

| Tool | Tiers available | Type | speed_multiplier by tier (wood / bronze / iron) | Durability (uses) | Notes |
|---|---|---|---|---|---|
| Digging stick → Spade | wood, bronze, iron | `spade` | 1.6 / 2.4 / 3.2 | 60 (ironwood 120) / 150 / 600 | Soil only. The first tool. |
| Maul | wood only (ironwood variant) | `maul` | 1.4 | 80 / 160 | Breaks cracked rock; drives the wedge. |
| Wedge | wood (ironwood) | — | — | 40 / 80 | Consumed by the plank recipe, not by digging. |
| Axe | bronze, iron | `axe` | 2.2 / 3.0 | 120 / 500 | Wood and hardwood. |
| Pick | bronze, iron | `pick` | 1.8 / 2.6 | 100 / 450 | Rock; iron for hard rock. |
| Chisel | bronze, iron | `chisel` | brush `subnode`, 0.6 / 0.9 | 200 / 800 | The only sub-node tool; replaces the reference chisel. |
| Hammer | bronze, iron | `hammer` | (not a dig tool) | 120 / 600 | Station tool: anvil recipes require it in hand; wears per recipe. |
| Knife | bronze, iron | — | — | 80 / 300 | Recipe tool: cordage, bark strips, butchering later. |
| Sickle | bronze | — | — | 100 | Reserved: harvests bramble/berries faster (v1.1). |
| Pot | copper | — | — | ∞ | Campfire tool: enables stew (§6.2). |

Wood has no pick and no axe: **that is the point.** The wood tier moves soil, breaks fire-cracked rock, and makes the workshop. Ironwood doubles wood durability, but ironwood is class `hardwood` (tier 1): the hand is refused, so ironwood tools come *after* the first bronze axe. They are the cheap, durable wood option that stays useful all game — a maul is still the fastest thing on fire-cracked rock, and an ironwood digging stick outlasts a bronze spade.

### 5.2 Registration

Each tool is **both** an item and an engine tool under the same id (the registries are separate; the stubs allow it):

```lua
game.register_item{ id = "bronze_pick", name = "Bronze pick", texture = "textures/bronze_pick.png", description = ... }
game.register_tool{ id = "bronze_pick", name = "Bronze pick", brush = "block", speed_multiplier = 1.8 }
game.register_tool{ id = "hand", name = "Hand", brush = "block", speed_multiplier = 1.0, default = true }
```

`tools.lua` holds `TOOLS[id] = { type, tier, uses, speed }` and `CLASSES[material_id] = { class, type, tier }` resolved from string ids to numeric ids on the first tick (Life's lazy-resolve pattern, because numeric ids are per-session and World may be absent).

### 5.3 Held → tool sync

In the single tick handler, for each connected player (track joins/leaves; iterate a table, not the world):

```
held = game.held(uuid)
want = (held and TOOLS[held.material]) and held.material or "hand"
if want ~= expected[uuid] then game.set_tool(uuid, want); expected[uuid] = want end
if game.get_tool(uuid) ~= expected[uuid] then game.set_tool(uuid, expected[uuid]) end   -- undo the R key
```

`set_tool` only when the answer changes — the engine cancels the current dig on every call. Re-apply on `register_on_player_join` because the engine does not save the choice.

### 5.4 Wear: identity in `detail`, wear in storage

A tool stack's `detail` is `"t=<serial>"`, a serial minted from a storage counter at craft time. Serials make every tool unique, so tools never merge and `take{ detail = ... }` targets exactly one. **Wear lives in `game.storage["wear:<serial>"]`**, not in `detail`. Reason: changing `detail` means `take` + `give`, and the re-given stack may land in a different slot than the hotbar slot the player selected, with no slot-targeted give to fix it. Storage keeps the stack untouched in the hand.

On each successful `on_dig_complete` by a tool of ours: `wear += 1`; at `uses`, `take` the tool by material+detail, `chat_to` "Your bronze pick has worn to nothing.", cue `tool_break`, clear the storage key. Show remaining uses on the HUD: `set_hud(uuid, { wear_permille = ... })` for the held tool; `hud.lua` draws five pips under the hotbar. Hammer/knife wear is charged per recipe by `stations.lua`.

Garbage: a storage key per tool ever made. Acceptable at v1 scale; note it in engine-asks (a `detail`-only design would need slot-targeted give).

### 5.5 Veto messages (the tutorial)

`on_dig_complete` returns a string to refuse. Write them as one sentence each, in World's voice:

- `rock` with hand: "Bare hands will not move stone. Fire will crack it, or a bronze pick will break it."
- `rock` with spade/axe/maul: "That wants a pick."
- `hard_rock` with bronze pick: "The bronze skitters off. This stone wants iron."
- `hardwood` with hand: "Too dense to break by hand. An axe would do it."
- `loose` with a pick: allowed (a pick digs dirt, badly — speed is the pick's) — no message.

A refused dig has already cost the player the wait. Mitigate with a HUD hint: when `looking_at` reports a material whose class the held tool cannot dig, `set_hud` a `warn` flag and draw the target line red. Cheap, and turns the veto into a warning before the click.

---

## 6. Fire and food

### 6.1 The campfire

Life's `tiamat_default_life:campfire` is lit forever and cannot be made. This mod adds the cycle around it:

- **`unlit_campfire`** block (this mod): 3 sticks + 2 logs + 1 tinder at the workbench, or placed directly from the hotbar. Hardness 0.4. Class `loose`.
- **Lighting:** `on_use` on `unlit_campfire` holding a `fire_striker` (2 flint at the workbench; wears 20 strikes) → `set_block` to **`tiamat_default_life:campfire`** if Life is present, else to this mod's own `campfire_lit` fallback (same light, contact fire via this mod's veto-free rules — but in practice Life is there). Record the fire in `fire.lua`'s table with `fuel_ticks = 20 min`.
- **Feeding:** `on_use` on the lit fire holding any log or charcoal adds fuel (log 5 min, charcoal 10 min) and consumes 27 units.
- **Burning out:** fuel reaches 0 → `set_block` back to `unlit_campfire` and a `ash` item is given to nobody (v1: nothing; v1.1: ash for lye).
- Fires this mod did not light (the dev kit's) burn forever, as today, because they are not in the table.

Register with Life: `life.add_contact_fire("tiamat_default_craft:campfire_lit", {damage=1, ticks=20, after=40})` and `add_heat_source(..., 1.0)` for the fallback block; the kiln's lit state gets `add_heat_source(…, 0.6)` so a warm workshop counts for Life's thermometer. Nice, free, and exactly what the exports are for.

### 6.2 Cooking

Life exports nothing for cooking, so cooking is this mod's, using Life's *ids* (allowed) and handing results to Life's eat key by outputting Life's own items.

- **Spit-roasting:** `on_use` on a lit campfire holding `tiamat_default_life:raw_meat` → take 1, register a job `{fire, item, done_at = now + 15 s}` in the fire's record (up to 3 jobs per fire). When done, the next `on_use` on that fire with an empty hand gives `cooked_meat` × jobs done, with cue `sizzle` at completion. Leave the meat too long (another 60 s) and it becomes `charred_meat` (this mod's item; 1 food — needs Life's `add_food` export to be edible, until then it is just a lesson). The dialog is optional; a `chat_to` "The meat is done." suffices for v1.
- **Stew:** with a `copper_pot` in the off-hand or inventory, `on_use` on the fire with `raw_meat` and any of `apple`/`berries` present → 30 s → `tiamat_default_life:hot_stew`. Warm food for the frozen wastes: the first thing copper is *for*, and a reason to smelt copper before you can make bronze.
- **Drying clay:** the kiln does ceramics, but a campfire can dry `wet_clay` → `dry_clay` items 9 at a time in 20 s. Bootstrap only.

Tell Life's maintainers (sibling ask L3) that their "X at a campfire cooks" plan is covered here, so the two mods do not both cook.

---

## 7. Stations

All stations share one pattern in `stations.lua`: `register_on_place` records `kind:x,y,z` in a storage index; `register_on_use` opens the station; `on_dig_complete` on a station block empties its container into the digger's inventory (`break_container` returns nothing while open — refuse the dig with "Someone is using it." in that case) and removes the index entry. Containers are named `tiamat_default_craft:<kind>:x,y,z`.

### 7.1 Workbench — recipes with several ingredients

Block: 4 logs + 4 cord (`loose` class, hardness 1.0). Dialog: a 3×3 `item_grid` on the station's 10-slot container (slots 1–9 input, 10 output), a **recipe list** on the right (buttons, filtered to recipes whose ingredients are present — the discoverability the shape crafter lacks), the player's `player:main` grid below. Press the recipe → `container_take` each input (refund on shortfall, the shape crafter's transaction pattern) → `container_give` output to slot 10 → cue `craft` (bind this mod's own cue to `tiamat_default_ui:craft` when the Interface is present).

**The recipe registry is the mod's spine and is exported** (§11.5). It uses Schism's schema unchanged, so the later magic and tech mods register into it:

```lua
craft.register{
  id       = "bronze_ingot",                  -- unique within the registering mod; stored as "<mod>:<id>"
  station  = "kiln",                          -- "hand" | "workbench" | "campfire" | "kiln" | "bloomery" | "anvil" | "sluice" | any registered station
  inputs   = { {"tiamat_default_craft:copper_ingot", count = 9}, {"tiamat_default_craft:tin_ingot", count = 1} },
  tools    = { "crucible" },                  -- present but not consumed; may take wear (hammer, knife, chisel, mould)
  heat     = 2,                               -- minimum heat tier, stations with fuel only
  ticks    = 900,                             -- 0 for instant hand/workbench recipes
  outputs  = { {"tiamat_default_craft:bronze_ingot", count = 10} },
  requires = nil,                             -- progression node id; nil = always. Answered by the gate (§11.5)
}
```

- Inputs are **shapeless multisets**; a `"#log"`, `"#plank"`, `"#ingot"` group name matches any member, and groups are registered with `craft.register_group("#log", {...})` so World's thirteen logs are one line and a later mod can add its own log to `#log`.
- Quantities are `count` (items, 27 units each) or `units`; conservation is the recipe author's job and the registry checks that unit totals balance for material→material recipes and logs a warning if not (Schism §2, "unit conservation is yours").
- `craft.perform(uuid, recipe_id, container_name?)` is the one transaction: gate check → take every input (rollback on shortfall) → wear tools → give outputs → fire `on_crafted`. Stations call it; the hand tab calls it; a future automation block calls it.
- Stations are registered too: `craft.register_station{ id = "kiln", slots = {fuel=1, input=2, tool=3, output=4}, heat = true, block = "tiamat_default_craft:kiln", lit_block = "…:kiln_lit" }`. The job loop, dialog and fuel handling are generic over that record — an alembic or an assembler is a station record plus recipes, nothing more.
- Fuels: `craft.register_fuel(material, heat_tier, ticks_per_27_units)`; this mod registers logs, planks, sticks, coal and charcoal, and the bloomery's rule "charcoal only" is a station field `fuels = {"…:charcoal"}`.

Also add a **Craft tab** via `ui.add_tab{ id = "tiamat_default_craft:hand", label = "Craft", order = 25 }` for the handful of *hand* recipes that need no bench (sticks from a log, cord from bramble, fire striker, tinder, the workbench itself). Without the Interface, those recipes appear in a plain `show_dialog` opened by a `tiamat_default_craft:craft` action on key **V** (E, Q, Z, C, R, F, N, T, X, O are taken).

### 7.2 Chest

9 planks + 2 cord (pegged, no nails). 27-slot container, one player at a time (engine rule; the second player is told "somebody is using that", the stub's own example). Ironwood-planked chest = same thing, 2.0 hardness, purely for the look; skip unless free.

### 7.3 Kiln

`unfired_kiln` item (9 wet clay + 9 cobbles at the workbench) places as a block; first lighting (fire striker, needs fuel inside) swaps it to `kiln`, and burning swaps `kiln` ↔ `kiln_lit` (light_emit {12,6,1}). Container of 4 slots: **fuel**, **input**, **crucible/mould** (optional), **output**. Dialog: three `item_slot`s, a `progress` bar for heat and one for the job, the player grid.

Heat model, one number per kiln: fuel adds heat-ticks, each recipe needs a **minimum heat tier** and a **duration**:

| Fuel | Heat tier | Burns |
|---|---|---|
| any log, planks, sticks | 1 (red) | 40 s per 27 units |
| `coal` | 2 (orange) | 90 s |
| `charcoal` (this mod) | 2 (orange) | 60 s |
| charcoal **with bellows attached** (bloomery only) | 3 (white) | — |

| Kiln recipe | Heat | Time | In → out |
|---|---|---|---|
| Charcoal burn | 1 | 60 s | 27 log units → 9 charcoal |
| Fire clay | 1 | 30 s | 9 wet clay → 9 fired clay; unfired crucible → crucible; unfired mould → mould |
| Smelt copper | 2 | 45 s | 27 copper ore units + crucible → 1 copper ingot (crucible returned) |
| Smelt tin | 2 | 30 s | 9 tin grains *or* 27 tin ore units + crucible → 1 tin ingot |
| Alloy bronze | 2 | 45 s | 9 copper ingots + 1 tin ingot + crucible → 10 bronze ingots (≈10 % tin, the real ratio) |
| Cast bronze | 2 | 30 s | N bronze ingots + `mould_<tool>` → `<tool>_head` (mould survives 4 pours, then cracks) |
| Smelt silver / gold / lead | 2 | 45 s | 27 ore units → 1 ingot (no use in v1; they stack in the chest for the next mod) |
| Cook meat | 1 | 20 s | raw_meat → cooked_meat (the kiln is also an oven) |

Iron ore in the kiln at heat 2: refused, "The ore glows and does nothing. Iron wants a bloomery." Chromium: refused, "Nothing you have burns hot enough." (Its future is stainless — leave it.)

### 7.4 Bloomery and anvil

- **Bloomery**: 9 fired clay + 9 stone + 1 bronze tuyere (cast) at the workbench. Same code path as the kiln with `is_bloomery = true`; only charcoal is accepted ("Coal's sulphur spoils the bloom." — true and a good sentence); a **bellows** item (4 planks + 2 hide… Life has no hide; use 4 planks + 4 cord + 1 copper nozzle) must sit in the bloomery's tool slot to reach heat 3. Recipe: 54 iron ore units + 27 charcoal → 1 **iron bloom** in 120 s. Mark the bloomery block a heat source 0.8.
- **Anvil**: **`stone_anvil`**, 27 units of `granite` shaped at the workbench with a bronze chisel in hand (the chisel wears 10). Granite needs a bronze pick and is slow at hardness 2.0, so the anvil is the first thing that makes a player go looking for a harder stone — the bronze-age gate to iron. No metal anvil in v1; an iron anvil is a natural `0.2.x` upgrade (halves strike counts).
- Anvil recipes are `on_use` with a hammer in hand and the ingredient in the off-hand (slot 28): bloom → **wrought iron bar** (3 strikes, each a right-click, each `set_hud` progress, bronze hammer ok); bar → iron tool head (5 strikes, **iron hammer only** — the first iron hammer is forged with the bronze hammer as the one exception, with 8 strikes and double wear). Cue `anvil_ring`, particles sparks. No dialog needed; the anvil is the one station played entirely in the world.
- **Parts are not v1.** Schism's T2 parts (plate, nails, chain, hinge, iron frame for the Keystone; bronze gears in place of brass — there is no zinc in World) are what the Fork and both trees build from, but nothing in the smelt→dig loop needs them. They are the after-the-loop milestone (§12, step 10), registered through the same exported registry, so the loop ships first and the parts are one recipe file later.

### 7.5 Sluice

4 planks + 2 cord; must be placed with a `water` fluid block face-adjacent (check `get_fluid` on place; refuse with "A sluice needs running water."). 2-slot container: gravel in, take out. Every 10 s of tick with gravel present: 27 `gravel` units → 24 `sand` units + 1 **tin grain**; every 9th wash (storage counter per sluice) also 1 **gold flake** (9 flakes → 1 gold ingot in the kiln). Placer tin: how the Bronze Age really got it, and it means tin is available at the surface in river valleys without the 200-block dig. Deep `tin_ore` remains the *efficient* source once you have the pick.

### 7.6 The torch

The one thing outside the strict loop that v1 carries, because the loop happens underground and no shipped mod registers any portable light. **Torch**: 1 stick + 1 bark strip + 1 tinder at the hand tab; a `cutout`, `passable` block, `light_emit {14, 10, 4}`, hardness 0.1, class `loose`. Burns out by `register_random_tick` (≈20 min) into `spent_torch` (dark, drops a stick), so light is an upkeep cost that charcoal and later a lantern relieve. Nothing else — no lantern, brick, glass, mudbrick, door or bucket in v1; those are the **after-the-loop** milestone (§12, step 10) and are listed there so the recipe ids are reserved.

---

## 8. Items to register (v1 complete list)

**Intermediates:** `stick`, `cord`, `tinder`, `bark_strip`, `plank` (block, 0.8, `loose`), `fired_clay` (clay goes in as World's `wet_clay` units; no clay item of our own), `charcoal`, `ash` (v1.1), `tin_grain`, `gold_flake`, `copper_ingot`, `tin_ingot`, `bronze_ingot`, `silver_ingot`, `gold_ingot`, `lead_ingot`, `iron_bloom`, `iron_bar`, `crucible`, `unfired_crucible`, `mould_pick|axe|spade|chisel|knife|hammer|tuyere|pot` (+ unfired), `bronze_*_head` (7), `iron_*_head` (5), `bronze_tuyere`, `copper_nozzle`, `bellows`, `fire_striker`, `charred_meat`.

**Tools:** `digging_stick`, `ironwood_digging_stick`, `wooden_maul`, `ironwood_maul`, `wooden_wedge`, `ironwood_wedge`, `bronze_spade|pick|axe|chisel|hammer|knife|sickle`, `iron_spade|pick|axe|chisel|hammer|knife`, `copper_pot`. Register a `hand` tool (default).

**Blocks:** `workbench`, `chest`, `unlit_campfire`, `campfire_lit` (fallback only), `unfired_kiln`, `kiln`, `kiln_lit`, `bloomery`, `bloomery_lit`, `stone_anvil`, `sluice`, `plank`, `torch`, `spent_torch`, and the cracked twins (§4.4).

**Reserved ids, not v1 (§12 step 10):** `iron_plate`, `iron_nails`, `iron_chain`, `iron_hinge`, `iron_frame`, `bronze_gear`, `mould_gear`, `iron_lantern`, `mudbrick`, `brick`, `glass`, `bucket`.

Every item needs a `texture` or it renders as the pink missing-texture pattern. `tools/make_textures.py` draws every one as a flat colour with a one-shape silhouette in World's muted palette (copper = verdigris on rust, bronze = dull gold, iron = blue-grey, ironwood = near-black).

---

## 9. Code rules (from the audit; violations fail quietly)

1. One `register_on_*` per hook. `hooks.lua` registers `on_tick`, `on_dig_complete`, `on_place`, `on_use`, `on_dialog_event`, `on_player_join`, `on_player_leave` **once each** and fans out to subscriber lists; every other module subscribes.
2. Never call `set_tool` unless the wanted tool changed (§5.3).
3. Resolve string ids to numeric ids lazily on the first tick and never persist a numeric id.
4. All state that must survive a restart is in `game.storage` as strings/numbers, or in engine containers. Encode records as `"k=v;k=v"`; write one helper, test it.
5. No `math.random`, no `^`, no `math.sqrt` in simulation paths. Integer arithmetic for wear, heat, timers.
6. `game.give` never refuses — a full inventory overflows into slot 29+, which no screen shows (Interface ask 14). Prefer `container_give` to the station's output slot, which reports what did not fit.
7. `break_container` on an open station returns nothing: veto the dig instead.
8. Every exported function answers `nil`/`false` on bad input and never raises — an error in an export disables *this* mod for everyone.
9. Read sibling exports through `game.exports(id)` and check `version == 1`; degrade to plain dialogs / no heat registration when a sibling is absent. The mod must load and pass tests with none of them installed.
10. Follow Life's ghost rule: if `game.world_option("tiamat_default_life:mode")` says the player is a ghost, stations refuse to open (Life already blocks dig/place/use for ghosts; this is belt-and-braces for dialogs).

---

## 10. Tests (`tests/native`, through the engine's real VM — copy Life's harness)

- **Load**: mod loads alone; with each sibling; with all three. `--check-mods` clean.
- **Default tool**: after load, the default tool is `tiamat_default_craft:hand` (proves `conflicts` did its job).
- **Sync**: select a bronze pick → tool is `bronze_pick`; select dirt → `hand`; force `set_tool` to another → next tick restores.
- **Classes**: table-driven: (material, tool) → allowed/refused with the exact message. Includes "unknown material → allowed".
- **Wear**: 100 digs kill a bronze pick; the 101st dig is by hand; storage key cleared; tools never merge (two fresh picks have different serials).
- **Fire-setting**: light a fire beside `stone` and `copper_ore`; advance 600 ticks; both are cracked; dig cracked ore → 27 copper ore units. Not granite.
- **Kiln**: charcoal burn yields 9; copper needs a crucible; iron ore refused; bronze ratio 9+1→10; mould cracks after 4 pours; fuel runs out and `kiln_lit` reverts.
- **Bloomery**: coal refused; no bellows → no bloom; with bellows → bloom in 2400 ticks.
- **Anvil**: three strikes make a bar; iron head refused with a bronze hammer except the first iron hammer.
- **Sluice**: refuses placement without water; 9 washes → 9 tin grains + 1 gold flake; deterministic across two runs.
- **Cooking**: raw → cooked in 300 ticks; empty-hand use collects; 1500 ticks → charred.
- **Chest**: 27 slots persist across a save/load; break gives contents to the breaker; break refused while open.
- **Persistence**: every station survives a restart with contents, heat and jobs.
- **Determinism**: the whole suite twice → identical storage dump.

---

## 11. Asks (write these files; they are deliverables)

**`docs/engine-asks.md`**
1. A dig-*start* hook (or a `can_dig(player, material, tool)` predicate) so a refusal is instant rather than after the wait.
2. Per-material speed on `register_tool` (`speeds = { [material] = mult }`) or a `speed(material)` callback.
3. Per-tool `drops` override in `on_dig_complete` (e.g. a pick yields ore lumps, a hand yields rubble).
4. `game.give` targeting a slot of a player view, so wear could live in `detail` without the stack jumping slots.
5. Container enumeration (`game.containers(prefix)`), so station indexes need not be hand-kept in storage.
6. A `game.tags(material)` / `game.hardness(material)` read, so dig classes could derive from World's data instead of a parallel table.

**`docs/sibling-asks.md`**
- **Life** L1: `add_food(material, {food, saturation, effects})` so `charred_meat`, stew variants and future crops are edible by X. L2: `add_weapon(material, damage)` — proposed: bronze knife 4, bronze axe 5, iron axe 7, iron pick 5, mauls 4. L3: coordination note — campfire cooking now lives in Craft; please drop "X at a campfire cooks" from your roadmap or export a hook instead. L4: `drop(pos, stack, opts)` export so Craft can scatter items with your pickup loop. L5: creature drops `hide`, `bone`, `sinew` (bellows, needles, glue) — future.
- **World** W1: none required. Note that this mod does not add planks per tree, on purpose. W2 (nice-to-have): `tags = {"ore", "rock"}` on blocks so ask E6 has something to read. W3 (for the tech tree, not v1): a `pitchblende` vein at 1,200+ alongside lead and silver — the one Schism ore with no World equivalent. W4: confirm `white_sand` is the intended glass sand.
- **Interface** U1: a `register_recipe` export is *not* requested — recipes live in Craft's registry; but an `open_dialog_in_theme(player, form, tree)` helper would save re-implementing the frame for station dialogs. U2: confirm the `item_grid`-on-another-mod's-tab path works in a real window (README says untested). U3 (for Schism §7.1 glyphs, later): export the carved mask from the shape crafter's `chiselled` event so a glyph registry can read it.

### 11.5 `docs/exports.md` — what this mod exports (version 1)

This is the contract `schism_progress`, `schism_magic` and `schism_tech` will build on. Every function answers `nil, reason` on bad input and never raises. All tables returned are read-only views.

```lua
local craft = game.exports("tiamat_default_craft")   -- requires optional_depends
craft.version                                        -- 1

-- recipes and stations (§7.1)
craft.register{ id, station, inputs, tools?, heat?, ticks, outputs, requires? }   -- → true | nil, why
craft.register_group(name, members)                  -- "#log", { "tiamat_default_world:oak_log", ... }; additive
craft.register_station{ id, slots, heat?, fuels?, block, lit_block? }
craft.register_fuel(material, heat_tier, ticks_per_27_units)
craft.recipes(station?)                              -- list of recipe records (for a research UI)
craft.perform(uuid, recipe_id, container?)           -- the transaction; → true | nil, why

-- tools and dig classes (§4.3, §5)
craft.register_tool{ id, type, tier, uses, speed, brush? }   -- an item + engine tool, wear-tracked by this mod
craft.classify(material, class)                      -- add a block to "loose" | "cracked" | "wood" | "hardwood" | "rock" | "hard_rock"
craft.register_class{ id, types, tier }              -- a new class (magic: "warded"; tech: "reinforced")
craft.tool_of(uuid)                                  -- { id, type, tier, wear, uses } for the held tool, or nil
craft.wear(uuid, amount)                             -- charge wear to the held tool (a spell that uses a chisel, say)

-- fire (§6)
craft.register_cracked(material, cracked_twin)       -- extend fire-setting
craft.is_burning(pos)                                -- a fire this mod lit
craft.add_fuel_at(pos, ticks)

-- progression hooks (§0.1)
craft.set_gate(fn(uuid, node) -> boolean)            -- replaces the always-true gate; one owner, first wins
craft.on_crafted(fn(uuid, recipe_id, outputs))       -- every perform
craft.on_first(fn(uuid, event))                      -- "smelt:copper", "cast:bronze_pick", "forge:iron_bar", "fire:lit",
                                                     -- "fireset:copper_ore", "wash:tin" … once per player, stored
craft.on_tool_broken(fn(uuid, tool_id))

-- glyphs (reserved, v1.1; Schism §7.1)
craft.register_glyph(mask27, id)                     -- both trees read the same carved masks
craft.glyph_of(stack)
```

`on_first` is the bridge to Schism's insight: the progress mod subscribes and awards points; this mod only records that it happened (`storage["first:<uuid>:<event>"] = true`).

---

## 12. Build order (do it in this order; each step ships)

1. Repo scaffold, `mod.toml`, `hooks.lua` fan-out, `config.lua`, textures script with one placeholder. **The recipe/station/fuel registry and `craft.perform` with rollback, as the export, with a test that a second dummy mod registers a station and a recipe into it.** `--check-mods` clean. **Tests: load, registry.**
2. `tools.lua`: hand default (conflicts with `core_tools`), held→tool sync, class table, veto messages, wear-in-storage. Register the whole tool set as items+tools with placeholder recipes via `kit`-style operator chat for testing. **Tests: default tool, sync, classes, wear.**
3. `fire.lua`: unlit campfire, striker, fuel, burn-out, fire-setting with cracked twins. **Tests: fire-setting.**
4. `stations.lua` + `screens.lua`: workbench with the shapeless recipe engine and the recipe list, hand-craft tab / V dialog, chest. **Tests: chest.**
5. Kiln: heat model, ceramics, charcoal, copper/tin/bronze, moulds and casting. Bronze tools become obtainable legitimately. **Tests: kiln.**
6. Cooking on the campfire and in the kiln; copper pot and stew. **Tests: cooking.**
7. Sluice. **Tests: sluice.**
8. Bloomery, bellows, anvil, iron. **Tests: bloomery, anvil.**
9. Torch; HUD wear pips and red target line; sounds; `docs/progression.md`; `docs/exports.md`; README; the two asks files. **Tests: torch burns out; determinism, persistence, full suite twice; a stub `schism_progress` that installs a gate and confirms a `requires` recipe is refused.** ← **the loop is complete here; tag `0.2.0`.**
10. *After the loop* (`0.3.0`, separate PR, one recipe file): anvil parts (plate, nails, chain, hinge, iron frame), bronze gear + mould, mudbrick, fired brick, glass (white sand + ash, heat 2), iron lantern; bucket only once `set_fluid` runtime semantics are confirmed. **Tests: parts recipes balance units.** This is what the progress mod's Keystone and both trees consume; nothing in steps 1–9 depends on it.

Ship after step 5 as `0.1.0-bronze` if the schedule needs a cut: wood → fire → bronze is already a complete loop. Iron is `0.2.0`.

---

## 13. Numbers a designer will turn (put them all in `config.lua`)

`FIRESET_TICKS 600`, fuel burn times, heat tiers per fuel, every recipe's time and ratio, every tool's `uses` and `speed`, sluice wash time and the 9-wash gold counter, mould pour count 4, cooking 300 / charring 1500 ticks, campfire fuel 20 min, bloom 2400 ticks, anvil strikes 3/5/8, the veto sentences.

---

## 14. Out of scope for v1 (say so in the README)

Stone tools (never). Diamond tools (never). Smithing beyond wrought iron (steel is tech T3: coke from coal, chromium later). Uses for silver, gold, lead, crystal, diamond, orichalcum, `metal` — all mined and kept for the trees (§3.1). Insight, research table, the Fork (`schism_progress`). **Farming is Life's**: crops, hoe, bucket-as-watering, breeding — Craft supplies nothing for it in v1 and will register a hoe through the same tool tables when Life asks (Life is small today and is where hunger, random-tick growth and animals already live). Parts, brick, glass, lantern, bucket (§12 step 10). Glyph registry (v1.1, export reserved). Hide, bone, leather. Item entities on the ground (waiting on Life's `drop` export). Multi-player-at-once containers (engine rule). Shaped (grid-position) recipes — shapeless multisets are enough for this content and the Interface has no grid model to match.
