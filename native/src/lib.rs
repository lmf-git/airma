//! The terrain field and the road router, in native code.
//!
//! Both are the same shape of work: a small piece of arithmetic asked for a
//! very large number of points. The height field is four to six noise lookups,
//! and the whole game is built on it -- every terrain chunk, every road cost,
//! every scatter placement, every missile flying down a valley. The router then
//! asks for it a few hundred thousand times per leg.
//!
//! This is the single source of truth for the natural field. GDScript layers
//! the things that depend on world state -- town pads, road corridors, the
//! aerodrome -- on top of what comes back from here.

use fastnoise_lite::{FastNoiseLite, FractalType, NoiseType};
use godot::prelude::*;
use rayon::prelude::*;
use std::sync::OnceLock;

struct FlightNative;

#[gdextension]
unsafe impl ExtensionLibrary for FlightNative {}

const COAST_X: f32 = 15000.0;
const WATER_LEVEL: f32 = -35.0;
const NAV_DEPTH: f32 = 16.0;
const NAV_FLAT: f32 = 95000.0;
const NAV_RISE: f32 = 150000.0;

fn mk(seed: i32, freq: f32, oct: i32, lac: f32, gain: f32) -> FastNoiseLite {
    let mut n = FastNoiseLite::with_seed(seed);
    // Godot's TYPE_SIMPLEX is this one, and its default fractal is FBm.
    n.set_noise_type(Some(NoiseType::OpenSimplex2));
    n.set_fractal_type(Some(FractalType::FBm));
    n.set_frequency(Some(freq));
    n.set_fractal_octaves(Some(oct));
    n.set_fractal_lacunarity(Some(lac));
    n.set_fractal_gain(Some(gain));
    n
}

struct Field {
    lo: FastNoiseLite,
    hi: FastNoiseLite,
    det: FastNoiseLite,
    river: FastNoiseLite,
    river2: FastNoiseLite,
    cont: FastNoiseLite,
}

static FIELD: OnceLock<Field> = OnceLock::new();

fn field() -> &'static Field {
    FIELD.get_or_init(|| Field {
        lo: mk(1337, 0.000055, 4, 2.1, 0.5),
        hi: mk(99, 0.00042, 3, 2.0, 0.5),
        det: mk(7, 0.0035, 2, 2.0, 0.5),
        river: mk(5150, 0.0000135, 2, 2.0, 0.4),
        river2: mk(8807, 0.0000181, 2, 2.0, 0.45),
        cont: mk(20260827, 0.0000047, 3, 2.3, 0.45),
    })
}

#[inline]
fn smoothstep(a: f32, b: f32, x: f32) -> f32 {
    if b <= a {
        return if x < a { 0.0 } else { 1.0 };
    }
    let t = ((x - a) / (b - a)).clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

#[inline]
fn lerp(a: f32, b: f32, t: f32) -> f32 {
    a + (b - a) * t
}

/// Carve one channel. `rv` is the channel field at the point, zero on the
/// centreline; `home` is 1 near the airfield and 0 out where the continents
/// take over.
fn river(h: f32, x: f32, rv: f32, home: f32) -> f32 {
    let mut out = h;
    let chan = 1.0 - smoothstep(0.0, 0.045, rv);
    if chan > 0.0 && h > WATER_LEVEL - 120.0 {
        let low = (1.0 - (h - WATER_LEVEL) / 1100.0).clamp(0.0, 1.0);
        out -= lerp(14.0, 210.0, low * low) * chan * chan;
    }
    if home <= 0.0 {
        return out;
    }
    let inland = (COAST_X - x).max(0.0);
    let mut bed = WATER_LEVEL - NAV_DEPTH;
    if inland > NAV_FLAT {
        bed += ((inland - NAV_FLAT) / NAV_RISE).powf(1.4) * 1300.0;
    }
    // flat bottom along the centreline, valley sides out to the rim
    let prof = 1.0 - smoothstep(0.022, 0.085, rv);
    let w = prof * prof * home;
    if w > 0.0 && bed < out {
        out = lerp(out, bed, w);
    }
    out
}

/// The land before anything is built on it.
pub fn natural(x: f32, z: f32) -> f32 {
    let f = field();
    let mut m = (f.lo.get_noise_2d(x, z) + 1.0) * 0.5;
    m = m.powf(2.3);
    let mut h = m * 2100.0;
    h += f.hi.get_noise_2d(x, z) * 150.0 * m;
    h += f.det.get_noise_2d(x, z) * 6.0 * (m * 4.0).clamp(0.15, 1.0);
    h -= 90.0;
    // the valley the airfield sits in, held to the airfield's own latitude
    let along = 1.0 - smoothstep(5000.0, 24000.0, z.abs());
    if along > 0.0 {
        let axis = ((x.abs() - 1000.0) / 3400.0).clamp(0.0, 1.0);
        let cap = 55.0 + axis * axis * 2500.0;
        if h > cap {
            h = lerp(h, cap + (h - cap) * 0.12, along);
        }
    }
    // canyons: where a channel field crosses high ground it cuts hard
    let cy = f.river.get_noise_2d(z * 1.9 + 31000.0, x * 1.9 - 17000.0).abs();
    let gorge = 1.0 - smoothstep(0.0, 0.020, cy);
    if gorge > 0.0 && h > 420.0 {
        let bite = ((h - 420.0) / 700.0).clamp(0.0, 1.0);
        h -= 340.0 * gorge * gorge * bite;
    }
    let far = smoothstep(55000.0, 150000.0, (x * x + z * z).sqrt());
    let sea = smoothstep(COAST_X, COAST_X + 9000.0, x) * (1.0 - far);
    if sea > 0.0 {
        h = lerp(h, -240.0, sea);
    }
    if far > 0.0 {
        let cont = f.cont.get_noise_2d(x, z);
        let landness = lerp(1.0, smoothstep(-0.10, 0.16, cont), far);
        if landness < 1.0 {
            let floor_y = lerp(-1500.0, -160.0, smoothstep(0.0, 0.45, landness));
            h = lerp(floor_y, h, smoothstep(0.0, 0.62, landness));
        }
    }
    let home = 1.0 - smoothstep(200000.0, 450000.0, (x * x + z * z).sqrt());
    h = river(h, x, f.river.get_noise_2d(x * 0.28, z).abs(), home);
    h = river(
        h,
        x,
        f.river2.get_noise_2d(x * 0.34 + z * 0.10, z + x * 0.06).abs(),
        home,
    );
    h
}


// ------------------------------------------------------------- the corridor
//
// The made road, and the ground it was cut from. Every height query in the
// game asks whether it is on a road, so this has to answer without walking the
// network: the legs are stamped into a coarse grid once and the query looks at
// one cell.

const ROAD_HALF: f32 = 7.5;
const ROAD_SHOULDER: f32 = 24.0;
const ROAD_FILL_MAX: f32 = 22.0;
const ROAD_CUT_MAX: f32 = 34.0;
const CORR_CELL: f32 = 64.0;

#[derive(Clone, Copy)]
struct Leg {
    ax: f32,
    az: f32,
    bx: f32,
    bz: f32,
    ya: f32,
    yb: f32,
    na: f32,
    nb: f32,
}

#[derive(Default)]
struct Corridor {
    legs: Vec<Leg>,
    grid: std::collections::HashMap<i64, Vec<u32>>,
}

/// Same reasoning as `WORLD_P`.
static CORR_P: std::sync::atomic::AtomicPtr<Corridor> =
    std::sync::atomic::AtomicPtr::new(std::ptr::null_mut());

fn corridor() -> &'static Corridor {
    static EMPTY: std::sync::OnceLock<Corridor> = std::sync::OnceLock::new();
    let p = CORR_P.load(std::sync::atomic::Ordering::Acquire);
    if p.is_null() {
        return EMPTY.get_or_init(Corridor::default);
    }
    unsafe { &*p }
}

/// The made surface at a point: its height, how much of it applies here, and
/// the ground it was cut from. Zero weight means the land is left as it was.
fn road_surface(c: &Corridor, x: f32, z: f32) -> (f32, f32, f32) {
    if c.legs.is_empty() {
        return (0.0, 0.0, 0.0);
    }
    let reach = ROAD_HALF + ROAD_SHOULDER;
    let k = key((x / CORR_CELL).floor() as i32, (z / CORR_CELL).floor() as i32);
    let bucket = match c.grid.get(&k) {
        Some(b) => b,
        None => return (0.0, 0.0, 0.0),
    };
    let mut best = 1e9f32;
    let mut ysum = 0.0;
    let mut gsum = 0.0;
    let mut wsum = 0.0;
    for idx in bucket {
        let l = &c.legs[*idx as usize];
        let abx = l.bx - l.ax;
        let abz = l.bz - l.az;
        let len2 = (abx * abx + abz * abz).max(0.001);
        let t = (((x - l.ax) * abx + (z - l.az) * abz) / len2).clamp(0.0, 1.0);
        let dx = x - (l.ax + abx * t);
        let dz = z - (l.az + abz * t);
        let d = (dx * dx + dz * dz).sqrt();
        if d < best {
            best = d;
        }
        if d < reach {
            // Blended, not nearest wins: where two routes run a few metres
            // apart the carriageway would otherwise snap to one of them and
            // leave a step down the middle of the road.
            let w = 1.0 / (d * d + 1.5);
            ysum += lerp(l.ya, l.yb, t) * w;
            gsum += lerp(l.na, l.nb, t) * w;
            wsum += w;
        }
    }
    if best > reach || wsum <= 0.0 {
        return (0.0, 0.0, 0.0);
    }
    (ysum / wsum, 1.0 - smoothstep(ROAD_HALF, reach, best), gsum / wsum)
}

/// The ground as the world has left it: the field, the levelled town
/// platforms, and the made roads. The aerodromes and the carrier decks are few
/// enough to stay on the other side of the boundary.
fn ground_at(w: &World, c: &Corridor, x: f32, z: f32, roads: bool) -> f32 {
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
    if !roads {
        return h;
    }
    let (ry, rw, rg) = road_surface(c, x, z);
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
        let target = ry.clamp(rg - ROAD_CUT_MAX, rg + ROAD_FILL_MAX);
        h = lerp(h, target, ww);
    }
    h
}

#[derive(GodotClass)]
#[class(base=RefCounted, init)]
struct Terra {
    base: Base<RefCounted>,
}

#[godot_api]
impl Terra {
    /// One point. Kept for the odd caller that needs a single sample; anything
    /// asking for a grid should ask for the grid.
    #[func]
    fn natural_height(&self, x: f64, z: f64) -> f64 {
        natural(x as f32, z as f32) as f64
    }

    /// A square grid of samples, `n` by `n`, starting at (x0, z0) and stepping
    /// by `cell`, row-major in z. Filled across every core.
    ///
    /// This is the call that matters: a terrain chunk is one of these, and
    /// asking for it as a block rather than as 289 separate calls removes the
    /// per-call overhead as well as putting the work on all the cores.
    #[func]
    fn heights(&self, x0: f64, z0: f64, cell: f64, n: i64) -> PackedFloat32Array {
        let n = n.max(0) as usize;
        let (x0, z0, cell) = (x0 as f32, z0 as f32, cell as f32);
        let mut out = vec![0f32; n * n];
        out.par_chunks_mut(n.max(1))
            .enumerate()
            .for_each(|(j, row)| {
                let z = z0 + j as f32 * cell;
                for (i, v) in row.iter_mut().enumerate() {
                    *v = natural(x0 + i as f32 * cell, z);
                }
            });
        PackedFloat32Array::from(out.as_slice())
    }

    /// Scattered samples rather than a grid: the points come in as x, z pairs
    /// and the heights come back in the same order.
    #[func]
    fn heights_at(&self, pts: PackedVector2Array) -> PackedFloat32Array {
        let src: Vec<Vector2> = pts.as_slice().to_vec();
        let out: Vec<f32> = src
            .par_iter()
            .map(|p| natural(p.x, p.y))
            .collect();
        PackedFloat32Array::from(out.as_slice())
    }


    /// The corridor: every leg as (ax, az, bx, bz, made a, made b, natural a,
    /// natural b). Stamped into a grid here, once, rather than walked per query.
    #[func]
    fn set_corridor(&self, data: PackedFloat32Array) {
        let mut c = Corridor::default();
        for q in data.as_slice().chunks_exact(8) {
            c.legs.push(Leg {
                ax: q[0], az: q[1], bx: q[2], bz: q[3],
                ya: q[4], yb: q[5], na: q[6], nb: q[7],
            });
        }
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
        CORR_P.store(Box::into_raw(Box::new(c)),
            std::sync::atomic::Ordering::Release);
    }

    /// One point of finished ground. `roads` is false while the network is
    /// being surveyed, which is the only thing that makes the corridor invisible
    /// to a query.
    #[func]
    fn ground(&self, x: f64, z: f64, roads: bool) -> f64 {
        ground_at(world(), corridor(), x as f32, z as f32, roads) as f64
    }

    /// A square grid of finished ground, the call a terrain chunk makes.
    #[func]
    fn grounds(&self, x0: f64, z0: f64, cell: f64, n: i64) -> PackedFloat32Array {
        let w = world();
        let c = corridor();
        let n = n.max(0) as usize;
        let (x0, z0, cell) = (x0 as f32, z0 as f32, cell as f32);
        let mut out = vec![0f32; n * n];
        out.par_chunks_mut(n.max(1)).enumerate().for_each(|(j, row)| {
            let z = z0 + j as f32 * cell;
            for (i, v) in row.iter_mut().enumerate() {
                *v = ground_at(w, c, x0 + i as f32 * cell, z, true);
            }
        });
        PackedFloat32Array::from(out.as_slice())
    }

    /// Scattered points of finished ground, in the order they came in.
    #[func]
    fn grounds_at(&self, pts: PackedVector2Array, roads: bool) -> PackedFloat32Array {
        let w = world();
        let c = corridor();
        let src: Vec<Vector2> = pts.as_slice().to_vec();
        let out: Vec<f32> = src.par_iter()
            .map(|p| ground_at(w, c, p.x, p.y, roads))
            .collect();
        PackedFloat32Array::from(out.as_slice())
    }

    /// The upward component of the ground normal at each point -- how flat it
    /// is there. Four ground samples apiece, which is why it is worth asking
    /// for a whole scatter's worth at once rather than one tree at a time.
    #[func]
    fn slopes_at(&self, pts: PackedVector2Array) -> PackedFloat32Array {
        let w = world();
        let c = corridor();
        const E: f32 = 3.0;
        let src: Vec<Vector2> = pts.as_slice().to_vec();
        let out: Vec<f32> = src
            .par_iter()
            .map(|p| {
                let hl = ground_at(w, c, p.x - E, p.y, true);
                let hr = ground_at(w, c, p.x + E, p.y, true);
                let hd = ground_at(w, c, p.x, p.y - E, true);
                let hu = ground_at(w, c, p.x, p.y + E, true);
                let len = ((hl - hr) * (hl - hr) + (2.0 * E) * (2.0 * E)
                    + (hd - hu) * (hd - hu)).sqrt();
                if len > 0.0 { 2.0 * E / len } else { 1.0 }
            })
            .collect();
        PackedFloat32Array::from(out.as_slice())
    }

    /// The ground as the mesh actually draws it: the four corners of the cell
    /// the point falls in, interpolated across whichever of the two triangles
    /// the chunk splits that cell into. A tree stood on the analytic height
    /// hangs above the triangles as soon as the cells get coarse.
    #[func]
    fn surfaces_at(&self, pts: PackedVector2Array, cell: f64) -> PackedFloat32Array {
        let w = world();
        let c = corridor();
        let cell = cell as f32;
        let src: Vec<Vector2> = pts.as_slice().to_vec();
        let out: Vec<f32> = src
            .par_iter()
            .map(|p| {
                let x0 = (p.x / cell).floor() * cell;
                let z0 = (p.y / cell).floor() * cell;
                let tx = (p.x - x0) / cell;
                let tz = (p.y - z0) / cell;
                let h00 = ground_at(w, c, x0, z0, true);
                let h10 = ground_at(w, c, x0 + cell, z0, true);
                let h11 = ground_at(w, c, x0 + cell, z0 + cell, true);
                let h01 = ground_at(w, c, x0, z0 + cell, true);
                // the chunk splits each cell as (a,b,c) then (a,c,d), so the
                // diagonal runs from (0,0) to (1,1)
                if tz <= tx {
                    h00 + (h10 - h00) * tx + (h11 - h10) * tz
                } else {
                    h00 + (h11 - h01) * tx + (h01 - h00) * tz
                }
            })
            .collect();
        PackedFloat32Array::from(out.as_slice())
    }

    /// The made surface at a point, as (height, how much of it applies, the
    /// ground it was cut from) -- the same three numbers GDScript's own
    /// `road_surface` returns, so the road ribbons and the harnesses can ask
    /// the side that actually holds the corridor.
    #[func]
    fn road_surface_at(&self, x: f64, z: f64) -> Vector3 {
        let (y, w, g) = road_surface(corridor(), x as f32, z as f32);
        Vector3::new(y, w, g)
    }

    /// The distance-to-road field: for every texel of a square grid, how far
    /// the nearest piece of road is.
    ///
    /// `segs` is a flat run of ax, az, bx, bz. Brute force against every
    /// segment, which is what it has to be -- but it is a bounding-box reject
    /// and a projection per segment, run across all the cores. In GDScript this
    /// was a hundred and thirty million distance tests against a network that
    /// now spans the map, and it took sixty-seven seconds: longer than
    /// everything else in world generation put together.
    #[func]
    fn road_field(&self, segs: PackedFloat32Array, res: i64, half: f64)
            -> PackedFloat32Array {
        let src = segs.as_slice();
        let n = res.max(1) as usize;
        let half = half as f32;
        // ax, az, dx, dz, 1/len2, minx, maxx, minz, maxz
        let mut seg: Vec<[f32; 9]> = Vec::with_capacity(src.len() / 4);
        for q in src.chunks_exact(4) {
            let (ax, az, bx, bz) = (q[0], q[1], q[2], q[3]);
            let dx = bx - ax;
            let dz = bz - az;
            seg.push([
                ax, az, dx, dz,
                1.0 / (dx * dx + dz * dz).max(1e-9),
                ax.min(bx), ax.max(bx), az.min(bz), az.max(bz),
            ]);
        }
        let step = half * 2.0 / (n as f32 - 1.0).max(1.0);
        let mut out = vec![0f32; n * n];
        out.par_chunks_mut(n).enumerate().for_each(|(j, row)| {
            let z = -half + j as f32 * step;
            for (i, v) in row.iter_mut().enumerate() {
                let x = -half + i as f32 * step;
                let mut best2 = f32::INFINITY;
                for sg in &seg {
                    // the box first: a segment whose box is already further
                    // away than the best cannot win, and most of them are
                    let ox = (sg[5] - x).max(x - sg[6]).max(0.0);
                    let oz = (sg[7] - z).max(z - sg[8]).max(0.0);
                    if ox * ox + oz * oz >= best2 {
                        continue;
                    }
                    let px = x - sg[0];
                    let pz = z - sg[1];
                    let t = ((px * sg[2] + pz * sg[3]) * sg[4]).clamp(0.0, 1.0);
                    let qx = px - sg[2] * t;
                    let qz = pz - sg[3] * t;
                    let d2 = qx * qx + qz * qz;
                    if d2 < best2 {
                        best2 = d2;
                    }
                }
                *v = best2.sqrt();
            }
        });
        PackedFloat32Array::from(out.as_slice())
    }

    /// The relaxation the road survey runs: weld parallel stretches together,
    /// tie the heights where roads meet, hold the ruling gradient, and clamp
    /// what is left back to the ground -- twenty-odd times over.
    ///
    /// All of it in one call. It is eighty thousand stations against a spatial
    /// index, twice a pass, and in GDScript that was the longest thing left in
    /// world generation. The whole loop runs here so nothing is marshalled
    /// back and forth between passes.
    ///
    /// `pts` and `ys` are every line's stations end to end, `nat` the untouched
    /// ground under them, and `starts` where each line begins (plus a final
    /// entry holding the total). Returns the moved stations and the settled
    /// profile.
    #[func]
    fn survey_relax(&self, pts: PackedVector2Array, ys: PackedFloat32Array,
            nat: PackedFloat32Array, starts: PackedInt32Array, passes: i64,
            cut: f64, fill: f64) -> Array<Variant> {
        const WELD: f32 = 34.0;
        const TIE: f32 = 70.0;
        const TIE_CELL: f32 = 96.0;
        const ROAD_GRADE_L: f32 = 0.062;
        let mut p: Vec<Vector2> = pts.as_slice().to_vec();
        let mut y: Vec<f32> = ys.as_slice().to_vec();
        let g: Vec<f32> = nat.as_slice().to_vec();
        let st: Vec<i32> = starts.as_slice().to_vec();
        let lines = st.len().saturating_sub(1);
        let (cut, fill) = (cut as f32, fill as f32);
        // which line a station belongs to, so a road is not a junction with
        // the stretch of itself it stands on
        let mut owner = vec![0u32; p.len()];
        for li in 0..lines {
            for k in st[li] as usize..st[li + 1] as usize {
                owner[k] = li as u32;
            }
        }
        for _ in 0..passes.max(0) {
            // --- the index, over every leg as the pass found it -----------
            // leg k joins station k and k+1, and never spans two lines
            let mut grid: Map<i64, Vec<u32>> = Map::default();
            for li in 0..lines {
                let (a0, a1) = (st[li] as usize, st[li + 1] as usize);
                for k in a0..a1.saturating_sub(1) {
                    let (u, v) = (p[k], p[k + 1]);
                    let len = (u - v).length();
                    let steps = ((len / (TIE_CELL * 0.5)) as i32).max(1);
                    for q in 0..=steps {
                        let t = q as f32 / steps as f32;
                        let w = u + (v - u) * t;
                        let ci = (w.x / TIE_CELL).floor() as i32;
                        let cj = (w.y / TIE_CELL).floor() as i32;
                        for oi in -1..=1 {
                            for oj in -1..=1 {
                                let e = grid.entry(key(ci + oi, cj + oj))
                                    .or_default();
                                if e.last() != Some(&(k as u32)) {
                                    e.push(k as u32);
                                }
                            }
                        }
                    }
                }
            }
            // legs near a point, as (height there, distance, foot)
            let near = |p: &Vec<Vector2>, y: &Vec<f32>, at: Vector2, idx: usize,
                    reach: f32| -> Vec<(f32, f32, Vector2)> {
                let mut out = Vec::new();
                let k = key((at.x / TIE_CELL).floor() as i32,
                    (at.y / TIE_CELL).floor() as i32);
                let bucket = match grid.get(&k) {
                    Some(b) => b,
                    None => return out,
                };
                for l in bucket {
                    let l = *l as usize;
                    if owner[l] == owner[idx]
                        && (l as i64 - idx as i64).abs() < 6 {
                        continue;
                    }
                    let a = p[l];
                    let ab = p[l + 1] - a;
                    let len2 = ab.length_squared().max(0.001);
                    let t = ((at - a).dot(ab) / len2).clamp(0.0, 1.0);
                    let foot = a + ab * t;
                    let d = (at - foot).length();
                    if d > reach {
                        continue;
                    }
                    out.push((lerp(y[l], y[l + 1], t), d, foot));
                }
                out
            };
            // --- weld: pull parallel stretches onto one another -----------
            let mut moved = p.clone();
            for i in 0..p.len() {
                let mut pull = Vector2::ZERO;
                let mut wsum = 0.0f32;
                for (_, d, foot) in near(&p, &y, p[i], i, WELD) {
                    let w = 1.0 - d / WELD;
                    pull += foot * w;
                    wsum += w;
                }
                if wsum > 0.0 {
                    let t = (wsum * 0.35).clamp(0.0, 0.5);
                    moved[i] = moved[i] + (pull / wsum - moved[i]) * t;
                }
            }
            // --- tie: agree about the height where they meet --------------
            let mut tied = y.clone();
            for i in 0..p.len() {
                let mut ysum = 0.0f32;
                let mut wsum = 0.0f32;
                for (hy, d, _) in near(&p, &y, p[i], i, TIE) {
                    let mut w = 1.0 - d / TIE;
                    w *= w;
                    ysum += hy * w;
                    wsum += w;
                }
                if wsum > 0.0 {
                    tied[i] = lerp(y[i], ysum / wsum, (wsum * 0.6).clamp(0.0, 0.9));
                }
            }
            // Do not let a station be pulled onto its own neighbour.
            //
            // Welding drags parallel stretches together, and where several
            // roads run close it can pull two consecutive stations of the same
            // line onto the same spot. That leaves a zero length leg, which has
            // no direction and therefore no gradient -- and the profile either
            // side of it steps instead of sloping. Measured on a network with
            // real parallel running: worst gradient sixty-four per cent, and
            // legs whose two ends were the same point.
            for li in 0..lines {
                let (a0, a1) = (st[li] as usize, st[li + 1] as usize);
                for i in a0 + 1..a1 {
                    let want = (p[i] - p[i - 1]).length() * 0.35;
                    let got = moved[i] - moved[i - 1];
                    let d = got.length();
                    if d < want && d > 1e-4 {
                        moved[i] = moved[i - 1] + got / d * want;
                    } else if d <= 1e-4 {
                        moved[i] = moved[i - 1] + (p[i] - p[i - 1]) * 0.35;
                    }
                }
            }
            p = moved;
            y = tied;
            // --- the ruling gradient, then back to the ground -------------
            for li in 0..lines {
                let (a0, a1) = (st[li] as usize, st[li + 1] as usize);
                if a1 <= a0 + 1 {
                    continue;
                }
                for i in a0 + 1..a1 {
                    y[i] = y[i].min(y[i - 1]
                        + ROAD_GRADE_L * (p[i] - p[i - 1]).length());
                }
                for i in (a0..a1 - 1).rev() {
                    y[i] = y[i].min(y[i + 1]
                        + ROAD_GRADE_L * (p[i + 1] - p[i]).length());
                }
                for i in a0 + 1..a1 {
                    y[i] = y[i].max(y[i - 1]
                        - ROAD_GRADE_L * (p[i] - p[i - 1]).length());
                }
                for i in (a0..a1 - 1).rev() {
                    y[i] = y[i].max(y[i + 1]
                        - ROAD_GRADE_L * (p[i + 1] - p[i]).length());
                }
                for i in a0..a1 {
                    y[i] = y[i].clamp(g[i] - cut, g[i] + fill);
                }
            }
        }
        let mut out: Array<Variant> = Array::new();
        out.push(&PackedVector2Array::from(p.as_slice()).to_variant());
        out.push(&PackedFloat32Array::from(y.as_slice()).to_variant());
        out
    }

    /// Nodes expanded and wall time of the last `route_many`.
    #[func]
    fn route_stats(&self) -> Vector2 {
        Vector2::new(
            LAST_NODES.load(std::sync::atomic::Ordering::Relaxed) as f32,
            LAST_MS.load(std::sync::atomic::Ordering::Relaxed) as f32,
        )
    }

    /// How many threads the pool will actually use, so the game can say so.
    #[func]
    fn threads(&self) -> i64 {
        rayon::current_num_threads() as i64
    }

    /// The levelled town platforms, as (x, z, radius, height) quadruples, and
    /// the aerodromes as (x, z, yaw) triples. Both have to be in before any
    /// road is routed: a road is surveyed against the ground as the towns have
    /// already left it.
    #[func]
    fn set_world(&self, pads: PackedFloat32Array, fields: PackedFloat32Array) {
        let mut w = World::default();
        let p = pads.as_slice();
        for c in p.chunks_exact(4) {
            w.pads.push(Pad { x: c[0], z: c[1], r: c[2], y: c[3] });
        }
        let f = fields.as_slice();
        for c in f.chunks_exact(3) {
            w.fields.push(Airfield { x: c[0], z: c[1], yaw: c[2] });
        }
        WORLD_P.store(Box::into_raw(Box::new(w)),
            std::sync::atomic::Ordering::Release);
    }

    /// Every leg at once. `ends` is a flat run of a, b, a, b... and what comes
    /// back is one polyline per pair, empty where there is no route.
    ///
    /// The whole search is in here: the cost function reads the height field
    /// directly, so a hundred thousand node expansions cross no boundary at
    /// all, and the legs themselves run on every core.
    #[func]
    fn route_many(&self, ends: PackedVector2Array) -> Array<PackedVector2Array> {
        let w = world();
        let pts = ends.as_slice();
        let jobs: Vec<((f32, f32), (f32, f32))> = pts
            .chunks_exact(2)
            .map(|c| ((c[0].x, c[0].y), (c[1].x, c[1].y)))
            .collect();
        let clock = std::time::Instant::now();
        let nodes = std::sync::atomic::AtomicUsize::new(0);
        let done: Vec<Vec<(f32, f32)>> = jobs
            .par_iter()
            .map(|(a, b)| {
                // The grid has to suit the leg: at a flat 400 m a hundred
                // kilometre link needs more cells than the node budget just to
                // reach the far end, and could never finish.
                let dx = b.0 - a.0;
                let dz = b.1 - a.1;
                let span = (dx * dx + dz * dz).sqrt();
                let cell = (span / 140.0).clamp(400.0, 2600.0);
                let t0 = std::time::Instant::now();
                let (mut r, mut n) = search_counted(w, *a, *b, cell, RT_MARGIN,
                    RT_MAX_NODES);
                if r.len() < 2 {
                    let (r2, n2) = search_counted(w, *a, *b, cell * 1.8,
                        RT_MARGIN * 2.0, RT_MAX_NODES * 2);
                    r = r2;
                    n += n2;
                }
                let _ = t0;
                nodes.fetch_add(n, std::sync::atomic::Ordering::Relaxed);
                if r.len() < 2 {
                    return Vec::new();
                }
                pull_straight(w, r)
            })
            .collect();
        LAST_NODES.store(nodes.load(std::sync::atomic::Ordering::Relaxed),
            std::sync::atomic::Ordering::Relaxed);
        LAST_MS.store(clock.elapsed().as_millis() as usize,
            std::sync::atomic::Ordering::Relaxed);
        let mut out: Array<PackedVector2Array> = Array::new();
        for line in done {
            let mut pa = PackedVector2Array::new();
            for p in line {
                pa.push(Vector2::new(p.0, p.1));
            }
            out.push(&pa);
        }
        out
    }
}

// ---------------------------------------------------------------- the router
//
// A* over a grid, one search per leg, all legs at once across the cores. The
// cost function is the surveyor's: distance, climb, the square of the grade,
// and a hard penalty past the gradient a trunk road is built to -- plus water,
// the aerodrome keep-out and the runway itself.

const ROAD_GRADE: f32 = 0.062;
const RUNWAY_LEN: f32 = 3000.0;
const RUNWAY_HALF_W: f32 = 23.0;
/// What the search believes a metre still to go will cost it.
///
/// The cheapest a metre can actually be is 0.55 -- flat, dry, clear of the
/// field -- so anything at or below that is admissible and finds the provably
/// shortest road. It also spreads out like Dijkstra the moment the ground
/// stops being flat, because the real cost of a metre through hills is several
/// times the estimate and through water is four hundred times it. At 1.45 most
/// legs still ran to the sixty-thousand node ceiling and took over a second
/// each. A road does not have to be the shortest one, so the estimate is
/// allowed well ahead of the truth: the search commits to a direction and
/// finishes in a fraction of the expansions.
// Back down close to admissible. At 5.0 the search commits to a direction and
// finishes in almost no time, but it buys that by accepting whatever ground
// lies straight ahead: the surveyed network came out with a 95th percentile
// gradient of eight per cent against a limit of six. Routing costs thirty-two
// milliseconds, so there is plenty of room to pay for a better line.
const RT_HEUR: f32 = 1.6;
const RT_MARGIN: f32 = 9000.0;
const RT_MAX_NODES: usize = 60000;

#[derive(Clone, Copy)]
struct Pad {
    x: f32,
    z: f32,
    r: f32,
    y: f32,
}

#[derive(Clone, Copy)]
struct Airfield {
    x: f32,
    z: f32,
    yaw: f32,
}

#[derive(Default)]
struct World {
    pads: Vec<Pad>,
    fields: Vec<Airfield>,
}

/// Set once while the world is built, then read from every thread for the rest
/// of the run. Behind a lock this was two atomic read-modify-writes per height
/// query on one shared cache line, and with eight workers scattering trees that
/// contention cost more than the arithmetic did -- a call that measures at a
/// quarter of a microsecond on its own took seventeen times that in the crowd.
/// The data is leaked deliberately: it lives as long as the process, so a
/// reader only has to load a pointer.
static WORLD_P: std::sync::atomic::AtomicPtr<World> =
    std::sync::atomic::AtomicPtr::new(std::ptr::null_mut());

fn world() -> &'static World {
    static EMPTY: std::sync::OnceLock<World> = std::sync::OnceLock::new();
    let p = WORLD_P.load(std::sync::atomic::Ordering::Acquire);
    if p.is_null() {
        return EMPTY.get_or_init(World::default);
    }
    // Sound: the pointee is leaked at publication and never mutated or freed.
    unsafe { &*p }
}

/// The ground the surveyor sees: the field, plus the platforms the towns have
/// already been levelled onto. The aerodrome is not blended in here -- it is
/// kept out by penalty below, which is what actually steers a road around it.
fn road_height(w: &World, x: f32, z: f32) -> f32 {
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

fn clear_of_airfield(x: f32, z: f32) -> bool {
    if x.abs() < 620.0 && z.abs() < 2600.0 {
        return false;
    }
    // and clear of the extended centreline, where the approach lights run
    !(x.abs() < 260.0 && z.abs() < 5200.0)
}

fn on_runway(w: &World, x: f32, z: f32) -> bool {
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

/// What one step of road costs, in the surveyor's terms.
fn step_cost(w: &World, ha: f32, hb: f32, run: f32, wx: f32, wz: f32) -> f32 {
    let climb = (hb - ha).abs();
    let grade = climb / run;
    let mut cost = run * 0.55 + climb * 1.6 + grade * grade * run * 260.0;
    let over = (grade - ROAD_GRADE).max(0.0);
    cost += over * over * run * 9000.0;
    // Water is crossable -- that is what a bridge is for -- but it is the last
    // resort, not a shortcut across a bay.
    if hb < WATER_LEVEL + 6.0 {
        cost += run * 260.0;
    }
    if !clear_of_airfield(wx, wz) {
        cost += run * 400.0;
    }
    if on_runway(w, wx, wz) {
        cost += run * 4000.0;
    }
    cost
}

const NEIGHBOURS: [(i32, i32, f32); 16] = [
    (1, 0, 1.0), (-1, 0, 1.0), (0, 1, 1.0), (0, -1, 1.0),
    (1, 1, 1.41421), (1, -1, 1.41421), (-1, 1, 1.41421), (-1, -1, 1.41421),
    (2, 1, 2.23607), (2, -1, 2.23607), (-2, 1, 2.23607), (-2, -1, 2.23607),
    (1, 2, 2.23607), (-1, 2, 2.23607), (1, -2, 2.23607), (-1, -2, 2.23607),
];

/// A cheap hash for integer cell keys.
///
/// The search does a handful of map operations per neighbour and expands tens
/// of thousands of nodes per leg, so this runs into the tens of millions per
/// route. The standard library hashes with SipHash, which is the right default
/// for a map that might see hostile keys and entirely wasted on a grid
/// coordinate.
#[derive(Default, Clone, Copy)]
struct FxHasher {
    h: u64,
}

impl std::hash::Hasher for FxHasher {
    #[inline]
    fn finish(&self) -> u64 {
        self.h
    }
    #[inline]
    fn write(&mut self, bytes: &[u8]) {
        for b in bytes {
            self.h = (self.h ^ *b as u64).wrapping_mul(0x0100_0000_01b3);
        }
    }
    #[inline]
    fn write_i64(&mut self, i: i64) {
        self.h = (i as u64).wrapping_mul(0x9E37_79B9_7F4A_7C15);
        self.h ^= self.h >> 29;
    }
    #[inline]
    fn write_u64(&mut self, i: u64) {
        self.h = i.wrapping_mul(0x9E37_79B9_7F4A_7C15);
        self.h ^= self.h >> 29;
    }
}

type FxBuild = std::hash::BuildHasherDefault<FxHasher>;
type Map<K, V> = std::collections::HashMap<K, V, FxBuild>;

/// Nodes expanded by the last `route_many`, so the game can report it.
static LAST_NODES: std::sync::atomic::AtomicUsize =
    std::sync::atomic::AtomicUsize::new(0);
static LAST_MS: std::sync::atomic::AtomicUsize =
    std::sync::atomic::AtomicUsize::new(0);

#[inline]
fn key(i: i32, j: i32) -> i64 {
    ((i as i64) << 32) ^ (j as i64 & 0xffff_ffff)
}

/// Cheapest-first, ordered on the estimate. f32 has no total order, so the bits
/// carry the comparison; every value here is finite and non-negative.
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

fn search(w: &World, a: (f32, f32), b: (f32, f32), cell: f32, margin: f32,
        budget: usize) -> Vec<(f32, f32)> {
    search_counted(w, a, b, cell, margin, budget).0
}

fn search_counted(w: &World, a: (f32, f32), b: (f32, f32), cell: f32,
        margin: f32, budget: usize) -> (Vec<(f32, f32)>, usize) {
    use std::collections::BinaryHeap;
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
            let ng = gc + step_cost(w, ha, hb, run, ni as f32 * cell, nj as f32 * cell);
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
    out.push(b);
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
fn pull_straight(w: &World, pts: Vec<(f32, f32)>) -> Vec<(f32, f32)> {
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
