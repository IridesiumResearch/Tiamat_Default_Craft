-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Campfires: building, lighting, feeding, burning out — and fire-setting,
-- the mechanism that stands where stone tools would have been (brief §4.4).
--
-- # The cycle
--
-- An unlit campfire is a block a player lays. Struck with a fire striker, or
-- with a torch held to it, it becomes a lit fire: this mod's own
-- `campfire_lit`, drawn as the campfire model, which burns and warms through
-- Life's exports when Life is here. (A fire lit as Life's `campfire`, as
-- they were before 0.7, still burns and is still tended.) A fire this mod lit has fuel, and goes back to an unlit campfire
-- when the fuel runs out; logs thrown on keep it going. A fire it did not
-- light — the dev kit's — burns for ever, as it always did, because it is
-- not in the table.
--
-- # Fire-setting
--
-- A fire that has burned `fireset_ticks` cracks the rock around it: the six
-- blocks against it, and, through any of those that is open air, the blocks
-- one further on — so as a player digs the cracked face away the heat
-- reaches the next layer in. A cracked block breaks by hand and drops the
-- rock whole (materials.lua). Only whole blocks crack; a carved one keeps
-- its shape.
--
-- # State
--
-- Each fire is one storage string, `fire:<domain>@x,y,z`, rewritten once a
-- second while it burns, and read back on the first tick after a restart.
-- A fire in a chunk that is not loaded is paused, not burned: nobody is
-- there, and a fire that went out unseen would have to be put out in a
-- chunk that cannot be written.

local C = tdc.config
local U = tdc.util
local R = tdc.registry
local M = tdc.materials
local T = tdc.tools

local F = {}

local UNLIT = game.mod_id .. ":unlit_campfire"
local OWN_LIT = game.mod_id .. ":campfire_lit"
local LIFE_LIT = "tiamat_default_life:campfire"
local STRIKER = game.mod_id .. ":fire_striker"

--- The fire blocks, by name: what a mixed block is read as (U.name_at).
local FIRES = { [UNLIT] = true, [OWN_LIT] = true, [LIFE_LIT] = true }

--- The fire block at `pos`, or whatever is there, by name; nil if nothing
--- is or the chunk is not loaded.
function F.name_at(pos)
    return U.name_at(game.get_block(pos), FIRES)
end

--- The block a fire is lit as: this mod's own, drawn as its model. Life's
--- campfire was the lit fire before there was one (0.6 and earlier), and a
--- fire burning as one still burns, is fed and goes out.
F.LIT = OWN_LIT

local life = game.exports("tiamat_default_life")
if life and life.version == 1 then
    -- This mod's own fire burns and warms as Life's does, for a world that
    -- has Life and still somehow holds one of ours.
    if life.add_contact_fire then life.add_contact_fire(OWN_LIT, { damage = 1, ticks = 20, after = 40 }) end
    if life.add_heat_source then life.add_heat_source(OWN_LIT, 1.0) end
end

-- What cracks into what -----------------------------------------------------------

local cracked_names = {}   -- parent qualified id -> twin qualified id
for _, name in ipairs(U.sorted_keys(M.cracked)) do
    cracked_names[U.world(name)] = M.cracked[name]
    assert(T.classify(M.cracked[name], "cracked"))
end
local crack_of = nil        -- numeric parent -> { twin, parent name }, resolved on first use

local function cracks()
    if crack_of then return crack_of end
    crack_of = {}
    for _, parent in ipairs(U.sorted_keys(cracked_names)) do
        local material = U.material(parent)
        if material and U.material(cracked_names[parent]) then
            crack_of[material] = { twin = cracked_names[parent], parent = parent }
        end
    end
    return crack_of
end

--- Another mod's rock into fire-setting: `material` cracks into `twin`.
function F.register_cracked(material, twin)
    if not tdc.loading() then return nil, "cracks are registered while mods load" end
    if not (U.qualified(material) and U.qualified(twin)) then return nil, "both are qualified block ids" end
    cracked_names[material] = twin
    return true
end



-- The fires ---------------------------------------------------------------------

local fires = {}      -- key -> { x, y, z, domain, fuel, heat, by }
local restored = false

local function key_of(pos)
    return (pos.domain or "overworld") .. "@" .. U.key(pos.x, pos.y, pos.z)
end

local function pos_of(fire)
    return { x = fire.x, y = fire.y, z = fire.z, domain = fire.domain ~= "overworld" and fire.domain or nil }
end

local function save(key)
    local fire = fires[key]
    game.storage.set("fire:" .. key, fire and U.encode(fire) or nil)
end

local function forget(key)
    fires[key] = nil
    save(key)
end

local function restore()
    restored = true
    for _, key in ipairs(game.storage.keys("fire:")) do
        local rest = string.match(key, "^fire:(.+)$")
        if rest then
            local fire = U.decode(game.storage.get(key))
            if math.type(fire.x) == "integer" and math.type(fire.fuel) == "integer" then
                fires[rest] = fire
            end
        end
    end
end

--- Whether a block is a lit fire, by name.
local function is_lit(name)
    return name == OWN_LIT or name == LIFE_LIT
end

--- Every fire this mod lit, sorted: `{ { pos, by } }`.
function F.list()
    local out = {}
    for _, key in ipairs(U.sorted_keys(fires)) do
        local fire = fires[key]
        out[#out + 1] = { pos = pos_of(fire), by = fire.by }
    end
    return out
end

--- Whether a fire burns at a block position: one this mod lit, or a lit
--- fire block it did not — placed lit (Creative, the toolkit), or Life's
--- dev kit — which burns for ever and cooks like any other.
function F.burning(pos)
    return fires[key_of(pos)] ~= nil or is_lit(F.name_at(pos))
end

--- Adds `ticks` of fuel to the fire at `pos`, up to the most a fire holds.
--- Answers whether there was a fire there.
function F.add_fuel(pos, ticks)
    local key = key_of(pos)
    local fire = fires[key]
    if not fire then return false end
    fire.fuel = math.min(C.fire_max_fuel, fire.fuel + ticks)
    save(key)
    return true
end

--- The blocks fire reaches from a fire at `pos`: its six neighbours, and the
--- neighbours of any of those that is open air.
local SIDES = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } }

local function reach(pos)
    local seen = { [U.key(pos.x, pos.y, pos.z)] = true }
    local out = {}
    local function add(p)
        local k = U.key(p.x, p.y, p.z)
        if seen[k] then return end
        seen[k] = true
        out[#out + 1] = p
    end
    for _, s in ipairs(SIDES) do
        local n = { x = pos.x + s[1], y = pos.y + s[2], z = pos.z + s[3], domain = pos.domain }
        add(n)
        local at = game.get_block(n)
        if at and at.occupancy == 0 then
            for _, t in ipairs(SIDES) do
                add({ x = n.x + t[1], y = n.y + t[2], z = n.z + t[3], domain = pos.domain })
            end
        end
    end
    return out
end

-- Fire-setting: the rock the fire reaches comes away a few cells at a time,
-- the cells nearest the fire first, each falling as the rock it was — one
-- unit a cell, so the rock's own cells are what a player picks up and
-- nothing is made twice. A block that loses its last cell is gone, and the
-- block behind it is then within the fire's reach (`reach`), and no further.

--- The rock a material is, for fire-setting: its parent's name (a cracked
--- twin, from a world before cells fell, comes away as its rock too), or nil.
local twins = nil
local function rock_of(material)
    local table_ = cracks()
    if table_[material] then return table_[material].parent end
    if not twins then
        twins = {}
        for m, crack in pairs(table_) do
            local twin = U.material(crack.twin)
            if twin then twins[twin] = crack.parent end
        end
    end
    return twins[material]
end

--- Where a stack falls, and how: Life's ground when Life is here, else the
--- pack of whoever lit the fire. Answers whether it went anywhere.
local function fall(fire, spec, at, toward)
    if life and life.drop and life.drop(at, spec, { owner = fire.by, velocity = toward }) then return true end
    return fire.by ~= nil and U.give(fire.by, spec) == 0
end

--- Breaks the cells of one block nearest the fire, and lets them fall.
local function spall_block(fire, p, at)
    local rock = at.material and at.occupancy ~= 0 and rock_of(at.material)
    if not rock then return end
    local fx, fy, fz = fire.x * 3 + 1, fire.y * 3 + 1, fire.z * 3 + 1
    local function far(i)
        local dx = p.x * 3 + i % 3 - fx
        local dy = p.y * 3 + (i // 3) % 3 - fy
        local dz = p.z * 3 + i // 9 - fz
        return dx * dx + dy * dy + dz * dz
    end
    local cells = {}
    for i = 0, 26 do
        if at.occupancy & (1 << i) ~= 0 then cells[#cells + 1] = i end
    end
    table.sort(cells, function(a, b)
        local da, db = far(a), far(b)
        if da ~= db then return da < db end
        return a < b
    end)
    local n = math.min(C.spall_cells, #cells)
    local mask, sx, sy, sz = at.occupancy, 0, 0, 0
    for k = 1, n do
        local i = cells[k]
        mask = mask & ~(1 << i)
        sx, sy, sz = sx + i % 3, sy + (i // 3) % 3, sz + i // 9
    end
    local here = { x = p.x + (sx / n + 0.5) / 3, y = p.y + (sy / n + 0.5) / 3, z = p.z + (sz / n + 0.5) / 3,
        domain = p.domain }
    local toward = { x = (fire.x - p.x) * 1.5, y = 1.0, z = (fire.z - p.z) * 1.5 }
    -- The cells come off only if they have somewhere to fall.
    local name = game.block_of(at.material)
    local wrote = mask == 0 and game.set_block(p, "engine:air") or (mask ~= 0 and game.set_block(p, name, mask))
    if not wrote then return end
    if not fall(fire, { material = rock, units = n }, here, toward) then
        game.set_block(p, name, at.occupancy)       -- nowhere for them: put back
        return
    end
    game.emit_particles{
        pos = here, count = C.spall_dust, size = 0.12, lifetime = 1.2,
        colour = { r = 0.55, g = 0.52, b = 0.48 },
        velocity = { x = toward.x * 0.5, y = 0.6, z = toward.z * 0.5 }, spread = 0.8,
        area = { x = 0.15, y = 0.15, z = 0.15 }, gravity = 6, collide = true,
    }
    if fire.by then R.first(fire.by, "fireset:" .. string.match(rock, ":(.+)$")) end
end

--- Breaks away the rock the fire reaches, a few cells a block.
local function spall_around(fire)
    for _, p in ipairs(reach(pos_of(fire))) do
        local at = game.get_block(p)
        if at then spall_block(fire, p, at) end
    end
end

--- One step of a fire's life: burn, heat, crack, go out.
local function tend(key, fire, step)
    local pos = pos_of(fire)
    local at = game.get_block(pos)
    if at == nil then return end                    -- not loaded: paused
    local name = U.name_at(at, FIRES)
    if not is_lit(name) then                         -- dug, or put out by something else
        forget(key)
        return
    end
    fire.fuel = fire.fuel - step
    -- It heats the rock round it first; hot, the rock comes away every
    -- C.spall_ticks for as long as it burns.
    local fireset = math.max(C.fire_step, C.fireset_ticks + R.effect(fire.by, "craft.fireset_ticks"))
    local was_hot = fire.heat >= fireset
    fire.heat = math.min(fireset, fire.heat + step)
    if fire.heat >= fireset then
        -- The first cells come away the moment the rock is hot.
        local due = was_hot and (math.type(fire.spall) == "integer" and fire.spall or 0) + step or C.spall_ticks
        while due >= C.spall_ticks do
            due = due - C.spall_ticks
            spall_around(fire)
        end
        fire.spall = due
    end
    if fire.fuel <= 0 then
        game.set_block(pos, UNLIT)
        forget(key)
        -- A fire that burned out leaves ash on it, in its box (cooking.lua).
        local box = tdc.stations and tdc.stations.ensure("campfire", pos)
        if box then
            local out = R.station("campfire").slots.output[1]
            game.container_give(box, { material = game.mod_id .. ":ash", count = 1, slot = out })
        end
        return
    end
    save(key)
end

local elapsed = 0
tdc.on_tick(function(dt)
    if not restored then restore() end
    elapsed = elapsed + dt
    if elapsed < C.fire_step then return end
    local step = elapsed
    elapsed = 0
    for _, key in ipairs(U.sorted_keys(fires)) do
        tend(key, fires[key], step)
    end
end)

-- Torches burn out: a random tick, about twenty minutes a block, turns one
-- into a spent torch, whose stick comes back when it is dug.
local TORCH = M.blocks.torch
if TORCH then
    game.register_random_tick(TORCH, function(e)
        game.set_block({ x = e.x, y = e.y, z = e.z }, game.mod_id .. ":spent_torch")
    end)
end

-- Lighting and feeding ----------------------------------------------------------------

-- A torch held to a laid fire, or to a furnace with fuel in it, lights it.
-- Holding a torch, the place control places one, so this is heard as a
-- placement: aimed at something to light, the fire is lit and no torch is
-- set down. The torch is not spent; it is still burning.
tdc.on_place(function(e)
    if game.block_of(e.material) ~= game.mod_id .. ":torch" then return nil end
    local look = game.looking_at(e.player)
    if not (look and look.x and look.material) then return nil end
    local pos = { x = look.x // 3, y = look.y // 3, z = look.z // 3,
        domain = look.domain ~= "overworld" and look.domain or nil }
    local name = game.block_of(look.material)
    if name == UNLIT then
        local ok, why = F.ignite(pos, e.player)
        return ok and "" or why
    end
    local kind = tdc.stations and tdc.stations.kind(look.material)
    if kind and kind.station and kind.station.heat and tdc.furnace
        and name ~= kind.station.lit_block then
        local ok, why = tdc.furnace.ignite(kind.station, tdc.stations.name(kind.id, pos), pos, e.player)
        return ok and "" or why
    end
    return nil
end)

--- Ticks of fire in 27 units of a material, by name, or nil.
local function fuel_ticks(name)
    if C.campfire_fuel[name] then return C.campfire_fuel[name] end
    for _, group in ipairs(U.sorted_keys(C.campfire_fuel)) do
        if U.group(group) and R.in_group(group, name) then return C.campfire_fuel[group] end
    end
    return nil
end

--- Lights the laid campfire at `pos` for `uuid`: `true`, or nil and why.
--- What a striker does, and what another mod's fire-lighter does through
--- `ignite` (Science's C-S6, a burning glass).
function F.ignite(pos, uuid)
    local name = F.name_at(pos)
    if name == nil then return nil, "There is nothing there." end
    if is_lit(name) then return nil, "It is burning already." end
    if name ~= UNLIT then return nil, "There is no fire laid there." end
    if not game.set_block(pos, F.LIT) then return nil, "It will not catch." end
    local key = key_of(pos)
    fires[key] = { x = pos.x, y = pos.y, z = pos.z, domain = pos.domain or "overworld",
        fuel = C.fire_fuel, heat = 0, by = uuid }
    save(key)
    if uuid then R.first(uuid, "fire:lit") end
    return true
end

tdc.on_use(function(e)
    local name = game.block_of(e.material)
    local pos = { x = e.x // 3, y = e.y // 3, z = e.z // 3,
        domain = e.domain ~= "overworld" and e.domain or nil }
    local held = e.held and game.block_of(e.held.material)

    if name == UNLIT then
        -- Without a striker the fire's box opens (cooking.lua), and says
        -- the fire wants striking.
        if held ~= STRIKER then return nil end
        local ok, why = F.ignite(pos, e.player)
        if not ok then return why end
        T.wear_held(e.player, 1)
        return ""
    end

    if is_lit(name) and held then
        local ticks = fuel_ticks(held)
        if not ticks then
            -- Not fuel: food (or clay) held out over a burning fire goes on
            -- it, into its box (cooking.lua).
            if tdc.cooking then return tdc.cooking.put_on(e, pos) end
            return nil
        end
        local key = key_of(pos)
        local fire = fires[key]
        if not fire then return "That fire needs nothing from you." end
        if fire.fuel + ticks > C.fire_max_fuel then return "The fire is roaring already." end
        if e.held.units < U.UNITS or e.held.shape ~= nil or e.held.detail ~= nil then return nil end
        if game.take(e.player, { material = e.held.material, units = U.UNITS }) < U.UNITS then
            return nil
        end
        F.add_fuel(pos, ticks)
        return ""
    end
end)

return F
