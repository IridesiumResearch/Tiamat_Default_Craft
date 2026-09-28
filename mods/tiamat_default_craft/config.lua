-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Every number a designer might want to turn, in one place, in the units the
-- rest of the mod uses: UNITS for quantities (27 to a block, and to an item)
-- and TICKS for time (20 to a second).
--
-- Nothing here shapes the world, so nothing here is a `game.register_setting`:
-- these are the mod's opinions, read once at load.

local C = {}

-- Chat words for testing and for the operator (commands.lua). `recipes` and
-- `craft` are for anyone: they list and make hand recipes from what a player
-- already carries, which is only what the Craft tab does. This switch removes
-- the operator's words altogether for a server that wants none of them.
C.dev_commands = true

-- The world mod whose blocks this mod names. Its ids are looked up by name,
-- never copied, so a world without it loses those recipes and nothing else.
C.world = "tiamat_default_world"

-- The world's mode, from Life: "Default", "Creative" or "Adventure". In a
-- Creative world nothing is refused to the wrong tool and nothing wears.
C.mode = "Default"
do
    local chosen = game.world_option("tiamat_default_life:mode")
    if type(chosen) == "string" then C.mode = chosen end
end

-- The registry's own limits: what a recipe may ask for, so that a malformed
-- one from another mod is refused at registration rather than discovered by
-- a player.
C.max_inputs = 16
C.max_tools = 4
C.max_outputs = 8
C.max_units = 27 * 999      -- in one entry: a thousand items is not a recipe
C.max_heat = 9
C.max_ticks = 20 * 60 * 60  -- an hour of burning is the longest job there is

-- Groups: a recipe asking for "#log" takes any of them. Additive: another mod
-- may put its own log in with `register_group`.
C.groups = {
    ["#log"] = {
        "oak_log", "birch_log", "dead_log", "fir_log", "willow_log", "kapok_log",
        "juniper_log", "apple_log", "cherry_log", "mangrove_log", "acacia_log",
        "redwood_log", "ironwood_log",
    },
}

-- Tools ------------------------------------------------------------------------
--
-- Every tool is an item AND, when it digs, an engine tool of the same id. The
-- engine knows one number about a tool, its speed; everything else here is
-- this mod's. `type` is what it is for, `tier` how hard a thing it may break
-- (0 wood, 1 bronze, 2 iron), `uses` how many digs or strikes before it wears
-- to nothing (0 never), `speed` the engine's multiplier over a bare hand.
-- A tool with no `speed` does not dig: holding it is holding nothing, as far
-- as the ground is concerned.
--
-- Wood has no pick and no axe. That is the point: the wood tier moves soil,
-- breaks fire-cracked rock and makes the workshop, and metal does the rest.
-- Ironwood doubles a wooden tool's life, and is hardwood, so it comes after
-- the first bronze axe.

C.hand_speed = 1.0

C.tools = {
    digging_stick          = { name = "Digging stick", type = "spade", tier = 0, uses = 60, speed = 1.6 },
    ironwood_digging_stick = { name = "Ironwood digging stick", type = "spade", tier = 0, uses = 120, speed = 1.6 },
    bronze_spade           = { name = "Bronze spade", type = "spade", tier = 1, uses = 150, speed = 2.4 },
    iron_spade             = { name = "Iron spade", type = "spade", tier = 2, uses = 600, speed = 3.2 },

    wooden_maul            = { name = "Wooden maul", type = "maul", tier = 0, uses = 80, speed = 1.4, weapon = 4 },
    ironwood_maul          = { name = "Ironwood maul", type = "maul", tier = 0, uses = 160, speed = 1.4, weapon = 4 },
    wooden_wedge           = { name = "Wooden wedge", type = "wedge", tier = 0, uses = 40 },
    ironwood_wedge         = { name = "Ironwood wedge", type = "wedge", tier = 0, uses = 80 },

    bronze_axe             = { name = "Bronze axe", type = "axe", tier = 1, uses = 120, speed = 2.2, weapon = 5 },
    iron_axe               = { name = "Iron axe", type = "axe", tier = 2, uses = 500, speed = 3.0, weapon = 7 },
    bronze_pick            = { name = "Bronze pick", type = "pick", tier = 1, uses = 100, speed = 1.8, weapon = 4 },
    iron_pick              = { name = "Iron pick", type = "pick", tier = 2, uses = 450, speed = 2.6, weapon = 5 },
    -- The only sub-node tool: one cell of the 27 at a time. It carves what a
    -- pick or an axe of its tier may break.
    bronze_chisel          = { name = "Bronze chisel", type = "chisel", tier = 1, uses = 200, speed = 0.6, brush = "subnode" },
    iron_chisel            = { name = "Iron chisel", type = "chisel", tier = 2, uses = 800, speed = 0.9, brush = "subnode" },

    -- Station tools: worn by the recipes that name them, not by digging.
    bronze_hammer          = { name = "Bronze hammer", type = "hammer", tier = 1, uses = 120, weapon = 4 },
    iron_hammer            = { name = "Iron hammer", type = "hammer", tier = 2, uses = 600, weapon = 5 },
    bronze_knife           = { name = "Bronze knife", type = "knife", tier = 1, uses = 80, weapon = 4 },
    iron_knife             = { name = "Iron knife", type = "knife", tier = 2, uses = 300, weapon = 6 },
    copper_pot             = { name = "Copper pot", type = "pot", tier = 1, uses = 0 },

    -- Farm tools, which Life's exports make work: a sickle reaps more of a
    -- ripe crop, a hoe tills.
    bronze_sickle          = { name = "Bronze sickle", type = "sickle", tier = 1, uses = 100, harvest = 2 },
    iron_sickle            = { name = "Iron sickle", type = "sickle", tier = 2, uses = 400, harvest = 3 },
    bronze_hoe             = { name = "Bronze hoe", type = "hoe", tier = 1, uses = 150, tills = true },
    iron_hoe               = { name = "Iron hoe", type = "hoe", tier = 2, uses = 600, tills = true },
}

-- Dig classes -----------------------------------------------------------------
--
-- Every block this mod has an opinion about has a CLASS; a dig begins only
-- if the tool in hand is one of the class's `types` and at least its
-- `tier`. `"hand"` in a class's types is a bare hand — or anything held that
-- does not dig — and `"any"` lets everything through. A block in no class
-- is diggable by anything, the engine's default, so another mod's blocks
-- keep working until somebody classifies them.
--
-- There is no stone tier, and the hand is refused rock: fire cracks it
-- (step 3), and a cracked block is `cracked`, which the hand and the maul
-- break. Granite is `rock`, not `hard_rock`: the slow, expensive stone of the
-- bronze age, and what the anvil is made of.

C.classes = {
    loose     = { types = { "any" }, tier = 0 },
    cracked   = { types = { "hand", "maul", "pick", "chisel" }, tier = 0 },
    wood      = { types = { "hand", "axe", "chisel" }, tier = 0, hint = "An axe would make short work of that." },
    hardwood  = { types = { "axe", "chisel" }, tier = 1 },
    rock      = { types = { "pick", "chisel" }, tier = 1 },
    hard_rock = { types = { "pick", "chisel" }, tier = 2 },
}

-- The world's blocks, by class. Plants, leaves and needles are in none: they
-- come away in anything.
C.classify = {
    loose = {
        "dirt", "packed_dirt", "grass", "mud", "black_mud", "dried_mud", "mulch", "gravel", "sand",
        "white_sand", "dark_sand", "wet_clay", "dry_clay", "charcoal", "volcanic_ash", "pumice",
        "cobbles", "snow", "permafrost", "ice", "clear_ice", "moss", "lichen", "mycelium",
        "mushroom_cap", "caul", "marrow", "sulfur", "bramble", "cactus", "dead_log", "dead_coral",
        "coral_magenta", "coral_cyan", "coral_amber", "barnacles", "pink_algae", "ocean_moss",
    },
    wood = {
        "oak_log", "birch_log", "fir_log", "willow_log", "kapok_log", "juniper_log", "apple_log",
        "cherry_log", "willow_planks", "kapok_planks",
    },
    hardwood = { "ironwood_log", "mangrove_log", "acacia_log", "redwood_log", "ironwood_planks" },
    rock = {
        "stone", "granite", "slate", "calcite", "dark_basalt", "rust_red_sandstone", "ochre_sandstone",
        "lava_rock", "dark_sediment", "light_sediment", "pale_terracotta", "flowstone", "black_marble",
        "bone", "salt", "flint", "copper_ore", "iron_ore", "coal", "tin_ore", "silver_ore", "lead_ore",
        "gold_ore", "pyrite",
    },
    hard_rock = {
        "morphic_rock", "scorch", "obsidian", "apex_stone", "metal", "crystal", "chromium_ore",
        "diamond", "orichalcum", "magma", "magma_crust", "hot_fiber_stone", "cold_fiber_stone",
    },
}

-- What a refused dig says, by class and by what was wrong: `hand` for a bare
-- hand, `type` for the wrong kind of tool, `tier` for the right kind too
-- soft. One sentence each, in the world's voice; they are the tutorial.
C.refusals = {
    cracked   = { type = "That wants a maul, or a pick." },
    wood      = { type = "That wants an axe." },
    hardwood  = { hand = "Too dense to break by hand. An axe would do it.", type = "That wants an axe." },
    rock      = { hand = "Bare hands will not move stone. Fire will crack it, or a bronze pick will break it.",
                  type = "That wants a pick." },
    hard_rock = { hand = "Bare hands will not move this. It wants an iron pick.",
                  type = "That wants a pick.",
                  tier = "The bronze skitters off. This stone wants iron." },
}
C.refusal = "That wants a better tool."

-- What wearing out says.
C.worn_out = "Your %s has worn to nothing."

-- A test harness may set `tdc_overrides` before the mod loads; a real
-- server never does.
for key, value in pairs(tdc_overrides or {}) do
    C[key] = value
end

return C
