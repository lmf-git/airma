//! The things the world is drawn from that are one arithmetic rule asked for
//! several million points: the ground mask, the climate texture, the road
//! ribbons and the map relief.
//!
//! All of them were loops in script over a worker pool, and every one of them
//! paid a crossing of the extension boundary per sample to ask how high the
//! ground was. Here they are one call each, and the loop is inside.

use crate::field::{climate, lerp, smoothstep, WATER_LEVEL};
use crate::index::SegGrid;
use crate::world::{base, carve_road, corridor, ground_at, world, Corridor, G_ALL,
    ROAD_FILL_MAX};
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

// ------------------------------------------------------------- road ribbons

/// The drawn surface of one road: a carriageway and a kerb strip either side,
/// hugging the ground closely enough not to float over it.
///
/// Four height samples every eleven metres of every leg, and with a settlement
/// network spread across the map that was two and a half seconds -- the single
/// largest thing left in world generation. Every one of those samples used to
/// be its own crossing of the boundary.
pub struct Ribbon {
    pub surf: Vec<[f32; 3]>,
    pub kerb: Vec<[f32; 3]>,
}

fn strip(out: &mut Vec<[f32; 3]>, a: [f32; 3], b: [f32; 3], c: [f32; 3], d: [f32; 3]) {
    out.extend_from_slice(&[a, b, c, a, c, d]);
}

/// One leg of road. `ya`/`yb` are the design height at its two ends, and
/// `deck` says the leg is a bridge approach or a tunnel portal: it runs on the
/// design surface alone, because that is what it has to meet.
#[allow(clippy::too_many_arguments)]
fn ribbon(c: &Corridor, ax: f32, az: f32, bx: f32, bz: f32, half: f32,
        ya: f32, yb: f32, deck: bool) -> Ribbon {
    let mut out = Ribbon { surf: Vec::new(), kerb: Vec::new() };
    let dx = bx - ax;
    let dz = bz - az;
    let len = (dx * dx + dz * dz).sqrt();
    if len < 1.0 {
        return out;
    }
    let w = world();
    // One quad is enough for a leg shorter than a step. Routing chops the trunk
    // network into thousands of short segments, and a floor of two steps gave
    // every fifteen metre piece four rows of samples it had no detail to fill.
    let trunk = half > 6.0;
    let steps = ((len / if trunk { 11.0 } else { 17.0 }).round() as i32).max(1);
    let nx = -dz / len;
    let nz = dx / len;
    const OFF: [f32; 4] = [-1.55, -1.0, 1.0, 1.55];
    let mut prev = [[0.0f32; 3]; 4];
    for i in 0..=steps {
        let t = i as f32 / steps as f32;
        let px = ax + dx * t;
        let pz = az + dz * t;
        let mut row = [[0.0f32; 3]; 4];
        for (k, o) in OFF.iter().enumerate() {
            let qx = px + nx * half * o;
            let qz = pz + nz * half * o;
            let mut y;
            if deck {
                // The approach to a structure. Drawn on the ground, the
                // carriageway stopped at the abutment and started again on the
                // far side, with the deck floating clear of both; the alignment
                // is continuous whatever the country under it does, so this is
                // the one stretch that follows it and nothing else.
                y = lerp(ya, yb, t);
            } else if trunk {
                // A trunk road on an embankment rides on the design surface,
                // not on whatever is underneath it -- but only as far as the
                // ground was actually raised to meet it. Drawn on the design
                // whatever the fill limit did, the carriageway hung in the air
                // over an untouched hillside.
                //
                // Both out of one walk of the corridor: the ground here *is*
                // the design surface applied to the land, so working it out and
                // then asking for it again separately is the same grid walked
                // twice, and that was most of what this cost.
                let (h, (ry, rw, rg)) =
                    carve_road(w, c, base(qx, qz), qx, qz, G_ALL);
                y = h;
                if rw > 0.35 && ry - rg <= ROAD_FILL_MAX * 1.25 {
                    y = y.max(ry);
                }
            } else {
                y = ground_at(w, c, qx, qz, G_ALL);
            }
            row[k] = [qx, y + 0.16, qz];
        }
        // lift the surface to the highest of the two kerbs so it never sinks in
        let top = row[1][1].max(row[2][1]);
        row[1][1] = top;
        row[2][1] = top;
        row[0][1] = row[0][1].min(top) - 0.04;
        row[3][1] = row[3][1].min(top) - 0.04;
        if i > 0 {
            strip(&mut out.surf, prev[1], prev[2], row[2], row[1]);
            strip(&mut out.kerb, prev[0], prev[1], row[1], row[0]);
            strip(&mut out.kerb, prev[2], prev[3], row[3], row[2]);
        }
        prev = row;
    }
    out
}

/// One ribbon per leg, before they are put together.
///
/// Split out because the bucketed form wants them *apart*: joined into one pair
/// of lists and then sorted into cells, a million triangles are copied twice
/// over -- forty megabytes each way -- to arrive somewhere they could have been
/// put in the first place.
pub fn ribbon_parts(legs: &[f32]) -> Vec<Ribbon> {
    let c = corridor();
    legs.par_chunks_exact(8)
        .map(|q| ribbon(c, q[0], q[1], q[2], q[3], q[4], q[5], q[6], q[7] > 0.5))
        .collect()
}

/// Every road and street on the map, as two vertex lists. `legs` is a flat run
/// of ax, az, bx, bz, half, design a, design b, and whether it is a structure
/// approach.
pub fn ribbons(legs: &[f32]) -> Ribbon {
    let parts = ribbon_parts(legs);
    let ns: usize = parts.iter().map(|p| p.surf.len()).sum();
    let nk: usize = parts.iter().map(|p| p.kerb.len()).sum();
    let mut all = Ribbon {
        surf: Vec::with_capacity(ns),
        kerb: Vec::with_capacity(nk),
    };
    for p in &parts {
        all.surf.extend_from_slice(&p.surf);
        all.kerb.extend_from_slice(&p.kerb);
    }
    all
}

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
