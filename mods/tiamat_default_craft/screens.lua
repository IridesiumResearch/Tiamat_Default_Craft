-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Dialog trees: a station's screen, the chest's, and the list of recipes
-- both a station and the Craft tab show.
--
-- Built from the engine's own widgets. When Tiamat Default UI is here its
-- fonts and colours are borrowed (copied out of its `theme`, which is plain
-- data), so a station reads as part of the same interface; its builders are
-- not used, because what they answer is a read-only view that cannot be
-- sent inside another mod's tree.
--
-- A sheet's body is about 530 by 260. A grid's recipes are a scrolling
-- list beside it, each saying on hover what it takes; other stations' lists
-- are paged, eight to a page.

local R = tdc.registry
local U = tdc.util

local S = {}

S.PAGE = 8

local ui = game.exports("tiamat_default_ui")
if not (ui and ui.version == 1) then ui = nil end
S.ui = ui

local font, text_font, ink, muted
if ui and ui.theme then
    font = type(ui.theme.font) == "string" and ui.theme.font or nil
    text_font = type(ui.theme.text_font) == "string" and ui.theme.text_font or nil
    local colours = ui.theme.colours
    local function colour(c)
        if type(c) ~= "table" then return nil end
        local out = {}
        for i = 1, 4 do
            if type(c[i]) == "number" then out[i] = c[i] end
        end
        return #out >= 3 and out or nil
    end
    if type(colours) == "table" then
        ink, muted = colour(colours.ink), colour(colours.muted)
    end
end
muted = muted or { 150, 140, 125 }

function S.label(text, heading)
    local style = {}
    if heading and font then style.font = font elseif text_font then style.font = text_font end
    if ink then style.text_colour = ink end
    return { type = "label", text = text, style = next(style) and style or nil }
end

function S.hint(text)
    local style = { text_colour = muted }
    if text_font then style.font = text_font end
    return { type = "label", text = text, style = style }
end

function S.button(name, text, dim)
    local style = {}
    if font then style.font = font end
    if dim then style.text_colour = muted end
    return { type = "button", name = name, text = text, style = next(style) and style or nil }
end

function S.box(direction, children, gap)
    return { type = "container", direction = direction, gap = gap or 6, children = children }
end

function S.grid(view, first, count, columns)
    return { type = "item_grid", view = view, first = first, count = count, columns = columns }
end

--- A recipe as one line: "Sticks x4".
function S.recipe_text(recipe)
    local out = recipe.outputs[1]
    if not out then return recipe.name end
    local n = out.units // U.UNITS
    local text = recipe.name
    if n > 1 then text = text .. " x" .. n end
    return text
end

--- An amount of units as a player reads it: "3", or "1/3" of an item.
local function amount(units)
    local n, rest = units // U.UNITS, units % U.UNITS
    if rest == 0 then return tostring(n) end
    local part = rest == 9 and "1/3" or rest == 18 and "2/3" or (rest .. "/27")
    return n == 0 and part or (n .. " " .. part)
end

local function thing(name)
    if U.group(name) then return "any " .. U.friendly(name) end
    return U.friendly(name)
end

--- What a recipe takes and makes, for its button's hover: the grid laid
--- out and what each letter is, or a list. At most 256 bytes, the engine's
--- cap: the layout is dropped first, then the end cut.
function S.recipe_tip(recipe)
    local out = recipe.outputs[1]
    local head = out and ("Makes " .. amount(out.units) .. " " .. U.friendly(out.name) .. ".") or "Makes nothing."
    local lines = { head }
    local layout = {}
    if recipe.pattern then
        local p = recipe.pattern
        for r = 1, p.height do
            local row = {}
            for c = 1, p.width do row[c] = p.cells[r][c] or "." end
            layout[#layout + 1] = table.concat(row, " ")
        end
        for _, ch in ipairs(U.sorted_keys(p.keys)) do
            local k = p.keys[ch]
            if k.tool then
                lines[#lines + 1] = ch .. ": " .. thing(k.name) .. " (kept)"
            else
                local n = k.glyph and tostring(k.count) or amount(k.units)
                lines[#lines + 1] = ch .. ": " .. (n ~= "1" and (n .. " ") or "") .. thing(k.name)
                    .. (k.glyph and (" carved as " .. U.friendly(k.glyph)) or "")
            end
        end
    else
        for _, e in ipairs(recipe.inputs) do
            local n = e.glyph and tostring(e.count) or amount(e.units)
            lines[#lines + 1] = n .. " " .. thing(e.name) .. (e.glyph and (" carved as " .. U.friendly(e.glyph)) or "")
        end
    end
    for _, t in ipairs(recipe.tools) do
        if not t.cell then lines[#lines + 1] = "With " .. thing(t.name) .. " (kept)" end
    end
    local full = table.concat(lines, "\n")
    if #layout > 0 then
        local with = lines[1] .. "\n" .. table.concat(layout, "\n") .. "\n" .. table.concat(lines, "\n", 2)
        if #with <= 256 then return with end
    end
    if #full <= 256 then return full end
    return string.sub(full, 1, 253) .. "..."
end

--- Every recipe of `ids` as a button, `r<n>`, in a list that scrolls, each
--- with its hover. One that cannot be made from the pack now is dim, and
--- pressing it does nothing.
function S.recipe_panel(player, ids, width, height)
    local children = {}
    for i, id in ipairs(ids) do
        local recipe = R.recipe(id)
        local button = S.button("r" .. i, S.recipe_text(recipe), not R.check(player, id, { pack = true }))
        button.tooltip = S.recipe_tip(recipe)
        children[#children + 1] = button
    end
    if #ids == 0 then children[1] = S.hint("Nothing is made here yet.") end
    return { type = "scroll", size = width, cross_size = height, children = children }
end

--- The recipe buttons of one page, `r<n>` by index into `ids`, and the page
--- buttons. Recipes that cannot be made now are drawn dim, and say why when
--- pressed.
function S.recipe_list(player, ids, page, container, per)
    per = per or S.PAGE
    local pages = math.max(1, (#ids + per - 1) // per)
    page = math.max(1, math.min(page or 1, pages))
    local children = {}
    for i = (page - 1) * per + 1, math.min(#ids, page * per) do
        local recipe = R.recipe(ids[i])
        local ok = R.check(player, ids[i], container)
        local button = S.button("r" .. i, S.recipe_text(recipe), not ok)
        button.tooltip = S.recipe_tip(recipe)
        children[#children + 1] = button
    end
    if #ids == 0 then
        children[#children + 1] = S.hint("Nothing is made here yet.")
    end
    if pages > 1 then
        children[#children + 1] = S.box("row", {
            S.button("prev", "<", page == 1),
            S.hint(page .. " / " .. pages),
            S.button("next", ">", page == pages),
        })
    end
    return S.box("column", children, 4), page
end

--- A crafting station's screen: its input grid, its output, its recipes,
--- and the player's own inventory below.
--- A bar, `permille` full, labelled.
function S.bar(text, permille)
    return S.box("row", { S.hint(text), { type = "progress", permille = math.max(0, math.min(1000, permille)) } }, 6)
end

function S.station(player, station, container, ids, page, note, status)
    local list
    list, page = S.recipe_list(player, ids, page, container)
    local input = station.slots.input
    local output = station.slots.output
    local left = { S.label(station.name, true),
        S.grid(container, input[1], #input, math.min(3, #input)) }
    local middle = { S.label("Makes"), S.grid(container, output[1], #output, 1) }
    if station.slots.tool then
        middle[#middle + 1] = S.label("Tool")
        middle[#middle + 1] = S.grid(container, station.slots.tool[1], #station.slots.tool, 1)
    end
    if station.slots.fuel then
        middle[#middle + 1] = S.label("Fuel")
        middle[#middle + 1] = S.grid(container, station.slots.fuel[1], #station.slots.fuel, 1)
    end
    if status then
        middle[#middle + 1] = S.bar(status.heat_text, status.burn)
        middle[#middle + 1] = S.bar(status.job_text, status.progress)
        note = note or status.note
    end
    local tree = S.box("column", {
        S.box("row", { S.box("column", left), S.box("column", middle), list }, 16),
        S.hint(note or ""),
        S.label("Yours"),
        S.grid("player:main", 1, 27, 9),
    }, 6)
    tree.padding = 8
    return tree, page
end

--- A grid and what it makes: the grid `n` by `n` from slot `first`, then
--- the output slot.
local function grid_and_output(container, first, n, output)
    return S.box("row", { S.grid(container, first, n * n, n), S.label(">"), S.grid(container, output, 1, 1) }, 10)
end

--- A grid station's screen (the workbench): its recipes down the left, to
--- make at once from the pack; the grid and what it makes; the pack.
function S.grid_station(player, station, container, ids, note)
    local work = S.box("column", {
        S.label(station.name, true),
        grid_and_output(container, station.slots.input[1], station.grid, station.slots.output[1]),
        S.hint(note or "Take what it makes."),
    }, 8)
    local tree = S.box("column", {
        S.box("row", { S.recipe_panel(player, ids, 230, 170), work }, 16),
        S.label("Yours"),
        S.grid("player:main", 1, 27, 9),
    }, 6)
    tree.padding = 8
    return tree
end

--- The chest's screen.
function S.chest(container, size)
    local tree = S.box("column", {
        S.label("Chest", true),
        S.grid(container, 1, size, 9),
        S.label("Yours"),
        S.grid("player:main", 1, 27, 9),
    }, 8)
    tree.padding = 8
    return tree
end

--- By hand, as a tab body or a dialog: the recipes, the two by two and
--- what it makes, and the pack.
function S.hand(player, ids, container, note)
    local work = S.box("column", {
        S.label("By hand", true),
        grid_and_output(container, 1, 2, 5),
        S.hint(note or ""),
    }, 6)
    return S.box("column", {
        S.box("row", { S.recipe_panel(player, ids, 200, 120), work }, 12),
        S.grid("player:main", 1, 27, 9),
    }, 6)
end

return S
