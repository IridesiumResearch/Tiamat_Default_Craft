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

--- The qualified id of one of this mod's items.
function M.id(short)
    return game.mod_id .. ":" .. short
end

return M
