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

/// A stand-in for the tech mod (fixtures/tech.lua).
const TECH: &str = include_str!("../fixtures/tech.lua");

fn main() {
    load_alone();
    registry();
    tools();
    creative();
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

fn tools() {
    let mut r = Rig::new(Setup {
        world: true,
        life: true,
        fixtures: vec![("schism_tech".into(), TECH.into())],
        ..Setup::default()
    });
    r.join(PLAYER);
    r.tick(1);

    // The hand is this mod's, and the reference chisel is not in the set.
    assert_eq!(r.tool(PLAYER).as_deref(), Some("tiamat_default_craft:hand"));
    let tools = r.vm.registered_tools();
    let default: Vec<&str> = tools.iter().filter(|t| t.default).map(|t| t.id.as_str()).collect();
    assert_eq!(default, vec!["tiamat_default_craft:hand"]);

    // The kit is the operator's.
    r.say("toolkit");
    assert_eq!(r.said(), "toolkit is for operators");
    r.huds.operators.lock().unwrap().push(PLAYER);
    r.say("toolkit");
    assert_eq!(r.said(), "a toolkit: one of each");
    let pick = r.details(PLAYER, "bronze_pick");
    assert_eq!(pick.len(), 1);
    assert!(pick[0].starts_with("t="), "a tool carries its serial: {pick:?}");
    r.say("toolkit");
    let picks = r.details(PLAYER, "bronze_pick");
    assert_eq!(picks.len(), 2, "two tools never stack: {picks:?}");
    assert_ne!(picks[0], picks[1]);

    // Held -> tool: set once, on the change, and put back if the tool key moved it.
    let calls = |r: &Rig| r.tools.calls.lock().unwrap().len();
    r.hold(PLAYER, "bronze_pick", Some(&pick[0]));
    let before = calls(&r);
    r.tick(1);
    assert_eq!(r.tool(PLAYER).as_deref(), Some("tiamat_default_craft:bronze_pick"));
    r.tick(5);
    assert_eq!(calls(&r), before + 1, "set_tool once, not every tick");
    r.hold(PLAYER, "tiamat_default_world:dirt", None);
    r.tick(1);
    assert_eq!(r.tool(PLAYER).as_deref(), Some("tiamat_default_craft:hand"));
    let hammer = r.details(PLAYER, "bronze_hammer")[0].clone();
    r.hold(PLAYER, "bronze_hammer", Some(&hammer));
    let before = calls(&r);
    r.tick(1);
    assert_eq!(calls(&r), before, "a hammer does not dig: still the hand, and nothing called");
    r.tools.hand.lock().unwrap().insert(PLAYER, Some("tiamat_default_craft:iron_pick".into()));
    r.tick(1);
    assert_eq!(r.tool(PLAYER).as_deref(), Some("tiamat_default_craft:hand"), "the tool key does not stick");

    // Another mod's tools: an engine tool is put in the hand; one that is not
    // is the hand, and is not asked for again.
    r.give(PLAYER, "schism_tech:drill", 27);
    r.hold(PLAYER, "schism_tech:drill", None);
    r.tick(1);
    assert_eq!(r.tool(PLAYER).as_deref(), Some("schism_tech:drill"));
    r.hold(PLAYER, "schism_tech:rod", None);
    r.tick(1);
    assert_eq!(r.tool(PLAYER).as_deref(), Some("tiamat_default_craft:hand"));
    let before = calls(&r);
    r.tick(5);
    assert_eq!(calls(&r), before, "a refused tool is not asked for every tick");

    // The classes, as a table: what is held, what is dug, what is said.
    let bronze_pick = pick[0].clone();
    let rock_by_hand = "Bare hands will not move stone. Fire will crack it, or a bronze pick will break it.";
    let cases: Vec<(Option<&str>, &str, Result<(), &str>)> = vec![
        (None, "tiamat_default_world:dirt", Ok(())),
        (None, "tiamat_default_world:stone", Err(rock_by_hand)),
        (None, "tiamat_default_world:ironwood_log", Err("Too dense to break by hand. An axe would do it.")),
        (None, "tiamat_default_world:obsidian", Err("Bare hands will not move this. It wants an iron pick.")),
        (None, "schism_tech:plain", Ok(())),
        (None, "schism_tech:alloy_wall", Err("Only a drill.")),
        (Some("digging_stick"), "tiamat_default_world:dirt", Ok(())),
        (Some("digging_stick"), "tiamat_default_world:stone", Err("That wants a pick.")),
        (Some("digging_stick"), "tiamat_default_world:oak_log", Err("That wants an axe.")),
        (Some("wooden_maul"), "tiamat_default_world:granite", Err("That wants a pick.")),
        (Some("bronze_pick"), "tiamat_default_world:stone", Ok(())),
        (Some("bronze_pick"), "tiamat_default_world:granite", Ok(())),
        (Some("bronze_pick"), "tiamat_default_world:copper_ore", Ok(())),
        (Some("bronze_pick"), "tiamat_default_world:gravel", Ok(())),
        (Some("bronze_pick"), "tiamat_default_world:obsidian", Err("The bronze skitters off. This stone wants iron.")),
        (Some("bronze_pick"), "tiamat_default_world:oak_log", Err("That wants an axe.")),
        (Some("bronze_pick"), "schism_tech:alloy_wall", Err("Only a drill.")),
        (Some("iron_pick"), "tiamat_default_world:obsidian", Ok(())),
        (Some("bronze_axe"), "tiamat_default_world:ironwood_log", Ok(())),
        (Some("bronze_axe"), "tiamat_default_world:stone", Err("That wants a pick.")),
        (Some("bronze_chisel"), "tiamat_default_world:stone", Ok(())),
        (Some("bronze_chisel"), "tiamat_default_world:obsidian", Err("The bronze skitters off. This stone wants iron.")),
        (Some("bronze_hammer"), "tiamat_default_world:stone", Err(rock_by_hand)),
    ];
    // Checked without wearing anything out: only the start and the veto on
    // completion are asked, never the wear that follows a real dig.
    for (held, block, want) in cases {
        match held {
            Some(id) => {
                let d = if id == "bronze_pick" { bronze_pick.clone() } else { r.details(PLAYER, id)[0].clone() };
                r.hold(PLAYER, id, Some(&d));
            }
            None => r.hold_nothing(PLAYER),
        }
        let got = r.dig_start(PLAYER, block);
        assert_eq!(got, want.map_err(str::to_owned), "{held:?} on {block}");
    }
    r.hold(PLAYER, "schism_tech:drill", None);
    assert_eq!(r.dig_start(PLAYER, "schism_tech:alloy_wall"), Ok(()));
    r.hold_nothing(PLAYER);
    assert_eq!(r.dig_complete(PLAYER, "tiamat_default_world:stone"), Err(rock_by_hand.to_owned()), "and as it completes");

    // The hand on a log is allowed, with a hint the first time only.
    r.heard(PLAYER);
    assert_eq!(r.dig_start(PLAYER, "tiamat_default_world:oak_log"), Ok(()));
    assert_eq!(r.heard(PLAYER), vec!["An axe would make short work of that."]);
    assert_eq!(r.dig_start(PLAYER, "tiamat_default_world:birch_log"), Ok(()));
    assert!(r.heard(PLAYER).is_empty(), "the hint is said once");

    // Wear: a hundred digs of stone and the bronze pick is gone.
    r.hold(PLAYER, "bronze_pick", Some(&bronze_pick));
    r.tick(1);
    for _ in 0..99 {
        r.dig(PLAYER, "tiamat_default_world:stone").unwrap();
    }
    r.say("t tool");
    assert_eq!(r.said(), "tiamat_default_craft:bronze_pick pick 1 99/100");
    // A refused dig costs nothing.
    assert!(r.dig(PLAYER, "tiamat_default_world:obsidian").is_err());
    r.say("t tool");
    assert_eq!(r.said(), "tiamat_default_craft:bronze_pick pick 1 99/100");
    r.heard(PLAYER);
    r.dig(PLAYER, "tiamat_default_world:stone").unwrap();
    assert_eq!(r.heard(PLAYER), vec!["Your bronze pick has worn to nothing."]);
    let other: Vec<String> = picks.iter().filter(|d| **d != bronze_pick).cloned().collect();
    assert_eq!(r.details(PLAYER, "bronze_pick"), other, "only the other pick is left");
    let serial = bronze_pick.trim_start_matches("t=");
    assert!(!r.storage.dump().contains(&format!("wear:{serial}=")), "its wear key is gone");
    r.tick(1);
    assert_eq!(r.tool(PLAYER).as_deref(), Some("tiamat_default_craft:hand"));
    r.hold_nothing(PLAYER);
    assert!(r.dig_start(PLAYER, "tiamat_default_world:stone").is_err(), "the 101st dig is by hand");

    // Another mod charges wear; a tool of its own breaks and it hears.
    r.hold(PLAYER, "schism_tech:drill", None);
    r.say("t wear 2");
    assert_eq!(r.said(), "true");
    r.say("t tool");
    assert_eq!(r.said(), "schism_tech:drill drill 3 2/3");
    r.say("t wear 1");
    r.say("t broken");
    assert_eq!(r.said(), "tiamat_default_craft:bronze_pick schism_tech:drill", "both breaks were heard");
    assert_eq!(r.units(PLAYER, "schism_tech:drill"), 0);

    // A recipe that makes tools makes each with its own serial.
    r.give(PLAYER, "stick", 27);
    let before = r.details(PLAYER, "digging_stick").len();
    r.say("craft schism_tech:diggers");
    let after = r.details(PLAYER, "digging_stick");
    assert_eq!(after.len(), before + 2, "{after:?}");
    assert!(after.iter().all(|d| d.starts_with("t=")));

    // Life was told which tools are weapons, sickles and hoes.
    for (call, want) in [
        ("weapon tiamat_default_craft:iron_axe 7", "yes"),
        ("weapon tiamat_default_craft:bronze_knife 4", "yes"),
        ("harvest tiamat_default_craft:bronze_sickle 2", "yes"),
        ("tills tiamat_default_craft:iron_hoe", "yes"),
        ("weapon tiamat_default_craft:copper_pot 1", "no"),
    ] {
        r.say(&format!("life heard {call}"));
        assert_eq!(r.said(), want, "{call}");
    }
    println!("tools: ok");
}

/// In a Creative world nothing is refused to the wrong tool and nothing wears.
fn creative() {
    let mut r = Rig::new(Setup { world: true, mode: Some("Creative".into()), ..Setup::default() });
    r.join(PLAYER);
    r.tick(1);
    r.say("toolkit");
    assert_eq!(r.said(), "a toolkit: one of each");
    r.hold_nothing(PLAYER);
    assert_eq!(r.dig(PLAYER, "tiamat_default_world:obsidian"), Ok(()));
    let pick = r.details(PLAYER, "bronze_pick")[0].clone();
    r.hold(PLAYER, "bronze_pick", Some(&pick));
    for _ in 0..150 {
        r.dig(PLAYER, "tiamat_default_world:stone").unwrap();
    }
    assert_eq!(r.details(PLAYER, "bronze_pick"), vec![pick]);
    println!("creative: ok");
}
