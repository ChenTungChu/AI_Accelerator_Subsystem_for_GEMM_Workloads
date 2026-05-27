# GEMM 4-Lane MAC Feasibility Spec

## 0. P8 Closure Status

P8 has now been implemented and closed.

Final validated configuration:

```text
GEMM_MAC_LANES=4
GEMM_ENABLE_B_CACHE=1
GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1
GEMM_ENABLE_A_ROW_CACHE=1
GEMM_A_ROW_CACHE_MAX_K=4
GEMM_ENABLE_PACKED_A_ROW_PRELOAD=1
```

Closure result:

```text
P8A: feasibility spec                         PASS
P8B: safe parameter validation / plumbing      PASS
P8C: cache-backed true 4-lane MAC RTL          PASS
P8D: focused perf/profile compare              PASS
P8E: Direct Stream compatibility               PASS
P8F: stress / CDC manual subset                PASS
P8G: representative regression inclusion       PASS

Full regression after P8G:
  TOTAL : 62
  PASS  : 62
  FAIL  : 0
```

Representative 4x4x4 profile improved from the P7 2-lane packed A-row baseline of approximately 500 busy cycles to approximately 472 busy cycles with the cache-backed 4-lane path.

---

## 1. Purpose

This document defines the **P8 feasibility and closure record** for extending the AI Accelerator Subsystem GEMM compute datapath from the current 1-lane / 2-lane MAC model to a cache-backed **4-lane MAC** mode.

The project had already completed the memory-side and operand-reuse milestones before P8:

```text
P4: B-cache operand reuse optimization
P5: packed B-cache preload optimization
P6: scalar A-row cache optimization
P7: packed A-row preload optimization
```

P8 is the first milestone that revisits compute-side parallelism after the operand delivery path has been improved.

The original goal of P8A was not to immediately modify RTL. The goal was to decide whether a 4-lane MAC mode was architecturally reasonable, what constraints were required, and how it should be verified without destabilizing the P7 baseline.

P8 has now completed that feasibility, implementation, profile, stress, CDC, and regression-inclusion flow.

---

## 2. File Name

Recommended file name:

```text
docs/gemm_4lane_mac_feasibility_spec.md
```

Reason:

```text
P8 began as a feasibility and architecture-planning step.
The file now also records P8 closure.
```

---

## 3. Baseline Before P8

The optimized P7 stack was:

```text
GEMM_MAC_LANES=2
GEMM_ENABLE_B_CACHE=1
GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1
GEMM_ENABLE_A_ROW_CACHE=1
GEMM_A_ROW_CACHE_MAX_K=4
GEMM_ENABLE_PACKED_A_ROW_PRELOAD=1
```

Representative P7 performance profile:

```text
CASE_ID | KIND | M | N | K | MACS | OUTPUTS | GEMM_BUSY_CYCLES
100     | 1    | 1 | 1 | 1 | 1    | 1       | 43
101     | 1    | 2 | 2 | 2 | 8    | 4       | 152
105     | 1    | 2 | 3 | 4 | 24   | 6       | 275
5       | 0    | 4 | 4 | 4 | 64   | 16      | 500
400     | 2    | 4 | 4 | 4 | 64   | 16      | 500
401     | 2    | 4 | 4 | 4 | 64   | 16      | 500
402     | 2    | 4 | 4 | 4 | 64   | 16      | 500
403     | 2    | 4 | 4 | 4 | 64   | 16      | 500
```

The P7 stack reduced memory-side bottlenecks enough that compute-side expansion became meaningful to evaluate.

---

## 4. Problem Statement

The P7 compute datapath supported a 2-lane K-parallel MAC mode.

For each output element:

```text
C[m][n] = sum over k of A[m][k] * B[k][n]
```

With 2-lane MAC:

```text
K step width = 2
compute groups per output = ceil(K / 2)
```

For K=4:

```text
2-lane compute groups per output = ceil(4 / 2) = 2
```

A 4-lane MAC mode targets:

```text
K step width = 4
compute groups per output = ceil(K / 4)
```

For K=4:

```text
4-lane compute groups per output = ceil(4 / 4) = 1
```

Therefore, for K=4 cases, a 4-lane MAC can reduce compute groups per output from 2 to 1.

However, a wider MAC only helps if the operand delivery path can supply:

```text
A[m][k+0], A[m][k+1], A[m][k+2], A[m][k+3]
B[k+0][n], B[k+1][n], B[k+2][n], B[k+3][n]
```

in the same compute step.

That is why P8 depends on the completed cache stack:

```text
B-cache
packed B-cache preload
A-row cache
packed A-row preload
```

---

## 5. P8 Design Goals

P8 goals:

1. Preserve the existing default regression behavior.
2. Keep `GEMM_MAC_LANES=4` optional and non-default.
3. Avoid changing the GEMM algorithm.
4. Avoid changing A/B/C memory layout.
5. Avoid changing DMA / AXI-Stream / Direct Stream protocols.
6. Reuse existing B-cache and A-row cache storage.
7. Keep MAC/output counters semantically unchanged.
8. Support correct lane masking for K tails.
9. Keep 1-lane and 2-lane behavior unchanged.
10. Keep full regression growth controlled by adding only representative 4-lane items.
11. Treat 4-lane mode as cache-backed in the first implementation.

---

## 6. Non-Goals

P8 does not attempt to:

- add a systolic array
- add tile scheduling
- increase matrix dimensions
- increase scratchpad bandwidth
- widen the local memory read data bus
- change AXI-MM behavior
- change AXI-Stream behavior
- change Direct Stream protocol
- change C output format
- change accumulator precision
- add multiple C write ports
- add multi-row A caching
- add multi-column B streaming
- make 4-lane mode the default
- require exact performance thresholds in regression
- replace the existing 1-lane or 2-lane modes

P8 is a compute datapath parallelism milestone.

---

## 7. Parameterization Strategy

The project uses:

```systemverilog
parameter int GEMM_MAC_LANES = 1;
```

Supported values after P8:

```text
GEMM_MAC_LANES = 1, 2, or 4
```

Default policy:

```systemverilog
parameter int GEMM_MAC_LANES = 1;
```

Reason:

```text
Existing default-off regression behavior must remain stable.
4-lane mode is opt-in only.
```

Recommended defensive validation:

```systemverilog
initial begin
    if (!((GEMM_MAC_LANES == 1) ||
          (GEMM_MAC_LANES == 2) ||
          (GEMM_MAC_LANES == 4))) begin
        $fatal(1, "Unsupported GEMM_MAC_LANES=%0d. Supported values: 1, 2, 4",
               GEMM_MAC_LANES);
    end
end
```

---

## 8. Effective Enable Policy

### 8.1 Cache-Backed 4-Lane Policy

The first P8 implementation makes true 4-lane compute active only when the job can use the cache-backed operand path:

```text
four_lane_compute_active =
    (GEMM_MAC_LANES == 4) &&
    B-cache active &&
    A-row cache active &&
    dim_k <= GEMM_A_ROW_CACHE_MAX_K &&
    dim_k <= GEMM_B_CACHE_MAX_K
```

Validated strict performance configuration:

```text
GEMM_MAC_LANES=4
GEMM_ENABLE_B_CACHE=1
GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1
GEMM_ENABLE_A_ROW_CACHE=1
GEMM_ENABLE_PACKED_A_ROW_PRELOAD=1
GEMM_A_ROW_CACHE_MAX_K=4
GEMM_B_CACHE_MAX_K=4
GEMM_B_CACHE_MAX_N=4
```

Reason:

```text
The one-read-at-a-time local memory interface cannot naturally feed four A/B operands
directly from scratchpad every compute step.

The completed P7 cache stack can.
```

### 8.2 Fallback Policy

If `GEMM_MAC_LANES=4` is requested but cache-backed 4-lane conditions are not met, the implementation may fall back to the existing 2-lane or scalar-safe path for correctness.

This keeps unsupported cases from failing while making the validated performance path explicit.

The logs should show the requested and effective lane configuration clearly enough to distinguish true 4-lane execution from fallback behavior.

---

## 9. Lane Mask Semantics

For a requested lane count `L`, each compute step consumes up to `L` K-elements.

For 4-lane:

```text
lane 0 valid when k_idx + 0 < dim_k
lane 1 valid when k_idx + 1 < dim_k
lane 2 valid when k_idx + 2 < dim_k
lane 3 valid when k_idx + 3 < dim_k
```

Examples:

```text
K=1:
  lane0 valid
  lane1 invalid
  lane2 invalid
  lane3 invalid

K=2:
  lane0 valid
  lane1 valid
  lane2 invalid
  lane3 invalid

K=3:
  lane0 valid
  lane1 valid
  lane2 valid
  lane3 invalid

K=4:
  lane0 valid
  lane1 valid
  lane2 valid
  lane3 valid

K=5:
  group0: lane0..3 valid
  group1: lane0 valid, lane1..3 invalid
```

For the current P8 target, the most meaningful profile cases are K=4 because the configured cache max values are 4.

---

## 10. Compute Source Model

### 10.1 A Operand Source

In cache-backed 4-lane mode:

```text
A lane0 = a_row_cache[k_idx + 0]
A lane1 = a_row_cache[k_idx + 1]
A lane2 = a_row_cache[k_idx + 2]
A lane3 = a_row_cache[k_idx + 3]
```

Each lane is guarded:

```text
only read/use a_row_cache[k_idx + lane] when lane is valid
```

### 10.2 B Operand Source

In cache-backed 4-lane mode:

```text
B lane0 = b_cache[k_idx + 0][n_idx]
B lane1 = b_cache[k_idx + 1][n_idx]
B lane2 = b_cache[k_idx + 2][n_idx]
B lane3 = b_cache[k_idx + 3][n_idx]
```

Each lane is guarded:

```text
only read/use b_cache[k_idx + lane][n_idx] when lane is valid
```

### 10.3 Accumulation

Each lane computes a signed product:

```text
prod0 = A0 * B0
prod1 = A1 * B1
prod2 = A2 * B2
prod3 = A3 * B3
```

The per-step sum is:

```text
mac_sum = valid0 ? prod0 : 0
        + valid1 ? prod1 : 0
        + valid2 ? prod2 : 0
        + valid3 ? prod3 : 0
```

Then:

```text
acc_next = acc_q + mac_sum
```

The mathematical result remains:

```text
C[m][n] = sum over K of A[m][k] * B[k][n]
```

No scoreboard reference model change is required because the mathematical result does not change.

---

## 11. Signedness and Width Requirements

P8 preserves existing signed int8 behavior.

Recommended signed product model:

```systemverilog
logic signed [A_DATA_WIDTH-1:0] a_lane [0:3];
logic signed [B_DATA_WIDTH-1:0] b_lane [0:3];

logic signed [ACC_WIDTH-1:0] prod_lane [0:3];
logic signed [ACC_WIDTH-1:0] mac_sum;
```

Each product should be sign-extended before accumulation.

Important rule:

```text
Do not let unsigned packed array indexing or part-selects silently convert operands.
```

---

## 12. FSM Integration Model

P8 should not add new high-level scheduling states if avoidable.

Recommended high-level flow:

```text
same P7 FSM
same B-cache preload
same A-row preload
same C writeback
only modify compute step to support 4-lane K stride
```

K step update:

```text
active_lanes = effective lane count
k_idx_next = k_idx + active_lanes
done when k_idx + active_lanes >= dim_k
```

For simplicity, explicit branches are acceptable:

```text
if four_lane_active:
    step = 4
else if two_lane_active:
    step = 2
else:
    step = 1
```

---

## 13. Expected Performance Model

Compute groups per output:

```text
compute_groups_per_output = ceil(K / active_lanes)
```

For K=4:

```text
1-lane: ceil(4 / 1) = 4 groups
2-lane: ceil(4 / 2) = 2 groups
4-lane: ceil(4 / 4) = 1 group
```

For 4x4x4:

```text
M = 4
N = 4
K = 4

2-lane compute groups = 4 * 4 * 2 = 32
4-lane compute groups = 4 * 4 * 1 = 16
```

The P7 4x4x4 class baseline was approximately 500 busy cycles. P8 4-lane reduced the same class to approximately 472 busy cycles.

The speedup is limited because `gemm_perf_busy_cycles` includes preload, compute, C writeback, and FSM overhead. Compute grouping is reduced, but non-compute overhead remains.

---

## 14. Performance Counter Requirements

Existing counters retain their meaning:

```text
gemm_perf_busy_cycles:
  counts the full GEMM busy window

gemm_perf_mac_count:
  equals M * N * K

gemm_perf_output_count:
  equals M * N
```

For 4-lane mode:

```text
MAC count must not decrease.
Only compute grouping changes.
```

Example:

```text
4x4x4:
  expected MAC count = 4 * 4 * 4 = 64
  expected output count = 4 * 4 = 16
```

A correct 4-lane implementation still reports:

```text
mac_count    = 64
output_count = 16
```

---

## 15. Direct Stream Compatibility

Direct Stream mode does not require protocol changes.

P8 changes the compute grouping after operands have already been staged into cache-backed local storage.

Validated Direct Stream coverage:

```text
Direct Stream smoke RUN_ALL with GEMM_MAC_LANES=4
Direct Stream load-store stress default clock
Direct Stream load-store stress CDC sanity
```

Important distinction:

```text
Direct Stream latency_cycles and GEMM_BUSY_CYCLES are not the same metric.
```

Direct Stream smoke may report higher control latency due to frontend integration timing, while `gemm_perf_busy_cycles` measures the GEMM core busy window.

---

## 16. DMA / AXI-Stream Compatibility

P8 does not require changes to:

```text
dma_load_engine
dma_store_engine
axis_preload_engine
axis_scratchpad_write_adapter
scratchpad owner muxes
scoreboard protocol
result bridge protocol
host traffic checker
```

Validated paths:

```text
host-primary path
DMA load A/B -> GEMM -> DMA store C
AXI-Stream preload A/B -> GEMM -> DMA store C
Direct Stream preload A/B -> GEMM -> DMA store C
```

---

## 17. Verification Plan and Closure

### P8A: Feasibility Spec

Status:

```text
PASS
```

Completion:

```text
docs/gemm_4lane_mac_feasibility_spec.md created
lane mask policy defined
effective enable / fallback policy defined
performance model defined
verification plan defined
```

### P8B: Safe Parameter Validation

Status:

```text
PASS
```

Completion:

```text
GEMM_MAC_LANES=4 can be passed through run scripts and top-level parameters.
Default full regression remained 59/59 PASS before true 4-lane RTL.
```

### P8C: 4-Lane Compute RTL Prototype

Status:

```text
PASS
```

Completion:

```text
4-lane lane-valid logic added
4-lane A/B cache operand selection added
4-product signed multiply / signed sum added
K index increment by 4 supported
fallback behavior preserved for unsupported paths
focused perf counter smoke PASS
```

### P8D: Focused Performance Profile

Status:

```text
PASS
```

Profile summary:

```text
CASE_ID | M | N | K | MACS | OUTPUTS | 1-LANE BUSY | 2-LANE BUSY | 4-LANE BUSY
100     | 1 | 1 | 1 | 1    | 1       | 43          | 43          | 43
101     | 2 | 2 | 2 | 8    | 4       | 160         | 152         | 152
105     | 2 | 3 | 4 | 24   | 6       | 305         | 275         | 265
5       | 4 | 4 | 4 | 64   | 16      | 577         | 500         | 472
400     | 4 | 4 | 4 | 64   | 16      | 575         | 500         | 472
401     | 4 | 4 | 4 | 64   | 16      | 575         | 500         | 472
402     | 4 | 4 | 4 | 64   | 16      | 575         | 500         | 472
403     | 4 | 4 | 4 | 64   | 16      | 575         | 500         | 472
```

### P8E: Direct Stream Compatibility

Status:

```text
PASS
```

Validated:

```text
Direct Stream smoke RUN_ALL
Direct Stream load-store stress
GEMM_MAC_LANES=4
full cache/preload stack enabled
UVM_ERROR=0
UVM_FATAL=0
```

### P8F: Stress / CDC Manual Subset

Status:

```text
PASS
```

Validated:

```text
DMA load-store stress default clock
DMA load-store stress CDC 10/13
AXI-Stream load-store stress default clock
AXI-Stream load-store stress CDC 10/13
Direct Stream load-store stress default clock
Direct Stream load-store stress CDC 10/13
```

### P8G: Regression Inclusion

Status:

```text
PASS
```

Representative full-regression items added:

```text
gemm_4lane_fullcache_dma_load_store_stress
gemm_4lane_fullcache_axis_stream_load_store_stress
gemm_4lane_fullcache_direct_stream_load_store_stress
```

Regression closure:

```text
TOTAL : 62
PASS  : 62
FAIL  : 0
```

---

## 18. Suggested Tcl Runs

### 18.1 4-Lane Perf Counter Smoke

```tcl
set UVM_TEST ai_accel_subsys_perf_counter_smoke_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 100
set RUN_ALL 1

set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14

set GEMM_MAC_LANES 4
set GEMM_ENABLE_B_CACHE 1
set GEMM_B_CACHE_MAX_K 4
set GEMM_B_CACHE_MAX_N 4
set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
set GEMM_ENABLE_A_ROW_CACHE 1
set GEMM_A_ROW_CACHE_MAX_K 4
set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1

do run_uvm.tcl
```

### 18.2 4-Lane Perf Profile

```tcl
set UVM_TEST ai_accel_subsys_perf_profile_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 100

set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14

set GEMM_MAC_LANES 4
set GEMM_ENABLE_B_CACHE 1
set GEMM_B_CACHE_MAX_K 4
set GEMM_B_CACHE_MAX_N 4
set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
set GEMM_ENABLE_A_ROW_CACHE 1
set GEMM_A_ROW_CACHE_MAX_K 4
set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1

do run_uvm.tcl
```

### 18.3 4-Lane Load-Store Stress

Use the same feature stack with one of:

```text
ai_accel_subsys_dma_load_store_stress_test
ai_accel_subsys_axis_stream_load_store_stress_test
ai_accel_subsys_direct_stream_load_store_stress_test
```

Default clock:

```tcl
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14
```

CDC sanity:

```tcl
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 13
```

---

## 19. Risk Analysis

### Risk 1: Incorrect Lane Masking

Possible failure:

```text
lane2 or lane3 reads beyond dim_k
```

Mitigation:

```text
guard each lane with k_idx + lane < dim_k
run K=1, K=2, and K=4 cases
```

### Risk 2: Wrong K Step / Final Detection

Possible failure:

```text
K=4 computes only one group but final detection is wrong
K=2 advances by 4 and skips finalization
```

Mitigation:

```text
centralize compute_step calculation
verify CASE_ID=100, 101, 105, 5, 400-403
```

### Risk 3: Signedness Bug

Possible failure:

```text
negative A/B operands produce wrong C
```

Mitigation:

```text
use signed lane operands and signed product sums
rely on existing scoreboard with mixed-sign matrices
```

### Risk 4: Accumulator Width Bug

Possible failure:

```text
sum of four signed products overflows temporary mac_sum before reaching accumulator
```

Mitigation:

```text
sign-extend each product to accumulator width before addition
avoid narrow intermediate expressions
```

### Risk 5: Cache Source Mismatch

Possible failure:

```text
4-lane compute reads B-cache with wrong [k][n] indexing
lane3 uses wrong column n
```

Mitigation:

```text
reuse existing 2-lane B-cache indexing convention
verify CASE_ID=105 and 4x4x4 cases
```

### Risk 6: Unsupported Config Confusion

Possible failure:

```text
GEMM_MAC_LANES=4 is set but effective path silently behaves like 2-lane
```

Mitigation:

```text
print requested/effective lane configuration
document fallback behavior
```

### Risk 7: No Visible Performance Gain

Possible cause:

```text
preload/writeback/FSM overhead dominates total busy cycles
```

Mitigation:

```text
do not require exact cycle threshold
compare profile trend
use 4x4x4 class as the primary trend signal
```

### Risk 8: Regression Growth

Possible issue:

```text
full regression becomes too heavy after adding 4-lane variants
```

Mitigation:

```text
manual stress/CDC closure first
add only three representative default-clock items to full regression
```

---

## 20. Summary

P8 is now closed as a cache-backed compute parallelism milestone.

The key result is:

```text
P7 improved operand delivery enough that a 4-lane MAC became useful.
P8 implemented that cache-backed 4-lane path without changing protocols or memory layout.
```

Final P8 validated behavior:

```text
optional GEMM_MAC_LANES=4
default off
cache-backed only for true 4-lane operation
reuse A-row cache and B-cache
preserve 1-lane / 2-lane behavior
preserve scoreboard model
preserve protocol interfaces
verify correctness first
profile second
stress/CDC third
regression inclusion last
```

P8 closure:

```text
62/62 full regression PASS
```

Recommended next milestone candidate:

```text
P9: larger GEMM dimension support / cache-size scaling
```
