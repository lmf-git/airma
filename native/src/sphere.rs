//! The planet's height field.
//!
//! The world this game grew up on is a function of `(x, z)` on a plane. A planet
//! cannot be: a plane has edges and a sphere does not, and every scheme for
//! papering one onto the other either seams at the joins or pinches at the
//! poles. So this is the same *character* of ground written as a function of a
//! **direction from the planet's centre**. A function of a direction has nowhere
//! to seam, nothing to wrap and no poles to pinch, and it is unique everywhere.
//!
//! What people have built is carved into it rather than blended over it. The
//! aerodrome, the roads and the town platforms are not terrain -- they are what
//! is done to terrain once somebody lives on it -- and they apply to a planetary
//! field exactly as they applied to a flat one.
//!
//! Callers still ask in `(x, z)`. That pair now means metres east and metres
//! south of wherever the chart is centred, and the conversion to a direction
//! happens here, once per entry point, so the thousands of call sites in the
//! game above do not have to know the world is round.

use crate::field::{lerp, smoothstep};
use crate::world::{carve, corridor, world};
use fastnoise_lite::{FastNoiseLite, FractalType, NoiseType};
use rayon::prelude::*;
use std::sync::atomic::{AtomicPtr, Ordering};
use std::sync::OnceLock;

/// Where the flat pair is measured from, and how big the planet is.
#[derive(Clone, Copy)]
pub struct Chart {
    pub origin: [f32; 3],
    pub east: [f32; 3],
    pub south: [f32; 3],
    pub radius: f32,
}

impl Default for Chart {
    fn default() -> Self {
        // The chart the flat world was always drawn on.
        Chart {
            origin: [0.0, 1.0, 0.0],
            east: [1.0, 0.0, 0.0],
            south: [0.0, 0.0, 1.0],
            radius: 6_371_000.0,
        }
    }
}

/// Published as a pointer rather than held behind a lock.
///
/// A read lock is still a write to a shared cache line, and this is read once
/// per height sample -- four million times over a map sheet, from every core at
/// once. The chart moves perhaps twice in a sortie, so the new one is put
/// somewhere fresh and the pointer swung at it; readers only load. The old
/// chart is leaked, which costs forty bytes a move and lets a reader that is
/// mid-sample keep the one it has.
static CHART: AtomicPtr<Chart> = AtomicPtr::new(std::ptr::null_mut());

pub fn set_chart(origin: [f32; 3], east: [f32; 3], south: [f32; 3], radius: f32) {
    let c = Chart {
        origin: norm(origin),
        east: norm(east),
        south: norm(south),
        radius,
    };
    CHART.store(Box::into_raw(Box::new(c)), Ordering::Release);
}

/// Read once per entry point where it can be: this is a hot path, and even a
/// pointer load is worth hoisting out of a four million texel loop.
pub fn chart() -> Chart {
    let p = CHART.load(Ordering::Acquire);
    if p.is_null() {
        return Chart::default();
    }
    // Sound: every chart ever published is leaked and never mutated.
    unsafe { *p }
}

#[inline]
fn norm(v: [f32; 3]) -> [f32; 3] {
    let l = (v[0] * v[0] + v[1] * v[1] + v[2] * v[2]).sqrt();
    if l < 1e-20 {
        return [0.0, 1.0, 0.0];
    }
    [v[0] / l, v[1] / l, v[2] / l]
}

/// Chart coordinates to a direction. Azimuthal equidistant about the origin, so
/// distance along the ground from the middle of the chart is exact -- which is
/// what every range readout and weapon envelope in the game above assumes.
#[inline]
pub fn dir_from_chart(c: &Chart, x: f32, z: f32) -> [f32; 3] {
    let s = (x * x + z * z).sqrt();
    if s < 1e-6 {
        return c.origin;
    }
    let ang = s / c.radius;
    let (sa, ca) = ang.sin_cos();
    let tx = x / s;
    let tz = z / s;
    norm([
        c.origin[0] * ca + (c.east[0] * tx + c.south[0] * tz) * sa,
        c.origin[1] * ca + (c.east[1] * tx + c.south[1] * tz) * sa,
        c.origin[2] * ca + (c.east[2] * tx + c.south[2] * tz) * sa,
    ])
}

// ------------------------------------------------------------- the generator

fn mk3(seed: i32, freq: f32, oct: i32, ft: FractalType) -> FastNoiseLite {
    let mut n = FastNoiseLite::with_seed(seed);
    n.set_noise_type(Some(NoiseType::OpenSimplex2));
    n.set_fractal_type(Some(ft));
    n.set_frequency(Some(freq));
    n.set_fractal_octaves(Some(oct));
    n
}

struct Planet {
    cont: FastNoiseLite,
    // The same continental field with its detail left off: the shape of the
    // landmass rather than the shape of its coastline. Low near the margins
    // and high in the interior, which is the one honest measure this planet
    // has of how far inside a continent a point is.
    cont1: FastNoiseLite,
    mount: FastNoiseLite,
    // The land's own relief, and the grain over it. Both are read in *metres
    // over the surface* rather than in radians over the unit ball -- see
    // `generated` -- so their frequencies are the flat world's own and do not
    // scale with the radius.
    hills: FastNoiseLite,
    detail: FastNoiseLite,
    warp: FastNoiseLite,
    moist: FastNoiseLite,
    // The climate pair, on the sphere. Sampled on the chart pair they slide
    // under the ground every time the chart moves: the same field would be
    // temperate in one sortie and arid in the next because the player had flown
    // a hundred and fifty kilometres. Frequencies chosen so a feature is about
    // the 160 km the flat fields drew.
    ctemp: FastNoiseLite,
    cmoist: FastNoiseLite,
    // The drainage. Two channel systems rather than one, so they cross and
    // meet: a single field gives a planet of parallel rivers that never join.
    river: FastNoiseLite,
    river2: FastNoiseLite,
    // Which stretches of coast are drowned ones.
    ria: FastNoiseLite,
    // The radius the metre-space fields are read against, settled once with
    // the rest of the generator rather than looked up per sample.
    surf: f32,
}

static PLANET: OnceLock<Planet> = OnceLock::new();

/// Frequencies are quoted against a reference planet and scaled from there, in
/// two different ways.
///
/// Mountains and roughness scale with the radius, so the ground keeps its
/// character whatever size the planet is. Continents and climate scale with the
/// *square root*, so a bigger planet gets bigger landmasses rather than the same
/// landmasses many more times over.
///
/// Leaving the scaling out is not a subtle error. Quoted raw on a planet twice
/// the reference radius, the continents came out at nearly twice the frequency:
/// half the world turned to land and it broke into a scatter of small islands
/// instead of a handful of continents.
const REF_RADIUS: f32 = 3_000_000.0;

fn planet() -> &'static Planet {
    PLANET.get_or_init(|| {
        let ts = REF_RADIUS / chart().radius.max(1.0);
        let cs = ts.sqrt();
        Planet {
            cont: mk3(20260903, 0.85 * cs, 5, FractalType::FBm),
            // Same seed and frequency as `cont`, with the top two octaves
            // left off: this has to be `cont` without its detail and not an
            // independent field, or the plains it draws would have nothing to
            // do with where the coasts are. Three octaves rather than one
            // because the field's gradient is what sets how wide a coastal
            // plain comes out -- one octave of a 7500 km feature ramps over a
            // thousand kilometres, and a thousand kilometre plain is the whole
            // country.
            cont1: mk3(20260903, 0.85 * cs, 3, FractalType::FBm),
            mount: mk3(20260904, 2.6 * ts, 5, FractalType::Ridged),
            // Relief below the range scale, which this planet had none of.
            //
            // `mount` is a ridged field at 5200 km over five octaves, so the
            // finest thing in it is three hundred kilometres across, and the
            // old detail field was 1800 km over four, so the finest thing in
            // *that* was two hundred and twenty-five. Between those and the
            // rivers at twenty-five kilometres there was nothing whatever --
            // so the ground a sortie actually flies over was a smooth ramp
            // with channels cut in it, which is exactly what it looked like.
            //
            // These two are read in metres over the surface, so they carry the
            // flat world's own spectrum: hills from a hundred and thirty
            // kilometres down to eight, and grain from four kilometres down to
            // five hundred metres. With `mount` above them the land now has
            // something at every scale it can be seen at.
            hills: mk3(20260907, 0.0000075, 5, FractalType::FBm),
            detail: mk3(20260905, 0.00025, 4, FractalType::FBm),
            // One octave. This is a distortion, not a field anybody looks at:
            // the second octave of it went into three lookups a sample once
            // the warp was done properly, and what it bought was detail in
            // something whose whole job is to be smooth.
            warp: mk3(20260906, 1.9 * cs, 1, FractalType::FBm),
            moist: mk3(20260908, 1.3 * cs, 3, FractalType::FBm),
            ctemp: mk3(515, 40.0, 2, FractalType::FBm),
            cmoist: mk3(811, 29.0, 3, FractalType::FBm),
            // A drainage every eighty kilometres in one system and every
            // hundred and twenty in the other.
            //
            // It used to be every twenty-five from each. Measured along a
            // great circle, sixty per cent of the land was inside a river
            // valley and fifty-five per cent of it had a channel cut through
            // it: the planet was not land with rivers on it, it was corduroy,
            // and the two systems crossing read at map scale as a swirl.
            // Three octaves rather than two, so that what is left meanders.
            river: mk3(20260910, 66.0 * ts, 3, FractalType::FBm),
            river2: mk3(20260911, 50.0 * ts, 3, FractalType::FBm),
            // Features about two hundred kilometres across, so a drowned
            // coast is a region of the map rather than one river or a whole
            // continent.
            ria: mk3(20260912, 34.0 * ts, 2, FractalType::FBm),
            surf: chart().radius.max(1.0),
        }
    })
}

/// The frame the planet's geography is written in: north, the prime meridian,
/// and east off it. Written out once because it was written out three times --
/// in `homeland`, in `sheet_dir` and again on the GDScript side, where one copy
/// had north's sign the other way round. Six countries came out at the mirror
/// of their own latitudes and three of them were under the sea.
pub const HOME: [f32; 3] = [0.0, 1.0, 0.0];
/// The planet's north. Mirrors `Sim.PLANET_NORTH`.
pub const NORTH: [f32; 3] = [0.0, 0.0, -1.0];

/// A direction from a latitude and longitude in radians, in that frame.
pub fn at_lat_lon(lat: f32, lon: f32, north: [f32; 3]) -> [f32; 3] {
    let east = norm(cross(north, HOME));
    let (sla, cla) = lat.sin_cos();
    let (slo, clo) = lon.sin_cos();
    norm([
        north[0] * sla + (HOME[0] * clo + east[0] * slo) * cla,
        north[1] * sla + (HOME[1] * clo + east[1] * slo) * cla,
        north[2] * sla + (HOME[2] * clo + east[2] * slo) * cla,
    ])
}

/// Where the countries are.
///
/// Found, not written down, and found on the terrain as it is.
///
/// They used to be six latitudes and longitudes inside twenty degrees of each
/// other, with a bias in the continental field raising land under every one of
/// them so there would be ground there at all. That bias is why a country did
/// not look like the rest of the planet: it lifted the field toward land over a
/// radially symmetric patch and damped the mountains inside it, so each one was
/// a suspiciously round, suspiciously gentle place in an ocean that had not
/// been asked about -- and the aerodromes and roads were then carved into
/// terrain that had already been flattened for them.
///
/// So: no bias, one terrain rule for the whole planet, and the countries put
/// where the planet already has somewhere to put them. The search wants solid
/// land with room around it and ground a road survey can work in, and it wants
/// the six of them spread out.
static HOMELANDS: OnceLock<[[f32; 3]; 6]> = OnceLock::new();

/// How many places on the planet are looked at. A Fibonacci sphere, so they are
/// evenly spread with no pole and no seam; at this count they are about a
/// hundred and thirty kilometres apart, which is finer than what is being
/// looked for.
const HOME_SAMPLES: usize = 24000;
/// How far a country's surroundings are judged over.
const HOME_RINGS: [f32; 2] = [140_000.0, 300_000.0];

/// The six of them, worked out once.
pub fn homelands() -> &'static [[f32; 3]; 6] {
    HOMELANDS.get_or_init(|| {
        let n = HOME_SAMPLES;
        // The planet's own radius, read once: `REF_RADIUS` is what the noise
        // frequencies are scaled against and is not this.
        let radius = chart().radius.max(1.0);
        // Every candidate scored on how much of its surroundings is dry and how
        // rough that ground is. A country wants a landmass rather than an
        // island, and it wants ground a road can be built in -- the alternative
        // to damping the mountains under a country is not putting the country
        // in the mountains.
        let ga = std::f32::consts::PI * (3.0 - 5.0f32.sqrt());
        let scored: Vec<(f32, [f32; 3])> = (0..n)
            .into_par_iter()
            .map(|i| {
                let y = 1.0 - 2.0 * (i as f32 + 0.5) / n as f32;
                let r = (1.0 - y * y).max(0.0).sqrt();
                let th = ga * i as f32;
                let d = norm([r * th.cos(), y, r * th.sin()]);
                let here = generated(d);
                if here < 40.0 {
                    return (-1e9, d);
                }
                let a = norm(cross(d, if d[1].abs() < 0.9 {
                    [0.0, 1.0, 0.0]
                } else {
                    [1.0, 0.0, 0.0]
                }));
                let b = norm(cross(d, a));
                let mut dry = 0;
                let mut total = 0;
                let mut lo = here;
                let mut hi = here;
                for ring in HOME_RINGS {
                    let ang = ring / radius;
                    let (sa, ca) = ang.sin_cos();
                    for k in 0..12 {
                        let t = std::f32::consts::TAU * k as f32 / 12.0;
                        let (st, ct) = t.sin_cos();
                        let q = norm([
                            d[0] * ca + (a[0] * ct + b[0] * st) * sa,
                            d[1] * ca + (a[1] * ct + b[1] * st) * sa,
                            d[2] * ca + (a[2] * ct + b[2] * st) * sa,
                        ]);
                        let h = generated(q);
                        total += 1;
                        if h > 0.0 {
                            dry += 1;
                        }
                        lo = lo.min(h);
                        hi = hi.max(h);
                    }
                }
                let land = dry as f32 / total.max(1) as f32;
                // Land first, then flat. The relief term is the range over
                // three hundred kilometres, which is what a road survey has to
                // cope with; two kilometres of it is alpine.
                let relief = (hi - lo).max(0.0);
                let score = land * 3.0 - (relief / 2200.0).min(2.4)
                    - (here / 2600.0).min(1.2);
                (score, d)
            })
            .collect();
        let mut order: Vec<usize> = (0..n).collect();
        order.sort_by(|&a, &b| scored[b].0.total_cmp(&scored[a].0));
        // Greedy, best first, with a minimum separation so they end up on
        // different parts of the planet rather than six abreast on one
        // continent. The separation is relaxed until six fit, because how far
        // apart six good places can be is a fact about the terrain rather than
        // something to insist on.
        for sep_deg in [80.0f32, 70.0, 60.0, 50.0, 40.0, 30.0, 20.0, 10.0] {
            let cos_sep = sep_deg.to_radians().cos();
            let mut picked: Vec<[f32; 3]> = Vec::new();
            for &idx in &order {
                let (sc, d) = scored[idx];
                if sc < -1e8 {
                    break;
                }
                if picked.iter().any(|p| dot(*p, d) > cos_sep) {
                    continue;
                }
                picked.push(d);
                if picked.len() == 6 {
                    break;
                }
            }
            if picked.len() == 6 {
                return [picked[0], picked[1], picked[2], picked[3],
                    picked[4], picked[5]];
            }
        }
        // Nowhere at all, which would be a planet with no land on it. Six
        // points spread over it, so the game still has somewhere to be.
        let mut out = [[0.0f32; 3]; 6];
        for (k, o) in out.iter_mut().enumerate() {
            *o = at_lat_lon((k as f32 * 29.0 - 40.0).to_radians(),
                (k as f32 * 60.0).to_radians(), NORTH);
        }
        out
    })
}

/// A country's direction from the planet's centre.
pub fn homeland(i: usize) -> [f32; 3] {
    homelands()[i.min(5)]
}

pub const RELIEF: f32 = 5200.0;
pub const OCEAN: f32 = 4600.0;

/// Height above sea level for a direction, in metres, before anything built.
pub fn generated(d: [f32; 3]) -> f32 {
    let p = planet();
    // The continental warp: three decorrelated samples, not one.
    //
    // This used to take a single scalar and add it to all three axes at once,
    // which is not a domain warp at all -- it displaces every point along the
    // same fixed direction and only varies how far. What that draws is a
    // shear: coastlines and sea floor smeared along one axis of the planet,
    // read on the orbital view as swirls that all lean the same way. Offsetting
    // the field three different ways costs two more lookups and displaces each
    // point somewhere of its own.
    //
    // And by less. A fifth of a radian is thirteen hundred kilometres -- wider
    // than the feature it is warping, so the field was not being distorted so
    // much as stirred.
    const WA: f32 = 0.11;
    let (wx, wy, wz) = (d[0] * 1.7, d[1] * 1.7, d[2] * 1.7);
    let w = [
        p.warp.get_noise_3d(wx, wy, wz) * WA,
        p.warp.get_noise_3d(wy + 31.0, wz - 17.0, wx + 5.0) * WA,
        p.warp.get_noise_3d(wz + 71.0, wx + 43.0, wy - 61.0) * WA,
    ];
    let q = norm([d[0] + w[0], d[1] + w[1], d[2] + w[2]]);
    let c = p.cont.get_noise_3d(q[0], q[1], q[2]);
    // Where this point is in metres over the surface, for the relief fields.
    //
    // A unit direction times the radius. Noise read in radians cannot go below
    // about a couple of hundred kilometres before the frequency it needs runs
    // the lattice coordinate past what a single can hold; read in metres the
    // coordinate is the same magnitude the flat world's always was, and the
    // flat world draws ground down to a few hundred metres with it. The warp
    // is deliberately not applied here: it is a continental distortion, and
    // dragging the fine grain through it by a thousand kilometres would smear
    // exactly the detail this is for.
    let pm = [d[0] * p.surf, d[1] * p.surf, d[2] * p.surf];
    // One rule, everywhere.
    //
    // There used to be a bias here: a lift toward land wherever one of the six
    // countries was, so that the aerodrome, the roads and the towns laid out on
    // the chart had ground under them. It worked and it looked exactly like
    // what it was -- a radially symmetric patch of raised, damped terrain that
    // did not match the planet round it, with the works then carved into ground
    // that had already been flattened for them. The countries are searched for
    // on the terrain instead (see `homelands`), so nothing here needs to know
    // where they are.
    let land = smoothstep(-0.20, 0.06, c);
    let mut h = -OCEAN * (1.0 - land) * (0.35 + 0.65 * (1.0 - land));
    if land < 1.0 {
        // The sea floor is not a table: ridges and basins are what make one
        // piece of deep ocean a different place from another. Swells, though,
        // not ridges -- `mount` is a ridged field, and a ridged field is
        // filaments. Taken at nine hundred metres under an ocean whose colour
        // ramps over four and a half kilometres it painted the whole sea floor
        // with pale threads, which from orbit was the one thing the planet was
        // covered in. The continental field at its own scale gives deep and
        // shallow without drawing a web over it.
        let fl = p.cont.get_noise_3d(q[0] * 2.3, q[1] * 2.3, q[2] * 2.3);
        let fd = p.hills.get_noise_3d(pm[0] * 0.7, pm[1] * 0.7, pm[2] * 0.7);
        h += (1.0 - land) * (fl * 900.0 + fd * 420.0);
    }
    if land > 0.0 {
        let m = p.mount.get_noise_3d(q[0], q[1], q[2]).abs();
        let hill = p.hills.get_noise_3d(pm[0], pm[1], pm[2]);
        // Ranges inland, where the continent is thickest, and low coasts.
        let mass = ((c + 0.12) / 0.5).clamp(0.0, 1.0);
        // The mountains are left where the generator puts them.
        //
        // This used to be damped by the same bias, so the country you were
        // flying from was rolling and the alpine ground began wherever nobody
        // had built anything -- which is a flattened patch by another name. A
        // road survey still cannot build in five kilometres of ridged relief;
        // the answer is to put the country somewhere the planet is already
        // gentle, which is what `homelands` searches for.
        //
        // How mountainous this stretch of continent is: nothing on a margin,
        // everything in the middle of a range. One number, so the relief
        // beneath it can be weighted by the same thing the ranges are.
        let belt = (0.10 + 0.90 * mass * mass) * m;
        // The ranges, then the country between them, then the grain on that.
        //
        // The middle term is what the planet was missing. `belt` varies over
        // three hundred kilometres at its finest, so on its own the land is a
        // ramp two hundred kilometres long however high it gets -- you can fly
        // a sortie across it and never see the ground change. `hill` runs from
        // a hundred and thirty kilometres down to eight, which is the band a
        // valley, a ridge and a saddle live in, and it is scaled by the belt
        // so that lowland rolls by a hundred metres and an alpine stretch
        // throws up a kilometre of it.
        let mut lh = RELIEF * belt * 0.82
            + (300.0 + RELIEF * belt * 0.55) * hill
            + 210.0;
        // And the grain over that: a few metres on a plain, a few tens on a
        // hillside, the same weighting the flat world gives its own detail.
        lh += p.detail.get_noise_3d(pm[0], pm[1], pm[2]) * (14.0 + 120.0 * m);
        // Coastal plains.
        //
        // Measured, this planet went from the shore to a 410 m tableland in
        // twenty kilometres and then stayed there for the next hundred and
        // forty. Real coasts do the opposite: low country for a long way in,
        // then the ground gets up. That is not a detail of the scenery -- it
        // is why rivers are navigable a long way inland, and with a twenty
        // kilometre ramp a boat got three kilometres up one.
        //
        // Scaled by how far inside the landmass a point is, so the hills are
        // inland and the flat country is by the sea, which is where flat
        // country is.
        let inner = p.cont1.get_noise_3d(q[0], q[1], q[2]);
        let plain = smoothstep(-0.02, 0.16, inner);
        lh *= 0.18 + 0.82 * plain;
        // And a floor under the lot of it.
        //
        // Land ought to be above the water and is not: what is left of the sum
        // above is a ridged field plus a signed one, and where the ridge is
        // quiet and the signed field negative it comes out below sea level.
        // Four of the six countries came out drowned that way, one with its
        // aerodrome 136 m under, on ground the continent field called land.
        //
        // Bounded *here* rather than on the total, because on the total it
        // lifts the ocean: a point whose land weight is a thousandth is 4600 m
        // down, and a floor applied to the sum brings it to the surface --
        // forty-seven per cent of the planet turned to land that way. The
        // land's own shape is what is bounded; the shore still fades into deep
        // water on the weight.
        //
        // And by a softplus, not by a maximum. A hard floor is a crease -- a
        // first-derivative discontinuity along every contour it bites on -- and
        // the road survey, the river carving and the aerodrome levelling all
        // broke on it. A soft maximum is smooth and is not a bound: it dips
        // below its own floor by half the smoothing width, which put the
        // countries straight back under. This is above the floor for every
        // input and tends to the height itself once clear of it.
        let floor = 30.0f32;
        let k = 60.0f32;
        let dh = lh - floor;
        if dh / k <= 18.0 {
            lh = floor + k * (1.0 + (dh / k).exp()).ln();
        }
        h += land * lh;
        // Rivers, once the land they run over exists.
        //
        // The flat world drew these against a coastline at a fixed `x`, with a
        // navigable bed that rose with distance from it. A planet has no such
        // line: the coast is wherever the ocean happens to be, and it is
        // somewhere different on every continent. What stands in for "how far
        // inland" here is how high the ground is -- which is what a river cares
        // about anyway. It runs downhill, it cuts hardest through high ground,
        // and it is navigable where what it has cut is near sea level.
        let rv1 = p.river.get_noise_3d(q[0], q[1], q[2]).abs();
        let rv2 = p.river2
            .get_noise_3d(q[1] + 4.0, q[2] - 2.0, q[0] + 7.0)
            .abs();
        // How drowned this stretch of coast is. See `river_cut`.
        let ria = smoothstep(-0.40, 0.40,
            p.ria.get_noise_3d(q[0] + 3.0, q[1] - 9.0, q[2] + 5.0));
        h = river_cut(h, rv1, land, ria);
        h = river_cut(h, rv2, land, ria);
    }
    h
}

/// Cut one drainage into the land.
///
/// `rv` is the channel field, zero along a centreline; `land` fades the whole
/// thing out as the shore does, so a river does not go on cutting a trench
/// across the sea floor.
fn river_cut(h: f32, rv: f32, land: f32, ria: f32) -> f32 {
    if land <= 0.0 || h < -180.0 {
        return h;
    }
    let mut out = h;
    // The valley the channel sits in: broad, and deeper through high ground --
    // a gorge in the mountains and barely a dip on a coastal plain, which is
    // the difference between a river that has had to cut and one that has not.
    let vale = 1.0 - smoothstep(0.004, 0.030, rv);
    if vale > 0.0 {
        let bite = ((out - 120.0) / 900.0).clamp(0.0, 1.0);
        out -= lerp(26.0, 260.0, bite) * vale * vale * land;
    }
    // The channel itself, and it has to reach the sea. Below about three
    // hundred metres the bed is taken under sea level, so a hull can come in
    // off the ocean and go up it; higher than that the river is still a river
    // but it is one you fly over rather than sail. Without this the planet had
    // channels everywhere and not one of them navigable -- a boat drawing five
    // metres reached nothing, because a trench four hundred metres up is a
    // valley, not a waterway.
    // Flat bottomed, not peaked. `1 - smoothstep(0, w, rv)` squared comes to
    // its full depth only on the centreline, and a channel whose bed is a V
    // has water in it for the couple of hundred metres either side where the
    // cut actually reaches below the sea. That is narrower than the grid a
    // boat is routed on, so the waterway came out as a dotted line: every
    // channel inland was wet in places and none of them joined up. A river has
    // a bed, and this is one -- full depth for seven hundred metres across,
    // then banks.
    // The bank taper is a road's problem, not just a river's. Cut over the
    // four hundred metres this first used, a hundred metre channel has banks
    // at better than one in four, and the road survey -- which will bridge the
    // water but has to get down to the bridge -- came back with a leg at 16.5 %
    // against its own 15 % limit. Over a kilometre and a half the same channel
    // has banks a road can climb.
    let chan = 1.0 - smoothstep(0.0025, 0.014, rv);
    if chan > 0.0 {
        // How far up a channel the sea comes.
        //
        // Measured, the country this is built on is a tableland: 400 m at
        // twenty kilometres from the shore and 417 m at a hundred and sixty.
        // So height tells you how far inland you are for the first twenty
        // kilometres and nothing at all after that, and a river bed set from
        // height alone is navigable for three kilometres and dry beyond it.
        //
        // What reaches further on a real coast is a drowned valley -- the sea
        // standing in a channel cut when it was lower. `ria` says which
        // stretches of coast are that sort, over about two hundred kilometres,
        // so they come in regions: a firth here, a plain river mouth there,
        // rather than every channel on the planet being an inlet.
        let ceiling = lerp(400.0, 900.0, ria);
        let low = 1.0 - smoothstep(ceiling * 0.55, ceiling, out);
        let bed = lerp(out, -16.0, low);
        // Not weighted by `land`, which the valley above is. `land` falls to
        // zero at the shore -- which is precisely where a river meets the sea
        // -- so weighting the channel by it left the last few hundred metres
        // of every river only part cut: a two metre lip across every mouth on
        // the planet. Every channel inland was wet and not one of them was
        // reachable from the water. The `bed < out` test below is what keeps
        // the trench from carrying on across the sea floor, and it does the
        // job on its own: out there the floor is already far below the bed.
        if bed < out {
            out = lerp(out, bed, chan);
        }
    }
    out
}

/// Height above sea level for a direction on the planet.
///
/// One terrain, the same rule everywhere, and that is the point. The playable
/// world used to be a 1200 km square of authored height field blended into the
/// generated planet, and it drew exactly what it was: a box of islands sitting
/// in the middle of an ocean, plainly a box on the tactical globe.
///
/// What is kept is the *carving*. The town platforms, the aerodromes and the
/// road earthworks were never terrain -- they are what is done to terrain once
/// people are living on it -- and they apply to a planetary field exactly as
/// they applied to a flat one. Only the ground underneath them changed.
pub fn height(d: [f32; 3], radius: f32, flags: u32) -> f32 {
    height_on(&chart(), d, radius, flags)
}

/// The same, against a chart already in hand -- `ground_world_y` has one, and
/// taking the lock again for every sample of a terrain chunk is not free.
pub fn height_on(c: &Chart, d: [f32; 3], _radius: f32, flags: u32) -> f32 {
    let gen = generated(d);
    // The carving is laid out in chart coordinates, which is where the roads
    // were surveyed and the fields sited, so it is asked for in those.
    let (x, z) = chart_xz(c, d);
    // ...and in the flat world's `y`, where the sea is at WATER_LEVEL rather
    // than at zero. A runway levelled to "elevation 0" means zero in *that*
    // reckoning, so handing `carve` an elevation above sea level put the
    // aerodrome thirty-five metres under the water and the game started in the
    // sea. In and out of that convention around it.
    let carved = carve(world(), corridor(),
        crate::field::WATER_LEVEL + gen, x, z, flags);
    carved - crate::field::WATER_LEVEL
}

/// Where a direction lands on the chart the built things are laid out in.
///
/// The near side only: `x` and `z` taken off a direction are the same on both
/// sides of the planet, so without the hemisphere test the airfield is carved
/// into the antipode as well and the world's works appear twice.
#[inline]
/// Chart coordinates for a direction: the exact inverse of `dir_from_chart`.
///
/// This was `(d[0] * radius, d[2] * radius)`, with a bail-out on the southern
/// hemisphere -- which is the right answer for small angles about `Vector3::UP`
/// and the wrong answer everywhere else. It was written when the chart was
/// always at `UP`. Once the chart was put on whichever country the sortie is
/// flown from, it returned points a thousand kilometres from the one asked
/// about, so `carve` was laying the aerodromes, the town platforms and the
/// roads down at places nobody had built anything.
///
/// Nothing caught it, because a field is levelled to the height of its own
/// site: with the ground under a strip already at the strip's elevation, a
/// flattening that never happened looks exactly like one that did. Rivers were
/// what made the ground under a runway differ from the runway, and the field
/// test found 130 m of it. The road test had been printing the evidence for a
/// while: "earth moved to make the road: mean 0.00 m cut".
pub fn chart_xz(c: &Chart, d: [f32; 3]) -> (f32, f32) {
    let ca = dot(d, c.origin).clamp(-1.0, 1.0);
    let ex = dot(d, c.east);
    let sz = dot(d, c.south);
    let t = (ex * ex + sz * sz).sqrt();
    if t < 1e-12 {
        // On the axis, where there is no bearing. The origin is (0, 0); the
        // antipode is half a circumference away and it matters which of the
        // two this is -- reported as the origin, the point opposite the chart
        // gets the home aerodrome levelled onto it, and the planet test duly
        // said the antipode was a copy of the airfield.
        return if ca > 0.0 {
            (0.0, 0.0)
        } else {
            (std::f32::consts::PI * c.radius, 0.0)
        };
    }
    // `atan2(t, ca)`, not `acos(ca)`. A point 1500 m from the chart's origin
    // has `ca` within 3e-8 of one, which a 32-bit float cannot tell from one
    // at all: the arc cosine of it is zero and the whole aerodrome collapses
    // to a point. `t` is the sine of the same angle and is small where the
    // precision is needed, so this is exact at the origin and holds to the
    // antipode.
    let s = t.atan2(ca) * c.radius;
    (s * ex / t, s * sz / t)
}

/// The ground under a chart coordinate, as the game above measures height.
///
/// Not an elevation: the world `y` the flat game has always used, with the sea
/// at `WATER_LEVEL` under the middle of the chart and falling away from it as
/// the planet curves. Keeping this convention is what lets the aeroplane, the
/// weapons and the vehicles move onto a planet without being touched.
///
/// The drop is `R(1 - cos(s/R))` rather than the flat world's `s^2/2R`. They
/// agree to a metre near the chart and part company badly past it, and past
/// it is the whole point of this.
pub fn ground_world_y(c: &Chart, x: f32, z: f32, flags: u32) -> f32 {
    let s = (x * x + z * z).sqrt();
    let drop = c.radius * (1.0 - (s / c.radius).cos());
    // The carving is asked for at the coordinates the caller gave, not at the
    // ones that come back from turning them into a direction and out again.
    // The works are laid out on the chart and this *is* the chart; going round
    // by way of the sphere only costs accuracy where there is least of it to
    // spare, which is next to the origin, which is where the aerodrome is.
    let d = dir_from_chart(c, x, z);
    let carved = crate::world::carve(crate::world::world(),
        crate::world::corridor(), crate::field::WATER_LEVEL + generated(d),
        x, z, flags);
    carved - drop
}

// -------------------------------------------------------------- the sheet
//
// One equirectangular picture of the whole planet, read by the orbital body and
// by the tactical globe so the two cannot disagree about what the world looks
// like.
//
// Built here rather than in the game above for two reasons. It was 922 ms of a
// 4.4 s cold boot in GDScript, half a million texels evaluated one at a time on
// one thread; and the colour rule would otherwise exist twice, which is exactly
// how a map stops matching the country it is a map of.

/// Whose colour the ground is, given a direction and its height.
///
/// By the same rule the ground shader draws with and the tactical chart is
/// rasterised from. It had its own palette for a while -- a reasonable-looking
/// one, written here because it was quicker than plumbing the real one through
/// -- and the result was a planet whose map did not match the view out of the
/// window, because they were two different worlds' worth of colour.
pub fn colour(d: [f32; 3], h: f32, north: [f32; 3], _moist: f32) -> [f32; 3] {
    surface_colour(d, h, north, 1.0)
}

/// What the ground looks like from above: the rule the orbital sheet and the
/// tactical chart both draw with.
///
/// They had a rule each. The globe faded its oceans over `OCEAN` metres from
/// one blue to another and grew sea ice at the poles; the chart ramped a
/// different blue over four hundred metres and had no ice at all. Same planet,
/// same heights, two pictures that did not look like each other -- which is
/// exactly how it was reported. `shade` is the chart's hill shading, and 1.0 is
/// the sheet asking for none.
///
/// `elev` is metres above local sea level in both cases: the sheet works in the
/// flat frame where that is the height itself, the chart in the world frame
/// where it is the height less the dropped sea.
pub fn surface_colour(d: [f32; 3], elev: f32, north: [f32; 3], shade: f32)
        -> [f32; 3] {
    let h = elev;
    let lat_raw = dot(d, north).abs();
    if h <= 0.0 {
        let deep = (-h / OCEAN).clamp(0.0, 1.0);
        let sea = mix3([0.10, 0.20, 0.30], [0.02, 0.05, 0.11], deep);
        // Sea ice. Broken up rather than thresholded on latitude alone: a
        // perfect circle of white on a round planet reads as a decal.
        let (t, _m) = climate(d);
        let shelf = (1.0 + h / 2600.0).clamp(0.0, 1.0);
        let ice = smoothstep(0.88, 0.995,
            lat_raw + (t - 0.5) * 0.11 + shelf * 0.035);
        return mix3(sea, [0.82, 0.87, 0.92], ice);
    }
    // The same climate the ground and the chart read, and the same compression:
    // the whole 1200 km world is 5.4 degrees of a real planet, and 5.4 degrees
    // of anywhere is one climate.
    let (t, m) = climate(d);
    let lat = (lat_raw * CLIMATE_SQUEEZE).clamp(0.0, 1.0);
    // What the season is worth here: nothing at the equator, most at the poles,
    // and opposite signs either side of the line. `lat_raw` is signed before it
    // is folded, which is the whole of the difference between a hemisphere
    // having winter and both of them having it at once.
    let warmth = season() * dot(d, north) * SEASON_AMP;
    let c = crate::raster::planet_colour(lat, t, m, h, 1.0, warmth);
    // Land takes the hill shading; water does not -- a sea lit off its own bed
    // is a relief map of the sea floor, not a sea.
    [c.0 * shade, c.1 * shade, c.2 * shade]
}

/// How much warmer midsummer is than midwinter at the pole, on the 0..1 scale
/// the biome rule works in. Mirrors `Sim.SEASON_AMP`.
pub const SEASON_AMP: f32 = 0.12;

/// Where the planet is in its year: +1 at northern midsummer, -1 at northern
/// midwinter. Pushed in from the clock rather than worked out here, because the
/// clock is what everything else reads it from.
static SEASON: std::sync::atomic::AtomicI32 =
    std::sync::atomic::AtomicI32::new(0);

pub fn set_season(s: f32) {
    SEASON.store((s.clamp(-1.0, 1.0) * 10000.0) as i32,
        std::sync::atomic::Ordering::Relaxed);
}

pub fn season() -> f32 {
    SEASON.load(std::sync::atomic::Ordering::Relaxed) as f32 / 10000.0
}

/// Where the climate scale reaches 1: the polar circle, which is ninety degrees
/// less the planet's axial tilt. Mirrors `Sim.CLIMATE_SQUEEZE`, and
/// `--suntest` checks that the two agree.
pub const CLIMATE_SQUEEZE: f32 = 1.0899;

#[inline]
fn mix3(a: [f32; 3], b: [f32; 3], t: f32) -> [f32; 3] {
    [
        a[0] + (b[0] - a[0]) * t,
        a[1] + (b[1] - a[1]) * t,
        a[2] + (b[2] - a[2]) * t,
    ]
}

#[inline]
fn dot(a: [f32; 3], b: [f32; 3]) -> f32 {
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}

/// The direction a texel of the sheet looks at. Longitude runs east from the
/// chart origin, so the world lands on the planet where the world is.
pub fn sheet_dir(u: f32, v: f32, north: [f32; 3]) -> [f32; 3] {
    let lat = (0.5 - v) * std::f32::consts::PI;
    let lon = (u - 0.5) * std::f32::consts::TAU;
    at_lat_lon(lat, lon, north)
}

#[inline]
fn cross(a: [f32; 3], b: [f32; 3]) -> [f32; 3] {
    [
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    ]
}

/// `smoothstep`, for the crate. The map rasteriser wants the same easing the
/// terrain uses rather than a second one of its own.
pub fn smoothstep_pub(a: f32, b: f32, x: f32) -> f32 {
    smoothstep(a, b, x)
}

/// The whole planet as an RGB8 equirectangular sheet.
pub fn sheet(w: usize, h: usize, north: [f32; 3], radius: f32) -> Vec<u8> {
    sheet_window(w, h, north, radius, 0.0, 1.0, 0.0, 1.0)
}

/// A window of that sheet, at whatever resolution is asked for.
///
/// The map's globe samples one sheet of the whole planet however far it is
/// zoomed in. At the far end of the zoom the visible cap is a couple of
/// hundredths of a degree across -- thirty kilometres -- and a whole-planet
/// sheet has perhaps two texels in it. This bakes the same rule over just the
/// part being looked at, so the detail arrives as you close on it.
///
/// `u` and `v` are the sheet's own coordinates: `u` runs east over a full turn
/// and `v` from the north pole to the south.
pub fn sheet_window(w: usize, h: usize, north: [f32; 3], radius: f32,
        u0: f32, u1: f32, v0: f32, v1: f32) -> Vec<u8> {
    let p = planet();
    // Once, not once a texel. `height` and `road_ink` both want it, and at four
    // million texels across every core the read was the sheet's own bottleneck.
    let ch = chart();
    let mut out = vec![0u8; w * h * 3];
    let du = u1 - u0;
    let dv = v1 - v0;
    // What one texel of this window covers on the ground, which is what decides
    // how wide the roads are drawn and whether they are drawn at all.
    let texel = dv * std::f32::consts::PI * radius / h as f32;
    out.par_chunks_mut(w * 3).enumerate().for_each(|(j, row)| {
        let v = v0 + (j as f32 + 0.5) / h as f32 * dv;
        for i in 0..w {
            let u = u0 + (i as f32 + 0.5) / w as f32 * du;
            let d = sheet_dir(u, v, north);
            let hh = height_on(&ch, d, radius, crate::G_ALL);
            let mo = p.moist.get_noise_3d(d[0], d[1], d[2]);
            let mut c = colour(d, hh, north, mo);
            // The roads, where the picture is fine enough to be worth drawing
            // them on. Baked into the sheet rather than drawn over it every
            // frame: the network is fifty thousand legs and the map redraws
            // every frame it is open.
            if texel < 4000.0 && hh > 0.0 {
                let (rx, rz) = chart_xz(&ch, d);
                c = crate::raster::road_ink(rx, rz, texel, c);
            }
            let o = i * 3;
            row[o] = (c[0].clamp(0.0, 1.0) * 255.0) as u8;
            row[o + 1] = (c[1].clamp(0.0, 1.0) * 255.0) as u8;
            row[o + 2] = (c[2].clamp(0.0, 1.0) * 255.0) as u8;
        }
    });
    out
}

/// Sea level under a chart coordinate, in the same world `y` the ground uses.
pub fn sea_at(c: &Chart, x: f32, z: f32) -> f32 {
    let s = (x * x + z * z).sqrt();
    crate::field::WATER_LEVEL - c.radius * (1.0 - (s / c.radius).cos())
}

/// Temperature and moisture at a direction, 0..1 each. The planetary
/// counterpart of `field::climate`, and attached to the planet rather than to
/// the chart that happens to be looking at it.
pub fn climate(d: [f32; 3]) -> (f32, f32) {
    let p = planet();
    (
        (p.ctemp.get_noise_3d(d[0], d[1], d[2]) + 1.0) * 0.5,
        (p.cmoist.get_noise_3d(d[0], d[1], d[2]) + 1.0) * 0.5,
    )
}

// ---------------------------------------------- the chart's own rasters

/// The close-in ground as the map draws it, on the planet.
///
/// `map_relief` rasterises the flat field about the world origin, which is the
/// last thing in the map that still believes in an authored square: on a planet
/// the ground under the chart is the planetary field, and the chart moves. This
/// takes the same picture in chart coordinates, so it is the country the player
/// is actually over and it can be taken again when the chart is put somewhere
/// else.
///
/// A free function rather than a method, because it is wanted from two places:
/// the blocking call the loading screen pumps, and the off-thread bake a chart
/// move asks for.
pub fn relief_globe(c: &Chart, n: usize, half: f32) -> Vec<u8> {
    let step = half * 2.0 / n as f32;
    // The heights first, once each, on a grid one bigger than the picture.
    //
    // Every texel needs its own height and its two forward neighbours' to
    // light it off the slope, and every one of those neighbours is another
    // texel's own height. Asked for three times over, a 2048 sheet was
    // twelve and a half million evaluations of the full field -- generated
    // terrain, rivers, carving and all -- for four million texels, and the
    // map was the largest single item in the world's build.
    let gn = n + 1;
    let mut hs = vec![0f32; gn * gn];
    hs.par_chunks_mut(gn).enumerate().for_each(|(j, row)| {
        let z = -half + j as f32 * step;
        for (i, v) in row.iter_mut().enumerate() {
            *v = ground_world_y(&c, -half + i as f32 * step, z, crate::G_ALL);
        }
    });
    let mut out = vec![0u8; n * n * 3];
    out.par_chunks_mut(n * 3).enumerate().for_each(|(j, row)| {
        let z = -half + j as f32 * step;
        for i in 0..n {
            let x = -half + i as f32 * step;
            let h = hs[j * gn + i];
            let sea = sea_at(&c, x, z);
            // Lit off the slope, the same way the flat sheet is: a map with
            // no hill shading on it is a biome chart, not a map. Worked out
            // for water too and then thrown away, because the colour rule
            // below declines to shade a sea.
            let dx = hs[j * gn + i + 1] - h;
            let dz = hs[(j + 1) * gn + i] - h;
            let shade = (0.72 + (-dx - dz) / (step * 0.55)).clamp(0.35, 1.5);
            // The planet's own rule, not a second one written for the
            // chart: these are two pictures of the same ground.
            let d = dir_from_chart(&c, x, z);
            let col = crate::raster::road_ink(x, z, step,
                surface_colour(d, h - sea, NORTH, shade));
            let o = i * 3;
            row[o] = (col[0].clamp(0.0, 1.0) * 255.0) as u8;
            row[o + 1] = (col[1].clamp(0.0, 1.0) * 255.0) as u8;
            row[o + 2] = (col[2].clamp(0.0, 1.0) * 255.0) as u8;
        }
    });
    out
}

/// Temperature and moisture over the chart, as the two half float channels the
/// ground shader samples. A free function because it is wanted from the main
/// thread at boot and from a worker after a chart move.
pub fn climate_globe(c: &Chart, n: usize, half: f32) -> Vec<u8> {
    let span = half * 2.0;
    let mut out = vec![0u8; n * n * 4];
    out.par_chunks_mut(n * 4).enumerate().for_each(|(j, row)| {
        let z = (j as f32 + 0.5) / n as f32 * span - half;
        for i in 0..n {
            let x = (i as f32 + 0.5) / n as f32 * span - half;
            let (t, m) = climate(dir_from_chart(c, x, z));
            row[i * 4..i * 4 + 2].copy_from_slice(&crate::raster::f16(t).to_le_bytes());
            row[i * 4 + 2..i * 4 + 4]
                .copy_from_slice(&crate::raster::f16(m).to_le_bytes());
        }
    });
    out
}
