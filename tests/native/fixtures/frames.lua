-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- A stand-in for science and magic's asks of Craft: a frame run by power
-- (C-S1), a blower that boosts only while powered (C-S2), a glyph as an
-- ingredient and a tool (C-S3/C-M1), a glyph known twice (C-S5/C-M7), a fire
-- lit without a striker (C-S6), unattended perform (C-S7), a long station
-- that works while unloaded (C-M5), add_progress (C-M6) and the container
-- on_crafted hears (C-M9).

for _, id in ipairs({ "frame", "athanor", "athanor_lit", "engine_furnace", "engine_furnace_lit", "plain" }) do
    game.register_block{ id = id }
end
for _, id in ipairs({ "blower", "gear", "red_stone", "relic", "saw", "steel" }) do
    game.register_item{ id = id }
end
local craft = game.exports("tiamat_default_craft")
local power, blowing = 0, false

-- Refused: what a station that runs, a long one and a boost may not be.
assert(craft.register_station{ id = "schism_frames:bad", slots = { input = 1, output = 2 }, runs = 3 } == nil)
assert(craft.register_station{ id = "schism_frames:bad", heat = true, slots = { fuel = 1, input = 2, output = 3 },
    runs = function() return 100 end } == nil)
assert(craft.register_station{ id = "schism_frames:bad", slots = { input = 1, output = 2 }, long = true } == nil)
assert(craft.register_station{ id = "schism_frames:bad", heat = true, slots = { fuel = 1, input = 2, tool = 3, output = 4 },
    boost = { tool = "schism_frames:blower", heat = 2, when = "yes" } } == nil)

assert(craft.register_station{ id = "schism_frames:frame", slots = { input = 1, tool = 2, output = 3 },
    block = "schism_frames:frame", runs = function(container) return power end } == true)
assert(craft.register_station{ id = "schism_frames:athanor", heat = true, long = true,
    slots = { fuel = 1, input = 2, output = 3 },
    block = "schism_frames:athanor", lit_block = "schism_frames:athanor_lit" } == true)
assert(craft.register_station{ id = "schism_frames:engine", heat = true,
    slots = { fuel = 1, input = 2, tool = 3, output = 4 },
    block = "schism_frames:engine_furnace", lit_block = "schism_frames:engine_furnace_lit",
    boost = { tool = "schism_frames:blower", heat = 2, when = function(container) return blowing end } } == true)

assert(craft.register{ id = "schism_frames:gear", station = "schism_frames:frame",
    inputs = { { "tiamat_default_craft:stick" } }, tools = { { "schism_frames:saw", wear = 0 } }, ticks = 200,
    outputs = { { "schism_frames:gear" } } } == true)
assert(craft.register{ id = "schism_frames:red_stone", station = "schism_frames:athanor", heat = 1,
    inputs = { { "schism_frames:gear" } }, ticks = 4000, outputs = { { "schism_frames:red_stone" } } } == true)
assert(craft.register{ id = "schism_frames:steel", station = "schism_frames:engine", heat = 2,
    inputs = { { "schism_frames:gear" } }, ticks = 100, outputs = { { "schism_frames:steel" } } } == true)

-- Glyphs: the same meaning twice is fine; a second meaning is not.
local SUN = 0x7   -- the three cells of the bottom front row
assert(craft.register_glyph(SUN, "schism_frames:sun") == true)
assert(craft.register_glyph(SUN, "schism_frames:sun") == true, "known twice (C-M7)")
assert(craft.register_glyph(SUN, "schism_frames:moon") == nil)
-- An output is never carved; an input or tool may name a glyph.
assert(craft.register{ id = "schism_frames:bad", station = "hand", inputs = { { "schism_frames:plain" } },
    outputs = { { "schism_frames:relic", glyph = "schism_frames:sun" } } } == nil)
assert(craft.register{ id = "schism_frames:relic", station = "hand",
    inputs = { { glyph = "schism_frames:sun", material = "schism_frames:plain", count = 2 } },
    outputs = { { "schism_frames:relic" } } } == true)
assert(craft.register{ id = "schism_frames:blessed_gear", station = "hand",
    inputs = { { "tiamat_default_craft:stick" } },
    tools = { { "schism_frames:plain", glyph = "schism_frames:sun" } },
    outputs = { { "schism_frames:gear" } } } == true)

local crafted = {}
assert(craft.on_crafted(function(uuid, id, outputs, container)
    crafted[#crafted + 1] = id .. "@" .. tostring(container)
end) == true)

game.register_on_chat(function(e)
    local word, rest = string.match(e.text, "^f (%S+)%s*(.*)$")
    if not word then return end
    local args = {}
    for a in string.gmatch(rest, "%S+") do args[#args + 1] = a end
    local answer
    if word == "power" then
        power = math.tointeger(tonumber(args[1]))
        answer = "ok"
    elseif word == "blow" then
        blowing = args[1] == "on"
        answer = "ok"
    elseif word == "ignite" then
        local ok, why = craft.ignite({ x = math.tointeger(tonumber(args[1])), y = math.tointeger(tonumber(args[2])),
            z = math.tointeger(tonumber(args[3])) }, e.player)
        answer = tostring(ok) .. " " .. tostring(why)
    elseif word == "addp" then
        answer = tostring(craft.add_progress(args[1], math.tointeger(tonumber(args[2]))))
    elseif word == "perform" then
        local ok, why = craft.perform(e.player, args[1], args[2], { unattended = args[3] == "alone" })
        answer = tostring(ok) .. " " .. (ok and "" or tostring(why))
    elseif word == "make" then
        local ok, why = craft.perform(e.player, args[1])
        answer = tostring(ok) .. " " .. (ok and "" or tostring(why))
    elseif word == "crafted" then
        answer = table.concat(crafted, " ")
    end
    game.chat_to(e.player, answer or "?")
    return false
end)
