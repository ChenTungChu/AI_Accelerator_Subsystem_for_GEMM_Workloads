# AXI-Lite CSR Control Plane Spec

## 1. Purpose

This document defines the AXI-Lite control-plane specification for the AI Accelerator Subsystem.  It records the canonical CSR address map, register access types, reset values, and register bit definitions for the P14 CSR shell and the later P15/P16/P17/P18/P19 CSR extensions.

The subsystem already has a stable GEMM datapath and multiple validated data movement frontends.  P14 adds a lightweight software-visible control plane so a host can program, launch, poll, and observe the accelerator through control/status registers instead of driving top-level sideband control wires directly.

P14 is intentionally scoped as a minimal CSR shell.  It is not a descriptor engine, interrupt controller, software driver, or UVM RAL model.  P15 builds on the same CSR shell by adding a CSR-resident single-job descriptor and hardware job sequencer above the P14 micro-operation command model.  P16 adds CSR-resident recipes, P17 adds memory-backed descriptor fetch, P18 adds completion writeback, P19 adds a host-visible command / completion queue CSR window, P20 validates multi-entry in-order queue drain behavior using that same P19 queue window, P21 validates runtime doorbell / live queue service behavior without adding new CSR addresses, P22 adds a lightweight event notification / interrupt-lite CSR window above the queue status model, P23 validates a driver-style event-driven host runtime by reusing the existing P19 queue and P22 event CSR windows without adding new CSR addresses, P24 clarifies the existing queue timeout / watchdog reporting policy without adding a new CSR window, P25/P26 reuse the existing queue/event CSR policy for runtime stress and lifecycle recovery, P27 adds a memory guard CSR window for host-visible address range validation, P28 reuses reserved P22 event CSR addresses for event coalescing / interrupt moderation policy, and P29 adds a runtime telemetry CSR window for queue/event/cycle observability.

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
Full UVM regression baseline passing 132/132 after P24G queue timeout / watchdog closure
P24B timeout / watchdog CSR policy clarification without new CSR addresses
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

### 6.4 Direct Stream Operand-Readiness / Committed-Extent Policy

The Direct Stream operand buffer owns its physical `a_loaded` and `b_loaded` state in `core_clk`.

P14/P15 GEMM launch acceptance occurs in the `dma_clk` control domain, so the launch boundary must not sample raw core-domain state or independently synchronize a multi-bit written-length bus.

Frozen readiness policy:

```text
core_clk:
  ds_operands_ready_core = a_loaded && b_loaded

core_clk -> dma_clk:
  ds_operands_ready_core passes through a 2FF level synchronizer
```

R3-B adds committed-extent ownership in the existing Direct Stream preload engine, which already owns the requested beat count and the transaction-completion handshake in `dma_clk`:

```text
dma_clk direct_stream_preload_engine:
  on new preload start for operand A/B:
    invalidate that operand's committed extent

  on clean terminal preload completion:
    selected_extent_valid     = 1
    selected_completed_beats  = latched ds_load_beats

  on failed terminal preload completion:
    selected extent remains invalid
```

No independent 32-bit `a_written_beats` / `b_written_beats` CDC is used.  The committed extent is constructed directly from the already-latched `beats_dma_q`, `operand_sel_dma_q`, and the existing transaction-completion/error handshake.

At the shared GEMM launch boundary, Direct Stream mode requires both:

```text
synchronized A/B loaded readiness
and
committed extent / physical-capacity validation against the actual launch M/N/K
```

For the current int8 GEMM operands and 64-bit Direct Stream path:

```text
required_A_bytes = M * K
required_B_bytes = K * N
committed_A_bytes = A_completed_beats * 8
committed_B_bytes = B_completed_beats * 8
```

The comparison uses widened arithmetic before launch.  Legal padded tails are allowed when the committed beat extent covers the requested byte footprint; the dimension-derived footprint must still be no larger than the physical A/B operand-buffer capacity.  Router-side bounds checking remains a defensive backstop and is not the primary launch-validity policy.

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
P27 memory guard window        : 0x640 - 0x6BC
P29 runtime telemetry window   : 0x6C0 - 0x73C
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
P27 memory guard window        : 0x640 - 0x6BC
P29 runtime telemetry window   : 0x6C0 - 0x73C
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
P27 memory guard window        : 0x640 - 0x6BC
P29 runtime telemetry window   : 0x6C0 - 0x73C
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
| 0x630 | `CSR_EVENT_MOD_CONTROL` | RW | `0x0000_0000` | P28 event coalescing / interrupt moderation control. |
| 0x634 | `CSR_EVENT_MOD_STATUS` | RO | implementation | Live moderation status, CQ occupancy snapshot, and unnotified CQ snapshot. |
| 0x638 | `CSR_EVENT_MOD_TIMER_LIMIT` | RW | 0 | Moderation timer limit in dma_clk cycles. 0 disables timer fallback. |
| 0x63C | `CSR_EVENT_MOD_DEBUG` | RO | 0 | Moderation release cause and debug counters. |

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
| `CSR_EVENT_MOD_CONTROL` | Host | Program while event moderation is idle or before enabling queue service. Reset disables moderation. |
| `CSR_EVENT_MOD_STATUS` | Hardware | Read-only live moderation state and snapshots. |
| `CSR_EVENT_MOD_TIMER_LIMIT` | Host | Program the moderation timer limit in dma_clk cycles. 0 disables timer fallback. |
| `CSR_EVENT_MOD_DEBUG` | Hardware | Read-only moderation release/debug snapshot. Cleared by `CSR_EVENT_COMMAND.CLEAR_EVENT_COUNTERS`. |

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
CQ_MODERATION_TIMER_EVENT
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

Current implementation status:

```text
P21 runtime SQ_TAIL append / live queue service:
  implemented and validated

P22 RUNTIME_DOORBELL_EVENT producer:
  reserved by the ABI but tied low in the current RTL revision

P22 RUNTIME_APPEND_CONSUMED_EVENT producer:
  reserved by the ABI but tied low in the current RTL revision
```

Bits 8 and 9 retain their frozen CSR positions for forward compatibility.  In the current RTL revision they read zero in `CSR_EVENT_PENDING`, do not contribute to `event_irq`, and do not generate `EVENT_SRC_RUNTIME_DOORBELL` last-cause classification.  A future implementation may connect these sources without changing the P22 CSR map.

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



### 9.4 P27 Memory Access Guard CSR Register Window

P27B freezes the software-visible memory access guard CSR window used by the P27 range-validation prototype.

P22 uses the `0x600 - 0x63C` event notification CSR window.  P27 adds a guard CSR window after the event window.

Frozen P27B CSR base:

```text
P27 memory guard CSR base = 0x640
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
P27 memory guard window        : 0x640 - 0x6BC
P29 runtime telemetry window   : 0x6C0 - 0x73C
```

P27B does not add RTL, UVM tests, Tcl scripts, README updates, or regression-list items.  It freezes the guard register map and bit definitions so P27C/P27D/P27E/P27F implementation can use stable constants.

#### 9.4.1 Register Map

| Offset | Name | Access | Reset | Description |
|---:|---|---|---:|---|
| 0x640 | `CSR_MEM_GUARD_VERSION` | RO | `0x0001_0027` | Memory guard version / feature ID. |
| 0x644 | `CSR_MEM_GUARD_COMMAND` | W1P | 0 | Guard sticky-status and debug-counter clear commands. |
| 0x648 | `CSR_MEM_GUARD_STATUS` | RO | implementation | Live guard enable / error / reject summary. |
| 0x64C | `CSR_MEM_GUARD_ERROR_STATUS` | RO/W1C | 0 | Sticky guard error status. |
| 0x650 | `CSR_MEM_GUARD_CONTROL` | RW | `0x0000_0000` | Guard enable, strict reject, and per-domain check enables. |
| 0x654 | `CSR_MEM_GUARD_REJECT_STATUS` | RO/W1C | 0 | Sticky guard command/config reject reasons. |
| 0x658 | `CSR_MEM_GUARD_ERROR_DETAIL` | RO | 0 | Last guard error detail code / domain / index / state. |
| 0x65C | `CSR_MEM_GUARD_ERROR_ADDR` | RO | 0 | Address associated with the last guard error. |
| 0x660 | `CSR_MEM_GUARD_ERROR_SIZE_BYTES` | RO | 0 | Access size in bytes associated with the last guard error. |
| 0x664 | `CSR_MEM_GUARD_ERROR_DOMAIN` | RO | 0 | Domain associated with the last guard error. |
| 0x668 | `CSR_MEM_GUARD_CHECK_COUNT` | RO | 0 | Number of guard checks performed while enabled. |
| 0x66C | `CSR_MEM_GUARD_ERROR_COUNT` | RO | 0 | Number of guard failures observed while enabled. |
| 0x670 | `CSR_MEM_GUARD_LAST_CHECK_ADDR` | RO | 0 | Address associated with the last guard check. |
| 0x674 | `CSR_MEM_GUARD_LAST_CHECK_SIZE_BYTES` | RO | 0 | Access size in bytes associated with the last guard check. |
| 0x678 | `CSR_MEM_GUARD_LAST_CHECK_DOMAIN` | RO | 0 | Domain associated with the last guard check. |
| 0x67C | `CSR_MEM_GUARD_RESERVED_67C` | RO | 0 | Reserved. |
| 0x680 | `CSR_MEM_GUARD_SQ_BASE` | RW | 0 | Allowed SQ command-memory region base address. |
| 0x684 | `CSR_MEM_GUARD_SQ_LIMIT` | RW | 0 | Allowed SQ command-memory region exclusive limit address. |
| 0x688 | `CSR_MEM_GUARD_CQ_BASE` | RW | 0 | Allowed CQ completion-memory region base address. |
| 0x68C | `CSR_MEM_GUARD_CQ_LIMIT` | RW | 0 | Allowed CQ completion-memory region exclusive limit address. |
| 0x690 | `CSR_MEM_GUARD_DESC_BASE` | RW | 0 | Allowed descriptor-memory region base address. |
| 0x694 | `CSR_MEM_GUARD_DESC_LIMIT` | RW | 0 | Allowed descriptor-memory region exclusive limit address. |
| 0x698 | `CSR_MEM_GUARD_SRC_BASE` | RW | 0 | Allowed source-memory region base address. |
| 0x69C | `CSR_MEM_GUARD_SRC_LIMIT` | RW | 0 | Allowed source-memory region exclusive limit address. |
| 0x6A0 | `CSR_MEM_GUARD_DST_BASE` | RW | 0 | Allowed destination-memory region base address. |
| 0x6A4 | `CSR_MEM_GUARD_DST_LIMIT` | RW | 0 | Allowed destination-memory region exclusive limit address. |
| 0x6A8 | `CSR_MEM_GUARD_RESERVED_6A8` | RO | 0 | Reserved. |
| 0x6AC | `CSR_MEM_GUARD_RESERVED_6AC` | RO | 0 | Reserved. |
| 0x6B0 | `CSR_MEM_GUARD_RESERVED_6B0` | RO | 0 | Reserved. |
| 0x6B4 | `CSR_MEM_GUARD_RESERVED_6B4` | RO | 0 | Reserved. |
| 0x6B8 | `CSR_MEM_GUARD_RESERVED_6B8` | RO | 0 | Reserved. |
| 0x6BC | `CSR_MEM_GUARD_RESERVED_6BC` | RO | 0 | Reserved. |

#### 9.4.2 Region Semantics

All P27 guard regions use half-open address ranges:

```text
valid access if:
  access_start >= region_base
  access_end   <= region_limit
  access_end   = access_start + size_bytes
  access_end does not overflow 32-bit address space
```

The exclusive-limit policy avoids inclusive-end off-by-one ambiguity and makes a zero-sized region easy to identify:

```text
region_base == region_limit : empty / invalid region when that domain is enabled
region_base  > region_limit : invalid region configuration
```

#### 9.4.3 Register Ownership Summary

| Register | Owner | Write Policy |
|---|---|---|
| `CSR_MEM_GUARD_CONTROL` | Host | Program while queue is idle. Reset disables all guard checks. |
| `CSR_MEM_GUARD_*_BASE/LIMIT` | Host | Program while queue is idle. Used only when the corresponding domain check is enabled. |
| `CSR_MEM_GUARD_ERROR_STATUS` | Hardware set / host W1C clear | Sticky guard error summary. |
| `CSR_MEM_GUARD_REJECT_STATUS` | Hardware set / host W1C clear | Sticky guard command/config reject summary. |
| `CSR_MEM_GUARD_ERROR_*` | Hardware | Last guard failure diagnostics. |
| `CSR_MEM_GUARD_LAST_CHECK_*` | Hardware | Last guard check diagnostics. |
| `CSR_MEM_GUARD_CHECK_COUNT` | Hardware | Cleared by `CSR_MEM_GUARD_COMMAND.CLEAR_GUARD_COUNTERS`. |
| `CSR_MEM_GUARD_ERROR_COUNT` | Hardware | Cleared by `CSR_MEM_GUARD_COMMAND.CLEAR_GUARD_COUNTERS`. |

Region base/limit writes while `queue_busy` is high are rejected or ignored and set `CSR_MEM_GUARD_REJECT_STATUS.CONFIG_WRITE_BUSY_REJECT`.

#### 9.4.4 Queue / Event Integration

P27B adds one queue-level error summary bit:

```text
CSR_QUEUE_ERROR_STATUS[9] = MEMORY_GUARD_ERROR
```

P27B does not add a P22 event bit.  Guard failures that reach the queue error path use the existing event source:

```text
CSR_EVENT_PENDING.QUEUE_ERROR_EVENT
```

If the selected CQ slot is inside the enabled CQ range, hardware may produce a CQ error completion record.  If the CQ slot itself is unsafe, hardware must not issue the completion writeback.  In that case, queue CSR error/detail and guard CSR diagnostics are authoritative.

#### 9.4.5 P27B Frozen Constants

```text
CSR_MEM_GUARD_BASE_ADDR      = 0x640
CSR_MEM_GUARD_WINDOW_LAST    = 0x6BC
CSR_MEM_GUARD_VERSION_RESET  = 0x0001_0027
CSR_MEM_GUARD_CONTROL_RESET  = 0x0000_0000
P27_QUEUE_MEMORY_GUARD_ERROR_BIT = 9
P27_GUARD_DOMAIN_SQ          = 1
P27_GUARD_DOMAIN_CQ          = 2
P27_GUARD_DOMAIN_DESC        = 3
P27_GUARD_DOMAIN_SRC         = 4
P27_GUARD_DOMAIN_DST         = 5
```

---

### 9.5 P29 Runtime Telemetry CSR Register Window

P29B freezes the software-visible runtime telemetry CSR window used by the P29 counter prototype.

P27 uses the `0x640 - 0x6BC` memory guard CSR window.  P29 adds a telemetry CSR window after the guard window.

Frozen P29B CSR base:

```text
P29 runtime telemetry CSR base = 0x6C0
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
P27 memory guard window        : 0x640 - 0x6BC
P29 runtime telemetry window   : 0x6C0 - 0x73C
```

P29B does not add RTL, UVM tests, Tcl scripts, README updates, or regression-list items.  It freezes the telemetry register map and bit definitions so P29C/P29D/P29E/P29F implementation can use stable constants.

#### 9.5.1 Register Map

| Offset | Name | Access | Reset | Description |
|---:|---|---|---:|---|
| 0x6C0 | `CSR_TELEM_VERSION` | RO | `0x0001_0029` | Runtime telemetry version / feature ID. |
| 0x6C4 | `CSR_TELEM_COMMAND` | W1P | 0 | Telemetry clear command. |
| 0x6C8 | `CSR_TELEM_STATUS` | RO | implementation | Live telemetry enable / status summary. |
| 0x6CC | `CSR_TELEM_CONTROL` | RW | `0x0000_0000` | Telemetry enable and counter-category enables. |
| 0x6D0 | `CSR_TELEM_QUEUE_START_COUNT` | RO | 0 | Number of accepted queue starts. |
| 0x6D4 | `CSR_TELEM_SQ_ACCEPT_COUNT` | RO | 0 | Number of validated SQ commands accepted for execution. |
| 0x6D8 | `CSR_TELEM_CMD_COMPLETE_COUNT` | RO | 0 | Number of queue commands that reached normal completion. |
| 0x6DC | `CSR_TELEM_CQ_COMMIT_COUNT` | RO | 0 | Number of CQ records committed and made visible. |
| 0x6E0 | `CSR_TELEM_QUEUE_DRAINED_COUNT` | RO | 0 | Number of queue drained terminal observations. |
| 0x6E4 | `CSR_TELEM_QUEUE_STOPPED_COUNT` | RO | 0 | Number of queue stopped terminal observations. |
| 0x6E8 | `CSR_TELEM_QUEUE_ERROR_COUNT` | RO | 0 | Number of queue error terminal observations. |
| 0x6EC | `CSR_TELEM_CQ_HEAD_UPDATE_COUNT` | RO | 0 | Number of positive host CQ_HEAD advancements observed. |
| 0x6F0 | `CSR_TELEM_CQ_CONSUMED_COUNT` | RO | 0 | Accumulated positive CQ_HEAD delta observed from host consumption. |
| 0x6F4 | `CSR_TELEM_MAX_CQ_BATCH_SIZE` | RO | 0 | Maximum positive CQ_HEAD delta observed in one host update. |
| 0x6F8 | `CSR_TELEM_EVENT_CAPTURE_COUNT` | RO | 0 | Number of event source captures observed by telemetry. |
| 0x6FC | `CSR_TELEM_IRQ_ELIGIBLE_COUNT` | RO | 0 | Number of interrupt-eligible event captures observed by telemetry. |
| 0x700 | `CSR_TELEM_COMPLETION_EVENT_COUNT` | RO | 0 | Number of completion-style event releases observed. |
| 0x704 | `CSR_TELEM_COALESCED_RELEASE_COUNT` | RO | 0 | Number of P28 coalesced CQ notification releases. |
| 0x708 | `CSR_TELEM_THRESHOLD_RELEASE_COUNT` | RO | 0 | Number of P28 threshold-caused releases. |
| 0x70C | `CSR_TELEM_TIMER_RELEASE_COUNT` | RO | 0 | Number of P28 timer-caused releases. |
| 0x710 | `CSR_TELEM_URGENT_BYPASS_COUNT` | RO | 0 | Number of urgent event bypass observations while moderation is enabled. |
| 0x714 | `CSR_TELEM_CQ_FULL_STALL_COUNT` | RO | 0 | Number of CQ-full stall observations. |
| 0x718 | `CSR_TELEM_CQ_SPACE_RECOVERED_COUNT` | RO | 0 | Number of CQ-space recovered observations. |
| 0x71C | `CSR_TELEM_TIMEOUT_ERROR_COUNT` | RO | 0 | Number of command-timeout queue error observations. |
| 0x720 | `CSR_TELEM_MEM_GUARD_ERROR_COUNT` | RO | 0 | Number of memory-guard queue error observations. |
| 0x724 | `CSR_TELEM_STOP_QUEUE_REQUEST_COUNT` | RO | 0 | Number of accepted STOP_QUEUE requests observed. |
| 0x728 | `CSR_TELEM_QUEUE_ENABLED_CYCLES` | RO | 0 | dma_clk cycles with queue processing enabled and telemetry cycle count enabled. |
| 0x72C | `CSR_TELEM_QUEUE_BUSY_CYCLES` | RO | 0 | dma_clk cycles with queue_busy high and telemetry cycle count enabled. |
| 0x730 | `CSR_TELEM_QUEUE_IDLE_CYCLES` | RO | 0 | dma_clk cycles with queue enabled, not busy, and not stalled. |
| 0x734 | `CSR_TELEM_QUEUE_STALLED_CYCLES` | RO | 0 | dma_clk cycles with queue stalled. |
| 0x738 | `CSR_TELEM_CQ_FULL_STALL_CYCLES` | RO | 0 | dma_clk cycles with CQ-full stall active. |
| 0x73C | `CSR_TELEM_LOWER_WAIT_CYCLES` | RO | 0 | dma_clk cycles waiting for lower-level P17/P18/P16/P15/P14 quiescence or terminal progress. |

#### 9.5.2 Register Ownership Summary

| Register | Owner | Write Policy |
|---|---|---|
| `CSR_TELEM_COMMAND` | Host | Write-one-pulse commands. Reads return zero. |
| `CSR_TELEM_STATUS` | Hardware | Read-only live telemetry summary. |
| `CSR_TELEM_CONTROL` | Host | Program while queue is idle or active. Telemetry is observational only. |
| `CSR_TELEM_*_COUNT` | Hardware | Read-only counters. Cleared by `CSR_TELEM_COMMAND.CLEAR_TELEMETRY_COUNTERS`. |
| `CSR_TELEM_MAX_CQ_BATCH_SIZE` | Hardware | Read-only max tracker. Cleared by `CSR_TELEM_COMMAND.CLEAR_TELEMETRY_COUNTERS`. |

Telemetry clear is observational only.  It must not clear functional queue state, event pending bits, memory guard diagnostics, timeout status, SQ/CQ pointers, CQ records, or lower-level sticky status.

#### 9.5.3 Counter Source Summary

P29B freezes these first source policies:

```text
CSR_TELEM_QUEUE_START_COUNT increments when START_QUEUE is accepted.
CSR_TELEM_SQ_ACCEPT_COUNT increments when an SQ command is fetched, validated, and accepted for execution.
CSR_TELEM_CMD_COMPLETE_COUNT increments when a command reaches normal queue completion.
CSR_TELEM_CQ_COMMIT_COUNT increments only after a valid CQ record commit and CQ_TAIL advancement.
CSR_TELEM_CQ_HEAD_UPDATE_COUNT increments only for positive host CQ_HEAD advancement.
CSR_TELEM_CQ_CONSUMED_COUNT increments by positive CQ_HEAD delta.
CSR_TELEM_MAX_CQ_BATCH_SIZE tracks the maximum positive CQ_HEAD delta.
CSR_TELEM_EVENT_CAPTURE_COUNT observes existing P22 event capture source firings.
CSR_TELEM_IRQ_ELIGIBLE_COUNT observes existing P22 interrupt-eligible event captures.
CSR_TELEM_COMPLETION_EVENT_COUNT observes completion-style CQ notification releases.
CSR_TELEM_COALESCED_RELEASE_COUNT observes P28 coalesced CQ release events.
CSR_TELEM_THRESHOLD_RELEASE_COUNT observes P28 threshold release events.
CSR_TELEM_TIMER_RELEASE_COUNT observes P28 timer release events.
CSR_TELEM_URGENT_BYPASS_COUNT observes urgent bypass release events while moderation is enabled.
CSR_TELEM_CQ_FULL_STALL_COUNT observes CQ-full stall entries.
CSR_TELEM_CQ_SPACE_RECOVERED_COUNT observes CQ-space recovered event points.
CSR_TELEM_TIMEOUT_ERROR_COUNT observes CSR_QUEUE_ERROR_STATUS[6] timeout error source points.
CSR_TELEM_MEM_GUARD_ERROR_COUNT observes CSR_QUEUE_ERROR_STATUS[9] memory guard error source points.
CSR_TELEM_STOP_QUEUE_REQUEST_COUNT increments when STOP_QUEUE is accepted.
```

Cycle counters increment at most once per `dma_clk` cycle when `CSR_TELEM_CONTROL.TELEMETRY_ENABLE=1` and `CSR_TELEM_CONTROL.CYCLE_COUNT_ENABLE=1`.

#### 9.5.4 Counter Width and Overflow Policy

P29B freezes the first implementation as 32-bit wrapping counters:

```text
counter width      : 32 bits
reset value        : 0
clear value        : 0
overflow behavior  : wrap modulo 2^32
sticky overflow    : not implemented in first prototype
hardware division  : not implemented in first prototype
ratio calculation  : software / UVM derived from raw counters
```

This keeps the first telemetry block simple and deterministic.  UVM tests are expected to run short enough that overflow is not part of P29D/P29E/P29F validation.

#### 9.5.5 P29B Frozen Constants

```text
CSR_TELEM_BASE_ADDR              = 0x6C0
CSR_TELEM_WINDOW_LAST            = 0x73C
CSR_TELEM_VERSION_RESET          = 0x0001_0029
CSR_TELEM_CONTROL_RESET          = 0x0000_0000
P29_COUNTER_WIDTH                = 32
P29_COUNTER_OVERFLOW_POLICY      = wrap modulo 2^32
```



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
| 5 | `GEMM_OPERAND_NOT_READY_REJECT` | RO/W1C | `START_GEMM` requested in Direct Stream mode before both A and B operand buffers report synchronized loaded/ready state |
| 6 | `GEMM_OPERAND_EXTENT_REJECT` | RO/W1C | `START_GEMM` requested in Direct Stream mode after A/B preload completion, but the committed operand extent is insufficient for the programmed M/N/K or the required A/B footprint exceeds physical operand-buffer capacity |
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
| 6 | `COMMAND_TIMEOUT_ERROR` | RO/W1C | P24 per-command watchdog expired before the accepted SQ command reached terminal queue status. CQ-full pre-acceptance stall remains a stall, not this error. |
| 7 | `CONFIG_WRITE_BUSY_ERROR` | RO/W1C | Queue base/depth/stride config write attempted while queue busy. |
| 8 | `INTERNAL_SEQUENCE_ERROR` | RO/W1C | Queue FSM reached an illegal state or unexpected terminal condition. |
| 9 | `MEMORY_GUARD_ERROR` | RO/W1C | P27 memory access guard rejected or suppressed an unsafe host-visible memory access. |

P24B freezes bit 6 as the queue command timeout indication.  The bit is set only for an accepted SQ command whose snapshotted `CMD_TIMEOUT_CYCLES` value is non-zero and whose watchdog expires before terminal queue status.  It is not used for normal CQ-full stalls before command acceptance.  Timeout is a queue-level error subtype, so `CSR_QUEUE_STATUS.QUEUE_ERROR` is also asserted and P22 reports the condition through `QUEUE_ERROR_EVENT`.

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
| 0x0C | `DETAIL_COMMAND_TIMEOUT` |
| 0x0D | `DETAIL_TIMEOUT_IN_DESC_FETCH` |
| 0x0E | `DETAIL_TIMEOUT_IN_RECIPE` |
| 0x0F | `DETAIL_TIMEOUT_IN_COMPLETION_WB` |
| 0x10 | `DETAIL_TIMEOUT_IN_QUEUE_ADVANCE` |

`CSR_QUEUE_LAST_CMD_TAG` captures `CMD_USER_TAG` from the last accepted SQ entry.

`CSR_QUEUE_LAST_CMD_CONTROL` captures `CMD_CONTROL` from the last accepted SQ entry.

P24B timeout detail policy:

```text
CSR_QUEUE_ERROR_STATUS[6] = COMMAND_TIMEOUT_ERROR
CSR_QUEUE_ERROR_DETAIL[7:0] uses one of the DETAIL_TIMEOUT_* codes above
CSR_QUEUE_ERROR_DETAIL[15:8] captures the active SQ physical index
CSR_QUEUE_ERROR_DETAIL[23:16] captures the reserved CQ physical index, when one exists
CSR_QUEUE_ERROR_DETAIL[31:24] captures the queue FSM state when timeout was recorded
CSR_QUEUE_ERROR_INDEX uses the same SQ/CQ index packing as the current/error index register
CSR_QUEUE_LAST_CMD_TAG remains the timed-out command's CMD_USER_TAG
CSR_QUEUE_LAST_CMD_CONTROL remains the timed-out command's CMD_CONTROL snapshot
```

If a timeout completion record is successfully committed, `CSR_QUEUE_DONE_STATUS.COMMAND_COMPLETED` may also be set because a CQ-visible terminal record exists.  If the timeout occurs while the completion writeback path itself is stuck and no valid CQ record is committed, `CSR_QUEUE_ERROR_STATUS.COMMAND_TIMEOUT_ERROR` and `CSR_QUEUE_ERROR_DETAIL` are authoritative; `CSR_CQ_TAIL` must not advance without a valid completion commit.

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
P24_QUEUE_TIMEOUT_ERROR_BIT = 6
P24_DETAIL_COMMAND_TIMEOUT  = 0x0C
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
| 11 | `CQ_MODERATION_TIMER_EVENT` | RO/W1C | P28 moderation timer fallback released a coalesced CQ notification. |
| 31:12 | `RSVD` | RO/W1C | Reserved. |

Current implementation note:

```text
Bits 8 and 9 keep their software-visible ABI allocation, but their hardware
set producers are tied low in the current RTL revision.  They therefore read
zero until a future runtime-event producer is integrated.
```

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
| 11 | `CQ_MODERATION_TIMER_EVENT_EN` | RW | 0 | Enable moderation-timer event interrupt contribution. |
| 31:12 | `RSVD` | RO | 0 | Reserved. |

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

#### 10.10.13 `CSR_EVENT_MOD_CONTROL` at 0x630

P28B reuses reserved addresses inside the existing P22 event CSR window for event coalescing / interrupt moderation.  Moderation is disabled by reset so existing P22/P23/P24/P25/P26/P27 behavior is preserved unless software explicitly opts in.

| Bit | Name | Access | Reset | Description |
|---:|---|---|---:|---|
| 0 | `MODERATION_ENABLE` | RW | 0 | Enable P28 coalesced completion notification policy. 0 preserves immediate P22 behavior. |
| 1 | `CQ_THRESHOLD_ENABLE` | RW | 0 | Enable threshold-based moderation release using `CSR_EVENT_CQ_THRESHOLD`. |
| 2 | `MODERATION_TIMER_ENABLE` | RW | 0 | Enable timer fallback release using `CSR_EVENT_MOD_TIMER_LIMIT`. |
| 3 | `RETRIGGER_ON_STILL_NONEMPTY` | RW | 0 | After W1C / re-arm, resample CQ occupancy and reassert or restart moderation if CQ remains non-empty. |
| 31:4 | `RSVD` | RO | 0 | Reserved. |

Reset value:

```text
0x0000_0000
```

When `MODERATION_ENABLE=0`, the event layer preserves the existing P22 behavior: completion-related pending bits may be set immediately after CQ commit.

When `MODERATION_ENABLE=1`, completion-style sources may be held until a release condition is met:

```text
threshold release : CQ_THRESHOLD_ENABLE=1 and CQ occupancy >= CSR_EVENT_CQ_THRESHOLD
timer release     : MODERATION_TIMER_ENABLE=1 and timer reaches CSR_EVENT_MOD_TIMER_LIMIT
urgent bypass     : queue error / stopped / drained / CQ-full recovery / runtime debug / TEST_EVENT sources set pending immediately
```

On a moderation release, hardware sets the relevant coalesced CQ notification pending bits.  The first implementation should set `CQ_NOT_EMPTY_EVENT` for any coalesced CQ release, set `CQ_THRESHOLD_EVENT` when the threshold caused the release, and set `CQ_MODERATION_TIMER_EVENT` when the timer caused the release.  `QUEUE_COMMAND_COMPLETED_EVENT` may be set as a summary completion indication when at least one unnotified completion contributed to the release.

#### 10.10.14 `CSR_EVENT_MOD_STATUS` at 0x634

| Bits | Name | Access | Description |
|---:|---|---|---|
| 0 | `MODERATION_ACTIVE` | RO | Mirror of `CSR_EVENT_MOD_CONTROL.MODERATION_ENABLE`. |
| 1 | `THRESHOLD_ACTIVE` | RO | Threshold moderation is enabled and the threshold value is non-zero. |
| 2 | `TIMER_ACTIVE` | RO | Timer moderation is enabled and timer limit is non-zero. |
| 3 | `TIMER_RUNNING` | RO | Moderation timer is currently running for unnotified CQ work. |
| 4 | `THRESHOLD_MET` | RO | Current CQ occupancy meets or exceeds the programmed threshold. |
| 5 | `TIMER_EXPIRED` | RO | Timer expiry release is pending or was the most recent release cause. |
| 6 | `RELEASE_PENDING` | RO | A coalesced CQ notification release is pending capture into `CSR_EVENT_PENDING`. |
| 7 | `URGENT_BYPASS_ACTIVE` | RO | An urgent event bypassed moderation at the last event sample. |
| 15:8 | `RSVD` | RO | Reserved. |
| 23:16 | `CQ_OCCUPANCY_LOW8` | RO | Low byte of the current CQ occupancy snapshot used by moderation. |
| 31:24 | `UNNOTIFIED_CQ_LOW8` | RO | Low byte of unnotified CQ completion count tracked by moderation. |

#### 10.10.15 `CSR_EVENT_MOD_TIMER_LIMIT` at 0x638

`CSR_EVENT_MOD_TIMER_LIMIT` is a 32-bit RW timer limit in dma_clk cycles.

```text
0x0000_0000 : timer fallback disabled
non-zero    : timer fallback releases coalesced CQ notification after this many dma_clk cycles
```

The moderation timer is a notification-latency timer only.  It is not a queue progress watchdog and must not set `CSR_QUEUE_ERROR_STATUS.COMMAND_TIMEOUT_ERROR`.

#### 10.10.16 `CSR_EVENT_MOD_DEBUG` at 0x63C

Recommended first implementation encoding:

| Bits | Name | Access | Description |
|---:|---|---|---|
| 7:0 | `LAST_RELEASE_CAUSE` | RO | Most recent moderation release cause. |
| 15:8 | `MOD_RELEASE_COUNT_LOW8` | RO | Low byte of total moderation releases. |
| 23:16 | `THRESHOLD_RELEASE_COUNT_LOW8` | RO | Low byte of threshold-caused releases. |
| 31:24 | `TIMER_RELEASE_COUNT_LOW8` | RO | Low byte of timer-caused releases. |

Recommended `LAST_RELEASE_CAUSE` values:

| Value | Name |
|---:|---|
| 0x00 | `EVENT_MOD_RELEASE_NONE` |
| 0x01 | `EVENT_MOD_RELEASE_THRESHOLD` |
| 0x02 | `EVENT_MOD_RELEASE_TIMER` |
| 0x03 | `EVENT_MOD_RELEASE_IMMEDIATE_COMPAT` |
| 0x04 | `EVENT_MOD_RELEASE_URGENT_BYPASS` |
| 0x05 | `EVENT_MOD_RELEASE_REARM_NONEMPTY` |

Moderation debug counters are cleared by `CSR_EVENT_COMMAND.CLEAR_EVENT_COUNTERS`.

#### 10.10.17 P22/P28 Frozen Event Constants

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
P28_EVENT_CQ_MOD_TIMER       = 11

CSR_EVENT_MOD_CONTROL        = 0x630
CSR_EVENT_MOD_STATUS         = 0x634
CSR_EVENT_MOD_TIMER_LIMIT    = 0x638
CSR_EVENT_MOD_DEBUG          = 0x63C
CSR_EVENT_MOD_CONTROL_RESET  = 0x0000_0000

P28_MOD_RELEASE_NONE         = 0x00
P28_MOD_RELEASE_THRESHOLD    = 0x01
P28_MOD_RELEASE_TIMER        = 0x02
P28_MOD_RELEASE_IMMEDIATE    = 0x03
P28_MOD_RELEASE_URGENT       = 0x04
P28_MOD_RELEASE_REARM        = 0x05
```



### 10.11 P27 Memory Access Guard Registers

The P27 memory guard registers use the same AXI-Lite access policy and the same W1P/W1C definitions as the earlier CSR windows.

#### 10.11.1 `CSR_MEM_GUARD_VERSION` at 0x640

| Bits | Name | Access | Reset | Description |
|---:|---|---|---:|---|
| [31:16] | `MAJOR` | RO | 16'h0001 | Memory guard major version. |
| [15:8] | `MINOR` | RO | 8'h00 | Memory guard minor version. |
| [7:0] | `FEATURE_ID` | RO | 8'h27 | P27 memory guard feature ID. |

Reset value:

```text
0x0001_0027
```

#### 10.11.2 `CSR_MEM_GUARD_COMMAND` at 0x644

This is a write-one-pulse register.  Reads return zero.

| Bit | Name | Type | Description |
|---:|---|---|---|
| 8 | `CLEAR_GUARD_ERROR` | W1P | Clear sticky guard error status. |
| 9 | `CLEAR_GUARD_REJECT` | W1P | Clear sticky guard reject status. |
| 10 | `CLEAR_GUARD_COUNTERS` | W1P | Clear guard check/error counters and last-check snapshots. |
| 31:11, 7:0 | `RSVD` | — | Reserved. |

Unsupported command bits are ignored in the first P27 prototype and may set `CSR_MEM_GUARD_REJECT_STATUS.UNSUPPORTED_COMMAND_COMBO` in stricter implementations.

#### 10.11.3 `CSR_MEM_GUARD_STATUS` at 0x648

| Bit | Name | Access | Description |
|---:|---|---|
| 0 | `GUARD_ENABLED` | RO | Mirror of `CSR_MEM_GUARD_CONTROL.GUARD_ENABLE`. |
| 1 | `STRICT_REJECT_ENABLED` | RO | Mirror of `CSR_MEM_GUARD_CONTROL.STRICT_REJECT_ENABLE`. |
| 2 | `ANY_GUARD_ERROR` | RO | Any sticky guard error bit is set. |
| 3 | `ANY_GUARD_REJECT` | RO | Any sticky guard reject bit is set. |
| 4 | `SQ_CHECK_ENABLED` | RO | SQ command-memory range checking enabled. |
| 5 | `CQ_CHECK_ENABLED` | RO | CQ completion-memory range checking enabled. |
| 6 | `DESC_CHECK_ENABLED` | RO | Descriptor-memory range checking enabled. |
| 7 | `SRC_CHECK_ENABLED` | RO | Source-memory range checking enabled. |
| 8 | `DST_CHECK_ENABLED` | RO | Destination-memory range checking enabled. |
| 9 | `GUARD_ERROR_PENDING` | RO | Guard error is pending and may block strict launches. |
| 10 | `QUEUE_GUARD_ERROR_MIRROR` | RO | Queue-level memory guard error summary is set. |
| 16 | `CSR_READY` | RO | CSR block ready for transactions. |
| 31:17, 15:11 | `RSVD` | RO | Reserved. |

#### 10.11.4 `CSR_MEM_GUARD_ERROR_STATUS` at 0x64C

Sticky error bits are set by guard failures and cleared by W1C writes or by `CSR_MEM_GUARD_COMMAND.CLEAR_GUARD_ERROR`.

| Bit | Name | Type | Description |
|---:|---|---|---|
| 0 | `ANY_GUARD_ERROR` | RO/W1C | At least one guard failure has been observed. |
| 1 | `SQ_RANGE_ERROR` | RO/W1C | SQ command-memory access was outside the enabled SQ region. |
| 2 | `CQ_RANGE_ERROR` | RO/W1C | CQ completion-memory access was outside the enabled CQ region. |
| 3 | `DESC_RANGE_ERROR` | RO/W1C | Descriptor-memory access was outside the enabled descriptor region. |
| 4 | `SRC_RANGE_ERROR` | RO/W1C | Source-memory access was outside the enabled source region. |
| 5 | `DST_RANGE_ERROR` | RO/W1C | Destination-memory access was outside the enabled destination region. |
| 6 | `BASE_LIMIT_CONFIG_ERROR` | RO/W1C | Enabled region has invalid base/limit configuration. |
| 7 | `ADDRESS_OVERFLOW_ERROR` | RO/W1C | Address plus size overflowed or failed monotonic end calculation. |
| 8 | `ALIGNMENT_ERROR` | RO/W1C | Address violates the required alignment for the checked domain. |
| 9 | `STRIDE_ERROR` | RO/W1C | SQ/CQ/descriptor stride is unsupported for the checked span. |
| 10 | `DEPTH_ERROR` | RO/W1C | SQ/CQ depth is zero, unsupported, or creates an invalid span. |
| 11 | `SIZE_ZERO_ERROR` | RO/W1C | Access size is zero when a non-zero memory access is required. |
| 12 | `UNSAFE_CQ_WRITE_SUPPRESSED` | RO/W1C | CQ error completion was suppressed because the target CQ slot was unsafe. |
| 13 | `DOMAIN_MISMATCH_ERROR` | RO/W1C | Access was checked against an unexpected or disabled memory domain. |
| 14 | `CONFIG_WRITE_BUSY_ERROR` | RO/W1C | Guard region/control write attempted while queue busy. |
| 15 | `INTERNAL_GUARD_ERROR` | RO/W1C | Guard checker detected an unexpected internal condition. |
| 31:16 | `RSVD` | RO/W1C | Reserved. |

#### 10.11.5 `CSR_MEM_GUARD_CONTROL` at 0x650

| Bit | Name | Access | Reset | Description |
|---:|---|---|---:|---|
| 0 | `GUARD_ENABLE` | RW | 0 | Enable memory guard checks globally. |
| 1 | `STRICT_REJECT_ENABLE` | RW | 0 | Reject unsafe launches instead of observe-only diagnostic capture. |
| 4 | `SQ_CHECK_ENABLE` | RW | 0 | Enable SQ command-memory range checking. |
| 5 | `CQ_CHECK_ENABLE` | RW | 0 | Enable CQ completion-memory range checking. |
| 6 | `DESC_CHECK_ENABLE` | RW | 0 | Enable descriptor-memory range checking. |
| 7 | `SRC_CHECK_ENABLE` | RW | 0 | Enable source-memory range checking. |
| 8 | `DST_CHECK_ENABLE` | RW | 0 | Enable destination-memory range checking. |
| 12 | `WRITE_CQ_ERROR_RECORD_IF_SAFE` | RW | 0 | Permit a CQ error record when the selected CQ slot is valid and inside the CQ guard range. |
| 31:13, 11:9, 3:2 | `RSVD` | RO | 0 | Reserved. |

Reset value:

```text
0x0000_0000
```

The reset value preserves all existing pre-P27 regression behavior.  P27-specific tests must explicitly program regions and enable the desired check domains.

#### 10.11.6 `CSR_MEM_GUARD_REJECT_STATUS` at 0x654

Sticky reject bits are cleared by W1C writes or by `CSR_MEM_GUARD_COMMAND.CLEAR_GUARD_REJECT`.

| Bit | Name | Type | Description |
|---:|---|---|---|
| 0 | `CONFIG_WRITE_BUSY_REJECT` | RO/W1C | Guard control or region write attempted while queue busy. |
| 1 | `INVALID_REGION_CONFIG_REJECT` | RO/W1C | Enabled guard region has invalid base/limit configuration. |
| 2 | `UNSUPPORTED_COMMAND_COMBO` | RO/W1C | Unsupported guard command-bit combination was written. |
| 3 | `STRICT_START_REJECT` | RO/W1C | A strict guard failure rejected a queue start or command launch. |
| 31:4 | `RSVD` | RO/W1C | Reserved. |

#### 10.11.7 `CSR_MEM_GUARD_ERROR_DETAIL` at 0x658

Recommended encoding:

```text
[7:0]   detail code
[15:8]  guard domain
[23:16] SQ/CQ/descriptor physical index when applicable
[31:24] queue FSM state or guard check source
```

Recommended guard domain values:

| Value | Name |
|---:|---|
| 0x00 | `GUARD_DOMAIN_NONE` |
| 0x01 | `GUARD_DOMAIN_SQ` |
| 0x02 | `GUARD_DOMAIN_CQ` |
| 0x03 | `GUARD_DOMAIN_DESC` |
| 0x04 | `GUARD_DOMAIN_SRC` |
| 0x05 | `GUARD_DOMAIN_DST` |
| 0x06 | `GUARD_DOMAIN_CONFIG` |

Recommended P27 detail code values:

| Value | Name |
|---:|---|
| 0x20 | `DETAIL_MEM_GUARD_SQ_RANGE` |
| 0x21 | `DETAIL_MEM_GUARD_CQ_RANGE` |
| 0x22 | `DETAIL_MEM_GUARD_DESC_RANGE` |
| 0x23 | `DETAIL_MEM_GUARD_SRC_RANGE` |
| 0x24 | `DETAIL_MEM_GUARD_DST_RANGE` |
| 0x25 | `DETAIL_MEM_GUARD_ADDR_OVERFLOW` |
| 0x26 | `DETAIL_MEM_GUARD_ALIGNMENT` |
| 0x27 | `DETAIL_MEM_GUARD_SPAN_CONFIG` |
| 0x28 | `DETAIL_MEM_GUARD_DOMAIN_MISMATCH` |

The queue-level `CSR_QUEUE_ERROR_DETAIL[7:0]` may use the same P27 detail code values when `CSR_QUEUE_ERROR_STATUS.MEMORY_GUARD_ERROR` is set.

#### 10.11.8 Region Base / Limit Registers

The base and limit registers define half-open ranges:

```text
[base, limit)
```

A memory access is valid only when:

```text
addr >= base
addr + size_bytes <= limit
addr + size_bytes does not overflow
```

This policy applies to:

```text
CSR_MEM_GUARD_SQ_BASE   / CSR_MEM_GUARD_SQ_LIMIT
CSR_MEM_GUARD_CQ_BASE   / CSR_MEM_GUARD_CQ_LIMIT
CSR_MEM_GUARD_DESC_BASE / CSR_MEM_GUARD_DESC_LIMIT
CSR_MEM_GUARD_SRC_BASE  / CSR_MEM_GUARD_SRC_LIMIT
CSR_MEM_GUARD_DST_BASE  / CSR_MEM_GUARD_DST_LIMIT
```

---

### 10.12 P29 Runtime Telemetry Registers

The P29 telemetry registers use the same AXI-Lite access policy and the same W1P definitions as the earlier CSR windows.

#### 10.12.1 `CSR_TELEM_VERSION` at 0x6C0

| Bits | Name | Access | Reset | Description |
|---:|---|---|---:|---|
| [31:16] | `MAJOR` | RO | 16'h0001 | Telemetry block major version. |
| [15:8] | `MINOR` | RO | 8'h00 | Telemetry block minor version. |
| [7:0] | `FEATURE_ID` | RO | 8'h29 | P29 runtime telemetry feature ID. |

Reset value:

```text
0x0001_0029
```

#### 10.12.2 `CSR_TELEM_COMMAND` at 0x6C4

This is a write-one-pulse register.  Reads return zero.

| Bit | Name | Type | Description |
|---:|---|---|---|
| 8 | `CLEAR_TELEMETRY_COUNTERS` | W1P | Clear all telemetry counters and max trackers. |
| 31:9, 7:0 | `RSVD` | — | Reserved. |

Unsupported command bits are ignored in the first P29 prototype.  Telemetry commands are observational and must not set queue-level errors.

#### 10.12.3 `CSR_TELEM_STATUS` at 0x6C8

| Bit | Name | Access | Description |
|---:|---|---|
| 0 | `TELEMETRY_ENABLED` | RO | Mirror of `CSR_TELEM_CONTROL.TELEMETRY_ENABLE`. |
| 1 | `CYCLE_COUNT_ENABLED` | RO | Mirror of `CSR_TELEM_CONTROL.CYCLE_COUNT_ENABLE`. |
| 2 | `HOST_CQ_CONSUME_ENABLED` | RO | Mirror of `CSR_TELEM_CONTROL.HOST_CQ_CONSUME_ENABLE`. |
| 3 | `EVENT_EFFICIENCY_ENABLED` | RO | Mirror of `CSR_TELEM_CONTROL.EVENT_EFFICIENCY_ENABLE`. |
| 4 | `ANY_COUNTER_NONZERO` | RO | At least one telemetry counter is non-zero. |
| 5 | `QUEUE_COUNTERS_ACTIVE` | RO | Queue service telemetry is enabled. |
| 6 | `CYCLE_COUNTERS_ACTIVE` | RO | Cycle telemetry is enabled and counting may occur. |
| 16 | `CSR_READY` | RO | CSR block ready for transactions. |
| 31:17, 15:7 | `RSVD` | RO | Reserved. |

#### 10.12.4 `CSR_TELEM_CONTROL` at 0x6CC

| Bit | Name | Access | Reset | Description |
|---:|---|---|---:|---|
| 0 | `TELEMETRY_ENABLE` | RW | 0 | Enable P29 telemetry counters globally. |
| 1 | `CYCLE_COUNT_ENABLE` | RW | 0 | Enable cycle counters when telemetry is globally enabled. |
| 2 | `HOST_CQ_CONSUME_ENABLE` | RW | 0 | Enable host CQ_HEAD delta consumption counters. |
| 3 | `EVENT_EFFICIENCY_ENABLE` | RW | 0 | Enable event / IRQ / moderation efficiency counters. |
| 31:4 | `RSVD` | RO | 0 | Reserved. |

Reset value:

```text
0x0000_0000
```

Telemetry is disabled by reset to preserve existing pre-P29 regression behavior.  Enabling telemetry changes only counter visibility and must not change queue execution, event behavior, moderation behavior, guard behavior, or lower-level datapath behavior.

#### 10.12.5 Queue Service Counters

| Register | Offset | Access | Reset | Description |
|---|---:|---|---:|---|
| `CSR_TELEM_QUEUE_START_COUNT` | 0x6D0 | RO | 0 | Accepted START_QUEUE count. |
| `CSR_TELEM_SQ_ACCEPT_COUNT` | 0x6D4 | RO | 0 | Fetched / validated / accepted SQ command count. |
| `CSR_TELEM_CMD_COMPLETE_COUNT` | 0x6D8 | RO | 0 | Normal queue command completion count. |
| `CSR_TELEM_CQ_COMMIT_COUNT` | 0x6DC | RO | 0 | CQ record commit and CQ_TAIL advancement count. |
| `CSR_TELEM_QUEUE_DRAINED_COUNT` | 0x6E0 | RO | 0 | Queue drained terminal observation count. |
| `CSR_TELEM_QUEUE_STOPPED_COUNT` | 0x6E4 | RO | 0 | Queue stopped terminal observation count. |
| `CSR_TELEM_QUEUE_ERROR_COUNT` | 0x6E8 | RO | 0 | Queue error terminal observation count. |

Queue service counters increment only when `CSR_TELEM_CONTROL.TELEMETRY_ENABLE=1`.

#### 10.12.6 Host CQ Consumption Counters

| Register | Offset | Access | Reset | Description |
|---|---:|---|---:|---|
| `CSR_TELEM_CQ_HEAD_UPDATE_COUNT` | 0x6EC | RO | 0 | Number of positive CQ_HEAD advancements accepted from host writes. |
| `CSR_TELEM_CQ_CONSUMED_COUNT` | 0x6F0 | RO | 0 | Sum of positive CQ_HEAD deltas accepted from host writes. |
| `CSR_TELEM_MAX_CQ_BATCH_SIZE` | 0x6F4 | RO | 0 | Maximum positive CQ_HEAD delta observed in one host update. |

Host CQ consumption counters increment only when both `TELEMETRY_ENABLE=1` and `HOST_CQ_CONSUME_ENABLE=1`.

Positive CQ_HEAD delta policy:

```text
if new_cq_head > old_cq_head:
  cq_head_update_count += 1
  cq_consumed_count    += new_cq_head - old_cq_head
  max_cq_batch_size     = max(max_cq_batch_size, new_cq_head - old_cq_head)
else:
  no host-consumption telemetry counter update
```

P29B does not redefine the existing queue policy for invalid CQ_HEAD writes.

#### 10.12.7 Event / IRQ Efficiency and P28 Moderation Counters

| Register | Offset | Access | Reset | Description |
|---|---:|---|---:|---|
| `CSR_TELEM_EVENT_CAPTURE_COUNT` | 0x6F8 | RO | 0 | Event source capture count observed by telemetry. |
| `CSR_TELEM_IRQ_ELIGIBLE_COUNT` | 0x6FC | RO | 0 | Interrupt-eligible event capture count observed by telemetry. |
| `CSR_TELEM_COMPLETION_EVENT_COUNT` | 0x700 | RO | 0 | Completion-style event release count. |
| `CSR_TELEM_COALESCED_RELEASE_COUNT` | 0x704 | RO | 0 | P28 coalesced CQ notification release count. |
| `CSR_TELEM_THRESHOLD_RELEASE_COUNT` | 0x708 | RO | 0 | P28 threshold release count. |
| `CSR_TELEM_TIMER_RELEASE_COUNT` | 0x70C | RO | 0 | P28 timer fallback release count. |
| `CSR_TELEM_URGENT_BYPASS_COUNT` | 0x710 | RO | 0 | Urgent bypass observation count while moderation is enabled. |

Event / IRQ efficiency counters increment only when both `TELEMETRY_ENABLE=1` and `EVENT_EFFICIENCY_ENABLE=1`.

These counters are raw counters.  Derived metrics such as completions per IRQ and IRQ reduction estimate are computed by software or UVM.

#### 10.12.8 Stall / Recovery Counters

| Register | Offset | Access | Reset | Description |
|---|---:|---|---:|---|
| `CSR_TELEM_CQ_FULL_STALL_COUNT` | 0x714 | RO | 0 | CQ-full stall observation count. |
| `CSR_TELEM_CQ_SPACE_RECOVERED_COUNT` | 0x718 | RO | 0 | CQ-space recovered observation count. |
| `CSR_TELEM_TIMEOUT_ERROR_COUNT` | 0x71C | RO | 0 | Command timeout queue error observation count. |
| `CSR_TELEM_MEM_GUARD_ERROR_COUNT` | 0x720 | RO | 0 | Memory guard queue error observation count. |
| `CSR_TELEM_STOP_QUEUE_REQUEST_COUNT` | 0x724 | RO | 0 | Accepted STOP_QUEUE request count. |

Stall / recovery counters increment only when `CSR_TELEM_CONTROL.TELEMETRY_ENABLE=1`.

Timeout and memory-guard telemetry are summary counts only.  The authoritative diagnostics remain `CSR_QUEUE_ERROR_STATUS`, `CSR_QUEUE_ERROR_DETAIL`, and the P27 memory guard diagnostic registers.

#### 10.12.9 Runtime Cycle Counters

| Register | Offset | Access | Reset | Description |
|---|---:|---|---:|---|
| `CSR_TELEM_QUEUE_ENABLED_CYCLES` | 0x728 | RO | 0 | Cycles with queue enable policy active. |
| `CSR_TELEM_QUEUE_BUSY_CYCLES` | 0x72C | RO | 0 | Cycles with queue_busy high. |
| `CSR_TELEM_QUEUE_IDLE_CYCLES` | 0x730 | RO | 0 | Cycles with queue enabled, not busy, and not stalled. |
| `CSR_TELEM_QUEUE_STALLED_CYCLES` | 0x734 | RO | 0 | Cycles with queue stalled. |
| `CSR_TELEM_CQ_FULL_STALL_CYCLES` | 0x738 | RO | 0 | Cycles with CQ-full stall active. |
| `CSR_TELEM_LOWER_WAIT_CYCLES` | 0x73C | RO | 0 | Cycles waiting for lower-level quiescence or terminal progress. |

Cycle counters increment only when both `TELEMETRY_ENABLE=1` and `CYCLE_COUNT_ENABLE=1`.

The first implementation should increment each cycle counter at most once per dma_clk cycle.

#### 10.12.10 P29B Frozen Telemetry Constants

```text
CSR_TELEM_BASE_ADDR              = 0x6C0
CSR_TELEM_WINDOW_LAST            = 0x73C
CSR_TELEM_VERSION_RESET          = 0x0001_0029
CSR_TELEM_CONTROL_RESET          = 0x0000_0000
P29_COUNTER_WIDTH                = 32
P29_COUNTER_OVERFLOW_POLICY      = wrap modulo 2^32
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

and, when CSR_MODE.GEMM_INPUT_STREAM_MODE == 1:

ds_operands_ready == 1
ds_gemm_extent_ok == 1
```

This preserves the existing busy/zero-dimension policy while enforcing both Direct Stream preload completion and length/capacity sufficiency before the core can consume operand-buffer data.

Manual P14 reject precedence is:

```text
busy / ownership conflict
  -> zero dimension
  -> Direct Stream A/B not ready
       CSR_CMD_REJECT_STATUS.GEMM_OPERAND_NOT_READY_REJECT
  -> Direct Stream committed extent or capacity invalid
       CSR_CMD_REJECT_STATUS.GEMM_OPERAND_EXTENT_REJECT
  -> START_GEMM accepted
```

If Direct Stream mode is selected while `ds_operands_ready == 0`, no `acc_start` pulse is generated and bit 5 is set.  If A/B are ready but their committed extents do not cover the dimension-derived operand footprints, or a required footprint exceeds physical A/B capacity, no `acc_start` pulse is generated and bit 6 is set.  Neither condition sets `CSR_ERROR_STATUS` solely for this pre-launch rejection.

Scratchpad-mode GEMM bypasses the Direct Stream readiness/extent checks.

The final `ai_accel_subsys` GEMM launch boundary rechecks Direct Stream readiness and committed extent after P14/P15 control selection.  This shared guard protects manual P14, P15 Job, P16 Recipe-to-Job, and P19 Queue-to-Recipe/Job producers even when an upstream producer does not perform an equivalent early validation.

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

For `INPUT_MODE=DIRECT_STREAM`, P15 still performs the programmed A/B preloads, but its later GEMM pulse passes through the same shared subsystem readiness/committed-extent guard used by every GEMM producer.  If that final launch is rejected after successful preloads (for example, because the programmed preload lengths are too short for the snapshotted M/N/K), the job sequencer terminates with `CSR_JOB_ERROR_STATUS.JOB_SEQUENCE_ERROR` rather than remaining stuck in `GEMM_WAIT`.  The current R3-B repair does not allocate a new P15 reject-status bit; this shared actual-state failure is a post-`START_JOB` sequence error.

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
input logic ds_operands_ready,
input logic ds_gemm_extent_ok,

input logic dma_store_busy,
input logic dma_store_done,
input logic dma_store_error,

// Performance counter inputs from existing subsystem
input logic [31:0] gemm_perf_busy_cycles,
input logic [31:0] gemm_perf_mac_count,
input logic [31:0] gemm_perf_output_count
```

`acc_done`, `dma_load_done`, `axis_load_done`, `ds_load_done`, and `dma_store_done` are converted into sticky CSR done bits.

`ds_operands_ready` is the dma_clk-domain synchronized view of the Direct Stream operand buffer's combined A/B loaded state.  `ds_gemm_extent_ok` is the dma_clk-domain committed-extent/capacity result for the currently selected M/N/K.  P14 manual Direct Stream `START_GEMM` uses bit 5 for not-ready and bit 6 for ready-but-insufficient extent/capacity.  The subsystem also applies the same actual-state check at the final shared launch boundary for P15/P16/P19-derived GEMM starts.

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

### P22G Event Notification / Interrupt-Lite Validation Checkpoint

P22G closes the event notification / interrupt-lite milestone through integrated CSR validation, real queue-event validation, event clear / re-arm validation, and full-regression integration.  P22 does not change the P19/P20/P21 queue CSR window, the P19 SQ command entry format, the P18 completion record format, or any BRAM / GEMM / DMA / frontend datapath behavior.

```text
P22A: Event notification / interrupt-lite prototype spec          PASS
P22B: Event CSR register map freeze                               PASS
P22C: Integrated Event CSR smoke                                  PASS
P22D: Queue completion event smoke                                PASS
P22E: Queue drained / stopped / error event smoke                 PASS
P22F: Event mask / W1C clear / re-arm behavior                    PASS
P22G: Full regression integration                                 PASS
P22H: Documentation closure                                       PASS

Full regression after P22G:
  TOTAL : 125
  PASS  : 125
  FAIL  : 0
```

Validated P22 event representatives:

```text
csr_event_csr_smoke
csr_queue_completion_event_case102
csr_queue_drained_stopped_error_event_case102
csr_event_mask_w1c_rearm
```

Validated P22 event behavior:

```text
CSR_EVENT_VERSION / COMMAND / STATUS / PENDING / ENABLE / CONTROL readback
TEST_EVENT pending capture and W1C / CLEAR_PENDING clear
mask disabled capture without IRQ assertion
late enable / late GLOBAL_IRQ_ENABLE level IRQ behavior
W1C clear followed by same-event re-arm
QUEUE_COMMAND_COMPLETED_EVENT after CQ completion commit
CQ_NOT_EMPTY_EVENT after CQ occupancy becomes non-zero
QUEUE_DRAINED_EVENT on empty-SQ drain
QUEUE_STOPPED_EVENT on graceful STOP_QUEUE command-boundary stop
QUEUE_ERROR_EVENT on queue validation error
```

The canonical event CSR map remains:

```text
P22 event notification window: 0x600 - 0x63C
```

### P23G Event-Driven Host Runtime CSR Usage Checkpoint

P23 does not introduce a new CSR window, register offset, access type, reset value, or bit definition.

P23 reuses the existing CSR windows:

```text
P19 queue window               : 0x580 - 0x5FC
P22 event notification window  : 0x600 - 0x63C
```

Validated P23 CSR usage:

```text
host initializes SQ/CQ base, depth, stride, SQ_TAIL, and CQ_HEAD through the P19 queue window
host starts or stops queue service through CSR_QUEUE_COMMAND
host publishes runtime appends through CSR_SQ_TAIL
host publishes CQ consumption / CQ-full recovery through CSR_CQ_HEAD
host arms event notification through CSR_EVENT_ENABLE and CSR_EVENT_CONTROL
host waits on EVENT_STATUS / event_irq semantics
host W1C-clears handled CSR_EVENT_PENDING bits
host observes queue error, stopped, drained, and completion events through the existing event pending bits
```

Validated P23 full-regression result:

```text
TOTAL : 129
PASS  : 129
FAIL  : 0
```

The canonical CSR map remains unchanged from P22.  P23 is a UVM/helper and validation milestone for the software usage pattern of the existing queue and event CSR windows.



---

## 24. P24B Timeout / Watchdog CSR Policy Addendum

P24B does not allocate new CSR addresses and does not change the P19 queue CSR window or the P22 event CSR window.

Frozen P24B CSR policy:

```text
Timeout source field       : SQ command word6 CMD_TIMEOUT_CYCLES
Timeout disabled value     : CMD_TIMEOUT_CYCLES == 0
Timeout status bit         : CSR_QUEUE_ERROR_STATUS[6] COMMAND_TIMEOUT_ERROR
Timeout detail register    : CSR_QUEUE_ERROR_DETAIL
Timeout error index        : CSR_QUEUE_ERROR_INDEX
Timeout event notification : P22 QUEUE_ERROR_EVENT
```

Timeout is a queue-level terminal error for an accepted command.  It is not a new command reject, not a new event bit, and not a new CSR window.  CQ-full before command acceptance remains a recoverable queue stall and does not start the command watchdog.


---

## 25. P24H Timeout / Watchdog Validation Result

P24H closes the timeout / watchdog CSR policy through targeted validation and full-regression integration.

Validated P24 timeout CSR behavior:

```text
CMD_TIMEOUT_CYCLES == 0 preserves timeout-disabled legacy behavior
CMD_TIMEOUT_CYCLES != 0 enables the per-command queue watchdog after SQ command acceptance
CSR_QUEUE_ERROR_STATUS[6] = COMMAND_TIMEOUT_ERROR is set on timeout
CSR_QUEUE_ERROR_DETAIL[7:0] records DETAIL_TIMEOUT_IN_DESC_FETCH for descriptor-fetch / recipe wait timeout
CSR_QUEUE_ERROR_DETAIL[7:0] records DETAIL_TIMEOUT_IN_COMPLETION_WB for blocked completion-writeback timeout
CSR_QUEUE_LAST_CMD_TAG preserves the timed-out SQ command tag
CSR_CQ_TAIL does not advance when no valid completion record commits
P22 QUEUE_ERROR_EVENT is raised for timeout
```

Validated P24 full-regression representatives:

```text
csr_queue_timeout_desc_fetch_case102
csr_queue_timeout_completion_wb_case102
csr_queue_timeout_recovery_case102
```

Full regression after P24G:

```text
TOTAL : 132
PASS  : 132
FAIL  : 0
```

No new CSR window, no new P22 event bit, and no SQ/CQ entry-size change are introduced by P24.


---

## 26. P25H Runtime Stress / Robustness CSR Policy Checkpoint

P25H does not allocate new CSR addresses and does not change the P19 queue CSR window, the P22 event CSR window, SQ command entry format, CQ completion record format, descriptor format, or timeout field policy.

P25 validates stress / robustness behavior using existing CSR resources:

```text
CSR_SQ_TAIL runtime append doorbell
CSR_CQ_HEAD CQ consume / CQ-space recovery update
CSR_QUEUE_COMMAND.START_QUEUE
CSR_QUEUE_COMMAND.STOP_QUEUE
CSR_QUEUE_COMMAND.CLEAR_QUEUE_DONE
CSR_QUEUE_COMMAND.CLEAR_QUEUE_ERROR
CSR_EVENT_PENDING W1C
CSR_EVENT_COMMAND.CLEAR_EVENT_PENDING
CSR_EVENT_COMMAND.CLEAR_EVENT_COUNTERS
CSR_EVENT_ENABLE / CSR_EVENT_CONTROL re-arm policy
SQ command word6 CMD_TIMEOUT_CYCLES
```

Validated P25 full-regression representatives:

```text
csr_event_driven_multi_session_stress_case102
csr_event_driven_append_consume_stress_case102
csr_event_driven_stop_timeout_recovery_stress_case102
```

Full regression after P25F:

```text
TOTAL : 135
PASS  : 135
FAIL  : 0
```

P25 is a validation milestone over the existing P19/P21/P22/P23/P24 CSR policy.  It adds no new register, event bit, SQ/CQ format, or datapath behavior.


---

## 27. P26H Queue Lifecycle / Soft-Reset CSR Policy Addendum

P26H closes the queue lifecycle / soft-reset validation using the CSR policy frozen in P26B.

P26 does not allocate a new CSR window and does not change any canonical CSR address, access type, reset value, or bit definition.

Frozen P26 CSR policy:

```text
No new P26 CSR window
No new lifecycle command register
No new queue command bit
No new event pending bit
No SQ entry format change
No CQ completion record format change
No descriptor format change
No timeout field change
```

Validated P26 lifecycle operations use existing CSR resources:

```text
CSR_QUEUE_COMMAND.START_QUEUE
CSR_QUEUE_COMMAND.STOP_QUEUE
CSR_QUEUE_COMMAND.CLEAR_QUEUE_DONE
CSR_QUEUE_COMMAND.CLEAR_QUEUE_ERROR
CSR_QUEUE_COMMAND.CLEAR_QUEUE_COUNTERS
CSR_QUEUE_COMMAND.RESET_QUEUE_POINTERS
CSR_QUEUE_STATUS / DONE_STATUS / ERROR_STATUS / REJECT_STATUS
CSR_QUEUE_ERROR_DETAIL / ERROR_INDEX / LAST_CMD_TAG / LAST_CMD_CONTROL
CSR_SQ_HEAD / CSR_SQ_TAIL
CSR_CQ_HEAD / CSR_CQ_TAIL
CSR_QUEUE_SQ_OCCUPANCY / CQ_OCCUPANCY / CQ_SPACE
CSR_EVENT_PENDING W1C
CSR_EVENT_COMMAND.CLEAR_EVENT_PENDING
CSR_EVENT_COMMAND.CLEAR_EVENT_COUNTERS
CSR_EVENT_ENABLE / CSR_EVENT_CONTROL
P17/P18/P16/P15/P14 existing lower-level clear commands
```

Validated P26 full-regression representatives:

```text
csr_queue_lifecycle_drained_reinit_case102
csr_queue_lifecycle_stopped_preserve_restart_case102
csr_queue_lifecycle_timeout_error_reinit_case102
```

Full regression after P26G:

```text
TOTAL : 138
PASS  : 138
FAIL  : 0
```

Validated P26 CSR usage policy:

```text
Drained cleanup may preserve a clean non-zero monotonic pointer epoch when SQ_HEAD == SQ_TAIL and CQ_HEAD == CQ_TAIL.
STOP_QUEUE work-preserving cleanup must not write RESET_QUEUE_POINTERS and must not clear pending SQ VALID words.
Timeout/error cleanup captures diagnostics before clear, uses session-discard cleanup, waits for lower-level quiescence before restart, and re-arms events before the known-good recovery command.
RESET_QUEUE_POINTERS remains an idle-only session-discard operation, not an abort, preemption, rollback, or cancellation mechanism.
```

P26 keeps the P19 queue CSR window at `0x580 - 0x5FC` and the P22 event CSR window at `0x600 - 0x63C` unchanged.

---

## 28. P27B Memory Access Guard CSR Policy / Range Register Map Freeze

P27B freezes the memory access guard CSR policy for the first implementation checkpoint.

Unlike P25 and P26, P27 intentionally allocates a new CSR window because the guard requires software-programmable region ranges and guard-specific diagnostics.

Frozen P27 CSR policy:

```text
New P27 memory guard CSR window: 0x640 - 0x6BC
Guard disabled by reset to preserve existing regression behavior
Strict reject disabled by reset
Per-domain checking disabled by reset
Region ranges use half-open [base, limit) semantics
One new queue error summary bit: CSR_QUEUE_ERROR_STATUS[9] MEMORY_GUARD_ERROR
No new P22 event bit; reuse QUEUE_ERROR_EVENT
No SQ entry format change
No CQ completion record format change
No descriptor format change
No BRAM / GEMM / DMA / frontend datapath semantic change
```

Frozen P27 guard domains:

```text
SQ command memory
CQ completion memory
descriptor memory
source memory
destination memory
```

Guard checking is intended to happen before unsafe lower-level traffic is issued:

```text
SQ range checked before SQ command fetch
CQ range checked before reserving / writing completion slots
descriptor range checked before descriptor-fetch AXI read launch
source range checked before DMA / AXI-Stream / Direct Stream source reads
destination range checked before DMA store destination writes
```

P27B queue/event integration policy:

```text
Guard failure sets guard-specific sticky diagnostics.
Guard failure in the queue command path sets CSR_QUEUE_ERROR_STATUS[9].
The host is notified through the existing P22 QUEUE_ERROR_EVENT.
If the CQ slot is safe, a CQ error record may be written.
If the CQ slot is unsafe, no completion writeback is issued and CSR diagnostics are authoritative.
```

P27B validation status:

```text
P27A: Memory access guard prototype spec PASS
P27B: Memory guard CSR policy / range register map freeze PASS
```

P27B does not add UVM regression items.  Full regression remains:

```text
TOTAL : 138
PASS  : 138
FAIL  : 0
```



---

## 29. P27H Memory Access Guard Documentation Closure Addendum

P27H closes the memory access guard validation using the CSR policy frozen in P27B.

The canonical P27 CSR map remains unchanged from P27B:

```text
P27 memory guard window : 0x640 - 0x6BC
CSR_QUEUE_ERROR_STATUS[9] = MEMORY_GUARD_ERROR
P22 event notification    = reuse QUEUE_ERROR_EVENT, no new event bit
```

Validated P27 CSR usage policy:

```text
Guard remains disabled by reset.
P27 tests program guard regions explicitly before enabling checks.
Region base/limit registers use half-open [base, limit) semantics.
SQ, CQ, descriptor, source, and destination checks are individually enabled through CSR_MEM_GUARD_CONTROL.
Guard failures set CSR_MEM_GUARD_ERROR_STATUS and CSR_QUEUE_ERROR_STATUS[9].
Guard failures notify the host through the existing P22 QUEUE_ERROR_EVENT.
If the selected CQ slot is safe, a CQ error record may be written.
If the selected CQ slot is unsafe, completion writeback is suppressed and guard/queue CSR diagnostics are authoritative.
```

Validated P27 full-regression representatives:

```text
csr_mem_guard_sq_desc_case102
csr_mem_guard_dma_range_case102
csr_mem_guard_cq_recovery_case102
```

Full regression after P27G:

```text
TOTAL : 141
PASS  : 141
FAIL  : 0
```

P27G also updates the P22 event CSR smoke invalid-address probe to stay beyond the P27 memory guard window.  Address `0x640` is now a valid P27 register (`CSR_MEM_GUARD_VERSION`), so the invalid-address probe uses the first word after the P27 window instead.

P27H does not change the canonical CSR map, register access types, reset values, SQ entry format, CQ completion record format, descriptor format, or P22 event bit allocation.


---

## 30. P28B Event CSR Moderation Policy Freeze

P28B freezes the first event coalescing / interrupt moderation CSR policy.

Unlike P27, P28 does not allocate a new CSR window.  P28 reuses reserved fields inside the existing P22 event notification window:

```text
P22/P28 event notification window : 0x600 - 0x63C
P28 moderation registers          : 0x630 - 0x63C
```

Frozen P28 CSR policy:

```text
CSR_EVENT_CQ_THRESHOLD at 0x628 is reused as the CQ occupancy threshold.
CSR_EVENT_MOD_CONTROL at 0x630 enables moderation policy.
CSR_EVENT_MOD_STATUS at 0x634 reports live moderation state.
CSR_EVENT_MOD_TIMER_LIMIT at 0x638 programs bounded-latency timer fallback.
CSR_EVENT_MOD_DEBUG at 0x63C reports release cause and debug counters.
CSR_EVENT_MOD_CONTROL reset is 0x0000_0000, so existing regression behavior is preserved.
```

Frozen P28 event source policy:

```text
Completion-style sources may be coalesced when moderation is enabled:
  QUEUE_COMMAND_COMPLETED_EVENT
  CQ_NOT_EMPTY_EVENT
  CQ_THRESHOLD_EVENT
  CQ_MODERATION_TIMER_EVENT

Urgent sources bypass moderation:
  QUEUE_ERROR_EVENT
  QUEUE_STOPPED_EVENT
  QUEUE_DRAINED_EVENT
  CQ_FULL_STALL_EVENT
  CQ_SPACE_RECOVERED_EVENT
  RUNTIME_DOORBELL_EVENT
  RUNTIME_APPEND_CONSUMED_EVENT
  TEST_EVENT
```

Frozen release policy:

```text
Threshold release occurs when CQ occupancy reaches CSR_EVENT_CQ_THRESHOLD.
Timer release occurs when unnotified CQ work remains until CSR_EVENT_MOD_TIMER_LIMIT expires.
Timer expiry is not a queue error and does not set COMMAND_TIMEOUT_ERROR.
Queue error / stopped / drained / CQ-full recovery sources remain prompt and bypass coalescing.
W1C / re-arm while CQ remains non-empty must resample CQ occupancy and either reassert or restart moderation timing.
```

Validation status after P28B:

```text
P28A: Event coalescing / interrupt moderation prototype spec PASS
P28B: Event CSR moderation policy freeze PASS
```

P28B does not add RTL, UVM tests, Tcl scripts, README updates, or regression-list items.  Full regression remains:

```text
TOTAL : 141
PASS  : 141
FAIL  : 0
```


---

## 31. P28H Event Coalescing / Interrupt Moderation CSR Closure

P28H records closure of the event coalescing / interrupt moderation CSR policy after P28D/P28E/P28F targeted validation and P28G full-regression integration.

The canonical P28 CSR map remains unchanged from P28B:

```text
P22/P28 event notification window : 0x600 - 0x63C
CSR_EVENT_CQ_THRESHOLD            : 0x628
CSR_EVENT_MOD_CONTROL             : 0x630
CSR_EVENT_MOD_STATUS              : 0x634
CSR_EVENT_MOD_TIMER_LIMIT         : 0x638
CSR_EVENT_MOD_DEBUG               : 0x63C
```

Validated P28 CSR behavior:

```text
CSR_EVENT_MOD_CONTROL reset disables moderation and preserves immediate P22 behavior.
CSR_EVENT_CQ_THRESHOLD controls threshold-based coalesced CQ notification.
CSR_EVENT_MOD_TIMER_LIMIT controls bounded-latency timer fallback notification.
CSR_EVENT_MOD_STATUS exposes moderation active state, CQ occupancy, unnotified CQ count, and timer state.
CSR_EVENT_MOD_DEBUG exposes release cause and threshold/timer release counters.
CSR_EVENT_PENDING[11] reports CQ_MODERATION_TIMER_EVENT for timer fallback release.
```

Validated P28 full-regression representatives:

```text
csr_event_mod_cq_threshold_case102
csr_event_mod_timer_fallback_case102
csr_event_mod_batch_rearm_recovery_case102
```

Full regression after P28G:

```text
TOTAL : 144
PASS  : 144
FAIL  : 0
```

P28H does not add a new CSR window, change any existing CSR address, change the SQ entry format, change the CQ completion record format, change the P17 descriptor format, change the P18 completion record format, or change the BRAM/GEMM/DMA/frontend datapaths.


---

## 32. P29B Runtime Telemetry CSR Policy / Counter Map Freeze

P29B freezes the first runtime telemetry CSR policy for queue/event/cycle observability.

Unlike P28, P29 allocates a new CSR window because the telemetry block needs a consolidated software-readable counter view beyond the existing queue, event, moderation, and guard debug registers.

Frozen P29 CSR policy:

```text
New P29 runtime telemetry CSR window: 0x6C0 - 0x73C
Telemetry disabled by reset to preserve existing regression behavior
Telemetry counters are observational only
Telemetry clear does not clear functional queue/event/guard state
32-bit software-visible counters
Counters wrap on overflow in the first prototype
No hardware division or ratio registers
No new P22 event bit
No SQ entry format change
No CQ completion record format change
No descriptor format change
No completion record format change
No BRAM / GEMM / DMA / frontend datapath semantic change
```

Frozen P29 telemetry groups:

```text
Queue service counters:
  queue starts, SQ command accepts, command completions, CQ commits, drained / stopped / error observations

Host CQ consumption counters:
  positive CQ_HEAD update count, total consumed CQ delta, maximum CQ batch size

Event / interrupt efficiency counters:
  event captures, IRQ-eligible captures, completion-style event releases

P28 moderation counters:
  coalesced releases, threshold releases, timer releases, urgent bypass observations

Stall / recovery counters:
  CQ-full stall, CQ-space recovery, timeout error, memory-guard error, STOP_QUEUE request

Cycle counters:
  queue enabled, queue busy, queue idle, queue stalled, CQ-full stall, lower-level wait cycles
```

Frozen P29 source policy:

```text
P29 counters observe existing queue/event/moderation/guard source points.
P29 counters must not create new command acceptance, new event pending bits, new queue errors, or new datapath side effects.
P29 host-consume telemetry observes positive CSR_CQ_HEAD deltas only.
P29 event efficiency telemetry mirrors source points already validated by P22 and P28.
P29 timeout and guard telemetry are summary counts; existing P24/P27 diagnostics remain authoritative.
```

P29B validation status:

```text
P29A: Runtime telemetry prototype spec PASS
P29B: Telemetry CSR policy / counter map freeze PASS
```

P29B does not add RTL, UVM regression items, Tcl scripts, README updates, or regression-list items.  Full regression remains:

```text
TOTAL : 144
PASS  : 144
FAIL  : 0
```

---

## 33. P29H Runtime Telemetry CSR Closure

P29H records closure of the runtime telemetry CSR policy after P29D/P29E/P29F targeted validation and P29G full-regression integration.

The canonical P29 CSR map remains the P29B frozen runtime telemetry window:

```text
P29 runtime telemetry window : 0x6C0 - 0x73C
CSR_TELEM_VERSION            : 0x6C0
CSR_TELEM_COMMAND            : 0x6C4
CSR_TELEM_STATUS             : 0x6C8
CSR_TELEM_CONTROL            : 0x6CC
CSR_TELEM_QUEUE_START_COUNT  : 0x6D0
CSR_TELEM_LOWER_WAIT_CYCLES  : 0x73C
```

Validated P29 CSR behavior:

```text
CSR_TELEM_VERSION reports 0x0001_0029.
CSR_TELEM_CONTROL reset is 0x0000_0000, so telemetry is disabled by reset.
CSR_TELEM_COMMAND.CLEAR_TELEMETRY_COUNTERS clears telemetry counters and max trackers only.
Telemetry clear does not clear queue state, event pending bits, memory guard diagnostics, timeout status, SQ/CQ pointers, CQ records, or lower-level sticky status.
Queue service counters observe accepted START_QUEUE, SQ accepts, command completions, CQ commits, drained, stopped, and error observations.
Host CQ consumption counters observe positive CSR_CQ_HEAD deltas and track maximum CQ batch size.
Event / IRQ efficiency counters observe existing P22 event capture and IRQ-eligible source points.
P28 moderation counters observe coalesced, threshold, timer, and urgent-bypass release source points.
CQ-full stall / CQ-space recovery counters and cycle counters observe existing queue state source points.
```

Validated P29 full-regression representatives:

```text
csr_basic_telemetry_counter_case102
csr_interrupt_efficiency_telemetry_case102
csr_stall_recovery_telemetry_case102
```

Full regression after P29G:

```text
TOTAL : 147
PASS  : 147
FAIL  : 0
```

P29H does not change the P29B address map, access types, reset values, or register bit definitions.  It also does not add new event bits, alter P28 moderation policy, alter P27 memory guard policy, alter P26 lifecycle policy, change SQ/CQ/descriptor/completion formats, or change BRAM/GEMM/DMA/frontend datapaths.

