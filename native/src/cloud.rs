//! The cloud layer's noise, baked into one volume.
//!
//! The layer used to sample a 64-cube of *random bytes* four times over for its
//! shape and four more for its detail, and call the sum a fractal. Trilinear
//! filtering of uncorrelated bytes is value noise whose lattice is one texel, so
//! every octave was a lattice one texel wide read at a different rate -- and at
//! the scale the detail was read, one texel is 383 m of sky and the finest
//! octave 47 m. The march's first step is 571 m. Everything the detail field
//! had to say was finer than anything the march could see, so it arrived as
//! noise that changed with the camera rather than as cloud: a fizzing grey
//! sheet with no shape in it, which is what it looked like.
//!
//! So the octaves are summed here instead, once, into a volume whose finest
//! content is about a kilometre of sky -- a size the march resolves and an
//! aeroplane can fly between. Two channels: the weather system in red and the
//! clouds within it in green. The shader fetches each once rather than four
//! times, which pays for the extra march steps that were taken away to afford
//! the old one.
//!
//! Everything here is periodic. The volume is tiled over a sphere, so a field
//! that does not wrap seams along every tile boundary in the sky.

use rayon::prelude::*;

/// Where the two channels live in a texel.
pub const CHANNELS: usize = 2;

// ------------------------------------------------------------- the lattices

#[inline]
fn hash3(x: i32, y: i32, z: i32, seed: u32) -> u32 {
    let mut h = seed
        ^ (x as u32).wrapping_mul(0x9E37_79B1)
        ^ (y as u32).wrapping_mul(0x85EB_CA77)
        ^ (z as u32).wrapping_mul(0xC2B2_AE3D);
    h ^= h >> 15;
    h = h.wrapping_mul(0x2545_F491);
    h ^= h >> 13;
    h
}

/// One of the twelve cube-edge gradients, dotted with the offset. Perlin's own
/// set: no table lookup and no bias towards the axes.
#[inline]
fn grad(h: u32, dx: f32, dy: f32, dz: f32) -> f32 {
    match h % 12 {
        0 => dx + dy,
        1 => -dx + dy,
        2 => dx - dy,
        3 => -dx - dy,
        4 => dx + dz,
        5 => -dx + dz,
        6 => dx - dz,
        7 => -dx - dz,
        8 => dy + dz,
        9 => -dy + dz,
        10 => dy - dz,
        _ => -dy - dz,
    }
}

#[inline]
fn fade(t: f32) -> f32 {
    t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
}

#[inline]
fn lerp(a: f32, b: f32, t: f32) -> f32 {
    a + (b - a) * t
}

/// Gradient noise over a lattice of `f` cells to the tile, wrapping at `f`.
/// Roughly -1..1.
fn perlin(p: [f32; 3], f: i32, seed: u32) -> f32 {
    let fx = p[0] * f as f32;
    let fy = p[1] * f as f32;
    let fz = p[2] * f as f32;
    let (i0, j0, k0) = (fx.floor(), fy.floor(), fz.floor());
    let (tx, ty, tz) = (fx - i0, fy - j0, fz - k0);
    let (ux, uy, uz) = (fade(tx), fade(ty), fade(tz));
    let wrap = |v: f32| -> i32 { (v as i32).rem_euclid(f) };
    let (xi, yi, zi) = (wrap(i0), wrap(j0), wrap(k0));
    let (xj, yj, zj) = (wrap(i0 + 1.0), wrap(j0 + 1.0), wrap(k0 + 1.0));
    let g = |x: i32, y: i32, z: i32, dx: f32, dy: f32, dz: f32| {
        grad(hash3(x, y, z, seed), dx, dy, dz)
    };
    let x00 = lerp(g(xi, yi, zi, tx, ty, tz), g(xj, yi, zi, tx - 1.0, ty, tz), ux);
    let x10 = lerp(g(xi, yj, zi, tx, ty - 1.0, tz),
        g(xj, yj, zi, tx - 1.0, ty - 1.0, tz), ux);
    let x01 = lerp(g(xi, yi, zj, tx, ty, tz - 1.0),
        g(xj, yi, zj, tx - 1.0, ty, tz - 1.0), ux);
    let x11 = lerp(g(xi, yj, zj, tx, ty - 1.0, tz - 1.0),
        g(xj, yj, zj, tx - 1.0, ty - 1.0, tz - 1.0), ux);
    lerp(lerp(x00, x10, uy), lerp(x01, x11, uy), uz)
}

/// Distance to the nearest of one feature point per cell, over `f` cells to the
/// tile, scaled so it runs about 0..1. Wraps, like everything here.
///
/// This is what makes a cloud look like a cloud rather than like fog: the
/// field is a set of rounded lobes with defined edges, where gradient noise on
/// its own is a smooth swell with none.
fn worley(p: [f32; 3], f: i32, seed: u32) -> f32 {
    let fx = p[0] * f as f32;
    let fy = p[1] * f as f32;
    let fz = p[2] * f as f32;
    let (bx, by, bz) = (fx.floor() as i32, fy.floor() as i32, fz.floor() as i32);
    let mut best = f32::INFINITY;
    for oz in -1..=1 {
        for oy in -1..=1 {
            for ox in -1..=1 {
                let (cx, cy, cz) = (bx + ox, by + oy, bz + oz);
                // The nearest corner of this cell. A cell whose *closest* point
                // is further off than the best point found already cannot hold
                // a better one, and at three octaves over two million voxels
                // the cells that can be skipped are most of the twenty-seven.
                let near = |c: i32, f: f32| -> f32 {
                    let lo = c as f32;
                    if f < lo { lo - f } else if f > lo + 1.0 { f - lo - 1.0 }
                    else { 0.0 }
                };
                let (nx, ny, nz) = (near(cx, fx), near(cy, fy), near(cz, fz));
                if nx * nx + ny * ny + nz * nz >= best {
                    continue;
                }
                let h = hash3(cx.rem_euclid(f), cy.rem_euclid(f),
                    cz.rem_euclid(f), seed);
                // The cell's own point, somewhere inside it.
                let px = cx as f32 + (h & 0x3ff) as f32 / 1024.0;
                let py = cy as f32 + ((h >> 10) & 0x3ff) as f32 / 1024.0;
                let pz = cz as f32 + ((h >> 20) & 0x3ff) as f32 / 1024.0;
                let (dx, dy, dz) = (px - fx, py - fy, pz - fz);
                let d2 = dx * dx + dy * dy + dz * dz;
                if d2 < best {
                    best = d2;
                }
            }
        }
    }
    best.sqrt().min(1.0)
}

/// Octaves of gradient noise, each on its own lattice so the sum still wraps.
fn perlin_fbm(p: [f32; 3], f: i32, oct: i32, seed: u32) -> f32 {
    let mut sum = 0.0;
    let mut amp = 0.5;
    let mut norm = 0.0;
    let mut fr = f;
    for o in 0..oct {
        sum += perlin(p, fr, seed.wrapping_add(o as u32 * 131)) * amp;
        norm += amp;
        amp *= 0.5;
        fr *= 2;
    }
    sum / norm
}

/// The same for the lobes, inverted so a feature point is a lump rather than a
/// hole.
fn worley_fbm(p: [f32; 3], f: i32, oct: i32, seed: u32) -> f32 {
    let mut sum = 0.0;
    let mut amp = 0.5;
    let mut norm = 0.0;
    let mut fr = f;
    for o in 0..oct {
        sum += (1.0 - worley(p, fr, seed.wrapping_add(o as u32 * 977))) * amp;
        norm += amp;
        amp *= 0.5;
        fr *= 2;
    }
    sum / norm
}

// ------------------------------------------------------------- the volume

/// The lattice the weather system is drawn on, in cells to the tile. The tile
/// is the whole planet over `CloudShell.NOISE_SCALE`, so at eighteen that is
/// 354 km and these are systems of 88 km down to 5.5 km -- where the detail
/// channel picks the scale up.
const SHAPE_F: i32 = 4;
const SHAPE_OCT: i32 = 5;
/// And the clouds within it. The tile there is 77 km, so these run from 4.8 km
/// down to 1.2 km -- which is a cloud you can fly between and, just as much to
/// the point, a size the march can actually see. Nothing here is finer than
/// that on purpose: what the march cannot resolve does not arrive as detail, it
/// arrives as noise that moves with the camera.
const DETAIL_F: i32 = 16;
const DETAIL_OCT: i32 = 3;

/// What the old `spread` in the shader left behind: a field centred on a half
/// with this much spread either way, clipped at both ends. Reproduced here so
/// that `coverage` and `erode` still mean what they were tuned to mean -- and
/// so the byte has the whole of its range to say it in, which the stretch in
/// the shader could not give it.
const OUT_SPREAD: f32 = 0.31;

/// The layer's noise as an `n` cube of two channels: the weather system, and
/// the clouds within it.
///
/// Both channels are normalised to the distribution the shader's own stretch
/// used to produce -- measured here rather than written down, because what a
/// lattice sum's mean and spread come out at is a fact about the lattice. That
/// is what lets `coverage` and `erode` carry over unchanged from the field this
/// replaces.
pub fn volume(n: usize) -> Vec<u8> {
    let n = n.max(2);
    let scale = 1.0 / n as f32;
    // Raw first, then normalised.
    let mut raw = vec![0f32; n * n * n * CHANNELS];
    raw.par_chunks_mut(n * CHANNELS)
        .enumerate()
        .for_each(|(row, out)| {
            let j = row % n;
            let k = row / n;
            let y = (j as f32 + 0.5) * scale;
            let z = (k as f32 + 0.5) * scale;
            for i in 0..n {
                let p = [(i as f32 + 0.5) * scale, y, z];
                // The weather system: gradient noise given edges by the lobes,
                // which is what turns a smooth swell into something with a
                // shape to it.
                let base = (perlin_fbm(p, SHAPE_F, SHAPE_OCT, 0x51ED_2701) + 1.0)
                    * 0.5;
                let lobes = worley_fbm(p, SHAPE_F, 3, 0x1F12_9A03);
                out[i * CHANNELS] = base * 0.62 + lobes * 0.38;
                out[i * CHANNELS + 1] =
                    worley_fbm(p, DETAIL_F, DETAIL_OCT, 0x77C3_5B19);
            }
        });
    let mut out = vec![0u8; n * n * n * CHANNELS];
    for ch in 0..CHANNELS {
        let count = (n * n * n) as f64;
        let mut sum = 0.0f64;
        let mut sum2 = 0.0f64;
        for v in raw.iter().skip(ch).step_by(CHANNELS) {
            sum += *v as f64;
            sum2 += (*v as f64) * (*v as f64);
        }
        let mean = sum / count;
        let var = (sum2 / count - mean * mean).max(1e-12);
        let gain = OUT_SPREAD / var.sqrt() as f32;
        for (o, v) in out.iter_mut().skip(ch).step_by(CHANNELS)
                .zip(raw.iter().skip(ch).step_by(CHANNELS)) {
            let t = ((*v - mean as f32) * gain + 0.5).clamp(0.0, 1.0);
            *o = (t * 255.0 + 0.5) as u8;
        }
    }
    out
}
