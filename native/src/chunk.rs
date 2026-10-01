//! One leaf of the terrain quadtree, from the height field to the vertex
//! arrays the mesh is made of.
//!
//! This was the last large loop left in script. A chunk is 289 grid heights and
//! about six hundred more around its border, and out of them come 1920 vertices
//! with a normal, a morph target and the normal of the surface the level above
//! draws. The heights were already asked for in one call -- that part was done
//! -- but the assembly around them was still GDScript walking packed arrays a
//! Vector3 at a time, on a worker, and it was the largest single item in world
//! generation and the reason crossing a detail boundary in flight cost a frame.
//!
//! The rule is unchanged: this is a transcription of what the script did, not a
//! new one. Where the two could differ they must not, because the *neighbour*
//! of a chunk is meshed by the same code and a seam is what disagreement looks
//! like.

use crate::world::Ground;

/// Cells across a chunk, at every level. Mirrors `Terrain.CELLS`.
pub const CELLS: usize = 16;
/// Cells across the level above, which is what the morph target is drawn on.
/// Mirrors `Terrain.HALF_CELLS`.
const HALF_CELLS: i32 = 8;
/// The finest cell the ground can hold. Mirrors `Terrain.BASE_CELL`.
const BASE_CELL: f32 = 15.0;
/// 15 x 16 x 8192. Mirrors `Terrain.ROOT_SPAN`.
pub const ROOT_SPAN: f32 = BASE_CELL * CELLS as f32 * 8192.0;

/// Vertices in a chunk: two triangles a cell, plus the skirt's four curtains of
/// two triangles each. Mirrors the script's `count`.
pub const VERTS: usize = CELLS * CELLS * 6 + CELLS * 24;

#[inline]
pub fn span_at(depth: i32) -> f32 {
    ROOT_SPAN / (1i64 << depth.clamp(0, 40)) as f32
}

// -------------------------------------------------------------- the chunk

/// Everything a chunk is, as plain arrays.
pub struct Chunk {
    pub verts: Vec<[f32; 3]>,
    pub nrms: Vec<[f32; 3]>,
    /// How far the level above draws each vertex from where this one does, and
    /// how wide this chunk is -- the band the blend runs over.
    pub morph: Vec<[f32; 2]>,
    /// The normal of the surface the level above draws, as a tangent array so
    /// the shader can blend the shading along with the shape.
    pub cnrm: Vec<f32>,
    /// What the edge stitching left behind, which is the number the seam
    /// harnesses gate on.
    pub residual: f32,
}

#[inline]
fn edge_point(side: usize, t: f32, x0: f32, z0: f32, span: f32) -> (f32, f32) {
    match side {
        0 => (x0, z0 + t),
        1 => (x0 + span, z0 + t),
        2 => (x0 + t, z0),
        _ => (x0 + t, z0 + span),
    }
}

#[inline]
fn edge_index(side: usize, i: usize, n: usize) -> usize {
    match side {
        0 => i * n,
        1 => i * n + n - 1,
        2 => i,
        _ => (n - 1) * n + i,
    }
}

/// The height the coarser neighbour draws at one of our edge vertices: its two
/// nearest vertices on that edge, linearly interpolated, which is what its
/// triangles do between them.
///
/// In double, and every height-derived intermediate here is. The grid is stored
/// single because that is what a mesh holds, and out at the edge of the world
/// the drop puts these heights near -28 km, where a single carries four
/// millimetres. Interpolating in single and rounding once is a different number
/// from interpolating in double and rounding once -- and the *residual* below
/// is the difference between the two, which is precisely what the seam
/// harnesses are asked to measure. Computed single throughout, the residual
/// comes out an exact zero by construction and the harness measures nothing.
#[inline]
fn coarse_from(eh: &[f32], at: usize, v: f64, big: f64) -> f64 {
    let t = (v - (v / big).floor() * big) / big;
    let (a, b) = (eh[at] as f64, eh[at + 1] as f64);
    a + (b - a) * t
}

/// Build one leaf. `nb` is what each of the four edges meets, already clamped
/// to this chunk's own depth, and `fine` marks the edges a *finer* neighbour
/// has conformed itself to.
///
/// The ground is handed in rather than gathered here: a batch builds hundreds
/// of these at once across every core, and gathering it per chunk is hundreds
/// of threads taking the same lock to read a list that has not changed.
pub fn build(g: &Ground, depth: i32, ix: i32, iz: i32, nb: [i32; 4], fine: u32)
        -> Chunk {
    let span = span_at(depth);
    let cell = span / CELLS as f32;
    let x0 = ix as f32 * span;
    let z0 = iz as f32 * span;
    let n = CELLS + 1;

    // The grid itself.
    let mut h = vec![0f32; n * n];
    for j in 0..n {
        let z = z0 + j as f32 * cell;
        for i in 0..n {
            h[j * n + i] = g.at(x0 + i as f32 * cell, z);
        }
    }

    // Every height the border needs. First the pairs a coarser neighbour
    // interpolates between, then eight points around each border vertex -- four
    // for its normal and four for the normal of the surface above.
    let big2 = cell * 2.0;
    let mut eh: Vec<f32> = Vec::with_capacity(4 * (n - 2) * 2 + 4 * (n - 1) * 8);
    for (side, &nd) in nb.iter().enumerate() {
        if nd >= depth {
            continue;
        }
        let big = span_at(nd) / CELLS as f32;
        for i in 1..n - 1 {
            let (px, pz) = edge_point(side, i as f32 * cell, x0, z0, span);
            if side >= 2 {
                let lo = (px / big).floor() * big;
                eh.push(g.at(lo, pz));
                eh.push(g.at(lo + big, pz));
            } else {
                let lo = (pz / big).floor() * big;
                eh.push(g.at(px, lo));
                eh.push(g.at(px, lo + big));
            }
        }
    }
    let nrm_base = eh.len();
    for j in 0..n {
        for i in 0..n {
            if !(i == 0 || j == 0 || i == n - 1 || j == n - 1) {
                continue;
            }
            let px = x0 + i as f32 * cell;
            let pz = z0 + j as f32 * cell;
            for (dx, dz) in [
                (cell, 0.0),
                (-cell, 0.0),
                (0.0, cell),
                (0.0, -cell),
                (big2, 0.0),
                (-big2, 0.0),
                (0.0, big2),
                (0.0, -big2),
            ] {
                eh.push(g.at(px + dx, pz + dz));
            }
        }
    }

    // Stitch the edges that face a coarser neighbour. Only the coarse side of a
    // boundary is deferred to, so exactly one of the two chunks moves and they
    // cannot both chase each other. The corners belong to both edges at once
    // and are left on the raw field, where both sides read the same height.
    let mut at = 0usize;
    for (side, &nd) in nb.iter().enumerate() {
        if nd >= depth {
            continue;
        }
        let big = (span_at(nd) / CELLS as f32) as f64;
        for i in 1..n - 1 {
            let (px, pz) = edge_point(side, i as f32 * cell, x0, z0, span);
            let v = if side >= 2 { px } else { pz } as f64;
            h[edge_index(side, i, n)] = coarse_from(&eh, at, v, big) as f32;
            at += 2;
        }
    }

    // What the stitching left behind, measured rather than assumed.
    let mut residual = 0.0f32;
    let mut at = 0usize;
    for (side, &nd) in nb.iter().enumerate() {
        if nd >= depth {
            continue;
        }
        let big = (span_at(nd) / CELLS as f32) as f64;
        for i in 1..n - 1 {
            let (px, pz) = edge_point(side, i as f32 * cell, x0, z0, span);
            let v = if side >= 2 { px } else { pz } as f64;
            let d = (h[edge_index(side, i, n)] as f64
                - coarse_from(&eh, at, v, big)).abs() as f32;
            if d > residual {
                residual = d;
            }
            at += 2;
        }
    }

    // What the level above draws at each of our grid points. Even indices sit
    // on the parent's grid and read the same height; the odd ones in between
    // are where the two surfaces part company, and that difference is what gets
    // morphed away. Taken from the grid we already have, so it costs no
    // samples at all.
    let mut hc = vec![0f32; n * n];
    for j in 0..n {
        let pj = ((j as i32) >> 1).min(HALF_CELLS - 1);
        let tz = (j as f64 - (pj * 2) as f64) * 0.5;
        let b0 = (pj * 2) as usize;
        for i in 0..n {
            let pi = ((i as i32) >> 1).min(HALF_CELLS - 1);
            let tx = (i as f64 - (pi * 2) as f64) * 0.5;
            let a0 = (pi * 2) as usize;
            let h00 = h[b0 * n + a0] as f64;
            let h10 = h[b0 * n + a0 + 2] as f64;
            let h11 = h[(b0 + 2) * n + a0 + 2] as f64;
            let h01 = h[(b0 + 2) * n + a0] as f64;
            // the same diagonal the chunks are triangulated on
            hc[j * n + i] = if tz <= tx {
                h00 + (h10 - h00) * tx + (h11 - h10) * tz
            } else {
                h00 + (h11 - h01) * tx + (h01 - h00) * tz
            } as f32;
        }
    }
    // Pin the edges a finer neighbour has conformed itself to: if this chunk
    // morphs an edge the fine side has already matched, the two part company.
    for e in 0..4 {
        if fine & (1 << e) == 0 {
            continue;
        }
        for t in 0..n {
            let a = edge_index(e, t, n);
            hc[a] = h[a];
        }
    }

    // Per vertex normals, taken from the gradient of the field rather than from
    // the triangle -- and the same for the surface the level above draws, which
    // the morph blends towards, sampled two of our cells apart because two of
    // ours is one of its.
    let mut vn = vec![[0f32; 3]; n * n];
    let mut cvn = vec![[0f32; 3]; n * n];
    let cell64 = cell as f64;
    let big = cell64 * 2.0;
    let mut nrm_at = 0usize;
    let d = |k: usize| eh[k] as f64;
    for j in 0..n {
        for i in 0..n {
            let (gx, gz, cx, cz);
            if i == 0 || j == 0 || i == n - 1 || j == n - 1 {
                // Off the field, not off this chunk's grid: a one sided
                // difference at the border gives a different answer from the
                // one the chunk next door works out for the very same vertex,
                // and the ground picks up a shading seam along every edge.
                let b = nrm_base + nrm_at * 8;
                nrm_at += 1;
                gx = (d(b) - d(b + 1)) / (2.0 * cell64);
                gz = (d(b + 2) - d(b + 3)) / (2.0 * cell64);
                cx = (d(b + 4) - d(b + 5)) / (2.0 * big);
                cz = (d(b + 6) - d(b + 7)) / (2.0 * big);
            } else {
                gx = (h[j * n + i + 1] as f64 - h[j * n + i - 1] as f64)
                    / (2.0 * cell64);
                gz = (h[(j + 1) * n + i] as f64 - h[(j - 1) * n + i] as f64)
                    / (2.0 * cell64);
                let l2 = i.saturating_sub(2);
                let r2 = (i + 2).min(n - 1);
                let f2 = j.saturating_sub(2);
                let b2 = (j + 2).min(n - 1);
                cx = (hc[j * n + r2] as f64 - hc[j * n + l2] as f64)
                    / ((r2 - l2) as f64 * cell64);
                cz = (hc[b2 * n + i] as f64 - hc[f2 * n + i] as f64)
                    / ((b2 - f2) as f64 * cell64);
            }
            vn[j * n + i] = normalized([-gx as f32, 1.0, -gz as f32]);
            cvn[j * n + i] = normalized([-cx as f32, 1.0, -cz as f32]);
        }
    }

    let mut out = Chunk {
        verts: Vec::with_capacity(VERTS),
        nrms: Vec::with_capacity(VERTS),
        morph: Vec::with_capacity(VERTS),
        cnrm: Vec::with_capacity(VERTS * 4),
        residual,
    };
    for j in 0..CELLS {
        for i in 0..CELLS {
            let q00 = j * n + i;
            let q10 = j * n + i + 1;
            let q11 = (j + 1) * n + i + 1;
            let q01 = (j + 1) * n + i;
            let xa = x0 + i as f32 * cell;
            let xb = x0 + (i + 1) as f32 * cell;
            let za = z0 + j as f32 * cell;
            let zb = z0 + (j + 1) as f32 * cell;
            let a = [xa, h[q00], za];
            let b = [xb, h[q10], za];
            let c = [xb, h[q11], zb];
            let d = [xa, h[q01], zb];
            let ma = (hc[q00] as f64 - h[q00] as f64) as f32;
            let mb = (hc[q10] as f64 - h[q10] as f64) as f32;
            let mc = (hc[q11] as f64 - h[q11] as f64) as f32;
            let md = (hc[q01] as f64 - h[q01] as f64) as f32;
            out.face([a, b, c], [ma, mb, mc], [vn[q00], vn[q10], vn[q11]],
                [cvn[q00], cvn[q10], cvn[q11]]);
            out.face([a, c, d], [ma, mc, md], [vn[q00], vn[q11], vn[q01]],
                [cvn[q00], cvn[q11], cvn[q01]]);
        }
    }
    out.skirt(x0, z0, cell, &h, n);
    // every vertex carries how wide its chunk is, which is the band it blends
    // over
    for m in out.morph.iter_mut() {
        m[1] = span;
    }
    out
}

impl Chunk {
    fn face(&mut self, vs: [[f32; 3]; 3], ms: [f32; 3], ns: [[f32; 3]; 3],
            ks: [[f32; 3]; 3]) {
        for i in 0..3 {
            self.verts.push(vs[i]);
            self.nrms.push(ns[i]);
            self.morph.push([ms[i], 0.0]);
            self.cnrm.extend_from_slice(&[ks[i][0], ks[i][1], ks[i][2], 1.0]);
        }
    }

    /// A vertical curtain around the chunk edge so a coarser neighbour cannot
    /// show daylight through the seam. A few centimetres is ample: the boundary
    /// stitching already pulls the crack to a fraction of a millimetre, and a
    /// curtain hanging kilometres under a coarse leaf is visible from anywhere
    /// at or below sea level.
    fn skirt(&mut self, x0: f32, z0: f32, cell: f32, h: &[f32], n: usize) {
        let drop = (cell * 0.004).clamp(0.15, 0.6);
        let far = CELLS as f32 * cell;
        for i in 0..CELLS {
            let xa = x0 + i as f32 * cell;
            let xb = x0 + (i + 1) as f32 * cell;
            let za = z0 + i as f32 * cell;
            let zb = z0 + (i + 1) as f32 * cell;
            let edges = [
                ([xa, h[i], z0], [xb, h[i + 1], z0]),
                ([xb, h[CELLS * n + i + 1], z0 + far], [xa, h[CELLS * n + i], z0 + far]),
                ([x0, h[(i + 1) * n], zb], [x0, h[i * n], za]),
                ([x0 + far, h[i * n + CELLS], za], [x0 + far, h[(i + 1) * n + CELLS], zb]),
            ];
            for (a, b) in edges {
                let a2 = [a[0], a[1] - drop, a[2]];
                let b2 = [b[0], b[1] - drop, b[2]];
                for v in [a, b, b2, a, b2, a2] {
                    self.verts.push(v);
                    self.nrms.push([0.0, 1.0, 0.0]);
                    // the curtain hangs from the edge, which is conformed and
                    // so never morphs; a morph of its own would peel it away
                    self.morph.push([0.0, 0.0]);
                    self.cnrm.extend_from_slice(&[0.0, 1.0, 0.0, 1.0]);
                }
            }
        }
    }
}

#[inline]
fn normalized(v: [f32; 3]) -> [f32; 3] {
    let l2 = v[0] * v[0] + v[1] * v[1] + v[2] * v[2];
    if l2 <= 0.0 {
        return [0.0, 1.0, 0.0];
    }
    let l = l2.sqrt();
    [v[0] / l, v[1] / l, v[2] / l]
}
