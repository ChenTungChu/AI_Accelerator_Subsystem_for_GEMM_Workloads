# GEMM 2-Lane MAC Microarchitecture Spec

## 1. Purpose

This document defines and records the first performance-oriented GEMM datapath upgrade after the completed Performance Counter P0 and Performance Profile P1 baselines.

Current status:

```text
P0: passive GEMM performance counters completed
P1: performance profile test completed
P2: 2-lane K-parallel MAC prototype completed
P3: 2-lane stress / CDC hardening completed
P4: B-cache operand reuse optimization completed
P5: packed B-cache preload optimization completed
P6: scalar A-row cache optimization completed

Full regression:
  TOTAL : 56
  PASS  : 56
  FAIL  : 0
```

The goal of this milestone was to introduce a controlled 2-lane MAC datapath while preserving the existing single-MAC behavior as the default safe configuration.

This is the first step from:

```text
single-MAC iterative GEMM
```

toward:

```text
multi-MAC performance GEMM
```

The implementation remains incremental, measurable, and regression-safe.

---

## 2. Current Single-MAC Baseline

The single-lane GEMM algorithm is conceptually:

```text
for m in 0 .. M-1:
  for n in 0 .. N-1:
    acc = 0
    for k in 0 .. K-1:
      acc += A[m][k] * B[k][n]
    C[m][n] = acc
```

The single-lane RTL computes one multiply-accumulate operation per inner-loop MAC step.

Current P1 profile baseline:

```text
CASE_ID | M | N | K | MACS | OUTPUTS | GEMM_BUSY_CYCLES
100     | 1 | 1 | 1 | 1    | 1       | 24
101     | 2 | 2 | 2 | 8    | 4       | 230
105     | 2 | 3 | 4 | 24   | 6       | 603
5       | 4 | 4 | 4 | 64   | 16      | 1638
400     | 4 | 4 | 4 | 64   | 16      | 1637
401     | 4 | 4 | 4 | 64   | 16      | 1637
402     | 4 | 4 | 4 | 64   | 16      | 1637
403     | 4 | 4 | 4 | 64   | 16      | 1637
```

This baseline remains reproducible with `GEMM_MAC_LANES=1`.

---

## 3. 2-Lane Profile Baseline

The implemented 2-lane profile baseline is:

```text
CASE_ID | M | N | K | MACS | OUTPUTS | GEMM_BUSY_CYCLES
100     | 1 | 1 | 1 | 1    | 1       | 24
101     | 2 | 2 | 2 | 8    | 4       | 224
105     | 2 | 3 | 4 | 24   | 6       | 594
5       | 4 | 4 | 4 | 64   | 16      | 1609
400     | 4 | 4 | 4 | 64   | 16      | 1610
401     | 4 | 4 | 4 | 64   | 16      | 1610
402     | 4 | 4 | 4 | 64   | 16      | 1610
403     | 4 | 4 | 4 | 64   | 16      | 1610
```

`CASE_ID=100` has `K=1`, so lane 1 is masked and the cycle count remains unchanged. Cases with `K>=2` show reduced busy cycles compared with the single-lane baseline.

---

## 4. Design Goals

The 2-lane MAC milestone required:

1. Preserve the full regression baseline with default configuration.
2. Add a `GEMM_MAC_LANES` parameter.
3. Keep `GEMM_MAC_LANES=1` behavior equivalent to the current single-MAC implementation.
4. Add `GEMM_MAC_LANES=2` K-parallel execution.
5. Preserve signed int8 A/B behavior and signed int32 accumulation.
6. Preserve row-major A/B/C layout.
7. Preserve C writeback format and scratchpad address mapping.
8. Preserve Direct Stream B1 compatibility through `gemm_input_mem_router`.
9. Preserve performance counter semantics.
10. Verify result correctness before optimizing memory bandwidth.

Status:

```text
All goals completed for P2.
```

---

## 5. Non-Goals for the First 2-Lane Step

The first 2-lane step does not attempt to:

- implement a full systolic array
- implement tile scheduling
- widen the scratchpad memory interface
- widen the operand buffer interface
- stream C directly to S2MM
- change A/B/C storage format
- change the scoreboard reference model
- change DMA / AXI-Stream / Direct Stream frontends
- require exact cycle-count matching in regression
- guarantee 2x end-to-end speedup

The implementation is a correctness-first 2-lane prototype.

---

## 6. Parameter Definition

The GEMM lane parameter is:

```systemverilog
parameter int GEMM_MAC_LANES = 1
```

Supported values:

```text
1 = current single-MAC baseline
2 = 2-lane K-parallel prototype
```

Unsupported values should remain guarded by elaboration-time checks.

Default:

```systemverilog
GEMM_MAC_LANES = 1
```

This ensures existing regression remains unchanged unless a test or run configuration explicitly selects 2 lanes.

The parameter is propagated through:

```text
ai_accel_subsys_uvm_top
    -> ai_accel_subsys
    -> gemm_top
```

The run script forwards it through a simulator parameter override.

---

## 7. 2-Lane Algorithm

### 7.1 K-Parallel Accumulation

For each output element `C[m][n]`, the 2-lane version processes up to two K indices per accumulation step.

Current single-MAC:

```text
for k in 0 .. K-1:
    acc += A[m][k] * B[k][n]
```

2-lane K-parallel:

```text
for k in 0 .. K-1 step 2:
    acc += A[m][k + 0] * B[k + 0][n]

    if (k + 1 < K):
        acc += A[m][k + 1] * B[k + 1][n]
```

### 7.2 Lane Valid Rules

For `GEMM_MAC_LANES=2`:

```text
lane0_valid = (k_idx < dim_k)
lane1_valid = ((k_idx + 1) < dim_k)
```

In normal execution, lane 0 is always valid while inside the K loop. Lane 1 handles even/odd K.

Examples:

```text
K = 1:
  iteration 0: lane0 valid, lane1 invalid

K = 2:
  iteration 0: lane0 valid, lane1 valid

K = 3:
  iteration 0: lane0 valid, lane1 valid
  iteration 1: lane0 valid, lane1 invalid

K = 4:
  iteration 0: lane0 valid, lane1 valid
  iteration 1: lane0 valid, lane1 valid
```

---

## 8. Memory Access Strategy

### 8.1 Correctness-First Strategy

The existing GEMM local memory interface provides one read request at a time:

```systemverilog
output logic                  mem_rd_en;
output logic [ADDR_WIDTH-1:0] mem_rd_addr;
input  logic [31:0]           mem_rd_data;
input  logic                  mem_rd_valid;
```

The first 2-lane implementation does not widen this interface.

Instead, it sequentially reads operands for both lanes:

```text
read A0 = A[m][k + 0]
read B0 = B[k + 0][n]

if lane1_valid:
    read A1 = A[m][k + 1]
    read B1 = B[k + 1][n]

compute:
    acc += A0*B0 + optional A1*B1
```

### 8.2 Expected Performance Impact

Because the first 2-lane version still performs sequential operand reads, the speedup is modest.

The main reduction comes from:

```text
fewer K-loop control iterations
fewer MAC states
fewer NEXT-to-read transitions within each C output
```

It does not reduce total operand reads.

Therefore:

```text
MAC count remains M*N*K
output count remains M*N
read request count would remain approximately 2*M*N*K if read counters are added later
busy cycles improve somewhat for K >= 2, but do not approach 2x
```

---

## 9. Address Generation

A is row-major:

```text
A[m][k] address = base_addr_a + (m * K + k) * A_BYTES
```

B is row-major:

```text
B[k][n] address = base_addr_b + (k * N + n) * B_BYTES
```

C is row-major:

```text
C[m][n] address = base_addr_c + (m * N + n) * C_BYTES
```

For lane 0:

```text
k0 = k_idx
A0 address = base_addr_a + (m_idx * dim_k + k0) * A_BYTES
B0 address = base_addr_b + (k0 * dim_n + n_idx) * B_BYTES
```

For lane 1:

```text
k1 = k_idx + 1
A1 address = base_addr_a + (m_idx * dim_k + k1) * A_BYTES
B1 address = base_addr_b + (k1 * dim_n + n_idx) * B_BYTES
```

Lane 1 addresses must only be used when:

```text
k_idx + 1 < dim_k
```

---

## 10. Datapath Registers

The 2-lane implementation adds lane-1 storage:

```systemverilog
logic signed [A_DATA_WIDTH-1:0] a1_val_q, a1_val_d;
logic signed [B_DATA_WIDTH-1:0] b1_val_q, b1_val_d;
logic                           lane1_valid_q, lane1_valid_d;
```

The existing lane-0 storage remains:

```text
a_val_q / b_val_q = lane0
```

---

## 11. FSM Strategy

### 11.1 Single-Lane Path

`GEMM_MAC_LANES=1` preserves the original single-lane path:

```text
S_IDLE
  -> S_READ_A
  -> S_WAIT_A
  -> S_READ_B
  -> S_WAIT_B
  -> S_MAC
  -> S_WRITE_C or S_READ_A
  -> S_NEXT
  -> S_DONE
```

### 11.2 2-Lane Path

The implemented state set adds:

```text
S_READ_A1
S_WAIT_A1
S_READ_B1
S_WAIT_B1
```

If lane 1 is valid:

```text
S_IDLE
  -> S_READ_A
  -> S_WAIT_A
  -> S_READ_B
  -> S_WAIT_B
  -> S_READ_A1
  -> S_WAIT_A1
  -> S_READ_B1
  -> S_WAIT_B1
  -> S_MAC
  -> S_WRITE_C or S_READ_A
  -> S_NEXT
  -> S_DONE
```

If lane 1 is invalid:

```text
S_IDLE
  -> S_READ_A
  -> S_WAIT_A
  -> S_READ_B
  -> S_WAIT_B
  -> S_MAC
  -> S_WRITE_C
  -> S_NEXT
  -> S_DONE
```

---

## 12. K Index Update Rules

### 12.1 Single-Lane Mode

```text
if k_idx == dim_k - 1:
    write C
else:
    k_idx = k_idx + 1
    continue
```

### 12.2 2-Lane Mode

After the 2-lane MAC step:

```text
if (k_idx + 2 >= dim_k):
    write C
else:
    k_idx = k_idx + 2
    continue
```

---

## 13. MAC Computation

### 13.1 Single-Lane Mode

```systemverilog
acc_d = acc_q + (a_val_q * b_val_q);
```

### 13.2 2-Lane Mode

Conceptual behavior:

```systemverilog
lane0_product = a_val_q  * b_val_q;
lane1_product = a1_val_q * b1_val_q;

if (lane1_valid_q) begin
    mac_sum = lane0_product + lane1_product;
end
else begin
    mac_sum = lane0_product;
end

acc_d = acc_q + mac_sum;
```

---

## 14. Performance Counter Requirements

Existing counters:

```systemverilog
gemm_perf_busy_cycles
gemm_perf_mac_count
gemm_perf_output_count
```

Required behavior:

```text
gemm_perf_busy_cycles:
    increments while GEMM is busy

gemm_perf_mac_count:
    increments by number of valid MAC lanes committed

gemm_perf_output_count:
    increments once per completed C write
```

Counter clear policy:

```text
clear on reset
clear on accepted GEMM start
```

Counter snapshot policy:

```text
stable after done until next accepted GEMM start
```

Expected values remain:

```text
MAC_COUNT    = M * N * K
OUTPUT_COUNT = M * N
```

For 2-lane mode, `gemm_perf_mac_count` equals `M*N*K`, not the number of 2-lane loop iterations.

---

## 15. UVM Verification Status

Completed P2/P3 verification:

```text
GEMM_MAC_LANES=1 full regression                       PASS
GEMM_MAC_LANES=2 perf_counter_smoke                    PASS
GEMM_MAC_LANES=2 perf_profile                          PASS
GEMM_MAC_LANES=2 direct_stream_smoke                   PASS
GEMM_MAC_LANES=2 DMA load-store stress                 PASS
GEMM_MAC_LANES=2 AXI-Stream load-store stress          PASS
GEMM_MAC_LANES=2 Direct Stream load-store stress       PASS
GEMM_MAC_LANES=2 DMA load-store CDC sanity             PASS
GEMM_MAC_LANES=2 AXI-Stream load-store CDC sanity      PASS
GEMM_MAC_LANES=2 Direct Stream load-store CDC sanity   PASS
```

2-lane subset in regression:

```text
gemm_2lane_perf_counter_smoke
gemm_2lane_perf_profile
gemm_2lane_direct_stream_smoke
gemm_2lane_dma_load_store_stress
gemm_2lane_axis_stream_load_store_stress
gemm_2lane_direct_stream_load_store_stress
gemm_2lane_dma_load_store_cdc
gemm_2lane_axis_stream_load_store_cdc
gemm_2lane_direct_stream_load_store_cdc
```

Current regression:

```text
56/56 PASS
```

---

## 16. Direct Stream Compatibility

Direct Stream B1 routes GEMM A/B reads through:

```text
gemm_input_mem_router
```

In stream mode:

```text
GEMM A/B reads -> gemm_operand_buffer
GEMM C writes  -> scratchpad
```

The 2-lane implementation keeps the same single-read GEMM local memory interface, so it remains compatible with:

```text
scratchpad mode
Direct Stream operand-buffer mode
```

Verified:

```text
ai_accel_subsys_direct_stream_smoke_test RUN_ALL=1 with GEMM_MAC_LANES=2
```

This verifies:

```text
Direct Stream preload A/B
operand buffer write path
GEMM input router read classification
2-lane GEMM read order
scratchpad C write
DMA store C
scoreboard compare
ctrl/result pairing
```

---

## 16A. P3 Stress / CDC Verification

P3 extends the original 2-lane smoke/profile coverage into repeated load-store stress and non-default clock-ratio sanity.

Verified stress paths:

```text
DMA load A/B -> GEMM 2-lane -> DMA store C
AXI-Stream preload A/B -> GEMM 2-lane -> DMA store C
Direct Stream preload A/B -> GEMM 2-lane -> DMA store C
```

Verified clock ratios:

```text
default stress ratio : dma_clk=10ns, core_clk=14ns
CDC sanity ratio     : dma_clk=10ns, core_clk=13ns
```

Regression items added in P3:

```text
gemm_2lane_dma_load_store_stress
gemm_2lane_axis_stream_load_store_stress
gemm_2lane_direct_stream_load_store_stress
gemm_2lane_dma_load_store_cdc
gemm_2lane_axis_stream_load_store_cdc
gemm_2lane_direct_stream_load_store_cdc
```

All P3 items complete with:

```text
result compare PASS
control/result pairing PASS
UVM_WARNING=0
UVM_ERROR=0
UVM_FATAL=0
```

---

---

## 16B. P4 B-Cache Compatibility

P4 layers an optional B-operand cache on top of the 2-lane datapath.

New GEMM parameters:

```systemverilog
parameter bit GEMM_ENABLE_B_CACHE = 1'b0;
parameter int GEMM_B_CACHE_MAX_K  = 4;
parameter int GEMM_B_CACHE_MAX_N  = 4;
```

Default behavior remains the original no-cache path:

```text
GEMM_ENABLE_B_CACHE=0
```

When B-cache is active, lane B operands are sourced locally:

```text
lane0 B = b_cache[k_idx][n_idx]
lane1 B = b_cache[k_idx + 1][n_idx], when lane1_valid
```

A operands continue to use the existing local memory read path:

```text
scratchpad mode     : A reads from scratchpad
Direct Stream mode  : A reads from gemm_operand_buffer through gemm_input_mem_router
```

B-cache preload uses the same local GEMM memory read interface, so it remains compatible with both scratchpad-backed and Direct Stream operand-buffer modes.

### Done / C visibility semantic

P4 also strengthens the GEMM completion contract.

Before the fix, `done` could mean:

```text
last C write request accepted
```

After the P4 fix, `done` means:

```text
last C write completed and is safe for a following DMA store / readback flow
```

This was validated because Direct Stream + B-cache + immediate DMA store exposed the unsafe earlier semantic.

### P4 B-cache verification

Completed B-cache validation:

```text
B-cache perf counter smoke/profile                      PASS
B-cache Direct Stream smoke RUN_ALL                     PASS
B-cache DMA load-store stress                           PASS
B-cache AXI-Stream load-store stress                    PASS
B-cache Direct Stream load-store stress                 PASS
B-cache DMA / AXI-Stream / Direct Stream CDC subset     PASS
B-cache representative full regression                  PASS
```

Representative B-cache regression items:

```text
gemm_2lane_bcache_dma_load_store_stress
gemm_2lane_bcache_axis_stream_load_store_stress
gemm_2lane_bcache_direct_stream_load_store_stress
```

Final full regression after P4:

```text
47/47 PASS
```

## 17. Edge Cases Verified

### K = 1

Only lane 0 is valid.

Expected:

```text
lane0 MAC committed
lane1 masked
mac_count += 1
write C
```

Covered by:

```text
CASE_ID=100
```

### K = 2

Both lanes valid in one K-group.

Covered by:

```text
CASE_ID=101
```

### K = 4

Two full K-groups.

Covered by:

```text
CASE_ID=105
CASE_ID=5
CASE_ID=400/401/402/403
```

### Configurable base cases

Cases 400-403 pass in the 2-lane profile and Direct Stream smoke runs.

This verifies that lane-1 address calculation honors shifted legal base addresses.

---

## 18. Risk Analysis

### Risk 1: Off-by-one bug in K loop

Mitigation:

```text
K=1, K=2, K=4 cases are in regression
mac_count exactly equals M*N*K
scoreboard result compare passes
```

### Risk 2: Lane 1 address generated when invalid

Mitigation:

```text
lane1 read states are entered only when lane1_valid is true
CASE_ID=100 validates lane1 masking
```

### Risk 3: Counter counts MAC states instead of logical MACs

Mitigation:

```text
mac_count increments by valid lane count
perf_counter_smoke checks exact M*N*K
```

### Risk 4: Direct Stream operand buffer read ordering mismatch

Mitigation:

```text
Direct Stream smoke with GEMM_MAC_LANES=2 is in regression
```

### Risk 5: Single-lane regression changes

Mitigation:

```text
default parameter remains 1
full 56-item regression includes single-lane mainline coverage
```

---

## 19. Milestone Closure

### P2A: Parameterized Single-Lane Safe Patch

```text
DONE
GEMM_MAC_LANES parameter exists
default GEMM_MAC_LANES=1
full regression remained clean
```

### P2B: 2-Lane FSM / Datapath

```text
DONE
lane1 states added
lane1 registers added
2-lane accumulation added
logical MAC counter update added
```

### P2C: 2-Lane Profile Baseline

```text
DONE
2-lane profile summary captured
host-primary profile path passed
```

### P2D: 2-Lane Direct Stream Compatibility

```text
DONE
Direct Stream smoke RUN_ALL passed with GEMM_MAC_LANES=2
```

### P2E: 2-Lane Subset Regression

```text
DONE
3 focused 2-lane tests added to regression
```

### P2 Final

```text
DONE
single-lane full regression clean
2-lane host-primary/profile clean
2-lane Direct Stream clean
historical P2 regression PASS
```

### P3A: 2-Lane DMA Load-Store Stress

```text
DONE
8-job random stress passed
dma_clk=10ns, core_clk=14ns
```

### P3B: 2-Lane AXI-Stream Load-Store Stress

```text
DONE
8-job random stress passed
dma_clk=10ns, core_clk=14ns
```

### P3C: 2-Lane Direct Stream Load-Store Stress

```text
DONE
8-job random stress passed
dma_clk=10ns, core_clk=14ns
```

### P3D: 2-Lane CDC Sanity

```text
DONE
DMA load-store CDC passed
AXI-Stream load-store CDC passed
Direct Stream load-store CDC passed
dma_clk=10ns, core_clk=13ns
```

### P3E: 2-Lane Stress / CDC Regression

```text
DONE
6 focused P3 tests added to regression
historical P3 regression: 44/44 PASS
```

---


### P4A: B-Cache Parameterization

```text
DONE
GEMM_ENABLE_B_CACHE parameter exists
GEMM_B_CACHE_MAX_K / GEMM_B_CACHE_MAX_N parameters exist
default no-cache behavior remains protected
```

### P4B/P4C: B-Cache RTL and Compute Bypass

```text
DONE
B-cache storage added
B-cache preload FSM added
lane0/lane1 B-cache compute bypass added
unsupported dimensions fall back to no-cache path
```

### P4D: B-Cache Direct Stream Compatibility

```text
DONE
Direct Stream smoke RUN_ALL passed with GEMM_MAC_LANES=2 and GEMM_ENABLE_B_CACHE=1
```

### P4E: B-Cache Stress / CDC Manual Subset

```text
DONE
DMA load-store stress passed
AXI-Stream load-store stress passed
Direct Stream load-store stress passed
CDC subset passed at dma_clk=10ns, core_clk=13ns
```

### P4F: B-Cache Regression Inclusion

```text
DONE
3 focused B-cache tests added to regression
47/47 PASS
```

## 20. Recommended Next Steps

P4 is complete. The next recommended stage is:

```text
P5: 32-bit packed operand read / scratchpad bandwidth utilization
```

Evaluate memory bandwidth improvements:

```text
32-bit packed int8 operand reads
aligned byte-lane extraction
reduced narrow operand-read request count
optional read/hit counters for profile visibility
larger tile scheduling after packed reads are stable
```text
operand staging registers
wider local read extraction
operand-buffer multi-read support
Direct Stream tiled operand reuse
```

---

## 21. Summary

The 2-lane GEMM milestone and the P4/P5/P6 operand-bandwidth milestones are complete.

The key rule was:

```text
Preserve single-lane correctness first.
Add 2-lane correctness second.
Measure performance third.
Optimize bandwidth later.
```

Current result:

```text
GEMM_MAC_LANES=1 mainline remains clean
GEMM_MAC_LANES=2 correctness and profile are verified
DMA / AXI-Stream / Direct Stream stress are verified
DMA / AXI-Stream / Direct Stream CDC sanity is verified
2-lane stress / CDC subset is part of full regression
B-cache representative subset is part of full regression
packed B-cache representative subset is part of full regression
A-row cache stress / CDC representative subset is part of full regression
56/56 PASS
```



## P5 Packed B-Cache Preload Microarchitecture Addendum

P5 does not change the 2-lane MAC arithmetic datapath. It changes how the B-cache is filled before compute.

Packed preload activation:

```text
GEMM_MAC_LANES=2
GEMM_ENABLE_B_CACHE=1
GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1
base_addr_b[1:0] == 0
```

Packed preload FSM states added to `gemm_top`:

```text
S_BCACHE_PACK_INIT
S_BCACHE_PACK_READ
S_BCACHE_PACK_WAIT
S_BCACHE_PACK_NEXT
```

Packed preload data mapping:

```text
mem_rd_data[ 7: 0] -> B linear index + 0
mem_rd_data[15: 8] -> B linear index + 1
mem_rd_data[23:16] -> B linear index + 2
mem_rd_data[31:24] -> B linear index + 3
```

The compute source remains unchanged from P4 once the cache is filled:

```text
lane0 B operand = b_cache[k + 0][n]
lane1 B operand = b_cache[k + 1][n] when lane1_valid
```

The scratchpad adapter now returns a 32-bit byte window on local reads, which enables packed preload while preserving scalar compatibility for existing local reads.

P5 closure:

```text
P5A/P5B/P5C/P5D/P5E/P5F/P5G PASS
Final full regression: 50/50 PASS
```




## P6 Scalar A-Row Cache Microarchitecture Addendum

P6 does not change the 2-lane MAC arithmetic datapath. It changes how A operands are supplied to the MAC when the completed performance stack is enabled.

Validated activation:

```text
GEMM_MAC_LANES=2
GEMM_ENABLE_B_CACHE=1
GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1
GEMM_ENABLE_A_ROW_CACHE=1
GEMM_A_ROW_CACHE_MAX_K=4
```

A-row cache behavior:

```text
for each output row m:
  preload A[m][0 .. K-1] once into a_row_cache
  for each output column n:
    lane0 A operand = a_row_cache[k + 0]
    lane1 A operand = a_row_cache[k + 1] when lane1_valid
```

The B operand source remains the P4/P5 B-cache path:

```text
lane0 B operand = b_cache[k + 0][n]
lane1 B operand = b_cache[k + 1][n] when lane1_valid
```

The 2-lane MAC commit rule remains unchanged:

```text
acc += lane0_product + optional lane1_product
mac_count increments by the number of valid lanes
output_count increments after C write completion
```

P6 focused profile:

```text
CASE_ID | M | N | K | MACS | OUTPUTS | BUSY
100     | 1 | 1 | 1 | 1    | 1       | 43
101     | 2 | 2 | 2 | 8    | 4       | 152
105     | 2 | 3 | 4 | 24   | 6       | 275
5       | 4 | 4 | 4 | 64   | 16      | 627
400     | 4 | 4 | 4 | 64   | 16      | 627
401     | 4 | 4 | 4 | 64   | 16      | 627
402     | 4 | 4 | 4 | 64   | 16      | 627
403     | 4 | 4 | 4 | 64   | 16      | 627
```

P6 closure:

```text
P6A/P6B/P6C/P6D/P6E/P6F/P6G PASS
Final full regression: 56/56 PASS
```

