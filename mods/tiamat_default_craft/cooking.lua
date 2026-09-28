-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Cooking on a campfire (brief §6.2, reshaped).
--
-- # Why the fire has a box
--
-- The brief had a player use a fire holding raw meat. Life hears every use
-- first — it loads before this mod — and eats whatever food is in the hand,
-- at a fire or anywhere, which is right for eating and leaves nothing to
-- cook with. So a fire has a container, as a station does: used with an
-- empty hand it opens, with two slots on the fire, one for a pot and one for
-- what comes off, and a burning fire cooks whatever is on it on its own.
-- Nothing here reaches past Life's eating; the two never contend.
--
-- # What a fire does
--
-- The most particular campfire recipe that what is on the fire allows, at a
-- steady pace while it burns: raw meat to cooked, raw meat and fruit to hot
-- stew in a copper pot, wet clay dried. Cooked meat left in the out slot
-- over a burning fire chars. A fire that goes out keeps what was on it, and
-- the box opens on the unlit campfire too.
--
-- The food is Life's — its raw and cooked meat, its stew, its eat key — so
-- a world without Life cooks nothing, and the recipes naming its items say
-- so in the log once.

local C = tdc.config
local U = tdc.util
local R = tdc.registry
local ST = tdc.stations
local F = tdc.fire

local CO = {}

local LIFE = "tiamat_default_life:"
local COOKED = LIFE .. "cooked_meat"
local CHARRED = game.mod_id .. ":charred_meat"

-- The fire's box opens on every campfire this mod knows, lit or not.
ST.alias(game.mod_id .. ":campfire_lit", "campfire")
ST.alias(game.mod_id .. ":unlit_campfire", "campfire")

local states = {}    -- container -> { job, progress, char }

local function state(name)
    local s = states[name]
    if s then return s end
    s = U.decode(game.storage.get("cook:" .. name))
    s.progress = math.type(s.progress) == "integer" and s.progress or 0
    s.char = math.type(s.char) == "integer" and s.char or 0
    if type(s.job) ~= "string" or s.job == "" then s.job = nil end
    states[name] = s
    return s
end

local function save(name)
    local s = states[name]
    game.storage.set("cook:" .. name, s and U.encode{ job = s.job or "", progress = s.progress, char = s.char } or nil)
end

--- The stack in a container's slot, or nil.
local function in_slot(name, slot)
    for _, stack in ipairs(game.container(name)) do
        if stack.slot == slot then return stack end
    end
    return nil
end

--- Cooked meat left over a fire chars.
local function char(station, name, s, step)
    local out = station.slots.output[1]
    local stack = in_slot(name, out)
    local cooked = U.material(COOKED)
    if not (stack and cooked and stack.material == cooked and stack.detail == nil) then
        s.char = 0
        return
    end
    s.char = s.char + step
    if s.char < C.char_ticks then return end
    s.char = 0
    local units = game.container_take(name, { material = cooked, units = stack.units, slot = out })
    if units > 0 then
        local put = game.container_give(name, { material = CHARRED, units = units, slot = out })
        if put < units then
            -- The slot will not take it back as charred: leave it cooked.
            game.container_give(name, { material = cooked, units = units - put, slot = out })
        end
    end
end

--- One step of cooking over one burning fire.
local function cook(station, fire, step)
    local name = ST.name("campfire", fire.pos)
    if not game.container_holder(name) and #game.container(name) == 0 then return end
    local s = state(name)
    local opts = { container = name, unattended = true }
    local job = nil
    if s.job and R.check(fire.by, s.job, opts) then
        job = s.job
    else
        for _, recipe in ipairs(R.list_particular("campfire")) do
            if R.check(fire.by, recipe.id, opts) then job = recipe.id break end
        end
    end
    if job ~= s.job then s.job, s.progress = job, 0 end
    if job then
        s.progress = s.progress + step
        if s.progress >= R.recipe(job).ticks then
            s.progress = 0
            if R.perform(fire.by, job, opts) then
                tdc.sounds.at("sizzle", fire.pos)
            end
        end
    end
    char(station, name, s, step)
    save(name)
    ST.redraw(name)
end

local elapsed = 0
tdc.on_tick(function(dt)
    elapsed = elapsed + dt
    if elapsed < C.fire_step then return end
    local step = elapsed
    elapsed = 0
    local station = R.station("campfire")
    for _, fire in ipairs(F.list()) do
        cook(station, fire, step)
    end
end)

--- What a fire's screen shows: the job, and whether it burns.
function CO.status(name, pos)
    local s = state(name)
    local status = { burn = 0, progress = 0, heat_text = "Out", job_text = "Nothing on it" }
    if pos and F.burning(pos) then
        status.burn = 1000
        status.heat_text = "Burning"
    else
        status.note = "The fire is out. Strike it to cook."
    end
    if s.job then
        local recipe = R.recipe(s.job)
        status.job_text = recipe.name
        status.progress = recipe.ticks > 0 and (s.progress * 1000) // recipe.ticks or 0
    end
    return status
end

function CO.forget(name)
    states[name] = nil
    game.storage.set("cook:" .. name, nil)
end

return CO
