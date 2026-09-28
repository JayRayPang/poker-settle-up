//! Minimum-payments settle-up solver compiled to freestanding WASM + SIMD128.
//!
//! min payments = n - (max number of disjoint zero-sum groups). We compute
//! that maximum with the subset DP
//!     dp[m] = max_{i in m} dp[m without i] + (sum(m) == 0 ? 1 : 0)
//! but process masks in aligned blocks of 16 (the low 4 player bits) so each
//! block is one u8x16 vector:
//!   * removing a high bit (player >= 4) maps a block onto an earlier block,
//!     same lanes -> one vector load + max per set high bit;
//!   * removing a low bit stays inside the block -> lane shuffles, resolved
//!     in 4 rounds (one per popcount level of the low nibble).
//! Subset sums are only stored per block (lane 0); the 16 lanes are
//! reconstructed as base + a constant vector of low-nibble sums.
//! After a call, `dpPtr()[m]` holds dp[m] for every mask m (block layout is
//! just m = block * 16 + lane), which JS walks to recover the groups.

const V16u8 = @Vector(16, u8);
const V16i32 = @Vector(16, i32);

const max_players = 32;
var nets: [max_players]i32 = undefined;

var heap_start: usize = 0;
var heap_cap: usize = 0;

/// JS writes player nets (in cents) here before calling `minPayments`.
export fn netsPtr() [*]i32 {
    return &nets;
}

/// dp table from the last `minPayments` call (2^max(n, 4) bytes).
export fn dpPtr() [*]u8 {
    return @ptrFromInt(heap_start);
}

fn ensureHeap(bytes: usize) bool {
    if (heap_start == 0) {
        heap_start = @wasmMemorySize(0) * 65536;
        heap_cap = heap_start;
    }
    const need = heap_start + bytes;
    if (need > heap_cap) {
        const pages = (need - heap_cap + 65535) / 65536;
        if (@wasmMemoryGrow(0, pages) < 0) return false;
        heap_cap += pages * 65536;
    }
    return true;
}

/// lane index -> lane index with low bit `j` flipped
fn flipMask(comptime j: u2) @Vector(16, i32) {
    var m: [16]i32 = undefined;
    for (0..16) |lo| m[lo] = @intCast(lo ^ (@as(usize, 1) << j));
    return m;
}

/// lanes whose low nibble has bit `j` set
fn hasBit(comptime j: u2) @Vector(16, bool) {
    var m: [16]bool = undefined;
    for (0..16) |lo| m[lo] = (lo >> j) & 1 == 1;
    return m;
}

/// Returns the minimum number of payments for the first `n_in` nets,
/// or -1 if memory could not be allocated.
export fn minPayments(n_in: u32) i32 {
    if (n_in > 28) return -1;
    // Pad to 4 players with zeros; each zero forms its own zero-sum group,
    // so n - groups is unchanged.
    var n: u32 = n_in;
    while (n < 4) : (n += 1) nets[n] = 0;

    const blocks: usize = @as(usize, 1) << @intCast(n - 4);
    const dp_bytes = blocks * 16;
    if (!ensureHeap(dp_bytes + blocks * 4)) return -1;
    const dp: [*]u8 = @ptrFromInt(heap_start);
    const base: [*]i32 = @ptrFromInt(heap_start + dp_bytes);

    var low: [16]i32 = undefined;
    for (0..16) |lo| {
        var s: i32 = 0;
        for (0..4) |j| {
            if ((lo >> @intCast(j)) & 1 == 1) s += nets[j];
        }
        low[lo] = s;
    }
    const low_sums: V16i32 = low;
    const zeros: V16u8 = @splat(0);
    const ones: V16u8 = @splat(1);

    base[0] = 0;
    var b: usize = 0;
    while (b < blocks) : (b += 1) {
        if (b != 0) base[b] = base[b & (b - 1)] + nets[4 + @ctz(b)];

        const sums = low_sums + @as(V16i32, @splat(base[b]));
        var z = @select(u8, sums == @as(V16i32, @splat(0)), ones, zeros);
        if (b == 0) z[0] = 0; // empty set is not a group

        var acc = zeros;
        var r = b;
        while (r != 0) : (r &= r - 1) {
            const prev: V16u8 = dp[(b ^ (r & (~r +% 1))) * 16 ..][0..16].*;
            acc = @max(acc, prev);
        }

        var cur = acc + z;
        inline for (0..4) |_| {
            var cand = acc;
            inline for (0..4) |j| {
                const sh = @shuffle(u8, cur, undefined, flipMask(j));
                cand = @select(u8, comptime hasBit(j), @max(cand, sh), cand);
            }
            cur = cand + z;
        }
        dp[b * 16 ..][0..16].* = cur;
    }
    return @as(i32, @intCast(n)) - @as(i32, dp[blocks * 16 - 1]);
}
