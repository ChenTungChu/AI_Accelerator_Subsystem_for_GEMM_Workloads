# Packed A-Row Preload Spec

## 1. Purpose

This document defines the P7 performance milestone for the AI Accelerator Subsystem GEMM datapath.

The project has already completed:

```text
P4: B-cache operand reuse optimization
P5: packed B-cache preload optimization
P6: scalar A-row cache optimization

Full regression after P6:
  TOTAL : 56
  PASS  : 56
  FAIL  : 0
```

P7 focuses on reducing the remaining **A-row cache fill cost**.

P6 introduced scalar A-row cache preload:

```text
for each output row m:
  read A[m][0]
  read A[m][1]
  read A[m][2]
  read A[m][3]
  ...
  then reuse cached A row across all n columns
```

P7 changes the preload mechanism from scalar byte reads to aligned 32-bit packed reads:

```text
for each output row m:
  read one aligned 32-bit local word
  unpack up to four int8 A operands
  fill a_row_cache[k + 0 .. k + 3]
```

This milestone builds directly on:

```text
P5 packed B-cache preload:
  proved aligned 32-bit local read window semantics

P6 scalar A-row cache:
  proved A-row reuse correctness and performance benefit
```

P7 does **not** introduce a new GEMM algorithm. It only optimizes how the A-row cache is filled.

## 1.1 P7 Closure Status

P7 has now been implemented and closed.

```text
P7A: packed A-row preload spec                         PASS
P7B: safe parameter plumbing, default off              PASS
P7C: packed A-row preload RTL                          PASS
P7D: focused perf/profile compare                      PASS
P7E: Direct Stream compatibility                       PASS
P7F: stress / CDC manual subset                        PASS
P7G: representative packed A-row regression inclusion  PASS

Full regression after P7G:
  TOTAL : 59
  PASS  : 59
  FAIL  : 0
```

Representative packed A-row profile closure:

```text
CASE_ID | M | N | K | MACS | OUTPUTS | GEMM_BUSY_CYCLES
100     | 1 | 1 | 1 | 1    | 1       | 43
101     | 2 | 2 | 2 | 8    | 4       | 152
105     | 2 | 3 | 4 | 24   | 6       | 275
5       | 4 | 4 | 4 | 64   | 16      | 500
400     | 4 | 4 | 4 | 64   | 16      | 500
401     | 4 | 4 | 4 | 64   | 16      | 500
402     | 4 | 4 | 4 | 64   | 16      | 500
403     | 4 | 4 | 4 | 64   | 16      | 500
```

Compared with the P6 scalar A-row preload baseline, the 4x4x4 class improved from roughly 627 busy cycles to roughly 500 busy cycles while preserving result correctness, MAC/output counters, and zero UVM errors/fatals.

---


## 2. Recommended File Name

Recommended file name:

```text
docs/packed_a_row_preload_spec.md
```

Alternative acceptable names:

```text
docs/gemm_packed_a_row_preload_spec.md
docs/packed_a_operand_read_spec.md
docs/gemm_packed_a_operand_read_spec.md
```

Recommended name for this project:

```text
docs/packed_a_row_preload_spec.md
```

Reason:

```text
P5 already has docs/packed_operand_read_spec.md.
P7 is specifically about packed preload into A-row cache.
The name is short and directly describes the optimization.
```

---

## 3. Baseline Before P7

Current P6 performance stack:

```text
GEMM_MAC_LANES=2
GEMM_ENABLE_B_CACHE=1
GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1
GEMM_ENABLE_A_ROW_CACHE=1
GEMM_A_ROW_CACHE_MAX_K=4
```

Current P6 behavior:

```text
1. Optionally preload B into B-cache.
2. If packed B-cache preload is enabled and B base is aligned:
     fill B-cache using aligned 32-bit local reads.
3. For each output row m:
     scalar preload A[m][0 .. K-1] into A-row cache.
4. For each output column n:
     compute C[m][n] using:
       A from A-row cache
       B from B-cache
5. Write C.
6. Assert done only after final C write completion.
```

P6 profile result:

```text
CASE_ID | KIND | M | N | K | MACS | OUTPUTS | GEMM_BUSY_CYCLES
100     | 1    | 1 | 1 | 1 | 1    | 1       | 43
101     | 1    | 2 | 2 | 2 | 8    | 4       | 152
105     | 1    | 2 | 3 | 4 | 24   | 6       | 275
5       | 0    | 4 | 4 | 4 | 64   | 16      | 627
400     | 2    | 4 | 4 | 4 | 64   | 16      | 627
401     | 2    | 4 | 4 | 4 | 64   | 16      | 627
402     | 2    | 4 | 4 | 4 | 64   | 16      | 627
403     | 2    | 4 | 4 | 4 | 64   | 16      | 627
```

---

## 4. Problem Statement

P6 removes repeated A reads during compute by caching one A row per output row.

However, P6 still fills the A-row cache using scalar reads:

```text
A-row preload reads per row = K
A-row preload reads per job = M * K
```

For supported K=4 cases:

```text
P6 scalar A-row preload:
  one row needs 4 local reads

P7 packed A-row preload:
  one row needs 1 aligned 32-bit local read
```

For 4x4x4:

```text
M=4, K=4

P6 scalar A-row preload reads:
  M * K = 4 * 4 = 16

P7 packed A-row preload reads:
  M * ceil(K/4) = 4 * 1 = 4

Saved A-row fill reads:
  16 - 4 = 12
```

The goal is to reduce A-row fill overhead while preserving all P6 compute semantics.

---

## 5. P7 Design Goals

P7 must:

1. Preserve the current P6 56/56 full regression baseline by default.
2. Add packed A-row preload as an optional feature, default off.
3. Keep scalar A-row cache behavior unchanged when packed A-row preload is disabled.
4. Keep existing no-cache, B-cache, packed B-cache, and scalar A-row cache fallback behavior unchanged.
5. Reuse the existing local read interface.
6. Use aligned 32-bit local reads only.
7. Use the same byte-lane mapping proven by P5:
   ```text
   mem_rd_data[7:0]   = lowest byte address
   mem_rd_data[15:8]  = next byte address
   mem_rd_data[23:16] = next byte address
   mem_rd_data[31:24] = highest byte address in the 32-bit window
   ```
8. Preserve signed int8 A operand interpretation.
9. Preserve row-major A layout.
10. Preserve 2-lane K-parallel compute behavior.
11. Preserve B-cache and packed B-cache preload behavior.
12. Preserve C writeback format and done semantics.
13. Validate host-primary, DMA, AXI-Stream, and Direct Stream paths.
14. Validate at least one CDC representative path before regression closure.
15. Avoid exact cycle-count pass/fail thresholds in the first implementation.

---

## 6. Non-Goals

P7 does not attempt to:

- change GEMM math
- change A/B/C memory layout
- change C accumulation format
- change C writeback protocol
- widen the local memory interface
- add a new scratchpad protocol
- change DMA protocols
- change AXI-Stream protocols
- change Direct Stream protocols
- change scoreboard reference model
- add 4-lane MAC
- add tile scheduling
- add systolic-array behavior
- support unaligned packed A-row reads in the first implementation
- support arbitrary K tail handling in the first implementation
- remove scalar A-row preload fallback
- remove P6 scalar A-row cache mode

P7 is a local A-row cache fill optimization.

---

## 7. Parameterization

Add a new parameter to `gemm_top.sv`:

```systemverilog
parameter bit GEMM_ENABLE_PACKED_A_ROW_PRELOAD = 1'b0
```

Default must be:

```systemverilog
GEMM_ENABLE_PACKED_A_ROW_PRELOAD = 1'b0
```

Recommended parameter propagation:

```text
gemm_top
ai_accel_subsys
ai_accel_subsys_uvm_top
run_uvm.tcl
run_full_uvm_regression.tcl
```

Recommended run script variable:

```tcl
set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1
```

Recommended cleanup in `clear_uvm_run_vars`:

```tcl
unset -nocomplain GEMM_ENABLE_PACKED_A_ROW_PRELOAD
```

Recommended display updates:

```text
[GEMM_TOP_CFG]
  GEMM_ENABLE_PACKED_A_ROW_PRELOAD=%0d

[UVM_TOP_CFG]
  GEMM_ENABLE_PACKED_A_ROW_PRELOAD=%0d
```

---

## 8. Effective Enable Policy

### 8.1 Conservative First Implementation

Recommended first implementation policy:

```systemverilog
packed_a_row_preload_active =
    GEMM_ENABLE_PACKED_A_ROW_PRELOAD &&
    a_row_cache_active_job_q &&
    (A_BYTES == 1) &&
    (base_addr_a[1:0] == 2'b00) &&
    (dim_k[1:0] == 2'b00) &&
    (int'(dim_k) <= GEMM_A_ROW_CACHE_MAX_K);
```

Meaning:

```text
packed A-row preload is active only when:
  A-row cache is already active
  A operands are int8
  A base address is 32-bit aligned
  dim_k is a multiple of 4
  dim_k fits inside the A-row cache
```

### 8.2 Why Require dim_k Multiple of 4?

A row start address is:

```text
row_start = base_addr_a + (m * dim_k) * A_BYTES
```

For int8 A:

```text
row_start = base_addr_a + m * dim_k
```

If:

```text
base_addr_a[1:0] == 0
dim_k % 4 == 0
```

then every row start is also 32-bit aligned.

This avoids first-version complexity such as:

```text
unaligned read-window address generation
byte-offset extraction
cross-row packed preload
tail masking for arbitrary K
reading beyond the logical A matrix region
```

For the current regression-relevant performance cases:

```text
CASE_ID=105: K=4
CASE_ID=5  : K=4
CASE_ID=400: K=4
CASE_ID=401: K=4
CASE_ID=402: K=4
CASE_ID=403: K=4
```

this policy gives useful P7 coverage and keeps the patch low-risk.

### 8.3 Fallback Rule

If the packed A-row preload conditions are not met:

```text
fall back to P6 scalar A-row preload
```

For example:

```text
K=1 or K=2:
  scalar A-row preload

base_addr_a not 32-bit aligned:
  scalar A-row preload

GEMM_ENABLE_PACKED_A_ROW_PRELOAD=0:
  scalar A-row preload
```

This is important because P7 must not reduce functional coverage or create unsupported-job failures.

---

## 9. Address Model

A layout remains row-major:

```text
A[m][k] address = base_addr_a + (m * dim_k + k) * A_BYTES
```

For int8 A:

```text
A_BYTES = 1
```

P6 scalar A-row preload address:

```text
base_addr_a + (m_idx * dim_k + arow_k)
```

P7 packed A-row preload address:

```text
row_base_addr = base_addr_a + (m_idx * dim_k)

packed_read_addr = row_base_addr + arow_pack_k
```

where:

```text
arow_pack_k = 0, 4, 8, ...
```

For current `GEMM_A_ROW_CACHE_MAX_K=4`:

```text
only arow_pack_k = 0 is needed for K=4
```

Future larger K can use multiple packed reads per row.

---

## 10. Byte-Lane Mapping

Use the same little-endian byte-lane mapping as the existing packed B-cache preload path.

For an aligned 32-bit local read at address `A`:

```text
mem_rd_data[7:0]    -> byte at A + 0
mem_rd_data[15:8]   -> byte at A + 1
mem_rd_data[23:16]  -> byte at A + 2
mem_rd_data[31:24]  -> byte at A + 3
```

For row `m` and `arow_pack_k`:

```text
a_row_cache[arow_pack_k + 0] = signed'(mem_rd_data[7:0])
a_row_cache[arow_pack_k + 1] = signed'(mem_rd_data[15:8])
a_row_cache[arow_pack_k + 2] = signed'(mem_rd_data[23:16])
a_row_cache[arow_pack_k + 3] = signed'(mem_rd_data[31:24])
```

Required signedness:

```systemverilog
logic signed [A_DATA_WIDTH-1:0] a_row_cache_q [0:GEMM_A_ROW_CACHE_MAX_K-1];
```

Recommended assignment style:

```systemverilog
a_row_cache_d[int'(arow_pack_k_q) + 0] =
    signed'(mem_rd_data[7:0]);

a_row_cache_d[int'(arow_pack_k_q) + 1] =
    signed'(mem_rd_data[15:8]);

a_row_cache_d[int'(arow_pack_k_q) + 2] =
    signed'(mem_rd_data[23:16]);

a_row_cache_d[int'(arow_pack_k_q) + 3] =
    signed'(mem_rd_data[31:24]);
```

Use the existing project style for casts.

---

## 11. Storage Impact

P7 does not require new A-row cache storage.

Existing P6 storage remains:

```systemverilog
logic signed [A_DATA_WIDTH-1:0] a_row_cache_q [0:GEMM_A_ROW_CACHE_MAX_K-1];
logic signed [A_DATA_WIDTH-1:0] a_row_cache_d [0:GEMM_A_ROW_CACHE_MAX_K-1];
```

P7 adds packed-preload control state only.

Recommended new registers:

```systemverilog
logic [DIM_WIDTH-1:0] arow_pack_k_q, arow_pack_k_d;
```

Optional address registers:

```systemverilog
logic [ADDR_WIDTH-1:0] arow_pack_addr_q, arow_pack_addr_d;
logic [ADDR_WIDTH-1:0] arow_pack_end_addr_q, arow_pack_end_addr_d;
```

For the first version, using `arow_pack_k_q` plus address combinational calculation is enough.

---

## 12. FSM Integration

### 12.1 Existing P6 Flow

P6 high-level flow:

```text
S_IDLE
  -> optional B-cache preload
  -> for each m:
       scalar preload A row
       compute all n using A-row cache + B-cache
  -> done
```

P6 A-row states:

```text
S_AROW_INIT
S_AROW_READ
S_AROW_WAIT
S_AROW_NEXT
```

### 12.2 P7 Flow

P7 high-level flow:

```text
S_IDLE
  -> optional B-cache preload
  -> for each m:
       if packed A-row preload active:
           packed preload A row
       else:
           scalar preload A row
       compute all n using A-row cache + B-cache
  -> done
```

### 12.3 Recommended New States

Add separate packed A-row states:

```text
S_AROW_PACK_INIT
S_AROW_PACK_READ
S_AROW_PACK_WAIT
S_AROW_PACK_NEXT
```

Reason:

```text
keeps P6 scalar A-row preload path unchanged
makes fallback behavior explicit
simplifies debug and waveform inspection
```

### 12.4 State Transition Sketch

At the beginning of each row:

```text
S_AROW_INIT:
  if packed_a_row_preload_active:
      arow_pack_k = 0
      goto S_AROW_PACK_READ
  else:
      arow_k = 0
      goto S_AROW_READ
```

Packed read:

```text
S_AROW_PACK_READ:
  mem_rd_addr = base_addr_a + (m_idx * dim_k) + arow_pack_k

  if mem_req_ready:
      mem_rd_en = 1
      goto S_AROW_PACK_WAIT
```

Packed response:

```text
S_AROW_PACK_WAIT:
  if mem_rd_valid:
      a_row_cache[arow_pack_k + 0] = mem_rd_data[7:0]
      a_row_cache[arow_pack_k + 1] = mem_rd_data[15:8]
      a_row_cache[arow_pack_k + 2] = mem_rd_data[23:16]
      a_row_cache[arow_pack_k + 3] = mem_rd_data[31:24]
      goto S_AROW_PACK_NEXT
```

Next packed window:

```text
S_AROW_PACK_NEXT:
  if arow_pack_k + 4 >= dim_k:
      arow_pack_k = 0
      goto S_READ_A
  else:
      arow_pack_k += 4
      goto S_AROW_PACK_READ
```

Compute source stays unchanged from P6:

```text
A comes from a_row_cache
B comes from b_cache
```

---

## 13. 2-Lane Compute Interaction

P7 does not change the compute step.

For 2-lane K-parallel compute:

```text
lane0:
  A operand = a_row_cache[k_idx]
  B operand = b_cache[k_idx][n_idx]

lane1:
  A operand = a_row_cache[k_idx + 1] when lane1_valid
  B operand = b_cache[k_idx + 1][n_idx] when lane1_valid
```

P7 only changes how `a_row_cache[]` is filled before compute.

Expected counters remain:

```text
gemm_perf_mac_count    = M * N * K
gemm_perf_output_count = M * N
```

---

## 14. Direct Stream Compatibility

Direct Stream mode routes operand-buffer local reads into `gemm_top`.

P7 still uses the same local read interface:

```text
mem_rd_en
mem_rd_addr
mem_rd_data
mem_rd_valid
```

No new Direct Stream protocol is introduced.

However, Direct Stream must be revalidated because P7 changes A-row preload timing and address sequence:

```text
P6:
  multiple scalar A-row reads per row

P7:
  fewer aligned 32-bit A-row reads per row
```

Required validation:

```text
Direct Stream smoke RUN_ALL
Direct Stream load/store stress default clock
Direct Stream load/store stress CDC sanity
```

---

## 15. DMA / AXI-Stream Compatibility

P7 does not require changes to:

```text
dma_load_engine
dma_store_engine
axis_preload_engine
axis_scratchpad_write_adapter
scratchpad owner muxes
scoreboard protocol
result bridge protocol
```

P7 only changes local A-row preload scheduling inside `gemm_top`.

Required validation paths:

```text
host-primary path
DMA load A/B -> GEMM -> DMA store C
AXI-Stream preload A/B -> GEMM -> DMA store C
Direct Stream preload A/B -> GEMM -> DMA store C
```

---

## 16. Expected Performance Model

### 16.1 P6 Scalar A-Row Fill Reads

```text
A-row fill reads = M * K
```

### 16.2 P7 Packed A-Row Fill Reads

For supported aligned K multiple of 4:

```text
A-row fill reads = M * (K / 4)
```

### 16.3 Saved A-Row Fill Reads

```text
saved reads = M * K - M * (K / 4)
            = M * K * 3/4
```

### 16.4 Examples

CASE_ID=100:

```text
M=1, N=1, K=1

First P7 policy:
  K is not a multiple of 4
  fallback to scalar A-row preload

Expected trend:
  same or nearly same as P6
```

CASE_ID=101:

```text
M=2, N=2, K=2

First P7 policy:
  K is not a multiple of 4
  fallback to scalar A-row preload

Expected trend:
  same or nearly same as P6
```

CASE_ID=105:

```text
M=2, N=3, K=4

P6 scalar A-row fill reads:
  M * K = 2 * 4 = 8

P7 packed A-row fill reads:
  M * (K / 4) = 2 * 1 = 2

Saved reads:
  6
```

CASE_ID=5 / 400-403:

```text
M=4, N=4, K=4

P6 scalar A-row fill reads:
  M * K = 4 * 4 = 16

P7 packed A-row fill reads:
  M * (K / 4) = 4 * 1 = 4

Saved reads:
  12
```

### 16.5 Expected Busy-Cycle Trend

Compared to P6 scalar A-row cache baseline:

```text
CASE_ID=100:
  unchanged or nearly unchanged

CASE_ID=101:
  unchanged or nearly unchanged

CASE_ID=105:
  modest improvement

CASE_ID=5 / 400-403:
  modest improvement
```

P7 improvement is expected to be smaller than P6 because P6 removed repeated A reads across N columns, while P7 only reduces the remaining A-row fill cost.

Do not add exact cycle thresholds in the first implementation.

---

## 17. Performance Counter Requirements

Existing counters must retain their meaning:

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
gemm_perf_a_row_scalar_fill_count
gemm_perf_a_row_packed_fill_count
gemm_perf_a_row_packed_fallback_count
```

Do not add these in the first patch unless debugging requires them.

---

## 18. Verification Plan

### 18.1 P7A: Spec

Complete when:

```text
docs/packed_a_row_preload_spec.md exists
packed A-row preload policy is defined
fallback policy is defined
verification plan is defined
```

### 18.2 P7B: Safe Parameter Plumbing

Add:

```systemverilog
parameter bit GEMM_ENABLE_PACKED_A_ROW_PRELOAD = 1'b0
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
default full regression remains 56/56 PASS
```

### 18.3 P7C: Packed A-Row Preload RTL

Add:

```text
packed A-row preload effective-enable helper
packed A-row preload FSM states
packed A-row preload address generation
32-bit read response unpacking into a_row_cache[]
fallback to P6 scalar A-row preload when unsupported
```

Recommended first validation mode:

```text
GEMM_MAC_LANES=2
GEMM_ENABLE_B_CACHE=1
GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1
GEMM_ENABLE_A_ROW_CACHE=1
GEMM_ENABLE_PACKED_A_ROW_PRELOAD=1
```

Acceptance:

```text
focused perf_counter_smoke RUN_ALL PASS
default-off 56/56 regression PASS
```

### 18.4 P7D: Focused Performance Profile

Run:

```text
ai_accel_subsys_perf_profile_test
```

with packed A-row preload enabled.

Acceptance:

```text
result compare PASS
mac_count/output_count PASS
profile summary printed
busy cycles non-zero
K=4 cases show modest improvement versus P6
K=1/K=2 fallback cases remain correct
no UVM_ERROR / UVM_FATAL
```

### 18.5 P7E: Direct Stream Compatibility

Run:

```text
ai_accel_subsys_direct_stream_smoke_test RUN_ALL
```

with packed A-row preload enabled.

Acceptance:

```text
8 cases PASS
scoreboard compare PASS
control/result pairing PASS
no UVM_ERROR / UVM_FATAL
```

### 18.6 P7F: Stress / CDC Manual Subset

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
DMA load-store stress CDC
AXI-Stream load-store stress CDC
Direct Stream load-store stress CDC
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

Closure result:

```text
DMA load-store stress default       PASS
AXI-Stream load-store default       PASS
Direct Stream load-store default    PASS
DMA load-store stress CDC 10/13     PASS
AXI-Stream load-store CDC 10/13     PASS
Direct Stream load-store CDC 10/13  PASS
```

### 18.7 P7G: Regression Inclusion

Recommended minimal final P7 regression inclusion:

```text
gemm_2lane_packed_arow_dma_load_store_stress
gemm_2lane_packed_arow_axis_stream_load_store_stress
gemm_2lane_packed_arow_direct_stream_load_store_stress
```

Expected minimal regression total:

```text
current P6 total = 56
P7 representative items = +3

56 + 3 = 59
```

Optional additional focused regression items:

```text
gemm_2lane_packed_arow_perf_counter_smoke
gemm_2lane_packed_arow_perf_profile
```

If these are also added:

```text
56 + 3 + 2 = 61
```

Recommended first closure target:

```text
59/59 PASS
```

because it keeps full regression from growing too quickly while still covering the three main frontend paths.

---

## 19. Suggested Tcl Runs

### 19.1 Packed A-Row Perf Counter Smoke

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
set GEMM_B_CACHE_MAX_K 4
set GEMM_B_CACHE_MAX_N 4
set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
set GEMM_ENABLE_A_ROW_CACHE 1
set GEMM_A_ROW_CACHE_MAX_K 4
set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1

do run_uvm.tcl
```

### 19.2 Packed A-Row Perf Profile

```tcl
set UVM_TEST ai_accel_subsys_perf_profile_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 100

set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14

set GEMM_MAC_LANES 2
set GEMM_ENABLE_B_CACHE 1
set GEMM_B_CACHE_MAX_K 4
set GEMM_B_CACHE_MAX_N 4
set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
set GEMM_ENABLE_A_ROW_CACHE 1
set GEMM_A_ROW_CACHE_MAX_K 4
set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1

do run_uvm.tcl
```

### 19.3 Packed A-Row Direct Stream Smoke

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
set GEMM_B_CACHE_MAX_K 4
set GEMM_B_CACHE_MAX_N 4
set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
set GEMM_ENABLE_A_ROW_CACHE 1
set GEMM_A_ROW_CACHE_MAX_K 4
set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1

do run_uvm.tcl
```

### 19.4 Packed A-Row DMA Load-Store Stress

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
set GEMM_B_CACHE_MAX_K 4
set GEMM_B_CACHE_MAX_N 4
set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
set GEMM_ENABLE_A_ROW_CACHE 1
set GEMM_A_ROW_CACHE_MAX_K 4
set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1

do run_uvm.tcl
```

### 19.5 Packed A-Row AXI-Stream Load-Store Stress

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
set GEMM_B_CACHE_MAX_K 4
set GEMM_B_CACHE_MAX_N 4
set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
set GEMM_ENABLE_A_ROW_CACHE 1
set GEMM_A_ROW_CACHE_MAX_K 4
set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1

do run_uvm.tcl
```

### 19.6 Packed A-Row Direct Stream Load-Store Stress

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
set GEMM_B_CACHE_MAX_K 4
set GEMM_B_CACHE_MAX_N 4
set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
set GEMM_ENABLE_A_ROW_CACHE 1
set GEMM_A_ROW_CACHE_MAX_K 4
set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1

do run_uvm.tcl
```

### 19.7 Packed A-Row Direct Stream CDC

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

set GEMM_MAC_LANES 2
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

## 20. Risk Analysis

### Risk 1: Wrong Byte-Lane Mapping

Possible failure:

```text
A[k] gets mem_rd_data[15:8] instead of [7:0]
A[k+1] gets wrong lane
```

Mitigation:

```text
reuse P5 packed read lane convention
run CASE_ID=105 and 4x4x4 cases
compare against scoreboard
```

### Risk 2: Signedness Bug

Possible failure:

```text
negative int8 A values are interpreted as positive
```

Mitigation:

```text
assign into signed A_DATA_WIDTH cache entries
run existing variable/fixed cases with mixed operand signs
```

### Risk 3: Row Alignment Bug

Possible failure:

```text
row m=1 starts at unaligned address but packed path still used
```

Mitigation:

```text
first P7 policy requires dim_k % 4 == 0 and base_addr_a aligned
fallback to scalar otherwise
```

### Risk 4: Incorrect Fallback

Possible failure:

```text
K=1 or K=2 incorrectly enters packed path
```

Mitigation:

```text
CASE_ID=100 and 101 must pass
wave/debug packed_a_row_preload_active
```

### Risk 5: Cache Index Overflow

Possible failure:

```text
a_row_cache[arow_pack_k+3] writes beyond GEMM_A_ROW_CACHE_MAX_K
```

Mitigation:

```text
gate packed path with dim_k <= GEMM_A_ROW_CACHE_MAX_K
only increment in groups of 4
guard array writes if needed
```

### Risk 6: Direct Stream Read Sequence Change

Possible failure:

```text
Direct Stream router expects scalar read sequence timing
packed read sequence exposes timing bug
```

Mitigation:

```text
run Direct Stream smoke RUN_ALL
run Direct Stream load/store stress default and CDC
```

### Risk 7: No Visible Performance Improvement

Possible cause:

```text
A-row fill is now a small fraction of total runtime
writeback or frontend preload dominates
```

Mitigation:

```text
do not require exact cycle threshold
compare profile trend against P6
expect larger K=4 cases to improve more than K=1/K=2
```

---

## 21. Recommended Implementation Order

Recommended patch sequence:

```text
Patch 1:
  Add GEMM_ENABLE_PACKED_A_ROW_PRELOAD parameter.
  Propagate through top-level and run scripts.
  Add clear_uvm_run_vars cleanup.
  Compile and run 56/56.

Patch 2:
  Add packed_a_row_preload_active helper and config display.
  No FSM behavior change yet.
  Compile and run focused no-change tests.

Patch 3:
  Add packed A-row FSM states and registers.
  Keep scalar fallback intact.
  Compile.

Patch 4:
  Implement packed A-row preload address generation.
  Use aligned row_start + arow_pack_k.

Patch 5:
  Implement 32-bit response unpack into a_row_cache[].
  Run focused smoke with waveform/debug if needed.

Patch 6:
  Run default-off 56/56 regression.

Patch 7:
  Run packed A-row enabled perf_counter_smoke RUN_ALL.

Patch 8:
  Run packed A-row enabled perf_profile.

Patch 9:
  Run Direct Stream smoke RUN_ALL.

Patch 10:
  Run DMA / AXI-Stream / Direct Stream stress default clock.

Patch 11:
  Run Direct Stream stress CDC.

Patch 12:
  Add representative packed A-row items to full regression.
```

---

## 22. Acceptance Criteria

P7B safe parameter patch is complete when:

```text
GEMM_ENABLE_PACKED_A_ROW_PRELOAD exists and defaults to 0.
Default full regression remains 56/56 PASS.
```

P7C RTL prototype is complete when:

```text
GEMM_ENABLE_PACKED_A_ROW_PRELOAD=1 focused tests PASS.
Result compare PASS.
MAC/output counters PASS.
K=1/K=2 scalar fallback cases PASS.
K=4 packed cases PASS.
No UVM_ERROR / UVM_FATAL.
Default-off 56/56 regression remains PASS.
```

P7D profile step is complete when:

```text
perf_profile PASS.
K=4 cases show reasonable busy-cycle improvement versus P6.
K=1/K=2 fallback cases remain correct.
```

P7F stress closure is complete when:

```text
packed A-row DMA load-store stress PASS.
packed A-row AXI-Stream load-store stress PASS.
packed A-row Direct Stream load-store stress PASS.
selected CDC sanity PASS.
```

P7G regression closure is complete when:

```text
Selected packed A-row representative items are added to run_full_uvm_regression.tcl.
New full regression PASS.
```

Achieved closure target:

```text
TOTAL : 59
PASS  : 59
FAIL  : 0
```

---

## 23. Future Work After P7

After packed A-row preload is stable, evaluate:

```text
support unaligned packed A-row preload
support K tails not divisible by 4
increase GEMM_A_ROW_CACHE_MAX_K beyond 4
support larger M/N/K cases
add optional A-row fill counters
evaluate 4-lane MAC
evaluate tile-level A/B cache scheduling
evaluate multiple A rows cached per tile
evaluate true streaming GEMM execution
```

Recommended next candidate after P7:

```text
P8: 4-lane MAC feasibility study
```

But only after confirming whether the memory/preload path can supply enough operands to justify 4-lane compute.

---

## 24. Summary

P7 is the natural next step after P6.

P5 proved packed 32-bit local reads for B-cache fill.

P6 proved A-row cache reuse.

P7 combines those ideas:

```text
use aligned 32-bit reads to fill the A-row cache faster
```

The safest first implementation is:

```text
optional packed A-row preload
default off
requires A-row cache
requires int8 A
requires base_addr_a 32-bit aligned
requires dim_k multiple of 4
fallback to scalar A-row preload otherwise
no compute-path change
no protocol change
correctness first
profile second
stress/CDC third
regression inclusion last
```

P7 has closed cleanly with a `59/59 PASS` full regression baseline.
