// SPDX-FileCopyrightText: Iridesium
// SPDX-License-Identifier: GPL-3.0-only
//
// Fitting a sheet: Tiamat Default UI's own check, as Life's harness has it.
// The engine's layout run over a whole screen at the room a window gives a
// framed sheet, with a ruler that sizes text as the interface's faces run.
// Nothing on a screen scrolls, so a slot squeezed too small or out of
// square, a label with no room for its text, or anything spilling out of its
// parent is a screen that does not work at that window.

use tiamat_core::ui::{self as ui_layout, Widget};

struct Ruler;

fn text_size(text: &str, style: &ui_layout::Style) -> (i32, i32) {
    let size = f32::from(style.text_size.unwrap_or(14));
    let per = if style.font.as_deref() == Some("tiamat_default_ui:display") { 0.84 } else { 0.63 };
    let chars = text.chars().count() as f32;
    ((chars * size * per).ceil() as i32, (size * 1.3).ceil() as i32)
}

impl ui_layout::Measure for Ruler {
    fn natural(&self, widget: &Widget, style: &ui_layout::Style) -> (i32, i32) {
        match widget {
            Widget::Label { text } => text_size(text, style),
            Widget::Button { text } => {
                let (w, h) = text_size(text, style);
                (w + 16, h + 8)
            }
            Widget::ItemSlot { .. } => (36, 36),
            _ => (0, 0),
        }
    }
}

/// The room a sheet gets in a window: three quarters of its height, 4:3,
/// clear of the tallest HUD reserve (Life's, 216 of 1080), less the sheet's
/// margins, its Close bar and the interface's frame.
fn sheet_room(w: f32, h: f32) -> (i32, i32) {
    let reserve = (216.0 / 1080.0 * h).clamp(0.0, h / 2.0);
    let height = (h * 0.75).min(h - reserve).max(120.0);
    let width = (height * 4.0 / 3.0).min(w * 0.9).max(160.0);
    let height = (width * 3.0 / 4.0).min(height).max(120.0);
    ((width - 16.0 - 24.0) as i32, (height - 48.0 - 24.0) as i32)
}

fn misfits(tree: &ui_layout::Tree, area: (i32, i32)) -> Vec<String> {
    let laid = ui_layout::layout(tree, ui_layout::Rect::new(0, 0, area.0, area.1), &Ruler);
    let mut found = Vec::new();
    walk(tree, 0, &laid, None, &mut found);
    found
}

fn walk(tree: &ui_layout::Tree, at: usize, laid: &ui_layout::Laid, parent: Option<ui_layout::Rect>, found: &mut Vec<String>) {
    let node = &tree.nodes[at];
    let r = laid.rect;
    if let Some(p) = parent
        && (r.x < p.x || r.y < p.y || r.x + r.w > p.x + p.w || r.y + r.h > p.y + p.h)
    {
        found.push(format!("{:?} spills out of its parent: {r:?} in {p:?}", node.widget));
    }
    match &node.widget {
        // The engine gives every child of a scroll the whole box, so two
        // children are drawn one over the other: a scroll holds one column.
        Widget::Scroll if laid.children.len() > 1 => {
            found.push(format!("a scroll with {} children, drawn over each other", laid.children.len()));
        }
        Widget::ItemSlot { view, index } => {
            let ratio = r.w as f32 / r.h.max(1) as f32;
            if r.w.min(r.h) < 36 || !(0.8..=1.25).contains(&ratio) {
                found.push(format!("{view} slot {} is {}x{}", index + 1, r.w, r.h));
            }
        }
        Widget::Label { text } | Widget::Button { text } if !text.is_empty() => {
            let (w, h) = text_size(text, &node.style);
            let pad = if matches!(node.widget, Widget::Button { .. }) { 8 } else { 0 };
            if w + pad > r.w || h > r.h + 4 {
                found.push(format!("{text:?} needs {}x{} and has {}x{}", w + pad, h, r.w, r.h));
            }
        }
        _ => {}
    }
    let first = node.children.first as usize;
    for (n, child) in laid.children.iter().enumerate() {
        walk(tree, first + n, child, Some(r), found);
    }
}

/// Every problem a screen has at the common window sizes, or none.
pub fn check(what: &str, tree: &ui_layout::Tree) {
    let mut failed = Vec::new();
    for (w, h) in [(800.0, 600.0), (1024.0, 768.0), (1280.0, 720.0), (1366.0, 768.0), (1920.0, 1080.0)] {
        let area = sheet_room(w, h);
        for problem in misfits(tree, area) {
            failed.push(format!("{w}x{h} ({}x{} room): {problem}", area.0, area.1));
        }
    }
    assert!(failed.is_empty(), "{what} does not fit:\n  {}", failed.join("\n  "));
}
