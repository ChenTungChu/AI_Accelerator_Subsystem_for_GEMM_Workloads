# AI Accelerator Subsystem for GEMM Workloads

## Overview

This repository is a subsystem-level RTL and UVM verification project for a GEMM-oriented AI accelerator path.

The design currently validates end-to-end data-movement flows for multiple GEMM input paths:

```text
Host / DMA / AXI-Stream preload / Direct Stream operand preload
    -> Scratchpad memory or GEMM operand buffer
    -> GEMM core
    -> Scratchpad result C
    -> Host readback or DMA store
    -> Software reference / scoreboard compare
```

The current focus is subsystem integration, DMA load/store behavior, AXI-Stream frontend integration, Direct Stream GEMM frontend integration, CDC-aware control/status handling, reset robustness, UVM scoreboard-based verification, and performance-oriented GEMM datapath upgrades. The performance path now includes a parameterized 2-lane K-parallel MAC datapath, a B-operand cache / compute-bypass optimization, a packed B-cache preload optimization, a scalar A-row cache optimization, and a packed A-row preload optimization.

Current milestone:

```text
Performance GEMM P7: Packed A-row Preload Optimization Completed

Regression:
  TOTAL : 59
  PASS  : 59
  FAIL  : 0
```

The current baseline includes:

```text
GEMM_MAC_LANES=1 mainline regression
GEMM_MAC_LANES=2 focused performance subset regression
GEMM_MAC_LANES=2 stress / CDC hardening subset regression
GEMM_MAC_LANES=2 + GEMM_ENABLE_B_CACHE=1 representative regression
GEMM_MAC_LANES=2 + GEMM_ENABLE_B_CACHE=1 + GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1 representative regression
GEMM_MAC_LANES=2 + GEMM_ENABLE_B_CACHE=1 + GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1 + GEMM_ENABLE_A_ROW_CACHE=1 stress / CDC representative regression
GEMM_MAC_LANES=2 + GEMM_ENABLE_B_CACHE=1 + GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1 + GEMM_ENABLE_A_ROW_CACHE=1 + GEMM_ENABLE_PACKED_A_ROW_PRELOAD=1 representative regression
```

Direct Stream B1 remains supported:

```text
AXI-MM source memory
    -> MM2S DMA
    -> AXI-Stream async FIFO
    -> stream loader
    -> GEMM operand buffer A/B
    -> GEMM reads A/B from operand buffer
    -> GEMM writes C to scratchpad
    -> DMA store C to destination memory
    -> scoreboard compare
```

Performance GEMM P2 added a parameterized 2-lane K-parallel MAC path inside `gemm_top` while preserving the original single-lane behavior as the default safe configuration.

Performance GEMM P3 expands the 2-lane coverage from smoke/profile into stress and CDC sanity across the DMA, AXI-Stream, and Direct Stream load-store paths.

Performance GEMM P4 adds B-operand cache support for the 2-lane GEMM path. When the configured GEMM dimensions fit within the cache limits, B operands are preloaded once per job and reused during compute, reducing repeated B reads from the scratchpad or operand-buffer path. P4 also fixed the GEMM completion semantics so `done` is asserted only after the final C write has completed, which prevents downstream DMA-store readback from observing stale C data.


Performance GEMM P5 adds optional packed B-cache preload. When `GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1`, B-cache preload reads aligned 32-bit local memory windows and unpacks four int8 B operands per read when `base_addr_b` is 4-byte aligned. Unaligned B bases fall back to the scalar P4 B-cache preload path. P5 also updates the scratchpad adapter local-read return contract so `mem_rd_data[31:0]` can carry a 32-bit byte window while preserving scalar compatibility through `mem_rd_data[7:0]`.

Performance GEMM P6 adds optional scalar A-row cache support. When `GEMM_ENABLE_A_ROW_CACHE=1` and the configured row fits within `GEMM_A_ROW_CACHE_MAX_K`, GEMM preloads the current A row once per output row `m` and reuses it across all output columns `n`. The first P6 implementation is intentionally scalar and requires the B-cache performance stack, so the validated mode is `GEMM_MAC_LANES=2 + GEMM_ENABLE_B_CACHE=1 + GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1 + GEMM_ENABLE_A_ROW_CACHE=1`.

Performance GEMM P7 adds optional packed A-row preload support. When `GEMM_ENABLE_PACKED_A_ROW_PRELOAD=1` and the configured A row is aligned and supported, GEMM fills the A-row cache using aligned 32-bit local reads and unpacks four int8 A operands per read. Unsupported cases fall back to the scalar P6 A-row preload path. P7 preserves the compute path and only optimizes the A-row cache fill mechanism.
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

`gemm_top` now supports:

```systemverilog
parameter int GEMM_MAC_LANES       = 1
parameter bit GEMM_ENABLE_B_CACHE                  = 1'b0
parameter int GEMM_B_CACHE_MAX_K                   = 4
parameter int GEMM_B_CACHE_MAX_N                   = 4
parameter bit GEMM_ENABLE_PACKED_BCACHE_PRELOAD    = 1'b0
parameter bit GEMM_ENABLE_A_ROW_CACHE               = 1'b0
parameter int GEMM_A_ROW_CACHE_MAX_K                = 4
parameter bit GEMM_ENABLE_PACKED_A_ROW_PRELOAD      = 1'b0
```

Supported lane settings:

```text
GEMM_MAC_LANES=1 : original single-MAC baseline
GEMM_MAC_LANES=2 : 2-lane K-parallel MAC prototype
```

Supported B-cache settings:

```text
GEMM_ENABLE_B_CACHE=0 : original no-cache B operand path
GEMM_ENABLE_B_CACHE=1 : preload B[k][n] into a local cache when dim_k/dim_n fit the configured cache bounds
```

Supported packed B-cache preload settings:

```text
GEMM_ENABLE_PACKED_BCACHE_PRELOAD=0 : original scalar B-cache preload path
GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1 : use aligned 32-bit packed B-cache preload when B base is 4-byte aligned
```

Supported A-row cache settings:

```text
GEMM_ENABLE_A_ROW_CACHE=0 : original compute-driven A operand read path
GEMM_ENABLE_A_ROW_CACHE=1 : preload one A row per m and reuse it across n when K fits GEMM_A_ROW_CACHE_MAX_K
```

Supported packed A-row preload settings:

```text
GEMM_ENABLE_PACKED_A_ROW_PRELOAD=0 : original scalar A-row preload path
GEMM_ENABLE_PACKED_A_ROW_PRELOAD=1 : use aligned 32-bit packed A-row preload when A base is 4-byte aligned and K is a supported multiple of 4
```

The default remains `GEMM_MAC_LANES=1`, `GEMM_ENABLE_B_CACHE=0`, `GEMM_ENABLE_PACKED_BCACHE_PRELOAD=0`, `GEMM_ENABLE_A_ROW_CACHE=0`, and `GEMM_ENABLE_PACKED_A_ROW_PRELOAD=0` so existing regression behavior is preserved unless the run script explicitly overrides these parameters.

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

Some tests use shifted legal base addresses to verify configurable memory mapping.

For Direct Stream B1, A/B are loaded into local operand buffers instead of scratchpad. The logical A/B base addresses are still used by `gemm_input_mem_router` to classify GEMM reads and translate them into local operand-buffer offsets.

---

## GEMM Compute Architecture

### Single-lane baseline

The default GEMM algorithm is:

```text
for m in 0 .. M-1:
  for n in 0 .. N-1:
    acc = 0
    for k in 0 .. K-1:
      acc += A[m][k] * B[k][n]
    C[m][n] = acc
```

This is the compatibility baseline used by the main regression.

### 2-lane K-parallel prototype

When `GEMM_MAC_LANES=2`, the core processes up to two K positions per accumulation step:

```text
for k in 0 .. K-1 step 2:
    acc += A[m][k + 0] * B[k + 0][n]

    if (k + 1 < K):
        acc += A[m][k + 1] * B[k + 1][n]
```

Odd-K cases are handled by lane masking. For example, `K=1` uses only lane 0, while `K=2` and `K=4` use both lanes.

The first 2-lane implementation is correctness-first. It keeps the existing single-read local memory interface and sequentially collects lane operands before committing the multi-lane MAC step.

### B-cache operand reuse prototype

When `GEMM_ENABLE_B_CACHE=1` and the active job fits within `GEMM_B_CACHE_MAX_K` and `GEMM_B_CACHE_MAX_N`, `gemm_top` preloads the B matrix tile into a small local cache before compute begins:

```text
for k in 0 .. K-1:
  for n in 0 .. N-1:
    b_cache[k][n] = B[k][n]
```

During compute, B operands are read from the local cache instead of repeatedly issuing B reads through the local memory request interface:

```text
lane0 B operand = b_cache[k + 0][n]
lane1 B operand = b_cache[k + 1][n] when lane1 is valid
```

If the job dimensions do not fit the configured cache bounds, the design falls back to the original non-cache B operand path. This keeps the optimization correctness-safe for unsupported dimensions.


### Packed B-cache preload optimization

When both `GEMM_ENABLE_B_CACHE=1` and `GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1`, the B-cache fill path can fetch four int8 B operands per local 32-bit read:

```text
scalar P4 preload:
  one local read per B element

packed P5 preload:
  one aligned local read per four B elements
  unpack mem_rd_data[7:0], [15:8], [23:16], [31:24]
```

The first P5 implementation uses a conservative activation policy:

```text
packed preload active only when base_addr_b[1:0] == 2'b00
otherwise fallback to scalar B-cache preload
```

This keeps configurable-base and Direct Stream behavior stable while still proving the memory-granularity optimization on aligned B regions.

### Scalar A-row cache optimization

When `GEMM_ENABLE_A_ROW_CACHE=1`, the GEMM core can preload the current A row once per output row and reuse that row across all output columns:

```text
for each m:
  preload A[m][0 .. K-1] into a_row_cache
  for each n:
    compute C[m][n] using cached A row and cached B operands
```

For the first P6 implementation, A-row cache is validated as part of the completed performance stack:

```text
GEMM_MAC_LANES=2
GEMM_ENABLE_B_CACHE=1
GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1
GEMM_ENABLE_A_ROW_CACHE=1
GEMM_A_ROW_CACHE_MAX_K=4
```

This reduces A-side reads for supported dimensions from `M*N*K` to `M*K`. For 4x4x4 cases, A reads are reduced from 64 to 16 before compute reuse.

### Packed A-row preload optimization

When both `GEMM_ENABLE_A_ROW_CACHE=1` and `GEMM_ENABLE_PACKED_A_ROW_PRELOAD=1`, the A-row cache fill path can fetch four int8 A operands per local 32-bit read:

```text
scalar P6 A-row preload:
  one local read per A element in the active row

packed P7 A-row preload:
  one aligned local read per four A elements
  unpack mem_rd_data[7:0], [15:8], [23:16], [31:24]
```

The first P7 implementation uses a conservative activation policy:

```text
packed A-row preload active only when:
  A-row cache is active
  A operands are int8
  base_addr_a[1:0] == 2'b00
  dim_k[1:0] == 2'b00
  dim_k fits GEMM_A_ROW_CACHE_MAX_K
otherwise fallback to scalar A-row preload
```

For the current K=4 performance cases, this reduces A-row cache fill reads from `M*K` to `M*(K/4)`. For 4x4x4 cases, A-row fill reads are reduced from 16 to 4 while preserving the P6 compute semantics.

### GEMM completion semantics

`gemm_top.done` now means:

```text
all C write requests have completed and the final C word is visible to downstream readers
```

This is stronger than the earlier request-issued definition and is required for flows that launch DMA store immediately after `acc_done`.

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

Counter meaning:

```text
gemm_perf_busy_cycles  : cycles while GEMM is busy
gemm_perf_mac_count    : logical MAC operations committed
gemm_perf_output_count : C outputs whose local-memory write completion has been observed
```

For both single-lane and 2-lane modes:

```text
gemm_perf_mac_count    = M * N * K
gemm_perf_output_count = M * N
```

In 2-lane mode, `gemm_perf_mac_count` increments by the number of valid lanes committed, not by the number of MAC FSM states. `gemm_perf_output_count` increments when each C write completion is observed, matching the corrected GEMM done semantics.

---

## Current Performance Profile Baselines

### Single-lane baseline (`GEMM_MAC_LANES=1`)

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

### 2-lane baseline (`GEMM_MAC_LANES=2`)

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

`CASE_ID=100` has `K=1`, so lane 1 is masked and the cycle count remains unchanged. Cases with `K>=2` show the 2-lane path is active.

### 2-lane + B-cache representative profile (`GEMM_MAC_LANES=2`, `GEMM_ENABLE_B_CACHE=1`)

P4 validation confirmed that B-cache reuse reduces repeated B operand reads for supported tiles. Representative 4x4x4 cases improved from the 2-lane no-cache baseline of approximately 1609-1610 busy cycles to approximately 1146-1147 busy cycles while preserving:

```text
gemm_perf_mac_count    = M * N * K
gemm_perf_output_count = M * N
result compare         = PASS
```

The exact cycle count still depends on the selected frontend path, clock ratio, and memory arbitration pattern.

---


### 2-lane + packed B-cache representative profile (`GEMM_MAC_LANES=2`, `GEMM_ENABLE_B_CACHE=1`, `GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1`)

P5 validation confirmed that packed B-cache preload reduces B-cache fill overhead for larger supported tiles. Representative profile results:

```text
CASE_ID | M | N | K | MACS | OUTPUTS | BUSY
100     | 1 | 1 | 1 | 1    | 1       | 43
101     | 2 | 2 | 2 | 8    | 4       | 182
105     | 2 | 3 | 4 | 24   | 6       | 415
5       | 4 | 4 | 4 | 64   | 16      | 1060
400     | 4 | 4 | 4 | 64   | 16      | 1060
401     | 4 | 4 | 4 | 64   | 16      | 1060
402     | 4 | 4 | 4 | 64   | 16      | 1060
403     | 4 | 4 | 4 | 64   | 16      | 1060
```

Compared with the P4 scalar B-cache baseline, the 4x4x4 class improved from roughly 1146-1147 busy cycles to roughly 1060 busy cycles. `CASE_ID=100` is intentionally not a performance win because it has only one B byte and cannot amortize the packed-preload FSM overhead.

### 2-lane + packed B-cache + A-row cache representative profile (`GEMM_MAC_LANES=2`, `GEMM_ENABLE_B_CACHE=1`, `GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1`, `GEMM_ENABLE_A_ROW_CACHE=1`)

P6 validation confirmed that scalar A-row cache reduces repeated A operand reads across output columns for supported rows. Representative profile results:

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

Compared with the P5 packed B-cache baseline, the 4x4x4 class improved from roughly 1060 busy cycles to roughly 627 busy cycles. `CASE_ID=100` is intentionally not improved because `N=1`, so there is no A-row reuse opportunity.


### 2-lane + packed B-cache + A-row cache + packed A-row preload representative profile (`GEMM_MAC_LANES=2`, `GEMM_ENABLE_B_CACHE=1`, `GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1`, `GEMM_ENABLE_A_ROW_CACHE=1`, `GEMM_ENABLE_PACKED_A_ROW_PRELOAD=1`)

P7 validation confirmed that packed A-row preload reduces the remaining A-row cache fill overhead for supported aligned K=4 rows. Representative profile results:

```text
CASE_ID | M | N | K | MACS | OUTPUTS | BUSY
100     | 1 | 1 | 1 | 1    | 1       | 43
101     | 2 | 2 | 2 | 8    | 4       | 152
105     | 2 | 3 | 4 | 24   | 6       | 275
5       | 4 | 4 | 4 | 64   | 16      | 500
400     | 4 | 4 | 4 | 64   | 16      | 500
401     | 4 | 4 | 4 | 64   | 16      | 500
402     | 4 | 4 | 4 | 64   | 16      | 500
403     | 4 | 4 | 4 | 64   | 16      | 500
```

Compared with the P6 scalar A-row preload baseline, the 4x4x4 class improved from roughly 627 busy cycles to roughly 500 busy cycles. `CASE_ID=100` and `CASE_ID=101` fall back to the scalar A-row preload path under the first conservative P7 policy because their K values are not multiples of 4.

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

The control monitor publishes phase-aware `START` and `DONE` events. The result bridge publishes result payloads into the scoreboard.

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
- 2-lane profile summary generation

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

This is the main strict verification path.

### DMA load path

```text
DMA source memory
    -> dma_load_engine
    -> scratchpad_port0_owner_mux
    -> BRAM Port0
    -> GEMM
    -> Host readback C
    -> result_bridge / scoreboard
```

### DMA store / S2MM path

```text
DMA source memory
    -> DMA load A/B into scratchpad
    -> GEMM
    -> C written into scratchpad
    -> dma_store_engine
    -> destination AXI-MM memory model
    -> result_bridge / scoreboard
```

### AXI-Stream preload path

```text
DMA / AXIS source memory
    -> axis_src_axi_ar/r responder
    -> axi_mm2s_dma
    -> axis_async_fifo
    -> axi_stream_loader
    -> axis_scratchpad_write_adapter
    -> scratchpad_port1_owner_mux
    -> BRAM Port1
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
    -> gemm_operand_buffer_write_adapter
    -> gemm_operand_buffer A/B
    -> gemm_input_mem_router
    -> GEMM
    -> scratchpad C
    -> dma_store_engine
    -> destination AXI-MM memory model
    -> result_bridge / scoreboard
```

Direct Stream B1 verifies that A/B operands can be streamed into local GEMM operand buffers instead of scratchpad, while C still writes to scratchpad and is exported through the existing DMA store / S2MM path.

Mode behavior:

```text
gemm_input_stream_mode = 0:
    GEMM A/B reads -> scratchpad
    GEMM C writes  -> scratchpad

gemm_input_stream_mode = 1:
    GEMM A/B reads -> gemm_operand_buffer
    GEMM C writes  -> scratchpad
```

The 2-lane GEMM path has been verified in Direct Stream mode through the 2-lane direct-stream smoke regression subset. The B-cache, packed B-cache, A-row cache, and packed A-row preload paths have also been verified in Direct Stream mode through smoke, load-store stress, and CDC-oriented runs.

---

## CDC-Aware Baseline

The subsystem includes CDC-aware control/status handling between `dma_clk` and `core_clk`.

Current CDC behavior:

- `dma_load_engine` and scratchpad Port0 DMA load/store paths remain in `dma_clk`.
- GEMM compute path remains in `core_clk`.
- AXI-Stream preload source read side starts in `dma_clk`.
- AXI-Stream preload destination write side runs in `core_clk`.
- Direct Stream source read side starts in `dma_clk`.
- Direct Stream operand buffer write side runs in `core_clk`.
- `axis_async_fifo` transfers `{tlast, tdata}` across the DMA/core clock boundary.
- `acc_start` crosses into `core_clk` through a toggle synchronizer.
- GEMM config is latched into core-domain registers at GEMM start.
- `gemm_input_stream_mode` is captured with the GEMM job configuration.
- `acc_done` crosses back from `core_clk` to `dma_clk` through a toggle synchronizer.
- `acc_busy` crosses back from `core_clk` to `dma_clk` through a level synchronizer.

Clock periods are configurable from the run script:

```text
+DMA_CLK_PERIOD_NS=<real>
+CORE_CLK_PERIOD_NS=<real>
```

Default clock periods:

```text
dma_clk  = 10 ns
core_clk = 14 ns
```

---

## Implemented Coverage

Current UVM regression covers:

- smoke tests for fixed, variable-dimension, and configurable-base GEMM cases
- DMA load smoke with scoreboard integration
- DMA load stress regression
- DMA load CDC clock-ratio sanity
- DMA load error and recovery behavior
- DMA store / S2MM smoke with scoreboard integration
- DMA store / S2MM error and recovery behavior
- DMA load + GEMM + DMA store stress regression
- AXI-Stream preload smoke with scoreboard integration
- AXI-Stream preload error and recovery behavior
- AXI-Stream load-store stress regression
- AXI-Stream CDC clock-ratio sanity
- Direct Stream smoke with scoreboard integration
- Direct Stream error and recovery behavior
- Direct Stream load-store stress regression
- Direct Stream CDC clock-ratio sanity
- GEMM performance counter smoke
- GEMM performance profile baseline
- 2-lane GEMM performance counter smoke
- 2-lane GEMM performance profile
- 2-lane Direct Stream compatibility smoke
- back-to-back GEMM jobs
- reset recovery between jobs
- mixed corner recipe
- mid-run reset / expected-abort recovery
- helper fallback sanity checks

Important case groups:

```text
Fixed baseline       : CASE_ID 5
Variable dimension   : CASE_ID 100, 101, 105
Configurable base    : CASE_ID 400, 401, 402, 403
RUN_ALL recipe       : 100 -> 101 -> 105 -> 5 -> 400 -> 401 -> 402 -> 403
Corner recipe        : 5 -> 101 -> 105 -> 403
```

---

## Current Regression Baseline

The current full UVM regression contains 59 items and is passing:

```text
TOTAL : 59
PASS  : 59
FAIL  : 0
```

Covered categories:

- host primary smoke
- DMA load smoke with scoreboard
- DMA load stress
- DMA load CDC clock-ratio sanity
- DMA load error/recovery
- DMA store smoke with scoreboard
- DMA store error/recovery
- DMA load + store stress
- AXI-Stream preload smoke with scoreboard
- AXI-Stream preload error/recovery
- AXI-Stream load-store stress
- AXI-Stream CDC clock-ratio sanity
- Direct Stream smoke with scoreboard
- Direct Stream error/recovery
- Direct Stream load-store stress
- Direct Stream CDC clock-ratio sanity
- GEMM performance counter smoke
- GEMM performance profile
- GEMM 2-lane performance counter smoke
- GEMM 2-lane performance profile
- GEMM 2-lane Direct Stream smoke
- GEMM 2-lane DMA load-store stress
- GEMM 2-lane AXI-Stream load-store stress
- GEMM 2-lane Direct Stream load-store stress
- GEMM 2-lane DMA load-store CDC sanity
- GEMM 2-lane AXI-Stream load-store CDC sanity
- GEMM 2-lane Direct Stream load-store CDC sanity
- GEMM 2-lane B-cache DMA load-store stress
- GEMM 2-lane B-cache AXI-Stream load-store stress
- GEMM 2-lane B-cache Direct Stream load-store stress
- GEMM 2-lane packed B-cache DMA load-store stress
- GEMM 2-lane packed B-cache AXI-Stream load-store stress
- GEMM 2-lane packed B-cache Direct Stream load-store stress
- GEMM 2-lane packed B-cache + A-row-cache DMA load-store stress
- GEMM 2-lane packed B-cache + A-row-cache AXI-Stream load-store stress
- GEMM 2-lane packed B-cache + A-row-cache Direct Stream load-store stress
- GEMM 2-lane packed B-cache + A-row-cache DMA load-store CDC sanity
- GEMM 2-lane packed B-cache + A-row-cache AXI-Stream load-store CDC sanity
- GEMM 2-lane packed B-cache + A-row-cache Direct Stream load-store CDC sanity
- GEMM 2-lane packed B-cache + A-row-cache + packed A-row DMA load-store stress
- GEMM 2-lane packed B-cache + A-row-cache + packed A-row AXI-Stream load-store stress
- GEMM 2-lane packed B-cache + A-row-cache + packed A-row Direct Stream load-store stress
- back-to-back
- reset recovery
- corner recipe
- mid-run reset / abort recovery
- helper fallback sanity

P3 2-lane stress / CDC regression status:

```text
2-lane DMA load-store stress, 10/14            : PASS
2-lane AXI-Stream load-store stress, 10/14     : PASS
2-lane Direct Stream load-store stress, 10/14  : PASS
2-lane DMA load-store CDC, 10/13               : PASS
2-lane AXI-Stream load-store CDC, 10/13        : PASS
2-lane Direct Stream load-store CDC, 10/13     : PASS
```

P4 B-cache regression status:

```text
P4C: B-cache compute bypass / perf profile              : PASS
P4D: B-cache + Direct Stream compatibility              : PASS
P4E: B-cache stress / CDC manual subset                  : PASS
P4F: Representative B-cache tests added to full regression: PASS
Full regression after P4F                                : 47/47 PASS
```


P5 packed B-cache preload regression status:

```text
P5A: packed_operand_read_spec.md                         : PASS
P5B: safe parameter plumbing, default-off 47/47 PASS      : PASS
P5C: packed B-cache preload RTL + baseline 47/47 PASS     : PASS
P5D: focused perf/profile compare                         : PASS
P5E: Direct Stream compatibility                          : PASS
P5F: stress / CDC manual subset                            : PASS
P5G: Representative packed-read tests added to regression  : PASS
Full regression after P5G                                  : 50/50 PASS
```

P6 scalar A-row cache regression status:

```text
P6A: gemm_a_row_cache_spec.md                         : PASS
P6B: safe parameter plumbing                          : PASS
P6C: scalar A-row cache RTL prototype                  : PASS
P6D: focused perf/profile compare                      : PASS
P6E: Direct Stream compatibility                       : PASS
P6F: stress / CDC subset                               : PASS
P6G: representative A-row-cache regression added       : PASS
Full regression after P6G                              : 56/56 PASS
```

P7 packed A-row preload regression status:

```text
P7A: packed_a_row_preload_spec.md                     : PASS
P7B: safe parameter plumbing, default-off              : PASS
P7C: packed A-row preload RTL                          : PASS
P7D: focused perf/profile compare                      : PASS
P7E: Direct Stream compatibility                       : PASS
P7F: stress / CDC manual subset                        : PASS
P7G: representative packed A-row regression added      : PASS
Full regression after P7G                              : 59/59 PASS
```



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

The regression runner checks each generated log for:

```text
UVM_ERROR : 0
UVM_FATAL : 0
```

For GUI-based QuestaSim runs, the flow uses:

```tcl
onfinish stop
```

to avoid `$finish` confirmation popups during regression.

---

## Useful Single-Test Runs

### Performance counter smoke, single-lane baseline

```tcl
set UVM_TEST ai_accel_subsys_perf_counter_smoke_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 100
set RUN_ALL 1
set GEMM_MAC_LANES 1
do run_uvm.tcl
```

### Performance profile, single-lane baseline

```tcl
set UVM_TEST ai_accel_subsys_perf_profile_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 100
set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14
set GEMM_MAC_LANES 1
do run_uvm.tcl
```

### Performance counter smoke, 2-lane

```tcl
set UVM_TEST ai_accel_subsys_perf_counter_smoke_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 100
set RUN_ALL 1
set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14
set GEMM_MAC_LANES 2
do run_uvm.tcl
```

### Performance profile, 2-lane

```tcl
set UVM_TEST ai_accel_subsys_perf_profile_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 100
set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14
set GEMM_MAC_LANES 2
do run_uvm.tcl
```

### Direct Stream smoke RUN_ALL, 2-lane

```tcl
set UVM_TEST ai_accel_subsys_direct_stream_smoke_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 100
set RUN_ALL 1
set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14
set GEMM_MAC_LANES 2
do run_uvm.tcl
```

### DMA load-store stress, 2-lane

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
do run_uvm.tcl
```

### AXI-Stream load-store stress, 2-lane

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
do run_uvm.tcl
```

### Direct Stream load-store stress, 2-lane

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
do run_uvm.tcl
```

### DMA / AXI-Stream / Direct Stream CDC sanity, 2-lane

Use the same stress commands above and switch the core clock to 13ns:

```tcl
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 13
set GEMM_MAC_LANES 2
```


### Performance profile, 2-lane + B-cache

```tcl
set UVM_TEST ai_accel_subsys_perf_profile_test
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
do run_uvm.tcl
```

### Direct Stream smoke RUN_ALL, 2-lane + B-cache

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
do run_uvm.tcl
```

### Representative B-cache load-store stress runs

Use one of the three frontend paths below:

```tcl
# DMA load A/B -> GEMM with B-cache -> DMA store C
set UVM_TEST ai_accel_subsys_dma_load_store_stress_test
set STORE_STRESS_JOB_COUNT 8
set STORE_STRESS_SEED 20260502
set STORE_STRESS_RANDOM 1
set STORE_STRESS_GAP_CYCLES 10
```

```tcl
# AXI-Stream preload A/B -> GEMM with B-cache -> DMA store C
set UVM_TEST ai_accel_subsys_axis_stream_load_store_stress_test
set AXIS_STRESS_JOB_COUNT 8
set AXIS_STRESS_SEED 20260502
set AXIS_STRESS_RANDOM 1
set AXIS_STRESS_GAP_CYCLES 10
```

```tcl
# Direct Stream preload A/B -> GEMM with B-cache -> DMA store C
set UVM_TEST ai_accel_subsys_direct_stream_load_store_stress_test
set DS_STRESS_JOB_COUNT 8
set DS_STRESS_SEED 20260502
set DS_STRESS_RANDOM 1
set DS_STRESS_GAP_CYCLES 10
```

Common B-cache settings for all three:

```tcl
set ENABLE_RESULT_CHECK 1
set FORCE_HELPER_MEM_PATH 0
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 14
set GEMM_MAC_LANES 2
set GEMM_ENABLE_B_CACHE 1
set GEMM_B_CACHE_MAX_K 4
set GEMM_B_CACHE_MAX_N 4
do run_uvm.tcl
```


### Representative packed B-cache preload load-store stress runs

```tcl
# DMA load A/B -> packed B-cache preload -> GEMM -> DMA store C
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

# AXI-Stream preload A/B -> packed B-cache preload -> GEMM -> DMA store C
set UVM_TEST ai_accel_subsys_axis_stream_load_store_stress_test
set AXIS_STRESS_JOB_COUNT 8
set AXIS_STRESS_SEED 20260502
set AXIS_STRESS_RANDOM 1
set AXIS_STRESS_GAP_CYCLES 10
do run_uvm.tcl

# Direct Stream preload A/B -> packed B-cache preload -> GEMM -> DMA store C
set UVM_TEST ai_accel_subsys_direct_stream_load_store_stress_test
set DS_STRESS_JOB_COUNT 8
set DS_STRESS_SEED 20260502
set DS_STRESS_RANDOM 1
set DS_STRESS_GAP_CYCLES 10
do run_uvm.tcl
```

### Representative A-row cache load-store stress runs

```tcl
# DMA load A/B -> packed B-cache + A-row cache -> GEMM -> DMA store C
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
set GEMM_ENABLE_A_ROW_CACHE 1
set GEMM_A_ROW_CACHE_MAX_K 4
do run_uvm.tcl
```

For AXI-Stream or Direct Stream, switch only the test and stress knob group:

```tcl
set UVM_TEST ai_accel_subsys_axis_stream_load_store_stress_test
set AXIS_STRESS_JOB_COUNT 8
set AXIS_STRESS_SEED 20260502
set AXIS_STRESS_RANDOM 1
set AXIS_STRESS_GAP_CYCLES 10
```

```tcl
set UVM_TEST ai_accel_subsys_direct_stream_load_store_stress_test
set DS_STRESS_JOB_COUNT 8
set DS_STRESS_SEED 20260502
set DS_STRESS_RANDOM 1
set DS_STRESS_GAP_CYCLES 10
```

For CDC sanity, switch:

```tcl
set CORE_CLK_PERIOD_NS 13
do run_uvm.tcl
```


### Representative packed A-row preload load-store stress runs

```tcl
# DMA load A/B -> packed B-cache + A-row cache + packed A-row preload -> GEMM -> DMA store C
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
set GEMM_ENABLE_A_ROW_CACHE 1
set GEMM_A_ROW_CACHE_MAX_K 4
set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1
do run_uvm.tcl
```

For AXI-Stream or Direct Stream, switch only the test and stress knob group:

```tcl
set UVM_TEST ai_accel_subsys_axis_stream_load_store_stress_test
set AXIS_STRESS_JOB_COUNT 8
set AXIS_STRESS_SEED 20260502
set AXIS_STRESS_RANDOM 1
set AXIS_STRESS_GAP_CYCLES 10
```

```tcl
set UVM_TEST ai_accel_subsys_direct_stream_load_store_stress_test
set DS_STRESS_JOB_COUNT 8
set DS_STRESS_SEED 20260502
set DS_STRESS_RANDOM 1
set DS_STRESS_GAP_CYCLES 10
```

For CDC sanity, switch:

```tcl
set CORE_CLK_PERIOD_NS 13
do run_uvm.tcl
```

### DMA load RUN_ALL

```tcl
set UVM_TEST ai_accel_subsys_dma_load_smoke_test
set ENABLE_RESULT_CHECK 1
set RUN_ALL 1
do run_uvm.tcl
```

### DMA load stress

```tcl
set UVM_TEST ai_accel_subsys_dma_load_stress_test
set ENABLE_RESULT_CHECK 1
set STRESS_JOB_COUNT 8
set STRESS_SEED 20260502
set STRESS_RANDOM 1
set STRESS_GAP_CYCLES 10
do run_uvm.tcl
```

### DMA store / S2MM RUN_ALL

```tcl
set UVM_TEST ai_accel_subsys_dma_store_smoke_test
set ENABLE_RESULT_CHECK 1
set RUN_ALL 1
do run_uvm.tcl
```

### AXI-Stream preload RUN_ALL

```tcl
set UVM_TEST ai_accel_subsys_axis_stream_preload_smoke_test
set ENABLE_RESULT_CHECK 1
set RUN_ALL 1
do run_uvm.tcl
```

### Direct Stream smoke RUN_ALL

```tcl
set UVM_TEST ai_accel_subsys_direct_stream_smoke_test
set ENABLE_RESULT_CHECK 1
set RUN_ALL 1
do run_uvm.tcl
```

---

## Log Handling

`run_uvm.tcl` generates timestamped logs under `sim/logs/`.

Current log format:

```text
YYYYMMDD_HHMMSS_<test_specific_name>_lanes_<GEMM_MAC_LANES>.log
```

The lane tag makes 1-lane and 2-lane runs easier to distinguish.

The log directory keeps only the newest 50 `.log` files by default. This can be overridden before running a test:

```tcl
set LOG_KEEP_COUNT 100
do run_uvm.tcl
```

---

## Known Warning

Questa may report `vsim-3838` multiple-driver warnings around `bram_axi0_if` request-side signals.

This warning is currently classified as a known simulator/interface warning related to the shared `axi_mm_if` clocking-block driver model and the Port0 owner mux connection style.

Current policy:

```text
Known warning accepted.
Functional regression passes.
No BRAM interface semantic change required.
```

---

## What This Baseline Proves

At this checkpoint, the subsystem verifies:

- scratchpad-backed GEMM execution
- fixed and variable GEMM dimensions
- configurable A/B/C base addresses
- scoreboard-based result checking
- repeated jobs in one simulation
- reset recovery and mid-run abort recovery
- DMA load into scratchpad
- DMA multi-beat load behavior
- DMA source RRESP error recovery
- DMA load stress behavior
- DMA store / S2MM result movement out of scratchpad
- DMA destination memory compare
- DMA destination BRESP error recovery
- repeated full DMA load -> GEMM -> DMA store jobs
- AXI-Stream preload into scratchpad Port1
- AXI-Stream MM2S source read behavior
- AXI-Stream async FIFO CDC behavior
- AXI-Stream source RRESP error recovery
- repeated full AXI-Stream preload -> GEMM -> DMA store jobs
- Direct Stream preload into GEMM operand buffers
- Direct Stream MM2S source read behavior
- Direct Stream async FIFO CDC behavior
- Direct Stream source RRESP error recovery
- Direct Stream operand-buffer GEMM A/B read behavior
- repeated full Direct Stream preload -> GEMM -> DMA store jobs
- CDC-aware GEMM control/status crossing
- alternate `dma_clk` / `core_clk` ratio sanity
- Port0 ownership recovery after DMA load/store errors
- Port1 ownership switching between AXI-Stream preload and GEMM
- transparent scratchpad-mode bypass through `gemm_input_mem_router`
- GEMM performance counters
- single-lane performance profile baseline
- 2-lane K-parallel GEMM datapath correctness
- 2-lane Direct Stream operand-buffer compatibility
- 2-lane DMA / AXI-Stream / Direct Stream stress coverage
- 2-lane DMA / AXI-Stream / Direct Stream CDC sanity
- B-cache preload and compute-bypass correctness for supported K/N tiles
- B-cache compatibility across DMA, AXI-Stream, and Direct Stream load-store paths
- B-cache manual CDC subset stability
- packed B-cache preload correctness for aligned B bases
- packed B-cache compatibility across DMA, AXI-Stream, and Direct Stream load-store paths
- packed B-cache stress / CDC manual subset stability
- scalar A-row cache correctness for supported K dimensions
- A-row cache compatibility across DMA, AXI-Stream, and Direct Stream load-store paths
- A-row cache CDC sanity across DMA, AXI-Stream, and Direct Stream load-store paths
- packed A-row preload correctness for aligned A bases and supported K=4 rows
- packed A-row preload compatibility across DMA, AXI-Stream, and Direct Stream load-store paths
- packed A-row preload stress / CDC manual subset stability
- corrected GEMM done semantics after final C write completion
- unattended full UVM regression flow

---

## Current Milestone Summary

```text
Performance GEMM P7: Packed A-row Preload Optimization Completed

Completed:
  P0: GEMM performance counter smoke                  PASS
  P1: GEMM performance profile baseline               PASS
  P2A: GEMM_MAC_LANES parameter baseline              PASS
  P2B: 2-lane FSM/datapath added                      PASS
  P2C: 2-lane host-primary profile baseline           PASS
  P2D: 2-lane Direct Stream compatibility             PASS
  P2E: 2-lane subset regression                       PASS
  P3A: 2-lane DMA load-store stress                   PASS
  P3B: 2-lane AXI-Stream load-store stress            PASS
  P3C: 2-lane Direct Stream load-store stress         PASS
  P3D: 2-lane CDC sanity                              PASS
  P3E: 2-lane stress / CDC regression subset          PASS
  P4C: B-cache compute bypass / perf profile          PASS
  P4D: B-cache Direct Stream compatibility            PASS
  P4E: B-cache stress / CDC manual subset             PASS
  P4F: B-cache representative regression added        PASS
  P5A: packed operand read spec                       PASS
  P5B: safe parameter plumbing                        PASS
  P5C: packed B-cache preload RTL                     PASS
  P5D: focused perf/profile compare                   PASS
  P5E: Direct Stream compatibility                    PASS
  P5F: packed B-cache stress / CDC manual subset      PASS
  P5G: packed B-cache representative regression added PASS
  P6A: A-row cache spec                               PASS
  P6B: safe parameter plumbing                        PASS
  P6C: scalar A-row cache RTL                         PASS
  P6D: focused perf/profile compare                   PASS
  P6E: Direct Stream compatibility                    PASS
  P6F: A-row cache stress / CDC subset                PASS
  P6G: A-row cache representative regression added    PASS
  P7A: packed A-row preload spec                       PASS
  P7B: safe parameter plumbing                         PASS
  P7C: packed A-row preload RTL                        PASS
  P7D: focused perf/profile compare                    PASS
  P7E: Direct Stream compatibility                     PASS
  P7F: packed A-row stress / CDC manual subset         PASS
  P7G: packed A-row representative regression added    PASS

Regression:
  59/59 PASS

Next:
  P8 candidate: 4-lane MAC feasibility study / larger GEMM / tile-based scheduling
```

---

## Summary

This repository currently contains a working GEMM-oriented AI accelerator subsystem with:

- stable scratchpad-backed RTL integration
- host-primary memory path verification
- DMA load path verification
- DMA store / S2MM result path verification
- full DMA load + GEMM + DMA store stress verification
- AXI-Stream preload path verification
- AXI-Stream frontend CDC verification
- full AXI-Stream preload + GEMM + DMA store stress verification
- Direct Stream GEMM frontend B1 verification
- Direct Stream frontend CDC verification
- full Direct Stream preload + GEMM + DMA store stress verification
- CDC-aware GEMM control/status handling
- DMA, AXI-Stream, and Direct Stream stress and error/recovery coverage
- scoreboard-based result checking
- reset and abort recovery tests
- configurable clock-ratio regression coverage
- GEMM performance counter and profile baseline
- parameterized 1-lane / 2-lane GEMM compute path
- B-cache operand reuse optimization for supported tiles
- corrected GEMM done semantics after final C write completion
- focused 2-lane smoke/profile regression subset
- 2-lane stress / CDC hardening regression subset
- representative 2-lane + B-cache full-regression subset
- packed B-cache preload optimization
- representative 2-lane + packed B-cache full-regression subset
- scalar A-row cache optimization
- representative 2-lane + packed B-cache + A-row-cache stress / CDC full-regression subset
- packed A-row preload optimization
- representative 2-lane + packed B-cache + A-row-cache + packed A-row full-regression subset
- full UVM regression automation

This is the current subsystem verification and P7 performance-GEMM baseline. The next planned optimization milestone should be selected from larger GEMM dimensions, 4-lane MAC feasibility, or tile-based scheduling.
