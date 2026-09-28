-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- The anvil: iron worked by hand (brief §7.4).
--
-- A station you STRIKE. The work goes on it through its screen, where the
-- player also chooses what to forge; then each use of the anvil with a
-- hammer in hand is a blow. A recipe here takes `strikes` blows, with a
-- hammer the recipe names in the hand — the held one, not one in a pocket —
-- and is made on the last, the hammer taking its wear. A bloom is beaten
-- into a wrought bar with any hammer; a bar into a head only with an iron
-- one, except the first iron hammer's own head, which a bronze hammer
-- forges in more blows at twice the wear.
--
-- Blows are counted per anvil and kept with the world. Changing the work
-- or the choice starts the count over.

local U = tdc.util
local R = tdc.registry
local ST = tdc.stations

local A = {}

local states = {}   -- container -> { choice, strikes, work }

local function state(name)
    local s = states[name]
    if s then return s end
    s = U.decode(game.storage.get("anvil:" .. name))
    s.strikes = math.type(s.strikes) == "integer" and s.strikes or 0
    if type(s.choice) ~= "string" or s.choice == "" then s.choice = nil end
    if type(s.work) ~= "string" or s.work == "" then s.work = nil end
    states[name] = s
    return s
end

local function save(name)
    local s = states[name]
    game.storage.set("anvil:" .. name, s and U.encode{ choice = s.choice or "", strikes = s.strikes,
        work = s.work or "" } or nil)
end

function A.forget(name)
    states[name] = nil
    game.storage.set("anvil:" .. name, nil)
end

--- Chooses what an anvil forges.
function A.choose(name, id)
    local s = state(name)
    if s.choice ~= id then s.choice, s.strikes, s.work = id, 0, nil end
    save(name)
end

--- Whether the hammer in hand is one a recipe names.
local function right_hammer(recipe, held)
    local id = held and game.block_of(held.material)
    if not id then return false end
    for _, tool in ipairs(recipe.tools) do
        for _, member in ipairs(R.members(tool.name)) do
            if member == id then return true end
        end
    end
    return false
end

--- What is on the anvil, as one string, so a change of work is seen.
local function work_of(name, station)
    local parts = {}
    for _, stack in ipairs(game.container(name)) do
        for _, slot in ipairs(station.slots.input) do
            if stack.slot == slot then parts[#parts + 1] = stack.material .. "x" .. stack.units end
        end
    end
    return table.concat(parts, "+")
end

--- One blow. Answers what the player is told ("" for nothing).
function A.strike(e, station, name)
    local s = state(name)
    local held = e.held
    -- With nothing chosen, the one recipe the work allows is the choice.
    if not s.choice then
        for _, recipe in ipairs(R.list_particular(station.id)) do
            if right_hammer(recipe, held) and R.check(e.player, recipe.id, name) then
                s.choice = recipe.id
                break
            end
        end
        if not s.choice then return "Nothing on the anvil that hammer can work." end
    end
    local recipe = R.recipe(s.choice)
    if not right_hammer(recipe, held) then
        return "That takes the " .. U.friendly(recipe.tools[1].name) .. "."
    end
    local ok, why = R.check(e.player, s.choice, name)
    if not ok then return "Cannot forge " .. recipe.name .. ": " .. why .. "." end
    local work = work_of(name, station)
    if work ~= s.work then s.work, s.strikes = work, 0 end
    s.strikes = s.strikes + 1
    tdc.sounds.at("anvil_ring", { x = e.x // 3, y = e.y // 3, z = e.z // 3 })
    local done = s.strikes >= recipe.strikes
    if done then
        s.strikes, s.work = 0, nil
        local made, reason = R.perform(e.player, s.choice, name)
        save(name)
        ST.redraw(name)
        if not made then return "Cannot forge " .. recipe.name .. ": " .. reason .. "." end
        return ""
    end
    save(name)
    ST.redraw(name)
    return ""
end

--- What an anvil's screen shows.
function A.status(name)
    local s = state(name)
    local status = { burn = 0, progress = 0, heat_text = "Strike it", job_text = "Nothing chosen" }
    if s.choice then
        local recipe = R.recipe(s.choice)
        status.job_text = recipe.name
        status.progress = (s.strikes * 1000) // recipe.strikes
        status.note = string.format("Forging %s: %d of %d blows.", recipe.name, s.strikes, recipe.strikes)
    else
        status.note = "Choose what to forge, then strike the anvil with a hammer."
    end
    return status
end

return A
