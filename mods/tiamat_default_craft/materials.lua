-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- The items and blocks this mod registers.
--
-- Every one has a texture: without one a thing reaches players as the
-- missing-texture chequer. The pictures are flat colours with one shape each,
-- drawn by tools/make_textures.py, and are meant to be replaced.

local M = {}

--- Every item this mod registered, by short id: `{ id, name, material }`.
M.items = {}

local function item(id, name, description)
    local material = game.register_item{
        id = id,
        name = name,
        description = description,
        texture = "textures/" .. id .. ".png",
    }
    M.items[id] = { id = game.mod_id .. ":" .. id, name = name, material = material }
    return material
end

item("stick", "Stick", "Split from a log. Hafts, kindling, a digging stick's shaft.")
item("tinder", "Tinder", "Dry grass, needles and moss, rubbed to fluff. It catches a spark.")
item("cord", "Cord", "Bramble cane, stripped and twisted. It binds a haft and hangs a lid.")
item("haft", "Haft", "A straight handle, bound. A head goes on it.")
item("bark_strip", "Bark strip", "Peeled from a log. It binds a torch's head.")

-- The sluice's.
item("tin_grain", "Tin grain", "Black grains of tin, washed out of river gravel.")
item("gold_flake", "Gold flake", "A fleck of gold the water left behind.")

-- Cooking's: what a fire makes of meat left on it too long.
item("charred_meat", "Charred meat", "Left on the fire. It is food, just.")

-- The kiln's: fuel, ceramics, metal.
item("charcoal", "Charcoal", "Wood burned without air. It burns hotter than the log it was.")
item("fired_clay", "Fired clay", "Clay the kiln has made stone of.")
item("unfired_crucible", "Unfired crucible", "A clay pot, shaped. Fire it in the kiln.")
for _, metal in ipairs({ "copper", "tin", "bronze", "silver", "gold", "lead" }) do
    local name = string.upper(string.sub(metal, 1, 1)) .. string.sub(metal, 2)
    item(metal .. "_ingot", name .. " ingot", nil)
end
for _, head in ipairs(tdc.util.sorted_keys(tdc.config.heads)) do
    item("unfired_mould_" .. head, "Unfired " .. head .. " mould", "Clay pressed round a pattern. Fire it in the kiln.")
    item("bronze_" .. head .. "_head", "Bronze " .. head .. " head", "Cast. It wants a haft at the workbench.")
end
item("unfired_mould_pot", "Unfired pot mould", "Clay pressed round a pattern. Fire it in the kiln.")
item("unfired_mould_tuyere", "Unfired tuyere mould", "Clay pressed round a pattern. Fire it in the kiln.")
item("bronze_tuyere", "Bronze tuyere", "The nozzle a bloomery's air comes in by.")
item("copper_nozzle", "Copper nozzle", "The spout of a pair of bellows.")

-- After the loop (step 10): the parts the progress mod's Keystone and both
-- trees are built from, and the first building materials.
item("iron_plate", "Iron plate", "A bar beaten flat.")
item("iron_nails", "Iron nails", "A bar's worth of nails.")
item("iron_chain", "Iron chain", "A bar's worth of links.")
item("iron_hinge", "Iron hinge", "Two leaves and a pin.")
item("iron_frame", "Iron frame", "Plates nailed square. What a keystone is set in.")
item("bronze_gear", "Bronze gear", "Cast. It turns another.")
item("unfired_mould_gear", "Unfired gear mould", "Clay pressed round a pattern. Fire it in the kiln.")
item("ash", "Ash", "What a fire leaves. With sand, it is glass.")

-- Iron: a bloom out of the bloomery, a bar off the anvil, heads forged from bars.
item("iron_bloom", "Iron bloom", "Spongy iron and slag. Beat it on an anvil.")
item("iron_bar", "Wrought iron bar", "Iron beaten clean. Forge it into a head.")
for _, head in ipairs(tdc.util.sorted_keys(tdc.config.heads)) do
    item("iron_" .. head .. "_head", "Iron " .. head .. " head", "Forged. It wants a haft at the workbench.")
end

--- Every block this mod registered, by short id: its numeric material.
M.blocks = {}

local function block(id, spec)
    spec.id = id
    spec.textures = spec.textures or { all = "textures/" .. id .. ".png" }
    M.blocks[id] = game.register_block(spec)
    return M.blocks[id]
end

-- The workshop (stations.lua). One plank for every tree: the world keeps
-- its rule of one of each, and a plank is a plank.
block("plank", {
    name = "Plank",
    description = "Split from a log with a wedge and a maul.",
    hardness = 0.8,
})
block("workbench", {
    name = "Workbench",
    description = "Logs lashed with cord. What is made of several things is made here.",
    hardness = 1.0,
})
block("chest", {
    name = "Chest",
    description = "Planks pegged into a box. Use it to open it; dig it to take it away, contents and all.",
    hardness = 1.0,
})

-- The torch (fire.lua): a light that burns out.
block("torch", {
    name = "Torch",
    description = "Tinder bound to a stick with bark. It burns out, in time.",
    hardness = 0.1,
    cutout = true,
    passable = true,
    light_emit = tdc.config.torch_light,
})
block("spent_torch", {
    name = "Spent torch",
    description = "Burned out. The stick is still good.",
    hardness = 0.1,
    cutout = true,
    passable = true,
    drops = { stick = 27 },
})

-- Building: mudbrick dries by itself; fired, it is brick; sand and ash are glass.
block("mudbrick", {
    name = "Mudbrick",
    description = "Clay and straw, pressed and dried.",
    hardness = 0.9,
})
block("brick", {
    name = "Brick",
    description = "Mudbrick the kiln has fired.",
    hardness = 1.8,
})
block("glass", {
    name = "Glass",
    description = "Sand and ash, melted. You can see through it; you cannot walk through it.",
    hardness = 0.3,
    transparent = true,
})
block("iron_lantern", {
    name = "Iron lantern",
    description = "A torch behind glass in an iron case. It does not burn out.",
    hardness = 0.5,
    cutout = true,
    light_emit = { r = 14, g = 11, b = 6 },
})

-- The sluice (sluice.lua): it stands in running water.
block("sluice", {
    name = "Sluice",
    description = "A plank trough with riffles. Stand it in running water and give it gravel.",
    hardness = 0.8,
})

-- The bloomery (furnace.lua) and the anvil (anvil.lua).
block("bloomery", {
    name = "Bloomery",
    description = "A clay stack with a tuyere. Charcoal only; bellows make it burn white.",
    hardness = 1.5,
})
block("bloomery_lit", {
    name = "Bloomery (burning)",
    description = "Burning.",
    hardness = 1.5,
    light_emit = { r = 14, g = 8, b = 2 },
})
block("stone_anvil", {
    name = "Stone anvil",
    description = "Granite, squared with a chisel. Put the work on it and strike it with a hammer.",
    hardness = 2.0,
})

-- The kiln (furnace.lua): laid of wet clay and cobbles, fired once to be a
-- kiln, lit with a striker to burn.
block("unfired_kiln", {
    name = "Unfired kiln",
    description = "Clay and cobbles, laid. Put fuel in it and strike it: the first fire makes it a kiln.",
    hardness = 0.8,
})
block("kiln", {
    name = "Kiln",
    description = "Fuel in the bottom, work in the middle. Strike it to light it.",
    hardness = 1.5,
})
block("kiln_lit", {
    name = "Kiln (burning)",
    description = "Burning.",
    hardness = 1.5,
    light_emit = { r = 12, g = 6, b = 1 },
})

-- Fire (fire.lua). The lit fire is Life's campfire when Life is here, so
-- its heat and its burn are Life's; `campfire_lit` is this mod's own, for a
-- world without Life.
block("unlit_campfire", {
    name = "Campfire (unlit)",
    description = "Sticks, logs and tinder, laid. Strike it with a fire striker.",
    hardness = 0.4,
    cutout = true,
})
block("campfire_lit", {
    name = "Campfire",
    description = "A fire of your own making. Feed it logs; it cracks the rock beside it.",
    hardness = 0.4,
    cutout = true,
    light_emit = { r = 14, g = 9, b = 4 },
})

-- What fire leaves of rock: the rock it was, cracked, which the hand can
-- break and which yields the rock whole. Only for the world's rocks that
-- exist in this world.
--
-- It drops the world's rock, whole: a `drops` key may name another mod's
-- block (engine ask 7, engine c83fbc9), paid in units as it comes apart.
M.cracked = {}   -- world short name -> this mod's cracked twin's qualified id
for _, name in ipairs(tdc.config.cracks) do
    local parent = tdc.util.world(name)
    if tdc.util.material(parent) then
        block("cracked_" .. name, {
            name = "Cracked " .. string.gsub(name, "_", " "),
            description = "Fire-cracked. It comes away by hand.",
            hardness = tdc.config.cracked_hardness,
            drops = { [parent] = 27 },
            tags = { "cracked" },
        })
        M.cracked[name] = game.mod_id .. ":cracked_" .. name
    end
end

--- The qualified id of one of this mod's items.
function M.id(short)
    return game.mod_id .. ":" .. short
end

return M
