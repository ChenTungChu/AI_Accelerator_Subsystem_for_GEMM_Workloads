# AI Accelerator Subsystem for GEMM Workloads

## Overview

This repository is a subsystem-level RTL and UVM verification project for a GEMM-oriented AI accelerator path.

The design validates end-to-end data movement across multiple GEMM input paths:

```text
Host / DMA / AXI-Stream preload / Direct Stream operand preload
    -> Scratchpad memory or GEMM operand buffer
    -> GEMM core
    -> Scratchpad result C
    -> Host readback or DMA store
    -> Software reference / scoreboard compare
```

The current focus is subsystem integration, DMA load/store behavior, AXI-Stream frontend integration, Direct Stream GEMM frontend integration, CDC-aware control/status handling, reset robustness, UVM scoreboard-based verification, and performance-oriented GEMM datapath upgrades.

Current milestone:

```text
Performance GEMM P11: N-Dimension Tiling Completed

Regression:
  TOTAL : 71
  PASS  : 71
  FAIL  : 0
```

The current optimized baseline includes:

```text
GEMM_MAC_LANES=1 mainline regression
GEMM_MAC_LANES=2 focused performance subset regression
GEMM_MAC_LANES=2 stress / CDC hardening subset regression
GEMM_MAC_LANES=2 + B-cache representative regression
GEMM_MAC_LANES=2 + packed B-cache representative regression
GEMM_MAC_LANES=2 + packed B-cache + A-row cache stress / CDC representative regression
GEMM_MAC_LANES=2 + packed B-cache + A-row cache + packed A-row representative regression
GEMM_MAC_LANES=4 + full cache/preload representative regression
GEMM_MAC_LANES=4 + scaled cache8 large-dimension representative regression
GEMM_MAC_LANES=4 + K-tiling representative regression across DMA / AXI-Stream / Direct Stream
GEMM_MAC_LANES=4 + N-tiling representative regression across DMA / AXI-Stream / Direct Stream
```

Validated P11 N-tiling configuration:

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
GEMM_ENABLE_N_TILING=1
GEMM_N_TILE_SIZE=8
```

P10 extends the P9 cache8 path to K values larger than the local cache depth by executing multiple K tiles and accumulating partial sums in an internal row accumulator before writing final C results.

P11 extends the P10 row-accumulator model to output-column tiling.  It supports `N_total` larger than the local B-cache / row-accumulator N capacity by splitting output columns into local N tiles.

P11 scope:

```text
N-dimension / output-column tiling
K tiling composes with N tiling
M tiling is future work
Scratchpad C read-modify-write accumulation is not used in P11
N-tiled jobs use conservative scalar tile preload in the first implementation
```

---

## Main RTL Blocks

- `ai_accel_subsys`
- `gemm_top`
- `gemm_scratchpad_adapter`
- `gemm_input_mem_router`
- `gemm_operand_buffer`
- `gemm_operand_buffer_write_adapter`
- `dma_load_engine`
- `dma_store_engine`
- `scratchpad_port0_owner_mux`
- `scratchpad_port1_owner_mux`
- `axi_mm2s_dma`
- `axi_stream_loader`
- `axis_async_fifo`
- `axis_preload_engine`
- `axis_scratchpad_write_adapter`
- `direct_stream_preload_engine`
- `axi_mm_dual_port_bram`

The `axi_mm_dual_port_bram` model is treated as a stable scratchpad baseline.

`gemm_top` supports:

```systemverilog
parameter int GEMM_MAC_LANES                    = 1
parameter bit GEMM_ENABLE_B_CACHE               = 1'b0
parameter int GEMM_B_CACHE_MAX_K                = 4
parameter int GEMM_B_CACHE_MAX_N                = 4
parameter bit GEMM_ENABLE_PACKED_BCACHE_PRELOAD = 1'b0
parameter bit GEMM_ENABLE_A_ROW_CACHE           = 1'b0
parameter int GEMM_A_ROW_CACHE_MAX_K            = 4
parameter bit GEMM_ENABLE_PACKED_A_ROW_PRELOAD  = 1'b0
parameter bit GEMM_ENABLE_K_TILING              = 1'b0
parameter int GEMM_K_TILE_SIZE                  = 8
parameter bit GEMM_ENABLE_N_TILING              = 1'b0
parameter int GEMM_N_TILE_SIZE                  = 8
```

Supported lane settings:

```text
GEMM_MAC_LANES=1 : original single-MAC baseline
GEMM_MAC_LANES=2 : 2-lane K-parallel MAC prototype
GEMM_MAC_LANES=4 : cache-backed true 4-lane K-parallel MAC path
```

Supported cache-size settings:

```text
Default cache capacity:
  GEMM_B_CACHE_MAX_K=4
  GEMM_B_CACHE_MAX_N=4
  GEMM_A_ROW_CACHE_MAX_K=4

P9/P10/P11 scaled cache capacity:
  GEMM_B_CACHE_MAX_K=8
  GEMM_B_CACHE_MAX_N=8
  GEMM_A_ROW_CACHE_MAX_K=8

P10 K-tiling opt-in:
  GEMM_ENABLE_K_TILING=1
  GEMM_K_TILE_SIZE=8

P11 N-tiling opt-in:
  GEMM_ENABLE_N_TILING=1
  GEMM_N_TILE_SIZE=8
```

The default remains:

```text
GEMM_MAC_LANES=1
GEMM_ENABLE_B_CACHE=0
GEMM_ENABLE_PACKED_BCACHE_PRELOAD=0
GEMM_ENABLE_A_ROW_CACHE=0
GEMM_ENABLE_PACKED_A_ROW_PRELOAD=0
GEMM_ENABLE_K_TILING=0
GEMM_ENABLE_N_TILING=0
```

This preserves existing regression behavior unless the run script explicitly overrides the performance parameters.

---

## Data Model

Current GEMM assumptions:

- A and B are signed 8-bit elements.
- C / accumulator values are signed 32-bit.
- Matrices use compact row-major layout.
- C is read back or stored out as signed 32-bit words.

Default scratchpad map:

```text
A = 0x0000_0000
B = 0x0000_0100
C = 0x0000_0200
```

For Direct Stream B1, A/B are loaded into local operand buffers instead of scratchpad. The logical A/B base addresses are still used by `gemm_input_mem_router` to classify GEMM reads and translate them into local operand-buffer offsets.

---

## GEMM Compute Architecture

### Single-lane baseline

```text
for m in 0 .. M-1:
  for n in 0 .. N-1:
    acc = 0
    for k in 0 .. K-1:
      acc += A[m][k] * B[k][n]
    C[m][n] = acc
```

### 2-lane K-parallel prototype

When `GEMM_MAC_LANES=2`, the core processes up to two K positions per accumulation step. Odd-K cases are handled by lane masking.

### B-cache and packed B-cache preload

When `GEMM_ENABLE_B_CACHE=1`, the GEMM core can preload B into a local B cache and reuse B operands during compute. When `GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1`, aligned B-cache fills can fetch four int8 B operands per 32-bit local read.

### A-row cache and packed A-row preload

When `GEMM_ENABLE_A_ROW_CACHE=1`, the core can preload the current A row once per output row and reuse it across all output columns. When `GEMM_ENABLE_PACKED_A_ROW_PRELOAD=1`, aligned A-row fills can fetch four int8 A operands per 32-bit local read.

### Cache-backed 4-lane MAC

When `GEMM_MAC_LANES=4` is enabled together with the cache/preload stack, the GEMM core can process up to four K positions per accumulation step. Tail K groups are handled by lane-valid masking.

### P10 K-dimension tiling / row accumulator

When `GEMM_ENABLE_K_TILING=1`, the cache-backed 4-lane path can process `K_total` values larger than the configured local tile size by splitting K into multiple local-cache tiles.

The P10 implementation uses an internal row accumulator:

```text
for each output row m:
  clear c_row_accum[0 .. N-1]

  for each K tile:
    preload B tile into b_cache[local_k][n]
    preload A row tile into a_row_cache[local_k]
    accumulate partial dot products into c_row_accum[n]

  write final C[m][n] once after all K tiles are complete
```

Validated P10 policy:

```text
K_tile_size = 8
N must fit GEMM_B_CACHE_MAX_N
K may exceed GEMM_B_CACHE_MAX_K and GEMM_A_ROW_CACHE_MAX_K
M/N tiling is not part of P10
Scratchpad C read-modify-write accumulation is not used in P10
```

### P11 N-dimension tiling / output-column tiling

When `GEMM_ENABLE_N_TILING=1`, the cache-backed 4-lane path can process `N_total` values larger than the configured local N tile size by splitting output columns into local N tiles.

The P11 implementation reuses the P10 row accumulator as a local-N-tile accumulator:

```text
for each output row m:
  for each N tile:
    clear c_row_accum[0 .. n_tile_len-1]

    for each K tile:
      preload B tile into b_cache[local_k][local_n]
      preload A row tile into a_row_cache[local_k]
      accumulate partial dot products into c_row_accum[local_n]

    write final C[m][n_tile_base + local_n] once after all K tiles are complete
```

Validated P11 policy:

```text
K_tile_size = 8
N_tile_size = 8
K tiling and N tiling may be active in the same job
M tiling is not part of P11
Scratchpad C read-modify-write accumulation is not used in P11
```

### GEMM completion semantics

`gemm_top.done` means:

```text
all C write requests have completed and the final C word is visible to downstream readers
```

This is stronger than a request-issued definition and is required for flows that launch DMA store immediately after `acc_done`.

---

## Performance Counters

The GEMM core exposes passive performance counters:

```text
gemm_perf_busy_cycles
gemm_perf_mac_count
gemm_perf_output_count
```

Counter policy:

```text
clear on reset
clear on accepted GEMM start
remain stable after done until next accepted GEMM start
```

For all lane/cache/tiling configurations:

```text
gemm_perf_mac_count    = M * N * K
gemm_perf_output_count = M * N
```

For P10 K-tiling, the MAC counter counts logical MACs across all K tiles.

For P11 N-tiling, the MAC counter counts logical MACs across all K tiles and N tiles.

---

## Validated Case Groups

```text
Fixed baseline       : CASE_ID 5
Variable dimension   : CASE_ID 100, 101, 105
P9 larger dimension  : CASE_ID 190, 191, 192
P10 K-tiling cases   : CASE_ID 193, 194, 195, 196, 197
P11 N-tiling cases   : CASE_ID 198, 199, 200, 201, 202
Configurable base    : CASE_ID 400, 401, 402, 403
RUN_ALL recipe       : 100 -> 101 -> 105 -> 5 -> 400 -> 401 -> 402 -> 403
Corner recipe        : 5 -> 101 -> 105 -> 403
```

P10 focused cases:

```text
CASE_ID | M | N | K  | MACS | OUTPUTS | Purpose
193     | 1 | 4 | 16 | 64   | 4       | minimum K=16 smoke
194     | 2 | 4 | 16 | 128  | 8       | multi-row K=16
195     | 4 | 4 | 16 | 256  | 16      | representative two-tile regression case
196     | 3 | 5 | 9  | 135  | 15      | tail tile 8+1 and N=5 indexing
197     | 4 | 4 | 12 | 192  | 16      | tail tile 8+4
```

P11 focused cases:

```text
CASE_ID | M | N  | K  | MACS | OUTPUTS | Purpose
198     | 1 | 16 | 8  | 128  | 16      | N tiling only, K fits one tile
199     | 2 | 16 | 8  | 256  | 32      | multi-row N tiling
200     | 4 | 16 | 16 | 1024 | 64      | representative N tiling + K tiling case
201     | 3 | 9  | 9  | 243  | 27      | N tail 8+1 and K tail 8+1
202     | 4 | 12 | 16 | 768  | 48      | N tail 8+4 and K tiles 8+8
```

---

## Execution Paths

### Host-primary path

```text
host clear C
host preload A/B
launch GEMM
host readback C
scoreboard compare
```

### DMA load-store path

```text
DMA source memory
    -> DMA load A/B into scratchpad
    -> GEMM
    -> C written into scratchpad
    -> dma_store_engine
    -> destination AXI-MM memory model
    -> result_bridge / scoreboard
```

### AXI-Stream preload / load-store path

```text
DMA / AXIS source memory
    -> axis_src_axi_ar/r responder
    -> axi_mm2s_dma
    -> axis_async_fifo
    -> axi_stream_loader
    -> axis_scratchpad_write_adapter
    -> scratchpad Port1
    -> GEMM
    -> dma_store_engine
    -> destination AXI-MM memory model
    -> result_bridge / scoreboard
```

### Direct Stream GEMM frontend path

```text
DMA / Direct Stream source memory
    -> ds_src_axi_ar/r responder
    -> axi_mm2s_dma
    -> axis_async_fifo
    -> axi_stream_loader
    -> gemm_operand_buffer A/B
    -> gemm_input_mem_router
    -> GEMM
    -> scratchpad C
    -> dma_store_engine
    -> destination AXI-MM memory model
    -> result_bridge / scoreboard
```

P10/P11 do not change any frontend protocol. The K/N-tiled GEMM path uses the same GEMM local-memory interface, so scratchpad mode and Direct Stream mode both remain compatible.

---

## Verification Architecture

The UVM environment includes:

- control monitor
- scoreboard
- result bridge
- AXI-MM host agent
- host traffic checker
- DMA source memory model
- AXI-Stream preload source memory responder
- Direct Stream preload source memory responder
- DMA destination memory model
- helper fallback path

The scoreboard checks:

- control profile consistency
- latency sanity
- ctrl/result pairing
- result compare correctness

Performance tests additionally check:

- `gemm_perf_mac_count == M*N*K`
- `gemm_perf_output_count == M*N`
- `gemm_perf_busy_cycles > 0`
- counter clear/update across multiple jobs
- profile summary generation

---

## Implemented Coverage

Current UVM regression covers:

- smoke tests for fixed, variable-dimension, and configurable-base GEMM cases
- DMA load smoke / stress / CDC / error-recovery
- DMA store / S2MM smoke / error-recovery
- DMA load + GEMM + DMA store stress regression
- AXI-Stream preload smoke / stress / CDC / error-recovery
- Direct Stream smoke / stress / CDC / error-recovery
- GEMM performance counter smoke
- GEMM performance profile baseline
- 2-lane GEMM performance and stress subsets
- B-cache / packed B-cache / A-row cache / packed A-row cache subsets
- cache-backed 4-lane MAC representative regression
- P9 scaled-cache large-dimension representative regression
- P10 K-tiling host-primary focused cases
- P10 K-tiling DMA / AXI-Stream / Direct Stream representative regression
- P11 N-tiling host-primary focused cases
- P11 N-tiling DMA / AXI-Stream / Direct Stream representative regression
- back-to-back jobs
- reset recovery
- mixed corner recipe
- mid-run reset / expected-abort recovery
- helper fallback sanity checks

---

## Current Regression Baseline

The current full UVM regression contains 71 items and is passing:

```text
TOTAL : 71
PASS  : 71
FAIL  : 0
```

P10F added these representative K-tiling items:

```text
gemm_4lane_ktiling_dma_load_store_case195
gemm_4lane_ktiling_axis_stream_load_store_case195
gemm_4lane_ktiling_direct_stream_load_store_case195
```

These all use forced single-case mode with `CASE_ID=195`, `GEMM_ENABLE_K_TILING=1`, and `GEMM_K_TILE_SIZE=8`.

P11G added these representative N-tiling items:

```text
gemm_4lane_ntiling_dma_load_store_case200
gemm_4lane_ntiling_axis_stream_load_store_case200
gemm_4lane_ntiling_direct_stream_load_store_case200
```

These all use forced single-case mode with `CASE_ID=200`, `GEMM_ENABLE_K_TILING=1`, `GEMM_K_TILE_SIZE=8`, `GEMM_ENABLE_N_TILING=1`, and `GEMM_N_TILE_SIZE=8`.

---

## Running Regression

From the `sim/` directory:

```tcl
do compile_uvm.tcl
do run_full_uvm_regression.tcl
```

Optional compile-and-run:

```tcl
set DO_COMPILE 1
do run_full_uvm_regression.tcl
```

Optional fail-fast debug:

```tcl
set STOP_ON_FIRST_FAIL 1
do run_full_uvm_regression.tcl
```

Expected current result:

```text
TOTAL : 71
PASS  : 71
FAIL  : 0
```

---

## Useful P10 Single-Test Runs

### P10 host-primary K-tiling focused case

```tcl
set UVM_TEST ai_accel_subsys_perf_counter_smoke_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 195
set RUN_ALL 0
set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14
set GEMM_MAC_LANES 4
set GEMM_ENABLE_B_CACHE 1
set GEMM_B_CACHE_MAX_K 8
set GEMM_B_CACHE_MAX_N 8
set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
set GEMM_ENABLE_A_ROW_CACHE 1
set GEMM_A_ROW_CACHE_MAX_K 8
set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1
set GEMM_ENABLE_K_TILING 1
set GEMM_K_TILE_SIZE 8
do run_uvm.tcl
```

### P10 DMA load-store K-tiling representative case

```tcl
set UVM_TEST ai_accel_subsys_dma_load_store_stress_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 195
set STORE_STRESS_JOB_COUNT 1
set STORE_STRESS_RANDOM 0
set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14
set GEMM_MAC_LANES 4
set GEMM_ENABLE_B_CACHE 1
set GEMM_B_CACHE_MAX_K 8
set GEMM_B_CACHE_MAX_N 8
set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
set GEMM_ENABLE_A_ROW_CACHE 1
set GEMM_A_ROW_CACHE_MAX_K 8
set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1
set GEMM_ENABLE_K_TILING 1
set GEMM_K_TILE_SIZE 8
do run_uvm.tcl
```

### P10 AXI-Stream load-store K-tiling representative case

```tcl
set UVM_TEST ai_accel_subsys_axis_stream_load_store_stress_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 195
set AXIS_STRESS_JOB_COUNT 1
set AXIS_STRESS_RANDOM 0
set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14
set GEMM_MAC_LANES 4
set GEMM_ENABLE_B_CACHE 1
set GEMM_B_CACHE_MAX_K 8
set GEMM_B_CACHE_MAX_N 8
set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
set GEMM_ENABLE_A_ROW_CACHE 1
set GEMM_A_ROW_CACHE_MAX_K 8
set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1
set GEMM_ENABLE_K_TILING 1
set GEMM_K_TILE_SIZE 8
do run_uvm.tcl
```

### P10 Direct Stream K-tiling representative case

```tcl
set UVM_TEST ai_accel_subsys_direct_stream_load_store_stress_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 195
set DS_STRESS_JOB_COUNT 1
set DS_STRESS_RANDOM 0
set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14
set GEMM_MAC_LANES 4
set GEMM_ENABLE_B_CACHE 1
set GEMM_B_CACHE_MAX_K 8
set GEMM_B_CACHE_MAX_N 8
set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
set GEMM_ENABLE_A_ROW_CACHE 1
set GEMM_A_ROW_CACHE_MAX_K 8
set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1
set GEMM_ENABLE_K_TILING 1
set GEMM_K_TILE_SIZE 8
do run_uvm.tcl
```

---

## Useful P11 Single-Test Runs

### P11 host-primary N-tiling focused case

```tcl
set UVM_TEST ai_accel_subsys_smoke_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 200
set RUN_ALL 0
set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14
set SMOKE_DONE_TIMEOUT_CYCLES 100000
set GEMM_MAC_LANES 4
set GEMM_ENABLE_B_CACHE 1
set GEMM_B_CACHE_MAX_K 8
set GEMM_B_CACHE_MAX_N 8
set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
set GEMM_ENABLE_A_ROW_CACHE 1
set GEMM_A_ROW_CACHE_MAX_K 8
set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1
set GEMM_ENABLE_K_TILING 1
set GEMM_K_TILE_SIZE 8
set GEMM_ENABLE_N_TILING 1
set GEMM_N_TILE_SIZE 8
do run_uvm.tcl
```

### P11 DMA load-store N-tiling representative case

```tcl
set UVM_TEST ai_accel_subsys_dma_load_store_stress_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 200
set STORE_STRESS_JOB_COUNT 1
set STORE_STRESS_RANDOM 0
set STORE_STRESS_GAP_CYCLES 10
set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14
set SMOKE_DONE_TIMEOUT_CYCLES 100000
set GEMM_MAC_LANES 4
set GEMM_ENABLE_B_CACHE 1
set GEMM_B_CACHE_MAX_K 8
set GEMM_B_CACHE_MAX_N 8
set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
set GEMM_ENABLE_A_ROW_CACHE 1
set GEMM_A_ROW_CACHE_MAX_K 8
set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1
set GEMM_ENABLE_K_TILING 1
set GEMM_K_TILE_SIZE 8
set GEMM_ENABLE_N_TILING 1
set GEMM_N_TILE_SIZE 8
do run_uvm.tcl
```

### P11 AXI-Stream load-store N-tiling representative case

```tcl
set UVM_TEST ai_accel_subsys_axis_stream_load_store_stress_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 200
set AXIS_STRESS_JOB_COUNT 1
set AXIS_STRESS_RANDOM 0
set AXIS_STRESS_GAP_CYCLES 10
set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14
set SMOKE_DONE_TIMEOUT_CYCLES 100000
set GEMM_MAC_LANES 4
set GEMM_ENABLE_B_CACHE 1
set GEMM_B_CACHE_MAX_K 8
set GEMM_B_CACHE_MAX_N 8
set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
set GEMM_ENABLE_A_ROW_CACHE 1
set GEMM_A_ROW_CACHE_MAX_K 8
set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1
set GEMM_ENABLE_K_TILING 1
set GEMM_K_TILE_SIZE 8
set GEMM_ENABLE_N_TILING 1
set GEMM_N_TILE_SIZE 8
do run_uvm.tcl
```

### P11 Direct Stream N-tiling representative case

```tcl
set UVM_TEST ai_accel_subsys_direct_stream_load_store_stress_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 200
set DS_STRESS_JOB_COUNT 1
set DS_STRESS_RANDOM 0
set DS_STRESS_GAP_CYCLES 10
set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14
set SMOKE_DONE_TIMEOUT_CYCLES 100000
set GEMM_MAC_LANES 4
set GEMM_ENABLE_B_CACHE 1
set GEMM_B_CACHE_MAX_K 8
set GEMM_B_CACHE_MAX_N 8
set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
set GEMM_ENABLE_A_ROW_CACHE 1
set GEMM_A_ROW_CACHE_MAX_K 8
set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1
set GEMM_ENABLE_K_TILING 1
set GEMM_K_TILE_SIZE 8
set GEMM_ENABLE_N_TILING 1
set GEMM_N_TILE_SIZE 8
do run_uvm.tcl
```

---

## Known Warning

Questa may report `vsim-3838` multiple-driver warnings around `bram_axi0_if` request-side signals.

Current policy:

```text
Known warning accepted.
Functional regression passes.
No BRAM interface semantic change required.
```

---

## Current Milestone Summary

```text
Performance GEMM P11: N-Dimension Tiling Completed

Completed:
  P0: GEMM performance counter smoke                       PASS
  P1: GEMM performance profile baseline                    PASS
  P2: 2-lane MAC datapath                                  PASS
  P3: 2-lane stress / CDC hardening                        PASS
  P4: B-cache operand reuse                                PASS
  P5: packed B-cache preload                               PASS
  P6: scalar A-row cache                                   PASS
  P7: packed A-row preload                                 PASS
  P8: cache-backed true 4-lane MAC                         PASS
  P9: larger-dimension / cache-size scaling                PASS
  P10B: safe K-tiling parameter plumbing                   PASS
  P10C: K>8 testcase / software reference support          PASS
  P10D: actual K-tile execution microarchitecture          PASS
  P10E: frontend compatibility sanity                      PASS
  P10F: regression integration                             PASS
  P11A: N-tiling / output-column tiling spec               PASS
  P11B: safe N-tiling parameter plumbing                   PASS
  P11C: N>8 testcase / software reference support          PASS
  P11D: actual N-tile execution microarchitecture          PASS
  P11E: frontend compatibility sanity                      PASS
  P11G: regression integration                             PASS
  P11H: documentation / closure update                     PASS

Regression:
  71/71 PASS
```

---

## Summary

This repository currently contains a working GEMM-oriented AI accelerator subsystem with stable scratchpad-backed RTL integration, DMA and frontend data movement, Direct Stream operand-buffer input, scoreboard-based verification, cache-backed multi-lane GEMM compute, scaled cache8 larger-dimension support, K-dimension tiling, and N-dimension output-column tiling using row-accumulator partial accumulation.

P11 proves that the 4-lane cache-backed GEMM path can handle both `K_total` and `N_total` larger than the local tile capacity by composing K tiles with output-column N tiles and writing each final C output once after all tile accumulation completes.
