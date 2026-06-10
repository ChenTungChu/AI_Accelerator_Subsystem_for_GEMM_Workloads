# Performance GEMM Spec

## 1. Purpose

This document defines the performance-oriented GEMM architecture milestone sequence on top of the completed subsystem-level GEMM, DMA, AXI-Stream, CDC, Direct Stream B1, and scoreboard verification baseline.

The project has now completed the performance sequence through P13:

```text
P0: GEMM performance counter baseline
P1: GEMM performance profile baseline
P2: 2-lane K-parallel MAC datapath prototype
P3: 2-lane stress / CDC hardening
P4: B-cache operand reuse optimization
P5: packed B-cache preload optimization
P6: scalar A-row cache optimization
P7: packed A-row preload optimization
P8: cache-backed true 4-lane MAC
P9: larger-dimension / cache-size scaling
P10: K-dimension tiling with row-accumulator partial accumulation
P11: N-dimension / output-column tiling with row-accumulator partial accumulation
P12: M-dimension / multi-row output-tile scheduling
P13: C read-modify-write accumulation for external partial-K jobs
```

Current full regression baseline:

```text
TOTAL : 82
PASS  : 82
FAIL  : 0
```

---

## 2. Current Subsystem Baseline

The subsystem baseline verifies correctness across:

```text
Host-primary GEMM path
DMA load path
DMA store / S2MM path
DMA load + store stress path
AXI-Stream preload path
Direct Stream GEMM frontend B1 path
CDC clock-ratio sanity
error/recovery flows
scoreboard-based result compare
```

The 82-item regression now also includes:

```text
GEMM performance counter smoke
GEMM performance profile
2-lane performance and frontend stress coverage
B-cache / packed B-cache / A-row cache / packed A-row cache coverage
cache-backed 4-lane MAC representative regression
scaled cache8 larger-dimension representative regression
K-tiling representative regression across DMA / AXI-Stream / Direct Stream
N-tiling representative regression across DMA / AXI-Stream / Direct Stream
M-tiling representative regression across DMA / AXI-Stream / Direct Stream
C RMW accumulation focused DUT recipes and frontend representative regression
```

---

## 3. Architecture Evolution

### P0/P1: Counter and Profile Baseline

P0/P1 established passive GEMM counters and profile collection:

```text
gemm_perf_busy_cycles
gemm_perf_mac_count
gemm_perf_output_count
```

### P2/P3: 2-Lane MAC and Stress Hardening

P2 introduced a 2-lane K-parallel MAC path. P3 expanded the verification from smoke/profile into stress and CDC sanity across the main frontend paths.

### P4/P5: B-Cache and Packed B-Cache Preload

P4 introduced optional B-cache operand reuse. P5 improved B-cache fill bandwidth by using aligned 32-bit local reads to unpack four int8 B operands per read.

### P6/P7: A-Row Cache and Packed A-Row Preload

P6 introduced scalar A-row cache reuse across output columns. P7 improved A-row cache fill bandwidth with aligned 32-bit packed reads when supported.

### P8: Cache-Backed True 4-Lane MAC

P8 used the completed cache/preload stack as the local operand source for a true 4-lane K-parallel MAC path.

### P9: Scaled Cache8 Larger-Dimension Support

P9 scaled the validated 4-lane full-cache path to:

```text
GEMM_B_CACHE_MAX_K=8
GEMM_B_CACHE_MAX_N=8
GEMM_A_ROW_CACHE_MAX_K=8
```

Representative P9 cases:

```text
CASE_ID=190 : M=1, N=8, K=8
CASE_ID=191 : M=2, N=8, K=8
CASE_ID=192 : M=3, N=5, K=7
```

### P10: K-Dimension Tiling

P10 extends the P9 cache8 path beyond single-cache-fit K values.

Validated P10 configuration:

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

P10 row-accumulator model:

```text
for each output row m:
  clear c_row_accum[n]

  for each K tile:
    preload A row tile
    preload B tile
    accumulate partial dot products into c_row_accum[n]

  write final C[m][n] once
```

P10 does not use scratchpad C read-modify-write accumulation.

### P11: N-Dimension / Output-Column Tiling

P11 extends the P10 row-accumulator model beyond single-N-tile jobs.  The active output columns are split into local N tiles that fit the B-cache and row accumulator.

Validated P11 configuration:

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

P11 output-column tiling model:

```text
for each output row m:
  for each N tile:
    clear c_row_accum[local_n]

    for each K tile:
      preload A row tile
      preload B K/N tile
      accumulate partial dot products into c_row_accum[local_n]

    write final C[m][n_tile_base + local_n] once
```

P11 does not use scratchpad C read-modify-write accumulation.

### P12: M-Dimension / Multi-Row Output Tile Scheduling

P12 extends the P11 K/N-tiled model beyond single-row scheduling.  The active output rows are split into local M tiles, and the row accumulator is extended into a local M/N output-tile accumulator.

Validated P12 configuration:

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

P12 output-tile scheduling model:

```text
for each M tile:
  for each N tile:
    clear c_tile_accum[local_m][local_n]

    for each K tile:
      preload B K/N tile once

      for each local M row:
        preload A row tile
        accumulate partial dot products into c_tile_accum[local_m][local_n]

    write final C[m_tile_base + local_m][n_tile_base + local_n] once
```

P12 does not use scratchpad C read-modify-write accumulation.



### P13: C Read-Modify-Write Accumulation

P13 extends the P12 tiled GEMM baseline from one complete GEMM job to external multi-job partial accumulation.

Runtime behavior:

```text
if accumulate_enable=0:
  C_new = partial_sum

if accumulate_enable=1:
  C_new = C_old + partial_sum
```

Feature enable condition:

```text
GEMM_ENABLE_C_RMW_ACCUM && accumulate_enable
```

P13 composes with the full P12 performance stack:

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
GEMM_ENABLE_C_RMW_ACCUM=1
```

P13 does not change MAC counting semantics. Per partial job:

```text
gemm_perf_mac_count    = M * N * K_part
gemm_perf_output_count = M * N
```

---

## 4. P10 Validation

Focused host-primary cases:

```text
CASE_ID=193 : M=1, N=4, K=16 -> MAC=64,  OUTPUT=4   PASS
CASE_ID=194 : M=2, N=4, K=16 -> MAC=128, OUTPUT=8   PASS
CASE_ID=195 : M=4, N=4, K=16 -> MAC=256, OUTPUT=16  PASS
CASE_ID=196 : M=3, N=5, K=9  -> MAC=135, OUTPUT=15  PASS
CASE_ID=197 : M=4, N=4, K=12 -> MAC=192, OUTPUT=16  PASS
```

Frontend compatibility sanity:

```text
DMA load-store        CASE_ID=195 PASS
AXI-Stream load-store CASE_ID=195 PASS
Direct Stream         CASE_ID=195 PASS
```

Regression integration:

```text
gemm_4lane_ktiling_dma_load_store_case195
gemm_4lane_ktiling_axis_stream_load_store_case195
gemm_4lane_ktiling_direct_stream_load_store_case195
```

Final regression at that milestone remained integrated into the current P13 baseline:

```text
Current full regression: 82/82 PASS
```

---

## 4A. P11 Validation

Focused host-primary cases:

```text
CASE_ID=198 : M=1, N=16, K=8  -> MAC=128,  OUTPUT=16  PASS
CASE_ID=199 : M=2, N=16, K=8  -> MAC=256,  OUTPUT=32  PASS
CASE_ID=200 : M=4, N=16, K=16 -> MAC=1024, OUTPUT=64  PASS
CASE_ID=201 : M=3, N=9,  K=9  -> MAC=243,  OUTPUT=27  PASS
CASE_ID=202 : M=4, N=12, K=16 -> MAC=768,  OUTPUT=48  PASS
```

Frontend compatibility sanity:

```text
DMA load-store        CASE_ID=200 PASS
AXI-Stream load-store CASE_ID=200 PASS
Direct Stream         CASE_ID=200 PASS
```

Representative observed latency for CASE_ID=200:

```text
Host-primary smoke    : approximately 31k cycles
DMA load-store        : 31369 cycles
AXI-Stream load-store : 31369 cycles
Direct Stream         : 14124 cycles
```

Regression integration:

```text
gemm_4lane_ntiling_dma_load_store_case200
gemm_4lane_ntiling_axis_stream_load_store_case200
gemm_4lane_ntiling_direct_stream_load_store_case200
```

Final regression at that milestone remained integrated into the current P13 baseline:

```text
Current full regression: 82/82 PASS
```

---


## 4B. P12 Validation

Focused host-primary cases:

```text
CASE_ID=203 : M=8, N=8,  K=8  -> MAC=512,  OUTPUT=64   PASS
CASE_ID=204 : M=8, N=16, K=8  -> MAC=1024, OUTPUT=128  PASS
CASE_ID=205 : M=8, N=16, K=16 -> MAC=2048, OUTPUT=128  PASS
CASE_ID=206 : M=5, N=9,  K=9  -> MAC=405,  OUTPUT=45   PASS
CASE_ID=207 : M=7, N=12, K=16 -> MAC=1344, OUTPUT=84   PASS
```

Frontend compatibility sanity:

```text
DMA store smoke       CASE_ID=205 PASS
DMA load-store        CASE_ID=207 PASS
AXI-Stream load-store CASE_ID=207 PASS
Direct Stream         CASE_ID=207 PASS
```

Regression integration:

```text
gemm_4lane_mtiling_dma_load_store_case207
gemm_4lane_mtiling_axis_stream_load_store_case207
gemm_4lane_mtiling_direct_stream_load_store_case207
```

Final regression at that milestone remained integrated into the current P13 baseline:

```text
Current full regression: 82/82 PASS
```

---


## 4C. P13 Validation

Focused C RMW accumulation recipes:

```text
CASE_ID=208 : M=1, N=4,  K_total=16, parts 8+8  PASS
CASE_ID=209 : M=4, N=4,  K_total=16, parts 8+8  PASS
CASE_ID=210 : M=4, N=16, K_total=16, parts 8+8  PASS
CASE_ID=211 : M=8, N=16, K_total=16, parts 8+8  PASS
CASE_ID=212 : M=5, N=9,  K_total=9,  parts 8+1  PASS
```

Frontend compatibility sanity:

```text
DMA load-store        CASE_ID=211 PASS
AXI-Stream load-store CASE_ID=211 PASS
Direct Stream         CASE_ID=211 PASS
```

Regression integration:

```text
p13d_c_rmw_accum_case208
p13d_c_rmw_accum_case209
p13d_c_rmw_accum_case210
p13d_c_rmw_accum_case211
p13d_c_rmw_accum_case212
gemm_4lane_c_rmw_dma_load_store_case211
gemm_4lane_c_rmw_axis_stream_load_store_case211
gemm_4lane_c_rmw_direct_stream_load_store_case211
```

Final regression:

```text
TOTAL : 82
PASS  : 82
FAIL  : 0
```

---

## 5. Acceptance Status

```text
performance counters                                      DONE
profile baseline                                          DONE
2-lane MAC datapath                                       DONE
2-lane stress / CDC hardening                             DONE
B-cache operand reuse                                     DONE
packed B-cache preload                                    DONE
scalar A-row cache                                        DONE
packed A-row preload                                      DONE
cache-backed true 4-lane MAC                              DONE
scaled cache8 larger-dimension support                    DONE
K-dimension tiling with row accumulator                    DONE
N-dimension tiling with row accumulator                    DONE
M-dimension tiling with multi-row output tile accumulator   DONE
C read-modify-write partial accumulation                    DONE
frontend compatibility for P10 representative case         DONE
frontend compatibility for P11 representative case         DONE
frontend compatibility for P12 representative case         DONE
frontend compatibility for P13 representative case          DONE
full regression integration                                DONE
```

---

## 6. Future Work

After P13, recommended directions are:

```text
packed tile-preload optimization for K-tiled tails
larger Direct Stream operand buffers
coverage closure / constrained-random expansion
external scheduler / descriptor support for multi-job GEMM recipes
```



P17 sits above P16 as a control-plane descriptor fetch prototype.  It does not change MAC scheduling, tiling, C RMW arithmetic, or performance counter semantics.  For fetched-descriptor recipes, the existing P16 recipe-level performance accumulation policy still applies because each fetched descriptor is dispatched through the existing P15/GEMM worker path.

Validated P17 performance-related observations are correctness/sanity checks rather than new performance targets:

```text
csr_desc_fetch_dma_two_slot_case102        : recipe perf snapshot PASS
csr_desc_fetch_c_rmw_two_slot_case208      : C RMW recipe perf snapshot PASS
csr_desc_fetch_direct_stream_two_slot_case102: recipe perf snapshot PASS
```
