-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- This mod's own stations and recipes, as data, into the registry. Other mods
-- put theirs in through the same calls (exports.lua), so nothing here is
-- special: the kiln is a station record and some recipes, and so will an
-- alembic be.

local C = tdc.config
local R = tdc.registry
local U = tdc.util
local M = tdc.materials

-- Stations -------------------------------------------------------------------

-- By hand, from what the player carries: the Craft tab, or `craft <recipe>`.
assert(R.register_station{ id = "hand", name = "Hand", inventory = true })

-- Groups ---------------------------------------------------------------------

for name, members in pairs(C.groups) do
    local qualified = {}
    for i, member in ipairs(members) do qualified[i] = U.world(member) end
    assert(R.register_group(name, qualified))
end

-- Recipes --------------------------------------------------------------------

R.own{
    id = "stick", station = "hand", name = "Sticks",
    inputs = { { "#log", count = 1 } },
    outputs = { { M.id("stick"), count = 4 } },
}

R.own{
    id = "tinder", station = "hand", name = "Tinder",
    inputs = { { "#tinder", units = 9 } },
    outputs = { { M.id("tinder"), count = 1 } },
}

R.own{
    id = "fire_striker", station = "hand", name = "Fire striker",
    inputs = { { U.world("flint"), count = 2 } },
    outputs = { { M.id("fire_striker"), count = 1 } },
    first = "craft:fire_striker",
}

R.own{
    id = "unlit_campfire", station = "hand", name = "Campfire",
    inputs = { { M.id("stick"), count = 3 }, { "#log", count = 2 }, { M.id("tinder"), count = 1 } },
    outputs = { { M.id("unlit_campfire"), count = 1 } },
}

return {}
