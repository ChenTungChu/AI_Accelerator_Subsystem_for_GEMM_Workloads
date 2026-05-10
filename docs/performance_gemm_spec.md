# Performance GEMM Spec

## 1. Purpose

This document defines the performance-oriented GEMM architecture milestone on top of the completed subsystem-level GEMM, DMA, AXI-Stream, CDC, Direct Stream B1, and scoreboard verification baseline.

The project has now completed the first performance sequence:

```text
P0: GEMM performance counter baseline
P1: GEMM performance profile baseline
P2: 2-lane K-parallel MAC datapath prototype
```

Current full regression baseline:

```text
TOTAL : 38
PASS  : 38
FAIL  : 0
```

The current performance milestone moves the GEMM core from a correctness-first single-MAC engine toward a measurable, parameterized, multi-lane architecture while preserving all existing subsystem paths.

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

The 38-item regression now also includes:

```text
GEMM performance counter smoke
GEMM performance profile
GEMM_MAC_LANES=2 performance counter smoke
GEMM_MAC_LANES=2 performance profile
GEMM_MAC_LANES=2 Direct Stream smoke
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
```

### Risk 4: Single-lane regression changes

Mitigation:

```text
GEMM_MAC_LANES default remains 1
run full 38-item regression after changes
```

---

## 11. Recommended Next Stages

### Stage P3: 2-Lane Stress Expansion

Possible additions:

```text
DMA load-store stress, GEMM_MAC_LANES=2
AXI-Stream load-store stress, GEMM_MAC_LANES=2
Direct Stream load-store stress, GEMM_MAC_LANES=2
CDC clock-ratio sanity, GEMM_MAC_LANES=2
```

### Stage P4: Memory-Bandwidth Improvement

The first 2-lane design proves arithmetic-lane correctness but does not widen the memory interface.

Future options:

```text
operand staging registers
wider local operand extraction
operand-buffer multi-read support
Direct Stream tiled operand reuse
```

### Stage P5: 4-Lane Planning

Do not start 4-lane until:

```text
2-lane result correctness is stable
2-lane regression subset is clean
memory bandwidth bottlenecks are understood
```

---

## 12. Current Acceptance Status

```text
Performance Counter Baseline      : DONE
Performance Profile Baseline      : DONE
2-Lane MAC Prototype              : DONE
2-Lane Direct Stream Compatibility: DONE
2-Lane Regression Subset          : DONE

Regression:
  38/38 PASS
```

---

## 13. Future Direction

After P2, the project can move toward:

```text
2-lane stress and CDC expansion
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
