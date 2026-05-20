# Performance GEMM Spec

## 1. Purpose

This document defines the performance-oriented GEMM architecture milestone on top of the completed subsystem-level GEMM, DMA, AXI-Stream, CDC, Direct Stream B1, and scoreboard verification baseline.

The project has now completed the first performance sequence through P6:

```text
P0: GEMM performance counter baseline
P1: GEMM performance profile baseline
P2: 2-lane K-parallel MAC datapath prototype
P3: 2-lane stress / CDC hardening
P4: B-cache operand reuse optimization
P5: packed B-cache preload optimization
P6: scalar A-row cache optimization
```

Current full regression baseline:

```text
TOTAL : 56
PASS  : 56
FAIL  : 0
```

The current performance milestone moves the GEMM core from a correctness-first single-MAC engine toward a measurable, parameterized, multi-lane architecture while preserving all existing subsystem paths. P4 added an optional B-operand cache for small GEMM shapes, P5 adds optional packed B-cache preload to reduce the cost of filling that cache, and P6 adds optional scalar A-row cache to reduce repeated A reads across output columns.

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

The 56-item regression now also includes:

```text
GEMM performance counter smoke
GEMM performance profile
GEMM_MAC_LANES=2 performance counter smoke
GEMM_MAC_LANES=2 performance profile
GEMM_MAC_LANES=2 Direct Stream smoke
GEMM_MAC_LANES=2 DMA load-store stress
GEMM_MAC_LANES=2 AXI-Stream load-store stress
GEMM_MAC_LANES=2 Direct Stream load-store stress
GEMM_MAC_LANES=2 DMA / AXI-Stream / Direct Stream CDC sanity
GEMM_MAC_LANES=2 + GEMM_ENABLE_B_CACHE=1 representative DMA / AXI-Stream / Direct Stream load-store stress
GEMM_MAC_LANES=2 + GEMM_ENABLE_B_CACHE=1 + GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1 representative DMA / AXI-Stream / Direct Stream load-store stress
GEMM_MAC_LANES=2 + GEMM_ENABLE_B_CACHE=1 + GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1 + GEMM_ENABLE_A_ROW_CACHE=1 representative DMA / AXI-Stream / Direct Stream stress and CDC sanity
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

This design is:

```text
simple
deterministic
easy to debug
easy to verify
easy to compare against a software reference
```

It remains the default configuration:

```systemverilog
parameter int GEMM_MAC_LANES = 1
```

### 3.2 2-Lane K-Parallel GEMM

The P2 implementation adds:

```text
GEMM_MAC_LANES=2
```

For each output element `C[m][n]`, the 2-lane path processes up to two K positions per MAC step:

```text
for k in 0 .. K-1 step 2:
    acc += A[m][k + 0] * B[k + 0][n]

    if (k + 1 < K):
        acc += A[m][k + 1] * B[k + 1][n]
```

The implementation uses lane masking for odd K and preserves the same C output format, memory map, scoreboard model, and execution paths.

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

P2 explicitly verifies that `GEMM_MAC_LANES=2` works through Direct Stream B1.

---

## 5. Performance Measurement Model

The current implemented GEMM counters are:

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
    increments when one C[m][n] output is written
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

For both 1-lane and 2-lane modes:

```text
MAC_COUNT    = M * N * K
OUTPUT_COUNT = M * N
```

For `GEMM_MAC_LANES=2`, `gemm_perf_mac_count` counts logical MAC operations, not the number of 2-lane loop iterations.

---

## 6. Single-Lane Profile Baseline

The P1 single-lane profile baseline is:

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

This profile is the reference for future compute improvements.

---

## 7. 2-Lane Profile Baseline

The P2 2-lane profile baseline is:

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

Observed behavior:

```text
CASE_ID=100:
    K=1, lane1 masked, busy cycles unchanged

CASE_ID=101/105/5/400/401/402/403:
    K>=2, 2-lane path active, busy cycles reduced
```

The reduction is modest because the first 2-lane implementation preserves the existing single-read local memory interface and still performs sequential operand reads.

---

## 8. Completed Performance Stages

### Stage P0: Performance Counter Baseline

Implemented:

```text
gemm_perf_busy_cycles
gemm_perf_mac_count
gemm_perf_output_count
```

Verification:

```text
ai_accel_subsys_perf_counter_smoke_test
```

Status:

```text
PASS
Regression moved from 33/33 to 34/34
```

### Stage P1: Single-Lane Profile Baseline

Implemented:

```text
ai_accel_subsys_perf_profile_test
8-case profile summary
```

Status:

```text
PASS
Regression moved from 34/34 to 35/35
```

### Stage P2: 2-Lane MAC Prototype

Implemented:

```text
GEMM_MAC_LANES parameter
GEMM_MAC_LANES=1 mainline baseline
GEMM_MAC_LANES=2 2-lane K-parallel datapath
lane1 operand registers
lane1 valid masking
2-lane MAC commit
logical MAC counter update
```

Verified:

```text
GEMM_MAC_LANES=1 full regression remains clean
GEMM_MAC_LANES=2 perf_counter_smoke PASS
GEMM_MAC_LANES=2 perf_profile PASS
GEMM_MAC_LANES=2 direct_stream_smoke PASS
```

Status:

```text
PASS
Regression moved from 35/35 to 38/38
```

---

## 9. Current Regression Subset for 2-Lane

The full regression includes the following focused 2-lane subset:

```text
gemm_2lane_perf_counter_smoke
    ai_accel_subsys_perf_counter_smoke_test
    CASE_ID=100
    RUN_ALL=1
    GEMM_MAC_LANES=2

gemm_2lane_perf_profile
    ai_accel_subsys_perf_profile_test
    CASE_ID=100
    GEMM_MAC_LANES=2

gemm_2lane_direct_stream_smoke
    ai_accel_subsys_direct_stream_smoke_test
    CASE_ID=100
    RUN_ALL=1
    GEMM_MAC_LANES=2
```

This subset protects:

```text
logical MAC/output counter correctness
K=1 lane1 mask behavior
K=2/K=4 active lane1 behavior
host-primary profile flow
Direct Stream operand-buffer compatibility
scoreboard result compare
ctrl/result pairing
```

P3 adds the following 2-lane stress / CDC subset:

```text
gemm_2lane_dma_load_store_stress
gemm_2lane_axis_stream_load_store_stress
gemm_2lane_direct_stream_load_store_stress
gemm_2lane_dma_load_store_cdc
gemm_2lane_axis_stream_load_store_cdc
gemm_2lane_direct_stream_load_store_cdc
```

This subset protects:

```text
DMA load A/B -> GEMM -> DMA store C
AXI-Stream preload A/B -> GEMM -> DMA store C
Direct Stream preload A/B -> GEMM -> DMA store C
scoreboard result compare under repeated jobs
clock-ratio sanity at dma_clk=10ns, core_clk=13ns
```


---

---

## 9A. P4 B-Cache Operand Reuse Closure

P4 adds an optional B-operand cache path to reduce repeated B reads during GEMM compute.

New parameters:

```systemverilog
parameter bit GEMM_ENABLE_B_CACHE = 1'b0;
parameter int GEMM_B_CACHE_MAX_K  = 4;
parameter int GEMM_B_CACHE_MAX_N  = 4;
```

Default behavior remains no-cache:

```text
GEMM_ENABLE_B_CACHE=0:
    preserve the P3 1-lane / 2-lane baseline behavior
```

When enabled and the dimensions are supported:

```text
GEMM_ENABLE_B_CACHE=1
and dim_k <= GEMM_B_CACHE_MAX_K
and dim_n <= GEMM_B_CACHE_MAX_N:
    preload B[k][n] once per GEMM job
    read A from the existing local memory path during compute
    source B operands from the local B cache during compute
```

Unsupported dimensions fall back to the original no-cache path.

### B-cache compute source selection

For the 2-lane datapath:

```text
lane0 B operand = b_cache[k_idx][n_idx]
lane1 B operand = b_cache[k_idx + 1][n_idx], when lane1_valid
```

The no-cache path remains:

```text
lane0 B operand = memory read B[k_idx][n_idx]
lane1 B operand = memory read B[k_idx + 1][n_idx], when lane1_valid
```

### GEMM done semantic fix

During P4D Direct Stream compatibility testing, the Direct Stream + B-cache flow exposed a completion-semantic issue: `acc_done` could be observed after the final C write request was accepted, but before the final C write was completed and visible to the following DMA store.

The fix changes `gemm_top.done` semantics to:

```text
assert done only after the final C write completion is observed
```

This was implemented by adding a wait-for-C-write-completion state after `S_WRITE_C` and before advancing to `S_NEXT` / `S_DONE`.

This semantic is stronger and safer for all flows:

```text
Host readback
DMA store / S2MM
AXI-Stream preload -> GEMM -> DMA store
Direct Stream preload -> GEMM -> DMA store
```

### P4 validation

Manual and regression validation completed:

```text
P4C: B-cache compute bypass / perf profile              PASS
P4D: B-cache + Direct Stream compatibility              PASS
P4E: B-cache stress / CDC manual subset                  PASS
P4F: Representative B-cache tests added to full regression PASS
```

Final full regression:

```text
TOTAL : 47
PASS  : 47
FAIL  : 0
```

Representative B-cache regression items:

```text
gemm_2lane_bcache_dma_load_store_stress
gemm_2lane_bcache_axis_stream_load_store_stress
gemm_2lane_bcache_direct_stream_load_store_stress
```

P4E also manually covered the CDC variants at:

```text
dma_clk  = 10ns
core_clk = 13ns
```


## 9B. P5 Packed B-Cache Preload Closure

P5 adds an optional packed B-cache preload path on top of the P4 B-cache architecture.

Effective packed-preload mode:

```text
GEMM_MAC_LANES=2
GEMM_ENABLE_B_CACHE=1
GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1
base_addr_b[1:0] == 0
```

First implementation policy:

```text
aligned B base:
  use packed B-cache preload

unaligned B base:
  fallback to scalar P4 B-cache preload
```

The key local-read contract update is:

```text
old scratchpad adapter return:
  mem_rd_data[7:0]  = requested byte
  mem_rd_data[31:8] = zero

new scratchpad adapter return:
  mem_rd_data[31:0] = 32-bit byte window starting at requested address
```

Scalar compatibility is preserved because scalar GEMM reads still consume only `mem_rd_data[7:0]`.

Focused P5 profile result:

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

P5 validation completed:

```text
P5A: packed operand read spec                         PASS
P5B: safe parameter plumbing, default-off 47/47 PASS   PASS
P5C: packed B-cache preload RTL + baseline 47/47 PASS  PASS
P5D: focused perf/profile compare                      PASS
P5E: Direct Stream compatibility                       PASS
P5F: stress / CDC manual subset                         PASS
P5G: representative packed-read regression added        PASS
```

Final P5 regression:

```text
TOTAL : 56
PASS  : 56
FAIL  : 0
```



## 9C. P6 Scalar A-Row Cache Closure

P6 adds an optional scalar A-row cache path on top of the P5 packed B-cache architecture.

Effective validated mode:

```text
GEMM_MAC_LANES=2
GEMM_ENABLE_B_CACHE=1
GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1
GEMM_ENABLE_A_ROW_CACHE=1
GEMM_A_ROW_CACHE_MAX_K=4
```

Implemented behavior:

```text
for each output row m:
  preload A[m][0 .. K-1] once into a_row_cache
  compute all C[m][n] using cached A row and cached B operands
```

A-side read model:

```text
without A-row cache:
  A reads = M * N * K

with scalar A-row cache:
  A preload reads = M * K

saved A reads = M * K * (N - 1)
```

Focused P6 profile result:

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

P6 validation completed:

```text
P6A: A-row cache spec                                PASS
P6B: safe parameter plumbing                         PASS
P6C: scalar A-row cache RTL prototype                PASS
P6D: focused perf/profile compare                    PASS
P6E: Direct Stream compatibility                     PASS
P6F: stress / CDC subset                             PASS
P6G: representative A-row-cache regression added     PASS
```

Final P6 regression:

```text
TOTAL : 56
PASS  : 56
FAIL  : 0
```

Representative A-row-cache regression items:

```text
gemm_2lane_arow_cache_dma_load_store_stress
gemm_2lane_arow_cache_axis_stream_load_store_stress
gemm_2lane_arow_cache_direct_stream_load_store_stress
gemm_2lane_arow_cache_dma_load_store_cdc
gemm_2lane_arow_cache_axis_stream_load_store_cdc
gemm_2lane_arow_cache_direct_stream_load_store_cdc
```

---

## 10. Risks and Mitigations

### Risk 1: Counters change timing

Counters must remain passive and must not feed back into datapath control.

Mitigation:

```text
counter updates are derived from existing FSM events
counter values are used only by UVM/profile checks
```

### Risk 2: Multi-MAC requires more memory bandwidth

The first 2-lane design still performs sequential operand reads, so speedup is limited.

Mitigation:

```text
measure first
keep 2-lane correctness stable
optimize memory bandwidth in a later stage
```

### Risk 3: Direct Stream mode diverges from scratchpad mode

Mitigation:

```text
run Direct Stream smoke with GEMM_MAC_LANES=2 in regression
run DMA / AXI-Stream / Direct Stream 2-lane stress and CDC sanity in regression
```

### Risk 4: Single-lane regression changes

Mitigation:

```text
GEMM_MAC_LANES default remains 1
run full 47-item regression after changes
```

---

## 11. Recommended Next Stages

### Stage P4: B-Cache Operand Reuse Optimization

Implemented and verified:

```text
Optional B-cache parameterization
B-cache preload FSM
B-cache compute bypass for lane0/lane1 B operands
Fallback to no-cache path when disabled or unsupported
Direct Stream compatibility
DMA / AXI-Stream / Direct Stream stress validation
Representative B-cache regression inclusion
```

Status:

```text
PASS
Regression moved from 44/44 to 47/47
```

### Stage P5: Packed B-Cache Preload Optimization

Implemented and verified:

```text
use 32-bit local reads to fetch multiple int8 operands
unpack aligned byte lanes locally
reduce narrow operand-read request count
preserve the existing result model and scoreboard checks
```

P5 closed with the following checkpoint:

```text
2-lane GEMM + B-cache + packed B-cache preload + full regression 50/50 PASS
```

### Stage P6: Scalar A-Row Cache Optimization

Implemented and verified:

```text
optional scalar A-row cache
A row preload once per output row m
A-row reuse across output columns n
integration with 2-lane + B-cache + packed B-cache performance stack
DMA / AXI-Stream / Direct Stream stress and CDC validation
```

P6 closed with the following checkpoint:

```text
2-lane GEMM + B-cache + packed B-cache preload + A-row cache + full regression 56/56 PASS
```

### Stage P7: Candidate Next Optimization

Recommended next candidates:

```text
packed A-row preload
larger GEMM dimensions
4-lane K-parallel GEMM
tile-based scheduling
```

## 12. Current Acceptance Status

```text
Performance Counter Baseline        : DONE
Performance Profile Baseline        : DONE
2-Lane MAC Prototype                : DONE
2-Lane Direct Stream Compatibility  : DONE
2-Lane Smoke/Profile Regression     : DONE
2-Lane Stress / CDC Hardening       : DONE
2-Lane Stress / CDC Regression      : DONE
B-Cache Operand Reuse Optimization  : DONE
B-Cache Direct Stream Compatibility : DONE
B-Cache Stress / CDC Manual Subset  : DONE
B-Cache Regression Inclusion        : DONE
Packed B-Cache Preload Optimization : DONE
Packed B-Cache Stress / CDC Subset  : DONE
Packed B-Cache Regression Inclusion : DONE
Scalar A-Row Cache Optimization   : DONE
A-Row Cache Stress / CDC Subset    : DONE
A-Row Cache Regression Inclusion   : DONE

Regression:
  56/56 PASS
```

---

## 13. Future Direction

After P6, the project can move toward:

```text
packed A-row preload
packed A compute reads
operand staging buffers
wider or multi-read operand access
tile-based GEMM
4-lane K-parallel GEMM
better Direct Stream operand reuse
optional C direct-store path
more constrained-random coverage
coverage closure
```

The guiding principle remains:

```text
measure first
accelerate second
verify every step
```
