-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- The sluice: tin washed out of river gravel (brief §7.5).
--
-- Placer tin is how the Bronze Age really got it, and it puts tin at the
-- surface in any river valley, so bronze does not wait on a 200-block dig.
-- Deep tin ore stays the efficient source once there is a pick for it.
--
-- A sluice is planks and cord, and must stand in running water: placed
-- with no water against a face, it is refused. Gravel put in it is washed a
-- block at a time — sand out, and a grain of tin — every `wash_ticks` while
-- water still touches it. Every ninth wash also leaves a flake of gold. The
-- ninth is a COUNTER kept per sluice, not a chance: the same gravel washes
-- the same way on every machine (charter rule 4), and nothing is luck.

local C = tdc.config
local U = tdc.util
local R = tdc.registry
local ST = tdc.stations

local SL = {}

local WATER = U.world("water")
local FLAKE = game.mod_id .. ":gold_flake"
local SIDES = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } }

--- Whether water touches a block.
function SL.wet(pos)
    local water = game.fluid_id(WATER)
    if not water then return false end
    for _, s in ipairs(SIDES) do
        local here = game.get_fluid{ x = pos.x + s[1], y = pos.y + s[2], z = pos.z + s[3], domain = pos.domain }
        if here and not here.empty and here.fluid == water and here.volume > 0 then return true end
    end
    return false
end

ST.check("sluice", function(pos)
    if not SL.wet(pos) then return C.sluice_dry end
end)

local states = {}   -- container -> { progress, washes }

local function state(name)
    local s = states[name]
    if s then return s end
    s = U.decode(game.storage.get("sluice:" .. name))
    s.progress = math.type(s.progress) == "integer" and s.progress or 0
    s.washes = math.type(s.washes) == "integer" and s.washes or 0
    states[name] = s
    return s
end

local function save(name)
    local s = states[name]
    game.storage.set("sluice:" .. name, s and U.encode{ progress = s.progress, washes = s.washes } or nil)
end

function SL.forget(name)
    states[name] = nil
    game.storage.set("sluice:" .. name, nil)
end

local WASH = game.mod_id .. ":wash"

local function tend(station, name, pos, step)
    if game.get_block(pos) == nil then return end          -- not loaded: paused
    local s = state(name)
    local opts = { container = name, unattended = true }
    if not (SL.wet(pos) and R.check(nil, WASH, opts)) then
        if s.progress ~= 0 then s.progress = 0 save(name) end
        return
    end
    s.progress = s.progress + step
    if s.progress >= R.recipe(WASH).ticks then
        s.progress = 0
        if R.perform(nil, WASH, opts) then
            s.washes = s.washes + 1
            if s.washes % C.gold_every == 0 then
                for _, slot in ipairs(station.slots.output) do
                    if game.container_give(name, { material = FLAKE, count = 1, slot = slot }) > 0 then break end
                end
            end
        end
    end
    save(name)
    ST.redraw(name)
end

local elapsed = 0
tdc.on_tick(function(dt)
    elapsed = elapsed + dt
    if elapsed < C.fire_step then return end
    local step = elapsed
    elapsed = 0
    local station = R.station("sluice")
    for _, placed in ipairs(ST.indexed("sluice")) do
        tend(station, placed.name, placed.pos, step)
    end
end)

return SL
