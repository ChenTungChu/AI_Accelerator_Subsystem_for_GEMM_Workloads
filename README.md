# AI Accelerator Subsystem for GEMM Workloads

## Overview

This repository is a subsystem-level RTL and UVM verification project for a GEMM-oriented AI accelerator path.

The design validates an end-to-end scratchpad-based flow:

```text
Host / DMA load A and B
    -> Scratchpad memory
    -> GEMM core
    -> Scratchpad result C
    -> Host readback
    -> Software reference / scoreboard compare
```

The current focus is subsystem integration, DMA load behavior, CDC-aware control/status handling, reset robustness, and UVM scoreboard-based verification.

---

## Main RTL Blocks

- `ai_accel_subsys`
- `gemm_top`
- `gemm_scratchpad_adapter`
- `dma_load_engine`
- `scratchpad_port0_owner_mux`
- `axi_mm_dual_port_bram`

The `axi_mm_dual_port_bram` model is treated as a stable scratchpad baseline. Current development is focused on integration, DMA load behavior, CDC-aware control/status crossing, and subsystem-level verification around that memory subsystem.

---

## Data Model

Current GEMM assumptions:

- A and B are signed 8-bit elements
- C / accumulator values are signed 32-bit
- matrices use compact row-major layout
- C is read back as signed 32-bit words

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
- helper fallback path

The control monitor publishes phase-aware `START` and `DONE` events. The result bridge publishes post-readback result payloads into the scoreboard.

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

The DMA path verifies DMA-loaded A/B, GEMM execution, C readback, scoreboard compare, stress behavior, and error recovery.

---

## CDC-Aware Baseline

The subsystem now includes a CDC-aware control/status baseline between `dma_clk` and `core_clk`.

Current CDC behavior:

- `dma_load_engine` and scratchpad Port0 DMA load path remain in `dma_clk`
- GEMM compute path remains in `core_clk`
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

The full regression includes a DMA-load CDC sanity run using a non-default clock ratio.

---

## Implemented Coverage

Current UVM regression covers:

- smoke tests for fixed, variable-dimension, and configurable-base GEMM cases
- DMA load smoke with scoreboard integration
- DMA load stress regression
- DMA load CDC clock-ratio sanity
- DMA load error and recovery behavior
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
DMA RUN_ALL recipe   : 100 -> 101 -> 105 -> 5 -> 400 -> 401 -> 402 -> 403
Corner recipe        : 5 -> 101 -> 105 -> 403
```

DMA error coverage includes:

- zero `load_beats`
- unaligned source address
- unaligned destination address
- source AXI RRESP error injection
- Port0 ownership recovery after DMA error
- valid DMA/GEMM recovery after errors

DMA stress coverage repeatedly selects GEMM cases through the DMA load path and verifies scoreboard pairing across multiple jobs.

---

## Current Regression Baseline

The current full UVM regression contains 22 items and is passing:

```text
TOTAL : 22
PASS  : 22
FAIL  : 0
```

Covered categories:

- host primary smoke
- DMA load smoke with scoreboard
- DMA load stress
- DMA load CDC clock-ratio sanity
- DMA load error/recovery
- back-to-back
- reset recovery
- corner recipe
- mid-run reset / abort recovery
- helper fallback sanity

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
- CDC-aware GEMM control/status crossing
- alternate `dma_clk` / `core_clk` ratio sanity
- Port0 ownership recovery after DMA errors
- unattended full UVM regression flow

---

## Summary

This repository currently contains a working GEMM-oriented AI accelerator subsystem with:

- stable scratchpad-backed RTL integration
- host-primary memory path verification
- DMA load path verification
- CDC-aware GEMM control/status handling
- DMA stress and error/recovery coverage
- scoreboard-based result checking
- reset and abort recovery tests
- configurable clock-ratio regression coverage
- full UVM regression automation

This is the current subsystem verification baseline.
