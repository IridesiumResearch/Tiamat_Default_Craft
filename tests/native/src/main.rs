// SPDX-FileCopyrightText: Iridesium
// SPDX-License-Identifier: GPL-3.0-only
//
// The mod, run for real: the engine's script VM with a fake server around it
// (rig.rs), and small fixture mods that use its exports the way the progress,
// magic and tech mods will — including the calls they must be refused.

// The rig carries fakes the later steps use; not every one is read yet.
#[allow(dead_code)]
mod rig;
mod fit;

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
game.register_block{ id = "alembic" }
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
assert(craft.register_station{ id = "schism_magic:bad", heat = true, slots = { input = 1, output = 2 } } == nil)
assert(craft.register_station{ id = "hand", inventory = true } == nil)
assert(craft.register_station{ id = "schism_magic:alembic", name = "Alembic", block = "schism_magic:alembic",
    slots = { input = { 1, 2 }, tool = 3, output = 4, fuel = 5 }, heat = true } == true)
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
        game.make_container("magic:alembic", 5)
        game.chat_to(e.player, "box")
    elseif word == "late" then
        local ok, why = craft.register{ id = "schism_magic:late", station = "hand", inputs = herb, outputs = tea }
        local g = craft.register_group("#log", { "schism_magic:herb" })
        game.chat_to(e.player, tostring(ok) .. " " .. tostring(why) .. " " .. tostring(g))
    end
    return false
end)
"##;

/// A stand-in for the progress mod as it uses Craft (fixtures/progress.lua).
const PROGRESS_STANDIN: &str = include_str!("../fixtures/progress.lua");

/// A stand-in for the tech mod (fixtures/tech.lua).
const TECH: &str = include_str!("../fixtures/tech.lua");

fn main() {
    load_alone();
    registry();
    tools();
    creative();
    fire();
    fire_alone();
    stations();
    craft_tab();
    cooking();
    sluice();
    iron();
    torch_and_hud();
    after_the_loop();
    progress_asks();
    wear_on_the_tool();
    anvil_offhand();
    // The same world, played the same way twice, is the same world.
    let (a, b) = (kiln(), kiln());
    assert_eq!(a, b, "two runs of the kiln leave the same storage");
    println!("determinism: ok");
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
    assert_eq!(r.heard(PLAYER), vec!["ready: nothing", "lacking something: bark_strip, cord, fire_striker, stick, tinder, torch, unlit_campfire, workbench"]);
    // Every thing this mod registers has its picture: the world's rocks are
    // absent here, so do the check where they are too (registry()).
    textures_present(&r);
    println!("load alone: ok");
}

/// Every block and item this mod registered has `textures/<id>.png`.
fn textures_present(r: &Rig) {
    let dir = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../mods").join(MOD).join("textures");
    let mut missing: Vec<String> = r
        .materials
        .keys()
        .filter_map(|id| id.strip_prefix(&format!("{MOD}:")))
        .filter(|short| !dir.join(format!("{short}.png")).exists())
        .map(str::to_owned)
        .collect();
    missing.sort();
    assert!(missing.is_empty(), "no texture for {missing:?}");
}

fn registry() {
    let mut r = Rig::new(Setup {
        world: true,
        fixtures: vec![("schism_progress".into(), PROGRESS.into()), ("schism_magic".into(), MAGIC.into())],
        ..Setup::default()
    });
    r.join(PLAYER);
    r.tick(1);
    textures_present(&r);

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

    // A block nobody classed that tags itself an ore is rock (engine ask 6).
    r.hold_nothing(PLAYER);
    assert_eq!(r.dig_start(PLAYER, "schism_tech:tagged_ore"), Err(rock_by_hand.to_owned()));

    // A pick is slower on earth than on rock (engine ask 2).
    let pick = r.vm.registered_tools().into_iter().find(|t| t.id == "tiamat_default_craft:bronze_pick").unwrap();
    assert_eq!(pick.speed_multiplier, 1.8);
    assert!(pick.speeds.contains(&("tiamat_default_world:dirt".to_owned(), 0.9)), "{:?}", pick.speeds);
    assert!(!pick.speeds.iter().any(|(b, _)| b == "tiamat_default_world:stone"), "rock at its own speed");

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
    assert!(!r.storage.dump().contains("wear:"), "no wear is kept in storage");
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

/// A fire from nothing: flint, tinder and logs by hand, struck alight, cracking
/// the rock around it, fed, and burning out after a restart.
fn fire() {
    let prelude = "tdc_overrides = { fire_fuel = 1200, fire_max_fuel = 8000 }";
    let mut r = Rig::new(Setup { world: true, life: true, prelude: prelude.into(), ..Setup::default() });
    r.join(PLAYER);
    r.tick(1);

    // Everything a fire needs, by hand.
    r.give(PLAYER, "tiamat_default_world:flint", 54);
    r.give(PLAYER, "tiamat_default_world:tall_grass", 9);
    r.give(PLAYER, "tiamat_default_world:oak_log", 27 * 3);
    for recipe in ["fire_striker", "tinder", "stick", "unlit_campfire"] {
        r.say(&format!("craft {recipe}"));
        assert!(r.said().starts_with("made"), "{recipe}");
    }
    assert_eq!(r.units(PLAYER, "unlit_campfire"), 27);
    assert_eq!(r.units(PLAYER, "stick"), 27, "four sticks made, three laid");
    let striker = r.details(PLAYER, "fire_striker")[0].clone();

    // Flint is broken out by hand; rock is not.
    r.hold_nothing(PLAYER);
    assert_eq!(r.dig_start(PLAYER, "tiamat_default_world:flint"), Ok(()));

    // The fire, and rock round it: beside it, under it, and one further on
    // through open air. Granite does not crack.
    r.put(10, 64, 10, "unlit_campfire");
    r.put(11, 64, 10, "tiamat_default_world:stone");
    r.put(10, 63, 10, "tiamat_default_world:copper_ore");
    r.put(9, 64, 10, "tiamat_default_world:granite");
    r.put(10, 64, 12, "tiamat_default_world:stone");
    r.put(12, 64, 10, "tiamat_default_world:stone");

    assert_eq!(r.use_at(PLAYER, 10, 64, 10).as_deref(), Some(""), "no striker: the fire's box opens");
    assert!(r.screen_says(PLAYER, "The fire is out. Strike it to cook."));
    r.close(PLAYER, "station");
    r.hold(PLAYER, "fire_striker", Some(&striker));
    assert_eq!(r.use_at(PLAYER, 10, 64, 10).as_deref(), Some(""));
    assert_eq!(r.block_name(10, 64, 10), "tiamat_default_life:campfire", "lit as Life's campfire");
    let serial = striker.trim_start_matches("t=");
    assert_eq!(r.details(PLAYER, "fire_striker"), vec![format!("t={serial};w=1")], "the wear is on the striker");

    r.tick(560);
    assert_eq!(r.block_name(11, 64, 10), "tiamat_default_world:stone", "not yet");
    r.tick(60);
    assert_eq!(r.block_name(11, 64, 10), "tiamat_default_craft:cracked_stone");
    assert_eq!(r.block_name(10, 63, 10), "tiamat_default_craft:cracked_copper_ore");
    assert_eq!(r.block_name(10, 64, 12), "tiamat_default_craft:cracked_stone", "through the air beside it");
    assert_eq!(r.block_name(9, 64, 10), "tiamat_default_world:granite");
    assert_eq!(r.block_name(12, 64, 10), "tiamat_default_world:stone", "behind rock, out of reach");
    r.hold_nothing(PLAYER);
    assert_eq!(r.dig_start(PLAYER, "cracked_copper_ore"), Ok(()));
    assert_eq!(r.dig_start(PLAYER, "tiamat_default_world:copper_ore"), Err("Bare hands will not move stone. Fire will crack it, or a bronze pick will break it.".into()));
    // A cracked block drops the ore it was, whole: the engine pays a drop
    // that names the world's block (engine ask 7).
    let rules = r.vm.registered_block_rules();
    let cracked = rules.iter().find(|b| b.block == "tiamat_default_craft:cracked_copper_ore").expect("cracked ore");
    assert_eq!(cracked.drops, Some(vec![("tiamat_default_world:copper_ore".to_owned(), 27)]));
    let dump = r.storage.dump();
    for first in ["fire:lit", "fireset:copper_ore", "fireset:stone"] {
        assert!(dump.contains(&format!("first:{}:{first}=", hex(PLAYER))), "{first}");
    }

    // Fed a log; then too full for another.
    r.give(PLAYER, "tiamat_default_world:oak_log", 54);
    r.hold(PLAYER, "tiamat_default_world:oak_log", None);
    assert_eq!(r.use_at(PLAYER, 10, 64, 10).as_deref(), Some(""));
    assert_eq!(r.units(PLAYER, "tiamat_default_world:oak_log"), 27);
    assert_eq!(r.use_at(PLAYER, 10, 64, 10).as_deref(), Some("The fire is roaring already."));
    assert_eq!(r.units(PLAYER, "tiamat_default_world:oak_log"), 27, "nothing taken");
    // Anything else in hand opens what is cooking on it.
    r.give(PLAYER, "tiamat_default_world:dirt", 27);
    r.hold(PLAYER, "tiamat_default_world:dirt", None);
    assert_eq!(r.use_at(PLAYER, 10, 64, 10).as_deref(), Some(""));
    assert_eq!(r.last_form(), "tiamat_default_craft:station");
    r.close(PLAYER, "station");

    // A restart: the fire is read back and burns out where it left off.
    let mut r = Rig::new(Setup {
        world: true,
        life: true,
        prelude: prelude.into(),
        restart: Some(r.saved()),
        ..Setup::default()
    });
    r.join(PLAYER);
    r.tick(6000);
    assert_eq!(r.block_name(10, 64, 10), "tiamat_default_life:campfire", "still burning");
    r.tick(1200);
    assert_eq!(r.block_name(10, 64, 10), "tiamat_default_craft:unlit_campfire", "burned out");
    assert!(!r.storage.dump().contains("fire:overworld@"), "and forgotten");
    println!("fire: ok");
}

/// Without Life the fire is this mod's own; a fire dug away is forgotten.
fn fire_alone() {
    let mut r = Rig::new(Setup { world: true, ..Setup::default() });
    r.join(PLAYER);
    r.huds.operators.lock().unwrap().push(PLAYER);
    r.say("toolkit");
    r.tick(1);
    let striker = r.details(PLAYER, "fire_striker")[0].clone();
    r.hold(PLAYER, "fire_striker", Some(&striker));
    r.put(0, 64, 0, "unlit_campfire");
    assert_eq!(r.use_at(PLAYER, 0, 64, 0).as_deref(), Some(""));
    assert_eq!(r.block_name(0, 64, 0), "tiamat_default_craft:campfire_lit");
    r.tick(40);
    assert!(r.storage.dump().contains("fire:overworld@0,64,0"));
    r.world.apply(tiamat_core::BlockPos { x: 0, y: 64, z: 0 }, "engine:air");
    r.tick(40);
    assert!(!r.storage.dump().contains("fire:overworld@0,64,0"), "a dug fire is forgotten");
    println!("fire alone: ok");
}

/// The workshop: cord and a workbench by hand, planks with a wedge at the
/// bench, one player at a time, a bench that gives back what is in it, a
/// chest, and another mod's station on the same road.
fn stations() {
    let mut r = Rig::new(Setup {
        world: true,
        life: true,
        fixtures: vec![("schism_progress".into(), PROGRESS.into()), ("schism_magic".into(), MAGIC.into())],
        ..Setup::default()
    });
    r.join(PLAYER);
    r.join(OTHER);
    r.tick(1);

    r.give(PLAYER, "tiamat_default_world:bramble", 54);
    r.give(PLAYER, "tiamat_default_world:oak_log", 27 * 6);
    r.say("craft cord 2");
    assert_eq!(r.said(), "made Cord x2");
    r.say("craft workbench");
    assert_eq!(r.said(), "made Workbench x1");
    assert_eq!(r.units(PLAYER, "workbench"), 27);

    // Placed, it has a container, and is in the index.
    r.place(PLAYER, 5, 64, 5, "workbench").unwrap();
    let bench = "tiamat_default_craft:workbench:5,64,5";
    assert!(r.boxes.exists(bench));
    assert!(r.storage.dump().contains(&format!("placer:{bench}=Text(\"{}\")", hex(PLAYER))), "{}", r.storage.dump());

    // Used: the screen, and the container lent to this player alone.
    assert_eq!(r.use_at(PLAYER, 5, 64, 5).as_deref(), Some(""));
    assert_eq!(r.last_form(), "tiamat_default_craft:station");
    assert_eq!(r.use_at(OTHER, 5, 64, 5).as_deref(), Some("Somebody is using that."));
    fit::check("the workbench", &r.dialogs.shown.lock().unwrap().last().unwrap().tree);

    // Planks: a log in the grid, a wedge in the hands, the recipe pressed.
    // Workbench recipes are listed by id; planks are the seventh.
    r.huds.operators.lock().unwrap().push(PLAYER);
    r.say("toolkit");
    r.boxes.set(bench, 1, Some(r.stack("tiamat_default_world:oak_log", 27)));
    r.press_labelled(PLAYER, "station", "Planks x4");
    assert_eq!(r.boxes.get(bench, 10).map(|s| s.units), Some(4 * 27), "four planks out");
    assert_eq!(r.boxes.get(bench, 1), None);
    assert!(r.details(PLAYER, "wooden_wedge").iter().any(|d| d.ends_with(";w=1")), "the wedge wore: {:?}", r.details(PLAYER, "wooden_wedge"));
    r.press_labelled(PLAYER, "station", "Planks x4");
    assert!(r.screen_says(PLAYER, "Cannot: missing log."), "the screen says why");

    // Somebody else cannot dig it from under them; they can, and get the planks.
    assert_eq!(r.dig_complete_at(OTHER, 5, 64, 5), Err("Somebody is using that.".into()));
    r.put(100, 64, 100, "workbench");
    r.boxes.slots.lock().unwrap().insert("tiamat_default_craft:workbench:100,64,100".into(), vec![None; 10]);
    r.boxes.set("tiamat_default_craft:workbench:100,64,100", 3, Some(r.stack("tiamat_default_craft:plank", 54)));
    let planks = r.units(PLAYER, "plank");
    assert_eq!(r.dig(PLAYER, "workbench"), Ok(()));
    assert_eq!(r.units(PLAYER, "plank"), planks + 54, "what was in it comes back");
    assert!(!r.boxes.exists("tiamat_default_craft:workbench:100,64,100"));

    // The chest: nine planks and two cord at the bench.
    r.close(PLAYER, "station");
    r.boxes.set(bench, 1, Some(r.stack("plank", 27 * 9)));
    r.boxes.set(bench, 2, Some(r.stack("cord", 54)));
    r.boxes.set(bench, 10, None);
    assert_eq!(r.use_at(PLAYER, 5, 64, 5).as_deref(), Some(""));
    r.press_labelled(PLAYER, "station", "Chest");
    assert_eq!(r.boxes.get(bench, 10).map(|s| s.material), Some(r.material("chest")));
    r.close(PLAYER, "station");

    r.give(PLAYER, "chest", 27);
    r.place(PLAYER, 7, 64, 5, "chest").unwrap();
    let chest = "tiamat_default_craft:chest:7,64,5";
    assert_eq!(r.use_at(PLAYER, 7, 64, 5).as_deref(), Some(""));
    let tree = format!("{:?}", r.dialogs.shown.lock().unwrap().last().unwrap().tree);
    assert!(tree.contains(chest), "the chest's grid");
    fit::check("the chest", &r.dialogs.shown.lock().unwrap().last().unwrap().tree);
    r.boxes.set(chest, 5, Some(r.stack("tiamat_default_world:flint", 27)));
    r.close(PLAYER, "station");
    r.put(100, 64, 100, "chest");
    r.boxes.slots.lock().unwrap().insert("tiamat_default_craft:chest:100,64,100".into(), vec![None; 27]);
    r.boxes.set("tiamat_default_craft:chest:100,64,100", 9, Some(r.stack("tiamat_default_world:flint", 27)));
    let flint = r.units(PLAYER, "tiamat_default_world:flint");
    assert_eq!(r.dig(PLAYER, "chest"), Ok(()));
    assert_eq!(r.units(PLAYER, "tiamat_default_world:flint"), flint + 27);

    // Another mod's station is a block, a record and recipes: the same road.
    r.give(PLAYER, "schism_magic:alembic", 27);
    r.place(PLAYER, 9, 64, 5, "schism_magic:alembic").unwrap();
    assert_eq!(r.use_at(PLAYER, 9, 64, 5).as_deref(), Some(""));
    assert!(r.boxes.exists("tiamat_default_craft:schism_magic:alembic:9,64,5"));
    fit::check("the alembic", &r.dialogs.shown.lock().unwrap().last().unwrap().tree);
    r.close(PLAYER, "station");

    // By hand without the interface: the V action opens a dialog of its own.
    r.action(PLAYER, "tiamat_default_craft:craft");
    assert_eq!(r.last_form(), "tiamat_default_craft:hand");
    fit::check("the hand dialog", &r.dialogs.shown.lock().unwrap().last().unwrap().tree);
    r.give(PLAYER, "tiamat_default_world:oak_log", 27);
    r.press_labelled(PLAYER, "hand", "Sticks x4");
    assert!(r.screen_says(PLAYER, "Made Sticks x4."));
    println!("stations: ok");
}

/// With the interface, the Craft tab is on its screen and V opens it there.
fn craft_tab() {
    let mut r = Rig::new(Setup { world: true, ui: true, ..Setup::default() });
    r.join(PLAYER);
    r.tick(1);
    r.action(PLAYER, "tiamat_default_craft:craft");
    let form = r.last_form();
    assert!(form.starts_with("tiamat_default_ui:"), "the interface's screen, not ours: {form}");
    let tree = format!("{:?}", r.dialogs.shown.lock().unwrap().last().unwrap().tree);
    assert!(tree.contains("By hand"), "on the Craft tab");
    fit::check("the Craft tab", &r.dialogs.shown.lock().unwrap().last().unwrap().tree);
    println!("craft tab: ok");
}

/// The kiln: fired from clay, lit with a striker, charcoal at red heat,
/// copper and bronze at orange with a crucible, heads cast until the mould
/// cracks, iron refused, going out, and a head hafted into a pick.
fn kiln() -> String {
    let mut r = Rig::new(Setup { world: true, life: true, ..Setup::default() });
    r.join(PLAYER);
    r.huds.operators.lock().unwrap().push(PLAYER);
    r.say("toolkit");
    r.tick(1);
    let striker = r.details(PLAYER, "fire_striker")[0].clone();
    let crucible = r.details(PLAYER, "crucible")[0].clone();
    let mould = r.details(PLAYER, "mould_pick")[0].clone();
    let tool = |r: &Rig, id: &str, detail: &str| tiamat_core::inventory::Stack {
        detail: Some(detail.into()),
        ..r.stack(id, 27)
    };

    // Laid of clay, placed, and struck: no fuel, no fire.
    r.give(PLAYER, "unfired_kiln", 27);
    r.place(PLAYER, 20, 64, 20, "unfired_kiln").unwrap();
    let k = "tiamat_default_craft:kiln:20,64,20";
    assert!(r.boxes.exists(k));
    r.hold(PLAYER, "fire_striker", Some(&striker));
    assert_eq!(r.use_at(PLAYER, 20, 64, 20).as_deref(), Some("It wants fuel first."));

    // Logs in the bottom: it lights, and the first fire makes it a kiln.
    r.boxes.set(k, 1, Some(r.stack("tiamat_default_world:oak_log", 27 * 4)));
    assert_eq!(r.use_at(PLAYER, 20, 64, 20).as_deref(), Some(""));
    assert_eq!(r.block_name(20, 64, 20), "tiamat_default_craft:kiln_lit");
    assert!(r.storage.dump().contains(&format!("first:{}:fire:kiln=", hex(PLAYER))));
    assert_eq!(r.use_at(PLAYER, 20, 64, 20).as_deref(), Some("It is burning already."));

    // A log in the work slot at red heat is charcoal in a minute.
    r.boxes.set(k, 2, Some(r.stack("tiamat_default_world:oak_log", 27)));
    r.tick(1180);
    assert_eq!(r.boxes.get(k, 5), None, "not yet");
    r.tick(60);
    assert_eq!(r.boxes.get(k, 5).map(|s| (s.material, s.units)), Some((r.material("charcoal"), 27)));

    // Ore at red heat does nothing: copper wants orange.
    r.boxes.set(k, 2, Some(r.stack("tiamat_default_world:copper_ore", 27)));
    r.boxes.set(k, 4, Some(tool(&r, "crucible", &crucible)));
    r.boxes.set(k, 5, None);
    r.tick(1000);
    assert_eq!(r.boxes.get(k, 5), None, "red heat does not melt copper");

    // It goes out when the fuel is gone, and shows it.
    r.tick(3200);
    assert_eq!(r.block_name(20, 64, 20), "tiamat_default_craft:kiln", "out");

    // Coal is orange heat: copper in a crucible is an ingot; the crucible stays.
    r.boxes.set(k, 1, Some(r.stack("tiamat_default_world:coal", 27 * 9)));
    assert_eq!(r.use_at(PLAYER, 20, 64, 20).as_deref(), Some(""));
    r.tick(940);
    assert_eq!(r.boxes.get(k, 5).map(|s| (s.material, s.units)), Some((r.material("copper_ingot"), 27)));
    assert_eq!(r.boxes.get(k, 4), Some(tool(&r, "crucible", &crucible)), "the crucible comes back");
    assert!(r.storage.dump().contains(&format!("first:{}:smelt:copper=", hex(PLAYER))));

    // Bronze: nine of copper, one of tin, ten out.
    r.boxes.set(k, 2, Some(r.stack("copper_ingot", 27 * 9)));
    r.boxes.set(k, 3, Some(r.stack("tin_ingot", 27)));
    r.boxes.set(k, 5, None);
    r.tick(940);
    assert_eq!(r.boxes.get(k, 5).map(|s| (s.material, s.units)), Some((r.material("bronze_ingot"), 270)));
    assert_eq!(r.boxes.get(k, 2), None);
    assert_eq!(r.boxes.get(k, 3), None);

    // Casting: three ingots and a pick mould are a head; four pours crack it.
    r.boxes.set(k, 2, Some(r.stack("bronze_ingot", 27 * 12)));
    r.boxes.set(k, 4, Some(tool(&r, "mould_pick", &mould)));
    r.boxes.set(k, 5, None);
    r.tick(640);
    assert_eq!(r.boxes.get(k, 5).map(|s| (s.material, s.units)), Some((r.material("bronze_pick_head"), 27)));
    assert!(r.boxes.get(k, 4).is_some(), "a mould survives a pour");
    r.tick(640 * 3);
    assert_eq!(r.boxes.get(k, 5).map(|s| s.units), Some(4 * 27), "four heads");
    assert_eq!(r.boxes.get(k, 4), None, "and the mould has cracked");

    // Iron ore: the kiln says what it wants.
    r.boxes.set(k, 2, Some(r.stack("tiamat_default_world:iron_ore", 27)));
    r.hold_nothing(PLAYER);
    assert_eq!(r.use_at(PLAYER, 20, 64, 20).as_deref(), Some(""));
    fit::check("the kiln", &r.screen(PLAYER));
    r.tick(40);
    assert!(r.screen_says(PLAYER, "The ore glows and does nothing. Iron wants a bloomery."));
    assert!(r.screen_says(PLAYER, "Orange heat"));
    r.close(PLAYER, "station");

    // Hafted at the workbench: the head and a haft are a bronze pick, with its serial.
    let heads = r.boxes.get(k, 5).unwrap();
    r.give(PLAYER, "workbench", 27);
    r.place(PLAYER, 22, 64, 20, "workbench").unwrap();
    let b = "tiamat_default_craft:workbench:22,64,20";
    r.boxes.set(b, 1, Some(heads));
    r.boxes.set(b, 2, Some(r.stack("haft", 27)));
    assert_eq!(r.use_at(PLAYER, 22, 64, 20).as_deref(), Some(""));
    r.press_labelled(PLAYER, "station", "Bronze pick");
    let made = r.boxes.get(b, 10).expect("a pick");
    assert_eq!(made.material, r.material("bronze_pick"));
    assert!(made.detail.as_deref().is_some_and(|d| d.starts_with("t=")), "minted with a serial");
    r.close(PLAYER, "station");

    // Life hears the kiln is a heat source.
    r.say("life heard heat tiamat_default_craft:kiln_lit 0.6");
    assert_eq!(r.said(), "yes");

    // A restart in the middle of a job: it carries on.
    r.boxes.set(k, 2, Some(r.stack("tiamat_default_world:gold_ore", 27)));
    r.boxes.set(k, 4, Some(tool(&r, "crucible", &crucible)));
    r.boxes.set(k, 5, None);
    r.tick(400);
    let mut r = Rig::new(Setup { world: true, life: true, restart: Some(r.saved()), ..Setup::default() });
    r.join(PLAYER);
    r.tick(560);
    assert_eq!(r.boxes.get(k, 5).map(|s| (s.material, s.units)), Some((r.material("gold_ingot"), 27)));
    println!("kiln: ok");
    r.storage.dump()
}

/// Cooking: a fire's box, meat roasted and left to char, a stew in a copper
/// pot, and what is on a fire that has gone out kept.
fn cooking() {
    let prelude = "tdc_overrides = { fire_fuel = 6000 }";
    let mut r = Rig::new(Setup { world: true, life: true, prelude: prelude.into(), ..Setup::default() });
    r.join(PLAYER);
    r.huds.operators.lock().unwrap().push(PLAYER);
    r.say("toolkit");
    r.tick(1);
    let striker = r.details(PLAYER, "fire_striker")[0].clone();
    let pot = r.details(PLAYER, "copper_pot")[0].clone();

    r.put(30, 64, 30, "unlit_campfire");
    r.hold(PLAYER, "fire_striker", Some(&striker));
    assert_eq!(r.use_at(PLAYER, 30, 64, 30).as_deref(), Some(""));
    r.hold_nothing(PLAYER);
    assert_eq!(r.use_at(PLAYER, 30, 64, 30).as_deref(), Some(""), "an empty hand opens the fire");
    let fire = "tiamat_default_craft:campfire:30,64,30";
    assert!(r.boxes.exists(fire));
    fit::check("the campfire", &r.screen(PLAYER));
    assert!(r.screen_says(PLAYER, "Burning"));

    // Two raw meat on the fire: one after the other, cooked.
    r.boxes.set(fire, 1, Some(r.stack("tiamat_default_life:raw_meat", 54)));
    r.tick(320);
    assert_eq!(r.boxes.get(fire, 4).map(|s| (s.material, s.units)), Some((r.material("tiamat_default_life:cooked_meat"), 27)));
    r.tick(300);
    assert_eq!(r.boxes.get(fire, 4).map(|s| s.units), Some(54));
    assert!(r.storage.dump().contains(&format!("first:{}:cook:meat=", hex(PLAYER))));

    // Left on the fire, it chars.
    r.tick(1220);
    assert_eq!(r.boxes.get(fire, 4).map(|s| (s.material, s.units)), Some((r.material("charred_meat"), 54)));
    r.say("life heard food tiamat_default_craft:charred_meat");
    assert_eq!(r.said(), "yes", "charred meat is food to Life");

    // Meat and fruit in a copper pot: a stew, not a roast. The pot stays.
    r.boxes.set(fire, 4, None);
    r.boxes.set(fire, 1, Some(r.stack("tiamat_default_life:raw_meat", 27)));
    r.boxes.set(fire, 2, Some(r.stack("tiamat_default_life:berries", 27)));
    let pot_stack = tiamat_core::inventory::Stack { detail: Some(pot.clone()), ..r.stack("copper_pot", 27) };
    r.boxes.set(fire, 3, Some(pot_stack.clone()));
    r.tick(620);
    assert_eq!(r.boxes.get(fire, 4).map(|s| (s.material, s.units)), Some((r.material("tiamat_default_life:hot_stew"), 27)));
    assert_eq!(r.boxes.get(fire, 3), Some(pot_stack), "the pot comes back");
    assert_eq!(r.boxes.get(fire, 1), None);
    r.close(PLAYER, "station");

    // Wet clay dries; a fire that goes out keeps what is on it, and cooks nothing.
    r.boxes.set(fire, 4, None);
    r.boxes.set(fire, 1, Some(r.stack("tiamat_default_world:wet_clay", 27)));
    r.tick(220);
    assert_eq!(r.boxes.get(fire, 4).map(|s| s.material), Some(r.world_material("dry_clay")));
    r.boxes.set(fire, 1, Some(r.stack("tiamat_default_life:raw_meat", 27)));
    r.boxes.set(fire, 4, None);
    r.world.apply(tiamat_core::BlockPos { x: 30, y: 64, z: 30 }, "tiamat_default_craft:unlit_campfire");
    r.tick(400);
    assert_eq!(r.boxes.get(fire, 4), None, "an unlit fire cooks nothing");
    assert_eq!(r.use_at(PLAYER, 30, 64, 30).as_deref(), Some(""), "and its box still opens");
    assert!(r.screen_says(PLAYER, "The fire is out."));
    r.close(PLAYER, "station");

    // The kiln bakes Life's bread.
    r.say("recipes kiln");
    let heard = r.heard(PLAYER).join(" ");
    assert!(heard.contains("bread") && heard.contains("oven_roast"), "{heard}");
    println!("cooking: ok");
}

/// One sluice washing nine blocks of gravel; answers the storage it left.
fn sluice_run() -> (Rig, String) {
    let mut r = Rig::new(Setup { world: true, life: true, ..Setup::default() });
    r.join(PLAYER);
    r.tick(1);
    r.give(PLAYER, "sluice", 54);

    // Dry ground: refused, and nothing is left behind.
    assert_eq!(r.place(PLAYER, 40, 64, 40, "sluice"), Err("A sluice needs running water.".into()));
    assert!(!r.boxes.exists("tiamat_default_craft:sluice:40,64,40"));

    // Water against a face: placed.
    r.world.fluids.lock().unwrap().insert((41, 64, 40), 27);
    r.place(PLAYER, 40, 64, 40, "sluice").unwrap();
    let s = "tiamat_default_craft:sluice:40,64,40";
    assert!(r.boxes.exists(s));

    r.boxes.set(s, 1, Some(r.stack("tiamat_default_world:gravel", 27 * 9)));
    r.tick(9 * 200 + 40);
    assert_eq!(r.boxes.get(s, 1), None, "all nine washed");
    assert_eq!(r.boxes.get(s, 2).map(|st| (st.material, st.units)), Some((r.world_material("sand"), 24 * 9)));
    assert_eq!(r.boxes.get(s, 3).map(|st| (st.material, st.units)), Some((r.material("tin_grain"), 27 * 9)));
    assert_eq!(r.boxes.get(s, 4).map(|st| (st.material, st.units)), Some((r.material("gold_flake"), 27)), "one flake in nine");
    let dump = r.storage.dump();
    (r, dump)
}

fn sluice() {
    let (mut r, first) = sluice_run();
    let (_, second) = sluice_run();
    assert_eq!(first, second, "two runs wash alike");

    // The water gone, washing stops.
    let s = "tiamat_default_craft:sluice:40,64,40";
    r.world.fluids.lock().unwrap().clear();
    r.boxes.set(s, 1, Some(r.stack("tiamat_default_world:gravel", 27)));
    r.tick(400);
    assert!(r.boxes.get(s, 1).is_some(), "no water, no washing");
    println!("sluice: ok");
}

/// Iron: the anvil squared from granite with a chisel, the bloomery refusing
/// coal and burning white only with bellows, a bloom beaten into a bar, the
/// first iron hammer forged with bronze, and an iron head with iron.
fn iron() {
    let mut r = Rig::new(Setup { world: true, life: true, ..Setup::default() });
    r.join(PLAYER);
    r.huds.operators.lock().unwrap().push(PLAYER);
    r.say("toolkit");
    r.tick(1);
    let d = |r: &Rig, id: &str| r.details(PLAYER, id)[0].clone();
    let tool = |r: &Rig, id: &str| tiamat_core::inventory::Stack { detail: Some(d(r, id)), ..r.stack(id, 27) };

    // The anvil: a block of granite and a bronze chisel's ten uses.
    r.give(PLAYER, "workbench", 27);
    r.place(PLAYER, 50, 64, 50, "workbench").unwrap();
    let bench = "tiamat_default_craft:workbench:50,64,50";
    r.boxes.set(bench, 1, Some(r.stack("tiamat_default_world:granite", 27)));
    assert_eq!(r.use_at(PLAYER, 50, 64, 50).as_deref(), Some(""));
    r.press_labelled(PLAYER, "station", "Stone anvil");
    assert_eq!(r.boxes.get(bench, 10).map(|s| s.material), Some(r.material("stone_anvil")));
    let chisels: Vec<String> = r.details(PLAYER, "bronze_chisel");
    assert!(chisels.iter().any(|d| d.ends_with(";w=10")), "the chisel wore ten, on the chisel: {chisels:?}");
    r.close(PLAYER, "station");

    // The bloomery: coal is refused by name.
    r.give(PLAYER, "bloomery", 27);
    r.place(PLAYER, 52, 64, 50, "bloomery").unwrap();
    let b = "tiamat_default_craft:bloomery:52,64,50";
    r.boxes.set(b, 1, Some(r.stack("tiamat_default_world:coal", 27)));
    r.hold(PLAYER, "fire_striker", Some(&d(&r, "fire_striker")));
    assert_eq!(r.use_at(PLAYER, 52, 64, 50).as_deref(), Some("Coal's sulphur spoils the bloom. It wants charcoal."));

    // Charcoal alone is orange heat: no bloom.
    r.boxes.set(b, 1, Some(r.stack("charcoal", 27 * 12)));
    assert_eq!(r.use_at(PLAYER, 52, 64, 50).as_deref(), Some(""));
    assert_eq!(r.block_name(52, 64, 50), "tiamat_default_craft:bloomery_lit");
    r.boxes.set(b, 2, Some(r.stack("tiamat_default_world:iron_ore", 54)));
    r.boxes.set(b, 3, Some(r.stack("charcoal", 27)));
    r.tick(2500);
    assert_eq!(r.boxes.get(b, 5), None, "orange heat makes no bloom");

    // Bellows in: white heat, and a bloom.
    r.boxes.set(b, 4, Some(tool(&r, "bellows")));
    r.hold_nothing(PLAYER);
    assert_eq!(r.use_at(PLAYER, 52, 64, 50).as_deref(), Some(""));
    fit::check("the bloomery", &r.screen(PLAYER));
    r.tick(40);
    assert!(r.screen_says(PLAYER, "White heat"));
    r.close(PLAYER, "station");
    r.tick(2460);
    assert_eq!(r.boxes.get(b, 5).map(|s| s.material), Some(r.material("iron_bloom")));
    assert!(r.storage.dump().contains(&format!("first:{}:bloom:iron=", hex(PLAYER))));
    r.say("life heard heat tiamat_default_craft:bloomery_lit 0.8");
    assert_eq!(r.said(), "yes");

    // On the anvil, three blows of a bronze hammer: a bar.
    r.give(PLAYER, "stone_anvil", 27);
    r.place(PLAYER, 54, 64, 50, "stone_anvil").unwrap();
    let a = "tiamat_default_craft:anvil:54,64,50";
    r.boxes.set(a, 1, r.boxes.get(b, 5));
    r.hold_nothing(PLAYER);
    assert_eq!(r.use_at(PLAYER, 54, 64, 50).as_deref(), Some(""), "an empty hand opens it");
    fit::check("the anvil", &r.screen(PLAYER));
    r.close(PLAYER, "station");
    let bronze_hammer = d(&r, "bronze_hammer");
    r.hold(PLAYER, "bronze_hammer", Some(&bronze_hammer));
    for _ in 0..2 {
        assert_eq!(r.use_at(PLAYER, 54, 64, 50).as_deref(), Some(""));
        assert_eq!(r.boxes.get(a, 2), None, "not yet");
    }
    assert_eq!(r.use_at(PLAYER, 54, 64, 50).as_deref(), Some(""));
    assert_eq!(r.boxes.get(a, 2).map(|s| s.material), Some(r.material("iron_bar")));

    // A head wants an iron hammer...
    r.boxes.set(a, 2, None);
    r.boxes.set(a, 1, Some(r.stack("iron_bar", 27 * 5)));
    r.hold_nothing(PLAYER);
    r.use_at(PLAYER, 54, 64, 50);
    r.press_labelled(PLAYER, "station", "Iron pick head");
    r.close(PLAYER, "station");
    r.hold(PLAYER, "bronze_hammer", Some(&bronze_hammer));
    assert_eq!(r.use_at(PLAYER, 54, 64, 50).as_deref(), Some("That takes the iron hammer."));

    // ...but the first iron hammer is forged with bronze, eight blows, double wear.
    r.hold_nothing(PLAYER);
    r.use_at(PLAYER, 54, 64, 50);
    r.press_labelled(PLAYER, "station", "First iron hammer head");
    r.close(PLAYER, "station");
    r.hold(PLAYER, "bronze_hammer", Some(&bronze_hammer));
    for _ in 0..8 {
        assert_eq!(r.use_at(PLAYER, 54, 64, 50).as_deref(), Some(""));
    }
    assert_eq!(r.boxes.get(a, 2).map(|s| s.material), Some(r.material("iron_hammer_head")));
    let serial = bronze_hammer.trim_start_matches("t=");
    assert!(r.details(PLAYER, "bronze_hammer").contains(&format!("t={serial};w=3")), "one for the bar, two for this");

    // With an iron hammer, five blows and three bars: an iron pick head.
    r.boxes.set(a, 2, None);
    r.hold_nothing(PLAYER);
    r.use_at(PLAYER, 54, 64, 50);
    r.press_labelled(PLAYER, "station", "Iron pick head");
    r.close(PLAYER, "station");
    r.hold(PLAYER, "iron_hammer", Some(&d(&r, "iron_hammer")));
    for _ in 0..5 {
        assert_eq!(r.use_at(PLAYER, 54, 64, 50).as_deref(), Some(""));
    }
    assert_eq!(r.boxes.get(a, 2).map(|s| s.material), Some(r.material("iron_pick_head")));
    assert_eq!(r.boxes.get(a, 1), None, "the three bars left went into it");
    assert!(r.storage.dump().contains(&format!("first:{}:forge:iron_pick=", hex(PLAYER))));
    println!("iron: ok");
}

/// The torch burns out; the HUD says how worn the tool is and warns before
/// a refused dig; and the HUD script draws every state it can be sent.
fn torch_and_hud() {
    let mut r = Rig::new(Setup { world: true, life: true, ..Setup::default() });
    r.join(PLAYER);
    r.tick(1);

    // Torches by hand, and one burning out on a random tick.
    r.give(PLAYER, "tiamat_default_world:oak_log", 54);
    r.give(PLAYER, "tiamat_default_world:tall_grass", 9);
    for recipe in ["stick", "bark_strip", "tinder", "torch"] {
        r.say(&format!("craft {recipe}"));
        assert!(r.said().starts_with("made"), "{recipe}");
    }
    assert_eq!(r.units(PLAYER, "torch"), 54);
    r.put(60, 64, 60, "torch");
    let out = r.vm.random_tick(&tiamat_core::script::RandomTickEvent {
        pos: tiamat_core::BlockPos { x: 60, y: 64, z: 60 },
        material: r.material("torch"),
    });
    assert!(out.faults.is_empty(), "{:?}", out.faults);
    assert_eq!(r.block_name(60, 64, 60), "tiamat_default_craft:spent_torch");

    // The HUD: a bronze pick in hand is whole; worn, it says so.
    r.huds.operators.lock().unwrap().push(PLAYER);
    r.say("toolkit");
    let pick = r.details(PLAYER, "bronze_pick")[0].clone();
    r.hold(PLAYER, "bronze_pick", Some(&pick));
    r.tick(10);
    let hud = |r: &Rig, key: &str| r.huds.values.lock().unwrap().get(&PLAYER).and_then(|v| v.get(key).cloned());
    use tiamat_core::hud::Value;
    assert_eq!(hud(&r, "wear"), Some(Value::Number(1000.0)));
    assert_eq!(hud(&r, "warn"), Some(Value::Flag(false)));
    for _ in 0..85 {
        r.dig(PLAYER, "tiamat_default_world:stone").unwrap();
    }
    r.tick(10);
    assert_eq!(hud(&r, "wear"), Some(Value::Number(150.0)));

    // Pointing a bare hand at stone: the warning, before any click.
    r.hold_nothing(PLAYER);
    r.put(61, 64, 60, "tiamat_default_world:stone");
    *r.world.aimed.lock().unwrap() = Some((61, 64, 60));
    r.tick(10);
    assert_eq!(hud(&r, "warn"), Some(Value::Flag(true)));
    assert_eq!(hud(&r, "wear"), Some(Value::Number(-1.0)));
    *r.world.aimed.lock().unwrap() = None;

    // The HUD script, drawn as a client draws it, in every state.
    let dir = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../mods").join(MOD);
    let source = std::fs::read_to_string(dir.join("hud.lua")).unwrap();
    let states: Vec<(&str, Vec<(&str, Value)>, usize)> = vec![
        ("nothing sent", vec![], 0),
        ("a whole tool", vec![("wear", Value::Number(1000.0)), ("warn", Value::Flag(false))], 5),
        ("nearly gone, and warned", vec![("wear", Value::Number(150.0)), ("warn", Value::Flag(true))], 6),
        ("a hand", vec![("wear", Value::Number(-1.0)), ("warn", Value::Flag(false))], 0),
    ];
    for (name, values, want) in states {
        let mut vm = tiamat_core::script::HudVm::new(tiamat_core::script::HudLimits::default()).unwrap();
        vm.load(MOD, &source).expect("hud.lua loads");
        let mut state = tiamat_core::hud::State::default();
        state.values.insert(MOD.into(), values.into_iter().map(|(k, v)| (k.to_owned(), v)).collect());
        let faults = vm.draw(&state);
        assert!(faults.is_empty(), "hud faults on {name}: {faults:?}");
        let commands = vm.with_frame(|f| f.commands().len()).unwrap();
        assert_eq!(commands, want, "draw commands for {name}");
    }
    println!("torch and hud: ok");
}

/// After the loop: parts forged from bars (each conserving units), the iron
/// frame, a bronze gear, brick, ash from a burned-out fire, glass, and a
/// lantern that does not burn out.
const PARTS_CHECK: &str = r##"
local craft = game.exports("tiamat_default_craft")
local parts = { iron_plate = true, iron_nails = true, iron_chain = true, iron_hinge = true,
    bronze_gear = true, brick = true }
local seen = 0
for _, recipe in ipairs(craft.recipes()) do
    local short = string.match(recipe.id, "^tiamat_default_craft:(.+)$")
    if short and parts[short] then
        local into, out = 0, 0
        for _, e in ipairs(recipe.inputs) do into = into + e.units end
        for _, e in ipairs(recipe.outputs) do out = out + e.units end
        assert(into == out, recipe.id .. " takes " .. into .. " and gives " .. out)
        seen = seen + 1
    end
end
assert(seen == 6, "six parts, saw " .. seen)
"##;

fn after_the_loop() {
    let prelude = "tdc_overrides = { fire_fuel = 200 }";
    let mut r = Rig::new(Setup {
        world: true,
        life: true,
        prelude: prelude.into(),
        fixtures: vec![("parts_check".into(), PARTS_CHECK.into())],
        ..Setup::default()
    });
    r.join(PLAYER);
    r.huds.operators.lock().unwrap().push(PLAYER);
    r.say("toolkit");
    r.tick(1);
    let d = |r: &Rig, id: &str| r.details(PLAYER, id)[0].clone();
    let tool = |r: &Rig, id: &str| tiamat_core::inventory::Stack { detail: Some(d(r, id)), ..r.stack(id, 27) };

    // Every part conserves, as the registry holds a `conserve` recipe to:
    // the fixture asserts it through the exports, at its load.
    // Parts on the anvil with an iron hammer.
    r.give(PLAYER, "stone_anvil", 27);
    r.place(PLAYER, 70, 64, 70, "stone_anvil").unwrap();
    let a = "tiamat_default_craft:anvil:70,64,70";
    let hammer = d(&r, "iron_hammer");
    for (part, blows) in [("Iron plate", 5), ("Iron nails", 3)] {
        r.boxes.set(a, 1, Some(r.stack("iron_bar", 27)));
        r.boxes.set(a, 2, None);
        r.hold_nothing(PLAYER);
        r.use_at(PLAYER, 70, 64, 70);
        r.press_labelled(PLAYER, "station", part);
        r.close(PLAYER, "station");
        r.hold(PLAYER, "iron_hammer", Some(&hammer));
        for _ in 0..blows {
            assert_eq!(r.use_at(PLAYER, 70, 64, 70).as_deref(), Some(""));
        }
        let made = r.boxes.get(a, 2).expect(part);
        assert_eq!(made.units, 27, "{part}: a bar's units, whole");
    }

    // The iron frame: four plates and nails, a hammer at hand.
    r.give(PLAYER, "workbench", 27);
    r.place(PLAYER, 72, 64, 70, "workbench").unwrap();
    let b = "tiamat_default_craft:workbench:72,64,70";
    r.boxes.set(b, 1, Some(r.stack("iron_plate", 27 * 4)));
    r.boxes.set(b, 2, Some(r.stack("iron_nails", 27)));
    r.hold_nothing(PLAYER);
    r.use_at(PLAYER, 72, 64, 70);
    r.press_labelled(PLAYER, "station", "Iron frame");
    assert_eq!(r.boxes.get(b, 10).map(|s| s.material), Some(r.material("iron_frame")));
    // A lantern: a plate, glass and a torch.
    r.boxes.set(b, 10, None);
    r.boxes.set(b, 1, Some(r.stack("iron_plate", 27)));
    r.boxes.set(b, 2, Some(r.stack("glass", 27)));
    r.boxes.set(b, 3, Some(r.stack("torch", 27)));
    r.press_labelled(PLAYER, "station", "Iron lantern");
    assert_eq!(r.boxes.get(b, 10).map(|s| s.material), Some(r.material("iron_lantern")));
    r.close(PLAYER, "station");

    // A fire burned out leaves ash on it.
    r.put(74, 64, 70, "unlit_campfire");
    r.hold(PLAYER, "fire_striker", Some(&d(&r, "fire_striker")));
    assert_eq!(r.use_at(PLAYER, 74, 64, 70).as_deref(), Some(""));
    r.tick(260);
    assert_eq!(r.block_name(74, 64, 70), "tiamat_default_craft:unlit_campfire");
    let fire = "tiamat_default_craft:campfire:74,64,70";
    assert_eq!(r.boxes.get(fire, 4).map(|s| s.material), Some(r.material("ash")), "ash on the dead fire");

    // In a kiln at orange heat: glass from white sand and ash (the world's
    // volcanic ash does as well), brick from mudbrick, a gear from bronze.
    r.give(PLAYER, "kiln", 27);
    r.place(PLAYER, 76, 64, 70, "kiln").unwrap();
    let k = "tiamat_default_craft:kiln:76,64,70";
    r.boxes.set(k, 1, Some(r.stack("tiamat_default_world:coal", 27 * 9)));
    r.hold(PLAYER, "fire_striker", Some(&d(&r, "fire_striker")));
    assert_eq!(r.use_at(PLAYER, 76, 64, 70).as_deref(), Some(""));
    r.boxes.set(k, 2, Some(r.stack("tiamat_default_world:white_sand", 27)));
    r.boxes.set(k, 3, Some(r.stack("tiamat_default_world:volcanic_ash", 9)));
    r.tick(640);
    assert_eq!(r.boxes.get(k, 5).map(|s| s.material), Some(r.material("glass")));
    r.boxes.set(k, 5, None);
    r.boxes.set(k, 2, Some(r.stack("mudbrick", 27)));
    r.tick(440);
    assert_eq!(r.boxes.get(k, 5).map(|s| (s.material, s.units)), Some((r.material("brick"), 27)));
    r.boxes.set(k, 5, None);
    r.boxes.set(k, 2, Some(r.stack("bronze_ingot", 27)));
    r.boxes.set(k, 4, Some(tool(&r, "mould_gear")));
    r.tick(640);
    assert_eq!(r.boxes.get(k, 5).map(|s| (s.material, s.units)), Some((r.material("bronze_gear"), 27)));

    // Brick is masonry: a pick's, not a hand's.
    r.hold_nothing(PLAYER);
    assert!(r.dig_start(PLAYER, "brick").is_err());
    println!("after the loop: ok");
}

/// The progress mod's asks: requirements set from outside, a study that
/// makes nothing, and each node effect moving the number it names.
fn progress_asks() {
    let prelude = "tdc_overrides = { fire_fuel = 4000 }";
    let mut r = Rig::new(Setup {
        world: true,
        life: true,
        prelude: prelude.into(),
        fixtures: vec![("tiamat_default_progress".into(), PROGRESS_STANDIN.into())],
        ..Setup::default()
    });
    r.join(PLAYER);
    r.huds.operators.lock().unwrap().push(PLAYER);
    r.say("toolkit");
    r.tick(1);
    let d = |r: &Rig, id: &str| r.details(PLAYER, id)[0].clone();
    let tool = |r: &Rig, id: &str| tiamat_core::inventory::Stack { detail: Some(d(r, id)), ..r.stack(id, 27) };

    // Only while mods load.
    r.say("q late");
    assert_eq!(r.said(), "nil");

    // A study: a copper ingot on the table, nothing made, the insight heard.
    r.say("q set craft.none 0");
    r.said();
    r.give(PLAYER, "copper_ingot", 27);
    r.say("q study");
    assert_eq!(r.said(), "nil 20 0", "refused: \"missing copper ingot\"");
    r.boxes.set("progress:table", 1, Some(r.stack("copper_ingot", 27)));
    r.say("q study");
    assert_eq!(r.said(), "true 0 10", "made, nothing out, and heard");
    assert_eq!(r.boxes.get("progress:table", 1), None);

    // Fire-setting 200 ticks sooner.
    r.say("q set craft.fireset_ticks -200");
    r.put(80, 64, 80, "unlit_campfire");
    r.put(81, 64, 80, "tiamat_default_world:stone");
    r.hold(PLAYER, "fire_striker", Some(&d(&r, "fire_striker")));
    assert_eq!(r.use_at(PLAYER, 80, 64, 80).as_deref(), Some(""));
    r.tick(420);
    assert_eq!(r.block_name(81, 64, 80), "tiamat_default_craft:cracked_stone", "cracked at 400");

    // A kiln: charcoal a third more, copper from 18 units of ore.
    r.say("q set craft.charcoal_yield 3");
    r.say("q set craft.smelt_ore_units -9");
    r.give(PLAYER, "kiln", 27);
    r.place(PLAYER, 82, 64, 80, "kiln").unwrap();
    let k = "tiamat_default_craft:kiln:82,64,80";
    r.boxes.set(k, 1, Some(r.stack("tiamat_default_world:coal", 27 * 9)));
    assert_eq!(r.use_at(PLAYER, 82, 64, 80).as_deref(), Some(""));
    r.boxes.set(k, 2, Some(r.stack("tiamat_default_world:oak_log", 27)));
    r.tick(1240);
    assert_eq!(r.boxes.get(k, 5).map(|s| s.units), Some(36), "a log is a charcoal and a third");
    r.boxes.set(k, 5, None);
    r.boxes.set(k, 2, Some(r.stack("tiamat_default_world:copper_ore", 18)));
    r.boxes.set(k, 4, Some(tool(&r, "crucible")));
    r.tick(940);
    assert_eq!(r.boxes.get(k, 5).map(|s| (s.material, s.units)), Some((r.material("copper_ingot"), 27)), "from 18 units");

    // The anvil: a blow fewer.
    r.say("q set craft.anvil_strikes -1");
    r.give(PLAYER, "stone_anvil", 27);
    r.place(PLAYER, 84, 64, 80, "stone_anvil").unwrap();
    let a = "tiamat_default_craft:anvil:84,64,80";
    r.boxes.set(a, 1, Some(r.stack("iron_bloom", 27)));
    r.hold(PLAYER, "bronze_hammer", Some(&d(&r, "bronze_hammer")));
    for _ in 0..2 {
        assert_eq!(r.use_at(PLAYER, 84, 64, 80).as_deref(), Some(""));
    }
    assert_eq!(r.boxes.get(a, 2).map(|s| s.material), Some(r.material("iron_bar")), "two blows, not three");

    // Tools last longer: a bronze pick's hundred uses are a hundred and twenty-five.
    r.say("q set craft.uses_percent.bronze 25");
    r.hold(PLAYER, "bronze_pick", Some(&d(&r, "bronze_pick")));
    r.say("q tool");
    assert_eq!(r.said(), "0/125");

    // A chisel wears half as fast: two uses, one of wear.
    r.say("q set craft.chisel_wear_percent -50");
    r.hold(PLAYER, "bronze_chisel", Some(&d(&r, "bronze_chisel")));
    r.dig(PLAYER, "tiamat_default_world:stone").unwrap();
    r.dig(PLAYER, "tiamat_default_world:stone").unwrap();
    r.say("q tool");
    assert_eq!(r.said(), "1/250", "one wear for two uses (and bronze lasts a quarter longer)");
    println!("progress asks: ok");
}

/// Wear rides on the tool: rewritten in the slot it is held in, and an old
/// world's wear, kept in storage, moved onto it at its next use.
fn wear_on_the_tool() {
    let mut r = Rig::new(Setup { world: true, ..Setup::default() });
    r.join(PLAYER);
    r.huds.operators.lock().unwrap().push(PLAYER);
    r.say("toolkit");
    r.tick(1);
    let pick = r.details(PLAYER, "bronze_pick")[0].clone();
    let serial = pick.trim_start_matches("t=").to_owned();
    r.hold(PLAYER, "bronze_pick", Some(&pick));
    let slot = *r.inventory.held.lock().unwrap().get(&PLAYER).unwrap();

    // An old world kept fifty uses of wear in storage.
    use tiamat_core::storage::Access;
    r.storage.set(MOD, &format!("wear:{serial}"), Some(tiamat_core::storage::Value::Number(50.0)));
    r.dig(PLAYER, "tiamat_default_world:stone").unwrap();
    assert_eq!(r.details(PLAYER, "bronze_pick"), vec![format!("t={serial};w=51")]);
    assert!(!r.storage.dump().contains("wear:"), "moved off storage");

    // Still in the hand, in the same slot, and still the tool in hand.
    assert_eq!(*r.inventory.held.lock().unwrap().get(&PLAYER).unwrap(), slot);
    let held = tiamat_core::inventory::Access::held(&*r.inventory, PLAYER).expect("held");
    assert_eq!(held.detail.as_deref(), Some(format!("t={serial};w=51").as_str()));
    r.tick(1);
    assert_eq!(r.tool(PLAYER).as_deref(), Some("tiamat_default_craft:bronze_pick"));
    println!("wear on the tool: ok");
}

/// The anvil worked as the brief meant: the work in the off-hand, a hammer
/// in the main hand, a blow a use.
fn anvil_offhand() {
    let mut r = Rig::new(Setup { world: true, ..Setup::default() });
    r.join(PLAYER);
    r.huds.operators.lock().unwrap().push(PLAYER);
    r.say("toolkit");
    r.tick(1);
    let d = |r: &Rig, id: &str| r.details(PLAYER, id)[0].clone();
    r.give(PLAYER, "stone_anvil", 27);
    r.place(PLAYER, 90, 64, 90, "stone_anvil").unwrap();

    // The off-hand is slot 28 of the pack (27 zero-based).
    let offhand = |r: &Rig, stack: Option<tiamat_core::inventory::Stack>| {
        let mut views = r.inventory.views.lock().unwrap();
        let slots = views.entry((PLAYER, "player:main".into())).or_default();
        while slots.len() < 28 {
            slots.push(None);
        }
        slots[27] = stack;
    };
    let in_offhand = |r: &Rig| tiamat_core::inventory::Access::slot(&*r.inventory, PLAYER, "player:main", 27);

    // A bloom in the off-hand, three blows of a bronze hammer: a bar, in the off-hand.
    offhand(&r, Some(r.stack("iron_bloom", 27)));
    r.hold(PLAYER, "bronze_hammer", Some(&d(&r, "bronze_hammer")));
    for _ in 0..3 {
        assert_eq!(r.use_at(PLAYER, 90, 64, 90).as_deref(), Some(""));
    }
    assert_eq!(in_offhand(&r).map(|s| (s.material, s.units)), Some((r.material("iron_bar"), 27)));
    assert!(r.storage.dump().contains(&format!("first:{}:forge:iron_bar=", hex(PLAYER))));

    // Five bars held; the pick head chosen on the anvil's screen; five blows
    // of the iron hammer. The head goes to the pack, the two bars left stay.
    offhand(&r, Some(r.stack("iron_bar", 27 * 5)));
    r.hold_nothing(PLAYER);
    assert_eq!(r.use_at(PLAYER, 90, 64, 90).as_deref(), Some(""));
    r.press_labelled(PLAYER, "station", "Iron pick head");
    r.close(PLAYER, "station");
    r.hold(PLAYER, "iron_hammer", Some(&d(&r, "iron_hammer")));
    for _ in 0..5 {
        assert_eq!(r.use_at(PLAYER, 90, 64, 90).as_deref(), Some(""));
    }
    assert_eq!(in_offhand(&r).map(|s| s.units), Some(54), "two bars left in the hand");
    assert_eq!(r.units(PLAYER, "iron_pick_head"), 27);

    // Nothing the hammer can work: said so.
    offhand(&r, Some(r.stack("tiamat_default_world:dirt", 27)));
    assert_eq!(r.use_at(PLAYER, 90, 64, 90).as_deref(), Some("Nothing in your off-hand that hammer can work."));
    println!("anvil off-hand: ok");
}
