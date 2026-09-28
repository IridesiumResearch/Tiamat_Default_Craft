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

-- A test harness may set `tdc_overrides` before the mod loads; a real
-- server never does.
for key, value in pairs(tdc_overrides or {}) do
    C[key] = value
end

return C
