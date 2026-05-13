# Packed Operand Read Spec

## 1. Purpose

This document defines the P5 performance milestone for the AI Accelerator Subsystem GEMM datapath.

The project has already completed the correctness-first subsystem baseline, DMA/AXI-Stream/Direct Stream integration, 2-lane GEMM datapath, 2-lane stress/CDC hardening, and the P4 B-cache operand reuse milestone.

Current baseline before P5:

```text
P4: B-cache operand reuse optimization completed

Full regression:
  TOTAL : 47
  PASS  : 47
  FAIL  : 0
```

P5 focuses on improving **memory read granularity** for int8 GEMM operands.

The key observation is:

```text
P2 added 2-lane MAC parallelism.
P4 reduced repeated B reads by adding a B-cache.
But the GEMM local memory read path still often fetches one int8 operand per memory request.
```

P5 aims to use the existing 32-bit local memory read container more efficiently by fetching multiple packed int8 operands per request, then unpacking the selected bytes locally.

---

## 2. Naming

Recommended file name:

```text
docs/packed_operand_read_spec.md
```

This name is acceptable and clear.

Alternative names:

```text
docs/gemm_packed_operand_read_spec.md
docs/packed_int8_operand_read_spec.md
```

The proposed name is preferred because it is concise and broad enough to cover both future A and B operand packing.

---

## 3. Current Baseline

### 3.1 Data Format

Current GEMM data model:

```text
A element      : signed int8
B element      : signed int8
Accumulator C : signed int32
C output       : signed int32
```

Layout:

```text
A[m][k] row-major
B[k][n] row-major
C[m][n] row-major
```

Address formulas:

```text
A[m][k] = base_addr_a + (m * dim_k + k) * 1
B[k][n] = base_addr_b + (k * dim_n + n) * 1
C[m][n] = base_addr_c + (m * dim_n + n) * 4
```

### 3.2 Existing GEMM Local Memory Interface

The GEMM local read interface already returns a 32-bit value:

```systemverilog
output logic                  mem_rd_en;
output logic [ADDR_WIDTH-1:0] mem_rd_addr;
input  logic [31:0]           mem_rd_data;
input  logic                  mem_rd_valid;
```

Current int8 operand extraction effectively uses:

```systemverilog
operand = mem_rd_data[7:0];
```

This is simple, but it does not fully use the 32-bit read data width.

### 3.3 Current P4 B-Cache Behavior

With B-cache enabled:

```text
1. Preload B[k][n] into local B-cache.
2. During compute, read A from memory/router.
3. During compute, read B from local B-cache.
```

Current B-cache preload still conceptually fetches one B element per memory read request:

```text
for k in 0 .. dim_k-1:
  for n in 0 .. dim_n-1:
    read B[k][n]
    b_cache[k][n] = returned int8 value
```

This is the safest first point to improve memory read granularity.

---

## 4. Problem Statement

The current P4 B-cache design reduces repeated B reads, but the B preload itself still performs byte-level operand reads.

For a 4x4 B matrix:

```text
B elements = K * N = 4 * 4 = 16
```

Current B-cache preload:

```text
16 read requests
each request returns 32 bits
only one byte is consumed
```

Packed B-cache preload target:

```text
4 read requests
each request returns 4 packed int8 B elements
all four bytes are consumed
```

For B-cache preload, ideal read-request reduction is:

```text
old B preload reads = K * N
new B preload reads = ceil((K * N + byte_offset) / 4)  // depending on alignment
```

For aligned 4x4 B:

```text
old = 16 reads
new = 4 reads
saved = 12 reads
```

---

## 5. P5 Design Goals

P5 must:

1. Preserve the current 47/47 full regression baseline by default.
2. Keep `GEMM_ENABLE_B_CACHE=0` behavior unchanged.
3. Keep `GEMM_ENABLE_PACKED_BCACHE_PRELOAD=0` behavior unchanged.
4. Add packed read as an optional feature, default off.
5. Start with packed B-cache preload only.
6. Avoid changing DMA, AXI-Stream, Direct Stream, or scoreboard protocols.
7. Reuse the existing 32-bit GEMM local read data path.
8. Preserve signed int8 operand behavior.
9. Preserve row-major layout.
10. Preserve C writeback format and done semantics.
11. Preserve Direct Stream compatibility.
12. Validate configurable base address cases.
13. Characterize performance before adding more aggressive packed A-read behavior.

---

## 6. Non-Goals for First P5 Step

The first P5 step does not attempt to:

- widen the GEMM local memory interface beyond 32 bits
- add a new AXI protocol mode
- change scratchpad memory format
- change operand-buffer memory format
- change C format
- implement packed A compute reads
- implement A row cache
- implement tile scheduling
- implement 4-lane MAC
- add a systolic array
- require exact busy-cycle pass/fail thresholds
- change the scoreboard reference model

The first P5 implementation is a local GEMM read-efficiency optimization.

---

## 7. Recommended First Target

Recommended first target:

```text
P5 first RTL target = packed B-cache preload
```

Reason:

```text
B-cache preload reads B in compact row-major order.
B-cache preload happens before compute.
B-cache preload already has its own FSM.
Packed preload does not disturb the main MAC loop as much as packed A reads would.
P4 already gives strong regression protection for B-cache behavior.
```

Do not start with packed A compute reads.

Packed A reads require more careful handling because A access order depends on:

```text
m_idx
n_idx
k_idx
lane grouping
A reuse across n
Direct Stream operand-buffer routing
```

Packed A reads are better as a later P5 or P6 step.

---

## 8. Parameterization

Add a new parameter to `gemm_top.sv`:

```systemverilog
parameter bit GEMM_ENABLE_PACKED_BCACHE_PRELOAD = 1'b0
```

Default must be:

```systemverilog
GEMM_ENABLE_PACKED_BCACHE_PRELOAD = 1'b0
```

Effective enable:

```systemverilog
packed_bcache_preload_active =
    GEMM_ENABLE_B_CACHE &&
    GEMM_ENABLE_PACKED_BCACHE_PRELOAD &&
    b_cache_dim_supported;
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
set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
```

Optional future parameter:

```systemverilog
parameter int GEMM_PACKED_READ_BYTES = 4
```

For the first P5 step, keep this implicit at 4 bytes because `mem_rd_data` is 32 bits.

---

## 9. Packed Read Address Model

### 9.1 Byte Address

The logical B element byte address remains:

```text
b_elem_addr = base_addr_b + ((k * dim_n) + n) * B_BYTES
```

For int8 B:

```text
B_BYTES = 1
```

### 9.2 Aligned 32-Bit Read Address

Packed read aligns the read request address down to a 4-byte boundary:

```text
packed_addr = {b_elem_addr[ADDR_WIDTH-1:2], 2'b00}
```

Equivalent:

```text
packed_addr = b_elem_addr & ~32'h3
```

### 9.3 Byte Lane

The byte lane inside the returned 32-bit word is:

```text
byte_lane = b_elem_addr[1:0]
```

Mapping:

```text
byte_lane=0 -> mem_rd_data[ 7: 0]
byte_lane=1 -> mem_rd_data[15: 8]
byte_lane=2 -> mem_rd_data[23:16]
byte_lane=3 -> mem_rd_data[31:24]
```

### 9.4 Signed Extraction

For signed int8 B:

```systemverilog
logic signed [7:0] b0;
logic signed [7:0] b1;
logic signed [7:0] b2;
logic signed [7:0] b3;

b0 = mem_rd_data[ 7: 0];
b1 = mem_rd_data[15: 8];
b2 = mem_rd_data[23:16];
b3 = mem_rd_data[31:24];
```

When storing into `b_cache`, each byte must be treated as signed int8.

---

## 10. Packed B-Cache Preload Strategy

### 10.1 Existing Scalar Preload

Current scalar preload loops over B elements:

```text
linear_idx = k * dim_n + n

for linear_idx in 0 .. K*N-1:
    read base_addr_b + linear_idx
    b_cache[k][n] = mem_rd_data[7:0]
```

### 10.2 New Packed Preload Concept

Packed preload loops over aligned 32-bit chunks that cover the B matrix byte range:

```text
b_total_elems = dim_k * dim_n
b_total_bytes = b_total_elems * B_BYTES

first_byte_addr = base_addr_b
first_aligned_addr = align_down(first_byte_addr, 4)

last_byte_addr = base_addr_b + b_total_bytes - 1
last_aligned_addr = align_down(last_byte_addr, 4)

for packed_addr in first_aligned_addr .. last_aligned_addr step 4:
    read packed_addr
    unpack up to four bytes
    store bytes whose logical addresses are within the B matrix range
```

### 10.3 Why Address-Range Filtering Is Needed

Configurable base address cases may shift `base_addr_b`.

If `base_addr_b` is not 4-byte aligned, the first packed read may include bytes before the B matrix. These bytes must be ignored.

Example:

```text
base_addr_b = 0x101
B byte range = 0x101 .. 0x110
first packed read address = 0x100
valid byte lanes in first word = 1, 2, 3
byte lane 0 belongs before B and must be ignored
```

Therefore, packed preload must filter by logical byte address:

```text
if current_byte_addr >= base_addr_b &&
   current_byte_addr <  base_addr_b + b_total_bytes:
       store into b_cache
else:
       ignore
```

### 10.4 Linear Index Conversion

For each valid byte address:

```text
linear_idx = current_byte_addr - base_addr_b
```

For int8 B:

```text
b_k = linear_idx / dim_n
b_n = linear_idx % dim_n
```

Store:

```text
b_cache[b_k][b_n] = selected_byte
```

---

## 11. Suggested Packed Preload FSM

### 11.1 Additional State Variables

Recommended registers:

```systemverilog
logic [ADDR_WIDTH-1:0] bpack_addr_q, bpack_addr_d;
logic [ADDR_WIDTH-1:0] bpack_end_addr_q, bpack_end_addr_d;
logic [ADDR_WIDTH-1:0] bpack_base_q, bpack_base_d;
logic [ADDR_WIDTH-1:0] bpack_total_bytes_q, bpack_total_bytes_d;
```

Optional loop helpers:

```systemverilog
logic [ADDR_WIDTH-1:0] byte_addr0;
logic [ADDR_WIDTH-1:0] byte_addr1;
logic [ADDR_WIDTH-1:0] byte_addr2;
logic [ADDR_WIDTH-1:0] byte_addr3;
```

### 11.2 FSM States

Option A: Add a parallel packed-preload state set:

```text
S_BCACHE_PACK_INIT
S_BCACHE_PACK_READ
S_BCACHE_PACK_WAIT
S_BCACHE_PACK_NEXT
```

Option B: Reuse current B-cache states with a mode flag.

Recommended first implementation:

```text
Use separate packed-preload states.
```

Reason:

```text
less risk to scalar B-cache preload
easier debug
easier waveform reading
simple fallback path
```

### 11.3 FSM Flow

```text
S_IDLE
  -> if start && b_cache_active && packed_bcache_preload_active:
         S_BCACHE_PACK_INIT
     else if start && b_cache_active:
         S_BCACHE_INIT
     else:
         S_READ_A

S_BCACHE_PACK_INIT
  -> bpack_base       = base_addr_b
  -> bpack_total      = dim_k * dim_n * B_BYTES
  -> bpack_addr       = align_down(base_addr_b, 4)
  -> bpack_end_addr   = align_down(base_addr_b + bpack_total - 1, 4)
  -> S_BCACHE_PACK_READ

S_BCACHE_PACK_READ
  -> mem_rd_addr = bpack_addr
  -> if mem_req_ready:
         mem_rd_en = 1
         S_BCACHE_PACK_WAIT

S_BCACHE_PACK_WAIT
  -> if mem_rd_valid:
         unpack mem_rd_data[31:0]
         store valid bytes into b_cache
         S_BCACHE_PACK_NEXT

S_BCACHE_PACK_NEXT
  -> if bpack_addr == bpack_end_addr:
         S_READ_A
     else:
         bpack_addr += 4
         S_BCACHE_PACK_READ
```

---

## 12. Helper Functions

Recommended helper functions in `gemm_top.sv`.

### 12.1 Align Down to 4 Bytes

```systemverilog
function automatic logic [ADDR_WIDTH-1:0] align_down4(
    input logic [ADDR_WIDTH-1:0] addr
);
    align_down4 = {addr[ADDR_WIDTH-1:2], 2'b00};
endfunction
```

### 12.2 Select Byte from Word

```systemverilog
function automatic logic signed [B_DATA_WIDTH-1:0] select_b_byte(
    input logic [31:0] word,
    input logic [1:0]  lane
);
    case (lane)
        2'd0: select_b_byte = word[ 7: 0];
        2'd1: select_b_byte = word[15: 8];
        2'd2: select_b_byte = word[23:16];
        default: select_b_byte = word[31:24];
    endcase
endfunction
```

### 12.3 Store Valid Packed Byte

Conceptual helper:

```systemverilog
task automatic store_packed_b_byte(
    input logic [ADDR_WIDTH-1:0] byte_addr,
    input logic signed [B_DATA_WIDTH-1:0] byte_val
);
    int unsigned linear_idx;
    int unsigned bk;
    int unsigned bn;

    if ((byte_addr >= base_addr_b) &&
        (byte_addr <  (base_addr_b + bpack_total_bytes_q))) begin

        linear_idx = byte_addr - base_addr_b;
        bk = linear_idx / dim_n;
        bn = linear_idx % dim_n;

        b_cache_d[bk][bn] = byte_val;
    end
endtask
```

For synthesizable RTL, this logic may be implemented inline in `always_comb` rather than as a task.

---

## 13. Direct Stream Compatibility

Direct Stream mode routes GEMM A/B reads through:

```text
gemm_input_mem_router
```

With packed B-cache preload:

```text
B-cache preload read requests still go through the same GEMM local read interface.
```

Therefore, Direct Stream compatibility depends on whether the operand buffer/router can support aligned 32-bit read requests that may begin before the logical B region when `base_addr_b` is unaligned.

This is the key P5 Direct Stream risk.

### 13.1 Conservative First Policy

For first P5 implementation, two policies are possible.

#### Policy A: Require 4-byte aligned base_addr_b for packed B-cache preload

Effective enable:

```systemverilog
packed_bcache_preload_active =
    GEMM_ENABLE_B_CACHE &&
    GEMM_ENABLE_PACKED_BCACHE_PRELOAD &&
    b_cache_dim_supported &&
    (base_addr_b[1:0] == 2'b00);
```

If `base_addr_b` is unaligned:

```text
fallback to scalar B-cache preload
```

Benefits:

```text
lowest risk
Direct Stream operand-buffer region decode remains simple
no before-region aligned read issue
configurable base unaligned cases still pass through scalar fallback
```

Limitations:

```text
packed-read benefit applies only to aligned B base cases
```

#### Policy B: Support unaligned base_addr_b with aligned read-before-region

This requires the router/operand buffer to safely handle a read at:

```text
align_down(base_addr_b, 4)
```

even when it starts before the B region.

Benefits:

```text
more complete packed-read support
better future extensibility
```

Risks:

```text
may conflict with current Direct Stream start-address decode policy
requires careful operand-buffer read behavior
more likely to disturb already-stable P4 paths
```

### 13.2 Recommended First Implementation Policy

Recommended first implementation:

```text
Policy A: packed B-cache preload only when base_addr_b is 4-byte aligned.
```

Reason:

```text
P5 should first prove packed-read value with minimal router/operand-buffer disruption.
Configurable base cases can validate fallback behavior.
Unaligned packed support can become P5 follow-up.
```

This means:

```text
aligned B base:
    use packed B-cache preload

unaligned B base:
    use scalar B-cache preload
```

---

## 14. Scratchpad / DMA / AXI-Stream Compatibility

For scratchpad-backed modes, aligned packed reads are expected to work naturally because the underlying memory returns a 32-bit container.

Paths to verify:

```text
Host-primary scratchpad path
DMA load A/B into scratchpad -> GEMM -> DMA store C
AXI-Stream preload A/B into scratchpad -> GEMM -> DMA store C
```

P5 does not require changes to:

```text
dma_load_engine
dma_store_engine
axis_preload_engine
axis_scratchpad_write_adapter
scratchpad_port0_owner_mux
scratchpad_port1_owner_mux
```

---

## 15. Configurable Base Address Policy

Existing configurable-base cases remain important:

```text
CASE_ID=400
CASE_ID=401
CASE_ID=402
CASE_ID=403
```

P5 should use them to validate both:

```text
aligned packed path
fallback scalar path for unaligned base_addr_b
```

Recommended acceptance:

```text
All configurable-base cases must still pass.
If base_addr_b is aligned, packed preload may activate.
If base_addr_b is unaligned, scalar fallback must activate.
```

Optional debug messages can help:

```text
[GEMM_P5] packed_bcache_preload_active=1 base_b=...
[GEMM_P5] packed_bcache_preload_fallback_unaligned=1 base_b=...
```

---

## 16. Expected Performance Model

### 16.1 Scalar B-Cache Preload

```text
B preload reads = K * N
```

### 16.2 Packed B-Cache Preload, Aligned

```text
B preload reads = ceil((K * N) / 4)
```

### 16.3 Examples

CASE_ID=100:

```text
K=1, N=1
scalar B preload reads = 1
packed B preload reads = 1
saved = 0
```

CASE_ID=101:

```text
K=2, N=2
scalar B preload reads = 4
packed B preload reads = 1
saved = 3
```

CASE_ID=105:

```text
K=4, N=3
scalar B preload reads = 12
packed B preload reads = 3
saved = 9
```

CASE_ID=5 / 400-403, aligned B base:

```text
K=4, N=4
scalar B preload reads = 16
packed B preload reads = 4
saved = 12
```

### 16.4 Expected Busy-Cycle Behavior

Expected trend compared to P4 B-cache:

```text
CASE_ID=100:
    little or no improvement

CASE_ID=101:
    small improvement

CASE_ID=105:
    moderate improvement

CASE_ID=5 / aligned 400-403:
    clear improvement in B-cache preload overhead
```

Acceptance should not require exact cycle values in first implementation.

---

## 17. Performance Counter Requirements

Existing counters keep their current meaning:

```text
gemm_perf_busy_cycles
gemm_perf_mac_count
gemm_perf_output_count
```

With packed B-cache preload:

```text
gemm_perf_busy_cycles:
    includes packed B-cache preload and compute

gemm_perf_mac_count:
    unchanged expected value = M * N * K

gemm_perf_output_count:
    unchanged expected value = M * N
```

Recommended future optional counters:

```systemverilog
gemm_perf_mem_rd_count
gemm_perf_b_cache_fill_count
gemm_perf_b_cache_packed_read_count
gemm_perf_b_cache_scalar_fallback_count
```

Do not add these in the first P5 patch unless profile visibility becomes insufficient.

---

## 18. Verification Plan

### 18.1 P5A: Spec

Complete when:

```text
docs/packed_operand_read_spec.md exists
architecture and verification plan are defined
```

### 18.2 P5B: Safe Parameter Patch

Add:

```systemverilog
parameter bit GEMM_ENABLE_PACKED_BCACHE_PRELOAD = 1'b0
```

Propagate through:

```text
gemm_top
ai_accel_subsys
ai_accel_subsys_uvm_top
run_uvm.tcl
```

No functional behavior change.

Acceptance:

```text
compile PASS
47/47 regression PASS
```

### 18.3 P5C: Packed B-Cache Preload RTL

Add:

```text
packed preload active helper
packed preload FSM states
packed preload address registers
32-bit unpack logic
aligned-base packed path
unaligned-base scalar fallback
```

Acceptance:

```text
GEMM_ENABLE_PACKED_BCACHE_PRELOAD=0:
    47/47 regression PASS

GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1:
    focused B-cache packed smoke PASS
```

### 18.4 P5D: Focused Profile

Run:

```text
ai_accel_subsys_perf_counter_smoke_test RUN_ALL=1
ai_accel_subsys_perf_profile_test
```

With:

```tcl
set GEMM_MAC_LANES 2
set GEMM_ENABLE_B_CACHE 1
set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
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
no UVM_ERROR / UVM_FATAL
```

### 18.5 P5E: Direct Stream Compatibility

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
do run_uvm.tcl
```

Acceptance:

```text
8 cases PASS
scoreboard compare PASS
control/result pairing PASS
no UVM_ERROR / UVM_FATAL
```

### 18.6 P5F: Stress / CDC Subset

Run:

```text
DMA load-store stress
AXI-Stream load-store stress
Direct Stream load-store stress
DMA load-store CDC
AXI-Stream load-store CDC
Direct Stream load-store CDC
```

With:

```text
GEMM_MAC_LANES=2
GEMM_ENABLE_B_CACHE=1
GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1
```

Acceptance:

```text
selected stress jobs PASS
scoreboard compare PASS
control/result pairing PASS
no UVM_ERROR / UVM_FATAL
```

### 18.7 P5G: Regression Inclusion

Add a small representative packed-read subset after manual runs pass.

Recommended first regression subset:

```text
gemm_2lane_packed_bcache_perf_profile
gemm_2lane_packed_bcache_dma_load_store_stress
gemm_2lane_packed_bcache_direct_stream_load_store_stress
```

Do not add all CDC variants immediately unless runtime is acceptable.

---

## 19. Suggested Tcl Runs

### 19.1 Packed B-Cache Perf Counter Smoke

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

do run_uvm.tcl
```

### 19.2 Packed B-Cache Perf Profile

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

do run_uvm.tcl
```

### 19.3 Packed B-Cache Direct Stream Smoke

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

do run_uvm.tcl
```

### 19.4 Packed B-Cache DMA Load-Store Stress

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

do run_uvm.tcl
```

### 19.5 Packed B-Cache AXI-Stream Load-Store Stress

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

do run_uvm.tcl
```

### 19.6 Packed B-Cache Direct Stream Load-Store Stress

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

do run_uvm.tcl
```

### 19.7 CDC Variant

Use the same stress commands and switch:

```tcl
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 13
```

---

## 20. Risk Analysis

### Risk 1: Byte-Lane Extraction Bug

Possible failure:

```text
wrong byte selected from mem_rd_data[31:0]
signedness lost during extraction
```

Mitigation:

```text
include positive and negative int8 data cases if available
compare against software reference
run CASE_ID=101/105/5
```

### Risk 2: Unaligned Base Address Bug

Possible failure:

```text
base_addr_b not 4-byte aligned
packed read includes bytes before B region
wrong values stored into b_cache
```

Mitigation:

```text
first implementation falls back to scalar preload when base_addr_b[1:0] != 0
run configurable base cases 400-403
```

### Risk 3: Direct Stream Router Range Bug

Possible failure:

```text
packed read aligned address starts before B operand region
router classifies read incorrectly
```

Mitigation:

```text
use aligned-base-only packed enable first
fallback to scalar preload for unaligned B base
run Direct Stream smoke/stress
```

### Risk 4: Scalar B-Cache Regression

Possible failure:

```text
existing P4 scalar B-cache preload breaks
```

Mitigation:

```text
default packed preload off
run 47/47 regression after safe parameter patch
run B-cache regression with packed disabled
```

### Risk 5: Done Timing Regression

Possible failure:

```text
packed preload changes busy/done sequencing
DMA store starts before final C write visible
```

Mitigation:

```text
preserve P4 done semantics:
GEMM done only after final C write completion
run Direct Stream and DMA store tests
```

### Risk 6: Performance Benefit Is Smaller Than Expected

Possible cause:

```text
preload time is only part of total busy time
A reads still dominate
adapter latency dominates
small matrices have limited savings
```

Mitigation:

```text
accept correctness first
profile before adding checks
consider packed A reads or A row cache later
```

---

## 21. Recommended Implementation Order

Recommended patch sequence:

```text
Patch 1:
  Add GEMM_ENABLE_PACKED_BCACHE_PRELOAD parameter default 0.
  Propagate through top-level and run script.
  Add clear_uvm_run_vars cleanup.
  Compile and run 47/47.

Patch 2:
  Add packed enable helper and debug display.
  Do not change FSM behavior yet.
  Compile and run focused no-change tests.

Patch 3:
  Add packed preload states and address registers.
  Use aligned-base-only activation.
  Fallback to scalar preload if unaligned.
  Compile.

Patch 4:
  Implement packed read issue and 32-bit unpack into b_cache.
  Run focused CASE_ID=100/101/105/5.

Patch 5:
  Run perf_counter_smoke RUN_ALL with packed preload enabled.

Patch 6:
  Run perf_profile with packed preload enabled and capture cycle profile.

Patch 7:
  Run Direct Stream smoke RUN_ALL.

Patch 8:
  Run stress / CDC subset.

Patch 9:
  Add selected packed-read subset to full regression.
```

---

## 22. Acceptance Criteria

P5 safe parameter patch is complete when:

```text
GEMM_ENABLE_PACKED_BCACHE_PRELOAD exists and defaults to 0.
Default full regression remains 47/47 PASS.
```

P5 packed preload prototype is complete when:

```text
GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1 focused tests PASS.
B-cache scalar fallback still works for unaligned base cases.
Result compare PASS.
MAC/output counters PASS.
No UVM_ERROR / UVM_FATAL.
```

P5 stress closure is complete when:

```text
Packed B-cache DMA load-store stress PASS.
Packed B-cache AXI-Stream load-store stress PASS.
Packed B-cache Direct Stream load-store stress PASS.
Selected CDC sanity PASS.
```

P5 regression closure is complete when:

```text
Selected packed-read subset is added to run_full_uvm_regression.tcl.
New full regression PASS.
```

---

## 23. Future Work After P5

After packed B-cache preload is stable, evaluate:

```text
packed scalar B-cache preload with unaligned base support
packed A compute reads
A row cache
A row cache + packed B-cache
read-request counters
larger GEMM dimensions
4-lane MAC
tile-based scheduling
Direct Stream true streaming compute
```

Recommended next candidate after packed B-cache preload:

```text
A row cache or packed A row read
```

Reason:

```text
After P4/P5, B-side repeated-read pressure is reduced.
A reads remain repeated across N columns.
A row reuse is the next major memory-read optimization.
```

---

## 24. Summary

P5 is the next natural step after P4 B-cache.

P4 reduced repeated B reads.

P5 should reduce the cost of filling the B-cache by using the existing 32-bit read data more efficiently.

The safest first implementation is:

```text
optional packed B-cache preload
default off
aligned B base only
scalar fallback for unaligned base
correctness first
profile second
stress/CDC third
regression inclusion last
```

The current `47/47 PASS` baseline gives a clean checkpoint for starting this work.
