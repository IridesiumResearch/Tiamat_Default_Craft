-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Stations run by another mod's say-so: `register_station{ runs = fn }`
-- (Science's C-S1). A frame turned by a water wheel is a station whose
-- recipes are nobody's to press; the mod that knows whether the wheel turns
-- answers `runs(container)` with a speed in per cent, and this file keeps
-- the job, counts the ticks and makes the recipe, as furnace.lua does for a
-- fire. So the other mod writes no job loop of its own.
--
-- # The callback
--
-- It is the registering mod's and faults on that mod (the engine's rule for
-- a function passed across an export): a fault answers nil here, which is
-- stopped. Anything but a whole number above 0 is stopped too, and a speed
-- is capped at `C.max_run_percent`.
--
-- # State
--
-- One storage string per container, `run:<container>`: the job and its
-- progress, rewritten when either changes. A station in a chunk that is not
-- loaded is not asked and does not advance. Recipes are made for whoever
-- placed the station, unattended: tools come out of its own slots only.

local C = tdc.config
local U = tdc.util
local R = tdc.registry
local ST = tdc.stations

local RU = {}

local states = {}   -- container -> { job, progress, speed }

local function state(name)
    local s = states[name]
    if s then return s end
    s = U.decode(game.storage.get("run:" .. name))
    s.progress = math.type(s.progress) == "integer" and s.progress or 0
    if type(s.job) ~= "string" or s.job == "" or not R.recipe(s.job) then s.job, s.progress = nil, 0 end
    s.speed = 0
    states[name] = s
    return s
end

local function save(name)
    local s = states[name]
    game.storage.set("run:" .. name, U.encode{ job = s.job or "", progress = s.progress })
end

--- What the callback says, as a whole per cent: 0 is stopped.
local function speed_of(station, name)
    local ok, speed = pcall(station.runs, name)
    if not ok then return 0 end
    if math.type(speed) ~= "integer" or speed <= 0 then return 0 end
    return math.min(speed, C.max_run_percent)
end

--- What the station would make now, by recipe id, or nil.
local function choose(station, name, s, by)
    local opts = { container = name, unattended = true }
    if s.job and R.check(by, s.job, opts) then return s.job end
    for _, recipe in ipairs(R.list_particular(station.id)) do
        if R.check(by, recipe.id, opts) then return recipe.id end
    end
    return nil
end

--- One step of a running station's life.
local function tend(station, placed, step)
    local name = placed.name
    local s = state(name)
    if game.get_block(placed.pos) == nil then return end   -- not loaded: paused
    local was, speed = s.speed, speed_of(station, name)
    s.speed = speed
    local job = speed > 0 and choose(station, name, s, placed.by) or s.job
    if job ~= s.job then
        s.job, s.progress = job, 0
        save(name)
    end
    if speed > 0 and job then
        s.progress = s.progress + step * speed // 100
        if s.progress >= R.ticks(placed.by, R.recipe(job)) then
            s.progress = 0
            R.perform(placed.by, job, { container = name, unattended = true })
        end
        save(name)
        ST.redraw(name)
    elseif was ~= speed then
        ST.redraw(name)
    end
end

local elapsed = 0
local run_stations = nil   -- built on the first tick: every mod has registered

tdc.on_tick(function(dt)
    elapsed = elapsed + dt
    if elapsed < C.furnace_step then return end
    local step = elapsed
    elapsed = 0
    if not run_stations then
        run_stations = {}
        for _, id in ipairs(R.station_ids()) do
            local station = R.station(id)
            if station.runs and station.block then run_stations[#run_stations + 1] = station end
        end
    end
    for _, station in ipairs(run_stations) do
        for _, placed in ipairs(ST.indexed(station.id)) do
            tend(station, placed, step)
        end
    end
end)

--- Adds `ticks` to the job a running station has in hand: `true`, or false
--- when it has none. The next step makes it if that is enough.
function RU.add_progress(name, ticks)
    local s = (states[name] or game.storage.get("run:" .. name)) and state(name)
    if not (s and s.job) then return false end
    s.progress = s.progress + ticks
    save(name)
    return true
end

--- What a running station's screen shows: its speed and its job.
function RU.status(name)
    local s = state(name)
    local status = { burn = math.min(1000, s.speed * 10), progress = 0,
        heat_text = s.speed > 0 and ("Running at " .. s.speed .. "%") or "Stopped", job_text = "Idle" }
    if s.job then
        local recipe = R.recipe(s.job)
        local placer = game.storage.get("placer:" .. name)
        status.job_text = recipe.name
        status.progress = math.min(1000, (s.progress * 1000) // R.ticks(type(placer) == "string" and placer or nil, recipe))
    elseif s.speed == 0 then
        status.note = "It is not running."
    end
    return status
end

return RU
