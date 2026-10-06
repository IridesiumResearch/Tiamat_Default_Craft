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
-- is what keeps another mod's box at the same place a different box. A
-- station that runs on the tick (a kiln, a sluice) is found by listing the
-- containers with its prefix, so one a plan stamped runs as one placed by
-- hand.
--
-- # One player at a time
--
-- The engine lends a container to one player: a second is told somebody is
-- using it, and a station somebody else has open cannot be dug.

local C = tdc.config
local U = tdc.util
local R = tdc.registry
local S = tdc.screens
local G = tdc.grid

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

-- Where the stations are is the engine's to say: every container is
-- listed by `game.containers(prefix)` (engine ask 5), and a station's name
-- says where it stands. The one thing a name does not hold is who placed
-- it, which the progression's effects answer to (a sluice's gold): that is
-- kept in storage, `placer:<name>`.

--- Makes a station's container if it has none; `by` is who placed it.
local ensure

--- The same, by station id: for a mod file that has to put something into a
--- station nobody has opened yet (a fire's ash).
function ST.ensure(id, pos)
    local station = R.station(id)
    if not station then return nil end
    return ensure({ id = id, size = station.size, station = station }, pos)
end

function ensure(kind, pos, by)
    local name = ST.name(kind.id, pos)
    game.make_container(name, kind.size)
    if by and not game.storage.get("placer:" .. name) then
        game.storage.set("placer:" .. name, by)
    end
    return name
end

--- Where a container stands, from its name after the kind's prefix:
--- `x,y,z`, or `domain@x,y,z`.
local function pos_of_name(rest)
    local domain, where = string.match(rest, "^(.*)@([^@]+)$")
    where = where or rest
    local x, y, z = string.match(where, "^(%-?%d+),(%-?%d+),(%-?%d+)$")
    if not x then return nil end
    return { x = math.tointeger(tonumber(x)), y = math.tointeger(tonumber(y)), z = math.tointeger(tonumber(z)),
        domain = domain }
end

--- The station a container belongs to, by id, or nil: the longest station
--- id whose prefix the name has.
function ST.kind_id(name)
    local best = nil
    for _, id in ipairs(R.station_ids()) do
        local prefix = game.mod_id .. ":" .. id .. ":"
        if string.sub(name, 1, #prefix) == prefix and pos_of_name(string.sub(name, #prefix + 1))
            and (not best or #id > #best) then
            best = id
        end
    end
    return best
end

local function unindex(name)
    game.storage.set("placer:" .. name, nil)
end

-- The index this mod kept before the engine could list containers.
local cleaned = false
local function clean_old_index()
    cleaned = true
    for _, key in ipairs(game.storage.keys("station:")) do
        game.storage.set(key, nil)
    end
end

--- Every container of a station, sorted, with where it is and who placed
--- it: `{ { name, pos, by } }`.
function ST.indexed(kind_id)
    if not cleaned then clean_old_index() end
    local prefix = game.mod_id .. ":" .. kind_id .. ":"
    local out = {}
    for _, name in ipairs(game.containers(prefix)) do
        local pos = pos_of_name(string.sub(name, #prefix + 1))
        if pos and ST.kind_id(name) == kind_id then
            local by = game.storage.get("placer:" .. name)
            out[#out + 1] = { name = name, pos = pos, by = type(by) == "string" and by or nil }
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
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

-- A placement and a dig say which domain they are in, and a station's box
-- is named with it (Science's C-S8): a frame at a star must not share a box
-- with one at the same place in the overworld.
local function domain_of(e)
    if e.domain == nil or e.domain == "overworld" then return nil end
    return e.domain
end

tdc.on_place(function(e)
    local kind = kind_of(e.material)
    if not kind then return end
    local pos = { x = e.x, y = e.y, z = e.z, domain = domain_of(e) }
    local check = checks[kind.id]
    local refusal = check and check(pos)
    if refusal then return refusal end
    if e.occupancy == game.OCCUPANCY_FULL then
        ensure(kind, pos, e.player)
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
        elseif o.station.runs and tdc.runs then
            status = tdc.runs.status(o.container)
        elseif o.station.forge and tdc.anvil then
            status = tdc.anvil.status(o.container)
        end
        if o.grid then
            tree = S.grid_station(player, o.station, o.container, o.ids, o.note)
        else
            tree, o.page = S.station(player, o.station, o.container, o.ids, o.page, o.note, status)
        end
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
    local o = {
        container = name, station = kind.station, size = kind.size, pos = pos,
        ids = kind.station and recipe_ids(kind.id) or {}, page = 1,
    }
    if kind.station and kind.station.grid then
        -- A grid at a station holds that station's recipes and the hand's.
        local ids = recipe_ids(kind.id)
        for _, id in ipairs(recipe_ids("hand")) do ids[#ids + 1] = id end
        G.recover(name, kind.station.slots.output[1])
        o.grid = G.new{
            container = name, n = kind.station.grid, inputs = kind.station.slots.input,
            output = kind.station.slots.output[1], ids = ids, player = e.player,
        }
        G.refresh(o.grid)
    end
    open[e.player] = o
    draw(e.player, true)
    return ""
end)

--- A recipe from the list beside a grid: made at once from the pack. The
--- list shows only what can be made, so a refusal here is a pack that
--- changed under the screen, and does nothing.
local function quick(player, id)
    if not R.check(player, id, { pack = true }) then return nil end
    local ok = R.perform(player, id, { pack = true })
    if not ok then return nil end
    tdc.sounds.at_player("craft", player)
    return "Made " .. S.recipe_text(R.recipe(id)) .. "."
end

tdc.on_dialog(FORM, function(e)
    local o = open[e.player]
    if not o then return end
    if e.kind == "closed" then
        if o.grid then G.closed(o.grid) end
        open[e.player] = nil
        return
    end
    if e.kind == "clicked" and o.grid then
        G.clicked(o.grid, e)
    end
    if e.kind == "pressed" and e.name then
        local index = tonumber(string.match(e.name, "^r(%d+)$"))
        if index and o.ids[index] and o.grid then
            o.note = quick(e.player, o.ids[index]) or o.note
            G.refresh(o.grid)
        elseif index and o.ids[index] and o.station.forge then
            tdc.anvil.choose(o.container, o.ids[index])
            o.note = nil
        elseif index and o.ids[index] and o.station.auto then
            o.note = "It works on its own: put in what it takes."
        elseif index and o.ids[index] then
            local ok, why = R.perform(e.player, o.ids[index], o.container)
            if ok then tdc.sounds.at_player("craft", e.player) end
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
    local name = ST.name(kind.id, { x = e.x // 3, y = e.y // 3, z = e.z // 3, domain = domain_of(e) })
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
    local name = ST.name(kind.id, { x = e.x // 3, y = e.y // 3, z = e.z // 3, domain = domain_of(e) })
    -- Nothing is destroyed (charter rule 5): what was inside goes to the
    -- digger. Units, not counts: a stack is blocks and loose nodes. A
    -- grid's preview was never made, and is not handed out.
    local station = R.station(kind.id)
    if station and station.grid then G.recover(name, station.slots.output[1]) end
    for _, stack in ipairs(game.break_container(name)) do
        U.give(e.player, { material = stack.material, units = stack.units, shape = stack.shape,
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
local hand = {}   -- uuid -> { note }

local function hand_ids()
    return recipe_ids("hand")
end

local function press_hand(player, name)
    local h = hand[player] or {}
    hand[player] = h
    local ids = hand_ids()
    local index = tonumber(string.match(name or "", "^r(%d+)$"))
    if index and ids[index] then
        h.note = quick(player, ids[index]) or h.note
    end
end

--- A slot clicked on the hand's screen: its grid, or the pack beside it.
local function click_hand(player, event)
    local g = G.hand_of(player)
    if g then G.clicked(g, event) end
end

local function hand_tree(player)
    local h = hand[player] or {}
    hand[player] = h
    local g = G.hand(player, hand_ids())
    G.refresh(g)
    return S.hand(player, g.ids, g.container, h.note)
end

local tab = false
if S.ui then
    tab = S.ui.add_tab{
        id = HAND_TAB,
        label = "Craft",
        -- Beside Inventory, where the interface's own Crafting tab was (its ask C2).
        order = 20,
        build = function(player) return hand_tree(player) end,
        on_event = function(player, event)
            if event.kind == "pressed" then
                press_hand(player, event.name)
                return true
            elseif event.kind == "clicked" then
                click_hand(player, event)
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
        local g = G.hand_of(e.player)
        if g then G.closed(g) end
        return
    end
    if e.kind == "pressed" then
        press_hand(e.player, e.name)
    elseif e.kind == "clicked" then
        click_hand(e.player, e)
    end
    game.update_dialog{ player = e.player, form = HAND_FORM, tree = hand_tree(e.player) }
end)

return ST
