//! What the world has been made to do to the land: the levelled town
//! platforms, the aerodromes, and the made roads.
//!
//! Everything that asks how high the ground is asks here, and it has to answer
//! the same way for the terrain mesh, the landing gear and the road survey --
//! so all three layers live on this side of the boundary rather than being
//! finished off in script afterwards.

use crate::field::{lerp, natural, smoothstep};
use crate::index::key;
use std::collections::HashMap;
use std::sync::atomic::{AtomicPtr, Ordering};

// ------------------------------------------------------------- what is built

#[derive(Clone, Copy)]
pub struct Pad {
    pub x: f32,
    pub z: f32,
    pub r: f32,
    pub y: f32,
}

/// An aerodrome: where it is, which way the runway points, and the elevation
/// its pavement was laid at.
#[derive(Clone, Copy)]
pub struct Airfield {
    pub x: f32,
    pub z: f32,
    pub yaw: f32,
    pub elev: f32,
}

#[derive(Default)]
pub struct World {
    pub pads: Vec<Pad>,
    pub fields: Vec<Airfield>,
}

/// Set once while the world is built, then read from every thread for the rest
/// of the run. Behind a lock this was two atomic read-modify-writes per height
/// query on one shared cache line, and with eight workers scattering trees that
/// contention cost more than the arithmetic did -- a call that measures at a
/// quarter of a microsecond on its own took seventeen times that in the crowd.
/// The data is leaked deliberately: it lives as long as the process, so a
/// reader only has to load a pointer.
static WORLD_P: AtomicPtr<World> = AtomicPtr::new(std::ptr::null_mut());

pub fn world() -> &'static World {
    static EMPTY: std::sync::OnceLock<World> = std::sync::OnceLock::new();
    let p = WORLD_P.load(Ordering::Acquire);
    if p.is_null() {
        return EMPTY.get_or_init(World::default);
    }
    // Sound: the pointee is leaked at publication and never mutated or freed.
    unsafe { &*p }
}

pub fn publish_world(w: World) {
    WORLD_P.store(Box::into_raw(Box::new(w)), Ordering::Release);
}

// ------------------------------------------------------------- the aerodrome

pub const RUNWAY_LEN: f32 = 3000.0;
pub const RUNWAY_HALF_W: f32 = 23.0;
/// Half the levelled apron, plus the margin the terrain mesh needs to be able
/// to draw it: a strip narrower than a cell is smaller than one triangle and
/// the flattening is invisible. `Terrain.BASE_CELL` is 15 m, and the pad is two
/// and a half cells.
const FIELD_HALF_X: f32 = 950.0 + 37.5;
const FIELD_HALF_Z: f32 = 1950.0 + 37.5;
const FIELD_FADE: f32 = 2600.0;

/// How much of one aerodrome applies at a point: 1 on the apron, easing to 0
/// out in open country.
#[inline]
pub fn field_factor(f: &Airfield, x: f32, z: f32) -> f32 {
    let dx = x - f.x;
    let dz = z - f.z;
    let c = (-f.yaw).cos();
    let s = (-f.yaw).sin();
    let lx = dx * c - dz * s;
    let lz = dx * s + dz * c;
    let ox = (lx.abs() - FIELD_HALF_X).max(0.0);
    let oz = (lz.abs() - FIELD_HALF_Z).max(0.0);
    1.0 - smoothstep(0.0, FIELD_FADE, (ox * ox + oz * oz).sqrt())
}

pub fn on_runway(w: &World, x: f32, z: f32) -> bool {
    for f in &w.fields {
        let dx = x - f.x;
        let dz = z - f.z;
        let c = (-f.yaw).cos();
        let s = (-f.yaw).sin();
        let lx = dx * c - dz * s;
        let ly = dx * s + dz * c;
        if lx.abs() <= RUNWAY_HALF_W && ly.abs() <= RUNWAY_LEN * 0.5 {
            return true;
        }
    }
    false
}

// ------------------------------------------------------------- the corridor
//
// The made road, and the ground it was cut from. Every height query in the
// game asks whether it is on a road, so this has to answer without walking the
// network: the legs are stamped into a coarse grid once and the query looks at
// one cell.

pub const ROAD_HALF: f32 = 7.5;
pub const ROAD_SHOULDER: f32 = 24.0;
pub const ROAD_FILL_MAX: f32 = 22.0;
pub const ROAD_CUT_MAX: f32 = 34.0;
const CORR_CELL: f32 = 64.0;
/// How far apart in height two stretches of road may be and still be treated as
/// one carriageway.
const AGREE: f32 = 6.0;

#[derive(Clone, Copy)]
pub struct Leg {
    pub ax: f32,
    pub az: f32,
    pub bx: f32,
    pub bz: f32,
    pub ya: f32,
    pub yb: f32,
    pub na: f32,
    pub nb: f32,
}

#[derive(Default)]
pub struct Corridor {
    pub legs: Vec<Leg>,
    pub grid: HashMap<i64, Vec<u32>>,
}

/// Same reasoning as `WORLD_P`.
static CORR_P: AtomicPtr<Corridor> = AtomicPtr::new(std::ptr::null_mut());

pub fn corridor() -> &'static Corridor {
    static EMPTY: std::sync::OnceLock<Corridor> = std::sync::OnceLock::new();
    let p = CORR_P.load(Ordering::Acquire);
    if p.is_null() {
        return EMPTY.get_or_init(Corridor::default);
    }
    unsafe { &*p }
}

/// Build the lookup grid over a set of legs and publish it.
pub fn publish_corridor(legs: Vec<Leg>) {
    let mut c = Corridor {
        legs,
        grid: HashMap::new(),
    };
    let pad = ROAD_HALF + ROAD_SHOULDER;
    for (idx, l) in c.legs.iter().enumerate() {
        let dx = l.bx - l.ax;
        let dz = l.bz - l.az;
        let len = (dx * dx + dz * dz).sqrt();
        let steps = ((len / (CORR_CELL * 0.5)) as i32).max(1);
        for k in 0..=steps {
            let t = k as f32 / steps as f32;
            let qx = l.ax + dx * t;
            let qz = l.az + dz * t;
            let ci = ((qx - pad) / CORR_CELL).floor() as i32;
            let cj = ((qz - pad) / CORR_CELL).floor() as i32;
            for oi in 0..3 {
                for oj in 0..3 {
                    let e = c.grid.entry(key(ci + oi, cj + oj)).or_default();
                    if e.last() != Some(&(idx as u32)) {
                        e.push(idx as u32);
                    }
                }
            }
        }
    }
    CORR_P.store(Box::into_raw(Box::new(c)), Ordering::Release);
}

/// Where a point falls on a leg: the distance to it and how far along it.
#[inline]
fn foot(l: &Leg, x: f32, z: f32) -> (f32, f32) {
    let abx = l.bx - l.ax;
    let abz = l.bz - l.az;
    let len2 = (abx * abx + abz * abz).max(0.001);
    let t = (((x - l.ax) * abx + (z - l.az) * abz) / len2).clamp(0.0, 1.0);
    let dx = x - (l.ax + abx * t);
    let dz = z - (l.az + abz * t);
    ((dx * dx + dz * dz).sqrt(), t)
}

/// The made surface at a point: its height, how much of it applies here, and
/// the ground it was cut from. Zero weight means the land is left as it was.
pub fn road_surface(c: &Corridor, x: f32, z: f32) -> (f32, f32, f32) {
    if c.legs.is_empty() {
        return (0.0, 0.0, 0.0);
    }
    let reach = ROAD_HALF + ROAD_SHOULDER;
    let k = key((x / CORR_CELL).floor() as i32, (z / CORR_CELL).floor() as i32);
    let bucket = match c.grid.get(&k) {
        Some(b) => b,
        None => return (0.0, 0.0, 0.0),
    };
    // Nearest first, then blend what agrees with it.
    //
    // Blending everything within reach by distance alone is right for two
    // routes running a few metres apart -- without it the carriageway snaps to
    // one of them and leaves a step down the middle of the road. It is wrong
    // for a hairpin, where the two limbs are a few metres apart in plan and
    // tens of metres apart in height: the blend smears the upper limb into the
    // lower one and tips the carriageway sideways. Measured, an 18% cross fall.
    let mut best = 1e9f32;
    let mut near_y = 0.0f32;
    let mut near_g = 0.0f32;
    for idx in bucket {
        let l = &c.legs[*idx as usize];
        let (d, t) = foot(l, x, z);
        if d < best {
            best = d;
            near_y = lerp(l.ya, l.yb, t);
            near_g = lerp(l.na, l.nb, t);
        }
    }
    if best > reach {
        return (0.0, 0.0, 0.0);
    }
    let mut ysum = 0.0;
    let mut gsum = 0.0;
    let mut wsum = 0.0;
    for idx in bucket {
        let l = &c.legs[*idx as usize];
        let (d, t) = foot(l, x, z);
        if d >= reach {
            continue;
        }
        let y = lerp(l.ya, l.yb, t);
        if (y - near_y).abs() > AGREE {
            continue;                  // a different road, passing over or under
        }
        let w = 1.0 / (d * d + 1.5);
        ysum += y * w;
        gsum += lerp(l.na, l.nb, t) * w;
        wsum += w;
    }
    if wsum <= 0.0 {
        return (near_y, 1.0 - smoothstep(ROAD_HALF, reach, best), near_g);
    }
    (ysum / wsum, 1.0 - smoothstep(ROAD_HALF, reach, best), gsum / wsum)
}

// ------------------------------------------------------------ finished ground

/// What a height query is asking to have applied. The town platforms are
/// always in -- they are part of the land as soon as a town is sited.
pub const G_ROADS: u32 = 1;
/// The aerodromes, which win over everything else. Off only while a field is
/// being sited, so it reads the height of its own ground rather than of the
/// pavement it is about to lay.
pub const G_FIELDS: u32 = 2;
/// Everything: what `Sim.height_at` asks for.
pub const G_ALL: u32 = G_ROADS | G_FIELDS;

/// The ground as the world has left it. The carrier decks are the one thing
/// still applied on the far side of the boundary: they move every frame, and
/// there are two of them.
pub fn ground_at(w: &World, c: &Corridor, x: f32, z: f32, flags: u32) -> f32 {
    let mut h = natural(x, z);
    let mut pad_w = 0.0f32;
    for p in &w.pads {
        let dx = x - p.x;
        let dz = z - p.z;
        let d = (dx * dx + dz * dz).sqrt();
        if d < p.r * 1.60 {
            let t = 1.0 - smoothstep(p.r * 1.06, p.r * 1.60, d);
            h = lerp(h, p.y, t);
            if t > pad_w {
                pad_w = t;
            }
        }
    }
    if flags & G_FIELDS != 0 {
        // The aerodrome beats the town platforms, and it beats them outright: a
        // town levelled itself on top of the runway and the pavement ended up
        // fifty-seven metres under the ground it was supposed to be lying on.
        for f in &w.fields {
            let ff = field_factor(f, x, z);
            if ff > 0.0 {
                h = lerp(h, f.elev, ff);
            }
        }
    }
    if flags & G_ROADS != 0 {
        // The road last, because the road was surveyed against the ground with
        // the aerodrome already in it -- that is what lets a road run onto an
        // airfield's apron instead of ending at a cliff beside it.
        //
        // Applied the other way round, the survey believed it was cutting five
        // metres where the corridor was in fact carving ninety-five: the design
        // was drawn against the levelled apron and then imposed on the hillside
        // underneath it. Nothing is at risk on the runway itself -- the router
        // charges four thousand times the going rate to cross one.
        h = road_over(c, x, z, h, pad_w);
    }
    h
}

/// The earthworks: what the corridor does to the ground it passes over.
fn road_over(c: &Corridor, x: f32, z: f32, h: f32, pad_w: f32) -> f32 {
    let (ry, rw, _) = road_surface(c, x, z);
    if rw <= 0.0 {
        return h;
    }
    // Eased out rather than switched off: a hard cut-off left a step down one
    // side of the carriageway wherever the earthworks reached their limit.
    let mut carry = 1.0 - smoothstep(ROAD_FILL_MAX, ROAD_FILL_MAX * 2.2, ry - h);
    carry *= 1.0 - smoothstep(ROAD_CUT_MAX, ROAD_CUT_MAX * 2.4, h - ry);
    // a town has already been levelled; a road through it runs on the made
    // ground rather than in a cutting of its own
    carry *= 1.0 - pad_w;
    // The carriageway itself is always levelled; only the grading out to
    // either side of it eases off.
    let core = ((rw - 0.82) / 0.18).clamp(0.0, 1.0);
    let ww = (rw * carry).max(core);
    if ww > 0.0 {
        // Straight onto the design surface, with no bound of its own.
        //
        // This used to clamp the target against the untouched ground at the
        // centreline, as a guard on a profile that could ask for anything. The
        // survey now solves the earthworks limit and the gradient together, so
        // the design is inside what can be built by construction -- and the
        // guard was doing real harm: wherever it bit, the finished road stood
        // several metres off its own surface, which tipped the carriageway
        // sideways and put a cliff along the centreline. Measured, an 18% cross
        // fall and a 174% gradient in the finished ground.
        return lerp(h, ry, ww);
    }
    h
}

/// The ground the surveyor sees: the field and the town platforms, with no
/// road on it. The aerodrome is not blended in -- it is kept out by penalty in
/// the router, which is what actually steers a road around it.
#[inline]
pub fn road_height(w: &World, x: f32, z: f32) -> f32 {
    let mut h = natural(x, z);
    for p in &w.pads {
        let dx = x - p.x;
        let dz = z - p.z;
        let d = (dx * dx + dz * dz).sqrt();
        if d < p.r * 1.60 {
            let t = 1.0 - smoothstep(p.r * 1.06, p.r * 1.60, d);
            h = lerp(h, p.y, t);
        }
    }
    h
}
