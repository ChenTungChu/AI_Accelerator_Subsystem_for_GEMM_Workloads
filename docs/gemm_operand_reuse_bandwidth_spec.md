# GEMM Operand Reuse / Bandwidth Optimization Spec

## 1. Purpose

This document records the completed P4 GEMM operand-reuse milestone and the completed P5 packed B-cache preload milestone after the 2-lane MAC datapath and 2-lane stress / CDC hardening work.

Current baseline:

```text
P2: 2-lane GEMM MAC datapath prototype completed
P3: 2-lane stress / CDC hardening completed
P4: B-cache operand reuse optimization completed
P5: packed B-cache preload optimization completed

Full regression:
  TOTAL : 50
  PASS  : 50
  FAIL  : 0
```

P4 reduces operand-memory bandwidth pressure by caching the B matrix once per GEMM job and reusing it during compute.

The key observation is:

```text
P2 increased MAC parallelism,
but the GEMM core still performed many repeated B operand reads.
```

The implemented P4 target is a low-risk, optional B-operand cache prototype. The implemented P5 target improves B-cache fill bandwidth by adding optional aligned packed B-cache preload.

---

---

## 1A. P4 Closure Summary

P4 is complete.

Implemented RTL behavior:

```text
GEMM_ENABLE_B_CACHE=0:
    preserve the no-cache P3 baseline

GEMM_ENABLE_B_CACHE=1 and supported dimensions:
    preload B[k][n] into a local B cache
    compute lane0 B from b_cache[k][n]
    compute lane1 B from b_cache[k+1][n] when lane1_valid
```

Supported cache dimensions for the current milestone:

```text
GEMM_B_CACHE_MAX_K = 4
GEMM_B_CACHE_MAX_N = 4
```

Current supported case set:

```text
CASE_ID=100     dim=(1,1,1)
CASE_ID=101     dim=(2,2,2)
CASE_ID=105     dim=(2,3,4)
CASE_ID=5       dim=(4,4,4)
CASE_ID=400-403 dim=(4,4,4) with shifted legal base addresses
```

Important correctness fix found during P4D:

```text
gemm_top.done now asserts only after the final C write completion,
not merely after the final C write request is accepted.
```

This prevents a following DMA store from reading C before the final GEMM write is visible.

Validation completed:

```text
P4C: B-cache compute bypass / perf profile              PASS
P4D: B-cache Direct Stream compatibility                PASS
P4E: B-cache DMA / AXIS / Direct Stream stress          PASS
P4E: B-cache CDC subset at dma/core=10ns/13ns           PASS
P4F: Representative B-cache tests added to regression   PASS
```

Final regression:

```text
TOTAL : 47
PASS  : 47
FAIL  : 0
```


## 1B. P5 Packed B-Cache Preload Closure Summary

P5 is complete.

Implemented RTL behavior:

```text
GEMM_ENABLE_PACKED_BCACHE_PRELOAD=0:
    preserve the scalar P4 B-cache preload path

GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1 and base_addr_b[1:0] == 0:
    issue aligned 32-bit local reads during B-cache preload
    unpack up to four int8 B operands from mem_rd_data[31:0]
    fill b_cache[k][n] from packed byte lanes

GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1 and base_addr_b[1:0] != 0:
    fallback to scalar P4 B-cache preload
```

Important local-read contract update:

```text
gemm_scratchpad_adapter now returns a 32-bit byte window in mem_rd_data[31:0].
Existing scalar reads remain compatible because mem_rd_data[7:0] is still the requested byte.
```

P5 focused profile:

```text
CASE_ID | P4 B-cache | P5 packed B-cache | Change
100     | 24         | 43                | +19
101     | 189        | 182               | -7
105     | 485        | 415               | -70
5       | 1147       | 1060              | -87
400     | 1146       | 1060              | -86
401     | 1147       | 1060              | -87
402     | 1147       | 1060              | -87
403     | 1146       | 1060              | -86
```

P5 validation completed:

```text
P5A: packed operand read spec                         PASS
P5B: safe parameter plumbing                           PASS
P5C: packed B-cache preload RTL                        PASS
P5D: focused perf/profile compare                      PASS
P5E: Direct Stream compatibility                       PASS
P5F: DMA / AXIS / Direct Stream stress and CDC subset  PASS
P5G: Representative packed-read regression added       PASS
```

Final P5 regression:

```text
TOTAL : 50
PASS  : 50
FAIL  : 0
```


## 2. Current Baseline

### 2.1 Current 2-Lane GEMM Datapath

The current `GEMM_MAC_LANES=2` datapath processes two K terms per MAC group:

```text
lane0: A[m][k+0] * B[k+0][n]
lane1: A[m][k+1] * B[k+1][n], if k+1 < K
```

Current conceptual compute path:

```text
read A0
read B0
read A1, if valid
read B1, if valid
MAC
```

The design is correctness-first and preserves the original local memory interface:

```systemverilog
output logic                  mem_rd_en;
output logic [ADDR_WIDTH-1:0] mem_rd_addr;
input  logic [31:0]           mem_rd_data;
input  logic                  mem_rd_valid;
```

### 2.2 Current Performance Status

Pre-P4 2-lane no-cache profile baseline:

```text
CASE_ID | KIND | M | N | K | MACS | OUTPUTS | GEMM_BUSY_CYCLES
100     | 1    | 1 | 1 | 1 | 1    | 1       | 24
101     | 1    | 2 | 2 | 2 | 8    | 4       | 224
105     | 1    | 2 | 3 | 4 | 24   | 6       | 594
5       | 0    | 4 | 4 | 4 | 64   | 16      | 1609
400     | 2    | 4 | 4 | 4 | 64   | 16      | 1610
401     | 2    | 4 | 4 | 4 | 64   | 16      | 1610
402     | 2    | 4 | 4 | 4 | 64   | 16      | 1610
403     | 2    | 4 | 4 | 4 | 64   | 16      | 1610
```

P4 does not lock exact cycle matching in regression. It preserves correctness, reports profile changes, and protects representative B-cache flows in full regression.

---

## 3. Problem Statement

The current GEMM datapath repeatedly reads the same operands.

For row-major GEMM:

```text
C[m][n] = sum_k A[m][k] * B[k][n]
```

Current loop structure:

```text
for m in 0 .. M-1:
  for n in 0 .. N-1:
    for k in 0 .. K-1:
      read A[m][k]
      read B[k][n]
      MAC
```

This causes repeated reads:

```text
A[m][k] is reused across different n values.
B[k][n] is reused across different m values.
```

For a 4x4x4 GEMM:

```text
logical MACs = 64

current operand reads:
  A reads = M * N * K = 64
  B reads = M * N * K = 64
  total   = 128
```

If B is cached once per GEMM job:

```text
B preload reads = K * N = 16
A compute reads = M * N * K = 64
total           = 80
```

This saves:

```text
128 - 80 = 48 reads
```

That is a 37.5% reduction in GEMM operand-read requests for the 4x4x4 case.

---

## 4. P4 Design Goals

The P4 implementation satisfies:

1. Preserve the existing pre-P4 44/44 baseline by default, and preserve the current 47/47 full regression after P4 inclusion.
2. Add operand reuse without changing the DMA / AXI-Stream / Direct Stream frontend protocols.
3. Keep `GEMM_ENABLE_B_CACHE=0` behavior equivalent to the current P3 baseline.
4. Add an optional B-operand cache path controlled by a parameter.
5. Preserve `GEMM_MAC_LANES=1` and `GEMM_MAC_LANES=2` correctness.
6. Preserve signed int8 A/B behavior and signed int32 accumulation.
7. Preserve row-major A/B/C layout.
8. Preserve C writeback behavior and address mapping.
9. Preserve Direct Stream compatibility through `gemm_input_mem_router`.
10. Improve or at least characterize busy-cycle profile for repeated-read cases.
11. Avoid widening the local memory interface in the first P4 implementation.

---

## 5. Non-Goals for First P4 Step

The completed first P4 step does not attempt to:

- implement 4-lane or wider MAC
- implement systolic-array scheduling
- widen the scratchpad RAM interface
- widen the operand buffer interface
- add multi-read operand-buffer ports
- change the DMA engine
- change AXI-Stream or Direct Stream protocols
- change the scoreboard reference model
- change C writeback format
- require exact cycle-count checks
- guarantee a large speedup for all dimensions

The first P4 step is an incremental operand-reuse prototype.

---

## 6. Candidate Optimization Approaches

### 6.1 Approach A: B Operand Cache

Preload the B matrix once per GEMM job into a small local cache.

Then compute:

```text
A is still read from memory/router
B is read from local B cache
```

Benefits:

```text
low risk
no external interface change
good reuse when M > 1
compatible with scratchpad and Direct Stream modes
easier to verify
```

Limitations:

```text
adds preload time
does not reduce A reads
cache size must be bounded
small M cases may see little or no improvement
```

Recommended first P4 implementation.

### 6.2 Approach B: A Row Cache

Cache one A row at a time:

```text
A[m][0:K-1]
```

Then reuse it across all N columns.

Benefits:

```text
good reuse when N > 1
small storage requirement
```

Limitations:

```text
requires careful row transition handling
B reads remain repeated
```

Potential P4 follow-up.

### 6.3 Approach C: Combined A Row Cache + B Cache

Cache both:

```text
A current row
B full small tile
```

Benefits:

```text
largest read reduction for small matrices
```

Limitations:

```text
more FSM and verification complexity
```

Potential P4 or P5 follow-up after B-cache is stable.

### 6.4 Approach D: 32-bit Packed Operand Reads

Use one 32-bit read to extract multiple int8 operands.

Benefits:

```text
better memory bandwidth utilization
can reduce read requests for aligned row-major data
```

Limitations:

```text
alignment-sensitive
base address offset-sensitive
byte-lane selection required
configurable base cases 400-403 become more important
Direct Stream operand-buffer behavior must be checked carefully
```

Recommended after B-cache, not as first P4 implementation.

### 6.5 Approach E: Tile-Based Scheduling

Change GEMM scheduling to operate on tiles and maximize reuse.

Benefits:

```text
moves toward real accelerator-style architecture
```

Limitations:

```text
larger architectural change
larger UVM update
more complex scoreboard/debug
```

Out of scope for first P4.

---

## 7. Chosen First P4 Architecture

The completed first P4 implementation is:

```text
P4B: Optional B operand cache prototype
```

High-level behavior:

```text
if GEMM_ENABLE_B_CACHE == 0:
    use current P3 GEMM path

if GEMM_ENABLE_B_CACHE == 1:
    preload B matrix into local B cache
    compute GEMM using memory reads for A and local-cache reads for B
```

The local memory interface remains unchanged.

---

## 8. Parameterization

Add a new parameter to `gemm_top.sv`:

```systemverilog
parameter bit GEMM_ENABLE_B_CACHE = 1'b0
```

Default must be:

```systemverilog
GEMM_ENABLE_B_CACHE = 1'b0
```

This preserved the pre-P4 44/44 regression baseline; after P4F, the current full regression baseline is 47/47.

Recommended additional parameters:

```systemverilog
parameter int GEMM_B_CACHE_MAX_K = 4;
parameter int GEMM_B_CACHE_MAX_N = 4;
```

These are enough for the current verified case set:

```text
CASE_ID=100: M=1, N=1, K=1
CASE_ID=101: M=2, N=2, K=2
CASE_ID=105: M=2, N=3, K=4
CASE_ID=5  : M=4, N=4, K=4
CASE_ID=400-403: M=4, N=4, K=4
```

Recommended parameter propagation eventually:

```text
gemm_top
ai_accel_subsys
ai_accel_subsys_uvm_top
run_uvm.tcl
run_full_uvm_regression.tcl
```

---

## 9. Supported Dimension Policy

For the first B-cache prototype, support:

```text
dim_k <= GEMM_B_CACHE_MAX_K
dim_n <= GEMM_B_CACHE_MAX_N
```

Implemented behavior for unsupported dimensions:

```text
fallback to original no-cache path
```

This is safer than fatal termination because it preserves future scalability.

Effective enable:

```systemverilog
b_cache_active = GEMM_ENABLE_B_CACHE &&
                 (dim_k <= GEMM_B_CACHE_MAX_K) &&
                 (dim_n <= GEMM_B_CACHE_MAX_N);
```

If `b_cache_active == 0`, the existing current P3 path is used.

---

## 10. B Cache Storage

Recommended local storage:

```systemverilog
logic signed [B_DATA_WIDTH-1:0] b_cache_q [GEMM_B_CACHE_MAX_K][GEMM_B_CACHE_MAX_N];
logic signed [B_DATA_WIDTH-1:0] b_cache_d [GEMM_B_CACHE_MAX_K][GEMM_B_CACHE_MAX_N];
```

Alternative flattened storage:

```systemverilog
logic signed [B_DATA_WIDTH-1:0] b_cache_q [GEMM_B_CACHE_MAX_K*GEMM_B_CACHE_MAX_N];
```

Implemented first version:

```text
2D array for readability
```

Indexing:

```text
b_cache[k][n] = B[k][n]
```

Address formula for preload:

```text
B[k][n] address = base_addr_b + (k * dim_n + n) * B_BYTES
```

---

## 11. B Cache Preload Flow

### 11.1 Preload Sequence

Before starting normal GEMM compute:

```text
for preload_k in 0 .. dim_k-1:
  for preload_n in 0 .. dim_n-1:
    read B[preload_k][preload_n]
    store into b_cache[preload_k][preload_n]
```

Then start the normal compute loop:

```text
m_idx = 0
n_idx = 0
k_idx = 0
acc   = 0
```

### 11.2 Preload FSM States

Add states only used when `b_cache_active == 1`:

```text
S_BCACHE_INIT
S_BCACHE_READ
S_BCACHE_WAIT
S_BCACHE_NEXT
```

Suggested flow:

```text
S_IDLE
  -> if start && b_cache_active:
         S_BCACHE_INIT
     else:
         S_READ_A

S_BCACHE_INIT
  -> preload_k = 0
  -> preload_n = 0
  -> S_BCACHE_READ

S_BCACHE_READ
  -> issue read to B[preload_k][preload_n]
  -> S_BCACHE_WAIT

S_BCACHE_WAIT
  -> capture mem_rd_data into b_cache[preload_k][preload_n]
  -> S_BCACHE_NEXT

S_BCACHE_NEXT
  -> advance preload_n/preload_k
  -> if preload complete:
         S_READ_A
     else:
         S_BCACHE_READ
```

### 11.3 Request Handshake

The preload read path must use the same memory request handshake:

```text
issue read only when mem_req_ready == 1
wait for mem_rd_valid
```

This keeps compatibility with:

```text
scratchpad path
input memory router
Direct Stream operand buffer path
```

---

## 12. Compute Path with B Cache

### 12.1 Existing No-Cache 2-Lane Path

For each K group:

```text
read A0
read B0
read A1, if valid
read B1, if valid
MAC
```

### 12.2 B-Cache 2-Lane Path

For each K group:

```text
read A0
B0 = b_cache[k_idx][n_idx]

read A1, if lane1 valid
B1 = b_cache[k_idx+1][n_idx]

MAC
```

So B read states can be skipped when cache is active.

Conceptual flow:

```text
S_READ_A
S_WAIT_A
  if b_cache_active:
      b_val = b_cache[k_idx][n_idx]
      if lane1 valid:
          S_READ_A1
      else:
          S_MAC
  else:
      S_READ_B

S_READ_A1
S_WAIT_A1
  if b_cache_active:
      b1_val = b_cache[k_idx+1][n_idx]
      S_MAC
  else:
      S_READ_B1
```

### 12.3 Single-Lane Compatibility

For `GEMM_MAC_LANES=1` with B cache:

```text
read A
B = b_cache[k][n]
MAC
```

This can be supported, but first verification should prioritize:

```text
GEMM_MAC_LANES=2
GEMM_ENABLE_B_CACHE=1
```

The no-cache single-lane path remains the main regression default.

---

## 13. Address Generation

### 13.1 B Cache Preload Address

```text
preload_B_addr =
    base_addr_b + ((preload_k * dim_n) + preload_n) * B_BYTES
```

### 13.2 B Cache Compute Index

Lane 0:

```text
b_val = b_cache[k_idx][n_idx]
```

Lane 1:

```text
b1_val = b_cache[k_idx + 1][n_idx]
```

Lane 1 access must only occur when:

```text
k_idx + 1 < dim_k
```

### 13.3 Configurable Base Cases

The existing configurable base cases must remain important:

```text
CASE_ID=400
CASE_ID=401
CASE_ID=402
CASE_ID=403
```

They check that B preload address generation respects shifted legal base addresses.

---

## 14. Performance Model

### 14.1 Read Request Reduction

For no-cache:

```text
A reads = M * N * K
B reads = M * N * K
total   = 2 * M * N * K
```

For B cache:

```text
B preload reads = K * N
A compute reads = M * N * K
total           = (K * N) + (M * N * K)
```

Savings:

```text
saved reads = (M * N * K) - (K * N)
            = K * N * (M - 1)
```

### 14.2 Examples

CASE_ID=100:

```text
M=1, N=1, K=1

no-cache reads = 2
B-cache reads  = 1 preload B + 1 A = 2
saved reads    = 0
```

CASE_ID=101:

```text
M=2, N=2, K=2

no-cache reads = 16
B-cache reads  = 4 preload B + 8 A = 12
saved reads    = 4
```

CASE_ID=105:

```text
M=2, N=3, K=4

no-cache reads = 48
B-cache reads  = 12 preload B + 24 A = 36
saved reads    = 12
```

CASE_ID=5 / 400-403:

```text
M=4, N=4, K=4

no-cache reads = 128
B-cache reads  = 16 preload B + 64 A = 80
saved reads    = 48
```

### 14.3 Expected Busy-Cycle Behavior

Expected trend:

```text
CASE_ID=100:
  little or no improvement

CASE_ID=101:
  small improvement

CASE_ID=105:
  moderate improvement

CASE_ID=5/400/401/402/403:
  larger improvement
```

Do not lock exact cycle counts in first verification.

Acceptance rule for first B-cache milestone:

```text
result correctness must pass
mac_count must equal M*N*K
output_count must equal M*N
profile must be printed
busy cycle must be non-zero
busy cycle should not regress severely
```

Later tuning can make cycle improvement a formal check.

---

## 15. Performance Counter Requirements

Existing counters must keep their meaning:

```systemverilog
gemm_perf_busy_cycles
gemm_perf_mac_count
gemm_perf_output_count
```

Required behavior with B cache:

```text
gemm_perf_busy_cycles:
  includes B-cache preload time and compute time

gemm_perf_mac_count:
  counts logical MACs only
  unchanged expected value = M*N*K

gemm_perf_output_count:
  counts C outputs only
  unchanged expected value = M*N
```

Recommended optional future counters:

```systemverilog
gemm_perf_mem_rd_count
gemm_perf_b_cache_fill_count
gemm_perf_b_cache_hit_count
```

These are not required for first B-cache correctness, but they would make bandwidth optimization easier to measure.

Current P4 policy:

```text
Do not add new top-level counter ports in the first patch unless needed.
Use existing profile busy cycles first.
Add read/hit counters as P4C or P4D if profile analysis needs more visibility.
```

---

## 16. Direct Stream Compatibility

Direct Stream mode routes GEMM A/B reads through:

```text
gemm_input_mem_router
```

In Direct Stream mode:

```text
GEMM A/B reads -> gemm_operand_buffer
GEMM C writes  -> scratchpad
```

With B cache enabled:

```text
B cache preload reads B through the same GEMM local memory read interface.
A compute reads continue through the same interface.
C writes remain unchanged.
```

Therefore, the B-cache implementation must not assume scratchpad-only behavior.

Completed Direct Stream test:

```text
GEMM_ENABLE_B_CACHE=1
GEMM_MAC_LANES=2
ai_accel_subsys_direct_stream_smoke_test RUN_ALL=1
```

Then expand to:

```text
ai_accel_subsys_direct_stream_load_store_stress_test
CDC sanity at dma_clk=10ns, core_clk=13ns
```

---

## 17. DMA / AXI-Stream Compatibility

B-cache preload uses the same GEMM local memory interface after A/B data has already been loaded.

Therefore, it should remain compatible with:

```text
DMA load A/B path
AXI-Stream preload A/B path
Direct Stream preload A/B path
```

Completed stress tests after smoke/profile passed:

```text
GEMM_ENABLE_B_CACHE=1, GEMM_MAC_LANES=2:
  ai_accel_subsys_dma_load_store_stress_test
  ai_accel_subsys_axis_stream_load_store_stress_test
  ai_accel_subsys_direct_stream_load_store_stress_test
```

Completed CDC subset:

```text
dma_clk=10ns
core_clk=13ns
GEMM_ENABLE_B_CACHE=1
GEMM_MAC_LANES=2
```

---

## 18. Verification Closure

### 18.1 P4A: Spec

Status:

```text
DONE
```

### 18.2 P4B: Safe Parameter Patch

Implemented:

```systemverilog
parameter bit GEMM_ENABLE_B_CACHE = 1'b0;
parameter int GEMM_B_CACHE_MAX_K  = 4;
parameter int GEMM_B_CACHE_MAX_N  = 4;
```

Acceptance:

```text
compile PASS
baseline regression remained clean
```

### 18.3 P4C: B Cache RTL Prototype / Compute Bypass

Implemented:

```text
B cache storage
B cache preload FSM
b_cache_active helper
B cache compute bypass for lane0/lane1 B operands
fallback to original B memory-read path when inactive
```

Acceptance:

```text
perf_counter_smoke RUN_ALL PASS
perf_profile PASS
result compare PASS
mac_count/output_count PASS
```

### 18.4 P4D: Direct Stream Compatibility

Validated:

```text
GEMM_ENABLE_B_CACHE=1
GEMM_MAC_LANES=2
ai_accel_subsys_direct_stream_smoke_test RUN_ALL=1
```

Acceptance:

```text
8 cases PASS
scoreboard compare PASS
no UVM_ERROR / UVM_FATAL
```

P4D also exposed and closed the GEMM completion semantic issue:

```text
done waits for final C write completion before assertion
```

### 18.5 P4E: B Cache Stress / CDC

Manually validated:

```text
DMA load-store stress + B-cache, 10/14                  PASS
DMA load-store stress + B-cache, 10/13 CDC              PASS
AXI-Stream load-store stress + B-cache, 10/14           PASS
AXI-Stream load-store stress + B-cache, 10/13 CDC       PASS
Direct Stream load-store stress + B-cache, 10/14        PASS
Direct Stream load-store stress + B-cache, 10/13 CDC    PASS
```

### 18.6 P4F: Regression Inclusion

Added representative default-clock B-cache subset:

```text
gemm_2lane_bcache_dma_load_store_stress
gemm_2lane_bcache_axis_stream_load_store_stress
gemm_2lane_bcache_direct_stream_load_store_stress
```

Final acceptance:

```text
TOTAL : 47
PASS  : 47
FAIL  : 0
```

## 19. Suggested Tcl Runs

### 19.1 B-Cache Perf Counter Smoke

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

do run_uvm.tcl
```

### 19.2 B-Cache Perf Profile

```tcl
set UVM_TEST ai_accel_subsys_perf_profile_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 100

set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14

set GEMM_MAC_LANES 2
set GEMM_ENABLE_B_CACHE 1

do run_uvm.tcl
```

### 19.3 B-Cache Direct Stream Smoke

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

do run_uvm.tcl
```

### 19.4 B-Cache Stress

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

do run_uvm.tcl
```

### 19.5 B-Cache CDC

```tcl
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 13
set GEMM_MAC_LANES 2
set GEMM_ENABLE_B_CACHE 1
```

Use the same stress tests as above.

---


### 19.6 B-Cache Full-Regression Representative Items

The full regression includes these P4F representative B-cache tests:

```text
gemm_2lane_bcache_dma_load_store_stress
gemm_2lane_bcache_axis_stream_load_store_stress
gemm_2lane_bcache_direct_stream_load_store_stress
```

These are default-clock representatives:

```text
dma_clk  = 10ns
core_clk = 14ns
```

The CDC variants were validated manually during P4E and can be kept as manual/nightly targets.

## 20. Risk Analysis

### Risk 1: B Cache Preload Address Bug

Possible failure:

```text
wrong B[k][n] address
wrong base address handling
configurable base cases fail
```

Mitigation:

```text
run CASE_ID=400-403
run Direct Stream smoke
run scoreboard compare
```

### Risk 2: Cache Index Bug

Possible failure:

```text
B[k][n] stored correctly but read back with wrong k/n index
```

Mitigation:

```text
run non-square or variable-dimension CASE_ID=105
run K=2 CASE_ID=101
run K=4 CASE_ID=5
```

### Risk 3: Lane1 Cache Access Bug

Possible failure:

```text
lane1 reads b_cache[k+1][n] when invalid
odd K out-of-range access
```

Mitigation:

```text
include K=1 case
eventually add odd-K case if available
keep lane1_valid guard
```

### Risk 4: No-Cache Path Regression

Possible failure:

```text
GEMM_ENABLE_B_CACHE=0 behavior changes accidentally
```

Mitigation:

```text
default parameter remains 0
run the full baseline regression after each safe patch
```

### Risk 5: Direct Stream Router Assumption

Possible failure:

```text
B cache preload reads from wrong source in Direct Stream mode
```

Mitigation:

```text
run Direct Stream smoke and stress with B cache enabled
```

### Risk 6: Performance Does Not Improve

Possible cause:

```text
preload overhead offsets saved reads for small cases
FSM still inefficient
read latency dominates
```

Mitigation:

```text
do not fail first milestone on exact busy-cycle improvement
print profile
consider A row cache or packed reads next
```

---

## 21. Recommended Implementation Order

Recommended patch sequence:

```text
Patch 1:
  Add GEMM_ENABLE_B_CACHE parameter default 0.
  Propagate parameter through ai_accel_subsys and ai_accel_subsys_uvm_top.
  Add run_uvm.tcl default/guard.
  No functional behavior change.
  Compile and run the applicable baseline regression at that patch point.

Patch 2:
  Add b_cache storage and preload indices.
  Add b_cache_active helper.
  Do not yet change compute path.
  Compile.

Patch 3:
  Add B cache preload FSM.
  After preload, continue into existing compute path.
  For now, optionally still read B from memory.
  Compile and focused smoke.

Patch 4:
  Bypass B memory reads during compute when b_cache_active.
  Use b_cache for lane0/lane1 B values.
  Run focused CASE_ID=100/101/105/5.

Patch 5:
  Run perf_counter_smoke RUN_ALL with B cache enabled.

Patch 6:
  Run perf_profile with B cache enabled and record summary.

Patch 7:
  Run Direct Stream smoke RUN_ALL with B cache enabled.

Patch 8:
  Run stress / CDC subset with B cache enabled.

Patch 9:
  Add selected B-cache subset to full regression.
```

---

## 22. Acceptance Criteria

P4 closure is complete.

Completed acceptance:

```text
GEMM_ENABLE_B_CACHE=0 baseline remains protected
GEMM_ENABLE_B_CACHE=1 perf_counter_smoke RUN_ALL PASS
GEMM_ENABLE_B_CACHE=1 perf_profile PASS
GEMM_ENABLE_B_CACHE=1 Direct Stream smoke RUN_ALL PASS
result compare PASS
mac_count/output_count PASS
no UVM_ERROR / UVM_FATAL
profile summary captured
```

P4 stress closure is complete:

```text
B-cache DMA load-store stress PASS
B-cache AXI-Stream load-store stress PASS
B-cache Direct Stream load-store stress PASS
B-cache DMA / AXI-Stream / Direct Stream CDC sanity PASS
```

P4 regression closure is complete:

```text
selected B-cache subset added to run_full_uvm_regression.tcl
full regression PASS: 47/47
```

## 23. Future Work After B Cache

After the B-cache path is stable, evaluate:

```text
A row cache
A row cache + B cache
32-bit packed int8 operand reads
wider local memory interface
multi-read operand buffer
larger GEMM dimensions
tile-based scheduling
4-lane MAC
```

Recommended next optimization after B cache:

```text
32-bit packed B-cache preload
```

Reason:

```text
B cache preload currently still reads one int8 value per memory request.
A packed preload can reduce preload request count by extracting 4 B elements from one 32-bit read when aligned.
```

---

## 24. Summary

P4 improves GEMM performance by reducing repeated operand reads rather than immediately adding more MAC lanes.

The safest first optimization is:

```text
optional B operand cache
```

The key rule is:

```text
default off
correctness first
profile second
stress/CDC third
regression inclusion last
```

The current `50/50 PASS` baseline is the clean checkpoint for the next performance milestone.
