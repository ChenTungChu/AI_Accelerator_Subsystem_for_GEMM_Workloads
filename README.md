# AI Accelerator Subsystem for GEMM Workloads

## Overview

This project is a subsystem-level RTL and verification exercise for a GEMM-oriented AI accelerator path.

The current subsystem focuses on a simple but practical end-to-end flow:

- host-side matrix preload into scratchpad memory
- GEMM core access through a local scratchpad adapter
- result writeback into scratchpad
- host-side readback and comparison against a reference model

The verified subsystem stack is:

- `ai_accel_subsystem`
- `gemm_top`
- `gemm_scratchpad_adapter`
- `axi_mm_dual_port_bram`

The BRAM model is treated as an already-established baseline and is not being reworked as part of this subsystem verification stage.

---

## Current project status

The project is no longer at the earlier non-UVM subsystem baseline stage.

The current verification flow is now centered on a **UVM-based subsystem environment** with:

- control-path monitoring
- result compare / pairing
- host-side AXI memory access through a dedicated host agent
- host traffic checking on the host memory path

Recent UVM runs show:

- `ai_accel_subsys_smoke_test` passes with control summary `start=1 completed=1`, scoreboard result pass, and host traffic checker summary `start_events=1 done_events=1 jobs_created=1 pass=1 fail=0`
- `ai_accel_subsys_back_to_back_test` passes with control summary `start=2 completed=2`, scoreboard pairing `matched=2`, and host traffic checker summary `start_events=2 done_events=2 jobs_created=2 pass=2 fail=0`
- `ai_accel_subsys_reset_recovery_test` passes with control summary `start=2 completed=2`, scoreboard pairing `matched=2`, and host traffic checker summary `start_events=2 done_events=2 jobs_created=2 pass=2 fail=0` :contentReference[oaicite:2]{index=2} :contentReference[oaicite:3]{index=3} :contentReference[oaicite:4]{index=4}

At this point, the subsystem has a working UVM sanity / regression layer for the main execution path.

---

## Data model and assumptions

Current GEMM-oriented assumptions:

- A / B elements are signed 8-bit
- C / accumulator elements are signed 32-bit
- matrix data is stored in compact row-major layout
- result region C is read back as signed 32-bit words

Default base map used by the common baseline cases:

- `A = 0x0000_0000`
- `B = 0x0000_0100`
- `C = 0x0000_0200`

The configurable-base smoke cases also exercise shifted but non-overlapping base maps.

---

## Verification architecture

### 1. Control path

The subsystem control path is exercised through a UVM control agent and monitor.

The monitor now publishes **phase-aware control events on the same control analysis path**:

- `START`
- `DONE`

This lets the environment track job boundaries without introducing a second parallel control stream.

### 2. Result checking

A dedicated result bridge publishes post-run result items into the scoreboard.

The scoreboard checks:

- control profile consistency
- latency sanity
- ctrl/result pairing
- result compare correctness

For the current passing UVM runs, the scoreboard summaries show clean matching counts and zero errors. :contentReference[oaicite:5]{index=5} :contentReference[oaicite:6]{index=6} :contentReference[oaicite:7]{index=7}

### 3. Host memory path

Host-side memory operations are driven through a UVM AXI-MM host agent.

That path is used for:

- clearing C before a run
- preloading A and B
- reading back C after completion

This replaced the earlier direct helper-style memory path as the main verification path for current UVM result-check runs.

### 4. Host traffic checker

The environment also includes a host traffic checker.

Its current role is to verify that the observed host traffic matches the intended memory flow for each job:

- A preload writes
- B preload writes
- C clear writes
- C readback reads

It also uses the same phase-aware control stream to enforce simple phase rules:

- pre-start traffic must contain only preload / clear behavior
- compute phase should not see host traffic
- post-done traffic should contain only C readback

The recent smoke, back-to-back, and reset-recovery UVM runs all pass with this checker enabled in strict mode. :contentReference[oaicite:8]{index=8} :contentReference[oaicite:9]{index=9} :contentReference[oaicite:10]{index=10}

---

## Implemented test coverage

## 1. Smoke test

Main UVM test:
- `ai_accel_subsys_smoke_test`

This test currently covers three useful groups of cases.

### Fixed 4x4 directed baseline
Implemented fixed cases:

- `CASE_ID=0` : identity × known
- `CASE_ID=1` : all-ones × known
- `CASE_ID=2` : signed mixed
- `CASE_ID=3` : zero A × known
- `CASE_ID=4` : known × identity
- `CASE_ID=5` : diagonal × diagonal
- `CASE_ID=6` : sparse / checkerboard-like
- `CASE_ID=7` : larger signed magnitude (safe range)

These remain the main fixed-dimension correctness baseline. The older README already documented these fixed baseline cases, and that part is still valid. :contentReference[oaicite:11]{index=11}

### Variable-dimension smoke
Implemented variable-dimension cases:

- `CASE_ID=100` : `1x1x1`
- `CASE_ID=101` : `2x2x2`
- `CASE_ID=102` : `4x4x1`
- `CASE_ID=103` : `1x4x4`
- `CASE_ID=104` : `4x1x4`
- `CASE_ID=105` : `2x3x4`

These verify that `dim_m`, `dim_n`, and `dim_k` are functionally active, not just fixed placeholders. The legacy variable-dimension payload/reference extraction still reflects this compact row-major model. :contentReference[oaicite:12]{index=12} :contentReference[oaicite:13]{index=13}

### Configurable base-address smoke
Implemented configurable-base cases:

- `CASE_ID=400` : baseline base map
- `CASE_ID=401` : shifted base map #1
- `CASE_ID=402` : shifted base map #2
- `CASE_ID=403` : tighter non-overlapping base map

These cases exercise the same functional path while moving the A/B/C regions to different legal locations. The earlier extracted configurable-base flow documents these four base-map variants. :contentReference[oaicite:14]{index=14}

---

## 2. Back-to-back test

Main UVM test:
- `ai_accel_subsys_back_to_back_test`

Purpose:

- run multiple GEMM jobs in one simulation
- verify reusable control behavior across consecutive launches
- verify result compare and host traffic checking remain aligned across multiple jobs

A recent passing run used:

- `JOB_COUNT=2`
- `JOB0_CASE_ID=100`
- `JOB1_CASE_ID=101`

That run completed with:

- scoreboard control summary `start=2 completed=2`
- scoreboard pairing `matched=2`
- host traffic checker summary `start_events=2 done_events=2 jobs_created=2 pass=2 fail=0` :contentReference[oaicite:15]{index=15} :contentReference[oaicite:16]{index=16}

---

## 3. Reset recovery test

Main UVM test:
- `ai_accel_subsys_reset_recovery_test`

Purpose:

- run a valid job
- apply a controlled recovery reset
- verify the subsystem returns to a clean state
- run another valid job after reset

A recent passing run used:

- `PRE_RESET_CASE_ID=5`
- `POST_RESET_CASE_ID=101`

That run completed with:

- successful recovery reset
- scoreboard control summary `start=2 completed=2`
- scoreboard pairing `matched=2`
- host traffic checker summary `start_events=2 done_events=2 jobs_created=2 pass=2 fail=0` :contentReference[oaicite:17]{index=17}

---

## Legacy baseline vs current flow

The older repository milestone writeups were useful for establishing the original non-UVM subsystem baseline:

- fixed 4x4 directed baseline
- variable-dimension smoke
- back-to-back smoke
- reset-recovery smoke

That history is still useful, but it is no longer the best description of the **current** verification flow. The older README still describes non-UVM top-level tests and presents minimal UVM as a future step. That is now outdated. :contentReference[oaicite:18]{index=18} :contentReference[oaicite:19]{index=19}

Today, the main working path is:

- UVM control agent
- UVM host agent
- scoreboard with ctrl/result pairing
- host traffic checker using the same control path

---

## Notes on the reference model

The current environment still benefits from helper/reference extraction from the earlier non-UVM subsystem tests.

In particular, the compact row-major GEMM reference model and several directed payload builders were extracted forward into the UVM flow rather than being rewritten from scratch. The legacy helper snippets for fixed and variable cases still reflect the same reference computation style used by the current subsystem tests. :contentReference[oaicite:20]{index=20} :contentReference[oaicite:21]{index=21}

---

## What the current baseline proves

At the current checkpoint, the subsystem has demonstrated:

- end-to-end GEMM preload / compute / writeback / readback flow
- correct fixed-dimension directed behavior
- correct variable-dimension smoke behavior
- correct configurable-base smoke behavior
- repeated-run robustness in one simulation
- reset recovery between completed runs
- phase-aware control observation on the existing ctrl path
- host memory traffic consistency checks on the main UVM memory path

This is no longer just a bring-up environment. It is now a usable UVM subsystem verification baseline.

---

## Current top-level verification view

A simple way to think about the current verification stack is:

1. `ai_accel_subsys_smoke_test`  
   single-job correctness and case coverage

2. `ai_accel_subsys_back_to_back_test`  
   repeated-run robustness

3. `ai_accel_subsys_reset_recovery_test`  
   post-reset recovery robustness

Together, these form the current subsystem regression baseline.

---

## What is next

Near-term work can go in a few directions:

- cleanup and documentation alignment
- helper fallback sanity runs
- tighter host traffic rules if needed
- additional directed corner coverage
- broader regression organization

The main structural step that is already complete is the move from the earlier non-UVM milestone description to a working UVM subsystem environment.

---

## Summary

This repository currently contains a working GEMM-oriented AI accelerator subsystem baseline with:

- stable scratchpad-backed subsystem integration
- UVM-based subsystem verification
- multiple reusable smoke / robustness tests
- scoreboard-based result checking
- phase-aware host traffic checking

That is the current baseline to build on.