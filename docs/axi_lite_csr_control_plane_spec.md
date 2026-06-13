# AXI-Lite CSR Control Plane Spec

## 1. Purpose

This document defines the AXI-Lite control-plane specification for the AI Accelerator Subsystem.  It records the canonical CSR address map, register access types, reset values, and register bit definitions for the P14 CSR shell and the later P15/P16/P17/P18/P19 CSR extensions.

The subsystem already has a stable GEMM datapath and multiple validated data movement frontends.  P14 adds a lightweight software-visible control plane so a host can program, launch, poll, and observe the accelerator through control/status registers instead of driving top-level sideband control wires directly.

P14 is intentionally scoped as a minimal CSR shell.  It is not a descriptor engine, interrupt controller, software driver, or UVM RAL model.  P15 builds on the same CSR shell by adding a CSR-resident single-job descriptor and hardware job sequencer above the P14 micro-operation command model.  P16 adds CSR-resident recipes, P17 adds memory-backed descriptor fetch, P18 adds completion writeback, P19 adds a host-visible command / completion queue CSR window, P20 validates multi-entry in-order queue drain behavior using that same P19 queue window, P21 validates runtime doorbell / live queue service behavior without adding new CSR addresses, and P22 adds a lightweight event notification / interrupt-lite CSR window above the queue status model.

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
Full UVM regression baseline passing 121/121 after P21G runtime doorbell / live queue service closure
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

P14 keeps the existing datapath subsystem intact and adds a CSR programming layer around it.  P15 preserves that wrapper and adds a higher-level job descriptor window above the P14 micro-operation registers.  Later CSR windows extend the same wrapper without changing the stable BRAM, GEMM, DMA, AXI-Stream, or Direct Stream datapaths.

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


The CSR address space is partitioned by milestone-owned windows:

```text
P14 micro-operation CSR window : 0x000 - 0x08C
P15 job CSR window             : 0x100 - 0x18C
P16 recipe CSR window          : 0x200 - 0x28C
P16 slot CSR window            : 0x300 - 0x4FC
P17 descriptor fetch window    : 0x500 - 0x53C
P18 completion writeback window: 0x540 - 0x57C
P19 queue window               : 0x580 - 0x5FC
P22 event notification window  : 0x600 - 0x63C
```

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


### 9.2 P19 Queue CSR Register Window

P19B freezes the software-visible queue CSR window used by the P19 command / completion queue controller.

P18 uses the `0x540 - 0x57C` completion-writeback CSR window.  P19 adds a queue CSR window immediately after P18.

Frozen P19B CSR base:

```text
P19 queue CSR base = 0x580
```

Existing windows remain unchanged:

```text
P14 micro-operation CSR window : 0x000 - 0x08C
P15 job CSR window             : 0x100 - 0x18C
P16 recipe CSR window          : 0x200 - 0x28C
P16 slot CSR window            : 0x300 - 0x4FC
P17 descriptor fetch window    : 0x500 - 0x53C
P18 completion writeback window: 0x540 - 0x57C
P19 queue window               : 0x580 - 0x5FC
P22 event notification window  : 0x600 - 0x63C
```

P19B does not add RTL, UVM tests, Tcl scripts, README updates, or regression-list items.  It freezes the queue register map and bit definitions so P19C/P19D implementation can use stable constants.

#### 9.2.1 Register Map

| Offset | Name | Access | Reset | Description |
|---:|---|---|---:|---|
| 0x580 | `CSR_QUEUE_VERSION` | RO | `0x0001_0019` | Queue controller version / feature ID. |
| 0x584 | `CSR_QUEUE_COMMAND` | W1P | 0 | Queue start/kick, stop request, pointer reset, and sticky clear commands. |
| 0x588 | `CSR_QUEUE_STATUS` | RO | implementation | Live queue status summary. |
| 0x58C | `CSR_QUEUE_DONE_STATUS` | RO/W1C | 0 | Sticky queue started / drained / command-completed status. |
| 0x590 | `CSR_QUEUE_ERROR_STATUS` | RO/W1C | 0 | Sticky queue error status. |
| 0x594 | `CSR_QUEUE_CONTROL` | RW | `0x0000_001F` | Queue policy bits. |
| 0x598 | `CSR_QUEUE_REJECT_STATUS` | RO/W1C | 0 | Sticky queue command/config reject reasons. |
| 0x59C | `CSR_QUEUE_STATE` | RO | 0 | Current queue controller FSM state. |
| 0x5A0 | `CSR_SQ_BASE_ADDR` | RW | 0 | Submission queue base address. |
| 0x5A4 | `CSR_SQ_DEPTH` | RW | 0 | Submission queue depth in 64-byte entries. |
| 0x5A8 | `CSR_SQ_HEAD` | RO | 0 | Hardware-owned consumed-command counter. |
| 0x5AC | `CSR_SQ_TAIL` | RW | 0 | Host-owned produced-command counter / doorbell value. |
| 0x5B0 | `CSR_SQ_STRIDE` | RW | `0x0000_0040` | Submission queue entry stride in bytes. |
| 0x5B4 | `CSR_CQ_BASE_ADDR` | RW | 0 | Completion queue base address. |
| 0x5B8 | `CSR_CQ_DEPTH` | RW | 0 | Completion queue depth in 64-byte entries. |
| 0x5BC | `CSR_CQ_HEAD` | RW | 0 | Host-owned consumed-completion counter. |
| 0x5C0 | `CSR_CQ_TAIL` | RO | 0 | Hardware-owned produced-completion counter. |
| 0x5C4 | `CSR_CQ_STRIDE` | RW | `0x0000_0040` | Completion queue entry stride in bytes. |
| 0x5C8 | `CSR_QUEUE_CURRENT_INDEX` | RO | 0 | Current SQ physical index being fetched or executed. |
| 0x5CC | `CSR_QUEUE_COMPLETED_COUNT` | RO | 0 | Number of commands completed through CQ commit. |
| 0x5D0 | `CSR_QUEUE_ERROR_INDEX` | RO | 0 | SQ physical index associated with the last queue error. |
| 0x5D4 | `CSR_QUEUE_ERROR_DETAIL` | RO | 0 | Queue-level error detail. |
| 0x5D8 | `CSR_QUEUE_LAST_CMD_TAG` | RO | 0 | Last accepted command user tag. |
| 0x5DC | `CSR_QUEUE_LAST_CMD_CONTROL` | RO | 0 | Last accepted command control word. |
| 0x5E0 | `CSR_QUEUE_SQ_OCCUPANCY` | RO | 0 | Computed submission-queue occupancy. |
| 0x5E4 | `CSR_QUEUE_CQ_OCCUPANCY` | RO | 0 | Computed completion-queue occupancy. |
| 0x5E8 | `CSR_QUEUE_CQ_SPACE` | RO | 0 | Computed completion-queue free entries. |
| 0x5EC | `CSR_QUEUE_RESERVED_5EC` | RO | 0 | Reserved. |
| 0x5F0 | `CSR_QUEUE_RESERVED_5F0` | RO | 0 | Reserved. |
| 0x5F4 | `CSR_QUEUE_RESERVED_5F4` | RO | 0 | Reserved. |
| 0x5F8 | `CSR_QUEUE_RESERVED_5F8` | RO | 0 | Reserved. |
| 0x5FC | `CSR_QUEUE_RESERVED_5FC` | RO | 0 | Reserved. |

#### 9.2.2 Register Ownership Summary

| Register | Owner | Write Policy |
|---|---|---|
| `CSR_SQ_BASE_ADDR` | Host | Program while queue is idle. |
| `CSR_SQ_DEPTH` | Host | Program while queue is idle. |
| `CSR_SQ_HEAD` | Hardware | Read-only to host. |
| `CSR_SQ_TAIL` | Host | May be written as a doorbell value, including while `queue_busy=1` for P21 live service. |
| `CSR_SQ_STRIDE` | Host | Program while queue is idle. |
| `CSR_CQ_BASE_ADDR` | Host | Program while queue is idle. |
| `CSR_CQ_DEPTH` | Host | Program while queue is idle. |
| `CSR_CQ_HEAD` | Host | May be written after host consumes CQ entries, including during CQ-full live-service recovery. |
| `CSR_CQ_TAIL` | Hardware | Read-only to host. |
| `CSR_CQ_STRIDE` | Host | Program while queue is idle. |

Queue base/depth/stride configuration writes while `queue_busy` is high are ignored and set `CSR_QUEUE_REJECT_STATUS.CONFIG_WRITE_BUSY_REJECT`.  `CSR_SQ_TAIL` and `CSR_CQ_HEAD` remain host-owned queue pointer updates and may be written while the queue controller is enabled or busy.  P21 constrains the hardware observation points for these live updates to command-boundary checks and CQ-full stall checks; active-command SQ/CQ addresses are taken from the command snapshot.

#### 9.2.3 Queue Configuration Validation

A queue configuration is valid when:

```text
CSR_QUEUE_CONTROL.QUEUE_ENABLE == 1
CSR_SQ_BASE_ADDR is DATA_WIDTH-byte aligned
CSR_CQ_BASE_ADDR is DATA_WIDTH-byte aligned
CSR_SQ_DEPTH is non-zero
CSR_CQ_DEPTH is non-zero
CSR_SQ_DEPTH <= P19_QUEUE_MAX_DEPTH
CSR_CQ_DEPTH <= P19_QUEUE_MAX_DEPTH
CSR_SQ_DEPTH is a power of two
CSR_CQ_DEPTH is a power of two
CSR_SQ_STRIDE == 0x40 for P19B
CSR_CQ_STRIDE == 0x40 for P19B
CSR_SQ_TAIL >= CSR_SQ_HEAD before 32-bit counter wrap
CSR_CQ_TAIL >= CSR_CQ_HEAD before 32-bit counter wrap
SQ occupancy <= SQ depth
CQ occupancy <= CQ depth
```

P19B deliberately keeps the first implementation simple by requiring 64-byte SQ and CQ strides.  The registers remain RW for forward compatibility, but any non-`0x40` stride is rejected by the queue configuration checker in the P19B/P19C prototype.

#### 9.2.4 Occupancy and Index Calculation

The first implementation treats queue pointers as monotonic 32-bit counters and does not rely on raw wrapped physical pointers.

```text
sq_occupancy = CSR_SQ_TAIL - CSR_SQ_HEAD
cq_occupancy = CSR_CQ_TAIL - CSR_CQ_HEAD
cq_space     = CSR_CQ_DEPTH - cq_occupancy

sq_index = CSR_SQ_HEAD[log2(SQ_DEPTH)-1:0]
cq_index = CSR_CQ_TAIL[log2(CQ_DEPTH)-1:0]
```

P19B assumes tests do not run enough commands to wrap the 32-bit counters.  Counter wrap support can be added later without changing the visible register map.

#### 9.2.5 Address Calculation

```text
SQ entry address = CSR_SQ_BASE_ADDR + (sq_index * CSR_SQ_STRIDE)
CQ entry address = CSR_CQ_BASE_ADDR + (cq_index * CSR_CQ_STRIDE)
```

P19B queue entries are fixed at 64 bytes.  The command fetch engine reads one 64-byte SQ entry.  The completion writeback path writes one existing P18 64-byte completion record into the selected CQ entry.

---


### 9.3 P22 Event Notification / Interrupt-Lite CSR Register Window

P22B freezes the software-visible event notification CSR window used by the P22 interrupt-lite layer.

P19/P20/P21 use the `0x580 - 0x5FC` queue CSR window.  P22 adds a small event notification CSR window immediately after the queue window.

Frozen P22B CSR base:

```text
P22 event notification CSR base = 0x600
```

Existing windows remain unchanged:

```text
P14 micro-operation CSR window : 0x000 - 0x08C
P15 job CSR window             : 0x100 - 0x18C
P16 recipe CSR window          : 0x200 - 0x28C
P16 slot CSR window            : 0x300 - 0x4FC
P17 descriptor fetch window    : 0x500 - 0x53C
P18 completion writeback window: 0x540 - 0x57C
P19 queue window               : 0x580 - 0x5FC
P22 event notification window  : 0x600 - 0x63C
```

P22B does not add RTL, UVM tests, Tcl scripts, README updates, or regression-list items.  It freezes the event register map and bit definitions so later P22 RTL and UVM milestones can use stable constants.

#### 9.3.1 Register Map

| Offset | Name | Access | Reset | Description |
|---:|---|---|---:|---|
| 0x600 | `CSR_EVENT_VERSION` | RO | `0x0001_0022` | Event notification / interrupt-lite version and feature ID. |
| 0x604 | `CSR_EVENT_COMMAND` | W1P | 0 | Event pending clear, counter clear, snapshot clear, and software test-event command. |
| 0x608 | `CSR_EVENT_STATUS` | RO | implementation | Live event / interrupt summary. |
| 0x60C | `CSR_EVENT_PENDING` | RO/W1C | 0 | Sticky event pending bits. |
| 0x610 | `CSR_EVENT_ENABLE` | RW | 0 | Per-event interrupt enable bits. Pending capture is independent of this mask. |
| 0x614 | `CSR_EVENT_CONTROL` | RW | `0x0000_0004` | Global interrupt enable and event snapshot policy. |
| 0x618 | `CSR_EVENT_LAST_CAUSE` | RO | 0 | Last captured event cause bit index and source class. |
| 0x61C | `CSR_EVENT_COUNT` | RO | 0 | Number of captured event source firings. |
| 0x620 | `CSR_EVENT_QUEUE_SNAPSHOT0` | RO | 0 | Queue pointer snapshot for the last event. |
| 0x624 | `CSR_EVENT_QUEUE_SNAPSHOT1` | RO | 0 | Queue status / done / error snapshot for the last event. |
| 0x628 | `CSR_EVENT_CQ_THRESHOLD` | RW | 0 | Optional CQ occupancy threshold for threshold event generation. 0 disables threshold events. |
| 0x62C | `CSR_EVENT_IRQ_COUNT` | RO | 0 | Number of interrupt-eligible event assertions. |
| 0x630 | `CSR_EVENT_RESERVED_630` | RO | 0 | Reserved. |
| 0x634 | `CSR_EVENT_RESERVED_634` | RO | 0 | Reserved. |
| 0x638 | `CSR_EVENT_RESERVED_638` | RO | 0 | Reserved. |
| 0x63C | `CSR_EVENT_RESERVED_63C` | RO | 0 | Reserved. |

#### 9.3.2 Event Register Ownership Summary

| Register | Owner | Write Policy |
|---|---|---|
| `CSR_EVENT_COMMAND` | Host | Write-one-pulse commands. Reads return zero. |
| `CSR_EVENT_STATUS` | Hardware | Read-only live event / interrupt summary. |
| `CSR_EVENT_PENDING` | Hardware set / host W1C clear | Host clears sticky event bits after observing the event. |
| `CSR_EVENT_ENABLE` | Host | May be programmed while the queue is idle or active. Controls interrupt generation only. |
| `CSR_EVENT_CONTROL` | Host | May be programmed while the queue is idle or active. Controls global interrupt enable and snapshot policy. |
| `CSR_EVENT_LAST_CAUSE` | Hardware | Debug snapshot of the last event source. |
| `CSR_EVENT_COUNT` | Hardware | Incremented on captured event source firings. |
| `CSR_EVENT_QUEUE_SNAPSHOT0/1` | Hardware | Debug snapshot when an event is captured. |
| `CSR_EVENT_CQ_THRESHOLD` | Host | Optional threshold value. 0 disables threshold events. |
| `CSR_EVENT_IRQ_COUNT` | Hardware | Incremented when a new event is interrupt-eligible. |

P22 event pending capture is independent of interrupt enable.  Events are captured in `CSR_EVENT_PENDING` even when `CSR_EVENT_ENABLE` is zero or `CSR_EVENT_CONTROL.GLOBAL_IRQ_ENABLE` is zero.

#### 9.3.3 Event Source Summary

P22B freezes these first event sources:

```text
QUEUE_COMMAND_COMPLETED_EVENT
QUEUE_DRAINED_EVENT
QUEUE_STOPPED_EVENT
QUEUE_ERROR_EVENT
CQ_NOT_EMPTY_EVENT
CQ_THRESHOLD_EVENT
CQ_FULL_STALL_EVENT
CQ_SPACE_RECOVERED_EVENT
RUNTIME_DOORBELL_EVENT
RUNTIME_APPEND_CONSUMED_EVENT
TEST_EVENT
```

The event layer is summary-only.  The CQ completion record remains the authoritative per-command completion detail.

Queue command-completed event generation is tied to the existing P18/P19/P20/P21 completion-commit point:

```text
P18 completion record final commit succeeds
    -> P19/P20/P21 advances CQ_TAIL
    -> P22 sets QUEUE_COMMAND_COMPLETED_EVENT
```

Runtime doorbell events are tied to P21 live-service semantics:

```text
host writes CSR_SQ_TAIL while queue_busy=1
    -> P22 may set RUNTIME_DOORBELL_EVENT
hardware later accepts the appended command at a command boundary
    -> P22 may set RUNTIME_APPEND_CONSUMED_EVENT
```

#### 9.3.4 Interrupt-Lite Output Policy

The P22 notification layer may expose one wrapper-level interrupt output:

```systemverilog
output logic event_irq
```

Recommended first implementation:

```text
event_irq = CSR_EVENT_CONTROL.GLOBAL_IRQ_ENABLE && |(CSR_EVENT_PENDING & CSR_EVENT_ENABLE)
```

In the default level mode, `event_irq` remains asserted until software clears all enabled pending bits.  Pulse mode is reserved by `CSR_EVENT_CONTROL.IRQ_PULSE_MODE` for later validation and can remain tied off in the first RTL checkpoint.


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


### 10.9 P19 Queue Command / Status Registers

The P19 queue registers use the same AXI-Lite access policy and the same W1P/W1C definitions as the earlier CSR windows.

#### 10.9.1 `CSR_QUEUE_VERSION` at 0x580

| Bits | Name | Access | Reset | Description |
|---:|---|---|---:|---|
| [31:16] | `MAJOR` | RO | 16'h0001 | Queue controller major version. |
| [15:8] | `MINOR` | RO | 8'h00 | Queue controller minor version. |
| [7:0] | `FEATURE_ID` | RO | 8'h19 | P19 queue controller feature ID. |

Reset value:

```text
0x0001_0019
```

#### 10.9.2 `CSR_QUEUE_COMMAND` at 0x584

This is a write-one-pulse register.  Reads return zero.

| Bit | Name | Type | Description |
|---:|---|---|---|
| 0 | `START_QUEUE` | W1P | Enable / kick queue processing if accepted. |
| 1 | `STOP_QUEUE` | W1P | Request the queue controller to stop after the current command. |
| 8 | `CLEAR_QUEUE_DONE` | W1P | Clear queue done / idle sticky bits. |
| 9 | `CLEAR_QUEUE_ERROR` | W1P | Clear queue error and reject sticky bits. |
| 10 | `CLEAR_QUEUE_COUNTERS` | W1P | Clear completed count and last-command debug snapshots. |
| 11 | `RESET_QUEUE_POINTERS` | W1P | Reset SQ/CQ head/tail counters when the queue is idle. |
| 31:12, 7:2 | `RSVD` | — | Reserved. |

Unsupported combinations:

```text
START_QUEUE while queue_busy is high
START_QUEUE while QUEUE_ENABLE=0
START_QUEUE while queue error sticky is set and CLEAR_QUEUE_ERROR is not requested
START_QUEUE with invalid queue configuration
RESET_QUEUE_POINTERS while queue_busy is high
unsupported command bits in the same write
```

Unsupported combinations do not start queue processing and set `CSR_QUEUE_REJECT_STATUS`.

#### 10.9.3 `CSR_QUEUE_STATUS` at 0x588

| Bit | Name | Access | Description |
|---:|---|---|---|
| 0 | `QUEUE_BUSY` | RO | Queue controller is fetching, executing, or completing a command. |
| 1 | `QUEUE_DONE` | RO | Sticky queue done / drained / stopped status is set. |
| 2 | `QUEUE_ERROR` | RO | Sticky queue error or reject status is set. |
| 3 | `QUEUE_ACCEPT_READY` | RO | Queue controller is idle and can accept `START_QUEUE`. |
| 4 | `QUEUE_ENABLED` | RO | Queue processing is enabled by `CSR_QUEUE_CONTROL.QUEUE_ENABLE`. |
| 5 | `SQ_EMPTY` | RO | Submission queue has no unconsumed entries. |
| 6 | `CQ_FULL` | RO | Completion queue has no free entries. |
| 7 | `QUEUE_STALLED` | RO | Queue is enabled but waiting for SQ entry, CQ space, or lower-level idle. |
| 8 | `CMD_FETCH_BUSY` | RO | Command queue fetch is active. |
| 9 | `DESC_FETCH_BUSY` | RO | P17 descriptor fetch is busy. |
| 10 | `RECIPE_BUSY` | RO | P16 recipe sequencer is busy. |
| 11 | `COMP_BUSY` | RO | P18 completion writeback is busy. |
| 12 | `UNDERLYING_BUSY` | RO | Any lower-level P17/P18/P16/P15/P14 engine is busy. |
| 16 | `CSR_READY` | RO | CSR block ready for transactions. |

#### 10.9.4 `CSR_QUEUE_DONE_STATUS` at 0x58C

Sticky done bits are cleared by W1C writes or by `CSR_QUEUE_COMMAND.CLEAR_QUEUE_DONE`.

| Bit | Name | Type | Description |
|---:|---|---|---|
| 0 | `QUEUE_STARTED` | RO/W1C | `START_QUEUE` was accepted. |
| 1 | `QUEUE_DRAINED` | RO/W1C | Queue reached SQ empty after processing available commands. |
| 2 | `COMMAND_COMPLETED` | RO/W1C | At least one command completed and committed to CQ. |
| 3 | `STOPPED_AFTER_COMMAND` | RO/W1C | Queue stopped due to `STOP_QUEUE` or `STOP_AFTER_THIS`. |

#### 10.9.5 `CSR_QUEUE_ERROR_STATUS` at 0x590

Sticky error bits are cleared by W1C writes or by `CSR_QUEUE_COMMAND.CLEAR_QUEUE_ERROR`.

| Bit | Name | Type | Description |
|---:|---|---|---|
| 0 | `CMD_FETCH_ERROR` | RO/W1C | Command queue AXI read returned error or malformed response. |
| 1 | `CMD_VALIDATION_ERROR` | RO/W1C | Command entry failed validation after fetch. |
| 2 | `DESC_FETCH_ERROR` | RO/W1C | P17 descriptor fetch error propagated to queue level. |
| 3 | `RECIPE_ERROR` | RO/W1C | P16 recipe error propagated to queue level. |
| 4 | `COMPLETION_WB_ERROR` | RO/W1C | P18 completion writeback error propagated to queue level. |
| 5 | `QUEUE_POINTER_ERROR` | RO/W1C | Queue pointer configuration or occupancy calculation invalid. |
| 6 | `CQ_FULL_TIMEOUT_ERROR` | RO/W1C | Reserved for future timeout policy. P19B stalls on CQ full. |
| 7 | `CONFIG_WRITE_BUSY_ERROR` | RO/W1C | Queue base/depth/stride config write attempted while queue busy. |
| 8 | `INTERNAL_SEQUENCE_ERROR` | RO/W1C | Queue FSM reached an illegal state or unexpected terminal condition. |

#### 10.9.6 `CSR_QUEUE_CONTROL` at 0x594

| Bits | Name | Access | Reset | Description |
|---:|---|---|---:|---|
| 0 | `QUEUE_ENABLE` | RW | 1 | Queue processing may accept `START_QUEUE`. |
| 1 | `RUN_UNTIL_EMPTY` | RW | 1 | Continue processing commands until SQ empty. If 0, process one command per `START_QUEUE`. |
| 2 | `STOP_ON_ERROR` | RW | 1 | Stop queue processing after a command error. |
| 3 | `WRITE_COMPLETION_ON_CMD_REJECT` | RW | 1 | Attempt a CQ completion for fetched command validation rejects. |
| 4 | `AUTO_CLEAR_P17_P18_ON_START` | RW | 1 | Clear relevant P17/P18 sticky status before launching a command. |
| 31:5 | `RSVD` | RO | 0 | Reserved. |

Reset value:

```text
0x0000_001F
```

#### 10.9.7 `CSR_QUEUE_REJECT_STATUS` at 0x598

Sticky reject bits are cleared by W1C writes or by `CSR_QUEUE_COMMAND.CLEAR_QUEUE_ERROR`.

| Bit | Name | Type | Description |
|---:|---|---|---|
| 0 | `QUEUE_BUSY_REJECT` | RO/W1C | `START_QUEUE` requested while `queue_busy` is high. |
| 1 | `QUEUE_DISABLED_REJECT` | RO/W1C | `START_QUEUE` requested while `QUEUE_ENABLE=0`. |
| 2 | `INVALID_QUEUE_CONFIG_REJECT` | RO/W1C | Base/depth/stride/pointer configuration invalid. |
| 3 | `UNDERLYING_BUSY_REJECT` | RO/W1C | P17/P18/P16/P15/P14 path busy before queue command acceptance. |
| 4 | `STICKY_ERROR_REJECT` | RO/W1C | `START_QUEUE` requested while uncleared queue error is sticky. |
| 5 | `UNSUPPORTED_COMMAND_COMBO` | RO/W1C | Unsupported bits written to `CSR_QUEUE_COMMAND`. |
| 6 | `RESET_POINTERS_BUSY_REJECT` | RO/W1C | `RESET_QUEUE_POINTERS` requested while `queue_busy` is high. |
| 7 | `CONFIG_WRITE_BUSY_REJECT` | RO/W1C | Queue base/depth/stride config write attempted while `queue_busy` is high. |

#### 10.9.8 `CSR_QUEUE_STATE` at 0x59C

Recommended first implementation state encodings:

| Value | Name | Meaning |
|---:|---|---|
| 0 | `Q_IDLE` | Queue controller idle. |
| 1 | `Q_CHECK_READY` | Check SQ occupancy, CQ space, and lower-level idle state. |
| 2 | `Q_FETCH_CMD` | Fetch 64-byte SQ command entry. |
| 3 | `Q_VALIDATE_CMD` | Validate fetched command entry. |
| 4 | `Q_PREP_LAUNCH` | Build internal P17/P18 launch context. |
| 5 | `Q_START_DESC_FETCH` | Issue internal P17 descriptor-fetch start. |
| 6 | `Q_WAIT_DESC_FETCH_ACCEPT` | Wait for descriptor-fetch launch acceptance. |
| 7 | `Q_WAIT_RECIPE_TERMINAL` | Wait for fetch failure or recipe terminal status. |
| 8 | `Q_START_COMPLETION` | Request P18 completion writeback to the selected CQ slot. |
| 9 | `Q_WAIT_COMPLETION` | Wait for P18 completion writeback done/error. |
| 10 | `Q_ADVANCE_POINTERS` | Advance SQ/CQ pointers and update debug counters. |
| 11 | `Q_DRAINED` | Queue drained or stopped cleanly. |
| 12 | `Q_ERROR` | Queue terminal error state. |
| 13 | `Q_STALLED` | Queue enabled but waiting for SQ entry, CQ space, or lower-level idle. |

#### 10.9.9 Queue Debug Registers

`CSR_QUEUE_CURRENT_INDEX` reports the current SQ physical index:

```text
CSR_QUEUE_CURRENT_INDEX[7:0]   = current SQ physical index
CSR_QUEUE_CURRENT_INDEX[15:8]  = current CQ physical index
CSR_QUEUE_CURRENT_INDEX[31:16] = reserved
```

`CSR_QUEUE_ERROR_INDEX` reports the last error SQ/CQ physical index with the same packing.

`CSR_QUEUE_ERROR_DETAIL` is implementation-defined.  Recommended first encoding:

| Bits | Name | Description |
|---:|---|---|
| 7:0 | `DETAIL_CODE` | Queue-level debug reason code. |
| 15:8 | `SQ_INDEX` | SQ physical index associated with the detail. |
| 23:16 | `CQ_INDEX` | CQ physical index associated with the detail. |
| 31:24 | `STATE` | Queue FSM state when detail was captured. |

Recommended `DETAIL_CODE` values:

| Value | Name |
|---:|---|
| 0x00 | `DETAIL_NONE` |
| 0x01 | `DETAIL_INVALID_CONFIG` |
| 0x02 | `DETAIL_SQ_EMPTY` |
| 0x03 | `DETAIL_CQ_FULL` |
| 0x04 | `DETAIL_CMD_FETCH_RRESP` |
| 0x05 | `DETAIL_CMD_FETCH_MALFORMED` |
| 0x06 | `DETAIL_CMD_INVALID_CONTROL` |
| 0x07 | `DETAIL_CMD_INVALID_DESC_CFG` |
| 0x08 | `DETAIL_DESC_FETCH_ERROR` |
| 0x09 | `DETAIL_RECIPE_ERROR` |
| 0x0A | `DETAIL_COMPLETION_WB_ERROR` |
| 0x0B | `DETAIL_INTERNAL_SEQUENCE` |

`CSR_QUEUE_LAST_CMD_TAG` captures `CMD_USER_TAG` from the last accepted SQ entry.

`CSR_QUEUE_LAST_CMD_CONTROL` captures `CMD_CONTROL` from the last accepted SQ entry.

#### 10.9.10 P19B Frozen Constants

```text
CSR_QUEUE_BASE_ADDR      = 0x580
CSR_QUEUE_WINDOW_LAST    = 0x5FC
CSR_QUEUE_VERSION_RESET  = 0x0001_0019
CSR_QUEUE_CONTROL_RESET  = 0x0000_001F
P19_SQ_ENTRY_BYTES       = 0x40
P19_CQ_ENTRY_BYTES       = 0x40
P19_SQ_STRIDE_RESET      = 0x0000_0040
P19_CQ_STRIDE_RESET      = 0x0000_0040
P19_FIRST_OPCODE         = 0x01  // fetch descriptor table and run recipe
```

---


### 10.10 P22 Event Notification / Interrupt-Lite Registers

The P22 event registers use the same AXI-Lite access policy and the same W1P/W1C definitions as the earlier CSR windows.

#### 10.10.1 `CSR_EVENT_VERSION` at 0x600

| Bits | Name | Access | Reset | Description |
|---:|---|---|---:|---|
| [31:16] | `MAJOR` | RO | 16'h0001 | Event block major version. |
| [15:8] | `MINOR` | RO | 8'h00 | Event block minor version. |
| [7:0] | `FEATURE_ID` | RO | 8'h22 | P22 event notification / interrupt-lite feature ID. |

Reset value:

```text
0x0001_0022
```

#### 10.10.2 `CSR_EVENT_COMMAND` at 0x604

This is a write-one-pulse register.  Reads return zero.

| Bit | Name | Type | Description |
|---:|---|---|---|
| 0 | `CLEAR_EVENT_PENDING` | W1P | Clear all sticky event pending bits. |
| 1 | `FORCE_TEST_EVENT` | W1P | Generate a software-visible test event for CSR smoke validation. |
| 8 | `CLEAR_EVENT_COUNTERS` | W1P | Clear event count, IRQ count, last cause, and queue snapshots. |
| 31:9, 7:2 | `RSVD` | — | Reserved. |

Unsupported command bits are ignored in the first P22 prototype.  They should not set queue-level errors because the event block is observational.

#### 10.10.3 `CSR_EVENT_STATUS` at 0x608

| Bit | Name | Access | Description |
|---:|---|---|
| 0 | `EVENT_PENDING_NONZERO` | RO | At least one event pending bit is set. |
| 1 | `EVENT_IRQ_ELIGIBLE` | RO | At least one pending bit is enabled by `CSR_EVENT_ENABLE`. |
| 2 | `EVENT_IRQ_OUT` | RO | Current value of the event interrupt-lite output. |
| 3 | `GLOBAL_IRQ_ENABLE` | RO | Mirror of `CSR_EVENT_CONTROL.GLOBAL_IRQ_ENABLE`. |
| 4 | `QUEUE_EVENT_PENDING` | RO | Any queue-level event bit is pending. |
| 5 | `RUNTIME_EVENT_PENDING` | RO | Any P21 runtime doorbell event bit is pending. |
| 6 | `TEST_EVENT_PENDING` | RO | Test event pending bit is set. |
| 31:7 | `RSVD` | RO | Reserved. |

#### 10.10.4 `CSR_EVENT_PENDING` at 0x60C

Sticky pending bits are set by hardware event sources and cleared by W1C writes or by `CSR_EVENT_COMMAND.CLEAR_EVENT_PENDING`.

| Bit | Name | Type | Description |
|---:|---|---|
| 0 | `QUEUE_COMMAND_COMPLETED_EVENT` | RO/W1C | A queue command reached completion commit and CQ_TAIL advanced. |
| 1 | `QUEUE_DRAINED_EVENT` | RO/W1C | The queue reached SQ empty and reported drained. |
| 2 | `QUEUE_STOPPED_EVENT` | RO/W1C | The queue stopped gracefully due to STOP_QUEUE or STOP_AFTER_THIS. |
| 3 | `QUEUE_ERROR_EVENT` | RO/W1C | Queue-level error or reject status became sticky. |
| 4 | `CQ_NOT_EMPTY_EVENT` | RO/W1C | CQ occupancy became non-zero at an event point. |
| 5 | `CQ_THRESHOLD_EVENT` | RO/W1C | CQ occupancy reached or exceeded `CSR_EVENT_CQ_THRESHOLD` when threshold is non-zero. |
| 6 | `CQ_FULL_STALL_EVENT` | RO/W1C | Queue stalled because CQ space was zero. |
| 7 | `CQ_SPACE_RECOVERED_EVENT` | RO/W1C | Host advanced CQ_HEAD and CQ-full stall became recoverable. |
| 8 | `RUNTIME_DOORBELL_EVENT` | RO/W1C | Host updated SQ_TAIL while queue_busy was high. |
| 9 | `RUNTIME_APPEND_CONSUMED_EVENT` | RO/W1C | A runtime-appended SQ command was accepted at a command boundary. |
| 10 | `TEST_EVENT` | RO/W1C | Software-generated test event. |
| 31:11 | `RSVD` | RO/W1C | Reserved. |

Reserved pending bits should read zero.  W1C writes to reserved bits are ignored.

#### 10.10.5 `CSR_EVENT_ENABLE` at 0x610

`CSR_EVENT_ENABLE` uses the same bit positions as `CSR_EVENT_PENDING`.  A set enable bit allows the corresponding pending bit to contribute to `event_irq` when `GLOBAL_IRQ_ENABLE=1`.

| Bit | Name | Access | Reset | Description |
|---:|---|---|---:|---|
| 0 | `QUEUE_COMMAND_COMPLETED_EVENT_EN` | RW | 0 | Enable command-completed event interrupt contribution. |
| 1 | `QUEUE_DRAINED_EVENT_EN` | RW | 0 | Enable drained event interrupt contribution. |
| 2 | `QUEUE_STOPPED_EVENT_EN` | RW | 0 | Enable stopped event interrupt contribution. |
| 3 | `QUEUE_ERROR_EVENT_EN` | RW | 0 | Enable queue-error event interrupt contribution. |
| 4 | `CQ_NOT_EMPTY_EVENT_EN` | RW | 0 | Enable CQ-not-empty event interrupt contribution. |
| 5 | `CQ_THRESHOLD_EVENT_EN` | RW | 0 | Enable CQ-threshold event interrupt contribution. |
| 6 | `CQ_FULL_STALL_EVENT_EN` | RW | 0 | Enable CQ-full-stall event interrupt contribution. |
| 7 | `CQ_SPACE_RECOVERED_EVENT_EN` | RW | 0 | Enable CQ-space-recovered event interrupt contribution. |
| 8 | `RUNTIME_DOORBELL_EVENT_EN` | RW | 0 | Enable runtime-doorbell event interrupt contribution. |
| 9 | `RUNTIME_APPEND_CONSUMED_EVENT_EN` | RW | 0 | Enable runtime-append-consumed event interrupt contribution. |
| 10 | `TEST_EVENT_EN` | RW | 0 | Enable test-event interrupt contribution. |
| 31:11 | `RSVD` | RO | 0 | Reserved. |

Pending bits are captured even when their enable bits are zero.

#### 10.10.6 `CSR_EVENT_CONTROL` at 0x614

| Bit | Name | Access | Reset | Description |
|---:|---|---|---:|---|
| 0 | `GLOBAL_IRQ_ENABLE` | RW | 0 | Enable the shared event interrupt-lite output. |
| 1 | `IRQ_PULSE_MODE` | RW | 0 | 0 = level while enabled pending is non-zero. 1 = one-cycle pulse on new enabled event. Pulse mode may remain reserved in first RTL. |
| 2 | `CAPTURE_QUEUE_SNAPSHOTS` | RW | 1 | Capture queue pointer/status snapshots when an event fires. |
| 3 | `COUNT_TEST_EVENTS` | RW | 0 | Include software-forced test events in `CSR_EVENT_COUNT`. |
| 31:4 | `RSVD` | RO | 0 | Reserved. |

Reset value:

```text
0x0000_0004
```

#### 10.10.7 `CSR_EVENT_LAST_CAUSE` at 0x618

Recommended encoding:

```text
[7:0]   last event bit index
[15:8]  event source class
[23:16] queue FSM state snapshot, if available
[31:24] reserved
```

Recommended event source class values:

| Value | Name |
|---:|---|
| 0x00 | `EVENT_SRC_NONE` |
| 0x01 | `EVENT_SRC_QUEUE_COMPLETION` |
| 0x02 | `EVENT_SRC_QUEUE_TERMINAL` |
| 0x03 | `EVENT_SRC_QUEUE_ERROR` |
| 0x04 | `EVENT_SRC_CQ_BACKPRESSURE` |
| 0x05 | `EVENT_SRC_RUNTIME_DOORBELL` |
| 0x06 | `EVENT_SRC_SOFTWARE_TEST` |

#### 10.10.8 `CSR_EVENT_COUNT` at 0x61C

`CSR_EVENT_COUNT` increments whenever an event source sets at least one pending bit.  It is cleared by `CSR_EVENT_COMMAND.CLEAR_EVENT_COUNTERS`.

If multiple event bits are generated by the same source in one cycle, the first implementation may count that as one event-source firing.

#### 10.10.9 `CSR_EVENT_QUEUE_SNAPSHOT0` at 0x620

Recommended encoding:

```text
[7:0]    SQ_HEAD low byte
[15:8]   SQ_TAIL low byte
[23:16]  CQ_HEAD low byte
[31:24]  CQ_TAIL low byte
```

A later implementation may widen or reinterpret the snapshot fields without changing the CSR address.

#### 10.10.10 `CSR_EVENT_QUEUE_SNAPSHOT1` at 0x624

Recommended encoding:

```text
[7:0]    CSR_QUEUE_STATUS[7:0]
[15:8]   CSR_QUEUE_DONE_STATUS[7:0]
[23:16]  CSR_QUEUE_ERROR_STATUS[7:0]
[31:24]  CSR_QUEUE_REJECT_STATUS[7:0]
```

#### 10.10.11 `CSR_EVENT_CQ_THRESHOLD` at 0x628

`CSR_EVENT_CQ_THRESHOLD` is an optional CQ occupancy threshold.

```text
0 disables threshold event generation
non-zero threshold generates CQ_THRESHOLD_EVENT when CQ occupancy is greater than or equal to the programmed value at an event sampling point
```

The threshold is a debug/notification policy field only.  It does not affect CQ full stall behavior.

#### 10.10.12 `CSR_EVENT_IRQ_COUNT` at 0x62C

`CSR_EVENT_IRQ_COUNT` increments when a newly captured event is interrupt-eligible:

```text
GLOBAL_IRQ_ENABLE=1
and at least one newly captured event bit is enabled in CSR_EVENT_ENABLE
```

It is cleared by `CSR_EVENT_COMMAND.CLEAR_EVENT_COUNTERS`.

#### 10.10.13 P22B Frozen Constants

```text
CSR_EVENT_BASE_ADDR          = 0x600
CSR_EVENT_WINDOW_LAST        = 0x63C
CSR_EVENT_VERSION_RESET      = 0x0001_0022
CSR_EVENT_CONTROL_RESET      = 0x0000_0004
P22_EVENT_QUEUE_COMPLETED    = 0
P22_EVENT_QUEUE_DRAINED      = 1
P22_EVENT_QUEUE_STOPPED      = 2
P22_EVENT_QUEUE_ERROR        = 3
P22_EVENT_CQ_NOT_EMPTY       = 4
P22_EVENT_CQ_THRESHOLD       = 5
P22_EVENT_CQ_FULL_STALL      = 6
P22_EVENT_CQ_SPACE_RECOVERED = 7
P22_EVENT_RUNTIME_DOORBELL   = 8
P22_EVENT_RUNTIME_CONSUMED   = 9
P22_EVENT_TEST               = 10
```


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


---

### 9.6 P18 Completion Writeback Validation Checkpoint

P18H closes the completion-writeback prototype through full-regression integration.

```text
P18A: Completion writeback prototype spec                              PASS
P18B: Completion record format / CSR map freeze                        PASS
P18C: Completion writeback engine RTL / compile smoke                  PASS
P18D: CSR plumbing + standalone completion writeback smoke              PASS
P18E: Descriptor-fetch DMA recipe + completion writeback validation     PASS
P18F: C RMW + Direct Stream completion writeback validation             PASS
P18G: Completion writeback error / busy / sticky clear handling         PASS
P18H: Full regression integration                                      PASS

Full regression after P18H:
  TOTAL : 110
  PASS  : 110
  FAIL  : 0
```

Validated P18 full-regression representatives:

```text
csr_completion_wb_smoke
csr_desc_fetch_dma_completion_wb_case102
csr_desc_fetch_direct_stream_completion_wb_case102
csr_desc_fetch_c_rmw_completion_wb_case208
csr_completion_wb_error_busy_clear
```

P18 uses two TB-only fault-injection interfaces for validation:

```text
desc_src_inject_if   : descriptor-source AXI read-side fault domain
comp_wb_inject_if    : completion writeback AXI write-side fault domain
```

These interfaces are testbench-only.  They do not change the CSR map, BRAM, GEMM datapath, DMA datapath, AXI-Stream path, or Direct Stream path.


### P19B Queue CSR Map Checkpoint

P19B freezes the queue CSR address map and register bit definitions in this document.  The architectural queue behavior, command entry format, completion-queue usage, and validation plan remain documented in `command_completion_queue_prototype_spec.md`.

```text
P19A: Command / completion queue prototype spec          PASS
P19B: Queue CSR register map freeze                      PASS

P19B CSR window:
  0x580 - 0x5FC
```

P19B is a specification checkpoint only.  It does not add RTL, UVM tests, Tcl scripts, regression items, or README updates.



### P19G Queue Integration Validation Checkpoint

P19G closes the first command / completion queue prototype through targeted validation and full-regression integration.  The CSR register map, access types, reset values, and bit definitions remain the P19B-frozen canonical definitions in this document.

```text
P19A: Command / completion queue prototype spec                 PASS
P19B: Queue CSR register map freeze                             PASS
P19C: Single-outstanding queue fetch controller                 PASS
P19D: Command queue -> existing P17 descriptor fetch launch      PASS
P19E: Completion queue writeback integration                    PASS
P19F: Queue reject / empty / full / bad pointer handling         PASS
P19G: Full regression integration                               PASS

Full regression after P19G:
  TOTAL : 113
  PASS  : 113
  FAIL  : 0
```

Validated P19 queue representatives:

```text
csr_queue_desc_fetch_dma_case102
csr_queue_completion_wb_case102
csr_queue_reject_error_case102
```

P19 does not change the P14/P15/P16/P17/P18 CSR windows.  It only uses the P19 queue window at `0x580 - 0x5FC` to configure SQ/CQ base, depth, stride, head/tail ownership, status, reject, and debug counters.


### P20G Queue Drain Validation Checkpoint

P20G closes the multi-entry in-order queue drain milestone through targeted validation and full-regression integration.  P20 does not add a new CSR window and does not change the P19B-frozen queue CSR address map.  It validates the runtime meaning of existing queue control semantics such as `CSR_QUEUE_CONTROL.RUN_UNTIL_EMPTY`, `CSR_QUEUE_COMMAND.STOP_QUEUE`, and command-entry `CMD_CONTROL.STOP_AFTER_THIS`.

```text
P20A: Multi-entry in-order queue drain spec                    PASS
P20B: Queue controller auto-continue policy                    PASS
P20C: Two-command DMA recipe queue smoke                       PASS
P20D: DMA + Direct Stream + C RMW mixed queue smoke            PASS
P20E: SQ/CQ wrap-around representative validation              PASS
P20F: STOP_AFTER_THIS / STOP_QUEUE behavior                    PASS
P20G: Full regression integration                              PASS

Full regression after P20G:
  TOTAL : 117
  PASS  : 117
  FAIL  : 0
```

Validated P20 queue-drain representatives:

```text
csr_queue_two_command_dma_case102
csr_queue_mixed_dma_ds_c_rmw_case208
csr_queue_wraparound_case102
csr_queue_stop_behavior_case102
```

The canonical queue CSR map remains:

```text
P19/P20/P21 queue window: 0x580 - 0x5FC
```



### P21G Runtime Doorbell / Live Queue Service Validation Checkpoint

P21G closes the runtime doorbell / live queue service milestone through targeted validation and full-regression integration.  P21 does not add a new CSR window and does not change the P19B-frozen queue CSR address map.  It validates the runtime meaning of existing host-owned queue pointers: `CSR_SQ_TAIL` as the submission doorbell and `CSR_CQ_HEAD` as completion-consumption recovery state.

```text
P21A: Runtime doorbell / live queue service spec                  PASS
P21B: Queue controller live SQ_TAIL observation policy             PASS
P21C: Append-while-active DMA queue smoke                         PASS
P21D: Append-while-active mixed queue smoke                       PASS
P21E: CQ full stall + host CQ_HEAD recovery during active service  PASS
P21F: STOP_QUEUE during live service                              PASS
P21G: Full regression integration                                 PASS
P21H: Documentation closure                                       PASS

Full regression after P21G:
  TOTAL : 121
  PASS  : 121
  FAIL  : 0
```

Validated P21 queue representatives:

```text
csr_queue_runtime_doorbell_dma_case102
csr_queue_runtime_doorbell_mixed_case102
csr_queue_cq_full_live_recovery_case102
csr_queue_stop_live_service_case102
```

The canonical queue CSR map remains:

```text
P19/P20/P21 queue window: 0x580 - 0x5FC
```

P21 freezes the following CSR ownership policy:

```text
CSR_SQ_TAIL is host-owned and may be written while queue_busy=1.
CSR_CQ_HEAD is host-owned and may be written while queue_busy=1.
The queue controller observes these live host-owned values only at safe command-boundary or CQ-full stall checks.
The active command continues to use its snapshotted SQ/CQ addresses and is not affected by host pointer writes during execution.
```


### P22B Event Notification / Interrupt-Lite CSR Map Checkpoint

P22A/P22B define the lightweight event notification / interrupt-lite layer above the validated P21 live queue service model.  P22 does not change the P19/P20/P21 queue CSR window, the P19 SQ command format, or the P18 completion record format.  It adds a small event CSR window that captures queue-level completion, drained, stopped, error, CQ backpressure, and runtime-doorbell events.

```text
P22A: Event notification / interrupt-lite prototype spec          PASS
P22B: Event CSR register map freeze                               PASS
```

P22B CSR window:

```text
0x600 - 0x63C
```

P22A/P22B are documentation checkpoints only.  They do not add RTL, UVM tests, Tcl scripts, README updates, regression-list items, or full-regression count changes.

The canonical event CSR map is:

```text
P22 event notification window: 0x600 - 0x63C
```

The event layer is summary-only.  The CQ completion record remains the authoritative per-command completion detail.
