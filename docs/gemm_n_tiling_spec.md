# GEMM N-Tiling / Output-Column Tiling Spec

## 0. Purpose

This document defines the P11 milestone for extending the completed P10 K-dimension tiling baseline into output-column tiling.

P10 proved that the cache-backed 4-lane GEMM datapath can process `K_total` larger than the local cache K capacity by splitting K into multiple K tiles and accumulating partial sums in an internal row accumulator.

P11 extends that model from:

```text
K_total may exceed GEMM_B_CACHE_MAX_K / GEMM_A_ROW_CACHE_MAX_K
N_total must still fit GEMM_B_CACHE_MAX_N
```

to:

```text
K_total may exceed the local K tile capacity
N_total may exceed the local B-cache / row-accumulator N capacity
```

The completed P11 implementation is intentionally limited to N-dimension tiling only on top of the P10 row-accumulator model:

```text
M is still processed row-by-row.
K may be either single-tile or K-tiled through the P10 mechanism.
N is split into output-column tiles.
Each active K/N tile still fits the existing B-cache and row-accumulator capacity.
```

The primary target is to support shapes such as:

```text
M=4, N=16, K=16
```

using:

```text
N tile 0: N = 0  .. 7
N tile 1: N = 8  .. 15
K tile 0: K = 0  .. 7
K tile 1: K = 8  .. 15
```

P11 must preserve existing subsystem paths:

```text
Host primary
DMA load-store
AXI-Stream load-store
Direct Stream load-store
```

and must preserve scoreboard-based result correctness.

---

## 1. Baseline Before P11

Closed P10 baseline:

```text
Performance GEMM P10: K-Dimension Tiling Completed

Full regression:
  TOTAL : 68
  PASS  : 68
  FAIL  : 0
```

P10 validated:

```text
P10B: safe K-tiling parameter plumbing                 PASS
P10C: K>8 testcase / software reference support        PASS
P10D: actual K-tile execution microarchitecture        PASS
P10E: frontend compatibility sanity                    PASS
P10F: regression integration                           PASS
P10G: documentation / closure update                   PASS
```

Representative P10 K-tiling cases:

```text
CASE_ID=193 : M=1, N=4, K=16
CASE_ID=194 : M=2, N=4, K=16
CASE_ID=195 : M=4, N=4, K=16
CASE_ID=196 : M=3, N=5, K=9
CASE_ID=197 : M=4, N=4, K=12
```

P10 solved the K-capacity limitation but intentionally preserved the first-step policy:

```text
N <= GEMM_B_CACHE_MAX_N
```

P11 starts the next natural step: output-column tiling for `N_total > GEMM_B_CACHE_MAX_N`.

---

## 1A. P11 Closure Status

P11 is closed.

```text
P11A: N-tiling spec                                      PASS
P11B: safe N-tiling parameter plumbing                   PASS
P11C: N>8 testcase / software reference support          PASS
P11D: actual N-tile execution microarchitecture          PASS
P11E: frontend compatibility sanity                      PASS
P11G: regression integration                             PASS
P11H: documentation / closure update                     PASS
```

Final full regression:

```text
TOTAL : 71
PASS  : 71
FAIL  : 0
```

Validated P11 representative configuration:

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
```

P11G adds three representative full-regression items using `CASE_ID=200` across DMA, AXI-Stream, and Direct Stream load-store paths.

---

## 2. P11 High-Level Goal

P11 adds optional N-tiling support to `gemm_top`.

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
```

The first P11 implementation should support:

```text
N_total > 8
N_tile <= 8
K may be <= 8 or > 8
K_tile <= 8
```

The design must compute the same mathematical result as the untiled GEMM:

```text
C[m][n] = sum over k=0..K_total-1 of A[m][k] * B[k][n]
```

but internally execute N and K loops as local tiles:

```text
C[m][n_tile + local_n] = sum over all K tiles of partial_dot(m, n_tile + local_n, k_tile)
```

---

## 3. Non-Goals for First P11 Step

P11A/P11B/P11C should not attempt to implement the full general tiling problem.

The first P11 implementation does not include:

```text
- M tiling
- multi-row output tile scheduling
- scratchpad C read-modify-write partial accumulation
- C accumulation across multiple external jobs
- C direct-store path
- systolic array scheduling
- multi-row A cache
- multi-bank scratchpad
- widened local memory interface
- additional AXI ports
- new DMA protocol
- new AXI-Stream packet format
- new Direct Stream packet format
- simultaneous compute and preload overlap
```

P11 focuses only on output-column tiling inside one GEMM job.

---

## 4. Key Architectural Choice

There are two practical ways to extend P10 to `N_total > GEMM_B_CACHE_MAX_N`.

### 4.1 Option A: Larger Row Accumulator for Full N

Allocate `c_row_accum[0 .. N_total-1]` and keep accumulating all output columns for one row.

This is not recommended for the first P11 step because it introduces:

```text
- runtime-sized or much larger accumulator storage
- larger clear/writeback loops
- wider scoreboard/debug surface
- less direct reuse of the existing P10 local-N accumulator model
```

### 4.2 Option B: Output-Column Tile Accumulator

Keep the existing small row accumulator sized by the local N tile:

```text
c_row_accum[local_n] for local_n = 0 .. n_tile_len-1
```

Then process one output-column tile at a time:

```text
for m in 0 .. M-1:
  for each N tile:
    clear c_row_accum[0 .. n_tile_len-1]

    for each K tile:
      preload B[k_tile][n_tile] into b_cache
      preload A[m][k_tile] into a_row_cache

      for local_n in 0 .. n_tile_len-1:
        c_row_accum[local_n] += dot(A row tile, B tile column)

    write final C[m][n_tile + local_n]
```

This is the recommended first P11 architecture.

Benefits:

```text
- reuses the P10 row-accumulator model
- keeps row accumulator storage small
- avoids scratchpad C read-modify-write
- writes each C output exactly once
- keeps completion semantics close to P10
- naturally maps B-cache to a local K x local N tile
- preserves frontend protocols
```

Cost:

```text
A row tile may be reloaded for each N tile.
```

This is acceptable for the first P11 implementation because P11 is correctness-first. A later milestone can optimize A-row tile reuse across multiple N tiles.

---

## 5. P11 Execution Model

### 5.1 Logical Loop Structure

Recommended first P11 loop order:

```text
for m in 0 .. M-1:
  for n_tile_base in 0, N_TILE_MAX, 2*N_TILE_MAX, ...:
    n_tile_len = min(N_TILE_MAX, N_total - n_tile_base)

    c_row_accum[0 .. n_tile_len-1] = 0

    for k_tile_base in 0, K_TILE_MAX, 2*K_TILE_MAX, ...:
      k_tile_len = min(K_TILE_MAX, K_total - k_tile_base)

      preload A[m][k_tile_base + 0 .. k_tile_base + k_tile_len - 1]
        into a_row_cache[0 .. k_tile_len - 1]

      preload B[k_tile_base + 0 .. k_tile_base + k_tile_len - 1]
               [n_tile_base + 0 .. n_tile_base + n_tile_len - 1]
        into b_cache[0 .. k_tile_len - 1][0 .. n_tile_len - 1]

      for local_n in 0 .. n_tile_len-1:
        for local_k in 0 .. k_tile_len-1 step GEMM_MAC_LANES:
          c_row_accum[local_n] += lane dot product

    for local_n in 0 .. n_tile_len-1:
      write C[m][n_tile_base + local_n] = c_row_accum[local_n]
```

### 5.2 Tile Lengths

For the initial P11 target:

```text
K_TILE_MAX = min(GEMM_K_TILE_SIZE, GEMM_B_CACHE_MAX_K, GEMM_A_ROW_CACHE_MAX_K)
N_TILE_MAX = min(GEMM_N_TILE_SIZE, GEMM_B_CACHE_MAX_N)
```

For the current cache8 configuration:

```text
K_TILE_MAX = 8
N_TILE_MAX = 8
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

### 5.3 Lane Validity

K-lane validity remains local to the current K tile:

```text
lane_valid[lane] = (local_k + lane) < k_tile_len
```

N tile validity is handled by the local output-column index:

```text
local_n < n_tile_len
```

The global output column is:

```text
global_n = n_tile_base + local_n
```

---

## 6. Proposed New Parameters

Add a default-off parameter to `gemm_top`:

```systemverilog
parameter bit GEMM_ENABLE_N_TILING = 1'b0
```

Add an optional tile-size parameter:

```systemverilog
parameter int GEMM_N_TILE_SIZE = 8
```

Recommended effective tile-size derivation:

```text
GEMM_N_TILE_SIZE_EFFECTIVE = min(GEMM_N_TILE_SIZE, GEMM_B_CACHE_MAX_N)
```

Recommended policy:

```text
GEMM_ENABLE_N_TILING=0:
  preserve existing P10/P9 behavior

GEMM_ENABLE_N_TILING=1 and dim_n <= GEMM_N_TILE_SIZE_EFFECTIVE:
  existing single-N-tile behavior may be reused

GEMM_ENABLE_N_TILING=1 and dim_n > GEMM_N_TILE_SIZE_EFFECTIVE:
  use output-column tiled row-accumulator path
```

Default behavior must remain unchanged:

```text
GEMM_ENABLE_N_TILING=0
```

P11 should not disturb the closed 68/68 P10 regression when N tiling is disabled.

---

## 7. Supported Dimension Policy

First P11 support target:

```text
M <= existing DIM_WIDTH capacity
N may be greater than GEMM_B_CACHE_MAX_N
K may be greater than GEMM_B_CACHE_MAX_K / GEMM_A_ROW_CACHE_MAX_K
N_TILE_MAX <= GEMM_B_CACHE_MAX_N
K_TILE_MAX <= GEMM_B_CACHE_MAX_K and GEMM_A_ROW_CACHE_MAX_K
```

For the initial P11 implementation:

```text
N_TILE_MAX <= 8
K_TILE_MAX <= 8
```

Recommended safe policy:

```text
if GEMM_ENABLE_N_TILING=0:
  preserve existing P10/P9 behavior

if GEMM_ENABLE_N_TILING=1 and GEMM_N_TILE_SIZE_EFFECTIVE == 0:
  fatal, because no legal N tile can be formed

if GEMM_ENABLE_N_TILING=1 and B-cache is disabled:
  fallback or fatal depending on test policy

if GEMM_ENABLE_N_TILING=1 and row accumulator cannot cover one N tile:
  fatal, because the local output tile cannot be accumulated
```

For the verification-oriented RTL, a UVM-visible fatal for unsupported directed P11 tests is acceptable during bring-up. A production-like fallback can be added later.

---

## 8. Target CASE_ID Plan

P11 introduces N>8 directed cases. These cases require test-side payload storage expansion because B can exceed 64 bytes.

Recommended P11 case map:

```text
CASE_ID=198 : M=1, N=16, K=8
CASE_ID=199 : M=2, N=16, K=8
CASE_ID=200 : M=4, N=16, K=16
CASE_ID=201 : M=3, N=9,  K=9
CASE_ID=202 : M=4, N=12, K=16
```

Footprint table:

```text
CASE_ID | M | N  | K  | A bytes | B bytes | C words | C bytes | Purpose
198     | 1 | 16 | 8  | 8       | 128     | 16      | 64      | minimum N=16 smoke, K fits one tile
199     | 2 | 16 | 8  | 16      | 128     | 32      | 128     | multi-row N=16, K fits one tile
200     | 4 | 16 | 16 | 64      | 256     | 64      | 256     | full P11 representative: N tiling + K tiling
201     | 3 | 9  | 9  | 27      | 81      | 27      | 108     | N tail 8+1 and K tail 8+1
202     | 4 | 12 | 16 | 64      | 192     | 48      | 192     | N tail 8+4 and K tiles 8+8
```

Why these cases are chosen:

```text
- CASE_ID=198 isolates N tiling without K tiling.
- CASE_ID=199 validates multi-row N tiling.
- CASE_ID=200 validates combined N tiling and K tiling.
- CASE_ID=201 validates both N-tail and K-tail behavior.
- CASE_ID=202 validates a partial N tile with full K tiling.
```

Test infrastructure implication:

```text
B payload storage must support at least 256 bytes.
Expected C storage must support at least 64 words for CASE_ID=200.
CASE_ID inference / scoreboard whitelist must include the P11 directed case range.
```

Recommended P11C policy:

```text
Treat CASE_ID=198..202 as variable-dimension directed cases.
If the existing inference only maps 100..199 to variable-dimension tests,
extend the inference or explicitly whitelist 200..202 as variable-dimension P11 cases.
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

For N and K tiling:

```text
A tile address = base_a + (m * K_total + (k_tile_base + local_k))
B tile address = base_b + ((k_tile_base + local_k) * N_total + (n_tile_base + local_n))
C tile address = base_c + ((m * N_total + (n_tile_base + local_n)) * 4)
```

The B-cache stores the active tile with local K and local N indices:

```text
b_cache[local_k][local_n]
```

The A-row cache stores only the active K tile:

```text
a_row_cache[local_k]
```

The row accumulator stores only the active N tile:

```text
c_row_accum[local_n]
```

Global indices:

```text
global_k = k_tile_base + local_k
global_n = n_tile_base + local_n
```

### 9.1 Footprint / Overlap Policy

For the first P11 cases, the default map remains legal.

The largest planned B footprint is:

```text
CASE_ID=200: B bytes = 256
B region: 0x0000_0100 .. 0x0000_01ff
C base : 0x0000_0200
```

Therefore B and C do not overlap for the first P11 representative set.

Future larger cases may require moving `base_c` or expanding the scratchpad map.

---

## 10. Internal Storage Requirements

### 10.1 B Cache

P11 reuses the cache8 B-cache capacity:

```text
GEMM_B_CACHE_MAX_K=8
GEMM_B_CACHE_MAX_N=8
```

Required entries per active tile:

```text
8 * 8 = 64 int8 entries
```

For N tiling, the B-cache stores only the active K/N tile:

```text
b_cache[0 .. k_tile_len-1][0 .. n_tile_len-1]
```

It does not store the full `K_total * N_total` matrix.

### 10.2 A-Row Cache

P11 reuses the P10/P9 A-row cache capacity:

```text
GEMM_A_ROW_CACHE_MAX_K=8
```

For each row and N tile, the A-row cache stores the active K tile:

```text
a_row_cache[0 .. k_tile_len-1]
```

The first P11 implementation may reload the A row tile for each N tile. This is acceptable for correctness-first bring-up.

### 10.3 C Row Accumulator

P11 reuses the P10 conceptual row accumulator, but interprets it as a local-N-tile accumulator:

```systemverilog
logic signed [31:0] c_row_accum [0:GEMM_B_CACHE_MAX_N-1];
```

For the first P11 target:

```text
n_tile_len <= 8
```

Clear policy:

```text
clear active c_row_accum[0 .. n_tile_len-1]
at the start of each output-column tile for each row m
```

Update policy:

```text
c_row_accum[local_n] += tile_partial_sum
```

Final write policy:

```text
write C[m][n_tile_base + local_n] once after all K tiles for that N tile are complete
```

---

## 11. Packed Preload Behavior Under N Tiling

P11 first implementation should prioritize correctness over packed preload optimization.

### 11.1 Recommended First Policy

Recommended P11D bring-up policy:

```text
Use conservative scalar preload for N-tiled jobs.
```

Reason:

```text
N tiling changes B address traversal and tail masking.
A packed preload can also become redundant across N tiles.
Scalar preload reduces first-implementation risk.
```

This mirrors the P10D correctness-first strategy.

### 11.2 Future Packed B-Cache Tile Preload

For a B tile:

```text
B tile bytes = k_tile_len * n_tile_len
```

For full K=8, N=8 tile:

```text
B tile bytes = 64
```

A future optimized implementation may use aligned 32-bit reads and unpack byte lanes, but it must map to local tile indices:

```text
local_k = global_k - k_tile_base
local_n = global_n - n_tile_base
b_cache[local_k][local_n]
```

### 11.3 Future A-Row Tile Reuse

Because P11 loop order is `m -> n_tile -> k_tile`, the first version may reload A row tiles for each N tile.

A future optimization can keep A-row tile data valid across N tiles when:

```text
same m
same k_tile_base
same k_tile_len
```

This is future work and should not block P11 correctness closure.

---

## 12. Performance Counter Requirements

Existing counter semantics remain unchanged:

```text
gemm_perf_busy_cycles  : cycles while GEMM is busy
gemm_perf_mac_count    : logical MAC operations committed
gemm_perf_output_count : final C outputs whose write completion has been observed
```

For P11 N tiling:

```text
gemm_perf_mac_count    = M * N_total * K_total
gemm_perf_output_count = M * N_total
```

The MAC counter must count logical MACs across all K tiles and N tiles.

Expected values for first P11 cases:

```text
CASE_ID | M | N  | K  | expected_mac | expected_output
198     | 1 | 16 | 8  | 128          | 16
199     | 2 | 16 | 8  | 256          | 32
200     | 4 | 16 | 16 | 1024         | 64
201     | 3 | 9  | 9  | 243          | 27
202     | 4 | 12 | 16 | 768          | 48
```

`gemm_perf_busy_cycles` is expected to increase relative to P10, but P11 should not use exact busy-cycle thresholds in the first implementation.

---

## 13. GEMM Done Semantics

P11 must preserve the P10/P9 done semantics:

```text
gemm_top.done asserts only after the final C write completion has been observed.
```

For N tiling, this means:

```text
all rows are complete
all N tiles are complete
all K tiles inside each N tile are complete
all final C writes have completed
only then assert done
```

`done` must not assert after the last MAC calculation if final C writes are still outstanding.

This is required because DMA store may start immediately after `acc_done`.

---

## 14. Frontend Compatibility Requirements

P11 must not change frontend protocols.

### 14.1 Host Primary Path

```text
host preload A/B
launch GEMM with N tiling enabled
host readback C
scoreboard compare
```

### 14.2 DMA Load-Store Path

```text
DMA load A/B into scratchpad
GEMM N/K-tiled compute
DMA store final C
scoreboard compare
```

### 14.3 AXI-Stream Load-Store Path

```text
AXI-Stream preload A/B into scratchpad
GEMM N/K-tiled compute
DMA store final C
scoreboard compare
```

### 14.4 Direct Stream Load-Store Path

```text
Direct Stream preload A/B into operand buffer
GEMM N/K-tiled compute through gemm_input_mem_router
C written to scratchpad
DMA store final C
scoreboard compare
```

P11 B-cache tile preload and A-row tile preload must use the existing GEMM local memory interface so that scratchpad mode and Direct Stream mode both work.

Direct Stream buffer capacity must be audited for at least:

```text
B bytes = 256
A bytes = 64
```

for `CASE_ID=200`.

---

## 15. Verification Milestone Plan

### P11A: N-Tiling Spec

Deliverable:

```text
docs/gemm_n_tiling_spec.md
```

Status criteria:

```text
spec reviewed and committed
N-only tiling scope approved
output-column tile accumulator policy approved
CASE_ID plan approved
```

### P11B: Safe Parameter Plumbing

Goal:

```text
Add GEMM_ENABLE_N_TILING default 0.
Add GEMM_N_TILE_SIZE default 8.
Propagate through gemm_top, ai_accel_subsys, ai_accel_subsys_uvm_top, run_uvm.tcl, and run_full_uvm_regression.tcl.
Confirm default full regression remains unchanged.
```

Expected acceptance:

```text
Full regression remains 68/68 PASS with GEMM_ENABLE_N_TILING=0.
Focused elaboration with GEMM_ENABLE_N_TILING=1 compiles and runs a non-N-tiling case.
```

### P11C: Test CASE_ID Support

Goal:

```text
Add CASE_ID=198..202 to shared case database / helper payloads / scoreboard whitelist.
Expand test payload arrays for B payloads up to at least 256 bytes.
```

Expected checks:

```text
software expected C is generated correctly
A/B/C footprints are legal
CASE_ID inference maps P11 cases to variable-dimension directed tests
```

Initial software/reference run targets:

```text
CASE_ID=198
CASE_ID=200
CASE_ID=201
```

### P11D: RTL N-Tiling Prototype

Goal:

```text
Implement output-column tiled row-accumulator scheduling inside gemm_top.
```

Minimum required behavior:

```text
GEMM_ENABLE_N_TILING=1
GEMM_ENABLE_K_TILING=1
GEMM_MAC_LANES=4
cache/preload stack enabled
N_TILE_MAX=8 effective tile size
K_TILE_MAX=8 effective tile size
CASE_ID=198 PASS
CASE_ID=200 PASS
CASE_ID=201 PASS
```

### P11E: Host-Primary Focused Validation

Goal:

```text
Validate host-primary N-tiled correctness before frontend path stress.
```

Recommended focused cases:

```text
CASE_ID=198 : N tiling only
CASE_ID=200 : N tiling + K tiling
CASE_ID=201 : N tail + K tail
CASE_ID=202 : N tail 8+4 + K tiling
```

Required checks:

```text
result compare PASS
mac_count = M*N*K
output_count = M*N
UVM_ERROR=0
UVM_FATAL=0
```

### P11F: Frontend Compatibility

Goal:

```text
Validate N/K-tiled GEMM across DMA, AXI-Stream, and Direct Stream load-store paths.
```

Recommended representative case:

```text
CASE_ID=200 : M=4, N=16, K=16
```

Recommended path checks:

```text
DMA load-store           CASE_ID=200
AXI-Stream load-store    CASE_ID=200
Direct Stream load-store CASE_ID=200
```

### P11G: Regression Integration

Goal:

```text
Add a small representative P11 subset to full regression.
```

Recommended additions:

```text
gemm_4lane_ntiling_dma_load_store_case200
gemm_4lane_ntiling_axis_stream_load_store_case200
gemm_4lane_ntiling_direct_stream_load_store_case200
```

Expected full regression total:

```text
Current after P10F:
  68

After P11G:
  68 + 3 = 71
```

The exact total may change if more representative cases are selected.

### P11H: Documentation / Closure

Goal:

```text
Update README, regression list, performance spec, operand reuse spec, Direct Stream frontend spec, and P11 closure summary.
```

Expected closure status:

```text
Performance GEMM P11: N-Dimension Tiling Completed
Full regression: 71/71 PASS
```

---

## 15A. P11 Validation Results

Focused host-primary validation:

```text
CASE_ID=198 : M=1, N=16, K=8   PASS
CASE_ID=199 : M=2, N=16, K=8   PASS
CASE_ID=200 : M=4, N=16, K=16  PASS
CASE_ID=201 : M=3, N=9,  K=9   PASS
CASE_ID=202 : M=4, N=12, K=16  PASS
```

Representative frontend compatibility validation:

```text
DMA load-store           CASE_ID=200 PASS
AXI-Stream load-store    CASE_ID=200 PASS
Direct Stream load-store CASE_ID=200 PASS
```

Full regression integration:

```text
gemm_4lane_ntiling_dma_load_store_case200        PASS
gemm_4lane_ntiling_axis_stream_load_store_case200 PASS
gemm_4lane_ntiling_direct_stream_load_store_case200 PASS

TOTAL : 71
PASS  : 71
FAIL  : 0
```

---

## 16. Regression Inclusion Policy

P11 full regression should remain lightweight.

Recommended policy:

```text
- Keep default stress pools unchanged.
- Add only forced single-case N-tiling representative items.
- Do not add all P11 cases to default stress pools.
- Keep larger and tail-heavy P11 cases manual or nightly until runtime is measured.
```

Initial full-regression representative case:

```text
CASE_ID=200 : M=4, N=16, K=16
```

Why CASE_ID=200:

```text
- exercises two full N=8 tiles
- exercises two full K=8 tiles
- uses full 4-lane groups inside each K tile
- validates multi-row output scheduling
- B payload remains within 256 bytes
- C output count is 64, matching existing expected-C array scale if expanded to at least 64 words
```

Manual / focused cases:

```text
CASE_ID=198 : N tiling only
CASE_ID=201 : N tail 8+1 and K tail 8+1
CASE_ID=202 : N tail 8+4 and K tiling
```

---

## 17. Suggested Tcl Runs

### 17.1 Host-Primary N-Tiling Smoke

```tcl
set UVM_TEST ai_accel_subsys_smoke_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 200

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
set GEMM_ENABLE_K_TILING 1
set GEMM_K_TILE_SIZE 8
set GEMM_ENABLE_N_TILING 1
set GEMM_N_TILE_SIZE 8

 do run_uvm.tcl
```

### 17.2 DMA Load-Store N-Tiling

```tcl
set UVM_TEST ai_accel_subsys_dma_load_store_stress_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 200
set STORE_STRESS_JOB_COUNT 1
set STORE_STRESS_RANDOM 0
set STORE_STRESS_GAP_CYCLES 10

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
set GEMM_ENABLE_K_TILING 1
set GEMM_K_TILE_SIZE 8
set GEMM_ENABLE_N_TILING 1
set GEMM_N_TILE_SIZE 8

 do run_uvm.tcl
```

### 17.3 AXI-Stream Load-Store N-Tiling

```tcl
set UVM_TEST ai_accel_subsys_axis_stream_load_store_stress_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 200
set AXIS_STRESS_JOB_COUNT 1
set AXIS_STRESS_RANDOM 0
set AXIS_STRESS_GAP_CYCLES 10

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
set GEMM_ENABLE_K_TILING 1
set GEMM_K_TILE_SIZE 8
set GEMM_ENABLE_N_TILING 1
set GEMM_N_TILE_SIZE 8

 do run_uvm.tcl
```

### 17.4 Direct Stream Load-Store N-Tiling

```tcl
set UVM_TEST ai_accel_subsys_direct_stream_load_store_stress_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 200
set DS_STRESS_JOB_COUNT 1
set DS_STRESS_RANDOM 0
set DS_STRESS_GAP_CYCLES 10

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
set GEMM_ENABLE_K_TILING 1
set GEMM_K_TILE_SIZE 8
set GEMM_ENABLE_N_TILING 1
set GEMM_N_TILE_SIZE 8

 do run_uvm.tcl
```

### 17.5 Optional CDC N-Tiling Sanity

Use one of the load-store commands above and switch:

```tcl
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 13
```

---

## 18. Pass / Fail Criteria

P11 is considered closed because:

```text
P11A spec is created and committed
P11B default-off parameter plumbing passes full regression
P11C new CASE_ID support passes software reference / scoreboard setup
P11D N-tiled RTL prototype passes host-primary correctness
P11E focused host-primary N/K-tile cases pass
P11F DMA / AXI-Stream / Direct Stream path compatibility passes
P11G representative N-tiling items are added to full regression
full regression passes with the new total
P11H docs are updated
```

Final P11 full-regression result:

```text
TOTAL : 71
PASS  : 71
FAIL  : 0
```

The selected representative subset uses three CASE_ID=200 frontend-path items, bringing the full regression total to 71.

---

## 19. Risk Analysis

### Risk 1: Local-N vs Global-N Indexing Bug

Potential failure:

```text
B-cache or C output uses local_n when global_n is required, or vice versa.
```

Mitigation:

```text
Define local_n and global_n explicitly.
Use CASE_ID=198 and CASE_ID=200 with N=16.
Check C columns 8..15 differ from columns 0..7.
```

### Risk 2: B Tile Base Address Bug

Potential failure:

```text
N tile 1 reloads B columns 0..7 instead of columns 8..15.
```

Mitigation:

```text
Use input patterns where B columns 8..15 are distinguishable.
Use CASE_ID=198/200.
```

### Risk 3: Row Accumulator Clear Bug Between N Tiles

Potential failure:

```text
c_row_accum from N tile 0 contaminates N tile 1.
```

Mitigation:

```text
Clear accumulator per N tile.
Use CASE_ID=198 and verify all 16 output columns.
```

### Risk 4: Row Accumulator Clear Bug Between Rows

Potential failure:

```text
c_row_accum from row m contaminates row m+1.
```

Mitigation:

```text
Use multi-row CASE_ID=199/200.
Use row-varying A patterns.
```

### Risk 5: K and N Tile Interaction Bug

Potential failure:

```text
Only the first K tile is accumulated for each N tile,
or K tile state is not reset when moving to a new N tile.
```

Mitigation:

```text
Use CASE_ID=200 with both N=16 and K=16.
Use mac_count = 1024 and result compare.
```

### Risk 6: Tail Tile Bug

Potential failure:

```text
N tail or K tail lanes use stale cache data.
```

Mitigation:

```text
Use CASE_ID=201 with N=9 and K=9.
Use lane-valid and n-valid masking.
```

### Risk 7: Test Payload Capacity Bug

Potential failure:

```text
B payload arrays silently truncate B bytes beyond 64.
```

Mitigation:

```text
P11C must expand payload arrays to at least 256 bytes.
Add fatal checks if A/B/C footprints exceed helper storage.
```

### Risk 8: Direct Stream Operand Buffer Capacity Bug

Potential failure:

```text
Direct Stream B operand buffer cannot store B bytes=256.
```

Mitigation:

```text
Audit operand buffer depth before P11F.
Run Direct Stream CASE_ID=200 focused test.
```

### Risk 9: Done Assertion Too Early

Potential failure:

```text
done asserts after the final N tile MAC but before final C write completion.
```

Mitigation:

```text
Preserve final C write completion wait state.
Run DMA store immediately after GEMM done.
```

### Risk 10: Regression Runtime Growth

Potential failure:

```text
N/K-tiled cases make full regression too slow.
```

Mitigation:

```text
Add only three CASE_ID=200 forced representative items.
Keep additional P11 cases focused/manual.
```

---

## 20. Future Work After P11

After N-only tiling is stable, future milestones can consider:

```text
P12: M tiling / multi-row tile scheduling
P13: C read-modify-write partial accumulation
P14: external tile scheduler
P15: A-row tile reuse across N tiles
P16: overlapped preload / compute scheduling
P17: larger Direct Stream tile movement
P18: optional C direct-store path
```

P11 should be treated as the bridge between P10 K-only tiling and a more general 2D tiled GEMM scheduler.

---

## 21. Summary

P11 is the next natural milestone after P10.

P10 proved:

```text
4-lane full-cache GEMM can process K_total larger than cache capacity
by splitting K into multiple local-cache tiles and accumulating partial sums internally.
```

P11 proves:

```text
4-lane full-cache GEMM can process N_total larger than the B-cache / row-accumulator N capacity
by splitting output columns into local N tiles and reusing the P10 K-tile accumulation model within each output-column tile.
```

The recommended first P11 implementation is:

```text
N-only output-column tiling
row-accumulator based partial accumulation per N tile
reuse P10 K-tiling inside each N tile
no scratchpad C read-modify-write
no frontend protocol changes
default-off parameterization
focused CASE_ID=198..202 bring-up
small regression addition using CASE_ID=200
```

This milestone is now closed with full regression passing, while keeping the implementation meaningful, interview-friendly, and low-risk as the project moves toward a true tiled GEMM accelerator architecture.
