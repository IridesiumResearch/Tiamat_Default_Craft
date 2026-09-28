-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- What the mod sounds like: four sounds, each bound to a cue of the same
-- name, and the cues raised where things happen.
--
-- The mod raises CUES, never sounds: a cue is an event with a name, and
-- whatever is bound to it plays. A sound pack re-skins this mod by binding
-- its own sounds to these cues, and a cue nobody bound is silence rather
-- than an error. The files are placeholders from tools/make_sounds.py.
--
-- `craft` is Tiamat Default UI's own crafting sound when that mod is here,
-- so making something at a bench sounds like making something in its
-- shape crafter.

local SD = {}

SD.CUES = { "tool_break", "anvil_ring", "sizzle", "craft" }

local GAIN = { tool_break = 0.9, anvil_ring = 0.8, sizzle = 0.6, craft = 0.7 }

local ui = game.exports("tiamat_default_ui")
for _, id in ipairs(SD.CUES) do
    game.register_sound{ id = id, file = "sounds/" .. id .. ".wav", gain = GAIN[id], pitch_variance = 0.08 }
    if id == "craft" and ui then
        game.bind_sound(id, "tiamat_default_ui:craft")
    else
        game.bind_sound(id, id)
    end
end

--- Raises a cue at a place.
function SD.at(cue, pos, radius)
    game.cue{ cue = cue, pos = { x = pos.x + 0.5, y = pos.y + 0.5, z = pos.z + 0.5 }, radius = radius or 16 }
end

--- Raises a cue where a player stands.
function SD.at_player(cue, uuid)
    local id = uuid and game.player_entity(uuid)
    local body = id and game.entity(id)
    if body then
        game.cue{ cue = cue, pos = body.pos, radius = 16 }
    end
end

return SD
