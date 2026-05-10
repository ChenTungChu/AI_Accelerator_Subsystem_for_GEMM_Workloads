# Performance GEMM Spec

## 1. Purpose

This document defines the next architecture milestone after the completed subsystem-level GEMM, DMA, AXI-Stream, CDC, and Direct Stream B1 baseline.

The current subsystem baseline already verifies correctness across:

```text
Host-primary GEMM path
DMA load path
DMA store / S2MM path
DMA load + store stress path
AXI-Stream preload path
Direct Stream GEMM frontend B1 path
CDC clock-ratio sanity
error/recovery flows
scoreboard-based result compare
```

Current full regression baseline:

```text
TOTAL : 33
PASS  : 33
FAIL  : 0
```

The goal of this Performance GEMM milestone is to move from a correctness-first single-MAC GEMM engine toward a measurable, performance-oriented GEMM architecture.

The immediate focus is not to rewrite the entire datapath at once. The first step is to create a profiling baseline and then upgrade the GEMM compute microarchitecture in controlled stages.

---

## 2. Background

The current GEMM engine is a simple iterative design.

Conceptually:

```text
for m in 0 .. M-1:
  for n in 0 .. N-1:
    acc = 0
    for k in 0 .. K-1:
      acc += A[m][k] * B[k][n]
    C[m][n] = acc
```

This design is excellent for bring-up because it is:

```text
simple
deterministic
easy to debug
easy to verify
easy to compare against a software reference
```

However, it is not performance-optimized because it effectively uses one MAC datapath and computes one multiply-accumulate step at a time.

This milestone introduces performance measurement and then explores a gradual multi-MAC upgrade.

---

## 3. Design Goals

The Performance GEMM milestone must:

1. Preserve the current 33/33 regression baseline.
2. Keep all existing execution paths functional.
3. Add useful performance counters and latency visibility.
4. Establish a measurable single-MAC baseline.
5. Define a safe path toward multi-MAC GEMM execution.
6. Avoid breaking host, DMA, AXI-Stream, and Direct Stream flows.
7. Preserve scoreboard result correctness.
8. Keep signed int8 A/B and signed int32 C behavior unchanged.
9. Support fixed, variable-dimension, and configurable-base cases.
10. Support stress and CDC sanity after each architectural change.

---

## 4. Non-Goals for the First Performance Step

The first step does not attempt to:

- immediately implement a full systolic array
- immediately implement large tile scheduling
- remove scratchpad
- remove Direct Stream B1 operand buffers
- stream C directly to S2MM
- change the software-visible result format
- change A/B/C layout
- change the current regression case definitions
- change the scoreboard reference model
- optimize every path at once

The first step is measurement and controlled acceleration, not a full redesign.

---

## 5. Current Baseline Architecture

### 5.1 Scratchpad Mode

```text
A/B in scratchpad
    -> GEMM reads A/B through gemm_scratchpad_adapter
    -> GEMM writes C to scratchpad
    -> host readback or DMA store
    -> scoreboard compare
```

### 5.2 AXI-Stream Preload Mode

```text
AXI-MM source
    -> axi_mm2s_dma
    -> axis_async_fifo
    -> axi_stream_loader
    -> axis_scratchpad_write_adapter
    -> scratchpad A/B
    -> GEMM
    -> scratchpad C
    -> DMA store
    -> scoreboard compare
```

### 5.3 Direct Stream B1 Mode

```text
AXI-MM source
    -> axi_mm2s_dma
    -> axis_async_fifo
    -> axi_stream_loader
    -> gemm_operand_buffer_write_adapter
    -> gemm_operand_buffer A/B
    -> gemm_input_mem_router
    -> GEMM reads A/B from operand buffer
    -> GEMM writes C to scratchpad
    -> DMA store
    -> scoreboard compare
```

Performance GEMM changes should initially focus on the GEMM compute core and its local memory request pattern. The data-movement frontends should remain stable unless a later optimization explicitly requires changes.

---

## 6. Performance Measurement Model

### 6.1 Why Counters First?

Before changing the GEMM datapath, the design should record performance-relevant cycle counts.

This gives a before/after comparison when moving from:

```text
single-MAC GEMM
```

to:

```text
2-lane MAC GEMM
4-lane MAC GEMM
tile-based GEMM
```

Without counters, performance improvement is only estimated. With counters, each regression run can report measurable latency.

### 6.2 Recommended Counter Scope

Counters should be split into two levels:

```text
subsystem-level counters
GEMM-core-level counters
```

Subsystem-level counters answer:

```text
How long did the whole job take?
How long did DMA load take?
How long did AXI-Stream preload take?
How long did Direct Stream preload take?
How long did GEMM compute take?
How long did DMA store take?
```

GEMM-core-level counters answer:

```text
How many cycles was GEMM busy?
How many memory read requests were issued?
How many memory write requests were issued?
How many MAC operations were performed?
How many cycles were spent waiting for memory?
How many cycles were spent in compute?
```

---

## 7. Proposed Performance Counters

### 7.1 Subsystem-Level Counters

Recommended signals in `ai_accel_subsys.sv` or a small status block:

```systemverilog
logic [31:0] perf_job_cycles;
logic [31:0] perf_gemm_cycles;
logic [31:0] perf_dma_load_cycles;
logic [31:0] perf_dma_store_cycles;
logic [31:0] perf_axis_load_cycles;
logic [31:0] perf_direct_stream_load_cycles;
```

Recommended behavior:

```text
perf_job_cycles:
    counts from accepted acc_start to acc_done

perf_gemm_cycles:
    counts while GEMM is active in core_clk domain

perf_dma_load_cycles:
    counts while dma_load_busy is high

perf_dma_store_cycles:
    counts while dma_store_busy is high

perf_axis_load_cycles:
    counts while axis_load_busy is high

perf_direct_stream_load_cycles:
    counts while ds_load_busy is high
```

The exact clock domain must be documented for each counter.

Recommended default:

```text
DMA/data-movement counters use dma_clk
GEMM counters use core_clk
```

### 7.2 GEMM-Core Counters

Recommended GEMM-level counters:

```systemverilog
logic [31:0] gemm_perf_busy_cycles;
logic [31:0] gemm_perf_mac_count;
logic [31:0] gemm_perf_read_req_count;
logic [31:0] gemm_perf_read_wait_cycles;
logic [31:0] gemm_perf_write_req_count;
logic [31:0] gemm_perf_write_wait_cycles;
logic [31:0] gemm_perf_output_count;
```

Recommended behavior:

```text
gemm_perf_busy_cycles:
    increments while GEMM is busy

gemm_perf_mac_count:
    increments when a valid multiply-accumulate operation is committed

gemm_perf_read_req_count:
    increments when GEMM issues a memory read request

gemm_perf_read_wait_cycles:
    increments when GEMM is waiting for read data or read acceptance

gemm_perf_write_req_count:
    increments when GEMM issues a memory write request

gemm_perf_write_wait_cycles:
    increments when GEMM is waiting for write acceptance

gemm_perf_output_count:
    increments when one C[m][n] output is written
```

### 7.3 Counter Clear Policy

Counters should clear on:

```text
reset
new accepted GEMM start
explicit perf_clear pulse
```

For regression and debug, clearing at accepted GEMM start is the most convenient default.

### 7.4 Counter Snapshot Policy

Counters should remain stable after `acc_done` until the next accepted job or explicit clear.

This allows UVM to sample the values after job completion.

---

## 8. Expected Single-MAC Baseline Metrics

For an idealized single-MAC GEMM, the math workload is:

```text
MAC_COUNT = M * N * K
OUTPUT_COUNT = M * N
```

For key regression cases:

```text
CASE_ID=100, dim=(1,1,1):
  MAC_COUNT = 1
  OUTPUT_COUNT = 1

CASE_ID=101, dim=(2,2,2):
  MAC_COUNT = 8
  OUTPUT_COUNT = 4

CASE_ID=105, dim=(2,3,4):
  MAC_COUNT = 24
  OUTPUT_COUNT = 6

CASE_ID=5/400/401/402/403, dim=(4,4,4):
  MAC_COUNT = 64
  OUTPUT_COUNT = 16
```

Actual cycle latency will be larger than MAC_COUNT because the current design includes FSM overhead, memory read latency, writeback cycles, and handshaking.

The first performance-counter test should not require exact latency values unless the current RTL behavior is already deterministic enough to lock down. A better first rule is:

```text
counter values must be non-zero when expected
gemm_perf_mac_count must equal M*N*K
gemm_perf_output_count must equal M*N
latency must be within a broad sanity range
```

---

## 9. Multi-MAC Upgrade Strategy

### 9.1 Direction

The next compute improvement should increase the number of MAC operations committed per inner-loop step.

Possible options:

```text
Option 1: K-lane parallelism
Option 2: N-lane parallelism
Option 3: output-stationary multi-lane accumulation
Option 4: small systolic/tile prototype
```

Recommended first implementation:

```text
Option 1: K-lane parallelism with 2 MAC lanes
```

Why:

```text
simple to reason about
same C[m][n] accumulation target
only reduces inner-loop latency
does not require computing multiple C outputs at once
easy to compare against existing single-MAC behavior
```

### 9.2 2-Lane K-Parallel GEMM

For each C[m][n]:

Current single-MAC:

```text
for k in 0..K-1:
    acc += A[m][k] * B[k][n]
```

2-lane K-parallel:

```text
for k in 0..K-1 step 2:
    acc += A[m][k+0] * B[k+0][n]
    acc += A[m][k+1] * B[k+1][n]
```

Expected benefit:

```text
inner-loop MAC iterations roughly halve when K is even
```

For odd K, the final lane must be masked:

```text
if k+1 >= K:
    lane1_valid = 0
```

### 9.3 4-Lane K-Parallel GEMM

After 2-lane is stable:

```text
for k in 0..K-1 step 4:
    acc += A[m][k+0] * B[k+0][n]
    acc += A[m][k+1] * B[k+1][n]
    acc += A[m][k+2] * B[k+2][n]
    acc += A[m][k+3] * B[k+3][n]
```

Expected benefit:

```text
inner-loop MAC iterations roughly divide by 4 when K is a multiple of 4
```

### 9.4 Memory Bandwidth Concern

K-parallel MAC lanes require multiple A/B values per compute step.

For 2 lanes:

```text
need A[m][k+0], B[k+0][n]
need A[m][k+1], B[k+1][n]
```

For 4 lanes:

```text
need four A values and four B values per inner-loop step
```

The existing local memory interface may not naturally supply multiple byte operands per cycle.

Possible approaches:

```text
Approach A:
    issue multiple sequential reads, then compute multiple MACs together
    easier, but less speedup

Approach B:
    widen read behavior and extract multiple bytes from a wider word
    better speedup, more RTL changes

Approach C:
    add small row/column operand staging registers
    good compromise

Approach D:
    use Direct Stream operand buffer as a wider/local operand source
    potentially best for direct-stream mode
```

The first multi-MAC prototype should be explicit about whether it improves arithmetic parallelism only or also improves memory bandwidth.

---

## 10. Recommended Architecture Stages

### Stage P0: Performance Counter Baseline

Add counters without changing compute behavior.

Expected regression:

```text
Existing 33/33 remains passing
New perf counter smoke test passes
```

New test:

```text
ai_accel_subsys_perf_counter_smoke_test
```

Coverage:

```text
run selected cases
check mac_count == M*N*K
check output_count == M*N
check busy cycles are non-zero
check read/write counters are non-zero
check counters clear between jobs
```

### Stage P1: Single-MAC Profiling Regression

Add a stress/profile test that records baseline latencies across cases.

New test:

```text
ai_accel_subsys_perf_profile_test
```

Coverage:

```text
RUN_ALL recipe
collect per-case GEMM cycle counts
collect end-to-end job cycle counts
print summary table
do not fail on exact cycle count unless outside sanity bounds
```

This gives the baseline for comparing P2/P3.

### Stage P2: 2-Lane MAC Prototype

Implement a 2-lane MAC version behind a parameter or configuration define.

Recommended parameter:

```systemverilog
parameter int GEMM_MAC_LANES = 1
```

Supported values initially:

```text
1 = current single-MAC baseline
2 = 2-lane K-parallel prototype
```

Acceptance:

```text
33/33 baseline still passes with GEMM_MAC_LANES=1
2-lane smoke passes
2-lane direct-stream smoke passes
2-lane result compare passes
perf counters show same mac_count but reduced compute cycles
```

### Stage P3: 2-Lane Stress and CDC

Add stress and CDC runs for the 2-lane version.

Coverage:

```text
host smoke
DMA load/store stress
AXI-Stream load/store stress
Direct Stream load/store stress
CDC clock-ratio sanity
```

### Stage P4: 4-Lane MAC Planning

After 2-lane is stable, define the 4-lane plan.

Do not start 4-lane until:

```text
2-lane result correctness is stable
2-lane performance counters are stable
2-lane regression subset is clean
memory bandwidth bottlenecks are understood
```

---

## 11. RTL Integration Plan

### 11.1 Files Likely to Change

Expected first step:

```text
rtl/gemm/gemm_top.sv
rtl/gemm/gemm_ctrl.sv
rtl/gemm/gemm_mac.sv
rtl/top/ai_accel_subsys.sv
tb/interface/ai_accel_subsys_ctrl_if.sv
tb/top/ai_accel_subsys_uvm_top.sv
```

If counters are implemented as a separate block:

```text
rtl/subsystem/gemm_perf_counter.sv
```

### 11.2 Counter Exposure

For V1 of performance counters, the simplest exposure is top-level debug/status outputs connected to `ctrl_if`.

Recommended additions to `ai_accel_subsys_ctrl_if.sv`:

```systemverilog
logic [31:0] perf_job_cycles;
logic [31:0] perf_gemm_cycles;

logic [31:0] gemm_perf_busy_cycles;
logic [31:0] gemm_perf_mac_count;
logic [31:0] gemm_perf_read_req_count;
logic [31:0] gemm_perf_read_wait_cycles;
logic [31:0] gemm_perf_write_req_count;
logic [31:0] gemm_perf_write_wait_cycles;
logic [31:0] gemm_perf_output_count;
```

Optional later CSR model:

```text
Expose counters through AXI-Lite CSR registers.
```

For now, direct testbench visibility is acceptable.

### 11.3 Backward Compatibility

All new outputs should be passive status signals. They must not change current control sequencing.

Existing tests should not need modification.

---

## 12. UVM Verification Plan

### 12.1 Performance Counter Smoke Test

Recommended file:

```text
tb/uvm/test/ai_accel_subsys_perf_counter_smoke_test.sv
```

Flow:

```text
1. run normal GEMM case
2. wait acc_done
3. sample performance counters
4. check mac_count == M*N*K
5. check output_count == M*N
6. check busy cycles > 0
7. run second case
8. confirm counters reset/update correctly
```

Recommended first cases:

```text
CASE_ID=100
CASE_ID=101
CASE_ID=105
CASE_ID=5
```

### 12.2 Performance Profile Test

Recommended file:

```text
tb/uvm/test/ai_accel_subsys_perf_profile_test.sv
```

Flow:

```text
RUN_ALL recipe:
    100 -> 101 -> 105 -> 5 -> 400 -> 401 -> 402 -> 403

For each case:
    run selected input path
    record counters
    print profile summary
```

Recommended output:

```text
CASE_ID | M | N | K | MACs | Outputs | GEMM cycles | Job cycles
```

Optional mode selector:

```text
PERF_PROFILE_MODE=HOST
PERF_PROFILE_MODE=DMA
PERF_PROFILE_MODE=AXIS
PERF_PROFILE_MODE=DIRECT_STREAM
```

### 12.3 2-Lane MAC Test

Recommended file:

```text
tb/uvm/test/ai_accel_subsys_gemm_2lane_smoke_test.sv
```

Goal:

```text
same result as single-MAC
lower or equal GEMM cycles for K >= 2
same mac_count M*N*K
same output_count M*N
```

---

## 13. Acceptance Criteria

### 13.1 Performance Counter Baseline Complete

Complete when:

```text
existing 33/33 regression remains passing
performance counter smoke test passes
mac_count equals M*N*K
output_count equals M*N
busy cycle counters are non-zero
counters clear/update correctly across back-to-back jobs
```

### 13.2 Performance Profile Baseline Complete

Complete when:

```text
profile test runs RUN_ALL recipe
per-case counter summary is printed
no result compare mismatch
no ctrl/result pairing failure
no UVM_ERROR / UVM_FATAL
```

### 13.3 2-Lane MAC Prototype Complete

Complete when:

```text
2-lane result correctness passes
2-lane direct-stream path passes
2-lane stress subset passes
2-lane counters are consistent
compute cycles improve for K >= 2 cases or any non-improvement is explained by memory bandwidth
single-MAC configuration remains regression clean
```

---

## 14. Risks and Mitigations

### Risk 1: Counters change timing

Counters should be passive. They should not feed back into datapath control.

Mitigation:

```text
add counters in parallel with existing FSM behavior
do not use counters for control decisions
```

### Risk 2: Multi-MAC requires more memory bandwidth

Adding MAC lanes without changing memory access may not improve performance much.

Mitigation:

```text
measure current memory wait cycles first
prototype 2-lane with clear expectations
consider operand staging if memory wait dominates
```

### Risk 3: Direct Stream mode and scratchpad mode diverge

Multi-MAC changes may accidentally work in one mode but not the other.

Mitigation:

```text
run both scratchpad and direct-stream smoke for each compute change
keep gemm_input_mem_router behavior unchanged unless needed
```

### Risk 4: Regression grows too large

Performance runs can increase runtime.

Mitigation:

```text
keep full-regression perf tests small
move long profiling/stress runs to manual/nightly
```

---

## 15. Recommended Implementation Order

```text
1. Add performance counter signals inside GEMM core.
2. Expose GEMM counters through ai_accel_subsys.
3. Extend ctrl_if and UVM top to observe counters.
4. Add ai_accel_subsys_perf_counter_smoke_test.
5. Add ai_accel_subsys_perf_profile_test.
6. Run full regression and lock performance baseline.
7. Draft 2-lane MAC microarchitecture.
8. Add GEMM_MAC_LANES parameter with default 1.
9. Implement 2-lane K-parallel compute path.
10. Add 2-lane smoke and direct-stream smoke tests.
11. Add 2-lane stress subset.
12. Re-evaluate whether 4-lane or tiling is the next best step.
```

---

## 16. Suggested First Milestone

The first milestone should be:

```text
Performance Counter Baseline
```

Minimum deliverables:

```text
RTL:
  - GEMM busy cycle counter
  - GEMM MAC count counter
  - GEMM output count counter
  - optional read/write wait counters

UVM:
  - perf counter smoke test
  - checks for M*N*K and M*N
  - checks counter clear/update behavior

Regression:
  - existing 33/33 remains passing
  - new perf counter test passes
```

Expected new baseline after first performance test:

```text
TOTAL : 34
PASS  : 34
FAIL  : 0
```

---

## 17. Future Direction

After the performance counter baseline is clean, the project can move toward:

```text
2-lane K-parallel GEMM
4-lane K-parallel GEMM
operand staging buffers
tile-based GEMM
better Direct Stream operand reuse
optional C direct-store path
more constrained-random coverage
coverage closure
```

The guiding principle should remain:

```text
measure first
accelerate second
verify every step
