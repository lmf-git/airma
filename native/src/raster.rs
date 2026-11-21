//! The things the world is drawn from that are one arithmetic rule asked for
//! several million points: the ground mask, the climate texture, the road
//! ribbons and the map relief.
//!
//! All of them were loops in script over a worker pool, and every one of them
//! paid a crossing of the extension boundary per sample to ask how high the
//! ground was. Here they are one call each, and the loop is inside.

use crate::field::{climate, lerp, smoothstep, WATER_LEVEL};
use crate::index::SegGrid;
use crate::world::{base, carve_built, corridor, ground_at, world, Corridor, G_ALL};
use rayon::prelude::*;

// ------------------------------------------------------------- ground mask

/// A capsule or a disc to be stamped into the mask: the shape, the radius it is
/// solid out to, the radius it fades to, and which channel it lands in.
#[derive(Clone, Copy)]
pub struct Stamp {
    pub ax: f32,
    pub az: f32,
    pub bx: f32,
    pub bz: f32,
    pub solid: f32,
    pub fade: f32,
    pub channel: u8,
}

/// Rasterise the road network and the town footprints into one two-channel
/// mask: red is tarmac, green is made ground.
///
/// Sixteen million texels against nine thousand shapes, so the shapes are
/// bucketed by row first and each row only looks at what actually reaches it.
/// Rows go out across every core.
pub fn ground_mask(stamps: &[Stamp], n: usize, half: f32, cx: f32, cz: f32)
        -> (Vec<u8>, u32, u32) {
    let mut out = vec![0u8; n * n * 2];
    if stamps.is_empty() || n == 0 {
        return (out, 0, 0);
    }
    let tpm = n as f32 / (half * 2.0); // texels per metre
    // which shapes touch each row
    let mut rows: Vec<Vec<u32>> = vec![Vec::new(); n];
    for (i, s) in stamps.iter().enumerate() {
        let lo = s.az.min(s.bz) - cz - s.fade;
        let hi = s.az.max(s.bz) - cz + s.fade;
        let j0 = (((lo + half) * tpm).floor() as i64).clamp(0, n as i64 - 1) as usize;
        let j1 = (((hi + half) * tpm).ceil() as i64).clamp(0, n as i64 - 1) as usize;
        if hi < -half || lo > half {
            continue;
        }
        for r in rows.iter_mut().take(j1 + 1).skip(j0) {
            r.push(i as u32);
        }
    }
    out.par_chunks_mut(n * 2)
        .enumerate()
        .for_each(|(j, row)| {
            let bucket = &rows[j];
            if bucket.is_empty() {
                return;
            }
            let wz = j as f32 / tpm - half + cz;
            for s in bucket {
                let s = &stamps[*s as usize];
                // Only the stretch of this shape that actually reaches the row.
                //
                // Taken as the whole bounding box, a road running diagonally
                // across the map is scanned from one side of every row it
                // touches to the other -- sixteen million texel tests for a
                // capsule that covers a few thousand of them. Clipping the
                // segment to the band of z within reach of the row first turns
                // a diagonal back into what it is.
                let (mut lo, mut hi) = (f32::INFINITY, f32::NEG_INFINITY);
                let dz = s.bz - s.az;
                let (t0, t1) = if dz.abs() < 1e-6 {
                    if (s.az - wz).abs() <= s.fade { (0.0, 1.0) } else { (1.0, 0.0) }
                } else {
                    let u = (wz - s.fade - s.az) / dz;
                    let v = (wz + s.fade - s.az) / dz;
                    (u.min(v).clamp(0.0, 1.0), u.max(v).clamp(0.0, 1.0))
                };
                if t0 > t1 {
                    continue;
                }
                for t in [t0, t1] {
                    let x = s.ax + (s.bx - s.ax) * t;
                    lo = lo.min(x);
                    hi = hi.max(x);
                }
                lo = lo - cx - s.fade;
                hi = hi - cx + s.fade;
                let i0 = (((lo + half) * tpm).floor() as i64).clamp(0, n as i64 - 1) as usize;
                let i1 = (((hi + half) * tpm).ceil() as i64).clamp(0, n as i64 - 1) as usize;
                let abx = s.bx - s.ax;
                let abz = s.bz - s.az;
                let len2 = (abx * abx + abz * abz).max(1e-6);
                for i in i0..=i1 {
                    let wx = i as f32 / tpm - half + cx;
                    let t = (((wx - s.ax) * abx + (wz - s.az) * abz) / len2)
                        .clamp(0.0, 1.0);
                    let dx = wx - (s.ax + abx * t);
                    let dz = wz - (s.az + abz * t);
                    let d = (dx * dx + dz * dz).sqrt();
                    let v = 1.0 - smoothstep(s.solid, s.fade, d);
                    if v <= 0.0 {
                        continue;
                    }
                    let px = (v.clamp(0.0, 1.0) * 255.0) as u8;
                    let at = i * 2 + s.channel as usize;
                    if row[at] < px {
                        row[at] = px;
                    }
                }
            }
        });
    // Counted here rather than walked afterwards: at 4096 square the mask is
    // sixteen million texels, and a script loop over them to work out how much
    // of it is road cost more than drawing the whole thing did.
    let (road, town) = out
        .par_chunks(2)
        .map(|p| ((p[0] > 96) as u32, (p[1] > 96) as u32))
        .reduce(|| (0, 0), |a, b| (a.0 + b.0, a.1 + b.1));
    (out, road, town)
}

// ------------------------------------------------------------- climate

/// IEEE half, which is what `Image.FORMAT_RGH` holds. Only finite values in
/// 0..1 reach this, so the subnormal and infinity cases cannot arise.
#[inline]
pub fn f16(v: f32) -> u16 {
    let b = v.to_bits();
    let sign = ((b >> 16) & 0x8000) as u16;
    let exp = ((b >> 23) & 0xff) as i32 - 127 + 15;
    let man = (b >> 13) & 0x3ff;
    if exp <= 0 {
        return sign; // rounds to zero, which is what 0.0 and near it want
    }
    sign | ((exp as u16) << 10) | man as u16
}

/// Temperature and moisture rasterised over the whole world, as the two half
/// float channels the ground shader samples.
pub fn climate_map(n: usize, half: f32) -> Vec<u8> {
    let mut out = vec![0u8; n * n * 4];
    let span = half * 2.0;
    out.par_chunks_mut(n * 4).enumerate().for_each(|(j, row)| {
        let z = (j as f32 + 0.5) / n as f32 * span - half;
        for i in 0..n {
            let x = (i as f32 + 0.5) / n as f32 * span - half;
            let (t, m) = climate(x, z);
            row[i * 4..i * 4 + 2].copy_from_slice(&f16(t).to_le_bytes());
            row[i * 4 + 2..i * 4 + 4].copy_from_slice(&f16(m).to_le_bytes());
        }
    });
    out
}

// ------------------------------------------------------------- streets

/// A street stops where the made ground under it stands this far off the
/// town's own level -- at the foot of a bank it does not climb. It does not
/// stop at a road it meets: it runs on into it, and the two are painted as one
/// surface. Cut square a little inside the road, as it was, a street that met
/// one at an angle left a corner of the road's kerb across its mouth.
const STREET_RAISED: f32 = 0.3;
/// How far beyond its carriageway a street keeps off a bank. Taken only under
/// the carriageway, a street running beside a ramp, or into it, stopped where
/// the bank had already climbed over its kerb: the side of the ramp was built
/// over it, and it was cut off. Streets are kept off the whole footprint of a
/// raised road's bank, its side slope and a margin, rather than run up to it.
const STREET_CLEAR: f32 = 6.0;
/// The shortest piece of a street left standing after it is cut back.
const STREET_STUB: f32 = 25.0;

// ------------------------------------------------------------- road ink

/// The colour a road is drawn on a map, and how strongly.
const ROAD_INK: [f32; 3] = [0.72, 0.64, 0.50];

/// Lay the road network over a map colour.
///
/// A carriageway is twelve metres wide and the finest map sheet here is a
/// hundred and seventeen metres to a texel, so a road drawn to scale is
/// invisible at every zoom -- which is why the planet map had no roads on it at
/// all. Drawn about a texel and a half wide instead, the way a road is drawn on
/// any map: the line says where it goes, not how wide it is.
///
/// `texel` is the ground the texel covers, so the network thins as the picture
/// gets finer rather than staying a fixed smear.
pub fn road_ink(x: f32, z: f32, texel: f32, col: [f32; 3]) -> [f32; 3] {
    let g = match crate::index::segments() {
        Some(g) => g,
        None => return col,
    };
    let far = texel * 2.0;
    let d = g.distance(x, z, far);
    let w = 1.0 - crate::sphere::smoothstep_pub(texel * 0.35, texel * 1.3, d);
    if w <= 0.0 {
        return col;
    }
    let t = w * 0.85;
    [
        col[0] + (ROAD_INK[0] - col[0]) * t,
        col[1] + (ROAD_INK[1] - col[1]) * t,
        col[2] + (ROAD_INK[2] - col[2]) * t,
    ]
}

// ------------------------------------------------------------- map relief

/// The tactical map's background: hill-shaded relief in biome colour, with the
/// road network drawn over it.
///
/// Every pixel wants three heights, a biome and a distance to the nearest road.
/// At half a million samples the boundary crossings alone were most of the
/// nine hundred milliseconds this took.
pub fn relief(n: usize, half: f32, segs: &SegGrid) -> Vec<u8> {
    let w = world();
    let c = corridor();
    let step = half * 2.0 / n as f32;
    // The heights first, once each, on a grid one bigger than the picture.
    //
    // Every texel needs its own height and its two forward neighbours' to light
    // it off the slope, and every one of those neighbours is another texel's own
    // height. Asked for three times over -- which is what this did -- a sheet is
    // three evaluations of the whole field, rivers, carving and all, for each
    // texel of it. The planetary sheet was fixed this way; this is the flat
    // world's, and it was the last of the three-times-over rasterisers.
    let gn = n + 1;
    let mut hs = vec![0f32; gn * gn];
    hs.par_chunks_mut(gn).enumerate().for_each(|(j, row)| {
        let z = -half + j as f32 * step;
        for (i, v) in row.iter_mut().enumerate() {
            *v = ground_at(w, c, -half + i as f32 * step, z, G_ALL);
        }
    });
    let mut out = vec![0u8; n * n * 3];
    out.par_chunks_mut(n * 3).enumerate().for_each(|(j, row)| {
        let z = -half + j as f32 * step;
        for i in 0..n {
            let x = -half + i as f32 * step;
            let h = hs[j * gn + i];
            let (r, g, b);
            if h < WATER_LEVEL {
                let t = ((h + 400.0) / 400.0).clamp(0.0, 1.0);
                r = lerp(0.06, 0.10, t);
                g = lerp(0.16, 0.24, t);
                b = lerp(0.26, 0.34, t);
            } else {
                let (mut cr, mut cg, mut cb) = biome_colour(x, z, h, 1.0);
                let dx = hs[j * gn + i + 1] - h;
                let dz = hs[(j + 1) * gn + i] - h;
                let shade = (0.72 + (-dx - dz) / (step * 0.55)).clamp(0.35, 1.5);
                cr *= shade;
                cg *= shade;
                cb *= shade;
                if segs.distance(x, z, step) < step * 0.8 {
                    cr = lerp(cr, 0.14, 0.75);
                    cg = lerp(cg, 0.14, 0.75);
                    cb = lerp(cb, 0.15, 0.75);
                }
                r = cr;
                g = cg;
                b = cb;
            }
            row[i * 3] = (r.clamp(0.0, 1.0) * 255.0) as u8;
            row[i * 3 + 1] = (g.clamp(0.0, 1.0) * 255.0) as u8;
            row[i * 3 + 2] = (b.clamp(0.0, 1.0) * 255.0) as u8;
        }
    });
    out
}

// ------------------------------------------------------------- biomes
//
// The same rule `Sim.biome_weights` runs, and it has to stay the same rule:
// the ground shader, the scatter and the map all read it, and a second copy
// that drifts shows up as a map whose colours do not match the country.

const B_SNOW: usize = 0;
const B_ROCK: usize = 1;
const B_FOREST: usize = 2;
const B_GRASS: usize = 3;
const B_STEPPE: usize = 4;
const B_SAND: usize = 5;
const B_MARSH: usize = 6;

const WORLD_HALF: f32 = 600000.0;

const BIOME_RGB: [[f32; 3]; 7] = [
    [0.93, 0.95, 0.98], // snow
    [0.31, 0.28, 0.26], // rock
    [0.13, 0.24, 0.12], // forest
    [0.22, 0.33, 0.15], // grass
    [0.44, 0.41, 0.23], // steppe
    [0.60, 0.55, 0.38], // sand
    [0.19, 0.28, 0.20], // marsh
];

pub fn biome_weights(x: f32, z: f32, y: f32, slope: f32) -> [f32; 7] {
    let lat = (z.abs() / (WORLD_HALF * 0.85)).clamp(0.0, 1.0);
    let (nt, nm) = climate(x, z);
    // The flat world has no orbit, so it has no seasons.
    weights_from(lat, nt, nm, y, slope, 0.0)
}

/// The same rule with its inputs handed in.
///
/// Split out so the planet can use it. What the ground looks like is one rule
/// and has to stay one rule -- the ground shader draws it, the tactical chart
/// is rasterised from it, the scatter picks its species by it and the orbital
/// sheet is coloured by it. The planet had its own hand-written palette for a
/// while, which is why the map and the view out of the window did not agree.
/// `warmth` is the season: what the sun's declination is worth in temperature
/// here and now. Zero on the flat world and at the equator, and the reason the
/// snow line moves through the year.
pub fn weights_from(lat: f32, nt: f32, nm: f32, y: f32, slope: f32, warmth: f32)
        -> [f32; 7] {
    let band = 1.0 - lat * 1.25;
    // the dry belts sit either side of the hot middle, the way they do on Earth
    let belt = (1.0 - (lat - 0.32).abs() * 3.0).clamp(0.0, 1.0);
    let temp = (band * 0.70 + nt * 0.42
        - ((y - 300.0) / 2200.0).clamp(0.0, 1.0) * 0.85
        + warmth)
        .clamp(0.0, 1.0);
    let moist = (nm + (1.0 - (y - WATER_LEVEL).abs() / 900.0).clamp(0.0, 1.0) * 0.25
        - belt * 0.66)
        .clamp(0.0, 1.0);
    let steep = ((0.90 - slope) / 0.34).clamp(0.0, 1.0);
    let mut w = [0.0f32; 7];
    w[B_SNOW] = ((y - 1500.0) / 700.0).clamp(0.0, 1.0) * (1.0 - steep * 0.7)
        * (1.0 - temp * 1.4).clamp(0.0, 1.0)
        + ((y - 2400.0) / 500.0).clamp(0.0, 1.0)
        + ((0.18 - temp) / 0.18).clamp(0.0, 1.0) * 1.6;
    w[B_ROCK] = steep + ((y - 1100.0) / 1400.0).clamp(0.0, 1.0) * 0.5;
    w[B_FOREST] = (moist * 1.5 - 0.35).clamp(0.0, 1.0)
        * (temp * 1.6).clamp(0.0, 1.0)
        * (1.0 - (y - 200.0) / 1500.0).clamp(0.0, 1.0);
    w[B_GRASS] = (1.0 - (moist - 0.55).abs() * 3.2).clamp(0.0, 1.0) * 0.85
        * (1.0 - (y - 400.0) / 1600.0).clamp(0.0, 1.0);
    w[B_STEPPE] = (0.62 - moist).clamp(0.0, 1.0) * 1.7 * (temp * 1.3).clamp(0.0, 1.0);
    w[B_SAND] = (1.0 - (y - WATER_LEVEL).abs() / 26.0).clamp(0.0, 1.0) * 1.4
        + (0.40 - moist).clamp(0.0, 1.0) * (temp - 0.30).clamp(0.0, 1.0) * 7.0;
    w[B_MARSH] = (moist - 0.72).clamp(0.0, 1.0) * 2.2
        * (1.0 - (y - WATER_LEVEL).abs() / 140.0).clamp(0.0, 1.0);
    let mut total = 0.0f32;
    for v in w.iter_mut() {
        if *v < 0.0 {
            *v = 0.0;
        }
        total += *v;
    }
    if total < 0.001 {
        w[B_GRASS] = 1.0;
        total = 1.0;
    }
    for v in w.iter_mut() {
        *v /= total;
    }
    w
}

pub fn biome_colour(x: f32, z: f32, y: f32, slope: f32) -> (f32, f32, f32) {
    let w = biome_weights(x, z, y, slope);
    let mut c = [0.0f32; 3];
    for k in 0..7 {
        for ch in 0..3 {
            c[ch] += BIOME_RGB[k][ch] * w[k];
        }
    }
    // Under the sea. The biome field knows nothing about the waterline, so the
    // seabed came out as grassland: sand in the shallows, grading to silt and
    // then to bare rock as it drops away.
    if y < WATER_LEVEL {
        let deep = ((WATER_LEVEL - y) / 150.0).clamp(0.0, 1.0);
        let bed = [
            lerp(0.46, 0.17, deep),
            lerp(0.42, 0.18, deep),
            lerp(0.33, 0.19, deep),
        ];
        let t = ((WATER_LEVEL - y) / 10.0).clamp(0.0, 1.0);
        for ch in 0..3 {
            c[ch] = lerp(c[ch], bed[ch], t);
        }
    }
    (c[0], c[1], c[2])
}

/// The colour of the ground at a place on the planet, by the one rule.
pub fn planet_colour(lat: f32, nt: f32, nm: f32, elev: f32, slope: f32,
        warmth: f32) -> (f32, f32, f32) {
    // `weights_from` reckons height in the flat world's `y`, where the sea is
    // at WATER_LEVEL rather than at zero.
    let w = weights_from(lat, nt, nm, elev + WATER_LEVEL, slope, warmth);
    let mut c = [0.0f32; 3];
    for k in 0..7 {
        for ch in 0..3 {
            c[ch] += BIOME_RGB[k][ch] * w[k];
        }
    }
    (c[0], c[1], c[2])
}

// ------------------------------------------------------------- painted roads
//
// The roads are drawn into the ground's own material, not laid over it as
// strips of geometry. As strips they were shapes: where two met they fought
// over the same pixels, a street's kerb ran across the road it joined, and
// wherever the terrain mesh bent between two of its samples it came up through
// the carriageway. Painted, a junction is a union -- the asphalt of the two is
// one surface -- the kerb is wherever the asphalt is not, and nothing can come
// through the road because the road is the ground.

/// One straight piece of carriageway to paint: a leg of road, or the part of a
/// street's leg that is drawn (see `street_spans`). Round at an end that meets
/// more road, square at one cut short -- at the foot of a bank, or where it
/// runs into a road it meets.
#[derive(Clone, Copy)]
struct Piece {
    ax: f32,
    az: f32,
    ux: f32,
    uz: f32,
    len: f32,
    half: f32,
    round_a: bool,
    round_b: bool,
}

static PIECES: std::sync::RwLock<Vec<Piece>> = std::sync::RwLock::new(Vec::new());

/// The kerb's outer edge, as a share of the half width.
const KERB_OUT: f32 = 1.55;

/// Where along a street leg it is drawn: the spans of t, 0 to 1, that are not
/// up the bank of a road it does not climb, with the ends found to a few
/// centimetres.
fn street_spans(c: &Corridor, ax: f32, az: f32, bx: f32, bz: f32, half: f32,
        deck: u8) -> Vec<(f32, f32)> {
    let w = world();
    let (dx, dz) = (bx - ax, bz - az);
    let len = (dx * dx + dz * dz).sqrt().max(1e-3);
    let (nx, nz) = (-dz / len, dx / len);
    let gone = |t: f32| -> bool {
        let px = ax + dx * t;
        let pz = az + dz * t;
        // 3: an approach to a road it climbs to; 4: already laid clear of
        // every bank by the planner (`Scenery._streets_clear_of_bridges`)
        if deck == 3 || deck == 4 {
            return false;
        }
        // across the carriageway and out past its kerbs: a street keeps clear
        // of a bank's footprint, not only of the ground under its own wheels
        let wide = (half + STREET_CLEAR) / half;
        [-wide, -1.0f32, -0.5, 0.0, 0.5, 1.0, wide].iter().any(|o| {
            let qx = px + nx * half * o;
            let qz = pz + nz * half * o;
            let made = carve_built(w, base(qx, qz), qx, qz, G_ALL).0;
            (ground_at(w, c, qx, qz, G_ALL) - made).abs() > STREET_RAISED
        })
    };
    let steps = ((len / 4.0).ceil() as i32).max(1);
    let mut spans = Vec::new();
    let mut was = gone(0.0);
    let mut from = if was { -1.0 } else { 0.0 };
    for i in 1..=steps {
        let t = i as f32 / steps as f32;
        let now = gone(t);
        if now != was {
            let (mut lo, mut hi) = ((i - 1) as f32 / steps as f32, t);
            for _ in 0..10 {
                let mid = (lo + hi) * 0.5;
                if gone(mid) == was {
                    lo = mid;
                } else {
                    hi = mid;
                }
            }
            if was {
                from = hi;
            } else if from >= 0.0 {
                spans.push((from, lo));
                from = -1.0;
            }
        }
        was = now;
    }
    if !was && from >= 0.0 {
        spans.push((from, 1.0));
    }
    // and no stub left between a bank and whatever else cut the street: a
    // whole leg stays whatever its length, but a few metres of street running
    // up to a ramp's side and stopping there is not a street
    spans.retain(|&(t0, t1)| (t0 <= 0.0 && t1 >= 1.0) || (t1 - t0) * len >= STREET_STUB);
    spans
}

/// Where a street is clear of every bank: `street_spans` for one street, as
/// a flat run of t0, t1 pairs. The street planner cuts back from what is not.
pub fn street_clear(ax: f32, az: f32, bx: f32, bz: f32, half: f32) -> Vec<f32> {
    street_spans(corridor(), ax, az, bx, bz, half, 0)
        .into_iter()
        .flat_map(|(a, b)| [a, b])
        .collect()
}

/// Take the network to paint: a flat run of eight a leg, as the ribbons were
/// given it -- ax, az, bx, bz, half width, design a, design b, and the end
/// flag (3 for a street's approach to a road it climbs to meet). How many
/// pieces that came to.
pub fn publish_road_pieces(legs: &[f32]) -> usize {
    let c = corridor();
    let out: Vec<Piece> = legs
        .par_chunks_exact(8)
        .flat_map_iter(|q| {
            let (ax, az, bx, bz, half) = (q[0], q[1], q[2], q[3], q[4]);
            let (dx, dz) = (bx - ax, bz - az);
            let len = (dx * dx + dz * dz).sqrt();
            let mut v = Vec::new();
            if len < 0.5 {
                return v.into_iter();
            }
            let (ux, uz) = (dx / len, dz / len);
            let spans = if half > 6.0 {
                vec![(0.0, 1.0)]
            } else {
                street_spans(c, ax, az, bx, bz, half, q[7].round() as u8)
            };
            for (t0, t1) in spans {
                if (t1 - t0) * len < 0.05 {
                    continue;
                }
                v.push(Piece {
                    ax: ax + dx * t0,
                    az: az + dz * t0,
                    ux,
                    uz,
                    len: (t1 - t0) * len,
                    half,
                    round_a: t0 <= 0.0,
                    round_b: t1 >= 1.0,
                });
            }
            v.into_iter()
        })
        .collect();
    let n = out.len();
    *PIECES.write().unwrap() = out;
    n
}

/// Paint the roads into a square `n` texels across, `half` metres either side
/// of (`cx`, `cz`): RGBA8, red the asphalt, green the kerb, blue the paint of
/// the markings (only with `lines`), alpha unused. Each channel is a signed
/// distance to its edge, 0.5 on it, rising inward and falling outward across
/// two texels either side -- so 0.5 is the edge wherever it is asked.
///
/// At a junction the widest road there owns the texel and only its markings
/// are drawn; its edge line is not drawn across the mouth of a road that meets
/// it at an angle, and nor is anyone's centre line but a wider road's over a
/// narrower one. The kerb is the band outside any road's edge, wherever no
/// road's asphalt is -- so it stops at every mouth on its own.
pub fn road_paint(n: usize, half: f32, cx: f32, cz: f32, lines: bool) -> Vec<u8> {
    let mut out = vec![0u8; n * n * 4];
    let pieces = PIECES.read().unwrap();
    if pieces.is_empty() || n == 0 {
        return out;
    }
    let tpm = n as f32 / (half * 2.0);
    let px = 1.0 / tpm;
    // which pieces reach each row
    let mut rows: Vec<Vec<u32>> = vec![Vec::new(); n];
    let mut xr: Vec<(f32, f32)> = Vec::with_capacity(pieces.len());
    for (i, p) in pieces.iter().enumerate() {
        let r = p.half * KERB_OUT + px * 2.0;
        let (bx, bz) = (p.ax + p.ux * p.len, p.az + p.uz * p.len);
        let (x0, x1) = (p.ax.min(bx) - r, p.ax.max(bx) + r);
        let (z0, z1) = (p.az.min(bz) - r, p.az.max(bz) + r);
        xr.push((x0, x1));
        if x1 < cx - half || x0 > cx + half || z1 < cz - half || z0 > cz + half {
            continue;
        }
        let j0 = (((z0 - cz + half) * tpm).floor() as i64).clamp(0, n as i64 - 1) as usize;
        let j1 = (((z1 - cz + half) * tpm).ceil() as i64).clamp(0, n as i64 - 1) as usize;
        for r in rows.iter_mut().take(j1 + 1).skip(j0) {
            r.push(i as u32);
        }
    }
    // What is stored is not how much of a texel is covered but how far its
    // centre is inside the edge -- of the asphalt, the kerb, each line -- out
    // to two texels either way. Interpolated between texels a distance is
    // still a distance, so the shader finds the edge between them, straight
    // and sharp at any angle; coverage, interpolated, stepped from texel to
    // texel, and a line along the road at a slant was a saw.
    let range = px * 4.0;
    let enc = |sd: f32| ((0.5 + sd / range).clamp(0.0, 1.0) * 255.0 + 0.5) as u8;
    out.par_chunks_mut(n * 4).enumerate().for_each(|(j, row)| {
        let bucket = &rows[j];
        if bucket.is_empty() {
            for o in (0..n * 4).step_by(4) {
                row[o] = 0;
                row[o + 1] = 0;
                row[o + 2] = 0;
                row[o + 3] = 255;
            }
            return;
        }
        let wz = (j as f32 + 0.5) / tpm - half + cz;
        // each piece's say at a texel: how far inside its asphalt, its half
        // width, lateral offset, length along
        let mut hits: Vec<(f32, f32, f32, f32, u32)> = Vec::with_capacity(8);
        for i in 0..n {
            let wx = (i as f32 + 0.5) / tpm - half + cx;
            hits.clear();
            let mut asphalt = -1e9f32;
            let mut outer = -1e9f32;
            for &pi in bucket {
                let (x0, x1) = xr[pi as usize];
                if wx < x0 || wx > x1 {
                    continue;
                }
                let p = &pieces[pi as usize];
                let (rx, rz) = (wx - p.ax, wz - p.az);
                let along = rx * p.ux + rz * p.uz;
                let lat = rx * -p.uz + rz * p.ux;
                // inside the carriageway by how much, and inside its kerb,
                // with the ends round or square
                let (sd, sk) = if along < 0.0 && p.round_a {
                    let d = (along * along + lat * lat).sqrt();
                    (p.half - d, p.half * KERB_OUT - d)
                } else if along > p.len && p.round_b {
                    let o = along - p.len;
                    let d = (o * o + lat * lat).sqrt();
                    (p.half - d, p.half * KERB_OUT - d)
                } else {
                    let ends = along.min(p.len - along);
                    (
                        (p.half - lat.abs()).min(ends),
                        (p.half * KERB_OUT - lat.abs()).min(ends),
                    )
                };
                asphalt = asphalt.max(sd);
                outer = outer.max(sk);
                if sd > -range {
                    hits.push((sd, p.half, lat, along, pi));
                }
            }
            // the kerb is inside some road's kerb line and outside every
            // road's asphalt
            let kerb = outer.min(-asphalt);
            let mut paint = -1e9f32;
            if lines && asphalt > -range {
                // the widest road here, nearest its own centreline
                let mut own: Option<&(f32, f32, f32, f32, u32)> = None;
                for h in &hits {
                    if h.0 < 0.0 {
                        continue;
                    }
                    own = match own {
                        Some(o) if o.1 > h.1 + 0.01 => Some(o),
                        Some(o) if (o.1 - h.1).abs() <= 0.01 && o.2.abs() <= h.2.abs() => Some(o),
                        _ => Some(h),
                    };
                }
                if let Some(o) = own {
                    let po = &pieces[o.4 as usize];
                    // crossed by another road here, at an angle, and how wide
                    let mut crossed = 0.0f32;
                    for h in &hits {
                        if h.4 == o.4 || h.0 < 0.0 {
                            continue;
                        }
                        let ph = &pieces[h.4 as usize];
                        if (ph.ux * po.ux + ph.uz * po.uz).abs() < 0.94 {
                            crossed = crossed.max(ph.half);
                        }
                    }
                    let a = o.2.abs();
                    // a dashed centre line, six on and six off; a wider road
                    // keeps its own across a narrower one's mouth
                    if crossed == 0.0 || po.half > crossed + 0.5 {
                        let w = 0.16;
                        // along the line through the piece, taken from the
                        // world so the pieces of a straight road agree
                        let v = (wx * po.ux + wz * po.uz).rem_euclid(12.0);
                        let dash = if v < 6.0 { v.min(6.0 - v) } else { -(v - 6.0).min(12.0 - v) };
                        paint = paint.max((w - a).min(dash));
                    }
                    // a solid line just in from each edge of a trunk road,
                    // broken across a mouth
                    if po.half > 6.0 && crossed == 0.0 {
                        let e0 = po.half - 0.55;
                        let e1 = po.half - 0.22;
                        paint = paint.max((a - e0).min(e1 - a));
                    }
                }
                // and never off the asphalt
                paint = paint.min(asphalt);
            }
            let o = i * 4;
            row[o] = enc(asphalt);
            row[o + 1] = enc(kerb);
            row[o + 2] = enc(paint);
            row[o + 3] = 255;
        }
    });
    out
}
