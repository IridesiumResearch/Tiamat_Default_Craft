-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Stations that burn: the kiln, and anything else registered with
-- `heat = true` — the bloomery to come, another mod's alembic. One loop,
-- generic over the station record.
--
-- # The heat model
--
-- A furnace is lit with a fire striker once there is fuel in its fuel slot,
-- and from then it burns: 27 units of fuel at a time, each lasting the
-- fuel's ticks at the fuel's heat (config.lua, `C.fuels`), until the slot is
-- empty and it goes out. While it burns it makes whatever its contents
-- allow: of the station's recipes, the first (by id) that its inputs, its
-- tool slot and its heat satisfy. A recipe takes its `ticks` of burning to
-- make, and starts over if what is in the furnace changes under it or the
-- heat drops below it.
--
-- # Nobody is watching
--
-- A furnace works on the tick, whether or not anybody has it open. It makes
-- things as the player who lit it — the gate asks after them and the firsts
-- are theirs — but it uses nothing of theirs: its crucible and moulds are in
-- its own tool slot (`unattended` in the registry).
--
-- # State
--
-- One storage string per furnace, `furnace:<container>`, rewritten once a
-- second while it burns. A furnace in a chunk that is not loaded is paused.

local C = tdc.config
local U = tdc.util
local R = tdc.registry
local ST = tdc.stations

local FU = {}

local STRIKER = game.mod_id .. ":fire_striker"

-- The unfired kiln opens as the kiln; its first fire makes it one.
ST.alias(game.mod_id .. ":unfired_kiln", "kiln")

local life = game.exports("tiamat_default_life")
if life and life.version == 1 and life.add_heat_source then
    life.add_heat_source(game.mod_id .. ":kiln_lit", 0.6)
end

local states = {}   -- container -> { lit, burn, full, heat, job, progress, by }

local function state(name)
    local s = states[name]
    if s then return s end
    s = U.decode(game.storage.get("furnace:" .. name))
    s.lit = s.lit == 1 and 1 or 0
    s.burn = math.type(s.burn) == "integer" and s.burn or 0
    s.full = math.type(s.full) == "integer" and s.full or 0
    s.heat = math.type(s.heat) == "integer" and s.heat or 0
    s.progress = math.type(s.progress) == "integer" and s.progress or 0
    if type(s.job) ~= "string" or s.job == "" then s.job = nil end
    if type(s.by) ~= "string" or s.by == "" then s.by = nil end
    states[name] = s
    return s
end

local function save(name)
    local s = states[name]
    if not s then return end
    game.storage.set("furnace:" .. name, U.encode{
        lit = s.lit, burn = s.burn, full = s.full, heat = s.heat, progress = s.progress,
        job = s.job or "", by = s.by or "",
    })
end

--- Forgets a furnace that has been dug.
function FU.forget(name)
    states[name] = nil
    game.storage.set("furnace:" .. name, nil)
end

--- How hot a furnace is burning, as a tier; 0 when it is out.
function FU.heat(name)
    local s = states[name] or (game.storage.get("furnace:" .. name) and state(name))
    if not s or s.lit ~= 1 then return 0 end
    return s.heat
end

R.heat_of = FU.heat

--- The stack in a container's slot, or nil.
local function in_slot(name, slot)
    for _, stack in ipairs(game.container(name)) do
        if stack.slot == slot then return stack end
    end
    return nil
end

--- The fuel a station would burn next from its fuel slots: `{ slot, material,
--- heat, ticks }`, or nil.
local function next_fuel(station, name)
    for _, slot in ipairs(station.slots.fuel) do
        local stack = in_slot(name, slot)
        if stack and stack.shape == nil and stack.detail == nil and stack.units >= U.UNITS then
            local id = game.block_of(stack.material)
            local fuel = id and R.fuel(id, station)
            if fuel then
                return { slot = slot, material = stack.material, heat = fuel.heat, ticks = fuel.ticks }
            end
        end
    end
    return nil
end

--- Burns the next 27 units of fuel. Answers whether there was any.
local function stoke(station, name, s)
    local fuel = next_fuel(station, name)
    if not fuel then return false end
    if game.container_take(name, { material = fuel.material, units = U.UNITS, slot = fuel.slot }) < U.UNITS then
        return false
    end
    s.burn, s.full, s.heat = fuel.ticks, fuel.ticks, fuel.heat
    return true
end

--- The block a station is shown as, lit or not.
local function swap(station, pos, lit)
    local want = lit and (station.lit_block or station.block) or station.block
    local at = game.get_block(pos)
    local now = at and at.material and game.block_of(at.material)
    if want and now ~= want then game.set_block(pos, want) end
end

--- What a furnace would make now, by recipe id, or nil.
local function choose(station, name, s)
    local opts = { container = name, heat = s.heat, unattended = true }
    if s.job and R.check(s.by, s.job, opts) then return s.job end
    for _, recipe in ipairs(R.list(station.id)) do
        if R.check(s.by, recipe.id, opts) then return recipe.id end
    end
    return nil
end

--- One step of a furnace's life.
local function tend(station, name, pos, step)
    local s = state(name)
    if s.lit ~= 1 then return end
    if game.get_block(pos) == nil then return end   -- not loaded: paused
    s.burn = s.burn - step
    if s.burn <= 0 and not stoke(station, name, s) then
        s.lit, s.burn, s.full, s.heat, s.job, s.progress = 0, 0, 0, 0, nil, 0
        swap(station, pos, false)
        save(name)
        ST.redraw(name)
        return
    end
    local job = choose(station, name, s)
    if job ~= s.job then
        s.job, s.progress = job, 0
    end
    if job then
        s.progress = s.progress + step
        local recipe = R.recipe(job)
        if s.progress >= recipe.ticks then
            s.progress = 0
            R.perform(s.by, job, { container = name, heat = s.heat, unattended = true })
        end
    end
    save(name)
    ST.redraw(name)
end

local heat_stations = nil

local elapsed = 0
tdc.on_tick(function(dt)
    elapsed = elapsed + dt
    if elapsed < C.furnace_step then return end
    local step = elapsed
    elapsed = 0
    if not heat_stations then
        heat_stations = {}
        for _, id in ipairs(R.station_ids()) do
            local station = R.station(id)
            if station.heat and station.block then heat_stations[#heat_stations + 1] = station end
        end
    end
    for _, station in ipairs(heat_stations) do
        for _, placed in ipairs(ST.indexed(station.id)) do
            tend(station, placed.name, placed.pos, step)
        end
    end
end)

--- The place control on a furnace: a striker lights it. Answers nil when
--- the player is not holding one, so the screen opens instead.
function FU.light(e, station, name, pos)
    local held = e.held and game.block_of(e.held.material)
    if held ~= STRIKER then return nil end
    local s = state(name)
    if s.lit == 1 then return "It is burning already." end
    if not next_fuel(station, name) then return "It wants fuel first." end
    local was = game.block_of(e.material)
    if not stoke(station, name, s) then return "It wants fuel first." end
    s.lit, s.by, s.job, s.progress = 1, e.player, nil, 0
    swap(station, pos, true)
    save(name)
    tdc.tools.wear_held(e.player, 1)
    if was == game.mod_id .. ":unfired_kiln" then
        R.first(e.player, "fire:kiln")
    end
    return ""
end

--- What a furnace's screen shows: two bars and a line.
function FU.status(name)
    local s = state(name)
    local status = { burn = 0, progress = 0, heat_text = "Cold", job_text = "Idle" }
    if s.lit == 1 then
        status.burn = s.full > 0 and (s.burn * 1000) // s.full or 0
        status.heat_text = ({ "Red heat", "Orange heat", "White heat" })[s.heat] or ("Heat " .. s.heat)
    end
    if s.job then
        local recipe = R.recipe(s.job)
        status.job_text = recipe.name
        status.progress = recipe.ticks > 0 and (s.progress * 1000) // recipe.ticks or 0
    elseif s.lit == 1 then
        -- Burning, and something in the inputs that nothing here makes: say so.
        local station = R.station(ST.kind_id(name) or "")
        for _, slot in ipairs(station and station.slots.input or {}) do
            local stack = in_slot(name, slot)
            if stack then
                local id = game.block_of(stack.material) or ""
                status.note = C.kiln_refusals[string.match(id, ":(.+)$") or ""] or C.kiln_idle
                break
            end
        end
    else
        status.note = "Put fuel in, and strike it to light it."
    end
    return status
end

return FU
