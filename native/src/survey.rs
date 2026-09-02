//! What height the made road actually sits at.
//!
//! Routing says where a road goes; this says what it was built to. Both halves
//! are here because both are the same shape of work -- tens of thousands of
//! stations, a handful of passes over all of them, and nothing worth handing
//! back to script in between.

use crate::field::{lerp, smoothstep, WATER_LEVEL};
use crate::index::{key, Map};
use rayon::prelude::*;

/// Spacing of the profile's stations.
pub const SURVEY_STEP: f32 = 45.0;
/// The gradient a trunk road is built to.
pub const ROAD_GRADE: f32 = 0.062;
/// And what it may be pushed to rather than bore through the hill.
pub const ROAD_GRADE_MAX: f32 = 0.100;
/// And what it may be pushed to where there is no buildable profile at all.
pub const GRADE_HAIRPIN: f32 = 0.150;
/// Tallest embankment and deepest cutting before it becomes a structure.
pub const ROAD_FILL_MAX: f32 = 22.0;
pub const ROAD_CUT_MAX: f32 = 34.0;
/// A structure has to earn itself three times over: long enough to be worth
/// building, deep enough that there is no sensible alternative, and *mostly*
/// that deep rather than merely touching it once.
///
/// The last of those is what stops a viaduct being thrown up over every dip. A
/// run of embankment sitting at the fill limit with one station a couple of
/// metres past it satisfies a length rule and a depth rule together, and 213 km
/// of a 1200 km network came out on a deck. A structure is built where the
/// ground is not there to build on, and that is a statement about the whole
/// run.
const TUNNEL_MIN: f32 = 420.0;
const TUNNEL_DEEP: f32 = 45.0;
const BRIDGE_MIN: f32 = 200.0;
const BRIDGE_HIGH: f32 = 32.0;
/// A viaduct longer than this is not a structure, it is a mistake. Past it the
/// alignment goes back to being earthworks and takes the dip.
const BRIDGE_LONG: f32 = 3200.0;
/// And a bore longer than this is a mistake too.
const TUNNEL_LONG: f32 = 4200.0;
/// Deepest a tunnel is driven and tallest a viaduct stands.
pub const TUNNEL_MAX: f32 = 220.0;
pub const VIADUCT_MAX: f32 = 110.0;
/// Running surface over the water on a crossing.
const DECK_CLEAR: f32 = 2.5;

const WELD: f32 = 34.0;
/// How far apart in height two stretches of road may be and still be the same
/// carriageway. The corridor uses the same number.
const AGREE: f32 = 6.0;
const TIE: f32 = 70.0;
const TIE_CELL: f32 = 96.0;

/// The deepest cutting and tallest embankment the survey will actually build:
/// what a run that wanted a structure and did not earn one is allowed.
pub const CUT_HARD: f32 = TUNNEL_DEEP;
pub const FILL_HARD: f32 = BRIDGE_HIGH;

pub const F_OPEN: u8 = 0;
pub const F_BRIDGE: u8 = 1;
pub const F_TUNNEL: u8 = 2;

/// Chop a routed polyline into stations at survey spacing.
///
/// Profiled at the routing waypoints alone the road runs dead straight in
/// elevation for seven hundred metres at a time and every hummock between them
/// turns into an embankment. Coincident waypoints are dropped on the way
/// through: a leg with no length has no direction and therefore no gradient,
/// and the profile either side of one steps instead of sloping.
pub fn chain(line: &[(f32, f32)], step: f32) -> Vec<(f32, f32)> {
    let mut out: Vec<(f32, f32)> = Vec::new();
    for (i, p) in line.iter().enumerate() {
        if i == 0 {
            out.push(*p);
            continue;
        }
        let a = line[i - 1];
        let d = ((p.0 - a.0).powi(2) + (p.1 - a.1).powi(2)).sqrt();
        if d < 1e-3 {
            continue;
        }
        let steps = ((d / step).round() as i32).max(1);
        for k in 1..=steps {
            let t = k as f32 / steps as f32;
            out.push((a.0 + (p.0 - a.0) * t, a.1 + (p.1 - a.1) * t));
        }
    }
    out
}

// ------------------------------------------------------------- the profile

/// The design surface: the closest line to the ground that a road can actually
/// be built along.
///
/// This is the whole of the road survey in one idea. A gradient limit says the
/// profile `y` may not change faster than `G` metres per metre; among every
/// profile that obeys that, exactly one is nearest the ground it has to be cut
/// into, and it can be found in four sweeps.
///
/// `U[i] = min_j (g[j] + G·d(i,j))` is the highest such profile that never
/// stands above the ground -- all cutting, no embankment -- and `L[i] =
/// max_j (g[j] - G·d(i,j))` is the lowest that never stands below it. Their
/// midpoint is the profile whose worst earthwork is the smallest possible, and
/// the worst earthwork is exactly `(L - U) / 2`.
///
/// What was here before was `U` alone -- the four sweeps in the order that
/// leaves the minimum pass on top -- so the road was in cut everywhere and
/// never on an embankment. Over rolling country that is a cutting nearly the
/// whole way, and it is why more than half of a two thousand kilometre network
/// had been classified as tunnel: 1040 km of it bored through hills that a
/// balanced profile crosses at grade.
fn envelopes(g: &[f32], d: &[f32], gr: &[f32], u: &mut [f32], l: &mut [f32]) {
    let n = g.len();
    u.copy_from_slice(g);
    l.copy_from_slice(g);
    for i in 1..n {
        let step = gr[i] * d[i];
        u[i] = u[i].min(u[i - 1] + step);
        l[i] = l[i].max(l[i - 1] - step);
    }
    for i in (0..n - 1).rev() {
        let step = gr[i + 1] * d[i + 1];
        u[i] = u[i].min(u[i + 1] + step);
        l[i] = l[i].max(l[i + 1] - step);
    }
}

/// Leg lengths, `d[i]` being the run from station i-1 to station i.
fn runs(p: &[(f32, f32)]) -> Vec<f32> {
    let mut d = vec![0.0f32; p.len()];
    for i in 1..p.len() {
        d[i] = ((p[i].0 - p[i - 1].0).powi(2) + (p[i].1 - p[i - 1].1).powi(2))
            .sqrt()
            .max(1e-3);
    }
    d
}

/// The gradient allowance along one line, and the profile built to it.
///
/// A mountain road is built at one in ten and takes the hill; it is not built
/// as a hundred kilometres of tunnel. The allowance is opened up only where
/// country forces it, and smeared either side so a steep stretch has a run up
/// to it rather than a kink at each end.
///
/// The allowance comes back with the profile because every later pass has to
/// use the same one. Worked out afresh from how far the profile currently
/// stands off the ground -- which is what this did -- it reads zero the moment
/// anything has clamped the profile into the cut and fill band, so the next
/// projection is at the ruling gradient, pulls the alignment straight back out
/// of the band, and the two fight for ever. Measured, that left the design
/// surface seventy metres under the hillside at a place the classifier had not
/// made a tunnel of.
pub fn design(p: &[(f32, f32)], g: &[f32]) -> (Vec<f32>, Vec<f32>) {
    let n = g.len();
    if n < 2 {
        return (g.to_vec(), vec![ROAD_GRADE; n]);
    }
    let d = runs(p);
    let mut gr = vec![ROAD_GRADE; n];
    let mut u = vec![0.0f32; n];
    let mut l = vec![0.0f32; n];
    let mut y = vec![0.0f32; n];
    const SMEAR: usize = 6;
    for pass in 0..3 {
        envelopes(g, &d, &gr, &mut u, &mut l);
        for i in 0..n {
            y[i] = (u[i] + l[i]) * 0.5;
        }
        if pass == 2 {
            break;
        }
        // how far outside a cutting and an embankment the profile still stands
        let mut any = false;
        let over: Vec<f32> = (0..n)
            .map(|i| {
                let e = (y[i] - g[i] - ROAD_FILL_MAX).max(g[i] - y[i] - ROAD_CUT_MAX);
                if e > 0.0 {
                    any = true;
                    e
                } else {
                    0.0
                }
            })
            .collect();
        if !any {
            break;
        }
        for i in 0..n {
            if over[i] <= 0.0 {
                continue;
            }
            let want = lerp(ROAD_GRADE, ROAD_GRADE_MAX, smoothstep(0.0, 30.0, over[i]));
            let lo = i.saturating_sub(SMEAR);
            let hi = (i + SMEAR).min(n - 1);
            for k in lo..=hi {
                if gr[k] < want {
                    gr[k] = want;
                }
            }
        }
    }
    (y, gr)
}

/// Pull a profile back onto a buildable gradient after something else -- a
/// junction tie, a clamp to the ground, a water crossing -- has moved it.
/// Identity on a profile that already obeys the allowance.
fn project(p: &[(f32, f32)], y: &[f32], gr: &[f32]) -> Vec<f32> {
    let n = y.len();
    if n < 2 {
        return y.to_vec();
    }
    let d = runs(p);
    let mut u = vec![0.0f32; n];
    let mut l = vec![0.0f32; n];
    envelopes(y, &d, gr, &mut u, &mut l);
    (0..n).map(|i| (u[i] + l[i]) * 0.5).collect()
}

/// Lift the carriageway clear of the sea. Applied once and left, this is undone
/// by everything that comes after it -- over water the ground the profile is
/// held near is the seabed -- so it runs again after every pass that could pull
/// it back under.
fn float_over_water(y: &mut [f32]) -> bool {
    let deck = WATER_LEVEL + DECK_CLEAR;
    let mut lifted = false;
    for v in y.iter_mut() {
        if *v < deck {
            *v = deck;
            lifted = true;
        }
    }
    lifted
}

// ------------------------------------------------------------- structures

/// Where the alignment cannot simply be cut or filled into the country it needs
/// a structure: a bridge over the low ground, a tunnel through the high. Marked
/// per station and grouped into runs, because a road does not tunnel through
/// every hummock -- a structure has to earn its length.
pub fn classify(p: &[(f32, f32)], y: &[f32], g: &[f32], starts: &[i32]) -> Vec<u8> {
    let mut flags = vec![F_OPEN; y.len()];
    for li in 0..starts.len().saturating_sub(1) {
        let (a0, a1) = (starts[li] as usize, starts[li + 1] as usize);
        if a1 <= a0 {
            continue;
        }
        for i in a0..a1 {
            let over = y[i] - g[i];
            flags[i] = if over > ROAD_FILL_MAX {
                F_BRIDGE
            } else if -over > ROAD_CUT_MAX {
                F_TUNNEL
            } else {
                F_OPEN
            };
        }
        let mut i0 = a0;
        while i0 < a1 {
            if flags[i0] == F_OPEN {
                i0 += 1;
                continue;
            }
            let kind = flags[i0];
            let mut i1 = i0;
            while i1 + 1 < a1 && flags[i1 + 1] == kind {
                i1 += 1;
            }
            let run = ((p[i1].0 - p[i0].0).powi(2) + (p[i1].1 - p[i0].1).powi(2)).sqrt();
            let mut extreme = 0.0f32;
            let mut total = 0.0f32;
            let mut wet = false;
            for k in i0..=i1 {
                let over = (y[k] - g[k]).abs();
                extreme = extreme.max(over);
                total += over;
                // A road cannot lie on the seabed, so a crossing is a bridge
                // however short it is and however little it stands off the bed.
                wet = wet || g[k] < WATER_LEVEL;
            }
            let mean = total / (i1 - i0 + 1) as f32;
            let (min_run, min_deep, min_mean, max_run) = if kind == F_BRIDGE {
                (BRIDGE_MIN, BRIDGE_HIGH, ROAD_FILL_MAX, BRIDGE_LONG)
            } else {
                (TUNNEL_MIN, TUNNEL_DEEP, ROAD_CUT_MAX, TUNNEL_LONG)
            };
            // A short run that is very deep is a structure too: a cutting
            // seventy metres down is a bore with the lid off, and it is what
            // was left standing where the length rule refused a tunnel.
            let always = if kind == F_BRIDGE { 52.0 } else { 62.0 };
            let earned = run <= max_run
                && (wet
                    || extreme >= always
                    || (run >= min_run && extreme >= min_deep && mean >= min_mean));
            if !earned {
                for k in i0..=i1 {
                    flags[k] = F_OPEN; // cut or fill it instead
                }
            }
            i0 = i1 + 1;
        }
    }
    flags
}

/// What may be built at each station: how deep it may be cut into and how high
/// it may be filled over. Open ground gets a cutting and an embankment; a
/// structure gets a bore or a deck; a run that wanted a structure and did not
/// earn one gets a little extra, because the alternative is a road that steps.
fn limits(g: &[f32], flags: &[u8], refused: &[bool]) -> (Vec<f32>, Vec<f32>) {
    let n = g.len();
    let mut lo = vec![0.0f32; n];
    let mut hi = vec![0.0f32; n];
    for i in 0..n {
        let (cut, fill) = match flags[i] {
            F_BRIDGE => (ROAD_CUT_MAX, VIADUCT_MAX),
            F_TUNNEL => (TUNNEL_MAX, ROAD_FILL_MAX),
            _ if refused[i] => (TUNNEL_DEEP, BRIDGE_HIGH),
            _ => (ROAD_CUT_MAX, ROAD_FILL_MAX),
        };
        lo[i] = g[i] - cut;
        hi[i] = g[i] + fill;
    }
    (lo, hi)
}

/// The profile nearest to what the tying wants that a road can actually be
/// built along: inside the earthworks it is allowed, and never changing faster
/// than the gradient allowance.
///
/// What was here before was a clamp into the band followed by a projection onto
/// the gradient, run over and over. Those are two convex sets and alternating
/// between them does converge -- but only in the limit, and where they barely
/// intersect it converges slowly: measured, the design surface came out seventy
/// metres under the hillside at a station the classifier had left as open
/// ground, and the corridor then carved a cliff trying to reach it.
///
/// Both constraints at once instead. Propagating the band edges along the line
/// at the gradient allowance makes each of them Lipschitz in its own right --
/// `hi` cannot rise faster than the road may climb, `lo` cannot fall faster
/// than it may descend -- and the median of three Lipschitz functions is
/// Lipschitz. So clamping the wanted profile between the propagated edges
/// satisfies both in one pass, with nothing left to iterate.
///
/// Where the two edges cross, no road can be built there at all: that is the
/// country a structure exists for, and the crossing is what marks it out.
#[allow(clippy::too_many_arguments)]
fn solve_band(p: &[(f32, f32)], want: &[f32], g: &[f32], lo0: &[f32],
        hi0: &[f32], gr: &[f32], pin: &[f32]) -> Vec<f32> {
    let n = want.len();
    if n < 2 {
        return want.to_vec();
    }
    let d = runs(p);
    let mut allow = gr.to_vec();
    let mut lo = vec![0.0f32; n];
    let mut hi = vec![0.0f32; n];
    for attempt in 0..3 {
        lo.copy_from_slice(lo0);
        hi.copy_from_slice(hi0);
        // A junction is one height for both roads, not a range for each.
        for i in 0..n {
            if pin[i].is_finite() {
                lo[i] = pin[i];
                hi[i] = pin[i];
            }
        }
        for i in 1..n {
            let step = allow[i] * d[i];
            hi[i] = hi[i].min(hi[i - 1] + step);
            lo[i] = lo[i].max(lo[i - 1] - step);
        }
        for i in (0..n - 1).rev() {
            let step = allow[i + 1] * d[i + 1];
            hi[i] = hi[i].min(hi[i + 1] + step);
            lo[i] = lo[i].max(lo[i + 1] - step);
        }
        if attempt == 2 {
            break;
        }
        // Where the edges cross there is no profile at all: the road would have
        // to climb faster than it is allowed to reach ground it is also not
        // allowed to tunnel under. Open the allowance around it and try again
        // -- a steeper road is very much better than the alternative, which is
        // the profile being dragged down by the valley at the far end of the
        // climb. Measured before this, a design surface 1197 m under a
        // mountain, and a corridor dutifully carving a trench to meet it.
        let mut any = false;
        for i in 0..n {
            if lo[i] <= hi[i] {
                continue;
            }
            any = true;
            let k0 = i.saturating_sub(24);
            let k1 = (i + 24).min(n - 1);
            for a in allow.iter_mut().take(k1 + 1).skip(k0) {
                *a = a.max(GRADE_HAIRPIN);
            }
        }
        if !any {
            break;
        }
    }
    // And where even a hairpin cannot do it, the road lies on the country and
    // takes the gradient the country has. That is a mountain track, which is a
    // real thing; a kilometre deep slot through the range is not.
    (0..n)
        .map(|i| {
            let held = want[i].max(lo[i]).min(hi[i]);
            let bad = lo[i] - hi[i];
            if bad > 0.0 {
                lerp(held, g[i], smoothstep(0.0, 12.0, bad))
            } else {
                held
            }
        })
        .collect()
}

/// The whole tail of the survey: settle the profile, decide what has to be
/// carried or bored, and settle it again knowing that.
///
/// All of it here rather than a pass at a time across the boundary. In script
/// this was three classify-hold-grade rounds and a twenty-four pass smoother
/// over eighty thousand stations, and it was the longest thing left in world
/// generation after the routing itself went native.
pub fn finish(p: &[(f32, f32)], y0: &[f32], g: &[f32], gr: &[f32],
        starts: &[i32]) -> (Vec<f32>, Vec<u8>) {
    let lines = starts.len().saturating_sub(1);
    let n = y0.len();
    let mut y = y0.to_vec();
    float_over_water(&mut y);
    let owner = owners(n, starts);
    let grid = leg_grid(p, starts);
    let joins = junctions(p, starts, WELD);
    let mut flags = vec![F_OPEN; n];
    let mut refused = vec![false; n];
    // What is a structure depends on the profile, and the profile depends on
    // what may be built at each station -- so it is worked out by going round.
    for _ in 0..6 {
        let mut want_flags = classify(p, &y, g, starts);
        spread_structures(p, &y, &owner, &mut want_flags);
        // A run that asked for a structure and did not earn one is not simply
        // put back on the ground: it is the country that wanted one, so it gets
        // the deepest cutting and the tallest embankment that are still
        // earthworks. Without that the profile is held somewhere it cannot go
        // and the corridor carves a cliff reaching for it.
        for i in 0..n {
            refused[i] = flags[i] != F_OPEN && want_flags[i] == F_OPEN;
        }
        flags = want_flags;
        let (lo, hi) = limits(g, &flags, &refused);
        // Roads that meet have to go on agreeing about the height, and out of
        // the water before the solve rather than after it: a crossing lifted
        // onto a deck and then settled is a bridge, one settled and then lifted
        // has a step at each abutment.
        let mut want = tie(&grid, p, &y, &owner, Some(&flags));
        float_over_water(&mut want);
        // and where roads actually meet, one height rather than two
        let mut pin = vec![f32::NAN; n];
        for grp in &joins {
            let mut at = 0.0f32;
            for i in grp {
                at += y[*i as usize];
            }
            at /= grp.len() as f32;
            for i in grp {
                let i = *i as usize;
                // inside what can be built there, or the pin is a hole in the
                // ground that both roads then have to climb out of
                pin[i] = at.clamp(lo[i], hi[i]);
            }
        }
        let mut parts: Vec<(usize, Vec<f32>)> = (0..lines)
            .into_par_iter()
            .map(|li| {
                let (a0, a1) = (starts[li] as usize, starts[li + 1] as usize);
                (a0, solve_band(&p[a0..a1], &want[a0..a1], &g[a0..a1],
                    &lo[a0..a1], &hi[a0..a1], &gr[a0..a1], &pin[a0..a1]))
            })
            .collect();
        for (a0, seg) in parts.drain(..) {
            y[a0..a0 + seg.len()].copy_from_slice(&seg);
        }
    }
    // The last word: nothing on the network may be steeper than a hairpin,
    // whatever the country does. Where the band had no solution at all the
    // profile was left lying on the ground, and the ground in that sort of
    // place is a cliff -- measured, a 433% gradient in the alignment. This is
    // identity on every stretch that is already buildable.
    let hard = vec![GRADE_HAIRPIN; n];
    let mut parts: Vec<(usize, Vec<f32>)> = (0..lines)
        .into_par_iter()
        .map(|li| {
            let (a0, a1) = (starts[li] as usize, starts[li + 1] as usize);
            (a0, project(&p[a0..a1], &y[a0..a1], &hard[a0..a1]))
        })
        .collect();
    for (a0, seg) in parts.drain(..) {
        y[a0..a0 + seg.len()].copy_from_slice(&seg);
    }
    flags = classify(p, &y, g, starts);
    spread_structures(p, &y, &owner, &mut flags);
    (y, flags)
}

// ------------------------------------------------------------- the relaxation

/// Where two routes run into or alongside each other they have to agree about
/// the height. Surveyed independently a pair crossing at a junction came out
/// eight metres apart six metres from one another: a step down the side of the
/// carriageway with no slope in between.
///
/// Every station of every line, welded onto its neighbours, tied in height, and
/// re-profiled -- as many times as it takes. The passes are over an index built
/// from the state at the start of the pass, so each one is a pure map over the
/// stations and runs on every core.
pub fn relax(p: &mut Vec<(f32, f32)>, y: &mut Vec<f32>, gr: &[f32],
        starts: &[i32], passes: i32) {
    let lines = starts.len().saturating_sub(1);
    if lines == 0 {
        return;
    }
    let owner = owners(p.len(), starts);
    // The index is rebuilt every few passes rather than every pass. Welding
    // moves a station by a couple of metres against a thirty-four metre reach
    // and a ninety-six metre cell with a ring of neighbours around it, so an
    // index a few passes old still finds everything -- and building it is the
    // one part of the relaxation that cannot be spread across the cores.
    const REINDEX: i32 = 4;
    let mut grid = leg_grid(p, starts);
    for pass in 0..passes.max(0) {
        if pass > 0 && pass % REINDEX == 0 {
            grid = leg_grid(p, starts);
        }
        // --- weld: pull parallel stretches onto one another ---------------
        let moved: Vec<(f32, f32)> = (0..p.len())
            .into_par_iter()
            .map(|i| {
                let mut px = 0.0f32;
                let mut pz = 0.0f32;
                let mut wsum = 0.0f32;
                near(&grid, p, y, &owner, None, p[i], i, WELD, |_, d, fx, fz| {
                    let w = 1.0 - d / WELD;
                    px += fx * w;
                    pz += fz * w;
                    wsum += w;
                });
                if wsum > 0.0 {
                    let t = (wsum * 0.35).clamp(0.0, 0.5);
                    (
                        p[i].0 + (px / wsum - p[i].0) * t,
                        p[i].1 + (pz / wsum - p[i].1) * t,
                    )
                } else {
                    p[i]
                }
            })
            .collect();
        // --- tie: agree about the height where they meet ------------------
        let tied = tie(&grid, p, y, &owner, None);
        *p = moved;
        *y = tied;
        // Do not let a station be pulled onto its own neighbour. Welding drags
        // parallel stretches together, and where several roads run close it can
        // put two consecutive stations of one line on the same spot -- a leg
        // with no length, no direction and therefore no gradient.
        for li in 0..lines {
            let (a0, a1) = (starts[li] as usize, starts[li + 1] as usize);
            for i in a0 + 1..a1 {
                let dx = p[i].0 - p[i - 1].0;
                let dz = p[i].1 - p[i - 1].1;
                let d = (dx * dx + dz * dz).sqrt();
                if d >= SURVEY_STEP * 0.35 {
                    continue;
                }
                if d > 1e-4 {
                    let s = SURVEY_STEP * 0.35 / d;
                    p[i] = (p[i - 1].0 + dx * s, p[i - 1].1 + dz * s);
                } else {
                    // no direction left to push it along: take the line's
                    p[i] = (p[i - 1].0 + SURVEY_STEP * 0.35, p[i - 1].1);
                }
            }
        }
        // --- back onto a buildable gradient, line by line -----------------
        let mut parts: Vec<(usize, Vec<f32>)> = (0..lines)
            .into_par_iter()
            .map(|li| {
                let (a0, a1) = (starts[li] as usize, starts[li + 1] as usize);
                (a0, project(&p[a0..a1], &y[a0..a1], &gr[a0..a1]))
            })
            .collect();
        for (a0, seg) in parts.drain(..) {
            y[a0..a0 + seg.len()].copy_from_slice(&seg);
        }
    }
}

/// Which line each station belongs to, so a road is not a junction with the
/// stretch of itself it stands on.
fn owners(n: usize, starts: &[i32]) -> Vec<u32> {
    let mut owner = vec![0u32; n];
    for li in 0..starts.len().saturating_sub(1) {
        for k in starts[li] as usize..starts[li + 1] as usize {
            owner[k] = li as u32;
        }
    }
    owner
}

/// Pull the heights of roads that run into one another together.
///
/// `flags`, when given, keeps structures out of it in both directions: a road
/// on a viaduct is not disagreeing with the road passing underneath it, and
/// dragging the two together would put the deck on the ground.
fn tie(grid: &Map<i64, Vec<u32>>, p: &[(f32, f32)], y: &[f32], owner: &[u32],
        flags: Option<&[u8]>) -> Vec<f32> {
    (0..p.len())
        .into_par_iter()
        .map(|i| {
            if flags.map_or(false, |f| f[i] != F_OPEN) {
                return y[i];
            }
            let mut ysum = 0.0f32;
            let mut wsum = 0.0f32;
            near(grid, p, y, owner, flags, p[i], i, TIE, |hy, d, _, _| {
                let mut w = 1.0 - d / TIE;
                w *= w;
                ysum += hy * w;
                wsum += w;
            });
            if wsum > 0.0 {
                lerp(y[i], ysum / wsum, (wsum * 0.6).clamp(0.0, 0.9))
            } else {
                y[i]
            }
        })
        .collect()
}

/// Which stations are the same place: where one road runs into another, the
/// two have to be at one height, not merely near it.
///
/// Tying them softly -- pulling each station toward the mean of what runs near
/// it -- gets most of the way and no further, because the pull is local and the
/// re-grading it implies is not: a road arriving at a junction from a valley
/// cannot simply be lifted at the last station to meet one arriving along a
/// ridge, it has to be lifted over the kilometre before it. Measured, the worst
/// junction on the network still came out twenty-three metres apart, and a
/// blended corridor across that is a step down the middle of the carriageway
/// and a 74% gradient in the finished ground.
///
/// Found here and then *pinned* in the profile solve, which propagates the
/// shared height back along both roads at whatever gradient each is allowed.
fn junctions(p: &[(f32, f32)], starts: &[i32], reach: f32) -> Vec<Vec<u32>> {
    let n = p.len();
    let owner = owners(n, starts);
    let cell = reach.max(1.0);
    let mut grid: Map<i64, Vec<u32>> = Map::default();
    for (i, q) in p.iter().enumerate() {
        grid.entry(key((q.0 / cell).floor() as i32, (q.1 / cell).floor() as i32))
            .or_default()
            .push(i as u32);
    }
    // union-find over stations that are within reach and on different roads
    let mut root: Vec<u32> = (0..n as u32).collect();
    fn find(root: &mut Vec<u32>, a: u32) -> u32 {
        let mut r = a;
        while root[r as usize] != r {
            root[r as usize] = root[root[r as usize] as usize];
            r = root[r as usize];
        }
        r
    }
    let r2 = reach * reach;
    for i in 0..n {
        let ci = (p[i].0 / cell).floor() as i32;
        let cj = (p[i].1 / cell).floor() as i32;
        for oi in -1..=1 {
            for oj in -1..=1 {
                let Some(b) = grid.get(&key(ci + oi, cj + oj)) else {
                    continue;
                };
                for j in b {
                    let j = *j as usize;
                    if j <= i || owner[j] == owner[i] {
                        continue;
                    }
                    let dx = p[i].0 - p[j].0;
                    let dz = p[i].1 - p[j].1;
                    if dx * dx + dz * dz > r2 {
                        continue;
                    }
                    let (ra, rb) = (find(&mut root, i as u32), find(&mut root, j as u32));
                    if ra != rb {
                        root[ra as usize] = rb;
                    }
                }
            }
        }
    }
    let mut by: Map<u32, Vec<u32>> = Map::default();
    for i in 0..n as u32 {
        let r = find(&mut root, i);
        if r != i || root[i as usize] != i {
            by.entry(r).or_default().push(i);
        }
    }
    by.into_values().filter(|g| g.len() > 1).collect()
}

/// Two stretches of road in the same place at the same height are one road, and
/// one road is either carried on a deck or it is not.
///
/// Classified independently they came out as one of each -- so the deck stood
/// on made ground with its twin's carriageway painted on the country
/// underneath it, which is exactly what a bridge exists not to look like. It
/// happens where the weld has drawn two routes together, and where a line
/// doubles back and runs alongside itself.
fn spread_structures(p: &[(f32, f32)], y: &[f32], owner: &[u32], flags: &mut [u8]) {
    const REACH: f32 = WELD;
    /// How far apart along one road two stations have to be before being in the
    /// same place means the road has doubled back rather than simply gone on.
    const APART: i64 = 20;
    let n = p.len();
    let mut grid: Map<i64, Vec<u32>> = Map::default();
    for (i, q) in p.iter().enumerate() {
        grid.entry(key((q.0 / REACH).floor() as i32, (q.1 / REACH).floor() as i32))
            .or_default()
            .push(i as u32);
    }
    let r2 = REACH * REACH;
    let found: Vec<u8> = (0..n)
        .into_par_iter()
        .map(|i| {
            let mut kind = flags[i];
            if kind != F_OPEN {
                return kind;
            }
            let ci = (p[i].0 / REACH).floor() as i32;
            let cj = (p[i].1 / REACH).floor() as i32;
            for oi in -1..=1 {
                for oj in -1..=1 {
                    let Some(b) = grid.get(&key(ci + oi, cj + oj)) else {
                        continue;
                    };
                    for j in b {
                        let j = *j as usize;
                        if flags[j] == F_OPEN {
                            continue;
                        }
                        if owner[j] == owner[i]
                            && (j as i64 - i as i64).abs() < APART
                        {
                            continue;
                        }
                        if (y[i] - y[j]).abs() > AGREE {
                            continue;      // passing over or under, not alongside
                        }
                        let dx = p[i].0 - p[j].0;
                        let dz = p[i].1 - p[j].1;
                        if dx * dx + dz * dz <= r2 {
                            kind = flags[j];
                        }
                    }
                }
            }
            kind
        })
        .collect();
    flags.copy_from_slice(&found);
}

/// Every leg of the network, bucketed by ground cell.
fn leg_grid(p: &[(f32, f32)], starts: &[i32]) -> Map<i64, Vec<u32>> {
    let mut grid: Map<i64, Vec<u32>> = Map::default();
    for li in 0..starts.len().saturating_sub(1) {
        let (a0, a1) = (starts[li] as usize, starts[li + 1] as usize);
        for k in a0..a1.saturating_sub(1) {
            let (u, v) = (p[k], p[k + 1]);
            let len = ((v.0 - u.0).powi(2) + (v.1 - u.1).powi(2)).sqrt();
            let steps = ((len / (TIE_CELL * 0.5)) as i32).max(1);
            for q in 0..=steps {
                let t = q as f32 / steps as f32;
                let wx = u.0 + (v.0 - u.0) * t;
                let wz = u.1 + (v.1 - u.1) * t;
                let ci = (wx / TIE_CELL).floor() as i32;
                let cj = (wz / TIE_CELL).floor() as i32;
                for oi in -1..=1 {
                    for oj in -1..=1 {
                        let e = grid.entry(key(ci + oi, cj + oj)).or_default();
                        if e.last() != Some(&(k as u32)) {
                            e.push(k as u32);
                        }
                    }
                }
            }
        }
    }
    grid
}

/// Legs of somebody else's road running within `reach` of a point, handed to
/// the caller as (height there, distance, foot of the perpendicular).
///
/// Reported through a callback rather than as a list: at eighty thousand
/// stations twice a pass, allocating a vector for the handful of legs near each
/// one costs more than the arithmetic does.
///
/// Measuring vertex to vertex missed the case that actually matters -- two
/// roads crossing at a shallow angle, five metres apart, whose nearest
/// waypoints are fifty metres from one another.
#[inline]
fn near<F>(grid: &Map<i64, Vec<u32>>, p: &[(f32, f32)], y: &[f32],
        owner: &[u32], flags: Option<&[u8]>, at: (f32, f32), idx: usize,
        reach: f32, mut hit: F)
where
    F: FnMut(f32, f32, f32, f32),
{
    let k = key((at.0 / TIE_CELL).floor() as i32, (at.1 / TIE_CELL).floor() as i32);
    let bucket = match grid.get(&k) {
        Some(b) => b,
        None => return,
    };
    for l in bucket {
        let l = *l as usize;
        if owner[l] == owner[idx] && (l as i64 - idx as i64).abs() < 6 {
            continue;
        }
        // A leg on a viaduct or inside a bore is not running alongside the
        // road it passes over: it is a hundred metres above or below it, and
        // pulling the two together would put the deck on the ground.
        if flags.map_or(false, |f| f[l] != F_OPEN || f[l + 1] != F_OPEN) {
            continue;
        }
        let a = p[l];
        let abx = p[l + 1].0 - a.0;
        let abz = p[l + 1].1 - a.1;
        let len2 = (abx * abx + abz * abz).max(0.001);
        let t = (((at.0 - a.0) * abx + (at.1 - a.1) * abz) / len2).clamp(0.0, 1.0);
        let fx = a.0 + abx * t;
        let fz = a.1 + abz * t;
        let d = ((at.0 - fx).powi(2) + (at.1 - fz).powi(2)).sqrt();
        if d > reach {
            continue;
        }
        hit(lerp(y[l], y[l + 1], t), d, fx, fz);
    }
}

/// The largest height difference a driver would see between the road under the
/// wheels and another stretch of road running alongside it. The number the
/// tying pass exists to bring down, so it is measured rather than assumed.
pub fn worst_tie(p: &[(f32, f32)], y: &[f32], flags: &[u8], starts: &[i32]) -> f32 {
    if starts.len() < 2 {
        return 0.0;
    }
    let owner = owners(p.len(), starts);
    let grid = leg_grid(p, starts);
    (0..p.len())
        .into_par_iter()
        .map(|i| {
            if flags.get(i).copied().unwrap_or(F_OPEN) != F_OPEN {
                return 0.0;
            }
            let mut worst = 0.0f32;
            near(&grid, p, y, &owner, Some(flags), p[i], i, 40.0, |hy, _, _, _| {
                worst = worst.max((y[i] - hy).abs());
            });
            worst
        })
        .reduce(|| 0.0f32, f32::max)
}
