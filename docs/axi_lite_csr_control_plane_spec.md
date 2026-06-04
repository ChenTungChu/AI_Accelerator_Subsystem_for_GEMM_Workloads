# AXI-Lite CSR Control Plane Spec

## 1. Purpose

This document defines the P14 AXI-Lite control-plane specification for the AI Accelerator Subsystem.  It also records the P14F CSR-controlled frontend representative validation checkpoint and the P15E job-descriptor sequencer CSR extension checkpoint.

The subsystem already has a stable GEMM datapath and multiple validated data movement frontends.  P14 adds a lightweight software-visible control plane so a host can program, launch, poll, and observe the accelerator through control/status registers instead of driving top-level sideband control wires directly.

P14 is intentionally scoped as a minimal CSR shell.  It is not a descriptor engine, interrupt controller, software driver, or UVM RAL model.  P15 builds on the same CSR shell by adding a CSR-resident single-job descriptor and hardware job sequencer above the P14 micro-operation command model.

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
Full UVM regression baseline passing 82/82 before CSR representative expansion
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

P14 keeps the existing datapath subsystem intact and adds a CSR programming layer around it.  P15 preserves that wrapper and adds a higher-level job descriptor window above the P14 micro-operation registers.

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

The P14 CSR block does not automatically schedule multi-stage jobs.  Software or the UVM sequence remains responsible for launching DMA load, GEMM, and DMA store in the desired order.  P15 adds a separate job-level sequencer path that can consume one descriptor and automatically launch preload, GEMM, and optional store stages while preserving the P14 micro-operation programming model for debug and compatibility.

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

Current P14F validated scope:

```text
Standalone CSR register smoke through integrated run_uvm.tcl
CSR wrapper integration around the existing subsystem
CSR-controlled host-primary GEMM CASE_ID=100
CSR-controlled host-primary GEMM CASE_ID=102
CSR-controlled DMA load + GEMM + DMA store CASE_ID=100/102
CSR-controlled AXI-Stream preload + GEMM + DMA store CASE_ID=100/102
CSR-controlled Direct Stream preload + GEMM + DMA store CASE_ID=100/102
Full regression after P14F/P14G: 90/90 PASS
```

Current P15E validated scope:

```text
CSR job descriptor register window above the P14 CSR map
Hardware single-job sequencer integrated in ai_accel_subsys_csr_top
CSR job-level DMA load + GEMM + DMA store CASE_ID=100/102
CSR job reject / busy / clear handling CASE_ID=102
CSR job-level AXI-Stream preload + GEMM + DMA store CASE_ID=102
CSR job-level Direct Stream preload + GEMM + DMA store CASE_ID=102
Full regression after P15E: 95/95 PASS
```

### 4.2 Not Included

P14 does not include:

```text
Interrupt output
UVM RAL model
Linux driver
C software driver
Descriptor queue
P14 automatic job scheduler
Multi-job hardware command processor
Cache-coherent host interface
AXI interconnect / NoC integration
Double buffering
Streaming GEMM compute rewrite
```

These can be future milestones after the CSR control plane and the single-job P15 sequencer are stable.

---

## 5. Recommended RTL Partition

P14 should avoid destabilizing the existing `ai_accel_subsys.sv` datapath top.

Recommended new RTL:

```text
rtl/interface/axi_lite_if.sv
rtl/csr/ai_accel_csr_regs.sv
rtl/top/ai_accel_subsys_csr_top.sv
```

Recommended P14 partition:

```text
ai_accel_subsys_csr_top
    AXI-Lite CSR slave port
        -> ai_accel_csr_regs
            -> existing sideband control wires
                -> ai_accel_subsys
```

Recommended P15 extension:

```text
ai_accel_subsys_csr_top
    AXI-Lite CSR slave port
        -> ai_accel_csr_regs
            -> P14 micro-operation CSR outputs
            -> P15 job descriptor/config outputs
                -> ai_accel_job_sequencer
                    -> existing ai_accel_subsys sideband starts/configs
```

The existing `ai_accel_subsys.sv` remains the stable datapath subsystem.  The CSR top wraps it, and the P15 job sequencer arbitrates between job-level control and the existing P14 micro-operation controls.

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

P15 adds a job descriptor / sequencer register window above the P14 micro-operation window.  The P14 registers from `0x000` through `0x08C` remain unchanged.

### 9.1 P15 Job Descriptor Register Window

| Offset | Name | Access | Description |
|---:|---|---|---|
| 0x100 | `CSR_JOB_VERSION` | RO | Job sequencer version / feature ID |
| 0x104 | `CSR_JOB_COMMAND` | W1P | Job start and clear commands |
| 0x108 | `CSR_JOB_STATUS` | RO | Live job status summary |
| 0x10C | `CSR_JOB_DONE_STATUS` | RO/W1C | Sticky job done status |
| 0x110 | `CSR_JOB_ERROR_STATUS` | RO/W1C | Sticky job error status |
| 0x114 | `CSR_JOB_MODE` | RW | Job input/output mode and options |
| 0x118 | `CSR_JOB_REJECT_STATUS` | RO/W1C | Sticky job command reject reasons |
| 0x11C | `CSR_JOB_STATE` | RO | Current sequencer state |
| 0x120 | `CSR_JOB_BASE_ADDR_A` | RW | GEMM A logical base address |
| 0x124 | `CSR_JOB_BASE_ADDR_B` | RW | GEMM B logical base address |
| 0x128 | `CSR_JOB_BASE_ADDR_C` | RW | GEMM C scratchpad base address |
| 0x12C | `CSR_JOB_DIM_M` | RW | GEMM M dimension |
| 0x130 | `CSR_JOB_DIM_N` | RW | GEMM N dimension |
| 0x134 | `CSR_JOB_DIM_K` | RW | GEMM K dimension |
| 0x138 | `CSR_JOB_A_SRC_BASE` | RW | External/source-memory A base for preload modes |
| 0x13C | `CSR_JOB_A_DST_BASE` | RW | Scratchpad or operand-buffer A destination/base |
| 0x140 | `CSR_JOB_A_LOAD_BEATS` | RW | A preload length in DATA_WIDTH beats |
| 0x144 | `CSR_JOB_RESERVED_144` | RO | Reserved |
| 0x148 | `CSR_JOB_B_SRC_BASE` | RW | External/source-memory B base for preload modes |
| 0x14C | `CSR_JOB_B_DST_BASE` | RW | Scratchpad or operand-buffer B destination/base |
| 0x150 | `CSR_JOB_B_LOAD_BEATS` | RW | B preload length in DATA_WIDTH beats |
| 0x154 | `CSR_JOB_RESERVED_154` | RO | Reserved |
| 0x158 | `CSR_JOB_STORE_SRC_BASE` | RW | Scratchpad C source base for DMA store |
| 0x15C | `CSR_JOB_STORE_DST_BASE` | RW | External destination memory base for DMA store |
| 0x160 | `CSR_JOB_STORE_BYTE_COUNT` | RW | DMA store byte count |
| 0x164 | `CSR_JOB_RESERVED_164` | RO | Reserved |
| 0x180 | `CSR_JOB_PERF_BUSY_CYCLES` | RO | Captured GEMM busy-cycle count for completed job |
| 0x184 | `CSR_JOB_PERF_MAC_COUNT` | RO | Captured GEMM MAC count for completed job |
| 0x188 | `CSR_JOB_PERF_OUTPUT_COUNT` | RO | Captured GEMM output count for completed job |
| 0x18C | `CSR_JOB_RESERVED_18C` | RO | Reserved |

The P15 job window is intentionally separate from the P14 micro-operation window.  Software can continue using P14 commands directly when the job sequencer is idle.

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

### 10.8 P15 Job Command / Status Registers

The P15 job registers use the same AXI-Lite access policy and the same W1P/W1C definitions as the P14 CSR window.

`CSR_JOB_COMMAND` at `0x104` is a write-one-pulse register:

| Bit | Name | Type | Description |
|---:|---|---|---|
| 0 | `START_JOB` | W1P | Latch the CSR job descriptor and start the hardware job sequencer if accepted |
| 8 | `CLEAR_JOB_DONE` | W1P | Clear sticky job done bits |
| 9 | `CLEAR_JOB_ERROR` | W1P | Clear sticky job error and reject bits |
| 10 | `CLEAR_JOB_PERF` | W1P | Clear job performance snapshot registers |

`CSR_JOB_MODE` at `0x114` selects the job-level frontend and output path:

| Bits | Name | Access | Description |
|---:|---|---|---|
| [1:0] | `INPUT_MODE` | RW | 0=HOST_PRELOADED, 1=DMA_LOAD, 2=AXIS_PRELOAD, 3=DIRECT_STREAM |
| [3:2] | `OUTPUT_MODE` | RW | 0=HOST_READBACK, 1=DMA_STORE |
| 4 | `ACCUMULATE_ENABLE` | RW | GEMM C RMW accumulation control for this job |
| 5 | `CLEAR_P14_STICKY_ON_START` | RW | Optional debug policy bit, reserved by the current validated flow |
| [31:6] | `RSVD` | RO | Reserved |

`CSR_JOB_REJECT_STATUS` at `0x118` records job command rejects:

| Bit | Name | Type | Description |
|---:|---|---|---|
| 0 | `JOB_BUSY_REJECT` | RO/W1C | START_JOB requested while job_busy is high |
| 1 | `MICRO_OP_BUSY_REJECT` | RO/W1C | START_JOB requested while an underlying engine is already busy |
| 2 | `UNSUPPORTED_MODE_REJECT` | RO/W1C | Unsupported input/output mode combination |
| 3 | `ZERO_DIM_REJECT` | RO/W1C | M/N/K dimension is zero |
| 4 | `ZERO_A_LENGTH_REJECT` | RO/W1C | A preload length is zero when required |
| 5 | `ZERO_B_LENGTH_REJECT` | RO/W1C | B preload length is zero when required |
| 6 | `ZERO_STORE_LENGTH_REJECT` | RO/W1C | Store byte count is zero when DMA store is required |
| 7 | `MANUAL_CMD_DURING_JOB_REJECT` | RO/W1C | P14 manual micro-op command attempted while job sequencer owns control |
| 8 | `UNSUPPORTED_COMBO` | RO/W1C | Unsupported job command-bit combination was written |

The full job register bit definitions are recorded in `docs/job_descriptor_sequencer_spec.md`.

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

P15 job descriptor defaults mirror the same logical A/B/C and M/N/K bring-up map, while preload/store length fields reset to zero so accidental `START_JOB` does not launch a partial data movement operation without software programming the descriptor lengths.

```text
CSR_JOB_MODE              = 0x0000_0004
CSR_JOB_BASE_ADDR_A       = 0x0000_0000
CSR_JOB_BASE_ADDR_B       = 0x0000_0100
CSR_JOB_BASE_ADDR_C       = 0x0000_0200
CSR_JOB_DIM_M             = 0x0000_0004
CSR_JOB_DIM_N             = 0x0000_0004
CSR_JOB_DIM_K             = 0x0000_0004
CSR_JOB_A_LOAD_BEATS      = 0x0000_0000
CSR_JOB_B_LOAD_BEATS      = 0x0000_0000
CSR_JOB_STORE_BYTE_COUNT  = 0x0000_0000
```

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

### 13.7 P15 START_JOB Acceptance

`START_JOB` is accepted only when:

```text
job_busy == 0
acc_busy == 0
dma_load_busy == 0
axis_load_busy == 0
ds_load_busy == 0
dma_store_busy == 0
dim_m != 0
dim_n != 0
dim_k != 0
input/output mode combination is supported
required preload lengths are non-zero for preload modes
required store byte count is non-zero for DMA_STORE output mode
```

When a P15 job is active, P14 manual `START_*` commands are rejected and are not forwarded to the datapath.  This policy avoids two CSR control sources driving the same underlying engines.

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

For P15, the CSR block also exposes the job descriptor fields and job command pulses to `ai_accel_job_sequencer`.  The sequencer then drives the same style of subsystem sideband control/config wires during an active job.

Recommended job-facing outputs include:

```systemverilog
output logic                  job_start_pulse,
output logic                  job_clear_done_pulse,
output logic                  job_clear_error_pulse,
output logic                  job_clear_perf_pulse,
output logic [31:0]           job_mode,
output logic [ADDR_WIDTH-1:0] job_base_addr_a,
output logic [ADDR_WIDTH-1:0] job_base_addr_b,
output logic [ADDR_WIDTH-1:0] job_base_addr_c,
output logic [GEMM_DIM_WIDTH-1:0] job_dim_m,
output logic [GEMM_DIM_WIDTH-1:0] job_dim_n,
output logic [GEMM_DIM_WIDTH-1:0] job_dim_k,
output logic [ADDR_WIDTH-1:0] job_a_src_base,
output logic [ADDR_WIDTH-1:0] job_a_dst_base,
output logic [31:0]           job_a_load_beats,
output logic [ADDR_WIDTH-1:0] job_b_src_base,
output logic [ADDR_WIDTH-1:0] job_b_dst_base,
output logic [31:0]           job_b_load_beats,
output logic [ADDR_WIDTH-1:0] job_store_src_base,
output logic [ADDR_WIDTH-1:0] job_store_dst_base,
output logic [31:0]           job_store_byte_count
```

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

For P15, the CSR block receives job sequencer status and exposes them through the job CSR window:

```systemverilog
input logic        job_busy,
input logic [31:0] job_done_status,
input logic [31:0] job_error_status,
input logic [31:0] job_reject_status,
input logic [31:0] job_state,
input logic [31:0] job_perf_busy_cycles,
input logic [31:0] job_perf_mac_count,
input logic [31:0] job_perf_output_count
```

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

### 16.6 P15 Job Descriptor DMA Load + GEMM + DMA Store Sequence

```text
1. CSR writes JOB_BASE_ADDR_A/B/C and JOB_DIM_M/N/K.
2. CSR writes JOB_A_SRC_BASE / JOB_A_DST_BASE / JOB_A_LOAD_BEATS.
3. CSR writes JOB_B_SRC_BASE / JOB_B_DST_BASE / JOB_B_LOAD_BEATS.
4. CSR writes JOB_STORE_SRC_BASE / JOB_STORE_DST_BASE / JOB_STORE_BYTE_COUNT.
5. CSR writes JOB_MODE:
     INPUT_MODE  = DMA_LOAD
     OUTPUT_MODE = DMA_STORE
6. CSR writes CSR_JOB_COMMAND.START_JOB.
7. Hardware sequencer runs DMA load A.
8. Hardware sequencer runs DMA load B.
9. Hardware sequencer runs GEMM.
10. Hardware sequencer runs DMA store.
11. CSR polls CSR_JOB_DONE_STATUS.JOB_DONE.
12. Test checks DMA destination memory.
```

### 16.7 P15 Job Descriptor AXI-Stream / Direct Stream Frontend Sequence

For AXI-Stream job mode:

```text
INPUT_MODE  = AXIS_PRELOAD
OUTPUT_MODE = DMA_STORE
Sequencer runs AXI-Stream preload A, AXI-Stream preload B, GEMM, DMA store.
```

For Direct Stream job mode:

```text
INPUT_MODE  = DIRECT_STREAM
OUTPUT_MODE = DMA_STORE
Sequencer runs Direct Stream preload A with ds_operand_sel=0.
Sequencer runs Direct Stream preload B with ds_operand_sel=1.
Sequencer starts GEMM with GEMM_INPUT_STREAM_MODE=1.
Sequencer runs DMA store after GEMM completion.
```

---

## 17. Verification Plan For P14 / P15

### 17.1 P14 CSR Register Tests

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

### 17.2 P14 CSR-Controlled End-to-End Tests

P14E/P14F add representative tests, not duplicate the entire 82-item legacy regression.

Validated CSR regression items:

```text
csr_host_smoke_case100
csr_host_smoke_case102
csr_dma_load_store_case100
csr_dma_load_store_case102
csr_axis_stream_load_store_case100
csr_axis_stream_load_store_case102
csr_direct_stream_load_store_case100
csr_direct_stream_load_store_case102
```

The legacy sideband regression continues to pass unchanged, with CSR representative items increasing the integrated full regression total to 90.

### 17.3 P15 Job-Level End-to-End Tests

Validated P15 job-level regression items:

```text
csr_job_dma_load_store_case100
csr_job_dma_load_store_case102
csr_job_reject_error_case102
csr_job_axis_stream_load_store_case102
csr_job_direct_stream_load_store_case102
```

These use `UVM_TOP=ai_accel_subsys_csr_uvm_top`, program one CSR-resident job descriptor, issue `CSR_JOB_COMMAND.START_JOB`, let the hardware job sequencer launch the selected preload/GEMM/store stages, and compare the final DMA destination memory against the software reference.

### 17.4 Acceptance Criteria

P14 closure should require:

```text
CSR standalone tests PASS
CSR host-primary GEMM representative tests PASS
CSR frontend representative tests PASS
Legacy sideband full regression still PASS
New full regression total increases by the CSR representative items
P14F full regression: 90/90 PASS
P15E full regression: 95/95 PASS
No BRAM RTL changes
No GEMM datapath behavioral changes required for P14A/P14B
```

---

## 18. P14 / P15 Milestone Breakdown

Completed P14 split:

```text
P14A: CSR control-plane spec and register map                         PASS
P14B: Standalone AXI-Lite CSR register block                          PASS
P14C: CSR wrapper integration around existing ai_accel_subsys          PASS
P14D: UVM CSR access tasks / lightweight CSR agent                     PASS
P14E: CSR-controlled host-primary GEMM smoke                           PASS
P14F: CSR-controlled DMA / AXI-Stream / Direct Stream representatives  PASS
P14G: Regression and documentation closure                             PASS
```

Completed P15 job-sequencer split through the current checkpoint:

```text
P15A: Job descriptor / sequencer spec                                  PASS
P15B: CSR job-control register extension                               PASS
P15C: Single-job DMA load -> GEMM -> DMA store hardware FSM            PASS
P15D: Job sequencer reject / busy / clear handling                     PASS
P15E: Job sequencer frontend-mode extension                            PASS
P15F: Documentation / closure update                                   PASS
```

---

## 19. Open Decisions

The original P14 questions have been resolved for the current baseline:

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

## 20. Current P14F / P15E Validation Status

The validated P14F checkpoint is:

```text
CSR standalone register smoke: PASS
CSR-controlled host-primary GEMM CASE_ID=100: PASS
CSR-controlled host-primary GEMM CASE_ID=102: PASS
CSR-controlled DMA load + GEMM + DMA store CASE_ID=100: PASS
CSR-controlled DMA load + GEMM + DMA store CASE_ID=102: PASS
CSR-controlled AXI-Stream preload + GEMM + DMA store CASE_ID=100: PASS
CSR-controlled AXI-Stream preload + GEMM + DMA store CASE_ID=102: PASS
CSR-controlled Direct Stream preload + GEMM + DMA store CASE_ID=100: PASS
CSR-controlled Direct Stream preload + GEMM + DMA store CASE_ID=102: PASS
Full regression after P14F/P14G: 90/90 PASS
```

The validated P15E checkpoint is:

```text
CSR job-level DMA load + GEMM + DMA store CASE_ID=100: PASS
CSR job-level DMA load + GEMM + DMA store CASE_ID=102: PASS
CSR job reject / busy / clear handling CASE_ID=102: PASS
CSR job-level AXI-Stream preload + GEMM + DMA store CASE_ID=102: PASS
CSR job-level Direct Stream preload + GEMM + DMA store CASE_ID=102: PASS
Full regression after P15E: 95/95 PASS
```

P14F keeps the legacy sideband subsystem top available while using `ai_accel_subsys_csr_uvm_top` for CSR-wrapper validation.  The CSR-controlled frontend tests launch each selected data movement frontend through CSR commands, launch GEMM through CSR, launch DMA store through CSR, and compare the DMA destination memory against the software reference.

P15E uses the same CSR wrapper top, but software/UVM now programs a single job descriptor and writes `START_JOB`.  The hardware job sequencer then launches the selected frontend, GEMM, and DMA store stages automatically.

---

## 21. Summary

P14 adds a lightweight AXI-Lite CSR control plane to make the accelerator host-programmable while preserving the validated datapath subsystem.

The key P14 design choice is to keep the control plane as a micro-operation wrapper:

```text
CSR writes configure and launch individual operations.
Existing ai_accel_subsys executes the operations.
CSR reads expose live status, sticky completion/error, and performance snapshots.
Software/UVM controls operation sequencing.
```

P15 extends the same CSR wrapper into a job-level accelerator control model:

```text
CSR writes one job descriptor.
CSR writes START_JOB.
Hardware sequencer launches preload A, preload B, GEMM, and optional DMA store.
CSR reads expose job busy/done/error/reject status and job performance snapshots.
```

The current P15E checkpoint validates DMA, AXI-Stream, and Direct Stream job-level frontend modes while keeping P14 micro-operation CSR commands available when the job sequencer is idle.  Full regression is passing 95/95.
