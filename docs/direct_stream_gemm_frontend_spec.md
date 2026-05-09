# Direct Stream GEMM Frontend Integration Spec

## 1. Purpose

This document defines the next architecture milestone after the completed AXI-Stream preload baseline.

The current completed AXI-Stream Option A path is:

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

Current full regression baseline before this milestone:

```text
TOTAL : 29
PASS  : 29
FAIL  : 0
```

This document defines the next path:

```text
AXI-MM source memory
    -> AXI MM2S DMA
    -> AXI-Stream CDC boundary
    -> direct-stream operand frontend
    -> operand buffer A/B
    -> existing GEMM compute
    -> scratchpad C
    -> DMA store / S2MM
    -> destination memory compare / scoreboard
```

The goal is to move A/B input feeding away from scratchpad preload and toward a direct stream-backed GEMM input frontend, while preserving the existing GEMM compute behavior and the existing C output path.

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

New milestone.

```text
AXI Stream
    -> operand buffer A/B
    -> GEMM reads A/B from operand buffer
```

In this first direct-stream milestone, C still goes through scratchpad:

```text
GEMM C writes
    -> scratchpad C
    -> DMA store C
    -> destination memory compare
```

### 2.3 B1: Stream-Backed Operand Buffer

This spec selects **B1** as the first direct-stream architecture.

B1 means:

```text
AXI stream fills local operand buffers for A and B.
Existing GEMM then reads A/B from those local operand buffers.
C still writes to scratchpad.
```

This is not yet a fully cycle-by-cycle streaming systolic frontend. It is the safest first step because it removes A/B scratchpad dependency without rewriting the whole GEMM compute datapath.

---

## 3. Design Goals

The direct-stream frontend must:

1. Preserve the existing 29/29 baseline.
2. Keep the existing GEMM compute core mostly unchanged.
3. Avoid using scratchpad for A/B in direct-stream mode.
4. Continue using scratchpad for C output in V1.
5. Reuse the proven MM2S and AXI-Stream CDC infrastructure.
6. Reuse the existing DMA store / S2MM result path.
7. Support fixed, variable-dimension, and configurable-base cases.
8. Support scoreboard result compare and ctrl/result pairing.
9. Support error/recovery tests.
10. Support stress and CDC clock-ratio sanity tests.
11. Allow direct-stream mode and scratchpad mode to coexist.

---

## 4. Non-Goals for V1

The first direct-stream version does **not** attempt to:

- stream operands directly into MAC lanes every cycle
- tile a large matrix across many stream packets
- stream C directly to S2MM
- remove the scratchpad entirely
- change the GEMM arithmetic datapath
- introduce an in-stream packet header
- introduce multi-outstanding MM2S transactions
- support simultaneous stream preload and GEMM compute
- support simultaneous A and B stream channels

Those are future milestones.

---

## 5. Selected Architecture

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
│     - C writes to existing scratchpad adapter                  │
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
GEMM A/B reads -> operand buffer
GEMM C writes  -> scratchpad
```

---

## 6. Mode Model

### 6.1 New GEMM Input Mode

Recommended mode signal:

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
DMA load or host preload A/B into scratchpad
GEMM reads A/B from scratchpad
GEMM writes C to scratchpad
DMA store exports C
```

This mode must preserve all existing 29 regression items.

### 6.3 Direct-Stream Mode

New behavior:

```text
direct stream preload A into operand buffer
direct stream preload B into operand buffer
GEMM reads A/B from operand buffer
GEMM writes C to scratchpad
DMA store exports C
```

### 6.4 Mode Coexistence Rule

The mode is selected per job.

The testbench/software must not change `gemm_input_stream_mode` while:

```text
direct_stream_load_busy == 1
acc_busy == 1
dma_store_busy == 1
```

Recommended enforcement:

- testbench follows this sequencing
- RTL may latch mode at GEMM start
- assertions can flag illegal changes during active operations

---

## 7. Dataflow

### 7.1 Direct-Stream A/B Preload Sequence

```text
1. Configure direct-stream mode.
2. Preload A stream into operand buffer A.
3. Preload B stream into operand buffer B.
4. Start GEMM.
5. GEMM reads A/B from operand buffer.
6. GEMM writes C into scratchpad.
7. DMA store C to destination memory.
8. Compare destination memory.
9. Publish scoreboard result.
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
dma_store_start
wait dma_store_done
compare destination memory
publish scoreboard result
```

---

## 8. Packet Format

### 8.1 V1 Packet Format

V1 keeps the same headerless AXI-Stream packet model as Option A:

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
dim_m
dim_n
dim_k
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

The operand buffer should allow GEMM to keep using its existing address-generation behavior.

Therefore, operand-buffer reads should be selected by address range.

### 9.2 Address Matching

In direct-stream mode, the memory router checks GEMM read addresses.

Recommended rule:

```text
if mem_rd_addr is within A region:
    serve from operand_buffer A

else if mem_rd_addr is within B region:
    serve from operand_buffer B

else:
    route read to scratchpad adapter
```

For V1, only A/B reads are expected during compute.

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

### 9.4 Local Offset Calculation

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

V1 remains beat-count based:

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

If a matrix payload does not fill the final beat, unused bytes must be padded with zero or ignored by GEMM.

The operand buffer may store the full final beat. GEMM uses only the configured M/N/K footprint.

### 10.3 WSTRB Policy

The existing `axi_stream_loader` currently emits full write strobes.

For V1 this is acceptable because:

- A and B operand buffers are logically separate regions
- padded bytes are outside the active matrix footprint
- GEMM only reads valid configured matrix addresses

Future enhancement:

```text
Add byte_count and final-beat WSTRB support.
```

---

## 11. Proposed New RTL Blocks

### 11.1 direct_stream_preload_engine

Recommended file:

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

This can be derived from the existing `axis_preload_engine`, but the scratchpad write adapter is replaced with an operand-buffer write adapter.

### 11.2 gemm_operand_buffer

Recommended file:

```text
rtl/subsystem/gemm_operand_buffer.sv
```

Role:

```text
stores streamed A/B operands
serves GEMM A/B reads in direct-stream mode
```

Recommended interfaces:

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
write_error
read_error
```

V1 implementation can be simple register-array or inferred RAM.

### 11.3 gemm_operand_buffer_write_adapter

Recommended file:

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

- converts stream-loader linear writes into operand-buffer writes
- checks address alignment
- tracks accepted/completed writes
- reports sticky error

This should be much simpler than the scratchpad write adapter because there is no AXI B response.

### 11.4 gemm_input_mem_router

Recommended file:

```text
rtl/subsystem/gemm_input_mem_router.sv
```

Role:

```text
routes GEMM local memory requests to:
    operand buffer for A/B reads in direct-stream mode
    scratchpad adapter for C writes and scratchpad-mode A/B reads
```

Input from GEMM:

```systemverilog
gemm_mem_req_ready
gemm_mem_rd_en
gemm_mem_rd_addr
gemm_mem_rd_data
gemm_mem_rd_valid
gemm_mem_wr_en
gemm_mem_wr_addr
gemm_mem_wr_data
gemm_mem_wr_strb
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
all GEMM reads and writes route to gemm_scratchpad_adapter
```

Behavior in direct-stream mode:

```text
A/B reads route to operand buffer
C writes route to gemm_scratchpad_adapter
unexpected non-A/B reads may route to scratchpad or flag an error
```

### 11.5 direct_stream_frontend_status

This may be implemented as discrete status outputs rather than a separate module.

Recommended status signals:

```systemverilog
ds_load_busy
ds_load_done
ds_load_error
ds_a_loaded
ds_b_loaded
ds_router_error
ds_operand_buffer_error
```

---

## 12. Top-Level Integration

### 12.1 New Source AXI Port

The direct-stream preload path needs a source AXI-MM read interface.

Recommended naming:

```text
ds_src_axi_ar*
ds_src_axi_r*
```

Alternative:

The existing `axis_src_axi_ar/r` responder may be reused if direct-stream mode replaces the current AXI-Stream preload path in the testbench.

Recommendation for clarity:

```text
Use a new ds_src_axi_ar/r port for direct stream.
```

Reason:

- isolates Option A and Option B traffic
- keeps debug waveforms clear
- avoids sharing one source responder between two frontend modes
- allows independent RRESP error injection

### 12.2 New Control Fields

Add to `ai_accel_subsys_ctrl_if`:

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

Optional debug:

```systemverilog
logic                  ds_a_loaded;
logic                  ds_b_loaded;
logic                  ds_router_error;
logic                  ds_operand_buffer_error;
logic [31:0]           ds_loader_accepted_beats;
logic [31:0]           ds_loader_written_beats;
```

### 12.3 GEMM Start Gating

GEMM start should be accepted only when:

```text
ds_load_busy == 0
axis_load_busy == 0
dma_load_busy == 0
dma_store_busy == 0
```

In direct-stream mode, GEMM start should also require:

```text
ds_a_loaded == 1
ds_b_loaded == 1
```

Recommended behavior:

```text
If acc_start occurs while direct-stream operands are not loaded:
    reject start or flag an error
```

For V1, the testbench should sequence correctly. RTL should at least prevent illegal overlap.

### 12.4 GEMM Adapter Integration

Existing path:

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

`ds_load_error` should assert for:

- zero `ds_load_beats`
- unaligned source address
- unaligned destination/logical operand address
- AXI source `RRESP` error
- unexpected `RID`
- missing or invalid `RLAST`
- early `TLAST`
- missing `TLAST`
- operand buffer write overflow
- invalid `ds_operand_sel`
- start while busy

### 13.2 Operand Buffer Read Errors

Router or operand buffer should flag error for:

- GEMM read from A before A is loaded
- GEMM read from B before B is loaded
- GEMM read outside valid A/B range in direct-stream mode
- GEMM read beyond allocated operand buffer depth
- illegal mode change during GEMM active

### 13.3 Recovery Policy

After an error:

```text
ds_load_error = 1 for done pulse or sticky status
system returns to idle
next valid direct-stream load can proceed
valid direct-stream A/B preload + GEMM + DMA store should recover
```

Recommended recovery test:

```text
zero beats error
unaligned source error
unaligned destination error
source RRESP error
valid direct-stream A/B preload
GEMM
DMA store
destination compare
scoreboard pass
```

---

## 14. Verification Plan

### 14.1 Subsystem Smoke Test

Recommended new test:

```text
ai_accel_subsys_direct_stream_smoke_test
```

Flow:

```text
1. set gemm_input_stream_mode = 1
2. clear scratchpad C
3. clear destination memory
4. preload source memory with A payload
5. direct-stream preload A into operand buffer
6. preload source memory with B payload
7. direct-stream preload B into operand buffer
8. start GEMM
9. wait acc_done
10. DMA store C to destination memory
11. compare destination memory
12. publish result to scoreboard
```

Recommended first runs:

```text
CASE_ID=100
CASE_ID=101
RUN_ALL=1: 100 -> 101 -> 105 -> 5 -> 400 -> 401 -> 402 -> 403
```

### 14.2 Subsystem Error Test

Recommended new test:

```text
ai_accel_subsys_direct_stream_error_test
```

Coverage:

- zero `ds_load_beats`
- unaligned source address
- unaligned logical destination address
- source AXI RRESP error
- invalid operand select
- GEMM start before A/B loaded
- valid direct-stream recovery after errors
- valid GEMM + DMA store recovery after errors

### 14.3 Subsystem Stress Test

Recommended new test:

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

Recommended knobs:

```text
DS_STRESS_JOB_COUNT
DS_STRESS_SEED
DS_STRESS_RANDOM
DS_STRESS_GAP_CYCLES
```

Recommended full-regression version:

```text
8 jobs
```

Recommended manual/nightly version:

```text
20 jobs
```

### 14.4 CDC Sanity

Recommended clock-ratio sanity:

```text
DMA_CLK_PERIOD_NS  = 10
CORE_CLK_PERIOD_NS = 13
```

Coverage:

- MM2S source side runs in dma_clk
- stream data crosses async FIFO
- operand buffer write side runs in core_clk
- direct-stream load done/error returns to dma_clk
- GEMM starts only after A/B are loaded

---

## 15. Regression Plan

Current baseline before Direct Stream GEMM Frontend:

```text
TOTAL : 29
PASS  : 29
FAIL  : 0
```

Recommended staged additions:

### Stage B1-A: Direct-stream smoke

```text
+1 item
Expected full regression: 30 / 30 PASS
```

### Stage B1-B: Direct-stream error/recovery

```text
+1 item
Expected full regression: 31 / 31 PASS
```

### Stage B1-C: Direct-stream load-store stress

```text
+1 item
Expected full regression: 32 / 32 PASS
```

### Stage B1-D: Direct-stream CDC clock-ratio sanity

```text
+1 item
Expected full regression: 33 / 33 PASS
```

Each stage must preserve the existing 29 baseline tests.

---

## 16. Acceptance Criteria

The Direct Stream GEMM Frontend B1 milestone is complete when:

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

---

## 17. Recommended Implementation Sequence

Recommended RTL implementation order:

```text
1. Add gemm_operand_buffer.sv.
2. Add gemm_operand_buffer_write_adapter.sv.
3. Add direct_stream_preload_engine.sv.
4. Add gemm_input_mem_router.sv.
5. Integrate gemm_input_mem_router into ai_accel_subsys.sv.
6. Integrate direct_stream_preload_engine into ai_accel_subsys.sv.
7. Extend ai_accel_subsys_ctrl_if.sv with direct-stream control/status.
8. Extend ai_accel_subsys_uvm_top.sv with ds_src_axi responder.
9. Add ai_accel_subsys_direct_stream_smoke_test.sv.
10. Add ai_accel_subsys_direct_stream_error_test.sv.
11. Add ai_accel_subsys_direct_stream_load_store_stress_test.sv.
12. Add direct-stream CDC clock-ratio regression item.
```

Recommended first RTL target after this spec:

```text
gemm_operand_buffer.sv
```

Reason:

- it is local to the core clock domain
- it does not touch the top-level integration yet
- it can compile independently
- it defines the direct-stream data storage contract
- the later router and preload engine will connect to it

---

## 18. Future Option B2: True Streaming GEMM Compute

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

B2 should not begin until B1 has a passing regression baseline.
