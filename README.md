# AI Accelerator Subsystem for GEMM Workloads

## Overview

This repository is a subsystem-level RTL and UVM verification project for a GEMM-oriented AI accelerator path.

The design currently validates end-to-end scratchpad-based data-movement flows:

```text
Host / DMA / AXI-Stream preload A and B
    -> Scratchpad memory
    -> GEMM core
    -> Scratchpad result C
    -> Host readback or DMA store
    -> Software reference / scoreboard compare
```

The current focus is subsystem integration, DMA load/store behavior, AXI-Stream frontend integration, CDC-aware control/status handling, reset robustness, and UVM scoreboard-based verification.

---

## Main RTL Blocks

- `ai_accel_subsys`
- `gemm_top`
- `gemm_scratchpad_adapter`
- `dma_load_engine`
- `dma_store_engine`
- `scratchpad_port0_owner_mux`
- `scratchpad_port1_owner_mux`
- `axi_mm2s_dma`
- `axi_stream_loader`
- `axis_async_fifo`
- `axis_preload_engine`
- `axis_scratchpad_write_adapter`
- `axi_mm_dual_port_bram`

The `axi_mm_dual_port_bram` model is treated as a stable scratchpad baseline. Current development is focused on subsystem integration, DMA load/store behavior, AXI-Stream preload behavior, CDC-aware control/status crossing, and verification around that memory subsystem.

---

## Data Model

Current GEMM assumptions:

- A and B are signed 8-bit elements
- C / accumulator values are signed 32-bit
- matrices use compact row-major layout
- C is read back or stored out as signed 32-bit words

Default scratchpad map:

```text
A = 0x0000_0000
B = 0x0000_0100
C = 0x0000_0200
```

Some tests use shifted legal base addresses to verify configurable memory mapping.

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
- DMA destination memory model
- helper fallback path

The control monitor publishes phase-aware `START` and `DONE` events. The result bridge publishes result payloads into the scoreboard.

The scoreboard checks:

- control profile consistency
- latency sanity
- ctrl/result pairing
- result compare correctness

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

The DMA load path verifies DMA-loaded A/B, GEMM execution, C readback, scoreboard compare, stress behavior, CDC sanity, and error recovery.

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

The DMA store path verifies that GEMM result C can be moved out of scratchpad through a destination AXI-MM write path and compared from the destination memory model.

### DMA load + store stress path

```text
repeat N jobs:
    clear C
    clear destination memory
    preload DMA source A/B
    DMA load A/B into scratchpad
    run GEMM
    DMA store C to destination memory
    compare destination memory
    publish result payload
```

This is the full DMA data-movement stress path.

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

The AXI-Stream preload path verifies that A/B can be streamed into scratchpad through a CDC-aware AXI-Stream frontend before launching the existing GEMM datapath.

V1 uses a headerless AXI-Stream payload:

```text
beat 0      : payload data
beat 1      : payload data
...
beat N - 1  : payload data with TLAST = 1
```

The testbench provides metadata through control signals:

```text
axis_src_base_addr
axis_dst_base_addr
axis_load_beats
```

---

## CDC-Aware Baseline

The subsystem includes CDC-aware control/status handling between `dma_clk` and `core_clk`.

Current CDC behavior:

- `dma_load_engine` and scratchpad Port0 DMA load/store paths remain in `dma_clk`
- GEMM compute path remains in `core_clk`
- AXI-Stream preload source read side starts in `dma_clk`
- AXI-Stream preload destination write side runs in `core_clk`
- `axis_async_fifo` transfers `{tlast, tdata}` across the DMA/core clock boundary
- `axis_preload_engine` coordinates source-side MM2S and core-side stream loader activity
- `acc_start` is rising-edge detected in `dma_clk`
- GEMM config is captured in `dma_clk` before start
- `acc_start` crosses into `core_clk` through a toggle synchronizer
- GEMM config is latched into core-domain registers at GEMM start
- `acc_done` crosses back from `core_clk` to `dma_clk` through a toggle synchronizer
- `acc_busy` crosses back from `core_clk` to `dma_clk` through a level synchronizer

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

The full regression includes non-default clock-ratio sanity runs for both DMA load and AXI-Stream load/store paths.

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

DMA load error coverage includes:

- zero `load_beats`
- unaligned source address
- unaligned destination address
- source AXI RRESP error injection
- Port0 ownership recovery after DMA error
- valid DMA/GEMM recovery after errors

DMA store / S2MM error coverage includes:

- zero `store_byte_count`
- unaligned scratchpad source address
- unaligned destination address
- destination AXI BRESP error injection
- Port0 ownership recovery after DMA store error
- valid S2MM recovery store after errors

The optional manual DMA store error run also covers `start_while_busy`.

DMA stress coverage includes:

- repeated DMA load -> GEMM -> host readback jobs
- repeated DMA load -> GEMM -> DMA store -> destination memory compare jobs
- random or round-robin case selection
- scoreboard pairing across multiple jobs
- stale-result/stale-destination-memory prevention

AXI-Stream preload coverage includes:

- AXI-Stream preload A/B into scratchpad Port1
- MM2S source read through `axi_mm2s_dma`
- AXI-Stream CDC through `axis_async_fifo`
- stream-to-scratchpad write through `axi_stream_loader` and `axis_scratchpad_write_adapter`
- Port1 ownership switching between AXI-Stream preload and GEMM
- GEMM execution using stream-preloaded A/B
- DMA store of C to destination memory
- scoreboard result compare and ctrl/result pairing

AXI-Stream preload error coverage includes:

- zero `axis_load_beats`
- unaligned AXI-Stream source address
- unaligned scratchpad destination address
- AXI-Stream source RRESP error injection
- valid AXI-Stream preload recovery after errors
- valid GEMM + DMA store recovery after AXI-Stream preload errors

AXI-Stream stress coverage includes:

- repeated AXI-Stream preload A/B -> GEMM -> DMA store jobs
- random or round-robin case selection
- scoreboard pairing across multiple AXI-Stream jobs
- AXI-Stream CDC clock-ratio sanity
- 8-job full-regression stress
- 20-job manual/nightly stress

---

## Current Regression Baseline

The current full UVM regression contains 29 items and is passing:

```text
TOTAL : 29
PASS  : 29
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
- back-to-back
- reset recovery
- corner recipe
- mid-run reset / abort recovery
- helper fallback sanity

Manual/non-regression stress status:

```text
DMA load-store stress 20-job manual run       : PASS
AXI-Stream load-store stress 20-job manual run: PASS
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

DMA load RUN_ALL:

```tcl
set UVM_TEST ai_accel_subsys_dma_load_smoke_test
set ENABLE_RESULT_CHECK 1
set RUN_ALL 1
do run_uvm.tcl
```

DMA load stress:

```tcl
set UVM_TEST ai_accel_subsys_dma_load_stress_test
set ENABLE_RESULT_CHECK 1
set STRESS_JOB_COUNT 8
set STRESS_SEED 20260502
set STRESS_RANDOM 1
set STRESS_GAP_CYCLES 10
do run_uvm.tcl
```

DMA load CDC sanity:

```tcl
set UVM_TEST ai_accel_subsys_dma_load_stress_test
set ENABLE_RESULT_CHECK 1
set STRESS_JOB_COUNT 8
set STRESS_SEED 20260502
set STRESS_RANDOM 1
set STRESS_GAP_CYCLES 10
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 13
do run_uvm.tcl
```

DMA store / S2MM RUN_ALL:

```tcl
set UVM_TEST ai_accel_subsys_dma_store_smoke_test
set ENABLE_RESULT_CHECK 1
set RUN_ALL 1
do run_uvm.tcl
```

DMA store / S2MM error recovery:

```tcl
set UVM_TEST ai_accel_subsys_dma_store_error_test
set ENABLE_RESULT_CHECK 0
do run_uvm.tcl
```

Optional DMA store start-while-busy error run:

```tcl
set UVM_TEST ai_accel_subsys_dma_store_error_test
set ENABLE_RESULT_CHECK 0
set EXTRA_PLUSARGS "+RUN_START_WHILE_BUSY=1"
do run_uvm.tcl
```

DMA load + store stress, full-regression version:

```tcl
set UVM_TEST ai_accel_subsys_dma_load_store_stress_test
set ENABLE_RESULT_CHECK 1
set STORE_STRESS_JOB_COUNT 8
set STORE_STRESS_SEED 20260502
set STORE_STRESS_RANDOM 1
set STORE_STRESS_GAP_CYCLES 10
do run_uvm.tcl
```

DMA load + store stress, longer manual/nightly version:

```tcl
set UVM_TEST ai_accel_subsys_dma_load_store_stress_test
set ENABLE_RESULT_CHECK 1
set STORE_STRESS_JOB_COUNT 20
set STORE_STRESS_SEED 20260502
set STORE_STRESS_RANDOM 1
set STORE_STRESS_GAP_CYCLES 10
do run_uvm.tcl
```

AXI-Stream preload RUN_ALL:

```tcl
set UVM_TEST ai_accel_subsys_axis_stream_preload_smoke_test
set ENABLE_RESULT_CHECK 1
set RUN_ALL 1
do run_uvm.tcl
```

AXI-Stream preload error recovery:

```tcl
set UVM_TEST ai_accel_subsys_axis_stream_preload_error_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 100
do run_uvm.tcl
```

AXI-Stream load-store stress, full-regression version:

```tcl
set UVM_TEST ai_accel_subsys_axis_stream_load_store_stress_test
set ENABLE_RESULT_CHECK 1
set AXIS_STRESS_JOB_COUNT 8
set AXIS_STRESS_SEED 20260502
set AXIS_STRESS_RANDOM 1
set AXIS_STRESS_GAP_CYCLES 10
do run_uvm.tcl
```

AXI-Stream load-store stress, longer manual/nightly version:

```tcl
set UVM_TEST ai_accel_subsys_axis_stream_load_store_stress_test
set ENABLE_RESULT_CHECK 1
set AXIS_STRESS_JOB_COUNT 20
set AXIS_STRESS_SEED 20260502
set AXIS_STRESS_RANDOM 1
set AXIS_STRESS_GAP_CYCLES 10
do run_uvm.tcl
```

AXI-Stream load-store CDC sanity:

```tcl
set UVM_TEST ai_accel_subsys_axis_stream_load_store_stress_test
set ENABLE_RESULT_CHECK 1
set AXIS_STRESS_JOB_COUNT 8
set AXIS_STRESS_SEED 20260502
set AXIS_STRESS_RANDOM 1
set AXIS_STRESS_GAP_CYCLES 10
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 13
do run_uvm.tcl
```

---

## Log Handling

`run_uvm.tcl` generates timestamped logs under `sim/logs/`.

Current log format:

```text
YYYYMMDD_HHMMSS_<test_specific_name>.log
```

Example:

```text
20260502_203059_ai_accel_subsys_dma_load_stress_test_jobs_8_seed_20260502_random_1_gap_10_result_1_host_primary.log
```

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

The shared BRAM interface should not be modified only to remove this warning unless the BRAM repository regression is also updated and fully re-run.

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
- CDC-aware GEMM control/status crossing
- alternate `dma_clk` / `core_clk` ratio sanity
- Port0 ownership recovery after DMA load/store errors
- Port1 ownership switching between AXI-Stream preload and GEMM
- unattended full UVM regression flow

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
- CDC-aware GEMM control/status handling
- DMA and AXI-Stream stress and error/recovery coverage
- scoreboard-based result checking
- reset and abort recovery tests
- configurable clock-ratio regression coverage
- full UVM regression automation

This is the current subsystem verification baseline.
