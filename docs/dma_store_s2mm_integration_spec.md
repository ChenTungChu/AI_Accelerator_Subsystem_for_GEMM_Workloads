# DMA Store / S2MM Integration Spec

## 1. Purpose

This document defines the **DMA Store / S2MM result path** milestone for the AI Accelerator Subsystem.

The subsystem now supports the following verified scratchpad-based DMA data-movement loop:

```text
DMA load A/B
    -> scratchpad
    -> GEMM compute
    -> C written back to scratchpad
    -> DMA store C to destination memory
    -> destination memory compare / scoreboard
```

This closes the first basic subsystem DMA loop:

```text
MM2S-style load into scratchpad
GEMM compute
S2MM-style store out of scratchpad
```

This milestone does **not** change the GEMM compute microarchitecture and does **not** modify the stable `axi_mm_dual_port_bram` model.

---

## 2. Current Baseline

Current verified baseline:

```text
Full UVM regression: 24 / 24 PASS
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
- DMA store / S2MM smoke path
- DMA store / S2MM error recovery path
- destination AXI BRESP error recovery
- scoreboard result checking
- ctrl/result pairing

Known design style:

```text
DMA load/store paths are in dma_clk.
GEMM compute path is in core_clk.
Scratchpad is the memory boundary.
External control/status observation is in dma_clk.
```

---

## 3. Scope of This Milestone

### 3.1 Included

This milestone includes:

- `dma_store_engine.sv`
- scratchpad C-region read through Port0 in `dma_clk`
- destination AXI-MM write master port
- destination memory model in UVM top/testbench
- DMA store control/status signals
- store smoke verification
- store error/recovery verification
- integration with existing result bridge and scoreboard
- full regression integration

### 3.2 Not Included

This milestone does not include:

- direct AXI-Stream feeding GEMM
- GEMM microarchitecture rewrite
- tiling or multi-MAC datapath
- full AXI-Lite CSR register block
- cache / coherent memory behavior
- production-quality DMA descriptor engine
- arbitrary outstanding AXI transaction support
- fully generic unaligned S2MM source/destination transfers

---

## 4. High-Level Architecture

Implemented S2MM architecture:

```text
dma_clk domain
---------------------------------------------------------
scratchpad Port0 read
    -> dma_store_engine
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

The store path runs after GEMM has completed. It does not run concurrently with GEMM in the current baseline.

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

## 6. Implemented RTL Blocks

### 6.1 DMA Store Engine

Implemented module:

```text
rtl/subsystem/dma_store_engine.sv
```

The first version uses the direct store engine architecture:

```text
dma_store_engine
    - issues AXI-MM reads to scratchpad Port0
    - captures RDATA/RRESP
    - issues AXI-MM writes to destination memory
    - tracks byte count / last beat / errors
```

Current behavior:

- one store job at a time
- single outstanding scratchpad read
- single outstanding destination write
- single-beat AXI transactions
- byte-count based transfer length
- partial final beat supported through `WSTRB`
- `RRESP` and `BRESP` checked
- `store_done` is a one-cycle pulse
- `store_error` reports invalid argument or bus response error

### 6.2 Port0 Owner Mux

Updated module:

```text
rtl/subsystem/scratchpad_port0_owner_mux.sv
```

Port0 ownership now supports:

```text
HOST
DMA_LOAD
DMA_STORE
```

Implemented owner policy:

```text
HOST      : no DMA load/store active
DMA_LOAD  : dma_load_busy  = 1
DMA_STORE : dma_store_busy = 1
```

Illegal condition:

```text
dma_load_busy && dma_store_busy
```

This condition is checked as an error in simulation.

### 6.3 Top-Level Integration

Updated module:

```text
rtl/top/ai_accel_subsys.sv
```

The top-level subsystem now includes:

- DMA store control/status
- DMA store engine instance
- scratchpad Port0 read routing for DMA store
- destination AXI-MM write master port

---

## 7. Port0 Ownership

Port0 owner routing:

```text
HOST:
  host AW/W/B/AR/R <-> BRAM Port0

DMA_LOAD:
  dma_load AW/W/B -> BRAM Port0
  read path disabled

DMA_STORE:
  dma_store AR/R -> BRAM Port0
  write path disabled
```

Host access is blocked while either DMA operation owns Port0.

No BRAM interface semantic change was required.

---

## 8. DMA Store Control Interface

Implemented control/status signals:

```systemverilog
logic                  dma_store_start;
logic [ADDR_WIDTH-1:0] dma_store_src_base_addr;  // scratchpad C base
logic [ADDR_WIDTH-1:0] dma_store_dst_base_addr;  // destination memory base
logic [31:0]           dma_store_byte_count;

logic                  dma_store_busy;
logic                  dma_store_done;
logic                  dma_store_error;
```

### 8.1 Byte Count Policy

S2MM uses byte count instead of beat count.

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

Current first-version rules:

```text
dma_store_src_base_addr must be DATA_WIDTH-byte aligned.
dma_store_dst_base_addr must be DATA_WIDTH-byte aligned.
dma_store_byte_count must be non-zero.
```

The final beat may be partial and uses `WSTRB`.

---

## 9. Destination AXI-MM Write Interface

The top-level subsystem includes a destination AXI-MM write master port:

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

Current assumptions:

```text
single outstanding write
single-beat writes
no write interleaving
BRESP checked for every completed write
```

---

## 10. Destination Memory Model

The UVM top includes a byte-addressed destination memory model:

```systemverilog
logic [7:0] dma_dst_mem [0:DMA_DST_MEM_BYTES-1];
```

Implemented helper tasks/functions in `ai_accel_subsys_ctrl_if` include:

```systemverilog
task dma_dst_mem_clear();
task dma_dst_mem_write_byte(addr, data);
function logic [7:0] dma_dst_mem_read_byte(addr);
function logic [31:0] dma_dst_mem_read_word32(addr);
function int signed dma_dst_mem_read_s32(addr);
task dma_dst_mem_read_s32_array(base_addr, word_count, output int signed values[]);
```

Implemented destination memory model features:

- AW/W/B handshake
- WSTRB-based byte writes
- out-of-range detection
- optional BRESP error injection

Destination memory size:

```text
DMA_DST_MEM_BYTES = 4096
```

---

## 11. Store Engine Behavior

### 11.1 Normal Store

Given:

```text
src_base_addr  = scratchpad C base
dst_base_addr  = destination memory base
byte_count     = C_words * 4
```

The store engine:

1. accepts `dma_store_start` when idle
2. validates input arguments
3. asserts `dma_store_busy`
4. reads scratchpad C data from Port0
5. writes the data into destination memory through AXI-MM write
6. uses correct `WSTRB` on the final beat
7. checks scratchpad `RRESP`
8. checks destination `BRESP`
9. asserts `dma_store_done`
10. deasserts `dma_store_busy`
11. asserts `dma_store_error` only if an error occurred

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

`dma_store_done` is a one-cycle `dma_clk` pulse.

### 11.3 Error Conditions

Verified error conditions:

- `byte_count == 0`
- source address not DATA_WIDTH-byte aligned
- destination address not DATA_WIDTH-byte aligned
- destination memory BRESP error
- start while busy, optional/manual run

Planned/available extension:

- source scratchpad RRESP error
- out-of-range destination memory access
- mid-store reset recovery

---

## 12. Test Sequence

Implemented DMA-load + GEMM + DMA-store sequence:

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

This keeps the scratchpad model and replaces host readback C with DMA store C for the S2MM path.

---

## 13. Verification Status

### 13.1 Compile

```tcl
do compile_uvm.tcl
```

Status:

```text
PASS
```

### 13.2 DMA Store Smoke Test

Implemented test:

```text
ai_accel_subsys_dma_store_smoke_test
```

Verified RUN_ALL recipe:

```text
100 -> 101 -> 105 -> 5 -> 400 -> 401 -> 402 -> 403
```

Purpose:

- verify basic S2MM C result movement
- verify final-beat WSTRB for small/partial C byte counts
- verify configurable C source base
- verify result compare using destination memory
- verify scoreboard result pairing

Status:

```text
PASS
```

### 13.3 DMA Store Error Test

Implemented test:

```text
ai_accel_subsys_dma_store_error_test
```

Verified default error cases:

- zero `byte_count`
- unaligned scratchpad source address
- unaligned destination address
- destination BRESP error injection
- valid recovery store after errors

Optional/manual verified case:

- store start while busy

Status:

```text
PASS
```

### 13.4 Full Regression

Current full regression:

```text
TOTAL : 24
PASS  : 24
FAIL  : 0
```

---

## 14. Regression Plan

Current regression status:

```text
Stage 1: Bring-up                  DONE
Stage 2: Store smoke RUN_ALL       DONE
Stage 3: Store error / recovery    DONE
Stage 4: Load + Store stress       NEXT
```

Current full-regression additions:

```text
ai_accel_subsys_dma_store_smoke_test RUN_ALL
ai_accel_subsys_dma_store_error_test default
```

Recommended next regression item:

```text
ai_accel_subsys_dma_load_store_stress_test
```

Purpose:

- repeat DMA load -> GEMM -> DMA store
- vary case ID and base address
- verify ctrl/result pairing across multiple jobs
- verify no stale destination memory data is used

---

## 15. Scoreboard Integration

The store smoke test reads destination memory into the same expected/actual result item format and publishes through the existing result bridge.

Current implementation:

```text
Reuse existing result bridge.
Keep result payload format stable.
Use destination memory as actual C source.
```

This allows the existing scoreboard to check:

- result compare correctness
- ctrl/result pairing
- control profile consistency
- latency sanity

Possible future metadata extension:

```text
result_source = HOST_READBACK / DMA_STORE_DST_MEM
dst_base_addr
store_byte_count
```

This is not required for the current verified baseline.

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

No additional GEMM CDC was required.

---

## 17. Known Warning Policy

The existing Questa `vsim-3838` warning related to `axi_mm_if` clocking-block implicit drivers and the Port0 owner mux remains a known simulator/interface warning.

This S2MM milestone did not modify the shared BRAM `axi_mm_if.sv` to remove this warning.

Current policy:

```text
Known warning accepted.
Functional regression passes.
No BRAM interface semantic change required.
```

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

Current status:

```text
All acceptance criteria met.
Full UVM regression: 24 / 24 PASS
```

---

## 19. Future Extensions

After S2MM is stable, possible next milestones are:

### 19.1 DMA Load + Store Stress

```text
DMA load A/B
    -> GEMM
    -> DMA store C
    -> destination memory compare
```

This is the recommended next step.

### 19.2 Direct AXI-Stream GEMM Frontend

```text
DMA MM2S
    -> AXI-Stream async FIFO
    -> GEMM stream frontend
    -> compute
```

This is a larger architecture change and should remain separate from S2MM.

### 19.3 Descriptor-Based DMA

Add descriptor fields:

- source address
- destination address
- byte count
- operation type
- control flags
- completion status

### 19.4 Performance-Oriented GEMM

After DMA load/store and CDC boundaries are stable:

- tiled GEMM
- multi-MAC lanes
- local buffering
- performance counters
- throughput-oriented verification
