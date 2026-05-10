# GEMM 2-Lane MAC Microarchitecture Spec

## 1. Purpose

This document defines the first performance-oriented GEMM datapath upgrade after the completed Performance Counter P0 and Performance Profile P1 baselines.

Current baseline:

```text
P0: passive GEMM performance counters completed
P1: performance profile test completed

Full regression:
  TOTAL : 35
  PASS  : 35
  FAIL  : 0
```

The goal of this milestone is to introduce a controlled 2-lane MAC datapath while preserving the existing single-MAC behavior as the default safe configuration.

This is the first step from:

```text
single-MAC iterative GEMM
```

toward:

```text
multi-MAC performance GEMM
```

The implementation must remain incremental, measurable, and regression-safe.

---

## 2. Current Single-MAC Baseline

The current GEMM algorithm is conceptually:

```text
for m in 0 .. M-1:
  for n in 0 .. N-1:
    acc = 0
    for k in 0 .. K-1:
      acc += A[m][k] * B[k][n]
    C[m][n] = acc
```

The current RTL computes one multiply-accumulate operation per inner-loop MAC step.

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

This baseline must remain reproducible with `GEMM_MAC_LANES=1`.

---

## 3. Design Goals

The 2-lane MAC milestone must:

1. Preserve the current 35/35 full regression baseline with default configuration.
2. Add a `GEMM_MAC_LANES` parameter.
3. Keep `GEMM_MAC_LANES=1` behavior equivalent to the current single-MAC implementation.
4. Add `GEMM_MAC_LANES=2` K-parallel execution.
5. Preserve signed int8 A/B behavior and signed int32 accumulation.
6. Preserve row-major A/B/C layout.
7. Preserve C writeback format and scratchpad address mapping.
8. Preserve Direct Stream B1 compatibility through `gemm_input_mem_router`.
9. Preserve performance counter semantics.
10. Verify result correctness before optimizing memory bandwidth.

---

## 4. Non-Goals for the First 2-Lane Step

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

The first implementation is a correctness-first 2-lane prototype.

---

## 5. Parameter Definition

Add a GEMM lane parameter to `gemm_top.sv`.

Recommended parameter:

```systemverilog
parameter int GEMM_MAC_LANES = 1
```

Supported values for this milestone:

```text
1 = current single-MAC baseline
2 = 2-lane K-parallel prototype
```

Unsupported values should be guarded.

Recommended elaboration-time check:

```systemverilog
initial begin
    if ((GEMM_MAC_LANES != 1) && (GEMM_MAC_LANES != 2)) begin
        $fatal(1, "Unsupported GEMM_MAC_LANES=%0d. Supported values are 1 and 2.",
               GEMM_MAC_LANES);
    end
end
```

Default must be:

```systemverilog
GEMM_MAC_LANES = 1
```

This ensures existing regression remains unchanged unless a test or compile configuration explicitly selects 2 lanes.

---

## 6. 2-Lane Algorithm

### 6.1 K-Parallel Accumulation

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

### 6.2 Lane Valid Rules

For `GEMM_MAC_LANES=2`:

```text
lane0_valid = (k_idx < dim_k)
lane1_valid = ((k_idx + 1) < dim_k)
```

In normal execution, `lane0_valid` should always be true while inside the K loop. `lane1_valid` handles odd K.

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

## 7. Memory Access Strategy

### 7.1 Correctness-First Strategy

The existing GEMM local memory interface provides one read request at a time:

```systemverilog
output logic                  mem_rd_en;
output logic [ADDR_WIDTH-1:0] mem_rd_addr;
input  logic [31:0]           mem_rd_data;
input  logic                  mem_rd_valid;
```

For the first 2-lane implementation, do not widen this interface.

Instead, use sequential reads to collect operands for both lanes:

```text
read A0 = A[m][k + 0]
read B0 = B[k + 0][n]

if lane1_valid:
    read A1 = A[m][k + 1]
    read B1 = B[k + 1][n]

compute:
    acc += A0*B0 + optional A1*B1
```

This is not the final high-bandwidth architecture, but it is the safest first implementation.

### 7.2 Expected Performance Impact

Because the first 2-lane version still performs sequential operand reads, the speedup may be modest.

The main reduction comes from:

```text
fewer K-loop control iterations
fewer MAC states
fewer NEXT-to-read transitions within each C output
```

It does not reduce the total number of operand reads.

Therefore:

```text
MAC count remains M*N*K
output count remains M*N
read request count would remain approximately 2*M*N*K if read counters are added later
busy cycles should improve somewhat for K >= 2, but not necessarily approach 2x
```

### 7.3 Future Bandwidth-Oriented Upgrade

A later step may improve memory bandwidth using one of these approaches:

```text
Approach A: wider local read data extraction
Approach B: row/column operand staging registers
Approach C: operand-buffer multi-read support
Approach D: Direct Stream tiled operand reuse
```

These are out of scope for the first 2-lane implementation.

---

## 8. Address Generation

### 8.1 Existing Address Formula

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

### 8.2 Lane Address Formula

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

## 9. Datapath Registers

Recommended additional registers for 2-lane mode:

```systemverilog
logic signed [A_DATA_WIDTH-1:0] a1_val_q, a1_val_d;
logic signed [B_DATA_WIDTH-1:0] b1_val_q, b1_val_d;
logic                           lane1_valid_q, lane1_valid_d;
```

For minimum patch risk, keep existing:

```text
a_val_q / b_val_q = lane0
```

and add:

```text
a1_val_q / b1_val_q = lane1
```

This minimizes rewrite risk inside the current `gemm_top.sv`.

---

## 10. FSM Strategy

### 10.1 Keep Single-Lane Path Stable

The lowest-risk approach is to preserve the current single-lane FSM behavior when:

```text
GEMM_MAC_LANES == 1
```

Then add additional lane-1 read states that are only used when:

```text
GEMM_MAC_LANES == 2 && lane1_valid
```

### 10.2 Suggested FSM States

Current states:

```text
S_IDLE
S_READ_A
S_WAIT_A
S_READ_B
S_WAIT_B
S_MAC
S_WRITE_C
S_NEXT
S_DONE
```

Recommended minimal new states:

```text
S_READ_A1
S_WAIT_A1
S_READ_B1
S_WAIT_B1
```

So the full state set becomes:

```text
S_IDLE
S_READ_A
S_WAIT_A
S_READ_B
S_WAIT_B
S_READ_A1
S_WAIT_A1
S_READ_B1
S_WAIT_B1
S_MAC
S_WRITE_C
S_NEXT
S_DONE
```

### 10.3 State Flow for `GEMM_MAC_LANES=1`

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

This should match current behavior.

### 10.4 State Flow for `GEMM_MAC_LANES=2`

If lane1 is valid:

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

If lane1 is invalid:

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

## 11. K Index Update Rules

### 11.1 Single-Lane Mode

Existing behavior:

```text
if k_idx == dim_k - 1:
    write C
else:
    k_idx = k_idx + 1
    continue
```

### 11.2 2-Lane Mode

After the 2-lane MAC step:

```text
if (k_idx + 2 >= dim_k):
    write C
else:
    k_idx = k_idx + 2
    continue
```

Conceptual RTL:

```systemverilog
if (GEMM_MAC_LANES == 2) begin
    if ((k_idx_q + 2) >= dim_k) begin
        state_d = S_WRITE_C;
    end
    else begin
        k_idx_d = k_idx_q + 2;
        state_d = S_READ_A;
    end
end
```

Use clear helper logic to avoid off-by-one errors.

---

## 12. MAC Computation

### 12.1 Single-Lane Mode

```systemverilog
acc_d = acc_q + (a_val_q * b_val_q);
```

### 12.2 2-Lane Mode

Recommended signed intermediate products:

```systemverilog
logic signed [ACC_WIDTH-1:0] lane0_product;
logic signed [ACC_WIDTH-1:0] lane1_product;
logic signed [ACC_WIDTH-1:0] mac_sum;
```

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

### 12.3 Counter Behavior

The `gemm_perf_mac_count` counter must count logical MAC operations, not MAC-state executions.

Therefore:

```text
single-lane MAC state:
    +1

2-lane MAC state with lane1_valid=1:
    +2

2-lane MAC state with lane1_valid=0:
    +1
```

This preserves:

```text
gemm_perf_mac_count == M * N * K
```

---

## 13. Performance Counter Requirements

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
    increments once per accepted C write
```

Counter clear policy remains unchanged:

```text
clear on reset
clear on accepted GEMM start
```

Counter snapshot policy remains unchanged:

```text
stable after done until next accepted GEMM start
```

Expected values remain:

```text
MAC_COUNT    = M * N * K
OUTPUT_COUNT = M * N
```

For 2-lane mode, `gemm_perf_mac_count` must still equal `M*N*K`, not the number of 2-lane loop iterations.

---

## 14. Expected Profile Behavior

### 14.1 Correctness Counters

For both `GEMM_MAC_LANES=1` and `GEMM_MAC_LANES=2`:

```text
CASE_ID=100:
  MAC_COUNT = 1
  OUTPUT_COUNT = 1

CASE_ID=101:
  MAC_COUNT = 8
  OUTPUT_COUNT = 4

CASE_ID=105:
  MAC_COUNT = 24
  OUTPUT_COUNT = 6

CASE_ID=5/400/401/402/403:
  MAC_COUNT = 64
  OUTPUT_COUNT = 16
```

### 14.2 Busy Cycle Expectations

Exact 2-lane cycle counts should not be locked in the first test.

Initial rule:

```text
busy_cycles must be non-zero
busy-cycle profile must be printed
```

Recommended later rule after tuning:

```text
For K >= 2, 2-lane GEMM busy_cycles should be lower than single-lane baseline.
```

---

## 15. RTL Integration Plan

### 15.1 Files Likely to Change

Primary RTL:

```text
rtl/gemm/gemm_top.sv
```

Top-level parameter propagation may also touch:

```text
rtl/top/ai_accel_subsys.sv
tb/top/ai_accel_subsys_uvm_top.sv
```

If the parameter remains local to `gemm_top.sv` defaulting to 1, top-level propagation can be delayed.

### 15.2 Recommended First RTL Patch Strategy

Patch sequence:

```text
Patch 1:
  Add GEMM_MAC_LANES parameter with default 1.
  Do not change behavior.
  Compile.
  Run 35/35 regression.

Patch 2:
  Add lane1 registers and new FSM states.
  Keep GEMM_MAC_LANES=1 path equivalent.
  Compile.
  Run focused smoke.

Patch 3:
  Enable GEMM_MAC_LANES=2 path.
  Run single-case 2-lane smoke.

Patch 4:
  Run 2-lane profile test or reuse existing profile with lane parameter.
  Compare profile summary.

Patch 5:
  Run full baseline with lanes=1.
  Run selected 2-lane subset.
```

---

## 16. UVM Verification Plan

### 16.1 Keep Existing Baseline

The current full regression must remain:

```text
35/35 PASS
```

with:

```text
GEMM_MAC_LANES=1
```

### 16.2 New 2-Lane Smoke Test

Recommended new test:

```text
ai_accel_subsys_gemm_2lane_smoke_test.sv
```

Recommended flow:

```text
host-primary path
CASE_ID=100
CASE_ID=101
CASE_ID=105
CASE_ID=5
scoreboard compare enabled
counter check enabled
```

Expected:

```text
result compare PASS
mac_count == M*N*K
output_count == M*N
busy_cycles > 0
```

### 16.3 New 2-Lane Profile Test

Options:

```text
Option A:
  reuse ai_accel_subsys_perf_profile_test with GEMM_MAC_LANES=2

Option B:
  create ai_accel_subsys_gemm_2lane_profile_test
```

Recommended first approach:

```text
Option A
```

Reason:

```text
avoid duplicating profile code
same profile summary format makes comparison easier
```

### 16.4 Suggested 2-Lane Regression Subset

Initial subset:

```text
ai_accel_subsys_perf_counter_smoke_test RUN_ALL=1, GEMM_MAC_LANES=2
ai_accel_subsys_perf_profile_test, GEMM_MAC_LANES=2
ai_accel_subsys_direct_stream_smoke_test RUN_ALL=1, GEMM_MAC_LANES=2
```

Then expand to:

```text
DMA load-store stress, GEMM_MAC_LANES=2
AXI-Stream load-store stress, GEMM_MAC_LANES=2
Direct Stream load-store stress, GEMM_MAC_LANES=2
CDC clock-ratio sanity, GEMM_MAC_LANES=2
```

### 16.5 Acceptance Criteria for First 2-Lane Test

Complete when:

```text
single-lane full regression remains 35/35 PASS
2-lane host-primary smoke/profile passes
2-lane Direct Stream smoke passes
2-lane mac_count/output_count counters pass
scoreboard result compare passes
no UVM_ERROR / UVM_FATAL
```

---

## 17. Direct Stream Compatibility

Direct Stream B1 routes GEMM A/B reads through:

```text
gemm_input_mem_router
```

In stream mode:

```text
GEMM A/B reads -> gemm_operand_buffer
GEMM C writes  -> scratchpad
```

The 2-lane implementation must not assume scratchpad-only behavior.

Because the first 2-lane design still uses the same single-read GEMM local memory interface, it should remain compatible with:

```text
scratchpad mode
Direct Stream operand-buffer mode
```

Required Direct Stream check:

```text
ai_accel_subsys_direct_stream_smoke_test RUN_ALL=1 with GEMM_MAC_LANES=2
```

This proves the new read order and k-step behavior still work through `gemm_input_mem_router`.

---

## 18. Edge Cases

### 18.1 K = 1

Only lane 0 is valid.

Expected:

```text
lane0 MAC committed
lane1 masked
mac_count += 1
write C
```

### 18.2 K = 2

Both lanes valid in one K-group.

Expected:

```text
lane0 MAC committed
lane1 MAC committed
mac_count += 2
write C
```

### 18.3 K = 3

Two K-groups:

```text
group 0:
  k=0, lane0 valid
  k=1, lane1 valid
  mac_count += 2

group 1:
  k=2, lane0 valid
  lane1 invalid
  mac_count += 1
```

### 18.4 K = 4

Two full K-groups:

```text
group 0:
  k=0,1
  mac_count += 2

group 1:
  k=2,3
  mac_count += 2
```

### 18.5 Configurable Base Cases

Cases 400-403 must still pass.

This verifies that lane 1 address calculation honors shifted legal base addresses.

---

## 19. Risk Analysis

### Risk 1: Off-by-one bug in K loop

Most likely failure mode:

```text
missing final odd-K lane
double-counting final lane
incorrect transition to WRITE_C
```

Mitigation:

```text
test K=1, K=2, K=3, K=4
check mac_count exactly equals M*N*K
scoreboard compare
```

### Risk 2: Lane 1 address generated when invalid

Possible failure:

```text
out-of-range read for odd K
unexpected read to next row/column
```

Mitigation:

```text
only enter A1/B1 read states when lane1_valid is true
```

### Risk 3: Counter counts MAC states instead of logical MACs

Possible failure:

```text
mac_count == number of K groups, not M*N*K
```

Mitigation:

```text
increment mac_count by valid lane count
perf_counter_smoke detects mismatch
```

### Risk 4: Direct Stream operand buffer read ordering mismatch

Possible failure:

```text
scratchpad mode passes
Direct Stream mode fails
```

Mitigation:

```text
run Direct Stream smoke with GEMM_MAC_LANES=2
```

### Risk 5: Single-lane regression changes

Possible failure:

```text
default behavior changes accidentally
```

Mitigation:

```text
default parameter remains 1
run full 35/35 regression after each safe patch
```

---

## 20. Recommended Implementation Order

Recommended next steps:

```text
1. Add GEMM_MAC_LANES parameter to gemm_top.sv, default 1.
2. Compile and run full 35/35 regression.
3. Add lane1 storage registers and valid flag.
4. Add lane1 read states.
5. Update S_MAC to support 1-lane and 2-lane accumulation.
6. Update k_idx advance logic.
7. Update gemm_perf_mac_count increment logic.
8. Add parameter propagation if needed for simulation.
9. Run 2-lane CASE_ID=100.
10. Run 2-lane CASE_ID=101.
11. Run 2-lane CASE_ID=105.
12. Run 2-lane CASE_ID=5.
13. Run 2-lane perf_profile.
14. Run 2-lane Direct Stream smoke.
15. Decide whether to add 2-lane subset into regression or keep it manual initially.
```

---

## 21. Milestone Definition

### P2A: Parameterized Single-Lane Safe Patch

Complete when:

```text
GEMM_MAC_LANES parameter exists
default GEMM_MAC_LANES=1
full regression remains 35/35 PASS
```

### P2B: 2-Lane Host-Primary Correctness

Complete when:

```text
GEMM_MAC_LANES=2 host-primary smoke passes
CASE_ID=100/101/105/5 pass
mac_count/output_count pass
scoreboard compare pass
```

### P2C: 2-Lane Profile Baseline

Complete when:

```text
GEMM_MAC_LANES=2 profile summary is printed
2-lane results are compared with single-lane baseline
no exact busy-cycle lock yet
```

### P2D: 2-Lane Direct Stream Compatibility

Complete when:

```text
Direct Stream smoke RUN_ALL passes with GEMM_MAC_LANES=2
```

### P2 Final

Complete when:

```text
single-lane full regression remains clean
2-lane host-primary correctness passes
2-lane profile baseline is available
2-lane Direct Stream smoke passes
no UVM_ERROR / UVM_FATAL
```

---

## 22. Summary

The 2-lane GEMM milestone is intentionally conservative.

The key rule is:

```text
Preserve single-lane correctness first.
Add 2-lane correctness second.
Measure performance third.
Optimize bandwidth later.
```

The first 2-lane implementation should focus on correctness, counter consistency, and compatibility across scratchpad and Direct Stream modes. Once stable, later work can target operand staging, wider reads, and tile-based reuse for larger performance gains.
