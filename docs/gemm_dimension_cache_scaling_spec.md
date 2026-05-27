# GEMM Dimension / Cache Scaling Spec

## 0. Purpose

This document records the completed P9 milestone for scaling the GEMM accelerator beyond the closed P8 baseline.

P8 completed the cache-backed true 4-lane MAC path for the original small-tile class:

```text
GEMM_MAC_LANES=4
GEMM_ENABLE_B_CACHE=1
GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1
GEMM_ENABLE_A_ROW_CACHE=1
GEMM_ENABLE_PACKED_A_ROW_PRELOAD=1

Validated P8 cache capacity:
  GEMM_B_CACHE_MAX_K=4
  GEMM_B_CACHE_MAX_N=4
  GEMM_A_ROW_CACHE_MAX_K=4
```

P9 extends that full-cache 4-lane datapath to larger cache dimensions and larger single-job GEMM shapes:

```text
Validated P9 cache capacity:
  GEMM_B_CACHE_MAX_K=8
  GEMM_B_CACHE_MAX_N=8
  GEMM_A_ROW_CACHE_MAX_K=8
```

P9 is intentionally not a tiling milestone. It validates larger single GEMM jobs that still fit inside the configured local caches.

---

## 1. P9 Closure Status

P9 is closed.

```text
P9B: safe parameter validation / plumbing check        PASS
P9C: scaled cache compatibility, default clock         PASS
P9D: scaled cache CDC sanity, clk10/13                 PASS
P9E: focused perf/profile compare                      PASS
P9F: larger-dimension CASE_ID support                  PASS
P9G: large-dimension path compatibility sanity         PASS
P9H: regression integration                            PASS

Full regression:
  TOTAL : 65
  PASS  : 65
  FAIL  : 0
```

---

## 2. Baseline Before P9

Closed P8 baseline:

```text
Full regression:
  TOTAL : 62
  PASS  : 62
  FAIL  : 0
```

P8 completed:

```text
P8A: 4-lane MAC feasibility spec                    PASS
P8B: safe parameter validation / plumbing           PASS
P8C: cache-backed true 4-lane MAC RTL               PASS
P8D: focused perf/profile compare                   PASS
P8E: Direct Stream / load-store compatibility       PASS
P8F: 4-lane stress / CDC manual subset              PASS
P8G: representative 4-lane regression added         PASS
```

Representative P8 profile:

```text
CASE_ID | M | N | K | MACS | OUTPUTS | BUSY
100     | 1 | 1 | 1 | 1    | 1       | 43
101     | 2 | 2 | 2 | 8    | 4       | 152
105     | 2 | 3 | 4 | 24   | 6       | 265
5       | 4 | 4 | 4 | 64   | 16      | 472
400     | 4 | 4 | 4 | 64   | 16      | 472
401     | 4 | 4 | 4 | 64   | 16      | 472
402     | 4 | 4 | 4 | 64   | 16      | 472
403     | 4 | 4 | 4 | 64   | 16      | 472
```

---

## 3. P9 Target Configuration

Primary validated P9 configuration:

```text
GEMM_MAC_LANES=4
GEMM_ENABLE_B_CACHE=1
GEMM_B_CACHE_MAX_K=8
GEMM_B_CACHE_MAX_N=8
GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1
GEMM_ENABLE_A_ROW_CACHE=1
GEMM_A_ROW_CACHE_MAX_K=8
GEMM_ENABLE_PACKED_A_ROW_PRELOAD=1
```

Default configuration remains unchanged:

```text
GEMM_MAC_LANES=1
GEMM_ENABLE_B_CACHE=0
GEMM_ENABLE_PACKED_BCACHE_PRELOAD=0
GEMM_ENABLE_A_ROW_CACHE=0
GEMM_ENABLE_PACKED_A_ROW_PRELOAD=0

GEMM_B_CACHE_MAX_K=4
GEMM_B_CACHE_MAX_N=4
GEMM_A_ROW_CACHE_MAX_K=4
```

Cache-size scaling is opt-in through run-script / elaboration parameters.

---

## 4. P9 Non-Goals

P9 does not implement:

```text
- tile scheduler
- multi-tile GEMM
- partial C accumulation across tiles
- C read-modify-write accumulation
- systolic array
- multi-row A cache
- multi-column B streaming engine
- widened local memory interface
- additional AXI ports
- new DMA protocol
- new AXI-Stream protocol
- new Direct Stream protocol
```

---

## 5. Validated P9 CASE_ID Map

P9 uses focused larger-dimension cases in the variable-dimension range.

```text
CASE_ID | M | N | K | A bytes | B bytes | C words | C bytes | MACS | OUTPUTS
190     | 1 | 8 | 8 | 8       | 64      | 8       | 32      | 64   | 8
191     | 2 | 8 | 8 | 16      | 64      | 16      | 64      | 128  | 16
192     | 3 | 5 | 7 | 21      | 35      | 15      | 60      | 105  | 15
```

Purpose:

```text
CASE_ID=190:
  fills B-cache K/N=8 with one A row
  verifies K=8 and N=8 cache footprint

CASE_ID=191:
  repeats the K/N=8 B-cache footprint across two A rows
  verifies B-cache reuse across M

CASE_ID=192:
  non-power-of-two / non-multiple-of-four dimension
  verifies lane-tail handling and irregular C region size
```

P9 intentionally keeps these as focused directed cases instead of adding them to the default random stress pools.

---

## 6. Cache Capacity Policy

Activation policy:

```text
B-cache active when:
  GEMM_ENABLE_B_CACHE=1
  dim_k <= GEMM_B_CACHE_MAX_K
  dim_n <= GEMM_B_CACHE_MAX_N

A-row cache active when:
  GEMM_ENABLE_A_ROW_CACHE=1
  dim_k <= GEMM_A_ROW_CACHE_MAX_K
```

Packed preload policy:

```text
packed B-cache preload active when:
  GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1
  B-cache is active
  B base is 4-byte aligned

packed A-row preload active when:
  GEMM_ENABLE_PACKED_A_ROW_PRELOAD=1
  A-row cache is active
  A base is 4-byte aligned
  dim_k is compatible with packed preload grouping
```

For `K=8`, packed A-row preload uses two 32-bit local reads per A row.

For `CASE_ID=192`, `K=7` is intentionally irregular. The design must preserve correctness through valid-lane masking and safe fallback behavior where packed grouping is not applicable.

---

## 7. Cache Storage Requirements

### B-cache

P9 maximum:

```text
GEMM_B_CACHE_MAX_K=8
GEMM_B_CACHE_MAX_N=8
```

Required entries:

```text
8 * 8 = 64 int8 entries
```

Conceptual storage:

```systemverilog
logic signed [B_DATA_WIDTH-1:0] b_cache [0:GEMM_B_CACHE_MAX_K-1][0:GEMM_B_CACHE_MAX_N-1];
```

Required indexing rule:

```text
b_cache[k][n]
```

P9 verifies:

```text
k index spans 0..7 for K=8
n index spans 0..7 for N=8
lane access b_cache[k_idx + lane][n_idx] is correct for lane0..lane3
```

### A-row cache

P9 maximum:

```text
GEMM_A_ROW_CACHE_MAX_K=8
```

Required entries:

```text
8 int8 entries per active A row
```

Conceptual storage:

```systemverilog
logic signed [A_DATA_WIDTH-1:0] a_row_cache [0:GEMM_A_ROW_CACHE_MAX_K-1];
```

P9 verifies:

```text
A-row cache is refreshed for every m
A-row cache is reused across all n for the same m
stale A-row data is not reused after m increments
lane access a_row_cache[k_idx + lane] is correct for lane0..lane3
```

---

## 8. Memory Layout and Footprint

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
C bytes = M * N * 4
```

P9 footprint:

```text
CASE_ID | A range                      | B range                      | C range
190     | 0x0000_0000 .. 0x0000_0007   | 0x0000_0100 .. 0x0000_013f   | 0x0000_0200 .. 0x0000_021f
191     | 0x0000_0000 .. 0x0000_000f   | 0x0000_0100 .. 0x0000_013f   | 0x0000_0200 .. 0x0000_023f
192     | 0x0000_0000 .. 0x0000_0014   | 0x0000_0100 .. 0x0000_0122   | 0x0000_0200 .. 0x0000_023b
```

These regions fit within the existing default scratchpad spacing.

---

## 9. Compute Behavior for K=8 and K=7

For 4-lane mode:

```text
K step width = 4
```

For K=8:

```text
compute groups per output = ceil(8 / 4) = 2
```

Expected groups:

```text
group 0:
  k_idx=0
  lanes use k=0,1,2,3

group 1:
  k_idx=4
  lanes use k=4,5,6,7
```

For K=7:

```text
compute groups per output = ceil(7 / 4) = 2
```

Expected groups:

```text
group 0:
  k_idx=0
  lanes use k=0,1,2,3

group 1:
  k_idx=4
  lanes use k=4,5,6
  lane for k=7 is masked
```

Required correctness condition:

```text
No k element may be skipped.
No k element may be computed twice.
Masked lanes must not contribute to the accumulator.
```

---

## 10. Packed Preload Behavior

### Packed A-row preload for K=8

For K=8:

```text
A-row bytes per row = 8
packed reads per row = 8 / 4 = 2
```

Expected A-row preload behavior:

```text
read 0: A[m][0], A[m][1], A[m][2], A[m][3]
read 1: A[m][4], A[m][5], A[m][6], A[m][7]
```

### Packed B-cache preload for K=8, N=8

For K=8 and N=8:

```text
B bytes = K * N = 64
packed reads = 64 / 4 = 16
```

Expected B layout is row-major:

```text
B[k][n] offset = k * N + n
```

P9 verifies packed B-cache preload correctly maps packed words into:

```text
b_cache[k][n]
```

across:

```text
k = 0..7
n = 0..7
```

---

## 11. Performance Counter Requirements

Counter semantics remain unchanged:

```text
gemm_perf_mac_count    = M * N * K
gemm_perf_output_count = M * N
```

Expected P9 values:

```text
CASE_ID | M | N | K | expected_mac | expected_output
190     | 1 | 8 | 8 | 64           | 8
191     | 2 | 8 | 8 | 128          | 16
192     | 3 | 5 | 7 | 105          | 15
```

`gemm_perf_busy_cycles` is expected to be non-zero and stable for identical cases, but P9 does not use exact busy-cycle thresholds as pass/fail criteria.

---

## 12. Verification Closure

### P9B: Safe Parameter Validation / Plumbing

Status:

```text
PASS
```

Validated:

```text
GEMM_B_CACHE_MAX_K=8
GEMM_B_CACHE_MAX_N=8
GEMM_A_ROW_CACHE_MAX_K=8
default behavior unchanged
```

### P9C: Scaled Cache Compatibility, Default Clock

Status:

```text
PASS
```

Validated the P9 cache8 configuration under default clock ratio:

```text
dma_clk  = 10 ns
core_clk = 14 ns
```

### P9D: Scaled Cache CDC Sanity

Status:

```text
PASS
```

Validated the P9 cache8 configuration under CDC sanity clock ratio:

```text
dma_clk  = 10 ns
core_clk = 13 ns
```

### P9E: Focused Perf/Profile Compare

Status:

```text
PASS
```

Validated performance counters and profile behavior under 4-lane full-cache configuration.

### P9F: Larger-Dimension CASE_ID Support

Status:

```text
PASS
```

Validated:

```text
CASE_ID=190
CASE_ID=191
CASE_ID=192
```

under scaled cache8 configuration.

### P9G: Large-Dimension Path Compatibility Sanity

Status:

```text
PASS
```

Validated:

```text
DMA load-store path          CASE_ID=190
AXI-Stream load-store path   CASE_ID=191
Direct Stream load-store     CASE_ID=192
```

Each run confirmed:

```text
forced CASE_ID mode active
configured larger dimensions applied
preload/load-store path completed
result compare PASS
scoreboard pairing PASS
UVM_ERROR=0
UVM_FATAL=0
```

### P9H: Regression Integration

Status:

```text
PASS
```

Added representative P9 scaled-cache items to full regression:

```text
gemm_4lane_scaled_fullcache_dma_load_store_case190
gemm_4lane_scaled_fullcache_axis_stream_load_store_case191
gemm_4lane_scaled_fullcache_direct_stream_load_store_case192
```

Final full regression:

```text
TOTAL : 65
PASS  : 65
FAIL  : 0
```

---

## 13. Regression Inclusion Policy

Full regression includes only representative P9 larger-dimension items:

```text
- one DMA representative cache8 larger-dimension item
- one AXI-Stream representative cache8 larger-dimension item
- one Direct Stream representative cache8 larger-dimension item
```

The default stress pools remain unchanged and continue to use the existing 8-case set:

```text
100, 101, 105, 5, 400, 401, 402, 403
```

Forced single-case behavior is reserved for directed regression/sanity:

```text
CASE_ID=0        : no forced mode; use built-in/random stress pool
CASE_ID != 0     : forced mode; every stress job uses the selected CASE_ID
```

---

## 14. Risk Analysis and Closure

### Risk 1: B-cache indexing bug for N=8

Mitigation:

```text
CASE_ID=190 and CASE_ID=191 use N=8.
Result compare passed.
```

### Risk 2: K=8 final detection bug

Mitigation:

```text
CASE_ID=190 and CASE_ID=191 use K=8.
Performance counters and result compare passed.
```

### Risk 3: Packed A-row preload multi-word bug

Mitigation:

```text
K=8 cases require two packed A-row preload reads per row.
Result compare passed.
```

### Risk 4: Packed B-cache preload row-wrap bug

Mitigation:

```text
K=8 and N=8 exercise 64 B bytes and 16 packed B-cache reads.
Result compare passed.
```

### Risk 5: Stale A-row cache across M

Mitigation:

```text
CASE_ID=191 has M=2 and reuses B-cache across two A rows.
Result compare passed.
```

### Risk 6: Irregular tail-lane behavior

Mitigation:

```text
CASE_ID=192 uses M=3, N=5, K=7.
Result compare passed.
```

### Risk 7: Regression runtime growth

Mitigation:

```text
Full regression adds only three directed P9 items.
Default random stress pools remain unchanged.
```

---

## 15. Pass / Fail Criteria

P9 closure criteria:

```text
P9B cache8 parameter plumbing is clean
P9C scaled-cache default-clock compatibility passes
P9D scaled-cache CDC sanity passes
P9E perf/profile counters are correct
P9F larger CASE_IDs pass correctness
P9G DMA / AXI-Stream / Direct Stream path compatibility passes
P9H full regression integration passes
```

Final P9 target:

```text
TOTAL : 65
PASS  : 65
FAIL  : 0
```

Status:

```text
ACHIEVED
```

---

## 16. Summary

P9 validates that the completed P8 4-lane full-cache datapath scales beyond the 4x4x4 class.

P9 proves:

```text
K=8 multi-group 4-lane compute
N=8 B-cache column scaling
A-row cache K=8 scaling
packed preload multi-word behavior
irregular K/N tail-lane handling
larger C output writeback/readback
DMA / AXI-Stream / Direct Stream compatibility
full-regression integration
```

P9 deliberately avoids tiling and partial accumulation. Those remain future milestones after cache-size and larger-dimension single-job behavior has been proven.
