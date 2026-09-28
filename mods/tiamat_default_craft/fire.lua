-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Campfires: building, lighting, feeding, burning out — and fire-setting,
-- the mechanism that stands where stone tools would have been (brief §4.4).
--
-- # The cycle
--
-- An unlit campfire is a block a player lays. Struck with a fire striker it
-- becomes a lit fire: Life's campfire when Life is here (so its heat, light
-- and burn are Life's, written once), this mod's own `campfire_lit` when it
-- is not. A fire this mod lit has fuel, and goes back to an unlit campfire
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

--- The block a fire is lit as.
F.LIT = U.material(LIFE_LIT) and LIFE_LIT or OWN_LIT

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

-- A cracked block yields the rock it was: a unit for each of its cells the
-- dig takes, which is the whole block for a hand and one cell for a chisel.
local parent_of = nil   -- numeric twin -> parent qualified id

tdc.on_dug(function(e)
    if not parent_of then
        parent_of = {}
        for parent, twin in pairs(cracked_names) do
            local material = U.material(twin)
            if material and U.material(parent) then parent_of[material] = parent end
        end
    end
    local parent = parent_of[e.material]
    if not parent then return end
    local units = 1
    if e.brush == "block" then
        units = 0
        local at = game.get_block{ x = e.x // 3, y = e.y // 3, z = e.z // 3 }
        if at and at.cells then
            for _, cell in ipairs(at.cells) do
                if cell == e.material then units = units + 1 end
            end
        elseif at and at.material == e.material then
            for i = 0, 26 do
                if at.occupancy & (1 << i) ~= 0 then units = units + 1 end
            end
        end
    end
    if units > 0 then
        game.give(e.player, { material = parent, units = units })
    end
end)

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
    for _, key in ipairs(game.storage.keys()) do
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
    return name == F.LIT or name == OWN_LIT
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

--- Whether there is a fire this mod lit at a block position.
function F.burning(pos)
    return fires[key_of(pos)] ~= nil
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

--- Cracks what the fire reaches.
local function crack_around(fire)
    local table_ = cracks()
    for _, p in ipairs(reach(pos_of(fire))) do
        local at = game.get_block(p)
        local crack = at and at.occupancy == game.OCCUPANCY_FULL and at.material and table_[at.material]
        if crack and game.set_block(p, crack.twin) and fire.by then
            R.first(fire.by, "fireset:" .. string.match(crack.parent, ":(.+)$"))
        end
    end
end

--- One step of a fire's life: burn, heat, crack, go out.
local function tend(key, fire, step)
    local pos = pos_of(fire)
    local at = game.get_block(pos)
    if at == nil then return end                    -- not loaded: paused
    local name = at.material and game.block_of(at.material)
    if not is_lit(name) then                         -- dug, or put out by something else
        forget(key)
        return
    end
    fire.fuel = fire.fuel - step
    fire.heat = fire.heat + step
    local fireset = math.max(C.fire_step, C.fireset_ticks + R.effect(fire.by, "craft.fireset_ticks"))
    while fire.heat >= fireset do
        fire.heat = fire.heat - fireset
        crack_around(fire)
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

--- Ticks of fire in 27 units of a material, by name, or nil.
local function fuel_ticks(name)
    if C.campfire_fuel[name] then return C.campfire_fuel[name] end
    for _, group in ipairs(U.sorted_keys(C.campfire_fuel)) do
        if U.group(group) and R.in_group(group, name) then return C.campfire_fuel[group] end
    end
    return nil
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
        if not game.set_block(pos, F.LIT) then return "It will not catch." end
        local key = key_of(pos)
        fires[key] = { x = pos.x, y = pos.y, z = pos.z, domain = pos.domain or "overworld",
            fuel = C.fire_fuel, heat = 0, by = e.player }
        save(key)
        T.wear_held(e.player, 1)
        R.first(e.player, "fire:lit")
        return ""
    end

    if is_lit(name) and held then
        local ticks = fuel_ticks(held)
        if not ticks then return nil end
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
