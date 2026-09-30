-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Tiamat Default Craft: the crafting layer. This file only decides load order.
--
-- Every file below is loaded exactly once and hangs what it exports off the
-- `tdc` global, which the sandbox shares between a mod's own files. The
-- engine's `require` is confined to this directory and does not cache, so a
-- file required twice would run twice; nothing but this file calls it.
--
-- Order matters: config, helpers and the hook fan-out first (everything
-- subscribes to them), then the registry every recipe and station goes
-- through, then what registers into it, then the export, which has to be
-- built whole before the registration window closes.

tdc = {}

-- The host reports a failed load as "errored in init.lua" and nothing more,
-- so say which file and what the error was before letting it through.
local function load(name)
    local ok, result = pcall(require, name)
    if not ok then
        game.log(string.format("tiamat_default_craft: %s.lua failed: %s", name, tostring(result)))
        error(result, 0)
    end
    return result
end

tdc.config = load("config")
tdc.util = load("util")
load("hooks")                     -- one engine registration per hook, many subscribers
tdc.sounds = load("sounds")       -- four sounds, each bound to a cue of its name
tdc.registry = load("registry")   -- recipes, groups, stations, fuels, the gate, perform
tdc.materials = load("materials") -- the items and blocks this mod registers
tdc.tools = load("tools")         -- the hand, tools, dig classes, wear
tdc.fire = load("fire")           -- campfires: lighting, fuel, burning out, fire-setting
load("recipes")                   -- this mod's own stations and recipes, into the registry
tdc.screens = load("screens")     -- dialog trees, in Tiamat Default UI's look when present
tdc.stations = load("stations")   -- stations and chests in the world; the Craft tab
tdc.furnace = load("furnace")     -- stations that burn: heat, fuel, jobs
tdc.runs = load("runs")           -- stations another mod says are running
tdc.cooking = load("cooking")     -- what a campfire cooks
tdc.sluice = load("sluice")       -- tin washed out of river gravel
tdc.anvil = load("anvil")         -- iron worked by blows
load("commands")                  -- chat words: listing and crafting by hand

-- The HUD: wear pips beside the hotbar and a red bar under the crosshair
-- when the tool in hand cannot break what it points at. The pips sit
-- inside the interface's own reserve, so this asks for none of its own.
game.register_hud_script{ file = "hud.lua", reserve = 0 }

-- What other mods may call. One export per mod, built whole first.
game.export(load("exports"))

game.log(string.format("tiamat_default_craft ready: %d recipes at %d stations",
    tdc.registry.count(), tdc.registry.station_count()))
