# Job Descriptor / Sequencer Spec

## 1. Purpose

This document defines the P15A job descriptor and hardware sequencer specification for the AI Accelerator Subsystem.

P14 completed a software-visible AXI-Lite CSR control plane.  The host can now program individual operations through registers and launch each micro-operation independently:

```text
START_DMA_LOAD
START_AXIS_LOAD
START_DS_LOAD
START_GEMM
START_DMA_STORE
```

P15 raises the control abstraction from micro-operation control to job-level control.

The intended programming model is:

```text
1. Host writes one CSR-resident job descriptor.
2. Host writes START_JOB.
3. Hardware sequencer automatically launches the required preload stage(s).
4. Hardware sequencer launches GEMM after input preload completes.
5. Hardware sequencer optionally launches DMA store after GEMM completes.
6. Host polls JOB_DONE / JOB_ERROR and reads job/performance status.
```

The first P15 implementation is intentionally scoped as a single-outstanding-job sequencer.  It is not a descriptor queue, memory descriptor fetch engine, interrupt controller, or software driver.

---

## 2. Current Baseline Before P15

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
AXI-Lite CSR control-plane wrapper
CSR-controlled host-primary GEMM representative tests
CSR-controlled DMA / AXI-Stream / Direct Stream frontend representative tests
Full UVM regression passing 90/90 after P14F/P14G
```

P14 keeps the datapath subsystem intact and adds software-visible CSR control.  P15 should preserve that principle.

P15 must not require changes to:

```text
axi_mm_dual_port_bram
GEMM datapath behavior
DMA load/store datapath protocol
AXI-Stream preload datapath protocol
Direct Stream preload datapath protocol
existing P14 CSR micro-operation programming model
```

---

## 3. P15 Design Intent

P15 converts the accelerator from a CSR micro-operation model into a CSR job model.

P14 control model:

```text
Software/UVM explicitly sequences every operation:

  program DMA load A
  START_DMA_LOAD
  poll DMA_LOAD_DONE

  program DMA load B
  START_DMA_LOAD
  poll DMA_LOAD_DONE

  program GEMM
  START_GEMM
  poll GEMM_DONE

  program DMA store C
  START_DMA_STORE
  poll DMA_STORE_DONE
```

P15 control model:

```text
Software/UVM programs one descriptor and starts one job:

  program job descriptor
  START_JOB
  poll JOB_DONE / JOB_ERROR
```

The sequencer then performs the staged operation internally:

```text
LOAD_A -> LOAD_B -> GEMM -> optional STORE_C -> JOB_DONE
```

The key design goal is to add realistic accelerator job control without turning the subsystem into a full descriptor-queue DMA engine.

---

## 4. P15 Scope

### 4.1 Included

P15 includes:

```text
CSR-resident single-job descriptor registers
START_JOB command
job live busy status
sticky job done status
sticky job error status
job command reject status
job current-state debug register
hardware sequencer FSM
sequencer-generated starts/config for existing engines
support for host-preloaded, DMA, AXI-Stream, and Direct Stream input modes
optional DMA store output mode
job-level performance snapshot after GEMM completion
UVM job-level smoke tests
full regression integration
```

### 4.2 Not Included

P15 does not include:

```text
Descriptor queue
Memory-resident descriptor fetch
Linked-list descriptors
Multiple outstanding jobs
Interrupt output
Preemptive abort with partial rollback
Overlapped preload / compute / store pipeline
Double buffering
Cache-coherent host interface
Linux driver
C software driver
UVM RAL model
AXI interconnect / NoC integration
```

These can be future milestones after the single-job sequencer is stable.

---

## 5. Recommended RTL Partition

P15 should preserve the existing P14 CSR wrapper and datapath top.

Recommended new RTL:

```text
rtl/sequencer/ai_accel_job_sequencer.sv
```

Recommended modified RTL:

```text
rtl/csr/ai_accel_csr_regs.sv
rtl/top/ai_accel_subsys_csr_top.sv
```

Recommended partition:

```text
ai_accel_subsys_csr_top
    AXI-Lite CSR slave port
        -> ai_accel_csr_regs
            -> P14 micro-operation CSR outputs
            -> P15 job descriptor/config outputs
                -> ai_accel_job_sequencer
                    -> existing ai_accel_subsys sideband starts/configs
```

The job sequencer should sit between the CSR block and the existing subsystem control wires.  When no job is active, P14 micro-operation commands may continue to drive the subsystem for debug and backward compatibility.  When a P15 job is active, the sequencer owns the existing sideband starts/configs until the job completes or errors.

---

## 6. Clock and Reset Policy

### 6.1 Clock Domain

The P15 job sequencer is clocked by `dma_clk`.

Rationale:

```text
P14 CSR registers are dma_clk-domain.
Existing external control inputs are dma_clk-domain.
DMA load/store control already lives in dma_clk.
AXI-Stream and Direct Stream preload engines already handle their own CDC internally.
GEMM start/config are captured in dma_clk before crossing to core_clk inside ai_accel_subsys.
```

### 6.2 Reset

The P15 job sequencer reset uses `dma_rst_n`.

After reset:

```text
No sequencer-generated start pulse is asserted.
job_busy clears to 0.
job_done sticky bit clears to 0.
job_error sticky bits clear to 0.
job_state returns to IDLE.
active descriptor snapshot registers clear to defaults.
job performance snapshot registers clear to zero.
```

### 6.3 Descriptor Snapshot Policy

The job descriptor registers are CSR-visible storage.  On accepted `START_JOB`, the sequencer must latch a private active-job snapshot:

```text
job_mode_snapshot
base/dim snapshot
A/B preload descriptor snapshot
C store descriptor snapshot
```

The active job must use the snapshot, not the live CSR registers.

This allows software to read or even update descriptor registers while a job is active without changing the already-started job.  Updated descriptor registers take effect only on the next accepted `START_JOB`.

---

## 7. Job Model

### 7.1 Single Outstanding Job

P15 supports one active job at a time.

A job starts when `START_JOB` is accepted and ends when one of these occurs:

```text
All required stages complete successfully -> JOB_DONE
Any required stage reports error          -> JOB_ERROR
Reset                                     -> job state returns to IDLE
```

A second `START_JOB` while `job_busy==1` is rejected.

### 7.2 Job Input Modes

P15 supports four input modes:

| Encoding | Name | Meaning |
|---:|---|---|
| 0 | `HOST_PRELOADED` | A/B already exist in scratchpad. Sequencer skips input preload and starts GEMM. |
| 1 | `DMA_LOAD` | Sequencer uses CSR-controlled DMA load twice: A then B into scratchpad. |
| 2 | `AXIS_PRELOAD` | Sequencer uses CSR-controlled AXI-Stream preload twice: A then B into scratchpad. |
| 3 | `DIRECT_STREAM` | Sequencer uses CSR-controlled Direct Stream preload twice: A then B into operand buffer. |

### 7.3 Job Output Modes

P15 supports two output modes:

| Encoding | Name | Meaning |
|---:|---|---|
| 0 | `HOST_READBACK` | C remains in scratchpad. Sequencer does not launch DMA store. |
| 1 | `DMA_STORE` | Sequencer launches DMA store after GEMM done. |

### 7.4 GEMM Mode Derivation

For `HOST_PRELOADED`, `DMA_LOAD`, and `AXIS_PRELOAD` input modes:

```text
GEMM_INPUT_STREAM_MODE = 0
```

For `DIRECT_STREAM` input mode:

```text
GEMM_INPUT_STREAM_MODE = 1
```

`ACCUMULATE_ENABLE` comes from the job descriptor mode register.

### 7.5 First Implementation Target

The recommended first P15 implementation target is:

```text
INPUT_MODE  = DMA_LOAD
OUTPUT_MODE = DMA_STORE
CASE_ID=100
CASE_ID=102
```

After that is stable, P15 can extend the same sequencer framework to:

```text
HOST_PRELOADED + HOST_READBACK
AXIS_PRELOAD + DMA_STORE
DIRECT_STREAM + DMA_STORE
C RMW accumulation recipes
```

---

## 8. CSR Job Register Extension

P15 should add a job register window above the existing P14 CSR map.

Recommended base:

```text
JOB CSR base = 0x100
```

The existing P14 registers from `0x000` through `0x08C` remain unchanged.

### 8.1 Register Map

All registers are 32-bit and word-aligned.

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

The initial P15A map intentionally leaves gaps for timeout/debug expansion.

---

## 9. Register Bit Definitions

### 9.1 `CSR_JOB_VERSION` at 0x100

| Bits | Name | Access | Reset | Description |
|---:|---|---|---:|---|
| [31:16] | `MAJOR` | RO | 16'h0001 | Job sequencer major version |
| [15:8] | `MINOR` | RO | 8'h00 | Job sequencer minor version |
| [7:0] | `FEATURE_ID` | RO | 8'h15 | P15 job sequencer feature ID |

Recommended reset value:

```text
0x0001_0015
```

### 9.2 `CSR_JOB_COMMAND` at 0x104

This is a write-one-pulse register.  Reads return zero.

| Bit | Name | Type | Description |
|---:|---|---|---|
| 0 | `START_JOB` | W1P | Latch descriptor and start the job sequencer if accepted |
| 8 | `CLEAR_JOB_DONE` | W1P | Clear sticky job done bits |
| 9 | `CLEAR_JOB_ERROR` | W1P | Clear sticky job error and reject bits |
| 10 | `CLEAR_JOB_PERF` | W1P | Clear job performance snapshot registers |

Unsupported combinations:

```text
START_JOB with CLEAR_JOB_ERROR if job errors are currently sticky
START_JOB while job_busy is high
START_JOB with zero dimensions or zero required lengths
```

Unsupported combinations do not start a job and set `CSR_JOB_REJECT_STATUS`.

### 9.3 `CSR_JOB_STATUS` at 0x108

| Bit | Name | Access | Description |
|---:|---|---|---|
| 0 | `JOB_BUSY` | RO | Sequencer is running a job |
| 1 | `JOB_DONE` | RO | Sticky job done is set |
| 2 | `JOB_ERROR` | RO | Sticky job error or reject is set |
| 3 | `JOB_ACCEPT_READY` | RO | Sequencer is idle and can accept START_JOB |
| 8 | `MICRO_OP_BUSY` | RO | Any underlying engine busy is high |
| 16 | `CSR_READY` | RO | CSR block ready for transactions |

### 9.4 `CSR_JOB_DONE_STATUS` at 0x10C

| Bit | Name | Type | Description |
|---:|---|---|---|
| 0 | `JOB_DONE` | RO/W1C | Complete job finished successfully |
| 1 | `JOB_GEMM_DONE` | RO/W1C | GEMM stage completed inside the job |
| 2 | `JOB_STORE_DONE` | RO/W1C | Store stage completed inside the job, if enabled |

For `OUTPUT_MODE=HOST_READBACK`, successful completion sets `JOB_DONE` and `JOB_GEMM_DONE`; `JOB_STORE_DONE` remains zero.

### 9.5 `CSR_JOB_ERROR_STATUS` at 0x110

| Bit | Name | Type | Description |
|---:|---|---|---|
| 0 | `JOB_DMA_LOAD_ERROR` | RO/W1C | DMA load stage error observed |
| 1 | `JOB_AXIS_LOAD_ERROR` | RO/W1C | AXI-Stream preload stage error observed |
| 2 | `JOB_DS_LOAD_ERROR` | RO/W1C | Direct Stream preload stage error observed |
| 3 | `JOB_DMA_STORE_ERROR` | RO/W1C | DMA store stage error observed |
| 4 | `JOB_GEMM_ERROR_RESERVED` | RO/W1C | Reserved for future GEMM internal error |
| 8 | `JOB_SEQUENCE_ERROR` | RO/W1C | Sequencer reached an illegal state or unexpected done/error condition |

On any job error, the sequencer must stop launching new downstream stages and transition to an error terminal state.

### 9.6 `CSR_JOB_MODE` at 0x114

| Bits | Name | Access | Reset | Description |
|---:|---|---|---:|---|
| [1:0] | `INPUT_MODE` | RW | 0 | 0=HOST_PRELOADED, 1=DMA_LOAD, 2=AXIS_PRELOAD, 3=DIRECT_STREAM |
| [3:2] | `OUTPUT_MODE` | RW | 1 | 0=HOST_READBACK, 1=DMA_STORE |
| 4 | `ACCUMULATE_ENABLE` | RW | 0 | GEMM C RMW accumulation control for this job |
| 5 | `CLEAR_P14_STICKY_ON_START` | RW | 0 | Optional debug policy: clear P14 micro-op sticky status at accepted job start |
| [31:6] | `RSVD` | RO | 0 | Reserved |

The initial recommended default is:

```text
INPUT_MODE  = HOST_PRELOADED
OUTPUT_MODE = DMA_STORE
ACCUMULATE_ENABLE = 0
```

Software should explicitly program `INPUT_MODE` and `OUTPUT_MODE` for each job.

### 9.7 `CSR_JOB_REJECT_STATUS` at 0x118

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

### 9.8 `CSR_JOB_STATE` at 0x11C

Recommended state encodings:

| Value | Name | Meaning |
|---:|---|---|
| 0 | `IDLE` | No active job |
| 1 | `LOAD_A_SETUP` | Program selected preload engine for A |
| 2 | `LOAD_A_START` | Pulse selected preload start for A |
| 3 | `LOAD_A_WAIT` | Wait for A preload done/error |
| 4 | `LOAD_B_SETUP` | Program selected preload engine for B |
| 5 | `LOAD_B_START` | Pulse selected preload start for B |
| 6 | `LOAD_B_WAIT` | Wait for B preload done/error |
| 7 | `GEMM_SETUP` | Program GEMM config from descriptor snapshot |
| 8 | `GEMM_START` | Pulse GEMM start |
| 9 | `GEMM_WAIT` | Wait for GEMM done/error |
| 10 | `STORE_SETUP` | Program DMA store config |
| 11 | `STORE_START` | Pulse DMA store start |
| 12 | `STORE_WAIT` | Wait for DMA store done/error |
| 13 | `DONE` | Successful terminal state |
| 14 | `ERROR` | Error terminal state |

---

## 10. Descriptor Register Defaults

Recommended reset defaults:

| Register | Reset |
|---|---:|
| `CSR_JOB_MODE` | 0x0000_0004 |
| `CSR_JOB_BASE_ADDR_A` | 0x0000_0000 |
| `CSR_JOB_BASE_ADDR_B` | 0x0000_0100 |
| `CSR_JOB_BASE_ADDR_C` | 0x0000_0200 |
| `CSR_JOB_DIM_M` | 0x0000_0004 |
| `CSR_JOB_DIM_N` | 0x0000_0004 |
| `CSR_JOB_DIM_K` | 0x0000_0004 |
| `CSR_JOB_A_SRC_BASE` | 0x0000_0000 |
| `CSR_JOB_A_DST_BASE` | 0x0000_0000 |
| `CSR_JOB_A_LOAD_BEATS` | 0x0000_0000 |
| `CSR_JOB_B_SRC_BASE` | 0x0000_0100 |
| `CSR_JOB_B_DST_BASE` | 0x0000_0100 |
| `CSR_JOB_B_LOAD_BEATS` | 0x0000_0000 |
| `CSR_JOB_STORE_SRC_BASE` | 0x0000_0200 |
| `CSR_JOB_STORE_DST_BASE` | 0x0000_0000 |
| `CSR_JOB_STORE_BYTE_COUNT` | 0x0000_0000 |

`CSR_JOB_MODE` reset value `0x0000_0004` encodes:

```text
INPUT_MODE  = HOST_PRELOADED
OUTPUT_MODE = DMA_STORE
ACCUMULATE_ENABLE = 0
```

The descriptor defaults intentionally keep preload/store lengths at zero so that accidental `START_JOB` does not launch a partial data movement job without software programming length fields.

---

## 11. Sequencer Operation

### 11.1 Accepted START_JOB

When `START_JOB` is accepted:

```text
1. Clear job done/error/reject status for the new job.
2. Latch active descriptor snapshot.
3. Set job_busy.
4. Select the first state based on INPUT_MODE.
```

First state selection:

```text
INPUT_MODE=HOST_PRELOADED -> GEMM_SETUP
INPUT_MODE=DMA_LOAD       -> LOAD_A_SETUP
INPUT_MODE=AXIS_PRELOAD   -> LOAD_A_SETUP
INPUT_MODE=DIRECT_STREAM  -> LOAD_A_SETUP
```

### 11.2 Preload A Stage

For `DMA_LOAD` input mode:

```text
dma_src_base_addr = JOB_A_SRC_BASE
dma_dst_base_addr = JOB_A_DST_BASE
dma_load_beats    = JOB_A_LOAD_BEATS
pulse dma_load_start
wait dma_load_done or dma_load_error
```

For `AXIS_PRELOAD` input mode:

```text
axis_src_base_addr = JOB_A_SRC_BASE
axis_dst_base_addr = JOB_A_DST_BASE
axis_load_beats    = JOB_A_LOAD_BEATS
pulse axis_load_start
wait axis_load_done or axis_load_error
```

For `DIRECT_STREAM` input mode:

```text
ds_src_base_addr = JOB_A_SRC_BASE
ds_dst_base_addr = JOB_A_DST_BASE
ds_load_beats    = JOB_A_LOAD_BEATS
ds_operand_sel   = 0
pulse ds_load_start
wait ds_load_done or ds_load_error
```

### 11.3 Preload B Stage

For `DMA_LOAD` input mode:

```text
dma_src_base_addr = JOB_B_SRC_BASE
dma_dst_base_addr = JOB_B_DST_BASE
dma_load_beats    = JOB_B_LOAD_BEATS
pulse dma_load_start
wait dma_load_done or dma_load_error
```

For `AXIS_PRELOAD` input mode:

```text
axis_src_base_addr = JOB_B_SRC_BASE
axis_dst_base_addr = JOB_B_DST_BASE
axis_load_beats    = JOB_B_LOAD_BEATS
pulse axis_load_start
wait axis_load_done or axis_load_error
```

For `DIRECT_STREAM` input mode:

```text
ds_src_base_addr = JOB_B_SRC_BASE
ds_dst_base_addr = JOB_B_DST_BASE
ds_load_beats    = JOB_B_LOAD_BEATS
ds_operand_sel   = 1
pulse ds_load_start
wait ds_load_done or ds_load_error
```

### 11.4 GEMM Stage

The sequencer programs GEMM config from the active descriptor snapshot:

```text
base_addr_a = JOB_BASE_ADDR_A
base_addr_b = JOB_BASE_ADDR_B
base_addr_c = JOB_BASE_ADDR_C
dim_m       = JOB_DIM_M
dim_n       = JOB_DIM_N
dim_k       = JOB_DIM_K
```

Mode mapping:

```text
if INPUT_MODE == DIRECT_STREAM:
    gemm_input_stream_mode = 1
else:
    gemm_input_stream_mode = 0

accumulate_enable = JOB_MODE.ACCUMULATE_ENABLE
```

The sequencer then pulses `acc_start` and waits for `acc_done`.

On `acc_done`, the sequencer captures job performance snapshots:

```text
JOB_PERF_BUSY_CYCLES  = gemm_perf_busy_cycles
JOB_PERF_MAC_COUNT    = gemm_perf_mac_count
JOB_PERF_OUTPUT_COUNT = gemm_perf_output_count
```

### 11.5 Store Stage

If `OUTPUT_MODE=HOST_READBACK`, the sequencer skips store and completes the job after GEMM done.

If `OUTPUT_MODE=DMA_STORE`, the sequencer programs DMA store config:

```text
dma_store_src_base_addr = JOB_STORE_SRC_BASE
dma_store_dst_base_addr = JOB_STORE_DST_BASE
dma_store_byte_count    = JOB_STORE_BYTE_COUNT
```

It then pulses `dma_store_start` and waits for `dma_store_done` or `dma_store_error`.

### 11.6 Completion Semantics

`JOB_DONE` means:

```text
All required stages for the selected job mode completed successfully.
If OUTPUT_MODE=DMA_STORE, destination memory has received the complete C payload.
If OUTPUT_MODE=HOST_READBACK, final C is visible in scratchpad after GEMM done.
```

The sequencer must not assert `JOB_DONE` before the final required stage is complete.

---

## 12. Manual P14 Micro-Operation Compatibility

P15 should keep P14 micro-operation commands usable for debug and targeted testing.

Policy:

```text
When job_busy == 0:
  P14 START_DMA_LOAD / START_AXIS_LOAD / START_DS_LOAD / START_GEMM / START_DMA_STORE commands are allowed subject to existing P14 acceptance rules.

When job_busy == 1:
  P14 manual START_* commands are rejected.
  No manual start pulse is forwarded to ai_accel_subsys.
  JOB_REJECT_STATUS.MANUAL_CMD_DURING_JOB_REJECT is set.
```

This avoids two control sources driving the same underlying engine while the job sequencer is active.

---

## 13. Acceptance Rules

### 13.1 Common START_JOB Acceptance

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
```

### 13.2 Input Mode Length Rules

For `HOST_PRELOADED`:

```text
A_LOAD_BEATS may be zero
B_LOAD_BEATS may be zero
```

For `DMA_LOAD`, `AXIS_PRELOAD`, and `DIRECT_STREAM`:

```text
A_LOAD_BEATS != 0
B_LOAD_BEATS != 0
```

### 13.3 Output Mode Length Rules

For `HOST_READBACK`:

```text
STORE_BYTE_COUNT may be zero
```

For `DMA_STORE`:

```text
STORE_BYTE_COUNT != 0
```

### 13.4 Direct Stream Rules

For `DIRECT_STREAM`:

```text
The sequencer drives ds_operand_sel=0 for A preload.
The sequencer drives ds_operand_sel=1 for B preload.
GEMM_INPUT_STREAM_MODE is forced to 1 for the GEMM stage.
```

The logical A/B base addresses should still be programmed consistently with the Direct Stream operand-buffer routing policy used by `gemm_input_mem_router`.

---

## 14. Error Policy

If an error is observed during a required stage:

```text
1. Set the corresponding JOB_ERROR_STATUS bit.
2. Stop launching downstream stages.
3. Clear job_busy.
4. Enter ERROR terminal state.
5. Keep JOB_DONE deasserted.
```

Recommended mappings:

| Stage | Error input | Job error bit |
|---|---|---|
| DMA A/B preload | `dma_load_error` | `JOB_DMA_LOAD_ERROR` |
| AXI-Stream A/B preload | `axis_load_error` | `JOB_AXIS_LOAD_ERROR` |
| Direct Stream A/B preload | `ds_load_error` | `JOB_DS_LOAD_ERROR` |
| DMA store | `dma_store_error` | `JOB_DMA_STORE_ERROR` |
| Illegal sequencer state | internal | `JOB_SEQUENCE_ERROR` |

The current GEMM datapath does not expose a dedicated GEMM error signal.  `JOB_GEMM_ERROR_RESERVED` is reserved for future use.

---

## 15. Performance Counter Policy

P15 job performance registers capture the GEMM performance snapshot for the GEMM stage of the completed job.

For single GEMM jobs:

```text
JOB_PERF_MAC_COUNT    = M * N * K
JOB_PERF_OUTPUT_COUNT = M * N
```

For P13-style external partial-K accumulation recipes, each job descriptor represents one GEMM job, not the entire multi-job recipe.  Therefore:

```text
JOB_PERF_MAC_COUNT    = M * N * K_part
JOB_PERF_OUTPUT_COUNT = M * N
```

A future multi-descriptor recipe runner can sum per-job counters if recipe-level counters are desired.

---

## 16. Programming Sequences

### 16.1 Host-Preloaded Job With Host Readback

```text
1. Host writes A/B into scratchpad.
2. Host writes JOB_BASE_ADDR_A/B/C.
3. Host writes JOB_DIM_M/N/K.
4. Host writes JOB_MODE:
     INPUT_MODE        = HOST_PRELOADED
     OUTPUT_MODE       = HOST_READBACK
     ACCUMULATE_ENABLE = 0 or 1
5. Host writes CSR_JOB_COMMAND.START_JOB = 1.
6. Host polls CSR_JOB_DONE_STATUS.JOB_DONE.
7. Host reads C from scratchpad.
8. Test compares C against software reference.
```

### 16.2 DMA Load + GEMM + DMA Store Job

```text
1. Host writes JOB_BASE_ADDR_A/B/C and JOB_DIM_M/N/K.
2. Host writes JOB_A_SRC_BASE / JOB_A_DST_BASE / JOB_A_LOAD_BEATS.
3. Host writes JOB_B_SRC_BASE / JOB_B_DST_BASE / JOB_B_LOAD_BEATS.
4. Host writes JOB_STORE_SRC_BASE / JOB_STORE_DST_BASE / JOB_STORE_BYTE_COUNT.
5. Host writes JOB_MODE:
     INPUT_MODE  = DMA_LOAD
     OUTPUT_MODE = DMA_STORE
6. Host writes START_JOB.
7. Sequencer runs DMA load A.
8. Sequencer runs DMA load B.
9. Sequencer runs GEMM.
10. Sequencer runs DMA store.
11. Host polls JOB_DONE.
12. Test checks DMA destination memory.
```

### 16.3 AXI-Stream Preload + GEMM + DMA Store Job

```text
1. Host writes JOB_BASE_ADDR_A/B/C and JOB_DIM_M/N/K.
2. Host writes JOB_A_SRC_BASE / JOB_A_DST_BASE / JOB_A_LOAD_BEATS.
3. Host writes JOB_B_SRC_BASE / JOB_B_DST_BASE / JOB_B_LOAD_BEATS.
4. Host writes JOB_STORE_SRC_BASE / JOB_STORE_DST_BASE / JOB_STORE_BYTE_COUNT.
5. Host writes JOB_MODE:
     INPUT_MODE  = AXIS_PRELOAD
     OUTPUT_MODE = DMA_STORE
6. Host writes START_JOB.
7. Sequencer runs AXI-Stream preload A.
8. Sequencer runs AXI-Stream preload B.
9. Sequencer runs GEMM.
10. Sequencer runs DMA store.
11. Host polls JOB_DONE.
12. Test checks DMA destination memory.
```

### 16.4 Direct Stream Preload + GEMM + DMA Store Job

```text
1. Host writes JOB_BASE_ADDR_A/B/C and JOB_DIM_M/N/K.
2. Host writes JOB_A_SRC_BASE / JOB_A_DST_BASE / JOB_A_LOAD_BEATS.
3. Host writes JOB_B_SRC_BASE / JOB_B_DST_BASE / JOB_B_LOAD_BEATS.
4. Host writes JOB_STORE_SRC_BASE / JOB_STORE_DST_BASE / JOB_STORE_BYTE_COUNT.
5. Host writes JOB_MODE:
     INPUT_MODE  = DIRECT_STREAM
     OUTPUT_MODE = DMA_STORE
6. Host writes START_JOB.
7. Sequencer runs Direct Stream preload A with ds_operand_sel=0.
8. Sequencer runs Direct Stream preload B with ds_operand_sel=1.
9. Sequencer runs GEMM with GEMM_INPUT_STREAM_MODE=1.
10. Sequencer runs DMA store.
11. Host polls JOB_DONE.
12. Test checks DMA destination memory.
```

### 16.5 C RMW Accumulation Job Sequence

For external partial-K accumulation, software can still launch multiple P15 jobs:

```text
Job 0:
  ACCUMULATE_ENABLE = 0
  START_JOB
  poll JOB_DONE

Job 1:
  ACCUMULATE_ENABLE = 1
  START_JOB
  poll JOB_DONE
```

P15A does not require a hardware multi-job recipe runner.  The sequencer executes one job descriptor at a time.

---

## 17. Verification Plan For P15

### 17.1 Standalone Job Sequencer Tests

A lightweight sequencer-only testbench can mock engine done/error inputs and verify:

```text
reset default state
START_JOB acceptance
START_JOB rejection while busy
zero dimension rejection
zero preload length rejection
zero store length rejection
HOST_PRELOADED state path
DMA_LOAD state path
AXIS_PRELOAD state path
DIRECT_STREAM state path
DMA_STORE optional skip path
stage error stops downstream launches
manual P14 command rejected while job_busy
active descriptor snapshot does not change while CSR regs are rewritten
```

### 17.2 CSR Register Tests

P15B/P15D should include:

```text
job register reset default test
job RW register write/readback test
job byte-strobe test
job command read returns zero test
job done W1C clear test
job error W1C clear test
job reject W1C clear test
unsupported mode reject test
busy START_JOB reject test
```

### 17.3 End-to-End Job Tests

Recommended initial P15C end-to-end tests:

```text
csr_job_dma_load_store_case100
csr_job_dma_load_store_case102
```

Recommended P15F frontend extensions:

```text
csr_job_axis_stream_load_store_case100
csr_job_axis_stream_load_store_case102
csr_job_direct_stream_load_store_case100
csr_job_direct_stream_load_store_case102
```

Recommended later accumulation extension:

```text
csr_job_c_rmw_accum_host_primary_case208
csr_job_c_rmw_accum_dma_load_store_case208
```

### 17.4 Acceptance Criteria

P15 closure should require:

```text
P15A spec reviewed and accepted
Job register / sequencer RTL compiles
Standalone job sequencer tests PASS
Job-level DMA load + GEMM + DMA store representative tests PASS
Job-level AXI-Stream and Direct Stream representative tests PASS when added
Existing P14 micro-operation tests still PASS
Legacy sideband full regression still PASS
New full regression total increases only by targeted P15 representative items
No BRAM RTL changes
No GEMM datapath behavioral changes required for P15A/P15B/P15C
```

---

## 18. P15 Milestone Breakdown

Recommended P15 split:

```text
P15A: Job descriptor / sequencer spec                         PASS
P15B: CSR job register extension and compile integration       Future
P15C: Single-job DMA load -> GEMM -> DMA store sequencer       Future
P15D: Job-level UVM smoke CASE_ID=100 / CASE_ID=102            Future
P15E: Error / reject / busy / snapshot validation              Future
P15F: AXI-Stream and Direct Stream job input modes             Future
P15G: Full regression and documentation closure                Future
```

---

## 19. Open Decisions Before P15B

These should be confirmed before writing RTL:

```text
1. Should the job descriptor be integrated into ai_accel_csr_regs.sv or split into a small job CSR submodule?
   Recommended: integrate the CSR storage into ai_accel_csr_regs.sv first, then refactor only if needed.

2. Should P14 micro-operation commands remain available while no job is active?
   Recommended: yes, for debug and backward compatibility.

3. Should P14 micro-operation commands be rejected while job_busy is high?
   Recommended: yes.

4. Should descriptor registers be writable while job_busy is high?
   Recommended: yes, but active job uses a START_JOB snapshot.

5. Should P15 implement hardware timeout counters?
   Recommended: no for P15C; keep timeouts in UVM first.

6. Should START_JOB automatically clear P14 sticky done/error bits?
   Recommended: no by default.  Use raw done/error pulses internally and keep P14 status independent.

7. Should START_JOB require previous JOB_DONE/JOB_ERROR to be cleared?
   Recommended: no for JOB_DONE, yes or reject for sticky JOB_ERROR until CLEAR_JOB_ERROR is written.

8. Should HOST_PRELOADED + DMA_STORE be supported?
   Recommended: yes; it is useful for host-preload plus DMA-store result movement.

9. Should DMA_LOAD + HOST_READBACK be supported?
   Recommended: yes; it is useful for DMA-preload plus host-readback debug.

10. Should Direct Stream mode force GEMM_INPUT_STREAM_MODE=1 regardless of CSR_MODE?
    Recommended: yes; job mode should derive the required GEMM mode.
```

---

## 20. Risks and Mitigations

### Risk 1: Descriptor Reprogramming Race

Potential failure:

```text
Software rewrites descriptor registers while a job is active and changes the running job.
```

Mitigation:

```text
Latch an active descriptor snapshot on accepted START_JOB.
Use the snapshot for all sequencer stages.
```

### Risk 2: Manual CSR Command Conflict

Potential failure:

```text
Software issues START_DMA_LOAD while the job sequencer is also using DMA load.
```

Mitigation:

```text
Reject P14 manual START_* commands while job_busy is high.
```

### Risk 3: Store Starts Before C Is Visible

Potential failure:

```text
Sequencer starts DMA store before GEMM final C write is visible.
```

Mitigation:

```text
Only transition to STORE_SETUP after acc_done.
Rely on existing GEMM completion contract that done means final C is visible.
Run immediate GEMM-done -> DMA-store tests.
```

### Risk 4: Wrong GEMM Mode For Direct Stream

Potential failure:

```text
Direct Stream preloads A/B into operand buffer, but GEMM starts in scratchpad mode.
```

Mitigation:

```text
Derive gemm_input_stream_mode from JOB_MODE.INPUT_MODE.
For DIRECT_STREAM, force gemm_input_stream_mode=1.
```

### Risk 5: Wrong Operand Select In Direct Stream B Load

Potential failure:

```text
Direct Stream B preload accidentally writes operand A buffer again.
```

Mitigation:

```text
Sequencer drives ds_operand_sel=0 for A stage and ds_operand_sel=1 for B stage.
Check CASE_ID=102 with non-identical A/B payloads.
```

### Risk 6: Sticky Status Dependency Bug

Potential failure:

```text
Sequencer waits on old P14 sticky done bits instead of fresh done pulses.
```

Mitigation:

```text
Sequencer waits on live done/error pulses from the subsystem.
P14 sticky status remains software-visible but is not used for job stage completion.
```

### Risk 7: Error Path Starts Downstream Stage

Potential failure:

```text
A preload error occurs, but sequencer still starts GEMM.
```

Mitigation:

```text
Every wait state must branch to ERROR before any downstream setup/start state.
Run injected error tests for each frontend path.
```

### Risk 8: Regression Runtime Growth

Potential failure:

```text
Job-level tests duplicate existing P14 micro-op tests and make full regression too slow.
```

Mitigation:

```text
Add only representative CASE_ID=100 and CASE_ID=102 for each selected job path.
Keep broader P14 micro-op coverage unchanged.
```

---

## 21. Summary

P15 adds a single-job hardware sequencer on top of the completed P14 CSR control plane.

The design converts this software-visible micro-operation sequence:

```text
START_LOAD_A
START_LOAD_B
START_GEMM
START_STORE_C
```

into this software-visible job sequence:

```text
write descriptor
START_JOB
poll JOB_DONE / JOB_ERROR
```

The first implementation should remain conservative:

```text
single outstanding job
CSR-resident descriptor
no descriptor queue
no overlap pipeline
no BRAM changes
no GEMM datapath behavioral changes
P14 micro-operation commands preserved when job sequencer is idle
```

This gives the project a realistic job-based accelerator control model while preserving the validated datapath and verification foundation built through P14.
