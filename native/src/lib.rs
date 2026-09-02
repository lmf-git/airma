//! The height field, the road survey and everything raster, in native code.
//!
//! All of it is the same shape of work: a small piece of arithmetic asked for a
//! very large number of points. The height field is a handful of noise lookups
//! and the whole game is built on it -- every terrain chunk, every road cost,
//! every scatter placement, every missile flying down a valley. The router then
//! asks for it a few hundred thousand times per leg, and the map, the ground
//! mask and the road ribbons ask for it a few million times each.
//!
//! What is left on the script side is the part that is genuinely decisions
//! rather than arithmetic: where a town goes, what a road is for, what a chunk
//! of terrain is called. Anything that is a loop over a lot of points is here.
//!
//! - `field`  the land before anything is built on it
//! - `world`  what has been built on it: platforms, aerodromes, the corridor
//! - `router` where a road goes
//! - `survey` what height it was built to
//! - `raster` the mask, the climate, the ribbons and the map
//! - `index`  cell keys and the segment grid they index

mod field;
mod index;
mod raster;
mod router;
mod survey;
mod world;

use godot::prelude::*;
use rayon::prelude::*;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Mutex;

use field::natural;
use index::SegGrid;
use world::{
    corridor, ground_at, publish_corridor, publish_world, road_surface, world, Airfield, Leg,
    Pad, World, G_ALL, G_FIELDS, G_ROADS,
};

struct FlightNative;

#[gdextension]
unsafe impl ExtensionLibrary for FlightNative {}

/// Nodes expanded and wall time of the last `route_many`, so the game can
/// report what the search actually cost.
static LAST_NODES: AtomicUsize = AtomicUsize::new(0);
static LAST_MS: AtomicUsize = AtomicUsize::new(0);

/// Every road and street on the map, indexed for "how far is the nearest one".
/// Rebuilt whenever the network changes and read from every core after that.
static SEGS: Mutex<Option<&'static SegGrid>> = Mutex::new(None);

fn segments() -> Option<&'static SegGrid> {
    *SEGS.lock().unwrap()
}

#[derive(GodotClass)]
#[class(base=RefCounted, init)]
struct Terra {
    base: Base<RefCounted>,
}

#[godot_api]
impl Terra {
    // ---------------------------------------------------------- the field

    /// One point of untouched land. Kept for the odd caller that needs a single
    /// sample; anything asking for a grid should ask for the grid.
    #[func]
    fn natural_height(&self, x: f64, z: f64) -> f64 {
        natural(x as f32, z as f32) as f64
    }

    /// A square grid of untouched samples, `n` by `n`, starting at (x0, z0) and
    /// stepping by `cell`, row-major in z. Filled across every core.
    #[func]
    fn heights(&self, x0: f64, z0: f64, cell: f64, n: i64) -> PackedFloat32Array {
        let n = n.max(0) as usize;
        let (x0, z0, cell) = (x0 as f32, z0 as f32, cell as f32);
        let mut out = vec![0f32; n * n];
        out.par_chunks_mut(n.max(1)).enumerate().for_each(|(j, row)| {
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
        let out: Vec<f32> = src.par_iter().map(|p| natural(p.x, p.y)).collect();
        PackedFloat32Array::from(out.as_slice())
    }

    // ------------------------------------------------------ finished ground

    /// One point of finished ground. `flags` is 1 for the made roads and 2 for
    /// the aerodromes; the town platforms are always in.
    #[func]
    fn ground(&self, x: f64, z: f64, flags: i64) -> f64 {
        ground_at(world(), corridor(), x as f32, z as f32, flags as u32) as f64
    }

    /// A square grid of finished ground, the call a terrain chunk makes.
    ///
    /// This is the call that matters: a chunk is 289 points and the game builds
    /// hundreds of them, and asking as a block rather than as 289 separate
    /// calls removes the per-call overhead as well as using all the cores.
    #[func]
    fn grounds(&self, x0: f64, z0: f64, cell: f64, n: i64, flags: i64)
            -> PackedFloat32Array {
        let w = world();
        let c = corridor();
        let f = flags as u32;
        let n = n.max(0) as usize;
        let (x0, z0, cell) = (x0 as f32, z0 as f32, cell as f32);
        let mut out = vec![0f32; n * n];
        out.par_chunks_mut(n.max(1)).enumerate().for_each(|(j, row)| {
            let z = z0 + j as f32 * cell;
            for (i, v) in row.iter_mut().enumerate() {
                *v = ground_at(w, c, x0 + i as f32 * cell, z, f);
            }
        });
        PackedFloat32Array::from(out.as_slice())
    }

    /// Scattered points of finished ground, in the order they came in.
    #[func]
    fn grounds_at(&self, pts: PackedVector2Array, flags: i64) -> PackedFloat32Array {
        let w = world();
        let c = corridor();
        let f = flags as u32;
        let src: Vec<Vector2> = pts.as_slice().to_vec();
        let out: Vec<f32> = src
            .par_iter()
            .map(|p| ground_at(w, c, p.x, p.y, f))
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
                let hl = ground_at(w, c, p.x - E, p.y, G_ALL);
                let hr = ground_at(w, c, p.x + E, p.y, G_ALL);
                let hd = ground_at(w, c, p.x, p.y - E, G_ALL);
                let hu = ground_at(w, c, p.x, p.y + E, G_ALL);
                let len = ((hl - hr) * (hl - hr)
                    + (2.0 * E) * (2.0 * E)
                    + (hd - hu) * (hd - hu))
                    .sqrt();
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
                let h00 = ground_at(w, c, x0, z0, G_ALL);
                let h10 = ground_at(w, c, x0 + cell, z0, G_ALL);
                let h11 = ground_at(w, c, x0 + cell, z0 + cell, G_ALL);
                let h01 = ground_at(w, c, x0, z0 + cell, G_ALL);
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

    /// How far the drawn surface of a terrain node stands off the height field,
    /// and how high the ground in it reaches -- the two numbers the quadtree
    /// splits on, for a whole batch of nodes at once.
    ///
    /// `nodes` is a flat run of x0, z0, span per node, and what comes back is
    /// error and top per node. In script this was 353 separate height queries
    /// for every node the tree looked at.
    #[func]
    fn node_stats(&self, nodes: PackedFloat32Array, cells: i64) -> PackedFloat32Array {
        let w = world();
        let c = corridor();
        let cn = cells.max(1) as usize;
        let n = cn + 1;
        let src = nodes.as_slice().to_vec();
        let out: Vec<[f32; 2]> = src
            .par_chunks_exact(3)
            .map(|q| {
                let (x0, z0, span) = (q[0], q[1], q[2]);
                let cell = span / cn as f32;
                let mut g = vec![0f32; n * n];
                let mut top = -1e9f32;
                for j in 0..n {
                    let z = z0 + j as f32 * cell;
                    for i in 0..n {
                        let h = ground_at(w, c, x0 + i as f32 * cell, z, G_ALL);
                        g[j * n + i] = h;
                        if h > top {
                            top = h;
                        }
                    }
                }
                // At a cell's centre both of its triangles read the mean of the
                // two corners the shared diagonal runs through, so the drawn
                // height there is exact and needs no interpolation. Every other
                // cell is plenty to find a ridge.
                let mut e = 0.0f32;
                for j in (0..cn).step_by(2) {
                    for i in (0..cn).step_by(2) {
                        let drawn = (g[j * n + i] + g[(j + 1) * n + i + 1]) * 0.5;
                        let truth = ground_at(
                            w, c,
                            x0 + (i as f32 + 0.5) * cell,
                            z0 + (j as f32 + 0.5) * cell,
                            G_ALL,
                        );
                        e = e.max((truth - drawn).abs());
                    }
                }
                [e, top]
            })
            .collect();
        let mut flat = Vec::with_capacity(out.len() * 2);
        for v in out {
            flat.push(v[0]);
            flat.push(v[1]);
        }
        PackedFloat32Array::from(flat.as_slice())
    }

    // ------------------------------------------------------- what is built

    /// The levelled town platforms, as (x, z, radius, height) quadruples, and
    /// the aerodromes as (x, z, yaw, elevation). Both have to be in before any
    /// road is routed: a road is surveyed against the ground as the towns have
    /// already left it, and steered around the runways.
    #[func]
    fn set_world(&self, pads: PackedFloat32Array, fields: PackedFloat32Array) {
        let mut w = World::default();
        for c in pads.as_slice().chunks_exact(4) {
            w.pads.push(Pad { x: c[0], z: c[1], r: c[2], y: c[3] });
        }
        for f in fields.as_slice().chunks_exact(4) {
            w.fields.push(Airfield { x: f[0], z: f[1], yaw: f[2], elev: f[3] });
        }
        publish_world(w);
    }

    /// The corridor: every leg as (ax, az, bx, bz, made a, made b, natural a,
    /// natural b). Stamped into a grid here, once, rather than walked per query.
    #[func]
    fn set_corridor(&self, data: PackedFloat32Array) {
        let mut legs = Vec::with_capacity(data.len() / 8);
        for q in data.as_slice().chunks_exact(8) {
            legs.push(Leg {
                ax: q[0], az: q[1], bx: q[2], bz: q[3],
                ya: q[4], yb: q[5], na: q[6], nb: q[7],
            });
        }
        publish_corridor(legs);
    }

    /// Every road and street on the map, as a flat run of ax, az, bx, bz, for
    /// the distance queries. Indexed on a uniform grid so a query looks at a
    /// handful of segments rather than at all nine thousand.
    #[func]
    fn set_segments(&self, data: PackedFloat32Array) {
        let g: &'static SegGrid =
            Box::leak(Box::new(SegGrid::build(data.as_slice(), 256.0)));
        *SEGS.lock().unwrap() = Some(g);
    }

    /// The made surface at a point, as (height, how much of it applies, the
    /// ground it was cut from).
    #[func]
    fn road_surface_at(&self, x: f64, z: f64) -> Vector3 {
        let (y, w, g) = road_surface(corridor(), x as f32, z as f32);
        Vector3::new(y, w, g)
    }

    /// Metres to the nearest road or street centreline, exactly. `far` is how
    /// wide the search spreads before it gives up and answers that.
    #[func]
    fn road_distance_at(&self, x: f64, z: f64, far: f64) -> f64 {
        match segments() {
            Some(g) => g.distance(x as f32, z as f32, far as f32) as f64,
            None => far,
        }
    }

    /// The same, for a whole batch of points at once.
    #[func]
    fn road_distances_at(&self, pts: PackedVector2Array, far: f64)
            -> PackedFloat32Array {
        let far = far as f32;
        let src: Vec<Vector2> = pts.as_slice().to_vec();
        let out: Vec<f32> = match segments() {
            Some(g) => src.par_iter().map(|p| g.distance(p.x, p.y, far)).collect(),
            None => vec![far; src.len()],
        };
        PackedFloat32Array::from(out.as_slice())
    }

    // ------------------------------------------------------------ routing

    /// Every leg at once. `ends` is a flat run of a, b, a, b... and what comes
    /// back is one polyline per pair, empty where there is no route -- or where
    /// the only route was a causeway across open sea.
    ///
    /// The whole search is in here: the cost function reads the height field
    /// directly, so a hundred thousand node expansions cross no boundary at
    /// all, and the legs themselves run on every core.
    #[func]
    fn route_many(&self, ends: PackedVector2Array) -> Array<PackedVector2Array> {
        let w = world();
        let jobs: Vec<((f32, f32), (f32, f32))> = ends
            .as_slice()
            .chunks_exact(2)
            .map(|c| ((c[0].x, c[0].y), (c[1].x, c[1].y)))
            .collect();
        let clock = std::time::Instant::now();
        let nodes = AtomicUsize::new(0);
        let done: Vec<Vec<(f32, f32)>> = jobs
            .par_iter()
            .map(|(a, b)| {
                let (line, n) = router::route(w, *a, *b);
                nodes.fetch_add(n, Ordering::Relaxed);
                line
            })
            .collect();
        LAST_NODES.store(nodes.load(Ordering::Relaxed), Ordering::Relaxed);
        LAST_MS.store(clock.elapsed().as_millis() as usize, Ordering::Relaxed);
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

    /// Nodes expanded and wall time of the last `route_many`.
    #[func]
    fn route_stats(&self) -> Vector2 {
        Vector2::new(
            LAST_NODES.load(Ordering::Relaxed) as f32,
            LAST_MS.load(Ordering::Relaxed) as f32,
        )
    }

    // ------------------------------------------------------------- survey

    /// The whole road survey, from the routed polylines to the finished
    /// alignment: stations at survey spacing, a design profile for each line,
    /// the relaxation that makes roads meeting at a junction agree, and the
    /// classification of what has to be carried on a deck or bored through.
    ///
    /// `lines` is every routed polyline end to end and `starts` where each one
    /// begins, plus a final entry holding the total. What comes back is the
    /// stations, the profile, the untouched ground under them, the per-station
    /// structure flag, and the new starts -- the stations are chained here, so
    /// there are far more of them coming out than went in.
    ///
    /// All of it in one call. Handing it back a pass at a time was eighty
    /// thousand stations crossing the boundary twenty-odd times, and it was the
    /// longest thing left in world generation once routing went native.
    #[func]
    fn survey(&self, lines: PackedVector2Array, starts: PackedInt32Array,
            passes: i64) -> Array<Variant> {
        let src = lines.as_slice();
        let st = starts.as_slice();
        let n_lines = st.len().saturating_sub(1);
        // stations, line by line, at survey spacing
        let chained: Vec<Vec<(f32, f32)>> = (0..n_lines)
            .into_par_iter()
            .map(|li| {
                let seg: Vec<(f32, f32)> = src[st[li] as usize..st[li + 1] as usize]
                    .iter()
                    .map(|v| (v.x, v.y))
                    .collect();
                survey::chain(&seg, survey::SURVEY_STEP)
            })
            .collect();
        let mut p: Vec<(f32, f32)> = Vec::new();
        let mut out_starts: Vec<i32> = Vec::with_capacity(n_lines + 1);
        for line in &chained {
            out_starts.push(p.len() as i32);
            p.extend_from_slice(line);
        }
        out_starts.push(p.len() as i32);
        // the ground under every station, before any road is on it
        let w = world();
        let g: Vec<f32> = p
            .par_iter()
            .map(|q| ground_at(w, corridor(), q.0, q.1, G_FIELDS))
            .collect();
        // the design profile and the gradient allowance it needed, then the
        // relaxation between lines
        let mut y = vec![0f32; p.len()];
        let mut gr = vec![0f32; p.len()];
        {
            let parts: Vec<(usize, Vec<f32>, Vec<f32>)> = (0..n_lines)
                .into_par_iter()
                .map(|li| {
                    let (a0, a1) =
                        (out_starts[li] as usize, out_starts[li + 1] as usize);
                    let (seg, allow) = survey::design(&p[a0..a1], &g[a0..a1]);
                    (a0, seg, allow)
                })
                .collect();
            for (a0, seg, allow) in parts {
                y[a0..a0 + seg.len()].copy_from_slice(&seg);
                gr[a0..a0 + allow.len()].copy_from_slice(&allow);
            }
        }
        survey::relax(&mut p, &mut y, &gr, &out_starts, passes as i32);
        // Welding moved the stations, so the ground under them is not the
        // ground the design was drawn against any more.
        let g: Vec<f32> = p
            .par_iter()
            .map(|q| ground_at(w, corridor(), q.0, q.1, G_FIELDS))
            .collect();
        let (y, flags) = survey::finish(&p, &y, &g, &gr, &out_starts);
        let mut out: Array<Variant> = Array::new();
        let pv: Vec<Vector2> = p.iter().map(|q| Vector2::new(q.0, q.1)).collect();
        out.push(&PackedVector2Array::from(pv.as_slice()).to_variant());
        out.push(&PackedFloat32Array::from(y.as_slice()).to_variant());
        out.push(&PackedFloat32Array::from(g.as_slice()).to_variant());
        out.push(&PackedByteArray::from(flags.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(out_starts.as_slice()).to_variant());
        out
    }

    /// The largest height difference a driver would see between the road under
    /// the wheels and another stretch running alongside it. Measured rather
    /// than assumed, and only asked for by the harness.
    #[func]
    fn worst_tie(&self, pts: PackedVector2Array, ys: PackedFloat32Array,
            flags: PackedByteArray, starts: PackedInt32Array) -> f64 {
        let p: Vec<(f32, f32)> = pts.as_slice().iter().map(|v| (v.x, v.y)).collect();
        survey::worst_tie(&p, ys.as_slice(), flags.as_slice(), starts.as_slice())
            as f64
    }

    // ------------------------------------------------------------- raster

    /// The road network and the town footprints, rasterised into the two
    /// channel mask the ground shader paints from. `discs` is (x, z, solid,
    /// fade, channel) and `caps` is (ax, az, bx, bz, solid, fade, channel).
    #[func]
    fn ground_mask(&self, discs: PackedFloat32Array, caps: PackedFloat32Array,
            n: i64, half: f64, centre: Vector2) -> Array<Variant> {
        let mut stamps: Vec<raster::Stamp> = Vec::new();
        for q in discs.as_slice().chunks_exact(5) {
            stamps.push(raster::Stamp {
                ax: q[0], az: q[1], bx: q[0], bz: q[1],
                solid: q[2], fade: q[3], channel: q[4] as u8,
            });
        }
        for q in caps.as_slice().chunks_exact(7) {
            stamps.push(raster::Stamp {
                ax: q[0], az: q[1], bx: q[2], bz: q[3],
                solid: q[4], fade: q[5], channel: q[6] as u8,
            });
        }
        let (buf, road, town) = raster::ground_mask(&stamps, n.max(0) as usize,
            half as f32, centre.x, centre.y);
        let mut out: Array<Variant> = Array::new();
        out.push(&PackedByteArray::from(buf.as_slice()).to_variant());
        out.push(&Vector2::new(road as f32, town as f32).to_variant());
        out
    }

    /// Temperature and moisture over the whole world, as the half float pairs
    /// `Image.FORMAT_RGH` holds.
    #[func]
    fn climate_map(&self, n: i64, half: f64) -> PackedByteArray {
        let buf = raster::climate_map(n.max(0) as usize, half as f32);
        PackedByteArray::from(buf.as_slice())
    }

    /// Carriageways and kerbs for every road and street on the map, as two
    /// vertex lists. `legs` is a flat run of ax, az, bx, bz, half width.
    #[func]
    fn road_ribbons(&self, legs: PackedFloat32Array) -> Array<Variant> {
        let r = raster::ribbons(legs.as_slice());
        let to_v = |src: &[[f32; 3]]| -> PackedVector3Array {
            let v: Vec<Vector3> =
                src.iter().map(|q| Vector3::new(q[0], q[1], q[2])).collect();
            PackedVector3Array::from(v.as_slice())
        };
        let mut out: Array<Variant> = Array::new();
        out.push(&to_v(&r.surf).to_variant());
        out.push(&to_v(&r.kerb).to_variant());
        out
    }

    /// The tactical map's background: hill-shaded relief in biome colour with
    /// the road network over it, as RGB8.
    #[func]
    fn map_relief(&self, n: i64, half: f64) -> PackedByteArray {
        static EMPTY: std::sync::OnceLock<SegGrid> = std::sync::OnceLock::new();
        let segs = segments()
            .unwrap_or_else(|| EMPTY.get_or_init(|| SegGrid::build(&[], 256.0)));
        let buf = raster::relief(n.max(0) as usize, half as f32, segs);
        PackedByteArray::from(buf.as_slice())
    }

    /// The blended biome weights at a point, in the order snow, rock, forest,
    /// grass, steppe, sand, marsh.
    #[func]
    fn biome_weights(&self, x: f64, z: f64, y: f64, slope: f64)
            -> PackedFloat32Array {
        let w = raster::biome_weights(x as f32, z as f32, y as f32, slope as f32);
        PackedFloat32Array::from(w.as_slice())
    }

    // ------------------------------------------------------------- reporting

    /// How many threads the pool will actually use, so the game can say so.
    #[func]
    fn threads(&self) -> i64 {
        rayon::current_num_threads() as i64
    }

    /// What the survey builds to: the ruling gradient, what it may be pushed
    /// to, the hairpin nothing may exceed, the ordinary cutting and embankment,
    /// and the deepest and tallest either is ever allowed to reach. Read rather
    /// than written down twice, so a harness measures the road against the
    /// numbers the road was actually built to.
    #[func]
    fn survey_limits(&self) -> PackedFloat32Array {
        PackedFloat32Array::from([
            survey::ROAD_GRADE,
            survey::ROAD_GRADE_MAX,
            survey::GRADE_HAIRPIN,
            survey::ROAD_CUT_MAX,
            survey::ROAD_FILL_MAX,
            survey::CUT_HARD,
            survey::FILL_HARD,
            survey::SURVEY_STEP,
        ].as_slice())
    }

    /// The flag values `ground` and its batch forms take, so the two sides
    /// cannot disagree about what they mean.
    #[func]
    fn ground_flags(&self) -> Vector3 {
        Vector3::new(G_ROADS as f32, G_FIELDS as f32, G_ALL as f32)
    }
}
