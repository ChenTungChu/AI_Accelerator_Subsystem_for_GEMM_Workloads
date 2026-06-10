# AXI-Stream GEMM Frontend Integration Spec

## 1. Purpose

This document defines the AXI-Stream frontend architecture milestone for the AI Accelerator Subsystem.

The completed V1 data path is:

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

The goal of this milestone was to add an **AXI-Stream frontend path** without rewriting the current GEMM compute datapath.

The stable pre-AXIS subsystem baseline was:

```text
DMA load A/B
    -> scratchpad
    -> GEMM
    -> DMA store C
    -> destination memory
```

The AXI-Stream frontend milestone has now been implemented and verified.

Current full regression baseline at AXI-Stream V1 closure:

```text
TOTAL : 29
PASS  : 29
FAIL  : 0
```


Current project status after P17H closure:

```text
Descriptor Fetch P17H: Memory-Backed Recipe Descriptor Fetch Regression Completed
Full regression: 105/105 PASS
```

The AXI-Stream frontend remains compatible with the P13 C RMW accumulation path. AXI-Stream preload supplies compact A/B partial-job payloads through scratchpad, while GEMM C RMW old-C reads and C writes remain scratchpad-backed.


P17 descriptor format keeps `INPUT_MODE=AXIS_PRELOAD` structurally compatible with the same P15/P16 frontend-mode policy.  The P17H full-regression frontend representative uses Direct Stream to cover the non-scratchpad frontend path, while the existing P16 recipe regression continues to cover AXI-Stream two-slot recipes through `csr_recipe_axis_stream_two_slot_case102`.



---

## 2. Design Direction

### 2.1 Selected Direction: Option A

The implemented first version uses:

```text
Option A: Stream preload into scratchpad
```

Implemented architecture:

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

### 2.2 Why Option A Was Selected

Option A was selected because:

- it keeps the existing GEMM datapath unchanged
- it preserves the scratchpad-backed execution model
- it reuses the existing DMA store / S2MM result path
- it allows AXI-Stream protocol and CDC behavior to be verified independently
- it avoids introducing direct streaming compute hazards too early
- it minimizes risk to the existing DMA/load/store baseline

### 2.3 Deferred Direction: Option B

Option B remains deferred:

```text
DMA MM2S
    -> AXI-Stream async FIFO
    -> direct stream GEMM frontend
    -> GEMM compute
```

This would require changing GEMM operand scheduling, buffering, and compute timing. It should be treated as a future architecture milestone after the current Option A baseline is preserved.

---

## 3. Reusable RTL Blocks

### 3.1 AXI MM2S DMA

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

This module is used as the MM2S source engine for AXI-Stream preload.

### 3.2 AXI Stream Loader

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

This module is used as the stream-to-linear-write frontend.

---

## 4. Implemented V1 Architecture

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

### 4.2 Scratchpad Port1 Usage

The stream loader is placed in `core_clk`, after the AXI-Stream async FIFO.

Therefore the natural scratchpad write port for the stream frontend is:

```text
scratchpad Port1
```

Reason:

- Port1 already belongs to the `core_clk` domain
- the async FIFO cleanly separates `dma_clk` source traffic from `core_clk` scratchpad writes
- Port0 remains available for existing HOST / DMA_LOAD / DMA_STORE ownership logic
- the Port0 owner mux did not need to be modified for this AXI-Stream frontend version

### 4.3 Port1 Ownership Model

Port1 now has two core-domain owners:

```text
STREAM_LOAD
GEMM
```

Implemented owner policy:

```text
STREAM_LOAD : active while AXI-Stream preload is writing A or B
GEMM        : active while GEMM compute is running or when stream preload is idle
```

Illegal condition:

```text
stream_load_active && gemm_active
```

System-level sequencing prevents GEMM from starting while AXI-Stream preload is still active.

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
7. Publish result to scoreboard
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
axis_src_base_addr
axis_dst_base_addr
axis_load_beats
matrix selector / case context from test
```

### 6.2 Why Headerless First

Headerless packets are used in V1 because:

- `axi_mm2s_dma` already produces `TLAST`
- `axi_stream_loader` already checks `TLAST` against `expected_beats`
- control-driven A/B sequencing is easy to debug
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

If a matrix payload does not fill the final beat, unused bytes are padded.

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

### 8.1 Stream Preload Control

Top-level control signals:

```systemverilog
logic                  axis_load_start;
logic [ADDR_WIDTH-1:0] axis_src_base_addr;
logic [ADDR_WIDTH-1:0] axis_dst_base_addr;
logic [31:0]           axis_load_beats;

logic                  axis_load_busy;
logic                  axis_load_done;
logic                  axis_load_error;
```

### 8.2 Debug Status

Implemented/debug-friendly status signals include:

```systemverilog
logic [31:0] axis_loader_accepted_beats;
logic [31:0] axis_loader_written_beats;
logic        axis_loader_tlast_seen;

logic        axis_fifo_empty;
logic        axis_fifo_full;

logic [31:0] axis_adapter_accepted_writes;
logic [31:0] axis_adapter_completed_writes;
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

AXI-Stream data crosses domains through `axis_async_fifo`:

```text
dma_clk producer
    -> async FIFO
    -> core_clk consumer
```

FIFO payload:

```text
{tlast, tdata}
```

FIFO data width:

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

Implemented two-domain start sequence:

```text
1. dma_clk captures AXIS load config.
2. dma_clk sends load request toggle to core_clk.
3. core_clk latches dst_base_addr and expected_beats.
4. core_clk waits one cycle so latched config is stable.
5. core_clk starts axi_stream_loader.
6. core_clk sends request acknowledgement back to dma_clk.
7. dma_clk starts axi_mm2s_dma only after core-side request acceptance.
8. mm2s streams data into FIFO.
9. loader consumes FIFO data and writes scratchpad.
10. core_clk reports loader/write-adapter done/error back to dma_clk.
11. dma_clk reports axis_load_done/error.
```

### 9.3 Config Latch Timing Note

A one-cycle `C_START`-style state is required between core-side config latch and `axi_stream_loader.start`.

Reason:

```text
If loader_start_pulse is asserted in the same core_clk edge that
dst_addr_core_q / beats_core_q are updated, the loader can sample
the previous job's config.
```

The implemented fix is:

```text
C_IDLE:
    latch config on request event

C_START:
    pulse loader_start after config is already registered

C_ACTIVE:
    run stream loader / write adapter
```

`stream_load_active` covers both the loader-start and active write window so Port1 ownership is already assigned to STREAM_LOAD when the first write transaction appears.

### 9.4 Why MM2S Starts After Loader Ready

MM2S should not start before the core-side loader is armed.

Reason:

- prevents FIFO overflow at startup
- makes error handling deterministic
- avoids stream data arriving before the destination write path is armed
- simplifies debug waveforms

### 9.5 Config CDC Rule

Multi-bit config values must be captured and held stable while the request toggle crosses domains.

Config values:

```text
axis_dst_base_addr
axis_load_beats
```

The `axis_src_base_addr` is used only by the dma-side MM2S engine.

---

## 10. Implemented RTL Blocks

### 10.1 axis_preload_engine

Implemented module:

```text
rtl/subsystem/axis_preload_engine.sv
```

Role:

```text
integrates:
    axi_mm2s_dma
    axis_async_fifo
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

Additional implementation notes:

- uses request/done toggle synchronization across `dma_clk` and `core_clk`
- starts MM2S only after the core side has accepted the request
- injects a synthetic TLAST poison beat after MM2S-side error so the core-side loader cannot hang indefinitely waiting for TLAST
- reports errors back to the dma-side `axis_load_error`

### 10.2 axis_scratchpad_write_adapter

Implemented module:

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
- checks BRESP
- checks BID
- reports write response error
- provides backpressure through `wr_ready`
- tracks accepted and completed writes

### 10.3 scratchpad_port1_owner_mux

Implemented module:

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

- routes stream preload writes to Port1 during stream load
- routes GEMM scratchpad adapter to Port1 otherwise
- flags illegal overlap between stream load and GEMM busy
- keeps GEMM path unchanged when stream preload is disabled

### 10.4 axis_async_fifo

Implemented module:

```text
rtl/subsystem/axis_async_fifo.sv
```

Role:

```text
AXI-Stream valid/ready async FIFO wrapper
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
- exposes `empty/full` and level debug status
- uses Gray-code pointer CDC

---

## 11. Top-Level Integration

### 11.1 External Source AXI Port

The subsystem now has an AXI-MM source read interface for the stream preload path.

Naming:

```text
axis_src_axi_ar*
axis_src_axi_r*
```

This is separate from the existing DMA load source model and separate from the S2MM destination write model.

### 11.2 Control Interface Fields

Added to `ai_accel_subsys_ctrl_if`:

```systemverilog
logic                  axis_load_start;
logic [ADDR_WIDTH-1:0] axis_src_base_addr;
logic [ADDR_WIDTH-1:0] axis_dst_base_addr;
logic [31:0]           axis_load_beats;

logic                  axis_load_busy;
logic                  axis_load_done;
logic                  axis_load_error;
```

AXI-Stream source RRESP injection control was also added for error testing:

```systemverilog
task automatic axis_src_set_rresp_error(
    input bit        enable,
    input int signed beat_index
);
```

### 11.3 UVM Top Model

Added to `ai_accel_subsys_uvm_top.sv`:

```text
AXI source memory responder for axis_src_axi_ar/r
```

V1 reuses:

```text
ctrl_if.dma_src_mem[]
```

as the source storage for AXI-Stream preload payloads.

Reason:

- less testbench duplication
- easier comparison with existing DMA load tests
- same A/B payload generation helper can be reused

---

## 12. Error Handling

### 12.1 MM2S Errors

The stream preload operation fails if `axi_mm2s_dma` reports:

- zero `xfer_len_beats`
- unaligned source address
- AXI `RRESP` error
- unexpected `RID`
- missing or invalid `RLAST`

### 12.2 Loader Errors

The stream preload operation fails if `axi_stream_loader` reports:

- unaligned destination address
- `TLAST` earlier than `expected_beats`
- missing `TLAST` at `expected_beats`
- capture capacity exceeded

### 12.3 Scratchpad Write Errors

The stream preload operation fails if `axis_scratchpad_write_adapter` receives:

- AXI `BRESP` error from scratchpad Port1 write
- unexpected `BID`

### 12.4 Busy/Overlap Errors

The stream preload operation should fail or be rejected if:

- start while `axis_load_busy`
- start while `acc_busy`
- GEMM start while `axis_load_busy`
- illegal Port1 overlap is detected

Current full-regression AXIS error coverage includes zero-beat, unaligned source, unaligned destination, RRESP injection, and recovery. Additional busy/overlap and BRESP-specific directed tests remain possible future extensions.

---

## 13. Verification Plan and Completed Results

### 13.1 Unit-Level Tests

Recommended unit tests remain:

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

Current verification priority is subsystem-level coverage.

### 13.2 Subsystem Smoke Test

Implemented test:

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

Completed cases:

```text
CASE_ID 100 PASS
CASE_ID 101 PASS
RUN_ALL PASS: 100 -> 101 -> 105 -> 5 -> 400 -> 401 -> 402 -> 403
```

### 13.3 Subsystem Error Test

Implemented test:

```text
ai_accel_subsys_axis_stream_preload_error_test
```

Completed coverage:

- zero `axis_load_beats`
- unaligned source address
- unaligned destination address
- source AXI RRESP error
- valid AXI preload recovery after errors
- valid GEMM + DMA store recovery after errors
- scoreboard result compare after recovery
- ctrl/result pairing after recovery

### 13.4 Subsystem Stress Test

Implemented test:

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

Implemented knobs:

```text
AXIS_STRESS_JOB_COUNT
AXIS_STRESS_SEED
AXIS_STRESS_RANDOM
AXIS_STRESS_GAP_CYCLES
```

Completed runs:

```text
8-job full-regression stress  PASS
20-job manual/nightly stress  PASS
```

### 13.5 CDC Regression

Implemented clock-ratio sanity:

```text
DMA_CLK_PERIOD_NS  = 10
CORE_CLK_PERIOD_NS = 13
```

Completed coverage:

- stream data crosses async FIFO
- stream loader runs in core domain
- preload done/error returns to dma domain
- GEMM starts only after stream preload completes
- 8 repeated AXIS preload -> GEMM -> DMA store jobs pass under non-default clock ratio

---


### 13.6 P13 C RMW Accumulation Compatibility

The AXI-Stream load-store path was validated with the P13 C RMW accumulation recipe.

P13 AXI-Stream representative recipe:

```text
CASE_ID=211 : M=8, N=16, K_total=16
External K partition: 8 + 8
Job 0: accumulate_enable=0
Job 1: accumulate_enable=1
```

Flow:

```text
for each partial job:
  AXI-Stream preload A_part into scratchpad
  AXI-Stream preload B_part into scratchpad
  launch GEMM with per-job accumulate_enable

after the final partial job:
  DMA store final C
  scoreboard compare
```

P13 AXI-Stream validation completed:

```text
AXI-Stream load-store CASE_ID=211 PASS
Representative full-regression C RMW AXI-Stream item PASS
Full regression after P13G 82/82 PASS
```

## 14. Regression Plan and Current Status

Baseline before AXI-Stream frontend:

```text
TOTAL : 25
PASS  : 25
FAIL  : 0
```

Completed staged regression additions:

### Stage A: AXIS preload smoke

```text
+1 item
Full regression: 26 / 26 PASS
```

### Stage B: AXIS preload error/recovery

```text
+1 item
Full regression: 27 / 27 PASS
```

### Stage C: AXIS load-store stress

```text
+1 item
Full regression: 28 / 28 PASS
```

### Stage D: AXIS CDC clock-ratio sanity

```text
+1 item
Full regression: 29 / 29 PASS
```

Current full regression baseline at AXI-Stream V1 closure:

```text
TOTAL : 29
PASS  : 29
FAIL  : 0
```


Current project status after P17H closure:

```text
Descriptor Fetch P17H: Memory-Backed Recipe Descriptor Fetch Regression Completed
Full regression: 105/105 PASS
```

The AXI-Stream frontend remains compatible with the P13 C RMW accumulation path. AXI-Stream preload supplies compact A/B partial-job payloads through scratchpad, while GEMM C RMW old-C reads and C writes remain scratchpad-backed.


---

## 15. Acceptance Criteria

The AXI-Stream frontend milestone is complete.

Completed criteria:

1. Existing 25/25 regression remained passing after AXIS integration.
2. AXI MM2S can stream source memory payloads.
3. AXI-Stream async FIFO transfers `{tlast, tdata}` across clock domains.
4. AXI stream loader writes A/B payloads into scratchpad.
5. GEMM consumes stream-preloaded A/B from scratchpad.
6. DMA store exports C to destination memory.
7. Destination memory compare passes.
8. Scoreboard result compare passes.
9. Ctrl/result pairing passes.
10. Error/recovery test passes.
11. AXI-Stream CDC clock-ratio sanity passes.
12. No GEMM compute datapath rewrite was required.
13. No BRAM interface semantic change was required.
14. P13 C RMW accumulation is compatible with AXI-Stream load-store representative `CASE_ID=211`.

---

## 16. Implementation Sequence

Completed RTL/UVM implementation order:

```text
1. Confirm existing axi_mm2s_dma.sv compiles in current project.
2. Confirm existing axi_stream_loader.sv compiles in current project.
3. Add axis_scratchpad_write_adapter.sv.
4. Add scratchpad_port1_owner_mux.sv.
5. Add axis_async_fifo.sv.
6. Add axis_preload_engine.sv.
7. Integrate axis_preload_engine into ai_accel_subsys.sv.
8. Extend ai_accel_subsys_ctrl_if.sv.
9. Extend ai_accel_subsys_uvm_top.sv with stream source responder.
10. Add ai_accel_subsys_axis_stream_preload_smoke_test.sv.
11. Add ai_accel_subsys_axis_stream_preload_error_test.sv.
12. Add ai_accel_subsys_axis_stream_load_store_stress_test.sv.
13. Add AXIS preload smoke to full regression.
14. Add AXIS preload error/recovery to full regression.
15. Add AXIS load-store stress to full regression.
16. Add AXIS CDC clock-ratio sanity to full regression.
```

---

## 17. Useful Single-Test Runs

### AXI-Stream preload RUN_ALL

```tcl
set UVM_TEST ai_accel_subsys_axis_stream_preload_smoke_test
set ENABLE_RESULT_CHECK 1
set RUN_ALL 1
do run_uvm.tcl
```

### AXI-Stream preload error/recovery

```tcl
set UVM_TEST ai_accel_subsys_axis_stream_preload_error_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 100
do run_uvm.tcl
```

### AXI-Stream load-store stress, full-regression version

```tcl
set UVM_TEST ai_accel_subsys_axis_stream_load_store_stress_test
set ENABLE_RESULT_CHECK 1
set AXIS_STRESS_JOB_COUNT 8
set AXIS_STRESS_SEED 20260502
set AXIS_STRESS_RANDOM 1
set AXIS_STRESS_GAP_CYCLES 10
do run_uvm.tcl
```

### AXI-Stream load-store stress, manual/nightly version

```tcl
set UVM_TEST ai_accel_subsys_axis_stream_load_store_stress_test
set ENABLE_RESULT_CHECK 1
set AXIS_STRESS_JOB_COUNT 20
set AXIS_STRESS_SEED 20260502
set AXIS_STRESS_RANDOM 1
set AXIS_STRESS_GAP_CYCLES 10
do run_uvm.tcl
```

### AXI-Stream load-store CDC sanity

```tcl
set UVM_TEST ai_accel_subsys_axis_stream_load_store_stress_test
set ENABLE_RESULT_CHECK 1
set AXIS_STRESS_JOB_COUNT 8
set AXIS_STRESS_SEED 20260502
set AXIS_STRESS_RANDOM 1
set AXIS_STRESS_GAP_CYCLES 10
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 13
do run_uvm.tcl
```

---

## 18. Future Option B: Direct Stream GEMM Frontend

After Option A is preserved as a stable baseline, a direct stream GEMM frontend can be considered.

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

Option B should not begin unless the current 29/29 Option A regression baseline remains preserved.


### AXI-Stream load-store, 4-lane + C RMW CASE_ID=211

```tcl
set UVM_TEST ai_accel_subsys_axis_stream_load_store_stress_test
set ENABLE_RESULT_CHECK 1
set CASE_ID 211
set AXIS_STRESS_JOB_COUNT 1
set AXIS_STRESS_RANDOM 0
set AXIS_STRESS_GAP_CYCLES 10
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
