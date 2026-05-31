# GEMM Operand Reuse / Bandwidth Optimization Spec

## 1. Purpose

This document records the completed GEMM operand-reuse and bandwidth-reduction milestones after the 2-lane MAC datapath and stress / CDC hardening work.

Current baseline:

```text
P2: 2-lane GEMM MAC datapath prototype completed
P3: 2-lane stress / CDC hardening completed
P4: B-cache operand reuse optimization completed
P5: packed B-cache preload optimization completed
P6: scalar A-row cache optimization completed
P7: packed A-row preload optimization completed
P8: cache-backed true 4-lane MAC completed
P9: larger-dimension / cache-size scaling completed
P10: K-dimension tiling with row-accumulator partial accumulation completed
P11: N-dimension / output-column tiling with row-accumulator partial accumulation completed
P12: M-dimension / multi-row output-tile scheduling completed

Full regression:
  TOTAL : 74
  PASS  : 74
  FAIL  : 0
```

The bandwidth strategy evolved in layers:

```text
P4: cache B once per job
P5: fill B-cache using packed 32-bit reads
P6: cache one A row per output row
P7: fill A-row cache using packed 32-bit reads
P8: use the completed cache stack to feed a true 4-lane MAC
P9: scale B-cache to 8x8 and A-row cache to K=8
P10: reuse the cache stack per K tile and accumulate partial sums in an internal row accumulator
P11: reuse the P10 row-accumulator model per output-column N tile
P12: reuse each B tile across multiple local M rows in one output tile
```

---

## 2. Operand Reuse Problem

For row-major GEMM:

```text
C[m][n] = sum_k A[m][k] * B[k][n]
```

A straightforward iterative implementation repeatedly reads the same operands:

```text
for m in 0 .. M-1:
  for n in 0 .. N-1:
    for k in 0 .. K-1:
      read A[m][k]
      read B[k][n]
      MAC
```

Repeated-read pattern:

```text
A[m][k] is reused across different n values.
B[k][n] is reused across different m values.
```

---

## 3. P4/P5/P6/P7 Operand-Reuse Closure

P4 adds optional B-cache reuse. P5 improves B-cache fill bandwidth through aligned packed 32-bit reads. P6 adds optional A-row reuse. P7 improves A-row fill bandwidth through aligned packed 32-bit reads.

The key effect is to reduce repeated local-memory reads before increasing compute parallelism.

---

## 4. P8 Cache-Backed True 4-Lane Closure

P8 uses the completed cache/preload stack as the operand source for a 4-lane K-parallel MAC.

Validated P8 mode:

```text
GEMM_MAC_LANES=4
GEMM_ENABLE_B_CACHE=1
GEMM_B_CACHE_MAX_K=4
GEMM_B_CACHE_MAX_N=4
GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1
GEMM_ENABLE_A_ROW_CACHE=1
GEMM_A_ROW_CACHE_MAX_K=4
GEMM_ENABLE_PACKED_A_ROW_PRELOAD=1
```

The 4-lane MAC consumes up to four K positions per compute group.

Historical full regression after P8G:

```text
62/62 PASS
```

---

## 5. P9 Scaled Cache / Larger-Dimension Closure

P9 scales the cache capacity from the P8 4x4 class to cache8:

```text
GEMM_B_CACHE_MAX_K=8
GEMM_B_CACHE_MAX_N=8
GEMM_A_ROW_CACHE_MAX_K=8
```

Validated P9 cases:

```text
CASE_ID | M | N | K | MACS | OUTPUTS | Operand-reuse focus
190     | 1 | 8 | 8 | 64   | 8       | B-cache K/N=8 footprint
191     | 2 | 8 | 8 | 128  | 16      | B-cache reuse across M
192     | 3 | 5 | 7 | 105  | 15      | irregular K/N tail-lane behavior
```

P9 verifies cache8 correctness and compatibility across DMA, AXI-Stream, and Direct Stream paths.

Historical full regression after P9H:

```text
65/65 PASS
```

---

## 6. P10 K-Tiling / Row-Accumulator Closure

P10 extends the P9 cache8 path from single-cache-fit jobs to K-tiled jobs. Instead of requiring `K_total <= GEMM_A_ROW_CACHE_MAX_K` and `K_total <= GEMM_B_CACHE_MAX_K`, the active K dimension is split into local tiles that fit the existing caches.

Validated P10 mode:

```text
GEMM_MAC_LANES=4
GEMM_ENABLE_B_CACHE=1
GEMM_B_CACHE_MAX_K=8
GEMM_B_CACHE_MAX_N=8
GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1
GEMM_ENABLE_A_ROW_CACHE=1
GEMM_A_ROW_CACHE_MAX_K=8
GEMM_ENABLE_PACKED_A_ROW_PRELOAD=1
GEMM_ENABLE_K_TILING=1
GEMM_K_TILE_SIZE=8
```

For each output row, P10 accumulates partial sums across all K tiles before writing final C:

```text
for each output row m:
  clear c_row_accum[n]

  for each K tile:
    preload A[m][k_tile] into a_row_cache
    preload B[k_tile][n] into b_cache
    accumulate partial dot products into c_row_accum[n]

  write final C[m][n] once
```

Operand-reuse properties:

```text
A-row cache reuse: A row tile reused across N columns
B-cache reuse: B tile reused during local tile compute
C writeback: one final write per output element
```

Validated P10 cases:

```text
CASE_ID | M | N | K  | MACS | OUTPUTS | Purpose
193     | 1 | 4 | 16 | 64   | 4       | minimum K=16 smoke
194     | 2 | 4 | 16 | 128  | 8       | multi-row K=16
195     | 4 | 4 | 16 | 256  | 16      | two full K=8 tiles
196     | 3 | 5 | 9  | 135  | 15      | K tail 8+1, N=5
197     | 4 | 4 | 12 | 192  | 16      | K tail 8+4
```

P10 closure:

```text
P10B: safe parameter plumbing                         PASS
P10C: K>8 testcase / reference support                PASS
P10D: actual K-tile RTL execution                     PASS
P10E: frontend compatibility sanity                   PASS
P10F: regression integration                          PASS

Full regression after P10F:
  68/68 PASS
```

Current implementation note:

```text
The K-tiled path uses conservative scalar tile preload.
Packed tile-preload optimization for tiled tails is future work.
```

---

## 7. P11 N-Tiling / Output-Column Closure

P11 extends the P10 cache8 path from K-only tiling to combined K/N tiling.  Instead of requiring `N_total <= GEMM_B_CACHE_MAX_N`, the active output columns are split into local N tiles that fit the B-cache and row accumulator.

Validated P11 mode:

```text
GEMM_MAC_LANES=4
GEMM_ENABLE_B_CACHE=1
GEMM_B_CACHE_MAX_K=8
GEMM_B_CACHE_MAX_N=8
GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1
GEMM_ENABLE_A_ROW_CACHE=1
GEMM_A_ROW_CACHE_MAX_K=8
GEMM_ENABLE_PACKED_A_ROW_PRELOAD=1
GEMM_ENABLE_K_TILING=1
GEMM_K_TILE_SIZE=8
GEMM_ENABLE_N_TILING=1
GEMM_N_TILE_SIZE=8
```

For each output row, P11 accumulates one local output-column tile at a time:

```text
for each output row m:
  for each N tile:
    clear c_row_accum[local_n]

    for each K tile:
      preload A[m][k_tile] into a_row_cache
      preload B[k_tile][n_tile] into b_cache
      accumulate partial dot products into c_row_accum[local_n]

    write final C[m][n_tile_base + local_n] once
```

Operand-reuse properties:

```text
A-row cache reuse: A row tile reused across the active N tile
B-cache reuse: B K/N tile reused during local tile compute
C writeback: one final write per output element
N scheduling: output columns are processed in local N tiles
```

Validated P11 cases:

```text
CASE_ID | M | N  | K  | MACS | OUTPUTS | Purpose
198     | 1 | 16 | 8  | 128  | 16      | N tiling only
199     | 2 | 16 | 8  | 256  | 32      | multi-row N tiling
200     | 4 | 16 | 16 | 1024 | 64      | combined K/N tiling representative
201     | 3 | 9  | 9  | 243  | 27      | N and K tail tiles
202     | 4 | 12 | 16 | 768  | 48      | partial N tile and K tiling
```

P11 closure:

```text
P11B: safe parameter plumbing                         PASS
P11C: N>8 testcase / reference support                PASS
P11D: actual N-tile RTL execution                     PASS
P11E: frontend compatibility sanity                   PASS
P11G: regression integration                          PASS

Full regression after P11G:
  71/71 PASS
```

Current implementation note:

```text
The N-tiled path uses conservative scalar tile preload.
Packed tile-preload optimization for tiled paths remains future work.
```

---


## 8. P12 M-Tiling / Multi-Row Output Tile Closure

P12 extends the P11 K/N-tiled path from row-at-a-time scheduling to local M-tile scheduling.  Instead of writing one row accumulator per active output row, P12 accumulates a local M/N output tile:

```text
c_tile_accum[local_m][local_n]
```

Validated P12 mode:

```text
GEMM_MAC_LANES=4
GEMM_ENABLE_B_CACHE=1
GEMM_B_CACHE_MAX_K=8
GEMM_B_CACHE_MAX_N=8
GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1
GEMM_ENABLE_A_ROW_CACHE=1
GEMM_A_ROW_CACHE_MAX_K=8
GEMM_ENABLE_PACKED_A_ROW_PRELOAD=1
GEMM_ENABLE_K_TILING=1
GEMM_K_TILE_SIZE=8
GEMM_ENABLE_N_TILING=1
GEMM_N_TILE_SIZE=8
GEMM_ENABLE_M_TILING=1
GEMM_M_TILE_SIZE=2
```

For each active M/N tile, P12 preloads one B K/N tile and reuses it across all active local M rows before moving to the next K tile or N tile:

```text
for each M tile:
  for each N tile:
    clear c_tile_accum[local_m][local_n]

    for each K tile:
      preload B K/N tile once

      for each local M row:
        preload A row K tile
        accumulate into c_tile_accum[local_m][local_n]

    write final C tile once
```

Operand-reuse properties:

```text
A-row cache reuse: A row tile reused across the active N tile
B-cache reuse: B K/N tile reused across active local M rows
C writeback: one final write per output element
M scheduling: output rows are processed in local M tiles
```

Validated P12 cases:

```text
CASE_ID | M | N  | K  | MACS | OUTPUTS | Purpose
203     | 8 | 8  | 8  | 512  | 64      | M tiling only
204     | 8 | 16 | 8  | 1024 | 128     | M/N tiling
205     | 8 | 16 | 16 | 2048 | 128     | combined M/N/K tiling representative
206     | 5 | 9  | 9  | 405  | 45      | M/N/K tail tiles
207     | 7 | 12 | 16 | 1344 | 84      | representative frontend M/N/K tiling case
```

P12 closure:

```text
P12B: safe parameter plumbing                         PASS
P12C: M>current-row testcase / reference support      PASS
P12D: actual M-tile RTL execution                     PASS
P12E: host-primary focused validation                 PASS
P12F: frontend compatibility sanity                   PASS
P12G: regression integration                          PASS

Full regression after P12G:
  74/74 PASS
```

Current implementation note:

```text
The M-tiled path uses conservative scalar tile preload.
Packed multi-row tile-preload optimization remains future work.
```

---

## 9. Compatibility Across Frontend Paths

The cache/preload stack remains compatible with the three major operand delivery paths:

```text
DMA load-store path:
  DMA source memory -> scratchpad A/B -> GEMM -> scratchpad C -> DMA store

AXI-Stream load-store path:
  AXIS source -> MM2S DMA -> async FIFO -> scratchpad A/B -> GEMM -> DMA store

Direct Stream load-store path:
  DS source -> MM2S DMA -> async FIFO -> operand buffer A/B -> GEMM -> scratchpad C -> DMA store
```

P10E/P10F validate K-tiling compatibility:

```text
DMA load-store          CASE_ID=195
AXI-Stream load-store   CASE_ID=195
Direct Stream           CASE_ID=195
```

---

## 10. Acceptance Criteria

Current acceptance:

```text
B-cache operand reuse correctness                         DONE
packed B-cache preload correctness                        DONE
scalar A-row cache correctness                            DONE
packed A-row preload correctness                          DONE
cache-backed true 4-lane MAC correctness                  DONE
scaled cache8 larger-dimension correctness                DONE
K-dimension tiling correctness                            DONE
N-dimension tiling correctness                            DONE
M-dimension tiling correctness                            DONE
row/output-tile accumulator partial accumulation correctness           DONE
DMA / AXI-Stream / Direct Stream compatibility            DONE
full UVM regression integration                           DONE

Regression:
  74/74 PASS
```

---

## 11. Future Work

After P12, recommended directions are:

```text
C read-modify-write accumulation for external/multi-job tiling
packed tile-preload optimization for K-tiled tails
multi-bank or widened local memory
larger Direct Stream operand buffers
more constrained-random coverage
coverage closure
```

---

## 12. Summary

P4/P5/P6/P7/P8/P9/P10/P11/P12 improve GEMM performance and scalability by reducing repeated operand reads, improving cache fill granularity, reusing operands locally, feeding a cache-backed multi-lane compute step, extending K beyond the local cache depth through K-only tiling, and extending N beyond the local output-column tile capacity through N tiling, and extending M beyond row-at-a-time scheduling through local multi-row output-tile scheduling.

The current `74/74 PASS` baseline is the clean checkpoint after P12 M-dimension tiling closure.
