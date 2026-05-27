# Performance GEMM Spec

## 1. Purpose

This document defines the performance-oriented GEMM architecture milestones on top of the completed subsystem-level GEMM, DMA, AXI-Stream, CDC, Direct Stream B1, and scoreboard verification baseline.

The project has completed the performance sequence through P9:

```text
P0: GEMM performance counter baseline
P1: GEMM performance profile baseline
P2: 2-lane K-parallel MAC datapath prototype
P3: 2-lane stress / CDC hardening
P4: B-cache operand reuse optimization
P5: packed B-cache preload optimization
P6: scalar A-row cache optimization
P7: packed A-row preload optimization
P8: cache-backed true 4-lane MAC optimization
P9: larger-dimension / cache-size scaling
```

Current full regression baseline:

```text
TOTAL : 65
PASS  : 65
FAIL  : 0
```

The current performance milestone moves the GEMM core from a correctness-first single-MAC engine toward a measured, parameterized, cache-backed multi-lane architecture while preserving all existing subsystem paths.

---

## 2. Current Subsystem Baseline

The subsystem verifies correctness across:

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

The 65-item regression includes:

```text
GEMM performance counter smoke
GEMM performance profile
GEMM_MAC_LANES=2 performance counter smoke
GEMM_MAC_LANES=2 performance profile
GEMM_MAC_LANES=2 Direct Stream smoke
GEMM_MAC_LANES=2 DMA / AXI-Stream / Direct Stream stress and CDC sanity
GEMM_MAC_LANES=2 + B-cache representative stress
GEMM_MAC_LANES=2 + packed B-cache representative stress
GEMM_MAC_LANES=2 + packed B-cache + A-row cache representative stress / CDC
GEMM_MAC_LANES=2 + packed B-cache + A-row cache + packed A-row representative stress
GEMM_MAC_LANES=4 + full cache/preload representative stress
GEMM_MAC_LANES=4 + scaled cache8 larger-dimension representative stress
```

---

## 3. Baseline Architecture

### 3.1 Single-MAC GEMM

The original GEMM engine is a simple iterative design:

```text
for m in 0 .. M-1:
  for n in 0 .. N-1:
    acc = 0
    for k in 0 .. K-1:
      acc += A[m][k] * B[k][n]
    C[m][n] = acc
```

It remains the default configuration:

```systemverilog
parameter int GEMM_MAC_LANES = 1
```

### 3.2 2-Lane K-Parallel GEMM

When `GEMM_MAC_LANES=2`, each output element processes up to two K positions per MAC step:

```text
for k in 0 .. K-1 step 2:
    acc += A[m][k + 0] * B[k + 0][n]
    if (k + 1 < K):
        acc += A[m][k + 1] * B[k + 1][n]
```

### 3.3 Cache-Backed 4-Lane GEMM

When `GEMM_MAC_LANES=4` is enabled with the full cache/preload stack, each output element processes up to four K positions per MAC step:

```text
for k in 0 .. K-1 step 4:
    acc += A[m][k + 0] * B[k + 0][n]
    if (k + 1 < K): acc += A[m][k + 1] * B[k + 1][n]
    if (k + 2 < K): acc += A[m][k + 2] * B[k + 2][n]
    if (k + 3 < K): acc += A[m][k + 3] * B[k + 3][n]
```

The 4-lane path is cache-backed: A operands come from A-row cache and B operands come from B-cache. This avoids widening the local memory read interface.

---

## 4. Execution Paths That Must Remain Stable

### 4.1 Scratchpad Mode

```text
A/B in scratchpad
    -> GEMM reads A/B through gemm_scratchpad_adapter
    -> GEMM writes C to scratchpad
    -> host readback or DMA store
    -> scoreboard compare
```

### 4.2 AXI-Stream Preload Mode

```text
AXI-MM source
    -> axi_mm2s_dma
    -> axis_async_fifo
    -> axi_stream_loader
    -> axis_scratchpad_write_adapter
    -> scratchpad A/B
    -> GEMM
    -> scratchpad C
    -> DMA store
    -> scoreboard compare
```

### 4.3 Direct Stream B1 Mode

```text
AXI-MM source
    -> axi_mm2s_dma
    -> axis_async_fifo
    -> axi_stream_loader
    -> gemm_operand_buffer_write_adapter
    -> gemm_operand_buffer A/B
    -> gemm_input_mem_router
    -> GEMM reads A/B from operand buffer
    -> GEMM writes C to scratchpad
    -> DMA store
    -> scoreboard compare
```

P9 confirms the scaled cache8 larger-dimension cases through DMA, AXI-Stream, and Direct Stream load-store paths.

---

## 5. Performance Measurement Model

The implemented GEMM counters are:

```systemverilog
logic [31:0] gemm_perf_busy_cycles;
logic [31:0] gemm_perf_mac_count;
logic [31:0] gemm_perf_output_count;
```

Counter behavior:

```text
gemm_perf_busy_cycles:
    increments while GEMM is busy

gemm_perf_mac_count:
    increments when valid logical MAC operations are committed

gemm_perf_output_count:
    increments when one C[m][n] output write completion is observed
```

Counter clear policy:

```text
reset
accepted GEMM start
```

Snapshot policy:

```text
values remain stable after done until the next accepted GEMM start
```

For all lane/cache configurations:

```text
MAC_COUNT    = M * N * K
OUTPUT_COUNT = M * N
```

`gemm_perf_mac_count` counts logical MAC operations, not the number of lane groups or FSM states.

---

## 6. Performance Profile Baselines

### 6.1 Single-Lane Profile Baseline

```text
CASE_ID | M | N | K | MACS | OUTPUTS | GEMM_BUSY_CYCLES
100     | 1 | 1 | 1 | 1    | 1       | 24
101     | 2 | 2 | 2 | 8    | 4       | 230
105     | 2 | 3 | 4 | 24   | 6       | 603
5       | 4 | 4 | 4 | 64   | 16      | 1638
400     | 4 | 4 | 4 | 64   | 16      | 1637
401     | 4 | 4 | 4 | 64   | 16      | 1637
402     | 4 | 4 | 4 | 64   | 16      | 1637
403     | 4 | 4 | 4 | 64   | 16      | 1637
```

### 6.2 2-Lane Baseline

```text
CASE_ID | M | N | K | MACS | OUTPUTS | GEMM_BUSY_CYCLES
100     | 1 | 1 | 1 | 1    | 1       | 24
101     | 2 | 2 | 2 | 8    | 4       | 224
105     | 2 | 3 | 4 | 24   | 6       | 594
5       | 4 | 4 | 4 | 64   | 16      | 1609
400     | 4 | 4 | 4 | 64   | 16      | 1610
401     | 4 | 4 | 4 | 64   | 16      | 1610
402     | 4 | 4 | 4 | 64   | 16      | 1610
403     | 4 | 4 | 4 | 64   | 16      | 1610
```

### 6.3 2-Lane + Packed B-Cache

```text
CASE_ID | M | N | K | MACS | OUTPUTS | BUSY
100     | 1 | 1 | 1 | 1    | 1       | 43
101     | 2 | 2 | 2 | 8    | 4       | 182
105     | 2 | 3 | 4 | 24   | 6       | 415
5       | 4 | 4 | 4 | 64   | 16      | 1060
400     | 4 | 4 | 4 | 64   | 16      | 1060
401     | 4 | 4 | 4 | 64   | 16      | 1060
402     | 4 | 4 | 4 | 64   | 16      | 1060
403     | 4 | 4 | 4 | 64   | 16      | 1060
```

### 6.4 2-Lane + Packed B-Cache + A-Row Cache

```text
CASE_ID | M | N | K | MACS | OUTPUTS | BUSY
100     | 1 | 1 | 1 | 1    | 1       | 43
101     | 2 | 2 | 2 | 8    | 4       | 152
105     | 2 | 3 | 4 | 24   | 6       | 275
5       | 4 | 4 | 4 | 64   | 16      | 627
400     | 4 | 4 | 4 | 64   | 16      | 627
401     | 4 | 4 | 4 | 64   | 16      | 627
402     | 4 | 4 | 4 | 64   | 16      | 627
403     | 4 | 4 | 4 | 64   | 16      | 627
```

### 6.5 2-Lane + Packed B-Cache + A-Row Cache + Packed A-Row

```text
CASE_ID | M | N | K | MACS | OUTPUTS | BUSY
100     | 1 | 1 | 1 | 1    | 1       | 43
101     | 2 | 2 | 2 | 8    | 4       | 152
105     | 2 | 3 | 4 | 24   | 6       | 275
5       | 4 | 4 | 4 | 64   | 16      | 500
400     | 4 | 4 | 4 | 64   | 16      | 500
401     | 4 | 4 | 4 | 64   | 16      | 500
402     | 4 | 4 | 4 | 64   | 16      | 500
403     | 4 | 4 | 4 | 64   | 16      | 500
```

### 6.6 4-Lane + Full Cache/Preload

```text
CASE_ID | M | N | K | MACS | OUTPUTS | BUSY
100     | 1 | 1 | 1 | 1    | 1       | 43
101     | 2 | 2 | 2 | 8    | 4       | 152
105     | 2 | 3 | 4 | 24   | 6       | 265
5       | 4 | 4 | 4 | 64   | 16      | 472
400     | 4 | 4 | 4 | 64   | 16      | 472
401     | 4 | 4 | 4 | 64   | 16      | 472
402     | 4 | 4 | 4 | 64   | 16      | 472
403     | 4 | 4 | 4 | 64   | 16      | 472
```

### 6.7 P9 4-Lane + Scaled Cache8 Larger-Dimension Cases

```text
CASE_ID | M | N | K | MACS | OUTPUTS | Purpose
190     | 1 | 8 | 8 | 64   | 8       | K/N=8 B-cache footprint
191     | 2 | 8 | 8 | 128  | 16      | B-cache reuse across two A rows
192     | 3 | 5 | 7 | 105  | 15      | irregular K/N tail-lane sanity
```

P9 acceptance checks:

```text
UVM_ERROR=0
UVM_FATAL=0
result compare PASS
mac_count = M*N*K
output_count = M*N
DMA / AXI-Stream / Direct Stream large-dimension paths all PASS
```

P9 does not lock exact busy-cycle numbers in regression.

---

## 7. Completed Performance Stages

```text
P0: GEMM performance counter smoke                       PASS
P1: GEMM performance profile baseline                    PASS
P2: 2-lane MAC datapath                                  PASS
P3: 2-lane stress / CDC hardening                        PASS
P4: B-cache operand reuse                                PASS
P5: packed B-cache preload                               PASS
P6: scalar A-row cache                                   PASS
P7: packed A-row preload                                 PASS
P8: cache-backed true 4-lane MAC                         PASS
P9: larger-dimension / cache-size scaling                PASS
```

---

## 8. P9 Closure Details

Validated P9 configuration:

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

P9 closure sequence:

```text
P9B: safe parameter validation / plumbing check        PASS
P9C: scaled cache compatibility, default clock         PASS
P9D: scaled cache CDC sanity, clk10/13                 PASS
P9E: focused perf/profile compare                      PASS
P9F: larger-dimension CASE_ID support                  PASS
P9G: large-dimension path compatibility sanity         PASS
P9H: regression integration                            PASS
```

P9H final regression:

```text
TOTAL : 65
PASS  : 65
FAIL  : 0
```

---

## 9. Risks and Mitigations

### Risk 1: Counters change timing

Counters must remain passive and must not feed back into datapath control.

Mitigation:

```text
counter updates are derived from existing FSM events
counter values are used only by UVM/profile checks
```

### Risk 2: Multi-MAC requires more memory bandwidth

The 4-lane path is intentionally cache-backed.

Mitigation:

```text
use A-row cache and B-cache as the 4-lane operand source
do not widen the local memory interface in P8/P9
```

### Risk 3: Direct Stream mode diverges from scratchpad mode

Mitigation:

```text
run Direct Stream smoke, load-store stress, and P9 large-dimension directed cases
```

### Risk 4: Cache-size scaling breaks indexing

Mitigation:

```text
use K=8 and N=8 directed cases
check result compare and performance counters
```

### Risk 5: Irregular tail dimensions break lane masking

Mitigation:

```text
use CASE_ID=192 with M=3, N=5, K=7
```

### Risk 6: Full regression runtime growth

Mitigation:

```text
add only three directed P9 representative items
keep default stress pools unchanged
```

---

## 10. Current Acceptance Status

```text
Performance Counter Baseline                     : DONE
Performance Profile Baseline                     : DONE
2-Lane MAC Prototype                             : DONE
2-Lane Direct Stream Compatibility               : DONE
2-Lane Smoke/Profile Regression                  : DONE
2-Lane Stress / CDC Hardening                    : DONE
B-Cache Operand Reuse Optimization               : DONE
Packed B-Cache Preload Optimization              : DONE
Scalar A-Row Cache Optimization                  : DONE
Packed A-Row Preload Optimization                : DONE
Cache-Backed 4-Lane MAC Optimization             : DONE
Scaled Cache8 Larger-Dimension Verification      : DONE
P9 Regression Integration                         : DONE

Regression:
  65/65 PASS
```

---

## 11. Future Direction

After P9, the project can move toward:

```text
tile-based GEMM scheduling
multi-tile GEMM
C partial accumulation
C read-modify-write accumulation
larger operand buffers
wider local memory interface
multi-bank scratchpad
coverage closure
more constrained-random traffic
```

The guiding principle remains:

```text
measure first
accelerate second
verify every step
```
