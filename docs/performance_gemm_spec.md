# Performance GEMM Spec

## 1. Purpose

This document defines the performance-oriented GEMM architecture milestone sequence on top of the completed subsystem-level GEMM, DMA, AXI-Stream, CDC, Direct Stream B1, and scoreboard verification baseline.

The project has now completed the performance sequence through P10:

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
```

Current full regression baseline:

```text
TOTAL : 68
PASS  : 68
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

The 68-item regression now also includes:

```text
GEMM performance counter smoke
GEMM performance profile
2-lane performance and frontend stress coverage
B-cache / packed B-cache / A-row cache / packed A-row cache coverage
cache-backed 4-lane MAC representative regression
scaled cache8 larger-dimension representative regression
K-tiling representative regression across DMA / AXI-Stream / Direct Stream
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

Final regression:

```text
TOTAL : 68
PASS  : 68
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
frontend compatibility for P10 representative case         DONE
full regression integration                                DONE
```

---

## 6. Future Work

After P10, recommended directions are:

```text
N tiling / output-column tiling
M tiling / multi-row tile scheduling
C read-modify-write accumulation for external/multi-job tiling
packed tile-preload optimization for K-tiled tails
larger Direct Stream operand buffers
coverage closure / constrained-random expansion
```
