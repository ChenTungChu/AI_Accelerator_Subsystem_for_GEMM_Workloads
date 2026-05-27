# AI Accelerator Subsystem for GEMM Workloads

## Overview

This repository is a subsystem-level RTL and UVM verification project for a GEMM-oriented AI accelerator path.

The design validates end-to-end data movement across multiple GEMM input paths:

```text
Host / DMA / AXI-Stream preload / Direct Stream operand preload
    -> Scratchpad memory or GEMM operand buffer
    -> GEMM core
    -> Scratchpad result C
    -> Host readback or DMA store
    -> Software reference / scoreboard compare
```

The current focus is subsystem integration, DMA load/store behavior, AXI-Stream frontend integration, Direct Stream GEMM frontend integration, CDC-aware control/status handling, reset robustness, UVM scoreboard-based verification, and performance-oriented GEMM datapath upgrades.

Current milestone:

```text
Performance GEMM P9: Larger-Dimension / Cache-Size Scaling Completed

Regression:
  TOTAL : 65
  PASS  : 65
  FAIL  : 0
```

The current baseline includes:

```text
GEMM_MAC_LANES=1 mainline regression
GEMM_MAC_LANES=2 focused performance subset regression
GEMM_MAC_LANES=2 stress / CDC hardening subset regression
GEMM_MAC_LANES=2 + B-cache representative regression
GEMM_MAC_LANES=2 + packed B-cache representative regression
GEMM_MAC_LANES=2 + packed B-cache + A-row cache stress / CDC representative regression
GEMM_MAC_LANES=2 + packed B-cache + A-row cache + packed A-row representative regression
GEMM_MAC_LANES=4 + full cache/preload representative regression
GEMM_MAC_LANES=4 + scaled cache8 large-dimension representative regression
```

Validated P9 scaled-cache configuration:

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

P9 larger-dimension representative cases:

```text
CASE_ID=190 : M=1, N=8, K=8  -> MACS=64,  OUTPUTS=8
CASE_ID=191 : M=2, N=8, K=8  -> MACS=128, OUTPUTS=16
CASE_ID=192 : M=3, N=5, K=7  -> MACS=105, OUTPUTS=15
```

Direct Stream B1 remains supported:

```text
AXI-MM source memory
    -> MM2S DMA
    -> AXI-Stream async FIFO
    -> stream loader
    -> GEMM operand buffer A/B
    -> GEMM reads A/B from operand buffer
    -> GEMM writes C to scratchpad
    -> DMA store C to destination memory
    -> scoreboard compare
```

---

## Main RTL Blocks

- `ai_accel_subsys`
- `gemm_top`
- `gemm_scratchpad_adapter`
- `gemm_input_mem_router`
- `gemm_operand_buffer`
- `gemm_operand_buffer_write_adapter`
- `dma_load_engine`
- `dma_store_engine`
- `scratchpad_port0_owner_mux`
- `scratchpad_port1_owner_mux`
- `axi_mm2s_dma`
- `axi_stream_loader`
- `axis_async_fifo`
- `axis_preload_engine`
- `axis_scratchpad_write_adapter`
- `direct_stream_preload_engine`
- `axi_mm_dual_port_bram`

The `axi_mm_dual_port_bram` model is treated as a stable scratchpad baseline.

`gemm_top` supports:

```systemverilog
parameter int GEMM_MAC_LANES                    = 1
parameter bit GEMM_ENABLE_B_CACHE               = 1'b0
parameter int GEMM_B_CACHE_MAX_K                = 4
parameter int GEMM_B_CACHE_MAX_N                = 4
parameter bit GEMM_ENABLE_PACKED_BCACHE_PRELOAD = 1'b0
parameter bit GEMM_ENABLE_A_ROW_CACHE           = 1'b0
parameter int GEMM_A_ROW_CACHE_MAX_K            = 4
parameter bit GEMM_ENABLE_PACKED_A_ROW_PRELOAD  = 1'b0
```

Supported lane settings:

```text
GEMM_MAC_LANES=1 : original single-MAC baseline
GEMM_MAC_LANES=2 : 2-lane K-parallel MAC prototype
GEMM_MAC_LANES=4 : cache-backed true 4-lane K-parallel MAC path
```

Supported cache-size settings:

```text
Default cache capacity:
  GEMM_B_CACHE_MAX_K=4
  GEMM_B_CACHE_MAX_N=4
  GEMM_A_ROW_CACHE_MAX_K=4

P9 opt-in scaled cache capacity:
  GEMM_B_CACHE_MAX_K=8
  GEMM_B_CACHE_MAX_N=8
  GEMM_A_ROW_CACHE_MAX_K=8
```

The default remains:

```text
GEMM_MAC_LANES=1
GEMM_ENABLE_B_CACHE=0
GEMM_ENABLE_PACKED_BCACHE_PRELOAD=0
GEMM_ENABLE_A_ROW_CACHE=0
GEMM_ENABLE_PACKED_A_ROW_PRELOAD=0
```

This preserves existing regression behavior unless the run script explicitly overrides the performance parameters.

---

## Data Model

Current GEMM assumptions:

- A and B are signed 8-bit elements.
- C / accumulator values are signed 32-bit.
- Matrices use compact row-major layout.
- C is read back or stored out as signed 32-bit words.

Default scratchpad map:

```text
A = 0x0000_0000
B = 0x0000_0100
C = 0x0000_0200
```

Some tests use shifted legal base addresses to verify configurable memory mapping.

For Direct Stream B1, A/B are loaded into local operand buffers instead of scratchpad. The logical A/B base addresses are still used by `gemm_input_mem_router` to classify GEMM reads and translate them into local operand-buffer offsets.

---

## GEMM Compute Architecture

### Single-lane baseline

The default GEMM algorithm is:

```text
for m in 0 .. M-1:
  for n in 0 .. N-1:
    acc = 0
    for k in 0 .. K-1:
      acc += A[m][k] * B[k][n]
    C[m][n] = acc
```

### 2-lane K-parallel prototype

When `GEMM_MAC_LANES=2`, the core processes up to two K positions per accumulation step:

```text
for k in 0 .. K-1 step 2:
    acc += A[m][k + 0] * B[k + 0][n]
    if (k + 1 < K):
        acc += A[m][k + 1] * B[k + 1][n]
```

Odd-K cases are handled by lane masking.

### B-cache operand reuse

When `GEMM_ENABLE_B_CACHE=1` and the active job fits within `GEMM_B_CACHE_MAX_K` and `GEMM_B_CACHE_MAX_N`, `gemm_top` preloads the B matrix tile into a local cache before compute begins:

```text
for k in 0 .. K-1:
  for n in 0 .. N-1:
    b_cache[k][n] = B[k][n]
```

During compute, B operands are read from the local cache instead of repeatedly issuing B reads through the local memory request interface.

### Packed B-cache preload

When both `GEMM_ENABLE_B_CACHE=1` and `GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1`, the B-cache fill path can fetch four int8 B operands per aligned 32-bit local read:

```text
scalar preload:
  one local read per B element

packed preload:
  one aligned local read per four B elements
  unpack mem_rd_data[7:0], [15:8], [23:16], [31:24]
```

Unaligned B bases fall back to the scalar B-cache preload path.

### A-row cache

When `GEMM_ENABLE_A_ROW_CACHE=1`, the GEMM core can preload the current A row once per output row and reuse that row across all output columns:

```text
for each m:
  preload A[m][0 .. K-1] into a_row_cache
  for each n:
    compute C[m][n] using cached A row and cached B operands
```

### Packed A-row preload

When both `GEMM_ENABLE_A_ROW_CACHE=1` and `GEMM_ENABLE_PACKED_A_ROW_PRELOAD=1`, the A-row cache fill path can fetch four int8 A operands per aligned 32-bit local read.

For P9 `K=8`, the packed A-row preload requires two aligned 32-bit reads per A row:

```text
read 0: A[m][0], A[m][1], A[m][2], A[m][3]
read 1: A[m][4], A[m][5], A[m][6], A[m][7]
```

### Cache-backed 4-lane MAC

When `GEMM_MAC_LANES=4` is enabled together with the completed cache/preload stack, the GEMM core can process up to four K positions per accumulation step:

```text
for k in 0 .. K-1 step 4:
    acc += A[m][k + 0] * B[k + 0][n]
    if (k + 1 < K): acc += A[m][k + 1] * B[k + 1][n]
    if (k + 2 < K): acc += A[m][k + 2] * B[k + 2][n]
    if (k + 3 < K): acc += A[m][k + 3] * B[k + 3][n]
```

The first 4-lane implementation is intentionally cache-backed. It reuses the A-row cache and B-cache so four A operands and four B operands are locally available to the compute step without widening the local memory interface.

P9 extends the validated 4-lane full-cache path from the P8 `K/N <= 4` class to scaled cache dimensions:

```text
B-cache: K/N <= 8
A-row cache: K <= 8
```

### GEMM completion semantics

`gemm_top.done` means:

```text
all C write requests have completed and the final C word is visible to downstream readers
```

This is stronger than a request-issued definition and is required for flows that launch DMA store immediately after `acc_done`.

---

## Performance Counters

The GEMM core exposes passive performance counters:

```text
gemm_perf_busy_cycles
gemm_perf_mac_count
gemm_perf_output_count
```

Counter policy:

```text
clear on reset
clear on accepted GEMM start
remain stable after done until next accepted GEMM start
```

Counter meaning:

```text
gemm_perf_busy_cycles  : cycles while GEMM is busy
gemm_perf_mac_count    : logical MAC operations committed
gemm_perf_output_count : C outputs whose local-memory write completion has been observed
```

For all lane/cache configurations:

```text
gemm_perf_mac_count    = M * N * K
gemm_perf_output_count = M * N
```

In multi-lane mode, `gemm_perf_mac_count` increments by the number of valid lanes committed, not by the number of MAC FSM states.

---

## Current Performance Profile Baselines

### 4-lane full-cache P8 reference

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

### P9 scaled-cache larger-dimension focused cases

```text
CASE_ID | M | N | K | MACS | OUTPUTS | Purpose
190     | 1 | 8 | 8 | 64   | 8       | fills B-cache K/N=8 with one A row
191     | 2 | 8 | 8 | 128  | 16      | verifies B-cache reuse across two A rows
192     | 3 | 5 | 7 | 105  | 15      | non-power-of-two / tail-lane dimension sanity
```

P9 does not lock exact busy-cycle thresholds in regression. It verifies:

```text
UVM_ERROR=0
UVM_FATAL=0
result compare PASS
mac_count = M*N*K
output_count = M*N
larger dimensions run through DMA, AXI-Stream, and Direct Stream paths
```

---

## Verification Architecture

The UVM environment includes:

- control monitor
- scoreboard
- result bridge
- AXI-MM host agent
- host traffic checker
- DMA source memory model
- AXI-Stream preload source memory responder
- Direct Stream preload source memory responder
- DMA destination memory model
- helper fallback path

The control monitor publishes phase-aware `START` and `DONE` events. The result bridge publishes result payloads into the scoreboard.

The scoreboard checks:

- control profile consistency
- latency sanity
- ctrl/result pairing
- result compare correctness

Performance tests additionally check:

- `gemm_perf_mac_count == M*N*K`
- `gemm_perf_output_count == M*N`
- `gemm_perf_busy_cycles > 0`
- counter clear/update across multiple jobs
- profile summary generation

---

## Execution Paths

### Host-primary path

```text
host clear C
host preload A/B
launch GEMM
host readback C
scoreboard compare
```

### DMA load path

```text
DMA source memory
    -> dma_load_engine
    -> scratchpad_port0_owner_mux
    -> BRAM Port0
    -> GEMM
    -> Host readback C
    -> result_bridge / scoreboard
```

### DMA store / S2MM path

```text
DMA source memory
    -> DMA load A/B into scratchpad
    -> GEMM
    -> C written into scratchpad
    -> dma_store_engine
    -> destination AXI-MM memory model
    -> result_bridge / scoreboard
```

### AXI-Stream preload path

```text
DMA / AXIS source memory
    -> axis_src_axi_ar/r responder
    -> axi_mm2s_dma
    -> axis_async_fifo
    -> axi_stream_loader
    -> axis_scratchpad_write_adapter
    -> scratchpad_port1_owner_mux
    -> BRAM Port1
    -> GEMM
    -> dma_store_engine
    -> destination AXI-MM memory model
    -> result_bridge / scoreboard
```

### Direct Stream GEMM frontend path

```text
DMA / Direct Stream source memory
    -> ds_src_axi_ar/r responder
    -> axi_mm2s_dma
    -> axis_async_fifo
    -> axi_stream_loader
    -> gemm_operand_buffer_write_adapter
    -> gemm_operand_buffer A/B
    -> gemm_input_mem_router
    -> GEMM
    -> scratchpad C
    -> dma_store_engine
    -> destination AXI-MM memory model
    -> result_bridge / scoreboard
```

---

## CDC-Aware Baseline

The subsystem includes CDC-aware control/status handling between `dma_clk` and `core_clk`.

Current CDC behavior:

- `dma_load_engine` and scratchpad Port0 DMA load/store paths remain in `dma_clk`.
- GEMM compute path remains in `core_clk`.
- AXI-Stream preload source read side starts in `dma_clk`.
- AXI-Stream preload destination write side runs in `core_clk`.
- Direct Stream source read side starts in `dma_clk`.
- Direct Stream operand buffer write side runs in `core_clk`.
- `axis_async_fifo` transfers `{tlast, tdata}` across the DMA/core clock boundary.
- `acc_start` crosses into `core_clk` through a toggle synchronizer.
- GEMM config is latched into core-domain registers at GEMM start.
- `gemm_input_stream_mode` is captured with the GEMM job configuration.
- `acc_done` crosses back from `core_clk` to `dma_clk` through a toggle synchronizer.
- `acc_busy` crosses back from `core_clk` to `dma_clk` through a level synchronizer.

Default clock periods:

```text
dma_clk  = 10 ns
core_clk = 14 ns
```

CDC sanity commonly uses:

```text
dma_clk  = 10 ns
core_clk = 13 ns
```

---

## Implemented Coverage

Current UVM regression covers:

- smoke tests for fixed, variable-dimension, and configurable-base GEMM cases
- DMA load smoke with scoreboard integration
- DMA load stress regression
- DMA load CDC clock-ratio sanity
- DMA load error and recovery behavior
- DMA store / S2MM smoke with scoreboard integration
- DMA store / S2MM error and recovery behavior
- DMA load + GEMM + DMA store stress regression
- AXI-Stream preload smoke with scoreboard integration
- AXI-Stream preload error and recovery behavior
- AXI-Stream load-store stress regression
- AXI-Stream CDC clock-ratio sanity
- Direct Stream smoke with scoreboard integration
- Direct Stream error and recovery behavior
- Direct Stream load-store stress regression
- Direct Stream CDC clock-ratio sanity
- GEMM performance counter smoke
- GEMM performance profile baseline
- 2-lane GEMM performance and stress subsets
- B-cache / packed B-cache / A-row cache / packed A-row cache subsets
- cache-backed 4-lane MAC representative regression
- P9 scaled-cache large-dimension representative regression
- back-to-back GEMM jobs
- reset recovery between jobs
- mixed corner recipe
- mid-run reset / expected-abort recovery
- helper fallback sanity checks

Important case groups:

```text
Fixed baseline       : CASE_ID 5
Variable dimension   : CASE_ID 100, 101, 105
P9 larger dimension  : CASE_ID 190, 191, 192
Configurable base    : CASE_ID 400, 401, 402, 403
RUN_ALL recipe       : 100 -> 101 -> 105 -> 5 -> 400 -> 401 -> 402 -> 403
Corner recipe        : 5 -> 101 -> 105 -> 403
```

The default stress pools intentionally remain focused on the original 8-case set. P9 large-dimension cases are included through forced single-case representative items so full regression remains meaningful without making every stress item heavier.

---

## Current Regression Baseline

The current full UVM regression contains 65 items and is passing:

```text
TOTAL : 65
PASS  : 65
FAIL  : 0
```

P9H added these representative scaled-cache larger-dimension items:

```text
gemm_4lane_scaled_fullcache_dma_load_store_case190
gemm_4lane_scaled_fullcache_axis_stream_load_store_case191
gemm_4lane_scaled_fullcache_direct_stream_load_store_case192
```

These use forced single-case mode:

```text
CASE_ID=190 : DMA load-store path
CASE_ID=191 : AXI-Stream load-store path
CASE_ID=192 : Direct Stream load-store path
```

The forced-case policy is:

```text
CASE_ID=0        : not forced; use built-in/random stress pool
CASE_ID != 0     : forced single-case mode for directed regression/sanity
```

---

## Running Regression

From the `sim/` directory:

```tcl
do compile_uvm.tcl
do run_full_uvm_regression.tcl
```

Optional compile-and-run:

```tcl
set DO_COMPILE 1
do run_full_uvm_regression.tcl
```

Optional fail-fast debug:

```tcl
set STOP_ON_FIRST_FAIL 1
do run_full_uvm_regression.tcl
```

The regression runner checks each generated log for:

```text
UVM_ERROR : 0
UVM_FATAL : 0
```

---

## Useful P9 Single-Test Runs

### P9 DMA load-store large case

```tcl
set UVM_TEST ai_accel_subsys_dma_load_store_stress_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 190
set STORE_STRESS_JOB_COUNT 1
set STORE_STRESS_RANDOM 0
set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14
set GEMM_MAC_LANES 4
set GEMM_ENABLE_B_CACHE 1
set GEMM_B_CACHE_MAX_K 8
set GEMM_B_CACHE_MAX_N 8
set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
set GEMM_ENABLE_A_ROW_CACHE 1
set GEMM_A_ROW_CACHE_MAX_K 8
set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1
do run_uvm.tcl
```

### P9 AXI-Stream load-store large case

```tcl
set UVM_TEST ai_accel_subsys_axis_stream_load_store_stress_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 191
set AXIS_STRESS_JOB_COUNT 1
set AXIS_STRESS_RANDOM 0
set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14
set GEMM_MAC_LANES 4
set GEMM_ENABLE_B_CACHE 1
set GEMM_B_CACHE_MAX_K 8
set GEMM_B_CACHE_MAX_N 8
set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
set GEMM_ENABLE_A_ROW_CACHE 1
set GEMM_A_ROW_CACHE_MAX_K 8
set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1
do run_uvm.tcl
```

### P9 Direct Stream load-store large case

```tcl
set UVM_TEST ai_accel_subsys_direct_stream_load_store_stress_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 192
set DS_STRESS_JOB_COUNT 1
set DS_STRESS_RANDOM 0
set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14
set GEMM_MAC_LANES 4
set GEMM_ENABLE_B_CACHE 1
set GEMM_B_CACHE_MAX_K 8
set GEMM_B_CACHE_MAX_N 8
set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
set GEMM_ENABLE_A_ROW_CACHE 1
set GEMM_A_ROW_CACHE_MAX_K 8
set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1
do run_uvm.tcl
```

---

## Log Handling

`run_uvm.tcl` generates timestamped logs under `sim/logs/`.

The log name includes feature tags for lanes, B-cache, packed B-cache, A-row cache, packed A-row preload, and cache-size settings so P9 runs can be distinguished from earlier P8/P7/P6 runs.

The log directory keeps only the newest 50 `.log` files by default. This can be overridden before running a test:

```tcl
set LOG_KEEP_COUNT 100
do run_uvm.tcl
```

---

## Known Warning

Questa may report `vsim-3838` multiple-driver warnings around `bram_axi0_if` request-side signals.

This warning is currently classified as a known simulator/interface warning related to the shared `axi_mm_if` clocking-block driver model and the Port0 owner mux connection style.

Current policy:

```text
Known warning accepted.
Functional regression passes.
No BRAM interface semantic change required.
```

---

## What This Baseline Proves

At this checkpoint, the subsystem verifies:

- scratchpad-backed GEMM execution
- fixed, variable, configurable-base, and P9 larger-dimension GEMM cases
- scoreboard-based result checking
- repeated jobs in one simulation
- reset recovery and mid-run abort recovery
- DMA load into scratchpad
- DMA store / S2MM result movement out of scratchpad
- AXI-Stream preload into scratchpad Port1
- Direct Stream preload into GEMM operand buffers
- CDC-aware GEMM control/status crossing
- alternate `dma_clk` / `core_clk` ratio sanity
- Port0 ownership recovery after DMA load/store errors
- Port1 ownership switching between AXI-Stream preload and GEMM
- transparent scratchpad-mode bypass through `gemm_input_mem_router`
- GEMM performance counters
- parameterized 1-lane / 2-lane / 4-lane GEMM compute path
- B-cache operand reuse for supported K/N tiles
- packed B-cache preload for aligned B regions
- scalar A-row cache and packed A-row preload
- cache-backed true 4-lane MAC correctness
- scaled B-cache K/N=8 and A-row K=8 correctness
- larger-dimension path compatibility across DMA, AXI-Stream, and Direct Stream
- corrected GEMM done semantics after final C write completion
- unattended full UVM regression flow with failed-item reporting

---

## Current Milestone Summary

```text
Performance GEMM P9: Larger-Dimension / Cache-Size Scaling Completed

Completed:
  P0: GEMM performance counter smoke                       PASS
  P1: GEMM performance profile baseline                    PASS
  P2: 2-lane MAC datapath                                  PASS
  P3: 2-lane stress / CDC hardening                        PASS
  P4: B-cache operand reuse                                PASS
  P5: packed B-cache preload                               PASS
  P6: scalar A-row cache                                   PASS
  P7: packed A-row preload                                 PASS
  P8: cache-backed true 4-lane MAC                         PASS
  P9B: safe parameter validation / plumbing                PASS
  P9C: scaled cache compatibility, default clock           PASS
  P9D: scaled cache CDC sanity, clk10/13                   PASS
  P9E: focused perf/profile compare                        PASS
  P9F: larger-dimension CASE_ID support                    PASS
  P9G: large-dimension path compatibility sanity           PASS
  P9H: regression integration                              PASS

Regression:
  65/65 PASS

Next:
  P10 candidate: tile-based scheduling / multi-tile GEMM / C accumulation strategy
```

---

## Summary

This repository currently contains a working GEMM-oriented AI accelerator subsystem with:

- stable scratchpad-backed RTL integration
- host-primary memory path verification
- DMA load path verification
- DMA store / S2MM result path verification
- AXI-Stream preload path verification
- Direct Stream GEMM frontend verification
- CDC-aware GEMM control/status handling
- DMA, AXI-Stream, and Direct Stream stress and error/recovery coverage
- scoreboard-based result checking
- reset and abort recovery tests
- configurable clock-ratio regression coverage
- GEMM performance counter and profile baseline
- parameterized 1-lane / 2-lane / 4-lane GEMM compute path
- B-cache operand reuse optimization
- packed B-cache preload optimization
- scalar A-row cache optimization
- packed A-row preload optimization
- cache-backed true 4-lane MAC optimization
- scaled cache8 larger-dimension verification
- representative 65-item full UVM regression automation

This is the current subsystem verification and P9 performance-GEMM baseline. The next planned optimization milestone should be selected from tile-based scheduling, multi-tile GEMM, C accumulation, or broader constrained-random coverage closure.
