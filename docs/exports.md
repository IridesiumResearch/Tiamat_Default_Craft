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
  `{ "mod:thing", units = n }`. `count` is items, 27 units each (charter
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

**`perform`** takes from the container's input slots and gives to its output
slots when a container is named, and from and to the player's own
inventory when the station has no slots. It is one transaction: if any
ingredient is short, or the outputs do not fit, everything goes back to the
slot it came from.

### Progression

| Field | Shape | What it does |
|---|---|---|
| `set_gate(fn)` | `fn(uuid, node) -> boolean` | The gate every `requires` is asked through. One owner: the first to set it keeps it. With none, everything is open; a gate that answers nothing (its mod faulted) is read as open, so a broken progress mod never stops the world making anything. |
| `on_crafted(fn)` | `fn(uuid, recipe_id, outputs)` | Hears every recipe made. |
| `on_first(fn)` | `fn(uuid, event)` | Hears the first time a player does something, once per player for ever: `"craft:<recipe id>"`, or the recipe's own `first`. Fire, smelting, casting and forging add theirs as they land. |
| `on_tool_broken(fn)` | `fn(uuid, tool_id)` | Hears a tool wear out in somebody's hands (step 2). |

## Identifiers it registers

All are namespaced `tiamat_default_craft:` by the engine.

- **Items:** `stick`.
- **Recipes:** `stick` (by hand: any `#log` → four sticks).
- **Stations:** `hand`.
- **Groups:** `#log`, holding the world's thirteen logs.

## Commands it accepts

Chat words, said by a player and swallowed. For anyone: `recipes
[station]` lists what could be made by hand from what the player carries,
and `craft <recipe> [times]` makes it. A sentence that only begins with
one of them is chat.

## Data it stores or sends

None for other mods. `game.storage` is private to this mod: it keeps each
player's firsts (`first:<uuid>:<event>`).

## What it reads from other mods

Not exports, listed so the direction is clear: it names the blocks of
`tiamat_default_world` in its recipes and groups when that mod is loaded,
and loads after `tiamat_default_life` and `tiamat_default_ui` so that it
may use theirs.
