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

-- The workbench: nine slots in, one out.
assert(R.register_station{
    id = "workbench", name = "Workbench", block = M.id("workbench"),
    slots = { input = { from = 1, to = 9 }, output = 10 },
})

-- Groups ---------------------------------------------------------------------

for _, name in ipairs(U.sorted_keys(C.groups)) do
    local qualified = {}
    for i, member in ipairs(C.groups[name]) do qualified[i] = U.world(member) end
    assert(R.register_group(name, qualified))
end
assert(R.register_group("#plank", { M.id("plank") }))
assert(R.register_group("#wedge", { M.id("wooden_wedge"), M.id("ironwood_wedge") }))

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
    id = "cord", station = "hand", name = "Cord",
    inputs = { { U.world("bramble"), count = 1 } },
    outputs = { { M.id("cord"), count = 2 } },
}

R.own{
    id = "workbench", station = "hand", name = "Workbench",
    inputs = { { "#log", count = 4 }, { M.id("cord"), count = 4 } },
    outputs = { { M.id("workbench"), count = 1 } },
}

R.own{
    id = "unlit_campfire", station = "hand", name = "Campfire",
    inputs = { { M.id("stick"), count = 3 }, { "#log", count = 2 }, { M.id("tinder"), count = 1 } },
    outputs = { { M.id("unlit_campfire"), count = 1 } },
}

-- At the workbench: the wood tier.

R.own{
    id = "plank", station = "workbench", name = "Planks",
    inputs = { { "#log", count = 1 } },
    tools = { "#wedge" },
    outputs = { { M.id("plank"), count = 4 } },
}

R.own{
    id = "haft", station = "workbench", name = "Haft",
    inputs = { { M.id("stick"), count = 2 }, { M.id("cord"), count = 1 } },
    outputs = { { M.id("haft"), count = 1 } },
}

R.own{
    id = "digging_stick", station = "workbench", name = "Digging stick",
    inputs = { { M.id("stick"), count = 2 }, { M.id("cord"), count = 1 } },
    outputs = { { M.id("digging_stick"), count = 1 } },
}

R.own{
    id = "wooden_wedge", station = "workbench", name = "Wooden wedge",
    inputs = { { "#log", count = 1 } },
    outputs = { { M.id("wooden_wedge"), count = 2 } },
}

R.own{
    id = "wooden_maul", station = "workbench", name = "Wooden maul",
    inputs = { { "#log", count = 1 }, { M.id("haft"), count = 1 } },
    outputs = { { M.id("wooden_maul"), count = 1 } },
}

-- Ironwood: the same, from the hardwood a bronze axe fells, and twice as long-lived.

R.own{
    id = "ironwood_digging_stick", station = "workbench", name = "Ironwood digging stick",
    inputs = { { U.world("ironwood_log"), count = 1 }, { M.id("cord"), count = 1 } },
    outputs = { { M.id("ironwood_digging_stick"), count = 1 } },
}

R.own{
    id = "ironwood_wedge", station = "workbench", name = "Ironwood wedge",
    inputs = { { U.world("ironwood_log"), count = 1 } },
    outputs = { { M.id("ironwood_wedge"), count = 2 } },
}

R.own{
    id = "ironwood_maul", station = "workbench", name = "Ironwood maul",
    inputs = { { U.world("ironwood_log"), count = 1 }, { M.id("haft"), count = 1 } },
    outputs = { { M.id("ironwood_maul"), count = 1 } },
}

R.own{
    id = "chest", station = "workbench", name = "Chest",
    inputs = { { "#plank", count = 9 }, { M.id("cord"), count = 2 } },
    outputs = { { M.id("chest"), count = 1 } },
}

return {}
