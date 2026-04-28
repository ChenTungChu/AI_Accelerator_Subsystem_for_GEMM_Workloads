# AI Accelerator Subsystem for GEMM Workloads

## Overview

This repository is a subsystem-level RTL and verification project for a GEMM-oriented accelerator path.

The current subsystem focuses on a practical end-to-end flow:

- preload matrices A and B into scratchpad memory
- launch the GEMM core through the local scratchpad adapter
- write results into scratchpad memory
- read C back and compare against a software reference model

The main RTL stack in this stage is:

- `ai_accel_subsystem`
- `gemm_top`
- `gemm_scratchpad_adapter`
- `axi_mm_dual_port_bram`

The BRAM model is treated as an established subsystem baseline. The current work is focused on subsystem verification and execution flow robustness on top of that memory model.

---

## Current status

The project is now running on a UVM-based subsystem environment rather than the earlier non-UVM top-level bring-up flow.

The current environment includes:

- phase-aware control monitoring
- scoreboard-based result compare
- ctrl/result pairing
- a dedicated AXI-MM host agent for the main memory path
- a host traffic checker for the primary host-agent path
- helper fallback coverage for sanity checking

At the current checkpoint, the main regression baseline is green for:

- primary-path smoke tests
- primary-path back-to-back tests
- primary-path reset recovery tests
- primary-path corner recipe
- primary-path mid-run reset / abort recovery test
- helper fallback sanity runs

This is the current subsystem verification baseline.

---

## Data model and assumptions

Current GEMM-oriented assumptions:

- A and B elements are signed 8-bit
- C / accumulator elements are signed 32-bit
- matrix data is stored in compact row-major layout
- result region C is read back as signed 32-bit words

Default common base map:

- `A = 0x0000_0000`
- `B = 0x0000_0100`
- `C = 0x0000_0200`

Some smoke cases also move these regions to shifted but non-overlapping legal base maps.

---

## Verification architecture

### 1. Control path

The subsystem control path is observed through a UVM control agent and monitor.

The control monitor publishes phase-aware events on a single control analysis path:

- `START`
- `DONE`

This keeps job boundary tracking simple and lets the scoreboard and checker reason about execution phase without introducing a separate parallel control stream.

### 2. Scoreboard and result path

A dedicated result bridge publishes result items into the scoreboard after post-run readback.

The scoreboard checks:

- control profile consistency
- latency sanity
- ctrl/result pairing
- result compare correctness

The scoreboard also supports the expected-abort case used by the mid-run reset test, where a started job is intentionally interrupted before completion.

### 3. Host memory path

The main UVM path uses a dedicated AXI-MM host agent for memory-side activity such as:

- clearing C before a run
- preloading A and B
- reading C after completion

This is the primary path for normal strict subsystem verification.

### 4. Host traffic checker

The environment also includes a host traffic checker.

On the primary host-agent path, it runs in strict mode and checks that observed host activity matches the intended per-job flow:

- A preload writes
- B preload writes
- C clear writes
- C readback reads

It also uses the same phase-aware control stream to enforce simple phase rules:

- pre-start phase: preload / clear only
- compute phase: no host traffic
- post-done phase: C readback only

For helper fallback sanity runs, the checker remains present but operates in passive non-strict mode. In that mode, the goal is not strict host-path enforcement, but confirming that helper fallback still preserves scoreboard pairing and result correctness.

### 5. Reset-aware monitoring

The control monitor now drops pending active control state when reset is asserted mid-run.

This matters for abort-style testing because it prevents a reset-interrupted job from being incorrectly paired with the next completed job after reset.

---

## Implemented test coverage

## 1. Smoke test

Main UVM test:

- `ai_accel_subsys_smoke_test`

This test currently covers three groups of cases.

### Fixed 4x4 directed baseline

Implemented fixed cases:

- `CASE_ID=0` : identity × known
- `CASE_ID=1` : all-ones × known
- `CASE_ID=2` : signed mixed
- `CASE_ID=3` : zero A × known
- `CASE_ID=4` : known × identity
- `CASE_ID=5` : diagonal × diagonal
- `CASE_ID=6` : sparse / checkerboard-like
- `CASE_ID=7` : larger signed magnitude within safe range

These remain the main fixed-dimension correctness baseline.

### Variable-dimension smoke

Implemented variable-dimension cases:

- `CASE_ID=100` : `1x1x1`
- `CASE_ID=101` : `2x2x2`
- `CASE_ID=102` : `4x4x1`
- `CASE_ID=103` : `1x4x4`
- `CASE_ID=104` : `4x1x4`
- `CASE_ID=105` : `2x3x4`

These verify that `dim_m`, `dim_n`, and `dim_k` are functionally active rather than fixed placeholders.

### Configurable base-address smoke

Implemented configurable-base cases:

- `CASE_ID=400` : baseline base map
- `CASE_ID=401` : shifted base map #1
- `CASE_ID=402` : shifted base map #2
- `CASE_ID=403` : tighter non-overlapping base map

These cases exercise the same functional flow while moving A/B/C to different valid locations.

---

## 2. Back-to-back test

Main UVM test:

- `ai_accel_subsys_back_to_back_test`

Purpose:

- run multiple GEMM jobs in one simulation
- verify repeated launch behavior
- verify result pairing remains aligned across consecutive jobs
- verify host traffic checking remains aligned across multiple jobs on the primary path

Current regression examples include:

- `100 -> 101`
- `5 -> 0`
- `5 -> 101 -> 400`

---

## 3. Reset recovery test

Main UVM test:

- `ai_accel_subsys_reset_recovery_test`

Purpose:

- run one valid job
- apply a controlled recovery reset
- verify the subsystem returns to a clean state
- run another valid job after reset

Current regression examples include:

- `5 -> 101`
- `5 -> 400`

This test is focused on reset between completed jobs.

---

## 4. Corner test

Main UVM test:

- `ai_accel_subsys_corner_test`

Purpose:

- mix multiple case styles in one run
- exercise repeated job sequencing across different payload shapes and base-map styles
- keep the regression list compact while still covering a more realistic mixed recipe

Current default recipe:

- `5`
- `101`
- `105`
- `403`

This gives one fixed case, two variable-dimension cases, and one configurable-base case in a single run.

---

## 5. Mid-run reset / abort recovery test

Main UVM test:

- `ai_accel_subsys_midrun_reset_test`

Purpose:

- start a real job
- wait until compute is active
- assert reset before the job completes
- confirm the interrupted job is treated as an expected abort
- launch a clean recovery job after reset
- confirm the recovery job still completes and compares cleanly

Current default recipe:

- abort job: `CASE_ID=5`
- recovery job: `CASE_ID=101`

This test is the main check for reset during active compute, not just reset between completed jobs.

---

## 6. Helper fallback sanity

The main execution path now prefers the host-agent memory path.

That said, a small fallback sanity block is still kept in regression to confirm that helper-based memory access remains usable and does not break:

- scoreboard control summary
- ctrl/result pairing
- result compare correctness

Current fallback sanity runs include:

- smoke fallback: `CASE_ID=101`
- back-to-back fallback: `100 -> 101`
- reset recovery fallback: `5 -> 101`

This block is intentionally kept small.

---

## Current regression baseline

A simple view of the current regression baseline is:

1. `ai_accel_subsys_smoke_test`  
   single-job correctness and case coverage

2. `ai_accel_subsys_back_to_back_test`  
   repeated-run robustness

3. `ai_accel_subsys_reset_recovery_test`  
   recovery reset between completed jobs

4. `ai_accel_subsys_corner_test`  
   mixed-case sequencing coverage

5. `ai_accel_subsys_midrun_reset_test`  
   expected-abort behavior and post-reset recovery

6. helper fallback sanity  
   small non-primary-path confidence check

Together, these form the current subsystem regression baseline.

---

## What the current baseline proves

At this checkpoint, the subsystem has demonstrated:

- end-to-end preload / compute / writeback / readback flow
- correct fixed-dimension directed behavior
- correct variable-dimension smoke behavior
- correct configurable-base smoke behavior
- repeated-run robustness in one simulation
- reset recovery between completed runs
- reset interruption handling during active compute
- expected-abort semantics in scoreboard / checker flow
- phase-aware control observation on a single ctrl path
- host memory traffic consistency checks on the main UVM path
- helper fallback still working as a small sanity path

This is no longer just bring-up code. It is now a usable UVM subsystem verification baseline.

---

## Notes on the reference model

The current UVM environment still reuses the same core reference ideas established in the earlier subsystem bring-up stage:

- compact row-major payload layout
- software-side GEMM reference calculation
- directed payload generation for fixed and variable cases

The newer UVM environment builds on those helpers rather than replacing the whole reference flow from scratch.

---

## What is next

Near-term work can go in a few directions:

- README / repo cleanup
- regression script cleanup
- additional corner recipes
- optional fallback expansion if it becomes useful
- more targeted stress cases around reset and sequencing
- broader coverage organization if the environment grows further

The current baseline is stable enough to branch from.

---

## Summary

This repository currently contains a working GEMM-oriented AI accelerator subsystem baseline with:

- stable scratchpad-backed subsystem integration
- UVM-based subsystem verification
- reusable smoke / robustness / reset tests
- scoreboard-based result checking
- phase-aware control monitoring
- host-agent-based main memory path verification
- helper fallback sanity coverage

That is the current baseline to build on.
