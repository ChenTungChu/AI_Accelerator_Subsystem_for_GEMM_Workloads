# Descriptor Fetch Prototype for CSR Recipe Sequencer Spec

## 1. Purpose

This document defines the P17A descriptor-fetch prototype specification for the AI Accelerator Subsystem.

P16 completed a small CSR-resident recipe sequencer.  The host can program descriptor slots through AXI-Lite CSR registers and launch a multi-slot recipe with one command:

```text
program CSR slot0 descriptor
program CSR slot1 descriptor
program CSR_RECIPE_CONTROL
START_RECIPE
hardware dispatches slot0 -> slot1 through the P15 job worker
poll RECIPE_DONE / RECIPE_ERROR
```

P17-lite raises this one level by allowing the host to place the same type of recipe descriptors in external memory.  The hardware fetches those descriptors into an internal recipe snapshot and then reuses the existing P16 recipe sequencer and P15 job sequencer.

The intended P17-lite programming model is:

```text
1. Host writes a compact descriptor table into external descriptor memory.
2. Host writes DESC_BASE_ADDR / DESC_COUNT / DESC_STRIDE through CSR.
3. Host writes START_FETCH_RECIPE.
4. Hardware fetches the descriptors from memory.
5. Hardware validates the fetched descriptors.
6. Hardware builds an internal P16-compatible recipe snapshot.
7. Existing P16 recipe sequencer dispatches the fetched slots through the existing P15 job worker.
8. Host polls P16 recipe done/error status and checks final result memory.
```

P17 is intentionally scoped as a prototype extension.  It is not a full production command processor.

---

## 2. Baseline Before P17

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
P15 single-job descriptor and hardware sequencer
P16 CSR-resident multi-slot recipe sequencer
P16 recipe-level DMA / C RMW / AXI-Stream / Direct Stream validation
P16 recipe reject / busy / error handling validation
Full UVM regression passing 105/105 after P17H closure
```

P17 must preserve the existing hierarchy:

```text
P14 CSR micro-operation path     -> debug / compatibility
P15 single-job sequencer         -> one descriptor worker
P16 CSR-resident recipe sequencer -> multi-slot recipe dispatcher
P17 descriptor fetch prototype   -> memory-backed recipe descriptor loader
```

P17 must not require changes to:

```text
axi_mm_dual_port_bram
GEMM datapath behavior
DMA load/store datapath protocol
AXI-Stream preload datapath protocol
Direct Stream preload datapath protocol
existing P14 CSR micro-operation programming model
existing P15 START_JOB programming model
existing P16 CSR slot START_RECIPE programming model
```

---

## 3. P17 Design Intent

P17 converts the P16 CSR-slot programming model into a memory-backed descriptor programming model.

P16 control model:

```text
Software/UVM writes descriptor slots directly into CSR registers:

  write slot0 registers
  write slot1 registers
  START_RECIPE
```

P17-lite control model:

```text
Software/UVM writes descriptors into memory:

  write descriptor table into external memory
  write DESC_BASE_ADDR / DESC_COUNT
  START_FETCH_RECIPE
```

Hardware then performs:

```text
fetch descriptor0
fetch descriptor1
validate descriptors
build internal recipe snapshot
start existing P16 recipe sequencer
```

The key design goal is to add a realistic memory-backed descriptor launch path while reusing the stable P16/P15 control stack.

P17 is not intended to improve GEMM performance directly.  It improves the software-visible control model and makes the accelerator look more like a realistic host-programmable subsystem.

---

## 4. P17 Scope

### 4.1 Included

P17 includes:

```text
External-memory descriptor table format
Descriptor fetch CSR register window
START_FETCH_RECIPE command
Single outstanding descriptor fetch
Single outstanding launched recipe
Descriptor fetch engine
Descriptor validation
Fetched descriptor to P16 recipe snapshot bridge
DMA two-slot descriptor-fetch recipe validation
C RMW two-slot descriptor-fetch recipe validation
One frontend descriptor-fetch representative validation
Fetch reject / busy / malformed descriptor / AXI read error validation
Full regression integration with a small targeted subset
Documentation closure
```

### 4.2 Not Included

P17 does not include:

```text
Linked-list descriptors
Memory-resident circular queue
Multiple descriptor tables outstanding
Multiple recipes outstanding
Out-of-order recipe execution
Descriptor cache
Interrupt output
Completion writeback to descriptor memory
Doorbell queue with producer/consumer indices
Preemptive abort with partial rollback
Overlapped preload / compute / store pipeline
Double buffering
Scratchpad banking
Cache-coherent host interface
Linux driver
C software driver
UVM RAL model
AXI interconnect / NoC integration
```

These can remain future work.  The P17 prototype should stay small and explainable as a single-person project milestone.

### 4.3 Current Implementation Status

P17 has completed targeted validation and full-regression integration through P17H:

```text
P17A: Descriptor fetch prototype spec                         PASS
P17B: Descriptor fetch engine RTL / compile smoke              PASS
P17C: CSR register plumbing / CSR-level fetch smoke            PASS
P17D: Fetched descriptor -> P16 recipe snapshot bridge         PASS
P17E: C RMW descriptor-fetch recipe validation                 PASS
P17F: Frontend descriptor-fetch representative validation      PASS
P17G: Fetch reject / busy / malformed descriptor handling      PASS
P17H: Full regression integration                              PASS

Full regression after P17H:
  TOTAL : 105
  PASS  : 105
  FAIL  : 0
```

Validated P17 full-regression representatives:

```text
csr_desc_fetch_smoke
csr_desc_fetch_dma_two_slot_case102
csr_desc_fetch_c_rmw_two_slot_case208
csr_desc_fetch_direct_stream_two_slot_case102
csr_desc_fetch_reject_error_case102
```


---

## 5. Recommended RTL Partition

P17 should add one small descriptor fetch engine and a narrow integration bridge into the existing CSR top.

Recommended new RTL:

```text
rtl/sequencer/ai_accel_desc_fetch_engine.sv
```

Modified RTL:

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
            -> P16 CSR-resident recipe slot outputs
            -> P17 descriptor fetch control/status
                -> ai_accel_desc_fetch_engine
                    -> descriptor-memory AXI read master
                    -> fetched descriptor array
                    -> fetched recipe snapshot bridge
                        -> existing ai_accel_recipe_sequencer
                            -> existing ai_accel_job_sequencer
                                -> existing ai_accel_subsys datapath
```

P17 should not duplicate the P16 recipe FSM or the P15 job FSM.

P17's job is only:

```text
read descriptors from memory
validate descriptors
provide a P16-compatible snapshot
request the existing P16 recipe sequencer to start
```

---

## 6. Descriptor Memory Interface Policy

### 6.1 Prototype Interface

The P17 prototype should use a dedicated descriptor-memory AXI read master interface.

Rationale:

```text
keeps descriptor fetch independent from DMA load source ports
avoids adding AXI arbitration in P17-lite
avoids modifying the BRAM model
keeps the fetch feature easy to debug
preserves existing DMA / AXI-Stream / Direct Stream source interfaces
```

Recommended interface style:

```systemverilog
// Descriptor-memory AXI-MM read master, discrete wires
output logic [AXI_ID_WIDTH-1:0] desc_axi_arid,
output logic [ADDR_WIDTH-1:0]   desc_axi_araddr,
output logic [7:0]              desc_axi_arlen,
output logic [2:0]              desc_axi_arsize,
output logic [1:0]              desc_axi_arburst,
output logic                    desc_axi_arvalid,
input  logic                    desc_axi_arready,

input  logic [AXI_ID_WIDTH-1:0] desc_axi_rid,
input  logic [DATA_WIDTH-1:0]   desc_axi_rdata,
input  logic [1:0]              desc_axi_rresp,
input  logic                    desc_axi_rlast,
input  logic                    desc_axi_rvalid,
output logic                    desc_axi_rready
```

The descriptor fetch RTL should use discrete AXI wires, matching the existing project policy for RTL-side AXI masters.

### 6.2 Descriptor Read Width

The descriptor table is defined as a sequence of 32-bit logical words.

The physical AXI data width may be 64 bits.  For a 64-bit descriptor read beat:

```text
lower 32 bits -> descriptor word at byte offset +0
upper 32 bits -> descriptor word at byte offset +4
```

Recommended first implementation:

```text
Descriptor base address must be DATA_WIDTH-byte aligned.
Descriptor stride must be DATA_WIDTH-byte aligned.
Descriptor fetches use incrementing AXI reads.
No unaligned descriptor table support in P17-lite.
```

---

## 7. Memory Descriptor Format

The P17 memory descriptor mirrors the P16 slot descriptor layout.  This keeps the bridge simple and avoids inventing a second job format.

Recommended descriptor stride:

```text
DESC_STRIDE reset/default = 0x80 bytes
```

Only the first defined words are required for P17-lite.  Remaining bytes in the 0x80-byte descriptor stride are reserved.

| Byte Offset | Name | Description |
|---:|---|---|
| 0x00 | `DESC_CONTROL` | Valid bit, input/output mode, accumulate_enable, policy bits |
| 0x04 | `DESC_BASE_ADDR_A` | GEMM A logical base address |
| 0x08 | `DESC_BASE_ADDR_B` | GEMM B logical base address |
| 0x0C | `DESC_BASE_ADDR_C` | GEMM C scratchpad base address |
| 0x10 | `DESC_DIM_M` | GEMM M dimension |
| 0x14 | `DESC_DIM_N` | GEMM N dimension |
| 0x18 | `DESC_DIM_K` | GEMM K dimension |
| 0x1C | `DESC_A_SRC_BASE` | External/source-memory A base for preload modes |
| 0x20 | `DESC_A_DST_BASE` | Scratchpad or operand-buffer A destination/base |
| 0x24 | `DESC_A_LOAD_BEATS` | A preload length in DATA_WIDTH beats |
| 0x28 | `DESC_B_SRC_BASE` | External/source-memory B base for preload modes |
| 0x2C | `DESC_B_DST_BASE` | Scratchpad or operand-buffer B destination/base |
| 0x30 | `DESC_B_LOAD_BEATS` | B preload length in DATA_WIDTH beats |
| 0x34 | `DESC_STORE_SRC_BASE` | Scratchpad C source base for DMA store |
| 0x38 | `DESC_STORE_DST_BASE` | External destination memory base for DMA store |
| 0x3C | `DESC_STORE_BYTE_COUNT` | DMA store byte count |
| 0x40 | `DESC_USER_TAG` | Optional debug tag |
| 0x44 - 0x7C | `DESC_RESERVED` | Reserved for future fields |

### 7.1 `DESC_CONTROL` Bit Definitions

| Bits | Name | Reset | Description |
|---:|---|---:|---|
| 0 | `VALID` | 0 | Descriptor is valid and may be fetched into a recipe |
| [2:1] | `INPUT_MODE` | 0 | 0=HOST_PRELOADED, 1=DMA_LOAD, 2=AXIS_PRELOAD, 3=DIRECT_STREAM |
| [4:3] | `OUTPUT_MODE` | 0 | 0=HOST_READBACK, 1=DMA_STORE |
| 5 | `ACCUMULATE_ENABLE` | 0 | GEMM C RMW accumulation control for this descriptor |
| 6 | `FINAL_SLOT_HINT` | 0 | Optional software hint; not required for correctness |
| [31:7] | `RSVD` | 0 | Reserved |

The encodings match the P15 job mode and P16 slot control policy.

---

## 8. Descriptor Fetch CSR Register Extension

P17 should add a descriptor-fetch CSR window above the P16 recipe slot register range.

Recommended base:

```text
DESC_FETCH CSR base = 0x500
```

The existing windows remain unchanged:

```text
P14 micro-operation CSR window : 0x000 - 0x08C
P15 job CSR window             : 0x100 - 0x18C
P16 recipe CSR window          : 0x200 - 0x28C
P16 slot CSR window            : 0x300 - 0x4FC
P17 descriptor fetch window    : 0x500 and above
```

### 8.1 Register Map

| Offset | Name | Access | Description |
|---:|---|---|---|
| 0x500 | `CSR_DESC_FETCH_VERSION` | RO | Descriptor fetch version / feature ID |
| 0x504 | `CSR_DESC_FETCH_COMMAND` | W1P | Descriptor fetch start and clear commands |
| 0x508 | `CSR_DESC_FETCH_STATUS` | RO | Live fetch status summary |
| 0x50C | `CSR_DESC_FETCH_DONE_STATUS` | RO/W1C | Sticky fetch done status |
| 0x510 | `CSR_DESC_FETCH_ERROR_STATUS` | RO/W1C | Sticky fetch error status |
| 0x514 | `CSR_DESC_FETCH_CONTROL` | RW | Fetch policy bits |
| 0x518 | `CSR_DESC_FETCH_REJECT_STATUS` | RO/W1C | Sticky fetch command reject reasons |
| 0x51C | `CSR_DESC_FETCH_STATE` | RO | Current fetch engine state |
| 0x520 | `CSR_DESC_BASE_ADDR` | RW | Base address of descriptor table in external memory |
| 0x524 | `CSR_DESC_COUNT` | RW | Number of descriptors to fetch |
| 0x528 | `CSR_DESC_STRIDE` | RW | Byte stride between descriptors |
| 0x52C | `CSR_DESC_CURRENT_INDEX` | RO | Descriptor index currently being fetched or validated |
| 0x530 | `CSR_DESC_FETCHED_COUNT` | RO | Number of descriptors fetched in the last run |
| 0x534 | `CSR_DESC_ERROR_INDEX` | RO | Descriptor index associated with the last validation/fetch error |
| 0x538 | `CSR_DESC_ERROR_DETAIL` | RO | Implementation-defined debug detail for last error |
| 0x53C | `CSR_DESC_RESERVED_53C` | RO | Reserved |

---

## 9. Register Bit Definitions

### 9.1 `CSR_DESC_FETCH_VERSION` at 0x500

| Bits | Name | Access | Reset | Description |
|---:|---|---|---:|---|
| [31:16] | `MAJOR` | RO | 16'h0001 | Descriptor fetch major version |
| [15:8] | `MINOR` | RO | 8'h00 | Descriptor fetch minor version |
| [7:0] | `FEATURE_ID` | RO | 8'h17 | P17 descriptor fetch feature ID |

Recommended reset value:

```text
0x0001_0017
```

### 9.2 `CSR_DESC_FETCH_COMMAND` at 0x504

This is a write-one-pulse register.  Reads return zero.

| Bit | Name | Type | Description |
|---:|---|---|---|
| 0 | `START_FETCH_RECIPE` | W1P | Fetch descriptor table and launch a P16 recipe if accepted |
| 8 | `CLEAR_FETCH_DONE` | W1P | Clear sticky descriptor fetch done bits |
| 9 | `CLEAR_FETCH_ERROR` | W1P | Clear sticky descriptor fetch error/reject bits |

Unsupported combinations:

```text
START_FETCH_RECIPE with CLEAR_FETCH_ERROR if fetch errors are currently sticky
multiple unsupported command bits in the same write
```

Unsupported combinations do not start a fetch and set `CSR_DESC_FETCH_REJECT_STATUS.UNSUPPORTED_COMBO`.

### 9.3 `CSR_DESC_FETCH_STATUS` at 0x508

| Bit | Name | Access | Description |
|---:|---|---|---|
| 0 | `FETCH_BUSY` | RO | Descriptor fetch engine is fetching or validating descriptors |
| 1 | `FETCH_DONE` | RO | Sticky descriptor fetch done is set |
| 2 | `FETCH_ERROR` | RO | Sticky descriptor fetch error or reject is set |
| 3 | `FETCH_ACCEPT_READY` | RO | Fetch engine is idle and can accept START_FETCH_RECIPE |
| 4 | `RECIPE_LAUNCHED` | RO | Last successful fetch launched the P16 recipe path |
| 8 | `RECIPE_BUSY` | RO | Existing P16 recipe sequencer is busy |
| 9 | `JOB_BUSY` | RO | Existing P15 job worker is busy |
| 10 | `MICRO_OP_BUSY` | RO | Any underlying micro-operation engine is busy |
| 16 | `CSR_READY` | RO | CSR block ready for transactions |

`FETCH_DONE` means the descriptor fetch operation completed and the internal P16 recipe launch request was accepted.  It does not mean the GEMM recipe has completed.  Software should poll the existing P16 recipe done/error registers for recipe completion.

### 9.4 `CSR_DESC_FETCH_DONE_STATUS` at 0x50C

| Bit | Name | Type | Description |
|---:|---|---|---|
| 0 | `FETCH_DONE` | RO/W1C | Descriptor table fetch completed successfully |
| 1 | `DESC_VALIDATION_DONE` | RO/W1C | All fetched descriptors passed validation |
| 2 | `RECIPE_LAUNCH_DONE` | RO/W1C | Internal P16 recipe launch request was accepted |

### 9.5 `CSR_DESC_FETCH_ERROR_STATUS` at 0x510

| Bit | Name | Type | Description |
|---:|---|---|---|
| 0 | `AXI_READ_ERROR` | RO/W1C | Descriptor memory read returned non-OKAY response |
| 1 | `DESCRIPTOR_VALIDATION_ERROR` | RO/W1C | Fetched descriptor failed validation |
| 2 | `RECIPE_LAUNCH_ERROR` | RO/W1C | Internal P16 recipe launch request was unexpectedly rejected |
| 3 | `FETCH_SEQUENCE_ERROR` | RO/W1C | Fetch FSM reached an illegal state or unexpected event |
| 8 | `FETCH_TIMEOUT_RESERVED` | RO/W1C | Reserved for future timeout support |

On any fetch error, P17 must not launch a P16 recipe.

### 9.6 `CSR_DESC_FETCH_CONTROL` at 0x514

| Bits | Name | Access | Reset | Description |
|---:|---|---|---:|---|
| 0 | `AUTO_LAUNCH_RECIPE` | RW | 1 | Launch P16 recipe after successful fetch and validation |
| 1 | `STOP_ON_DESC_ERROR` | RW | 1 | Stop fetch/validation on first malformed descriptor |
| 2 | `CLEAR_RECIPE_STICKY_ON_START` | RW | 1 | Clear P16 recipe sticky status before internal launch |
| 3 | `CLEAR_JOB_STICKY_ON_START` | RW | 1 | Clear P15 job sticky status before recipe launch |
| [31:4] | `RSVD` | RO | 0 | Reserved |

Recommended reset value:

```text
0x0000_000F
```

P17-lite should use `AUTO_LAUNCH_RECIPE=1`.  Fetch-only mode can be reserved for later debug if needed.

### 9.7 `CSR_DESC_FETCH_REJECT_STATUS` at 0x518

| Bit | Name | Type | Description |
|---:|---|---|---|
| 0 | `FETCH_BUSY_REJECT` | RO/W1C | START_FETCH_RECIPE requested while fetch_busy is high |
| 1 | `RECIPE_BUSY_REJECT` | RO/W1C | START_FETCH_RECIPE requested while recipe_busy is high |
| 2 | `JOB_BUSY_REJECT` | RO/W1C | START_FETCH_RECIPE requested while job_busy is high |
| 3 | `MICRO_OP_BUSY_REJECT` | RO/W1C | START_FETCH_RECIPE requested while any underlying engine is busy |
| 4 | `ZERO_COUNT_REJECT` | RO/W1C | DESC_COUNT is zero |
| 5 | `COUNT_RANGE_REJECT` | RO/W1C | DESC_COUNT exceeds P16_RECIPE_QUEUE_DEPTH |
| 6 | `BASE_ALIGN_REJECT` | RO/W1C | DESC_BASE_ADDR is not DATA_WIDTH-byte aligned |
| 7 | `STRIDE_ALIGN_REJECT` | RO/W1C | DESC_STRIDE is not DATA_WIDTH-byte aligned |
| 8 | `STRIDE_TOO_SMALL_REJECT` | RO/W1C | DESC_STRIDE is smaller than the required descriptor byte length |
| 9 | `UNSUPPORTED_COMBO` | RO/W1C | Unsupported command-bit combination was written |

Rejected commands do not start descriptor memory reads.

### 9.8 `CSR_DESC_FETCH_STATE` at 0x51C

Recommended state encodings:

| Value | Name | Meaning |
|---:|---|---|
| 0 | `IDLE` | No active descriptor fetch |
| 1 | `CMD_VALIDATE` | Validate CSR fetch command fields |
| 2 | `DESC_ADDR_SETUP` | Compute current descriptor word address |
| 3 | `AXI_AR` | Issue descriptor memory read address |
| 4 | `AXI_R_WAIT` | Wait for descriptor memory read data |
| 5 | `UNPACK_WORDS` | Unpack AXI read data into descriptor words |
| 6 | `DESC_VALIDATE` | Validate the fetched descriptor |
| 7 | `DESC_ADVANCE` | Move to next descriptor |
| 8 | `BUILD_RECIPE_SNAPSHOT` | Build P16-compatible fetched recipe snapshot |
| 9 | `RECIPE_LAUNCH` | Pulse internal P16 recipe launch request |
| 10 | `DONE` | Successful terminal state |
| 11 | `ERROR` | Error terminal state |

---

## 10. Descriptor Fetch Acceptance Rules

`START_FETCH_RECIPE` is accepted only when:

```text
fetch_busy == 0
recipe_busy == 0
job_busy == 0
acc_busy == 0
dma_load_busy == 0
axis_load_busy == 0
ds_load_busy == 0
dma_store_busy == 0
DESC_COUNT != 0
DESC_COUNT <= P16_RECIPE_QUEUE_DEPTH
DESC_BASE_ADDR is DATA_WIDTH-byte aligned
DESC_STRIDE is DATA_WIDTH-byte aligned
DESC_STRIDE >= required descriptor byte length
command write contains a supported command combination
```

When accepted:

```text
fetch_busy is set
current_index starts at 0
fetched_count clears to 0
fetch engine begins reading descriptor memory
```

When rejected:

```text
no AXI descriptor read is issued
fetch_busy remains 0
the corresponding reject sticky bit is set
```

---

## 11. Fetched Descriptor Validation Rules

Each fetched descriptor is valid only when:

```text
DESC_CONTROL.VALID == 1
DESC_DIM_M != 0
DESC_DIM_N != 0
DESC_DIM_K != 0
input/output mode combination is supported
```

For `HOST_PRELOADED` input mode:

```text
DESC_A_LOAD_BEATS may be zero
DESC_B_LOAD_BEATS may be zero
```

For `DMA_LOAD`, `AXIS_PRELOAD`, and `DIRECT_STREAM` input modes:

```text
DESC_A_LOAD_BEATS != 0
DESC_B_LOAD_BEATS != 0
```

For `HOST_READBACK` output mode:

```text
DESC_STORE_BYTE_COUNT may be zero
```

For `DMA_STORE` output mode:

```text
DESC_STORE_BYTE_COUNT != 0
```

If descriptor validation fails after the command has already been accepted:

```text
set DESCRIPTOR_VALIDATION_ERROR
record CSR_DESC_ERROR_INDEX
record implementation-defined CSR_DESC_ERROR_DETAIL
stop fetching additional descriptors if STOP_ON_DESC_ERROR=1
do not launch the P16 recipe
enter ERROR terminal state
```

---

## 12. Fetched Descriptor to P16 Recipe Snapshot Bridge

P17 should not write fetched descriptors back into the live P16 CSR slot register window.

Recommended policy:

```text
CSR slot path:
  P16 CSR slot registers -> P16 active recipe snapshot

P17 fetch path:
  fetched descriptor array -> P16 active recipe snapshot
```

This creates two producers for the P16 active recipe snapshot:

```text
1. CSR-resident slot registers, selected by CSR_RECIPE_COMMAND.START_RECIPE
2. fetched memory descriptors, selected by CSR_DESC_FETCH_COMMAND.START_FETCH_RECIPE
```

Only one producer may be active at a time.

Ownership policy:

```text
while fetch_busy == 1:
  P16 CSR START_RECIPE is rejected
  P15 START_JOB is rejected
  P14 manual START_* commands are rejected

while recipe_busy == 1:
  P17 START_FETCH_RECIPE is rejected
  P16 CSR START_RECIPE is rejected
  P15 START_JOB is rejected
  P14 manual START_* commands are rejected
```

After successful descriptor fetch and validation, the bridge provides:

```text
recipe_start_slot = 0
recipe_count      = DESC_COUNT
recipe_slot_snapshot[0 .. DESC_COUNT-1] = fetched descriptors
```

Then it requests an internal P16 recipe launch.

---

## 13. Completion Semantics

### 13.1 Descriptor Fetch Completion

`DESC_FETCH_DONE` means:

```text
all requested descriptors were read from descriptor memory
all requested descriptors passed validation
an internal P16 recipe launch request was accepted
```

`DESC_FETCH_DONE` does not mean the recipe computation completed.

### 13.2 Recipe Completion

Recipe-level completion remains owned by the existing P16 recipe sequencer:

```text
CSR_RECIPE_DONE_STATUS.RECIPE_DONE
CSR_RECIPE_ERROR_STATUS
CSR_RECIPE_SLOT_DONE_MASK
CSR_RECIPE_SLOT_ERROR_MASK
CSR_RECIPE_SLOT_REJECT_MASK
```

Software or UVM should poll P16 recipe status after `DESC_FETCH_DONE` if it wants to know when the GEMM recipe has completed.

---

## 14. Error Policy

### 14.1 Command Rejects

Pre-fetch command issues are command rejects:

```text
zero DESC_COUNT
DESC_COUNT greater than queue depth
unaligned DESC_BASE_ADDR
unaligned DESC_STRIDE
DESC_STRIDE too small
START_FETCH_RECIPE while fetch_busy
START_FETCH_RECIPE while recipe_busy/job_busy/micro_op_busy
unsupported command combination
```

Command rejects do not issue descriptor memory reads.

### 14.2 Fetch Errors

Runtime fetch issues are fetch errors:

```text
AXI read response error
unexpected RLAST / missing response behavior
fetch FSM illegal state
descriptor validation failure
internal P16 recipe launch failure after validation
```

Fetch errors stop the descriptor-fetch flow and do not launch the recipe.

### 14.3 AXI Read Error Handling

If any descriptor read beat returns non-OKAY response:

```text
set AXI_READ_ERROR
record current descriptor index
stop fetching additional descriptor data
clear fetch_busy
enter ERROR terminal state
do not launch P16 recipe
```

P17-lite does not require automatic AXI retry.

---

## 15. Interaction With P14 / P15 / P16 Control Models

P17 must preserve the existing debug and control flows.

Policy:

```text
When fetch_busy == 0 and recipe_busy == 0 and job_busy == 0:
  P14 micro-operation commands are allowed.
  P15 START_JOB is allowed.
  P16 START_RECIPE from CSR slots is allowed.
  P17 START_FETCH_RECIPE is allowed.

When fetch_busy == 1:
  P14 START_* commands are rejected.
  P15 START_JOB is rejected.
  P16 START_RECIPE is rejected.
  Another P17 START_FETCH_RECIPE is rejected.

When recipe_busy == 1:
  P14 START_* commands are rejected.
  P15 START_JOB is rejected.
  P16 START_RECIPE is rejected.
  P17 START_FETCH_RECIPE is rejected.
```

This keeps a single control owner for the underlying engines at all times.

---

## 16. Programming Sequences

### 16.1 Two-Descriptor DMA Recipe

```text
1. UVM or software writes two descriptors into descriptor memory.

2. Descriptor 0:
     VALID             = 1
     INPUT_MODE        = DMA_LOAD
     OUTPUT_MODE       = HOST_READBACK or DMA_STORE depending test policy
     ACCUMULATE_ENABLE = 0

3. Descriptor 1:
     VALID             = 1
     INPUT_MODE        = DMA_LOAD
     OUTPUT_MODE       = DMA_STORE
     ACCUMULATE_ENABLE = 0

4. CSR writes:
     CSR_DESC_BASE_ADDR = descriptor_table_base
     CSR_DESC_COUNT     = 2
     CSR_DESC_STRIDE    = 0x80

5. CSR writes CSR_DESC_FETCH_COMMAND.START_FETCH_RECIPE.

6. Hardware fetches descriptor 0 and descriptor 1.
7. Hardware builds P16 recipe snapshot.
8. Hardware internally launches P16 recipe.
9. UVM polls P16 recipe done.
10. UVM compares DMA destination memory against software reference.
```

Recommended first case:

```text
CASE_ID=102
```

### 16.2 Two-Descriptor C RMW Recipe

```text
Descriptor 0:
  VALID             = 1
  INPUT_MODE        = DMA_LOAD
  OUTPUT_MODE       = HOST_READBACK
  ACCUMULATE_ENABLE = 0
  K_part            = first K partition

Descriptor 1:
  VALID             = 1
  INPUT_MODE        = DMA_LOAD
  OUTPUT_MODE       = DMA_STORE
  ACCUMULATE_ENABLE = 1
  K_part            = second K partition
```

Recommended first C RMW case:

```text
CASE_ID=208
```

This validates that P17 descriptor fetch can drive the existing P16 C RMW recipe behavior without changing the GEMM C RMW datapath.

### 16.3 Direct Stream Descriptor-Fetch Recipe

```text
Descriptor 0 / 1:
  INPUT_MODE = DIRECT_STREAM
  OUTPUT_MODE = HOST_READBACK for intermediate slots, DMA_STORE for final slot
```

The P15 job worker derives:

```text
GEMM_INPUT_STREAM_MODE = 1
```

for Direct Stream descriptors.

Recommended representative case:

```text
CASE_ID=102
```

---

## 17. P17 Validation Status

P17 validation is complete through P17H.  The final targeted and full-regression coverage proves both happy-path descriptor fetch and control/error handling.

### 17.1 CSR-Level Fetch Smoke

Validated test:

```text
ai_accel_subsys_csr_desc_fetch_smoke_test
```

Coverage:

```text
CSR writes DESC_BASE_ADDR / DESC_COUNT / DESC_STRIDE
START_FETCH_RECIPE launches the descriptor fetch engine
fetch_busy / fetch_done / fetch_error / reject / current_index / fetched_count are visible through CSR
fetched_snapshot_valid is visible after successful fetch
```

### 17.2 End-to-End Descriptor-Fetch Recipes

Validated tests:

```text
ai_accel_subsys_csr_desc_fetch_dma_two_slot_smoke_test           CASE_ID=102
ai_accel_subsys_csr_desc_fetch_c_rmw_two_slot_smoke_test         CASE_ID=208
ai_accel_subsys_csr_desc_fetch_direct_stream_two_slot_smoke_test CASE_ID=102
```

Coverage:

```text
fetch descriptor table from memory
build internal P16-compatible recipe snapshot
launch existing P16 recipe sequencer
dispatch through existing P15 job worker
validate final DMA destination memory against software reference
```

The C RMW descriptor-fetch recipe validates `slot0 accumulate_enable=0` and `slot1 accumulate_enable=1`.  The Direct Stream descriptor-fetch recipe validates that fetched `INPUT_MODE=DIRECT_STREAM` propagates through P16/P15 and selects GEMM input stream mode.

### 17.3 Reject / Busy / Error Handling

Validated test:

```text
ai_accel_subsys_csr_desc_fetch_reject_error_test CASE_ID=102
```

Coverage:

```text
DESC_COUNT=0 reject
DESC_COUNT > P16_RECIPE_QUEUE_DEPTH reject
unaligned DESC_BASE_ADDR reject
unaligned DESC_STRIDE reject
DESC_STRIDE too small reject
missing descriptor VALID bit error
unsupported descriptor output mode error
zero M/N/K dimension error
zero A preload length error
zero B preload length error
zero DMA store byte_count error
START_FETCH_RECIPE while fetch_busy reject
START_FETCH_RECIPE while recipe_busy reject
P16 START_RECIPE while fetch_busy reject
P15 START_JOB while fetch_busy reject
P14 START_* while fetch_busy reject
descriptor AXI RRESP error propagation
sticky clear and valid retry/recovery
```

### 17.4 Full Regression Integration

P17H added five descriptor-fetch representatives into the full UVM regression:

```text
csr_desc_fetch_smoke
csr_desc_fetch_dma_two_slot_case102
csr_desc_fetch_c_rmw_two_slot_case208
csr_desc_fetch_direct_stream_two_slot_case102
csr_desc_fetch_reject_error_case102
```

Current integrated baseline:

```text
TOTAL : 105
PASS  : 105
FAIL  : 0
```

---

## 18. Milestone Breakdown

```text
P17A: Descriptor fetch prototype spec                         PASS
P17B: Descriptor fetch engine RTL / compile smoke              PASS
P17C: CSR register plumbing / CSR-level fetch smoke            PASS
P17D: Fetched descriptor -> P16 recipe snapshot bridge         PASS
P17E: C RMW descriptor-fetch recipe validation                 PASS
P17F: Frontend descriptor-fetch representative validation      PASS
P17G: Fetch reject / busy / malformed descriptor handling      PASS
P17H: Full regression integration                              PASS
P17I: Documentation / closure update                           PASS target
```

---

## 19. Closed P17 Design Decisions

```text
Dedicated descriptor-memory AXI read master: yes
Descriptor field layout mirrors P16 slot descriptor: yes
Default descriptor stride: 0x80 bytes
START_FETCH_RECIPE auto-launches the P16 recipe after successful validation: yes
Fetch-only debug command: not included
Fetched descriptors write into live P16 CSR slots: no
DESC_FETCH_DONE waits for recipe completion: no
AXI read retry: not included
Linked-list or circular queue support: not included
Interrupt or descriptor completion writeback: not included
```

## 20. Risks and Mitigations

### Risk 1: Scope Creep Into Full Command Processor

Potential failure:

```text
P17 grows into linked lists, interrupts, completion writeback, producer/consumer queues, and multi-outstanding scheduling.
```

Mitigation:

```text
Define P17 as a descriptor fetch prototype.
Use one descriptor table base, one count, one start command, one outstanding fetch.
```

### Risk 2: Descriptor Format Mismatch

Potential failure:

```text
Memory descriptor format does not match P16 slot descriptor semantics.
```

Mitigation:

```text
Mirror P16 slot field layout and input/output mode encodings.
Create a focused snapshot bridge validation test.
```

### Risk 3: P16 CSR Slot Register Corruption

Potential failure:

```text
Fetched descriptors overwrite live P16 CSR slot registers and change software-visible state unexpectedly.
```

Mitigation:

```text
Use an internal fetched recipe snapshot path.
Do not write fetched descriptors into P16 CSR slot registers.
```

### Risk 4: Control Ownership Conflict

Potential failure:

```text
Software issues P14/P15/P16 commands while descriptor fetch is active.
```

Mitigation:

```text
Reject P14 START_*, P15 START_JOB, and P16 START_RECIPE while fetch_busy is high.
```

### Risk 5: Recipe Launch From Invalid Descriptor

Potential failure:

```text
Descriptor fetch completes but malformed descriptor still launches the recipe.
```

Mitigation:

```text
Validate all fetched descriptors before internal P16 recipe launch.
Stop and set DESCRIPTOR_VALIDATION_ERROR on first malformed descriptor.
```

### Risk 6: AXI Read Error Leaves Partial Snapshot

Potential failure:

```text
AXI read error occurs after some descriptors are fetched, but partial snapshot is launched.
```

Mitigation:

```text
Only assert internal recipe launch after all descriptors pass fetch and validation.
Clear or mark fetched snapshot invalid on AXI read error.
```

### Risk 7: Descriptor Endianness / Word Packing Bug

Potential failure:

```text
64-bit AXI read data is unpacked into 32-bit descriptor fields in the wrong order.
```

Mitigation:

```text
Document lower-32 first field ordering.
Use descriptor values with unique recognizable bit patterns in unit tests.
```

### Risk 8: Regression Runtime Growth

Potential failure:

```text
P17 adds too many recipe tests and makes full regression slow.
```

Mitigation:

```text
Add CSR smoke, three happy-path representatives, and one reject/error test to full regression.
Keep AXI-Stream descriptor-fetch as targeted if Direct Stream is selected for full regression.
```

---

## 21. Summary

P17 adds a minimal memory-backed descriptor fetch prototype on top of the completed P16 CSR-resident recipe sequencer.

The design converts this software-visible P16 flow:

```text
write CSR slot0
write CSR slot1
START_RECIPE
```

into this P17 flow:

```text
write descriptor table in memory
write DESC_BASE_ADDR / DESC_COUNT
START_FETCH_RECIPE
```

The implementation remains conservative:

```text
single outstanding descriptor fetch
single outstanding recipe
fixed descriptor format
fixed descriptor count bounded by P16_RECIPE_QUEUE_DEPTH
no linked list
no interrupt
no completion writeback
no descriptor cache
no overlap pipeline
no BRAM changes
no GEMM datapath changes
reuse existing P16 recipe sequencer
reuse existing P15 single-job worker
preserve P14/P15/P16 debug paths when idle
```

This provides a realistic host-programmable accelerator control extension while keeping the scope appropriate for a single-person digital design project.
