# AXI-Lite CSR Control Plane Spec

## 1. Purpose

This document defines the P14A control-plane specification for the AI Accelerator Subsystem.

The subsystem already has a stable GEMM datapath and multiple validated data movement frontends.  P14 adds a lightweight software-visible control plane so a host can program, launch, poll, and observe the accelerator through control/status registers instead of driving top-level sideband control wires directly.

P14 is intentionally scoped as a minimal CSR shell.  It is not a descriptor engine, interrupt controller, software driver, or UVM RAL model.

---

## 2. Current Baseline Before P14

The current subsystem baseline includes:

```text
AXI-MM dual-port BRAM scratchpad
GEMM compute core
Host-primary scratchpad preload/readback path
DMA load path
DMA store / S2MM path
AXI-Stream preload path
Direct Stream operand preload path
Multi-lane GEMM datapath
B-cache and A-row cache operand reuse
Packed B-cache / packed A-row preload options
K / N / M tiling
C read-modify-write accumulation for partial-K jobs
Performance counters
Full UVM regression baseline passing 82/82
```

The pre-P14 external control model is sideband-based:

```text
acc_start
base_addr_a / base_addr_b / base_addr_c
dim_m / dim_n / dim_k
gemm_input_stream_mode
accumulate_enable

dma_load_start / dma_src_base_addr / dma_dst_base_addr / dma_load_beats
axis_load_start / axis_src_base_addr / axis_dst_base_addr / axis_load_beats
ds_load_start / ds_src_base_addr / ds_dst_base_addr / ds_load_beats / ds_operand_sel
dma_store_start / dma_store_src_base_addr / dma_store_dst_base_addr / dma_store_byte_count
```

P14 keeps the existing datapath subsystem intact and adds a CSR programming layer around it.

---

## 3. P14 Design Intent

P14 converts the accelerator from a testbench-driven control model into a host-programmable subsystem model.

The intended programming model is:

```text
1. Host writes configuration registers.
2. Host writes a command bit to launch one operation.
3. CSR block generates a one-cycle start pulse to the existing subsystem.
4. Existing subsystem performs the operation.
5. CSR block captures done/error pulses into sticky status bits.
6. Host polls status registers and reads performance/status counters.
```

The CSR block does not automatically schedule multi-stage jobs.  Software or the UVM sequence remains responsible for launching DMA load, GEMM, and DMA store in the desired order.

---

## 4. P14 Scope

### 4.1 Included

P14 includes:

```text
AXI-Lite-compatible CSR slave
CSR register map
RW configuration registers
write-one-pulse command register
live busy status bits
sticky done bits
sticky error bits
performance counter snapshot registers
CSR-controlled host-primary GEMM smoke flow
CSR-controlled DMA / AXI-Stream / Direct Stream representative flows
```

### 4.2 Not Included

P14 does not include:

```text
Interrupt output
UVM RAL model
Linux driver
C software driver
Descriptor queue
Automatic job scheduler
Multi-job hardware command processor
Cache-coherent host interface
AXI interconnect / NoC integration
Double buffering
Streaming GEMM compute rewrite
```

These can be future milestones after the CSR control plane is stable.

---

## 5. Recommended RTL Partition

P14 should avoid destabilizing the existing `ai_accel_subsys.sv` datapath top.

Recommended new RTL:

```text
rtl/interface/axi_lite_if.sv
rtl/csr/ai_accel_csr_regs.sv
rtl/top/ai_accel_subsys_csr_top.sv
```

Recommended partition:

```text
ai_accel_subsys_csr_top
    AXI-Lite CSR slave port
        -> ai_accel_csr_regs
            -> existing sideband control wires
                -> ai_accel_subsys
```

The existing `ai_accel_subsys.sv` remains the stable datapath subsystem.  The new CSR top wraps it.

---

## 6. Clock and Reset Policy

### 6.1 CSR Clock Domain

The CSR block is clocked by `dma_clk`.

Rationale:

```text
Existing external control inputs are dma_clk-domain control signals.
DMA load/store control already lives in dma_clk.
acc_start/config are captured in dma_clk before crossing to core_clk inside ai_accel_subsys.
```

### 6.2 Reset

CSR reset uses `dma_rst_n`.

After reset:

```text
All RW configuration registers return to default values.
All sticky done/error bits clear.
No start pulse is generated.
Performance snapshot registers clear to zero.
```

### 6.3 Performance Counter CDC Policy

The GEMM performance counters are produced by the core-side GEMM logic and are stable after GEMM completion until the next accepted GEMM start.

The CSR block should not expose raw asynchronous counter wires directly as continuously changing CSR read data.

Recommended policy:

```text
On the dma_clk-domain acc_done pulse, capture a dma_clk-domain snapshot of:
  gemm_perf_busy_cycles
  gemm_perf_mac_count
  gemm_perf_output_count

CSR performance registers read the captured snapshot.
```

This is a stable-snapshot CDC policy.  It relies on the existing subsystem contract that performance counters are stable after GEMM done and remain stable until the next accepted start.

---

## 7. AXI-Lite CSR Bus Policy

The CSR slave uses a 32-bit AXI-Lite-style programming interface.

Recommended parameters:

```systemverilog
parameter int CSR_ADDR_WIDTH = 12;
parameter int CSR_DATA_WIDTH = 32;
```

Supported behavior:

```text
Single-beat read/write transactions only
No bursts
One outstanding write transaction
One outstanding read transaction
AW and W channels may arrive independently
B response returns after both AW and W are accepted and the write is applied
AR/R handles one read at a time
```

Response policy:

```text
Valid address read/write: OKAY
Unsupported address read/write: SLVERR
Write to read-only register: OKAY, ignored
Read from write-only command register: returns zero with OKAY
```

Write strobe policy:

```text
RW registers apply byte strobes.
Command register treats any written 1 bit with at least one active strobe as a command request.
WSTRB == 0 performs no update and returns OKAY for valid addresses.
```

---

## 8. Register Access Type Definitions

The register map uses these access types:

| Type | Meaning |
|---|---|
| RO | Read-only |
| RW | Read/write storage |
| W1P | Write-one-pulse. Writing 1 generates a one-cycle internal pulse if accepted. Reads return 0. |
| W1C | Write-one-clear. Writing 1 clears the corresponding sticky bit. |
| RSVD | Reserved. Reads return 0. Writes ignored. |

---

## 9. CSR Register Map

All registers are 32-bit and word-aligned.

| Offset | Name | Access | Description |
|---:|---|---|---|
| 0x000 | `CSR_VERSION` | RO | CSR block version / feature ID |
| 0x004 | `CSR_COMMAND` | W1P | Operation launch and sticky-status clear commands |
| 0x008 | `CSR_STATUS` | RO | Live busy/status summary |
| 0x00C | `CSR_DONE_STATUS` | RO/W1C | Sticky done status |
| 0x010 | `CSR_ERROR_STATUS` | RO/W1C | Sticky error status |
| 0x014 | `CSR_MODE` | RW | GEMM mode/config bits |
| 0x018 | `CSR_CMD_REJECT_STATUS` | RO/W1C | Sticky command reject reasons |
| 0x01C | `CSR_RESERVED_01C` | RO | Reserved |
| 0x020 | `CSR_BASE_ADDR_A` | RW | GEMM A base address |
| 0x024 | `CSR_BASE_ADDR_B` | RW | GEMM B base address |
| 0x028 | `CSR_BASE_ADDR_C` | RW | GEMM C base address |
| 0x02C | `CSR_DIM_M` | RW | GEMM M dimension |
| 0x030 | `CSR_DIM_N` | RW | GEMM N dimension |
| 0x034 | `CSR_DIM_K` | RW | GEMM K dimension |
| 0x038 | `CSR_RESERVED_038` | RO | Reserved |
| 0x03C | `CSR_RESERVED_03C` | RO | Reserved |
| 0x040 | `CSR_DMA_LOAD_SRC_BASE` | RW | DMA load source base address |
| 0x044 | `CSR_DMA_LOAD_DST_BASE` | RW | DMA load scratchpad destination base address |
| 0x048 | `CSR_DMA_LOAD_BEATS` | RW | DMA load length in DATA_WIDTH beats |
| 0x04C | `CSR_RESERVED_04C` | RO | Reserved |
| 0x050 | `CSR_AXIS_SRC_BASE` | RW | AXI-Stream preload source base address |
| 0x054 | `CSR_AXIS_DST_BASE` | RW | AXI-Stream preload scratchpad destination base address |
| 0x058 | `CSR_AXIS_LOAD_BEATS` | RW | AXI-Stream preload length in DATA_WIDTH beats |
| 0x05C | `CSR_RESERVED_05C` | RO | Reserved |
| 0x060 | `CSR_DS_SRC_BASE` | RW | Direct Stream preload source base address |
| 0x064 | `CSR_DS_DST_BASE` | RW | Direct Stream operand-buffer destination/base address |
| 0x068 | `CSR_DS_LOAD_BEATS` | RW | Direct Stream preload length in DATA_WIDTH beats |
| 0x06C | `CSR_DS_CONTROL` | RW | Direct Stream operand select and options |
| 0x070 | `CSR_DMA_STORE_SRC_BASE` | RW | DMA store scratchpad source base address |
| 0x074 | `CSR_DMA_STORE_DST_BASE` | RW | DMA store destination base address |
| 0x078 | `CSR_DMA_STORE_BYTE_COUNT` | RW | DMA store byte count |
| 0x07C | `CSR_RESERVED_07C` | RO | Reserved |
| 0x080 | `CSR_PERF_BUSY_CYCLES` | RO | Captured GEMM busy-cycle count |
| 0x084 | `CSR_PERF_MAC_COUNT` | RO | Captured GEMM MAC count |
| 0x088 | `CSR_PERF_OUTPUT_COUNT` | RO | Captured GEMM output count |
| 0x08C | `CSR_RESERVED_08C` | RO | Reserved |

The initial P14A map intentionally leaves gaps for future status/debug expansion.

---

## 10. Register Bit Definitions

### 10.1 `CSR_VERSION` at 0x000

| Bits | Name | Access | Reset | Description |
|---:|---|---|---:|---|
| [31:16] | `MAJOR` | RO | 16'h0001 | CSR major version |
| [15:8] | `MINOR` | RO | 8'h00 | CSR minor version |
| [7:0] | `FEATURE_ID` | RO | 8'h14 | P14 CSR feature ID |

Recommended reset value:

```text
0x0001_0014
```

### 10.2 `CSR_COMMAND` at 0x004

This is a write-one-pulse register.  Reads return zero.

| Bit | Name | Type | Description |
|---:|---|---|---|
| 0 | `START_GEMM` | W1P | Generate one `acc_start` pulse if GEMM start is accepted |
| 1 | `START_DMA_LOAD` | W1P | Generate one `dma_load_start` pulse if accepted |
| 2 | `START_AXIS_LOAD` | W1P | Generate one `axis_load_start` pulse if accepted |
| 3 | `START_DS_LOAD` | W1P | Generate one `ds_load_start` pulse if accepted |
| 4 | `START_DMA_STORE` | W1P | Generate one `dma_store_start` pulse if accepted |
| 8 | `CLEAR_DONE` | W1P | Clear all sticky done bits |
| 9 | `CLEAR_ERROR` | W1P | Clear all sticky error bits and command reject bits |
| 10 | `CLEAR_PERF` | W1P | Clear captured performance snapshot registers |

Multiple command bits may be written in one transaction only for clear commands plus one start command.

Unsupported combinations:

```text
Multiple START_* bits in the same write
START_* in the same write as CLEAR_ERROR if errors are currently sticky
```

Unsupported combinations do not launch any operation and set `CSR_CMD_REJECT_STATUS.unsupported_combo`.

### 10.3 `CSR_STATUS` at 0x008

| Bit | Name | Access | Description |
|---:|---|---|---|
| 0 | `ACC_BUSY` | RO | GEMM/subsystem accelerator busy |
| 1 | `DMA_LOAD_BUSY` | RO | DMA load engine busy |
| 2 | `AXIS_LOAD_BUSY` | RO | AXI-Stream preload engine busy |
| 3 | `DS_LOAD_BUSY` | RO | Direct Stream preload engine busy |
| 4 | `DMA_STORE_BUSY` | RO | DMA store engine busy |
| 8 | `ANY_BUSY` | RO | OR of all live busy bits |
| 12 | `ANY_DONE` | RO | OR of all sticky done bits |
| 13 | `ANY_ERROR` | RO | OR of sticky error bits and command reject bits |
| 16 | `CSR_READY` | RO | CSR block ready for transactions |

### 10.4 `CSR_DONE_STATUS` at 0x00C

Sticky done bits are set by one-cycle done pulses from the existing subsystem and cleared by W1C writes or by `CSR_COMMAND.CLEAR_DONE`.

| Bit | Name | Type | Description |
|---:|---|---|---|
| 0 | `GEMM_DONE` | RO/W1C | GEMM/subsystem done observed |
| 1 | `DMA_LOAD_DONE` | RO/W1C | DMA load done observed |
| 2 | `AXIS_LOAD_DONE` | RO/W1C | AXI-Stream preload done observed |
| 3 | `DS_LOAD_DONE` | RO/W1C | Direct Stream preload done observed |
| 4 | `DMA_STORE_DONE` | RO/W1C | DMA store done observed |

### 10.5 `CSR_ERROR_STATUS` at 0x010

Sticky error bits are set by error outputs from the existing subsystem and cleared by W1C writes or by `CSR_COMMAND.CLEAR_ERROR`.

| Bit | Name | Type | Description |
|---:|---|---|---|
| 0 | `DMA_LOAD_ERROR` | RO/W1C | DMA load error observed |
| 1 | `AXIS_LOAD_ERROR` | RO/W1C | AXI-Stream preload error observed |
| 2 | `DS_LOAD_ERROR` | RO/W1C | Direct Stream preload error observed |
| 3 | `DMA_STORE_ERROR` | RO/W1C | DMA store error observed |
| 4 | `GEMM_ERROR_RESERVED` | RO/W1C | Reserved for future GEMM internal error |

The current GEMM datapath does not expose a dedicated GEMM error signal.  Bit 4 is reserved for forward compatibility and should read zero in P14 unless a future GEMM error output is added.

### 10.6 `CSR_MODE` at 0x014

| Bit | Name | Access | Reset | Description |
|---:|---|---|---:|---|
| 0 | `GEMM_INPUT_STREAM_MODE` | RW | 0 | 0 = scratchpad mode, 1 = Direct Stream A/B operand-buffer mode |
| 1 | `ACCUMULATE_ENABLE` | RW | 0 | GEMM C RMW accumulation control for the launched job |
| 31:2 | `RSVD` | RO | 0 | Reserved |

`GEMM_INPUT_STREAM_MODE` and `ACCUMULATE_ENABLE` are sampled by the existing subsystem when `START_GEMM` is accepted.

### 10.7 `CSR_CMD_REJECT_STATUS` at 0x018

Sticky command reject bits are set when a CSR command write cannot be accepted.  They are cleared by W1C writes or by `CSR_COMMAND.CLEAR_ERROR`.

| Bit | Name | Type | Description |
|---:|---|---|---|
| 0 | `GEMM_BUSY_REJECT` | RO/W1C | `START_GEMM` requested while GEMM/subsystem busy or preload busy |
| 1 | `DMA_LOAD_BUSY_REJECT` | RO/W1C | `START_DMA_LOAD` requested while DMA load/store Port0 owner conflict exists |
| 2 | `AXIS_BUSY_REJECT` | RO/W1C | `START_AXIS_LOAD` requested while AXI-Stream preload or GEMM Port1 conflict exists |
| 3 | `DS_BUSY_REJECT` | RO/W1C | `START_DS_LOAD` requested while Direct Stream preload or GEMM conflict exists |
| 4 | `DMA_STORE_BUSY_REJECT` | RO/W1C | `START_DMA_STORE` requested while DMA load/store Port0 owner conflict exists |
| 8 | `UNSUPPORTED_COMBO` | RO/W1C | Unsupported command-bit combination was written |
| 9 | `ZERO_LENGTH_REJECT` | RO/W1C | Start command rejected because configured length/dimension is zero |

---

## 11. Configuration Register Defaults

After reset, recommended defaults are:

| Register | Reset |
|---|---:|
| `CSR_MODE` | 0x0000_0000 |
| `CSR_BASE_ADDR_A` | 0x0000_0000 |
| `CSR_BASE_ADDR_B` | 0x0000_0100 |
| `CSR_BASE_ADDR_C` | 0x0000_0200 |
| `CSR_DIM_M` | 0x0000_0004 |
| `CSR_DIM_N` | 0x0000_0004 |
| `CSR_DIM_K` | 0x0000_0004 |
| `CSR_DMA_LOAD_SRC_BASE` | 0x0000_0000 |
| `CSR_DMA_LOAD_DST_BASE` | 0x0000_0000 |
| `CSR_DMA_LOAD_BEATS` | 0x0000_0000 |
| `CSR_AXIS_SRC_BASE` | 0x0000_0000 |
| `CSR_AXIS_DST_BASE` | 0x0000_0000 |
| `CSR_AXIS_LOAD_BEATS` | 0x0000_0000 |
| `CSR_DS_SRC_BASE` | 0x0000_0000 |
| `CSR_DS_DST_BASE` | 0x0000_0000 |
| `CSR_DS_LOAD_BEATS` | 0x0000_0000 |
| `CSR_DS_CONTROL` | 0x0000_0000 |
| `CSR_DMA_STORE_SRC_BASE` | 0x0000_0000 |
| `CSR_DMA_STORE_DST_BASE` | 0x0000_0000 |
| `CSR_DMA_STORE_BYTE_COUNT` | 0x0000_0000 |

The A/B/C and M/N/K defaults match the original simple 4x4 bring-up memory map and make CSR smoke tests deterministic even before software writes every field.

---

## 12. Direct Stream Control Register

### `CSR_DS_CONTROL` at 0x06C

| Bit | Name | Access | Reset | Description |
|---:|---|---|---:|---|
| 0 | `DS_OPERAND_SEL` | RW | 0 | 0 = preload operand A, 1 = preload operand B |
| 31:1 | `RSVD` | RO | 0 | Reserved |

`DS_OPERAND_SEL` is sampled by the Direct Stream preload command when `START_DS_LOAD` is accepted.

---

## 13. Command Acceptance Rules

### 13.1 Common Rules

A start command is accepted only when:

```text
The selected operation is not already busy.
The selected operation has no illegal owner conflict with another active operation.
The configured length/dimensions for that operation are non-zero.
The command write contains exactly one START_* bit.
```

When a command is rejected:

```text
No start pulse is generated.
The corresponding reject sticky bit is set.
CSR_ERROR_STATUS is not necessarily set, but CSR_STATUS.ANY_ERROR becomes 1 because command reject bits are included.
```

### 13.2 GEMM Start Acceptance

`START_GEMM` is accepted only when:

```text
acc_busy == 0
axis_load_busy == 0
ds_load_busy == 0
dim_m != 0
dim_n != 0
dim_k != 0
```

This matches the existing policy that GEMM should not start while AXI-Stream or Direct Stream preload is active.

### 13.3 DMA Load Start Acceptance

`START_DMA_LOAD` is accepted only when:

```text
dma_load_busy == 0
dma_store_busy == 0
CSR_DMA_LOAD_BEATS != 0
```

DMA load and DMA store both use scratchpad Port0 ownership, so they must not overlap.

### 13.4 AXI-Stream Preload Start Acceptance

`START_AXIS_LOAD` is accepted only when:

```text
axis_load_busy == 0
acc_busy == 0
CSR_AXIS_LOAD_BEATS != 0
```

AXI-Stream preload writes scratchpad Port1, so it must not overlap with GEMM Port1 use.

### 13.5 Direct Stream Preload Start Acceptance

`START_DS_LOAD` is accepted only when:

```text
ds_load_busy == 0
acc_busy == 0
CSR_DS_LOAD_BEATS != 0
CSR_DS_CONTROL.DS_OPERAND_SEL is 0 or 1
```

Direct Stream preload writes the operand buffer and should complete before GEMM starts.

### 13.6 DMA Store Start Acceptance

`START_DMA_STORE` is accepted only when:

```text
dma_store_busy == 0
dma_load_busy == 0
CSR_DMA_STORE_BYTE_COUNT != 0
```

Software should normally launch DMA store only after GEMM done is observed, but P14A does not require the CSR block to enforce `GEMM_DONE` before `START_DMA_STORE`.  This keeps the CSR block a simple control plane rather than a scheduler.

---

## 14. Sideband Outputs From CSR Block

`ai_accel_csr_regs` should produce the same style of control/config wires currently driven by the testbench or top-level wrapper.

Recommended outputs:

```systemverilog
// GEMM control/config
output logic                  acc_start_pulse,
output logic                  gemm_input_stream_mode,
output logic                  accumulate_enable,
output logic [ADDR_WIDTH-1:0] base_addr_a,
output logic [ADDR_WIDTH-1:0] base_addr_b,
output logic [ADDR_WIDTH-1:0] base_addr_c,
output logic [GEMM_DIM_WIDTH-1:0] dim_m,
output logic [GEMM_DIM_WIDTH-1:0] dim_n,
output logic [GEMM_DIM_WIDTH-1:0] dim_k,

// DMA load
output logic                  dma_load_start_pulse,
output logic [ADDR_WIDTH-1:0] dma_src_base_addr,
output logic [ADDR_WIDTH-1:0] dma_dst_base_addr,
output logic [31:0]           dma_load_beats,

// AXI-Stream preload
output logic                  axis_load_start_pulse,
output logic [ADDR_WIDTH-1:0] axis_src_base_addr,
output logic [ADDR_WIDTH-1:0] axis_dst_base_addr,
output logic [31:0]           axis_load_beats,

// Direct Stream preload
output logic                  ds_load_start_pulse,
output logic [ADDR_WIDTH-1:0] ds_src_base_addr,
output logic [ADDR_WIDTH-1:0] ds_dst_base_addr,
output logic [31:0]           ds_load_beats,
output logic                  ds_operand_sel,

// DMA store
output logic                  dma_store_start_pulse,
output logic [ADDR_WIDTH-1:0] dma_store_src_base_addr,
output logic [ADDR_WIDTH-1:0] dma_store_dst_base_addr,
output logic [31:0]           dma_store_byte_count
```

All start outputs are one `dma_clk` cycle pulses.

---

## 15. Sideband Inputs To CSR Block

Recommended status inputs:

```systemverilog
// Live busy/done/error from existing subsystem
input logic acc_busy,
input logic acc_done,

input logic dma_load_busy,
input logic dma_load_done,
input logic dma_load_error,

input logic axis_load_busy,
input logic axis_load_done,
input logic axis_load_error,

input logic ds_load_busy,
input logic ds_load_done,
input logic ds_load_error,

input logic dma_store_busy,
input logic dma_store_done,
input logic dma_store_error,

// Performance counter inputs from existing subsystem
input logic [31:0] gemm_perf_busy_cycles,
input logic [31:0] gemm_perf_mac_count,
input logic [31:0] gemm_perf_output_count
```

`acc_done`, `dma_load_done`, `axis_load_done`, `ds_load_done`, and `dma_store_done` are converted into sticky CSR done bits.

Error inputs are converted into sticky CSR error bits.

---

## 16. Programming Sequences

### 16.1 Host-Primary GEMM Sequence

```text
1. Host AXI writes A/B into scratchpad.
2. CSR writes BASE_ADDR_A/B/C.
3. CSR writes DIM_M/N/K.
4. CSR writes CSR_MODE:
     GEMM_INPUT_STREAM_MODE = 0
     ACCUMULATE_ENABLE      = 0 or 1 depending on the job
5. CSR writes CSR_COMMAND.START_GEMM = 1.
6. CSR polls CSR_DONE_STATUS.GEMM_DONE.
7. CSR optionally reads performance snapshot registers.
8. Host AXI reads C from scratchpad.
9. Scoreboard compares C against reference.
```

### 16.2 DMA Load + GEMM + DMA Store Sequence

```text
1. CSR programs DMA load A source/destination/length.
2. CSR writes START_DMA_LOAD.
3. CSR polls DMA_LOAD_DONE.
4. CSR programs DMA load B source/destination/length.
5. CSR writes START_DMA_LOAD.
6. CSR polls DMA_LOAD_DONE.
7. CSR programs GEMM base/dim/mode.
8. CSR writes START_GEMM.
9. CSR polls GEMM_DONE.
10. CSR programs DMA store source/destination/byte_count.
11. CSR writes START_DMA_STORE.
12. CSR polls DMA_STORE_DONE.
13. Scoreboard checks destination memory.
```

### 16.3 AXI-Stream Preload + GEMM + DMA Store Sequence

```text
1. CSR programs AXI-Stream preload A source/destination/length.
2. CSR writes START_AXIS_LOAD.
3. CSR polls AXIS_LOAD_DONE.
4. CSR programs AXI-Stream preload B source/destination/length.
5. CSR writes START_AXIS_LOAD.
6. CSR polls AXIS_LOAD_DONE.
7. CSR programs GEMM scratchpad mode.
8. CSR writes START_GEMM.
9. CSR polls GEMM_DONE.
10. CSR launches DMA store.
11. CSR polls DMA_STORE_DONE.
```

### 16.4 Direct Stream Preload + GEMM + DMA Store Sequence

```text
1. CSR programs Direct Stream preload A source/destination/length and DS_OPERAND_SEL=0.
2. CSR writes START_DS_LOAD.
3. CSR polls DS_LOAD_DONE.
4. CSR programs Direct Stream preload B source/destination/length and DS_OPERAND_SEL=1.
5. CSR writes START_DS_LOAD.
6. CSR polls DS_LOAD_DONE.
7. CSR programs GEMM base/dim and GEMM_INPUT_STREAM_MODE=1.
8. CSR writes START_GEMM.
9. CSR polls GEMM_DONE.
10. CSR launches DMA store.
11. CSR polls DMA_STORE_DONE.
```

### 16.5 C RMW Accumulation Sequence

For two-job partial-K accumulation:

```text
Job 0:
  ACCUMULATE_ENABLE = 0
  START_GEMM
  poll GEMM_DONE

Job 1:
  ACCUMULATE_ENABLE = 1
  START_GEMM
  poll GEMM_DONE
```

Software or the UVM sequence is responsible for programming each job's A/B/C base and dimensions consistently with the C RMW recipe.

---

## 17. Verification Plan For P14

### 17.1 CSR Register Tests

P14B/P14D should include:

```text
CSR reset default test
CSR RW register write/readback test
CSR byte-strobe test
CSR read-only write-ignore test
CSR invalid-address SLVERR test
CSR command read returns zero test
CSR command pulse generation test
CSR sticky done clear test
CSR sticky error clear test
CSR busy-command reject test
```

### 17.2 CSR-Controlled End-to-End Tests

P14E/P14F should add representative tests, not duplicate the entire 82-item legacy regression.

Recommended initial CSR regression items:

```text
csr_host_primary_case100
csr_host_primary_case101
csr_dma_load_store_case211
csr_axis_stream_load_store_case211
csr_direct_stream_load_store_case211
csr_c_rmw_accum_host_primary_case211
```

The legacy 82-item regression should continue to pass unchanged.

### 17.3 Acceptance Criteria

P14 closure should require:

```text
CSR standalone tests PASS
CSR host-primary GEMM representative tests PASS
CSR frontend representative tests PASS
Legacy sideband full regression still PASS
New full regression total increases by the CSR representative items
No BRAM RTL changes
No GEMM datapath behavioral changes required for P14A/P14B
```

---

## 18. P14 Milestone Breakdown

Recommended P14 split:

```text
P14A: CSR control-plane spec and register map
P14B: Standalone AXI-Lite CSR register block
P14C: CSR wrapper integration around existing ai_accel_subsys
P14D: UVM CSR access tasks / lightweight CSR agent
P14E: CSR-controlled host-primary GEMM smoke
P14F: CSR-controlled DMA / AXI-Stream / Direct Stream representatives
P14G: Regression and documentation closure
```

---

## 19. Open Decisions Before P14B

These should be confirmed before writing RTL:

```text
1. Use a dedicated axi_lite_if.sv or plain port list?
2. Keep CSR block strictly dma_clk-domain?  Recommended: yes.
3. Use ai_accel_subsys_csr_top.sv wrapper and keep ai_accel_subsys.sv intact?  Recommended: yes.
4. Invalid address response: SLVERR?  Recommended: yes.
5. RO write behavior: ignored with OKAY?  Recommended: yes.
6. Do we want separate W1C done/error registers plus CLEAR_DONE/CLEAR_ERROR commands?  Recommended: yes.
7. Should CSR enforce GEMM_DONE before DMA_STORE?  Recommended: no for P14; software controls sequencing.
```

---

## 20. Summary

P14 adds a lightweight AXI-Lite CSR control plane to make the accelerator host-programmable while preserving the validated datapath subsystem.

The key design choice is to keep P14 as a control-plane wrapper:

```text
CSR writes configure and launch operations.
Existing ai_accel_subsys executes the operations.
CSR reads expose live status, sticky completion/error, and performance snapshots.
Software/UVM still controls operation sequencing.
```

This gives the project a realistic software-visible accelerator control model without turning P14 into a descriptor scheduler or full SoC software stack.
