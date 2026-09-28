-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- A stand-in for the tech mod: a tool of its own (an engine tool too), one
-- that claims to dig and is not an engine tool, a class of its own, and a
-- hand recipe that makes this mod's tools.

game.register_item{ id = "drill" }
game.register_tool{ id = "drill", name = "Drill", brush = "block", speed_multiplier = 5 }
game.register_item{ id = "rod" }
game.register_block{ id = "alloy_wall" }
game.register_block{ id = "plain" }
local craft = game.exports("tiamat_default_craft")
assert(craft.register_tool{ id = "schism_tech:drill", type = "drill", tier = 3, uses = 3, digs = true } == true)
assert(craft.register_tool{ id = "schism_tech:rod", type = "pick", tier = 2, uses = 5, digs = true } == true)
assert(craft.register_tool{ id = "schism_tech:drill", type = "drill", tier = 3, uses = 3 } == nil)
assert(craft.register_tool{ id = "drill", type = "drill", tier = 1, uses = 1 } == nil)
assert(craft.register_tool{ id = "schism_tech:x", type = "drill", tier = 99, uses = 1 } == nil)
assert(craft.register_class{ id = "reinforced", types = { "drill" }, tier = 3,
    refusals = { hand = "Only a drill.", type = "Only a drill." } } == true)
assert(craft.register_class{ id = "reinforced", types = { "drill" } } == nil)
assert(craft.classify("schism_tech:alloy_wall", "reinforced") == true)
assert(craft.classify("schism_tech:alloy_wall", "nope") == nil)
assert(craft.register{ id = "schism_tech:diggers", station = "hand",
    inputs = { { "tiamat_default_craft:stick" } },
    outputs = { { "tiamat_default_craft:digging_stick", count = 2 } } } == true)
local broken = {}
assert(craft.on_tool_broken(function(uuid, id) broken[#broken + 1] = id end) == true)
game.register_on_chat(function(e)
    local word, rest = string.match(e.text, "^t (%S+)%s*(.*)$")
    if not word then return end
    if word == "tool" then
        local t = craft.tool_of(e.player)
        game.chat_to(e.player, t and string.format("%s %s %d %d/%d", t.id, t.type, t.tier, t.wear, t.uses) or "none")
    elseif word == "wear" then
        game.chat_to(e.player, tostring(craft.wear(e.player, tonumber(rest))))
    elseif word == "broken" then
        game.chat_to(e.player, table.concat(broken, " "))
    end
    return false
end)
