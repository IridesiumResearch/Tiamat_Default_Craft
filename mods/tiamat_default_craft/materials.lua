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
-- It drops NOTHING of its own: the engine lets a block's `drops` name only
-- the registering mod's materials (engine ask 7), so the rock it yields is
-- given to the digger by fire.lua as the dig lands.
M.cracked = {}   -- world short name -> this mod's cracked twin's qualified id
for _, name in ipairs(tdc.config.cracks) do
    local parent = tdc.util.world(name)
    if tdc.util.material(parent) then
        block("cracked_" .. name, {
            name = "Cracked " .. string.gsub(name, "_", " "),
            description = "Fire-cracked. It comes away by hand.",
            hardness = tdc.config.cracked_hardness,
            drops = {},
        })
        M.cracked[name] = game.mod_id .. ":cracked_" .. name
    end
end

--- The qualified id of one of this mod's items.
function M.id(short)
    return game.mod_id .. ":" .. short
end

return M
