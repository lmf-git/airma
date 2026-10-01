//! What the world has been made to do to the land: the levelled town
//! platforms, the aerodromes, and the made roads.
//!
//! Everything that asks how high the ground is asks here, and it has to answer
//! the same way for the terrain mesh, the landing gear and the road survey --
//! so all three layers live on this side of the boundary rather than being
//! finished off in script afterwards.

use crate::field::{lerp, natural, smoothstep};
use crate::sphere::{self, Chart};
use crate::index::key;
use std::collections::HashMap;
use std::sync::atomic::{AtomicPtr, Ordering};
use rayon::prelude::*;
use std::sync::Mutex;

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

// ------------------------------------------------------------------ decks
//
// The one part of the world that moves. Everything else here is published once
// and read for the rest of the run; a carrier carries her flight deck with her,
// so the decks are pushed over before the work that reads them.

/// A landable platform standing over the ground: a carrier's flight deck.
///
/// The one part of the world the extension does not hold permanently, because
/// it moves -- so it is pushed in before each batch of chunks goes out rather
/// than published once with the roads and the aerodromes.
#[derive(Clone, Copy)]
pub struct Deck {
    ox: f32,
    oz: f32,
    cs: f32,
    sn: f32,
    hx: f32,
    hz: f32,
    y: f32,
}

static DECKS: Mutex<Vec<Deck>> = Mutex::new(Vec::new());

/// Flat runs of origin x, origin z, cos(-yaw), sin(-yaw), half x, half z, deck
/// height -- the same seven numbers `Sim.register_deck` keeps.
pub fn set_decks(data: &[f32]) {
    let mut v = Vec::with_capacity(data.len() / 7);
    for q in data.chunks_exact(7) {
        v.push(Deck {
            ox: q[0],
            oz: q[1],
            cs: q[2],
            sn: q[3],
            hx: q[4],
            hz: q[5],
            y: q[6],
        });
    }
    *DECKS.lock().unwrap() = v;
}

/// The deck over a point, or nothing. Mirrors `Sim.deck_height`.
#[inline]
fn deck_height(decks: &[Deck], x: f32, z: f32) -> Option<f32> {
    for d in decks {
        let dx = x - d.ox;
        let dz = z - d.oz;
        let lx = dx * d.cs - dz * d.sn;
        let lz = dx * d.sn + dz * d.cs;
        if lx.abs() <= d.hx && lz.abs() <= d.hz {
            return Some(d.y);
        }
    }
    None
}

// ------------------------------------------------------------- the ground

/// The ground as the game measures it, with the answer's ingredients gathered
/// once.
///
/// Everything that asks for a lot of ground at once wants the same three
/// things settled before it starts: whether this world is round, where the
/// chart is, and what has been built. Read per sample they are three atomic
/// loads and a `Vec` clone for every height in a nine hundred point chunk;
/// gathered here they are read once and the loop is arithmetic.
pub struct Ground {
    globe: bool,
    chart: Chart,
    /// Empty when the caller does not want the moving platforms.
    decks: Vec<Deck>,
    world: &'static World,
    corr: &'static Corridor,
}

impl Ground {
    /// The ground as anything standing on the world measures it -- the land,
    /// the works, and whatever is floating on it right now. This is what
    /// `Sim.height_at` answers.
    pub fn now() -> Ground {
        Ground {
            decks: DECKS.lock().unwrap().clone(),
            ..Ground::land()
        }
    }

    /// The same without the moving platforms.
    ///
    /// The quadtree measures the *land*: a carrier under way is not a reason to
    /// subdivide the sea under her, and a node whose error moved with a ship
    /// would be re-measured every time she sailed across it.
    pub fn land() -> Ground {
        Ground {
            globe: is_globe(),
            chart: sphere::chart(),
            decks: Vec::new(),
            world: world(),
            corr: corridor(),
        }
    }

    #[inline]
    pub fn at(&self, x: f32, z: f32) -> f32 {
        let h = if self.globe {
            sphere::ground_world_y(&self.chart, x, z, G_ALL)
        } else {
            ground_at(self.world, self.corr, x, z, G_ALL)
        };
        if self.decks.is_empty() {
            return h;
        }
        match deck_height(&self.decks, x, z) {
            // A deck is registered in the flat frame. On the planet the field
            // already carries the curve, so the deck has to be dropped onto it
            // here -- the same correction `Sim._deck_top` makes.
            Some(d) if self.globe => h.max(d - self.drop(x, z)),
            Some(d) => h.max(d),
            None => h,
        }
    }

    /// The same in the frame the game above measures heights in.
    ///
    /// `at` answers in the frame the *terrain mesh* is built in, and the two
    /// worlds differ there: the planetary field already carries the curve, so a
    /// planetary height is a height on a round world; the flat field is a plane
    /// and the ground shader bends it, so a flat height has the drop taken off
    /// afterwards. `Sim.height_at` is this one, and anything comparing itself
    /// against what the game says the ground is wants it.
    #[inline]
    pub fn world_y(&self, x: f32, z: f32) -> f32 {
        let h = self.at(x, z);
        if self.globe {
            h
        } else {
            h - self.drop(x, z)
        }
    }

    /// How far the planet's surface has fallen away by here. Mirrors
    /// `Sim.planet_drop`, including which world gets which form: exact on the
    /// planet, where this is asked at any range, and the parabola that is its
    /// first term on the flat world, which is what the flat world was written
    /// against and holds to thirty metres over the theatre.
    #[inline]
    pub fn drop(&self, x: f32, z: f32) -> f32 {
        let r = self.chart.radius;
        let s2 = x * x + z * z;
        if self.globe {
            r * (1.0 - (s2.sqrt() / r).cos())
        } else {
            s2 / (2.0 * r)
        }
    }

    /// Sea level here, in the same frame `world_y` answers in. Mirrors
    /// `Sim.sea_at`.
    #[inline]
    pub fn sea(&self, x: f32, z: f32) -> f32 {
        crate::field::WATER_LEVEL - self.drop(x, z)
    }

    /// `world_y` worked out in the width the game above works it out in.
    ///
    /// `Sim.height_at` hands back a GDScript float, which is a double: the
    /// field comes off this side as a single, the deck is maxed in against it
    /// and the drop is taken off in double. Anything *standing* on the ground
    /// wants this rather than `world_y` -- it is the number the script would
    /// have arrived at, so a wheel answered here rests where it rested when it
    /// asked for itself.
    #[inline]
    pub fn height(&self, x: f32, z: f32) -> f64 {
        let h = if self.globe {
            sphere::ground_world_y(&self.chart, x, z, G_ALL) as f64
        } else {
            ground_at(self.world, self.corr, x, z, G_ALL) as f64
        };
        let h = match deck_height(&self.decks, x, z) {
            Some(d) if self.globe => h.max(d as f64 - self.fall(x, z)),
            Some(d) => h.max(d as f64),
            None => h,
        };
        if self.globe {
            h
        } else {
            h - self.fall(x, z)
        }
    }

    /// `drop` in double, which is the width `Sim.planet_drop` works in.
    #[inline]
    fn fall(&self, x: f32, z: f32) -> f64 {
        let r = self.chart.radius as f64;
        let (x, z) = (x as f64, z as f64);
        let s2 = x * x + z * z;
        if self.globe {
            r * (1.0 - (s2.sqrt() / r).cos())
        } else {
            s2 / (2.0 * r)
        }
    }

    /// How well a wheel grips here. Mirrors `Sim.surface_grip`: a flight deck
    /// and an aerodrome's pavement hold, and everything else is a field.
    ///
    /// The script asks the runway of every aerodrome and then the taxiway loop
    /// of every aerodrome; one pass over them answers the same, because any
    /// hit at all is the same answer.
    pub fn grip(&self, x: f32, z: f32) -> f32 {
        if deck_height(&self.decks, x, z).is_some() {
            return 1.0;
        }
        for f in &self.world.fields {
            let dx = x - f.x;
            let dz = z - f.z;
            let c = (-f.yaw).cos();
            let s = (-f.yaw).sin();
            let lx = (dx * c - dz * s).abs();
            let lz = (dx * s + dz * c).abs();
            if lx <= RUNWAY_HALF_W && lz <= RUNWAY_LEN * 0.5 {
                return 1.0;                      // the runway
            }
            if lx >= 60.0 && lx <= 92.0 && lz <= RUNWAY_LEN * 0.5 {
                return 1.0;                      // the taxiways either side
            }
            if lz <= 1560.0 && lx <= 95.0 {
                return 1.0;                      // the apron between them
            }
        }
        0.45
    }
}

/// How rough the ground is over a disc: the mean of `1 - normal.y` over a
/// seven by seven grid of stations inside the circle.
///
/// This is what a settlement is sited by -- people build on the valley floor,
/// not up the side of a mountain -- and it mirrors `Sim.site_roughness` and
/// `Sim.normal_at` exactly, including which parts are worked out in single and
/// which in double. It has to: the answer chooses *where a town goes*, and a
/// different rounding puts it somewhere else.
pub fn roughness(g: &Ground, c: [f32; 2], r: f64) -> f64 {
    const E: f32 = 3.0;
    // The station spacing in double and the position in single, because that is
    // what the script did: a radius is a `float` and a `Vector2` holds singles,
    // so the product is worked out in double and narrowed once. Worked out in
    // single throughout, `1100 * 0.30` comes to 330.00003 rather than 330, the
    // stations land three hundredths of a millimetre off, and a candidate that
    // wins by less than that wins somewhere else. This picks where a town goes.
    let step = (r * 0.30) as f32;
    let mut total = 0.0f64;
    let mut n = 0u32;
    for i in 0..7 {
        for j in 0..7 {
            let qx = c[0] + (i as f32 - 3.0) * step;
            let qz = c[1] + (j as f32 - 3.0) * step;
            let (dx, dz) = (qx - c[0], qz - c[1]);
            if (dx * dx + dz * dz).sqrt() as f64 > r {
                continue;
            }
            // `normal_at`: the field's gradient over six metres, normalised as
            // a single-precision vector because that is what a `Vector3` is.
            let hx = g.world_y(qx - E, qz) - g.world_y(qx + E, qz);
            let hz = g.world_y(qx, qz - E) - g.world_y(qx, qz + E);
            let len = (hx * hx + (2.0 * E) * (2.0 * E) + hz * hz).sqrt();
            let up = if len > 0.0 { (2.0 * E) / len } else { 1.0 };
            total += 1.0 - up as f64;
            n += 1;
        }
    }
    total / n.max(1) as f64
}

/// Which ground is the ground the aerodrome stands on.
///
/// A town across a strait is a town the trunk network has to swim to, so before
/// anything is sited the world is asked which of it is reachable by land. The
/// grid is thresholded against the sea *under each point* -- which is not one
/// height on a round world -- and then flood filled from the middle.
///
/// One call, because it was a quarter of a million cells thresholded in script
/// and then a flood fill over the same quarter million that built a fresh array
/// of the four neighbour offsets for every cell it visited. Measured, 334 ms of
/// a four second cold start, and every bit of it arithmetic.
pub fn landmass(half: f32, n: usize) -> Vec<u8> {
    // The land, not what is floating on it: this is asked once while the world
    // is being laid out, before anything has been put to sea.
    let g = Ground::land();
    let n = n.max(1);
    let cell = half * 2.0 / n as f32;
    let mut wet = vec![0u8; n * n];
    wet.par_chunks_mut(n).enumerate().for_each(|(j, row)| {
        let z = -half + j as f32 * cell;
        for (i, v) in row.iter_mut().enumerate() {
            let x = -half + i as f32 * cell;
            *v = (g.world_y(x, z) > g.sea(x, z)) as u8;
        }
    });
    let mut mask = vec![0u8; n * n];
    let mid = n / 2;
    let start = mid * n + mid;
    if wet[start] == 0 {
        // The airfield is not on land, which should not happen. An empty mask
        // means "no answer", and everything that asks takes that as "anywhere",
        // rather than refusing every site in the world for want of one.
        return mask;
    }
    mask[start] = 1;
    let mut queue: Vec<u32> = Vec::with_capacity(n * n / 4);
    queue.push(start as u32);
    let mut head = 0usize;
    while head < queue.len() {
        let c = queue[head] as usize;
        head += 1;
        let (ci, cj) = (c % n, c / n);
        for (di, dj) in [(1i32, 0i32), (-1, 0), (0, 1), (0, -1)] {
            let ni = ci as i32 + di;
            let nj = cj as i32 + dj;
            if ni < 0 || nj < 0 || ni >= n as i32 || nj >= n as i32 {
                continue;
            }
            let k = nj as usize * n + ni as usize;
            if mask[k] == 1 || wet[k] == 0 {
                continue;
            }
            mask[k] = 1;
            queue.push(k as u32);
        }
    }
    mask
}

/// Is there ground in the way between two points?
///
/// Marched along the line at 180 m a step, up to forty-eight of them, against
/// the ground as the game measures it. Mirrors `Sim.line_of_sight` exactly --
/// which parts are single and which double included, because the answer decides
/// whether a radar paints a contact and whether a missile will take the shot.
///
/// `skip` is how much of the near end to ignore: a launcher does not mask its
/// own missile.
pub fn line_of_sight(g: &Ground, from: [f32; 3], to: [f32; 3], skip: f64) -> bool {
    let d = [to[0] - from[0], to[1] - from[1], to[2] - from[2]];
    let span = (d[0] * d[0] + d[1] * d[1] + d[2] * d[2]).sqrt() as f64;
    if span < 1.0 {
        return true;
    }
    let t0 = (skip / span).clamp(0.0, 0.9);
    let steps = ((span / 180.0) as i32).clamp(6, 48);
    for i in 1..steps {
        let f = i as f64 / steps as f64;
        if f < t0 {
            continue;
        }
        let ff = f as f32;
        let qx = from[0] + (to[0] - from[0]) * ff;
        let qy = from[1] + (to[1] - from[1]) * ff;
        let qz = from[2] + (to[2] - from[2]) * ff;
        let h = g.world_y(qx, qz) as f64;
        // Ground under the sea masks nothing. Everything afloat sits at the
        // water line, so a sight line between two ships runs *below* it -- and
        // the seabed is terrain, so a shoal a few metres proud of the ray
        // blocked two ships looking at each other across open water.
        if h <= crate::field::WATER_LEVEL as f64 {
            continue;
        }
        if (qy as f64) < h - 2.0 {
            return false;
        }
    }
    true
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
    carve(w, c, base(x, z), x, z, flags)
}

/// The ground before anything was built on it, whichever world this is.
///
/// This is the one place that decides, and it has to be one place. The router
/// costs its edges against it, the survey draws its profile against it and the
/// settlements are sited on it -- so a planet whose roads were laid out against
/// the *flat* field is a planet with a trunk network surveyed for terrain that
/// is not there: cuttings through nothing, embankments across hills, and a
/// coast road under water.
static GLOBE: std::sync::atomic::AtomicBool =
    std::sync::atomic::AtomicBool::new(false);

/// Whether the world is the planet or the old flat one.
pub fn is_globe() -> bool {
    GLOBE.load(std::sync::atomic::Ordering::Relaxed)
}

pub fn set_globe(on: bool) {
    GLOBE.store(on, std::sync::atomic::Ordering::Relaxed);
}

#[inline]
pub fn base(x: f32, z: f32) -> f32 {
    if GLOBE.load(std::sync::atomic::Ordering::Relaxed) {
        let c = crate::sphere::chart();
        return crate::field::WATER_LEVEL
            + crate::sphere::generated(crate::sphere::dir_from_chart(&c, x, z));
    }
    natural(x, z)
}

/// The carving, over whatever ground is underneath it.
///
/// Split out from `ground_at` so the planet can have it. The town platforms,
/// the aerodromes and the road earthworks are not part of the *terrain*: they
/// are what is done to terrain once people are living on it, and they apply to
/// a planetary height field exactly as they applied to a flat one. Only the
/// base underneath them changed.
pub fn carve(w: &World, c: &Corridor, base: f32, x: f32, z: f32, flags: u32)
        -> f32 {
    let (h, pad_w) = carve_built(w, base, x, z, flags);
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
        return road_over(c, x, z, h, pad_w);
    }
    h
}

/// The carving and the made surface it laid, together.
///
/// `carve` works the road surface out to apply the earthworks and then throws
/// it away. The ribbon that *draws* the carriageway wants both -- the finished
/// ground to lie on and the design surface to ride when the ground was raised
/// to meet it -- and asking twice walks the corridor grid twice. Measured, that
/// second walk was most of the 105 ms drawing every road on the map cost.
pub fn carve_road(w: &World, c: &Corridor, base: f32, x: f32, z: f32, flags: u32)
        -> (f32, (f32, f32, f32)) {
    let (h, pad_w) = carve_built(w, base, x, z, flags);
    let rs = road_surface(c, x, z);
    let h = if flags & G_ROADS != 0 {
        road_over_with(rs, h, pad_w)
    } else {
        h
    };
    (h, rs)
}

/// What has been built here, before any road: the town platforms and the
/// aerodromes, and how much town platform applies -- which the road needs,
/// because a road through a town runs on the made ground rather than in a
/// cutting of its own.
#[inline]
fn carve_built(w: &World, base: f32, x: f32, z: f32, flags: u32) -> (f32, f32) {
    let mut h = base;
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
    (h, pad_w)
}

/// The earthworks: what the corridor does to the ground it passes over.
#[inline]
fn road_over(c: &Corridor, x: f32, z: f32, h: f32, pad_w: f32) -> f32 {
    road_over_with(road_surface(c, x, z), h, pad_w)
}

/// The same with the made surface already in hand.
fn road_over_with(rs: (f32, f32, f32), h: f32, pad_w: f32) -> f32 {
    let (ry, rw, _) = rs;
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
    let mut h = base(x, z);
    for p in &w.pads {
        let dx = x - p.x;
        let dz = z - p.z;
        let d = (dx * dx + dz * dz).sqrt();
        if d < p.r * 1.60 {
            let t = 1.0 - smoothstep(p.r * 1.06, p.r * 1.60, d);
            h = lerp(h, p.y, t);
        }
    }
    // The aerodromes too, in the same order `carve` applies them.
    //
    // `carve` says the road is laid last "because the road was surveyed against
    // the ground with the aerodrome already in it -- that is what lets a road
    // run onto an airfield's apron instead of ending at a cliff beside it".
    // That was the intent and this is where it has to happen; without it the
    // surveyor read the raw ground *under* the pavement. It did not matter
    // while the ground under an aerodrome was much the same height as the
    // aerodrome. Once rivers were cut into the planet one ran under a strip,
    // the survey followed the river bed, and the road carve then dug the
    // apron out from under the runway to meet it -- a hundred and thirty
    // metres down, on a field the flattening had correctly levelled.
    for f in &w.fields {
        let ff = field_factor(f, x, z);
        if ff > 0.0 {
            h = lerp(h, f.elev, ff);
        }
    }
    h
}
