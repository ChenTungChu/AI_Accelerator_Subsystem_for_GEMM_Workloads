# AI Accelerator Subsystem for GEMM Workloads

## Overview

This repository is a subsystem-level RTL and UVM verification project for a GEMM-oriented AI accelerator path.

The design currently validates end-to-end data-movement flows for multiple GEMM input paths:

```text
Host / DMA / AXI-Stream preload / Direct Stream operand preload
    -> Scratchpad memory or GEMM operand buffer
    -> GEMM core
    -> Scratchpad result C
    -> Host readback or DMA store
    -> Software reference / scoreboard compare
```

The current focus is subsystem integration, DMA load/store behavior, AXI-Stream frontend integration, Direct Stream GEMM frontend integration, CDC-aware control/status handling, reset robustness, UVM scoreboard-based verification, and the first performance-oriented GEMM datapath upgrade.

Current milestone:

```text
Performance GEMM P2: 2-Lane MAC Datapath Prototype Completed

Regression:
  TOTAL : 38
  PASS  : 38
  FAIL  : 0
```

The current baseline includes both:

```text
GEMM_MAC_LANES=1 mainline regression
GEMM_MAC_LANES=2 focused performance subset regression
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

Performance GEMM P2 adds a parameterized 2-lane K-parallel MAC path inside `gemm_top` while preserving the original single-lane behavior as the default safe configuration.

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

`gemm_top` now supports:

```systemverilog
parameter int GEMM_MAC_LANES = 1
```

Supported lane settings:

```text
GEMM_MAC_LANES=1 : original single-MAC baseline
GEMM_MAC_LANES=2 : 2-lane K-parallel MAC prototype
```

The default remains `1` so existing regression behavior is preserved unless the run script explicitly overrides the parameter.

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

This is the compatibility baseline used by the main regression.

### 2-lane K-parallel prototype

When `GEMM_MAC_LANES=2`, the core processes up to two K positions per accumulation step:

```text
for k in 0 .. K-1 step 2:
    acc += A[m][k + 0] * B[k + 0][n]

    if (k + 1 < K):
        acc += A[m][k + 1] * B[k + 1][n]
```

Odd-K cases are handled by lane masking. For example, `K=1` uses only lane 0, while `K=2` and `K=4` use both lanes.

The first 2-lane implementation is correctness-first. It keeps the existing single-read local memory interface and sequentially collects lane operands before committing the multi-lane MAC step.

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
gemm_perf_output_count : C outputs committed
```

For both single-lane and 2-lane modes:

```text
gemm_perf_mac_count    = M * N * K
gemm_perf_output_count = M * N
```

In 2-lane mode, `gemm_perf_mac_count` increments by the number of valid lanes committed, not by the number of MAC FSM states.

---

## Current Performance Profile Baselines

### Single-lane baseline (`GEMM_MAC_LANES=1`)

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

### 2-lane baseline (`GEMM_MAC_LANES=2`)

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

`CASE_ID=100` has `K=1`, so lane 1 is masked and the cycle count remains unchanged. Cases with `K>=2` show the 2-lane path is active.

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
- 2-lane profile summary generation

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

This is the main strict verification path.

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

Direct Stream B1 verifies that A/B operands can be streamed into local GEMM operand buffers instead of scratchpad, while C still writes to scratchpad and is exported through the existing DMA store / S2MM path.

Mode behavior:

```text
gemm_input_stream_mode = 0:
    GEMM A/B reads -> scratchpad
    GEMM C writes  -> scratchpad

gemm_input_stream_mode = 1:
    GEMM A/B reads -> gemm_operand_buffer
    GEMM C writes  -> scratchpad
```

The 2-lane GEMM path has been verified in Direct Stream mode through the 2-lane direct-stream smoke regression subset.

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

Clock periods are configurable from the run script:

```text
+DMA_CLK_PERIOD_NS=<real>
+CORE_CLK_PERIOD_NS=<real>
```

Default clock periods:

```text
dma_clk  = 10 ns
core_clk = 14 ns
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
- 2-lane GEMM performance counter smoke
- 2-lane GEMM performance profile
- 2-lane Direct Stream compatibility smoke
- back-to-back GEMM jobs
- reset recovery between jobs
- mixed corner recipe
- mid-run reset / expected-abort recovery
- helper fallback sanity checks

Important case groups:

```text
Fixed baseline       : CASE_ID 5
Variable dimension   : CASE_ID 100, 101, 105
Configurable base    : CASE_ID 400, 401, 402, 403
RUN_ALL recipe       : 100 -> 101 -> 105 -> 5 -> 400 -> 401 -> 402 -> 403
Corner recipe        : 5 -> 101 -> 105 -> 403
```

---

## Current Regression Baseline

The current full UVM regression contains 38 items and is passing:

```text
TOTAL : 38
PASS  : 38
FAIL  : 0
```

Covered categories:

- host primary smoke
- DMA load smoke with scoreboard
- DMA load stress
- DMA load CDC clock-ratio sanity
- DMA load error/recovery
- DMA store smoke with scoreboard
- DMA store error/recovery
- DMA load + store stress
- AXI-Stream preload smoke with scoreboard
- AXI-Stream preload error/recovery
- AXI-Stream load-store stress
- AXI-Stream CDC clock-ratio sanity
- Direct Stream smoke with scoreboard
- Direct Stream error/recovery
- Direct Stream load-store stress
- Direct Stream CDC clock-ratio sanity
- GEMM performance counter smoke
- GEMM performance profile
- GEMM 2-lane performance counter smoke
- GEMM 2-lane performance profile
- GEMM 2-lane Direct Stream smoke
- back-to-back
- reset recovery
- corner recipe
- mid-run reset / abort recovery
- helper fallback sanity

Manual/non-regression stress status:

```text
DMA load-store stress 20-job manual run       : PASS
AXI-Stream load-store stress 20-job manual run: PASS
Direct Stream load-store 20-job run           : not yet recorded
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

The regression runner checks each generated log for:

```text
UVM_ERROR : 0
UVM_FATAL : 0
```

For GUI-based QuestaSim runs, the flow uses:

```tcl
onfinish stop
```

to avoid `$finish` confirmation popups during regression.

---

## Useful Single-Test Runs

### Performance counter smoke, single-lane baseline

```tcl
set UVM_TEST ai_accel_subsys_perf_counter_smoke_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 100
set RUN_ALL 1
set GEMM_MAC_LANES 1
do run_uvm.tcl
```

### Performance profile, single-lane baseline

```tcl
set UVM_TEST ai_accel_subsys_perf_profile_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 100
set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14
set GEMM_MAC_LANES 1
do run_uvm.tcl
```

### Performance counter smoke, 2-lane

```tcl
set UVM_TEST ai_accel_subsys_perf_counter_smoke_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 100
set RUN_ALL 1
set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14
set GEMM_MAC_LANES 2
do run_uvm.tcl
```

### Performance profile, 2-lane

```tcl
set UVM_TEST ai_accel_subsys_perf_profile_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 100
set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14
set GEMM_MAC_LANES 2
do run_uvm.tcl
```

### Direct Stream smoke RUN_ALL, 2-lane

```tcl
set UVM_TEST ai_accel_subsys_direct_stream_smoke_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 100
set RUN_ALL 1
set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14
set GEMM_MAC_LANES 2
do run_uvm.tcl
```

### DMA load RUN_ALL

```tcl
set UVM_TEST ai_accel_subsys_dma_load_smoke_test
set ENABLE_RESULT_CHECK 1
set RUN_ALL 1
do run_uvm.tcl
```

### DMA load stress

```tcl
set UVM_TEST ai_accel_subsys_dma_load_stress_test
set ENABLE_RESULT_CHECK 1
set STRESS_JOB_COUNT 8
set STRESS_SEED 20260502
set STRESS_RANDOM 1
set STRESS_GAP_CYCLES 10
do run_uvm.tcl
```

### DMA store / S2MM RUN_ALL

```tcl
set UVM_TEST ai_accel_subsys_dma_store_smoke_test
set ENABLE_RESULT_CHECK 1
set RUN_ALL 1
do run_uvm.tcl
```

### AXI-Stream preload RUN_ALL

```tcl
set UVM_TEST ai_accel_subsys_axis_stream_preload_smoke_test
set ENABLE_RESULT_CHECK 1
set RUN_ALL 1
do run_uvm.tcl
```

### Direct Stream smoke RUN_ALL

```tcl
set UVM_TEST ai_accel_subsys_direct_stream_smoke_test
set ENABLE_RESULT_CHECK 1
set RUN_ALL 1
do run_uvm.tcl
```

---

## Log Handling

`run_uvm.tcl` generates timestamped logs under `sim/logs/`.

Current log format:

```text
YYYYMMDD_HHMMSS_<test_specific_name>_lanes_<GEMM_MAC_LANES>.log
```

The lane tag makes 1-lane and 2-lane runs easier to distinguish.

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
- fixed and variable GEMM dimensions
- configurable A/B/C base addresses
- scoreboard-based result checking
- repeated jobs in one simulation
- reset recovery and mid-run abort recovery
- DMA load into scratchpad
- DMA multi-beat load behavior
- DMA source RRESP error recovery
- DMA load stress behavior
- DMA store / S2MM result movement out of scratchpad
- DMA destination memory compare
- DMA destination BRESP error recovery
- repeated full DMA load -> GEMM -> DMA store jobs
- AXI-Stream preload into scratchpad Port1
- AXI-Stream MM2S source read behavior
- AXI-Stream async FIFO CDC behavior
- AXI-Stream source RRESP error recovery
- repeated full AXI-Stream preload -> GEMM -> DMA store jobs
- Direct Stream preload into GEMM operand buffers
- Direct Stream MM2S source read behavior
- Direct Stream async FIFO CDC behavior
- Direct Stream source RRESP error recovery
- Direct Stream operand-buffer GEMM A/B read behavior
- repeated full Direct Stream preload -> GEMM -> DMA store jobs
- CDC-aware GEMM control/status crossing
- alternate `dma_clk` / `core_clk` ratio sanity
- Port0 ownership recovery after DMA load/store errors
- Port1 ownership switching between AXI-Stream preload and GEMM
- transparent scratchpad-mode bypass through `gemm_input_mem_router`
- GEMM performance counters
- single-lane performance profile baseline
- 2-lane K-parallel GEMM datapath correctness
- 2-lane Direct Stream operand-buffer compatibility
- unattended full UVM regression flow

---

## Current Milestone Summary

```text
Performance GEMM P2: 2-Lane MAC Datapath Prototype Completed

Completed:
  P0: GEMM performance counter smoke             PASS
  P1: GEMM performance profile baseline          PASS
  P2A: GEMM_MAC_LANES parameter baseline         PASS
  P2B: 2-lane FSM/datapath added                 PASS
  P2C: 2-lane host-primary profile baseline      PASS
  P2D: 2-lane Direct Stream compatibility        PASS
  P2E: 2-lane subset regression                  PASS

Regression:
  38/38 PASS
```

---

## Summary

This repository currently contains a working GEMM-oriented AI accelerator subsystem with:

- stable scratchpad-backed RTL integration
- host-primary memory path verification
- DMA load path verification
- DMA store / S2MM result path verification
- full DMA load + GEMM + DMA store stress verification
- AXI-Stream preload path verification
- AXI-Stream frontend CDC verification
- full AXI-Stream preload + GEMM + DMA store stress verification
- Direct Stream GEMM frontend B1 verification
- Direct Stream frontend CDC verification
- full Direct Stream preload + GEMM + DMA store stress verification
- CDC-aware GEMM control/status handling
- DMA, AXI-Stream, and Direct Stream stress and error/recovery coverage
- scoreboard-based result checking
- reset and abort recovery tests
- configurable clock-ratio regression coverage
- GEMM performance counter and profile baseline
- parameterized 1-lane / 2-lane GEMM compute path
- focused 2-lane regression subset
- full UVM regression automation

This is the current subsystem verification and performance-GEMM baseline.
