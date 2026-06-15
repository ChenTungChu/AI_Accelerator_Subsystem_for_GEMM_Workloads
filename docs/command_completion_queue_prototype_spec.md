# P19 Command / Completion Queue Prototype Spec

## 1. Purpose

This document defines the P19A command / completion queue prototype for the AI Accelerator Subsystem.

P17 completed the memory-resident command ingress path for one descriptor table:

```text
external descriptor memory
    -> P17 descriptor fetch engine
    -> fetched P16-compatible recipe snapshot
    -> existing P16 recipe sequencer
    -> existing P15 job sequencer
    -> existing datapath
```

P18 completed the matching memory-resident completion egress path for one accepted descriptor-fetch context:

```text
recipe terminal status / fetch terminal status
    -> P18 completion record builder
    -> completion writeback engine
    -> external host-visible completion memory
```

P19 raises the software-visible control model from a single descriptor-fetch command into a small host-visible command / completion queue prototype:

```text
host command queue in memory
    -> P19 queue controller fetches the next command entry
    -> P19 maps the command entry into an internal P17 descriptor-fetch launch
    -> P17 fetches recipe descriptors and launches the existing P16/P15 execution stack
    -> P18 writes one completion record into the host completion queue
    -> P19 advances queue pointers and reports queue-level status
```

The goal is to make the subsystem look more like a realistic host-programmable accelerator while keeping the implementation small, deterministic, and explainable.

Current baseline entering P19A:

```text
P18H / P18I completion-writeback closure:
  TOTAL : 110
  PASS  : 110
  FAIL  : 0
```

Current closure after P25F:

```text
P25 runtime stress / robustness closure:
  TOTAL : 135
  PASS  : 135
  FAIL  : 0
```

---

## 2. Baseline Before P19

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
P17 memory-resident descriptor fetch into a P16-compatible recipe snapshot
P18 memory-resident completion writeback after terminal status
Full UVM regression passing 110/110 after P18H closure
```

P19 must preserve the existing control hierarchy:

```text
P14 CSR micro-operation path      -> debug / compatibility
P15 single-job sequencer          -> one descriptor worker
P16 CSR-resident recipe sequencer -> multi-slot recipe dispatcher
P17 descriptor fetch prototype    -> memory-backed recipe descriptor loader
P18 completion writeback          -> memory-backed completion record writer
P19 queue controller              -> small host command / completion queue wrapper around P17/P18
```

P19 must not require changes to:

```text
axi_mm_dual_port_bram
GEMM datapath behavior
DMA load/store datapath protocol
AXI-Stream preload datapath protocol
Direct Stream preload datapath protocol
existing P14 CSR micro-operation programming model
existing P15 START_JOB programming model
existing P16 START_RECIPE programming model
existing P17 descriptor format
existing P18 completion record format
```

---

## 3. P19 Design Intent

P19 converts the P17/P18 single-command memory model into a small ring-buffer queue model.

P17/P18 control model:

```text
Host writes one descriptor table.
Host writes DESC_BASE_ADDR / DESC_COUNT / DESC_STRIDE through CSR.
Host writes COMP_BASE_ADDR through CSR.
Host writes START_FETCH_RECIPE.
Hardware runs one recipe and writes one completion record.
```

P19 control model:

```text
Host writes one or more command entries into command queue memory.
Host updates SQ_TAIL through CSR.
Host kicks the queue controller.
Hardware fetches command entries one at a time.
For each command entry:
  hardware launches the existing P17 descriptor-fetch path
  hardware directs P18 to write one completion record into completion queue memory
  hardware advances SQ_HEAD and CQ_TAIL
Host polls completion queue memory or queue CSR status.
```

The key design goal is to add a realistic host queue abstraction without adding multiple outstanding commands or a full driver-visible interrupt model.

P19 is not intended to improve GEMM datapath performance directly.  It improves the software-visible command submission and completion observation model.

---

## 4. P19A Scope

### 4.1 Included

P19A defines:

```text
command queue design intent
completion queue design intent
queue pointer model
command entry format
queue CSR register window proposal
queue controller behavior
mapping from command queue entry to existing P17 descriptor fetch
mapping from queue completion slot to existing P18 completion writeback
queue-level error / reject / stall policy
UVM validation plan
full-regression closure plan
```

### 4.2 Not Included

P19A does not include:

```text
RTL implementation
CSR RTL changes
UVM tests
multiple commands outstanding
out-of-order completion
interrupt output
MSI/MSI-X style interrupt model
cache-coherent host interface
Linux driver
C software driver
UVM RAL model
command cancellation / preemption
command timeout abort with partial rollback
scheduler priority
doorbell batching optimization
command descriptor cache
AXI interconnect / NoC integration
DMA / GEMM / frontend datapath changes
```

These can remain future work.  P19 should stay a small queue prototype layered above the already validated P17/P18 path.

---

## 5. Fixed P19A Design Decisions

```text
Submission queue location       : external host-visible command memory
Completion queue location       : external host-visible completion memory
Submission queue entry size     : 64 bytes, 16 logical 32-bit words
Completion queue entry size     : 64 bytes, existing P18 completion record format
Queue entry visibility policy   : host writes command commit word last
Completion visibility policy    : P18 writes completion commit word last
Outstanding command count       : one active command at a time
Command execution order         : in-order SQ_HEAD -> SQ_TAIL
Completion order                : in-order CQ_TAIL matches command execution order
Queue pointer model             : monotonic head/tail counters with physical index = counter % depth
P17 descriptor format           : reused unchanged
P18 completion record format    : reused unchanged
BRAM / GEMM / DMA / frontend    : unchanged
Interrupt output                : not included in P19A
```

P19A intentionally avoids overlapping queue fetch, descriptor fetch, GEMM execution, and completion writeback.  The first queue controller is correctness-first and runs one command to terminal completion before accepting the next command.

---

## 6. Relationship to Existing Milestones

### 6.1 P19 Wraps P17/P18 Instead of Replacing Them

Recommended partition:

```text
ai_accel_subsys_csr_top
    AXI-Lite CSR slave port
        -> ai_accel_csr_regs
            -> P14 micro-operation CSRs
            -> P15 job descriptor CSRs
            -> P16 recipe CSRs
            -> P17 descriptor-fetch CSRs
            -> P18 completion-writeback CSRs
            -> P19 queue CSRs

    P19 command / completion queue controller
        -> command-memory AXI read master
        -> internal P17 launch context
            -> P17 descriptor fetch engine
                -> fetched P16-compatible recipe snapshot
                -> P16 recipe sequencer
                    -> P15 job sequencer
                        -> ai_accel_subsys datapath
        -> internal P18 completion context
            -> P18 completion writeback engine
                -> completion-memory AXI write master
```

The P19 controller should not duplicate descriptor validation, recipe dispatch, job sequencing, DMA load/store sequencing, or completion record construction.

P19's job is only:

```text
fetch a command queue entry
validate queue-level fields
translate the command into one P17 descriptor-fetch context
allocate one P18 completion queue slot
wait for terminal completion
advance queue pointers
```

### 6.2 Manual Debug Paths Remain Available

P19 does not remove the existing manual debug paths:

```text
P14 manual micro-operation commands
P15 START_JOB
P16 START_RECIPE
P17 START_FETCH_RECIPE
P18 manual completion writeback debug path, if retained by RTL
```

Recommended policy:

```text
When P19 queue_busy is high, P14/P15/P16/P17 manual starts are rejected.
When P14/P15/P16/P17/P18 engines are busy, P19 START_QUEUE is rejected or stalls before command acceptance.
```

This keeps ownership simple and prevents the queue controller from racing manual CSR launches.

---

## 7. Queue Model

### 7.1 Queue Names

P19 uses two host-visible queues:

```text
SQ: submission queue / command queue
CQ: completion queue
```

SQ contains fixed-size command entries.  CQ contains fixed-size P18 completion records.

### 7.2 Single Outstanding Queue Controller

P19 supports one command in execution at a time.

A command starts when:

```text
queue controller is enabled
SQ is non-empty
CQ has at least one free entry
no underlying P17/P18/P16/P15/P14 engine is busy
command entry fetch and validation succeeds
```

A command ends when:

```text
P18 completion writeback commits successfully
or completion writeback reports an error
or a queue-level fetch / validation error reaches terminal status
```

Only after terminal status does P19 consider the next SQ entry.

### 7.3 Monotonic Head / Tail Counters

P19 uses monotonic counters instead of raw wrapped pointers.

Recommended model:

```text
SQ_HEAD : hardware-owned consumed-command counter
SQ_TAIL : host-owned produced-command counter
CQ_HEAD : host-owned consumed-completion counter
CQ_TAIL : hardware-owned produced-completion counter
```

Physical index calculation:

```text
sq_index = SQ_HEAD % SQ_DEPTH
cq_index = CQ_TAIL % CQ_DEPTH
```

Occupancy calculation:

```text
sq_occupancy = SQ_TAIL - SQ_HEAD
cq_occupancy = CQ_TAIL - CQ_HEAD
cq_space     = CQ_DEPTH - cq_occupancy
```

Prototype counter width:

```text
16-bit monotonic counters are sufficient for P19A validation.
```

Software must not let monotonic counters wrap ambiguously during one test run.

### 7.4 Empty / Full Policy

SQ empty:

```text
SQ_HEAD == SQ_TAIL
```

CQ full:

```text
(CQ_TAIL - CQ_HEAD) >= CQ_DEPTH
```

Recommended behavior:

```text
SQ empty while queue enabled      -> idle / wait, not an error
CQ full before command acceptance -> stall, not an error
START_QUEUE while queue_busy      -> reject
invalid queue config             -> reject
```

P19A should not fetch an SQ command unless a CQ entry is available for its completion.

---

## 8. Command Queue Entry Format

P19A uses one fixed 64-byte command queue entry.

```text
Command entry size = 0x40 bytes
Logical word size  = 32 bits
Words per entry    = 16
```

The host should write payload words first and write `CMD_CONTROL.VALID=1` last.  Hardware must fetch word0 and verify `VALID=1` before accepting the command entry.

### 8.1 Entry Layout

| Byte Offset | Word Index | Name | Description |
|---:|---:|---|---|
| 0x00 | 0  | `CMD_CONTROL` | Command valid / opcode / policy bits. Written last by host. |
| 0x04 | 1  | `CMD_USER_TAG` | Host-visible command tag for debug / correlation. |
| 0x08 | 2  | `CMD_DESC_BASE_ADDR` | Base address of the P17 descriptor table. |
| 0x0C | 3  | `CMD_DESC_COUNT` | Number of descriptors to fetch. |
| 0x10 | 4  | `CMD_DESC_STRIDE` | Byte stride between descriptors. |
| 0x14 | 5  | `CMD_COMPLETION_FLAGS` | Completion policy / reserved debug flags. |
| 0x18 | 6  | `CMD_TIMEOUT_CYCLES` | P24 per-command watchdog budget in dma_clk cycles. Zero disables timeout for this command. |
| 0x1C | 7  | `CMD_RESERVED_07` | Reserved. |
| 0x20 | 8  | `CMD_RESERVED_08` | Reserved. |
| 0x24 | 9  | `CMD_RESERVED_09` | Reserved. |
| 0x28 | 10 | `CMD_RESERVED_10` | Reserved. |
| 0x2C | 11 | `CMD_RESERVED_11` | Reserved. |
| 0x30 | 12 | `CMD_RESERVED_12` | Reserved. |
| 0x34 | 13 | `CMD_RESERVED_13` | Reserved. |
| 0x38 | 14 | `CMD_RESERVED_14` | Reserved. |
| 0x3C | 15 | `CMD_RESERVED_15` | Reserved. |

### 8.2 `CMD_CONTROL` Bit Definitions

| Bits | Name | Reset | Description |
|---:|---|---:|---|
| 0 | `VALID` | 0 | Command entry is valid and may be consumed. |
| [7:1] | `OPCODE` | 0 | `0x01` = fetch descriptor table and run recipe. Other values reserved. |
| 8 | `ENABLE_COMPLETION` | 1 | Request P18 completion writeback into CQ. Must be 1 in P19A. |
| 9 | `STOP_AFTER_THIS` | 0 | Optional hint to stop queue after this command. |
| 10 | `RSVD` | 0 | Reserved. |
| 11 | `RSVD` | 0 | Reserved. |
| [31:12] | `RSVD` | 0 | Reserved. |

Recommended valid P19A command control value:

```text
VALID=1, OPCODE=0x01, ENABLE_COMPLETION=1
```

### 8.3 Command Validation

A command entry is valid when:

```text
CMD_CONTROL.VALID == 1
CMD_CONTROL.OPCODE == FETCH_RECIPE
CMD_CONTROL.ENABLE_COMPLETION == 1
CMD_DESC_BASE_ADDR is DATA_WIDTH-byte aligned
CMD_DESC_COUNT is non-zero and <= P19_MAX_DESC_COUNT
CMD_DESC_STRIDE is non-zero and DATA_WIDTH-byte aligned
reserved control bits are zero
CQ has free space before command acceptance
underlying P17/P18/P16/P15 engines are idle before command acceptance
```

Invalid command entries become queue-level command rejects.  If the command entry was fetched from SQ and CQ space is available, P19 should write a reject completion record into CQ using the P18 completion writeback path where practical.  If completion writeback cannot be attempted, CSR queue error status is authoritative.

### 8.4 P24B `CMD_TIMEOUT_CYCLES` Semantics

P24B freezes word6 as a per-command watchdog budget.

```text
CMD_TIMEOUT_CYCLES == 0
  timeout disabled; legacy P19/P20/P21/P22/P23 behavior is preserved

CMD_TIMEOUT_CYCLES != 0
  value is snapshotted when the SQ command is accepted
  watchdog counts dma_clk cycles while the accepted command owns the queue active context
  if terminal queue status arrives first, watchdog is cleared normally
  if watchdog expires first, the queue reports COMMAND_TIMEOUT_ERROR
```

The timeout budget is part of the active command snapshot.  Host writes to the SQ entry after command acceptance must not modify the active timeout budget.

CQ-full before command acceptance does not start the command watchdog.  Command fetch errors before command contents are known use the existing command-fetch error policy, not the timeout policy.

---

## 9. Completion Queue Entry Format

P19A reuses the existing P18 64-byte completion record format unchanged.

```text
Completion queue entry size = 0x40 bytes
Logical word size           = 32 bits
Words per entry             = 16
Commit policy               = existing P18 word0 VALID commit policy
```

Physical CQ address:

```text
completion_base = CQ_BASE_ADDR + ((CQ_TAIL % CQ_DEPTH) * CQ_STRIDE)
```

Recommended P19A CQ stride:

```text
CQ_STRIDE = 0x40
```

The P18 completion writeback engine owns the final memory visibility contract:

```text
write payload words first
write commit word last with VALID=1
set completion done sticky after final commit BRESP succeeds
```

P19 increments `CQ_TAIL` only after the completion record has committed successfully.

If P18 completion writeback fails before commit, P19 must not advance `CQ_TAIL`.  Software should use CSR queue error and P18 completion error status to diagnose the failed completion.

---

## 10. Queue CSR Window Proposal

P18 uses the `0x540 - 0x57C` completion-writeback CSR window.  P19 should add a queue CSR window immediately after P18.

Recommended base:

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
```

### 10.1 Register Map

| Offset | Name | Access | Reset | Description |
|---:|---|---|---:|---|
| 0x580 | `CSR_QUEUE_VERSION` | RO | `0x0001_0019` | Queue controller version / feature ID. |
| 0x584 | `CSR_QUEUE_COMMAND` | W1P | 0 | Queue start/kick and sticky clear commands. |
| 0x588 | `CSR_QUEUE_STATUS` | RO | implementation | Live queue status summary. |
| 0x58C | `CSR_QUEUE_DONE_STATUS` | RO/W1C | 0 | Sticky queue done / idle status. |
| 0x590 | `CSR_QUEUE_ERROR_STATUS` | RO/W1C | 0 | Sticky queue error status. |
| 0x594 | `CSR_QUEUE_CONTROL` | RW | `0x0000_0001` | Queue policy bits. |
| 0x598 | `CSR_QUEUE_REJECT_STATUS` | RO/W1C | 0 | Sticky queue command/config reject reasons. |
| 0x59C | `CSR_QUEUE_STATE` | RO | 0 | Current queue controller FSM state. |
| 0x5A0 | `CSR_SQ_BASE_ADDR` | RW | 0 | Submission queue base address. |
| 0x5A4 | `CSR_SQ_DEPTH` | RW | 0 | Submission queue depth in entries. |
| 0x5A8 | `CSR_SQ_HEAD` | RO | 0 | Hardware-owned SQ head counter. |
| 0x5AC | `CSR_SQ_TAIL` | RW | 0 | Host-owned SQ tail counter. |
| 0x5B0 | `CSR_SQ_STRIDE` | RW | `0x40` | Submission queue entry stride in bytes. |
| 0x5B4 | `CSR_CQ_BASE_ADDR` | RW | 0 | Completion queue base address. |
| 0x5B8 | `CSR_CQ_DEPTH` | RW | 0 | Completion queue depth in entries. |
| 0x5BC | `CSR_CQ_HEAD` | RW | 0 | Host-owned CQ head counter. |
| 0x5C0 | `CSR_CQ_TAIL` | RO | 0 | Hardware-owned CQ tail counter. |
| 0x5C4 | `CSR_CQ_STRIDE` | RW | `0x40` | Completion queue entry stride in bytes. |
| 0x5C8 | `CSR_QUEUE_CURRENT_INDEX` | RO | 0 | Current SQ physical index being fetched or executed. |
| 0x5CC | `CSR_QUEUE_COMPLETED_COUNT` | RO | 0 | Number of commands completed through CQ commit. |
| 0x5D0 | `CSR_QUEUE_ERROR_INDEX` | RO | 0 | SQ index associated with the last queue error. |
| 0x5D4 | `CSR_QUEUE_ERROR_DETAIL` | RO | 0 | Queue-level error detail. |
| 0x5D8 | `CSR_QUEUE_LAST_CMD_TAG` | RO | 0 | Last accepted command user tag. |
| 0x5DC | `CSR_QUEUE_LAST_CMD_CONTROL` | RO | 0 | Last accepted command control word. |
| 0x5E0 | `CSR_QUEUE_SQ_OCCUPANCY` | RO | 0 | Computed SQ occupancy. |
| 0x5E4 | `CSR_QUEUE_CQ_OCCUPANCY` | RO | 0 | Computed CQ occupancy. |
| 0x5E8 | `CSR_QUEUE_CQ_SPACE` | RO | 0 | Computed CQ free entries. |
| 0x5EC | `CSR_QUEUE_RESERVED_5EC` | RO | 0 | Reserved. |
| 0x5F0 | `CSR_QUEUE_RESERVED_5F0` | RO | 0 | Reserved. |
| 0x5F4 | `CSR_QUEUE_RESERVED_5F4` | RO | 0 | Reserved. |
| 0x5F8 | `CSR_QUEUE_RESERVED_5F8` | RO | 0 | Reserved. |
| 0x5FC | `CSR_QUEUE_RESERVED_5FC` | RO | 0 | Reserved. |

---

## 11. Queue Register Bit Definitions

### 11.1 `CSR_QUEUE_VERSION` at 0x580

| Bits | Name | Access | Reset | Description |
|---:|---|---|---:|---|
| [31:16] | `MAJOR` | RO | 16'h0001 | Queue controller major version. |
| [15:8] | `MINOR` | RO | 8'h00 | Queue controller minor version. |
| [7:0] | `FEATURE_ID` | RO | 8'h19 | P19 queue controller feature ID. |

Recommended reset value:

```text
0x0001_0019
```

### 11.2 `CSR_QUEUE_COMMAND` at 0x584

This is a write-one-pulse register.  Reads return zero.

| Bit | Name | Type | Description |
|---:|---|---|---|
| 0 | `START_QUEUE` | W1P | Enable / kick queue processing if accepted. |
| 1 | `STOP_QUEUE` | W1P | Request the queue controller to stop after the current command. Optional for P19A. |
| 8 | `CLEAR_QUEUE_DONE` | W1P | Clear queue done / idle sticky bits. |
| 9 | `CLEAR_QUEUE_ERROR` | W1P | Clear queue error and reject sticky bits. |
| 10 | `CLEAR_QUEUE_COUNTERS` | W1P | Clear completed count and last-command debug snapshots. |
| 11 | `RESET_QUEUE_POINTERS` | W1P | Reset SQ/CQ head/tail counters when queue is idle. |

Unsupported combinations:

```text
START_QUEUE while queue_busy is high
START_QUEUE while queue error sticky is set and CLEAR_QUEUE_ERROR is not requested
START_QUEUE with invalid queue configuration
RESET_QUEUE_POINTERS while queue_busy is high
unsupported command bits in the same write
```

Unsupported combinations do not start queue processing and set `CSR_QUEUE_REJECT_STATUS`.

### 11.3 `CSR_QUEUE_STATUS` at 0x588

| Bit | Name | Access | Description |
|---:|---|---|
| 0 | `QUEUE_BUSY` | RO | Queue controller is fetching, executing, or completing a command. |
| 1 | `QUEUE_DONE` | RO | Sticky queue done / stopped / drained status is set. |
| 2 | `QUEUE_ERROR` | RO | Sticky queue error or reject status is set. |
| 3 | `QUEUE_ACCEPT_READY` | RO | Queue controller is idle and can accept START_QUEUE. |
| 4 | `QUEUE_ENABLED` | RO | Queue processing is enabled by control. |
| 5 | `SQ_EMPTY` | RO | Submission queue has no unconsumed entries. |
| 6 | `CQ_FULL` | RO | Completion queue has no free entries. |
| 7 | `QUEUE_STALLED` | RO | Queue is enabled but waiting for SQ entry or CQ space. |
| 8 | `CMD_FETCH_BUSY` | RO | Command queue fetch is active. |
| 9 | `DESC_FETCH_BUSY` | RO | P17 descriptor fetch is busy. |
| 10 | `RECIPE_BUSY` | RO | P16 recipe sequencer is busy. |
| 11 | `COMP_BUSY` | RO | P18 completion writeback is busy. |
| 16 | `CSR_READY` | RO | CSR block ready for transactions. |

### 11.4 `CSR_QUEUE_DONE_STATUS` at 0x58C

| Bit | Name | Type | Description |
|---:|---|---|
| 0 | `QUEUE_STARTED` | RO/W1C | START_QUEUE was accepted. |
| 1 | `QUEUE_DRAINED` | RO/W1C | Queue reached SQ empty after processing available commands. |
| 2 | `COMMAND_COMPLETED` | RO/W1C | At least one command completed and committed to CQ. |
| 3 | `STOPPED_AFTER_COMMAND` | RO/W1C | Queue stopped due to STOP_QUEUE or STOP_AFTER_THIS. |

### 11.5 `CSR_QUEUE_ERROR_STATUS` at 0x590

| Bit | Name | Type | Description |
|---:|---|---|
| 0 | `CMD_FETCH_ERROR` | RO/W1C | Command queue AXI read returned error or malformed response. |
| 1 | `CMD_VALIDATION_ERROR` | RO/W1C | Command entry failed validation after fetch. |
| 2 | `DESC_FETCH_ERROR` | RO/W1C | P17 descriptor fetch error propagated to queue level. |
| 3 | `RECIPE_ERROR` | RO/W1C | P16 recipe error propagated to queue level. |
| 4 | `COMPLETION_WB_ERROR` | RO/W1C | P18 completion writeback error propagated to queue level. |
| 5 | `QUEUE_POINTER_ERROR` | RO/W1C | Queue pointer configuration or occupancy calculation invalid. |
| 6 | `CQ_FULL_ERROR_RESERVED` | RO/W1C | Reserved. P19A should stall on CQ full rather than error. |
| 8 | `INTERNAL_SEQUENCE_ERROR` | RO/W1C | Queue FSM reached an illegal state or unexpected terminal condition. |

### 11.6 `CSR_QUEUE_CONTROL` at 0x594

| Bits | Name | Access | Reset | Description |
|---:|---|---:|---:|---|
| 0 | `QUEUE_ENABLE` | RW | 1 | Queue processing may accept START_QUEUE. |
| 1 | `RUN_UNTIL_EMPTY` | RW | 1 | Continue processing commands until SQ empty. If 0, process one command per START_QUEUE. |
| 2 | `STOP_ON_ERROR` | RW | 1 | Stop queue processing after a command error. |
| 3 | `WRITE_COMPLETION_ON_CMD_REJECT` | RW | 1 | Attempt a CQ completion for fetched command validation rejects. |
| 4 | `AUTO_CLEAR_P17_P18_ON_START` | RW | 1 | Clear relevant P17/P18 sticky status before launching a command. |
| [31:5] | `RSVD` | RO | 0 | Reserved. |

Recommended reset value:

```text
0x0000_001F
```

A smaller first RTL implementation may tie some policy bits to the recommended values and still expose the register for readback/debug.

### 11.7 `CSR_QUEUE_REJECT_STATUS` at 0x598

| Bit | Name | Type | Description |
|---:|---|---|
| 0 | `QUEUE_BUSY_REJECT` | RO/W1C | START_QUEUE requested while queue_busy is high. |
| 1 | `QUEUE_DISABLED_REJECT` | RO/W1C | START_QUEUE requested while QUEUE_ENABLE=0. |
| 2 | `INVALID_QUEUE_CONFIG_REJECT` | RO/W1C | Base/depth/stride configuration invalid. |
| 3 | `UNDERLYING_BUSY_REJECT` | RO/W1C | P17/P18/P16/P15/P14 path busy before queue command acceptance. |
| 4 | `STICKY_ERROR_REJECT` | RO/W1C | START_QUEUE requested while uncleared queue error is sticky. |
| 5 | `UNSUPPORTED_COMMAND_COMBO` | RO/W1C | Unsupported bits written to `CSR_QUEUE_COMMAND`. |
| 6 | `RESET_POINTERS_BUSY_REJECT` | RO/W1C | RESET_QUEUE_POINTERS requested while queue_busy is high. |

---

## 12. Command Fetch Interface Policy

P19 should use a dedicated command-memory AXI read master interface.

Rationale:

```text
keeps command queue fetch independent from P17 descriptor fetch
keeps descriptor table reads and command entry reads easy to debug separately
avoids adding AXI arbitration in P19A
avoids modifying the BRAM model
preserves existing DMA / AXI-Stream / Direct Stream source interfaces
```

Recommended interface style:

```systemverilog
// Command-memory AXI-MM read master, discrete wires
output logic [AXI_ID_WIDTH-1:0] cmd_axi_arid,
output logic [ADDR_WIDTH-1:0]   cmd_axi_araddr,
output logic [7:0]              cmd_axi_arlen,
output logic [2:0]              cmd_axi_arsize,
output logic [1:0]              cmd_axi_arburst,
output logic                    cmd_axi_arvalid,
input  logic                    cmd_axi_arready,

input  logic [AXI_ID_WIDTH-1:0] cmd_axi_rid,
input  logic [DATA_WIDTH-1:0]   cmd_axi_rdata,
input  logic [1:0]              cmd_axi_rresp,
input  logic                    cmd_axi_rlast,
input  logic                    cmd_axi_rvalid,
output logic                    cmd_axi_rready
```

The RTL should use discrete AXI wires, matching the existing project policy for RTL-side AXI masters.

---

## 13. Completion Writeback Interface Policy

P19 should reuse the existing P18 completion-memory AXI write master path.

P19 does not need a second completion writer.  It only supplies the completion base address for the next CQ slot:

```text
p19_cq_comp_base_addr = CQ_BASE_ADDR + ((CQ_TAIL % CQ_DEPTH) * CQ_STRIDE)
```

The existing P18 writeback engine then writes the fixed completion record and reports commit success or writeback error.

---

## 14. Queue Controller FSM Proposal

Recommended first FSM states:

```text
Q_IDLE
Q_CHECK_READY
Q_FETCH_CMD
Q_VALIDATE_CMD
Q_PREP_LAUNCH
Q_START_DESC_FETCH
Q_WAIT_DESC_FETCH_ACCEPT
Q_WAIT_RECIPE_TERMINAL
Q_START_COMPLETION
Q_WAIT_COMPLETION
Q_ADVANCE_POINTERS
Q_DRAINED
Q_ERROR
```

### 14.1 High-Level Flow

```text
Q_IDLE:
  wait for accepted START_QUEUE

Q_CHECK_READY:
  if SQ empty -> Q_DRAINED
  if CQ full -> stay stalled
  if underlying engines busy -> reject or wait before command acceptance

Q_FETCH_CMD:
  read 64-byte command entry from SQ memory

Q_VALIDATE_CMD:
  validate CMD_CONTROL, descriptor base/count/stride, and reserved bits

Q_PREP_LAUNCH:
  build internal P17 descriptor-fetch context
  compute completion queue slot address for P18
  optionally clear P17/P18 sticky status

Q_START_DESC_FETCH:
  issue internal P17 START_FETCH_RECIPE request

Q_WAIT_RECIPE_TERMINAL:
  wait for fetch failure, recipe done, recipe error, or recipe reject terminal condition

Q_START_COMPLETION:
  request P18 completion writeback to current CQ slot

Q_WAIT_COMPLETION:
  wait for P18 completion done or completion writeback error

Q_ADVANCE_POINTERS:
  increment SQ_HEAD
  increment CQ_TAIL only if completion committed
  update completed count and last-command debug fields

Q_DRAINED:
  set queue drained sticky
  if RUN_UNTIL_EMPTY and new SQ entries appear, continue when kicked or enabled by policy

Q_ERROR:
  set queue error sticky
  stop processing until cleared
```

### 14.2 Pointer Advancement Policy

Recommended policy:

```text
SQ_HEAD advances after command reaches terminal queue status.
CQ_TAIL advances only after completion record final commit succeeds.
```

For command validation reject with CQ completion successfully written:

```text
SQ_HEAD advances
CQ_TAIL advances
completed_count may increment as a completed queue entry with reject status
```

For command fetch error before command contents are known:

```text
SQ_HEAD does not advance by default
CQ_TAIL does not advance
CSR_QUEUE_ERROR_STATUS.CMD_FETCH_ERROR is authoritative
```

This is conservative and avoids silently dropping an unread command entry.

---

## 15. Host Programming Model

### 15.1 Initialization

```text
1. Host initializes SQ memory entries to zero.
2. Host initializes CQ memory entries word0 to zero.
3. Host programs CSR_SQ_BASE_ADDR, CSR_SQ_DEPTH, CSR_SQ_STRIDE.
4. Host programs CSR_CQ_BASE_ADDR, CSR_CQ_DEPTH, CSR_CQ_STRIDE.
5. Host resets queue pointers or writes initial head/tail values while queue is idle.
6. Host enables queue processing.
```

### 15.2 Submit Commands

For each command:

```text
1. Host chooses sq_index = SQ_TAIL % SQ_DEPTH.
2. Host writes command payload words 1..15.
3. Host writes CMD_CONTROL with VALID=1 last.
4. Host updates CSR_SQ_TAIL to publish the new tail value.
5. Host writes START_QUEUE or relies on an already enabled run-until-empty policy.
```

### 15.3 Consume Completions

```text
1. Host reads CQ_TAIL through CSR or polls CQ memory.
2. For each available CQ entry, host polls completion_record[0].VALID.
3. Once VALID=1, host reads the remaining completion record words.
4. Host clears or recycles the CQ entry word0 to zero for debug cleanliness.
5. Host updates CSR_CQ_HEAD after consuming the completion entry.
```

The P19 prototype does not define cache-coherent ordering.  UVM memory models provide deterministic visibility for validation.

---

## 16. Error and Reject Policy

### 16.1 Queue-Level Rejects

Queue-level rejects are CSR-only when no SQ command entry has been accepted.

Examples:

```text
START_QUEUE while queue_busy
START_QUEUE with invalid queue base/depth/stride
START_QUEUE while queue disabled
RESET_QUEUE_POINTERS while queue_busy
unsupported CSR_QUEUE_COMMAND combination
```

These set `CSR_QUEUE_REJECT_STATUS` and do not write a completion record.

### 16.2 Fetched Command Rejects

A fetched SQ command that fails validation is associated with a queue entry.  If CQ space exists and completion writeback is enabled, P19 should attempt to write a reject completion record.

Examples:

```text
CMD_CONTROL.VALID=0 at fetched command slot
unsupported OPCODE
DESC_COUNT=0
DESC_STRIDE unaligned
reserved command control bits set
```

Recommended terminal behavior:

```text
write reject completion to current CQ slot
advance SQ_HEAD after completion commit
advance CQ_TAIL after completion commit
set queue command validation error sticky for debug
```

### 16.3 P17 / P16 / P15 Errors

Errors below P19 are captured in the existing P17/P16/P15 status and in the P18 completion record.

P19 should also mirror a summary into queue-level status:

```text
P17 fetch error      -> CSR_QUEUE_ERROR_STATUS.DESC_FETCH_ERROR
P16 recipe error     -> CSR_QUEUE_ERROR_STATUS.RECIPE_ERROR
P16/P15 reject after accepted context -> completion record OVERALL_REJECT and queue debug detail
```

### 16.4 Completion Writeback Error

If P18 completion writeback fails before commit:

```text
P19 sets CSR_QUEUE_ERROR_STATUS.COMPLETION_WB_ERROR
P19 does not increment CQ_TAIL
P19 stops if STOP_ON_ERROR=1
CSR completion-writeback status is authoritative for writeback failure detail
```

### 16.5 P24B Command Timeout Error

If an accepted SQ command has `CMD_TIMEOUT_CYCLES != 0` and the watchdog expires before terminal queue status:

```text
P24 sets CSR_QUEUE_ERROR_STATUS.COMMAND_TIMEOUT_ERROR
P24 records DETAIL_COMMAND_TIMEOUT or a phase-specific DETAIL_TIMEOUT_* code in CSR_QUEUE_ERROR_DETAIL
P24 records the active SQ/CQ physical index in CSR_QUEUE_ERROR_INDEX
P24 preserves CSR_QUEUE_LAST_CMD_TAG / CSR_QUEUE_LAST_CMD_CONTROL for the timed-out command
P24 stops the active queue service session when STOP_ON_ERROR=1
P22 raises QUEUE_ERROR_EVENT
```

Pointer policy:

```text
SQ_HEAD advances when the accepted command is converted into a timeout terminal status
CQ_TAIL advances only if a timeout completion record commits successfully
CQ_TAIL must not advance if the completion writeback path is the timed-out path and no valid CQ record was committed
```

If a timeout CQ record is committed, the record uses the existing P18 64-byte completion format with `OVERALL_ERROR=1` and the P24 timeout status/detail encoding.  If no timeout CQ record is committed, the queue CSR error status is authoritative.

---

## 17. Memory Ordering and Commit Policy

### 17.1 Host-to-Hardware Command Commit

The host publishes a command entry by writing `CMD_CONTROL.VALID=1` last.

Hardware must not consume a command entry unless:

```text
SQ_HEAD != SQ_TAIL
CMD_CONTROL.VALID == 1
command validation passes or produces a fetched-command reject completion
```

### 17.2 Hardware-to-Host Completion Commit

Hardware publishes a completion entry by reusing the P18 commit policy:

```text
completion payload words first
completion word0 COMP_COMMIT with VALID=1 last
CQ_TAIL increments only after final commit BRESP succeeds
```

This gives the host two visibility options:

```text
poll CQ_TAIL CSR
poll completion_record[0].VALID in memory
```

---

## 18. UVM Validation Plan and P19 Closure

P19 was implemented and validated as a correctness-first single-outstanding queue prototype.

Final P19 milestone split:

```text
P19A: Command / completion queue spec
P19B: CSR queue register map
P19C: Single-outstanding queue fetch controller
P19D: Command queue -> existing P17 descriptor fetch launch
P19E: Completion queue writeback integration
P19F: Queue reject / empty / full / bad pointer handling
P19G: Full regression integration
P19H: Documentation closure
```

### 18.1 Targeted Smoke Tests

Validated targeted tests:

```text
ai_accel_subsys_csr_queue_desc_fetch_dma_smoke_test
ai_accel_subsys_csr_queue_completion_wb_smoke_test
ai_accel_subsys_csr_queue_reject_error_test
```

Targeted coverage:

```text
SQ command entry fetch and validation
Queue command context to P17 descriptor-fetch launch
P18 completion writeback to CQ slot address
SQ_HEAD advancement after accepted command completion
CQ_TAIL advancement after completion commit
QUEUE_ENABLE disabled reject
invalid queue configuration reject
empty SQ drained status
bad SQ pointer reject
bad CQ pointer reject
CQ full stall
CQ full recovery after host advances CQ_HEAD
post-recovery valid command through P17/P18 to CQ writeback
```

### 18.2 Full Regression Representatives

P19G full-regression representatives:

```text
csr_queue_desc_fetch_dma_case102
csr_queue_completion_wb_case102
csr_queue_reject_error_case102
```

Full regression after P19G:

```text
TOTAL : 113
PASS  : 113
FAIL  : 0
```

---

## 19. P19 Closure Criteria

P19 is complete when the queue specification, CSR map, queue fetch controller, queue-to-P17 launch, CQ writeback integration, queue robustness handling, full regression, and documentation closure are complete.

Final P19 closure checklist:

```text
Queue design intent frozen
Command entry format frozen
Completion queue reuse of P18 record frozen
Queue pointer model frozen
Canonical CSR queue window recorded in axi_lite_csr_control_plane_spec.md
Single-outstanding queue fetch controller implemented
Queue command launches existing P17 descriptor fetch
Queue completion uses existing P18 completion record and writeback engine
SQ_HEAD and CQ_TAIL advance only after completion commit
Queue disabled / invalid config / empty SQ / bad pointer / CQ full handling validated
Full regression 113/113 PASS
No BRAM / GEMM / DMA / frontend datapath changes required
```

---

---

## 20. Relationship to P20 Multi-Entry Queue Drain

P20 extends the P19 command / completion queue prototype without changing the P19 command entry format, CQ completion record format, or canonical queue CSR register map.

P19 proves the single-command queue wrapper:

```text
one SQ command
    -> P19 fetch / validation
    -> P17 descriptor fetch
    -> P16/P15 execution
    -> P18 CQ writeback
    -> SQ_HEAD / CQ_TAIL advancement
```

P20 repeats that same path in order:

```text
SQ[0] -> execute -> CQ[0]
SQ[1] -> execute -> CQ[1]
SQ[2] -> execute -> CQ[2]
```

P20 retains the P19 correctness-first rule:

```text
one active command at a time
in-order SQ_HEAD to SQ_TAIL execution
in-order CQ_TAIL completion production
no multi-outstanding commands
no out-of-order completion
no BRAM / GEMM / DMA / frontend datapath changes
```

Validated P20 closure:

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

Validated P20 full-regression representatives:

```text
csr_queue_two_command_dma_case102
csr_queue_mixed_dma_ds_c_rmw_case208
csr_queue_wraparound_case102
csr_queue_stop_behavior_case102
```

The detailed P20 drain policy is documented in `multi_entry_queue_drain_spec.md`.


## 21. Relationship to P21 Runtime Doorbell / Live Queue Service

P21 extends the P19/P20 command / completion queue model without changing the P19 command entry format, CQ completion record format, or canonical queue CSR register map.

P19 proves the single-command queue wrapper:

```text
one SQ command
    -> P19 fetch / validation
    -> P17 descriptor fetch
    -> P16/P15 execution
    -> P18 CQ writeback
    -> SQ_HEAD / CQ_TAIL advancement
```

P20 repeats that path for all visible commands in a batch.  P21 keeps the same in-order, single-active-command path, but allows the host to append more SQ entries while the controller is still active:

```text
SQ[0] visible at START_QUEUE
SQ[1] published later by host writing CMD_CONTROL.VALID last
host updates CSR_SQ_TAIL while queue_busy=1
hardware observes the new SQ_TAIL only at the next command boundary
SQ[1] executes without a second START_QUEUE if the session has not drained
```

Validated P21 closure:

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

Validated P21 full-regression representatives:

```text
csr_queue_runtime_doorbell_dma_case102
csr_queue_runtime_doorbell_mixed_case102
csr_queue_cq_full_live_recovery_case102
csr_queue_stop_live_service_case102
```

The detailed P21 live-service policy is documented in `runtime_doorbell_live_queue_service_spec.md`.


## 22. Relationship to P22 Event Notification / Interrupt-Lite

P22 extends the P19/P20/P21 queue model with a summary notification layer.  It does not change the P19 command entry format, P18 completion record format, P19/P20/P21 queue pointer model, or queue CSR window.

P19/P20/P21 remain the authoritative queue execution and completion model:

```text
SQ command entry
    -> queue fetch / validation
    -> P17 descriptor fetch
    -> P16/P15 execution
    -> P18 CQ writeback
    -> SQ_HEAD / CQ_TAIL advancement after completion commit
```

P22 observes selected queue-level events after those existing state transitions:

```text
completion commit and CQ_TAIL advancement -> QUEUE_COMMAND_COMPLETED_EVENT
CQ occupancy becomes non-zero              -> CQ_NOT_EMPTY_EVENT
SQ empty drain                             -> QUEUE_DRAINED_EVENT
graceful STOP_QUEUE / STOP_AFTER_THIS      -> QUEUE_STOPPED_EVENT
queue validation / propagated error        -> QUEUE_ERROR_EVENT
```

The CQ record remains the authoritative per-command completion detail.  P22 only tells software that queue state or completion state should be inspected through the existing CSR and CQ memory interfaces.

Validated P22 full-regression representatives:

```text
csr_event_csr_smoke
csr_queue_completion_event_case102
csr_queue_drained_stopped_error_event_case102
csr_event_mask_w1c_rearm
```

Full regression after P22G:

```text
TOTAL : 125
PASS  : 125
FAIL  : 0
```

## 23. Interview Summary

P19 turns the P17/P18 memory-backed command prototype into a small host queue prototype.

The important design point is that P19 does not create a second accelerator execution stack.  It only adds a realistic queue manager above the already validated P17 descriptor fetch and P18 completion writeback blocks.

Concise summary:

```text
P17 gave the subsystem a memory-backed command ingress path.
P18 gave it a memory-backed completion egress path.
P19 wraps both with a small in-order host queue: command entries in memory, completion records in memory, one active command at a time.
```

The result is still small enough for a single-person RTL/UVM project, but it demonstrates a realistic accelerator software interface: host-visible submission queue, host-visible completion queue, CSR doorbell/control, error/status handling, and end-to-end command-to-completion validation.

## 20. P23 Event-Driven Host Runtime Validation

P23 validates the P19 command / completion queue model under a driver-style host runtime rather than only feature-centric queue tests.

Validated P23 queue usage:

```text
single SQ command submit -> event wait -> CQ consume
multiple SQ commands drained in order from one START_QUEUE
runtime SQ_TAIL append while queue service is live
CQ_HEAD update used as host-visible CQ consumption and CQ-full recovery doorbell
STOP_QUEUE handling with pending SQ entry preserved until restart
invalid SQ command converted into queue error status and QUEUE_ERROR_EVENT
```

Validated P23 full-regression representatives:

```text
csr_event_driven_single_queue_command_case102
csr_event_driven_multi_command_queue_drain_case102
csr_event_driven_runtime_append_case102
csr_event_driven_cq_full_stop_error_case102
```

P23 does not change the P19 SQ command entry, P18 CQ completion record, queue CSR window, monotonic head/tail pointer model, or single-active-command execution policy.  It validates that a host runtime can use those existing mechanisms as a complete submit / notify / consume / recover loop.



---

## 24. P24 Timeout / Watchdog Policy Freeze

P24B converts the existing `CMD_TIMEOUT_CYCLES` SQ word from optional debug metadata into the canonical per-command watchdog budget.

Frozen P24B queue policy:

```text
No SQ entry size change
No CQ entry size change
No queue CSR address change
No P22 event bit change
CMD_TIMEOUT_CYCLES=0 preserves existing behavior
Accepted command timeout sets CSR_QUEUE_ERROR_STATUS.COMMAND_TIMEOUT_ERROR
Timeout wakes the host through P22 QUEUE_ERROR_EVENT
Timeout completion records are optional and must follow the existing P18 commit-last policy
```

The queue runtime remains correctness-first and single-active-command.  Timeout does not introduce preemption, rollback, out-of-order completion, or a new lower-level abort protocol.


---

## 25. P24 Queue Timeout Validation Addendum

P24 validates the existing P19 command / completion queue model with a per-command watchdog layered on top of the accepted SQ command context.

Validated queue-level timeout behavior:

```text
CMD_TIMEOUT_CYCLES is snapshotted from SQ word6 when the command is accepted
CMD_TIMEOUT_CYCLES=0 disables the watchdog and preserves legacy behavior
watchdog expiry is reported as CSR_QUEUE_ERROR_STATUS.COMMAND_TIMEOUT_ERROR
phase-specific timeout detail is reported through CSR_QUEUE_ERROR_DETAIL
QUEUE_ERROR_EVENT wakes the P23-style host runtime
SQ_HEAD / CQ_TAIL advance only according to the existing terminal/commit policy
CQ_TAIL does not advance when completion writeback is blocked and no valid CQ record commits
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

P24 keeps the P19 queue correctness model: one active command, in-order command consumption, in-order completion production, existing 64-byte SQ entries, existing 64-byte CQ records, and no BRAM / datapath changes.


---

## 26. P25 Runtime Stress / Robustness Queue Validation

P25 validates the existing P19 command / completion queue model under representative runtime stress.  It keeps the same 64-byte SQ command entry, 64-byte CQ completion record, monotonic head/tail pointer model, and single-active-command execution policy.

Validated P25 queue behavior:

```text
multiple queue sessions can run and cleanly reuse SQ/CQ state
runtime append remains ordered and becomes visible through SQ_TAIL publication
delayed CQ consumption and later CQ_HEAD update recover CQ space without queue reset
STOP_QUEUE stops after the active command and leaves pending SQ work restartable
timeout recovery clears queue/lower-level sticky state before accepting a valid command
SQ_HEAD and CQ_TAIL advance only according to existing command terminal and completion commit policy
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

P25 does not introduce prefetch, multi-outstanding command execution, out-of-order completion, command cancellation, or BRAM / datapath changes.
