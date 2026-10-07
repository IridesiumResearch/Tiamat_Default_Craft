-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Small helpers with no opinion about the game.

local U = {}

--- Units in one item of loose material: an item is a block's worth.
U.UNITS = 27

--- Whether `name` is a qualified id, `"mod:thing"`.
function U.qualified(name)
    return type(name) == "string" and #name <= 128 and string.match(name, "^[%a_][%w_]*:[%w_]+$") ~= nil
end

--- Whether `name` is a group, `"#thing"`.
function U.group(name)
    return type(name) == "string" and #name <= 64 and string.match(name, "^#[%w_]+$") ~= nil
end

--- A whole number in lo..hi as an integer, or nil. `20` and `20.0` alike.
function U.whole(n, lo, hi)
    local i = type(n) == "number" and math.tointeger(n) or nil
    if i and i >= lo and i <= hi then return i end
    return nil
end

--- A numeric material id for a qualified block or item id, or nil when nothing
--- registered it. `game.get_block_id` errors on an unknown id, which is right
--- for a typo in this mod's own names and wrong for a block another mod may or
--- may not have registered.
function U.material(id)
    if not U.qualified(id) then return nil end
    local ok, material = pcall(game.get_block_id, id)
    if ok then return material end
    return nil
end

--- A world block's qualified id, from its short name.
function U.world(name)
    return tdc.config.world .. ":" .. name
end

--- A sorted copy of a table's keys.
function U.sorted_keys(t)
    local keys = {}
    for key in pairs(t) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

--- A deep copy of plain data: tables, strings, numbers, booleans.
function U.copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = U.copy(v) end
    return out
end

-- A flat record as one storage string: "key=value;key=value". Values are
-- integers or strings without `;` or `=`; keys come out sorted, so the same
-- record is always the same string.
function U.encode(record)
    local parts = {}
    for _, key in ipairs(U.sorted_keys(record)) do
        local value = record[key]
        if math.type(value) == "integer" then
            value = string.format("%d", value)
        end
        parts[#parts + 1] = key .. "=" .. tostring(value)
    end
    return table.concat(parts, ";")
end

function U.decode(text)
    local record = {}
    if type(text) ~= "string" then return record end
    for key, value in string.gmatch(text, "([%w_]+)=([^;]*)") do
        record[key] = math.tointeger(tonumber(value)) or value
    end
    return record
end

--- A whole number kept in `game.storage`, as an integer: storage hands a
--- number back as a float, and a float in a string reads "6.0".
function U.stored_int(key)
    local value = game.storage.get(key)
    return type(value) == "number" and math.tointeger(value) or 0
end

--- Gives a player a stack, and answers how many units did not go in.
---
--- An inventory grew for ever once; a mod may now fix the size of a
--- player's main view (Tiamat Default UI does), and then a full pack leaves
--- units over. What is left over is put on the ground at the player's feet
--- through Life's `drop` when Life is here, where its pickup finds it, and
--- is logged otherwise: nothing is destroyed quietly (charter rule 5).
function U.give(uuid, spec)
    local gave, left = game.give(uuid, spec)
    left = math.tointeger(left) or 0
    if gave or left <= 0 then return 0 end
    local over = { material = spec.material, units = left, shape = spec.shape, detail = spec.detail }
    local life = game.exports("tiamat_default_life")
    local id = game.player_entity(uuid)
    local body = id and game.entity(id)
    if life and life.drop and body and life.drop(body.pos, over, { owner = uuid }) then
        return 0
    end
    game.log(string.format("tiamat_default_craft: %d units of %s had no room in %s's pack",
        left, tostring(spec.material), tostring(uuid)))
    return left
end

--- What a block read by `game.get_block` IS, by qualified name, or nil. A
--- model block (a campfire) may stand in a thin floor and share its block
--- with the floor's cells (Sub-Node Contract §7.6): such a block reads as
--- mixed, `material` nil and `cells` listed, and it is the one of `whole`'s
--- names among its cells — or, with no `whole`, the one of this mod's.
function U.name_at(at, whole)
    if at == nil then return nil end
    if at.material then return game.block_of(at.material) end
    local own = game.mod_id .. ":"
    for _, cell in ipairs(at.cells or {}) do
        local name = cell ~= 0 and game.block_of(cell) or nil
        if name and (whole and whole[name] or (not whole and string.sub(name, 1, #own) == own)) then
            return name
        end
    end
    return nil
end

--- A block position as a key: "x,y,z".
function U.key(x, y, z)
    return x .. "," .. y .. "," .. z
end

--- The short name of a qualified id or a group, spaces for underscores.
function U.friendly(id)
    return (string.gsub(string.match(id, ":([^:]+)$") or string.match(id, "^#(.+)$") or id, "_", " "))
end

--- The same, with a capital: a name for a screen.
function U.title(id)
    local name = U.friendly(id)
    return string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2)
end

return U
