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
    -- Planks: this mod's own, one for every tree, and the world's three.
    ["#plank"] = { "willow_planks", "kapok_planks", "ironwood_planks" },
    -- What catches a spark: dry grass, needles, moss.
    ["#tinder"] = {
        "tall_grass", "dead_sagebrush", "fir_needles", "juniper_needles", "redwood_needles", "moss",
        "lichen", "heather",
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
    fire_striker           = { name = "Fire striker", type = "striker", tier = 0, uses = 20 },
    -- Kiln tools, found in its tool slot: a crucible holds a melt and comes
    -- back; a mould is cast into four times and cracks.
    crucible               = { name = "Crucible", type = "crucible", tier = 1, uses = 0 },
    -- The bloomery's: in its tool slot, it makes charcoal burn white.
    bellows                = { name = "Bellows", type = "bellows", tier = 1, uses = 0 },

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

-- The world's blocks are classed by their own tags (World's sibling ask W2,
-- engine ask 6): `stone` is rock, `hard` is hard rock, `ore` is rock, `log`
-- and `plank` wood, `hardwood` hardwood, `soil` and `sand` loose — the words
-- in `C.tag_classes` below, the first a block lists that this mod knows. A
-- block no word classes is diggable by anything, which is what loose means.
-- These are the exceptions, where this mod reads a block otherwise than its
-- tags would.
C.classify = {
    -- Flint breaks out of its bed by hand: it is what the first fire is
    -- struck with, and fire is how the hand gets past rock at all.
    cracked = { "flint" },
    -- Bone is as hard as stone to cut.
    rock = { "bone" },
    -- A dead log is punky, and marrow is spongy: the hand has them.
    loose = { "dead_log", "marrow" },
}

-- The world's loose ground, by name, for the one thing tags cannot yet do:
-- a tool's slower speed on it is registered at load, and the API reads a
-- block's tags but cannot list the blocks carrying a tag (engine ask 11).
C.soft_ground = {
        "dirt", "packed_dirt", "grass", "mud", "black_mud", "dried_mud", "mulch", "gravel", "sand",
        "white_sand", "dark_sand", "wet_clay", "dry_clay", "charcoal", "volcanic_ash", "pumice",
        "cobbles", "snow", "permafrost", "ice", "clear_ice", "moss", "lichen", "mycelium",
        "mushroom_cap", "caul", "marrow", "sulfur", "bramble", "cactus", "dead_log", "dead_coral",
        "coral_magenta", "coral_cyan", "coral_amber", "barnacles", "pink_algae", "ocean_moss",
    }

-- How fast a tool digs a class of block, as a share of its own speed
-- (engine ask 2). A class a type does not list digs at the tool's speed;
-- a class it may not break at all is refused before speed matters. A pick
-- or an axe is a poor spade.
C.speed_shares = {
    pick = { loose = 0.5 },
    axe = { loose = 0.5 },
    maul = { loose = 0.6 },
    chisel = { loose = 0.5 },
}

-- A block this mod has not classed, and that says what it is in its tags
-- (engine ask 6), is classed by them: a class's own name, or these.
C.tag_classes = {
    loose = "loose", soil = "loose", sand = "loose", plant = "loose",
    cracked = "cracked",
    wood = "wood", log = "wood", plank = "wood",
    hardwood = "hardwood",
    rock = "rock", stone = "rock", ore = "rock",
    hard_rock = "hard_rock", hard = "hard_rock",
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

-- How many slots of a player's pack are looked through for the tool being
-- worn: the hotbar first, then the pack and the off-hand. A pack grows when
-- nothing fixes its size, so the ceiling is generous; the scan stops at the
-- tool, which is almost always in the hotbar.
C.slot_scan = 128

-- What wearing out says.
C.worn_out = "Your %s has worn to nothing."

-- Stations ---------------------------------------------------------------------

C.chest_slots = 27

-- Furnaces ---------------------------------------------------------------------
--
-- A station that burns (the kiln; the bloomery; another mod's alembic) is
-- lit with a striker once fuel is in it, burns its fuel 27 units at a time,
-- and while it burns makes whatever its contents and its heat allow. HEAT is
-- a tier: 1 is red (wood), 2 orange (coal, charcoal), 3 white (charcoal
-- blown with bellows, step 8).

C.furnace_step = 20             -- furnaces are tended once a second

-- The kiln's container: fuel, two inputs (copper and tin go in together),
-- the crucible or mould, the output.
C.kiln_slots = { fuel = 1, input = { 2, 3 }, tool = 4, output = 5 }

-- What burns, how hot, and for how many ticks per 27 units. Names are
-- this mod's, the world's (`world:`) or groups.
C.fuels = {
    { "#log", 1, 800 },
    { "#plank", 1, 800 },
    { "stick", 1, 800 },
    { "world:coal", 2, 1800 },
    { "charcoal", 2, 1200 },
}

-- What a kiln says of something it will not fire.
C.kiln_refusals = {
    iron_ore = "The ore glows and does nothing. Iron wants a bloomery.",
    chromium_ore = "Nothing you have burns hot enough.",
}
C.kiln_idle = "Nothing to be made of that here."

-- The bloomery: charcoal only, and white heat with bellows in it.
C.bloomery_slots = { fuel = 1, input = { 2, 3 }, tool = 4, output = 5 }
C.bloom_ticks = 120 * 20
C.coal_spoils = "Coal's sulphur spoils the bloom. It wants charcoal."

-- The anvil: blows to beat a bloom into a bar, and a bar into a head. With
-- nothing on it, a blow works what is in the off-hand, this slot of the
-- player's pack.
C.offhand_slot = 28
C.strikes_bar = 3
C.strikes_head = 5
C.strikes_first_hammer = 8

-- Casting: bronze ingots a head takes, and the tools a head makes.
C.heads = {
    pick = 3, axe = 3, spade = 3, hammer = 2, sickle = 2, hoe = 2, chisel = 1, knife = 1,
}
C.mould_uses = 4                -- pours before a mould cracks

-- The sluice ------------------------------------------------------------------

C.wash_ticks = 10 * 20          -- a block of gravel washed every ten seconds
C.gold_every = 9                -- and every ninth wash leaves a flake of gold
C.sluice_dry = "A sluice needs running water."

-- The torch: a light a player carries underground, which burns out (a
-- random tick, about twenty minutes a block) and leaves a spent torch.
C.torch_light = { r = 14, g = 10, b = 4 }

-- The HUD is told what is in the hand and what it points at this often.
C.hud_ticks = 5

-- Cooking ----------------------------------------------------------------------

C.char_ticks = 60 * 20          -- cooked meat left over a fire this long chars

-- Fire -------------------------------------------------------------------------
--
-- A campfire is built unlit and struck alight with a flint striker. It burns
-- its fuel down and goes out; logs thrown on keep it going. A burning fire
-- heats the rock beside it, and after long enough the rock cracks: that is
-- how bare hands get at stone before any pick exists (brief §4.4).

C.fire_fuel = 20 * 60 * 20       -- ticks a newly lit fire burns: twenty minutes
C.fire_max_fuel = 60 * 60 * 20   -- no fire holds more than an hour
C.fire_step = 20                 -- fires are looked after once a second
C.fireset_ticks = 30 * 20        -- burning this long cracks the rock beside it

-- What a fire may be fed, ticks per 27 units.
C.campfire_fuel = {
    ["#log"] = 5 * 60 * 20,
}

-- What fire cracks, into what. A cracked block is class `cracked`, breaks by
-- hand or maul, and drops the block it was, whole: cracked copper ore yields
-- exactly what a pick would. Not granite, and nothing hard: that is what
-- bronze and iron are for.
C.cracks = { "stone", "slate", "calcite", "dark_basalt", "copper_ore", "iron_ore", "coal" }
C.cracked_hardness = 0.6

-- A test harness may set `tdc_overrides` before the mod loads; a real
-- server never does.
for key, value in pairs(tdc_overrides or {}) do
    C[key] = value
end

return C
