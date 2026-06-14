# P20 Multi-Entry In-Order Queue Drain Spec

## 1. Purpose

This document defines the P20A/P20B multi-entry queue-drain specification for the AI Accelerator Subsystem.

P19 completed a correctness-first command / completion queue prototype:

```text
one SQ command entry
    -> P19 queue fetch / validation
    -> P17 descriptor fetch
    -> P16 recipe sequencer
    -> P15 job sequencer
    -> existing datapath
    -> P18 completion writeback into one CQ slot
    -> SQ_HEAD / CQ_TAIL advancement after completion commit
```

P20 extends that validated path from a single queue command into an in-order queue drain:

```text
SQ[0] -> execute -> CQ[0]
SQ[1] -> execute -> CQ[1]
SQ[2] -> execute -> CQ[2]
...
```

P20 remains intentionally conservative:

```text
one active command at a time
in-order SQ_HEAD to SQ_TAIL command execution
in-order CQ_TAIL completion production
no overlap between queue fetch, descriptor fetch, recipe execution, and completion writeback for different commands
no out-of-order completion
no interrupt model
no driver model
no BRAM / GEMM / DMA / frontend datapath changes
```

The goal is to make the P19 host queue behave like a real queue while keeping the control logic small, deterministic, and explainable.

Current baseline entering P20A/P20B:

```text
P19G / P19H command-completion queue closure:
  TOTAL : 113
  PASS  : 113
  FAIL  : 0
```

Current closure after P20G:

```text
P20 multi-entry in-order queue drain closure:
  TOTAL : 117
  PASS  : 117
  FAIL  : 0
```

---

## 2. Baseline Before P20

The validated P19 queue model includes:

```text
P19 command queue CSR window
P19 submission queue entry fetch
P19 command entry validation
P19 queue command to P17 descriptor-fetch launch
P18 completion writeback to a CQ-selected address
SQ_HEAD advancement after accepted command terminal status
CQ_TAIL advancement after P18 completion commit
queue disabled / invalid config / empty SQ / bad pointer / CQ full handling
full regression 113/113 PASS
```

P20 builds only on the P19 queue controller layer.

P20 must preserve the existing lower-level hierarchy:

```text
P14 CSR micro-operation path      -> debug / compatibility
P15 single-job sequencer          -> one descriptor worker
P16 CSR-resident recipe sequencer -> multi-slot recipe dispatcher
P17 descriptor fetch prototype    -> memory-backed recipe descriptor loader
P18 completion writeback          -> memory-backed completion record writer
P19 queue controller              -> host command / completion queue wrapper
P20 queue drain policy            -> repeated in-order use of the P19 command path
```

P20 must not require changes to:

```text
axi_mm_dual_port_bram
GEMM datapath behavior
DMA load/store datapath protocol
AXI-Stream preload datapath protocol
Direct Stream preload datapath protocol
P17 descriptor format
P18 completion record format
P19 SQ entry format
P19 CQ entry format
P19 canonical CSR register map
```

---

## 3. P20 Design Intent

P19 validated one accepted queue command at a time.  P20 keeps that single-active-command rule but allows the controller to automatically return to the queue-ready check after each committed completion.

P19 effective model:

```text
START_QUEUE
  fetch one SQ entry
  execute one command
  write one CQ entry
  advance pointers
  return idle / drained
```

P20 model:

```text
START_QUEUE
  while queue is enabled and RUN_UNTIL_EMPTY=1:
    if SQ empty:
      drain complete
    else if CQ full:
      stall until CQ space exists
    else if lower-level engines are idle:
      fetch one SQ entry
      execute one command
      write one CQ entry
      advance pointers
      repeat
```

This is a drain loop, not multi-outstanding execution.

The main interview-friendly point is:

```text
P20 makes the host-visible queue real enough to submit multiple commands, while still using a correctness-first, single-active-command implementation.
```

---

## 4. P20A Scope

### 4.1 Included

P20A defines:

```text
multi-entry queue drain design intent
in-order command execution policy
auto-continue policy after completion commit
RUN_UNTIL_EMPTY behavior
CQ full stall / recovery behavior across multiple entries
SQ empty drained behavior after draining all visible commands
STOP_QUEUE and STOP_AFTER_THIS relationship to the drain loop
pointer advancement policy across multiple commands
physical index wrap policy using monotonic counters
UVM validation plan
full-regression closure plan
```

### 4.2 Not Included

P20A does not include:

```text
RTL implementation
CSR RTL changes
new CSR addresses
new CSR bit definitions
UVM tests
multiple outstanding commands
out-of-order completion
overlapped queue fetch and command execution
interrupt output
MSI/MSI-X style interrupt model
Linux driver
C software driver
UVM RAL model
command cancellation / preemption
scheduler priority
cache-coherent host interface
AXI interconnect / NoC integration
DMA / GEMM / frontend datapath changes
```

---

## 5. P20B Auto-Continue Policy Scope

P20B freezes the auto-continue behavior that the later RTL implementation should follow.

P20B is still a spec / design-policy milestone.  It should not add RTL by itself.

P20B defines:

```text
when the queue controller loops to the next SQ entry
when it stops after one command
when it reports drained
when it stalls on CQ full
when it honors STOP_QUEUE
when it honors CMD_CONTROL.STOP_AFTER_THIS
when it clears P17/P18 sticky state for each command
what state must be snapshot per command
what pointer updates occur per committed command
```

P20B intentionally reuses the P19 CSR map.  The canonical CSR register map remains in:

```text
docs/axi_lite_csr_control_plane_spec.md
```

No P20A/P20B CSR register-map update is required unless a later RTL milestone discovers a missing debug/status field.

---

## 6. Fixed P20 Design Decisions

```text
Outstanding command count       : one active command at a time
Command order                   : in-order SQ_HEAD -> SQ_TAIL
Completion order                : in-order CQ_TAIL follows accepted command order
Execution overlap               : not allowed in P20
Queue entry size                : existing P19 64-byte SQ entry
Completion entry size           : existing P18/P19 64-byte CQ entry
Descriptor format               : existing P17 descriptor format unchanged
Completion record format        : existing P18 record format unchanged
Pointer model                   : existing monotonic SQ_HEAD/SQ_TAIL/CQ_HEAD/CQ_TAIL counters
Physical index                  : pointer modulo depth
CSR map                         : existing P19 queue CSR map unchanged
RUN_UNTIL_EMPTY                 : existing CSR_QUEUE_CONTROL bit controls auto-drain
STOP_QUEUE                      : existing CSR_QUEUE_COMMAND bit requests stop after current command
STOP_AFTER_THIS                 : existing command-entry bit stops after the current command
BRAM / GEMM / DMA / frontend    : unchanged
```

P20 does not change the host memory protocol:

```text
host writes SQ command payload first
host writes SQ command VALID word last
hardware writes CQ completion payload first
hardware writes CQ commit word last
```

---

## 7. Queue Drain Session Model

A queue drain session begins when `CSR_QUEUE_COMMAND.START_QUEUE` is accepted.

At the start of a drain session:

```text
queue_busy is set
QUEUE_STARTED sticky status is set
current SQ/CQ pointer values are read from CSR state
queue controller validates queue configuration
queue controller checks SQ occupancy and CQ space
```

The drain session ends when one of these terminal conditions occurs:

```text
SQ becomes empty after all visible commands are consumed
RUN_UNTIL_EMPTY=0 and one command has completed
STOP_QUEUE was requested and the active command has completed
CMD_CONTROL.STOP_AFTER_THIS was set in the active command and the command has completed
a queue-level error occurs and STOP_ON_ERROR=1
reset occurs
```

The drain session may stall but remain active when:

```text
CQ is full
an underlying lower-level engine is still busy before command acceptance
host has not yet exposed a new SQ entry and the controller is configured to wait for a kick-only policy in later extensions
```

For P20, the preferred behavior is:

```text
SQ empty -> drained terminal state
CQ full  -> stall, not error
```

This matches the P19F robustness behavior and makes the host responsible for advancing `CSR_CQ_HEAD` after consuming CQ entries.

---

## 8. Auto-Continue Decision Point

The auto-continue decision occurs only after the current command has reached terminal queue status and pointer updates for that command have been applied.

Recommended state transition point:

```text
Q_ADVANCE_POINTERS
    -> Q_CHECK_CONTINUE
        -> Q_CHECK_READY for next command
        -> Q_DRAINED
        -> Q_STOPPED
        -> Q_ERROR
```

The controller must not fetch the next SQ entry until:

```text
active command completion record has committed successfully, or the active command reached a defined terminal reject/error policy
SQ_HEAD update for the completed command is applied
CQ_TAIL update is applied if a CQ record committed
per-command debug/status snapshots are updated
```

This prevents the next command from using stale CQ space or stale lower-level status.

---

## 9. Auto-Continue Rules

After a command completes, the queue controller evaluates the next action in this order:

```text
1. If reset is asserted, return to reset state.
2. If a queue-level error is sticky and STOP_ON_ERROR=1, stop in error state.
3. If STOP_QUEUE was requested, stop after the just-completed command.
4. If active command STOP_AFTER_THIS was set, stop after the just-completed command.
5. If RUN_UNTIL_EMPTY=0, stop after one command.
6. If SQ occupancy is zero, enter drained state.
7. If CQ space is zero, enter CQ-full stall state and wait for host to advance CQ_HEAD.
8. If any lower-level engine is busy, wait before accepting the next command.
9. Otherwise fetch the next SQ entry.
```

This ordering is important:

```text
STOP_QUEUE / STOP_AFTER_THIS win over RUN_UNTIL_EMPTY
SQ empty reports drained, not error
CQ full stalls before consuming another SQ entry
underlying busy prevents command acceptance but does not consume SQ_HEAD
```

---

## 10. `RUN_UNTIL_EMPTY` Policy

`CSR_QUEUE_CONTROL.RUN_UNTIL_EMPTY` already exists in the P19 CSR map.

P20 freezes its implementation meaning:

```text
RUN_UNTIL_EMPTY=0:
  one accepted START_QUEUE processes at most one SQ command.
  After one command terminal status and pointer advancement, the controller stops.

RUN_UNTIL_EMPTY=1:
  one accepted START_QUEUE processes commands until SQ empty, stop request, error, or reset.
```

`RUN_UNTIL_EMPTY=1` does not mean overlap or multi-outstanding execution.

It means:

```text
repeat the P19 single-command path automatically
```

---

## 11. `STOP_QUEUE` Policy

`CSR_QUEUE_COMMAND.STOP_QUEUE` requests a graceful stop.

If no command is active:

```text
STOP_QUEUE may set STOPPED_AFTER_COMMAND sticky status or be ignored as a no-op.
No SQ/CQ pointer changes occur.
```

If a command is active:

```text
finish the active command
attempt its normal completion writeback if applicable
apply normal SQ_HEAD / CQ_TAIL pointer updates
set STOPPED_AFTER_COMMAND sticky status
do not fetch another SQ entry
return queue_busy to 0
```

P20 does not define hard abort or partial rollback.

Unsupported behavior:

```text
STOP_QUEUE must not cancel an in-flight P17 descriptor fetch.
STOP_QUEUE must not cancel an in-flight P16/P15 recipe/job.
STOP_QUEUE must not cancel an in-flight P18 completion writeback.
```

---

## 12. `STOP_AFTER_THIS` Command Policy

`CMD_CONTROL.STOP_AFTER_THIS` is a per-command stop hint.

When the fetched command has `STOP_AFTER_THIS=1`:

```text
execute the command normally
write the completion record normally
advance SQ_HEAD normally
advance CQ_TAIL after completion commit
set STOPPED_AFTER_COMMAND sticky status
do not fetch the next SQ entry even if RUN_UNTIL_EMPTY=1 and SQ is non-empty
```

This lets software submit multiple SQ entries but mark a command as a graceful batch boundary.

---

## 13. CQ Full Stall / Recovery Policy

Before accepting a command, P20 must check CQ space.

Required rule:

```text
Do not fetch or consume an SQ entry unless at least one CQ slot is available for the command's terminal completion.
```

If CQ is full before command acceptance:

```text
queue controller stalls
SQ_HEAD does not advance
no command-memory AXI read is issued
QUEUE_STALLED / CQ_FULL live status is asserted
no error is set by default
```

When the host consumes one or more CQ entries and advances `CSR_CQ_HEAD`:

```text
cq_space becomes non-zero
the active drain session may continue if RUN_UNTIL_EMPTY=1 and no stop/error condition is pending
```

This recovers the same way P19F demonstrated CQ full recovery for one command, but extended to multi-entry draining.

---

## 14. SQ Empty / Drained Policy

If the queue controller reaches a command boundary and finds:

```text
SQ_HEAD == SQ_TAIL
```

then:

```text
enter drained terminal state
clear queue_busy
set QUEUE_DRAINED sticky status
keep COMMAND_COMPLETED sticky status if at least one command completed in the session
```

SQ empty is not an error.

If the host later writes more SQ entries and advances `CSR_SQ_TAIL`, software should issue another `START_QUEUE` kick for P20 unless a later extension explicitly defines always-on polling behavior.

Recommended P20 policy:

```text
P20 queue drain is kick-driven.
After drained, a new START_QUEUE kick is required to drain newly added commands.
```

---

## 15. Pointer Advancement Policy

Pointer advancement remains conservative.

For a successful command completion:

```text
SQ_HEAD = SQ_HEAD + 1
CQ_TAIL = CQ_TAIL + 1 after P18 completion commit succeeds
completed_count = completed_count + 1
```

For a command validation reject with a committed reject completion:

```text
SQ_HEAD = SQ_HEAD + 1
CQ_TAIL = CQ_TAIL + 1
completed_count may increment as a terminal queue entry
```

For command fetch AXI error before command contents are known:

```text
SQ_HEAD does not advance by default
CQ_TAIL does not advance
CSR_QUEUE_ERROR_STATUS.CMD_FETCH_ERROR is authoritative
queue stops until error is cleared
```

For completion writeback error before CQ commit:

```text
SQ_HEAD advancement policy must be conservative and implementation-defined in RTL notes
CQ_TAIL must not advance
CSR_QUEUE_ERROR_STATUS.COMPLETION_WB_ERROR is authoritative
queue stops until error is cleared
```

Recommended first RTL policy for P20:

```text
Do not continue draining after any completion writeback error.
Do not advance CQ_TAIL unless final commit BRESP succeeds.
```

---

## 16. Physical Index Wrap Policy

P20 validates physical ring-buffer wrap while continuing to use monotonic counters.

```text
sq_index = SQ_HEAD % SQ_DEPTH
cq_index = CQ_TAIL % CQ_DEPTH
```

Because the depths are required to be powers of two, RTL can implement:

```text
sq_index = SQ_HEAD[log2(SQ_DEPTH)-1:0]
cq_index = CQ_TAIL[log2(CQ_DEPTH)-1:0]
```

P20 validation should cover physical wrap, for example:

```text
SQ_DEPTH=2, CQ_DEPTH=2
initial SQ_HEAD=1, SQ_TAIL=3
initial CQ_HEAD=1, CQ_TAIL=1
```

This drains two commands at physical SQ indices:

```text
1 -> 0
```

and writes two completions to physical CQ indices:

```text
1 -> 0
```

P20 does not require testing ambiguous 32-bit monotonic counter wrap.

---

## 17. Per-Command Snapshot Policy

Each accepted command must snapshot the context needed for its completion before lower-level launch:

```text
sq_head_snapshot
sq_index
cq_tail_snapshot
cq_index
computed SQ entry address
computed CQ entry address
CMD_CONTROL
CMD_USER_TAG
CMD_DESC_BASE_ADDR
CMD_DESC_COUNT
CMD_DESC_STRIDE
CMD_COMPLETION_FLAGS
CMD_TIMEOUT_CYCLES
```

The active command must use the snapshot.  Host writes to `CSR_SQ_TAIL` or `CSR_CQ_HEAD` during execution must not change the active command's SQ/CQ addresses.

Only the command-boundary auto-continue check should observe updated host-owned pointers.

---

## 18. Lower-Level Sticky Clear Policy

If `CSR_QUEUE_CONTROL.AUTO_CLEAR_P17_P18_ON_START=1`, P20 should apply the clear policy for each accepted command, not only once at the beginning of the drain session.

Recommended behavior:

```text
before launching each command into P17:
  clear P17 descriptor-fetch sticky status needed by the next command
  clear P18 completion-writeback sticky status needed by the next command
  clear P16/P15 status only through the already validated P17/P16/P15 launch policy
```

Rationale:

```text
each CQ record should describe the current command, not stale status from the previous command
```

---

## 19. Error and Stop Interaction

Default P20 policy:

```text
STOP_ON_ERROR=1
```

When a queue-level error occurs:

```text
set queue error sticky status
record error index/detail
stop the drain session
require CLEAR_QUEUE_ERROR before a new START_QUEUE can be accepted
```

If a later implementation allows `STOP_ON_ERROR=0`, that behavior must be validated separately.  P20A/P20B do not require continuing after errors.

Stop requests are graceful and are not errors:

```text
STOP_QUEUE
STOP_AFTER_THIS
RUN_UNTIL_EMPTY=0 one-command mode
```

These should set done/stopped style status, not queue error status.

---

## 20. Host Programming Model

### 20.1 Multi-Command Drain

```text
1. Host initializes SQ entries and CQ commit words.
2. Host programs SQ/CQ base, depth, and stride.
3. Host writes command payloads into SQ memory.
4. Host writes each command VALID word last.
5. Host advances CSR_SQ_TAIL by the number of visible commands.
6. Host writes CSR_QUEUE_COMMAND.START_QUEUE.
7. Hardware drains commands one at a time in SQ order.
8. Hardware writes one CQ record per completed command.
9. Host observes CSR_CQ_TAIL or polls CQ commit words.
10. Host advances CSR_CQ_HEAD after consuming CQ records.
```

### 20.2 Doorbell While Queue Is Active

P20 allows the host to advance `CSR_SQ_TAIL` while the queue is active because `CSR_SQ_TAIL` is host-owned.

Recommended first validation policy:

```text
P20C/P20D write all SQ entries before START_QUEUE.
Dynamic doorbell while active can remain future validation.
```

This keeps P20 focused on deterministic multi-entry drain first.

---

## 21. Suggested RTL Delta for Later P20C/P20D

P20A/P20B do not implement RTL, but the expected RTL delta should remain small.

Likely modified RTL:

```text
rtl/sequencer/ai_accel_queue_fetch_controller.sv
rtl/top/ai_accel_subsys_csr_top.sv, only if additional pulse plumbing is needed
```

Likely queue-controller additions:

```text
drain_active_q
stop_pending_q
active_cmd_stop_after_this_q
cmds_completed_this_session_q
Q_CHECK_CONTINUE state or equivalent branch after Q_ADVANCE_POINTERS
per-command P17/P18 sticky-clear pulse generation
multi-command pointer update loop
```

No new RTL modules are expected for P20C/P20D.

---

## 22. UVM Validation Plan and P20 Closure

P20 was implemented and validated as a representative in-order queue drain extension above the P19 queue controller.

Final P20 milestone split:

```text
P20A: Multi-entry queue drain spec
P20B: Queue controller auto-continue policy
P20C: Two-command DMA recipe queue smoke
P20D: DMA + Direct Stream + C RMW mixed queue smoke
P20E: SQ/CQ wrap-around representative validation
P20F: STOP_AFTER_THIS / STOP_QUEUE behavior
P20G: Full regression integration
P20H: Documentation closure
```

### 22.1 P20C Two-Command DMA Recipe Queue Smoke

Validated test:

```text
ai_accel_subsys_csr_queue_two_command_dma_smoke_test
```

Validated coverage:

```text
one START_QUEUE kick
two visible SQ command entries
RUN_UNTIL_EMPTY auto-continues from SQ[0] to SQ[1]
two CQ completion records are committed in order
SQ_HEAD advances by 2
CQ_TAIL advances by 2
final DMA destination memory compare passes
```

### 22.2 P20D Mixed DMA / Direct Stream / C RMW Queue Smoke

Validated test:

```text
ai_accel_subsys_csr_queue_mixed_dma_ds_c_rmw_smoke_test
```

Validated coverage:

```text
one START_QUEUE kick
SQ[0] DMA descriptor recipe -> CQ[0]
SQ[1] Direct Stream descriptor recipe -> CQ[1]
SQ[2] C RMW two-slot partial-K descriptor recipe -> CQ[2]
GEMM_ENABLE_C_RMW_ACCUM=1 for the C RMW command
lower-level P17/P16/P15/P18 state is cleared/snapshotted per command
final C RMW DMA destination memory compare passes
```

### 22.3 P20E SQ/CQ Physical Wrap Validation

Validated test:

```text
ai_accel_subsys_csr_queue_wraparound_smoke_test
```

Validated coverage:

```text
SQ_DEPTH = 4
CQ_DEPTH = 4
logical SQ counter 3 -> physical SQ[3]
logical SQ counter 4 -> physical SQ[0]
logical CQ counter 3 -> physical CQ[3]
logical CQ counter 4 -> physical CQ[0]
CQ[3] and CQ[0] completion records commit
untouched CQ[1] and CQ[2] remain invalid
```

### 22.4 P20F Stop Behavior Validation

Validated test:

```text
ai_accel_subsys_csr_queue_stop_behavior_smoke_test
```

Validated coverage:

```text
CMD_CONTROL.STOP_AFTER_THIS stops after the marked command
CSR_QUEUE_COMMAND.STOP_QUEUE requests graceful stop after the active command
active command is not cancelled
completion record for the active command commits normally
next SQ command is not consumed after graceful stop
STOPPED_AFTER_COMMAND sticky status is set
```

## 23. Full Regression Plan and Result

P20G adds a small representative subset to full regression.

P20G full-regression representatives:

```text
csr_queue_two_command_dma_case102
csr_queue_mixed_dma_ds_c_rmw_case208
csr_queue_wraparound_case102
csr_queue_stop_behavior_case102
```

Count increase:

```text
Before P20G: 113
After P20G : 117
```

Full regression after P20G:

```text
TOTAL : 117
PASS  : 117
FAIL  : 0
```

This remains a representative regression, not an exhaustive queue stress suite.

## 24. P20 Closure Criteria

P20 is complete when:

```text
P20A/P20B design policy is documented
RUN_UNTIL_EMPTY auto-drain is implemented
multi-entry SQ drain is validated
multiple CQ records are committed in order
SQ_HEAD/CQ_TAIL advance by the number of committed commands
CQ full stall/recovery works at command boundaries
physical SQ/CQ wrap is validated
STOP_QUEUE / STOP_AFTER_THIS behavior is validated
full regression passes with P20 representatives
no BRAM / GEMM / DMA / frontend datapath changes are required
```

P20G closure status:

```text
all P20 closure criteria satisfied
full regression 117/117 PASS
```

## 25. Interview Summary

P20 is the step that turns P19 from a single-command queue wrapper into a real in-order command queue.

Concise explanation:

```text
P19 proved one SQ command can be fetched, executed through P17/P16/P15, and completed through P18 into one CQ slot.
P20 keeps one active command at a time, but loops that path until the submission queue is empty.
That validates realistic head/tail queue drain, CQ backpressure, physical ring wrap, and graceful stop behavior without introducing multi-outstanding or out-of-order complexity.
```

The main design advantage is that P20 increases host-interface realism while preserving the single-person project scale and the already validated datapath hierarchy.

P20G final result:

```text
TOTAL : 117
PASS  : 117
FAIL  : 0
```

## 26. P23 Event-Driven Queue-Drain Validation

P23 reuses the P20 multi-entry in-order drain model from an event-driven host-runtime perspective.

Additional validation from P23:

```text
P23D validates two-command in-order drain through a host runtime that waits on P22 event notification before consuming CQ records.
P23E validates that runtime-appended commands still complete in order without a second START_QUEUE.
P23F validates CQ-full recovery by consuming CQ and advancing CQ_HEAD, then allowing the in-order drain loop to resume.
P23F validates STOP_QUEUE interaction with a pending runtime-appended SQ entry.
```

Validated P23 full-regression representatives that exercise P20 drain behavior:

```text
csr_event_driven_multi_command_queue_drain_case102
csr_event_driven_runtime_append_case102
csr_event_driven_cq_full_stop_error_case102
```

The P20 single-active-command and in-order CQ completion policies remain unchanged.  P23 only changes the UVM host programming style: the host runtime waits on event notification, consumes CQ, advances CQ_HEAD, and W1C-acks event bits.

