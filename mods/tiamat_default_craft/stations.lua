-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Stations in the world: a block with a container behind it.
--
-- # One pattern for every station
--
-- Every station the registry holds that names a `block` — this mod's
-- workbench, and another mod's alembic alike — is handled here: placing the
-- block makes its container, using it opens the container and a screen of
-- its recipes, and digging it hands its contents to the digger. The chest
-- is the same pattern with no recipes. An alembic is a station record, a
-- block and some recipes, and nothing else.
--
-- # Names and the index
--
-- A container is named by what it is and where: `tiamat_default_craft:
-- <station>:x,y,z` (with `<domain>@` before the position off the
-- overworld). Container names are not namespaced by the engine; the prefix
-- is what keeps another mod's box at the same place a different box. The
-- engine cannot list containers (engine ask 5), so every station placed is
-- also kept in an index in storage, `station:<name>`, which a station that
-- runs on the tick (the kiln, step 5) walks.
--
-- # One player at a time
--
-- The engine lends a container to one player: a second is told somebody is
-- using it, and a station somebody else has open cannot be dug.

local C = tdc.config
local U = tdc.util
local R = tdc.registry
local S = tdc.screens

local ST = {}

local FORM = "station"
local CHEST = game.mod_id .. ":chest"

--- The kinds of block this file looks after, by qualified block id: `{ id,
--- size, station? }`. Filled from the registry at the first use, when every
--- mod has registered its stations.
local kinds = nil

--- More blocks that are a station: an unfired kiln is the kiln's.
local aliases = {}

--- Another block that opens as station `id`.
function ST.alias(block, id)
    aliases[block] = id
end

local function all_kinds()
    if kinds then return kinds end
    kinds = { [CHEST] = { id = "chest", size = C.chest_slots } }
    for _, id in ipairs(R.station_ids()) do
        local station = R.station(id)
        for _, block in ipairs({ station.block, station.lit_block }) do
            if block then kinds[block] = { id = id, size = station.size, station = station } end
        end
    end
    for _, block in ipairs(U.sorted_keys(aliases)) do
        local station = R.station(aliases[block])
        if station then kinds[block] = { id = station.id, size = station.size, station = station } end
    end
    return kinds
end

--- The kind of block a material is, or nil.
function ST.kind(material)
    local name = material and game.block_of(material)
    return name and all_kinds()[name]
end

local kind_of = ST.kind

--- A station's container name at a block.
function ST.name(kind_id, pos)
    local where = U.key(pos.x, pos.y, pos.z)
    if pos.domain and pos.domain ~= "overworld" then where = pos.domain .. "@" .. where end
    return game.mod_id .. ":" .. kind_id .. ":" .. where
end

-- The index: every station container placed, with where it is, kept in
-- storage (`station:<name>` = "kind=...;x=...;y=...;z=...;domain=...") and
-- in memory, read from storage once.
local index = nil   -- name -> { kind, x, y, z, domain }

local function load_index()
    if index then return index end
    index = {}
    for _, key in ipairs(game.storage.keys()) do
        local name = string.match(key, "^station:(.+)$")
        if name then
            local record = U.decode(game.storage.get(key))
            if type(record.kind) == "string" and math.type(record.x) == "integer" then
                index[name] = record
            end
        end
    end
    return index
end

--- Makes a station's container if it has none, and keeps it in the index.
local function ensure(kind, pos)
    local name = ST.name(kind.id, pos)
    game.make_container(name, kind.size)
    local idx = load_index()
    if not idx[name] then
        local record = { kind = kind.id, x = pos.x, y = pos.y, z = pos.z, domain = pos.domain or "overworld" }
        idx[name] = record
        game.storage.set("station:" .. name, U.encode(record))
    end
    return name
end

--- The station a container belongs to, by id, or nil.
function ST.kind_id(name)
    local record = load_index()[name]
    return record and record.kind
end

local function unindex(name)
    load_index()[name] = nil
    game.storage.set("station:" .. name, nil)
end

--- Every indexed container of a station, sorted, with where it is:
--- `{ { name, pos } }`.
function ST.indexed(kind_id)
    local out = {}
    local idx = load_index()
    for _, name in ipairs(U.sorted_keys(idx)) do
        local r = idx[name]
        if r.kind == kind_id then
            out[#out + 1] = { name = name, pos = { x = r.x, y = r.y, z = r.z,
                domain = r.domain ~= "overworld" and r.domain or nil } }
        end
    end
    return out
end

local function pos_of_use(e)
    return { x = e.x // 3, y = e.y // 3, z = e.z // 3, domain = e.domain ~= "overworld" and e.domain or nil }
end

-- Placing ----------------------------------------------------------------------

local checks = {}   -- station id -> fn(pos) -> refusal or nil

--- A rule a station's block must pass to be placed: `fn(pos)` answers a
--- sentence to refuse it, or nil. A sluice wants water.
function ST.check(id, fn)
    checks[id] = fn
end

tdc.on_place(function(e)
    local kind = kind_of(e.material)
    if not kind then return end
    local pos = { x = e.x, y = e.y, z = e.z }
    local check = checks[kind.id]
    local refusal = check and check(pos)
    if refusal then return refusal end
    if e.occupancy == game.OCCUPANCY_FULL then
        ensure(kind, pos)
    end
end)

-- Using ------------------------------------------------------------------------

local open = {}   -- uuid -> { container, station, ids, page, note }

--- The recipe ids a station shows.
local function recipe_ids(station_id)
    local ids = {}
    for i, recipe in ipairs(R.list(station_id)) do ids[i] = recipe.id end
    return ids
end

local function draw(player, first)
    local o = open[player]
    if not o then return end
    local tree
    if o.station then
        local status = nil
        if o.station.heat and tdc.furnace then
            status = tdc.furnace.status(o.container)
        elseif o.station.id == "campfire" and tdc.cooking then
            status = tdc.cooking.status(o.container, o.pos)
        elseif o.station.forge and tdc.anvil then
            status = tdc.anvil.status(o.container)
        end
        tree, o.page = S.station(player, o.station, o.container, o.ids, o.page, o.note, status)
    else
        tree = S.chest(o.container, o.size)
    end
    local spec = { player = player, form = FORM, tree = tree }
    if first then game.show_dialog(spec) else game.update_dialog(spec) end
end

--- Redraws the screen of whoever has a container open.
function ST.redraw(container)
    for _, player in ipairs(U.sorted_keys(open)) do
        if open[player].container == container then draw(player, false) end
    end
end

tdc.on_use(function(e)
    local kind = kind_of(e.material)
    if not kind then return nil end
    local pos = pos_of_use(e)
    local name = ensure(kind, pos)
    -- A station worked by blows is struck with a hammer, not opened.
    if kind.station and kind.station.forge and tdc.anvil then
        local tool = e.held and tdc.tools.record(e.held.material)
        if tool and tool.type == "hammer" then
            return tdc.anvil.strike(e, kind.station, name)
        end
    end
    -- A station that burns is lit with a striker, not opened.
    if kind.station and kind.station.heat and tdc.furnace then
        local lit = tdc.furnace.light(e, kind.station, name, pos)
        if lit ~= nil then return lit end
    end
    if not game.open_container(name, e.player) then
        return "Somebody is using that."
    end
    open[e.player] = {
        container = name, station = kind.station, size = kind.size, pos = pos,
        ids = kind.station and recipe_ids(kind.id) or {}, page = 1,
    }
    draw(e.player, true)
    return ""
end)

tdc.on_dialog(FORM, function(e)
    local o = open[e.player]
    if not o then return end
    if e.kind == "closed" then
        open[e.player] = nil
        return
    end
    if e.kind == "pressed" and e.name then
        local index = tonumber(string.match(e.name, "^r(%d+)$"))
        if index and o.ids[index] and o.station.forge then
            tdc.anvil.choose(o.container, o.ids[index])
            o.note = nil
        elseif index and o.ids[index] and o.station.auto then
            o.note = "It works on its own: put in what it takes."
        elseif index and o.ids[index] then
            local ok, why = R.perform(e.player, o.ids[index], o.container)
            o.note = ok and ("Made " .. S.recipe_text(R.recipe(o.ids[index])) .. ".") or ("Cannot: " .. why .. ".")
        elseif e.name == "prev" then
            o.page = o.page - 1
        elseif e.name == "next" then
            o.page = o.page + 1
        end
    end
    -- A click moved something: which recipes can be made has changed.
    draw(e.player, false)
end)

tdc.on_leave(function(e)
    open[e.player] = nil
end)

-- Digging ------------------------------------------------------------------------

tdc.on_dig_complete(function(e)
    local kind = kind_of(e.material)
    if not kind then return end
    local name = ST.name(kind.id, { x = e.x // 3, y = e.y // 3, z = e.z // 3 })
    local holder = game.container_holder(name)
    if holder ~= nil and holder ~= e.player then
        return "Somebody is using that."
    end
    if holder ~= nil then
        game.close_dialog{ player = holder, form = FORM }
        game.close_container(name, holder)
        open[holder] = nil
    end
end)

tdc.on_dug(function(e)
    local kind = kind_of(e.material)
    if not kind then return end
    local name = ST.name(kind.id, { x = e.x // 3, y = e.y // 3, z = e.z // 3 })
    -- Nothing is destroyed (charter rule 5): what was inside goes to the
    -- digger. Units, not counts: a stack is blocks and loose nodes.
    for _, stack in ipairs(game.break_container(name)) do
        game.give(e.player, { material = stack.material, units = stack.units, shape = stack.shape,
            detail = stack.detail })
    end
    unindex(name)
    if tdc.furnace then tdc.furnace.forget(name) end
    if tdc.cooking then tdc.cooking.forget(name) end
    if tdc.sluice then tdc.sluice.forget(name) end
    if tdc.anvil then tdc.anvil.forget(name) end
end)

-- By hand: the Craft tab, or a dialog of its own ------------------------------------------

local HAND_TAB = game.mod_id .. ":hand"
local HAND_FORM = "hand"
local hand = {}   -- uuid -> { page, note }

local function hand_ids()
    return recipe_ids("hand")
end

local function press_hand(player, name)
    local h = hand[player] or { page = 1 }
    hand[player] = h
    local ids = hand_ids()
    local index = tonumber(string.match(name or "", "^r(%d+)$"))
    if index and ids[index] then
        local ok, why = R.perform(player, ids[index], nil)
        h.note = ok and ("Made " .. S.recipe_text(R.recipe(ids[index])) .. ".") or ("Cannot: " .. why .. ".")
    elseif name == "prev" then
        h.page = h.page - 1
    elseif name == "next" then
        h.page = h.page + 1
    end
end

local function hand_tree(player)
    local h = hand[player] or { page = 1 }
    hand[player] = h
    local tree
    tree, h.page = S.hand(player, hand_ids(), h.page, h.note)
    return tree
end

local tab = false
if S.ui then
    tab = S.ui.add_tab{
        id = HAND_TAB,
        label = "Craft",
        order = 25,
        build = function(player) return hand_tree(player) end,
        on_event = function(player, event)
            if event.kind == "pressed" then
                press_hand(player, event.name)
                return true
            end
        end,
    } == true
end

game.register_action{ id = "craft", default_key = "KeyV", description = "Craft by hand" }

tdc.on_action(game.mod_id .. ":craft", function(e)
    if not e.pressed then return end
    if tab and S.ui.open(e.player, HAND_TAB) then return end
    game.show_dialog{ player = e.player, form = HAND_FORM, tree = hand_tree(e.player) }
end)

tdc.on_dialog(HAND_FORM, function(e)
    if e.kind == "closed" then
        hand[e.player] = nil
        return
    end
    if e.kind == "pressed" then
        press_hand(e.player, e.name)
    end
    game.update_dialog{ player = e.player, form = HAND_FORM, tree = hand_tree(e.player) }
end)

return ST
