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