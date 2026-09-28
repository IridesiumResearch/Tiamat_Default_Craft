// SPDX-FileCopyrightText: Iridesium
// SPDX-License-Identifier: GPL-3.0-only
//
// The mod, run for real: the engine's script VM with a fake server around it
// (rig.rs), and small fixture mods that use its exports the way the progress,
// magic and tech mods will — including the calls they must be refused.

// The rig carries fakes the later steps use; not every one is read yet.
#[allow(dead_code)]
mod rig;

use rig::{MOD, OTHER, PLAYER, Rig, Setup, hex};
use tiamat_core::script::{ChatEvent, ScriptVm};

/// A stand-in for the progress mod: it owns the gate, and counts what the
/// registry tells it.
const PROGRESS: &str = r##"
local craft = game.exports("tiamat_default_craft")
assert(craft and craft.version == 1, "craft exports version 1")
assert(craft.set_gate("not a function") == nil)
assert(craft.set_gate(function(uuid, node) return node ~= "magic.locked" end) == true)
local crafted, firsts = 0, {}
assert(craft.on_crafted(function(uuid, id, outputs) crafted = crafted + 1 end) == true)
assert(craft.on_first(function(uuid, event) firsts[#firsts + 1] = event end) == true)
assert(craft.on_first("nope") == nil)
game.register_on_chat(function(e)
    if e.text ~= "p tally" then return end
    table.sort(firsts)
    game.chat_to(e.player, crafted .. " " .. table.concat(firsts, " "))
    return false
end)
"##;

/// A stand-in for the magic mod: its own station and recipes, a log of its
/// own in `#log`, and every malformed call refused rather than raised.
const MAGIC: &str = r##"
for _, id in ipairs({ "herb", "elixir", "flask", "tea" }) do game.register_item{ id = id } end
game.register_block{ id = "dreamwood" }
local craft = game.exports("tiamat_default_craft")
assert(craft and craft.version == 1)

local herb = { { "schism_magic:herb" } }
local tea = { { "schism_magic:tea" } }
local function refused(spec, want)
    local ok, why = craft.register(spec)
    assert(ok == nil and type(why) == "string", "refused: " .. tostring(spec and spec.id))
    if want then assert(string.find(why, want, 1, true), why) end
end
refused({ id = "elixir", station = "hand", inputs = herb, outputs = tea }, "qualified")
refused({ id = "schism_magic:x", station = "nowhere", inputs = herb, outputs = tea }, "no station")
refused({ id = "schism_magic:x", station = "hand", inputs = {}, outputs = tea }, "inputs")
refused({ id = "schism_magic:x", station = "hand", inputs = { { "schism_magic:herb", count = 0 } }, outputs = tea }, "whole number")
refused({ id = "schism_magic:x", station = "hand", inputs = { { "herb" } }, outputs = tea }, "qualified")
refused({ id = "schism_magic:x", station = "hand", heat = 2, inputs = herb, outputs = tea }, "no heat")
refused({ id = "schism_magic:x", station = "hand", inputs = herb, outputs = { { "#log" } } }, "qualified")
refused({ id = "schism_magic:x", station = "hand", conserve = true,
    inputs = { { "schism_magic:herb", count = 2 } }, outputs = tea }, "conserves")
assert(craft.register("nonsense") == nil)
assert(craft.register_station{ id = "schism_magic:bad", slots = { input = 1 } } == nil)
assert(craft.register_station{ id = "schism_magic:bad", slots = { input = 1, output = 2, sideways = 3 } } == nil)
assert(craft.register_station{ id = "schism_magic:bad" } == nil)
assert(craft.register_station{ id = "hand", inventory = true } == nil)
assert(craft.register_station{ id = "schism_magic:alembic", name = "Alembic",
    slots = { input = { 1, 2 }, tool = 3, output = 4 }, heat = true } == true)
assert(craft.register_group("#log", { "schism_magic:dreamwood" }) == true)
assert(craft.register_group("log", { "schism_magic:dreamwood" }) == nil)
assert(craft.register_group("#log", { "dreamwood" }) == nil)
assert(craft.register_fuel("schism_magic:dreamwood", 1, 800) == true)
assert(craft.register_fuel("schism_magic:dreamwood", 99, 800) == nil)

assert(craft.register{ id = "schism_magic:tea", station = "hand",
    inputs = { { "schism_magic:herb", count = 2 } }, outputs = tea } == true)
refused({ id = "schism_magic:tea", station = "hand", inputs = herb, outputs = tea }, "already")
assert(craft.register{ id = "schism_magic:elixir", station = "schism_magic:alembic",
    inputs = { { "schism_magic:herb", count = 3 }, { "#log", units = 27 } },
    tools = { "schism_magic:flask" }, ticks = 100,
    outputs = { { "schism_magic:elixir", count = 2 } }, first = "brew:elixir" } == true)
assert(craft.register{ id = "schism_magic:secret", station = "hand", requires = "magic.locked",
    inputs = herb, outputs = tea } == true)
assert(craft.register{ id = "schism_magic:open", station = "hand", requires = "magic.open",
    inputs = herb, outputs = tea } == true)
assert(craft.register{ id = "schism_magic:split", station = "hand", conserve = true,
    inputs = { { "schism_magic:herb", units = 27 } },
    outputs = { { "schism_magic:tea", units = 13 }, { "schism_magic:elixir", units = 14 } } } == true)

local list = craft.recipes("schism_magic:alembic")
assert(#list == 1 and list[1].id == "schism_magic:elixir" and list[1].inputs[1].units == 81
    and list[1].tools[1].name == "schism_magic:flask", "recipes lists the alembic's")
assert(#craft.recipes() >= 6)
assert(craft.recipes(7) == nil)
assert(craft.in_group("#log", "schism_magic:dreamwood") == true)
assert(craft.in_group("#log", "schism_magic:herb") == false)
assert(craft.set_gate(function() return true end) == nil, "the progress mod set the gate first")
assert(craft.perform("not hex", "schism_magic:tea") == nil)
assert(not pcall(function() craft.version = 2 end), "the exports are read-only")

game.register_on_chat(function(e)
    local word, rest = string.match(e.text, "^m (%S+)%s*(.*)$")
    if not word then return end
    if word == "perform" or word == "can" then
        local id, box = string.match(rest, "^(%S+)%s*(%S*)$")
        local ok, out = craft[word](e.player, id, box ~= "" and box or nil)
        if ok and word == "perform" then
            local parts = {}
            for _, o in ipairs(out) do parts[#parts + 1] = o.material .. " " .. o.units end
            game.chat_to(e.player, "made " .. table.concat(parts, ", "))
        elseif ok then
            game.chat_to(e.player, "can")
        else
            game.chat_to(e.player, "no: " .. tostring(out))
        end
    elseif word == "box" then
        game.make_container("magic:alembic", 4)
        game.chat_to(e.player, "box")
    elseif word == "late" then
        local ok, why = craft.register{ id = "schism_magic:late", station = "hand", inputs = herb, outputs = tea }
        local g = craft.register_group("#log", { "schism_magic:herb" })
        game.chat_to(e.player, tostring(ok) .. " " .. tostring(why) .. " " .. tostring(g))
    end
    return false
end)
"##;

fn main() {
    load_alone();
    registry();
    println!("craft native check: all passed");
}

/// On a bare engine: loads, registers, and says what it cannot make.
fn load_alone() {
    let mut r = Rig::new(Setup::default());
    r.join(PLAYER);
    r.tick(1);
    r.say("craft stick");
    assert_eq!(r.said(), "cannot make Sticks: nothing registered is #log");
    r.say("recipes");
    assert_eq!(r.heard(PLAYER), vec!["ready: nothing", "lacking something: stick"]);
    println!("load alone: ok");
}

fn registry() {
    let mut r = Rig::new(Setup {
        world: true,
        fixtures: vec![("schism_progress".into(), PROGRESS.into()), ("schism_magic".into(), MAGIC.into())],
        ..Setup::default()
    });
    r.join(PLAYER);
    r.tick(1);

    // A hand recipe from the world's logs, through the chat word.
    r.give(PLAYER, "tiamat_default_world:oak_log", 27);
    r.say("craft stick");
    assert_eq!(r.said(), "made Sticks x1");
    assert_eq!(r.units(PLAYER, "stick"), 4 * 27);
    assert_eq!(r.units(PLAYER, "tiamat_default_world:oak_log"), 0);
    r.say("craft stick");
    assert_eq!(r.said(), "cannot make Sticks: missing log");

    // Another mod's log, put in the group, is a log.
    r.give(PLAYER, "schism_magic:dreamwood", 27);
    r.give(PLAYER, "tiamat_default_world:birch_log", 27);
    r.say("craft stick 5");
    assert_eq!(r.heard(PLAYER), vec!["made Sticks x2", "cannot make Sticks: missing log"]);
    assert_eq!(r.units(PLAYER, "stick"), 12 * 27);

    // A sentence that only starts with the word is chat, not a command.
    let out = r.vm.chat(&ChatEvent { player: PLAYER, text: "craft is fun".into() });
    assert!(out.allowed, "a sentence is let through");

    // Another mod's hand recipe, through the export.
    r.give(PLAYER, "schism_magic:herb", 54);
    r.say("m perform schism_magic:tea");
    assert_eq!(r.said(), "made schism_magic:tea 27");
    assert_eq!(r.units(PLAYER, "schism_magic:herb"), 0);

    // A named stack is somebody's particular thing, never an ingredient.
    r.give_detail(PLAYER, "schism_magic:herb", 54, "named");
    r.say("m perform schism_magic:tea");
    assert_eq!(r.said(), "no: missing herb");
    assert_eq!(r.units(PLAYER, "schism_magic:herb"), 54, "the named herbs are untouched");

    // The gate: refused, and nothing taken; open, and made.
    r.give(PLAYER, "schism_magic:herb", 27);
    r.say("m perform schism_magic:secret");
    assert_eq!(r.said(), "no: you do not know how to make that yet");
    assert_eq!(r.units(PLAYER, "schism_magic:herb"), 81);
    r.say("m perform schism_magic:open");
    assert_eq!(r.said(), "made schism_magic:tea 27");

    // Units, not items: a conserving recipe splitting one block's worth.
    r.give(PLAYER, "schism_magic:herb", 27);
    r.say("m perform schism_magic:split");
    assert_eq!(r.said(), "made schism_magic:tea 13, schism_magic:elixir 14");

    // A station's recipe, from its container's roles.
    r.say("m box");
    assert_eq!(r.said(), "box");
    let alembic = "magic:alembic";
    r.boxes.set(alembic, 1, Some(r.stack("schism_magic:herb", 81)));
    r.boxes.set(alembic, 2, Some(r.stack("tiamat_default_world:oak_log", 27)));
    let flask = tiamat_core::inventory::Stack { detail: Some("t=1".into()), ..r.stack("schism_magic:flask", 27) };
    r.boxes.set(alembic, 3, Some(flask.clone()));
    r.say("m can schism_magic:elixir magic:alembic");
    assert_eq!(r.said(), "can");
    r.say("m perform schism_magic:elixir magic:alembic");
    assert_eq!(r.said(), "made schism_magic:elixir 54");
    assert_eq!(r.boxes.get(alembic, 1), None);
    assert_eq!(r.boxes.get(alembic, 2), None);
    assert_eq!(r.boxes.get(alembic, 3), Some(flask.clone()), "a tool is not consumed");
    assert_eq!(r.boxes.get(alembic, 4).map(|s| s.units), Some(54));

    // No room for the output: everything goes back where it was.
    r.boxes.set(alembic, 1, Some(r.stack("schism_magic:herb", 81)));
    r.boxes.set(alembic, 2, Some(r.stack("schism_magic:dreamwood", 27)));
    r.boxes.set(alembic, 4, Some(r.stack("schism_magic:tea", 27)));
    r.say("m perform schism_magic:elixir magic:alembic");
    assert_eq!(r.said(), "no: no room for what it makes");
    assert_eq!(r.boxes.get(alembic, 1), Some(r.stack("schism_magic:herb", 81)));
    assert_eq!(r.boxes.get(alembic, 2), Some(r.stack("schism_magic:dreamwood", 27)));
    assert_eq!(r.boxes.get(alembic, 4), Some(r.stack("schism_magic:tea", 27)));

    // A missing tool is said; one in the player's own hands will do.
    r.boxes.set(alembic, 3, None);
    r.boxes.set(alembic, 4, None);
    r.say("m perform schism_magic:elixir magic:alembic");
    assert_eq!(r.said(), "no: needs flask");
    r.give_detail(PLAYER, "schism_magic:flask", 27, "t=2");
    r.say("m perform schism_magic:elixir magic:alembic");
    assert_eq!(r.said(), "made schism_magic:elixir 54");

    // Made in the right place or not at all.
    r.say("m perform schism_magic:tea magic:alembic");
    assert_eq!(r.said(), "no: that is made by hand, not at a station");
    r.say("m perform schism_magic:elixir");
    assert_eq!(r.said(), "no: that is made at the Alembic");
    r.say("craft schism_magic:elixir");
    assert_eq!(r.said(), "Elixir is made at the Alembic");

    // The registration window closed with the first tick.
    r.say("m late");
    assert_eq!(r.said(), "nil recipes are registered while mods load nil");

    // What the progress mod heard: every recipe made, and each first once.
    r.say("p tally");
    assert_eq!(
        r.said(),
        "8 brew:elixir craft:schism_magic:open craft:schism_magic:split craft:schism_magic:tea craft:tiamat_default_craft:stick"
    );
    let key = format!("first:{}:brew:elixir", hex(PLAYER));
    assert!(r.storage.dump().contains(&key), "firsts are kept with the world");

    // Somebody else's inventory is not the player's.
    r.join(OTHER);
    r.say_as(OTHER, "craft stick");
    assert_eq!(r.heard(OTHER), vec!["cannot make Sticks: missing log"]);

    let _ = MOD;
    println!("registry: ok");
}
