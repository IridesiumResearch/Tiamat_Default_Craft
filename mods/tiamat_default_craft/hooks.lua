-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- One of each engine hook for the whole mod, with subscribers.
--
-- The engine keeps ONE callback per hook per mod: a second registration is
-- refused. So every file that wants a tick, a dig, a use or a chat word
-- subscribes here, and this file holds the engine's single registration of
-- each.
--
-- The hooks that can refuse (a dig, a placement, a use) ask their
-- subscribers in order and stop at the first that answers: the engine's own
-- ladder, `nil` or `true` passing and anything else deciding.

local ticks = {}
local words = {}
local actions = {}
local joins = {}
local leaves = {}
local dialogs = {}
local dig_starts = {}
local dig_completes = {}
local dug = {}
local places = {}
local uses = {}

-- Whether the registration window is still open. The engine closes its own
-- when init.lua returns; this mod's registry (registry.lua) closes the same
-- moment, which it can tell by the first thing the running world does. The
-- world's seed is nil until then in every VM, which covers a callback from a
-- mod that loads after this one and registers from its own init.
local started = false

local function start()
    started = true
end

--- Whether mods are still loading.
function tdc.loading()
    return not started and game.world_seed == nil
end

-- Runs `fn(dt_ticks)` every tick, after everything subscribed before it.
---@param fn fun(dt_ticks: integer)
function tdc.on_tick(fn)
    ticks[#ticks + 1] = fn
end

-- Runs `fn(player, rest)` when a player says `word` (case-insensitive), alone
-- or followed by more words. The message is swallowed unless `fn` answers
-- `false`, which is how a word lets a sentence that only starts with it
-- through to chat.
---@param word string
---@param fn fun(player: string, rest: string): boolean?
function tdc.on_chat(word, fn)
    assert(not words[word], "chat word registered twice: " .. word)
    words[word] = fn
end

-- Runs `fn(event)` when a player presses or releases the qualified action `id`.
function tdc.on_action(id, fn)
    actions[id] = actions[id] or {}
    local list = actions[id]
    list[#list + 1] = fn
end

function tdc.on_join(fn)
    joins[#joins + 1] = fn
end

function tdc.on_leave(fn)
    leaves[#leaves + 1] = fn
end

-- Runs `fn(event)` for events from the dialog this mod showed as `form`
-- (unqualified; the engine reports it qualified).
function tdc.on_dialog(form, fn)
    dialogs[game.mod_id .. ":" .. form] = fn
end

-- Runs `fn(event)` when a dig begins. Answer a string to refuse with it.
function tdc.on_dig_start(fn)
    dig_starts[#dig_starts + 1] = fn
end

-- Runs `fn(event)` when a dig completes. Answer a string to refuse with it.
function tdc.on_dig_complete(fn)
    dig_completes[#dig_completes + 1] = fn
end

-- Runs `fn(event)` when a dig completes and nothing of this mod's refused it:
-- for what happens BECAUSE of a dig (a tool wearing), as against whether it
-- may happen. Answers are ignored.
function tdc.on_dug(fn)
    dug[#dug + 1] = fn
end

-- Runs `fn(event)` before a placement. The first non-nil answer wins.
function tdc.on_place(fn)
    places[#places + 1] = fn
end

-- Runs `fn(event)` when a player USES a block: the place control with nothing
-- to place. Answer a string or `false` to handle it; the first to do so stops
-- the rest.
function tdc.on_use(fn)
    uses[#uses + 1] = fn
end

--- Asks each of `list` in turn and answers the first verdict that decides.
local function first_verdict(list, event)
    for _, fn in ipairs(list) do
        local verdict = fn(event)
        if verdict ~= nil and verdict ~= true then
            return verdict
        end
    end
end

game.register_on_tick(function(dt_ticks)
    start()
    for _, fn in ipairs(ticks) do
        fn(dt_ticks)
    end
end)

game.register_on_chat(function(event)
    start()
    local first, rest = string.match(event.text, "^%s*(%S+)%s*(.*)$")
    if first == nil then return end
    local fn = words[string.lower(first)]
    if fn == nil then return end
    if fn(event.player, rest) == false then return end
    return false
end)

game.register_on_action(function(event)
    start()
    local list = actions[event.id]
    if list == nil then return end
    for _, fn in ipairs(list) do
        fn(event)
    end
end)

game.register_on_player_join(function(event)
    start()
    for _, fn in ipairs(joins) do
        fn(event)
    end
end)

game.register_on_player_leave(function(event)
    for _, fn in ipairs(leaves) do
        fn(event)
    end
end)

game.register_on_dialog_event(function(event)
    local fn = dialogs[event.form]
    if fn then fn(event) end
end)

game.register_on_dig_start(function(event)
    return first_verdict(dig_starts, event)
end)

game.register_on_dig_complete(function(event)
    local verdict = first_verdict(dig_completes, event)
    if verdict ~= nil then return verdict end
    for _, fn in ipairs(dug) do
        fn(event)
    end
end)

game.register_on_place(function(event)
    for _, fn in ipairs(places) do
        local verdict = fn(event)
        if verdict ~= nil then
            return verdict
        end
    end
end)

game.register_on_use(function(event)
    return first_verdict(uses, event)
end)

return {}
