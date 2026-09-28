-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- A stand-in for Tiamat Default Progress as it uses Craft: requirements put
-- on Craft's recipes from outside (its sibling ask C1), the node effects
-- handed in (C2), and a study at a research table that makes nothing (C5).
-- `q set <key> <n>` changes an effect; `q <word>` reports.

local craft = game.exports("tiamat_default_craft")
assert(craft and craft.version == 1)

-- C1: a requirement from outside, once.
assert(craft.set_requires("tiamat_default_craft:bronze_ingot", "shared.kiln_lore") == true)
assert(craft.set_requires("tiamat_default_craft:bronze_ingot", "shared.other") == nil, "already required")
assert(craft.set_requires("nobody:nothing", "shared.kiln_lore") == nil)
assert(craft.set_requires("tiamat_default_craft:charcoal", 7) == nil)
local found = false
for _, recipe in ipairs(craft.recipes("kiln")) do
    if recipe.id == "tiamat_default_craft:bronze_ingot" then found = recipe.requires == "shared.kiln_lore" end
end
assert(found, "the requirement is on the recipe")

-- C2: the effects, a table this stand-in changes from chat.
local deltas = {}
assert(craft.set_effects(function(uuid, prefix)
    local out = {}
    for k, v in pairs(deltas) do
        if string.sub(k, 1, #prefix) == prefix then out[k] = v end
    end
    return out
end) == true)
assert(craft.set_effects(function() return {} end) == nil, "one owner")

-- C5: a research table, and a study that makes nothing.
game.register_item{ id = "notes" }
assert(craft.register_station{ id = "tiamat_default_progress:table", name = "Research table",
    slots = { input = 1, output = 2 } } == true)
assert(craft.register{ id = "tiamat_default_progress:study_copper", station = "tiamat_default_progress:table",
    inputs = { { "tiamat_default_craft:copper_ingot", count = 1 } }, outputs = {} } == true)
assert(craft.register{ id = "tiamat_default_progress:bad", station = "tiamat_default_progress:table",
    conserve = true, inputs = { { "tiamat_default_craft:copper_ingot", count = 1 } }, outputs = {} } == nil,
    "a study that says it conserves is refused")

-- Glyphs: a carved mask means something, and a carved stack reads as it.
local RING = 0
for x = 0, 2 do for z = 0, 2 do if not (x == 1 and z == 1) then RING = RING | (1 << (x + 9 * z)) end end end
assert(craft.register_glyph(RING, "tiamat_default_progress:ring") == true)
assert(craft.register_glyph(RING, "tiamat_default_progress:other") == nil, "one meaning a mask")
assert(craft.register_glyph(0, "tiamat_default_progress:none") == nil)
assert(craft.register_glyph(1 << 27, "tiamat_default_progress:none") == nil)
assert(craft.glyph_of({ material = 1, shape = RING }) == "tiamat_default_progress:ring")
assert(craft.glyph_of(RING) == "tiamat_default_progress:ring")
assert(craft.glyph_of({ material = 1 }) == nil)
assert(craft.glyph_of("nonsense") == nil)

local insight = 0
assert(craft.on_crafted(function(uuid, id, outputs)
    if id == "tiamat_default_progress:study_copper" and #outputs == 0 then insight = insight + 10 end
end) == true)

game.register_on_chat(function(e)
    local word, rest = string.match(e.text, "^q (%S+)%s*(.*)$")
    if not word then return end
    if word == "set" then
        local key, n = string.match(rest, "^(%S+) (%-?%d+)$")
        deltas[key] = tonumber(n)
        game.chat_to(e.player, "set")
    elseif word == "study" then
        game.make_container("progress:table", 2)
        local ok, why = craft.perform(e.player, "tiamat_default_progress:study_copper", "progress:table")
        game.chat_to(e.player, tostring(ok) .. " " .. tostring(why and #why or why) .. " " .. insight)
    elseif word == "late" then
        game.chat_to(e.player, tostring(craft.set_requires("tiamat_default_craft:charcoal", "shared.x")))
    elseif word == "tool" then
        local t = craft.tool_of(e.player)
        game.chat_to(e.player, t and (t.wear .. "/" .. t.uses) or "none")
    end
    return false
end)
