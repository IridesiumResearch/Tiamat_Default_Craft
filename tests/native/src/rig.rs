// SPDX-FileCopyrightText: Iridesium
// SPDX-License-Identifier: GPL-3.0-only
//
// The fake server the mod runs in.
//
// Nothing is mocked at the Lua level: the mod's own files load through
// `EngineVm::load_mod`, and its hooks fire through the same trait the server
// calls. What is faked is the world around it — a player body, an inventory,
// the world's containers, the tool in each hand, storage, a map of blocks and
// fluid, each player's chat — and each fake keeps the engine's rules where the
// mod leans on them: a container slot holds one stack, capped at ninety
// items; a take matches material, cut and detail exactly; a tool nobody
// registered is refused.

use std::{
    collections::{BTreeMap, HashMap},
    path::PathBuf,
    sync::{Arc, Mutex},
};

use tiamat_core::{
    BlockPos, MaterialId,
    ent::{self, Entity, EntityId, Owner, Transform},
    fluid::{self, Fluid, FluidId},
    hud::{self, Values},
    identity::PlayerUuid,
    inventory::{self, Shape, Stack, stack_capacity},
    light::{Light, LightSource},
    particle::{self, BadgeRequest, EmitRequest},
    phys::Abilities,
    script::{ChatEvent, EngineVm, JoinEvent, ScriptVm, VmLimits, WorldEdit},
    sight::{self, Looked, Reading, Sighting, Skip, Surface},
    sound::{self, LoopRequest, PlayRequest},
    storage,
    ui::host::{self as uihost, ShowRequest},
};

pub const MOD: &str = "tiamat_default_craft";
pub const PLAYER: [u8; 32] = [7; 32];
pub const OTHER: [u8; 32] = [9; 32];

pub fn hex(player: [u8; 32]) -> String {
    player.iter().map(|b| format!("{b:02x}")).collect()
}

// --- Storage -------------------------------------------------------------------

#[derive(Default)]
pub struct Storage(pub Mutex<BTreeMap<(String, String), storage::Value>>);

impl storage::Access for Storage {
    fn get(&self, mod_id: &str, key: &str) -> Option<storage::Value> {
        self.0.lock().unwrap().get(&(mod_id.into(), key.into())).cloned()
    }
    fn set(&self, mod_id: &str, key: &str, value: Option<storage::Value>) {
        let mut map = self.0.lock().unwrap();
        match value {
            Some(v) => {
                map.insert((mod_id.into(), key.into()), v);
            }
            None => {
                map.remove(&(mod_id.into(), key.into()));
            }
        }
    }
    fn keys(&self, mod_id: &str) -> Vec<String> {
        self.0.lock().unwrap().keys().filter(|(m, _)| m == mod_id).map(|(_, k)| k.clone()).collect()
    }
}

impl Storage {
    /// This mod's storage as one sorted string, for comparing two runs.
    pub fn dump(&self) -> String {
        self.0
            .lock()
            .unwrap()
            .iter()
            .filter(|((m, _), _)| m == MOD)
            .map(|((_, k), v)| format!("{k}={v:?}"))
            .collect::<Vec<_>>()
            .join("\n")
    }
}

// --- Inventory -------------------------------------------------------------------

/// Each player's views, consolidated per material, cut and detail as the
/// engine reports them; and which stack is in the hand.
#[derive(Default)]
pub struct Inventory {
    pub views: Mutex<HashMap<([u8; 32], String), Vec<Stack>>>,
    pub held: Mutex<HashMap<[u8; 32], (MaterialId, Option<String>)>>,
}

fn same(a: &Stack, material: MaterialId, shape: Option<Shape>, detail: Option<&str>) -> bool {
    a.material == material && a.shape == shape && a.detail.as_deref() == detail
}

impl Inventory {
    pub fn units_of(&self, player: [u8; 32], material: MaterialId) -> u32 {
        self.views
            .lock()
            .unwrap()
            .get(&(player, "player:main".into()))
            .map(|v| v.iter().filter(|s| s.material == material).map(|s| s.units).sum())
            .unwrap_or(0)
    }
    pub fn stacks(&self, player: [u8; 32]) -> Vec<Stack> {
        self.views.lock().unwrap().get(&(player, "player:main".into())).cloned().unwrap_or_default()
    }
    pub fn put(&self, player: [u8; 32], stack: Stack) {
        inventory::Access::give(self, player, "player:main", None, stack);
    }
    pub fn clear(&self, player: [u8; 32]) {
        self.views.lock().unwrap().remove(&(player, "player:main".into()));
        self.held.lock().unwrap().remove(&player);
    }
}

impl inventory::Access for Inventory {
    fn contents(&self, player: [u8; 32], view: &str) -> Vec<Stack> {
        self.views.lock().unwrap().get(&(player, view.to_owned())).cloned().unwrap_or_default()
    }
    /// The view is kept consolidated, so a named slot lands where any give
    /// would: nothing here reads slot positions in a player's view.
    fn give(&self, player: [u8; 32], view: &str, _slot: Option<usize>, stack: Stack) -> bool {
        let mut views = self.views.lock().unwrap();
        let list = views.entry((player, view.to_owned())).or_default();
        if let Some(existing) = list.iter_mut().find(|s| same(s, stack.material, stack.shape, stack.detail.as_deref())) {
            existing.units += stack.units;
        } else {
            list.push(stack);
        }
        true
    }
    fn held(&self, player: [u8; 32]) -> Option<Stack> {
        let (material, detail) = self.held.lock().unwrap().get(&player).cloned()?;
        self.views
            .lock()
            .unwrap()
            .get(&(player, "player:main".into()))?
            .iter()
            .find(|s| s.material == material && s.detail == detail)
            .cloned()
    }
    fn take(
        &self,
        player: [u8; 32],
        view: &str,
        _slot: Option<usize>,
        material: MaterialId,
        shape: Option<Shape>,
        detail: Option<&str>,
        units: u32,
    ) -> u32 {
        let mut views = self.views.lock().unwrap();
        let Some(list) = views.get_mut(&(player, view.to_owned())) else { return 0 };
        let mut got = 0;
        for stack in list.iter_mut() {
            if same(stack, material, shape, detail) {
                let take = units.saturating_sub(got).min(stack.units);
                stack.units -= take;
                got += take;
            }
        }
        list.retain(|s| s.units > 0);
        got
    }
}

// --- Containers -------------------------------------------------------------------

#[derive(Default)]
pub struct Boxes {
    pub slots: Mutex<BTreeMap<String, Vec<Option<Stack>>>>,
    pub holders: Mutex<HashMap<String, [u8; 32]>>,
}

impl Boxes {
    /// Puts a stack straight into a slot (one-based), replacing what was there.
    pub fn set(&self, name: &str, slot: usize, stack: Option<Stack>) {
        let mut all = self.slots.lock().unwrap();
        let list = all.get_mut(name).unwrap_or_else(|| panic!("no container {name}"));
        list[slot - 1] = stack;
    }
    pub fn get(&self, name: &str, slot: usize) -> Option<Stack> {
        self.slots.lock().unwrap().get(name).and_then(|l| l.get(slot - 1).cloned().flatten())
    }
    pub fn exists(&self, name: &str) -> bool {
        self.slots.lock().unwrap().contains_key(name)
    }
}

impl inventory::Containers for Boxes {
    fn ensure(&self, name: &str, slots: usize) -> bool {
        let mut all = self.slots.lock().unwrap();
        if all.contains_key(name) {
            return false;
        }
        all.insert(name.to_owned(), vec![None; slots]);
        true
    }
    fn open(&self, name: &str, player: [u8; 32]) -> bool {
        if !self.exists(name) {
            return false;
        }
        let mut holders = self.holders.lock().unwrap();
        match holders.get(name) {
            Some(p) if *p != player => false,
            _ => {
                holders.insert(name.to_owned(), player);
                true
            }
        }
    }
    fn close(&self, name: &str, player: [u8; 32]) -> bool {
        let mut holders = self.holders.lock().unwrap();
        if holders.get(name) == Some(&player) {
            holders.remove(name);
            return true;
        }
        false
    }
    fn slots(&self, name: &str) -> Vec<Option<Stack>> {
        self.slots.lock().unwrap().get(name).cloned().unwrap_or_default()
    }
    fn give(&self, name: &str, slot: Option<usize>, stack: Stack) -> u32 {
        let mut all = self.slots.lock().unwrap();
        let Some(list) = all.get_mut(name) else { return 0 };
        let cap = stack_capacity(stack.shape);
        let mut left = stack.units;
        let indices: Vec<usize> = match slot {
            // Zero-based here: the engine has already taken one off the
            // mod's one-based slot.
            Some(s) if s < list.len() => vec![s],
            Some(_) => return 0,
            // Onto matching stacks first, then into empty slots, in slot order.
            None => {
                let mut matching: Vec<usize> = (0..list.len())
                    .filter(|i| list[*i].as_ref().is_some_and(|s| same(s, stack.material, stack.shape, stack.detail.as_deref())))
                    .collect();
                matching.extend((0..list.len()).filter(|i| list[*i].is_none()));
                matching
            }
        };
        for i in indices {
            if left == 0 {
                break;
            }
            match &mut list[i] {
                Some(existing) if same(existing, stack.material, stack.shape, stack.detail.as_deref()) => {
                    let room = cap.saturating_sub(existing.units).min(left);
                    existing.units += room;
                    left -= room;
                }
                Some(_) => {}
                empty @ None => {
                    let put = cap.min(left);
                    *empty = Some(Stack { units: put, ..stack.clone() });
                    left -= put;
                }
            }
        }
        stack.units - left
    }
    fn take(
        &self,
        name: &str,
        slot: Option<usize>,
        material: MaterialId,
        shape: Option<Shape>,
        detail: Option<&str>,
        units: u32,
    ) -> u32 {
        let mut all = self.slots.lock().unwrap();
        let Some(list) = all.get_mut(name) else { return 0 };
        let indices: Vec<usize> = match slot {
            // Zero-based here: the engine has already taken one off the
            // mod's one-based slot.
            Some(s) if s < list.len() => vec![s],
            Some(_) => return 0,
            None => (0..list.len()).collect(),
        };
        let mut got = 0;
        for i in indices {
            if let Some(stack) = &mut list[i]
                && same(stack, material, shape, detail)
            {
                let take = units.saturating_sub(got).min(stack.units);
                stack.units -= take;
                got += take;
                if stack.units == 0 {
                    list[i] = None;
                }
            }
        }
        got
    }
    fn remove(&self, name: &str) -> Vec<Stack> {
        if self.holders.lock().unwrap().contains_key(name) {
            return Vec::new();
        }
        self.slots.lock().unwrap().remove(name).unwrap_or_default().into_iter().flatten().collect()
    }
    fn holder(&self, name: &str) -> Option<[u8; 32]> {
        self.holders.lock().unwrap().get(name).copied()
    }
    fn names(&self, prefix: &str) -> Vec<String> {
        self.slots.lock().unwrap().keys().filter(|n| n.starts_with(prefix)).cloned().collect()
    }
}

// --- Tools -------------------------------------------------------------------

/// The tool in each player's hand, and every `set_tool` call, so a test can
/// count them: the engine cancels a dig on every call, so the mod must not
/// make one it does not need.
#[derive(Default)]
pub struct Tools {
    pub hand: Mutex<HashMap<[u8; 32], Option<String>>>,
    pub calls: Mutex<Vec<String>>,
    pub known: Mutex<Vec<String>>,
}

impl tiamat_core::dig::Tools for Tools {
    fn tool(&self, player: [u8; 32]) -> Option<String> {
        self.hand.lock().unwrap().get(&player).cloned().flatten()
    }
    fn set_tool(&self, player: [u8; 32], tool: Option<&str>) -> bool {
        if let Some(t) = tool
            && !self.known.lock().unwrap().iter().any(|k| k == t)
        {
            return false;
        }
        self.calls.lock().unwrap().push(tool.unwrap_or("-").to_owned());
        self.hand.lock().unwrap().insert(player, tool.map(str::to_owned));
        true
    }
}

// --- HUD, chat and operators ------------------------------------------------------

#[derive(Default)]
pub struct Huds {
    pub values: Mutex<HashMap<[u8; 32], Values>>,
    pub operators: Mutex<Vec<[u8; 32]>>,
    pub chat: Mutex<Vec<([u8; 32], String)>>,
}

impl hud::Access for Huds {
    fn set_hud(&self, mod_id: &str, player: [u8; 32], values: Values) -> bool {
        if mod_id == MOD {
            self.values.lock().unwrap().insert(player, values);
        }
        true
    }
    fn is_operator(&self, player: [u8; 32]) -> bool {
        self.operators.lock().unwrap().contains(&player)
    }
    fn chat_to(&self, player: [u8; 32], text: &str) -> bool {
        self.chat.lock().unwrap().push((player, text.to_owned()));
        true
    }
}

// --- Dialogs, sounds, particles -----------------------------------------------------

#[derive(Default)]
pub struct Dialogs {
    pub shown: Mutex<Vec<ShowRequest>>,
    pub closed: Mutex<Vec<(String, String)>>,
}

impl uihost::Access for Dialogs {
    fn show(&self, request: &ShowRequest) -> bool {
        tiamat_core::ui::check(&request.tree, tiamat_core::ui::Limits::default())
            .expect("every tree the mod sends passes the engine's checker");
        self.shown.lock().unwrap().push(request.clone());
        true
    }
    fn close(&self, player: &str, form: &str) -> bool {
        self.closed.lock().unwrap().push((player.to_owned(), form.to_owned()));
        true
    }
}

#[derive(Default)]
pub struct Sounds {
    pub plays: Mutex<Vec<String>>,
    pub time: Mutex<f32>,
}

impl sound::Access for Sounds {
    fn play(&self, request: &PlayRequest) -> u32 {
        self.plays.lock().unwrap().push(request.sound.clone());
        1
    }
    fn start_loop(&self, _: &LoopRequest) -> u32 {
        1
    }
    fn time_of_day(&self) -> f32 {
        *self.time.lock().unwrap()
    }
    fn stop_loop(&self, _: &sound::StopRequest) -> u32 {
        0
    }
    fn set_time_of_day(&self, fraction: f32) -> bool {
        *self.time.lock().unwrap() = fraction.rem_euclid(1.0);
        true
    }
}

#[derive(Default)]
pub struct Particles(pub Mutex<Vec<EmitRequest>>);

impl particle::Access for Particles {
    fn emit(&self, request: &EmitRequest) -> u32 {
        self.0.lock().unwrap().push(request.clone());
        1
    }
    fn show_over(&self, _: &BadgeRequest) -> u32 {
        1
    }
}

// --- The world -----------------------------------------------------------------

#[derive(Default)]
pub struct World {
    pub blocks: Mutex<HashMap<(i32, i32, i32), (MaterialId, u32)>>,
    pub fluids: Mutex<HashMap<(i32, i32, i32), u32>>,
    pub edits: Mutex<Vec<(BlockPos, String)>>,
    pub aimed: Mutex<Option<(i32, i32, i32)>>,
    pub names: Mutex<HashMap<String, MaterialId>>,
}

impl World {
    pub fn put(&self, x: i32, y: i32, z: i32, material: MaterialId) {
        self.blocks.lock().unwrap().insert((x, y, z), (material, 0x7FF_FFFF));
    }
    pub fn apply(&self, pos: BlockPos, block: &str) {
        self.edits.lock().unwrap().push((pos, block.to_owned()));
        let key = (pos.x, pos.y, pos.z);
        if block == "engine:air" {
            self.blocks.lock().unwrap().insert(key, (MaterialId(0), 0));
        } else if let Some(material) = self.names.lock().unwrap().get(block) {
            self.blocks.lock().unwrap().insert(key, (*material, 0x7FF_FFFF));
        } else {
            panic!("the mod wrote a block nobody registered: {block}");
        }
    }
}

impl sight::Access for World {
    fn line_of_sight(&self, _: &str, _: [f64; 3], _: [f64; 3]) -> Sighting {
        Sighting::Clear
    }
    fn looking_at(&self, uuid: [u8; 32]) -> Option<Looked> {
        let (x, y, z) = (*self.aimed.lock().unwrap())?;
        if uuid != PLAYER {
            return None;
        }
        let Reading::Single { material, occupancy } = self.block_at("", BlockPos { x, y, z }) else { return None };
        (occupancy != 0).then(|| Looked::Block {
            domain: "overworld".into(),
            cell: tiamat_core::SubNodePos { x: x * 3 + 1, y: y * 3 + 2, z: z * 3 + 1 },
            material,
            face: [0, 1, 0],
        })
    }
    fn surface_at(&self, domain: &str, column: [i32; 2], from: i32, depth: u32, _: Skip) -> Option<Surface> {
        for y in (from - depth as i32..=from).rev() {
            if let Reading::Single { material, occupancy } = self.block_at(domain, BlockPos { x: column[0], y, z: column[1] })
                && occupancy != 0
            {
                return Some(Surface { y, material, occupancy, fluid: None });
            }
        }
        None
    }
    fn block_at(&self, _: &str, pos: BlockPos) -> Reading {
        match self.blocks.lock().unwrap().get(&(pos.x, pos.y, pos.z)) {
            Some((material, occupancy)) => Reading::Single { material: *material, occupancy: *occupancy },
            None => Reading::Single { material: MaterialId(0), occupancy: 0 },
        }
    }
}

impl fluid::Access for World {
    fn fluid_at(&self, _: &str, pos: BlockPos) -> Fluid {
        match self.fluids.lock().unwrap().get(&(pos.x, pos.y, pos.z)) {
            Some(volume) => Fluid::new(FluidId(1), *volume),
            None => Fluid::EMPTY,
        }
    }
    fn set_fluid_at(&self, _: &str, pos: BlockPos, fluid: Fluid) -> bool {
        let mut fluids = self.fluids.lock().unwrap();
        if fluid.volume() == 0 {
            fluids.remove(&(pos.x, pos.y, pos.z));
        } else {
            fluids.insert((pos.x, pos.y, pos.z), fluid.volume());
        }
        true
    }
    /// The world's water is the one fluid here, number 1.
    fn fluid_id(&self, name: &str) -> Option<FluidId> {
        (name == "tiamat_default_world:water").then_some(FluidId(1))
    }
}

impl LightSource for World {
    fn light_at(&self, _: &str, _: BlockPos) -> Light {
        Light::DAYLIGHT
    }
}

impl WorldEdit for World {
    fn set_block(&self, _: &str, pos: BlockPos, block: &str) -> bool {
        self.apply(pos, block);
        true
    }
    fn set_partial(&self, _: &str, pos: BlockPos, block: &str, _: u32) -> bool {
        self.apply(pos, block);
        true
    }
    fn merge_partial(&self, _: &str, pos: BlockPos, block: &str, _: u32) -> bool {
        self.apply(pos, block);
        true
    }
}

// --- Entities: the player's body --------------------------------------------------

#[derive(Clone)]
pub struct Entities(pub Arc<Mutex<HashMap<u64, Entity>>>);

impl Entities {
    fn new() -> Self {
        let mut map = HashMap::new();
        for (id, who) in [(1, PLAYER), (2, OTHER)] {
            let mut body = Entity::at(Transform::from_world(100.5, 64.0, 100.5), "engine:player");
            body.owner = Some(Owner(PlayerUuid::from_bytes(who)));
            body.on_ground = true;
            map.insert(id, body);
        }
        Self(Arc::new(Mutex::new(map)))
    }
}

impl ent::Access for Entities {
    fn spawn(&self, entity: Entity) -> Option<EntityId> {
        let mut map = self.0.lock().unwrap();
        let id = map.keys().max().copied().unwrap_or(0) + 1;
        map.insert(id, entity);
        Some(EntityId(id))
    }
    fn despawn(&self, id: EntityId) -> bool {
        self.0.lock().unwrap().remove(&id.0).is_some()
    }
    fn get(&self, id: EntityId) -> Option<Entity> {
        self.0.lock().unwrap().get(&id.0).cloned()
    }
    fn patch(&self, id: EntityId, patch: &ent::Patch) -> bool {
        match self.0.lock().unwrap().get_mut(&id.0) {
            Some(entity) => patch.apply(entity),
            None => false,
        }
    }
    fn player(&self, uuid: [u8; 32]) -> Option<EntityId> {
        match uuid {
            PLAYER => Some(EntityId(1)),
            OTHER => Some(EntityId(2)),
            _ => None,
        }
    }
    fn within(&self, _: [f64; 3], _: f64, _: Option<&str>) -> Vec<EntityId> {
        Vec::new()
    }
    fn move_player(&self, _: [u8; 32], _: [f64; 3]) -> bool {
        true
    }
    fn select_slot(&self, _: [u8; 32], _: u16) -> bool {
        true
    }
    fn shove_player(&self, _: [u8; 32], _: [f32; 3]) -> bool {
        true
    }
    fn transfer(&self, _: EntityId, _: &str, _: [f64; 3]) -> bool {
        false
    }
    fn set_abilities(&self, _: [u8; 32], _: Option<Abilities>) -> bool {
        true
    }
}

// --- The rig -----------------------------------------------------------------

/// Which of the world around the mod to load.
#[derive(Default, Clone)]
pub struct Setup {
    /// Lua run before init.lua, e.g. `tdc_overrides = { ... }`.
    pub prelude: String,
    /// A stand-in for the world mod: the blocks this mod names, by name.
    pub world: bool,
    /// A stand-in for Life: its exports, recording what this mod tells it.
    pub life: bool,
    /// The real interface mod, from its checkout beside this repository
    /// (`../Tiamat_Default_Inventory`), loaded first as a world has it.
    pub ui: bool,
    /// Life's world option, "Default", "Creative" or "Adventure".
    pub mode: Option<String>,
    /// Mods that load after this one and use its exports: `(id, source)`.
    pub fixtures: Vec<(String, String)>,
    /// A restart: the storage and the world of a rig that ran before.
    pub restart: Option<(Arc<Storage>, Arc<World>, Arc<Boxes>)>,
}

/// Life's exports as this mod uses them, recording each call; `life heard
/// <call>` in chat answers whether it was made.
const LIFE: &str = r##"
local heard = {}
local function note(kind) return function(material, value)
    heard[kind .. " " .. material .. (value and (" " .. tostring(value)) or "")] = true
    return true
end end
game.register_block{ id = "campfire", light_emit = { r = 15, g = 9, b = 2 } }
game.export{ version = 1, add_weapon = note("weapon"), add_harvest_tool = note("harvest"),
    add_tilling_tool = note("tills"), add_contact_fire = note("fire"), add_heat_source = note("heat") }
game.register_on_chat(function(e)
    local call = string.match(e.text, "^life heard (.+)$")
    if not call then return end
    game.chat_to(e.player, heard[call] and "yes" or "no")
    return false
end)
"##;

pub struct Rig {
    pub vm: EngineVm,
    pub storage: Arc<Storage>,
    pub inventory: Arc<Inventory>,
    pub boxes: Arc<Boxes>,
    pub tools: Arc<Tools>,
    pub huds: Arc<Huds>,
    pub dialogs: Arc<Dialogs>,
    pub sounds: Arc<Sounds>,
    pub particles: Arc<Particles>,
    pub world: Arc<World>,
    pub materials: HashMap<String, MaterialId>,
}

/// The world's blocks this mod names, registered by a stand-in under the
/// world mod's id.
pub const WORLD_BLOCKS: &[&str] = &[
    "oak_log", "birch_log", "dead_log", "fir_log", "willow_log", "kapok_log", "juniper_log", "apple_log",
    "cherry_log", "mangrove_log", "acacia_log", "redwood_log", "ironwood_log", "stone", "granite", "dirt",
    "grass", "sand", "gravel", "wet_clay", "dry_clay", "cobbles", "bramble", "flint", "copper_ore",
    "iron_ore", "tin_ore", "coal", "obsidian", "water", "slate", "calcite", "dark_basalt", "tall_grass",
    "moss",
];

impl Rig {
    pub fn new(setup: Setup) -> Self {
        let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../mods").join(MOD);
        let mut vm = EngineVm::create(VmLimits::default()).unwrap();

        let (storage, world, boxes) = setup.restart.clone().unwrap_or_default();
        let inventory = Arc::new(Inventory::default());
        let tools = Arc::new(Tools::default());
        let huds = Arc::new(Huds::default());
        let dialogs = Arc::new(Dialogs::default());
        let sounds = Arc::new(Sounds::default());
        let particles = Arc::new(Particles::default());

        vm.set_storage_access(storage.clone());
        vm.set_entity_access(Arc::new(Entities::new()));
        vm.set_inventory_access(inventory.clone());
        vm.set_container_access(boxes.clone());
        vm.set_tools_access(tools.clone());
        vm.set_hud_access(huds.clone());
        vm.set_dialog_access(dialogs.clone());
        vm.set_sound_access(sounds.clone());
        vm.set_particle_access(particles.clone());
        vm.set_sight_access(world.clone());
        vm.set_fluid_access(world.clone());
        vm.set_light_source(world.clone());
        vm.set_world_edit(world.clone());

        if let Some(mode) = &setup.mode {
            vm.set_world_options(&[(
                "tiamat_default_life:mode".to_owned(),
                tiamat_core::modload::WorldOptionValue::Choice(mode.clone()),
            )]);
        }
        let mut after = Vec::new();
        if setup.ui {
            let ui = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
                .join("../../../Tiamat_Default_Inventory/mods/tiamat_default_ui");
            let source = std::fs::read_to_string(ui.join("init.lua")).expect("the interface mod beside this repo");
            vm.load_mod("tiamat_default_ui", &source, &ui).expect("the interface mod loads");
            after.push("tiamat_default_ui".to_owned());
        }
        if setup.world {
            let list = WORLD_BLOCKS.iter().map(|b| format!("'{b}'")).collect::<Vec<_>>().join(", ");
            vm.load_mod(
                "tiamat_default_world",
                &format!(
                    "for _, id in ipairs({{ {list} }}) do game.register_block{{ id = id }} end
                     game.register_fluid{{ id = 'water', material = 'water' }}"
                ),
                &dir,
            )
            .unwrap();
            after.push("tiamat_default_world".to_owned());
        }
        if setup.life {
            vm.load_mod("tiamat_default_life", LIFE, &dir).unwrap();
            after.push("tiamat_default_life".to_owned());
        }
        vm.note_dependencies(MOD, &after);
        let init = format!("{}\n{}", setup.prelude, std::fs::read_to_string(dir.join("init.lua")).unwrap());
        vm.load_mod(MOD, &init, &dir).expect("the mod loads");
        for (id, source) in &setup.fixtures {
            vm.note_dependencies(id, &[MOD.to_owned()]);
            vm.load_mod(id, source, &dir).unwrap_or_else(|err| panic!("fixture `{id}` failed to load: {err}"));
        }
        vm.freeze().unwrap();
        assert!(vm.faulted_mods().is_empty(), "faulted at load: {:?}", vm.faulted_mods());

        let materials: HashMap<String, MaterialId> = vm.registered_blocks().into_iter().collect();
        *world.names.lock().unwrap() = materials.clone();
        *tools.known.lock().unwrap() = vm.registered_tools().into_iter().map(|t| t.id).collect();
        Rig { vm, storage, inventory, boxes, tools, huds, dialogs, sounds, particles, world, materials }
    }

    pub fn material(&self, id: &str) -> MaterialId {
        let id = if id.contains(':') { id.to_owned() } else { format!("{MOD}:{id}") };
        *self.materials.get(&id).unwrap_or_else(|| panic!("no material {id}"))
    }

    pub fn world_material(&self, name: &str) -> MaterialId {
        self.material(&format!("tiamat_default_world:{name}"))
    }

    pub fn assert_healthy(&self, after: &str) {
        assert!(self.vm.faulted_mods().is_empty(), "faulted after {after}: {:?}", self.vm.faulted_mods());
    }

    pub fn tick(&mut self, n: u32) {
        for _ in 0..n {
            let faults = self.vm.tick(1).expect("the tick itself");
            assert!(faults.is_empty(), "mod faulted in tick: {faults:?}");
        }
        self.assert_healthy("ticks");
    }

    pub fn join(&mut self, player: [u8; 32]) {
        let _ = self.vm.player_join(&JoinEvent { player, name: "someone".into() });
        self.assert_healthy("join");
    }

    pub fn say_as(&mut self, player: [u8; 32], text: &str) {
        self.vm.chat(&ChatEvent { player, text: text.into() });
        self.assert_healthy(text);
    }

    pub fn say(&mut self, text: &str) {
        self.say_as(PLAYER, text);
    }

    /// Everything said to a player since the last call, oldest first.
    pub fn heard(&self, player: [u8; 32]) -> Vec<String> {
        let mut chat = self.huds.chat.lock().unwrap();
        let (mine, rest): (Vec<_>, Vec<_>) = chat.drain(..).partition(|(p, _)| *p == player);
        *chat = rest;
        mine.into_iter().map(|(_, t)| t).collect()
    }

    /// The last thing said to the player, clearing what they heard.
    pub fn said(&self) -> String {
        self.heard(PLAYER).pop().unwrap_or_default()
    }

    pub fn give(&self, player: [u8; 32], id: &str, units: u32) {
        let material = self.material(id);
        self.inventory.put(player, Stack::new(material, units).unwrap());
    }

    pub fn give_detail(&self, player: [u8; 32], id: &str, units: u32, detail: &str) {
        let material = self.material(id);
        self.inventory.put(player, Stack { detail: Some(detail.into()), ..Stack::new(material, units).unwrap() });
    }

    pub fn units(&self, player: [u8; 32], id: &str) -> u32 {
        self.inventory.units_of(player, self.material(id))
    }

    /// Puts a stack in the player's hand: into their inventory if it is not
    /// there, and selected.
    pub fn hold(&self, player: [u8; 32], id: &str, detail: Option<&str>) {
        let material = self.material(id);
        let have = self
            .inventory
            .stacks(player)
            .iter()
            .any(|s| s.material == material && s.detail.as_deref() == detail);
        if !have {
            self.inventory.put(player, Stack { detail: detail.map(str::to_owned), ..Stack::new(material, 27).unwrap() });
        }
        self.inventory.held.lock().unwrap().insert(player, (material, detail.map(str::to_owned)));
    }

    pub fn hold_nothing(&self, player: [u8; 32]) {
        self.inventory.held.lock().unwrap().remove(&player);
    }

    /// The details of every stack of a material the player carries.
    pub fn details(&self, player: [u8; 32], id: &str) -> Vec<String> {
        let material = self.material(id);
        let mut out: Vec<String> = self
            .inventory
            .stacks(player)
            .iter()
            .filter(|s| s.material == material)
            .map(|s| s.detail.clone().unwrap_or_default())
            .collect();
        out.sort();
        out
    }

    fn dig_event(&self, player: [u8; 32], material: &str, brush: tiamat_core::dig::Brush) -> tiamat_core::script::DigEvent {
        tiamat_core::script::DigEvent {
            player,
            target: tiamat_core::SubNodePos { x: 301, y: 193, z: 301 },
            material: self.material(material),
            brush,
        }
    }

    /// A dig of a block of `material` beginning: `Ok` if allowed, `Err` with
    /// the refusal.
    pub fn dig_start(&mut self, player: [u8; 32], material: &str) -> Result<(), String> {
        let out = self.vm.dig_start(&self.dig_event(player, material, tiamat_core::dig::Brush::Block));
        assert!(out.faults.is_empty(), "faulted in dig start: {:?}", out.faults);
        if out.allowed { Ok(()) } else { Err(out.reason.unwrap_or_default()) }
    }

    /// A dig completing at a block of the world, whatever is there.
    pub fn dig_complete_at(&mut self, player: [u8; 32], x: i32, y: i32, z: i32) -> Result<(), String> {
        let Reading::Single { material, .. } = sight::Access::block_at(&*self.world, "", BlockPos { x, y, z }) else {
            panic!("no block")
        };
        let out = self.vm.dig_complete(&tiamat_core::script::DigEvent {
            player,
            target: tiamat_core::SubNodePos { x: x * 3 + 1, y: y * 3 + 1, z: z * 3 + 1 },
            material,
            brush: tiamat_core::dig::Brush::Block,
        });
        assert!(out.faults.is_empty(), "faulted in dig complete: {:?}", out.faults);
        if out.allowed { Ok(()) } else { Err(out.reason.unwrap_or_default()) }
    }

    /// The same dig completing.
    pub fn dig_complete(&mut self, player: [u8; 32], material: &str) -> Result<(), String> {
        let out = self.vm.dig_complete(&self.dig_event(player, material, tiamat_core::dig::Brush::Block));
        assert!(out.faults.is_empty(), "faulted in dig complete: {:?}", out.faults);
        if out.allowed { Ok(()) } else { Err(out.reason.unwrap_or_default()) }
    }

    /// A whole dig: start, then complete.
    pub fn dig(&mut self, player: [u8; 32], material: &str) -> Result<(), String> {
        self.dig_start(player, material)?;
        self.dig_complete(player, material)
    }

    /// The engine tool in a player's hand.
    pub fn tool(&self, player: [u8; 32]) -> Option<String> {
        self.tools.hand.lock().unwrap().get(&player).cloned().flatten()
    }

    /// The place control at a block, with what the player holds: `None` when
    /// nobody handled it, `Some(what they were told)` when somebody did.
    pub fn use_at(&mut self, player: [u8; 32], x: i32, y: i32, z: i32) -> Option<String> {
        let Reading::Single { material, .. } = sight::Access::block_at(&*self.world, "", BlockPos { x, y, z }) else {
            panic!("no block")
        };
        let held = inventory::Access::held(&*self.inventory, player);
        let out = self.vm.use_block(&tiamat_core::script::UseEvent {
            player,
            domain: "overworld".into(),
            aim: Some(tiamat_core::script::UseAim {
                cell: tiamat_core::coords::SubNodePos::new(x * 3 + 1, y * 3 + 2, z * 3 + 1),
                material,
            }),
            held,
        });
        assert!(out.faults.is_empty(), "faulted in use: {:?}", out.faults);
        if out.allowed { None } else { Some(out.reason.unwrap_or_default()) }
    }

    /// What the world holds at a block, by name, or "air".
    pub fn block_name(&self, x: i32, y: i32, z: i32) -> String {
        let Reading::Single { material, occupancy } = sight::Access::block_at(&*self.world, "", BlockPos { x, y, z }) else {
            return "?".into();
        };
        if occupancy == 0 {
            return "air".into();
        }
        self.materials
            .iter()
            .find(|(_, m)| **m == material)
            .map(|(n, _)| n.clone())
            .unwrap_or_else(|| format!("#{}", material.0))
    }

    pub fn put(&self, x: i32, y: i32, z: i32, id: &str) {
        self.world.put(x, y, z, self.material(id));
    }

    /// A player placing a whole block of `id`: the mod's veto, then the
    /// block written if it allowed it.
    pub fn place(&mut self, player: [u8; 32], x: i32, y: i32, z: i32, id: &str) -> Result<(), String> {
        let out = self.vm.place(&tiamat_core::script::PlaceEvent {
            player,
            block: BlockPos { x, y, z },
            material: self.material(id),
            occupancy: 0x7FF_FFFF,
            units: 27,
        });
        assert!(out.faults.is_empty(), "faulted in place: {:?}", out.faults);
        if !out.allowed {
            return Err(out.reason.unwrap_or_default());
        }
        self.put(x, y, z, id);
        Ok(())
    }

    /// Something done in one of this mod's dialogs (`form` unqualified).
    pub fn dialog(&mut self, player: [u8; 32], form: &str, event: tiamat_core::proto::DialogEvent) {
        let _ = self.vm.dialog_event(&tiamat_core::script::DialogEvent {
            player,
            mod_id: MOD.into(),
            form: format!("{MOD}:{form}"),
            event,
        });
        self.assert_healthy(form);
    }

    pub fn press(&mut self, player: [u8; 32], form: &str, name: &str) {
        self.dialog(player, form, tiamat_core::proto::DialogEvent::Pressed { name: name.into() });
    }

    /// A dialog closed, and the container it lent put back, as the engine does.
    pub fn close(&mut self, player: [u8; 32], form: &str) {
        self.dialog(player, form, tiamat_core::proto::DialogEvent::Closed);
        self.boxes.holders.lock().unwrap().retain(|_, p| *p != player);
    }

    pub fn action(&mut self, player: [u8; 32], id: &str) {
        for pressed in [true, false] {
            let _ = self.vm.action(&tiamat_core::script::ActionEvent { player, id: id.into(), pressed });
        }
        self.assert_healthy(id);
    }

    /// The form of the last dialog shown to anybody.
    pub fn last_form(&self) -> String {
        self.dialogs.shown.lock().unwrap().last().map(|d| d.form.clone()).unwrap_or_default()
    }

    /// What a restart keeps.
    pub fn saved(&self) -> (Arc<Storage>, Arc<World>, Arc<Boxes>) {
        (self.storage.clone(), self.world.clone(), self.boxes.clone())
    }

    pub fn stack(&self, id: &str, units: u32) -> Stack {
        Stack::new(self.material(id), units).unwrap()
    }
}
