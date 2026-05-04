# DMA Store / S2MM Integration Spec

## 1. Purpose

This document defines the next subsystem milestone after the verified DMA-load CDC baseline.

The current subsystem already supports:

```text
DMA load A/B
    -> scratchpad
    -> GEMM compute
    -> C written back to scratchpad
    -> host readback C
    -> scoreboard compare
```

The goal of this milestone is to add a **DMA store / S2MM result path**:

```text
DMA load A/B
    -> scratchpad
    -> GEMM compute
    -> C written back to scratchpad
    -> DMA store C to destination memory
    -> destination memory compare / scoreboard
```

This closes the basic DMA data-movement loop:

```text
MM2S-style load into scratchpad
GEMM compute
S2MM-style store out of scratchpad
```

This milestone should not change the GEMM compute microarchitecture and should not modify the stable `axi_mm_dual_port_bram` model.

---

## 2. Current Baseline

Current verified baseline:

```text
Full UVM regression: 22 / 22 PASS
```

Implemented and verified:

- host-primary GEMM path
- DMA load smoke path
- DMA load error / recovery path
- source AXI RRESP error recovery
- DMA load stress regression
- configurable clock-period support
- CDC clock-ratio sanity regression
- GEMM control/status CDC hardening
- scoreboard result checking
- ctrl/result pairing

Known design style:

```text
DMA load path is in dma_clk.
GEMM compute path is in core_clk.
Scratchpad is the memory boundary.
External control/status observation is in dma_clk.
```

---

## 3. Scope of This Milestone

### 3.1 Included

This milestone includes:

- new DMA store / S2MM result path
- scratchpad C-region read through Port0 in `dma_clk`
- destination AXI-MM write master
- destination memory model in UVM top/testbench
- DMA store control/status signals
- basic store smoke verification
- store error/recovery verification
- integration with existing scoreboard/result flow

### 3.2 Not Included

This milestone does not include:

- direct AXI-Stream feeding GEMM
- GEMM microarchitecture rewrite
- tiling or multi-MAC datapath
- full AXI-Lite CSR register block
- cache / coherent memory behavior
- production-quality DMA descriptor engine
- arbitrary outstanding AXI transaction support

---

## 4. High-Level Architecture

Recommended first S2MM architecture:

```text
dma_clk domain
---------------------------------------------------------
scratchpad Port0 read
    -> DMA store engine
    -> destination AXI-MM write master
    -> destination memory model


core_clk domain
---------------------------------------------------------
GEMM writes C to scratchpad Port1


software / testbench sequencing
---------------------------------------------------------
DMA load A
DMA load B
start GEMM
wait acc_done
DMA store C
compare destination memory
```

The store path runs after GEMM has completed. It does not run concurrently with GEMM in the first version.

---

## 5. Clock Domain Ownership

### 5.1 DMA / Host Domain

Clock:

```text
dma_clk
```

Owns:

- DMA load engine
- DMA store engine
- scratchpad Port0 owner mux
- external host AXI0 path
- destination AXI-MM write master
- destination memory model interface in testbench
- DMA store status:
  - `dma_store_busy`
  - `dma_store_done`
  - `dma_store_error`

### 5.2 Core Domain

Clock:

```text
core_clk
```

Owns:

- GEMM core
- GEMM scratchpad adapter
- scratchpad Port1
- raw GEMM compute status

### 5.3 Data Boundary

The current data boundary remains the scratchpad.

C data is produced by GEMM in the `core_clk` domain and becomes visible to the DMA-side store path through scratchpad memory after `acc_done` has been synchronized back to the `dma_clk` domain.

---

## 6. Proposed RTL Blocks

### 6.1 New Top-Level Concept

Add a DMA store path to `ai_accel_subsys`:

```text
scratchpad Port0 read side
    -> dma_store_engine
    -> destination AXI-MM write master
```

### 6.2 New or Updated RTL Modules

Recommended modules:

```text
rtl/dma/dma_store_engine.sv
rtl/dma/axi_s2mm_dma.sv             optional if using stream split
rtl/subsystem/scratchpad_port0_owner_mux.sv updated or replaced
```

Two implementation styles are acceptable.

#### Option A: Direct Store Engine

```text
dma_store_engine
    - issues AXI-MM reads to scratchpad Port0
    - captures RDATA/RRESP
    - issues AXI-MM writes to destination memory
    - tracks byte count / last beat / errors
```

Pros:

- simplest first implementation
- fewer moving pieces
- good for subsystem bring-up

Cons:

- less reusable as a generic stream block

#### Option B: Stream-Split Store Path

```text
scratchpad_mm2s_reader
    -> AXI-Stream
    -> axi_s2mm_dma
    -> destination AXI-MM write
```

Pros:

- closer to the long-term AXI-Stream roadmap
- `axi_s2mm_dma` can be reused later

Cons:

- more modules
- more handshake points
- more verification burden

Recommended first version:

```text
Option A is preferred for v3.2.
Option B can be a later refactor once S2MM behavior is verified.
```

---

## 7. Port0 Ownership

Current Port0 ownership is:

```text
dma_load_busy = 0 -> host owns Port0
dma_load_busy = 1 -> DMA load engine owns Port0
```

The S2MM milestone requires a third owner:

```text
HOST
DMA_LOAD
DMA_STORE
```

Recommended owner policy:

```text
HOST      : no DMA load/store active
DMA_LOAD  : dma_load_busy  = 1
DMA_STORE : dma_store_busy = 1
```

Illegal condition:

```text
dma_load_busy && dma_store_busy
```

This must never happen.

Recommended implementation:

```systemverilog
typedef enum logic [1:0] {
    PORT0_OWNER_HOST,
    PORT0_OWNER_DMA_LOAD,
    PORT0_OWNER_DMA_STORE
} port0_owner_e;
```

Owner selection priority should reject simultaneous load/store starts instead of silently prioritizing one.

### 7.1 Required Port0 Mux Expansion

The current mux supports host access and DMA load write access.

S2MM requires Port0 read access from DMA store engine:

- AR channel
- R channel

Therefore, the Port0 owner mux must be extended to route:

```text
Host AW/W/B/AR/R
DMA load AW/W/B
DMA store AR/R
```

First version expectation:

```text
DMA load uses Port0 write channels.
DMA store uses Port0 read channels.
Host is blocked from Port0 while either DMA operation is active.
```

No BRAM interface semantic change should be required.

---

## 8. DMA Store Control Interface

Recommended new control/status signals:

```systemverilog
logic                  dma_store_start;
logic [ADDR_WIDTH-1:0] dma_store_src_base_addr;  // scratchpad C base
logic [ADDR_WIDTH-1:0] dma_store_dst_base_addr;  // destination memory base
logic [31:0]           dma_store_byte_count;

logic                  dma_store_busy;
logic                  dma_store_done;
logic                  dma_store_error;
```

### 8.1 Why Use Byte Count

Use byte count instead of beat count for S2MM.

Reason:

- C elements are 32-bit.
- DATA_WIDTH is currently 64-bit.
- some result sizes are not naturally 64-bit beat aligned.
- byte count allows correct final-beat `WSTRB` generation.

Example:

```text
CASE_ID 100: C_words = 1 -> C_bytes = 4
DATA_WIDTH  = 64      -> one 8-byte beat with WSTRB = 0x0F
```

### 8.2 Alignment Rules

Recommended first version:

```text
dma_store_src_base_addr must be DATA_WIDTH-byte aligned.
dma_store_dst_base_addr must be DATA_WIDTH-byte aligned.
dma_store_byte_count must be non-zero.
```

The final beat may be partial and should use `WSTRB`.

Later versions may support unaligned source/destination addresses.

---

## 9. Destination AXI-MM Write Interface

Add a destination AXI-MM write master port to `ai_accel_subsys`.

Recommended signals:

```systemverilog
output logic [ID_WIDTH-1:0]   dma_dst_axi_awid;
output logic [ADDR_WIDTH-1:0] dma_dst_axi_awaddr;
output logic [7:0]            dma_dst_axi_awlen;
output logic [2:0]            dma_dst_axi_awsize;
output logic [1:0]            dma_dst_axi_awburst;
output logic                  dma_dst_axi_awvalid;
input  logic                  dma_dst_axi_awready;

output logic [DATA_WIDTH-1:0]   dma_dst_axi_wdata;
output logic [DATA_WIDTH/8-1:0] dma_dst_axi_wstrb;
output logic                    dma_dst_axi_wlast;
output logic                    dma_dst_axi_wvalid;
input  logic                    dma_dst_axi_wready;

input  logic [ID_WIDTH-1:0]   dma_dst_axi_bid;
input  logic [1:0]            dma_dst_axi_bresp;
input  logic                  dma_dst_axi_bvalid;
output logic                  dma_dst_axi_bready;
```

First version assumptions:

```text
single outstanding write
INCR burst or single-beat writes
no write interleaving
BRESP checked for every completed write
```

---

## 10. Destination Memory Model

The UVM top should include a byte-addressed destination memory model:

```systemverilog
byte unsigned dma_dst_mem [DMA_DST_MEM_BYTES];
```

Recommended helper tasks in `ai_accel_subsys_ctrl_if`:

```systemverilog
task dma_dst_mem_clear();
task dma_dst_mem_write_byte(addr, data);
function byte unsigned dma_dst_mem_read_byte(addr);
task dma_dst_mem_read_s32_array(base_addr, word_count, output int signed values[]);
```

Recommended size:

```text
DMA_DST_MEM_BYTES = 4096
```

The destination memory model should support:

- AW/W/B handshake
- WSTRB-based byte writes
- out-of-range detection
- optional BRESP error injection

---

## 11. Store Engine Behavior

### 11.1 Normal Store

Given:

```text
src_base_addr  = scratchpad C base
dst_base_addr  = destination memory base
byte_count     = C_words * 4
```

The store engine should:

1. accept `dma_store_start` when idle
2. validate input arguments
3. assert `dma_store_busy`
4. read scratchpad C data from Port0
5. write the data into destination memory through AXI-MM write
6. use correct `WSTRB` on the final beat
7. check scratchpad `RRESP`
8. check destination `BRESP`
9. assert `dma_store_done`
10. deassert `dma_store_busy`
11. assert `dma_store_error` only if an error occurred

### 11.2 Store Done

Successful completion:

```text
dma_store_done  = 1
dma_store_error = 0
```

Error completion:

```text
dma_store_done  = 1
dma_store_error = 1
```

`dma_store_done` should be a one-cycle `dma_clk` pulse.

### 11.3 Error Conditions

Recommended first error conditions:

- `byte_count == 0`
- source address not DATA_WIDTH-byte aligned
- destination address not DATA_WIDTH-byte aligned
- source scratchpad RRESP error
- destination memory BRESP error
- out-of-range destination memory access
- start while busy

The first version does not need to support recovery from reset in the middle of an active store unless a test already exercises it.

---

## 12. Test Sequence

Recommended DMA-load + GEMM + DMA-store sequence:

```text
1. Clear scratchpad C through host path.
2. Clear destination memory model.
3. Preload DMA source memory with A/B.
4. DMA load A into scratchpad.
5. DMA load B into scratchpad.
6. Start GEMM.
7. Wait acc_done.
8. Start DMA store from scratchpad C to destination memory.
9. Wait dma_store_done.
10. Read destination memory model.
11. Compare against software reference.
12. Publish result payload to scoreboard.
```

This keeps the current scratchpad model and simply replaces host readback C with DMA store C.

---

## 13. Verification Plan

### 13.1 Compile

```tcl
do compile_uvm.tcl
```

Pass criteria:

- compile passes
- no new modport/interface errors
- no new CDC wiring errors

### 13.2 DMA Store Smoke Test

Proposed test:

```text
ai_accel_subsys_dma_store_smoke_test
```

Recommended first cases:

```text
CASE_ID 100
CASE_ID 101
CASE_ID 105
CASE_ID 5
```

Purpose:

- verify basic S2MM C result movement
- verify final-beat WSTRB for small/odd byte counts
- verify scoreboard result compare using destination memory

### 13.3 Configurable-Base Store Cases

Recommended cases:

```text
CASE_ID 400
CASE_ID 401
CASE_ID 402
CASE_ID 403
```

Purpose:

- verify C source base can move
- verify destination base can move
- verify store path does not assume fixed C address

### 13.4 DMA Store Error Test

Proposed test:

```text
ai_accel_subsys_dma_store_error_test
```

Recommended error cases:

- zero `byte_count`
- unaligned scratchpad source address
- unaligned destination address
- destination BRESP error injection
- store start while busy
- recovery store after error

### 13.5 DMA Load + Store Stress

Proposed test:

```text
ai_accel_subsys_dma_load_store_stress_test
```

Recommended first stress knobs:

```tcl
set STORE_STRESS_JOB_COUNT 8
set STORE_STRESS_SEED 20260502
set STORE_STRESS_RANDOM 1
set STORE_STRESS_GAP_CYCLES 10
```

Purpose:

- repeat DMA load -> GEMM -> DMA store
- vary case ID and base address
- verify ctrl/result pairing across multiple jobs
- verify no stale destination memory data is used

This can be added after smoke and error tests are stable.

---

## 14. Regression Plan

Recommended staged regression growth:

### Stage 1: Bring-Up

```text
compile
dma_store_smoke CASE_ID=100
```

Expected regression total increase:

```text
22 -> 23
```

### Stage 2: Store Smoke Expansion

Add store smoke cases:

```text
100, 101, 105, 5
```

Expected regression total increase depends on grouping.

Preferred approach:

```text
one RUN_ALL-style store smoke test item
```

### Stage 3: Store Error / Recovery

Add:

```text
ai_accel_subsys_dma_store_error_test
```

### Stage 4: Load + Store Stress

Add:

```text
ai_accel_subsys_dma_load_store_stress_test
```

This may be full regression or optional/manual depending on runtime.

---

## 15. Scoreboard Integration

The result payload should represent the final C data as observed in destination memory.

Recommended options:

### Option A: Reuse Existing Result Bridge

The store test reads destination memory into the same expected/actual result item format and publishes through the existing result bridge.

Preferred for first version.

### Option B: Add Store-Specific Result Metadata

Extend result item metadata with:

```text
result_source = HOST_READBACK / DMA_STORE_DST_MEM
dst_base_addr
store_byte_count
```

Recommended after first smoke pass if useful.

First version recommendation:

```text
Reuse existing result bridge and keep result payload format stable.
```

---

## 16. CDC Considerations

The DMA store engine runs in `dma_clk`.

It starts only after `acc_done` has been synchronized back into `dma_clk`.

Therefore:

```text
No new data CDC is required for the first S2MM version.
```

Reason:

- GEMM writes C through Port1 in `core_clk`.
- The scratchpad handles dual-clock memory access.
- DMA store reads C through Port0 in `dma_clk` after GEMM completion.

Control/status CDC already exists for:

- `acc_start`
- GEMM config
- `acc_done`
- `acc_busy`

No additional GEMM CDC should be required.

---

## 17. Known Warning Policy

The existing Questa `vsim-3838` warning related to `axi_mm_if` clocking-block implicit drivers and the Port0 owner mux remains a known simulator/interface warning.

This S2MM milestone should not modify the shared BRAM `axi_mm_if.sv` only to remove this warning.

No BRAM interface semantic change is expected.

---

## 18. Acceptance Criteria

The S2MM milestone is complete when:

1. DMA store engine compiles.
2. Port0 owner mux supports HOST / DMA_LOAD / DMA_STORE ownership.
3. DMA store can read scratchpad C from Port0.
4. DMA store can write C into destination memory.
5. Final-beat WSTRB is correct for partial C byte counts.
6. Destination memory compare passes.
7. Store error/recovery cases pass.
8. Existing DMA load tests still pass.
9. Existing CDC clock-ratio regression still passes.
10. Full UVM regression passes.
11. No new UVM error or fatal is introduced.
12. No BRAM interface semantic change is required.

---

## 19. Future Extensions

After S2MM is stable, possible next milestones are:

### 19.1 Direct AXI-Stream GEMM Frontend

```text
DMA MM2S
    -> AXI-Stream async FIFO
    -> GEMM stream frontend
    -> compute
```

This is a larger architecture change and should remain separate from S2MM.

### 19.2 Descriptor-Based DMA

Add descriptor fields:

- source address
- destination address
- byte count
- operation type
- control flags
- completion status

### 19.3 Performance-Oriented GEMM

After DMA load/store and CDC boundaries are stable:

- tiled GEMM
- multi-MAC lanes
- local buffering
- performance counters
- throughput-oriented verification
