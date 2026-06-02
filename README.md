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

The current focus is subsystem integration, DMA load/store behavior, AXI-Stream frontend integration, Direct Stream GEMM frontend integration, CDC-aware control/status handling, reset robustness, UVM scoreboard-based verification, performance-oriented GEMM datapath upgrades, and AXI-Lite CSR control-plane integration.

Current milestone:

```text
CSR Control Plane P14E2: CSR-Controlled Host-Primary GEMM Regression Integration Completed

Regression:
  TOTAL : 84
  PASS  : 84
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
GEMM_MAC_LANES=4 + M-tiling representative regression across DMA / AXI-Stream / Direct Stream
GEMM_MAC_LANES=4 + C RMW accumulation focused and frontend representative regression
AXI-Lite CSR standalone smoke and CSR-controlled host-primary GEMM representative regression
```

Validated P13 C RMW accumulation representative configuration:

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
GEMM_ENABLE_M_TILING=1
GEMM_M_TILE_SIZE=2
GEMM_ENABLE_C_RMW_ACCUM=1
ACCUMULATE_ENABLE=0
```

P10 extends the P9 cache8 path to K values larger than the local cache depth by executing multiple K tiles and accumulating partial sums in an internal row accumulator before writing final C results.

P11 extends the P10 row-accumulator model to output-column tiling.  It supports `N_total` larger than the local B-cache / row-accumulator N capacity by splitting output columns into local N tiles.

P12 extends the P11 tiled model to M-dimension tiling.  It supports `M_total` larger than the local M tile size by grouping output rows into local M tiles and accumulating a local M/N output tile before final C writeback.

P13 extends the P12 tiled model to external partial-K accumulation.  Multiple GEMM jobs can contribute partial sums to the same C region by optionally reading old C from scratchpad, adding the current partial sum, and writing the accumulated result back.

P13 scope:

```text
C read-modify-write accumulation across external partial-K GEMM jobs
GEMM_ENABLE_C_RMW_ACCUM enables the optional datapath
accumulate_enable is driven per job by the control sequence
job0 uses accumulate_enable=0 and writes the first partial C
job1 and later jobs use accumulate_enable=1 and add to old C
K/N/M tiling composes with C RMW accumulation
Direct Stream A/B reads use operand buffer while C RMW reads/writes use scratchpad
```

P14 extends the validated sideband-controlled subsystem with an AXI-Lite CSR control-plane wrapper.  The existing datapath top remains intact, while the CSR wrapper lets software or UVM program base addresses, dimensions, modes, command pulses, sticky status, and performance snapshots through registers.

P14E2 validated the first CSR-controlled host-primary GEMM regression entries:

```text
CSR standalone register smoke through integrated run_uvm.tcl
CSR-controlled host-primary GEMM CASE_ID=100
CSR-controlled host-primary GEMM CASE_ID=102
Full regression: 84/84 PASS
```

---

## Main RTL Blocks

- `ai_accel_subsys`
- `ai_accel_subsys_csr_top`
- `ai_accel_csr_regs`
- `axi_lite_if`
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

`ai_accel_subsys_csr_top` is a CSR wrapper around the existing `ai_accel_subsys` datapath top.  It is used by CSR-controlled tests and does not replace the legacy sideband UVM top.

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
parameter bit GEMM_ENABLE_M_TILING              = 1'b0
parameter int GEMM_M_TILE_SIZE                  = 2
parameter bit GEMM_ENABLE_C_RMW_ACCUM           = 1'b0
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

P9/P10/P11/P12 scaled cache capacity:
  GEMM_B_CACHE_MAX_K=8
  GEMM_B_CACHE_MAX_N=8
  GEMM_A_ROW_CACHE_MAX_K=8

P10 K-tiling opt-in:
  GEMM_ENABLE_K_TILING=1
  GEMM_K_TILE_SIZE=8

P11 N-tiling opt-in:
  GEMM_ENABLE_N_TILING=1
  GEMM_N_TILE_SIZE=8

P12 M-tiling opt-in:
  GEMM_ENABLE_M_TILING=1
  GEMM_M_TILE_SIZE=2

P13 C RMW accumulation opt-in:
  GEMM_ENABLE_C_RMW_ACCUM=1
  accumulate_enable is captured per GEMM job
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
GEMM_ENABLE_M_TILING=0
GEMM_ENABLE_C_RMW_ACCUM=0
ACCUMULATE_ENABLE=0
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

### P12 M-dimension tiling / multi-row output tile scheduling

When `GEMM_ENABLE_M_TILING=1`, the cache-backed 4-lane path can process `M_total` values larger than the configured local M tile size by splitting output rows into local M tiles.

The P12 implementation extends the P11 row accumulator into a local M/N output-tile accumulator:

```text
for each M tile:
  for each N tile:
    clear c_tile_accum[local_m][local_n]

    for each K tile:
      preload B tile into b_cache[local_k][local_n]

      for each local_m in the active M tile:
        preload A row tile into a_row_cache[local_k]
        accumulate partial dot products into c_tile_accum[local_m][local_n]

    write final C[m_tile_base + local_m][n_tile_base + local_n]
    once after all K tiles are complete
```

Validated P12 policy:

```text
M_tile_size = 2
K_tile_size = 8
N_tile_size = 8
K tiling, N tiling, and M tiling may be active in the same job
B tile is reused across active local M rows inside one M tile
Scratchpad C read-modify-write accumulation is not used in P12
```

### P13 C read-modify-write partial accumulation

When `GEMM_ENABLE_C_RMW_ACCUM=1`, the final C writeback point can optionally read old C from scratchpad before writing the new result.

For each output element in one partial job:

```text
partial_sum = current job dot product

if accumulate_enable == 0:
  C_new = partial_sum

if accumulate_enable == 1:
  C_old = scratchpad_read(C_addr)
  C_new = C_old + partial_sum

scratchpad_write(C_addr, C_new)
```

The standard P13 recipe uses compact per-job A/B payloads and keeps `base_c`, M, and N constant across partial jobs.

Validated P13 policy:

```text
GEMM_ENABLE_C_RMW_ACCUM = 1
ACCUMULATE_ENABLE = 0 at top-level default
per-job accumulate_enable is driven by the UVM recipe
job0 writes partial_sum directly
job1 reads old C and accumulates the second partial sum
Done waits for final C RMW write completion
```

Direct Stream mode keeps the same A/B operand-buffer policy, but C RMW old-C reads and C writes route to scratchpad.

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

For P12 M-tiling, the MAC counter counts logical MACs across all M tiles, N tiles, and K tiles.

For P13 C RMW recipes, counters remain per GEMM job:

```text
gemm_perf_mac_count    = M * N * K_part
gemm_perf_output_count = M * N
```

Across the full external recipe, the logical MAC count is the sum of all partial jobs. C RMW read transactions do not increase `gemm_perf_mac_count`.

---

## Validated Case Groups

```text
Fixed baseline       : CASE_ID 5
Variable dimension   : CASE_ID 100, 101, 105
P9 larger dimension  : CASE_ID 190, 191, 192
P10 K-tiling cases   : CASE_ID 193, 194, 195, 196, 197
P11 N-tiling cases   : CASE_ID 198, 199, 200, 201, 202
P12 M-tiling cases   : CASE_ID 203, 204, 205, 206, 207
P13 C RMW recipes    : CASE_ID 208, 209, 210, 211, 212
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


P13 focused recipes:

```text
CASE_ID | M | N  | K_total | Parts | OUTPUTS | Purpose
208     | 1 | 4  | 16      | 8+8   | 4       | minimum two-job accumulation smoke
209     | 4 | 4  | 16      | 8+8   | 16      | multi-row accumulation
210     | 4 | 16 | 16      | 8+8   | 64      | accumulation with N tiling
211     | 8 | 16 | 16      | 8+8   | 128     | accumulation with M and N tiling
212     | 5 | 9  | 9       | 8+1   | 45      | ragged M/N and tail K partition
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

### CSR-controlled host-primary path

```text
host clear C
host preload A/B
CSR writes GEMM base/dim/mode
CSR writes START_GEMM command
CSR polls GEMM_DONE and reads performance snapshot
host readback C
CSR smoke test compares C against software reference
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

P10/P11/P12/P13 do not change any frontend protocol. The K/N/M-tiled GEMM path and the C RMW accumulation path use the same GEMM local-memory interface, so scratchpad mode and Direct Stream mode both remain compatible.

Direct Stream routing policy with P13 C RMW enabled:

```text
GEMM A/B reads          -> operand buffer
GEMM C RMW old-C reads  -> scratchpad adapter
GEMM C writes           -> scratchpad adapter
```

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
- P12 M-tiling host-primary focused cases
- P12 M-tiling DMA / AXI-Stream / Direct Stream representative regression
- P13 C RMW accumulation focused cases
- P13 C RMW DMA / AXI-Stream / Direct Stream representative regression
- AXI-Lite CSR standalone register smoke
- CSR-controlled host-primary GEMM representative regression
- back-to-back jobs
- reset recovery
- mixed corner recipe
- mid-run reset / expected-abort recovery
- helper fallback sanity checks

---

## Current Regression Baseline

The current full UVM regression contains 84 items and is passing:

```text
TOTAL : 84
PASS  : 84
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

P12G added these representative M-tiling items:

```text
gemm_4lane_mtiling_dma_load_store_case207
gemm_4lane_mtiling_axis_stream_load_store_case207
gemm_4lane_mtiling_direct_stream_load_store_case207
```

These all use forced single-case mode with `CASE_ID=207`, `GEMM_ENABLE_K_TILING=1`, `GEMM_K_TILE_SIZE=8`, `GEMM_ENABLE_N_TILING=1`, `GEMM_N_TILE_SIZE=8`, `GEMM_ENABLE_M_TILING=1`, and `GEMM_M_TILE_SIZE=2`.

P13D added these focused C RMW DUT recipe items:

```text
p13d_c_rmw_accum_case208
p13d_c_rmw_accum_case209
p13d_c_rmw_accum_case210
p13d_c_rmw_accum_case211
p13d_c_rmw_accum_case212
```

These all use `GEMM_ENABLE_C_RMW_ACCUM=1` and `ACCUMULATE_ENABLE=0`. The test drives per-job `accumulate_enable` through the UVM control interface.

P13G added these representative C RMW frontend items:

```text
gemm_4lane_c_rmw_dma_load_store_case211
gemm_4lane_c_rmw_axis_stream_load_store_case211
gemm_4lane_c_rmw_direct_stream_load_store_case211
```

These use forced single-recipe mode with `CASE_ID=211`, the full P12 cache/tile stack, and `GEMM_ENABLE_C_RMW_ACCUM=1`.

P14E2 added these CSR-controlled host-primary items:

```text
csr_host_smoke_case100
csr_host_smoke_case102
```

These use `UVM_TOP=ai_accel_subsys_csr_uvm_top`, program the GEMM job through AXI-Lite CSR writes, poll sticky GEMM done status, read the CSR performance snapshot, and compare host-readback C against the software reference.

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
TOTAL : 84
PASS  : 84
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

## Useful P12 Single-Test Runs

### P12 host-primary M-tiling focused case

```tcl
set UVM_TEST ai_accel_subsys_smoke_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 207
set RUN_ALL 0
set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14
set SMOKE_DONE_TIMEOUT_CYCLES 200000
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
set GEMM_ENABLE_M_TILING 1
set GEMM_M_TILE_SIZE 2
do run_uvm.tcl
```

### P12 DMA load-store M-tiling representative case

```tcl
set UVM_TEST ai_accel_subsys_dma_load_store_stress_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 207
set STORE_STRESS_JOB_COUNT 1
set STORE_STRESS_RANDOM 0
set STORE_STRESS_GAP_CYCLES 10
set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14
set SMOKE_DONE_TIMEOUT_CYCLES 200000
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
set GEMM_ENABLE_M_TILING 1
set GEMM_M_TILE_SIZE 2
do run_uvm.tcl
```

### P12 AXI-Stream load-store M-tiling representative case

```tcl
set UVM_TEST ai_accel_subsys_axis_stream_load_store_stress_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 207
set AXIS_STRESS_JOB_COUNT 1
set AXIS_STRESS_RANDOM 0
set AXIS_STRESS_GAP_CYCLES 10
set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14
set SMOKE_DONE_TIMEOUT_CYCLES 200000
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
set GEMM_ENABLE_M_TILING 1
set GEMM_M_TILE_SIZE 2
do run_uvm.tcl
```

### P12 Direct Stream M-tiling representative case

```tcl
set UVM_TEST ai_accel_subsys_direct_stream_load_store_stress_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 207
set DS_STRESS_JOB_COUNT 1
set DS_STRESS_RANDOM 0
set DS_STRESS_GAP_CYCLES 10
set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14
set SMOKE_DONE_TIMEOUT_CYCLES 200000
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
set GEMM_ENABLE_M_TILING 1
set GEMM_M_TILE_SIZE 2
do run_uvm.tcl
```

---


## Useful P13 Single-Test Runs

### P13 host-primary C RMW focused recipe

```tcl
set UVM_TEST ai_accel_subsys_c_rmw_accum_dut_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 211
set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14
set SMOKE_DONE_TIMEOUT_CYCLES 300000
set GEMM_ENABLE_C_RMW_ACCUM 1
set ACCUMULATE_ENABLE 0
do run_uvm.tcl
```

### P13 DMA load-store C RMW representative recipe

```tcl
set UVM_TEST ai_accel_subsys_dma_load_store_stress_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 211
set STORE_STRESS_JOB_COUNT 1
set STORE_STRESS_RANDOM 0
set STORE_STRESS_GAP_CYCLES 10
set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14
set SMOKE_DONE_TIMEOUT_CYCLES 300000
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
set GEMM_ENABLE_M_TILING 1
set GEMM_M_TILE_SIZE 2
set GEMM_ENABLE_C_RMW_ACCUM 1
set ACCUMULATE_ENABLE 0
do run_uvm.tcl
```

For AXI-Stream or Direct Stream C RMW representative runs, switch only the frontend test and stress knobs:

```text
AXI-Stream:
  UVM_TEST = ai_accel_subsys_axis_stream_load_store_stress_test
  AXIS_STRESS_JOB_COUNT=1
  AXIS_STRESS_RANDOM=0

Direct Stream:
  UVM_TEST = ai_accel_subsys_direct_stream_load_store_stress_test
  DS_STRESS_JOB_COUNT=1
  DS_STRESS_RANDOM=0
```

---


## Useful P14 Single-Test Runs

### P14D standalone CSR register smoke

```tcl
set UVM_TEST ai_accel_csr_regs_smoke_test
set UVM_TOP ai_accel_csr_regs_uvm_top
do run_uvm.tcl
```

### P14E CSR-controlled host-primary GEMM smoke

```tcl
set UVM_TEST ai_accel_subsys_csr_smoke_test
set UVM_TOP ai_accel_subsys_csr_uvm_top
set CASE_ID 100
set ENABLE_RESULT_CHECK 1
set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14
do run_uvm.tcl
```

### P14E CSR-controlled host-primary representative case

```tcl
set UVM_TEST ai_accel_subsys_csr_smoke_test
set UVM_TOP ai_accel_subsys_csr_uvm_top
set CASE_ID 102
set ENABLE_RESULT_CHECK 1
set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14
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
CSR Control Plane P14E2: CSR-Controlled Host-Primary GEMM Regression Integration Completed

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
  P12A: M-tiling / multi-row tile scheduling spec         PASS
  P12B: safe M-tiling parameter plumbing                  PASS
  P12C: M>current-row testcase / reference support        PASS
  P12D: actual M-tile execution microarchitecture         PASS
  P12E: host-primary focused validation                   PASS
  P12F: frontend compatibility sanity                     PASS
  P12G: regression integration                            PASS
  P12H: documentation / closure update                    PASS
  P13A: C RMW / partial accumulation spec                  PASS
  P13B: safe C RMW parameter / control-bit plumbing        PASS
  P13C: partial-sum recipe / reference support             PASS
  P13D: RTL C RMW datapath                                 PASS
  P13E: host-primary focused validation                    PASS
  P13F: frontend compatibility sanity                      PASS
  P13G: regression integration                             PASS
  P13H: documentation / closure update                     PASS
  P14A: AXI-Lite CSR control-plane spec                     PASS
  P14B: standalone AXI-Lite CSR register block              PASS
  P14C: CSR wrapper around existing subsystem               PASS
  P14D: CSR access helper and integrated run flow           PASS
  P14E: CSR-controlled host-primary GEMM smoke              PASS
  P14E2: CSR regression integration                         PASS

Regression:
  84/84 PASS
```

---

## Summary

This repository currently contains a working GEMM-oriented AI accelerator subsystem with stable scratchpad-backed RTL integration, DMA and frontend data movement, Direct Stream operand-buffer input, scoreboard-based verification, cache-backed multi-lane GEMM compute, scaled cache8 larger-dimension support, K-dimension tiling, N-dimension output-column tiling, M-dimension multi-row output tile scheduling, C read-modify-write partial accumulation, and an AXI-Lite CSR control-plane wrapper.

P13 proves that the 4-lane cache-backed GEMM path can compose K/N/M tiling with external partial-K accumulation. The validated recipe writes the first partial C directly, reads old C for later partial jobs, accumulates the new partial sum, and preserves compatibility across host-primary, DMA load-store, AXI-Stream load-store, and Direct Stream load-store paths.

P14E2 proves that the subsystem can also be launched through a software-visible CSR control plane. The CSR-controlled host-primary regression programs GEMM base addresses and dimensions through AXI-Lite registers, issues a START_GEMM command, polls sticky done status, reads performance snapshots, and compares host-readback C against the software reference.
