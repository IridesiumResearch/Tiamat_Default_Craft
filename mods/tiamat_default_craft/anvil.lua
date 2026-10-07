-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- The anvil: iron worked by hand (brief §7.4).
--
-- A station you STRIKE. The work is held in the off-hand — the bloom, the
-- bars — and each use of the anvil with a hammer in the main hand is a blow
-- (engine ask 9: the off-hand read with `game.slot`, taken from and given
-- back into). Or the work goes on the anvil through its screen, which is
-- also where the player chooses what to forge when a bar could become
-- several things. A recipe here takes `strikes` blows, with a
-- hammer the recipe names in the hand — the held one, not one in a pocket —
-- and is made on the last, the hammer taking its wear. A bloom is beaten
-- into a wrought bar with any hammer; a bar into a head only with an iron
-- one, except the first iron hammer's own head, which a bronze hammer
-- forges in more blows at twice the wear.
--
-- Blows are counted per anvil and kept with the world. Changing the work
-- or the choice starts the count over.

local C = tdc.config
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

local IRON_ANVIL = game.mod_id .. ":iron_anvil"

--- Whether the anvil at a use is iron.
local function iron_at(e)
    local at = game.get_block{ x = e.x // 3, y = e.y // 3, z = e.z // 3, domain = e.domain ~= "overworld" and e.domain or nil }
    return U.name_at(at) == IRON_ANVIL
end

--- Blows a recipe takes this player, on a stone anvil or an iron one.
function A.strikes(uuid, recipe, iron)
    local n = math.max(1, recipe.strikes + R.effect(uuid, "craft.anvil_strikes"))
    if iron then n = (n + C.iron_anvil_divisor - 1) // C.iron_anvil_divisor end
    return n
end

--- What in the off-hand a recipe can work: the plain stack in the slot, if
--- it is the recipe's input and enough of it.
local function offhand_for(recipe, stack)
    local input = recipe.inputs[1]
    if #recipe.inputs ~= 1 or not stack or stack.shape ~= nil or stack.detail ~= nil then return false end
    local id = game.block_of(stack.material)
    for _, member in ipairs(R.members(input.name)) do
        if member == id then return stack.units >= input.units end
    end
    return false
end

--- A blow at work held in the off-hand.
local function strike_offhand(e, station, name, s, stack)
    local held = e.held
    local recipe = s.choice and R.recipe(s.choice)
    if not (recipe and right_hammer(recipe, held) and offhand_for(recipe, stack)) then
        recipe = nil
        for _, r in ipairs(R.list_particular(station.id)) do
            if right_hammer(r, held) and offhand_for(r, stack) and R.allowed(e.player, r.requires) then
                recipe = r
                break
            end
        end
    end
    if not recipe then return "Nothing in your off-hand that hammer can work." end
    if not R.allowed(e.player, recipe.requires) then return "You do not know how to forge that yet." end
    local work = "off:" .. stack.material .. "x" .. stack.units .. ":" .. recipe.id
    if work ~= s.work then s.work, s.strikes, s.choice = work, 0, recipe.id end
    s.strikes = s.strikes + 1
    tdc.sounds.at("anvil_ring", { x = e.x // 3, y = e.y // 3, z = e.z // 3 })
    if s.strikes < A.strikes(e.player, recipe, iron_at(e)) then
        save(name)
        return ""
    end
    s.strikes, s.work = 0, nil
    save(name)
    local slot = C.offhand_slot
    local need = recipe.inputs[1].units
    if game.take(e.player, { material = stack.material, units = need, slot = slot }) < need then
        return "The work slipped from your hand."
    end
    local outputs = {}
    for i, out in ipairs(recipe.outputs) do
        local spec = { material = out.name, units = out.units, slot = slot }
        if R.minted(out.name) then spec.detail = R.mint(out.name) end
        if not game.give(e.player, spec) then
            spec.slot = nil
            U.give(e.player, spec)
        end
        outputs[i] = { material = out.name, units = out.units }
    end
    for _, tool in ipairs(recipe.tools) do
        if tool.wear > 0 then tdc.tools.wear_held(e.player, tool.wear) end
    end
    R.announce(e.player, recipe.id, outputs)
    return ""
end

--- One blow. Answers what the player is told ("" for nothing).
function A.strike(e, station, name)
    local s = state(name)
    local held = e.held
    -- Nothing on the anvil: the work is in the off-hand.
    local on_it = false
    for _, stack in ipairs(game.container(name)) do
        for _, slot in ipairs(station.slots.input) do
            if stack.slot == slot then on_it = true end
        end
    end
    if not on_it then
        local off = game.slot(e.player, "player:main", C.offhand_slot)
        if off then return strike_offhand(e, station, name, s, off) end
    end
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
    s.iron = iron_at(e) and 1 or 0
    local done = s.strikes >= A.strikes(e.player, recipe, s.iron == 1)
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
        local blows = A.strikes(nil, recipe, s.iron == 1)
        status.progress = (s.strikes * 1000) // blows
        status.note = string.format("Forging %s: %d of %d blows.", recipe.name, s.strikes, blows)
    else
        status.note = "Choose what to forge, then strike the anvil with a hammer."
    end
    return status
end

return A
