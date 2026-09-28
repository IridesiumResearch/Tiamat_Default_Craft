-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- The craft HUD: five pips beside the hotbar for how much is left of the
-- tool in hand, and a red bar under the crosshair when that tool cannot
-- break what it is pointed at — the refusal seen before the click rather
-- than heard after it.
--
-- This runs on the PLAYER's machine, once a frame, in the HUD sandbox.
-- Everything it knows arrives in `state.values`, sent by tools.lua with
-- `game.set_hud`: `wear` (per mille of the tool left, or -1 for nothing
-- that wears) and `warn`. It draws and does not compute.

local HALF_WIDTH = 351        -- the hotbar's half width: the pips stand past its right end
local PIP = 9
local PITCH = 12
local ROW_Y = 66              -- the pips' top, from the bottom of the screen

local FULL = { 214, 180, 96, 255 }
local LOW = { 226, 92, 64, 255 }
local EMPTY = { 70, 64, 58, 200 }
local WARN = { 226, 64, 48, 230 }

hud.on_draw(function(state)
    local values = state.values or {}
    local wear = values.wear
    if type(wear) == "number" and wear >= 0 then
        local lit = (wear + 199) // 200
        for i = 1, 5 do
            local colour = EMPTY
            if i <= lit then colour = lit <= 1 and LOW or FULL end
            hud.rect{ anchor = "bottom", x = HALF_WIDTH + 14 + (i - 1) * PITCH, y = ROW_Y, w = PIP, h = PIP,
                colour = colour }
        end
    end
    if values.warn == true then
        hud.rect{ anchor = "centre", x = -12, y = 14, w = 24, h = 3, colour = WARN }
    end
end)
