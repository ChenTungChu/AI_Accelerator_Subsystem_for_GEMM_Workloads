# GEMM A-Row Cache Spec

## 1. Purpose

This document defines the P6 performance milestone for the AI Accelerator Subsystem GEMM datapath.

The project has already completed:

```text
P4: B-cache operand reuse optimization
P5: packed B-cache preload optimization

Full regression after P5:
  TOTAL : 50
  PASS  : 50
  FAIL  : 0
```

P6 focuses on reducing repeated **A operand reads** during GEMM compute.

P4 and P5 optimized the B side:

```text
P4:
  preload B[k][n] once into B-cache
  reuse B during compute

P5:
  reduce B-cache fill overhead
  use aligned 32-bit packed preload for B-cache
```

After P5, the next major memory-read inefficiency is on the A side.

For GEMM:

```text
C[m][n] = sum_k A[m][k] * B[k][n]
```

For a fixed row `m`, the same A row is reused across multiple output columns `n`:

```text
A[m][k] is reused for:
  C[m][0]
  C[m][1]
  C[m][2]
  ...
  C[m][N-1]
```

P6 introduces an optional A-row cache:

```text
for each output row m:
  preload A[m][0 .. K-1] once
  compute all C[m][n] using cached A row
```

This complements the existing B-cache:

```text
B-cache:
  reuse B across m

A-row cache:
  reuse A across n
```

---

## 2. Naming

Recommended file name:

```text
docs/gemm_a_row_cache_spec.md
```

This name is preferred because it follows the project’s GEMM-specific documentation style.

Alternative acceptable names:

```text
docs/a_row_cache_spec.md
docs/gemm_a_operand_reuse_spec.md
docs/gemm_a_row_reuse_spec.md
```

The recommended name is:

```text
docs/gemm_a_row_cache_spec.md
```

---

## 3. Baseline Before P6

### 3.1 Datapath Baseline

Current performance datapath baseline:

```text
GEMM_MAC_LANES=2
GEMM_ENABLE_B_CACHE=1
GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1
```

Current completed P5 behavior:

```text
1. Optionally preload B matrix into B-cache.
2. If packed B-cache preload is enabled and base_addr_b is aligned:
     read four B int8 elements per local 32-bit read.
3. During compute:
     read A operands from local memory path.
     read B operands from B-cache.
4. Accumulate C.
5. Write C.
6. Assert done only after final C write completion.
```

### 3.2 Current A Operand Behavior

Current A access is still compute-driven.

Conceptually, for each output element:

```text
for m in 0 .. M-1:
  for n in 0 .. N-1:
    acc = 0
    for k in 0 .. K-1:
      read A[m][k]
      read B[k][n] from B-cache
      acc += A[m][k] * B[k][n]
    write C[m][n]
```

This means the same `A[m][k]` is read repeatedly for every `n`.

For a fixed row `m`:

```text
A row length = K
number of output columns = N

Without A-row cache:
  A reads per row = K * N

With A-row cache:
  A preload reads per row = K
```

Ideal A-side read reduction:

```text
A read reduction per row = K*N - K = K*(N-1)
```

For 4x4x4:

```text
M=4, N=4, K=4

Without A-row cache:
  A reads = M * N * K = 4 * 4 * 4 = 64

With A-row cache:
  A preload reads = M * K = 4 * 4 = 16

Ideal saved A reads = 48
```

---

## 4. Problem Statement

P4 and P5 significantly reduce B-side memory traffic:

```text
P4:
  B is cached and reused during compute.

P5:
  B-cache preload is packed, reducing fill reads.
```

However, A-side memory traffic still scales with:

```text
M * N * K
```

A-row cache should reduce A-side read traffic to:

```text
M * K
```

for supported dimensions.

This is the next natural performance optimization because the A operand reuse pattern is deterministic and local to each output row.

---

## 5. P6 Design Goals

P6 must:

1. Preserve the current 50/50 full regression baseline by default.
2. Add A-row cache as an optional feature, default off.
3. Keep existing no-cache, B-cache, and packed B-cache behavior unchanged when A-row cache is disabled.
4. Support the current 2-lane K-parallel MAC datapath.
5. Support the existing B-cache and packed B-cache preload path.
6. Start with scalar A-row preload first.
7. Avoid packed A-row preload in the first implementation.
8. Avoid changing AXI, DMA, AXI-Stream, Direct Stream, or scoreboard protocols.
9. Reuse the existing GEMM local read interface.
10. Preserve signed int8 A operand behavior.
11. Preserve row-major A layout.
12. Preserve C writeback format and done semantics.
13. Validate host-primary, DMA, AXI-Stream, and Direct Stream paths.
14. Validate stress and CDC representative subsets before regression inclusion.

---

## 6. Non-Goals for First P6 Step

The first P6 implementation does not attempt to:

- implement packed A-row preload
- widen local memory interface
- add a new local memory protocol
- change A/B/C memory layout
- change C accumulation or output format
- change B-cache behavior
- change packed B-cache preload behavior
- implement 4-lane MAC
- implement tile scheduling
- implement full systolic array behavior
- increase supported GEMM dimensions beyond existing cache bounds
- add exact cycle-count pass/fail thresholds
- require scoreboard reference-model changes
- require DMA/AXI-Stream/Direct Stream protocol changes

P6 is a local GEMM datapath optimization.

---

## 7. Recommended First Target

Recommended first RTL target:

```text
P6 first RTL target = scalar A-row cache
```

Do not start with packed A reads.

Reason:

```text
A-row cache captures the main A-side reuse opportunity.
Scalar preload is easier to verify than packed preload.
The design can reuse the existing scalar A read behavior.
It avoids cross-boundary packed read issues during the first implementation.
It composes cleanly with the completed P5 packed B-cache preload.
```

Packed A-row preload can be a later follow-up:

```text
P7 candidate:
  packed A-row preload using the P5 32-bit local read window semantics
```

---

## 8. Parameterization

Add a new parameter to `gemm_top.sv`:

```systemverilog
parameter bit GEMM_ENABLE_A_ROW_CACHE = 1'b0
```

Default must be:

```systemverilog
GEMM_ENABLE_A_ROW_CACHE = 1'b0
```

Recommended effective enable:

```systemverilog
a_row_cache_active =
    GEMM_ENABLE_A_ROW_CACHE &&
    a_row_cache_dim_supported;
```

Recommended dimension support for first implementation:

```systemverilog
a_row_cache_dim_supported =
    (dim_k != 0) &&
    (int'(dim_k) <= GEMM_A_ROW_CACHE_MAX_K);
```

Recommended cache depth parameter:

```systemverilog
parameter int GEMM_A_ROW_CACHE_MAX_K = 4
```

Recommended initial defaults:

```systemverilog
parameter bit GEMM_ENABLE_A_ROW_CACHE = 1'b0;
parameter int GEMM_A_ROW_CACHE_MAX_K  = 4;
```

Recommended parameter propagation:

```text
gemm_top
ai_accel_subsys
ai_accel_subsys_uvm_top
run_uvm.tcl
run_full_uvm_regression.tcl
```

Recommended run script variables:

```tcl
set GEMM_ENABLE_A_ROW_CACHE 1
set GEMM_A_ROW_CACHE_MAX_K 4
```

Recommended cleanup in `clear_uvm_run_vars`:

```tcl
unset -nocomplain GEMM_ENABLE_A_ROW_CACHE
unset -nocomplain GEMM_A_ROW_CACHE_MAX_K
```

---

## 9. A-Row Cache Storage

### 9.1 Cache Shape

For first implementation:

```systemverilog
logic signed [A_DATA_WIDTH-1:0] a_row_cache_q [0:GEMM_A_ROW_CACHE_MAX_K-1];
logic signed [A_DATA_WIDTH-1:0] a_row_cache_d [0:GEMM_A_ROW_CACHE_MAX_K-1];
```

Cache stores one row:

```text
a_row_cache[k] = A[m][k]
```

Only the current `m_idx` row is cached.

### 9.2 Validity

Recommended cache-valid state:

```systemverilog
logic a_row_cache_valid_q, a_row_cache_valid_d;
logic [DIM_WIDTH-1:0] a_row_cache_m_q, a_row_cache_m_d;
```

Basic rule:

```text
cache is valid when:
  a_row_cache_valid_q == 1
  a_row_cache_m_q == current m_idx
```

However, because the FSM controls row transitions deterministically, the simplest first implementation can invalidate the cache whenever `m_idx` changes and preload again at the start of each row.

Recommended first policy:

```text
At job start:
  a_row_cache_valid = 0

At each new m row:
  preload A[m][0 .. K-1]
  set a_row_cache_valid = 1

When moving to next m:
  invalidate and preload next row
```

---

## 10. A Address Model

Current A layout:

```text
A[m][k] row-major
```

Address formula:

```text
A[m][k] = base_addr_a + (m * dim_k + k) * A_BYTES
```

For int8 A:

```text
A_BYTES = 1
```

Scalar A-row preload should issue reads to:

```text
base_addr_a + (m_idx * dim_k + preload_k) * A_BYTES
```

For first implementation:

```text
one local read per A row element
```

Packed A-row preload is deferred.

---

## 11. Compute Source Selection

### 11.1 Without A-Row Cache

Current compute source:

```text
A operand comes from local memory read response.
B operand comes from:
  - B-cache when B-cache active
  - local memory read response when B-cache inactive
```

### 11.2 With A-Row Cache

With A-row cache active:

```text
A operand comes from a_row_cache[k]
B operand comes from existing B path
```

For 2-lane K-parallel compute:

```text
lane0:
  A operand = a_row_cache[k]

lane1:
  A operand = a_row_cache[k+1] when lane1_valid
```

The B operand source remains unchanged:

```text
if B-cache active:
  lane0 B operand = b_cache[k][n]
  lane1 B operand = b_cache[k+1][n] when lane1_valid
else:
  use existing scalar B memory read path
```

Recommended first P6 combination:

```text
A-row cache is primarily validated with B-cache enabled.
```

The safest initial effective mode can be:

```systemverilog
a_row_cache_active =
    GEMM_ENABLE_A_ROW_CACHE &&
    GEMM_ENABLE_B_CACHE &&
    a_row_cache_dim_supported;
```

This reduces implementation risk because compute can use:

```text
A from A-row cache
B from B-cache
```

and avoid the more complex no-B-cache mode where B still needs memory reads during compute.

### 11.3 Policy Decision: Require B-Cache?

Two policies are possible.

#### Policy A: A-row cache requires B-cache

Effective enable:

```systemverilog
a_row_cache_active =
    GEMM_ENABLE_A_ROW_CACHE &&
    GEMM_ENABLE_B_CACHE &&
    a_row_cache_dim_supported;
```

Benefits:

```text
simpler compute FSM
clear performance stack:
  P4/P5 optimize B
  P6 optimizes A
avoids mixing A-cache with scalar B memory reads
lower risk
```

Limitations:

```text
A-row cache cannot be used when B-cache is disabled
```

#### Policy B: A-row cache independent of B-cache

Effective enable:

```systemverilog
a_row_cache_active =
    GEMM_ENABLE_A_ROW_CACHE &&
    a_row_cache_dim_supported;
```

Benefits:

```text
more general feature
can improve A reuse even without B-cache
```

Risks:

```text
compute FSM must still perform B memory reads
may need separate READ_B states
more interaction with existing scalar path
higher first-implementation risk
```

### 11.4 Recommended First Policy

Recommended first implementation:

```text
Policy A: A-row cache requires B-cache.
```

Reason:

```text
P6 is a performance-stack milestone after P4/P5.
The most valuable validated mode is:
  2-lane + B-cache + packed B-cache preload + A-row cache.
This keeps first RTL patch smaller and easier to debug.
```

A later enhancement can relax this requirement.

---

## 12. Suggested FSM Integration

### 12.1 Existing High-Level Flow

Current P5 high-level flow:

```text
S_IDLE
  -> optional B-cache preload
  -> compute loop
  -> write C
  -> done
```

### 12.2 P6 High-Level Flow

With A-row cache active:

```text
S_IDLE
  -> optional B-cache preload
  -> for each m:
       preload A row
       for each n:
         compute C[m][n] using cached A row and cached B
         write C[m][n]
  -> done
```

### 12.3 Recommended New States

Add A-row preload states:

```text
S_AROW_INIT
S_AROW_READ
S_AROW_WAIT
S_AROW_NEXT
```

Optional state names:

```text
S_A_ROW_INIT
S_A_ROW_READ
S_A_ROW_WAIT
S_A_ROW_NEXT
```

Use the naming style that best matches existing `gemm_top.sv` state names.

### 12.4 Recommended Flow

At start of compute for a row:

```text
if a_row_cache_active:
  S_AROW_INIT
else:
  existing compute path
```

A-row preload:

```text
S_AROW_INIT:
  arow_k = 0
  S_AROW_READ

S_AROW_READ:
  mem_rd_addr = base_addr_a + (m_idx * dim_k + arow_k)
  if mem_req_ready:
    mem_rd_en = 1
    S_AROW_WAIT

S_AROW_WAIT:
  if mem_rd_valid:
    a_row_cache[arow_k] = mem_rd_data[A_DATA_WIDTH-1:0]
    S_AROW_NEXT

S_AROW_NEXT:
  if arow_k == dim_k - 1:
    a_row_cache_valid = 1
    n_idx = 0
    k_idx = 0
    S_COMPUTE_FROM_CACHE
  else:
    arow_k++
    S_AROW_READ
```

Compute:

```text
S_COMPUTE_FROM_CACHE:
  lane0_a = a_row_cache[k_idx]
  lane1_a = a_row_cache[k_idx+1] if lane1_valid

  lane0_b = b_cache[k_idx][n_idx]
  lane1_b = b_cache[k_idx+1][n_idx] if lane1_valid

  acc += lane products
```

At end of a row:

```text
if n_idx == dim_n - 1 and row complete:
  if m_idx == dim_m - 1:
    finish
  else:
    m_idx++
    invalidate A-row cache
    S_AROW_INIT
```

---

## 13. 2-Lane Interaction

The current 2-lane datapath consumes up to two K elements per compute step.

For a given `k_idx`:

```text
lane0 valid when k_idx < dim_k
lane1 valid when k_idx + 1 < dim_k
```

With A-row cache:

```text
lane0_a = a_row_cache[k_idx]
lane1_a = a_row_cache[k_idx + 1]
```

This matches the existing B-cache lane mapping:

```text
lane0_b = b_cache[k_idx][n_idx]
lane1_b = b_cache[k_idx + 1][n_idx]
```

Expected MAC count remains:

```text
M * N * K
```

Expected output count remains:

```text
M * N
```

P6 must not change reference results.

---

## 14. Direct Stream Compatibility

Direct Stream mode uses the operand-buffer/router path for GEMM local reads.

A-row cache preload still uses the same local read interface:

```text
mem_rd_en
mem_rd_addr
mem_rd_data
mem_rd_valid
```

Therefore, P6 should be compatible with Direct Stream as long as A row scalar reads are valid through the router.

Because first P6 uses scalar A-row preload:

```text
no new Direct Stream packed-read assumption is introduced
```

This is lower risk than packed A-row preload.

Direct Stream validation is still required because:

```text
A-row preload changes read timing
A-row preload reads A before compute for each row
Direct Stream operand-buffer range decode must still route A addresses correctly
result pairing must remain correct
DMA store C must still wait for GEMM done
```

---

## 15. Scratchpad / DMA / AXI-Stream Compatibility

P6 does not require changes to:

```text
dma_load_engine
dma_store_engine
axis_preload_engine
axis_scratchpad_write_adapter
scratchpad owner muxes
scoreboard protocol
result bridge protocol
```

P6 only changes how `gemm_top` schedules local A reads.

Paths to verify:

```text
host-primary scratchpad path
DMA load A/B into scratchpad -> GEMM -> DMA store C
AXI-Stream preload A/B into scratchpad -> GEMM -> DMA store C
Direct Stream preload A/B -> GEMM -> DMA store C
```

---

## 16. Expected Performance Model

### 16.1 Scalar Compute A Reads

Without A-row cache:

```text
A reads = M * N * K
```

### 16.2 A-Row Cache Reads

With A-row cache:

```text
A preload reads = M * K
```

### 16.3 Ideal A-Read Savings

```text
saved A reads = M * K * (N - 1)
```

### 16.4 Examples

CASE_ID=100:

```text
M=1, N=1, K=1

without A-row cache:
  A reads = 1

with A-row cache:
  A preload reads = 1

saved = 0
```

CASE_ID=101:

```text
M=2, N=2, K=2

without A-row cache:
  A reads = 8

with A-row cache:
  A preload reads = 4

saved = 4
```

CASE_ID=105:

```text
M=2, N=3, K=4

without A-row cache:
  A reads = 24

with A-row cache:
  A preload reads = 8

saved = 16
```

CASE_ID=5 / 400-403:

```text
M=4, N=4, K=4

without A-row cache:
  A reads = 64

with A-row cache:
  A preload reads = 16

saved = 48
```

### 16.5 Expected Busy-Cycle Trend

Compared to P5 packed B-cache baseline:

```text
CASE_ID=100:
  little or no improvement

CASE_ID=101:
  small improvement

CASE_ID=105:
  moderate improvement

CASE_ID=5 / 400-403:
  clear improvement
```

Do not require exact cycle thresholds in the first implementation.

---

## 17. Performance Counter Requirements

Existing counters must retain their meaning:

```text
gemm_perf_busy_cycles
gemm_perf_mac_count
gemm_perf_output_count
```

With A-row cache:

```text
gemm_perf_busy_cycles:
  includes B-cache preload, A-row preload, compute, C writeback

gemm_perf_mac_count:
  expected value remains M * N * K

gemm_perf_output_count:
  expected value remains M * N
```

Recommended optional future counters:

```systemverilog
gemm_perf_a_read_count
gemm_perf_a_row_fill_count
gemm_perf_a_row_cache_hit_count
gemm_perf_a_row_cache_miss_count
```

Do not add these in the first patch unless debugging requires them.

---

## 18. Verification Plan

### 18.1 P6A: Spec

Complete when:

```text
docs/gemm_a_row_cache_spec.md exists
architecture and verification plan are defined
```

### 18.2 P6B: Safe Parameter Patch

Add:

```systemverilog
parameter bit GEMM_ENABLE_A_ROW_CACHE = 1'b0
parameter int GEMM_A_ROW_CACHE_MAX_K  = 4
```

Propagate through:

```text
gemm_top
ai_accel_subsys
ai_accel_subsys_uvm_top
run_uvm.tcl
run_full_uvm_regression.tcl
```

No functional behavior change.

Acceptance:

```text
compile PASS
50/50 regression PASS
```

### 18.3 P6C: Scalar A-Row Cache RTL Prototype

Add:

```text
A-row cache array
A-row preload FSM states
A-row preload address generation
compute source select from A-row cache
row transition invalidation / refill
```

Recommended first validation mode:

```text
GEMM_MAC_LANES=2
GEMM_ENABLE_B_CACHE=1
GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1
GEMM_ENABLE_A_ROW_CACHE=1
```

Acceptance:

```text
focused perf_counter_smoke RUN_ALL PASS
default-off 50/50 regression PASS
```

### 18.4 P6D: Focused Profile

Run:

```text
ai_accel_subsys_perf_profile_test
```

With:

```tcl
set GEMM_MAC_LANES 2
set GEMM_ENABLE_B_CACHE 1
set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
set GEMM_ENABLE_A_ROW_CACHE 1
set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14
```

Acceptance:

```text
result compare PASS
mac_count/output_count PASS
profile summary printed
busy cycles non-zero
larger cases show improvement versus P5 baseline
no UVM_ERROR / UVM_FATAL
```

### 18.5 P6E: Direct Stream Compatibility

Run:

```tcl
set UVM_TEST ai_accel_subsys_direct_stream_smoke_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 100
set RUN_ALL 1

set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14

set GEMM_MAC_LANES 2
set GEMM_ENABLE_B_CACHE 1
set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
set GEMM_ENABLE_A_ROW_CACHE 1

do run_uvm.tcl
```

Acceptance:

```text
8 cases PASS
scoreboard compare PASS
control/result pairing PASS
no UVM_ERROR / UVM_FATAL
```

### 18.6 P6F: Stress / CDC Subset

Run the three major load-store paths:

```text
DMA load-store stress
AXI-Stream load-store stress
Direct Stream load-store stress
```

For each path:

```text
default clock:
  dma_clk=10ns
  core_clk=14ns

CDC sanity:
  dma_clk=10ns
  core_clk=13ns
```

With:

```text
GEMM_MAC_LANES=2
GEMM_ENABLE_B_CACHE=1
GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1
GEMM_ENABLE_A_ROW_CACHE=1
```

Acceptance:

```text
selected stress jobs PASS
scoreboard compare PASS
control/result pairing PASS
no UVM_ERROR / UVM_FATAL
```

### 18.7 P6G: Regression Inclusion

Add a representative subset after manual closure.

Recommended first regression subset:

```text
gemm_2lane_arow_cache_dma_load_store_stress
gemm_2lane_arow_cache_axis_stream_load_store_stress
gemm_2lane_arow_cache_direct_stream_load_store_stress
```

Do not add all CDC variants immediately unless runtime is acceptable.

Expected regression total if adding 3 representative items:

```text
50 + 3 = 53
```

---

## 19. Suggested Tcl Runs

### 19.1 A-Row Cache Perf Counter Smoke

```tcl
set UVM_TEST ai_accel_subsys_perf_counter_smoke_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 100
set RUN_ALL 1

set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14

set GEMM_MAC_LANES 2
set GEMM_ENABLE_B_CACHE 1
set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
set GEMM_ENABLE_A_ROW_CACHE 1

do run_uvm.tcl
```

### 19.2 A-Row Cache Perf Profile

```tcl
set UVM_TEST ai_accel_subsys_perf_profile_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 100

set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14

set GEMM_MAC_LANES 2
set GEMM_ENABLE_B_CACHE 1
set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
set GEMM_ENABLE_A_ROW_CACHE 1

do run_uvm.tcl
```

### 19.3 A-Row Cache Direct Stream Smoke

```tcl
set UVM_TEST ai_accel_subsys_direct_stream_smoke_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 100
set RUN_ALL 1

set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14

set GEMM_MAC_LANES 2
set GEMM_ENABLE_B_CACHE 1
set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
set GEMM_ENABLE_A_ROW_CACHE 1

do run_uvm.tcl
```

### 19.4 A-Row Cache DMA Load-Store Stress

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

set GEMM_MAC_LANES 2
set GEMM_ENABLE_B_CACHE 1
set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
set GEMM_ENABLE_A_ROW_CACHE 1

do run_uvm.tcl
```

### 19.5 A-Row Cache AXI-Stream Load-Store Stress

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

set GEMM_MAC_LANES 2
set GEMM_ENABLE_B_CACHE 1
set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
set GEMM_ENABLE_A_ROW_CACHE 1

do run_uvm.tcl
```

### 19.6 A-Row Cache Direct Stream Load-Store Stress

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

set GEMM_MAC_LANES 2
set GEMM_ENABLE_B_CACHE 1
set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
set GEMM_ENABLE_A_ROW_CACHE 1

do run_uvm.tcl
```

### 19.7 CDC Variant

Use the same stress command and switch:

```tcl
set CORE_CLK_PERIOD_NS 13
do run_uvm.tcl
```

---

## 20. Risk Analysis

### Risk 1: Wrong A Row Address

Possible failure:

```text
cache fills A[k][m] or wrong row instead of A[m][k]
```

Mitigation:

```text
run CASE_ID=101, 105, 5, 400-403
compare against scoreboard
inspect first mismatch row/col if failure occurs
```

### Risk 2: Cache Not Refreshed on Row Change

Possible failure:

```text
row m=0 cache reused incorrectly for m=1
```

Mitigation:

```text
4x4 cases catch this strongly
invalidate cache when m_idx changes
add waveform debug for a_row_cache_m
```

### Risk 3: Lane1 Uses Invalid k+1

Possible failure:

```text
lane1 reads beyond dim_k for odd K
```

Mitigation:

```text
use existing lane1_valid logic
run odd/even K cases if available
CASE_ID=100/101/105/5 cover small and larger K
```

### Risk 4: Interaction with B-Cache

Possible failure:

```text
A-row cache compute path uses cached A but wrong B-cache index
```

Mitigation:

```text
keep B-cache source path unchanged
only change A source selection
run P5 packed B-cache tests with A-row cache enabled
```

### Risk 5: Direct Stream Range Decode / Timing

Possible failure:

```text
A-row preload changes the sequence of operand-buffer reads
Direct Stream router misroutes or returns wrong data
```

Mitigation:

```text
run Direct Stream smoke RUN_ALL
run Direct Stream load-store stress default and CDC
```

### Risk 6: Done Timing Regression

Possible failure:

```text
A-row preload changes state transitions and final C write completion handling
done asserts too early
```

Mitigation:

```text
preserve P4 done semantics
run DMA store readback tests
run full regression default-off and enabled representative subset
```

### Risk 7: Performance Benefit Smaller Than Expected

Possible cause:

```text
A preload overhead offsets savings for small cases
writeback or DMA dominates total latency
B-cache/P5 already removed a large portion of read traffic
```

Mitigation:

```text
correctness first
profile before adding cycle thresholds
expect CASE_ID=100 to show little/no improvement
focus on 4x4x4 class for meaningful trend
```

---

## 21. Recommended Implementation Order

Recommended patch sequence:

```text
Patch 1:
  Add GEMM_ENABLE_A_ROW_CACHE and GEMM_A_ROW_CACHE_MAX_K parameters.
  Propagate through top-level and run scripts.
  Add clear_uvm_run_vars cleanup.
  Compile and run 50/50.

Patch 2:
  Add a_row_cache_active helper and debug print.
  No FSM behavior change yet.
  Compile and run focused no-change tests.

Patch 3:
  Add A-row cache arrays and preload state registers.
  No compute source change yet if possible.
  Compile.

Patch 4:
  Add scalar A-row preload states.
  Fill cache for current m row.
  Run focused waveform/debug test.

Patch 5:
  Add compute source select:
    A from a_row_cache when active
    B from existing B-cache path
  Run perf_counter_smoke RUN_ALL.

Patch 6:
  Run default-off 50/50 regression.

Patch 7:
  Run perf_profile with A-row cache enabled.

Patch 8:
  Run Direct Stream smoke RUN_ALL.

Patch 9:
  Run stress / CDC subset.

Patch 10:
  Add representative A-row cache tests to full regression.
```

---

## 22. Acceptance Criteria

P6B safe parameter patch is complete when:

```text
GEMM_ENABLE_A_ROW_CACHE exists and defaults to 0.
Default full regression remains 50/50 PASS.
```

P6C RTL prototype is complete when:

```text
GEMM_ENABLE_A_ROW_CACHE=1 focused tests PASS.
Result compare PASS.
MAC/output counters PASS.
No UVM_ERROR / UVM_FATAL.
Default-off 50/50 regression remains PASS.
```

P6D profile step is complete when:

```text
perf_profile PASS.
larger cases show reasonable busy-cycle improvement versus P5.
```

P6F stress closure is complete when:

```text
A-row cache DMA load-store stress PASS.
A-row cache AXI-Stream load-store stress PASS.
A-row cache Direct Stream load-store stress PASS.
Selected CDC sanity PASS.
```

P6G regression closure is complete when:

```text
Selected A-row-cache subset is added to run_full_uvm_regression.tcl.
New full regression PASS.
```

---

## 23. Future Work After P6

After scalar A-row cache is stable, evaluate:

```text
packed A-row preload
A-row cache + packed A-row preload
larger K support
larger M/N/K test cases
4-lane K-parallel MAC
tile-level A/B cache scheduling
multiple A rows cached per tile
true streaming GEMM execution
systolic-style compute array
```

Recommended next candidate after scalar A-row cache:

```text
packed A-row preload
```

Reason:

```text
P5 already established 32-bit local read window semantics.
P6 scalar A-row cache establishes A reuse.
The next logical step is to reduce A-row fill cost using packed reads.
```

---

## 24. Summary

P6 is the next natural step after P5.

P4 reduced repeated B reads.

P5 reduced B-cache fill overhead.

P6 should reduce repeated A reads by caching one A row at a time.

The safest first implementation is:

```text
optional A-row cache
default off
requires B-cache for first implementation
scalar A-row preload first
no packed A read yet
correctness first
profile second
stress/CDC third
regression inclusion last
```

The current `50/50 PASS` P5 baseline gives a clean checkpoint for starting this work.
