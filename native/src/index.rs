//! Integer cell keys and the hash they are looked up with.

/// A cheap hash for integer cell keys.
///
/// The road search does a handful of map operations per neighbour and expands
/// tens of thousands of nodes per leg, so this runs into the tens of millions
/// per route. The standard library hashes with SipHash, which is the right
/// default for a map that might see hostile keys and entirely wasted on a grid
/// coordinate.
#[derive(Default, Clone, Copy)]
pub struct FxHasher {
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

pub type FxBuild = std::hash::BuildHasherDefault<FxHasher>;
pub type Map<K, V> = std::collections::HashMap<K, V, FxBuild>;

/// A cell as one integer. Packed rather than multiplied and added: `ci * N + cj`
/// cannot be taken apart again once `cj` is negative, which is half the map.
#[inline]
pub fn key(i: i32, j: i32) -> i64 {
    ((i as i64) << 32) ^ (j as i64 & 0xffff_ffff)
}

/// A uniform grid over line segments, for "what is the nearest road" without
/// walking every road on a twelve hundred kilometre map.
///
/// Buckets hold segment indices; a query looks at the nine cells around the
/// point and then widens the ring until the best distance found is inside the
/// ring it has already searched. That last part is what makes it exact: a
/// fixed nine-cell probe is only correct while something is guaranteed to be
/// within a cell and a half, which out in open country it is not.
pub struct SegGrid {
    pub cell: f32,
    /// ax, az, dx, dz, 1/len2 per segment
    pub segs: Vec<[f32; 5]>,
    pub grid: Map<i64, Vec<u32>>,
}

impl SegGrid {
    pub fn build(pairs: &[f32], cell: f32) -> SegGrid {
        let mut g = SegGrid {
            cell,
            segs: Vec::with_capacity(pairs.len() / 4),
            grid: Map::default(),
        };
        for q in pairs.chunks_exact(4) {
            let (ax, az, bx, bz) = (q[0], q[1], q[2], q[3]);
            let dx = bx - ax;
            let dz = bz - az;
            let idx = g.segs.len() as u32;
            g.segs.push([ax, az, dx, dz, 1.0 / (dx * dx + dz * dz).max(1e-9)]);
            let len = (dx * dx + dz * dz).sqrt();
            let steps = ((len / (cell * 0.5)) as i32).max(1);
            for k in 0..=steps {
                let t = k as f32 / steps as f32;
                let ci = ((ax + dx * t) / cell).floor() as i32;
                let cj = ((az + dz * t) / cell).floor() as i32;
                let e = g.grid.entry(key(ci, cj)).or_default();
                if e.last() != Some(&idx) {
                    e.push(idx);
                }
            }
        }
        g
    }

    #[inline]
    fn ring(&self, x: f32, z: f32, ci: i32, cj: i32, r: i32, best2: &mut f32) {
        let mut probe = |i: i32, j: i32| {
            if let Some(b) = self.grid.get(&key(i, j)) {
                for s in b {
                    let sg = &self.segs[*s as usize];
                    let px = x - sg[0];
                    let pz = z - sg[1];
                    let t = ((px * sg[2] + pz * sg[3]) * sg[4]).clamp(0.0, 1.0);
                    let qx = px - sg[2] * t;
                    let qz = pz - sg[3] * t;
                    let d2 = qx * qx + qz * qz;
                    if d2 < *best2 {
                        *best2 = d2;
                    }
                }
            }
        };
        if r == 0 {
            probe(ci, cj);
            return;
        }
        for i in (ci - r)..=(ci + r) {
            probe(i, cj - r);
            probe(i, cj + r);
        }
        for j in (cj - r + 1)..=(cj + r - 1) {
            probe(ci - r, j);
            probe(ci + r, j);
        }
    }

    /// Distance from a point to the nearest segment, exactly. `far` caps how
    /// wide the search will spread before giving up.
    pub fn distance(&self, x: f32, z: f32, far: f32) -> f32 {
        if self.segs.is_empty() {
            return far;
        }
        let ci = (x / self.cell).floor() as i32;
        let cj = (z / self.cell).floor() as i32;
        let max_r = ((far / self.cell).ceil() as i32).max(1);
        let mut best2 = f32::INFINITY;
        let mut r = 0;
        loop {
            self.ring(x, z, ci, cj, r, &mut best2);
            // Anything outside the ring already searched is at least this far
            // away, so once the best beats that the answer cannot improve.
            let guaranteed = r as f32 * self.cell;
            if best2 <= guaranteed * guaranteed || r >= max_r {
                break;
            }
            r += 1;
        }
        best2.sqrt().min(far)
    }
}
