# Multi-Job Descriptor Queue / Recipe Sequencer Spec

## 1. Purpose

This document defines the P16A multi-job descriptor queue and recipe sequencer specification for the AI Accelerator Subsystem.

P15 completed a single-job hardware sequencer on top of the AXI-Lite CSR control plane.  The host can now program one CSR-resident job descriptor and launch a complete accelerator job through a single command:

```text
write one job descriptor
START_JOB
hardware runs preload A/B -> GEMM -> optional DMA store
poll JOB_DONE / JOB_ERROR
```

P16 raises the control abstraction from a single job to a small CSR-resident multi-job recipe.

The intended programming model is:

```text
1. Host writes multiple CSR-resident descriptor slots.
2. Host writes RECIPE_COUNT / control policy.
3. Host writes START_RECIPE.
4. Hardware recipe sequencer runs slot0, slot1, ..., slotN-1 in order.
5. Each slot is dispatched through the existing P15 single-job sequencer.
6. Host polls RECIPE_DONE / RECIPE_ERROR and reads recipe/per-slot status.
```

The first P16 implementation is intentionally scoped as a small CSR-resident queue.  It is not a memory-resident descriptor fetch engine, linked-list DMA engine, interrupt controller, preemptive scheduler, or software driver.

---

## 2. Current Baseline Before P16

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
P15 single-job descriptor registers
P15 single-job hardware sequencer
P15 job reject / busy / clear handling
P15 job-level DMA / AXI-Stream / Direct Stream representative tests
Full UVM regression passing 95/95 after P15E/P15F
```

P15 keeps the datapath subsystem intact and adds job-level control.  P16 should preserve that principle.

P16 must not require changes to:

```text
axi_mm_dual_port_bram
GEMM datapath behavior
DMA load/store datapath protocol
AXI-Stream preload datapath protocol
Direct Stream preload datapath protocol
existing P14 CSR micro-operation programming model
existing P15 single-job programming model
```

---

## 3. P16 Design Intent

P16 converts the accelerator from a single-job CSR model into a multi-job recipe model.

P15 control model:

```text
Software/UVM explicitly starts one complete job at a time:

  program job0 descriptor
  START_JOB
  poll JOB_DONE

  program job1 descriptor
  START_JOB
  poll JOB_DONE
```

P16 control model:

```text
Software/UVM programs multiple slots and starts one recipe:

  program slot0 descriptor
  program slot1 descriptor
  set RECIPE_COUNT = 2
  START_RECIPE
  poll RECIPE_DONE / RECIPE_ERROR
```

The recipe sequencer then performs the staged operation internally:

```text
slot0 -> slot1 -> ... -> slotN-1 -> RECIPE_DONE
```

The key design goal is to add realistic accelerator recipe control while reusing the validated P15 single-job sequencer as the worker for each slot.

---

## 4. P16 Scope

### 4.1 Included

P16 includes:

```text
CSR-resident descriptor slots
START_RECIPE command
recipe live busy status
sticky recipe done status
sticky recipe error status
recipe command reject status
current-slot debug status
per-slot done/error status summary
recipe-level performance accumulation
hardware recipe sequencer FSM
sequencer dispatch into the existing P15 job sequencer
support for DMA, AXI-Stream, and Direct Stream input modes per slot
support for host-readback/store-skip and DMA-store output modes per slot
multi-job C RMW accumulation recipes
UVM recipe-level smoke tests
full regression integration
```

### 4.2 Not Included

P16 does not include:

```text
Memory-resident descriptor fetch
Linked-list descriptors
Descriptor cache
Multiple recipes outstanding
Out-of-order job execution
Overlapped preload / compute / store pipeline
Double buffering
Preemptive abort with partial rollback
Interrupt output
Linux driver
C software driver
UVM RAL model
AXI interconnect / NoC integration
```

These can be future milestones after the CSR-resident recipe controller is stable.

### 4.5 Relationship to P18 Completion Writeback

P18 does not change P16 recipe execution semantics.  The recipe sequencer still owns slot dispatch, slot terminal status, recipe done/error/reject status, and recipe performance accumulation.  P18 observes the accepted descriptor-fetch context and P16 terminal status to build a completion record.

Validated P18 recipe-based completion representatives:

```text
csr_desc_fetch_dma_completion_wb_case102
csr_desc_fetch_direct_stream_completion_wb_case102
csr_desc_fetch_c_rmw_completion_wb_case208
```


---

## 5. Recommended RTL Partition

P16 should preserve the existing P14 CSR wrapper, P15 job sequencer, and datapath top.

Recommended new RTL:

```text
rtl/sequencer/ai_accel_recipe_sequencer.sv
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
            -> P15 single-job descriptor/config outputs
            -> P16 recipe descriptor-slot outputs
                -> ai_accel_recipe_sequencer
                    -> existing ai_accel_job_sequencer as one-job worker
                        -> existing ai_accel_subsys sideband starts/configs
```

The P16 recipe sequencer should sit above the P15 single-job sequencer.  It should not duplicate the P15 per-job preload/GEMM/store FSM.  Instead, it selects one descriptor slot, dispatches it as a P15 job, waits for that job to finish, and then advances to the next selected slot.

When no recipe is active, the existing P14 micro-operation path and P15 single-job path remain usable for debug and backward compatibility.

When a P16 recipe is active, the recipe sequencer owns job dispatch until the recipe completes or errors.

---

## 6. Clock and Reset Policy

### 6.1 Clock Domain

The P16 recipe sequencer is clocked by `dma_clk`.

Rationale:

```text
P14 CSR registers are dma_clk-domain.
P15 job descriptor and job sequencer control are dma_clk-domain.
Existing external control inputs are dma_clk-domain.
DMA load/store control already lives in dma_clk.
AXI-Stream and Direct Stream preload engines already handle their own CDC internally.
GEMM start/config are captured in dma_clk before crossing to core_clk inside ai_accel_subsys.
```

### 6.2 Reset

The P16 recipe sequencer reset uses `dma_rst_n`.

After reset:

```text
No recipe-generated job start is asserted.
recipe_busy clears to 0.
recipe_done sticky bits clear to 0.
recipe_error sticky bits clear to 0.
recipe_reject sticky bits clear to 0.
recipe_state returns to IDLE.
current_slot returns to 0.
completed_slot_count clears to 0.
per-slot done/error summaries clear to zero.
recipe performance accumulation registers clear to zero.
```

Descriptor slot CSR storage returns to its reset defaults.

### 6.3 Descriptor Snapshot Policy

The descriptor slot registers are CSR-visible storage.  On accepted `START_RECIPE`, the recipe sequencer must lock or snapshot the selected descriptor slots.

Recommended policy:

```text
On accepted START_RECIPE:
  latch RECIPE_COUNT
  latch RECIPE_START_SLOT
  latch each selected descriptor slot into an active recipe snapshot
```

The active recipe must use the snapshot, not the live CSR slot registers.

This allows software to read or even update descriptor slot registers while a recipe is active without changing the already-started recipe.  Updated descriptor slot registers take effect only on the next accepted `START_RECIPE`.

---

## 7. Recipe Model

### 7.1 Single Outstanding Recipe

P16 supports one active recipe at a time.

A recipe starts when `START_RECIPE` is accepted and ends when one of these occurs:

```text
All selected slots complete successfully -> RECIPE_DONE
Any selected slot reports error          -> RECIPE_ERROR
Reset                                     -> recipe state returns to IDLE
```

A second `START_RECIPE` while `recipe_busy==1` is rejected.

A P15 `START_JOB` while `recipe_busy==1` is rejected.

A P14 manual micro-operation command while `recipe_busy==1` is rejected.

### 7.2 Descriptor Slots

The recommended first implementation uses a small CSR-resident descriptor array:

```text
P16_RECIPE_QUEUE_DEPTH = 4
```

The first validation target may use only two slots, but the CSR map should reserve four slots so the interface does not need to change immediately after bring-up.

Each slot contains one P15-style job descriptor:

```text
slot valid / enable bit
input mode
output mode
accumulate_enable
GEMM A/B/C base addresses
GEMM M/N/K dimensions
A preload source/destination/beats
B preload source/destination/beats
C store source/destination/byte_count
```

### 7.3 Slot Execution Order

The initial P16 recipe executes slots in increasing slot index order.

Recommended first policy:

```text
start_slot = RECIPE_CONTROL.START_SLOT
count      = RECIPE_CONTROL.RECIPE_COUNT

execute:
  start_slot
  start_slot + 1
  ...
  start_slot + count - 1
```

Slot wrapping is not required for P16A/P16B.  A recipe that would exceed the configured queue depth should be rejected.

### 7.4 Slot Input Modes

Each slot uses the same input-mode encoding as the P15 job mode:

| Encoding | Name | Meaning |
|---:|---|---|
| 0 | `HOST_PRELOADED` | A/B already exist in scratchpad. Recipe dispatch skips input preload for the slot. |
| 1 | `DMA_LOAD` | Slot uses DMA load twice: A then B into scratchpad. |
| 2 | `AXIS_PRELOAD` | Slot uses AXI-Stream preload twice: A then B into scratchpad. |
| 3 | `DIRECT_STREAM` | Slot uses Direct Stream preload twice: A then B into operand buffer. |

### 7.5 Slot Output Modes

Each slot uses the same output-mode encoding as the P15 job mode:

| Encoding | Name | Meaning |
|---:|---|---|
| 0 | `HOST_READBACK` | C remains in scratchpad. Recipe dispatch does not launch DMA store for that slot. |
| 1 | `DMA_STORE` | Slot launches DMA store after GEMM done. |

For multi-job C RMW recipes, the recommended policy is:

```text
intermediate partial slots: OUTPUT_MODE = HOST_READBACK
final slot:                OUTPUT_MODE = DMA_STORE
```

This avoids unnecessary external stores for intermediate partial results while keeping C visible in scratchpad for the next accumulating job.

### 7.6 First Implementation Target

The recommended first P16 implementation target is a two-slot C RMW recipe:

```text
slot0:
  INPUT_MODE        = DMA_LOAD
  OUTPUT_MODE       = HOST_READBACK
  ACCUMULATE_ENABLE = 0
  K_part            = first K partition

slot1:
  INPUT_MODE        = DMA_LOAD
  OUTPUT_MODE       = DMA_STORE
  ACCUMULATE_ENABLE = 1
  K_part            = second K partition
```

After that is stable, the same recipe framework should be validated for:

```text
AXIS_PRELOAD two-slot C RMW recipe
DIRECT_STREAM two-slot C RMW recipe
mixed frontend recipes if useful
four-slot recipe smoke
reject / busy / error handling
```

---

## 8. CSR Recipe Register Extension

P16 should add a recipe register window above the existing P15 job CSR map.

Recommended base:

```text
RECIPE CSR base = 0x200
```

The existing P14 registers from `0x000` through `0x08C` remain unchanged.

The existing P15 job registers from `0x100` through `0x18C` remain unchanged.

### 8.1 Recipe Control Register Map

All registers are 32-bit and word-aligned.

| Offset | Name | Access | Description |
|---:|---|---|---|
| 0x200 | `CSR_RECIPE_VERSION` | RO | Recipe sequencer version / feature ID |
| 0x204 | `CSR_RECIPE_COMMAND` | W1P | Recipe start and clear commands |
| 0x208 | `CSR_RECIPE_STATUS` | RO | Live recipe status summary |
| 0x20C | `CSR_RECIPE_DONE_STATUS` | RO/W1C | Sticky recipe done status |
| 0x210 | `CSR_RECIPE_ERROR_STATUS` | RO/W1C | Sticky recipe error status |
| 0x214 | `CSR_RECIPE_CONTROL` | RW | Recipe count, start slot, and policy bits |
| 0x218 | `CSR_RECIPE_REJECT_STATUS` | RO/W1C | Sticky recipe command reject reasons |
| 0x21C | `CSR_RECIPE_STATE` | RO | Current recipe sequencer state |
| 0x220 | `CSR_RECIPE_CURRENT_SLOT` | RO | Current slot index being dispatched or waited on |
| 0x224 | `CSR_RECIPE_COMPLETED_COUNT` | RO | Number of slots completed in current / last recipe |
| 0x228 | `CSR_RECIPE_SLOT_DONE_MASK` | RO/W1C | Per-slot sticky done mask |
| 0x22C | `CSR_RECIPE_SLOT_ERROR_MASK` | RO/W1C | Per-slot sticky error mask |
| 0x230 | `CSR_RECIPE_SLOT_REJECT_MASK` | RO/W1C | Per-slot sticky reject mask |
| 0x234 | `CSR_RECIPE_RESERVED_234` | RO | Reserved |
| 0x280 | `CSR_RECIPE_PERF_BUSY_CYCLES` | RO | Sum of job busy-cycle snapshots across completed slots |
| 0x284 | `CSR_RECIPE_PERF_MAC_COUNT` | RO | Sum of job MAC counts across completed slots |
| 0x288 | `CSR_RECIPE_PERF_OUTPUT_COUNT` | RO | Sum of job output counts across completed slots |
| 0x28C | `CSR_RECIPE_RESERVED_28C` | RO | Reserved |

### 8.2 Descriptor Slot Register Window

Recommended slot base and stride:

```text
CSR_RECIPE_SLOT_BASE   = 0x300
CSR_RECIPE_SLOT_STRIDE = 0x080
P16_RECIPE_QUEUE_DEPTH = 4
```

Slot address ranges:

```text
slot0: 0x300 - 0x37C
slot1: 0x380 - 0x3FC
slot2: 0x400 - 0x47C
slot3: 0x480 - 0x4FC
```

Within each slot, the register layout mirrors the P15 job descriptor layout and adds one slot control word.

| Slot Offset | Name | Access | Description |
|---:|---|---|---|
| 0x00 | `SLOT_CONTROL` | RW | Valid bit, input/output mode, accumulate_enable, policy bits |
| 0x04 | `SLOT_BASE_ADDR_A` | RW | GEMM A logical base address |
| 0x08 | `SLOT_BASE_ADDR_B` | RW | GEMM B logical base address |
| 0x0C | `SLOT_BASE_ADDR_C` | RW | GEMM C scratchpad base address |
| 0x10 | `SLOT_DIM_M` | RW | GEMM M dimension |
| 0x14 | `SLOT_DIM_N` | RW | GEMM N dimension |
| 0x18 | `SLOT_DIM_K` | RW | GEMM K dimension |
| 0x1C | `SLOT_A_SRC_BASE` | RW | External/source-memory A base for preload modes |
| 0x20 | `SLOT_A_DST_BASE` | RW | Scratchpad or operand-buffer A destination/base |
| 0x24 | `SLOT_A_LOAD_BEATS` | RW | A preload length in DATA_WIDTH beats |
| 0x28 | `SLOT_B_SRC_BASE` | RW | External/source-memory B base for preload modes |
| 0x2C | `SLOT_B_DST_BASE` | RW | Scratchpad or operand-buffer B destination/base |
| 0x30 | `SLOT_B_LOAD_BEATS` | RW | B preload length in DATA_WIDTH beats |
| 0x34 | `SLOT_STORE_SRC_BASE` | RW | Scratchpad C source base for DMA store |
| 0x38 | `SLOT_STORE_DST_BASE` | RW | External destination memory base for DMA store |
| 0x3C | `SLOT_STORE_BYTE_COUNT` | RW | DMA store byte count |
| 0x40 | `SLOT_USER_TAG` | RW | Optional software-visible debug tag |
| 0x44 | `SLOT_RESERVED_44` | RO | Reserved |
| 0x48 | `SLOT_RESERVED_48` | RO | Reserved |
| 0x4C | `SLOT_RESERVED_4C` | RO | Reserved |

The remaining bytes in the 0x80-byte slot stride are reserved for future timeout, dependency, or debug fields.

---

## 9. Register Bit Definitions

### 9.1 `CSR_RECIPE_VERSION` at 0x200

| Bits | Name | Access | Reset | Description |
|---:|---|---|---:|---|
| [31:16] | `MAJOR` | RO | 16'h0001 | Recipe sequencer major version |
| [15:8] | `MINOR` | RO | 8'h00 | Recipe sequencer minor version |
| [7:0] | `FEATURE_ID` | RO | 8'h16 | P16 recipe sequencer feature ID |

Recommended reset value:

```text
0x0001_0016
```

### 9.2 `CSR_RECIPE_COMMAND` at 0x204

This is a write-one-pulse register.  Reads return zero.

| Bit | Name | Type | Description |
|---:|---|---|---|
| 0 | `START_RECIPE` | W1P | Latch selected slots and start the recipe if accepted |
| 8 | `CLEAR_RECIPE_DONE` | W1P | Clear sticky recipe done bits and per-slot done mask |
| 9 | `CLEAR_RECIPE_ERROR` | W1P | Clear sticky recipe error/reject bits and per-slot error/reject masks |
| 10 | `CLEAR_RECIPE_PERF` | W1P | Clear recipe performance accumulation registers |
| 11 | `CLEAR_RECIPE_SLOT_STATUS` | W1P | Clear per-slot done/error/reject masks |

Unsupported combinations:

```text
START_RECIPE with CLEAR_RECIPE_ERROR if recipe errors are currently sticky
START_RECIPE while recipe_busy is high
START_RECIPE while job_busy is high
START_RECIPE with queue count zero
START_RECIPE with invalid selected slot range
START_RECIPE with invalid selected slot descriptor
```

Unsupported combinations do not start a recipe and set `CSR_RECIPE_REJECT_STATUS`.

### 9.3 `CSR_RECIPE_STATUS` at 0x208

| Bit | Name | Access | Description |
|---:|---|---|---|
| 0 | `RECIPE_BUSY` | RO | Recipe sequencer is running a recipe |
| 1 | `RECIPE_DONE` | RO | Sticky recipe done is set |
| 2 | `RECIPE_ERROR` | RO | Sticky recipe error or reject is set |
| 3 | `RECIPE_ACCEPT_READY` | RO | Recipe sequencer is idle and can accept START_RECIPE |
| 8 | `JOB_BUSY` | RO | Underlying P15 job worker is busy |
| 9 | `MICRO_OP_BUSY` | RO | Any underlying P14/P15 engine busy is high |
| 16 | `CSR_READY` | RO | CSR block ready for transactions |

### 9.4 `CSR_RECIPE_DONE_STATUS` at 0x20C

| Bit | Name | Type | Description |
|---:|---|---|---|
| 0 | `RECIPE_DONE` | RO/W1C | Complete recipe finished successfully |
| 1 | `ALL_SLOTS_DONE` | RO/W1C | All selected slots completed successfully |
| 2 | `FINAL_STORE_DONE` | RO/W1C | Final selected slot completed DMA store, if enabled |

### 9.5 `CSR_RECIPE_ERROR_STATUS` at 0x210

| Bit | Name | Type | Description |
|---:|---|---|---|
| 0 | `SLOT_JOB_ERROR` | RO/W1C | Selected slot completed with P15 job error |
| 1 | `SLOT_JOB_REJECT` | RO/W1C | Selected slot was rejected by the P15 job worker |
| 2 | `RECIPE_SEQUENCE_ERROR` | RO/W1C | Recipe FSM reached an illegal state or unexpected event |
| 3 | `RECIPE_SLOT_RANGE_ERROR` | RO/W1C | Selected slot range exceeded configured queue depth |
| 4 | `RECIPE_SLOT_DESCRIPTOR_ERROR` | RO/W1C | Selected slot descriptor failed pre-validation |
| 8 | `RECIPE_TIMEOUT_RESERVED` | RO/W1C | Reserved for future hardware timeout support |

On any recipe error, the recipe sequencer must stop dispatching new slots and transition to an error terminal state.

### 9.6 `CSR_RECIPE_CONTROL` at 0x214

| Bits | Name | Access | Reset | Description |
|---:|---|---|---:|---|
| [3:0] | `RECIPE_COUNT` | RW | 0 | Number of descriptor slots to execute |
| [7:4] | `START_SLOT` | RW | 0 | First slot index to execute |
| 8 | `STOP_ON_ERROR` | RW | 1 | Stop recipe when any slot reports error/reject |
| 9 | `CLEAR_JOB_STICKY_EACH_SLOT` | RW | 1 | Clear P15 job sticky status before dispatching each slot |
| 10 | `ACCUMULATE_PERF` | RW | 1 | Accumulate job performance counters into recipe counters |
| 11 | `ALLOW_SLOT_WRITES_WHILE_BUSY` | RW | 1 | Permit CSR writes to live slot registers while active recipe uses snapshot |
| [31:12] | `RSVD` | RO | 0 | Reserved |

Recommended reset value:

```text
0x0000_0700
```

This encodes:

```text
STOP_ON_ERROR = 1
CLEAR_JOB_STICKY_EACH_SLOT = 1
ACCUMULATE_PERF = 1
RECIPE_COUNT = 0
START_SLOT = 0
```

### 9.7 `CSR_RECIPE_REJECT_STATUS` at 0x218

| Bit | Name | Type | Description |
|---:|---|---|---|
| 0 | `RECIPE_BUSY_REJECT` | RO/W1C | START_RECIPE requested while recipe_busy is high |
| 1 | `JOB_BUSY_REJECT` | RO/W1C | START_RECIPE requested while underlying job worker is busy |
| 2 | `MICRO_OP_BUSY_REJECT` | RO/W1C | START_RECIPE requested while an underlying engine is busy |
| 3 | `ZERO_COUNT_REJECT` | RO/W1C | RECIPE_COUNT is zero |
| 4 | `SLOT_RANGE_REJECT` | RO/W1C | START_SLOT + RECIPE_COUNT exceeds queue depth |
| 5 | `SLOT_INVALID_REJECT` | RO/W1C | A selected slot valid bit is zero |
| 6 | `SLOT_DESCRIPTOR_REJECT` | RO/W1C | A selected slot descriptor has invalid dimensions, lengths, or mode |
| 7 | `MANUAL_CMD_DURING_RECIPE_REJECT` | RO/W1C | P14 or P15 manual command attempted while recipe sequencer owns control |
| 8 | `UNSUPPORTED_COMBO` | RO/W1C | Unsupported recipe command-bit combination was written |

### 9.8 `CSR_RECIPE_STATE` at 0x21C

Recommended state encodings:

| Value | Name | Meaning |
|---:|---|---|
| 0 | `IDLE` | No active recipe |
| 1 | `SNAPSHOT` | Latch selected slot descriptors into active snapshot |
| 2 | `VALIDATE` | Validate selected slot descriptors |
| 3 | `DISPATCH_SETUP` | Select current slot descriptor for P15 job worker |
| 4 | `DISPATCH_START` | Pulse internal P15 job start for current slot |
| 5 | `JOB_WAIT` | Wait for current slot P15 job done/error/reject |
| 6 | `SLOT_COMPLETE` | Capture per-slot done/perf status |
| 7 | `ADVANCE` | Move to the next selected slot |
| 8 | `DONE` | Successful terminal state |
| 9 | `ERROR` | Error terminal state |

### 9.9 `SLOT_CONTROL` at slot offset 0x00

| Bits | Name | Access | Reset | Description |
|---:|---|---|---:|---|
| 0 | `VALID` | RW | 0 | Slot descriptor is valid and may be selected by a recipe |
| [2:1] | `INPUT_MODE` | RW | 0 | 0=HOST_PRELOADED, 1=DMA_LOAD, 2=AXIS_PRELOAD, 3=DIRECT_STREAM |
| [4:3] | `OUTPUT_MODE` | RW | 0 | 0=HOST_READBACK, 1=DMA_STORE |
| 5 | `ACCUMULATE_ENABLE` | RW | 0 | GEMM C RMW accumulation control for this slot |
| 6 | `FINAL_SLOT_HINT` | RW | 0 | Optional software hint; not required for sequencing correctness |
| [31:7] | `RSVD` | RO | 0 | Reserved |

---

## 10. Descriptor Slot Defaults

Recommended reset defaults for each slot:

| Register | Reset |
|---|---:|
| `SLOT_CONTROL` | 0x0000_0000 |
| `SLOT_BASE_ADDR_A` | 0x0000_0000 |
| `SLOT_BASE_ADDR_B` | 0x0000_0100 |
| `SLOT_BASE_ADDR_C` | 0x0000_0200 |
| `SLOT_DIM_M` | 0x0000_0004 |
| `SLOT_DIM_N` | 0x0000_0004 |
| `SLOT_DIM_K` | 0x0000_0004 |
| `SLOT_A_SRC_BASE` | 0x0000_0000 |
| `SLOT_A_DST_BASE` | 0x0000_0000 |
| `SLOT_A_LOAD_BEATS` | 0x0000_0000 |
| `SLOT_B_SRC_BASE` | 0x0000_0100 |
| `SLOT_B_DST_BASE` | 0x0000_0100 |
| `SLOT_B_LOAD_BEATS` | 0x0000_0000 |
| `SLOT_STORE_SRC_BASE` | 0x0000_0200 |
| `SLOT_STORE_DST_BASE` | 0x0000_0000 |
| `SLOT_STORE_BYTE_COUNT` | 0x0000_0000 |
| `SLOT_USER_TAG` | 0x0000_0000 |

`SLOT_CONTROL.VALID` resets to 0 so accidental `START_RECIPE` cannot execute a slot unless software explicitly marks that slot valid.

---

## 11. Recipe Sequencer Operation

### 11.1 Accepted START_RECIPE

When `START_RECIPE` is accepted:

```text
1. Clear recipe done/error/reject status for the new recipe.
2. Clear or initialize per-slot done/error/reject masks for the selected run.
3. Clear recipe performance accumulation registers if CLEAR_RECIPE_PERF was also requested earlier.
4. Latch RECIPE_COUNT and START_SLOT.
5. Latch selected descriptor slots into an active recipe snapshot.
6. Set recipe_busy.
7. Set current_slot to START_SLOT.
8. Enter DISPATCH_SETUP.
```

### 11.2 Slot Dispatch

For each selected slot, the recipe sequencer builds a P15 job descriptor bundle from the active slot snapshot:

```text
job_mode.input_mode        = SLOT_CONTROL.INPUT_MODE
job_mode.output_mode       = SLOT_CONTROL.OUTPUT_MODE
job_mode.accumulate_enable = SLOT_CONTROL.ACCUMULATE_ENABLE

job_base_addr_a            = SLOT_BASE_ADDR_A
job_base_addr_b            = SLOT_BASE_ADDR_B
job_base_addr_c            = SLOT_BASE_ADDR_C
job_dim_m                  = SLOT_DIM_M
job_dim_n                  = SLOT_DIM_N
job_dim_k                  = SLOT_DIM_K

job_a_src_base             = SLOT_A_SRC_BASE
job_a_dst_base             = SLOT_A_DST_BASE
job_a_load_beats           = SLOT_A_LOAD_BEATS

job_b_src_base             = SLOT_B_SRC_BASE
job_b_dst_base             = SLOT_B_DST_BASE
job_b_load_beats           = SLOT_B_LOAD_BEATS

job_store_src_base         = SLOT_STORE_SRC_BASE
job_store_dst_base         = SLOT_STORE_DST_BASE
job_store_byte_count       = SLOT_STORE_BYTE_COUNT
```

The recipe sequencer then pulses an internal job start request to the P15 job worker and waits for one of:

```text
job done
job error
job reject
reset
```

### 11.3 Slot Completion

When a slot completes successfully:

```text
1. Set the corresponding bit in CSR_RECIPE_SLOT_DONE_MASK.
2. Increment CSR_RECIPE_COMPLETED_COUNT.
3. Add the P15 job performance snapshot to recipe performance totals if ACCUMULATE_PERF=1.
4. Advance to the next selected slot if any remain.
5. If no slots remain, set RECIPE_DONE and enter DONE.
```

### 11.4 Slot Error / Reject

When a slot reports job error or job reject:

```text
1. Set CSR_RECIPE_ERROR_STATUS.SLOT_JOB_ERROR or SLOT_JOB_REJECT.
2. Set the corresponding bit in CSR_RECIPE_SLOT_ERROR_MASK or CSR_RECIPE_SLOT_REJECT_MASK.
3. Clear recipe_busy.
4. Enter ERROR if STOP_ON_ERROR=1.
```

For P16A/P16B, `STOP_ON_ERROR=1` is the only required behavior.  Continuing after a failed slot can be reserved for a later milestone.

### 11.5 Recipe Completion Semantics

`RECIPE_DONE` means:

```text
All selected descriptor slots completed successfully in order.
Each selected slot reached the P15 JOB_DONE condition for its selected output mode.
If the final selected slot used OUTPUT_MODE=DMA_STORE, the final DMA destination memory has received the complete C payload.
If the final selected slot used OUTPUT_MODE=HOST_READBACK, final C is visible in scratchpad after GEMM done.
```

The recipe sequencer must not assert `RECIPE_DONE` before the final selected slot completes.

---

## 12. Interaction With P14 and P15 Control Models

P16 must preserve P14 and P15 debug usability when idle.

Policy:

```text
When recipe_busy == 0 and job_busy == 0:
  P14 START_DMA_LOAD / START_AXIS_LOAD / START_DS_LOAD / START_GEMM / START_DMA_STORE commands are allowed.
  P15 START_JOB is allowed.
  P16 START_RECIPE is allowed.

When job_busy == 1:
  P16 START_RECIPE is rejected.
  P14 manual START_* commands are rejected by the existing P15 policy.

When recipe_busy == 1:
  P14 manual START_* commands are rejected.
  P15 START_JOB is rejected.
  A second P16 START_RECIPE is rejected.
```

This avoids multiple control sources driving the same underlying engines while a recipe is active.

The P16 recipe sequencer should use raw P15 job done/error/reject events or dedicated internal worker status, not stale CSR sticky bits, as the condition for advancing from one slot to the next.

P15 job CSR status may still expose the last dispatched slot for debug.

---

## 13. Acceptance Rules

### 13.1 Common START_RECIPE Acceptance

`START_RECIPE` is accepted only when:

```text
recipe_busy == 0
job_busy == 0
acc_busy == 0
dma_load_busy == 0
axis_load_busy == 0
ds_load_busy == 0
dma_store_busy == 0
RECIPE_COUNT != 0
START_SLOT + RECIPE_COUNT <= P16_RECIPE_QUEUE_DEPTH
all selected slots have SLOT_CONTROL.VALID == 1
all selected slots pass descriptor validation
```

### 13.2 Slot Descriptor Validation

A selected slot is valid only when:

```text
SLOT_DIM_M != 0
SLOT_DIM_N != 0
SLOT_DIM_K != 0
input/output mode combination is supported
```

For `HOST_PRELOADED` input mode:

```text
SLOT_A_LOAD_BEATS may be zero
SLOT_B_LOAD_BEATS may be zero
```

For `DMA_LOAD`, `AXIS_PRELOAD`, and `DIRECT_STREAM` input modes:

```text
SLOT_A_LOAD_BEATS != 0
SLOT_B_LOAD_BEATS != 0
```

For `HOST_READBACK` output mode:

```text
SLOT_STORE_BYTE_COUNT may be zero
```

For `DMA_STORE` output mode:

```text
SLOT_STORE_BYTE_COUNT != 0
```

### 13.3 Initial Recipe Composition Rules

P16A recommends simple in-order recipes only:

```text
No slot dependencies beyond sequential order.
No branch or conditional execution.
No slot skip at runtime.
No wraparound slot ranges.
No descriptor fetch from memory.
```

A later milestone may extend the slot format with dependency or branch fields.

---

## 14. Error Policy

If an error is observed during a selected slot:

```text
1. Capture the current slot index.
2. Set the corresponding per-slot error or reject mask bit.
3. Set the corresponding recipe error status bit.
4. Stop dispatching downstream slots.
5. Clear recipe_busy.
6. Enter ERROR terminal state.
7. Keep RECIPE_DONE deasserted.
```

Recommended mappings:

| Source | Recipe error bit |
|---|---|
| P15 job error from current slot | `SLOT_JOB_ERROR` |
| P15 job reject from current slot | `SLOT_JOB_REJECT` |
| Invalid selected slot range | `RECIPE_SLOT_RANGE_ERROR` |
| Invalid selected descriptor | `RECIPE_SLOT_DESCRIPTOR_ERROR` |
| Illegal recipe FSM state | `RECIPE_SEQUENCE_ERROR` |

The current P16 scope does not require hardware timeout counters.  Timeouts should remain in UVM for P16A/P16B.

---

## 15. Performance Counter Policy

P16 recipe performance registers accumulate the P15 job performance snapshots across successfully completed slots.

For a recipe with N completed slots:

```text
CSR_RECIPE_PERF_BUSY_CYCLES  = sum(slot_i.job_perf_busy_cycles)
CSR_RECIPE_PERF_MAC_COUNT    = sum(slot_i.job_perf_mac_count)
CSR_RECIPE_PERF_OUTPUT_COUNT = sum(slot_i.job_perf_output_count)
```

For two-job partial-K accumulation recipes:

```text
slot0 JOB_PERF_MAC_COUNT = M * N * K_part0
slot1 JOB_PERF_MAC_COUNT = M * N * K_part1
recipe MAC total         = M * N * (K_part0 + K_part1)
```

For output count, the recipe total is the sum of per-slot GEMM outputs:

```text
recipe OUTPUT total = sum(M_i * N_i across completed slots)
```

This is a slot-work counter, not a unique-final-output counter.  A future software driver can derive unique final output count from descriptor semantics if needed.

---

## 16. Programming Sequences

### 16.1 Two-Slot DMA C RMW Recipe

```text
1. Program slot0:
     VALID             = 1
     INPUT_MODE        = DMA_LOAD
     OUTPUT_MODE       = HOST_READBACK
     ACCUMULATE_ENABLE = 0
     base/dim fields for first K partition
     A/B DMA source/destination/length fields

2. Program slot1:
     VALID             = 1
     INPUT_MODE        = DMA_LOAD
     OUTPUT_MODE       = DMA_STORE
     ACCUMULATE_ENABLE = 1
     base/dim fields for second K partition
     A/B DMA source/destination/length fields
     store source/destination/byte_count fields

3. Program CSR_RECIPE_CONTROL:
     START_SLOT   = 0
     RECIPE_COUNT = 2
     STOP_ON_ERROR = 1

4. Write CSR_RECIPE_COMMAND.START_RECIPE = 1.

5. Sequencer dispatches slot0 through P15 job worker.
6. Sequencer waits for slot0 JOB_DONE.
7. Sequencer dispatches slot1 through P15 job worker.
8. Sequencer waits for slot1 JOB_DONE.
9. Sequencer sets RECIPE_DONE.
10. Test checks DMA destination memory against software reference.
```

### 16.2 Two-Slot AXI-Stream C RMW Recipe

Same as the DMA recipe, except each slot uses:

```text
INPUT_MODE = AXIS_PRELOAD
SLOT_A_SRC_BASE / SLOT_A_DST_BASE / SLOT_A_LOAD_BEATS
SLOT_B_SRC_BASE / SLOT_B_DST_BASE / SLOT_B_LOAD_BEATS
```

The final slot normally uses `OUTPUT_MODE=DMA_STORE`.

### 16.3 Two-Slot Direct Stream C RMW Recipe

Same as the DMA recipe, except each slot uses:

```text
INPUT_MODE = DIRECT_STREAM
SLOT_A_SRC_BASE / SLOT_A_DST_BASE / SLOT_A_LOAD_BEATS
SLOT_B_SRC_BASE / SLOT_B_DST_BASE / SLOT_B_LOAD_BEATS
```

The P15 job worker derives `GEMM_INPUT_STREAM_MODE=1` for Direct Stream slots.

The final slot normally uses `OUTPUT_MODE=DMA_STORE`.

### 16.4 Four-Slot Smoke Recipe

A later P16 smoke can validate descriptor slot traversal with four slots:

```text
slot0 -> slot1 -> slot2 -> slot3 -> RECIPE_DONE
```

This does not need to be a performance-optimized workload.  It is mainly a queue-depth, current-slot, and per-slot mask validation test.

---

## 17. Verification Plan For P16

### 17.1 Recipe CSR Register Tests

P16B/P16C should include:

```text
recipe register reset default test
recipe RW register write/readback test
recipe byte-strobe test
recipe command read returns zero test
recipe done W1C clear test
recipe error W1C clear test
recipe reject W1C clear test
slot register write/readback test
slot valid bit behavior test
slot range reject test
zero recipe count reject test
invalid selected slot reject test
START_RECIPE while recipe_busy reject test
START_JOB while recipe_busy reject test
P14 manual command while recipe_busy reject test
```

### 17.2 Recipe Sequencer Tests

A lightweight sequencer-focused testbench can mock P15 job worker done/error/reject inputs and verify:

```text
reset default state
START_RECIPE acceptance
selected slot snapshot policy
slot0 -> slot1 dispatch order
current_slot update
completed_count update
per-slot done mask update
recipe performance accumulation
job error stops downstream slots
job reject stops downstream slots
recipe done only after final selected slot
live CSR slot rewrites do not affect active recipe
```

### 17.3 End-to-End Recipe Tests

Recommended initial P16D end-to-end tests:

```text
csr_recipe_dma_c_rmw_case208
csr_recipe_dma_c_rmw_case211
```

Recommended P16E frontend extension tests:

```text
csr_recipe_axis_stream_c_rmw_case208
csr_recipe_axis_stream_c_rmw_case211
csr_recipe_direct_stream_c_rmw_case208
csr_recipe_direct_stream_c_rmw_case211
```

Recommended P16F robustness tests:

```text
csr_recipe_reject_zero_count
csr_recipe_reject_invalid_slot
csr_recipe_reject_busy
csr_recipe_job_error_stop
csr_recipe_manual_cmd_during_busy_reject
```

### 17.4 Acceptance Criteria

P16 closure should require:

```text
P16A spec reviewed and accepted
Recipe CSR registers compile
Recipe sequencer RTL compiles
Recipe-level two-slot DMA C RMW tests PASS
Recipe-level AXI-Stream and Direct Stream C RMW tests PASS when added
Recipe reject / busy / error tests PASS
Existing P14 micro-operation tests still PASS
Existing P15 single-job tests still PASS
Legacy sideband full regression still PASS
New full regression total increases only by targeted P16 representative items
No BRAM RTL changes
No GEMM datapath behavioral changes required for P16A/P16B/P16C
```

---

## 18. P16 Milestone Breakdown

Recommended P16 split:

```text
P16A: Multi-job descriptor queue / recipe sequencer spec        PASS
P16B: Recipe CSR register extension and slot register tests     Future
P16C: Recipe sequencer dispatch into P15 job worker             Future
P16D: Two-slot DMA C RMW recipe validation                      Future
P16E: AXI-Stream and Direct Stream recipe validation            Future
P16F: Recipe reject / busy / error handling                     Future
P16G: Full regression and documentation closure                 Future
```

---

## 19. Open Decisions Before P16B

These should be confirmed before writing RTL:

```text
1. Queue depth: 2 slots or 4 slots?
   Recommended: reserve 4 slots in the CSR map, validate 2 slots first.

2. Should slot registers be writable while recipe_busy is high?
   Recommended: yes, because active recipe uses a START_RECIPE snapshot.

3. Should intermediate C RMW slots use HOST_READBACK output mode or DMA_STORE?
   Recommended: HOST_READBACK for intermediate slots, DMA_STORE for the final slot.

4. Should P16 support slot range wrapping?
   Recommended: no for P16B/P16C.

5. Should P16 support mixed frontend recipes?
   Recommended: allow by descriptor encoding, but validate homogeneous frontend recipes first.

6. Should P16 add hardware timeout counters?
   Recommended: no for P16C; keep timeouts in UVM first.

7. Should recipe performance output_count represent per-slot outputs or unique final outputs?
   Recommended: per-slot outputs, because it is accumulated directly from P15 job snapshots.

8. Should P15 job sticky status be cleared automatically before each slot?
   Recommended: yes as an internal policy, but the recipe FSM should use raw job worker events rather than relying on sticky bits.

9. Should P16 expose per-slot detailed error codes?
   Recommended: keep masks first; detailed per-slot debug registers can be added later if needed.

10. Should P16 implement memory-resident descriptors after CSR slots?
    Recommended: future milestone after CSR-resident recipe sequencing is stable.
```

---

## 20. Risks and Mitigations

### Risk 1: Descriptor Reprogramming Race

Potential failure:

```text
Software rewrites slot registers while a recipe is active and changes a later slot in the running recipe.
```

Mitigation:

```text
Latch active slot snapshots on accepted START_RECIPE.
Use the snapshots for all selected slots.
```

### Risk 2: Control Ownership Conflict

Potential failure:

```text
Software issues START_JOB or a P14 START_* command while the recipe sequencer is dispatching slots.
```

Mitigation:

```text
Reject P14 manual commands and P15 START_JOB while recipe_busy is high.
Set MANUAL_CMD_DURING_RECIPE_REJECT.
```

### Risk 3: Recipe Advances On Stale Job Done

Potential failure:

```text
Recipe controller sees a stale P15 sticky JOB_DONE from the previous slot and advances before the current slot finishes.
```

Mitigation:

```text
Use raw P15 job done/error/reject events or a dedicated internal job worker status handshake.
Clear P15 sticky job status before each slot as a debug visibility policy, not as the primary control condition.
```

### Risk 4: Intermediate Slot Stores Too Early Or Too Often

Potential failure:

```text
Intermediate partial-K slots store partial C externally even when the recipe only needs final C.
```

Mitigation:

```text
Use OUTPUT_MODE=HOST_READBACK for intermediate C RMW slots.
Use OUTPUT_MODE=DMA_STORE only on the final slot.
```

### Risk 5: Wrong Accumulate Enable Per Slot

Potential failure:

```text
slot0 and slot1 both run with the same accumulate_enable setting.
```

Mitigation:

```text
Store ACCUMULATE_ENABLE in each slot's SLOT_CONTROL.
Build the P15 job descriptor from the active slot snapshot for every dispatch.
Run two-slot C RMW recipes with known references.
```

### Risk 6: Wrong Frontend Mode Per Slot

Potential failure:

```text
A Direct Stream slot is dispatched as scratchpad mode or with wrong operand routing.
```

Mitigation:

```text
Reuse P15 input-mode derivation.
For DIRECT_STREAM slots, P15 job worker forces GEMM_INPUT_STREAM_MODE=1.
Run Direct Stream recipe tests with non-identical A/B payloads.
```

### Risk 7: Recipe Error Starts Downstream Slot

Potential failure:

```text
slot0 reports job error, but the recipe sequencer still dispatches slot1.
```

Mitigation:

```text
Every JOB_WAIT state must branch to ERROR before ADVANCE on any job error/reject event.
Run injected job-error and job-reject tests.
```

### Risk 8: Regression Runtime Growth

Potential failure:

```text
Recipe-level tests duplicate all P13/P14/P15 coverage and make full regression too slow.
```

Mitigation:

```text
Add only representative CASE_ID=208 and CASE_ID=211 for selected recipe paths.
Keep broader P13/P14/P15 coverage unchanged.
```

---

## 21. Summary

P16 adds a small CSR-resident multi-job recipe sequencer on top of the completed P15 single-job sequencer.

The design converts this software-visible sequence:

```text
program job0 descriptor
START_JOB
poll JOB_DONE

program job1 descriptor
START_JOB
poll JOB_DONE
```

into this software-visible recipe sequence:

```text
program slot0 descriptor
program slot1 descriptor
START_RECIPE
poll RECIPE_DONE / RECIPE_ERROR
```

The first implementation should remain conservative:

```text
CSR-resident descriptor slots
small fixed queue depth
in-order slot execution
single outstanding recipe
no memory descriptor fetch
no overlap pipeline
no BRAM changes
no GEMM datapath behavioral changes
P14 and P15 controls preserved when recipe sequencer is idle
```

This gives the project a realistic multi-job accelerator control model and naturally connects the P13 C RMW partial-K recipe with the P15 job-level sequencer foundation.
