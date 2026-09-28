-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- The recipe registry: the spine of the mod, and exported (exports.lua) so
-- that the mods after this one — progress, magic, tech — register their
-- stations and recipes into it without this mod knowing they exist.
--
-- The schema is Schism's, unchanged, so nothing written against that design
-- has to change:
--
--     register{ id, station, inputs, tools?, heat?, ticks, outputs, requires? }
--
-- # Quantities
--
-- An entry is `{ "mod:thing", count = n }` or `{ "mod:thing", units = n }`.
-- `count` is ITEMS, 27 units each (charter rule 5: an item of loose material
-- is a block's worth), and everything inside is units. A `"#group"` in place
-- of a name takes any member, in any mix.
--
-- # Names, never numbers
--
-- Recipes hold qualified names. They are resolved to the session's numeric
-- ids on first use, after every mod has registered, and the numbers are never
-- stored: they mean nothing in the next session (charter rule 8).
--
-- # One transaction
--
-- `perform` is the only way anything is made: gate, take every input, check
-- the tools, give every output, charge the tools' wear, tell the
-- subscribers. If any step falls short, everything taken is given back to
-- where it came from, and the answer is `nil` and a sentence a player can
-- read. Stations call it, the hand tab calls it, and a hopper someday will.

local C = tdc.config
local U = tdc.util

local R = {}

local recipes = {}         -- qualified id -> record
local groups = {}          -- "#name" -> { list = { names }, set = { name = true } }
local stations = {}        -- id -> record
local fuels = {}           -- qualified name -> { heat, ticks }
local gate = nil           -- fn(uuid, node) -> boolean, or nil for "everything is open"
local subscribers = { crafted = {}, first = {}, tool_broken = {} }

-- Numeric ids, resolved lazily. Cleared never: the registries are frozen by
-- the time anything resolves, so a name's number does not change in a session.
local resolved_names = {}  -- name -> material id, or false for "nobody registered it"

--- The material id of a qualified name, or nil.
function R.material(name)
    local known = resolved_names[name]
    if known == nil then
        known = U.material(name) or false
        if not tdc.loading() then resolved_names[name] = known end
    end
    return known or nil
end

-- Groups ---------------------------------------------------------------------

--- Adds members to a group, making it if it is new. Additive: a group is
--- never emptied, so one mod cannot take another's log out of `#log`.
function R.register_group(name, members)
    if not tdc.loading() then return nil, "groups are registered while mods load" end
    if not U.group(name) then return nil, "a group is named like #log" end
    if type(members) ~= "table" or #members == 0 then return nil, "a group needs members" end
    for _, member in ipairs(members) do
        if not U.qualified(member) then return nil, "a member is a qualified id: " .. tostring(member) end
    end
    local group = groups[name]
    if group == nil then
        group = { list = {}, set = {} }
        groups[name] = group
    end
    for _, member in ipairs(members) do
        if not group.set[member] then
            group.set[member] = true
            group.list[#group.list + 1] = member
        end
    end
    return true
end

--- The names a group holds, or `{ name }` for a plain name.
function R.members(name)
    if U.group(name) then
        local group = groups[name]
        return group and group.list or {}
    end
    return { name }
end

--- Whether a qualified name is in a group.
function R.in_group(group, name)
    local g = groups[group]
    return g ~= nil and g.set[name] == true
end

-- Stations -------------------------------------------------------------------

local ROLES = { input = true, output = true, fuel = true, tool = true }

--- A role's slots as a sorted list: `3` and `{ 3 }` alike, `{ 1, 9 }` is NOT
--- a range (a range is spelled out, or `{ from = 1, to = 9 }`).
local function slot_list(value)
    if math.type(value) == "integer" then
        return { value }
    end
    if type(value) ~= "table" then return nil end
    local out = {}
    if value.from ~= nil or value.to ~= nil then
        local from, to = U.whole(value.from, 1, 256), U.whole(value.to, 1, 256)
        if not (from and to and from <= to) then return nil end
        for slot = from, to do out[#out + 1] = slot end
        return out
    end
    for _, slot in ipairs(value) do
        local s = U.whole(slot, 1, 256)
        if not s then return nil end
        out[#out + 1] = s
    end
    table.sort(out)
    return #out > 0 and out or nil
end

--- Registers a station: where a recipe is made.
---
--- `{ id, name?, slots?, heat?, fuels?, block?, lit_block?, inventory? }`.
--- `slots` names the container's roles — `{ input = { from = 1, to = 9 },
--- output = 10 }` — and a station without slots works from the player's own
--- inventory, which it must then say with `inventory = true`. `heat = true`
--- makes it a station that burns, and `fuels` a list of the only fuels it
--- takes.
function R.register_station(spec)
    if not tdc.loading() then return nil, "stations are registered while mods load" end
    if type(spec) ~= "table" then return nil, "a station is a table" end
    local id = spec.id
    if type(id) ~= "string" or #id > 96 or not string.match(id, "^[%a_][%w_:]*$") then
        return nil, "a station id is letters, digits, underscores and colons"
    end
    if stations[id] then return nil, "station " .. id .. " is already registered" end
    local record = {
        id = id,
        name = type(spec.name) == "string" and string.sub(spec.name, 1, 64) or U.title(id),
        slots = {},
        size = 0,
        heat = spec.heat == true,
        inventory = spec.inventory == true,
    }
    if spec.slots ~= nil then
        if type(spec.slots) ~= "table" then return nil, "slots is a table of roles" end
        for role, value in pairs(spec.slots) do
            if not ROLES[role] then return nil, "unknown slot role " .. tostring(role) end
            local list = slot_list(value)
            if not list then return nil, "the " .. role .. " slots are one-based slot numbers" end
            record.slots[role] = list
            for _, slot in ipairs(list) do
                if slot > record.size then record.size = slot end
            end
        end
        if not (record.slots.input and record.slots.output) then
            return nil, "a station with slots has input and output slots"
        end
    elseif not record.inventory then
        return nil, "a station has slots, or says inventory = true"
    end
    for _, key in ipairs({ "block", "lit_block" }) do
        if spec[key] ~= nil then
            if not U.qualified(spec[key]) then return nil, key .. " is a qualified block id" end
            record[key] = spec[key]
        end
    end
    if spec.fuels ~= nil then
        if type(spec.fuels) ~= "table" or #spec.fuels == 0 then return nil, "fuels is a list of names" end
        record.fuels = {}
        for _, name in ipairs(spec.fuels) do
            if not (U.qualified(name) or U.group(name)) then return nil, "a fuel is a qualified id or a group" end
            record.fuels[#record.fuels + 1] = name
        end
    end
    stations[id] = record
    return true
end

function R.station(id)
    return stations[id]
end

-- Fuels ----------------------------------------------------------------------

--- `material` burns at `heat` (a tier) for `ticks` per 27 units.
function R.register_fuel(material, heat, ticks)
    if not tdc.loading() then return nil, "fuels are registered while mods load" end
    if not (U.qualified(material) or U.group(material)) then return nil, "a fuel is a qualified id or a group" end
    local h, t = U.whole(heat, 1, C.max_heat), U.whole(ticks, 1, C.max_ticks)
    if not (h and t) then return nil, "heat is a tier 1.." .. C.max_heat .. " and ticks a whole number" end
    fuels[material] = { heat = h, ticks = t }
    return true
end

--- What a material burns as — `{ heat, ticks }` — at a station, or nil. A
--- station with a `fuels` list takes nothing else.
function R.fuel(name, station)
    if station and station.fuels then
        local allowed = false
        for _, fuel in ipairs(station.fuels) do
            if fuel == name or R.in_group(fuel, name) then allowed = true break end
        end
        if not allowed then return nil end
    end
    local direct = fuels[name]
    if direct then return direct end
    for _, key in ipairs(U.sorted_keys(fuels)) do
        if U.group(key) and R.in_group(key, name) then return fuels[key] end
    end
    return nil
end

-- Recipes --------------------------------------------------------------------

--- One quantity entry, `{ name, count = n }` or `{ name, units = n }`, as
--- `{ name, units }`, or nil and why.
local function entry(value, groups_ok)
    if type(value) ~= "table" then return nil, "an entry is a table" end
    local name = value[1] or value.material
    if not (U.qualified(name) or (groups_ok and U.group(name))) then
        return nil, "an entry names a qualified id" .. (groups_ok and " or a #group" or "") .. ": " .. tostring(name)
    end
    local units
    if value.units ~= nil then
        units = U.whole(value.units, 1, C.max_units)
    else
        local count = U.whole(value.count or 1, 1, C.max_units // U.UNITS)
        units = count and count * U.UNITS
    end
    if not units then return nil, "the quantity of " .. name .. " is a whole number" end
    return { name = name, units = units }
end

local function entries(list, limit, groups_ok, what)
    if type(list) ~= "table" or #list == 0 then return nil, what .. " is a list" end
    if #list > limit then return nil, "at most " .. limit .. " " .. what end
    local out = {}
    for i, value in ipairs(list) do
        local e, why = entry(value, groups_ok)
        if not e then return nil, why end
        out[i] = e
    end
    return out
end

--- Registers a recipe. `id` is qualified — `"my_mod:elixir"` — because the
--- registry cannot see which mod is calling it; this mod's own recipes are
--- qualified for it by `R.own`.
function R.register(spec)
    if not tdc.loading() then return nil, "recipes are registered while mods load" end
    if type(spec) ~= "table" then return nil, "a recipe is a table" end
    local id = spec.id
    if not U.qualified(id) then return nil, "a recipe id is qualified: my_mod:thing" end
    if recipes[id] then return nil, "recipe " .. id .. " is already registered" end
    local station = stations[spec.station]
    if not station then return nil, "no station " .. tostring(spec.station) end

    local inputs, why = entries(spec.inputs, C.max_inputs, true, "inputs")
    if not inputs then return nil, why end
    local outputs
    outputs, why = entries(spec.outputs, C.max_outputs, false, "outputs")
    if not outputs then return nil, why end

    local tools = {}
    if spec.tools ~= nil then
        if type(spec.tools) ~= "table" or #spec.tools > C.max_tools then
            return nil, "tools is a list of at most " .. C.max_tools
        end
        for i, tool in ipairs(spec.tools) do
            local name, wear = tool, 1
            if type(tool) == "table" then name, wear = tool[1] or tool.material, tool.wear or 1 end
            if not (U.qualified(name) or U.group(name)) then return nil, "a tool is a qualified id or a #group" end
            local w = U.whole(wear, 0, 1000)
            if not w then return nil, "a tool's wear is a whole number" end
            tools[i] = { name = name, wear = w }
        end
    end

    local heat = U.whole(spec.heat or 0, 0, C.max_heat)
    if not heat then return nil, "heat is a tier 0.." .. C.max_heat end
    if heat > 0 and not station.heat then return nil, "station " .. station.id .. " has no heat" end
    local ticks = U.whole(spec.ticks or 0, 0, C.max_ticks)
    if not ticks then return nil, "ticks is a whole number of ticks" end
    if spec.requires ~= nil and (type(spec.requires) ~= "string" or #spec.requires > 64) then
        return nil, "requires is a progression node id"
    end
    if spec.first ~= nil and (type(spec.first) ~= "string" or #spec.first > 64) then
        return nil, "first is an event name"
    end

    -- Conservation is the recipe author's (Schism §2); a recipe that says it
    -- conserves is held to it. Only plain names can be counted: a group's
    -- members are all the same number of units, so a group counts too.
    if spec.conserve then
        local sum_in, sum_out = 0, 0
        for _, e in ipairs(inputs) do sum_in = sum_in + e.units end
        for _, e in ipairs(outputs) do sum_out = sum_out + e.units end
        if sum_in ~= sum_out then
            return nil, string.format("%s says it conserves but takes %d units and gives %d", id, sum_in, sum_out)
        end
    end

    recipes[id] = {
        id = id,
        name = type(spec.name) == "string" and string.sub(spec.name, 1, 64) or U.title(outputs[1].name),
        station = station.id,
        inputs = inputs,
        tools = tools,
        heat = heat,
        ticks = ticks,
        outputs = outputs,
        requires = spec.requires,
        first = spec.first or ("craft:" .. id),
    }
    return true
end

--- This mod's own recipe: the id qualified with this mod's.
function R.own(spec)
    spec.id = game.mod_id .. ":" .. spec.id
    local ok, why = R.register(spec)
    if not ok then error("recipe " .. spec.id .. ": " .. why, 2) end
    return spec.id
end

function R.recipe(id)
    return recipes[id]
end

--- The recipes at a station (or all of them), sorted by id: a stable order
--- for a list on a screen and for a research tree to walk.
function R.list(station)
    local out = {}
    for _, id in ipairs(U.sorted_keys(recipes)) do
        local recipe = recipes[id]
        if station == nil or recipe.station == station then
            out[#out + 1] = recipe
        end
    end
    return out
end

function R.count()
    local n = 0
    for _ in pairs(recipes) do n = n + 1 end
    return n
end

function R.station_count()
    local n = 0
    for _ in pairs(stations) do n = n + 1 end
    return n
end

-- The gate and the subscribers -------------------------------------------------

--- The progression gate: `fn(uuid, node) -> boolean`, asked for every recipe
--- that `requires` a node. One owner; the first to set it keeps it.
function R.set_gate(fn)
    if type(fn) ~= "function" then return nil, "a gate is a function" end
    if gate then return nil, "a gate is already set" end
    gate = fn
    return true
end

--- Whether a player may make a recipe that requires `node`. With no gate,
--- everything is open. A gate that answers nothing — its mod faulted and
--- its functions went quiet — is read as open too: a broken progress mod
--- must not stop the world from making anything.
function R.allowed(uuid, node)
    if node == nil or gate == nil then return true end
    return gate(uuid, node) ~= false
end

local function subscribe(list, fn)
    if not tdc.loading() then return nil, "subscribe while mods load" end
    if type(fn) ~= "function" then return nil, "a subscriber is a function" end
    list[#list + 1] = fn
    return true
end

function R.on_crafted(fn) return subscribe(subscribers.crafted, fn) end
function R.on_first(fn) return subscribe(subscribers.first, fn) end
function R.on_tool_broken(fn) return subscribe(subscribers.tool_broken, fn) end

--- Records that a player did something for the first time, and tells the
--- subscribers if it IS the first time. Stored with the world, per player.
function R.first(uuid, event)
    if uuid == nil then return false end
    local key = "first:" .. uuid .. ":" .. event
    if game.storage.get(key) then return false end
    game.storage.set(key, true)
    for _, fn in ipairs(subscribers.first) do
        fn(uuid, event)
    end
    return true
end

function R.tool_broken(uuid, tool)
    for _, fn in ipairs(subscribers.tool_broken) do
        fn(uuid, tool)
    end
end

-- Hooks the later files fill in. The registry does not know what a tool's
-- wear is or how hot a kiln is; the files that do replace these.

--- Charges wear to one tool stack found by `perform`.
function R.wear(uuid, found, amount) end

--- How hot a station's container is burning, as a tier.
function R.heat_of(container) return 0 end

-- Resolving and planning -------------------------------------------------------

--- A recipe's names as the session's numbers: each input and tool as a list
--- of candidate materials, each output as one. Nil and why when a name is
--- not registered in this session — a world without the world mod has no
--- logs, and a recipe asking for a log cannot be made.
local function resolve(recipe)
    if recipe.resolved then return recipe.resolved end
    if recipe.broken then return nil, recipe.broken end
    local function candidates(name)
        local out = {}
        for _, member in ipairs(R.members(name)) do
            local material = R.material(member)
            if material then out[#out + 1] = material end
        end
        return out
    end
    local r = { inputs = {}, tools = {}, outputs = {} }
    local why
    for i, e in ipairs(recipe.inputs) do
        local c = candidates(e.name)
        if #c == 0 then why = "nothing registered is " .. e.name break end
        r.inputs[i] = { candidates = c, units = e.units, name = e.name }
    end
    if not why then
        for i, t in ipairs(recipe.tools) do
            local c = candidates(t.name)
            if #c == 0 then why = "nothing registered is " .. t.name break end
            r.tools[i] = { candidates = c, wear = t.wear, name = t.name }
        end
    end
    if not why then
        for i, e in ipairs(recipe.outputs) do
            local material = R.material(e.name)
            if not material then why = "nothing registered is " .. e.name break end
            r.outputs[i] = { material = material, units = e.units, name = e.name }
        end
    end
    if tdc.loading() then
        -- Nothing is final while mods are still registering.
        if why then return nil, why end
        return r
    end
    if why then
        recipe.broken = why
        game.log("tiamat_default_craft: recipe " .. recipe.id .. " cannot be made this session: " .. why)
        return nil, why
    end
    recipe.resolved = r
    return r
end

--- Where the ingredients come from and the products go: a container's roles,
--- or a player's own inventory.
local function source_for(uuid, station, container)
    if container ~= nil then
        if type(container) ~= "string" or #container > 256 then return nil, "no such container" end
        if not station.slots.input then return nil, "that is made by hand, not at a station" end
        return { container = container, station = station }
    end
    if not station.inventory then return nil, "that is made at the " .. station.name end
    if uuid == nil then return nil, "nobody to make it" end
    return { player = uuid, station = station }
end

--- Plain stacks available to a recipe, by where they are: for a container,
--- each input slot's `{ slot, material, units }`; for a player, one entry per
--- material. A stack with a shape or a `detail` is somebody's particular
--- thing — a carved block, a named tool — and is never an ingredient.
local function available(source)
    local out = {}
    if source.container then
        local inputs = {}
        for _, slot in ipairs(source.station.slots.input) do inputs[slot] = true end
        for _, stack in ipairs(game.container(source.container)) do
            if inputs[stack.slot] and stack.shape == nil and stack.detail == nil then
                out[#out + 1] = { slot = stack.slot, material = stack.material, units = stack.units }
            end
        end
        table.sort(out, function(a, b) return a.slot < b.slot end)
    else
        for _, stack in ipairs(game.inventory(source.player)) do
            if stack.shape == nil and stack.detail == nil then
                out[#out + 1] = { material = stack.material, units = stack.units }
            end
        end
        table.sort(out, function(a, b) return a.material < b.material end)
    end
    return out
end

--- Which stacks each input comes out of: a list of `{ slot?, material,
--- units }` takes, or nil and the first thing missing. Candidates are tried in
--- the order they were named, and a stack spent on one input is not counted
--- again for the next.
local function plan(resolved, source)
    local stock = available(source)
    local takes = {}
    for _, input in ipairs(resolved.inputs) do
        local need = input.units
        for _, material in ipairs(input.candidates) do
            for _, stack in ipairs(stock) do
                if need == 0 then break end
                if stack.material == material and stack.units > 0 then
                    local take = math.min(need, stack.units)
                    stack.units = stack.units - take
                    need = need - take
                    takes[#takes + 1] = { slot = stack.slot, material = material, units = take }
                end
            end
            if need == 0 then break end
        end
        if need > 0 then
            return nil, "missing " .. U.friendly(input.name)
        end
    end
    return takes
end

--- The tools a recipe wants, found: `{ material, detail, container?, slot?,
--- player? }` each, or nil and the first one missing. A tool is looked for in
--- the station's tool slots, then its input slots, then the player's own
--- inventory. Any `detail` will do — a tool's detail is its serial.
local function find_tools(resolved, source, uuid)
    local found = {}
    local places = {}
    if source.container then
        local stacks = game.container(source.container)
        for _, role in ipairs({ "tool", "input" }) do
            for _, slot in ipairs(source.station.slots[role] or {}) do
                for _, stack in ipairs(stacks) do
                    if stack.slot == slot then
                        places[#places + 1] = { stack = stack, container = source.container, slot = slot }
                    end
                end
            end
        end
    end
    if uuid ~= nil then
        for _, stack in ipairs(game.inventory(uuid)) do
            places[#places + 1] = { stack = stack, player = uuid }
        end
    end
    for _, tool in ipairs(resolved.tools) do
        local hit
        for _, material in ipairs(tool.candidates) do
            for _, place in ipairs(places) do
                if place.stack.material == material and place.stack.shape == nil and not place.used then
                    hit = place
                    break
                end
            end
            if hit then break end
        end
        if not hit then return nil, "needs " .. U.friendly(tool.name) end
        hit.used = true
        found[#found + 1] = {
            material = hit.stack.material, detail = hit.stack.detail, wear = tool.wear,
            container = hit.container, slot = hit.slot, player = hit.player,
        }
    end
    return found
end

--- Takes `takes` out of `source`. Answers what came out, and whether all of it did.
local function take_all(source, takes)
    local got = {}
    for _, t in ipairs(takes) do
        local n
        if source.container then
            n = game.container_take(source.container, { material = t.material, units = t.units, slot = t.slot })
        else
            n = game.take(source.player, { material = t.material, units = t.units })
        end
        if n > 0 then got[#got + 1] = { slot = t.slot, material = t.material, units = n } end
        if n < t.units then return got, false end
    end
    return got, true
end

--- Puts back what `take_all` took, to the slot it came from where it fits,
--- else anywhere in the container, else into the player's hands. Nothing is
--- destroyed (charter rule 5).
local function give_back(source, got, uuid)
    for _, g in ipairs(got) do
        local left = g.units
        if source.container then
            left = left - game.container_give(source.container, { material = g.material, units = left, slot = g.slot })
            if left > 0 then
                left = left - game.container_give(source.container, { material = g.material, units = left })
            end
        end
        if left > 0 then
            local to = source.player or uuid
            if not (to and game.give(to, { material = g.material, units = left })) then
                game.log(string.format("tiamat_default_craft: %d units of %s had nowhere to go back to",
                    left, tostring(game.block_of(g.material))))
            end
        end
    end
end

--- Puts the outputs where they go. Answers what went in, and whether all of it did.
local function give_outputs(source, outputs)
    local given = {}
    for _, out in ipairs(outputs) do
        if source.container then
            local left = out.units
            for _, slot in ipairs(source.station.slots.output) do
                if left == 0 then break end
                local n = game.container_give(source.container, { material = out.material, units = left, slot = slot })
                if n > 0 then
                    given[#given + 1] = { slot = slot, material = out.material, units = n }
                    left = left - n
                end
            end
            if left > 0 then return given, false end
        else
            if not game.give(source.player, { material = out.material, units = out.units }) then
                return given, false
            end
            given[#given + 1] = { material = out.material, units = out.units }
        end
    end
    return given, true
end

--- Takes back outputs that were given, for a rollback.
local function take_back(source, given)
    for _, g in ipairs(given) do
        if source.container then
            game.container_take(source.container, { material = g.material, units = g.units, slot = g.slot })
        else
            game.take(source.player, { material = g.material, units = g.units })
        end
    end
end

--- Options for `check` and `perform`: a container name, or a table
--- `{ container?, heat? }`.
local function options(opts)
    if type(opts) == "table" then return opts.container, opts.heat end
    return opts, nil
end

--- Whether `uuid` could make recipe `id` now, without making it. Answers
--- `true`, or `nil` and why, plus what `perform` needs to go on.
function R.check(uuid, id, opts)
    local recipe = recipes[id]
    if not recipe then return nil, "no such recipe" end
    local container, heat = options(opts)
    local station = stations[recipe.station]
    local source, why = source_for(uuid, station, container)
    if not source then return nil, why end
    if not R.allowed(uuid, recipe.requires) then return nil, "you do not know how to make that yet" end
    if recipe.heat > 0 then
        heat = heat or (container and R.heat_of(container)) or 0
        if heat < recipe.heat then return nil, "not hot enough" end
    end
    local resolved
    resolved, why = resolve(recipe)
    if not resolved then return nil, why end
    local takes
    takes, why = plan(resolved, source)
    if not takes then return nil, why end
    local tools
    tools, why = find_tools(resolved, source, uuid)
    if not tools then return nil, why end
    return true, { recipe = recipe, source = source, resolved = resolved, takes = takes, tools = tools }
end

--- Makes recipe `id` for `uuid`: the one transaction. Answers `true` and the
--- outputs as `{ { material = name, units } }`, or `nil` and why, having put
--- back everything it took.
function R.perform(uuid, id, opts)
    local ok, job = R.check(uuid, id, opts)
    if not ok then return nil, job end
    local recipe, source = job.recipe, job.source

    local got, complete = take_all(source, job.takes)
    if not complete then
        give_back(source, got, uuid)
        return nil, "the ingredients moved"
    end
    local given
    given, complete = give_outputs(source, job.resolved.outputs)
    if not complete then
        take_back(source, given)
        give_back(source, got, uuid)
        return nil, "no room for what it makes"
    end

    for _, tool in ipairs(job.tools) do
        if tool.wear > 0 then R.wear(uuid, tool, tool.wear) end
    end

    local outputs = {}
    for i, out in ipairs(job.resolved.outputs) do
        outputs[i] = { material = out.name, units = out.units }
    end
    for _, fn in ipairs(subscribers.crafted) do
        fn(uuid, id, U.copy(outputs))
    end
    R.first(uuid, recipe.first)
    return true, outputs
end

return R
