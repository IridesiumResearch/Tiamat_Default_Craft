-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Tools: what is in a player's hand, what it may break, and how it wears.
--
-- # What the engine gives, and what this file adds
--
-- The engine knows one number about a tool, its speed, and has a tool
-- registry apart from the item registry. It has no tier, no type, no
-- durability. So each tool here is an ITEM, which is what a player carries,
-- and — when it digs — an engine TOOL of the same id, which is what decides
-- how fast. Everything else is this file's.
--
-- # The hand follows the hotbar
--
-- The engine's tool is a per-player setting the client can change on its
-- own (the tool key cycles every registered tool, with no idea what anybody
-- carries). The truth here is what the player HOLDS: once a tick, the tool
-- the held stack stands for — or the hand — is put in the player's hand if it
-- is not there already. Only on a change: `game.set_tool` cancels the dig in
-- progress every time it is called, so calling it every tick would make
-- digging impossible.
--
-- # The gate
--
-- A dig BEGINS only if the tool is of a type the block's class takes and of
-- its tier (config.lua). `register_on_dig_start` is asked as the player
-- starts, so the refusal — one sentence, the tutorial — comes at once rather
-- than after they have waited the dig out.
--
-- # Wear
--
-- Each tool is minted with a serial in its `detail` ("t=12"), so no two
-- tools stack and a take can find exactly one, and its wear rides in the
-- same detail ("t=12;w=40"): it goes where the tool goes, into a chest and
-- out, onto the ground and back. Wearing a tool rewrites it IN ITS SLOT —
-- taken from that slot and given back into it (engine ask 4) — so the pick
-- a player is digging with never leaves their hand. The slot is found by
-- the serial, which no other stack has (`game.slot`, engine ask 9). A world
-- from before this kept wear in storage under the serial; that is read once
-- and moved onto the tool.

local C = tdc.config
local U = tdc.util
local R = tdc.registry

local T = {}

--- The engine tool a player holds when their hand holds nothing that digs.
T.HAND = game.mod_id .. ":hand"

game.register_tool{
    id = "hand",
    name = "Hand",
    brush = "block",
    speed_multiplier = C.hand_speed,
    default = true,
}

-- The records ------------------------------------------------------------------

local tools = {}         -- qualified id -> { id, name, type, tier, uses, digs }
local by_material = {}   -- numeric material -> record, filled as ids resolve
local classes = {}       -- class id -> { types = set, any, tier, hint, refusals }
local class_names = {}   -- qualified block id -> class id
local class_of = {}      -- numeric material -> class record, or false
local unusable = {}      -- engine tool ids that `set_tool` refused: never asked again

local function lower(name)
    return string.lower(string.sub(name, 1, 1)) .. string.sub(name, 2)
end

--- Adds a tool record. `digs` says the id is also an engine tool.
local function add_tool(id, spec)
    tools[id] = {
        id = id,
        name = spec.name or U.title(id),
        type = spec.type,
        tier = spec.tier,
        uses = spec.uses,
        digs = spec.digs == true,
    }
end

--- A tool's record by numeric material, or nil.
function T.record(material)
    local known = by_material[material]
    if known ~= nil then return known or nil end
    local id = game.block_of(material)
    local record = id and tools[id] or false
    if not tdc.loading() then by_material[material] = record end
    return record or nil
end

--- The record of the tool a player holds, and the held stack; nil for a bare
--- hand or anything that is not a tool.
function T.held(uuid)
    local held = game.held(uuid)
    if held == nil then return nil, nil end
    return T.record(held.material), held
end

-- Moulds are tools of the kiln: one per head, and the pot's.
for _, head in ipairs(U.sorted_keys(C.heads)) do
    C.tools["mould_" .. head] = { name = U.title(head) .. " mould", type = "mould", tier = 1, uses = C.mould_uses }
end
C.tools.mould_pot = { name = "Pot mould", type = "mould", tier = 1, uses = C.mould_uses }
C.tools.mould_tuyere = { name = "Tuyere mould", type = "mould", tier = 1, uses = C.mould_uses }
C.tools.mould_gear = { name = "Gear mould", type = "mould", tier = 1, uses = C.mould_uses }

--- A digging tool's speed on each block it is slower on than its own
--- speed (engine ask 2): the world's blocks by class, at the share
--- `C.speed_shares` gives its type. Only blocks registered by now — the
--- world loads first — so no name is dropped at load.
local function speeds_of(spec)
    local shares = C.speed_shares[spec.type]
    if not shares then return nil end
    local out, any = {}, false
    for _, class in ipairs(U.sorted_keys(shares)) do
        for _, short in ipairs(class == "loose" and C.soft_ground or {}) do
            local id = U.world(short)
            if U.material(id) then
                out[id] = spec.speed * shares[class]
                any = true
            end
        end
    end
    return any and out or nil
end

-- This mod's own tools: an item each, and an engine tool for the ones that dig.
for _, short in ipairs(U.sorted_keys(C.tools)) do
    local spec = C.tools[short]
    game.register_item{
        id = short,
        name = spec.name,
        texture = "textures/" .. short .. ".png",
        description = spec.speed and string.format("Tier %d. Digs %s. Wears after %d uses.", spec.tier,
            spec.type == "spade" and "earth" or spec.type == "maul" and "cracked rock"
            or spec.type == "axe" and "wood" or spec.type == "pick" and "rock" or "one cell at a time",
            spec.uses) or nil,
    }
    if spec.speed then
        game.register_tool{
            id = short,
            name = spec.name,
            brush = spec.brush or "block",
            speed_multiplier = spec.speed,
            speeds = speeds_of(spec),
        }
    end
    add_tool(game.mod_id .. ":" .. short, {
        name = spec.name, type = spec.type, tier = spec.tier, uses = spec.uses, digs = spec.speed ~= nil,
    })
end

-- Classes ------------------------------------------------------------------------

local function add_class(id, spec)
    local record = { id = id, types = {}, any = false, tier = spec.tier, hint = spec.hint,
        refusals = spec.refusals or C.refusals[id] or {} }
    for _, t in ipairs(spec.types) do
        if t == "any" then record.any = true end
        record.types[t] = true
    end
    classes[id] = record
end

for _, id in ipairs(U.sorted_keys(C.classes)) do
    add_class(id, C.classes[id])
end
for _, class in ipairs(U.sorted_keys(C.classify)) do
    for _, short in ipairs(C.classify[class]) do
        class_names[U.world(short)] = class
    end
end
-- This mod's own blocks: planks are wood; the stations come away in anything.
class_names[game.mod_id .. ":plank"] = "wood"
-- Fired brick is masonry: it wants a pick, as the stone it stands for does.
class_names[game.mod_id .. ":brick"] = "rock"
for _, short in ipairs({ "workbench", "chest", "unlit_campfire", "campfire_lit", "unfired_kiln", "kiln", "kiln_lit",
        "sluice", "bloomery", "bloomery_lit", "stone_anvil", "torch", "spent_torch", "mudbrick", "glass",
        "iron_lantern" }) do
    class_names[game.mod_id .. ":" .. short] = "loose"
end

--- A class from a block's own tags (engine ask 6), or nil.
local function class_from_tags(material)
    local tags = game.tags(material)
    if type(tags) ~= "table" then return nil end
    for _, tag in ipairs(tags) do
        local class = C.tag_classes[tag] or (classes[tag] and tag)
        if class and classes[class] then return class end
    end
    return nil
end

--- The class of a numeric material, or nil: this mod's exceptions first,
--- then what the block's tags say.
function T.class(material)
    local known = class_of[material]
    if known ~= nil then return known or nil end
    local id = game.block_of(material)
    local name = id and (class_names[id] or class_from_tags(material))
    local record = name and classes[name] or false
    if not tdc.loading() then class_of[material] = record end
    return record or nil
end

--- Whether `tool` (a record, or nil for the hand) may break a block of
--- `class`. Answers nil when it may, and the sentence when it may not.
function T.refusal(class, tool)
    local digs = tool ~= nil and tool.digs
    local kind = digs and tool.type or "hand"
    local tier = digs and tool.tier or 0
    if not (class.any or class.types[kind]) then
        if kind == "hand" then
            return class.refusals.hand or class.refusals.type or C.refusal
        end
        return class.refusals.type or C.refusal
    end
    if tier < class.tier then
        return class.refusals.tier or class.refusals.type or C.refusal
    end
    return nil
end

local creative = C.mode == "Creative"
local hinted = {}   -- "uuid:class" -> true, for this session

tdc.on_dig_start(function(e)
    if creative then return end
    local class = T.class(e.material)
    if not class then return end
    local tool = T.held(e.player)
    local refusal = T.refusal(class, tool)
    if refusal then return refusal end
    if class.hint and not (tool and tool.digs) then
        local key = e.player .. ":" .. class.id
        if not hinted[key] then
            hinted[key] = true
            game.chat_to(e.player, class.hint)
        end
    end
end)

-- Asked again as the block comes off. Nothing should have changed — a new
-- held stack changes the tool, and a new tool is a new dig — but a refusal
-- here costs nothing and a dig let through by a gap costs the design.
tdc.on_dig_complete(function(e)
    if creative then return end
    local class = T.class(e.material)
    if not class then return end
    return T.refusal(class, (T.held(e.player)))
end)

-- Wear ---------------------------------------------------------------------------

--- A new tool's detail: its serial, from a counter kept with the world.
function T.mint()
    local serial = U.stored_int("serial") + 1
    game.storage.set("serial", serial)
    return "t=" .. serial
end

R.minted = function(name) return tools[name] ~= nil end
R.mint = function(name) return T.mint() end

--- A tool's detail read: `{ t = serial, w = wear, c = carry }`, each an
--- integer or nil.
local function read(detail)
    local r = U.decode(detail)
    return {
        t = math.type(r.t) == "integer" and r.t or nil,
        w = math.type(r.w) == "integer" and r.w or nil,
        c = math.type(r.c) == "integer" and r.c or nil,
    }
end

--- And written: serial first, so "t=12" is how a tool is known.
local function write(r)
    local parts = { "t=" .. r.t }
    if (r.w or 0) > 0 then parts[#parts + 1] = "w=" .. r.w end
    if (r.c or 0) > 0 then parts[#parts + 1] = "c=" .. r.c end
    return table.concat(parts, ";")
end

--- Wear a world from before kept in storage: under the serial, or for a
--- tool with no serial under the player and the kind. Read and cleared.
local function legacy_wear(tool, r, uuid, clear)
    local key = r.t and ("wear:" .. r.t) or ("wear:" .. tostring(uuid) .. ":" .. tool.id)
    local worn = U.stored_int(key)
    local carry = U.stored_int(key .. ":carry")
    if clear then
        game.storage.set(key, nil)
        game.storage.set(key .. ":carry", nil)
    end
    return worn, carry
end

--- How worn a tool is, in uses.
function T.worn(tool, detail, uuid)
    local r = read(detail)
    if r.w or r.c then return r.w or 0 end
    return (legacy_wear(tool, r, uuid, false))
end

--- The one-based slot of `player:main` holding exactly this stack, or nil.
local function slot_of(player, material, detail)
    for n = 1, C.slot_scan do
        local stack = game.slot(player, "player:main", n)
        if stack and stack.material == material and stack.detail == detail then return n end
    end
    return nil
end

--- Rewrites a tool's detail where it lies: in its slot of a container, or
--- of the player's pack. Whatever cannot go back where it was goes anywhere.
local function rewrite(uuid, found, new)
    local old = { material = found.material, units = U.UNITS, detail = found.detail }
    local fresh = { material = found.material, units = U.UNITS, detail = new }
    if found.container then
        old.slot, fresh.slot = found.slot, found.slot
        if game.container_take(found.container, old) < U.UNITS then return false end
        if game.container_give(found.container, fresh) < U.UNITS then
            fresh.slot = nil
            if game.container_give(found.container, fresh) < U.UNITS and uuid then U.give(uuid, fresh) end
        end
        return true
    end
    local player = found.player or uuid
    local slot = slot_of(player, found.material, found.detail)
    old.slot, fresh.slot = slot, slot
    if game.take(player, old) < U.UNITS then return false end
    local gave = game.give(player, fresh)
    if not gave then
        fresh.slot = nil
        U.give(player, fresh)
    end
    return true
end

--- Takes a worn-out tool away from where it lies.
local function remove(uuid, found)
    local spec = { material = found.material, units = U.UNITS, detail = found.detail }
    if found.container then
        spec.slot = found.slot
        game.container_take(found.container, spec)
    else
        local player = found.player or uuid
        spec.slot = slot_of(player, found.material, found.detail)
        game.take(player, spec)
    end
end

local TIERS = { [0] = "wood", [1] = "bronze", [2] = "iron" }

--- A tool's uses for a player, with the progression's effects: a mould's
--- pours, and each tier's lasting longer.
function T.uses(tool, uuid)
    local uses = tool.uses
    if uses == 0 then return 0 end
    if tool.type == "mould" then uses = uses + R.effect(uuid, "craft.mould_pours") end
    local tier = TIERS[tool.tier]
    if tier then uses = uses * (100 + R.effect(uuid, "craft.uses_percent." .. tier)) // 100 end
    return math.max(1, uses)
end

--- Charges `amount` uses to one tool, where it was found: `{ material,
--- detail, container?, slot?, player? }`. The wear is written onto the tool
--- in its slot; at its last use it is taken away and the player told.
function T.charge(uuid, found, amount)
    if creative then return false end
    local tool = T.record(found.material)
    if not tool or tool.uses == 0 or amount <= 0 then return false end
    local r = read(found.detail)
    if not (r.w or r.c) then
        -- First wear since this mod kept it in storage, or ever: moved over.
        r.w, r.c = legacy_wear(tool, r, uuid, true)
    end
    -- A chisel may wear slower than a use a use: the fraction is carried,
    -- in hundredths, on the tool.
    if tool.type == "chisel" then
        local pct = R.effect(uuid, "craft.chisel_wear_percent")
        if pct ~= 0 then
            local carry = (r.c or 0) + amount * math.max(0, 100 + pct)
            amount = carry // 100
            r.c = carry % 100
        end
    end
    r.t = r.t or math.tointeger(string.match(T.mint(), "%d+"))
    r.w = (r.w or 0) + amount
    if r.w < T.uses(tool, uuid) then
        if write(r) ~= found.detail then rewrite(uuid, found, write(r)) end
        return true
    end
    remove(uuid, found)
    if uuid then
        game.chat_to(uuid, string.format(C.worn_out, lower(tool.name)))
        tdc.sounds.at_player("tool_break", uuid)
    end
    R.tool_broken(uuid, tool.id)
    return true
end

R.wear = T.charge

--- Charges the tool a player holds.
function T.wear_held(uuid, amount)
    local tool, held = T.held(uuid)
    if not tool then return false end
    return T.charge(uuid, { material = held.material, detail = held.detail, player = uuid }, amount)
end

-- A dig that happened wears the tool that did it.
tdc.on_dug(function(e)
    local tool = T.held(e.player)
    if tool and tool.digs then
        T.wear_held(e.player, 1)
    end
end)

--- Gives a player `n` of a tool, each with its serial.
function T.give(uuid, id, n)
    for _ = 1, n or 1 do
        U.give(uuid, { material = id, count = 1, detail = T.mint() })
    end
end

-- The hand follows the hotbar ------------------------------------------------------

local online = {}     -- sorted UUIDs
local expected = {}   -- uuid -> the engine tool this mod last put in their hand

tdc.on_join(function(e)
    for _, uuid in ipairs(online) do
        if uuid == e.player then return end
    end
    online[#online + 1] = e.player
    table.sort(online)
    expected[e.player] = nil     -- the engine does not keep a choice across a join
end)

tdc.on_leave(function(e)
    for i, uuid in ipairs(online) do
        if uuid == e.player then table.remove(online, i) break end
    end
    expected[e.player] = nil
end)

--- The engine tool a player should be holding.
local function wanted(uuid)
    local tool = T.held(uuid)
    if tool and tool.digs and not unusable[tool.id] then return tool.id end
    return T.HAND
end

-- The HUD: what is left of the tool in hand, and whether it can break what
-- it points at. Sent only when it changes.
local last_hud = {}   -- uuid -> the values last sent, as one string
local hud_clock = 0

local function hud_values(uuid)
    local tool, held = T.held(uuid)
    local wear = -1
    if tool and tool.uses > 0 and not creative then
        local uses = T.uses(tool, uuid)
        local left = uses - T.worn(tool, held.detail, uuid)
        wear = math.max(0, (left * 1000) // uses)
    end
    local warn = false
    if not creative then
        local at = game.looking_at(uuid)
        local class = at and at.material and T.class(at.material)
        warn = class ~= nil and T.refusal(class, tool) ~= nil
    end
    return wear, warn
end

tdc.on_tick(function(dt)
    hud_clock = hud_clock + dt
    if hud_clock < C.hud_ticks then return end
    hud_clock = 0
    for _, uuid in ipairs(online) do
        local wear, warn = hud_values(uuid)
        local key = wear .. (warn and "!" or "")
        if last_hud[uuid] ~= key then
            last_hud[uuid] = key
            game.set_hud(uuid, { wear = wear, warn = warn })
        end
    end
end)

tdc.on_leave(function(e)
    last_hud[e.player] = nil
end)

tdc.on_tick(function()
    for _, uuid in ipairs(online) do
        local want = wanted(uuid)
        if expected[uuid] ~= want or game.get_tool(uuid) ~= want then
            if not game.set_tool(uuid, want) and want ~= T.HAND then
                -- Another mod's tool that is not an engine tool after all:
                -- hold the hand for it, and never ask again.
                unusable[want] = true
                want = T.HAND
                game.set_tool(uuid, want)
            end
            expected[uuid] = want
        end
    end
end)

-- For other mods ----------------------------------------------------------------------

--- Another mod's tool into the tables: `{ id, type, tier, uses, digs? }`,
--- `id` an item the caller registered, and `digs = true` when the caller also
--- registered an engine tool under the same id.
function T.register(spec)
    if not tdc.loading() then return nil, "tools are registered while mods load" end
    if type(spec) ~= "table" or not U.qualified(spec.id) then return nil, "a tool's id is qualified" end
    if tools[spec.id] then return nil, "tool " .. spec.id .. " is already registered" end
    if type(spec.type) ~= "string" or not string.match(spec.type, "^[%a_]+$") then
        return nil, "a tool has a type, like pick"
    end
    local tier, uses = U.whole(spec.tier, 0, 9), U.whole(spec.uses, 0, 1000000)
    if not (tier and uses) then return nil, "tier is 0..9 and uses a whole number" end
    add_tool(spec.id, { name = type(spec.name) == "string" and string.sub(spec.name, 1, 64) or nil,
        type = spec.type, tier = tier, uses = uses, digs = spec.digs })
    return true
end

--- A block into a class.
function T.classify(block, class)
    if not tdc.loading() then return nil, "blocks are classified while mods load" end
    if not U.qualified(block) then return nil, "a block is a qualified id" end
    if not classes[class] then return nil, "no class " .. tostring(class) end
    class_names[block] = class
    return true
end

--- A new class: `{ id, types, tier, refusals? }`.
function T.register_class(spec)
    if not tdc.loading() then return nil, "classes are registered while mods load" end
    if type(spec) ~= "table" or type(spec.id) ~= "string" or not string.match(spec.id, "^[%a_][%w_:]*$") then
        return nil, "a class has an id"
    end
    if classes[spec.id] then return nil, "class " .. spec.id .. " is already registered" end
    if type(spec.types) ~= "table" or #spec.types == 0 then return nil, "a class takes a list of tool types" end
    for _, t in ipairs(spec.types) do
        if type(t) ~= "string" then return nil, "a tool type is a word" end
    end
    local tier = U.whole(spec.tier or 0, 0, 9)
    if not tier then return nil, "tier is 0..9" end
    local refusals = {}
    if type(spec.refusals) == "table" then
        for _, k in ipairs({ "hand", "type", "tier" }) do
            if type(spec.refusals[k]) == "string" then refusals[k] = string.sub(spec.refusals[k], 1, 200) end
        end
    end
    add_class(spec.id, { types = spec.types, tier = tier, refusals = refusals })
    return true
end

--- The tool a player holds, as plain data, or nil.
function T.of(uuid)
    local tool, held = T.held(uuid)
    if not tool then return nil end
    return { id = tool.id, type = tool.type, tier = tool.tier, uses = T.uses(tool, uuid),
        wear = T.worn(tool, held.detail, uuid) }
end

-- A world that predates its tags has no dig classes at all: say so once,
-- rather than let bare hands quietly break stone.
if U.material(U.world("stone")) then
    local tags = game.tags(U.material(U.world("stone")))
    if type(tags) ~= "table" or #tags == 0 then
        game.log("tiamat_default_craft: " .. C.world .. " tags none of its blocks (its sibling ask W2): "
            .. "without tags nothing of it is classed, and every tool breaks everything")
    end
end

-- Life's side of it ----------------------------------------------------------------------
--
-- What a tool does to a creature, to a crop and to the ground is written once,
-- in Life; this mod tells it which of its tools are weapons, sickles and hoes.

local life = game.exports("tiamat_default_life")
if life and life.version == 1 then
    -- Charred meat is food, barely: Life eats it as it eats its own.
    if life.add_food then life.add_food(game.mod_id .. ":charred_meat", { food = 1 }) end
    for _, short in ipairs(U.sorted_keys(C.tools)) do
        local spec = C.tools[short]
        local id = game.mod_id .. ":" .. short
        if spec.weapon and life.add_weapon then life.add_weapon(id, spec.weapon) end
        if spec.harvest and life.add_harvest_tool then life.add_harvest_tool(id, spec.harvest) end
        if spec.tills and life.add_tilling_tool then life.add_tilling_tool(id) end
    end
end

-- The operator's kit ----------------------------------------------------------------------

if C.dev_commands then
    -- One of every tool, for trying the gates before the recipes exist. For
    -- operators, and for everyone in a Creative world.
    tdc.on_chat("toolkit", function(player, rest)
        if not (game.is_operator(player) or creative) then
            game.chat_to(player, "toolkit is for operators")
            return
        end
        for _, short in ipairs(U.sorted_keys(C.tools)) do
            T.give(player, game.mod_id .. ":" .. short, 1)
        end
        game.chat_to(player, "a toolkit: one of each")
    end)
end

return T
