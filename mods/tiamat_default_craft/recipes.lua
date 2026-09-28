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

-- The kiln: fuel, two inputs, the crucible or mould, the output.
assert(R.register_station{
    id = "kiln", name = "Kiln", block = M.id("kiln"), lit_block = M.id("kiln_lit"),
    slots = C.kiln_slots, heat = true,
})

-- Groups ---------------------------------------------------------------------

for _, name in ipairs(U.sorted_keys(C.groups)) do
    local qualified = {}
    for i, member in ipairs(C.groups[name]) do qualified[i] = U.world(member) end
    assert(R.register_group(name, qualified))
end
assert(R.register_group("#plank", { M.id("plank") }))
assert(R.register_group("#wedge", { M.id("wooden_wedge"), M.id("ironwood_wedge") }))

-- Fuels: what burns in anything that burns.
for _, fuel in ipairs(C.fuels) do
    local name = fuel[1]
    if string.match(name, "^world:") then
        name = U.world(string.sub(name, 7))
    elseif not U.group(name) then
        name = M.id(name)
    end
    assert(R.register_fuel(name, fuel[2], fuel[3]))
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

-- Clay, at the workbench: the kiln itself, a crucible, and the moulds.

R.own{
    id = "unfired_kiln", station = "workbench", name = "Kiln",
    inputs = { { U.world("wet_clay"), count = 9 }, { U.world("cobbles"), count = 9 } },
    outputs = { { M.id("unfired_kiln"), count = 1 } },
}

R.own{
    id = "unfired_crucible", station = "workbench", name = "Crucible (unfired)",
    inputs = { { U.world("wet_clay"), count = 3 } },
    outputs = { { M.id("unfired_crucible"), count = 1 } },
}

for _, shape in ipairs(U.sorted_keys(C.heads)) do
    R.own{
        id = "unfired_mould_" .. shape, station = "workbench", name = U.title(shape) .. " mould (unfired)",
        inputs = { { U.world("wet_clay"), count = 2 } },
        outputs = { { M.id("unfired_mould_" .. shape), count = 1 } },
    }
end
R.own{
    id = "unfired_mould_pot", station = "workbench", name = "Pot mould (unfired)",
    inputs = { { U.world("wet_clay"), count = 2 } },
    outputs = { { M.id("unfired_mould_pot"), count = 1 } },
}

-- Hafting, at the workbench: a cast head and a haft are a tool. The small
-- ones take a stick.
for _, shape in ipairs(U.sorted_keys(C.heads)) do
    local handle = (shape == "chisel" or shape == "knife") and M.id("stick") or M.id("haft")
    R.own{
        id = "bronze_" .. shape, station = "workbench", name = "Bronze " .. shape,
        inputs = { { M.id("bronze_" .. shape .. "_head"), count = 1 }, { handle, count = 1 } },
        outputs = { { M.id("bronze_" .. shape), count = 1 } },
        first = "haft:bronze_" .. shape,
    }
end

R.own{
    id = "chest", station = "workbench", name = "Chest",
    inputs = { { "#plank", count = 9 }, { M.id("cord"), count = 2 } },
    outputs = { { M.id("chest"), count = 1 } },
}

-- In the kiln. Heat 1 is wood's, 2 coal's and charcoal's.

R.own{
    id = "charcoal", station = "kiln", name = "Charcoal", heat = 1, ticks = 1200,
    inputs = { { "#log", count = 1 } },
    outputs = { { M.id("charcoal"), count = 1 } },
    first = "fire:charcoal",
}

R.own{
    id = "fired_clay", station = "kiln", name = "Fired clay", heat = 1, ticks = 200,
    inputs = { { U.world("wet_clay"), count = 1 } },
    outputs = { { M.id("fired_clay"), count = 1 } },
}

R.own{
    id = "crucible", station = "kiln", name = "Crucible", heat = 1, ticks = 600,
    inputs = { { M.id("unfired_crucible"), count = 1 } },
    outputs = { { M.id("crucible"), count = 1 } },
}

for _, shape in ipairs(U.sorted_keys(C.heads)) do
    R.own{
        id = "mould_" .. shape, station = "kiln", name = U.title(shape) .. " mould", heat = 1, ticks = 600,
        inputs = { { M.id("unfired_mould_" .. shape), count = 1 } },
        outputs = { { M.id("mould_" .. shape), count = 1 } },
    }
end
R.own{
    id = "mould_pot", station = "kiln", name = "Pot mould", heat = 1, ticks = 600,
    inputs = { { M.id("unfired_mould_pot"), count = 1 } },
    outputs = { { M.id("mould_pot"), count = 1 } },
}

-- Smelting: 27 units of ore in a crucible is an ingot.
local SMELT = { copper = 900, tin = 600, silver = 900, gold = 900, lead = 900 }
for _, metal in ipairs(U.sorted_keys(SMELT)) do
    R.own{
        id = metal .. "_ingot", station = "kiln", name = U.title(metal) .. " ingot", heat = 2, ticks = SMELT[metal],
        inputs = { { U.world(metal .. "_ore"), units = 27 } },
        tools = { M.id("crucible") },
        outputs = { { M.id(metal .. "_ingot"), count = 1 } },
        first = "smelt:" .. metal,
    }
end

-- Bronze: nine of copper to one of tin, which is the true ratio near enough.
R.own{
    id = "bronze_ingot", station = "kiln", name = "Bronze", heat = 2, ticks = 900,
    inputs = { { M.id("copper_ingot"), count = 9 }, { M.id("tin_ingot"), count = 1 } },
    tools = { M.id("crucible") },
    outputs = { { M.id("bronze_ingot"), count = 10 } },
    first = "smelt:bronze",
}

-- Casting: bronze poured into a mould; a copper pot.
for _, shape in ipairs(U.sorted_keys(C.heads)) do
    R.own{
        id = "bronze_" .. shape .. "_head", station = "kiln", name = "Bronze " .. shape .. " head",
        heat = 2, ticks = 600,
        inputs = { { M.id("bronze_ingot"), count = C.heads[shape] } },
        tools = { M.id("mould_" .. shape) },
        outputs = { { M.id("bronze_" .. shape .. "_head"), count = 1 } },
        first = "cast:bronze_" .. shape,
    }
end
R.own{
    id = "copper_pot", station = "kiln", name = "Copper pot", heat = 2, ticks = 600,
    inputs = { { M.id("copper_ingot"), count = 3 } },
    tools = { M.id("mould_pot") },
    outputs = { { M.id("copper_pot"), count = 1 } },
    first = "cast:copper_pot",
}

return {}
