# GEMM M-Tiling / Multi-Row Tile Scheduling Spec

## 0. Purpose

This document defines the P12 milestone for extending the completed P11 N-dimension tiling baseline into M-dimension tiling and multi-row output-tile scheduling.

P10 proved that the cache-backed 4-lane GEMM datapath can process `K_total` larger than the local cache K capacity by splitting K into multiple K tiles and accumulating partial sums in an internal row accumulator.

P11 proved that the same datapath can process `N_total` larger than the local B-cache / row-accumulator N capacity by splitting output columns into local N tiles.

P12 extends that model from:

```text
K_total may exceed the local K tile capacity
N_total may exceed the local N tile capacity
M is still scheduled one row at a time
```

to:

```text
K_total may exceed the local K tile capacity
N_total may exceed the local N tile capacity
M_total may be grouped into local M tiles
```

The first P12 implementation is intentionally limited to internal M-dimension tiling only on top of the P11 output-column tiled row-accumulator model:

```text
K may be either single-tile or K-tiled through the P10 mechanism.
N may be either single-tile or N-tiled through the P11 mechanism.
M is split into local output-row tiles.
Each active M/N/K tile still fits the existing local tile capacity.
```

The primary target is to support shapes such as:

```text
M=8, N=16, K=16
```

using:

```text
M tile 0: M = 0 .. 1
M tile 1: M = 2 .. 3
M tile 2: M = 4 .. 5
M tile 3: M = 6 .. 7
N tile 0: N = 0 .. 7
N tile 1: N = 8 .. 15
K tile 0: K = 0 .. 7
K tile 1: K = 8 .. 15
```

P12 must preserve existing subsystem paths:

```text
Host primary
DMA load-store
AXI-Stream load-store
Direct Stream load-store
```

and must preserve scoreboard-based result correctness.

---

## 1. Baseline Before P12

Closed P11 baseline:

```text
Performance GEMM P11: N-Dimension Tiling Completed

Full regression:
  TOTAL : 71
  PASS  : 71
  FAIL  : 0
```

P11 validated:

```text
P11A: N-tiling spec                                      PASS
P11B: safe N-tiling parameter plumbing                   PASS
P11C: N>8 testcase / software reference support          PASS
P11D: actual N-tile execution microarchitecture          PASS
P11E: frontend compatibility sanity                      PASS
P11G: regression integration                             PASS
P11H: documentation / closure update                     PASS
```

Representative P11 N-tiling cases:

```text
CASE_ID=198 : M=1, N=16, K=8
CASE_ID=199 : M=2, N=16, K=8
CASE_ID=200 : M=4, N=16, K=16
CASE_ID=201 : M=3, N=9,  K=9
CASE_ID=202 : M=4, N=12, K=16
```

P11 solved the N-capacity limitation but intentionally preserved the first-step policy:

```text
M is still processed row-by-row.
```

P12 starts the next natural step: local multi-row output tile scheduling for `M_total > GEMM_M_TILE_SIZE_EFFECTIVE`.

---

## 2. P12 High-Level Goal

P12 adds optional M-tiling support to `gemm_top`.

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
```

The first P12 implementation should support:

```text
M_total may be greater than 2
M_tile <= 2
N may be <= 8 or > 8
N_tile <= 8
K may be <= 8 or > 8
K_tile <= 8
```

The design must compute the same mathematical result as the untiled GEMM:

```text
C[m][n] = sum over k=0..K_total-1 of A[m][k] * B[k][n]
```

but internally execute M, N, and K loops as local tiles:

```text
C[m_tile + local_m][n_tile + local_n]
  = sum over all K tiles of partial_dot(m_tile + local_m,
                                        n_tile + local_n,
                                        k_tile)
```

---

## 3. Non-Goals for First P12 Step

P12A/P12B/P12C should not attempt to implement the full external tiled GEMM problem.

The first P12 implementation does not include:

```text
- scratchpad C read-modify-write partial accumulation
- C accumulation across multiple external jobs
- external tile scheduler
- multi-job tile chaining
- C direct-store path
- systolic array scheduling
- multi-bank scratchpad
- widened local memory interface
- additional AXI ports
- new DMA protocol
- new AXI-Stream packet format
- new Direct Stream packet format
- simultaneous compute and preload overlap
- multi-row packed A tile preload optimization
- larger Direct Stream streaming protocol
```

P12 focuses only on multi-row output tile scheduling inside one GEMM job.

---

## 4. Key Architectural Choice

There are two practical ways to extend P11 to local M tiling.

### 4.1 Option A: Outer M-Tile Loop with Existing Single-Row Accumulator

Add an outer M-tile loop but keep the compute body effectively row-by-row:

```text
for each M tile:
  for each local_m:
    run the existing P11 row-oriented N/K tile scheduler
```

This is simple, but it does not meaningfully reuse B tiles across multiple output rows. It is mostly a control-loop refactor and gives limited architectural value.

### 4.2 Option B: Multi-Row Output Tile Accumulator

Keep the existing B-cache tile model and extend the row accumulator into a small local M x local N output-tile accumulator:

```text
c_tile_accum[local_m][local_n]
```

Then process one local output tile at a time:

```text
for m_tile_base in 0, M_TILE_MAX, 2*M_TILE_MAX, ...:
  for n_tile_base in 0, N_TILE_MAX, 2*N_TILE_MAX, ...:
    clear c_tile_accum[local_m][local_n]

    for each K tile:
      preload B[k_tile][n_tile] once into b_cache

      for local_m in 0 .. m_tile_len-1:
        preload A[m_tile + local_m][k_tile] into a_row_cache
        accumulate partial dot products into c_tile_accum[local_m][local_n]

    write final C[m_tile + local_m][n_tile + local_n]
```

This is the recommended first P12 architecture.

Benefits:

```text
- reuses the P10/P11 K/N tile scheduler model
- reuses the existing B-cache tile storage
- reuses the existing A-row cache as a per-local-row staging buffer
- reuses B tile across multiple local output rows
- keeps local accumulator storage small for M_TILE_SIZE=2 and N_TILE_SIZE=8
- avoids scratchpad C read-modify-write
- writes each C output exactly once
- preserves frontend protocols
```

Cost:

```text
A row tile is still loaded once per local_m per K tile.
```

This is acceptable for the first P12 implementation because P12 is correctness-first. A later milestone can optimize multi-row A tile storage or preload/compute overlap.

---

## 5. P12 Execution Model

### 5.1 Logical Loop Structure

Recommended first P12 loop order:

```text
for m_tile_base in 0, M_TILE_MAX, 2*M_TILE_MAX, ...:
  m_tile_len = min(M_TILE_MAX, dim_m - m_tile_base)

  for n_tile_base in 0, N_TILE_MAX, 2*N_TILE_MAX, ...:
    n_tile_len = min(N_TILE_MAX, dim_n - n_tile_base)

    c_tile_accum[0 .. m_tile_len-1][0 .. n_tile_len-1] = 0

    for k_tile_base in 0, K_TILE_MAX, 2*K_TILE_MAX, ...:
      k_tile_len = min(K_TILE_MAX, dim_k - k_tile_base)

      preload B[k_tile_base + 0 .. k_tile_base + k_tile_len - 1]
               [n_tile_base + 0 .. n_tile_base + n_tile_len - 1]
        into b_cache[0 .. k_tile_len - 1][0 .. n_tile_len - 1]

      for local_m in 0 .. m_tile_len-1:
        preload A[m_tile_base + local_m]
                 [k_tile_base + 0 .. k_tile_base + k_tile_len - 1]
          into a_row_cache[0 .. k_tile_len - 1]

        for local_n in 0 .. n_tile_len-1:
          for local_k in 0 .. k_tile_len-1 step GEMM_MAC_LANES:
            c_tile_accum[local_m][local_n] += lane dot product

    for local_m in 0 .. m_tile_len-1:
      for local_n in 0 .. n_tile_len-1:
        write C[m_tile_base + local_m][n_tile_base + local_n]
          = c_tile_accum[local_m][local_n]
```

### 5.2 Tile Lengths

For the initial P12 target:

```text
M_TILE_MAX = GEMM_M_TILE_SIZE_EFFECTIVE
K_TILE_MAX = min(GEMM_K_TILE_SIZE, GEMM_B_CACHE_MAX_K, GEMM_A_ROW_CACHE_MAX_K)
N_TILE_MAX = min(GEMM_N_TILE_SIZE, GEMM_B_CACHE_MAX_N)
```

For the current target configuration:

```text
M_TILE_MAX = 2
K_TILE_MAX = 8
N_TILE_MAX = 8
```

Tile length per M tile:

```text
m_tile_len = min(M_TILE_MAX, dim_m - m_tile_base)
```

Examples:

```text
M=8 -> M tile lengths 2, 2, 2, 2
M=7 -> M tile lengths 2, 2, 2, 1
M=5 -> M tile lengths 2, 2, 1
```

Tile length per N tile:

```text
n_tile_len = min(N_TILE_MAX, dim_n - n_tile_base)
```

Examples:

```text
N=16 -> N tile lengths 8, 8
N=12 -> N tile lengths 8, 4
N=9  -> N tile lengths 8, 1
```

Tile length per K tile:

```text
k_tile_len = min(K_TILE_MAX, dim_k - k_tile_base)
```

Examples:

```text
K=16 -> K tile lengths 8, 8
K=12 -> K tile lengths 8, 4
K=9  -> K tile lengths 8, 1
```

### 5.3 Lane and Tile Validity

K-lane validity remains local to the current K tile:

```text
lane_valid[lane] = (local_k + lane) < k_tile_len
```

N tile validity is handled by the local output-column index:

```text
local_n < n_tile_len
```

M tile validity is handled by the local output-row index:

```text
local_m < m_tile_len
```

Global indices are:

```text
global_m = m_tile_base + local_m
global_n = n_tile_base + local_n
global_k = k_tile_base + local_k
```

---

## 6. Proposed New Parameters

Add a default-off parameter to `gemm_top`:

```systemverilog
parameter bit GEMM_ENABLE_M_TILING = 1'b0
```

Add an optional tile-size parameter:

```systemverilog
parameter int GEMM_M_TILE_SIZE = 2
```

Recommended effective tile-size derivation:

```text
GEMM_M_TILE_SIZE_EFFECTIVE = max(1, GEMM_M_TILE_SIZE)
```

For the first P12 implementation, the validated value should be:

```text
GEMM_M_TILE_SIZE_EFFECTIVE = 2
```

Recommended policy:

```text
GEMM_ENABLE_M_TILING=0:
  preserve existing P11/P10/P9 behavior

GEMM_ENABLE_M_TILING=1 and dim_m <= GEMM_M_TILE_SIZE_EFFECTIVE:
  existing single-M-tile behavior may be reused

GEMM_ENABLE_M_TILING=1 and dim_m > GEMM_M_TILE_SIZE_EFFECTIVE:
  use multi-row output tile scheduling
```

Default behavior must remain unchanged:

```text
GEMM_ENABLE_M_TILING=0
```

P12 should not disturb the closed 71/71 P11 regression when M tiling is disabled.

---

## 7. Supported Dimension Policy

First P12 support target:

```text
M may be greater than GEMM_M_TILE_SIZE_EFFECTIVE
N may be greater than GEMM_B_CACHE_MAX_N
K may be greater than GEMM_B_CACHE_MAX_K / GEMM_A_ROW_CACHE_MAX_K
M_TILE_MAX is small and fixed at 2 for first implementation
N_TILE_MAX <= GEMM_B_CACHE_MAX_N
K_TILE_MAX <= GEMM_B_CACHE_MAX_K and GEMM_A_ROW_CACHE_MAX_K
```

For the initial P12 implementation:

```text
M_TILE_MAX <= 2
N_TILE_MAX <= 8
K_TILE_MAX <= 8
```

Recommended safe policy:

```text
if GEMM_ENABLE_M_TILING=0:
  preserve existing P11/P10/P9 behavior

if GEMM_ENABLE_M_TILING=1 and GEMM_M_TILE_SIZE_EFFECTIVE == 0:
  fatal, because no legal M tile can be formed

if GEMM_ENABLE_M_TILING=1 and GEMM_ENABLE_N_TILING=0 for N>GEMM_B_CACHE_MAX_N:
  fatal or fallback depending on existing test policy

if GEMM_ENABLE_M_TILING=1 and GEMM_ENABLE_K_TILING=0 for K>GEMM_B_CACHE_MAX_K:
  fatal or fallback depending on existing test policy

if GEMM_ENABLE_M_TILING=1 and the output-tile accumulator cannot cover one M x N tile:
  fatal, because the local output tile cannot be accumulated
```

For the verification-oriented RTL, a UVM-visible fatal for unsupported directed P12 tests is acceptable during bring-up. A production-like fallback can be added later.

---

## 8. Target CASE_ID Plan

P12 introduces larger-M directed cases. These cases require test-side payload storage expansion because C can exceed the current P11 64-word representative output size.

Recommended P12 case map:

```text
CASE_ID=203 : M=8, N=8,  K=8
CASE_ID=204 : M=8, N=16, K=8
CASE_ID=205 : M=8, N=16, K=16
CASE_ID=206 : M=5, N=9,  K=9
CASE_ID=207 : M=7, N=12, K=16
```

Footprint table:

```text
CASE_ID | M | N  | K  | A bytes | B bytes | C words | C bytes | Purpose
203     | 8 | 8  | 8  | 64      | 64      | 64      | 256     | M tiling only, K/N fit one tile
204     | 8 | 16 | 8  | 64      | 128     | 128     | 512     | M tiling + N tiling
205     | 8 | 16 | 16 | 128     | 256     | 128     | 512     | full P12 representative: M tiling + N tiling + K tiling
206     | 5 | 9  | 9  | 45      | 81      | 45      | 180     | M tail 2+2+1, N tail 8+1, K tail 8+1
207     | 7 | 12 | 16 | 112     | 192     | 84      | 336     | M tail 2+2+2+1, N tail 8+4, K tiles 8+8
```

Why these cases are chosen:

```text
- CASE_ID=203 isolates M tiling without N or K tiling.
- CASE_ID=204 validates M tiling combined with N tiling.
- CASE_ID=205 validates combined M tiling, N tiling, and K tiling.
- CASE_ID=206 validates M-tail, N-tail, and K-tail behavior.
- CASE_ID=207 validates an irregular M tail with partial N tile and full K tiling.
```

Test infrastructure implication:

```text
A payload storage must support at least 128 bytes.
B payload storage must support at least 256 bytes.
Expected C storage must support at least 128 words for CASE_ID=205.
CASE_ID inference / scoreboard whitelist must include the P12 directed case range.
```

Recommended P12C policy:

```text
Treat CASE_ID=203..207 as variable-dimension directed cases.
If the existing inference only maps earlier ranges to variable-dimension tests,
extend the inference or explicitly whitelist 203..207 as variable-dimension P12 cases.
```

---

## 9. Memory Layout

The default memory map remains:

```text
A base = 0x0000_0000
B base = 0x0000_0100
C base = 0x0000_0200
```

For int8 A/B and int32 C:

```text
A bytes = M * K
B bytes = K * N
C words = M * N
C bytes = M * N * 4
```

Address formulas:

```text
A[m][k] address = base_a + (m * K_total + k)
B[k][n] address = base_b + (k * N_total + n)
C[m][n] address = base_c + ((m * N_total + n) * 4)
```

For M, N, and K tiling:

```text
A tile address = base_a + ((m_tile_base + local_m) * K_total
                           + (k_tile_base + local_k))

B tile address = base_b + ((k_tile_base + local_k) * N_total
                           + (n_tile_base + local_n))

C tile address = base_c + (((m_tile_base + local_m) * N_total
                            + (n_tile_base + local_n)) * 4)
```

The B-cache stores the active K/N tile with local K and local N indices:

```text
b_cache[local_k][local_n]
```

The A-row cache stores the active K tile for one local M row at a time:

```text
a_row_cache[local_k]
```

The output-tile accumulator stores the active M/N output tile:

```text
c_tile_accum[local_m][local_n]
```

Global indices:

```text
global_m = m_tile_base + local_m
global_n = n_tile_base + local_n
global_k = k_tile_base + local_k
```

### 9.1 Footprint / Overlap Policy

For the first P12 cases, the default map remains legal.

The largest planned A/B footprint is:

```text
CASE_ID=205: A bytes = 128
A region: 0x0000_0000 .. 0x0000_007f

CASE_ID=205: B bytes = 256
B region: 0x0000_0100 .. 0x0000_01ff
C base : 0x0000_0200
```

Therefore B and C do not overlap for the first P12 representative set.

The largest planned C footprint is:

```text
CASE_ID=205: C bytes = 512
C region: 0x0000_0200 .. 0x0000_03ff
```

Future larger cases may require moving `base_c` or expanding the scratchpad map.

---

## 10. Internal Storage Requirements

### 10.1 B Cache

P12 reuses the cache8 B-cache capacity:

```text
GEMM_B_CACHE_MAX_K=8
GEMM_B_CACHE_MAX_N=8
```

Required entries per active B tile:

```text
8 * 8 = 64 int8 entries
```

For M tiling, the B-cache stores only the active K/N tile:

```text
b_cache[0 .. k_tile_len-1][0 .. n_tile_len-1]
```

It does not store the full `K_total * N_total` matrix.

The main P12 reuse benefit is:

```text
one B tile can be reused across multiple local_m rows in the same M tile
```

### 10.2 A-Row Cache

P12 reuses the P10/P11 A-row cache capacity:

```text
GEMM_A_ROW_CACHE_MAX_K=8
```

For each local M row and K tile, the A-row cache stores the active K tile:

```text
a_row_cache[0 .. k_tile_len-1]
```

The first P12 implementation may load the A row tile once per `local_m` per K tile. This is acceptable for correctness-first bring-up.

A future implementation may introduce a true A tile cache:

```text
a_tile_cache[local_m][local_k]
```

but this is not required for P12 closure.

### 10.3 Output Tile Accumulator

P12 extends the P10/P11 row accumulator into a local M/N tile accumulator:

```systemverilog
logic signed [31:0] c_tile_accum [0:GEMM_M_TILE_SIZE_EFFECTIVE-1]
                                 [0:GEMM_B_CACHE_MAX_N-1];
```

For the first P12 target:

```text
m_tile_len <= 2
n_tile_len <= 8
```

Required accumulator entries:

```text
2 * 8 = 16 signed 32-bit entries
```

Clear policy:

```text
clear active c_tile_accum[0 .. m_tile_len-1][0 .. n_tile_len-1]
at the start of each output M/N tile
```

Update policy:

```text
c_tile_accum[local_m][local_n] += tile_partial_sum
```

Final write policy:

```text
write C[m_tile_base + local_m][n_tile_base + local_n]
once after all K tiles for that M/N tile are complete
```

---

## 11. Packed Preload Behavior Under M Tiling

P12 first implementation should prioritize correctness over packed preload optimization.

### 11.1 Recommended First Policy

Recommended P12D bring-up policy:

```text
Use conservative scalar tile preload for M-tiled jobs.
```

Reason:

```text
M tiling changes A address traversal and output-tile accumulation.
B tile reuse across local M rows changes scheduling order.
Scalar preload reduces first-implementation risk.
```

This mirrors the P10D and P11D correctness-first strategy.

### 11.2 Future Multi-Row A Tile Preload

For a local M/K tile:

```text
A tile bytes = m_tile_len * k_tile_len
```

For full M=2, K=8 tile:

```text
A tile bytes = 16
```

A future optimized implementation may store the active A tile as:

```text
a_tile_cache[local_m][local_k]
```

and preload it with aligned 32-bit reads. This optimization should not block P12 correctness closure.

### 11.3 B Tile Reuse Across M Tile

The first P12 implementation should preserve the B tile while iterating over local M rows:

```text
preload B tile once
for local_m in active M tile:
  preload A row tile
  compute using same B tile
```

This is the main architectural value of P12 compared with simply wrapping the existing P11 row scheduler in an outer loop.

---

## 12. Performance Counter Requirements

Existing counter semantics remain unchanged:

```text
gemm_perf_busy_cycles  : cycles while GEMM is busy
gemm_perf_mac_count    : logical MAC operations committed
gemm_perf_output_count : final C outputs whose write completion has been observed
```

For P12 M tiling:

```text
gemm_perf_mac_count    = M_total * N_total * K_total
gemm_perf_output_count = M_total * N_total
```

The MAC counter must count logical MACs across all M tiles, N tiles, and K tiles.

Expected values for first P12 cases:

```text
CASE_ID | M | N  | K  | expected_mac | expected_output
203     | 8 | 8  | 8  | 512          | 64
204     | 8 | 16 | 8  | 1024         | 128
205     | 8 | 16 | 16 | 2048         | 128
206     | 5 | 9  | 9  | 405          | 45
207     | 7 | 12 | 16 | 1344         | 84
```

`gemm_perf_busy_cycles` is expected to increase relative to P11, but P12 should not use exact busy-cycle thresholds in the first implementation.

---

## 13. GEMM Done Semantics

P12 must preserve the P10/P11 done semantics:

```text
gemm_top.done asserts only after the final C write completion has been observed.
```

For M tiling, this means:

```text
all M tiles are complete
all N tiles inside each M tile are complete
all K tiles inside each M/N tile are complete
all final C writes have completed
only then assert done
```

`done` must not assert after the last MAC calculation if final C writes are still outstanding.

This is required because DMA store may start immediately after `acc_done`.

---

## 14. Frontend Compatibility Requirements

P12 must not change frontend protocols.

### 14.1 Host Primary Path

```text
host preload A/B
launch GEMM with M/N/K tiling enabled
host readback C
scoreboard compare
```

### 14.2 DMA Load-Store Path

```text
DMA load A/B into scratchpad
GEMM M/N/K-tiled compute
DMA store final C
scoreboard compare
```

### 14.3 AXI-Stream Load-Store Path

```text
AXI-Stream preload A/B into scratchpad
GEMM M/N/K-tiled compute
DMA store final C
scoreboard compare
```

### 14.4 Direct Stream Load-Store Path

```text
Direct Stream preload A/B into operand buffer
GEMM M/N/K-tiled compute through gemm_input_mem_router
C written to scratchpad
DMA store final C
scoreboard compare
```

P12 B-cache tile preload and A-row tile preload must use the existing GEMM local memory interface so that scratchpad mode and Direct Stream mode both work.

Direct Stream buffer capacity must be audited for at least:

```text
A bytes = 128
B bytes = 256
```

for `CASE_ID=205`.

---

## 15. Verification Milestone Plan

### P12A: M-Tiling Spec

Deliverable:

```text
docs/gemm_m_tiling_spec.md
```

Status criteria:

```text
spec reviewed and committed
M-tiling first-step scope approved
multi-row output tile accumulator policy approved
CASE_ID plan approved
```

### P12B: Safe Parameter Plumbing

Goal:

```text
Add GEMM_ENABLE_M_TILING default 0.
Add GEMM_M_TILE_SIZE default 2.
Propagate through gemm_top, ai_accel_subsys, ai_accel_subsys_uvm_top, run_uvm.tcl, and run_full_uvm_regression.tcl.
Confirm default full regression remains unchanged.
```

Expected acceptance:

```text
Full regression remains 71/71 PASS with GEMM_ENABLE_M_TILING=0.
Focused elaboration with GEMM_ENABLE_M_TILING=1 compiles and runs a non-M-tiling case.
```

### P12C: Test CASE_ID Support

Goal:

```text
Add CASE_ID=203..207 to shared case database / helper payloads / scoreboard whitelist.
Expand test payload arrays for expected C up to at least 128 words.
```

Expected checks:

```text
software expected C is generated correctly
A/B/C footprints are legal
CASE_ID inference maps P12 cases to variable-dimension directed tests
```

Initial software/reference run targets:

```text
CASE_ID=203
CASE_ID=205
CASE_ID=206
```

### P12D: RTL M-Tiling Prototype

Goal:

```text
Implement local M/N output-tile accumulator scheduling inside gemm_top.
```

Minimum required behavior:

```text
GEMM_ENABLE_M_TILING=1
GEMM_ENABLE_N_TILING=1
GEMM_ENABLE_K_TILING=1
GEMM_MAC_LANES=4
cache/preload stack enabled
M_TILE_MAX=2 effective tile size
N_TILE_MAX=8 effective tile size
K_TILE_MAX=8 effective tile size
CASE_ID=203 PASS
CASE_ID=205 PASS
CASE_ID=206 PASS
```

### P12E: Host-Primary Focused Validation

Goal:

```text
Validate host-primary M-tiled correctness before frontend path stress.
```

Recommended focused cases:

```text
CASE_ID=203 : M tiling only
CASE_ID=204 : M tiling + N tiling
CASE_ID=205 : M tiling + N tiling + K tiling
CASE_ID=206 : M tail + N tail + K tail
CASE_ID=207 : M tail + N tail + K tiling
```

Required checks:

```text
result compare PASS
mac_count = M*N*K
output_count = M*N
UVM_ERROR=0
UVM_FATAL=0
```

### P12F: Frontend Compatibility

Goal:

```text
Validate M/N/K-tiled GEMM across DMA, AXI-Stream, and Direct Stream load-store paths.
```

Recommended representative case:

```text
CASE_ID=205 : M=8, N=16, K=16
```

Recommended path checks:

```text
DMA load-store           CASE_ID=205
AXI-Stream load-store    CASE_ID=205
Direct Stream load-store CASE_ID=205
```

### P12G: Regression Integration

Goal:

```text
Add a small representative P12 subset to full regression.
```

Recommended additions:

```text
gemm_4lane_mtiling_dma_load_store_case205
gemm_4lane_mtiling_axis_stream_load_store_case205
gemm_4lane_mtiling_direct_stream_load_store_case205
```

Expected full regression total:

```text
Current after P11G:
  71

After P12G:
  71 + 3 = 74
```

The exact total may change if more representative cases are selected.

### P12H: Documentation / Closure

Goal:

```text
Update README, regression list, performance spec, operand reuse spec, Direct Stream frontend spec, M-tiling spec, and P12 closure summary.
```

Expected closure status:

```text
Performance GEMM P12: M-Dimension Tiling Completed
Full regression: 74/74 PASS
```

---

## 16. Regression Inclusion Policy

P12 full regression should remain lightweight.

Recommended policy:

```text
- Keep default stress pools unchanged.
- Add only forced single-case M-tiling representative items.
- Do not add all P12 cases to default stress pools.
- Keep larger and tail-heavy P12 cases manual or nightly until runtime is measured.
```

Initial full-regression representative case:

```text
CASE_ID=205 : M=8, N=16, K=16
```

Why CASE_ID=205:

```text
- exercises four full M=2 tiles
- exercises two full N=8 tiles
- exercises two full K=8 tiles
- uses full 4-lane groups inside each K tile
- validates multi-row output-tile scheduling
- validates B tile reuse across local M rows
- B payload remains within 256 bytes
- C output count is 128, which forces expected-C storage expansion beyond P11
```

Manual / focused cases:

```text
CASE_ID=203 : M tiling only
CASE_ID=206 : M tail 2+2+1, N tail 8+1, K tail 8+1
CASE_ID=207 : M tail 2+2+2+1, N tail 8+4, K tiling
```

---

## 17. Suggested Tcl Runs

### 17.1 Host-Primary M-Tiling Smoke

```tcl
set UVM_TEST ai_accel_subsys_smoke_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 205

set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14
set SMOKE_DONE_TIMEOUT_CYCLES 200000

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

do run_uvm.tcl
```

### 17.2 DMA Load-Store M-Tiling

```tcl
set UVM_TEST ai_accel_subsys_dma_load_store_stress_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 205
set STORE_STRESS_JOB_COUNT 1
set STORE_STRESS_RANDOM 0
set STORE_STRESS_GAP_CYCLES 10

set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14
set SMOKE_DONE_TIMEOUT_CYCLES 200000

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

do run_uvm.tcl
```

### 17.3 AXI-Stream Load-Store M-Tiling

```tcl
set UVM_TEST ai_accel_subsys_axis_stream_load_store_stress_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 205
set AXIS_STRESS_JOB_COUNT 1
set AXIS_STRESS_RANDOM 0
set AXIS_STRESS_GAP_CYCLES 10

set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14
set SMOKE_DONE_TIMEOUT_CYCLES 200000

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

do run_uvm.tcl
```

### 17.4 Direct Stream Load-Store M-Tiling

```tcl
set UVM_TEST ai_accel_subsys_direct_stream_load_store_stress_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 205
set DS_STRESS_JOB_COUNT 1
set DS_STRESS_RANDOM 0
set DS_STRESS_GAP_CYCLES 10

set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14
set SMOKE_DONE_TIMEOUT_CYCLES 200000

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

do run_uvm.tcl
```

### 17.5 Optional CDC M-Tiling Sanity

Use one of the load-store commands above and switch:

```tcl
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 13
```

---

## 18. Pass / Fail Criteria

P12 is considered closed when:

```text
P12A spec is created and committed
P12B default-off parameter plumbing passes full regression
P12C new CASE_ID support passes software reference / scoreboard setup
P12D M-tiled RTL prototype passes host-primary correctness
P12E focused host-primary M/N/K tile cases pass
P12F DMA / AXI-Stream / Direct Stream path compatibility passes
P12G representative M-tiling items are added to full regression
full regression passes with the new total
P12H docs are updated
```

Expected first P12 full-regression target:

```text
TOTAL : 74
PASS  : 74
FAIL  : 0
```

The exact total may differ if the project selects more or fewer representative items.

---

## 19. Risk Analysis

### Risk 1: Local-M vs Global-M Indexing Bug

Potential failure:

```text
A reads or C writes use local_m when global_m is required, or vice versa.
```

Mitigation:

```text
Define local_m and global_m explicitly.
Use CASE_ID=203 and CASE_ID=205 with M=8.
Check rows 2..7 differ from rows 0..1.
```

### Risk 2: C Tile Accumulator Clear Bug Between M Tiles

Potential failure:

```text
c_tile_accum from M tile 0 contaminates M tile 1.
```

Mitigation:

```text
Clear accumulator per M/N tile.
Use CASE_ID=203 and verify all eight output rows.
```

### Risk 3: C Tile Accumulator Clear Bug Between N Tiles

Potential failure:

```text
c_tile_accum from N tile 0 contaminates N tile 1.
```

Mitigation:

```text
Use CASE_ID=204/205 with N=16.
Verify columns 8..15.
```

### Risk 4: B Tile Reuse Across Local M Rows Bug

Potential failure:

```text
B tile is overwritten or invalidated before all local_m rows consume it.
```

Mitigation:

```text
Use M_TILE_SIZE=2 and CASE_ID=203/205.
Keep B tile valid while iterating local_m.
```

### Risk 5: A Row Cache Stale Data Across Local M Rows

Potential failure:

```text
local_m=1 accidentally reuses A row data from local_m=0.
```

Mitigation:

```text
Reload A-row cache per local_m per K tile.
Use row-varying A patterns.
```

### Risk 6: M, N, and K Tile Interaction Bug

Potential failure:

```text
Only the first K tile is accumulated for each M/N tile,
or K tile state is not reset when moving to a new M tile or N tile.
```

Mitigation:

```text
Use CASE_ID=205 with M=8, N=16, K=16.
Use mac_count = 2048 and result compare.
```

### Risk 7: Tail Tile Bug

Potential failure:

```text
M tail, N tail, or K tail lanes use stale cache data.
```

Mitigation:

```text
Use CASE_ID=206 with M=5, N=9, K=9.
Use local_m-valid, local_n-valid, and lane-valid masking.
```

### Risk 8: Test Payload Capacity Bug

Potential failure:

```text
Expected C arrays silently truncate C words beyond 64.
```

Mitigation:

```text
P12C must expand expected C storage to at least 128 words.
Add fatal checks if A/B/C footprints exceed helper storage.
```

### Risk 9: Direct Stream Operand Buffer Capacity Bug

Potential failure:

```text
Direct Stream A/B operand buffer cannot store A bytes=128 or B bytes=256.
```

Mitigation:

```text
Audit operand buffer depth before P12F.
Run Direct Stream CASE_ID=205 focused test.
```

### Risk 10: Done Assertion Too Early

Potential failure:

```text
done asserts after the final M/N/K tile MAC but before final C write completion.
```

Mitigation:

```text
Preserve final C write completion wait state.
Run DMA store immediately after GEMM done.
```

### Risk 11: Regression Runtime Growth

Potential failure:

```text
M/N/K-tiled cases make full regression too slow.
```

Mitigation:

```text
Add only three CASE_ID=205 forced representative items.
Keep additional P12 cases focused/manual.
Use explicit smoke done timeout only for the representative long cases.
```

---

## 20. Future Work After P12

After M-only tiling is stable, future milestones can consider:

```text
P13: C read-modify-write partial accumulation
P14: external tile scheduler
P15: A tile cache / multi-row A reuse
P16: overlapped preload / compute scheduling
P17: larger Direct Stream tile movement
P18: optional C direct-store path
P19: multi-bank or widened local memory
P20: constrained-random tile coverage expansion
```

P12 should be treated as the bridge between the P11 row-oriented tiled scheduler and a true 2D output tile scheduler.

---

## 21. Summary

P12 is the next natural milestone after P11.

P10 proved:

```text
4-lane full-cache GEMM can process K_total larger than cache capacity
by splitting K into multiple local-cache tiles and accumulating partial sums internally.
```

P11 proved:

```text
4-lane full-cache GEMM can process N_total larger than the B-cache / row-accumulator N capacity
by splitting output columns into local N tiles and reusing the P10 K-tile accumulation model within each output-column tile.
```

P12 proves:

```text
4-lane full-cache GEMM can process multiple output rows as local M tiles
by using a small M x N output-tile accumulator and reusing each B tile across multiple local M rows.
```

The recommended first P12 implementation is:

```text
M-dimension output-row tiling
M_TILE_SIZE=2
local M x N output-tile accumulator
reuse P11 N tiling and P10 K tiling
reuse B tile across local M rows
reuse existing A-row cache as one-row staging
no scratchpad C read-modify-write
no frontend protocol changes
default-off parameterization
focused CASE_ID=203..207 bring-up
small regression addition using CASE_ID=205
```

This keeps the milestone meaningful, interview-friendly, and low-risk while moving the project toward a true tiled GEMM accelerator architecture.
