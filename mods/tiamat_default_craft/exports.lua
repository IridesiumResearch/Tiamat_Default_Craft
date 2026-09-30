-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- What other mods may call: the table `game.exports("tiamat_default_craft")`
-- answers to a mod that lists this one in `depends` or `optional_depends`.
-- docs/exports.md is the list, and changes in the same commit as this file.
--
-- The readers this is built for come after it: the progress mod sets the
-- gate and hears `on_first`, and the magic and tech mods register stations
-- and recipes of their own. None of them has to be known here.
--
-- # Every function here runs in THIS mod's sandbox
--
-- An error in one would disable this mod because another passed it the wrong
-- thing, so none of them raise: they check what they are given and answer
-- `nil` and a reason. Each is also run under `pcall`, so a fault of this
-- mod's own is logged and answered the same way rather than taking the mod
-- down for everybody. A callback passed IN is the caller's, and faults on
-- the caller (the engine's rule), so none is wrapped.
--
-- Bump `version` when a change would break a reader, and only then.

local R = tdc.registry
local T = tdc.tools
local U = tdc.util

--- `fn` under pcall: a fault here is logged and answered as `nil, why`.
local function safe(name, fn)
    return function(...)
        local result = table.pack(pcall(fn, ...))
        if not result[1] then
            game.log("tiamat_default_craft: export " .. name .. " failed: " .. tostring(result[2]))
            return nil, "tiamat_default_craft could not do that"
        end
        return table.unpack(result, 2, result.n)
    end
end

local function player(uuid)
    return uuid == nil or (type(uuid) == "string" and #uuid <= 64 and string.match(uuid, "^%x+$") ~= nil)
end

--- A block position, `{ x, y, z, domain? }` in whole blocks.
local function block_pos(pos)
    return type(pos) == "table" and math.type(pos.x) == "integer" and math.type(pos.y) == "integer"
        and math.type(pos.z) == "integer" and (pos.domain == nil or type(pos.domain) == "string")
end

--- A recipe as plain data another mod may keep.
local function public_recipe(recipe)
    local function list(entries, key)
        local out = {}
        for i, e in ipairs(entries) do out[i] = { name = e.name, [key] = e[key] } end
        return out
    end
    return {
        id = recipe.id,
        name = recipe.name,
        station = recipe.station,
        inputs = list(recipe.inputs, "units"),
        tools = list(recipe.tools, "wear"),
        heat = recipe.heat,
        ticks = recipe.ticks,
        outputs = list(recipe.outputs, "units"),
        requires = recipe.requires,
    }
end

return {
    version = 1,

    -- Recipes and stations ------------------------------------------------

    --- `{ id, station, inputs, tools?, heat?, ticks?, outputs, requires?,
    --- name?, first?, conserve? }`. `id` qualified with your mod's id.
    register = safe("register", function(spec) return R.register(spec) end),

    --- Adds qualified ids to a `"#group"`; additive.
    register_group = safe("register_group", function(name, members) return R.register_group(name, members) end),

    --- `{ id, name?, slots?, heat?, fuels?, block?, lit_block?, inventory?,
    --- boost?, runs?, long? }`: docs/exports.md says what each does.
    register_station = safe("register_station", function(spec) return R.register_station(spec) end),

    --- `material` (or a `"#group"`) burns at `heat` for `ticks` per 27 units.
    register_fuel = safe("register_fuel", function(material, heat, ticks) return R.register_fuel(material, heat, ticks) end),

    --- Every recipe, or a station's, sorted by id, as plain data.
    recipes = safe("recipes", function(station)
        if station ~= nil and type(station) ~= "string" then return nil, "a station is named by its id" end
        local out = {}
        for i, recipe in ipairs(R.list(station)) do out[i] = public_recipe(recipe) end
        return out
    end),

    --- Whether a player could make a recipe now: `true`, or `nil` and why.
    --- `container` for a station's recipe, as `perform`.
    can = safe("can", function(uuid, id, container)
        if not player(uuid) then return nil, "a player is a UUID in hex" end
        if type(id) ~= "string" then return nil, "a recipe is named by its id" end
        if container ~= nil and type(container) ~= "string" then return nil, "a container is named" end
        local ok, why = R.check(uuid, id, container)
        if ok then return true end
        return nil, why
    end),

    --- Makes a recipe: from `container` if the recipe's station has slots,
    --- else from the player's own inventory. `true` and the outputs, or
    --- `nil` and why, with everything put back. `opts.unattended`: the
    --- station works alone, so its tools come out of its own slots and never
    --- its owner's pack (Science's C-S7).
    perform = safe("perform", function(uuid, id, container, opts)
        if not player(uuid) then return nil, "a player is a UUID in hex" end
        if type(id) ~= "string" then return nil, "a recipe is named by its id" end
        if container ~= nil and type(container) ~= "string" then return nil, "a container is named" end
        if opts ~= nil and type(opts) ~= "table" then return nil, "opts is a table" end
        local unattended = opts ~= nil and opts.unattended == true
        if unattended and container == nil then return nil, "only a station works unattended" end
        return R.perform(uuid, id, { container = container, unattended = unattended or nil })
    end),

    --- Adds `ticks` to the job a lit furnace or a running station has in
    --- hand: `true`, or `false` when it has none (Magic's C-M6).
    add_progress = safe("add_progress", function(container, ticks)
        local t = U.whole(ticks, 1, 72000)
        if not (type(container) == "string" and t) then return false end
        local id = tdc.stations.kind_id(container)
        local station = id and R.station(id)
        if not station then return false end
        if station.heat then return tdc.furnace.add_progress(container, t) end
        if station.runs then return tdc.runs.add_progress(container, t) end
        return false
    end),

    -- Tools and dig classes -------------------------------------------------

    --- `{ id, type, tier, uses, digs?, name? }`: your item, worn and gated by
    --- this mod. `digs = true` when you registered an engine tool of the same
    --- id, which this mod then puts in the hand of whoever holds the item.
    register_tool = safe("register_tool", function(spec) return T.register(spec) end),

    --- A block into a class: "loose", "cracked", "wood", "hardwood", "rock",
    --- "hard_rock", or one registered with `register_class`.
    classify = safe("classify", function(block, class) return T.classify(block, class) end),

    --- `{ id, types, tier, refusals? }`: a class of your own.
    register_class = safe("register_class", function(spec) return T.register_class(spec) end),

    --- The tool a player holds — `{ id, type, tier, uses, wear }` — or nil.
    tool_of = safe("tool_of", function(uuid)
        if not player(uuid) or uuid == nil then return nil end
        return T.of(uuid)
    end),

    --- Charges `amount` uses to the tool a player holds. Answers whether
    --- there was one to charge.
    wear = safe("wear", function(uuid, amount)
        if not player(uuid) or uuid == nil then return nil, "a player is a UUID in hex" end
        local n = U.whole(amount, 1, 1000)
        if not n then return nil, "an amount is a whole number" end
        return T.wear_held(uuid, n)
    end),

    -- Fire ----------------------------------------------------------------

    --- Whether a fire this mod lit burns at `{ x, y, z, domain? }` (blocks).
    is_burning = safe("is_burning", function(pos)
        if not block_pos(pos) then return false end
        return tdc.fire.burning(pos)
    end),

    --- Adds `ticks` of fuel to a fire this mod lit. Answers whether there was one.
    add_fuel_at = safe("add_fuel_at", function(pos, ticks)
        local t = U.whole(ticks, 1, 72000)
        if not (block_pos(pos) and t) then return false end
        return tdc.fire.add_fuel(pos, t)
    end),

    --- Lights the laid campfire or the unlit furnace at `{ x, y, z, domain? }`
    --- (blocks) for `uuid`, as a striker would: `true`, or `nil` and why. A
    --- furnace needs fuel in it first (Science's C-S6, a burning glass).
    ignite = safe("ignite", function(pos, uuid)
        if not block_pos(pos) then return nil, "a position is whole blocks" end
        if not player(uuid) then return nil, "a player is a UUID in hex" end
        local at = game.get_block(pos)
        if at == nil or at.material == nil then return nil, "There is nothing there." end
        if game.block_of(at.material) == game.mod_id .. ":unlit_campfire" or tdc.fire.burning(pos) then
            return tdc.fire.ignite(pos, uuid)
        end
        local kind = tdc.stations.kind(at.material)
        if not (kind and kind.station and kind.station.heat) then return nil, "There is nothing there to light." end
        return tdc.furnace.ignite(kind.station, tdc.stations.name(kind.id, pos), pos, uuid)
    end),

    --- `material` cracks into `twin` beside a fire, as the world's rock does.
    --- Register the twin yourself: breakable by hand, dropping the rock.
    register_cracked = safe("register_cracked", function(material, twin)
        return tdc.fire.register_cracked(material, twin)
    end),

    -- Progression ---------------------------------------------------------

    --- `fn(uuid, node) -> boolean`, asked for every recipe that `requires`
    --- a node. One owner: the first to set it keeps it.
    set_gate = safe("set_gate", function(fn) return R.set_gate(fn) end),

    --- Puts a node requirement on one of the registry's recipes that has
    --- none. While mods load.
    set_requires = safe("set_requires", function(id, node)
        if type(id) ~= "string" then return nil, "a recipe is named by its id" end
        return R.set_requires(id, node)
    end),

    --- `fn(uuid, prefix) -> { ["craft.<name>"] = delta }`: the numbers the
    --- progression nodes change, read where each is used. One owner.
    set_effects = safe("set_effects", function(fn) return R.set_effects(fn) end),

    --- `fn(uuid, recipe_id, outputs)` after every recipe made.
    on_crafted = safe("on_crafted", function(fn) return R.on_crafted(fn) end),

    --- `fn(uuid, event)` the first time a player does something: `"craft:<recipe>"`
    --- and the events docs/exports.md lists. Once per player, for ever.
    on_first = safe("on_first", function(fn) return R.on_first(fn) end),

    --- `fn(uuid, tool_id)` when a tool wears out in somebody's hands.
    on_tool_broken = safe("on_tool_broken", function(fn) return R.on_tool_broken(fn) end),

    --- A glyph: a carved 27-cell mask and what it means (a qualified id).
    register_glyph = safe("register_glyph", function(mask, id) return R.register_glyph(mask, id) end),

    --- The glyph a stack is carved to (its `shape`), or a bare mask's, or nil.
    glyph_of = safe("glyph_of", function(x) return R.glyph_of(x) end),

    --- Whether a group holds a qualified id.
    in_group = safe("in_group", function(group, name)
        if not (U.group(group) and U.qualified(name)) then return false end
        return R.in_group(group, name)
    end),
}
