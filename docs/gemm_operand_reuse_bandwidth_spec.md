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

Full regression:
  TOTAL : 65
  PASS  : 65
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

For a 4x4x4 GEMM:

```text
logical MACs = 64

no-cache operand reads:
  A reads = M * N * K = 64
  B reads = M * N * K = 64
  total   = 128
```

---

## 3. P4 B-Cache Closure

P4 adds an optional B-operand cache path.

Implemented behavior:

```text
GEMM_ENABLE_B_CACHE=0:
    preserve the no-cache baseline

GEMM_ENABLE_B_CACHE=1 and supported dimensions:
    preload B[k][n] into a local B cache
    compute lane B operands from b_cache[k][n]
```

Cache activation:

```text
b_cache_active =
  GEMM_ENABLE_B_CACHE &&
  dim_k <= GEMM_B_CACHE_MAX_K &&
  dim_n <= GEMM_B_CACHE_MAX_N
```

Read model with B-cache:

```text
B preload reads = K * N
A compute reads = M * N * K
total           = (K * N) + (M * N * K)
```

For 4x4x4:

```text
without B-cache:
  total operand reads = 128

with B-cache:
  B preload reads = 16
  A compute reads = 64
  total           = 80

saved reads = 48
```

Important P4 semantic fix:

```text
gemm_top.done now asserts only after the final C write completion,
not merely after the final C write request is accepted.
```

P4 closure:

```text
P4C: B-cache compute bypass / perf profile              PASS
P4D: B-cache Direct Stream compatibility                PASS
P4E: B-cache DMA / AXIS / Direct Stream stress          PASS
P4E: B-cache CDC subset at dma/core=10ns/13ns           PASS
P4F: Representative B-cache tests added to regression   PASS

Full regression after P4F:
  47/47 PASS
```

---

## 4. P5 Packed B-Cache Preload Closure

P5 improves the B-cache fill path by reading a 32-bit byte window and unpacking up to four int8 B operands per local read.

Implemented behavior:

```text
GEMM_ENABLE_PACKED_BCACHE_PRELOAD=0:
    preserve scalar B-cache preload

GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1 and base_addr_b[1:0] == 0:
    issue aligned 32-bit local reads during B-cache preload
    unpack mem_rd_data[7:0], [15:8], [23:16], [31:24]
    fill b_cache[k][n] from packed byte lanes

GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1 and base_addr_b[1:0] != 0:
    fallback to scalar B-cache preload
```

Key local-read contract update:

```text
gemm_scratchpad_adapter returns a 32-bit byte window in mem_rd_data[31:0].
Existing scalar reads remain compatible because mem_rd_data[7:0] is still the requested byte.
```

Focused P5 profile:

```text
CASE_ID | P4 B-cache | P5 packed B-cache | Change
100     | 24         | 43                | +19
101     | 189        | 182               | -7
105     | 485        | 415               | -70
5       | 1147       | 1060              | -87
400     | 1146       | 1060              | -86
401     | 1147       | 1060              | -87
402     | 1147       | 1060              | -87
403     | 1146       | 1060              | -86
```

P5 closure:

```text
P5A: packed operand read spec                         PASS
P5B: safe parameter plumbing                          PASS
P5C: packed B-cache preload RTL                       PASS
P5D: focused perf/profile compare                     PASS
P5E: Direct Stream compatibility                      PASS
P5F: DMA / AXIS / Direct Stream stress and CDC subset PASS
P5G: Representative packed-read regression added      PASS

Full regression after P5G:
  50/50 PASS
```

---

## 5. P6 Scalar A-Row Cache Closure

P6 adds optional A-row reuse.

Implemented behavior:

```text
GEMM_ENABLE_A_ROW_CACHE=0:
    preserve the P5 packed B-cache baseline

GEMM_ENABLE_A_ROW_CACHE=1 and supported K:
    preload A[m][k] once per output row m
    store the current row in a local A-row cache
    reuse cached A values across all output columns n
```

A-side read model:

```text
without A-row cache:
  A reads = M * N * K

with scalar A-row cache:
  A preload reads = M * K

saved A reads = M * K * (N - 1)
```

Focused P6 profile:

```text
CASE_ID | P5 packed B-cache | P6 A-row cache | Change
100     | 43                | 43             | 0
101     | 182               | 152            | -30
105     | 415               | 275            | -140
5       | 1060              | 627            | -433
400     | 1060              | 627            | -433
401     | 1060              | 627            | -433
402     | 1060              | 627            | -433
403     | 1060              | 627            | -433
```

P6 closure:

```text
P6A: A-row cache spec                                PASS
P6B: safe parameter plumbing                         PASS
P6C: scalar A-row cache RTL prototype                PASS
P6D: focused perf/profile compare                    PASS
P6E: Direct Stream compatibility                     PASS
P6F: DMA / AXIS / Direct Stream stress and CDC subset PASS
P6G: Representative regression inclusion             PASS

Full regression after P6G:
  56/56 PASS
```

---

## 6. P7 Packed A-Row Preload Closure

P7 improves the A-row cache fill path by reading one 32-bit word per four A operands when the active row is aligned and compatible.

Implemented behavior:

```text
GEMM_ENABLE_PACKED_A_ROW_PRELOAD=0:
    preserve scalar A-row preload

GEMM_ENABLE_PACKED_A_ROW_PRELOAD=1 and supported:
    issue aligned 32-bit local reads during A-row preload
    unpack four int8 A operands from mem_rd_data[31:0]
    fill a_row_cache[k]
```

P7 conservative activation policy:

```text
A-row cache active
A base is 4-byte aligned
dim_k is compatible with packed grouping
dim_k fits GEMM_A_ROW_CACHE_MAX_K
```

For 4x4x4:

```text
scalar A-row fill reads = M * K     = 16
packed A-row fill reads = M * K / 4 = 4
```

Representative P7 profile:

```text
CASE_ID | P6 scalar A-row | P7 packed A-row | Change
100     | 43              | 43              | 0
101     | 152             | 152             | 0
105     | 275             | 275             | 0
5       | 627             | 500             | -127
400     | 627             | 500             | -127
401     | 627             | 500             | -127
402     | 627             | 500             | -127
403     | 627             | 500             | -127
```

P7 closure:

```text
P7A: packed A-row preload spec                    PASS
P7B: safe parameter plumbing                      PASS
P7C: packed A-row preload RTL                     PASS
P7D: focused perf/profile compare                 PASS
P7E: Direct Stream compatibility                  PASS
P7F: packed A-row stress / CDC manual subset      PASS
P7G: representative packed A-row regression added PASS

Full regression after P7G:
  59/59 PASS
```

---

## 7. P8 Cache-Backed True 4-Lane Closure

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

The 4-lane MAC consumes up to four K positions per compute group:

```text
lane0: A[m][k+0] * B[k+0][n]
lane1: A[m][k+1] * B[k+1][n], if valid
lane2: A[m][k+2] * B[k+2][n], if valid
lane3: A[m][k+3] * B[k+3][n], if valid
```

Representative P8 profile:

```text
CASE_ID | P7 2-lane packed A-row | P8 4-lane full-cache | Change
100     | 43                     | 43                   | 0
101     | 152                    | 152                  | 0
105     | 275                    | 265                  | -10
5       | 500                    | 472                  | -28
400     | 500                    | 472                  | -28
401     | 500                    | 472                  | -28
402     | 500                    | 472                  | -28
403     | 500                    | 472                  | -28
```

P8 closure:

```text
P8A: 4-lane MAC feasibility spec                 PASS
P8B: safe parameter validation / plumbing        PASS
P8C: cache-backed true 4-lane MAC RTL            PASS
P8D: focused perf/profile compare                PASS
P8E: Direct Stream / load-store compatibility    PASS
P8F: 4-lane stress / CDC manual subset           PASS
P8G: representative 4-lane regression added      PASS

Full regression after P8G:
  62/62 PASS
```

---

## 8. P9 Scaled Cache / Larger-Dimension Closure

P9 scales the cache capacity from the P8 4x4 class to cache8:

```text
GEMM_B_CACHE_MAX_K=8
GEMM_B_CACHE_MAX_N=8
GEMM_A_ROW_CACHE_MAX_K=8
```

Validated P9 mode:

```text
GEMM_MAC_LANES=4
GEMM_ENABLE_B_CACHE=1
GEMM_B_CACHE_MAX_K=8
GEMM_B_CACHE_MAX_N=8
GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1
GEMM_ENABLE_A_ROW_CACHE=1
GEMM_A_ROW_CACHE_MAX_K=8
GEMM_ENABLE_PACKED_A_ROW_PRELOAD=1
```

Validated larger-dimension cases:

```text
CASE_ID | M | N | K | MACS | OUTPUTS | Operand-reuse focus
190     | 1 | 8 | 8 | 64   | 8       | B-cache K/N=8 footprint
191     | 2 | 8 | 8 | 128  | 16      | B-cache reuse across M
192     | 3 | 5 | 7 | 105  | 15      | irregular K/N tail-lane behavior
```

P9 verifies:

```text
K=8 multi-group 4-lane compute
N=8 B-cache column scaling
A-row cache K=8 scaling
packed preload multi-word behavior
irregular K/N tail-lane behavior
larger C output writeback/readback
DMA / AXI-Stream / Direct Stream path compatibility
```

P9 closure:

```text
P9B: safe parameter validation / plumbing check        PASS
P9C: scaled cache compatibility, default clock         PASS
P9D: scaled cache CDC sanity, clk10/13                 PASS
P9E: focused perf/profile compare                      PASS
P9F: larger-dimension CASE_ID support                  PASS
P9G: large-dimension path compatibility sanity         PASS
P9H: regression integration                            PASS

Full regression after P9H:
  65/65 PASS
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

P9G specifically validates:

```text
DMA load-store          CASE_ID=190
AXI-Stream load-store   CASE_ID=191
Direct Stream           CASE_ID=192
```

---

## 10. Risk Analysis

### Risk 1: Cache Indexing

Potential issue:

```text
B-cache indexing works for N=4 but fails for N=8.
```

P9 mitigation:

```text
CASE_ID=190 and CASE_ID=191 use N=8.
```

### Risk 2: K-Step / Final Detection

Potential issue:

```text
4-lane mode computes only the first K group for K=8.
```

P9 mitigation:

```text
CASE_ID=190 and CASE_ID=191 use K=8.
```

### Risk 3: Packed A-Row Multi-Word Fill

Potential issue:

```text
K=8 A-row preload fills only the first four elements.
```

P9 mitigation:

```text
K=8 cases require two packed A-row reads per row.
```

### Risk 4: Irregular Tail Lanes

Potential issue:

```text
non-multiple-of-four K contributes invalid lane data.
```

P9 mitigation:

```text
CASE_ID=192 uses K=7.
```

### Risk 5: Regression Runtime Growth

Potential issue:

```text
adding large cases to every random stress run makes full regression too heavy.
```

P9 mitigation:

```text
default stress pools remain unchanged
only three directed P9 representative items are added
```

---

## 11. Acceptance Criteria

Current acceptance:

```text
B-cache operand reuse correctness                         DONE
packed B-cache preload correctness                        DONE
scalar A-row cache correctness                            DONE
packed A-row preload correctness                          DONE
cache-backed true 4-lane MAC correctness                  DONE
scaled cache8 larger-dimension correctness                DONE
DMA / AXI-Stream / Direct Stream compatibility            DONE
CDC sanity for optimized paths                            DONE
full UVM regression integration                           DONE

Regression:
  65/65 PASS
```

---

## 12. Future Work

After P9, recommended directions are:

```text
tile-based GEMM
multi-tile scheduling
C partial accumulation
C read-modify-write accumulation
multi-bank or widened local memory
larger Direct Stream operand buffers
more constrained-random coverage
coverage closure
```

---

## 13. Summary

P4/P5/P6/P7/P8/P9 improve GEMM performance and scalability by reducing repeated operand reads, improving cache fill granularity, reusing operands locally, and feeding a cache-backed multi-lane compute step.

The key project rule remains:

```text
default off
correctness first
profile second
stress/CDC third
regression inclusion last
```

The current `65/65 PASS` baseline is the clean checkpoint for the next architecture milestone.
