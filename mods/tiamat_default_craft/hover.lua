-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- What a thing is for, under its name when a player hovers it (engine ask
-- 16, `game.set_hover`): for every material they carry, every recipe it
-- goes into that they may make, the ones they have never made first —
-- R.uses_text, the line the `uses` chat word says.
--
-- It is a player's own (their research, what they have made), so it is
-- worked out per player, every C.hover_ticks, and sent only when it has
-- changed: one message when they pick something new up, make something
-- for the first time or learn a node, and none otherwise.

local C = tdc.config
local U = tdc.util
local R = tdc.registry

local HO = {}

local online = {}   -- uuid -> the lines last sent, as one string
local elapsed = 0

--- The lines for what a player carries: material id -> "Makes: ...".
function HO.lines(uuid)
    local lines, seen, n = {}, {}, 0
    for _, stack in ipairs(game.inventory(uuid) or {}) do
        local m = stack.material
        if m and not seen[m] and n < C.hover_most then
            seen[m] = true
            local line = R.uses_text(uuid, m, 256)
            if line then
                lines[m] = line
                n = n + 1
            end
        end
    end
    return lines
end

local function key_of(lines)
    local parts = {}
    for _, m in ipairs(U.sorted_keys(lines)) do parts[#parts + 1] = m .. "=" .. lines[m] end
    return table.concat(parts, "\n")
end

--- Sends a player their lines if they have changed.
function HO.refresh(uuid)
    if not game.set_hover then return end   -- an engine before protocol 90 has no hover lines
    local lines = HO.lines(uuid)
    local key = key_of(lines)
    if online[uuid] == key then return end
    if game.set_hover(uuid, next(lines) and lines or nil) then online[uuid] = key end
end

tdc.on_join(function(e)
    online[e.player] = false
    HO.refresh(e.player)
end)

tdc.on_leave(function(e)
    online[e.player] = nil
end)

tdc.on_tick(function(dt)
    elapsed = elapsed + dt
    if elapsed < C.hover_ticks then return end
    elapsed = 0
    for _, uuid in ipairs(U.sorted_keys(online)) do HO.refresh(uuid) end
end)

return HO
