# AXI-Stream GEMM Frontend Integration Spec

## 1. Purpose

This document defines the next architecture milestone for the AI Accelerator Subsystem:

```text
AXI-MM source memory
    -> AXI MM2S DMA
    -> AXI-Stream CDC boundary
    -> AXI-Stream loader
    -> scratchpad A/B preload
    -> existing GEMM
    -> scratchpad C
    -> DMA store / S2MM
    -> destination memory compare / scoreboard
```

The goal is to add an **AXI-Stream frontend path** without rewriting the current GEMM compute datapath.

The current subsystem baseline is already stable:

```text
DMA load A/B
    -> scratchpad
    -> GEMM
    -> DMA store C
    -> destination memory
```

Current full regression baseline:

```text
TOTAL : 25
PASS  : 25
FAIL  : 0
```

This AXI-Stream frontend milestone should preserve that baseline and add a new preload path for A/B data.

---

## 2. Design Direction

### 2.1 Selected Direction: Option A

The selected first implementation is:

```text
Option A: Stream preload into scratchpad
```

Architecture:

```text
dma_clk domain
---------------------------------------------------------
AXI-MM source memory
    -> axi_mm2s_dma
    -> AXI-Stream async FIFO write side


CDC boundary
---------------------------------------------------------
AXI-Stream async FIFO


core_clk domain
---------------------------------------------------------
AXI-Stream async FIFO read side
    -> axi_stream_loader
    -> axis_scratchpad_write_adapter
    -> scratchpad Port1 write path
    -> existing GEMM reads A/B from scratchpad
```

Then the existing compute/store flow continues:

```text
existing GEMM
    -> scratchpad C
    -> dma_store_engine
    -> destination memory model
    -> scoreboard compare
```

### 2.2 Why Option A First

Option A is selected because:

- it keeps the existing GEMM datapath unchanged
- it preserves the current scratchpad-backed execution model
- it reuses the existing DMA store / S2MM result path
- it allows AXI-Stream protocol and CDC behavior to be verified independently
- it avoids introducing direct streaming compute hazards too early
- it minimizes risk to the current 25/25 full regression baseline

### 2.3 Not Selected Yet: Option B

Option B is deferred:

```text
DMA MM2S
    -> AXI-Stream async FIFO
    -> direct stream GEMM frontend
    -> GEMM compute
```

This would require changing GEMM operand scheduling, buffering, and compute timing. It should be treated as a future architecture milestone after Option A is stable.

---

## 3. Existing Reusable RTL Blocks

### 3.1 Existing AXI MM2S DMA

Existing file:

```text
rtl/dma/axi_mm2s_dma.sv
```

Current role:

```text
AXI-MM read master
    -> AXI-Stream output
```

Relevant behavior:

- accepts `start`, `src_addr`, and `xfer_len_beats`
- issues single-beat AXI-MM reads
- outputs one AXI-Stream beat per AXI read response
- asserts `m_axis_tlast` on the final beat
- checks source address alignment
- rejects zero-length transfer
- checks AXI `RRESP`
- checks expected `RID`
- checks `RLAST`

This module is suitable as the first MM2S data source for the AXI-Stream frontend.

### 3.2 Existing AXI Stream Loader

Existing file:

```text
rtl/dma/axi_stream_loader.sv
```

Current role:

```text
AXI-Stream input
    -> simple linear write-request output
```

Relevant behavior:

- accepts `s_axis_tdata`, `s_axis_tvalid`, `s_axis_tready`, and `s_axis_tlast`
- writes sequential beats starting from `dst_base_addr`
- produces:
  - `wr_valid`
  - `wr_ready`
  - `wr_addr`
  - `wr_data`
  - `wr_strb`
  - `wr_last`
- tracks `accepted_beats`
- tracks `written_beats`
- tracks `tlast_seen`
- checks destination alignment
- checks `TLAST` against `expected_beats`
- contains optional capture memory for debug/readback

This module is suitable as the first AXI-Stream-to-linear-write frontend.

---

## 4. Proposed V1 Architecture

### 4.1 High-Level Block Diagram

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
│  AXI-Stream async FIFO write side                              │
│                                                                │
└───────────────────────────────┬────────────────────────────────┘
                                │
                                │ CDC
                                ▼
┌────────────────────────────────────────────────────────────────┐
│                                  core_clk                      │
│                                                                │
│  AXI-Stream async FIFO read side                               │
│           │                                                    │
│           ▼                                                    │
│  axi_stream_loader                                             │
│     - AXI-Stream consumer                                      │
│     - linear write-request producer                            │
│           │                                                    │
│           ▼                                                    │
│  axis_scratchpad_write_adapter                                 │
│     - converts wr_* requests to scratchpad AXI-MM writes       │
│           │                                                    │
│           ▼                                                    │
│  scratchpad_port1_owner_mux                                    │
│     - STREAM_LOAD owner before GEMM                            │
│     - GEMM owner during compute                                │
│           │                                                    │
│           ▼                                                    │
│  axi_mm_dual_port_bram Port1                                   │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

### 4.2 Why Use Scratchpad Port1

The stream loader is placed in `core_clk`, after the AXI-Stream async FIFO.

Therefore the natural scratchpad write port for the stream frontend is:

```text
scratchpad Port1
```

Reason:

- Port1 already belongs to the `core_clk` domain
- the async FIFO cleanly separates `dma_clk` source traffic from `core_clk` scratchpad writes
- Port0 remains available for existing HOST / DMA_LOAD / DMA_STORE ownership logic
- the current Port0 owner mux does not need to be modified for the first AXI-Stream frontend version

### 4.3 New Port1 Ownership Model

Port1 currently serves the GEMM scratchpad adapter.

V1 adds a core-side Port1 owner mux:

```text
STREAM_LOAD
GEMM
```

Recommended owner policy:

```text
STREAM_LOAD : active while AXI-stream preload is writing A or B
GEMM        : active while GEMM compute is running or idle after preload
```

Illegal condition:

```text
stream_load_busy && acc_busy
```

The system should not allow GEMM to start until stream preload is complete.

---

## 5. V1 Dataflow

### 5.1 A/B Preload Sequence

The first version uses two independent stream preload jobs:

```text
1. Stream preload A
2. Stream preload B
3. Start existing GEMM
4. Wait acc_done
5. DMA store C to destination memory
6. Compare destination memory
```

### 5.2 A Preload

```text
axis_load_start
axis_src_base_addr = source address of A payload
axis_dst_base_addr = scratchpad base_addr_a
axis_load_beats    = ceil(A_bytes / DATA_WIDTH_BYTES)
```

### 5.3 B Preload

```text
axis_load_start
axis_src_base_addr = source address of B payload
axis_dst_base_addr = scratchpad base_addr_b
axis_load_beats    = ceil(B_bytes / DATA_WIDTH_BYTES)
```

### 5.4 GEMM and Store

After both stream preload jobs finish:

```text
acc_start
wait acc_done
dma_store_start
wait dma_store_done
compare destination memory
publish scoreboard result
```

---

## 6. Packet Format

### 6.1 V1 Packet Format

V1 uses a headerless AXI-Stream packet:

```text
beat 0      : payload data
beat 1      : payload data
...
beat N - 1  : payload data with TLAST = 1
```

There is no in-stream header in V1.

Metadata is provided by the control interface:

```text
src_base_addr
dst_base_addr
expected_beats
matrix selector / case context from test
```

### 6.2 Why Headerless First

Headerless packets are selected for V1 because:

- `axi_mm2s_dma` already produces `TLAST`
- `axi_stream_loader` already checks `TLAST` against `expected_beats`
- control-driven A/B sequencing is easier to debug
- packet parser complexity is avoided in the first integration

### 6.3 Future Header Option

A future version may add an in-stream header:

```text
word 0: packet_type
word 1: dst_base_addr
word 2: byte_count
word 3: flags
```

This is not required for V1.

---

## 7. Beat Count and Padding Policy

### 7.1 Transfer Unit

V1 is beat-count based:

```text
axis_load_beats = ceil(matrix_bytes / BYTES_PER_BEAT)
```

Where:

```text
BYTES_PER_BEAT = DATA_WIDTH / 8
```

For the current 64-bit data width:

```text
BYTES_PER_BEAT = 8
```

### 7.2 Matrix Payload Padding

A and B matrix payloads remain compact row-major int8 arrays.

If a matrix payload does not fill the final beat, unused bytes must be padded.

Example:

```text
CASE_ID 100:
A_bytes = 1
B_bytes = 1
DATA_WIDTH = 64
axis_load_beats = 1
```

The loader writes one full beat into the scratchpad. The unused bytes are padding and are ignored by GEMM because GEMM only reads the configured M/N/K footprint.

### 7.3 V1 WSTRB Policy

`axi_stream_loader` currently emits full write strobes:

```text
wr_strb = all ones
```

This is acceptable for V1 because:

- A and B regions are separated in scratchpad
- matrix payloads are padded
- GEMM reads only the configured compact matrix footprint

Future enhancement:

```text
Add byte_count and final-beat WSTRB support to stream loader.
```

---

## 8. Control and Status Interface

### 8.1 New Stream Preload Control

Recommended top-level control signals:

```systemverilog
logic                  axis_load_start;
logic [ADDR_WIDTH-1:0] axis_src_base_addr;
logic [ADDR_WIDTH-1:0] axis_dst_base_addr;
logic [31:0]           axis_load_beats;

logic                  axis_load_busy;
logic                  axis_load_done;
logic                  axis_load_error;
```

### 8.2 Optional Debug Status

Recommended debug/status signals:

```systemverilog
logic [31:0] axis_loader_accepted_beats;
logic [31:0] axis_loader_written_beats;
logic        axis_loader_tlast_seen;
logic        axis_fifo_empty;
logic        axis_fifo_full;
```

### 8.3 Software/Testbench Sequencing

The control flow is:

```text
write axis_src_base_addr
write axis_dst_base_addr
write axis_load_beats
pulse axis_load_start
wait axis_load_done
check axis_load_error
```

Then repeat for the second matrix.

---

## 9. CDC Control Strategy

### 9.1 Data CDC

AXI-Stream data crosses domains through an async FIFO:

```text
dma_clk producer
    -> async FIFO
    -> core_clk consumer
```

The FIFO payload should include:

```text
tdata
tlast
```

Recommended FIFO data width:

```text
FIFO_WIDTH = DATA_WIDTH + 1
```

Packing:

```systemverilog
fifo_wdata = {m_axis_tlast, m_axis_tdata};
fifo_rdata = {s_axis_tlast, s_axis_tdata};
```

### 9.2 Control CDC

`axis_load_start` is accepted in `dma_clk`.

The destination side loader runs in `core_clk`.

Recommended two-domain start sequence:

```text
1. dma_clk captures axis load config.
2. dma_clk sends load request toggle to core_clk.
3. core_clk latches dst_base_addr and expected_beats.
4. core_clk starts axi_stream_loader.
5. core_clk sends loader_ready/active acknowledgement back to dma_clk.
6. dma_clk starts axi_mm2s_dma only after loader is ready.
7. mm2s streams data into FIFO.
8. loader consumes FIFO data and writes scratchpad.
9. core_clk reports loader_done/error back to dma_clk.
10. dma_clk reports axis_load_done/error.
```

### 9.3 Why MM2S Starts After Loader Ready

MM2S should not start before the core-side loader is ready.

Reason:

- prevents FIFO overflow at startup
- makes error handling deterministic
- avoids stream data arriving before the destination write path is armed
- simplifies debug waveforms

### 9.4 Config CDC Rule

Multi-bit config values must be captured and held stable while the request toggle crosses domains.

Config values:

```text
axis_dst_base_addr
axis_load_beats
```

The `axis_src_base_addr` is used only by the dma-side MM2S engine.

---

## 10. New RTL Blocks Required

### 10.1 axis_preload_engine

Recommended new module:

```text
rtl/subsystem/axis_preload_engine.sv
```

Role:

```text
integrates:
    axi_mm2s_dma
    AXI-Stream async FIFO
    axi_stream_loader
    axis_scratchpad_write_adapter
    control/status CDC
```

Primary interface:

```text
dma_clk / dma_rst_n
core_clk / core_rst_n

axis_load_start
axis_src_base_addr
axis_dst_base_addr
axis_load_beats
axis_load_busy
axis_load_done
axis_load_error

source AXI-MM read master port
scratchpad Port1 write request / AXI-MM write master side
debug status
```

### 10.2 axis_scratchpad_write_adapter

Recommended new module:

```text
rtl/subsystem/axis_scratchpad_write_adapter.sv
```

Role:

```text
axi_stream_loader wr_* output
    -> scratchpad AXI-MM single-beat write transaction
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
awaddr / awvalid / awready
wdata  / wstrb / wlast / wvalid / wready
bresp  / bvalid / bready
```

Behavior:

- accepts one linear write request at a time
- issues one single-beat AXI-MM write
- waits for BRESP
- reports write response error
- provides backpressure through `wr_ready`

### 10.3 scratchpad_port1_owner_mux

Recommended new module:

```text
rtl/subsystem/scratchpad_port1_owner_mux.sv
```

Role:

```text
selects scratchpad Port1 owner:
    STREAM_LOAD
    GEMM
```

Behavior:

- route stream preload writes to Port1 during stream load
- route GEMM scratchpad adapter to Port1 otherwise
- reject/flag illegal overlap between stream load and GEMM busy
- keep GEMM path unchanged when stream preload is disabled

### 10.4 AXI-Stream Async FIFO Wrapper

Recommended new module:

```text
rtl/subsystem/axis_async_fifo.sv
```

Role:

```text
AXI-Stream valid/ready wrapper around existing async_fifo
```

Payload:

```text
{tlast, tdata}
```

Behavior:

- source side:
  - accepts `s_axis_tvalid/tready`
  - writes FIFO
- destination side:
  - drives `m_axis_tvalid/tready`
  - reads FIFO
- exposes optional `empty/full` debug status

---

## 11. Top-Level Integration

### 11.1 New External Source AXI Port

The subsystem needs an AXI-MM source read interface for the stream preload path.

Recommended naming:

```text
axis_src_axi_ar*
axis_src_axi_r*
```

This is separate from the existing DMA load source model and separate from the S2MM destination write model.

### 11.2 New Control Interface Fields

Add to `ai_accel_subsys_ctrl_if`:

```systemverilog
logic                  axis_load_start;
logic [ADDR_WIDTH-1:0] axis_src_base_addr;
logic [ADDR_WIDTH-1:0] axis_dst_base_addr;
logic [31:0]           axis_load_beats;

logic                  axis_load_busy;
logic                  axis_load_done;
logic                  axis_load_error;
```

Optional debug:

```systemverilog
logic [31:0] axis_loader_accepted_beats;
logic [31:0] axis_loader_written_beats;
logic        axis_loader_tlast_seen;
```

### 11.3 UVM Top Model

Add to `ai_accel_subsys_uvm_top.sv`:

```text
AXI source memory responder for axis_src_axi_ar/r
```

This can reuse the same byte-addressed source memory concept already used by DMA load tests, or use a separate source array for stream-specific tests.

Recommended V1:

```text
reuse dma_src_mem[] for stream source payloads
```

Reason:

- less testbench duplication
- easier comparison with existing DMA load tests
- same A/B payload generation helper can be reused

---

## 12. Error Handling

### 12.1 MM2S Errors

The stream preload operation should fail if `axi_mm2s_dma` reports:

- zero `xfer_len_beats`
- unaligned source address
- AXI `RRESP` error
- unexpected `RID`
- missing or invalid `RLAST`

### 12.2 Loader Errors

The stream preload operation should fail if `axi_stream_loader` reports:

- unaligned destination address
- `TLAST` earlier than `expected_beats`
- missing `TLAST` at `expected_beats`
- capture capacity exceeded

### 12.3 Scratchpad Write Errors

The stream preload operation should fail if `axis_scratchpad_write_adapter` receives:

- AXI `BRESP` error from scratchpad Port1 write

### 12.4 Busy/Overlap Errors

The stream preload operation should fail or be rejected if:

- start while `axis_load_busy`
- start while `acc_busy`
- GEMM start while `axis_load_busy`
- FIFO not empty at job start

---

## 13. Verification Plan

### 13.1 Unit-Level Tests

Recommended unit tests:

```text
axi_mm2s_dma_unit_test
    - valid transfer
    - zero beats
    - unaligned source
    - RRESP error
    - RID mismatch
    - RLAST mismatch

axi_stream_loader_unit_test
    - valid packet
    - unaligned destination
    - early TLAST
    - missing TLAST
    - backpressure on wr_ready
    - capture depth overflow

axis_scratchpad_write_adapter_unit_test
    - valid single-beat write
    - backpressure on AW/W/B
    - BRESP error
```

Unit tests are optional for the project if subsystem-level tests are prioritized, but they are recommended because the stream path introduces more handshake states.

### 13.2 Subsystem Smoke Test

Recommended new test:

```text
ai_accel_subsys_axis_stream_preload_smoke_test
```

Flow:

```text
1. clear scratchpad C
2. clear destination memory
3. preload source memory with A payload
4. axis stream preload A into scratchpad
5. preload source memory with B payload
6. axis stream preload B into scratchpad
7. start GEMM
8. wait acc_done
9. DMA store C to destination memory
10. compare destination memory
11. publish result to scoreboard
```

Recommended first cases:

```text
CASE_ID 100
CASE_ID 101
RUN_ALL: 100 -> 101 -> 105 -> 5 -> 400 -> 401 -> 402 -> 403
```

### 13.3 Subsystem Error Test

Recommended new test:

```text
ai_accel_subsys_axis_stream_preload_error_test
```

Coverage:

- zero `axis_load_beats`
- unaligned source address
- unaligned destination address
- source AXI RRESP error
- loader TLAST mismatch
- scratchpad BRESP error
- start while busy
- recovery preload after errors
- recovery GEMM + DMA store after errors

### 13.4 Subsystem Stress Test

Recommended new test:

```text
ai_accel_subsys_axis_stream_load_store_stress_test
```

Flow per job:

```text
AXI-stream preload A
AXI-stream preload B
GEMM
DMA store C
destination memory compare
scoreboard publish
```

Recommended knobs:

```text
AXIS_STRESS_JOB_COUNT
AXIS_STRESS_SEED
AXIS_STRESS_RANDOM
AXIS_STRESS_GAP_CYCLES
```

Recommended full-regression version:

```text
8 jobs
```

Recommended manual/nightly version:

```text
20 jobs
```

### 13.5 CDC Regression

Recommended clock-ratio sanity:

```text
DMA_CLK_PERIOD_NS  = 10
CORE_CLK_PERIOD_NS = 13
```

Coverage:

- stream data crosses async FIFO
- stream loader runs in core domain
- preload done/error returns to dma domain
- GEMM start occurs after stream preload done

---

## 14. Regression Plan

Current baseline before AXI-Stream frontend:

```text
TOTAL : 25
PASS  : 25
FAIL  : 0
```

Recommended staged regression additions:

### Stage A: AXIS preload smoke

```text
+1 item
Expected full regression: 26 / 26 PASS
```

### Stage B: AXIS preload error/recovery

```text
+1 item
Expected full regression: 27 / 27 PASS
```

### Stage C: AXIS load-store stress

```text
+1 item
Expected full regression: 28 / 28 PASS
```

### Stage D: AXIS CDC clock-ratio sanity

```text
+1 item
Expected full regression: 29 / 29 PASS
```

Each stage must preserve all existing 25 baseline tests.

---

## 15. Acceptance Criteria

The AXI-Stream frontend milestone is complete when:

1. Existing 25/25 regression remains passing.
2. AXI MM2S can stream source memory payloads.
3. AXI-Stream async FIFO transfers `{tlast, tdata}` across clock domains.
4. AXI stream loader writes A/B payloads into scratchpad.
5. GEMM can consume stream-preloaded A/B from scratchpad.
6. DMA store can export C to destination memory.
7. Destination memory compare passes.
8. Scoreboard result compare passes.
9. Ctrl/result pairing passes.
10. Error/recovery tests pass.
11. AXI-Stream CDC clock-ratio sanity passes.
12. No GEMM compute datapath rewrite is required.
13. No BRAM interface semantic change is required.

---

## 16. Implementation Sequence

Recommended RTL implementation order:

```text
1. Confirm existing axi_mm2s_dma.sv compiles in current project.
2. Confirm existing axi_stream_loader.sv compiles in current project.
3. Add axis_scratchpad_write_adapter.sv.
4. Add scratchpad_port1_owner_mux.sv.
5. Add axis_async_fifo.sv wrapper around existing async_fifo.
6. Add axis_preload_engine.sv.
7. Integrate axis_preload_engine into ai_accel_subsys.sv.
8. Extend ai_accel_subsys_ctrl_if.sv.
9. Extend ai_accel_subsys_uvm_top.sv with stream source responder.
10. Add axis_stream_preload_smoke_test.
11. Add axis_stream_preload_error_test.
12. Add axis_stream_load_store_stress_test.
```

Recommended first RTL target after this spec:

```text
axis_scratchpad_write_adapter.sv
```

Reason:

- it is small and local
- it directly connects the existing `axi_stream_loader` output to scratchpad AXI-MM writes
- it can be tested before the full async FIFO/MM2S wrapper exists

---

## 17. Future Option B: Direct Stream GEMM Frontend

After Option A is stable, a direct stream GEMM frontend can be considered.

Possible architecture:

```text
AXI MM2S
    -> AXI-Stream async FIFO
    -> GEMM operand buffer
    -> GEMM compute pipeline
    -> scratchpad C or direct S2MM
```

Open questions for Option B:

- should A and B both be streamed?
- should B be cached while A streams?
- should stream format include matrix headers?
- how should tiling be represented?
- how many MAC lanes should consume stream data?
- should C still be written to scratchpad?
- should S2MM write C directly from compute output?

Option B should not begin until Option A has a passing regression baseline.
