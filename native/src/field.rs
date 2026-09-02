//! The natural height field, before anything is built on it.
//!
//! Four to eight noise lookups per point, and the whole game is built on it --
//! every terrain chunk, every road cost, every scatter placement, every missile
//! flying down a valley. This is the single source of truth for it: nothing
//! outside this file decides what the land looks like.

use fastnoise_lite::{FastNoiseLite, FractalType, NoiseType};
use std::sync::OnceLock;

pub const COAST_X: f32 = 15000.0;
pub const WATER_LEVEL: f32 = -35.0;
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
    /// Where the crest lines run. A field of its own, because keyed off `lo`
    /// every range would follow the contours of the ground it stands on.
    ridge: FastNoiseLite,
    /// The grain of the rock, which only shows on high ground.
    grain: FastNoiseLite,
    temp: FastNoiseLite,
    moist: FastNoiseLite,
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
        ridge: mk(4471, 0.0000225, 4, 2.05, 0.52),
        grain: mk(9013, 0.00115, 3, 2.15, 0.5),
        temp: mk(515, 0.0000062, 2, 2.0, 0.5),
        moist: mk(811, 0.0000085, 3, 2.0, 0.5),
    })
}

#[inline]
pub fn smoothstep(a: f32, b: f32, x: f32) -> f32 {
    if b <= a {
        return if x < a { 0.0 } else { 1.0 };
    }
    let t = ((x - a) / (b - a)).clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

#[inline]
pub fn lerp(a: f32, b: f32, t: f32) -> f32 {
    a + (b - a) * t
}

/// Temperature and moisture at a point, both 0..1. The climate texture the
/// ground shader reads is a raster of exactly this.
#[inline]
pub fn climate(x: f32, z: f32) -> (f32, f32) {
    let f = field();
    (
        (f.temp.get_noise_2d(x, z) + 1.0) * 0.5,
        (f.moist.get_noise_2d(x, z) + 1.0) * 0.5,
    )
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

/// How near a point is to a crest line, 1 on the watershed and 0 off it.
///
/// Fractional Brownian noise has no ridges in it at all -- it is a field of
/// rounded lobes, and a mountain range built out of it reads as a heap of
/// spoil with no spine and no passes. Taking the zero crossings of a noise
/// field as the crests gives a connected network of ridge lines, which is what
/// a watershed actually is. The seven is the crest's half width against the
/// spread of the field: at one the whole map is crest and the term is a
/// constant lift, and this is what makes it a ridge instead.
#[inline]
fn crest(n: f32) -> f32 {
    let r = 1.0 - n.abs() * 7.0;
    if r > 0.0 {
        r * r
    } else {
        0.0
    }
}

/// The mean of `crest` over the field, subtracted so that adding ridges does
/// not simply raise every mountain in the world by a couple of hundred metres.
const CREST_MEAN: f32 = 0.115;

/// The land before anything is built on it.
pub fn natural(x: f32, z: f32) -> f32 {
    let f = field();
    let mut m = (f.lo.get_noise_2d(x, z) + 1.0) * 0.5;
    m = m.powf(2.3);
    let mut h = m * 2100.0;
    h += f.hi.get_noise_2d(x, z) * 150.0 * m;
    // Crest lines through the high ground.
    //
    // The mountains used to be the same rounded field as the plains, only
    // taller: every range was a row of domes with no ridge and no col in it, so
    // there was nothing for a road to look for and nothing for an aeroplane to
    // fly between. The ridge field is laid over the high ground only -- weighted
    // by how mountainous the base already is -- so plains and coast are exactly
    // as they were.
    let up = smoothstep(0.16, 0.62, m);
    if up > 0.0 {
        let c = crest(f.ridge.get_noise_2d(x, z));
        h += (c - CREST_MEAN) * 430.0 * up;
        // a second, finer set of folds running off the flanks of the first
        h += (crest(f.ridge.get_noise_2d(x * 3.7 + 5100.0, z * 3.7 - 2300.0))
            - CREST_MEAN)
            * 96.0
            * up;
        // Rock grain, on high ground only. Detail applied evenly is either
        // invisible on a hillside or turns the plains into corrugated iron;
        // weighted by the same mountain mask it roughens the tops and leaves
        // the country anything is built on alone.
        h += f.grain.get_noise_2d(x, z) * 19.0 * up;
    }
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
