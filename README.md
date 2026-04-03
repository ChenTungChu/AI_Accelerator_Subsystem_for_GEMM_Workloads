AI Accelerator Subsystem for GEMM Workloads

# AI Accelerator Subsystem v1 Baseline
## 4x4 Fixed-Dimension Directed Baseline

## Overview

This baseline captures the first stable subsystem-level verification milestone for the AI Accelerator Subsystem targeting GEMM workloads.

At this point, the subsystem dataflow has been validated end-to-end for a fixed 4x4 configuration:

- Host preload of matrix A and B into scratchpad
- GEMM core reads A/B through the local-memory path
- GEMM compute and accumulation
- Result matrix C writeback into scratchpad
- Host readback and compare against reference model

This baseline is intended to serve as the first regression checkpoint before moving on to variable-dimension validation.

---
## Current subsystem structure

The validated subsystem path is:

- `ai_accel_subsystem`
- `gemm_top`
- `gemm_scratchpad_adapter`
- `axi_mm_dual_port_bram`

The scratchpad BRAM remains the previously verified baseline model and is not modified as part of this milestone.

---

## Fixed configuration

Current directed baseline assumptions:

- Matrix dimensions fixed to 4x4x4
- Base addresses:
  - `A = 0x0000`
  - `B = 0x0100`
  - `C = 0x0200`
- A/B element width: signed 8-bit
- Accumulator / C element width: signed 32-bit

---

## Directed baseline test

Current baseline testbench structure:

- Top:
  - `tb/top/ai_accel_subsystem_tb_top.sv`
- Baseline include:
  - `tb/top/4x4_fixed_dimension_baseline_test.sv`

The baseline test is selected by `+CASE=<id>`.

### Implemented directed cases

- `CASE=0` : identity × known
- `CASE=1` : all-ones × known
- `CASE=2` : signed mixed
- `CASE=3` : zero A × known
- `CASE=4` : known × identity
- `CASE=5` : diagonal × diagonal
- `CASE=6` : sparse / checkerboard-like
- `CASE=7` : larger signed magnitude (safe range)

---

## Verification status

All 8 fixed-dimension directed baseline cases pass.

This gives confidence in the following areas:

- Scratchpad preload/readback flow
- A/B address generation
- C writeback address generation
- GEMM accumulation flow
- Signed multiply-accumulate behavior
- Zero / identity / diagonal / sparse / larger signed-value patterns

---

## Notes on observability interfaces

The BRAM model exposes apply/commit observation interfaces with handshake behavior.
For this non-UVM baseline testbench, the corresponding `ready` signals are forced high in the top-level testbench so the BRAM commit engine can drain normally.

This is a testbench-side integration choice only and does not modify the BRAM RTL.

---

## Why this baseline matters

This milestone confirms that the subsystem is no longer only structurally connected, but functionally operational for fixed 4x4 GEMM execution.

It serves as the stable checkpoint before the next verification step:

- variable-dimension smoke testing

---

## Next step

Planned next milestone:

- `variable_dimension_smoke_test.sv`

Initial target cases include:

- 1x1x1
- 2x2x2
- 4x4x1
- 1x4x4
- 4x1x4

The goal is to verify that `dim_m`, `dim_n`, and `dim_k` are truly functional and not only fixed-value placeholders.


# AI Accelerator Subsystem v1
## Variable-Dimension Smoke Test Milestone

## Overview

This milestone extends the subsystem verification beyond the original 4x4 fixed-dimension directed baseline.

The main goal of this test stage is to verify that:

- `dim_m`
- `dim_n`
- `dim_k`

are functionally active and correctly affect:

- GEMM loop bounds
- A/B address generation
- C writeback region

This confirms that the current subsystem is not limited to only a fixed 4x4 execution pattern.

---

## Test structure

Current testbench organization:

- Top:
  - `tb/top/ai_accel_subsystem_tb_top.sv`
- Fixed baseline test:
  - `tb/top/4x4_fixed_dimension_baseline_test.sv`
- Variable-dimension smoke test:
  - `tb/test/variable_dimension_smoke_test.sv`

The top-level testbench selects between fixed-baseline cases and variable-dimension smoke cases using `+CASE=<id>`.

---

## Variable-dimension smoke cases

Implemented smoke cases:

- `CASE=100` : `1x1x1`
- `CASE=101` : `2x2x2`
- `CASE=102` : `4x4x1`
- `CASE=103` : `1x4x4`
- `CASE=104` : `4x1x4`
- `CASE=105` : `2x3x4`

These cases were chosen to cover:

- minimum dimension behavior
- small square matrix behavior
- `K=1` edge behavior
- single-row output
- single-column output
- non-square output shape

---

## Verification intent

This milestone verifies the following areas:

- `dim_m`, `dim_n`, `dim_k` are functionally effective
- loop termination depends on runtime dimensions
- address generation follows compact row-major indexing with variable dimensions
- only the valid output region is compared
- subsystem control path (`start`, `busy`, `done`) remains correct under variable dimensions

---

## Important testbench policy

For the variable-dimension smoke test:

- matrix storage is preloaded in compact row-major layout
- only valid matrix regions are preloaded
- only valid output regions are compared
- result region `C` is cleared before each run

This is a testbench-side validation policy and does not modify the BRAM RTL baseline.

---

## Current status

All variable-dimension smoke cases pass:

- `CASE=100`
- `CASE=101`
- `CASE=102`
- `CASE=103`
- `CASE=104`
- `CASE=105`

This means the subsystem has now been validated at two levels:

1. fixed 4x4 directed baseline
2. variable-dimension smoke baseline

---

## What this milestone proves

At this point, the subsystem has demonstrated:

- end-to-end matrix preload / compute / writeback / readback flow
- correct behavior under fixed and variable dimensions
- correct signed multiply-accumulate behavior
- correct output region generation for multiple output shapes

This milestone serves as the verification checkpoint before moving to repeated-run robustness testing.

---

## Next milestone

Planned next step:

- `back_to_back_run_smoke_test.sv`

Primary goal:

- run multiple GEMM jobs in the same simulation
- verify repeated use of `start / busy / done`
- verify no stale state remains across consecutive runs
- verify result clearing and re-use of the subsystem path

# AI Accelerator Subsystem v1
## Back-to-Back Run Smoke Milestone

## Overview

This milestone extends subsystem verification beyond single-run correctness.

At this stage, the subsystem has already passed:

- fixed 4x4 directed baseline tests
- variable-dimension smoke tests

The purpose of this milestone is to verify that the subsystem can be reused multiple times within the same simulation without requiring re-elaboration.

This checks repeated use of:

- `acc_start`
- `acc_busy`
- `acc_done`

and verifies that no stale state remains across consecutive runs.

---

## Test structure

Current testbench organization includes:

- Top:
  - `tb/top/ai_accel_subsystem_tb_top.sv`
- Fixed baseline test:
  - `tb/top/4x4_fixed_dimension_baseline_test.sv`
- Variable-dimension smoke test:
  - `tb/test/variable_dimension_smoke_test.sv`
- Back-to-back run smoke test:
  - `tb/test/back_to_back_run_smoke_test.sv`

The top-level testbench selects tests by `+CASE=<id>`.

---

## Back-to-back run smoke intent

This milestone verifies that:

- multiple GEMM jobs can run in one simulation
- state machines return to a reusable idle condition
- `start / busy / done` behavior remains valid across repeated runs
- scratchpad result clearing prevents stale result contamination
- both fixed-dimension and variable-dimension jobs can run sequentially

---

## Current back-to-back sequence

Current smoke sequence:

- `RUN 0` : fixed baseline `CASE=0`
- `RUN 1` : fixed baseline `CASE=2`
- `RUN 2` : variable-dimension `CASE=101`

This sequence was chosen to cover:

- a simple fixed baseline case
- a signed arithmetic fixed baseline case
- a variable-dimension case

within the same simulation.

---

## Current status

The back-to-back run smoke test passes.

This means the subsystem has demonstrated:

- repeated GEMM job execution in one simulation
- no stale GEMM core state across runs
- no stale adapter transaction state across runs
- correct result generation after multiple consecutive launches

---

## Verification significance

This milestone moves the subsystem beyond "single-run functional correctness".

It provides confidence that the subsystem is reusable across multiple jobs and that the current control/dataflow implementation is stable under consecutive operation.

This is an important checkpoint before reset robustness testing.

---

## Relationship to earlier milestones

At this point, the verification baseline consists of three layers:

1. fixed 4x4 directed baseline
2. variable-dimension smoke baseline
3. back-to-back run smoke baseline

Together, these establish the first practical subsystem-level verification baseline for v1.

---

## Next milestone

Planned next step:

- `reset_recovery_smoke_test.sv`

Primary goal:

- verify reset between runs
- verify reset recovery after completed runs
- verify subsystem can re-enter a clean operational state after reset
# AI Accelerator Subsystem v1 Milestone

## Overview

This milestone marks the completion of the first functional verification baseline for the AI Accelerator Subsystem targeting GEMM workloads.

At this stage, the subsystem has been validated end-to-end through:

- fixed-dimension directed baseline testing
- variable-dimension smoke testing
- back-to-back run smoke testing
- reset recovery smoke testing

The goal of v1 was to establish a stable, working subsystem dataflow before moving into broader configurability and UVM-based subsystem verification.

---

## v1 scope

The v1 implementation focuses on a GEMM-centered subsystem path:

- host-side preload of matrix data into scratchpad memory
- GEMM core access through a local-memory-to-AXI adapter
- scratchpad writeback of result matrix C
- host-side readback and comparison against a reference model

The verified subsystem stack includes:

- `ai_accel_subsystem`
- `gemm_top`
- `gemm_scratchpad_adapter`
- `axi_mm_dual_port_bram`

The BRAM model remains the previously verified baseline and is not modified as part of this milestone.

---

## Current verification structure

Current non-UVM verification structure:

- top-level testbench:
  - `tb/top/ai_accel_subsystem_tb_top.sv`
- fixed-dimension directed baseline:
  - `tb/top/4x4_fixed_dimension_baseline_test.sv`
- variable-dimension smoke test:
  - `tb/test/variable_dimension_smoke_test.sv`
- back-to-back run smoke test:
  - `tb/test/back_to_back_run_smoke_test.sv`
- reset recovery smoke test:
  - `tb/test/reset_recovery_smoke_test.sv`

The testbench currently uses `+CASE=<id>` style selection in the top-level flow. The fixed baseline, variable-dimension cases, repeated-run flow, and reset-recovery flow are all orchestrated from the same subsystem testbench top. :contentReference[oaicite:0]{index=0} :contentReference[oaicite:1]{index=1}

---

## Fixed-dimension directed baseline

The fixed-dimension baseline validates a 4x4x4 GEMM configuration with signed 8-bit A/B elements and signed 32-bit accumulation/result behavior.

Implemented directed cases:

- `CASE=0` : identity × known
- `CASE=1` : all-ones × known
- `CASE=2` : signed mixed
- `CASE=3` : zero A × known
- `CASE=4` : known × identity
- `CASE=5` : diagonal × diagonal
- `CASE=6` : sparse / checkerboard-like
- `CASE=7` : larger signed magnitude (safe range)

These cases establish the first correctness baseline for:

- preload / compute / writeback / readback flow
- signed MAC behavior
- structured matrix patterns
- sparse patterns
- result stability across a range of fixed 4x4 patterns

The fixed baseline testbench organization and case structure are reflected in the current top-level testbench flow. :contentReference[oaicite:2]{index=2}

---

## Variable-dimension smoke baseline

The variable-dimension smoke test verifies that:

- `dim_m`
- `dim_n`
- `dim_k`

are functionally active and affect:

- GEMM loop bounds
- compact row-major address generation
- valid output region sizing

Implemented variable-dimension smoke cases:

- `CASE=100` : `1x1x1`
- `CASE=101` : `2x2x2`
- `CASE=102` : `4x4x1`
- `CASE=103` : `1x4x4`
- `CASE=104` : `4x1x4`
- `CASE=105` : `2x3x4`

These cases confirm that the subsystem is not limited to only a fixed 4x4 execution pattern. The current variable-dimension test structure, case IDs, and compact indexing model are captured in the dedicated smoke test file. :contentReference[oaicite:3]{index=3}

---

## Repeated-run robustness

Two repeated-use robustness layers have been validated.

### Back-to-back run smoke

Multiple GEMM jobs are executed within the same simulation without re-elaboration.

Current back-to-back sequence:

- fixed baseline `CASE=0`
- fixed baseline `CASE=2`
- variable-dimension `CASE=101`

This confirms:

- repeated use of `acc_start`
- repeated observation of `acc_done`
- no stale core/adapter state blocking subsequent runs
- correct result clearing and re-use of the subsystem path

### Reset recovery smoke

The subsystem is reset between completed runs and then exercised again.

Current reset recovery sequence:

- run fixed baseline `CASE=0`
- apply reset
- run fixed baseline `CASE=2`
- apply reset
- run variable-dimension `CASE=101`

This confirms that the subsystem can recover from reset and return to a clean operational state for subsequent jobs.

---

## BRAM observation interface policy

The BRAM model exposes apply/commit observation interfaces with handshake behavior.  
For the current non-UVM subsystem testbench, the corresponding `ready` signals are forced high at the testbench top so the BRAM commit engine can drain normally.

This is strictly a testbench-side integration policy and does not modify the BRAM RTL baseline. The top-level testbench currently applies these ready-forcing connections. :contentReference[oaicite:4]{index=4}

---

## What v1 proves

At the end of v1, the subsystem has demonstrated:

- end-to-end GEMM subsystem dataflow
- correct fixed-dimension directed behavior
- correct variable-dimension smoke behavior
- repeated-run robustness in one simulation
- reset recovery across multiple runs

This means v1 is no longer just a structural or bring-up stage. It is now a stable functional baseline.

---

## v1 completion statement

v1 is considered complete with the following verification baseline established:

1. fixed 4x4 directed baseline
2. variable-dimension smoke baseline
3. back-to-back run smoke baseline
4. reset recovery smoke baseline

This milestone serves as the checkpoint before entering v2.

---

## Transition to v2

With v1 complete, the next phase is v2.

### Planned v2 directions

- parameterized `M / N / K`
- truly configurable base addresses
- more directed and limited random testing
- subsystem-level scoreboard
- start of minimal UVM subsystem environment

The intent is to preserve the current non-UVM baseline as a fast sanity layer, while beginning the first structured UVM verification infrastructure in parallel.

---

## Reference note

The original v1 direction was to first stabilize the subsystem dataflow before expanding toward greater configurability and later subsystem-level/UVM-oriented verification. That staged intent remains consistent with the current milestone closure and v2 transition. :contentReference[oaicite:5]{index=5}