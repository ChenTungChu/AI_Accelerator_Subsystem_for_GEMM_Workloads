# GEMM K-Tiling Execution Spec

## 1. Purpose

This document defines the completed P10 milestone for extending the GEMM accelerator beyond the closed P9 larger-dimension / cache-size scaling baseline.

P9 proved that the cache-backed 4-lane GEMM datapath can run larger single-job dimensions when the active GEMM job still fits inside the configured caches.

P10 extends the P9 architecture from **single-cache-fit GEMM jobs** to **K-tiled GEMM jobs**.

P10 is intentionally limited to K-dimension tiling only:

```text
K_total may exceed the local cache capacity.
M and N are not tiled in P10.
Each K tile still fits inside the existing B-cache and A-row-cache capacity.
```

Final P10 status:

```text
P10B: safe K-tiling parameter plumbing                   PASS
P10C: K>8 testcase / software reference support          PASS
P10D: actual K-tile execution microarchitecture          PASS
P10E: frontend compatibility sanity                      PASS
P10F: regression integration                             PASS

Full regression:
  TOTAL : 68
  PASS  : 68
  FAIL  : 0
```

---

## 2. Validated Configuration

```text
GEMM_MAC_LANES=4
GEMM_ENABLE_B_CACHE=1
GEMM_B_CACHE_MAX_K=8
GEMM_B_CACHE_MAX_N=8
GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1
GEMM_ENABLE_A_ROW_CACHE=1
GEMM_A_ROW_CACHE_MAX_K=8
GEMM_ENABLE_PACKED_A_ROW_PRELOAD=1
GEMM_ENABLE_K_TILING=1
GEMM_K_TILE_SIZE=8
```

The default remains safe:

```text
GEMM_ENABLE_K_TILING=0
```

---

## 3. Architectural Choice

P10 uses **internal row accumulation** rather than scratchpad C read-modify-write.

Rejected first-step option:

```text
for each K tile:
  read old C[m][n]
  add tile partial sum
  write updated C[m][n]
```

Reason this was not chosen for P10:

```text
scratchpad C read dependency
C initialization policy
read-modify-write hazards
more complex completion semantics
more scoreboard/debug complexity
```

Chosen P10 model:

```text
for each output row m:
  clear c_row_accum[0 .. N-1]

  for each K tile:
    preload B tile into b_cache
    preload A row tile into a_row_cache

    for n in 0 .. N-1:
      c_row_accum[n] += dot(A[m][k_tile], B[k_tile][n])

  for n in 0 .. N-1:
    write final C[m][n] = c_row_accum[n]
```

Benefits:

```text
no scratchpad C read-modify-write in P10
final C is written exactly once per output element
completion semantics remain close to the P9 behavior
B tile is reused during local tile compute
A row tile is reused across output columns
row accumulator storage is small for N <= 8
```

---

## 4. Execution Model

Logical loop structure:

```text
for m in 0 .. M-1:
  c_row_accum[0 .. N-1] = 0

  for k_tile_base in 0, K_TILE_SIZE, 2*K_TILE_SIZE, ...:
    k_tile_len = min(K_TILE_SIZE, K_total - k_tile_base)

    preload A[m][k_tile_base + 0 .. k_tile_base + k_tile_len - 1]
      into a_row_cache[0 .. k_tile_len - 1]

    preload B[k_tile_base + 0 .. k_tile_base + k_tile_len - 1][0 .. N-1]
      into b_cache[0 .. k_tile_len - 1][0 .. N-1]

    for n in 0 .. N-1:
      for local_k in 0 .. k_tile_len - 1 step GEMM_MAC_LANES:
        c_row_accum[n] += lane dot product

  for n in 0 .. N-1:
    write C[m][n] = c_row_accum[n]
```

Effective tile size:

```text
effective_k_tile_size = min(GEMM_K_TILE_SIZE, GEMM_B_CACHE_MAX_K, GEMM_A_ROW_CACHE_MAX_K)
```

Validated P10 value:

```text
effective_k_tile_size = 8
```

Examples:

```text
K=16 -> tile lengths 8, 8
K=12 -> tile lengths 8, 4
K=9  -> tile lengths 8, 1
```

---

## 5. Lane Validity

For 4-lane compute inside a K tile:

```text
lane_valid[lane] = (local_k + lane) < k_tile_len
```

For `K_TILE_SIZE=8`, each full tile contains two 4-lane groups:

```text
group 0: local_k = 0, lanes 0..3
group 1: local_k = 4, lanes 0..3
```

For a tail tile with `k_tile_len=1`, only lane 0 is valid.

---

## 6. Memory Layout

The default memory map remains unchanged:

```text
A base = 0x0000_0000
B base = 0x0000_0100
C base = 0x0000_0200
```

For int8 A/B and int32 C:

```text
A bytes = M * K
B bytes = K * N
C words = M * N
C bytes = M * N * 4
```

Address formulas:

```text
A[m][k] address = base_a + (m * K_total + k)
B[k][n] address = base_b + (k * N + n)
C[m][n] address = base_c + ((m * N + n) * 4)
```

For K tiling:

```text
A tile address = base_a + (m * K_total + (k_tile_base + local_k))
B tile address = base_b + ((k_tile_base + local_k) * N + n)
```

The B-cache stores the local tile with local K indices:

```text
b_cache[local_k][n]
```

The A-row cache stores the local tile with local K indices:

```text
a_row_cache[local_k]
```

---

## 7. Internal Storage

P10 reuses the P9 cache capacity:

```text
GEMM_B_CACHE_MAX_K=8
GEMM_B_CACHE_MAX_N=8
GEMM_A_ROW_CACHE_MAX_K=8
```

Conceptual row accumulator storage:

```systemverilog
logic signed [31:0] c_row_accum [0:GEMM_B_CACHE_MAX_N-1];
```

Accumulator policy:

```text
clear active entries at the start of each output row
accumulate tile partial sums into c_row_accum[n]
write final C[m][n] once after all K tiles for that row complete
```

---

## 8. Tile Preload Policy

The closed P10D RTL intentionally uses conservative scalar tile preload for K-tiled jobs.

Reason:

```text
isolate tile scheduling correctness
isolate local-K indexing correctness
isolate row accumulation correctness
isolate final C writeback correctness
avoid mixing packed-tail preload optimization into first tiled datapath bring-up
```

Existing packed preload support remains valid for non-tiled P7/P8/P9 cache-fit paths. Packed tile-preload optimization for K-tiled tails remains future work.

---

## 9. Performance Counter Requirements

Existing counter semantics remain unchanged:

```text
gemm_perf_busy_cycles  : cycles while GEMM is busy
gemm_perf_mac_count    : logical MAC operations committed
gemm_perf_output_count : final C outputs whose write completion has been observed
```

For P10 K-tiling:

```text
gemm_perf_mac_count    = M * N * K_total
gemm_perf_output_count = M * N
```

Expected values for P10 focused cases:

```text
CASE_ID | M | N | K  | expected_mac | expected_output
193     | 1 | 4 | 16 | 64           | 4
194     | 2 | 4 | 16 | 128          | 8
195     | 4 | 4 | 16 | 256          | 16
196     | 3 | 5 | 9  | 135          | 15
197     | 4 | 4 | 12 | 192          | 16
```

Exact busy-cycle matching is not required for P10 closure.

---

## 10. Done Semantics

P10 preserves the corrected done semantics:

```text
gemm_top.done asserts only after the final C write completion has been observed.
```

For K tiling:

```text
all K tiles for all rows are complete
all final C writes have completed
only then assert done
```

This is required because DMA store may start immediately after `acc_done`.

---

## 11. Frontend Compatibility

P10 does not change frontend protocols.

Validated paths:

```text
Host primary
DMA load-store
AXI-Stream load-store
Direct Stream load-store
```

Representative frontend case:

```text
CASE_ID=195 : M=4, N=4, K=16, K_TILE_SIZE=8
```

Validation result:

```text
DMA load-store        PASS
AXI-Stream load-store PASS
Direct Stream         PASS
```

---

## 12. CASE_ID Plan and Closure

```text
CASE_ID | M | N | K  | A bytes | B bytes | C words | C bytes | Purpose
193     | 1 | 4 | 16 | 16      | 64      | 4       | 16      | minimum K=16 smoke
194     | 2 | 4 | 16 | 32      | 64      | 8       | 32      | multi-row K=16
195     | 4 | 4 | 16 | 64      | 64      | 16      | 64      | full P10 representative
196     | 3 | 5 | 9  | 27      | 45      | 15      | 60      | K tile tail 8+1, N=5
197     | 4 | 4 | 12 | 48      | 48      | 16      | 64      | K tile tail 8+4
```

Host-primary focused validation:

```text
CASE_ID=193 PASS
CASE_ID=194 PASS
CASE_ID=195 PASS
CASE_ID=196 PASS
CASE_ID=197 PASS
```

---

## 13. Regression Integration

P10F added three forced single-case representative items:

```text
gemm_4lane_ktiling_dma_load_store_case195
gemm_4lane_ktiling_axis_stream_load_store_case195
gemm_4lane_ktiling_direct_stream_load_store_case195
```

Policy:

```text
Keep default stress pools unchanged.
Use forced single-case K-tiling representative items.
Do not add all P10 cases to default stress pools.
Keep heavier K/N/M expansion cases manual or nightly until runtime is measured.
```

Final regression:

```text
TOTAL : 68
PASS  : 68
FAIL  : 0
```

---

## 14. Current Limitations

P10 does not implement:

```text
M tiling
N tiling
2D output tile scheduling
partial C read-modify-write through scratchpad
C accumulation across multiple external jobs
C direct-store path
systolic array scheduling
multi-row A cache
multi-column streaming B engine beyond the existing B-cache
widened local memory interface
additional AXI ports
new DMA protocol
new AXI-Stream protocol
new Direct Stream protocol
```

---

## 15. Future Work After P10

After K-only tiling is stable, future milestones can consider:

```text
P11: N tiling / output-column tiling                    COMPLETED
P12: M tiling / multi-row tile scheduling
P13: C read-modify-write partial accumulation
P14: external tile scheduler
P15: larger Direct Stream tile movement
P16: optional C direct-store path
```

---

## 15A. Relationship to P11 N-Tiling

P11 builds directly on the P10 row-accumulator model.

P10 proved:

```text
K_total may exceed the local K tile capacity.
N still fits the B-cache / row-accumulator N capacity.
```

P11 extends the same execution model to:

```text
K_total may exceed the local K tile capacity.
N_total may exceed the local N tile capacity.
```

The P11 loop composition is:

```text
for each output row m:
  for each N tile:
    clear c_row_accum[local_n]

    for each K tile:
      reuse the P10 K-tile preload and accumulation behavior

    write final C for the active N tile
```

Representative P11 case:

```text
CASE_ID=200 : M=4, N=16, K=16
K tiling    : 16 = 8 + 8
N tiling    : 16 = 8 + 8
```

P11 does not change the P10 K-tile arithmetic rule. It changes the outer output-column scheduling so that the P10 row accumulator is reused as a local-N-tile accumulator.

Current subsystem checkpoint after P11:

```text
TOTAL : 71
PASS  : 71
FAIL  : 0
```

---

## 16. Summary

P10 proves:

```text
4-lane full-cache GEMM can process K_total larger than cache capacity by splitting K into multiple local-cache tiles and accumulating the partial sums internally.
```

The completed P10 implementation is:

```text
K-only tiling
row-accumulator based partial accumulation
no scratchpad C read-modify-write
no frontend protocol changes
default-off parameterization
focused CASE_ID=193..197 bring-up
small regression addition using CASE_ID=195
full regression 68/68 PASS
```
