# ♠ Poker Settle Up

A single-page app that tells a poker table who should Venmo / Cash App / Zelle whom, using the **fewest possible payments**.

**Live:** https://jayraypang.github.io/poker-settle-up/ · **Benchmark:** https://jayraypang.github.io/poker-settle-up/bench/

Enter each player's buy-in (rebuys like `20+20+40` work) and final cash-out. If the totals don't match, the app asks you to recount; otherwise it lists the payments. On a phone, open the link and use **Add to Home Screen** to get an app icon.

## The math

### Nets

For player $i$ with buy-in $\text{in}_i$ and cash-out $\text{out}_i$ (in cents), the net is

$$
b_i = \text{out}_i - \text{in}_i, \qquad \sum_{i=1}^{n} b_i = 0 .
$$

Players with $b_i = 0$ are dropped; let $n$ be the number left.

### Fewest payments

Split the players into groups $G_1, \dots, G_k$ where every group sums to zero. Each group of size $|G_j|$ can settle internally with $|G_j| - 1$ payments, so the total is $\sum_j (|G_j| - 1) = n - k$. Therefore

$$
\text{min payments} = n - k^{*},
$$

where $k^{*}$ is the largest number of disjoint zero-sum groups the players can be split into.

This is optimal. Draw each payment as an edge between two players. Every connected component of that graph must sum to zero (money only moves inside it), and a component with $v$ players needs at least $v - 1$ edges to be connected. So any valid set of payments has at least $n - (\text{number of components}) \ge n - k^{*}$ edges.

### Finding $k^{*}$ (subset DP)

Represent each subset $S$ of players as a bitmask. Let $\sigma(S) = \sum_{i \in S} b_i$, and define

$$
dp(\varnothing) = 0, \qquad
dp(S) = \max_{i \in S} \; dp\big(S \setminus \lbrace i \rbrace\big) \;+\; \big[\,\sigma(S) = 0\,\big],
$$

where $[\cdot]$ is 1 if true and 0 otherwise. Then $k^{*} = dp(\text{all players})$.

Intuition: remove players one at a time; every time the set of players still in play sums to zero, one group has just been closed off. $dp(S)$ is the most groups you can close off from $S$ by choosing the best removal order.

This takes $O(n \cdot 2^n)$ time. At 24 players there are about 16.7 million subsets.

### Recovering the payments

Walk back from the full set. At each step, remove any player $i$ with $dp(S \setminus \lbrace i \rbrace) + [\sigma(S) = 0] = dp(S)$, and start a new group whenever $\sigma(S) = 0$. Within each group, the player who owes the most pays the player owed the most, repeated until the group is square. Every payment clears at least one player, so a group of size $m$ uses at most $m - 1$ payments.

Since $k^*$ is at most $n/2$ with no zero nets, the answer is always between $\lceil n/2 \rceil$ and $n - 1$ payments.

## Implementation

The DP runs in [`solver/settle.zig`](solver/settle.zig), compiled to a ~1.6 KB freestanding WebAssembly module with SIMD and embedded in the page as base64:

- Masks are processed in aligned blocks of 16 (the low 4 player bits), so one block is one 16-lane `u8` vector.
- Removing a higher player maps a block onto an earlier block at the same lanes, so each one costs a single vector load and max.
- Removing one of the low 4 players stays inside the block. That is resolved with lane shuffles in 4 rounds, one per bit-count level.
- Subset sums are stored once per block and rebuilt per lane as `base + [sums of the low 4 players]`, which cuts memory to about $1.25 \cdot 2^n$ bytes.

The page then walks the resulting `dp` table in JavaScript to recover the groups. If WebAssembly isn't available (for example, iOS Lockdown Mode) or there are more than 24 players who didn't break even, it falls back to the greedy step on the whole table. That still settles everyone correctly but may use more payments than the minimum.

For comparison, [`/bench/`](bench/) runs the Zig solver side by side with the original plain-JavaScript DP. On a desktop the Zig solver is about 60–70× faster; at 24 players it takes ~15 ms versus ~1.1 s.

## Project layout

```
index.html          the app (HTML + CSS + JS, WASM inlined)
bench/index.html    JS vs Zig/WASM benchmark
solver/settle.zig   the SIMD subset-DP solver
solver/build.mjs    compiles the Zig and inlines it into both pages
```

## Building

Requires [Zig](https://ziglang.org/) 0.16 and Node.js. After changing `settle.zig`:

```bash
node solver/build.mjs
```

Set `ZIG=/path/to/zig` if `zig` isn't on your `PATH`. The script rewrites the `const WASM_B64 = "…";` line in both HTML files. Commit the result and GitHub Pages redeploys from `main`.
