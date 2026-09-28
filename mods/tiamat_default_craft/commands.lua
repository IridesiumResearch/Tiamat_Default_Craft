-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Chat words.
--
-- `recipes` and `craft` are for anyone, and they are no shortcut: they list
-- and make the recipes a player could make by hand from what they already
-- carry, through the same `perform` the Craft tab calls. A sentence that only
-- starts with one of them ("craft is fun") is let through to chat.

local R = tdc.registry

--- A recipe id as a player types it: this mod's own may be short.
local function recipe_id(word)
    if R.recipe(word) then return word end
    local own = game.mod_id .. ":" .. word
    if R.recipe(own) then return own end
    return nil
end

tdc.on_chat("recipes", function(player, rest)
    local station = rest ~= "" and rest or "hand"
    if not R.station(station) then return false end
    local ready, lacking = {}, {}
    for _, recipe in ipairs(R.list(station)) do
        local short = string.gsub(recipe.id, "^" .. game.mod_id .. ":", "")
        if R.check(player, recipe.id, nil) then
            ready[#ready + 1] = short
        else
            lacking[#lacking + 1] = short
        end
    end
    game.chat_to(player, "ready: " .. (#ready > 0 and table.concat(ready, ", ") or "nothing"))
    if #lacking > 0 then
        game.chat_to(player, "lacking something: " .. table.concat(lacking, ", "))
    end
end)

tdc.on_chat("craft", function(player, rest)
    local word, times = string.match(rest, "^(%S+)%s*(%d*)$")
    local id = word and recipe_id(word)
    if not id then return false end
    local recipe = R.recipe(id)
    if recipe.station ~= "hand" then
        game.chat_to(player, recipe.name .. " is made at the " .. R.station(recipe.station).name)
        return
    end
    local n = math.min(tonumber(times) or 1, 64)
    local made = 0
    local why
    for _ = 1, n do
        local ok, reason = R.perform(player, id, nil)
        if not ok then why = reason break end
        made = made + 1
    end
    if made > 0 then
        game.chat_to(player, string.format("made %s x%d", recipe.name, made))
    end
    if why then
        game.chat_to(player, "cannot make " .. recipe.name .. ": " .. why)
    end
end)

return {}
