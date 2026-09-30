-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Crafting grids: the workbench's three by three, and the two by two every
-- player carries on the Craft tab.
--
-- # What the output slot holds
--
-- While the grid holds a recipe (registry.lua's `grid_match`), its result is
-- put in the output slot to be seen: a PREVIEW, which nothing has paid for
-- yet. The engine moves items when a slot is clicked and tells this mod
-- afterwards, so a preview that is no longer there as it was put is one the
-- player took, and that is when the recipe is made: the grid's cells are
-- spent and its tools worn. Shift-click takes one into the pack and then
-- makes as many more as the grid holds.
--
-- Something put ON the preview (the same thing, merged in) is not a take:
-- the preview comes back out and what they put there stays. Taking half of
-- it is a take; the half left behind is paid for and is theirs.
--
-- # A preview must never outlive its screen
--
-- It is removed when the screen closes, when the player leaves, when the
-- station is dug, and — since the interface's tab says nothing when it
-- closes — whenever a tick finds its container no longer lent to the player
-- it was shown to. It is written in storage too (`preview:<container>`), so
-- one a crash left behind is taken back out the next time anybody looks.
-- The two by two gives what is left in it back to the pack when it closes.

local C = tdc.config
local U = tdc.util
local R = tdc.registry

local G = {}

local previews = {}   -- container -> { match, stack = { material, units, detail }, slot, g }
local hands = {}      -- uuid -> the player's own grid, while it is on their screen

local function marker(container) return "preview:" .. container end

local function in_slot(container, slot)
    for _, stack in ipairs(game.container(container)) do
        if stack.slot == slot then return stack end
    end
    return nil
end

local function same(stack, p)
    return stack ~= nil and stack.shape == nil and stack.material == p.material and stack.units == p.units
        and stack.detail == p.detail
end

--- Takes a preview back out of its slot, if it is still there as it was put.
local function withdraw(container)
    local p = previews[container]
    previews[container] = nil
    game.storage.set(marker(container), nil)
    if p and same(in_slot(container, p.slot), p.stack) then
        game.container_take(container,
            { material = p.stack.material, units = p.stack.units, slot = p.slot, detail = p.stack.detail })
    end
end

--- What a grid holds, as `grid_match` reads it.
local function grid_of(g)
    local cell = {}
    for i, slot in ipairs(g.inputs) do
        if i <= g.n * g.n then cell[slot] = i end
    end
    local stacks = {}
    for _, stack in ipairs(game.container(g.container)) do
        if cell[stack.slot] then stacks[cell[stack.slot]] = stack end
    end
    return { n = g.n, stacks = stacks }
end

--- A grid, as the rest of this file takes it: `{ container, n, inputs (its
--- slots, row by row), output (a slot), ids (the recipes it can hold),
--- player, hand? }`.
function G.new(spec) return spec end

--- Puts the grid's result in the output slot, or takes a stale one out.
function G.refresh(g)
    local p = previews[g.container]
    if p and not same(in_slot(g.container, p.slot), p.stack) then
        previews[g.container] = nil
        game.storage.set(marker(g.container), nil)
        p = nil
    end
    local match = R.grid_match(g.player, g.ids, grid_of(g))
    if p and match and match.recipe.id == p.match.recipe.id then
        -- The same thing still: keep the one shown (a tool keeps its serial).
        match.rest = p.match.rest
        p.match, p.g = match, g
        return
    end
    if p then withdraw(g.container) end
    if not match or in_slot(g.container, g.output) then return end   -- a real thing sits there
    local piece = R.grid_preview(match)
    local put = game.container_give(g.container,
        { material = piece.material, units = piece.units, slot = g.output, detail = piece.detail })
    if put < piece.units then
        if put > 0 then
            game.container_take(g.container, { material = piece.material, units = put, slot = g.output, detail = piece.detail })
        end
        return
    end
    previews[g.container] = {
        match = match, slot = g.output, g = g,
        stack = { material = piece.material, units = piece.units, detail = piece.detail },
    }
    game.storage.set(marker(g.container), U.encode{
        m = game.block_of(piece.material) or "", u = piece.units, d = piece.detail or "",
    })
end

--- The player took the preview: make it, and with shift, as many more as the
--- grid holds.
local function taken(g, match, shift)
    if not R.grid_make(g.player, match, g.container) then
        game.log("tiamat_default_craft: a grid's result was taken with its ingredients gone")
        return
    end
    tdc.sounds.at_player("craft", g.player)
    if not shift then return end
    for _ = 1, C.grid_shift_most do
        local more = R.grid_match(g.player, g.ids, grid_of(g))
        if not (more and more.recipe.id == match.recipe.id) then break end
        local piece = R.grid_preview(more)
        if not R.grid_make(g.player, more, g.container) then break end
        if U.give(g.player, piece) > 0 then break end
    end
end

--- A slot was clicked on a screen showing the grid: the engine has already
--- moved what it moved. Was the preview taken?
function G.clicked(g, e)
    local p = previews[g.container]
    if p then
        local now = in_slot(g.container, p.slot)
        if not same(now, p.stack) then
            previews[g.container] = nil
            game.storage.set(marker(g.container), nil)
            if now and now.shape == nil and now.material == p.stack.material and now.detail == p.stack.detail
                and now.units > p.stack.units then
                -- Put onto, not taken from: the preview comes back out.
                game.container_take(g.container,
                    { material = p.stack.material, units = p.stack.units, slot = p.slot, detail = p.stack.detail })
            else
                taken(g, p.match, e.click == "shift_left" and e.view == g.container and e.index == p.slot)
            end
        end
    end
    G.refresh(g)
end

--- The screen showing a grid has closed: its preview goes, and a hand grid
--- gives what is in it back to the pack.
function G.closed(g)
    withdraw(g.container)
    if not g.hand then return end
    hands[g.player] = nil
    for _, stack in ipairs(game.container(g.container)) do
        local spec = { material = stack.material, units = stack.units, slot = stack.slot, shape = stack.shape,
            detail = stack.detail }
        local took = game.container_take(g.container, spec)
        if took > 0 then
            spec.slot, spec.units = nil, took
            local left = U.give(g.player, spec)
            if left > 0 then
                spec.units, spec.slot = left, stack.slot
                game.container_give(g.container, spec)
            end
        end
    end
end

--- Takes out a preview a crash left behind: called before anybody sees a
--- grid's container.
function G.recover(container, slot)
    if previews[container] then return end
    local text = game.storage.get(marker(container))
    if text == nil then return end
    game.storage.set(marker(container), nil)
    local m = U.decode(text)
    local stack = in_slot(container, slot)
    local detail = m.d ~= "" and m.d or nil
    if stack and stack.shape == nil and game.block_of(stack.material) == m.m and stack.units == m.u
        and stack.detail == detail then
        game.container_take(container, { material = stack.material, units = stack.units, slot = slot, detail = detail })
    end
end

--- A player's own two by two: made, lent to them and remembered while it is
--- on their screen.
function G.hand(player, ids)
    local name = game.mod_id .. ":hand_grid:" .. player
    local g = hands[player]
    if not g then
        game.make_container(name, 5)
        G.recover(name, 5)
        g = G.new{ container = name, n = 2, inputs = { 1, 2, 3, 4 }, output = 5, player = player, hand = true }
        hands[player] = g
    end
    g.ids = ids
    if game.container_holder(name) ~= player then game.open_container(name, player) end
    return g
end

function G.hand_of(player) return hands[player] end

-- A grid whose screen went without a word (the interface's tab) is closed here.
local elapsed = 0
tdc.on_tick(function(dt)
    elapsed = elapsed + dt
    if elapsed < C.furnace_step then return end
    elapsed = 0
    local gone = {}
    for _, container in ipairs(U.sorted_keys(previews)) do
        local g = previews[container].g
        if game.container_holder(container) ~= g.player then gone[#gone + 1] = g end
    end
    for _, player in ipairs(U.sorted_keys(hands)) do
        local g = hands[player]
        if game.container_holder(g.container) ~= player then gone[#gone + 1] = g end
    end
    for _, g in ipairs(gone) do G.closed(g) end
end)

tdc.on_leave(function(e)
    local g = hands[e.player]
    if g then G.closed(g) end
    for _, container in ipairs(U.sorted_keys(previews)) do
        local p = previews[container]
        if p and p.g.player == e.player then G.closed(p.g) end
    end
end)

return G
