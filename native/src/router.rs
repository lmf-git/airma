//! Where a road goes: A* over a grid, one search per leg, all legs at once
//! across the cores.
//!
//! The cost function is the surveyor's -- distance, climb, the square of the
//! grade, and a hard penalty past the gradient a trunk road is built to -- plus
//! water, the aerodrome keep-out and the runway itself.

use crate::field::WATER_LEVEL;
use crate::index::{key, Map};
use crate::world::{on_runway, road_height, World};
use std::collections::BinaryHeap;

/// The gradient the search is costed against. What the profile is then built
/// to lives in `survey`, which is where the earthworks are decided.
const ROAD_GRADE: f32 = 0.062;

/// What the search believes a metre still to go will cost it.
///
/// The cheapest a metre can actually be is 0.55 -- flat, dry, clear of the
/// field -- so anything at or below that is admissible and finds the provably
/// shortest road. It also spreads out like Dijkstra the moment the ground stops
/// being flat. A road does not have to be the shortest one, so the estimate is
/// allowed a little ahead of the truth: at 1.6 the search commits to a
/// direction and still keeps the gradient it is paying for.
const RT_HEUR: f32 = 1.6;
const RT_MARGIN: f32 = 9000.0;
const RT_MAX_NODES: usize = 60000;

/// Water this deep is the sea, not a river. A road crosses a channel on a
/// bridge; it does not cross an ocean on one, and the network came out with a
/// hundred and twenty kilometre viaduct standing in open water because nothing
/// said so.
const DEEP_WATER: f32 = 90.0;
/// The longest water crossing that is worth building. A fixed link of a few
/// kilometres is a real thing -- the Oresund is eight, the Confederation Bridge
/// thirteen -- and a hundred and twenty is not. Past this the leg is abandoned
/// and the network is left to find another way round, or to leave that place
/// unconnected, which is the truth about it.
pub const MAX_CROSSING: f32 = 8000.0;

/// What a step of road costs when the ground between its ends is looked at as
/// well as its ends.
///
/// The search grid is four hundred metres to a cell at its finest and two and a
/// half kilometres at its coarsest, and a ridge crest is narrower than that: a
/// step measured end to end runs straight over the top of one and reports the
/// mean gradient of the two flanks, which is gentle. So the router cheerfully
/// laid roads over mountains it could not see, and the survey then had to make
/// something of a route with a thousand metre wall across it. Two half-steps
/// cost twice as much and see the crest.
pub fn edge_cost(w: &World, ha: f32, hb: f32, run: f32, ax: f32, az: f32,
        bx: f32, bz: f32) -> f32 {
    let mx = (ax + bx) * 0.5;
    let mz = (az + bz) * 0.5;
    let hm = road_height(w, mx, mz);
    step_cost(w, ha, hm, run * 0.5, mx, mz)
        + step_cost(w, hm, hb, run * 0.5, bx, bz)
}

/// What one step of road costs, in the surveyor's terms.
pub fn step_cost(w: &World, ha: f32, hb: f32, run: f32, wx: f32, wz: f32) -> f32 {
    let climb = (hb - ha).abs();
    let grade = climb / run;
    let mut cost = run * 0.55 + climb * 1.6 + grade * grade * run * 260.0;
    let over = (grade - ROAD_GRADE).max(0.0);
    cost += over * over * run * 9000.0;
    // Water is crossable -- that is what a bridge is for -- but the price goes
    // up with the depth, so a road will ford a river or cross a strait and will
    // not strike out across a bay. A flat charge let it do both.
    let depth = WATER_LEVEL + 6.0 - hb;
    if depth > 0.0 {
        cost += run * (180.0 + (depth / DEEP_WATER).min(4.0) * 2600.0);
    }
    if !clear_of_airfield(wx, wz) {
        cost += run * 400.0;
    }
    if on_runway(w, wx, wz) {
        cost += run * 4000.0;
    }
    cost
}

pub fn clear_of_airfield(x: f32, z: f32) -> bool {
    if x.abs() < 620.0 && z.abs() < 2600.0 {
        return false;
    }
    // and clear of the extended centreline, where the approach lights run
    !(x.abs() < 260.0 && z.abs() < 5200.0)
}

const NEIGHBOURS: [(i32, i32, f32); 16] = [
    (1, 0, 1.0), (-1, 0, 1.0), (0, 1, 1.0), (0, -1, 1.0),
    (1, 1, 1.41421), (1, -1, 1.41421), (-1, 1, 1.41421), (-1, -1, 1.41421),
    (2, 1, 2.23607), (2, -1, 2.23607), (-2, 1, 2.23607), (-2, -1, 2.23607),
    (1, 2, 2.23607), (-1, 2, 2.23607), (1, -2, 2.23607), (-1, -2, 2.23607),
];

/// Cheapest-first, ordered on the estimate. f32 has no total order, so the
/// comparison is done by hand; every value here is finite and non-negative.
#[derive(PartialEq)]
struct Node(f32, i32, i32);
impl Eq for Node {}
impl Ord for Node {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        other.0.partial_cmp(&self.0).unwrap_or(std::cmp::Ordering::Equal)
    }
}
impl PartialOrd for Node {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}

pub fn search_counted(w: &World, a: (f32, f32), b: (f32, f32), cell: f32,
        margin: f32, budget: usize) -> (Vec<(f32, f32)>, usize) {
    let ai = (a.0 / cell).round() as i32;
    let aj = (a.1 / cell).round() as i32;
    let bi = (b.0 / cell).round() as i32;
    let bj = (b.1 / cell).round() as i32;
    if ai == bi && aj == bj {
        return (vec![a, b], 0);
    }
    let m = (margin / cell).ceil() as i32;
    let lo_i = ai.min(bi) - m;
    let hi_i = ai.max(bi) + m;
    let lo_j = aj.min(bj) - m;
    let hi_j = aj.max(bj) + m;
    let mut came: Map<i64, i64> = Map::default();
    let mut cells: Map<i64, (i32, i32)> = Map::default();
    let mut g: Map<i64, f32> = Map::default();
    let mut hcache: Map<i64, f32> = Map::default();
    let mut closed: Map<i64, bool> = Map::default();
    let start = key(ai, aj);
    let goal = key(bi, bj);
    cells.insert(start, (ai, aj));
    cells.insert(goal, (bi, bj));
    g.insert(start, 0.0);
    let mut open = BinaryHeap::new();
    open.push(Node(0.0, ai, aj));
    let mut expanded = 0usize;
    let height = |hc: &mut Map<i64, f32>, i: i32, j: i32| -> f32 {
        let k = key(i, j);
        if let Some(v) = hc.get(&k) {
            return *v;
        }
        let v = road_height(w, i as f32 * cell, j as f32 * cell);
        hc.insert(k, v);
        v
    };
    while let Some(Node(_, ci, cj)) = open.pop() {
        if expanded >= budget {
            break;
        }
        let ck = key(ci, cj);
        if closed.contains_key(&ck) {
            continue;
        }
        closed.insert(ck, true);
        expanded += 1;
        if ck == goal {
            break;
        }
        let ha = height(&mut hcache, ci, cj);
        let gc = *g.get(&ck).unwrap_or(&0.0);
        for (di, dj, w8) in NEIGHBOURS {
            let ni = ci + di;
            let nj = cj + dj;
            if ni < lo_i || ni > hi_i || nj < lo_j || nj > hi_j {
                continue;
            }
            let nk = key(ni, nj);
            if closed.contains_key(&nk) {
                continue;
            }
            let run = w8 * cell;
            let hb = height(&mut hcache, ni, nj);
            let ng = gc
                + edge_cost(w, ha, hb, run, ci as f32 * cell, cj as f32 * cell,
                    ni as f32 * cell, nj as f32 * cell);
            if let Some(old) = g.get(&nk) {
                if *old <= ng {
                    continue;
                }
            }
            g.insert(nk, ng);
            came.insert(nk, ck);
            cells.insert(nk, (ni, nj));
            let hx = (bi - ni) as f32 * cell;
            let hz = (bj - nj) as f32 * cell;
            open.push(Node(ng + (hx * hx + hz * hz).sqrt() * RT_HEUR, ni, nj));
        }
    }
    if !came.contains_key(&goal) && start != goal {
        return (Vec::new(), expanded);
    }
    let mut rev: Vec<i64> = Vec::new();
    let mut cur = goal;
    let mut guard = 0;
    while cur != start && came.contains_key(&cur) && guard < 200000 {
        rev.push(cur);
        cur = came[&cur];
        guard += 1;
    }
    rev.push(start);
    rev.reverse();
    let mut out: Vec<(f32, f32)> = vec![a];
    for k in rev {
        let (ci, cj) = cells[&k];
        let p = (ci as f32 * cell, cj as f32 * cell);
        let last = *out.last().unwrap();
        let dx = p.0 - last.0;
        let dz = p.1 - last.1;
        if (dx * dx + dz * dz).sqrt() > cell * 0.5 {
            out.push(p);
        }
    }
    // Only if it is not already there: the last grid cell is usually the goal
    // cell, and pushing the endpoint on top of it left a zero length leg that
    // has no direction, and therefore no gradient, for the survey to work with.
    let last = *out.last().unwrap();
    if (b.0 - last.0).abs() > 0.5 || (b.1 - last.1).abs() > 0.5 {
        out.push(b);
    }
    (out, expanded)
}

/// What a straight leg between two points would cost, sampled along it.
fn leg_cost(w: &World, a: (f32, f32), b: (f32, f32)) -> f32 {
    let dx = b.0 - a.0;
    let dz = b.1 - a.1;
    let d = (dx * dx + dz * dz).sqrt();
    if d < 1.0 {
        return 0.0;
    }
    let steps = ((d / 120.0) as i32).clamp(2, 40);
    let mut cost = d * 0.55;
    let mut last = road_height(w, a.0, a.1);
    let run = d / steps as f32;
    for i in 1..=steps {
        let t = i as f32 / steps as f32;
        let qx = a.0 + dx * t;
        let qz = a.1 + dz * t;
        let h = road_height(w, qx, qz);
        cost += step_cost(w, last, h, run, qx, qz) - run * 0.55;
        last = h;
    }
    cost
}

/// Drop the waypoints that earn nothing, so the road runs straight where the
/// ground lets it instead of stepping along the search grid.
pub fn pull_straight(w: &World, pts: Vec<(f32, f32)>) -> Vec<(f32, f32)> {
    let mut cur = pts;
    for _ in 0..4 {
        if cur.len() < 3 {
            break;
        }
        let mut out = vec![cur[0]];
        let mut i = 1;
        while i < cur.len() - 1 {
            let a = *out.last().unwrap();
            let b = cur[i];
            let c = cur[i + 1];
            let bent = leg_cost(w, a, b) + leg_cost(w, b, c);
            let direct = leg_cost(w, a, c);
            if direct > bent * 1.02 {
                out.push(b);
            }
            i += 1;
        }
        out.push(cur[cur.len() - 1]);
        if out.len() == cur.len() {
            break;
        }
        cur = out;
    }
    cur
}

/// The longest unbroken stretch of water the line crosses, in metres.
///
/// A leg that has to be carried further than a bridge is ever built is not a
/// road; it is the router deciding that the cheapest way between two continents
/// is to pave the sea. Measured after straightening, on the line that would
/// actually be built.
pub fn worst_crossing(w: &World, pts: &[(f32, f32)]) -> f32 {
    let mut worst = 0.0f32;
    let mut run = 0.0f32;
    for pair in pts.windows(2) {
        let (a, b) = (pair[0], pair[1]);
        let d = ((b.0 - a.0).powi(2) + (b.1 - a.1).powi(2)).sqrt();
        if d < 1.0 {
            continue;
        }
        let steps = ((d / 90.0).ceil() as i32).max(1);
        let stride = d / steps as f32;
        for k in 0..steps {
            let t = (k as f32 + 0.5) / steps as f32;
            let x = a.0 + (b.0 - a.0) * t;
            let z = a.1 + (b.1 - a.1) * t;
            if road_height(w, x, z) < WATER_LEVEL {
                run += stride;
                if run > worst {
                    worst = run;
                }
            } else {
                run = 0.0;
            }
        }
    }
    worst
}

/// One leg, end to end: search, widen if it failed, straighten, and reject it
/// if what came back is a causeway across the sea.
pub fn route(w: &World, a: (f32, f32), b: (f32, f32)) -> (Vec<(f32, f32)>, usize) {
    // The grid has to suit the leg: at a flat 400 m a hundred kilometre link
    // needs more cells than the node budget just to reach the far end.
    let dx = b.0 - a.0;
    let dz = b.1 - a.1;
    let span = (dx * dx + dz * dz).sqrt();
    let cell = (span / 140.0).clamp(400.0, 2600.0);
    let (mut r, mut n) = search_counted(w, a, b, cell, RT_MARGIN, RT_MAX_NODES);
    if r.len() < 2 {
        let (r2, n2) =
            search_counted(w, a, b, cell * 1.8, RT_MARGIN * 2.0, RT_MAX_NODES * 2);
        r = r2;
        n += n2;
    }
    if r.len() < 2 {
        return (Vec::new(), n);
    }
    let line = pull_straight(w, r);
    if worst_crossing(w, &line) > MAX_CROSSING {
        return (Vec::new(), n);
    }
    (line, n)
}
