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

-- The campfire: what is put on a fire this mod lit cooks while it burns
-- (cooking.lua). Two on the fire, a pot, what comes off.
assert(R.register_station{
    id = "campfire", name = "Campfire", block = tdc.fire.LIT, auto = true,
    slots = { input = { 1, 2 }, tool = 3, output = 4 },
})

-- The bloomery: charcoal only; bellows in the tool slot for white heat.
assert(R.register_station{
    id = "bloomery", name = "Bloomery", block = M.id("bloomery"), lit_block = M.id("bloomery_lit"),
    slots = C.bloomery_slots, heat = true, fuels = { M.id("charcoal") },
    boost = { tool = M.id("bellows"), heat = 3 }, refuse_fuel = C.coal_spoils,
})

-- The anvil: the work on it, struck with a hammer (anvil.lua).
assert(R.register_station{
    id = "anvil", name = "Anvil", block = M.id("stone_anvil"), forge = true,
    slots = { input = 1, output = 2 },
})

-- The sluice: gravel in, sand, tin and now and then gold out (sluice.lua).
assert(R.register_station{
    id = "sluice", name = "Sluice", block = M.id("sluice"), auto = true,
    slots = { input = 1, output = { 2, 3, 4 } },
})

-- Groups ---------------------------------------------------------------------

for _, name in ipairs(U.sorted_keys(C.groups)) do
    local qualified = {}
    for i, member in ipairs(C.groups[name]) do qualified[i] = U.world(member) end
    assert(R.register_group(name, qualified))
end
assert(R.register_group("#plank", { M.id("plank") }))
assert(R.register_group("#wedge", { M.id("wooden_wedge"), M.id("ironwood_wedge") }))
assert(R.register_group("#hammer", { M.id("bronze_hammer"), M.id("iron_hammer") }))
assert(R.register_group("#chisel", { M.id("bronze_chisel"), M.id("iron_chisel") }))
assert(R.register_group("#ash", { M.id("ash"), U.world("volcanic_ash") }))
assert(R.register_group("#fruit", { "tiamat_default_life:apple", "tiamat_default_life:berries" }))

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
    id = "bark_strip", station = "hand", name = "Bark strips",
    inputs = { { "#log", count = 1 } },
    outputs = { { M.id("bark_strip"), count = 4 } },
}

R.own{
    id = "torch", station = "hand", name = "Torches",
    inputs = { { M.id("stick"), count = 1 }, { M.id("bark_strip"), count = 1 }, { M.id("tinder"), count = 1 } },
    outputs = { { M.id("torch"), count = 2 } },
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
R.own{
    id = "unfired_mould_tuyere", station = "workbench", name = "Tuyere mould (unfired)",
    inputs = { { U.world("wet_clay"), count = 2 } },
    outputs = { { M.id("unfired_mould_tuyere"), count = 1 } },
}

-- Iron's workshop, at the workbench: the bloomery, its bellows, the anvil.
R.own{
    id = "bloomery", station = "workbench", name = "Bloomery",
    inputs = { { M.id("fired_clay"), count = 9 }, { U.world("stone"), count = 9 }, { M.id("bronze_tuyere"), count = 1 } },
    outputs = { { M.id("bloomery"), count = 1 } },
}
R.own{
    id = "bellows", station = "workbench", name = "Bellows",
    inputs = { { "#plank", count = 4 }, { M.id("cord"), count = 4 }, { M.id("copper_nozzle"), count = 1 } },
    outputs = { { M.id("bellows"), count = 1 } },
}
R.own{
    id = "stone_anvil", station = "workbench", name = "Stone anvil",
    inputs = { { U.world("granite"), count = 1 } },
    tools = { { "#chisel", wear = 10 } },
    outputs = { { M.id("stone_anvil"), count = 1 } },
    first = "craft:anvil",
}

-- Hafting, at the workbench: a cast or forged head and a haft are a tool.
-- The small ones take a stick.
for _, metal in ipairs({ "bronze", "iron" }) do
    for _, shape in ipairs(U.sorted_keys(C.heads)) do
        local handle = (shape == "chisel" or shape == "knife") and M.id("stick") or M.id("haft")
        R.own{
            id = metal .. "_" .. shape, station = "workbench", name = U.title(metal) .. " " .. shape,
            inputs = { { M.id(metal .. "_" .. shape .. "_head"), count = 1 }, { handle, count = 1 } },
            outputs = { { M.id(metal .. "_" .. shape), count = 1 } },
            first = "haft:" .. metal .. "_" .. shape,
        }
    end
end

R.own{
    id = "sluice", station = "workbench", name = "Sluice",
    inputs = { { "#plank", count = 4 }, { M.id("cord"), count = 2 } },
    outputs = { { M.id("sluice"), count = 1 } },
}

R.own{
    id = "wash", station = "sluice", name = "Washed gravel", ticks = C.wash_ticks,
    inputs = { { U.world("gravel"), units = 27 } },
    outputs = { { U.world("sand"), units = 24 }, { M.id("tin_grain"), count = 1 } },
    first = "wash:tin",
}

R.own{
    id = "chest", station = "workbench", name = "Chest",
    inputs = { { "#plank", count = 9 }, { M.id("cord"), count = 2 } },
    outputs = { { M.id("chest"), count = 1 } },
}

-- On a campfire: Life's food, cooked; clay dried.

local LIFE = "tiamat_default_life:"

R.own{
    id = "spit_roast", station = "campfire", name = "Cooked meat", ticks = 300,
    inputs = { { LIFE .. "raw_meat", count = 1 } },
    outputs = { { LIFE .. "cooked_meat", count = 1 } },
    first = "cook:meat",
}

R.own{
    id = "stew", station = "campfire", name = "Hot stew", ticks = 600,
    inputs = { { LIFE .. "raw_meat", count = 1 }, { "#fruit", count = 1 } },
    tools = { { M.id("copper_pot"), wear = 0 } },
    outputs = { { LIFE .. "hot_stew", count = 1 } },
    first = "cook:stew",
}

R.own{
    id = "dry_clay", station = "campfire", name = "Dry clay", ticks = 200,
    inputs = { { U.world("wet_clay"), count = 1 } },
    outputs = { { U.world("dry_clay"), count = 1 } },
}

-- In the kiln. Heat 1 is wood's, 2 coal's and charcoal's.

R.own{
    id = "oven_roast", station = "kiln", name = "Cooked meat", heat = 1, ticks = 400,
    inputs = { { LIFE .. "raw_meat", count = 1 } },
    outputs = { { LIFE .. "cooked_meat", count = 1 } },
    first = "cook:meat",
}

R.own{
    id = "bread", station = "kiln", name = "Bread", heat = 1, ticks = 600,
    inputs = { { LIFE .. "wheat", count = 3 } },
    outputs = { { LIFE .. "bread", count = 1 } },
    first = "cook:bread",
}

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
R.own{
    id = "mould_tuyere", station = "kiln", name = "Tuyere mould", heat = 1, ticks = 600,
    inputs = { { M.id("unfired_mould_tuyere"), count = 1 } },
    outputs = { { M.id("mould_tuyere"), count = 1 } },
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

-- Washed metal: nine grains of tin, or nine flakes of gold, are an ingot.
R.own{
    id = "tin_from_grains", station = "kiln", name = "Tin ingot", heat = 2, ticks = 600,
    inputs = { { M.id("tin_grain"), count = 9 } },
    tools = { M.id("crucible") },
    outputs = { { M.id("tin_ingot"), count = 1 } },
    first = "smelt:tin",
}
R.own{
    id = "gold_from_flakes", station = "kiln", name = "Gold ingot", heat = 2, ticks = 600,
    inputs = { { M.id("gold_flake"), count = 9 } },
    tools = { M.id("crucible") },
    outputs = { { M.id("gold_ingot"), count = 1 } },
    first = "smelt:gold",
}

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
    id = "bronze_tuyere", station = "kiln", name = "Bronze tuyere", heat = 2, ticks = 600,
    inputs = { { M.id("bronze_ingot"), count = 2 } },
    tools = { M.id("mould_tuyere") },
    outputs = { { M.id("bronze_tuyere"), count = 1 } },
    first = "cast:bronze_tuyere",
}
R.own{
    id = "copper_nozzle", station = "kiln", name = "Copper nozzle", heat = 2, ticks = 600,
    inputs = { { M.id("copper_ingot"), count = 1 } },
    tools = { M.id("mould_tuyere") },
    outputs = { { M.id("copper_nozzle"), count = 1 } },
}

-- In the bloomery, at white heat: two parts ore to one of charcoal, and
-- out comes a bloom.
R.own{
    id = "iron_bloom", station = "bloomery", name = "Iron bloom", heat = 3, ticks = C.bloom_ticks,
    inputs = { { U.world("iron_ore"), units = 54 }, { M.id("charcoal"), units = 27 } },
    outputs = { { M.id("iron_bloom"), count = 1 } },
    first = "smelt:iron",
}

-- On the anvil: a bloom beaten into a bar with any hammer; a bar into a
-- head with an iron one. The first iron hammer is the exception.
R.own{
    id = "iron_bar", station = "anvil", name = "Wrought iron bar", strikes = C.strikes_bar,
    inputs = { { M.id("iron_bloom"), count = 1 } },
    tools = { "#hammer" },
    outputs = { { M.id("iron_bar"), count = 1 } },
    first = "forge:iron_bar",
}
for _, shape in ipairs(U.sorted_keys(C.heads)) do
    R.own{
        id = "iron_" .. shape .. "_head", station = "anvil", name = "Iron " .. shape .. " head",
        strikes = C.strikes_head,
        inputs = { { M.id("iron_bar"), count = C.heads[shape] } },
        tools = { M.id("iron_hammer") },
        outputs = { { M.id("iron_" .. shape .. "_head"), count = 1 } },
        first = "forge:iron_" .. shape,
    }
end
R.own{
    id = "first_iron_hammer_head", station = "anvil", name = "First iron hammer head",
    strikes = C.strikes_first_hammer,
    inputs = { { M.id("iron_bar"), count = C.heads.hammer } },
    tools = { { M.id("bronze_hammer"), wear = 2 } },
    outputs = { { M.id("iron_hammer_head"), count = 1 } },
    first = "forge:iron_hammer",
}

R.own{
    id = "copper_pot", station = "kiln", name = "Copper pot", heat = 2, ticks = 600,
    inputs = { { M.id("copper_ingot"), count = 3 } },
    tools = { M.id("mould_pot") },
    outputs = { { M.id("copper_pot"), count = 1 } },
    first = "cast:copper_pot",
}

-- After the loop (step 10) ---------------------------------------------------
--
-- Parts: a bar is beaten into one of each, an iron hammer's five blows, and
-- each is held to taking and giving the same units. What the Fork's
-- Keystone and both trees are built from.

local PARTS = { iron_plate = 5, iron_nails = 3, iron_chain = 6, iron_hinge = 4 }
for _, part in ipairs(U.sorted_keys(PARTS)) do
    R.own{
        id = part, station = "anvil", name = U.title(part), strikes = PARTS[part], conserve = true,
        inputs = { { M.id("iron_bar"), count = 1 } },
        tools = { M.id("iron_hammer") },
        outputs = { { M.id(part), count = 1 } },
        first = "forge:" .. part,
    }
end

R.own{
    id = "iron_frame", station = "workbench", name = "Iron frame",
    inputs = { { M.id("iron_plate"), count = 4 }, { M.id("iron_nails"), count = 1 } },
    tools = { "#hammer" },
    outputs = { { M.id("iron_frame"), count = 1 } },
    first = "craft:iron_frame",
}

-- Gears are bronze, cast: there is no zinc in the world for brass.
R.own{
    id = "unfired_mould_gear", station = "workbench", name = "Gear mould (unfired)",
    inputs = { { U.world("wet_clay"), count = 2 } },
    outputs = { { M.id("unfired_mould_gear"), count = 1 } },
}
R.own{
    id = "mould_gear", station = "kiln", name = "Gear mould", heat = 1, ticks = 600,
    inputs = { { M.id("unfired_mould_gear"), count = 1 } },
    outputs = { { M.id("mould_gear"), count = 1 } },
}
R.own{
    id = "bronze_gear", station = "kiln", name = "Bronze gear", heat = 2, ticks = 600, conserve = true,
    inputs = { { M.id("bronze_ingot"), count = 1 } },
    tools = { M.id("mould_gear") },
    outputs = { { M.id("bronze_gear"), count = 1 } },
    first = "cast:bronze_gear",
}

-- Building.
R.own{
    id = "mudbrick", station = "workbench", name = "Mudbrick",
    inputs = { { U.world("wet_clay"), count = 1 }, { M.id("tinder"), count = 1 } },
    outputs = { { M.id("mudbrick"), count = 1 } },
}
R.own{
    id = "brick", station = "kiln", name = "Brick", heat = 2, ticks = 400, conserve = true,
    inputs = { { M.id("mudbrick"), count = 1 } },
    outputs = { { M.id("brick"), count = 1 } },
}
R.own{
    id = "glass", station = "kiln", name = "Glass", heat = 2, ticks = 600,
    inputs = { { U.world("white_sand"), count = 1 }, { "#ash", units = 9 } },
    outputs = { { M.id("glass"), count = 1 } },
    first = "smelt:glass",
}
R.own{
    id = "iron_lantern", station = "workbench", name = "Iron lantern",
    inputs = { { M.id("iron_plate"), count = 1 }, { M.id("glass"), count = 1 }, { M.id("torch"), count = 1 } },
    outputs = { { M.id("iron_lantern"), count = 1 } },
}

return {}
