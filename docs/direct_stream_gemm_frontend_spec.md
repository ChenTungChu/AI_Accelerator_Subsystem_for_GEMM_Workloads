# Direct Stream GEMM Frontend Integration Spec

## 1. Purpose

This document defines the implemented **Direct Stream GEMM Frontend B1** architecture for the AI Accelerator Subsystem.

The previous completed AXI-Stream Option A path is:

```text
AXI-MM source memory
    -> axi_mm2s_dma
    -> axis_async_fifo
    -> axi_stream_loader
    -> axis_scratchpad_write_adapter
    -> scratchpad A/B preload through Port1
    -> existing GEMM
    -> scratchpad C
    -> dma_store_engine
    -> destination memory compare / scoreboard
```

The completed Direct Stream B1 path is:

```text
AXI-MM source memory
    -> AXI MM2S DMA
    -> AXI-Stream CDC boundary
    -> direct_stream_preload_engine
    -> gemm_operand_buffer_write_adapter
    -> gemm_operand_buffer A/B
    -> gemm_input_mem_router
    -> existing GEMM compute
    -> scratchpad C
    -> DMA store / S2MM
    -> destination memory compare / scoreboard
```

The goal of B1 is to move A/B input feeding away from scratchpad preload and toward a stream-backed local operand-buffer frontend, while preserving the existing GEMM compute behavior and the existing C output path.

Historical full regression baseline after Direct Stream B1 completion:

```text
TOTAL : 33
PASS  : 33
FAIL  : 0
```


Current project status after P13 C RMW accumulation closure:

```text
Performance GEMM P13: C Read-Modify-Write Partial Accumulation Completed
Full regression: 82/82 PASS
```

Direct Stream B1 remains compatible with:

```text
GEMM_MAC_LANES=1 baseline
GEMM_MAC_LANES=2 2-lane MAC datapath
GEMM_MAC_LANES=2 + GEMM_ENABLE_B_CACHE=1 B-cache datapath
GEMM_MAC_LANES=2 + GEMM_ENABLE_B_CACHE=1 + GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1 packed B-cache preload datapath
GEMM_MAC_LANES=2 + GEMM_ENABLE_B_CACHE=1 + GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1 + GEMM_ENABLE_A_ROW_CACHE=1 scalar A-row cache datapath
GEMM_MAC_LANES=2 + packed B-cache + A-row cache + packed A-row preload datapath
GEMM_MAC_LANES=4 + cache-backed full-cache datapath
GEMM_MAC_LANES=4 + scaled cache8 larger-dimension datapath
GEMM_MAC_LANES=4 + K-dimension tiling datapath, CASE_ID=195
GEMM_MAC_LANES=4 + N-dimension tiling datapath, CASE_ID=200
GEMM_MAC_LANES=4 + M-dimension tiling datapath, CASE_ID=207
GEMM_MAC_LANES=4 + C RMW accumulation datapath, CASE_ID=211
```


---

## 2. Terminology

### 2.1 Option A: AXI-Stream Preload into Scratchpad

Already completed.

```text
AXI Stream
    -> scratchpad A/B
    -> GEMM reads A/B from scratchpad
```

This path proves:

- MM2S source reads
- AXI-Stream valid/ready protocol
- AXI-Stream CDC through async FIFO
- stream loader behavior
- scratchpad Port1 ownership switching
- GEMM + DMA store end-to-end behavior
- error/recovery behavior
- stress behavior
- CDC clock-ratio sanity

### 2.2 Option B: Direct Stream GEMM Frontend

Implemented as B1.

```text
AXI Stream
    -> operand buffer A/B
    -> GEMM reads A/B from operand buffer
```

In this first direct-stream milestone, C remains scratchpad-backed:

```text
GEMM C writes
    -> scratchpad C
    -> DMA store C
    -> destination memory compare

P13 C RMW old-C reads
    -> scratchpad C
    -> GEMM accumulation writeback
```

### 2.3 B1: Stream-Backed Operand Buffer

B1 means:

```text
AXI stream fills local operand buffers for A and B.
Existing GEMM then reads A/B from those local operand buffers.
C still reads and writes through scratchpad when needed by the GEMM datapath.
```

This is not yet a fully cycle-by-cycle streaming systolic frontend. It is the safest first step because it removes A/B scratchpad dependency without rewriting the whole GEMM compute datapath.

---

## 3. Design Goals

The Direct Stream B1 frontend must:

1. Preserve the existing scratchpad, DMA, and AXI-Stream baseline.
2. Keep the existing GEMM compute core mostly unchanged.
3. Avoid using scratchpad for A/B in direct-stream mode.
4. Continue using scratchpad for C output in B1.
5. Reuse the proven MM2S and AXI-Stream CDC infrastructure.
6. Reuse the existing DMA store / S2MM result path.
7. Support fixed, variable-dimension, and configurable-base cases.
8. Support scoreboard result compare and ctrl/result pairing.
9. Support error/recovery tests.
10. Support stress and CDC clock-ratio sanity tests.
11. Allow direct-stream mode and scratchpad mode to coexist.
12. Preserve AXI-Stream Option A scratchpad preload behavior.

Current status: all goals above are implemented and covered by regression.

---

## 4. Non-Goals for B1

B1 does **not** attempt to:

- stream operands directly into MAC lanes every cycle
- tile a large matrix across many stream packets
- stream C directly to S2MM
- remove the scratchpad entirely
- change the GEMM arithmetic datapath
- introduce an in-stream packet header
- introduce multi-outstanding MM2S transactions
- support simultaneous stream preload and GEMM compute
- support simultaneous A and B stream channels
- add a new packet format specifically for K-tiling
- add a new packet format specifically for N-tiling
- stream K/N tiles directly into MAC lanes without local buffering

Those are future milestones.

P10 K-dimension tiling, P11 N-dimension tiling, and P12 M-dimension tiling are implemented inside the GEMM compute microarchitecture. Direct Stream B1 remains a preload-then-compute frontend: it loads compact A/B payloads into the operand buffer, then the GEMM core performs K/N tiling through the existing local-memory-like read interface.

---

## 5. Implemented Architecture

### 5.1 High-Level Architecture

```text
                                  dma_clk
┌────────────────────────────────────────────────────────────────┐
│                                                                │
│  AXI source memory model / external source                     │
│           │                                                    │
│           ▼                                                    │
│  axi_mm2s_dma                                                  │
│     - AXI-MM read master                                       │
│     - AXI-Stream producer                                      │
│           │                                                    │
│           ▼                                                    │
│  axis_async_fifo write side                                    │
│                                                                │
└───────────────────────────────┬────────────────────────────────┘
                                │
                                │ CDC
                                ▼
┌────────────────────────────────────────────────────────────────┐
│                                  core_clk                      │
│                                                                │
│  axis_async_fifo read side                                     │
│           │                                                    │
│           ▼                                                    │
│  axi_stream_loader                                             │
│     - AXI-Stream consumer                                      │
│     - linear write-request producer                            │
│           │                                                    │
│           ▼                                                    │
│  gemm_operand_buffer_write_adapter                             │
│     - writes stream payload into operand buffer A/B             │
│           │                                                    │
│           ▼                                                    │
│  gemm_operand_buffer                                           │
│     - stores streamed A/B bytes                                │
│     - serves GEMM A/B reads                                    │
│           │                                                    │
│           ▼                                                    │
│  gemm_input_mem_router                                         │
│     - A/B reads from operand buffer in direct-stream mode       │
│     - C RMW reads and C writes to scratchpad adapter            │
│     - transparent scratchpad bypass in scratchpad mode                  │
│                                                                │
│  existing GEMM compute                                         │
│           │                                                    │
│           ▼                                                    │
│  C writes through existing gemm_scratchpad_adapter              │
│           │                                                    │
│           ▼                                                    │
│  scratchpad C -> dma_store_engine                              │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

### 5.2 Key Concept

The existing GEMM still sees a local-memory-like interface:

```systemverilog
mem_req_ready
mem_rd_en
mem_rd_addr
mem_rd_data
mem_rd_valid
mem_wr_en
mem_wr_addr
mem_wr_data
mem_wr_strb
```

A new router sits between GEMM and the memory backends.

In scratchpad mode:

```text
GEMM A/B reads -> scratchpad
GEMM C writes  -> scratchpad
```

In direct-stream mode:

```text
GEMM A/B reads        -> operand buffer
GEMM C RMW old-C read -> scratchpad
GEMM C writes         -> scratchpad
```

The router is intentionally transparent in scratchpad mode. This preserves the existing host, DMA load/store, and AXI-Stream scratchpad-preload regression baseline.

---

## 6. Mode Model

### 6.1 GEMM Input Mode

Implemented mode signal:

```systemverilog
logic gemm_input_stream_mode;
```

Mode behavior:

```text
0 = scratchpad-backed mode
1 = direct-stream operand-buffer mode
```

### 6.2 Scratchpad Mode

This is the existing baseline behavior.

```text
DMA load, AXI-Stream preload, or host preload A/B into scratchpad
GEMM reads A/B from scratchpad
GEMM writes C to scratchpad
Host readback or DMA store exports C
```

This mode preserves the existing baseline and remains covered by full regression.

### 6.3 Direct-Stream Mode

New B1 behavior:

```text
direct stream preload A into operand buffer
direct stream preload B into operand buffer
GEMM reads A/B from operand buffer
GEMM reads old C from scratchpad when C RMW is enabled
GEMM writes C to scratchpad
DMA store exports C
```

### 6.4 Mode Coexistence Rule

The mode is selected per GEMM job.

The testbench/software must not change `gemm_input_stream_mode` while:

```text
ds_load_busy == 1
acc_busy == 1
dma_store_busy == 1
```

Implemented policy:

- testbench follows correct sequencing
- RTL captures `gemm_input_stream_mode` with the GEMM job configuration
- scratchpad mode and direct-stream mode can coexist across different jobs

---

## 7. Dataflow

### 7.1 Direct-Stream A/B Preload Sequence

```text
1. Clear scratchpad C.
2. Clear destination memory.
3. Preload source memory with A/B payloads.
4. Direct-stream preload A into operand buffer A.
5. Direct-stream preload B into operand buffer B.
6. Set gemm_input_stream_mode = 1.
7. Start GEMM.
8. GEMM reads A/B from operand buffer.
9. GEMM writes C into scratchpad.
10. DMA store C to destination memory.
11. Compare destination memory.
12. Publish scoreboard result.
```

### 7.2 A Preload

```text
ds_load_start
ds_src_base_addr = source address of A payload
ds_dst_base_addr = base_addr_a
ds_load_beats    = ceil(A_bytes / BYTES_PER_BEAT)
ds_operand_sel   = OPERAND_A
```

### 7.3 B Preload

```text
ds_load_start
ds_src_base_addr = source address of B payload
ds_dst_base_addr = base_addr_b
ds_load_beats    = ceil(B_bytes / BYTES_PER_BEAT)
ds_operand_sel   = OPERAND_B
```

### 7.4 GEMM and Store

After both direct-stream operand loads complete:

```text
gemm_input_stream_mode = 1
acc_start
wait acc_done
gemm_input_stream_mode = 0, for cleanup / next non-stream job
dma_store_start
wait dma_store_done
compare destination memory
publish scoreboard result
```

---

## 8. Packet Format

### 8.1 B1 Packet Format

B1 keeps the same headerless AXI-Stream packet model as Option A:

```text
beat 0      : payload data
beat 1      : payload data
...
beat N - 1  : payload data with TLAST = 1
```

Metadata remains out-of-band through the control interface.

### 8.2 Metadata

The following metadata is provided through control/config signals:

```text
ds_src_base_addr
ds_dst_base_addr
ds_load_beats
ds_operand_sel
base_addr_a
base_addr_b
base_addr_c
dim_m
dim_n
dim_k
gemm_input_stream_mode
```

### 8.3 Future Header Option

A future version may add a stream header:

```text
word 0: packet_type
word 1: operand_type
word 2: logical_base_addr
word 3: byte_count
word 4: flags
```

This is not required for B1.

---

## 9. Operand Buffer Address Model

### 9.1 Goal

The operand buffer allows GEMM to keep using its existing address-generation behavior.

Operand-buffer reads are selected by address range.

### 9.2 Address Matching

In direct-stream mode, the memory router checks GEMM read addresses.

Implemented rule:

```text
if mem_rd_addr starts within A region:
    serve from operand_buffer A

else if mem_rd_addr starts within B region:
    serve from operand_buffer B

else:
    return synthetic zero read and flag router error
```

In scratchpad mode, all GEMM reads and writes pass transparently to `gemm_scratchpad_adapter`.

### 9.3 Region Definitions

A region:

```text
base_addr_a <= addr < base_addr_a + A_region_bytes
```

B region:

```text
base_addr_b <= addr < base_addr_b + B_region_bytes
```

Where:

```text
A_region_bytes = ceil(A_bytes / BYTES_PER_BEAT) * BYTES_PER_BEAT
B_region_bytes = ceil(B_bytes / BYTES_PER_BEAT) * BYTES_PER_BEAT
```

The rounded region size accounts for final-beat padding.

### 9.4 Start-Address Decode Policy

The router uses the read **start address** for A/B region classification, not the full 32-bit read window.

Reason:

```text
GEMM operand reads are byte-addressed int8 element reads.
The 32-bit read data is only the local-memory container.
The active operand is selected by the requested byte address.
```

This is required for cases where a valid int8 element is near the end of an operand region, such as A offset 7 in an 8-byte A matrix.

### 9.5 Local Offset Calculation

For A:

```text
a_offset = mem_rd_addr - base_addr_a
```

For B:

```text
b_offset = mem_rd_addr - base_addr_b
```

The operand buffer uses local offsets internally.

---

## 10. Beat Count and Padding Policy

### 10.1 Transfer Unit

B1 remains beat-count based:

```text
ds_load_beats = ceil(matrix_bytes / BYTES_PER_BEAT)
```

Where:

```text
BYTES_PER_BEAT = DATA_WIDTH / 8
```

For the current 64-bit stream width:

```text
BYTES_PER_BEAT = 8
```

### 10.2 Padding

A and B matrix payloads remain compact row-major int8 arrays.

If a matrix payload does not fill the final beat, unused bytes are stored as part of the padded operand region but ignored by GEMM.

GEMM uses only the configured M/N/K footprint.

### 10.3 WSTRB Policy

The existing `axi_stream_loader` emits full write strobes.

For B1 this is acceptable because:

- A and B operand buffers are logically separate
- padded bytes are outside the active matrix footprint
- GEMM only reads valid configured matrix addresses

Future enhancement:

```text
Add byte_count and final-beat WSTRB support.
```

---

## 11. Implemented RTL Blocks

### 11.1 direct_stream_preload_engine

File:

```text
rtl/subsystem/direct_stream_preload_engine.sv
```

Role:

```text
integrates:
    axi_mm2s_dma
    axis_async_fifo
    axi_stream_loader
    gemm_operand_buffer_write_adapter
    control/status CDC
```

Primary interface:

```text
dma_clk / dma_rst_n
core_clk / core_rst_n

ds_load_start
ds_src_base_addr
ds_dst_base_addr
ds_load_beats
ds_operand_sel
ds_load_busy
ds_load_done
ds_load_error

source AXI-MM read master port
operand buffer write port
debug status
```

Implementation note:

This block is derived from the existing `axis_preload_engine` architecture, but the scratchpad write adapter is replaced with an operand-buffer write adapter.

### 11.2 gemm_operand_buffer

File:

```text
rtl/subsystem/gemm_operand_buffer.sv
```

Role:

```text
stores streamed A/B operands
serves GEMM A/B reads in direct-stream mode
```

Write side, core_clk domain:

```systemverilog
wr_valid
wr_ready
wr_operand_sel
wr_addr
wr_data
wr_strb
wr_last
```

Read side, core_clk domain:

```systemverilog
rd_valid
rd_ready
rd_operand_sel
rd_addr
rd_data
rd_data_valid
```

Status/debug:

```systemverilog
a_loaded
b_loaded
a_written_beats
b_written_beats
read_count
write_error_pulse
read_error_pulse
error
```

B1 uses a local byte-addressed buffer model for A and B.

### 11.3 gemm_operand_buffer_write_adapter

File:

```text
rtl/subsystem/gemm_operand_buffer_write_adapter.sv
```

Role:

```text
axi_stream_loader wr_* output
    -> gemm_operand_buffer write port
```

Input:

```systemverilog
wr_valid
wr_ready
wr_addr
wr_data
wr_strb
wr_last
```

Output:

```systemverilog
buf_wr_valid
buf_wr_ready
buf_wr_operand_sel
buf_wr_addr
buf_wr_data
buf_wr_strb
buf_wr_last
```

Behavior:

- converts stream-loader logical writes into operand-buffer local writes
- computes `buf_wr_addr = wr_addr - operand_base_addr`
- checks address alignment and underflow
- tracks accepted/forwarded/dropped writes
- reports sticky error

This is much simpler than the scratchpad write adapter because there is no AXI B response.

### 11.4 gemm_input_mem_router

File:

```text
rtl/subsystem/gemm_input_mem_router.sv
```

Role:

```text
routes GEMM local memory requests to:
    operand buffer for A/B reads in direct-stream mode
    scratchpad adapter for C RMW reads, C writes, and scratchpad-mode reads
```

Backend 0:

```text
operand buffer read port
```

Backend 1:

```text
existing gemm_scratchpad_adapter local memory interface
```

Behavior in scratchpad mode:

```text
all GEMM reads and writes route transparently to gemm_scratchpad_adapter
```

Behavior in direct-stream mode:

```text
A/B reads route to operand buffer
C writes route to gemm_scratchpad_adapter
non-A/B reads route to scratchpad; this supports P13 C RMW old-C reads
```

### 11.5 Direct Stream Status

Implemented status signals include:

```systemverilog
ds_load_busy
ds_load_done
ds_load_error
ds_a_loaded
ds_b_loaded
gemm_router_error
ds_operand_buffer_error
ds_loader_accepted_beats
ds_loader_written_beats
ds_adapter_accepted_writes
ds_adapter_forwarded_writes
ds_adapter_dropped_writes
```

Some debug/status signals are internal to `ai_accel_subsys.sv` and are not exposed through `ctrl_if` unless required by tests.

---

## 12. Top-Level Integration

### 12.1 Direct Stream Source AXI Port

The direct-stream preload path uses a dedicated source AXI-MM read interface:

```text
ds_src_axi_ar*
ds_src_axi_r*
```

Reason:

- isolates Option A and Option B traffic
- keeps debug waveforms clear
- avoids sharing one source responder between two frontend modes
- allows independent RRESP error injection

### 12.2 Control Fields

Added to `ai_accel_subsys_ctrl_if`:

```systemverilog
logic                  gemm_input_stream_mode;

logic                  ds_load_start;
logic [ADDR_WIDTH-1:0] ds_src_base_addr;
logic [ADDR_WIDTH-1:0] ds_dst_base_addr;
logic [31:0]           ds_load_beats;
logic                  ds_operand_sel;   // 0=A, 1=B

logic                  ds_load_busy;
logic                  ds_load_done;
logic                  ds_load_error;
```

Added Direct Stream source RRESP injection control:

```systemverilog
logic      ds_src_inject_rresp_error;
int signed ds_src_inject_rresp_error_beat;

task automatic ds_src_set_rresp_error(
    input bit        enable,
    input int signed beat_index
);
```

### 12.3 GEMM Start Gating

Implemented minimum gating:

```text
acc_start accepted only when:
    axis_load_busy == 0
    ds_load_busy   == 0
```

Testbench sequencing guarantees that direct-stream A/B preloads complete before GEMM start.

Future enhancement:

```text
Add explicit RTL start rejection/error if direct-stream mode starts before A/B loaded.
```

### 12.4 GEMM Adapter Integration

Old path:

```text
gemm_top
    -> gemm_scratchpad_adapter
    -> scratchpad Port1
```

New path:

```text
gemm_top
    -> gemm_input_mem_router
        -> operand buffer for A/B reads in direct-stream mode
        -> gemm_scratchpad_adapter for C writes and scratchpad mode
    -> scratchpad Port1
```

### 12.5 Port1 Ownership

In direct-stream mode, A/B do not write scratchpad.

Therefore, `scratchpad_port1_owner_mux` is not used for direct-stream A/B preload.

Port1 is still used by GEMM C writes through `gemm_scratchpad_adapter`.

The existing AXI-Stream preload Option A path still uses `scratchpad_port1_owner_mux`.

---

## 13. Error Handling

### 13.1 Direct Stream Load Errors

`ds_load_error` is covered for:

- zero `ds_load_beats`
- unaligned source address
- unaligned destination/logical operand address
- AXI source `RRESP` error
- invalid `ds_operand_sel` X-state check

Expected future coverage candidates:

- unexpected `RID`
- missing or invalid `RLAST`
- early `TLAST`
- missing `TLAST`
- operand buffer write overflow
- start while busy

### 13.2 Operand Buffer Read Errors

Router or operand buffer can flag error for:

- GEMM read from A before A is loaded
- GEMM read from B before B is loaded
- GEMM read outside valid A/B range in direct-stream mode
- GEMM read beyond allocated operand buffer depth
- illegal mode change during GEMM active

Current direct-stream tests use legal GEMM sequencing and do not intentionally trigger read-side operand-buffer errors yet.

### 13.3 Recovery Policy

After a direct-stream preload error:

```text
ds_load_error = 1 on completion
system returns to idle
next valid direct-stream load can proceed
valid direct-stream A/B preload + GEMM + DMA store recovers
```

Implemented recovery test sequence:

```text
zero beats error
unaligned source error
unaligned destination error
invalid operand select error
source RRESP error
valid direct-stream A/B preload
GEMM
DMA store
destination compare
scoreboard pass
```

---

## 14. Verification Plan and Implemented Tests

### 14.1 Subsystem Smoke Test

Implemented test:

```text
ai_accel_subsys_direct_stream_smoke_test
```

Flow:

```text
1. clear scratchpad C
2. clear destination memory
3. preload source memory with A/B payloads
4. direct-stream preload A into operand buffer
5. direct-stream preload B into operand buffer
6. set gemm_input_stream_mode = 1
7. start GEMM
8. wait acc_done
9. DMA store C to destination memory
10. compare destination memory
11. publish result to scoreboard
```

Passing coverage:

```text
CASE_ID=100
CASE_ID=101
CASE_ID=105
CASE_ID=5
CASE_ID=400
CASE_ID=401
CASE_ID=402
CASE_ID=403
```

### 14.2 Subsystem Error Test

Implemented test:

```text
ai_accel_subsys_direct_stream_error_test
```

Covered:

- zero `ds_load_beats`
- unaligned source address
- unaligned logical destination address
- source AXI RRESP error
- invalid operand select X-state
- valid direct-stream recovery after errors
- valid GEMM + DMA store recovery after errors

Future error coverage candidate:

- GEMM start before A/B loaded

### 14.3 Subsystem Stress Test

Implemented test:

```text
ai_accel_subsys_direct_stream_load_store_stress_test
```

Flow per job:

```text
direct-stream preload A
direct-stream preload B
GEMM
DMA store C
destination memory compare
scoreboard publish
```

Implemented knobs:

```text
DS_STRESS_JOB_COUNT
DS_STRESS_SEED
DS_STRESS_RANDOM
DS_STRESS_GAP_CYCLES
```

Full-regression version:

```text
8 jobs
```

Manual/nightly target:

```text
20 jobs
```

### 14.4 CDC Sanity

Implemented clock-ratio sanity:

```text
DMA_CLK_PERIOD_NS  = 10
CORE_CLK_PERIOD_NS = 13
```

Coverage:

- MM2S source side runs in dma_clk
- stream data crosses async FIFO
- operand buffer write side runs in core_clk
- direct-stream load done/error returns to dma_clk
- GEMM starts only after A/B are loaded by test sequencing
- DMA store path remains valid after direct-stream GEMM completion

---

## 15. Regression Plan and Completion Status

Baseline before Direct Stream GEMM Frontend:

```text
TOTAL : 29
PASS  : 29
FAIL  : 0
```

Completed staged additions:

### Stage B1-A: Direct-stream smoke

```text
+1 item
Full regression: 30 / 30 PASS
```

### Stage B1-B: Direct-stream error/recovery

```text
+1 item
Full regression: 31 / 31 PASS
```

### Stage B1-C: Direct-stream load-store stress

```text
+1 item
Full regression: 32 / 32 PASS
```

### Stage B1-D: Direct-stream CDC clock-ratio sanity

```text
+1 item
Full regression: 33 / 33 PASS
```

Historical final B1 regression baseline:

```text
TOTAL : 33
PASS  : 33
FAIL  : 0
```

Current subsystem regression baseline after P13 closure:

```text
TOTAL : 82
PASS  : 82
FAIL  : 0
```

P10 adds a Direct Stream representative K-tiling regression item:

```text
gemm_4lane_ktiling_direct_stream_load_store_case195
```

This item validates Direct Stream operand preload, GEMM K-tiling execution, scratchpad C writeback, DMA store, and scoreboard compare for:

```text
CASE_ID=195 : M=4, N=4, K=16, K_TILE_SIZE=8
```

---

## 16. Acceptance Criteria

The Direct Stream GEMM Frontend B1 milestone is complete because:

1. Existing 29/29 regression remains passing.
2. Direct-stream A/B preload does not write A/B into scratchpad.
3. Direct-stream A/B preload fills operand buffer correctly.
4. GEMM can read A/B from operand buffer in direct-stream mode.
5. GEMM can still write C into scratchpad.
6. DMA store can export C to destination memory.
7. Destination memory compare passes.
8. Scoreboard result compare passes.
9. Ctrl/result pairing passes.
10. Direct-stream error/recovery tests pass.
11. Direct-stream stress test passes.
12. Direct-stream CDC clock-ratio sanity passes.
13. Scratchpad mode remains compatible with existing tests.
14. AXI-Stream preload Option A remains compatible with existing tests.
15. No BRAM interface semantic change is required.
16. Direct Stream remains compatible with P10 K-dimension tiling through the existing operand-buffer and memory-router interface.
17. P10 Direct Stream representative regression passes with `CASE_ID=195`, `GEMM_ENABLE_K_TILING=1`, and `GEMM_K_TILE_SIZE=8`.
18. P11 Direct Stream representative regression passes with `CASE_ID=200`, K/N tiling enabled.
19. P12 Direct Stream representative regression passes with `CASE_ID=207`, K/N/M tiling enabled.
20. P13 Direct Stream C RMW representative regression passes with `CASE_ID=211`, K/N/M tiling and C RMW enabled.

---

## 17. Implementation Sequence Completed

Completed RTL and UVM integration sequence:

```text
1. Added gemm_operand_buffer.sv.
2. Added gemm_operand_buffer_write_adapter.sv.
3. Added direct_stream_preload_engine.sv.
4. Added gemm_input_mem_router.sv.
5. Integrated gemm_input_mem_router into ai_accel_subsys.sv.
6. Integrated direct_stream_preload_engine into ai_accel_subsys.sv.
7. Extended ai_accel_subsys_ctrl_if.sv with direct-stream control/status.
8. Extended ai_accel_subsys_uvm_top.sv with ds_src_axi responder.
9. Added ai_accel_subsys_direct_stream_smoke_test.sv.
10. Added ai_accel_subsys_direct_stream_error_test.sv.
11. Added ai_accel_subsys_direct_stream_load_store_stress_test.sv.
12. Added direct-stream CDC clock-ratio regression item.
```

Historical Direct Stream B1 milestone:

```text
v3.4.3 Direct Stream GEMM Frontend B1 Completed
Regression: 33/33 PASS
```

Current subsystem milestone after P13:

```text
Performance GEMM P13: C Read-Modify-Write Partial Accumulation Completed
Regression: 82/82 PASS
```

---


---

## 17A. P4 B-Cache Compatibility

Direct Stream B1 was validated with the P4 B-cache GEMM datapath.

Configuration:

```text
GEMM_MAC_LANES=2
GEMM_ENABLE_B_CACHE=1
GEMM_B_CACHE_MAX_K=4
GEMM_B_CACHE_MAX_N=4
```

In Direct Stream mode with B-cache enabled:

```text
Direct Stream preload A -> gemm_operand_buffer A
Direct Stream preload B -> gemm_operand_buffer B
B-cache preload reads B through gemm_input_mem_router
GEMM compute reads A through gemm_input_mem_router
GEMM compute reads B from local b_cache
GEMM writes C to scratchpad
DMA store exports C
scoreboard compares result
```

P4D initially exposed a useful completion-semantics issue: Direct Stream can start DMA store immediately after `acc_done`, so `gemm_top.done` must not assert until the final C write is complete.

The corrected completion contract is:

```text
acc_done / gemm_top.done means final C write completion has occurred
```

P4 Direct Stream validation completed:

```text
Direct Stream smoke RUN_ALL + B-cache                 PASS
Direct Stream load-store stress + B-cache, 10/14      PASS
Direct Stream load-store stress + B-cache, 10/13 CDC  PASS
Representative full-regression B-cache Direct Stream  PASS
```

Full regression after P4:

```text
47/47 PASS
```


## 17B. P5 Packed B-Cache Preload Compatibility

Direct Stream B1 was also validated with the P5 packed B-cache preload datapath.

The important compatibility point is that Direct Stream operand-buffer reads already return packed byte lanes through `op_rd_data[31:0]`, while scratchpad mode needed the adapter update to return a 32-bit byte window. The router continues to pass through whichever source is selected by `gemm_input_mode`.

Validated P5 Direct Stream configuration:

```text
GEMM_MAC_LANES=2
GEMM_ENABLE_B_CACHE=1
GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1
FORCE_HELPER_MEM_PATH=0
```

P5 Direct Stream validation completed:

```text
Direct Stream smoke RUN_ALL + packed B-cache              PASS
Direct Stream load-store stress + packed B-cache          PASS
Direct Stream load-store stress CDC + packed B-cache      PASS
Full regression representative Direct Stream packed item  PASS
```

Historical full regression after P5:

```text
50/50 PASS
```



## 17C. P6 A-Row Cache Compatibility

Direct Stream B1 was also validated with the P6 scalar A-row cache datapath.

Validated P6 Direct Stream configuration:

```text
GEMM_MAC_LANES=2
GEMM_ENABLE_B_CACHE=1
GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1
GEMM_ENABLE_A_ROW_CACHE=1
GEMM_A_ROW_CACHE_MAX_K=4
FORCE_HELPER_MEM_PATH=0
```

In Direct Stream mode with A-row cache enabled:

```text
Direct Stream preload A -> gemm_operand_buffer A
Direct Stream preload B -> gemm_operand_buffer B
B-cache / packed B-cache preload reads B through gemm_input_mem_router
A-row preload reads A through gemm_input_mem_router
GEMM compute reads A from local a_row_cache
GEMM compute reads B from local b_cache
GEMM writes C to scratchpad
DMA store exports C
scoreboard compares result
```

The key compatibility point is that P6 uses the same scalar GEMM local-read interface for A-row preload. Therefore, Direct Stream does not need a new packet format, new operand-buffer protocol, or new stream header.

P6 Direct Stream validation completed:

```text
Direct Stream smoke RUN_ALL + A-row cache                 PASS
Direct Stream load-store stress + A-row cache, 10/14      PASS
Direct Stream load-store stress + A-row cache, 10/13 CDC  PASS
Representative full-regression A-row Direct Stream items  PASS
```

Current full regression after P6:

```text
56/56 PASS
```


## 17D. P7 Packed A-Row Preload Compatibility

Direct Stream B1 was validated with the P7 packed A-row preload datapath.

Validated P7 Direct Stream configuration:

```text
GEMM_MAC_LANES=2
GEMM_ENABLE_B_CACHE=1
GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1
GEMM_ENABLE_A_ROW_CACHE=1
GEMM_A_ROW_CACHE_MAX_K=4
GEMM_ENABLE_PACKED_A_ROW_PRELOAD=1
FORCE_HELPER_MEM_PATH=0
```

In Direct Stream mode, packed A-row preload reads A operands through `gemm_input_mem_router`, which routes those A reads to the operand buffer. No new Direct Stream packet format or operand-buffer protocol is required.

P7 Direct Stream validation completed:

```text
Direct Stream load-store stress + packed A-row preload PASS
Representative full-regression packed A-row item       PASS
```

Historical full regression after P7:

```text
59/59 PASS
```


## 17E. P8 Cache-Backed 4-Lane Compatibility

Direct Stream B1 was validated with the P8 cache-backed true 4-lane MAC datapath.

Validated P8 Direct Stream configuration:

```text
GEMM_MAC_LANES=4
GEMM_ENABLE_B_CACHE=1
GEMM_B_CACHE_MAX_K=4
GEMM_B_CACHE_MAX_N=4
GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1
GEMM_ENABLE_A_ROW_CACHE=1
GEMM_A_ROW_CACHE_MAX_K=4
GEMM_ENABLE_PACKED_A_ROW_PRELOAD=1
FORCE_HELPER_MEM_PATH=0
```

The Direct Stream frontend still performs preload-then-compute. The 4-lane GEMM core obtains A and B operands through the same local-memory-like interface, so the frontend does not need to understand lane grouping.

P8 Direct Stream validation completed:

```text
Direct Stream load-store stress + 4-lane full-cache PASS
Representative full-regression 4-lane item          PASS
```

Historical full regression after P8:

```text
62/62 PASS
```


## 17F. P9 Scaled-Cache Compatibility

Direct Stream B1 was validated with the P9 scaled cache8 larger-dimension datapath.

Validated P9 Direct Stream configuration:

```text
GEMM_MAC_LANES=4
GEMM_ENABLE_B_CACHE=1
GEMM_B_CACHE_MAX_K=8
GEMM_B_CACHE_MAX_N=8
GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1
GEMM_ENABLE_A_ROW_CACHE=1
GEMM_A_ROW_CACHE_MAX_K=8
GEMM_ENABLE_PACKED_A_ROW_PRELOAD=1
FORCE_HELPER_MEM_PATH=0
```

P9 Direct Stream representative case:

```text
CASE_ID=192 : M=3, N=5, K=7
```

P9 Direct Stream validation completed:

```text
Direct Stream load-store larger-dimension sanity PASS
Representative full-regression scaled-cache item PASS
```

Historical full regression after P9:

```text
65/65 PASS
```


## 17G. P10 K-Dimension Tiling Compatibility

Direct Stream B1 was validated with the P10 K-dimension tiling datapath.

Validated P10 Direct Stream configuration:

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
FORCE_HELPER_MEM_PATH=0
```

P10 Direct Stream representative case:

```text
CASE_ID=195 : M=4, N=4, K=16
K_TILE_SIZE=8
Tile structure: K[0..7], K[8..15]
```

In Direct Stream mode with K-tiling enabled:

```text
Direct Stream preload A -> gemm_operand_buffer A
Direct Stream preload B -> gemm_operand_buffer B
For each K tile:
  B-cache tile preload reads B through gemm_input_mem_router
  A-row tile preload reads A through gemm_input_mem_router
  GEMM accumulates tile partial sums into the internal row accumulator
After all K tiles for a row:
  GEMM writes final C row to scratchpad
DMA store exports final C
scoreboard compares result
```

The important compatibility point is that K-tiling is internal to `gemm_top`. Direct Stream B1 does not need tile headers, per-tile stream packets, or direct stream scheduling changes for P10.

P10 Direct Stream validation completed:

```text
Direct Stream load-store CASE_ID=195 focused sanity      PASS
Representative full-regression K-tiling Direct Stream   PASS
Full regression after P10F                               68/68 PASS
```


## 17H. P11 N-Dimension Tiling Compatibility

Direct Stream B1 was validated with the P11 N-dimension / output-column tiling datapath.

Validated P11 Direct Stream configuration:

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
FORCE_HELPER_MEM_PATH=0
```

P11 Direct Stream representative case:

```text
CASE_ID=200 : M=4, N=16, K=16
K tile structure: K[0..7], K[8..15]
N tile structure: N[0..7], N[8..15]
```

In Direct Stream mode with N-tiling enabled:

```text
Direct Stream preload A -> gemm_operand_buffer A
Direct Stream preload B -> gemm_operand_buffer B
For each output row and N tile:
  For each K tile:
    B-cache tile preload reads B through gemm_input_mem_router
    A-row tile preload reads A through gemm_input_mem_router
    GEMM accumulates tile partial sums into the local-N row accumulator
  GEMM writes final C outputs for the active N tile to scratchpad
DMA store exports final C
scoreboard compares result
```

The important compatibility point is that N-tiling is internal to `gemm_top`. Direct Stream B1 does not need tile headers, per-tile stream packets, or direct stream scheduling changes for P11.

P11 Direct Stream validation completed:

```text
Direct Stream load-store CASE_ID=200 focused sanity      PASS
Representative full-regression N-tiling Direct Stream   PASS
Full regression after P11G                               71/71 PASS
```



## 17I. P12 M-Dimension Tiling Compatibility

Direct Stream B1 was validated with the P12 M-dimension / multi-row output tile scheduling datapath.

Validated P12 Direct Stream configuration:

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
FORCE_HELPER_MEM_PATH=0
```

P12 Direct Stream representative case:

```text
CASE_ID=207 : M=7, N=12, K=16
M tile structure: M[0..1], M[2..3], M[4..5], M[6]
N tile structure: N[0..7], N[8..11]
K tile structure: K[0..7], K[8..15]
```

In Direct Stream mode with M-tiling enabled:

```text
Direct Stream preload A -> gemm_operand_buffer A
Direct Stream preload B -> gemm_operand_buffer B
For each M tile and N tile:
  For each K tile:
    B-cache tile preload reads B through gemm_input_mem_router
    For each active local M row:
      A-row tile preload reads A through gemm_input_mem_router
      GEMM accumulates tile partial sums into the local M/N output-tile accumulator
  GEMM writes final C outputs for the active M/N tile to scratchpad
DMA store exports final C
scoreboard compares result
```

The important compatibility point is that M-tiling is internal to `gemm_top`. Direct Stream B1 does not need tile headers, per-tile stream packets, or direct stream scheduling changes for P12.

P12 Direct Stream validation completed:

```text
Direct Stream load-store CASE_ID=207 focused sanity      PASS
Representative full-regression M-tiling Direct Stream   PASS
Full regression after P12G                               74/74 PASS
```



## 17J. P13 C RMW Accumulation Compatibility

Direct Stream B1 was validated with the P13 C read-modify-write accumulation datapath.

Validated P13 Direct Stream configuration:

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

P13 Direct Stream representative recipe:

```text
CASE_ID=211 : M=8, N=16, K_total=16
External K partition: 8 + 8
Job 0: accumulate_enable=0
Job 1: accumulate_enable=1
```

Direct Stream P13 routing policy:

```text
A/B reads       -> operand buffer
C RMW old-C read -> scratchpad
C writes        -> scratchpad
```

This policy is required because the second partial job must read the C values produced by the first partial job before writing the accumulated result.

P13 Direct Stream validation completed:

```text
Direct Stream load-store CASE_ID=211 C RMW focused sanity PASS
Representative full-regression C RMW Direct Stream item   PASS
Full regression after P13G                                82/82 PASS
```

## 18. Useful Single-Test Runs

### Direct Stream smoke RUN_ALL

```tcl
set UVM_TEST ai_accel_subsys_direct_stream_smoke_test
set ENABLE_RESULT_CHECK 1
set RUN_ALL 1
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
do run_uvm.tcl
```

### Direct Stream load-store stress, 2-lane + B-cache

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
do run_uvm.tcl
```

For the P4E CDC variant, switch:

```tcl
set CORE_CLK_PERIOD_NS 13
```


### Direct Stream load-store stress, 2-lane + packed B-cache preload

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

For the CDC variant:

```tcl
set CORE_CLK_PERIOD_NS 13
do run_uvm.tcl
```



### Direct Stream load-store stress, 2-lane + packed B-cache + A-row cache

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
set GEMM_ENABLE_A_ROW_CACHE 1
set GEMM_A_ROW_CACHE_MAX_K 4
do run_uvm.tcl
```

For the CDC variant:

```tcl
set CORE_CLK_PERIOD_NS 13
do run_uvm.tcl
```

### Direct Stream load-store, 4-lane + K-tiling CASE_ID=195

```tcl
set UVM_TEST ai_accel_subsys_direct_stream_load_store_stress_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 195
set DS_STRESS_JOB_COUNT 1
set DS_STRESS_RANDOM 0
set DS_STRESS_GAP_CYCLES 10
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

For the CDC variant, switch:

```tcl
set CORE_CLK_PERIOD_NS 13
```

### Direct Stream load-store, 4-lane + K/N-tiling CASE_ID=200

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


### Direct Stream load-store, 4-lane + K/N/M-tiling CASE_ID=207

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

### Direct Stream error recovery

```tcl
set UVM_TEST ai_accel_subsys_direct_stream_error_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 100
do run_uvm.tcl
```

### Direct Stream load-store stress, full-regression version

```tcl
set UVM_TEST ai_accel_subsys_direct_stream_load_store_stress_test
set ENABLE_RESULT_CHECK 1
set DS_STRESS_JOB_COUNT 8
set DS_STRESS_SEED 20260502
set DS_STRESS_RANDOM 1
set DS_STRESS_GAP_CYCLES 10
do run_uvm.tcl
```

### Direct Stream load-store stress, longer manual/nightly version

```tcl
set UVM_TEST ai_accel_subsys_direct_stream_load_store_stress_test
set ENABLE_RESULT_CHECK 1
set DS_STRESS_JOB_COUNT 20
set DS_STRESS_SEED 20260502
set DS_STRESS_RANDOM 1
set DS_STRESS_GAP_CYCLES 10
do run_uvm.tcl
```

### Direct Stream load-store CDC sanity

```tcl
set UVM_TEST ai_accel_subsys_direct_stream_load_store_stress_test
set ENABLE_RESULT_CHECK 1
set DS_STRESS_JOB_COUNT 8
set DS_STRESS_SEED 20260502
set DS_STRESS_RANDOM 1
set DS_STRESS_GAP_CYCLES 10
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 13
do run_uvm.tcl
```

---

## 19. Future Option B2: True Streaming GEMM Compute

After B1 is stable, a more aggressive direct streaming model can be considered.

Possible architecture:

```text
AXI MM2S
    -> AXI-Stream async FIFO
    -> GEMM operand scheduler
    -> MAC datapath
    -> C accumulator / output path
```

Open questions:

- should A and B both stream every tile?
- should B be cached while A streams?
- should A be reused across multiple B tiles?
- should packet headers describe M/N/K/tile shape?
- how many MAC lanes consume stream data per cycle?
- should C still write scratchpad?
- should C stream directly to S2MM?
- how should backpressure propagate into compute?
- what is the tile-level ordering contract?

B2 should not begin until B1 has a stable passing regression baseline. B1 satisfies that requirement historically with `33/33 PASS`, and the current P18H subsystem checkpoint is `110/110 PASS`.


### Direct Stream load-store, 4-lane + C RMW CASE_ID=211

```tcl
set UVM_TEST ai_accel_subsys_direct_stream_load_store_stress_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 211
set DS_STRESS_JOB_COUNT 1
set DS_STRESS_RANDOM 0
set DS_STRESS_GAP_CYCLES 10
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


P18F validated Direct Stream completion writeback.  The descriptor-fetch Direct Stream recipe can now run through P17/P16/P15, complete the Direct Stream operand-buffer path, DMA-store C, and write a committed P18 completion record.

Validated P18 Direct Stream representative:

```text
csr_desc_fetch_direct_stream_completion_wb_case102 PASS
```
