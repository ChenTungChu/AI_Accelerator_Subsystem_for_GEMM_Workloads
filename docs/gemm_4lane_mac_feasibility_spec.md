# GEMM 4-Lane MAC Feasibility Spec

## 1. Purpose

This document defines the **P8 feasibility milestone** for extending the AI Accelerator Subsystem GEMM compute datapath from the current 1-lane / 2-lane MAC model toward a possible **4-lane MAC** mode.

The project has already completed the memory-side and operand-reuse milestones:

```text
P4: B-cache operand reuse optimization
P5: packed B-cache preload optimization
P6: scalar A-row cache optimization
P7: packed A-row preload optimization
```

Current P7 closure status:

```text
Full regression after P7:
  TOTAL : 59
  PASS  : 59
  FAIL  : 0
```

P8 is the first milestone that revisits the **compute-side parallelism** after the operand delivery path has been improved.

The goal of P8A is not to immediately modify RTL. The goal is to decide whether a 4-lane MAC mode is architecturally reasonable, what constraints are required, and how it should be verified without destabilizing the existing P7 baseline.

---

## 2. Recommended File Name

Recommended file name:

```text
docs/gemm_4lane_mac_feasibility_spec.md
```

Reason:

```text
P8A is a feasibility and architecture-planning step.
The document should not imply that 4-lane RTL is already implemented.
```

Alternative acceptable names:

```text
docs/gemm_4lane_mac_spec.md
docs/gemm_mac_lanes_4_spec.md
docs/gemm_compute_parallelism_spec.md
```

Recommended name for this project:

```text
docs/gemm_4lane_mac_feasibility_spec.md
```

---

## 3. Baseline Before P8

The current optimized P7 stack is:

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

The P7 stack has already reduced memory-side bottlenecks enough that a compute-side expansion can now be evaluated more meaningfully.

---

## 4. Problem Statement

The current P7 compute datapath supports a 2-lane K-parallel MAC mode.

For each output element:

```text
C[m][n] = sum over k of A[m][k] * B[k][n]
```

With 2-lane MAC:

```text
K step width = 2
compute groups per output = ceil(K / 2)
```

For the current K=4 performance cases:

```text
2-lane compute groups per output = ceil(4 / 2) = 2
```

A 4-lane MAC mode would target:

```text
K step width = 4
compute groups per output = ceil(K / 4)
```

For K=4:

```text
4-lane compute groups per output = ceil(4 / 4) = 1
```

Therefore, for K=4 cases, a 4-lane MAC can theoretically reduce compute groups per output from 2 to 1.

However, a wider MAC only helps if the operand delivery path can supply:

```text
A[m][k+0], A[m][k+1], A[m][k+2], A[m][k+3]
B[k+0][n], B[k+1][n], B[k+2][n], B[k+3][n]
```

in the same compute step.

That is why P8 should depend on the already-completed cache stack:

```text
B-cache
packed B-cache preload
A-row cache
packed A-row preload
```

---

## 5. P8 Design Goals

P8 should:

1. Preserve the current P7 full regression baseline by default.
2. Keep `GEMM_MAC_LANES=4` optional and non-default.
3. Avoid changing the GEMM algorithm.
4. Avoid changing A/B/C memory layout.
5. Avoid changing DMA / AXI-Stream / Direct Stream protocols.
6. Reuse the existing B-cache and A-row cache storage.
7. Keep MAC/output counters semantically unchanged.
8. Support correct lane masking for K tails.
9. Keep 1-lane and 2-lane behavior unchanged.
10. Keep full regression growth controlled by adding only representative 4-lane items.
11. Focus first implementation on correctness and feasibility, not exact cycle thresholds.
12. Treat 4-lane mode as cache-backed in the first implementation.

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
- replace the existing 2-lane mode

P8 is a compute datapath feasibility step.

---

## 7. Parameterization Strategy

### 7.1 Existing Parameter

The project already uses:

```systemverilog
parameter int GEMM_MAC_LANES = 1
```

The existing 2-lane work already validated:

```text
GEMM_MAC_LANES=2
```

P8 should extend the supported values to:

```text
GEMM_MAC_LANES = 1, 2, or 4
```

### 7.2 Default Policy

Do not change the default.

Recommended default remains:

```systemverilog
parameter int GEMM_MAC_LANES = 1
```

Reason:

```text
Existing default-off regression behavior must remain stable.
4-lane mode should be opt-in only.
```

### 7.3 Suggested Compile-Time Guard

Add a defensive elaboration-time check in simulation-oriented RTL:

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

If the project avoids `initial $fatal` in RTL, this can instead be handled by generate-time assertions or testbench checks.

---

## 8. Effective Enable Policy

### 8.1 First Implementation Policy

For the first P8 implementation, 4-lane compute should be considered active only when the job can use the cache-backed operand path:

```text
four_lane_compute_active =
    (GEMM_MAC_LANES == 4) &&
    B-cache active &&
    A-row cache active &&
    dim_k <= GEMM_A_ROW_CACHE_MAX_K &&
    dim_k <= GEMM_B_CACHE_MAX_K
```

Recommended stricter first implementation for performance validation:

```text
GEMM_MAC_LANES=4
GEMM_ENABLE_B_CACHE=1
GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1
GEMM_ENABLE_A_ROW_CACHE=1
GEMM_ENABLE_PACKED_A_ROW_PRELOAD=1
GEMM_A_ROW_CACHE_MAX_K >= 4
GEMM_B_CACHE_MAX_K >= 4
```

Reason:

```text
The one-read-at-a-time local memory interface cannot naturally feed four A/B operands
directly from scratchpad every compute step.

The P7 cache stack can.
```

### 8.2 Fallback Policy

There are two possible fallback policies.

#### Option A: Strict 4-Lane Mode

If `GEMM_MAC_LANES=4` is requested but cache-backed 4-lane conditions are not met, fail fast in simulation.

Pros:

```text
prevents misleading performance results
makes configuration mistakes visible
```

Cons:

```text
less flexible for mixed regression cases
requires tests to avoid unsupported combinations
```

#### Option B: Effective-Lane Fallback

If `GEMM_MAC_LANES=4` is requested but cache-backed 4-lane conditions are not met, use the existing 2-lane or scalar path.

Pros:

```text
preserves correctness
keeps unsupported cases from failing
easier for mixed CASE_ID regression
```

Cons:

```text
performance interpretation becomes less obvious
GEMM_MAC_LANES=4 does not always mean 4-lane compute was used
```

Recommended first P8 policy:

```text
Use effective-lane fallback for correctness,
but expose clear config/log messages so waveform and logs show whether
4-lane compute was actually active.
```

Suggested display:

```text
[GEMM_TOP_CFG]
  GEMM_MAC_LANES=4
  GEMM_4LANE_EFFECTIVE_POLICY=cache_backed
```

Optional future counter:

```text
gemm_perf_4lane_active_output_count
```

Do not add this counter in the first patch unless debug requires it.

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
  first compute group:
    lane0 valid
    lane1 invalid
    lane2 invalid
    lane3 invalid

K=2:
  first compute group:
    lane0 valid
    lane1 valid
    lane2 invalid
    lane3 invalid

K=3:
  first compute group:
    lane0 valid
    lane1 valid
    lane2 valid
    lane3 invalid

K=4:
  first compute group:
    lane0 valid
    lane1 valid
    lane2 valid
    lane3 valid

K=5:
  first compute group:
    lane0..3 valid
  second compute group:
    lane0 valid
    lane1..3 invalid
```

For the current P8 first target, most meaningful coverage is K=4 because current cache max values are 4.

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

Each lane must be guarded:

```text
only read/use a_row_cache[k_idx + lane] if lane is valid
```

### 10.2 B Operand Source

In cache-backed 4-lane mode:

```text
B lane0 = b_cache[k_idx + 0][n_idx]
B lane1 = b_cache[k_idx + 1][n_idx]
B lane2 = b_cache[k_idx + 2][n_idx]
B lane3 = b_cache[k_idx + 3][n_idx]
```

Each lane must be guarded:

```text
only read/use b_cache[k_idx + lane][n_idx] if lane is valid
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

The final result remains:

```text
C[m][n] = sum over K of A[m][k] * B[k][n]
```

No scoreboard reference model change should be required because the math result does not change.

---

## 11. Signedness and Width Requirements

P8 must preserve existing signed int8 behavior.

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

The P8 patch should follow the same signedness conventions already proven by:

```text
P6 scalar A-row cache
P7 packed A-row preload
P4/P5 B-cache paths
```

---

## 12. FSM Integration Model

### 12.1 Current P7 High-Level Flow

Current P7 flow:

```text
S_IDLE
  -> optional B-cache preload
  -> for each output row m:
       optional packed A-row preload
       compute all n using A-row cache + B-cache
  -> write C
  -> done
```

### 12.2 P8 Flow

P8 should not add new high-level scheduling states if avoidable.

Recommended P8 flow:

```text
same P7 FSM
same B-cache preload
same A-row preload
same C writeback
only modify compute step to support 4-lane K stride
```

### 12.3 K Step Update

For 2-lane mode:

```text
k_idx_next = k_idx + 2
done when k_idx + 2 >= dim_k
```

For 4-lane mode:

```text
k_idx_next = k_idx + 4
done when k_idx + 4 >= dim_k
```

General form:

```text
active_lanes = effective lane count
k_idx_next = k_idx + active_lanes
done when k_idx + active_lanes >= dim_k
```

For simplicity, first RTL patch may keep explicit branches:

```text
if four_lane_active:
    step = 4
else if two_lane_active:
    step = 2
else:
    step = 1
```

This is easier to review and debug than a fully generic lane loop.

---

## 13. Expected Performance Model

### 13.1 Compute Groups Per Output

```text
compute_groups_per_output = ceil(K / active_lanes)
```

For K=4:

```text
1-lane: ceil(4 / 1) = 4 groups
2-lane: ceil(4 / 2) = 2 groups
4-lane: ceil(4 / 4) = 1 group
```

### 13.2 Total Compute Groups

```text
total_compute_groups = M * N * ceil(K / active_lanes)
```

For 4x4x4:

```text
M = 4
N = 4
K = 4

2-lane compute groups = 4 * 4 * 2 = 32
4-lane compute groups = 4 * 4 * 1 = 16

Saved compute groups = 16
```

### 13.3 Expected Busy-Cycle Trend

For P7 4x4x4 class:

```text
P7 2-lane packed A-row baseline:
  GEMM_BUSY_CYCLES = 500
```

P8 4-lane expected trend:

```text
4x4x4 class should improve versus 500 busy cycles,
but exact threshold should not be used in first implementation.
```

Reason:

```text
GEMM_BUSY_CYCLES includes preload, compute, C writeback, and FSM overhead.
Even if compute groups are reduced, non-compute overhead remains.
```

For K=1/K=2 cases:

```text
K=1:
  4-lane has no real compute parallelism benefit over 1-lane for a single product

K=2:
  4-lane has no real benefit over 2-lane for two products

K=4:
  4-lane can reduce compute groups relative to 2-lane
```

Therefore, P8 performance expectations should focus on K=4 cases.

---

## 14. Performance Counter Requirements

Existing counters must retain their meaning:

```text
gemm_perf_busy_cycles:
  counts the full GEMM busy window

gemm_perf_mac_count:
  still equals M * N * K

gemm_perf_output_count:
  still equals M * N
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

A correct 4-lane implementation must still report:

```text
mac_count    = 64
output_count = 16
```

Optional future counters:

```text
gemm_perf_compute_group_count
gemm_perf_4lane_group_count
gemm_perf_lane0_valid_count
gemm_perf_lane1_valid_count
gemm_perf_lane2_valid_count
gemm_perf_lane3_valid_count
```

Do not add these in the first P8 patch unless debug requires them.

---

## 15. Direct Stream Compatibility

Direct Stream mode should not require protocol changes.

P8 changes the compute grouping after operands have already been staged into cache-backed local storage.

Required Direct Stream validation:

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

P8 should not require changes to:

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

Required validation paths:

```text
host-primary path
DMA load A/B -> GEMM -> DMA store C
AXI-Stream preload A/B -> GEMM -> DMA store C
Direct Stream preload A/B -> GEMM -> DMA store C
```

---

## 17. Verification Plan

### 17.1 P8A: Feasibility Spec

Complete when:

```text
docs/gemm_4lane_mac_feasibility_spec.md exists
lane mask policy is defined
effective enable / fallback policy is defined
performance model is defined
verification plan is defined
```

### 17.2 P8B: Safe Parameter Validation

Because `GEMM_MAC_LANES` already exists, P8B should confirm that:

```text
GEMM_MAC_LANES=4 can be passed through run scripts and top-level parameters.
Default full regression remains 59/59 PASS.
```

If 4-lane is not yet functionally implemented, P8B can still add:

```text
supported-value checks
config display updates
safe default-off behavior
```

Acceptance:

```text
compile PASS
default full regression remains 59/59 PASS
```

### 17.3 P8C: 4-Lane Compute RTL Prototype

Add:

```text
4-lane lane-valid logic
4-lane A/B cache operand selection
4-product signed multiply
4-product signed sum
K index increment by 4
final-K detection for 4-lane mode
fallback to existing 2-lane / scalar behavior
```

Acceptance:

```text
focused perf_counter_smoke RUN_ALL PASS
MAC/output counters PASS
result compare PASS
no UVM_ERROR / UVM_FATAL
```

### 17.4 P8D: Focused Performance Profile

Run:

```text
ai_accel_subsys_perf_profile_test
```

with 4-lane mode enabled and the P7 cache stack enabled.

Acceptance:

```text
result compare PASS
mac_count/output_count PASS
profile summary printed
K=4 cases improve versus P7 500-cycle class
K=1/K=2 cases remain correct
no exact cycle threshold required
no UVM_ERROR / UVM_FATAL
```

### 17.5 P8E: Direct Stream Compatibility

Run:

```text
ai_accel_subsys_direct_stream_smoke_test RUN_ALL
```

with 4-lane mode enabled.

Acceptance:

```text
8 cases PASS
scoreboard compare PASS
control/result pairing PASS
no UVM_ERROR / UVM_FATAL
```

### 17.6 P8F: Stress / CDC Manual Subset

Run the three major load-store paths:

```text
DMA load-store stress
AXI-Stream load-store stress
Direct Stream load-store stress
```

Default clock:

```text
dma_clk=10ns
core_clk=14ns
```

CDC sanity:

```text
dma_clk=10ns
core_clk=13ns
```

Acceptance:

```text
selected stress jobs PASS
scoreboard compare PASS
control/result pairing PASS
no UVM_ERROR / UVM_FATAL
```

### 17.7 P8G: Regression Inclusion

Recommended minimal final P8 regression inclusion:

```text
gemm_4lane_dma_load_store_stress
gemm_4lane_axis_stream_load_store_stress
gemm_4lane_direct_stream_load_store_stress
```

Expected minimal regression total:

```text
current P7 total = 59
P8 representative items = +3

59 + 3 = 62
```

Optional additional focused regression items:

```text
gemm_4lane_perf_counter_smoke
gemm_4lane_perf_profile
```

If these are also added:

```text
59 + 3 + 2 = 64
```

Recommended first closure target:

```text
62/62 PASS
```

because it keeps full regression growth controlled while covering the three primary frontend paths.

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

### 18.3 4-Lane Direct Stream Smoke

```tcl
set UVM_TEST ai_accel_subsys_direct_stream_smoke_test
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

### 18.4 4-Lane DMA Load-Store Stress

```tcl
set UVM_TEST ai_accel_subsys_dma_load_store_stress_test
set ENABLE_RESULT_CHECK 1

set STORE_STRESS_JOB_COUNT 8
set STORE_STRESS_SEED 20260502
set STORE_STRESS_RANDOM 1
set STORE_STRESS_GAP_CYCLES 10

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

### 18.5 4-Lane AXI-Stream Load-Store Stress

```tcl
set UVM_TEST ai_accel_subsys_axis_stream_load_store_stress_test
set ENABLE_RESULT_CHECK 1

set AXIS_STRESS_JOB_COUNT 8
set AXIS_STRESS_SEED 20260502
set AXIS_STRESS_RANDOM 1
set AXIS_STRESS_GAP_CYCLES 10

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

### 18.6 4-Lane Direct Stream Load-Store Stress

```tcl
set UVM_TEST ai_accel_subsys_direct_stream_load_store_stress_test
set ENABLE_RESULT_CHECK 1

set DS_STRESS_JOB_COUNT 8
set DS_STRESS_SEED 20260502
set DS_STRESS_RANDOM 1
set DS_STRESS_GAP_CYCLES 10

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

### 18.7 4-Lane CDC Sanity Example

```tcl
set UVM_TEST ai_accel_subsys_direct_stream_load_store_stress_test
set ENABLE_RESULT_CHECK 1

set DS_STRESS_JOB_COUNT 8
set DS_STRESS_SEED 20260502
set DS_STRESS_RANDOM 1
set DS_STRESS_GAP_CYCLES 10

set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 13

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
wave inspect CASE_ID=105 and 4x4x4
```

### Risk 6: Unsupported Config Confusion

Possible failure:

```text
GEMM_MAC_LANES=4 is set but effective path silently behaves like 2-lane
```

Mitigation:

```text
print config policy
optionally add debug counters or one-time log
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
consider optional compute-group counter if needed
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

## 20. Recommended Implementation Order

Recommended P8 patch sequence:

```text
P8A:
  Create docs/gemm_4lane_mac_feasibility_spec.md.

P8B:
  Validate GEMM_MAC_LANES=4 plumbing.
  Add supported-value checks if needed.
  Keep behavior default-off.
  Run full regression 59/59.

P8C:
  Add 4-lane compute helpers:
    lane valid bits
    lane operand selection
    signed products
    mac_sum
    k-step=4 update
  Keep 1-lane and 2-lane paths unchanged.

P8D:
  Run focused perf_counter_smoke and perf_profile.

P8E:
  Run Direct Stream smoke RUN_ALL.

P8F:
  Run DMA / AXI-Stream / Direct Stream stress default clock.
  Run selected CDC sanity.

P8G:
  Add representative 4-lane items to full regression.
  Close at recommended target 62/62 PASS.
```

---

## 21. Acceptance Criteria

P8A feasibility planning is complete when:

```text
4-lane lane mask policy is defined.
Cache-backed source model is defined.
Performance model is defined.
Verification plan is defined.
```

P8B safe plumbing is complete when:

```text
GEMM_MAC_LANES=4 can be passed safely.
Default full regression remains 59/59 PASS.
```

P8C RTL prototype is complete when:

```text
4-lane focused smoke PASS.
K=1/K=2/K=4 cases PASS.
MAC/output counters remain correct.
No UVM_ERROR / UVM_FATAL.
```

P8D profile step is complete when:

```text
perf_profile PASS.
K=4 cases show reasonable improvement versus P7.
No exact cycle threshold required.
```

P8F stress closure is complete when:

```text
4-lane DMA load-store stress PASS.
4-lane AXI-Stream load-store stress PASS.
4-lane Direct Stream load-store stress PASS.
selected CDC sanity PASS.
```

P8G regression closure is complete when:

```text
Selected 4-lane representative items are added to run_full_uvm_regression.tcl.
New full regression PASS.
```

Recommended minimal closure target:

```text
TOTAL : 62
PASS  : 62
FAIL  : 0
```

---

## 22. Future Work After P8

After 4-lane MAC is evaluated, possible next directions:

```text
increase GEMM_A_ROW_CACHE_MAX_K beyond 4
increase GEMM_B_CACHE_MAX_K / GEMM_B_CACHE_MAX_N
support larger M/N/K test cases
add compute-group performance counters
add true tile-level scheduling
cache multiple A rows per tile
cache multiple B columns per tile
evaluate 8-lane MAC feasibility
evaluate systolic-array style datapath
evaluate memory bandwidth bottlenecks after 4-lane
```

A likely next milestone after P8:

```text
P9: larger GEMM dimension support / cache-size scaling
```

But this should only be decided after the P8 profile shows whether 4-lane compute provides meaningful improvement.

---

## 23. Summary

P8 should be treated as a feasibility-driven compute parallelism milestone.

The key idea is:

```text
P7 improved operand delivery enough that a 4-lane MAC is now worth evaluating.
```

The safest first P8 implementation is:

```text
optional GEMM_MAC_LANES=4
default off
cache-backed only
reuse A-row cache and B-cache
preserve 1-lane / 2-lane behavior
preserve scoreboard model
preserve protocol interfaces
verify correctness first
profile second
stress/CDC third
regression inclusion last
```

Recommended P8 closure target:

```text
62/62 full regression PASS
```
