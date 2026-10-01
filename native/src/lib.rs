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
//! - `field`  the land before anything is built on it, on the flat world
//! - `sphere` the same on the planet, and the chart laid over it
//! - `world`  what has been built on it: platforms, aerodromes, the corridor
//! - `router` where a road goes
//! - `survey` what height it was built to
//! - `raster` the mask, the ribbons, the road ink and the map
//! - `tree`   which leaves of the terrain quadtree should exist
//! - `chunk`  one leaf of the terrain quadtree, meshed
//! - `cloud`  the noise the weather layer is drawn from
//! - `index`  cell keys, and the segment grid the world is indexed on
//!
//! What is left in this file is the boundary itself: the class the game calls
//! through, the marshalling either side of it, and the slots a raster is baked
//! in while the frame goes on without it. Nothing here decides anything.

mod chunk;
mod cloud;
mod field;
mod index;
mod raster;
mod router;
mod sphere;
mod survey;
mod tree;
mod world;

use godot::prelude::*;
use rayon::prelude::*;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Mutex;

use field::natural;
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

/// How far a road may wander before the connection is not worth making, as a
/// multiple of the distance between the two places it joins.
const ROUTE_DETOUR: f32 = 4.0;

/// A raster being baked off the main thread. One at a time per slot: the map
/// only ever wants the newest one, and a queue of stale windows is work nobody
/// is waiting for.
#[derive(Default)]
struct Bake {
    busy: bool,
    done: bool,
    data: Vec<u8>,
}

/// The globe's zoomed-in window, the chart's own close-in sheet, and the
/// climate the ground shader reads. A slot each, because they are asked for by
/// different things at different times and one would cancel another.
static PATCH: std::sync::OnceLock<Mutex<Bake>> = std::sync::OnceLock::new();
static SHEET: std::sync::OnceLock<Mutex<Bake>> = std::sync::OnceLock::new();
static CLIMATE: std::sync::OnceLock<Mutex<Bake>> = std::sync::OnceLock::new();

fn slot(cell: &'static std::sync::OnceLock<Mutex<Bake>>) -> &'static Mutex<Bake> {
    cell.get_or_init(|| Mutex::new(Bake::default()))
}

/// Start a bake if the slot is free, and say whether it was. The work runs on a
/// thread of its own; nothing waits for it.
fn bake_start<F>(cell: &'static std::sync::OnceLock<Mutex<Bake>>, f: F) -> bool
where
    F: FnOnce() -> Vec<u8> + Send + 'static,
{
    {
        let mut g = slot(cell).lock().unwrap();
        if g.busy {
            return false;
        }
        g.busy = true;
        g.done = false;
    }
    std::thread::spawn(move || {
        let buf = f();
        let mut g = slot(cell).lock().unwrap();
        g.data = buf;
        g.busy = false;
        g.done = true;
    });
    true
}

fn bake_ready(cell: &'static std::sync::OnceLock<Mutex<Bake>>) -> bool {
    slot(cell).lock().unwrap().done
}

/// The finished bake, handed over: asking again returns nothing until another
/// has been requested.
fn bake_take(cell: &'static std::sync::OnceLock<Mutex<Bake>>) -> Vec<u8> {
    let mut g = slot(cell).lock().unwrap();
    if !g.done {
        return Vec::new();
    }
    g.done = false;
    std::mem::take(&mut g.data)
}

/// A canvas triangle array under construction: the four parallel arrays
/// `canvas_item_add_triangle_array` wants.
#[derive(Default)]
struct MeshOut {
    pts: Vec<Vector2>,
    uvs: Vec<Vector2>,
    cols: Vec<Color>,
    idx: Vec<i32>,
}

impl MeshOut {
    /// Where a direction lands on the sheet. Longitude east of the prime
    /// meridian, latitude from the pole -- the same mapping the sheet is baked
    /// with, or the picture would be indexed by one rule and drawn by another.
    fn uv_of(n: Vector3) -> Vector2 {
        let d = [n.x, n.y, n.z];
        let pole = sphere::NORTH;
        let home = sphere::HOME;
        let ex = [
            pole[1] * home[2] - pole[2] * home[1],
            pole[2] * home[0] - pole[0] * home[2],
            pole[0] * home[1] - pole[1] * home[0],
        ];
        let dot = |a: [f32; 3], b: [f32; 3]| a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
        let lat = dot(d, pole).clamp(-1.0, 1.0).asin();
        let lon = dot(d, ex).atan2(dot(d, home));
        Vector2::new(lon / std::f32::consts::TAU + 0.5,
            0.5 - lat / std::f32::consts::PI)
    }

    fn quad(&mut self, ns: &[Vector3; 4], org: Vector2, rad: f32, b: Basis,
            lit: Vector3, seam: bool) {
        let mut uvs = [Vector2::ZERO; 4];
        for k in 0..4 {
            uvs[k] = Self::uv_of(ns[k]);
        }
        if seam {
            // The quad that straddles the seam meridian gets UVs half a world
            // apart, and interpolating between them draws the entire map
            // squeezed into one triangle. Carrying the low side round past 1
            // makes the interpolation continuous, and the texture's repeat
            // brings it back to the same texels.
            let (mut lo, mut hi) = (1e9f32, -1e9f32);
            for uv in uvs.iter() {
                lo = lo.min(uv.x);
                hi = hi.max(uv.x);
            }
            if hi - lo > 0.5 {
                for uv in uvs.iter_mut() {
                    if uv.x < 0.5 {
                        uv.x += 1.0;
                    }
                }
            }
        }
        self.quad_uv(ns, &uvs, org, rad, b, lit);
    }

    fn quad_uv(&mut self, ns: &[Vector3; 4], uvs: &[Vector2; 4], org: Vector2,
            rad: f32, b: Basis, lit: Vector3) {
        let mut vs = [Vector3::ZERO; 4];
        let mut near = false;
        for k in 0..4 {
            vs[k] = b * ns[k];
            if vs[k].z > 0.0 {
                near = true;
            }
        }
        if !near {
            return;
        }
        let base = self.pts.len() as i32;
        for k in 0..4 {
            let v = vs[k];
            self.pts.push(Vector2::new(org.x + v.x * rad, org.y - v.y * rad));
            self.uvs.push(uvs[k]);
            // Lambert against the real sun.
            //
            // The floor was lifted to 0.45 once, to make the night side
            // readable -- and that washed the terminator out until the whole
            // globe read as lit, which is the one thing this shading exists to
            // show. The map has to agree with the ground: where it is night in
            // the game it is night on the map. A little ambient so the dark
            // side is a silhouette rather than a hole, and no more.
            let sh = v.dot(lit).clamp(0.0, 1.0);
            let g = 0.18 + 0.82 * sh;
            self.cols.push(Color::from_rgb(g, g, g));
        }
        for k in [0, 1, 2, 0, 2, 3] {
            self.idx.push(base + k);
        }
    }

    /// Points, UVs, colours and indices, in the order
    /// `canvas_item_add_triangle_array` takes them.
    fn into_arrays(self) -> Array<Variant> {
        let mut out: Array<Variant> = Array::new();
        out.push(&PackedVector2Array::from(self.pts.as_slice()).to_variant());
        out.push(&PackedVector2Array::from(self.uvs.as_slice()).to_variant());
        out.push(&PackedColorArray::from(self.cols.as_slice()).to_variant());
        out.push(&PackedInt32Array::from(self.idx.as_slice()).to_variant());
        out
    }
}

/// One meshed leaf, as the five arrays the script turns into a mesh: vertices,
/// normals, the seam the stitching left, the morph and the coarse normal.
fn push_chunk(out: &mut Array<Variant>, c: &chunk::Chunk) {
    let verts: Vec<Vector3> = c.verts.iter()
        .map(|v| Vector3::new(v[0], v[1], v[2])).collect();
    let nrms: Vec<Vector3> = c.nrms.iter()
        .map(|v| Vector3::new(v[0], v[1], v[2])).collect();
    let morph: Vec<Vector2> = c.morph.iter()
        .map(|v| Vector2::new(v[0], v[1])).collect();
    out.push(&PackedVector3Array::from(verts.as_slice()).to_variant());
    out.push(&PackedVector3Array::from(nrms.as_slice()).to_variant());
    out.push(&(c.residual as f64).to_variant());
    out.push(&PackedVector2Array::from(morph.as_slice()).to_variant());
    out.push(&PackedFloat32Array::from(c.cnrm.as_slice()).to_variant());
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

    // ------------------------------------------------------------- the planet

    /// Put the chart somewhere on the planet. Everything asked for in `(x, z)`
    /// afterwards is measured east and south from here, along the ground.
    /// Whether the world is a planet. Told to the extension because the router
    /// and the survey ask for the ground before anything was built on it, and
    /// which ground that is depends on the answer.
    #[func]
    fn set_globe(&self, on: bool) {
        crate::world::set_globe(on);
    }

    #[func]
    fn set_chart(&self, origin: Vector3, east: Vector3, south: Vector3,
            radius: f64) {
        sphere::set_chart(
            [origin.x, origin.y, origin.z],
            [east.x, east.y, east.z],
            [south.x, south.y, south.z],
            radius as f32,
        );
    }

    /// The planet's ground at a chart coordinate, in the same world `y` the flat
    /// field returns -- so this can stand in for `ground` wherever the world is
    /// round rather than flat.
    #[func]
    fn ground_globe(&self, x: f64, z: f64) -> f64 {
        let c = sphere::chart();
        sphere::ground_world_y(&c, x as f32, z as f32, G_ALL) as f64
    }

    /// Planetary ground with the carving selected.
    ///
    /// `ground_globe` always asks for all of it, which is right for anything
    /// standing on the world and wrong for anything siting something on it: a
    /// field is levelled to the height of its own site, so it has to be able
    /// to ask what that site was before the field was there. Without this the
    /// globe had no way to leave the aerodromes out, `register_field` read back
    /// the elevation the field already had, and re-siting the home strip was a
    /// fixed point that never moved it anywhere.
    #[func]
    fn ground_globe_flags(&self, x: f64, z: f64, flags: i64) -> f64 {
        let c = sphere::chart();
        sphere::ground_world_y(&c, x as f32, z as f32, flags as u32) as f64
    }

    /// A square grid of it, which is what a terrain chunk asks for. Same shape
    /// as `grounds`, and parallel for the same reason.
    #[func]
    fn grounds_globe(&self, x0: f64, z0: f64, cell: f64, n: i64)
            -> PackedFloat32Array {
        let c = sphere::chart();
        let n = n.max(0) as usize;
        let (x0, z0, cell) = (x0 as f32, z0 as f32, cell as f32);
        let mut out = vec![0f32; n * n];
        out.par_chunks_mut(n.max(1)).enumerate().for_each(|(j, row)| {
            let z = z0 + j as f32 * cell;
            for (i, v) in row.iter_mut().enumerate() {
                *v = sphere::ground_world_y(&c, x0 + i as f32 * cell, z, G_ALL);
            }
        });
        PackedFloat32Array::from(out.as_slice())
    }

    /// Height above sea level for a direction from the planet's centre. The
    /// map and the orbital body ask in directions rather than in chart pairs,
    /// because they are looking at the whole planet rather than standing on it.
    #[func]
    fn planet_height(&self, dir: Vector3) -> f64 {
        let c = sphere::chart();
        sphere::height([dir.x, dir.y, dir.z], c.radius, G_ALL) as f64
    }

    /// A batch of those, for baking a whole planet at once.
    #[func]
    fn planet_heights(&self, dirs: PackedVector3Array) -> PackedFloat32Array {
        let c = sphere::chart();
        let src: Vec<Vector3> = dirs.to_vec();
        let mut out = vec![0f32; src.len()];
        out.par_iter_mut().enumerate().for_each(|(i, v)| {
            let d = src[i];
            *v = sphere::height([d.x, d.y, d.z], c.radius, G_ALL);
        });
        PackedFloat32Array::from(out.as_slice())
    }

    /// The close-in ground as the map draws it, on the planet. Blocking; the
    /// off-thread form is `sheet_request`.
    #[func]
    fn map_relief_globe(&self, n: i64, half: f64) -> PackedByteArray {
        let c = sphere::chart();
        PackedByteArray::from(
            sphere::relief_globe(&c, n.max(1) as usize, half as f32).as_slice())
    }

    /// The whole planet as one equirectangular RGB8 sheet.
    #[func]
    fn planet_sheet(&self, w: i64, h: i64, north: Vector3) -> PackedByteArray {
        let c = sphere::chart();
        let buf = sphere::sheet(w.max(1) as usize, h.max(1) as usize,
            [north.x, north.y, north.z], c.radius);
        PackedByteArray::from(buf.as_slice())
    }

    /// The aerodrome flattening weight the extension itself uses, for when the
    /// two sides disagree about whether a point is on a runway.
    #[func]
    fn field_flat(&self, x: f64, z: f64) -> f64 {
        let w = world::world();
        let mut best = 0.0f32;
        for f in &w.fields {
            let v = world::field_factor(f, x as f32, z as f32);
            if v > best {
                best = v;
            }
        }
        best as f64
    }

    /// Where the planet is in its year, from the clock: +1 at northern
    /// midsummer, -1 at northern midwinter. The biome rule reads it, so the
    /// snow line and the treeline move with the season.
    #[func]
    fn set_season(&self, s: f64) {
        sphere::set_season(s as f32);
    }

    /// The climate scale this side is using, so the other side can check that
    /// the two have not drifted apart. They are one number about the planet's
    /// tilt and they have been two copies of it more than once.
    #[func]
    fn climate_squeeze(&self) -> f64 {
        sphere::CLIMATE_SQUEEZE as f64
    }

    /// Where a country is, as a direction from the planet's centre.
    ///
    /// Asked rather than worked out again on the other side. Written out twice
    /// -- once here and once in GDScript -- the two copies disagreed about
    /// which way north was, and three of the six countries were sited in the
    /// ocean the generator had never been told to raise.
    #[func]
    fn homeland_dir(&self, i: i64) -> Vector3 {
        let d = sphere::homeland(i.max(0) as usize);
        Vector3::new(d[0], d[1], d[2])
    }

    /// The globe map's mesh: screen points, sheet UVs, shading and indices.
    ///
    /// Built in GDScript this was four and a half thousand quads -- eighteen
    /// thousand corners, each a little trigonometry and a basis multiply --
    /// every frame the map was open, and the map redraws every frame. It is a
    /// loop over a lot of points, so it lives here.
    ///
    /// Quads entirely round the back of the planet are dropped.
    #[func]
    fn globe_mesh(&self, rings: i64, segs: i64, org: Vector2, rad: f64,
            b: Basis, lit: Vector3) -> Array<Variant> {
        let rings = rings.max(1) as usize;
        let segs = segs.max(1) as usize;
        let mut m = MeshOut::default();
        for i in 0..rings {
            let t0 = std::f32::consts::PI * i as f32 / rings as f32;
            let t1 = std::f32::consts::PI * (i + 1) as f32 / rings as f32;
            for j in 0..segs {
                let p0 = std::f32::consts::TAU * j as f32 / segs as f32;
                let p1 = std::f32::consts::TAU * (j + 1) as f32 / segs as f32;
                // The sphere is walked about the world's own up, which is what
                // the chart is a cap on; the sheet is indexed from the pole.
                let corner = |t: f32, p: f32| -> Vector3 {
                    Vector3::new(t.sin() * p.cos(), t.cos(), t.sin() * p.sin())
                };
                let ns = [corner(t0, p0), corner(t0, p1),
                    corner(t1, p1), corner(t1, p0)];
                m.quad(&ns, org, rad as f32, b, lit, true);
            }
        }
        m.into_arrays()
    }

    /// The same, for the close-in detail patch: a grid over a window of the
    /// sheet rather than the whole sphere.
    #[func]
    fn globe_patch_mesh(&self, grid: i64, u0: f64, u1: f64, v0: f64, v1: f64,
            org: Vector2, rad: f64, b: Basis, lit: Vector3) -> Array<Variant> {
        let g = grid.max(1) as usize;
        let (u0, u1, v0, v1) = (u0 as f32, u1 as f32, v0 as f32, v1 as f32);
        let mut m = MeshOut::default();
        for i in 0..g {
            for j in 0..g {
                let fu0 = i as f32 / g as f32;
                let fu1 = (i + 1) as f32 / g as f32;
                let fv0 = j as f32 / g as f32;
                let fv1 = (j + 1) as f32 / g as f32;
                let at = |fu: f32, fv: f32| -> Vector3 {
                    let d = sphere::at_lat_lon(
                        (0.5 - (v0 + fv * (v1 - v0))) * std::f32::consts::PI,
                        ((u0 + fu * (u1 - u0)) - 0.5) * std::f32::consts::TAU,
                        sphere::NORTH);
                    Vector3::new(d[0], d[1], d[2])
                };
                let ns = [at(fu0, fv0), at(fu1, fv0), at(fu1, fv1), at(fu0, fv1)];
                let uvs = [Vector2::new(fu0, fv0), Vector2::new(fu1, fv0),
                    Vector2::new(fu1, fv1), Vector2::new(fu0, fv1)];
                m.quad_uv(&ns, &uvs, org, rad as f32, b, lit);
            }
        }
        m.into_arrays()
    }

    /// Somewhere near a point with room for an aerodrome on dry land.
    ///
    /// A spiral outward, and at each stop the whole footprint is checked --
    /// nine by nine over two kilometres by four -- because a field needs more
    /// than a dry point: a headland that is dry in the middle and sea at both
    /// ends gets a runway with its approach lights under water.
    ///
    /// Written in GDScript this was twenty-one thousand separate calls across
    /// the binding for each country, and there are six of them. It is a loop
    /// over a great many points, which is what this side is for.
    ///
    /// Returns an infinite vector when there is nowhere.
    #[func]
    fn dry_field_site(&self, cx: f64, cz: f64, r0: f64, dr: f64, da: f64,
            tries: i64, bound: f64) -> Vector2 {
        let c = sphere::chart();
        let globe = world::is_globe();
        let w = world::world();
        let corr = world::corridor();
        let wet = |x: f32, z: f32| -> bool {
            if globe {
                sphere::ground_world_y(&c, x, z, G_ALL)
                    < sphere::sea_at(&c, x, z) + 25.0
            } else {
                // Both sides of the flat comparison carry the same drop, so it
                // cancels and this is the sea level the field works in.
                world::ground_at(w, corr, x, z, G_ALL)
                    < crate::field::WATER_LEVEL + 25.0
            }
        };
        for k in 0..tries.max(0) {
            let a = 2.3 + k as f32 * da as f32;
            let r = r0 as f32 + k as f32 * dr as f32;
            let qx = cx as f32 + a.cos() * r;
            let qz = cz as f32 + a.sin() * r;
            if bound > 0.0 && (qx.abs() > bound as f32 || qz.abs() > bound as f32) {
                continue;
            }
            let mut dry = true;
            'foot: for i in 0..9 {
                for j in 0..9 {
                    let px = qx + (i as f32 - 4.0) * 700.0;
                    let pz = qz + (j as f32 - 4.0) * 900.0;
                    if wet(px, pz) {
                        dry = false;
                        break 'foot;
                    }
                }
            }
            if dry {
                return Vector2::new(qx, qz);
            }
        }
        Vector2::new(f32::INFINITY, f32::INFINITY)
    }

    /// Ask for a window of the sheet to be baked in the background.
    ///
    /// Returns false if one is already being baked. The bake is half a million
    /// texels of the full height field and takes about forty milliseconds,
    /// which is a visible hitch every time the map is zoomed. The thread is
    /// spawned here rather than in GDScript because everything it touches is
    /// this side's -- the noise tables, the chart, the carving -- and a script
    /// thread reaching back in through the binding is a different question
    /// with a worse answer.
    #[func]
    fn patch_request(&self, w: i64, h: i64, north: Vector3,
            u0: f64, u1: f64, v0: f64, v1: f64) -> bool {
        let radius = sphere::chart().radius;
        let n = [north.x, north.y, north.z];
        let (w, h) = (w.max(1) as usize, h.max(1) as usize);
        let (u0, u1, v0, v1) = (u0 as f32, u1 as f32, v0 as f32, v1 as f32);
        bake_start(&PATCH, move || {
            sphere::sheet_window(w, h, n, radius, u0, u1, v0, v1)
        })
    }

    /// Whether a requested bake has finished.
    #[func]
    fn patch_ready(&self) -> bool {
        bake_ready(&PATCH)
    }

    /// The finished bake, and it is handed over: asking again returns nothing
    /// until another has been requested.
    #[func]
    fn patch_take(&self) -> PackedByteArray {
        PackedByteArray::from(bake_take(&PATCH).as_slice())
    }

    /// The close-in sheet, baked off the main thread.
    ///
    /// This is the same picture `map_relief_globe` draws, asked for rather than
    /// waited on. The chart moves whenever the player gets 150 km from the
    /// middle of it, and everything laid out on it is renumbered at once --
    /// which used to include rasterising four million texels of relief on the
    /// frame the move happened. Measured, a chart move was a 1352 ms freeze in
    /// flight and 1183 ms of it was this. The map draws the sheet it has until
    /// the new one lands, which is a picture a few seconds stale rather than a
    /// second and a third of nothing at all.
    #[func]
    fn sheet_request(&self, n: i64, half: f64) -> bool {
        let c = sphere::chart();
        let n = n.max(1) as usize;
        let half = half as f32;
        bake_start(&SHEET, move || sphere::relief_globe(&c, n, half))
    }

    #[func]
    fn sheet_ready(&self) -> bool {
        bake_ready(&SHEET)
    }

    #[func]
    fn sheet_take(&self) -> PackedByteArray {
        PackedByteArray::from(bake_take(&SHEET).as_slice())
    }

    /// A window of the planet sheet, for the map's close zooms.
    ///
    /// `u0..u1` and `v0..v1` are the sheet's own coordinates. The map works out
    /// which cap it is looking at and asks for that, so the picture gets finer
    /// as it is zoomed rather than showing the same two texels magnified.
    #[func]
    fn planet_patch(&self, w: i64, h: i64, north: Vector3,
            u0: f64, u1: f64, v0: f64, v1: f64) -> PackedByteArray {
        let c = sphere::chart();
        let buf = sphere::sheet_window(w.max(1) as usize, h.max(1) as usize,
            [north.x, north.y, north.z], c.radius,
            u0 as f32, u1 as f32, v0 as f32, v1 as f32);
        PackedByteArray::from(buf.as_slice())
    }

    /// Scattered points of planetary ground, for a chunk's edge skirt.
    #[func]
    fn grounds_at_globe(&self, pts: PackedVector2Array) -> PackedFloat32Array {
        let c = sphere::chart();
        let src: Vec<Vector2> = pts.to_vec();
        let mut out = vec![0f32; src.len()];
        out.par_iter_mut().enumerate().for_each(|(i, v)| {
            *v = sphere::ground_world_y(&c, src[i].x, src[i].y, G_ALL);
        });
        PackedFloat32Array::from(out.as_slice())
    }

    /// The same error-and-highest-point measure the quadtree splits on, taken
    /// against the planetary field. The tree cannot be driven by one field and
    /// meshed from another: it would refine where the flat world has a ridge and
    /// leave the planet's own ranges as four triangles.
    #[func]
    fn node_stats_globe(&self, nodes: PackedFloat32Array, cells: i64)
            -> PackedFloat32Array {
        let ch = sphere::chart();
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
                        let h = sphere::ground_world_y(
                            &ch, x0 + i as f32 * cell, z, G_ALL);
                        g[j * n + i] = h;
                        if h > top {
                            top = h;
                        }
                    }
                }
                let mut e = 0.0f32;
                for j in (0..cn).step_by(2) {
                    for i in (0..cn).step_by(2) {
                        let drawn = (g[j * n + i] + g[(j + 1) * n + i + 1]) * 0.5;
                        let truth = sphere::ground_world_y(
                            &ch,
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

    // ---------------------------------------------------------- the clouds

    /// The cloud layer's noise volume: an `n` cube of two channels, the weather
    /// system and the clouds within it, with the octaves already summed.
    ///
    /// The layer used to sum four samples of a cube of random bytes for each of
    /// them, per march step, per pixel -- and the finest octave of the result
    /// was 47 m of sky against a march that steps 571 m. Summed once here, into
    /// a field whose finest content is about a kilometre, the shader fetches
    /// each channel once and the detail is a size it can actually see.
    #[func]
    fn cloud_volume(&self, n: i64) -> PackedByteArray {
        PackedByteArray::from(cloud::volume(n.max(2) as usize).as_slice())
    }

    // ----------------------------------------------------------- the tree

    /// The leaves that should exist for this eye position.
    ///
    /// Twelve numbers a leaf: depth, the two grid indices, what each of the
    /// four edges meets, a bit per edge that faces a *finer* neighbour, and the
    /// four unclamped lookups the harness checks against a full descent.
    ///
    /// The descent, the error measure and the neighbour lookups are all here.
    /// In script it was 4.1 ms every time the eye moved 120 m -- a dropped
    /// frame twice a second at cruise -- and every node the tree had not seen
    /// before paid 353 height samples for its error one node at a time, on the
    /// thread walking the tree. Here a level is measured in one parallel pass.
    #[func]
    fn terrain_tree(&self, eye: Vector3) -> PackedInt32Array {
        let leaves = tree::wanted([eye.x, eye.y, eye.z]);
        let mut out = Vec::with_capacity(leaves.len() * 12);
        for l in &leaves {
            out.extend_from_slice(&[l.depth, l.ix, l.iz, l.nb[0], l.nb[1],
                l.nb[2], l.nb[3], l.fine as i32, l.raw[0], l.raw[1], l.raw[2],
                l.raw[3]]);
        }
        PackedInt32Array::from(out.as_slice())
    }

    /// What depth the tree draws a point at, by descent from the root. The
    /// harness's second opinion about every neighbour lookup.
    #[func]
    fn terrain_depth_at(&self, x: f64, z: f64, eye: Vector3) -> i64 {
        tree::depth_at(x as f32, z as f32, [eye.x, eye.y, eye.z]) as i64
    }

    /// The highest ground in a node, measured if nobody has asked yet.
    #[func]
    fn terrain_node_top(&self, depth: i64, ix: i64, iz: i64) -> f64 {
        tree::node_top(depth as i32, ix as i32, iz as i32) as f64
    }

    /// What the tree has measured, for the bake, and back again.
    ///
    /// A node's error and high point are a property of the height field alone,
    /// so what one run learned is what the next one starts with -- and the two
    /// travel together, which they did not when the table lived in script: the
    /// errors went to disk and the high points did not, so a run off a bake
    /// read every node's high ground as zero.
    #[func]
    fn terrain_stats_take(&self) -> PackedByteArray {
        PackedByteArray::from(tree::export().as_slice())
    }

    #[func]
    fn terrain_stats_put(&self, data: PackedByteArray) {
        tree::import(data.as_slice());
    }

    // --------------------------------------------------------- the chunks

    /// The landable platforms, which are the one part of the world that moves.
    ///
    /// Pushed in before a batch of chunks goes out rather than published once
    /// with the roads and the aerodromes: a carrier under way carries her deck
    /// with her. Seven numbers each -- origin x and z, cos and sin of the
    /// negated yaw, the two half extents, and the deck height.
    #[func]
    fn set_decks(&self, data: PackedFloat32Array) {
        world::set_decks(data.as_slice());
    }

    /// Every queued leaf in one call.
    ///
    /// `jobs` is a flat run of eight numbers a chunk -- depth, the two grid
    /// indices, what each of the four edges meets, and the finer-neighbour bits
    /// -- and what comes back is five entries a chunk in the same order, the
    /// same five `chunk_build` hands back for one.
    ///
    /// One call because the engine's worker pool was not parallelising these:
    /// three hundred and forty chunks measure 95 ms built one after another on
    /// a single thread, and took about 120 ms of wall clock spread over eight
    /// of the pool's. Here the arithmetic goes out across the cores and only
    /// the marshalling is left on the calling thread.
    #[func]
    fn chunk_build_many(&self, jobs: PackedInt32Array) -> Array<Variant> {
        let src = jobs.as_slice();
        // Gathered once for the whole batch rather than once a chunk: it is a
        // lock and a list read, and three hundred threads taking it to learn
        // the same answer is contention for nothing.
        let g = world::Ground::now();
        let built: Vec<chunk::Chunk> = src
            .par_chunks_exact(8)
            .map(|q| {
                chunk::build(&g, q[0], q[1], q[2], [q[3], q[4], q[5], q[6]],
                    q[7] as u32)
            })
            .collect();
        let mut out: Array<Variant> = Array::new();
        for c in &built {
            push_chunk(&mut out, c);
        }
        out
    }

    /// One leaf of the terrain quadtree, meshed.
    ///
    /// Everything from the height field to the vertex arrays: the grid, the
    /// edges conformed to a coarser neighbour, the morph target the level above
    /// draws, both sets of normals and the skirt. This was a four hundred line
    /// loop in script running on a worker, and it was the largest single item
    /// in world generation.
    ///
    /// Comes back as the script left it: vertices, normals, the seam the
    /// stitching left, the morph, and the coarse normal as a tangent array.
    #[func]
    fn chunk_build(&self, depth: i64, ix: i64, iz: i64, nb: PackedInt32Array,
            fine: i64) -> Array<Variant> {
        let n = nb.as_slice();
        let nbs = [
            n.first().copied().unwrap_or(0),
            n.get(1).copied().unwrap_or(0),
            n.get(2).copied().unwrap_or(0),
            n.get(3).copied().unwrap_or(0),
        ];
        let c = chunk::build(&world::Ground::now(), depth as i32, ix as i32,
            iz as i32, nbs, fine as u32);
        let mut out: Array<Variant> = Array::new();
        push_chunk(&mut out, &c);
        out
    }

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

    /// Which ground is the ground the aerodrome stands on, as one byte a cell:
    /// the grid thresholded against the sea under each point, then flood filled
    /// from the middle. Empty when the middle is not on land at all.
    #[func]
    fn landmass(&self, half: f64, n: i64) -> PackedByteArray {
        PackedByteArray::from(
            world::landmass(half as f32, n.max(1) as usize).as_slice())
    }

    /// Is there ground in the way, for each of a list of sight lines?
    ///
    /// One byte a line. The head-up display's radar scope asks this of every
    /// contact on it, every frame -- a contact behind a ridge is not a return,
    /// and painting it and then refusing to lock it is worse than not painting
    /// it -- and each ask is up to forty-eight height queries. Fourteen
    /// aircraft in a fight is seven hundred crossings of the boundary a frame,
    /// and measured that panel alone was 1.0 ms of a 13 ms frame.
    #[func]
    fn sight_lines(&self, from: PackedVector3Array, to: PackedVector3Array,
            skip: f64) -> PackedByteArray {
        let g = world::Ground::now();
        let a = from.as_slice();
        let b = to.as_slice();
        let n = a.len().min(b.len());
        let mut out = vec![0u8; n];
        out.par_iter_mut().enumerate().for_each(|(k, v)| {
            *v = world::line_of_sight(&g, [a[k].x, a[k].y, a[k].z],
                [b[k].x, b[k].y, b[k].z], skip) as u8;
        });
        PackedByteArray::from(out.as_slice())
    }

    /// The ground under a set of wheels: five numbers each -- the height, the
    /// three of the ground normal, and the grip -- in the order they came in.
    ///
    /// A tank has fourteen road wheels and every one of them used to ask for
    /// itself: a height, four more for the normal and one for the surface, so
    /// eighty-four crossings of this boundary per vehicle per physics step. A
    /// sector's garrison on the move is forty-five vehicles at 120 Hz, and
    /// measured that was 87 ms of a hundred millisecond frame -- a frame the
    /// physics then needs twelve steps to catch up on, which makes the next one
    /// worse. The suspension is the same arithmetic either way; this is only
    /// where the asking happens.
    ///
    /// A wheel in the air gets its height and nothing else, which is the short
    /// circuit the script already made: without a contact there is no normal to
    /// stand on and no surface to grip.
    ///
    /// Deliberately serial. The work is fourteen points and the answer is
    /// wanted inside the physics step that asked for it; handing that to a
    /// thread pool costs more to dispatch than the arithmetic costs to do.
    #[func]
    fn wheel_ground(&self, pts: PackedVector3Array, radii: PackedFloat64Array)
            -> PackedFloat64Array {
        const E: f32 = 3.0;
        let g = world::Ground::now();
        let p = pts.as_slice();
        let r = radii.as_slice();
        let mut out = vec![0f64; p.len() * 5];
        for (k, w) in p.iter().enumerate() {
            let h = g.height(w.x, w.z);
            out[k * 5] = h;
            if h + r.get(k).copied().unwrap_or(0.0) <= w.y as f64 {
                continue;
            }
            // `Sim.normal_at`: the field's gradient over six metres, narrowed
            // into a `Vector3` and normalised there, because that is what the
            // script does with it.
            let dx = (g.height(w.x - E, w.z) - g.height(w.x + E, w.z)) as f32;
            let dz = (g.height(w.x, w.z - E) - g.height(w.x, w.z + E)) as f32;
            let dy = 2.0 * E;
            let len = (dx * dx + dy * dy + dz * dz).sqrt();
            let inv = if len > 0.0 { 1.0 / len } else { 0.0 };
            out[k * 5 + 1] = (dx * inv) as f64;
            out[k * 5 + 2] = (dy * inv) as f64;
            out[k * 5 + 3] = (dz * inv) as f64;
            out[k * 5 + 4] = g.grip(w.x, w.z) as f64;
        }
        PackedFloat64Array::from(out.as_slice())
    }

    /// The nearest point on any of a set of lines, for each of a set of points.
    ///
    /// `lines` is a flat run of ax, az, bx, bz. Which trunk road a town's own
    /// street runs out to meet is this question, asked once per town against
    /// the whole network -- twenty-nine thousand legs times forty-eight towns,
    /// a million and a half segment tests, and in script that was 156 ms of
    /// every launch whether the network came off disk or not.
    ///
    /// Worked out the way the script did, down to which parts are single and
    /// which double: a `Vector2` holds singles and `maxf` is a double, so the
    /// projection divides in double and narrows once. These land the end of a
    /// street, and a street is drawn where its end is.
    #[func]
    fn nearest_on_lines(&self, lines: PackedFloat32Array, pts: PackedVector2Array)
            -> PackedVector2Array {
        let lines = lines.as_slice();
        let src = pts.as_slice();
        let mut out = vec![Vector2::ZERO; src.len()];
        out.par_iter_mut().enumerate().for_each(|(k, v)| {
            let p = src[k];
            let mut best = f32::INFINITY;
            *v = p;
            for l in lines.chunks_exact(4) {
                let (abx, abz) = (l[2] - l[0], l[3] - l[1]);
                let dot = (p.x - l[0]) * abx + (p.y - l[1]) * abz;
                let len2 = abx * abx + abz * abz;
                let t = ((dot as f64) / (len2 as f64).max(0.001)).clamp(0.0, 1.0)
                    as f32;
                let q = Vector2::new(l[0] + abx * t, l[1] + abz * t);
                let d = (p - q).length();
                if d < best {
                    best = d;
                    *v = q;
                }
            }
        });
        PackedVector2Array::from(out.as_slice())
    }

    /// How rough the ground is over a disc, for every site being considered.
    ///
    /// The mean of `1 - normal.y` over a seven by seven grid inside the circle:
    /// what a town is chosen by. Asked for a point at a time it is 49 normals,
    /// each of them four heights, each of those its own crossing of the
    /// extension boundary -- 196 crossings a candidate, and siting the world's
    /// forty-eight settlements tries forty-nine candidates apiece. That is four
    /// hundred and sixty thousand crossings, and measured it was 550 ms of a
    /// four second cold start: the largest single thing in laying out the road
    /// network, and none of it arithmetic that had to be done in script.
    ///
    /// The rule is unchanged, down to the order the sum is accumulated in --
    /// this picks *where a town goes*, and a different rounding puts it
    /// somewhere else.
    #[func]
    fn roughness_at(&self, centres: PackedVector2Array, radii: PackedFloat64Array)
            -> PackedFloat64Array {
        let g = world::Ground::now();
        let c = centres.as_slice();
        let r = radii.as_slice();
        let mut out = vec![0f64; c.len()];
        out.par_iter_mut().enumerate().for_each(|(k, v)| {
            *v = world::roughness(&g, [c[k].x, c[k].y], *r.get(k).unwrap_or(&1.0));
        });
        PackedFloat64Array::from(out.as_slice())
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
        // In the frame the game measures heights in -- what `Sim.height_at`
        // answers, drop and all. It used to answer in the flat field's own
        // frame and leave every caller to take the drop off afterwards, which
        // is a footgun with two callers and would have been a bug with three:
        // the drop belongs under the interpolation, not over it.
        let g = world::Ground::now();
        let cell = cell as f32;
        let src: Vec<Vector2> = pts.as_slice().to_vec();
        let out: Vec<f32> = src
            .par_iter()
            .map(|p| {
                let x0 = (p.x / cell).floor() * cell;
                let z0 = (p.y / cell).floor() * cell;
                let tx = (p.x - x0) / cell;
                let tz = (p.y - z0) / cell;
                let h00 = g.world_y(x0, z0);
                let h10 = g.world_y(x0 + cell, z0);
                let h11 = g.world_y(x0 + cell, z0 + cell);
                let h01 = g.world_y(x0, z0 + cell);
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
        index::publish_segments(data.as_slice(), 256.0);
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
        match index::segments() {
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
        let out: Vec<f32> = match index::segments() {
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
        for (line, (a, b)) in done.into_iter().zip(jobs.iter()) {
            // A leg that walks several times the distance between its own ends
            // is not a road anybody would build.
            //
            // The router will always find *a* way round, and where the way
            // round is an airfield's approach keep-out or the far bank of a
            // firth, what it finds is a route that leaves a place, goes eight
            // kilometres past where it was going, and comes back -- which is
            // the looping this was reported for. The same judgement is already
            // made about water: past `MAX_CROSSING` the leg is abandoned "and
            // the network is left to find another way round, or to leave that
            // place unconnected, which is the truth about it". Two places you
            // cannot get between in less than four times the distance are not
            // neighbours, and the network reaches them another way.
            let direct = ((a.0 - b.0).powi(2) + (a.1 - b.1).powi(2)).sqrt();
            let mut walked = 0.0f32;
            for pair in line.windows(2) {
                walked += ((pair[1].0 - pair[0].0).powi(2)
                    + (pair[1].1 - pair[0].1).powi(2)).sqrt();
            }
            if direct > 2000.0 && walked > direct * ROUTE_DETOUR {
                out.push(&PackedVector2Array::new());
                continue;
            }
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

    /// The same picture on the planet: sampled on the direction, so a place
    /// keeps its climate when the chart moves off it.
    #[func]
    fn climate_map_globe(&self, n: i64, half: f64) -> PackedByteArray {
        let c = sphere::chart();
        PackedByteArray::from(
            sphere::climate_globe(&c, n.max(1) as usize, half as f32).as_slice())
    }

    /// The same, off the main thread. The ground keeps the climate it has until
    /// this lands, which after a chart move is a few frames of colour drawn for
    /// the country next door rather than half a second of nothing at all.
    #[func]
    fn climate_request(&self, n: i64, half: f64) -> bool {
        let c = sphere::chart();
        let n = n.max(1) as usize;
        let half = half as f32;
        bake_start(&CLIMATE, move || sphere::climate_globe(&c, n, half))
    }

    #[func]
    fn climate_ready(&self) -> bool {
        bake_ready(&CLIMATE)
    }

    #[func]
    fn climate_take(&self) -> PackedByteArray {
        PackedByteArray::from(bake_take(&CLIMATE).as_slice())
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

    /// The same ribbons, cut into square buckets so the frustum can drop them.
    ///
    /// `road_ribbons` returns the whole network as two meshes, and a mesh is
    /// culled as one object: any part of the road network on screen submits all
    /// of it. Measured, those two meshes cost 4.15 ms of the 6.20 ms the frame
    /// spends drawing -- two thirds of it, for two objects out of eighteen
    /// hundred, most of which is behind the camera or over the horizon.
    ///
    /// Cut here rather than in GDScript because a packed array taken out of a
    /// dictionary and put back is copied both ways, so bucketing a million
    /// triangles a triangle at a time is quadratic.
    ///
    #[func]
    fn road_ribbons_bucketed(&self, legs: PackedFloat32Array, cell: f64)
            -> Array<Variant> {
        type Cells = index::Map<i64, (Vec<Vector3>, Vec<Vector3>)>;
        let parts = raster::ribbon_parts(legs.as_slice());
        let cell = (cell as f32).max(1.0);
        // Sorted straight out of the per-leg ribbons, across every core.
        //
        // Joined into one pair of lists first and then sorted -- which is what
        // this did -- a million triangles are copied twice over on one thread
        // before any of them reaches a bucket. Each core sorts a run of legs
        // into a map of its own and the maps are merged in order afterwards, so
        // the answer does not depend on which core finished first.
        let sort = |src: &[[f32; 3]], kerb: bool, b: &mut Cells| {
            for tri in src.chunks_exact(3) {
                let cx = (tri[0][0] + tri[1][0] + tri[2][0]) / 3.0;
                let cz = (tri[0][2] + tri[1][2] + tri[2][2]) / 3.0;
                // Keyed on the triangle's own centre, so a triangle belongs to
                // one bucket and no seam can open between two.
                let key = index::key((cx / cell).floor() as i32,
                    (cz / cell).floor() as i32);
                let e = b.entry(key).or_default();
                let dst = if kerb { &mut e.1 } else { &mut e.0 };
                for q in tri {
                    dst.push(Vector3::new(q[0], q[1], q[2]));
                }
            }
        };
        let runs: Vec<Cells> = parts
            .par_chunks(256)
            .map(|run| {
                let mut b = Cells::default();
                for r in run {
                    sort(&r.surf, false, &mut b);
                    sort(&r.kerb, true, &mut b);
                }
                b
            })
            .collect();
        let mut buckets = Cells::default();
        for run in runs {
            for (k, (surf, kerb)) in run {
                let e = buckets.entry(k).or_default();
                e.0.extend_from_slice(&surf);
                e.1.extend_from_slice(&kerb);
            }
        }
        // Comes back flat: cell x, cell z, surface, kerb, for each non-empty
        // cell. In a settled order, because the meshes are named after the
        // cell and a harness finds them by name.
        let mut keys: Vec<i64> = buckets.keys().copied().collect();
        keys.sort_unstable();
        let mut out: Array<Variant> = Array::new();
        for k in keys {
            let (surf, kerb) = &buckets[&k];
            out.push(&((k >> 32) as i32 as i64).to_variant());
            out.push(&((k & 0xffff_ffff) as u32 as i32 as i64).to_variant());
            out.push(&PackedVector3Array::from(surf.as_slice()).to_variant());
            out.push(&PackedVector3Array::from(kerb.as_slice()).to_variant());
        }
        out
    }

    /// The tactical map's background: hill-shaded relief in biome colour with
    /// the road network over it, as RGB8.
    #[func]
    fn map_relief(&self, n: i64, half: f64) -> PackedByteArray {
        static EMPTY: std::sync::OnceLock<index::SegGrid> =
            std::sync::OnceLock::new();
        let segs = index::segments()
            .unwrap_or_else(|| EMPTY.get_or_init(|| index::SegGrid::build(&[], 256.0)));
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
