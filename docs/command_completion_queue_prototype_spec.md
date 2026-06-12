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
| 0x18 | 6  | `CMD_TIMEOUT_CYCLES` | Optional timeout budget. Zero disables timeout in P19A. |
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

## 10. Queue CSR Window Summary

P19B freezes the software-visible queue CSR window as part of the canonical AXI-Lite CSR map.

```text
P19 queue CSR base   = 0x580
P19 queue CSR window = 0x580 - 0x5FC
```

The canonical register map, access types, reset values, register ownership policy, and register bit definitions are recorded in:

```text
docs/axi_lite_csr_control_plane_spec.md
```

This P19 queue prototype spec intentionally keeps only the queue architecture, command entry format, completion queue behavior, host programming model, error policy, and validation plan.  It does not duplicate the full CSR table.

Frozen P19B constants used by the queue architecture:

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

P19B does not add RTL, UVM tests, Tcl scripts, README updates, or regression-list items.

---

## 11. Queue CSR Programming Model

The queue CSR programming model is:

```text
1. Host programs SQ base/depth/stride while the queue is idle.
2. Host programs CQ base/depth/stride while the queue is idle.
3. Host writes SQ entries into memory.
4. Host writes CSR_SQ_TAIL as a doorbell value.
5. Host writes CSR_QUEUE_COMMAND.START_QUEUE.
6. Hardware fetches SQ entries, runs one command at a time, and writes CQ entries.
7. Host observes CSR_CQ_TAIL or polls CQ commit words.
8. Host advances CSR_CQ_HEAD after consuming committed CQ entries.
```

Queue base/depth/stride configuration writes while `queue_busy` is high are rejected.  `CSR_SQ_TAIL` and `CSR_CQ_HEAD` remain host-owned queue pointer updates and may be written while the queue controller is enabled.

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

## 18. UVM Validation Plan

Recommended P19 validation sequence:

```text
P19A: command / completion queue spec
P19B: queue CSR register map / helper support
P19C: command queue fetch engine compile smoke
P19D: queue controller single DMA command smoke
P19E: two-command sequential queue smoke
P19F: C RMW command queue representative
P19G: Direct Stream command queue representative
P19H: queue empty / full / busy / invalid command handling
P19I: command fetch RRESP error and completion writeback error propagation
P19J: full regression integration
P19K: docs closure
```

### 18.1 Targeted Smoke Tests

Initial focused tests:

```text
queue_csr_regs_smoke
queue_single_dma_desc_fetch_completion_case102
queue_two_command_dma_case100_102
queue_c_rmw_case208
queue_direct_stream_case102
queue_invalid_command_reject
queue_empty_full_busy_handling
queue_cmd_fetch_error
queue_completion_wb_error
```

### 18.2 Full Regression Representatives

Recommended first full-regression subset:

```text
csr_queue_single_dma_case102
csr_queue_two_command_dma_case100_102
csr_queue_c_rmw_case208
csr_queue_direct_stream_case102
csr_queue_reject_error_case102
```

These mirror the P18H representative strategy without exploding regression runtime.

---

## 19. P19A Closure Criteria

P19A is complete when this specification is reviewed and frozen enough to start implementation.

Minimum P19A closure checklist:

```text
Queue design intent defined
Command entry format defined
Completion queue reuse of P18 record defined
Queue pointer model defined
CSR queue window proposed
Error / reject policy defined
Validation plan defined
Non-goals explicitly listed
No BRAM / GEMM / DMA / frontend datapath changes required
```

---

## 20. Interview Summary

P19 turns the P17/P18 memory-backed command prototype into a small host queue prototype.

The important design point is that P19 does not create a second accelerator execution stack.  It only adds a realistic queue manager above the already validated P17 descriptor fetch and P18 completion writeback blocks.

Concise summary:

```text
P17 gave the subsystem a memory-backed command ingress path.
P18 gave it a memory-backed completion egress path.
P19 wraps both with a small in-order host queue: command entries in memory, completion records in memory, one active command at a time.
```

The result is still small enough for a single-person RTL/UVM project, but it demonstrates a realistic accelerator software interface: host-visible submission queue, host-visible completion queue, CSR doorbell/control, error/status handling, and end-to-end command-to-completion validation.
