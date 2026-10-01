//! Which leaves of the terrain quadtree should exist, for an eye position.
//!
//! The world is one square, halved and halved again wherever the ground is
//! worth more triangles than it is getting. A node splits when the eye is
//! within `SPLIT_K` of its own spans *and* the surface it would draw stands far
//! enough off the real height field to be worth the vertices. The first test is
//! arithmetic; the second wants 353 height samples, so it is measured once per
//! node and kept for the life of the run.
//!
//! This was a descent in script. It walks about ninety thousand nodes, and each
//! leaf then probes its four neighbours, and it cost 4.1 ms every time the eye
//! moved 120 m -- a dropped frame twice a second at cruise, which is exactly the
//! stutter that no frame-rate average shows. The measuring is worse: flying into
//! country the tree has not seen before, every new node pays its 353 samples one
//! at a time, on the main thread, in the middle of a frame.
//!
//! Here the descent runs a level at a time, so every node at a level that still
//! needs measuring is measured in one parallel pass before any of them is
//! decided. Same tree, same leaves; the harness in `--lodtest` compares the
//! neighbour lookups against a full descent and the two still agree.

use crate::chunk::{span_at, CELLS};
use crate::index::Map;
use crate::world::Ground;
use rayon::prelude::*;
use std::sync::Mutex;

/// Mirrors `Terrain.MAX_DEPTH`.
const MAX_DEPTH: i32 = 13;
/// A node stops splitting once the eye is further away than this many of its
/// own spans. Mirrors `Terrain.SPLIT_K`.
const SPLIT_K: f32 = 2.0;
/// How far the drawn surface has to stand off the real one, in metres, before
/// subdividing is worth the triangles. Mirrors `Terrain.ERR_ABS`.
const ERR_ABS: f32 = 0.4;
/// How much less a node entirely under water is worth subdividing. Mirrors
/// `Terrain.SEABED_DETAIL`.
const SEABED_DETAIL: f32 = 0.12;
/// Mirrors `Sim.WATER_LEVEL`, which is `field::WATER_LEVEL`.
const WATER_LEVEL: f32 = crate::field::WATER_LEVEL;

/// A node's identity as one integer: depth in four bits and each index in
/// twenty-seven. Mirrors `Terrain._node_key`, and has to, because the harness
/// compares the two.
#[inline]
fn node_key(depth: i32, ix: i32, iz: i32) -> i64 {
    ((depth as i64) << 54) | (((ix & 0x7FF_FFFF) as i64) << 27)
        | ((iz & 0x7FF_FFFF) as i64)
}

/// The deviation and the high point of one node, measured once and kept.
///
/// It is a property of the height field alone -- no eye, no frame -- so a node
/// measured on one flight is still measured on the next. The table only grows,
/// and a node costs sixteen bytes in it against the 353 samples it saves.
static STATS: Mutex<Option<Map<i64, (f32, f32)>>> = Mutex::new(None);
/// Which nodes were subdivided last time the tree was walked, for the
/// hysteresis in `splits`. Replaced only at the end of a walk, so every
/// decision inside one walk is made against the same state.
static WAS_SPLIT: Mutex<Option<Map<i64, ()>>> = Mutex::new(None);

/// What every node the tree has ever looked at measured, for the bake.
///
/// Sixteen bytes a node: the key, the error, and the high point. The high point
/// travels with the error and always has to: kept apart, a run that loaded the
/// errors from disk and not the tops read every node's high ground as zero --
/// which means no node in the world is ever seabed and the eye's height above a
/// mountain is measured from the sea. It is not a visible failure, which is why
/// it survived: the tree still builds, at a different level of detail from the
/// one the same flight gets on a cold start.
pub fn export() -> Vec<u8> {
    let g = STATS.lock().unwrap();
    let m = match g.as_ref() {
        Some(m) => m,
        None => return Vec::new(),
    };
    let mut out = Vec::with_capacity(m.len() * 16);
    for (k, (e, t)) in m.iter() {
        out.extend_from_slice(&k.to_le_bytes());
        out.extend_from_slice(&e.to_le_bytes());
        out.extend_from_slice(&t.to_le_bytes());
    }
    out
}

/// The same, back off disk. The table is a property of the height field and of
/// nothing else, so what one run learned is what the next one starts with.
pub fn import(data: &[u8]) {
    let mut m: Map<i64, (f32, f32)> = Map::default();
    m.reserve(data.len() / 16);
    for q in data.chunks_exact(16) {
        let k = i64::from_le_bytes(q[0..8].try_into().unwrap());
        let e = f32::from_le_bytes(q[8..12].try_into().unwrap());
        let t = f32::from_le_bytes(q[12..16].try_into().unwrap());
        m.insert(k, (e, t));
    }
    *STATS.lock().unwrap() = Some(m);
}

/// How far the surface a node would draw stands off the field, and the highest
/// ground in it.
///
/// It is a property of the height field alone -- no eye, no frame -- which is
/// what lets it be measured once and kept for the life of the run, and written
/// to disk between runs.
///
/// Against the *land*: `Ground::land`, not `Ground::now`. The tree measures
/// terrain, and a carrier under way is not a reason to subdivide the sea
/// beneath her -- a node whose error moved with a ship would be re-measured
/// every time she sailed across it.
fn stats(g: &Ground, depth: i32, ix: i32, iz: i32) -> (f32, f32) {
    let span = span_at(depth);
    let x0 = ix as f32 * span;
    let z0 = iz as f32 * span;
    let cn = CELLS;
    let n = cn + 1;
    let cell = span / cn as f32;
    let mut grid = vec![0f32; n * n];
    let mut top = -1e9f32;
    for j in 0..n {
        let z = z0 + j as f32 * cell;
        for i in 0..n {
            let h = g.at(x0 + i as f32 * cell, z);
            grid[j * n + i] = h;
            if h > top {
                top = h;
            }
        }
    }
    let mut e = 0.0f32;
    for j in (0..cn).step_by(2) {
        for i in (0..cn).step_by(2) {
            let drawn = (grid[j * n + i] + grid[(j + 1) * n + i + 1]) * 0.5;
            let truth = g.at(x0 + (i as f32 + 0.5) * cell,
                z0 + (j as f32 + 0.5) * cell);
            e = e.max((truth - drawn).abs());
        }
    }
    (e, top)
}

/// One leaf: where it is, what each of its four edges meets, and which of them
/// face a *finer* neighbour.
pub struct Leaf {
    pub depth: i32,
    pub ix: i32,
    pub iz: i32,
    pub nb: [i32; 4],
    pub fine: u32,
    /// What the lookup actually found across each edge, before it was clamped.
    /// Only the clamped value and the `fine` bit change a chunk's geometry;
    /// this is carried for `--lodtest`, which checks every one of them against
    /// a full descent from the root.
    pub raw: [i32; 4],
}

#[inline]
fn in_root(x: f32, z: f32) -> bool {
    let h = crate::chunk::ROOT_SPAN * 0.5;
    x.abs() < h && z.abs() < h
}

/// Distance from the eye to a node's box, on the flat.
#[inline]
fn flat_gap(x0: f32, z0: f32, span: f32, ex: f32, ez: f32) -> (f32, f32) {
    (
        (x0 - ex).max(ex - (x0 + span)).max(0.0),
        (z0 - ez).max(ez - (z0 + span)).max(0.0),
    )
}

/// The leaves that should exist for this eye position.
pub fn wanted(eye: [f32; 3]) -> Vec<Leaf> {
    let g = Ground::land();
    let mut stats_g = STATS.lock().unwrap();
    let table = stats_g.get_or_insert_with(Map::default);
    let was_g = WAS_SPLIT.lock().unwrap();
    let was = was_g.as_ref();

    // First pass: which nodes are leaves.
    //
    // A level at a time, not a depth-first descent, so that every node at a
    // level whose error is not yet known is measured together. Measured one at
    // a time -- which is what a descent does -- flying into new country pays
    // 353 height samples per node on whichever thread is walking the tree.
    let mut level: Vec<(i32, i32)> = vec![(-1, -1), (0, -1), (-1, 0), (0, 0)];
    let mut depth = 1i32;
    let mut leaves: Vec<Leaf> = Vec::new();
    let mut opened: Map<i64, ()> = Map::default();
    while !level.is_empty() {
        let span = span_at(depth);
        // The finest level there is: nothing below it to hand over to, and
        // measuring it would be 353 height samples spent on an answer that is
        // already known. Checked before the error is asked for, as the script's
        // own first line did.
        if depth >= MAX_DEPTH {
            for (ix, iz) in level {
                leaves.push(Leaf { depth, ix, iz, nb: [0; 4], fine: 0, raw: [0; 4] });
            }
            break;
        }
        // Flat first, and only then in three dimensions. Height can only push a
        // node further away, so anything already out of range on the flat is
        // out of range full stop -- and asking for its height means measuring
        // its terrain error, which is 353 height samples for a node that was
        // going to be rejected on distance alone. Tested the other way round,
        // one look at the tree went from 5.7 ms to 16.3.
        let mut near: Vec<((i32, i32), f32, f32)> = Vec::with_capacity(level.len());
        for &(ix, iz) in &level {
            // Hysteresis: a node already subdivided has to be got clearly
            // further away before it merges again. One, now -- splitting and
            // merging at the same distance is what makes both directions of the
            // blend exact -- but the state is carried so the constant can be
            // moved without the walk being rewritten.
            let reach = SPLIT_K * span
                * if was.is_some_and(|w| w.contains_key(&node_key(depth, ix, iz))) {
                    HYST
                } else {
                    1.0
                };
            let (dx, dz) = flat_gap(ix as f32 * span, iz as f32 * span, span,
                eye[0], eye[2]);
            if dx * dx + dz * dz >= reach * reach {
                leaves.push(Leaf { depth, ix, iz, nb: [0; 4], fine: 0, raw: [0; 4] });
            } else {
                near.push(((ix, iz), dx * dx + dz * dz, reach));
            }
        }
        // Whatever of the near set has never been measured, measured now, in
        // one pass across every core. This is the difference between flying
        // into new country for nothing and paying 353 samples a node for it on
        // the thread that is walking the tree.
        let todo: Vec<(i32, i32)> = near
            .iter()
            .map(|n| n.0)
            .filter(|&(ix, iz)| !table.contains_key(&node_key(depth, ix, iz)))
            .collect();
        if !todo.is_empty() {
            let got: Vec<(f32, f32)> = todo
                .par_iter()
                .map(|&(ix, iz)| stats(&g, depth, ix, iz))
                .collect();
            for (&(ix, iz), v) in todo.iter().zip(got) {
                table.insert(node_key(depth, ix, iz), v);
            }
        }
        let mut next: Vec<(i32, i32)> = Vec::new();
        for ((ix, iz), flat2, reach) in near {
            let k = node_key(depth, ix, iz);
            let (mut e, top) = table[&k];
            let dy = (eye[1] - top).max(0.0);
            if (flat2 + dy * dy).sqrt() >= reach {
                leaves.push(Leaf { depth, ix, iz, nb: [0; 4], fine: 0, raw: [0; 4] });
                continue;
            }
            if top < WATER_LEVEL - 1.0 {
                // Nothing above the surface anywhere in it: this is seabed, and
                // it does not earn the triangles the same relief above water
                // would.
                e *= SEABED_DETAIL;
            }
            // The error decides *whether* a node is worth subdividing, not how
            // close you have to get before it is: every hand-over that happens
            // at all happens at exactly SPLIT_K spans, which is the distance the
            // blend is built around, so it is always complete.
            if e > ERR_ABS {
                opened.insert(k, ());
                for c in 0..4 {
                    next.push((ix * 2 + (c & 1), iz * 2 + (c >> 1)));
                }
            } else {
                leaves.push(Leaf { depth, ix, iz, nb: [0; 4], fine: 0, raw: [0; 4] });
            }
        }
        level = next;
        depth += 1;
    }
    drop(was_g);
    drop(stats_g);

    // Second pass: what each leaf meets along its four edges. Nothing about an
    // edge can be settled until every leaf is known, because an edge is a
    // question about a neighbour.
    let mut by_key: Map<i64, i32> = Map::default();
    for l in &leaves {
        by_key.insert(node_key(l.depth, l.ix, l.iz), l.depth);
    }
    for l in leaves.iter_mut() {
        let span = span_at(l.depth);
        let cell = span / CELLS as f32;
        let x0 = l.ix as f32 * span;
        let z0 = l.iz as f32 * span;
        let half = span * 0.5;
        let step = cell * 0.5;
        // A coarser neighbour spans this whole edge, so one probe just outside
        // the middle of it settles the question.
        let probes = [
            (x0 - step, z0 + half),
            (x0 + span + step, z0 + half),
            (x0 + half, z0 - step),
            (x0 + half, z0 + span + step),
        ];
        for (e, (px, pz)) in probes.iter().enumerate() {
            let raw = neighbour_depth(*px, *pz, l.depth, &by_key);
            l.raw[e] = raw;
            // Only a *coarser* neighbour changes this chunk's geometry -- a
            // finer one conforms to us -- so the exact depth of a finer one is
            // deliberately not recorded, or a leaf beside a detailed region is
            // rebuilt every time any of it shifts a level for a mesh that comes
            // out identical.
            l.nb[e] = raw.min(l.depth);
            if raw > l.depth {
                l.fine |= 1 << e;
            }
        }
    }
    *WAS_SPLIT.lock().unwrap() = Some(opened);
    leaves
}

/// Mirrors `Terrain.HYST`.
const HYST: f32 = 1.0;

/// What a leaf's neighbour across an edge is drawn at, looked up in the leaves
/// already collected rather than worked out again from the root.
///
/// A neighbour is almost always the same depth or one either side, so those are
/// tried first and the sweep is the fallback. Off the edge of the world there
/// is no neighbour: answering with our own depth is what says "nothing to
/// conform to here", where the sweep would otherwise find whichever leaf
/// happens to share a cell index with a point the tree does not cover, and the
/// outermost chunks would stitch themselves to the far side of the map.
fn neighbour_depth(px: f32, pz: f32, own: i32, leaves: &Map<i64, i32>) -> i32 {
    if !in_root(px, pz) {
        return own;
    }
    for probe in [own, own + 1, own - 1, own + 2, own - 2] {
        if probe < 1 || probe > MAX_DEPTH {
            continue;
        }
        let sp = span_at(probe);
        if leaves.contains_key(&node_key(probe, (px / sp).floor() as i32,
                (pz / sp).floor() as i32)) {
            return probe;
        }
    }
    for d in (1..=MAX_DEPTH).rev() {
        let sp = span_at(d);
        if leaves.contains_key(&node_key(d, (px / sp).floor() as i32,
                (pz / sp).floor() as i32)) {
            return d;
        }
    }
    own
}

/// What depth the tree draws a point at, by descent from the root. Zero when
/// the point is outside the root entirely.
///
/// The harness's second opinion: `--lodtest` compares every neighbour lookup
/// against this, and a disagreement means the tree has both split a node and
/// kept it.
pub fn depth_at(x: f32, z: f32, eye: [f32; 3]) -> i32 {
    if !in_root(x, z) {
        return 0;
    }
    let g = Ground::land();
    let mut stats_g = STATS.lock().unwrap();
    let table = stats_g.get_or_insert_with(Map::default);
    let was_g = WAS_SPLIT.lock().unwrap();
    let was = was_g.as_ref();
    let mut d = 1i32;
    let mut s = span_at(1);
    let mut ix = (x / s).floor().clamp(-1.0, 0.0) as i32;
    let mut iz = (z / s).floor().clamp(-1.0, 0.0) as i32;
    loop {
        if !splits_one(&g, table, was, d, ix, iz, eye) {
            return d;
        }
        d += 1;
        s = span_at(d);
        ix = (x / s).floor() as i32;
        iz = (z / s).floor() as i32;
    }
}

/// Does this node hand its ground to four children? The single-node form, for
/// the descent the harness checks against.
fn splits_one(g: &Ground, table: &mut Map<i64, (f32, f32)>,
        was: Option<&Map<i64, ()>>, depth: i32, ix: i32, iz: i32, eye: [f32; 3])
        -> bool {
    if depth >= MAX_DEPTH {
        return false;
    }
    let span = span_at(depth);
    let (dx, dz) = flat_gap(ix as f32 * span, iz as f32 * span, span, eye[0], eye[2]);
    let k = node_key(depth, ix, iz);
    let reach = SPLIT_K * span
        * if was.is_some_and(|w| w.contains_key(&k)) { HYST } else { 1.0 };
    if dx * dx + dz * dz >= reach * reach {
        return false;
    }
    let (mut e, top) = *table
        .entry(k)
        .or_insert_with(|| stats(g, depth, ix, iz));
    let dy = (eye[1] - top).max(0.0);
    if (dx * dx + dz * dz + dy * dy).sqrt() >= reach {
        return false;
    }
    if top < WATER_LEVEL - 1.0 {
        e *= SEABED_DETAIL;
    }
    e > ERR_ABS
}

/// The highest ground in a node, measuring it if nobody has yet. The pop
/// harness asks how far above a chunk the eye was when it appeared.
pub fn node_top(depth: i32, ix: i32, iz: i32) -> f32 {
    let k = node_key(depth, ix, iz);
    let mut held = STATS.lock().unwrap();
    let table = held.get_or_insert_with(Map::default);
    if let Some(v) = table.get(&k) {
        return v.1;
    }
    let v = stats(&Ground::land(), depth, ix, iz);
    table.insert(k, v);
    v.1
}
