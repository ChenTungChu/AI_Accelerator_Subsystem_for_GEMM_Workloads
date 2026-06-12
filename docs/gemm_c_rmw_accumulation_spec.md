# GEMM C Read-Modify-Write / Partial Accumulation Spec

## 0. Purpose

This document defines the P13 milestone for extending the completed P12 M/N/K tiled GEMM baseline into C read-modify-write partial accumulation.

P10 proved that the cache-backed 4-lane GEMM datapath can process `K_total` larger than the local cache K capacity by splitting K into multiple K tiles and accumulating partial sums inside one GEMM job.

P11 proved that the same datapath can process `N_total` larger than the local B-cache / row-accumulator N capacity by splitting output columns into local N tiles.

P12 proved that the same tiled datapath can process `M_total` as local multi-row M tiles, preserving compatibility with host-primary, DMA load-store, AXI-Stream load-store, and Direct Stream load-store paths.

P13 extends that model from:

```text
one GEMM job computes the complete logical C result
C[m][n] is written once with the final full dot-product result
```

to:

```text
multiple GEMM jobs may contribute partial sums to the same C region
C[m][n] may be read from scratchpad, incremented, and written back
```

The implemented P13 path is intentionally limited to local scratchpad C read-modify-write accumulation inside `gemm_top`:

```text
partial_sum = sum over the current job's K-partition

if accumulate_enable == 0:
  C_new = partial_sum

if accumulate_enable == 1:
  C_old = read C from scratchpad
  C_new = C_old + partial_sum
```


Current P13 closure status:

```text
P13A: spec                                    DONE
P13B: safe parameter / control-bit plumbing   DONE
P13C: recipe / reference model support        DONE
P13D: RTL C RMW datapath                      DONE
P13E: host-primary focused validation         DONE
P13F: frontend compatibility sanity           DONE
P13G: full regression integration             DONE
P13H: documentation / closure update          DONE

Full regression after P13G:
  TOTAL : 82
  PASS  : 82
  FAIL  : 0
```

The primary target is to support software/external scheduling patterns such as:

```text
Full logical GEMM: M=8, N=16, K=16

Job 0: K partition 0, dim_k=8,  accumulate_enable=0
Job 1: K partition 1, dim_k=8,  accumulate_enable=1

Final C = partial_sum(K0) + partial_sum(K1)
```

P13 must preserve existing subsystem paths:

```text
Host primary
DMA load-store
AXI-Stream load-store
Direct Stream load-store
```

and must preserve scoreboard-based result correctness.

---

## 1. Baseline Before P13

Closed P12 baseline:

```text
Performance GEMM P12: M-Dimension Tiling Completed

Full regression:
  TOTAL : 74
  PASS  : 74
  FAIL  : 0
```

P12 validated:

```text
P12A: M-tiling / multi-row tile scheduling spec          PASS
P12B: safe M-tiling parameter plumbing                   PASS
P12C: M>current-row testcase / software reference support PASS
P12D: actual M-tile execution microarchitecture          PASS
P12E: host-primary focused validation                    PASS
P12F: frontend compatibility sanity                      PASS
P12G: regression integration                             PASS
P12H: documentation / closure update                     PASS
```

Representative P12 M-tiling cases:

```text
CASE_ID=203 : M=8, N=8,  K=8
CASE_ID=204 : M=8, N=16, K=8
CASE_ID=205 : M=8, N=16, K=16
CASE_ID=206 : M=5, N=9,  K=9
CASE_ID=207 : M=7, N=12, K=16
```

P12 solved the internal M/N/K tiling problem for one complete GEMM job, but intentionally preserved the first-step policy:

```text
C is not read before final writeback.
Each GEMM job writes final C outputs directly.
C accumulation across multiple external jobs is not part of P12.
```

P13 starts the next natural step: scratchpad C read-modify-write accumulation for multi-job partial GEMM execution.

---

## 2. P13 High-Level Goal

P13 adds optional C accumulation support to `gemm_top`.

Primary target configuration:

```text
GEMM_MAC_LANES=4
GEMM_ENABLE_B_CACHE=1
GEMM_B_CACHE_MAX_K=8
GEMM_B_CACHE_MAX_N=8
GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1
GEMM_ENABLE_A_ROW_CACHE=1
GEMM_A_ROW_CACHE_MAX_K=8
GEMM_ENABLE_PACKED_A_ROW_PRELOAD=1
GEMM_ENABLE_K_TILING=1
GEMM_K_TILE_SIZE=8
GEMM_ENABLE_N_TILING=1
GEMM_N_TILE_SIZE=8
GEMM_ENABLE_M_TILING=1
GEMM_M_TILE_SIZE=2
GEMM_ENABLE_C_RMW_ACCUM=1
```

The first P13 implementation should support:

```text
C accumulation across multiple GEMM jobs
same base_c across partial jobs
same M and N across partial jobs
possibly different dim_k per partial job
compact per-job A/B payloads
host-primary path
DMA load-store path
AXI-Stream load-store path
Direct Stream load-store path
```

The design must compute the same mathematical result as a full untiled GEMM:

```text
C_final[m][n] = sum over k=0..K_total-1 of A_full[m][k] * B_full[k][n]
```

but allow the software/test sequence to split the K dimension across multiple jobs:

```text
C_partial_job_j[m][n] = sum over local_k in K_partition_j
                        A_partition_j[m][local_k]
                      * B_partition_j[local_k][n]

C_final[m][n] = sum over all partial jobs of C_partial_job_j[m][n]
```

---

## 3. Non-Goals for First P13 Step

P13A/P13B/P13C should not attempt to implement a full external tiled GEMM scheduler.

The first P13 implementation does not include:

```text
- external tile descriptor queue
- autonomous multi-job tile scheduler inside RTL
- automatic K partition generation
- scratchpad A/B gather from non-contiguous full matrices
- C accumulation across different M/N output tiles with changing base_c
- C accumulation across different base_c regions in one job
- C direct-store path
- systolic array scheduling
- multi-bank scratchpad
- widened local memory interface
- additional AXI ports
- new DMA protocol
- new AXI-Stream packet format
- new Direct Stream packet format
- simultaneous compute and C readback overlap
- saturation arithmetic
- floating-point accumulation
```

P13 focuses only on a controlled per-job C accumulation mode.

The testbench or software sequence is responsible for:

```text
- splitting the logical full-K problem into partial jobs
- preparing compact A/B payloads for each partial job
- selecting accumulate_enable=0 for the first partial job
- selecting accumulate_enable=1 for later partial jobs
- using the same base_c for all partial jobs in one accumulation recipe
```

---

## 4. Key Architectural Choice

There are two practical ways to support partial accumulation across jobs.

### 4.1 Option A: External Host/DMA Accumulation

Let GEMM write partial C results to temporary buffers, then let host or DMA/software accumulate the partial C buffers.

This keeps GEMM simple, but it does not validate accelerator-side accumulation and requires extra memory traffic:

```text
partial C write
host/DMA read partial C
host/DMA read old C
host/DMA write accumulated C
```

This is not the preferred P13 direction.

### 4.2 Option B: GEMM-Side Scratchpad C Read-Modify-Write

Let GEMM compute the partial sum for one output element, then optionally read old C from scratchpad, add the partial sum, and write the accumulated result back to the same C address.

Conceptual behavior:

```text
for each output element:
  partial_sum = current job dot product

  if accumulate_enable:
    old_c = scratchpad_read(C_addr)
    new_c = old_c + partial_sum
  else:
    new_c = partial_sum

  scratchpad_write(C_addr, new_c)
```

This is the recommended first P13 architecture.

Benefits:

```text
- keeps the external software/tile scheduler simple
- reuses the existing scratchpad C storage
- reuses the existing GEMM local-memory interface
- does not require temporary partial-C buffers
- enables external K-partitioned GEMM jobs
- naturally extends P10/P11/P12 tiling into multi-job accumulation
- preserves frontend A/B preload protocols
```

Cost:

```text
one C read is added before each accumulated C write when accumulate_enable=1
```

This is acceptable for the first P13 implementation because P13 is correctness-first.

---

## 5. P13 Execution Model

### 5.1 Single Partial Job

For one partial job, the GEMM arithmetic loop remains the same as the selected P12 path. The only change is the final C writeback step.

Without C accumulation:

```text
compute partial_sum for C[m][n]
write C[m][n] = partial_sum
```

With C accumulation:

```text
compute partial_sum for C[m][n]
read old_c = C[m][n]
write C[m][n] = old_c + partial_sum
```

### 5.2 Multi-Job Accumulation Recipe

A two-job K-partitioned recipe uses:

```text
Job 0:
  preload A_part0 and B_part0
  dim_k = K_part0
  accumulate_enable = 0
  GEMM writes C = partial_sum0

Job 1:
  preload A_part1 and B_part1
  dim_k = K_part1
  accumulate_enable = 1
  GEMM writes C = old_C + partial_sum1
```

After Job 1 completes:

```text
C = partial_sum0 + partial_sum1
```

For more than two jobs:

```text
Job 0: accumulate_enable = 0
Job 1: accumulate_enable = 1
Job 2: accumulate_enable = 1
...
```

### 5.3 Compact Partial A/B Payload Policy

The first P13 implementation uses compact per-job A/B payloads.

For a partial job with dimensions:

```text
M = M_total
N = N_total
K = K_part
```

A and B are laid out as compact row-major matrices:

```text
A_part[m][local_k]
B_part[local_k][n]
```

Address formulas inside each partial job remain unchanged:

```text
A[m][local_k] address = base_a + (m * K_part + local_k)
B[local_k][n] address = base_b + (local_k * N_total + n)
```

This avoids adding a new `global_k_base` control field in the first P13 implementation.

### 5.4 Relationship to Internal K Tiling

P13 does not replace the existing P10 internal K-tiling path.

There are two different concepts:

```text
Internal K tiling:
  one GEMM job has K_total > local K tile size
  GEMM internally iterates over K tiles
  C is written once at the end of the job

External partial accumulation:
  multiple GEMM jobs each compute a partial K partition
  later jobs read old C and add their partial sums
```

P13 enables the second concept. The two concepts can coexist, but the first P13 directed tests should use simple two-job recipes first.

---

## 6. Proposed New Parameter and Control

Add a default-off parameter to `gemm_top`:

```systemverilog
parameter bit GEMM_ENABLE_C_RMW_ACCUM = 1'b0
```

Add a runtime job control bit:

```systemverilog
logic accumulate_enable;
```

Recommended policy:

```text
GEMM_ENABLE_C_RMW_ACCUM=0:
  preserve existing P12/P11/P10 behavior
  accumulate_enable should be ignored or treated as unsupported

GEMM_ENABLE_C_RMW_ACCUM=1 and accumulate_enable=0:
  write C = partial_sum

GEMM_ENABLE_C_RMW_ACCUM=1 and accumulate_enable=1:
  read C_old from scratchpad
  write C_new = C_old + partial_sum
```

The control bit must be captured with the GEMM job configuration at accepted start.

The default behavior must remain unchanged:

```text
GEMM_ENABLE_C_RMW_ACCUM=0
accumulate_enable=0
```

P13 must not disturb the closed 74/74 P12 regression when C RMW accumulation is disabled.

---

## 7. C RMW Datapath Requirements

### 7.1 C Address Generation

P13 uses the existing C address formula:

```text
C[m][n] address = base_c + ((m * N_total + n) * 4)
```

For tiled paths:

```text
C tile address = base_c + (((m_tile_base + local_m) * N_total
                            + (n_tile_base + local_n)) * 4)
```

The read and write address must be identical for one output element:

```text
C_read_addr == C_write_addr
```

### 7.2 C Read Data Width

C is a signed 32-bit value.

The C RMW path reads exactly one C word:

```text
old_c[31:0]
```

and writes exactly one C word:

```text
new_c[31:0]
```

The write strobe should cover all bytes of the 32-bit C word.

### 7.3 Arithmetic Policy

First P13 arithmetic policy:

```text
new_c = old_c + partial_sum
```

where both values are interpreted as signed 32-bit values.

Saturation is not part of P13.

The first P13 directed cases should keep expected values well within signed 32-bit range.

### 7.4 Output Completion Policy

For `accumulate_enable=1`, an output is complete only after:

```text
C read response received
new_c calculated
C write request accepted
C write completion observed
```

For `accumulate_enable=0`, the existing P12 final write completion policy applies.

---

## 8. Router / Direct Stream Compatibility Requirement

P13 introduces an important Direct Stream compatibility requirement.

Before P13, Direct Stream mode routes GEMM A/B reads to the operand buffer and C writes to scratchpad. C reads were not needed for the GEMM datapath.

With C RMW accumulation, GEMM must be able to read C from scratchpad even when A/B are served from the Direct Stream operand buffer.

Required Direct Stream mode routing:

```text
GEMM A reads -> operand buffer A
GEMM B reads -> operand buffer B
GEMM C reads -> scratchpad
GEMM C writes -> scratchpad
```

Scratchpad mode remains:

```text
GEMM A reads -> scratchpad
GEMM B reads -> scratchpad
GEMM C reads -> scratchpad
GEMM C writes -> scratchpad
```

Therefore P13 updates the GEMM input memory router policy so that Direct Stream mode routes A/B reads to the operand buffer while routing C RMW old-C reads and C writes to scratchpad.

This does not require a new Direct Stream packet format.

---

## 9. Memory Layout

The default memory map remains:

```text
A base = 0x0000_0000
B base = 0x0000_0100
C base = 0x0000_0200
```

For one partial job:

```text
A bytes = M * K_part
B bytes = K_part * N
C words = M * N
C bytes = M * N * 4
```

A/B may be reloaded between partial jobs.

C must remain at the same `base_c` across all jobs in one accumulation recipe.

Example two-job recipe for full logical K=16:

```text
Job 0: K_part=8, base_c=0x0000_0200, accumulate_enable=0
Job 1: K_part=8, base_c=0x0000_0200, accumulate_enable=1
```

The two jobs may reuse the same A/B base addresses because only one partial A/B payload is needed at a time.

### 9.1 Initial C Contents

For the standard P13 partial-sum recipe:

```text
Job 0 uses accumulate_enable=0
```

Therefore Job 0 overwrites C and does not depend on the initial C contents.

This is useful because the test may preload C with a non-zero pattern before Job 0 to prove that non-accumulate mode replaces old C rather than adding to it.

Future tests may intentionally start with:

```text
Job 0 uses accumulate_enable=1
```

to validate bias-style accumulation into a preinitialized C matrix. That is not required for first P13 closure.

---

## 10. Internal Storage Requirements

P13 should reuse the existing P12 internal partial-sum storage:

```text
row accumulator or M/N tile accumulator
```

No new large C accumulator is required.

For each output element, P13 needs only temporary storage for:

```text
partial_sum
old_c
new_c
```

The first P13 implementation can serialize C RMW per output element.

Recommended first storage model:

```systemverilog
logic signed [31:0] c_partial_sum_q;
logic signed [31:0] c_old_q;
logic signed [31:0] c_new_q;
```

The active P12 `c_tile_accum[local_m][local_n]` entries may still hold partial sums until the writeback phase.

---

## 11. Interaction with P10/P11/P12 Tiling

P13 should compose with the completed internal tiling stack.

### 11.1 P10 K Tiling

Internal K tiling can still be used inside one partial job.

Example:

```text
full logical K = 32
external recipe has two jobs, each K_part=16
inside each job, P10 splits K_part=16 into two K=8 internal tiles
```

This is allowed architecturally, but not required for first P13 validation.

### 11.2 P11 N Tiling

For `N_total > 8`, the existing N tiling scheduler should still split output columns into local N tiles.

C RMW is applied at the final output writeback point for each local-N output.

### 11.3 P12 M Tiling

For `M_total > 2`, the existing M tile scheduler should still split output rows into local M tiles.

C RMW is applied at the final output writeback point for each local M/N output.

### 11.4 Recommended First Composition

The first full P13 representative case should validate:

```text
M tiling active
N tiling active
C RMW accumulation active on the second partial job
```

K can be split externally into two compact K=8 partial jobs to isolate C RMW behavior.

---

## 12. Performance Counter Requirements

Existing counter semantics remain unchanged per GEMM job:

```text
gemm_perf_busy_cycles  : cycles while GEMM is busy
gemm_perf_mac_count    : logical MAC operations committed in the current job
gemm_perf_output_count : final C outputs whose write completion has been observed in the current job
```

For one partial job:

```text
gemm_perf_mac_count    = M * N * K_part
gemm_perf_output_count = M * N
```

Across an external accumulation recipe, the testbench or software may sum per-job counters:

```text
recipe_mac_count = sum over jobs of M * N * K_part
                 = M * N * K_total
```

C RMW read transactions do not increase `gemm_perf_mac_count`.

`gemm_perf_output_count` counts output elements written by the current job, not the number of C reads.

Exact busy-cycle matching is not required for P13 closure.

---

## 13. GEMM Done Semantics

P13 must preserve the P10/P11/P12 done semantics:

```text
gemm_top.done asserts only after the final C write completion has been observed.
```

For C RMW accumulation, this means:

```text
all partial sums for the current job are computed
all required C reads for the current job are complete
all accumulated C writes for the current job are complete
only then assert done
```

`done` must not assert after the final MAC if the final C RMW read or write is still outstanding.

This is required because:

```text
- the next partial job may start immediately after acc_done
- DMA store may start immediately after the final accumulated job
```

---

## 14. Frontend Compatibility Requirements

P13 must not change frontend protocols.

### 14.1 Host Primary Path

```text
for each partial job:
  host preload A_part/B_part
  host sets accumulate_enable
  launch GEMM
  wait acc_done

host readback final C after last job
scoreboard compare
```

### 14.2 DMA Load-Store Path

```text
for each partial job:
  DMA load A_part/B_part into scratchpad
  set accumulate_enable
  GEMM partial compute with optional C RMW

after last job:
  DMA store final C
  scoreboard compare
```

### 14.3 AXI-Stream Load-Store Path

```text
for each partial job:
  AXI-Stream preload A_part/B_part into scratchpad
  set accumulate_enable
  GEMM partial compute with optional C RMW

after last job:
  DMA store final C
  scoreboard compare
```

### 14.4 Direct Stream Load-Store Path

```text
for each partial job:
  Direct Stream preload A_part/B_part into operand buffer
  set accumulate_enable
  GEMM reads A/B from operand buffer
  GEMM reads old C from scratchpad when accumulate_enable=1
  GEMM writes accumulated C to scratchpad

after last job:
  DMA store final C
  scoreboard compare
```

The Direct Stream path requires the router update described in Section 8.

---

## 15. Target CASE_ID / Recipe Plan

P13 introduces multi-job accumulation recipes. These IDs represent recipes rather than a single standalone GEMM job.

Recommended P13 recipe map:

```text
CASE_ID=208 : M=1, N=4,  K_total=16, parts 8+8
CASE_ID=209 : M=4, N=4,  K_total=16, parts 8+8
CASE_ID=210 : M=4, N=16, K_total=16, parts 8+8
CASE_ID=211 : M=8, N=16, K_total=16, parts 8+8
CASE_ID=212 : M=5, N=9,  K_total=9,  parts 8+1
```

Footprint table per recipe:

```text
CASE_ID | M | N  | K_total | Parts | Max A bytes/job | Max B bytes/job | C words | Purpose
208     | 1 | 4  | 16      | 8+8   | 8               | 32              | 4       | minimum two-job accumulation smoke
209     | 4 | 4  | 16      | 8+8   | 32              | 32              | 16      | multi-row accumulation without N/M tiling pressure
210     | 4 | 16 | 16      | 8+8   | 32              | 128             | 64      | accumulation with N tiling
211     | 8 | 16 | 16      | 8+8   | 64              | 128             | 128     | accumulation with M tiling + N tiling
212     | 5 | 9  | 9       | 8+1   | 40              | 72              | 45      | ragged M/N and tail K partition
```

Why these recipes are chosen:

```text
- CASE_ID=208 isolates C RMW accumulation with the smallest two-job recipe.
- CASE_ID=209 validates multi-row accumulation without requiring N or M tiling pressure.
- CASE_ID=210 validates C RMW with N tiling.
- CASE_ID=211 validates C RMW with combined M and N tiling.
- CASE_ID=212 validates ragged M/N dimensions and a short final K partition.
```

Test infrastructure implication:

```text
P13 recipe support must allow multiple GEMM jobs per selected CASE_ID.
The software reference must build full-K expected C across all partitions.
The test must generate compact A/B payloads per partial job.
The scoreboard must treat the final C after the last partial job as the compare target.
Intermediate partial jobs may publish no final result, or publish internal debug-only events.
```

Recommended P13C policy:

```text
Treat CASE_ID=208..212 as multi-job partial-accumulation recipes.
Keep existing CASE_ID=203..207 as single-job P12 directed cases.
```

---

## 16. Verification Milestone Plan

### P13A: C RMW / Partial Accumulation Spec

Deliverable:

```text
docs/gemm_c_rmw_accumulation_spec.md
```

Status criteria:

```text
spec reviewed and committed
C RMW first-step scope approved
accumulate_enable control policy approved
CASE_ID recipe plan approved
Direct Stream router C-read requirement approved
```

### P13B: Safe Parameter / Control Plumbing

Goal:

```text
Add GEMM_ENABLE_C_RMW_ACCUM default 0.
Add accumulate_enable job control bit.
Propagate through gemm_top, ai_accel_subsys, ai_accel_subsys_uvm_top, run_uvm.tcl, and run_full_uvm_regression.tcl as needed.
Confirm default full regression remains unchanged.
```

Expected acceptance:

```text
Full regression remains 74/74 PASS with GEMM_ENABLE_C_RMW_ACCUM=0.
Focused elaboration with GEMM_ENABLE_C_RMW_ACCUM=1 compiles and runs a non-accumulating case.
```

### P13C: Partial-Sum Recipe / Reference Model Support

Goal:

```text
Add CASE_ID=208..212 as multi-job accumulation recipes.
Generate compact per-job A/B payloads.
Generate full-K final expected C.
Update scoreboard/result flow to compare only the final accumulated C result.
```

Expected checks:

```text
software expected C is generated correctly
per-job A/B footprints are legal
C footprint remains legal
recipe metadata maps to the correct partial job list
```

Initial software/reference run targets:

```text
CASE_ID=208
CASE_ID=211
CASE_ID=212
```

### P13D: RTL C Read-Modify-Write Datapath

Goal:

```text
Implement optional scratchpad C RMW at final C writeback.
```

Minimum required behavior:

```text
GEMM_ENABLE_C_RMW_ACCUM=1
accumulate_enable=0 writes partial_sum directly
accumulate_enable=1 reads old C, adds partial_sum, writes new C
C read and C write target the same C address
Done waits for final C RMW write completion
```

Initial required cases:

```text
CASE_ID=208 PASS
CASE_ID=211 PASS
CASE_ID=212 PASS
```

### P13E: Host-Primary Focused Validation

Goal:

```text
Validate host-primary partial accumulation before frontend path stress.
```

Recommended focused recipes:

```text
CASE_ID=208 : minimum two-job accumulation smoke
CASE_ID=209 : multi-row accumulation
CASE_ID=210 : accumulation + N tiling
CASE_ID=211 : accumulation + M/N tiling
CASE_ID=212 : ragged M/N + K tail partition
```

Required checks:

```text
final result compare PASS
per-job mac_count = M*N*K_part
per-job output_count = M*N
UVM_ERROR=0
UVM_FATAL=0
```

### P13F: Frontend Compatibility

Goal:

```text
Validate C RMW accumulation across DMA, AXI-Stream, and Direct Stream load-store paths.
```

Recommended representative recipe:

```text
CASE_ID=211 : M=8, N=16, K_total=16, parts 8+8
```

Recommended path checks:

```text
DMA load-store           CASE_ID=211
AXI-Stream load-store    CASE_ID=211
Direct Stream load-store CASE_ID=211
```

Validated P13F result:

```text
DMA load-store           CASE_ID=211 PASS
AXI-Stream load-store    CASE_ID=211 PASS
Direct Stream load-store CASE_ID=211 PASS
```

### P13G: Regression Integration

Goal:

```text
Add a small representative P13 frontend subset to full regression.
```

Recommended additions:

```text
gemm_4lane_c_rmw_dma_load_store_case211
gemm_4lane_c_rmw_axis_stream_load_store_case211
gemm_4lane_c_rmw_direct_stream_load_store_case211
```

These items are added after the five P13D focused DUT recipes:

```text
p13d_c_rmw_accum_case208
p13d_c_rmw_accum_case209
p13d_c_rmw_accum_case210
p13d_c_rmw_accum_case211
p13d_c_rmw_accum_case212
```

Expected full regression total:

```text
Current after P13D:
  79

After P13G:
  79 + 3 = 82
```

The exact total may change if more representative recipes are selected.

### P13H: Documentation / Closure

Goal:

```text
Update README, regression list, C RMW accumulation spec, memory path policy, Direct Stream frontend spec, AXI-Stream frontend spec, DMA integration/store specs, and performance GEMM spec.
```

Expected closure status:

```text
Performance GEMM P13: C Read-Modify-Write Partial Accumulation Completed
Full regression: 82/82 PASS
```

---

## 17. Regression Inclusion Policy

P13 full regression should remain lightweight.

Recommended policy:

```text
- Keep default stress pools unchanged.
- Add only forced single-recipe C RMW representative items.
- Do not add all P13 recipes to default stress pools.
- Keep longer multi-job and ragged recipes manual or nightly until runtime is measured.
```

Initial full-regression representative recipe:

```text
CASE_ID=211 : M=8, N=16, K_total=16, parts 8+8
```

Why CASE_ID=211:

```text
- exercises four M=2 tiles
- exercises two N=8 tiles
- exercises two external K partitions
- validates C RMW accumulation on 128 C outputs
- validates M/N tiled scheduler interaction with C RMW writeback
- per-job A/B payloads remain bounded
- final C output count matches the existing P12 CASE_ID=205 scale
```

Manual / focused recipes:

```text
CASE_ID=208 : minimum C RMW smoke
CASE_ID=210 : N tiling + accumulation
CASE_ID=212 : ragged M/N and K tail partition
```

---

## 18. Suggested Tcl Runs

### 18.1 Host-Primary C RMW Focused Recipe

```tcl
set UVM_TEST ai_accel_subsys_smoke_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 211
set RUN_ALL 0

set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14
set SMOKE_DONE_TIMEOUT_CYCLES 300000

set GEMM_MAC_LANES 4
set GEMM_ENABLE_B_CACHE 1
set GEMM_B_CACHE_MAX_K 8
set GEMM_B_CACHE_MAX_N 8
set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
set GEMM_ENABLE_A_ROW_CACHE 1
set GEMM_A_ROW_CACHE_MAX_K 8
set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1
set GEMM_ENABLE_K_TILING 1
set GEMM_K_TILE_SIZE 8
set GEMM_ENABLE_N_TILING 1
set GEMM_N_TILE_SIZE 8
set GEMM_ENABLE_M_TILING 1
set GEMM_M_TILE_SIZE 2
set GEMM_ENABLE_C_RMW_ACCUM 1

# Test class or recipe sequence sets per-job accumulate_enable:
#   job0 accumulate_enable=0
#   job1 accumulate_enable=1

do run_uvm.tcl
```

### 18.2 DMA Load-Store C RMW Representative Recipe

```tcl
set UVM_TEST ai_accel_subsys_dma_load_store_stress_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 211
set STORE_STRESS_JOB_COUNT 1
set STORE_STRESS_RANDOM 0
set STORE_STRESS_GAP_CYCLES 10

set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14
set SMOKE_DONE_TIMEOUT_CYCLES 300000

set GEMM_MAC_LANES 4
set GEMM_ENABLE_B_CACHE 1
set GEMM_B_CACHE_MAX_K 8
set GEMM_B_CACHE_MAX_N 8
set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
set GEMM_ENABLE_A_ROW_CACHE 1
set GEMM_A_ROW_CACHE_MAX_K 8
set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1
set GEMM_ENABLE_K_TILING 1
set GEMM_K_TILE_SIZE 8
set GEMM_ENABLE_N_TILING 1
set GEMM_N_TILE_SIZE 8
set GEMM_ENABLE_M_TILING 1
set GEMM_M_TILE_SIZE 2
set GEMM_ENABLE_C_RMW_ACCUM 1

do run_uvm.tcl
```

### 18.3 AXI-Stream Load-Store C RMW Representative Recipe

```tcl
set UVM_TEST ai_accel_subsys_axis_stream_load_store_stress_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 211
set AXIS_STRESS_JOB_COUNT 1
set AXIS_STRESS_RANDOM 0
set AXIS_STRESS_GAP_CYCLES 10

set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14
set SMOKE_DONE_TIMEOUT_CYCLES 300000

set GEMM_MAC_LANES 4
set GEMM_ENABLE_B_CACHE 1
set GEMM_B_CACHE_MAX_K 8
set GEMM_B_CACHE_MAX_N 8
set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
set GEMM_ENABLE_A_ROW_CACHE 1
set GEMM_A_ROW_CACHE_MAX_K 8
set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1
set GEMM_ENABLE_K_TILING 1
set GEMM_K_TILE_SIZE 8
set GEMM_ENABLE_N_TILING 1
set GEMM_N_TILE_SIZE 8
set GEMM_ENABLE_M_TILING 1
set GEMM_M_TILE_SIZE 2
set GEMM_ENABLE_C_RMW_ACCUM 1

do run_uvm.tcl
```

### 18.4 Direct Stream Load-Store C RMW Representative Recipe

```tcl
set UVM_TEST ai_accel_subsys_direct_stream_load_store_stress_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 211
set DS_STRESS_JOB_COUNT 1
set DS_STRESS_RANDOM 0
set DS_STRESS_GAP_CYCLES 10

set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14
set SMOKE_DONE_TIMEOUT_CYCLES 300000

set GEMM_MAC_LANES 4
set GEMM_ENABLE_B_CACHE 1
set GEMM_B_CACHE_MAX_K 8
set GEMM_B_CACHE_MAX_N 8
set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
set GEMM_ENABLE_A_ROW_CACHE 1
set GEMM_A_ROW_CACHE_MAX_K 8
set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1
set GEMM_ENABLE_K_TILING 1
set GEMM_K_TILE_SIZE 8
set GEMM_ENABLE_N_TILING 1
set GEMM_N_TILE_SIZE 8
set GEMM_ENABLE_M_TILING 1
set GEMM_M_TILE_SIZE 2
set GEMM_ENABLE_C_RMW_ACCUM 1

do run_uvm.tcl
```

### 18.5 Optional CDC C RMW Sanity

Use one of the load-store commands above and switch:

```tcl
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 13
```

---

## 19. Pass / Fail Criteria

P13 is considered closed when:

```text
P13A spec is created and committed
P13B default-off parameter/control plumbing passes full regression
P13C partial-sum recipe / reference model support passes setup checks
P13D C RMW RTL datapath passes host-primary correctness
P13E focused host-primary accumulation recipes pass
P13F DMA / AXI-Stream / Direct Stream path compatibility passes
P13G representative C RMW items are added to full regression
full regression passes with the new total
P13H docs are updated
```

Final P13 full-regression result:

```text
TOTAL : 82
PASS  : 82
FAIL  : 0
```

The selected P13 regression contains five P13D focused DUT items plus three P13G frontend representative items, bringing the total to 82.

---

## 20. Risk Analysis

### Risk 1: C Read Address Bug

Potential failure:

```text
C RMW reads the wrong C address or uses local tile index where global output index is required.
```

Mitigation:

```text
Define C_read_addr and C_write_addr from the same global m/n indices.
Use CASE_ID=211 with M/N tiling and verify rows/columns beyond the first local tile.
```

### Risk 2: C Read/Write Ordering Bug

Potential failure:

```text
C write occurs before old C read data is valid.
```

Mitigation:

```text
Add explicit RMW read-wait state.
Write only after C read data is captured.
```

### Risk 3: Done Assertion Too Early

Potential failure:

```text
done asserts after final MAC but before final C RMW write completion.
```

Mitigation:

```text
Preserve final C write completion wait state.
Run back-to-back partial jobs and DMA store immediately after final done.
```

### Risk 4: Non-Accumulate Job Accidentally Adds Old C

Potential failure:

```text
Job 0 with accumulate_enable=0 still reads and adds old C.
```

Mitigation:

```text
Initialize C to a non-zero poison pattern before Job 0.
Check Job 0 overwrite behavior through final recipe result.
```

### Risk 5: Accumulate Job Accidentally Overwrites Old C

Potential failure:

```text
Job 1 with accumulate_enable=1 writes only partial_sum1 and loses partial_sum0.
```

Mitigation:

```text
Use two partitions with distinguishable non-zero contributions.
Compare final C against full-K reference.
```

### Risk 6: Direct Stream C Read Router Bug

Potential failure:

```text
In Direct Stream mode, GEMM C reads are incorrectly routed to operand buffer or treated as illegal reads.
```

Mitigation:

```text
Update router policy to route C-region reads to scratchpad.
Run Direct Stream CASE_ID=211 C RMW focused test.
```

### Risk 7: Scoreboard Intermediate Result Bug

Potential failure:

```text
Scoreboard compares after Job 0 instead of after final accumulated job.
```

Mitigation:

```text
Represent P13 CASE_ID=208..212 as multi-job recipes.
Publish final result only after the last partial job, or explicitly mark intermediate events as non-final.
```

### Risk 8: Counter Interpretation Bug

Potential failure:

```text
Test expects each partial job's mac_count to equal M*N*K_total instead of M*N*K_part.
```

Mitigation:

```text
Document per-job counter semantics.
Recipe-level reference can sum counters across partial jobs if needed.
```

### Risk 9: Stale C Across Recipes

Potential failure:

```text
A second accumulation recipe starts with C values left by the previous recipe.
```

Mitigation:

```text
Use accumulate_enable=0 for the first job of every recipe.
Optionally clear or poison C before each recipe to make behavior explicit.
```

### Risk 10: Regression Runtime Growth

Potential failure:

```text
Multi-job C RMW recipes make full regression too slow.
```

Mitigation:

```text
Add only three CASE_ID=211 representative items.
Keep the full P13 focused matrix manual until runtime is measured.
Use explicit longer timeout only for P13 representative recipes.
```

---

## 21. Future Work After P13

After C RMW partial accumulation is stable, future milestones can consider:

```text
P14: external tile scheduler
P15: A tile cache / multi-row A reuse
P16: overlapped preload / compute / C RMW scheduling
P17: memory-resident descriptor fetch into P16-compatible recipe snapshots (completed)
P18: memory-resident completion writeback after descriptor-fetch recipe terminal status (completed)
P19: multi-bank or widened local memory
P20: constrained-random tile coverage expansion
```

P13 is now treated as the bridge between internal single-job tiled GEMM and external multi-job tiled GEMM.

---

## 22. Summary

P13 adds the missing accelerator-side accumulation primitive:

```text
C_new = C_old + partial_sum
```

when `accumulate_enable=1`.

The completed P12 design can already compute large M/N/K tiled jobs inside one GEMM invocation. P13 extends the subsystem so multiple partial GEMM jobs can contribute to the same C output region without requiring host-side accumulation or temporary partial-C buffers.

The first P13 implementation is:

```text
C read-modify-write based
scratchpad C accumulation only
default-off parameterized
runtime controlled by accumulate_enable
compatible with host-primary, DMA, AXI-Stream, and Direct Stream flows
```

The final regression result after P13G is:

```text
TOTAL : 82
PASS  : 82
FAIL  : 0
```


---

## 23. P18 C RMW Completion Writeback Validation

P18F validates that a descriptor-fetch C RMW recipe can complete the P13 partial-K accumulation path and then write a committed completion record.

Validated representative:

```text
csr_desc_fetch_c_rmw_completion_wb_case208 PASS
```

Required run configuration:

```text
CASE_ID=208
GEMM_ENABLE_C_RMW_ACCUM=1
ACCUMULATE_ENABLE=0
```

The top-level `ACCUMULATE_ENABLE` remains 0 because each descriptor / recipe slot carries its own `accumulate_enable` control bit:

```text
slot0 accumulate_enable=0
slot1 accumulate_enable=1
```

Current integrated regression after P18H:

```text
TOTAL : 110
PASS  : 110
FAIL  : 0
```
