# P26 Queue Lifecycle / Soft Reset / Session Reinitialization Prototype Spec

## 1. Purpose

This document defines the P26A/P26B queue lifecycle / soft-reset / session reinitialization prototype and CSR policy freeze for the AI Accelerator Subsystem.

P17 through P25 established a host-programmable accelerator runtime stack:

```text
host-visible SQ command entry
    -> P19/P20/P21 queue controller
    -> P17 descriptor fetch
    -> P16 recipe sequencer
    -> P15 job sequencer
    -> selected GEMM / DMA / frontend datapath
    -> P18 completion writeback
    -> host-visible CQ completion record
    -> P22 event notification
    -> P23 event-driven host runtime
    -> P24 queue timeout / watchdog recovery
    -> P25 runtime stress / robustness validation
```

P25 proved that repeated sessions, runtime append timing, CQ consume timing variation, STOP_QUEUE handling, timeout-triggered recovery, and final queue/event cleanliness can compose without changing the hardware datapath.

P26 formalizes the lifecycle contract that sits around those flows:

```text
initialize queue/event state
start a queue session
observe normal drained / stopped / error terminal status
consume and recycle CQ records
clear event / queue / lower-level sticky state
choose whether to preserve pending SQ work or discard the session
reinitialize the queue runtime context
restart a known-good command without full reset
```

The P26A goal is not to add a new datapath feature.  The goal is to define a precise host-visible cleanup and soft-reset policy so the driver-style runtime can move between sessions deterministically after normal completion, graceful stop, timeout/error recovery, or intentional session discard.  P26B freezes the first CSR policy for that lifecycle: the existing P19 queue CSR window, P22 event CSR window, and existing lower-level clear commands are sufficient for the first lifecycle implementation, so no new P26 CSR window or new command bit is required.

Current baseline entering P26A:

```text
P25 runtime stress / robustness closure:
  TOTAL : 135
  PASS  : 135
  FAIL  : 0
```

---

## 2. Baseline Before P26

The validated baseline includes:

```text
P17 memory-backed descriptor fetch
P18 memory-backed completion writeback
P19 host-visible SQ/CQ command queue prototype
P20 multi-entry in-order queue drain
P21 runtime doorbell / live queue service
P22 event notification / interrupt-lite CSR layer
P23 event-driven UVM host runtime helper
P24 queue timeout / watchdog and event-driven recovery
P25 runtime stress / robustness helper and representative stress tests
CQ completion records committed into host-visible completion memory
SQ_HEAD / CQ_TAIL pointer advancement after completion commit
CQ_HEAD host recovery during active queue service
STOP_QUEUE / STOP_AFTER_THIS graceful command-boundary stop behavior
QUEUE_ERROR_EVENT based runtime wake-up and cleanup
COMMAND_TIMEOUT_ERROR structured queue error reporting
final queue/event/sticky-state cleanliness validation
full regression 135/135 PASS after P25F/P25G
```

P26 must preserve:

```text
one active command at a time
in-order command execution
in-order completion production
P17 descriptor format
P18 completion record format
P19 SQ entry format
P19/P20/P21 queue CSR window
P22 event CSR window
P23 host runtime programming model
P24 timeout / watchdog reporting model
P25 runtime stress behavior
BRAM / GEMM / DMA / AXI-Stream / Direct Stream datapath behavior
```

P26 should be implemented first as a lifecycle policy and UVM runtime-helper validation.  It should not require BRAM, GEMM, DMA, AXI-Stream, Direct Stream, descriptor-format, completion-format, SQ-format, CQ-format, or CSR-address changes for P26A.

---

## 3. P26 Design Intent

P19 through P25 answer how commands are submitted, executed, completed, observed, stopped, timed out, and stress-tested.  P26 answers the remaining driver-lifecycle question:

```text
After a queue session reaches drained, stopped, or error status,
what exact sequence makes the runtime context safe to reuse without a full reset?
```

Without a lifecycle spec, tests can use helper-specific cleanup sequences that pass individually but are not a clear software contract.  P26 turns those cleanup sequences into a documented state machine and a set of reusable host-runtime policies.

Concise intent:

```text
P26 defines the queue session lifecycle around the validated SQ/CQ/event/runtime stack.
It separates work-preserving restart from session-discard soft reset, defines what state is host-owned versus hardware-owned, and validates that a driver-like runtime can reinitialize and restart without relying on global reset.
```

The practical value is to make the accelerator feel less like a one-shot testbench block and more like a small host-controlled device with a repeatable lifecycle.

---

## 4. P26A Scope

### 4.1 Included

P26A defines:

```text
queue lifecycle state model
session start / terminal status / cleanup policy
soft-reset versus full-reset boundary
normal drained-session cleanup
STOP_QUEUE stopped-session cleanup
timeout/error-session cleanup
work-preserving restart policy
session-discard reinitialization policy
SQ/CQ pointer reset versus pointer-preserve policy
SQ/CQ memory recycle policy
event pending clear / enable / re-arm policy
queue done/error/reject sticky clear policy
lower-level P17/P18/P16/P15/P14 sticky clear policy
host-runtime helper extension direction
P26B/P26C/P26D/P26E/P26F/P26G/P26H validation plan
```

### 4.2 Not Included

P26A does not include:

```text
RTL implementation
CSR RTL changes
new CSR addresses
new SQ or CQ entry format
new descriptor format
new completion record size
new interrupt/event bit allocation
new timeout CSR field
new hardware abort of an active command
preemption
command cancellation rollback
multi-outstanding queue execution
out-of-order completion
cache-coherent host memory ordering
Linux driver
C software driver
UVM RAL model
BRAM / scratchpad memory clear
GEMM datapath reset beyond existing global reset
DMA / AXI-Stream / Direct Stream datapath changes
```

P26A is a specification milestone.  P26B freezes the first implementation policy: reuse existing queue/event/lower-level clear and pointer-reset mechanisms, do not allocate a new P26 CSR window, and do not add a new lifecycle command bit.

---

## 5. Fixed P26 Design Decisions

```text
Lifecycle location             : host runtime helper and queue CSR policy
Hardware queue model           : existing P19/P20/P21 queue controller
Notification model             : existing P22 event CSR / event_irq semantics
Runtime model                  : existing P23 event-driven host runtime style
Timeout model                  : existing P24 CMD_TIMEOUT_CYCLES watchdog policy
Stress baseline                : existing P25 multi-session / STOP / timeout stress behavior
Command execution              : one active command at a time
Completion order               : in-order CQ records
SQ entry format                : existing P19 64-byte SQ command entry
CQ entry format                : existing P18 64-byte completion record
Soft reset scope               : queue/event/lifecycle-visible control state only
Full reset scope               : existing dma_rst_n / subsystem reset behavior
Queue pointer reset            : only while queue is idle / terminal
SQ/CQ memory recycle           : host responsibility
Event pending/clear            : existing P22 W1C / CLEAR_EVENT_PENDING policy
Lower-level sticky clear        : explicit host-runtime cleanup when required
BRAM / GEMM / DMA / frontend   : unchanged
```

P26 does not redefine the command execution pipeline.  It defines when a previous session is considered closed and when a new session is safe to start.

---

## 6. Lifecycle State Model

P26A models the host-visible queue lifecycle using these abstract states:

```text
UNINITIALIZED
  Queue/event memory and CSR context have not been prepared for the current test/session.

READY_IDLE
  Queue configuration is valid, event policy is armed or intentionally disabled,
  no queue_busy is active, and the host may publish SQ commands.

RUNNING
  START_QUEUE has been accepted or live service is active.
  The queue may consume SQ commands and produce CQ records.

DRAINED_TERMINAL
  The queue reached SQ empty cleanly and reported drained status.

STOPPED_TERMINAL
  The queue stopped at a command boundary because of STOP_QUEUE,
  STOP_AFTER_THIS, or one-command service policy.

ERROR_TERMINAL
  The queue reported queue error/reject status, including timeout.

CLEANUP
  Host is consuming CQ records, clearing event pending bits,
  clearing queue/lower sticky state, and choosing preserve or discard policy.

REINITIALIZED
  Host has completed cleanup, and the next START_QUEUE or doorbell sequence
  can be issued without full reset.
```

Representative transitions:

```text
UNINITIALIZED     -> READY_IDLE        : host lifecycle init
READY_IDLE        -> RUNNING           : START_QUEUE accepted
RUNNING           -> DRAINED_TERMINAL  : SQ empty at command boundary
RUNNING           -> STOPPED_TERMINAL  : STOP_QUEUE / STOP_AFTER_THIS terminal
RUNNING           -> ERROR_TERMINAL    : queue error / timeout / lower-level error
DRAINED_TERMINAL  -> CLEANUP           : host observes drained event/status
STOPPED_TERMINAL  -> CLEANUP           : host observes stopped event/status
ERROR_TERMINAL    -> CLEANUP           : host observes error event/status
CLEANUP           -> REINITIALIZED     : selected cleanup policy completes
REINITIALIZED     -> READY_IDLE        : host arms next session
```

P26A treats these as software-visible lifecycle states, not necessarily new RTL FSM states.

---

## 7. Soft Reset Boundary

P26A uses "soft reset" to mean a host-visible queue runtime reinitialization sequence, not a global hardware reset.

### 7.1 Soft Reset May Clear or Reinitialize

```text
queue done sticky bits
queue error sticky bits
queue reject sticky bits
queue debug counters and last-command snapshots
queue pointers, only when queue is idle and session-discard is intended
event pending bits
event debug counters / snapshots
host-owned local runtime shadows
SQ/CQ memory commit words used by the session, by host memory writes
lower-level sticky status required by the failed path
```

### 7.2 Soft Reset Must Not Clear

```text
BRAM scratchpad contents
GEMM internal datapath through a hardware reset
DMA / frontend in-flight transactions
accepted active command context while queue_busy is high
SQ/CQ memory payload by hardware
descriptor memory by hardware
destination/result memory by hardware
global CSR reset defaults
```

### 7.3 Full Reset Remains Separate

Full reset is the existing `dma_rst_n` / subsystem reset behavior.  It resets CSR storage and lower-level RTL state according to the existing reset policy.  P26 soft reset is intentionally narrower and should be usable while clocks continue and after the queue has already reached an idle terminal state.

---

## 8. Session Cleanup Classes

P26A defines three cleanup classes.

### 8.1 Work-Preserving Cleanup

Work-preserving cleanup keeps pending SQ entries intact.

Use cases:

```text
STOP_QUEUE stopped while SQ_TAIL still contains pending work
RUN_UNTIL_EMPTY=0 one-command service leaves additional SQ entries pending
host wants to resume from current SQ_HEAD / SQ_TAIL without rebuilding SQ memory
```

Policy:

```text
do not reset SQ_HEAD / SQ_TAIL
do not clear pending SQ command VALID words
consume all committed CQ records from the completed command(s)
advance CSR_CQ_HEAD after CQ consumption
clear stopped/drained event bits that were handled
clear queue done sticky bits as needed
leave queue error sticky bits zero
re-arm event enables and global IRQ if event-driven service should continue
issue START_QUEUE again when the host wants to continue pending work
```

### 8.2 Session-Discard Cleanup

Session-discard cleanup throws away pending SQ/CQ runtime context and starts a new session from a clean pointer base.

Use cases:

```text
timeout/error recovery when preserving old SQ contents is unsafe
test wants deterministic new session indexes
host intentionally abandons pending SQ work
host changes SQ/CQ base/depth/stride configuration
```

Policy:

```text
queue must be idle / terminal before pointer reset
consume or intentionally discard any visible CQ records according to test policy
clear CQ commit words that may be reused
clear SQ command VALID words that may be reused
clear queue done/error/reject sticky bits
clear event pending bits and event counters if needed
clear lower-level sticky status required by the failed path
write RESET_QUEUE_POINTERS only while queue_busy is zero
program or reprogram SQ/CQ base/depth/stride/control while idle
set SQ_TAIL to the new produced count after writing fresh commands
re-arm events before starting the next session
```

### 8.3 Observation-Only Cleanup

Observation-only cleanup reads and records final status without changing pointer state.

Use cases:

```text
debug failure triage
post-test final state reporting
intermediate event handling when more CQ records remain
```

Policy:

```text
read queue status / done / error / reject
read event pending / status / snapshots
read SQ/CQ occupancy and pointer state
do not clear sticky status unless the test explicitly transitions into cleanup
do not reset pointers
do not overwrite SQ/CQ memory
```

---

## 9. Normal Drained-Session Cleanup

A normal drained session is the cleanest lifecycle path.

Expected terminal state:

```text
queue_busy == 0
QUEUE_DRAINED sticky status is set
QUEUE_ERROR status is zero
QUEUE_REJECT status is zero
SQ_HEAD == SQ_TAIL
CQ_TAIL reflects all committed completions
event pending may include QUEUE_DRAINED_EVENT, QUEUE_COMMAND_COMPLETED_EVENT, or CQ_NOT_EMPTY_EVENT
```

Recommended cleanup sequence:

```text
1. Wait for event notification or poll terminal queue status.
2. Read CSR_EVENT_PENDING and CSR_QUEUE_DONE_STATUS.
3. Read CSR_CQ_TAIL and consume all committed CQ records expected by the test.
4. Write CSR_CQ_HEAD after consuming CQ records.
5. W1C clear handled event pending bits.
6. Clear queue done sticky bits if the next session should start from a clean done state.
7. Optionally clear queue counters / debug snapshots.
8. Optionally reset queue pointers if starting a new independent session.
9. Clear or recycle SQ/CQ memory commit words that will be reused.
10. Re-arm EVENT_ENABLE / GLOBAL_IRQ_ENABLE as required.
11. Confirm final clean state before the next START_QUEUE.
```

A drained cleanup should not require lower-level error clear commands because no lower-level error path should be sticky.

---

## 10. STOP_QUEUE Stopped-Session Cleanup

STOP_QUEUE is a clean command-boundary stop, not an error.

Expected terminal state:

```text
queue_busy == 0
STOPPED_AFTER_COMMAND sticky status is set
QUEUE_ERROR status is zero
active command completion may have committed to CQ
runtime-appended SQ entries after the stopped command remain pending
QUEUE_STOPPED_EVENT may be pending
```

### 10.1 Work-Preserving Restart After STOP_QUEUE

This is the preferred STOP_QUEUE lifecycle path.

Recommended sequence:

```text
1. Observe QUEUE_STOPPED_EVENT or STOPPED_AFTER_COMMAND status.
2. Consume any CQ record produced by the active command.
3. Advance CSR_CQ_HEAD after consuming the CQ record.
4. Clear QUEUE_STOPPED_EVENT and completion-related event bits that were handled.
5. Clear queue done sticky bits if required by the test.
6. Do not reset SQ_HEAD / SQ_TAIL.
7. Do not clear the pending SQ command VALID word.
8. Confirm SQ_HEAD != SQ_TAIL if pending work remains.
9. Re-arm events.
10. Issue START_QUEUE to continue with the pending SQ entry.
```

This path validates that STOP_QUEUE suppresses automatic runtime append consumption only for the stopped session, not permanently.

### 10.2 Session-Discard After STOP_QUEUE

If the host decides not to run pending SQ entries:

```text
1. Complete the observation and CQ consumption steps above.
2. Clear handled event and queue done sticky state.
3. Clear pending SQ command VALID words in host memory.
4. Write RESET_QUEUE_POINTERS while queue_busy is zero.
5. Reinitialize SQ/CQ memory and pointer shadows for a new session.
```

P26A requires the test to state explicitly whether STOP_QUEUE cleanup is work-preserving or session-discarding.

---

## 11. Timeout / Error Cleanup

Timeout/error cleanup must be deterministic and must not hide real failures.

Expected terminal state after timeout/error:

```text
queue_busy eventually deasserts
CSR_QUEUE_STATUS.QUEUE_ERROR is visible
CSR_QUEUE_ERROR_STATUS records the error subtype
CSR_QUEUE_ERROR_DETAIL / CSR_QUEUE_ERROR_INDEX identify the failed command when available
QUEUE_ERROR_EVENT may be pending
CQ_TAIL may or may not advance, depending on whether a valid error/timeout completion record committed
lower-level sticky status may remain set depending on the failed path
```

Recommended sequence:

```text
1. Wait for QUEUE_ERROR_EVENT or queue error terminal status.
2. Read CSR_EVENT_PENDING.
3. Read CSR_QUEUE_ERROR_STATUS.
4. Read CSR_QUEUE_REJECT_STATUS.
5. Read CSR_QUEUE_ERROR_DETAIL / CSR_QUEUE_ERROR_INDEX / CSR_QUEUE_LAST_CMD_TAG.
6. Read CSR_CQ_TAIL and inspect the reserved CQ slot if one may have committed.
7. If a valid CQ error/timeout record exists, consume it and advance CSR_CQ_HEAD.
8. W1C clear handled event pending bits.
9. Clear queue error / reject sticky bits.
10. Clear lower-level sticky status associated with the failed path.
11. Clear queue done sticky bits and debug counters if needed.
12. Choose work-preserving restart only if the error policy explicitly allows it.
13. Otherwise perform session-discard cleanup:
    - clear reusable SQ/CQ commit words
    - reset queue pointers while idle
    - reprogram queue configuration if needed
    - re-arm events
14. Submit a known-good timeout-disabled command.
15. Confirm normal CQ completion and final clean state.
```

P26A recommends session-discard cleanup as the default after timeout/error.  Work-preserving error restart is reserved for later validation because it requires careful policy around whether the failed SQ entry was consumed, whether a CQ error record committed, and whether lower-level engines are safely reusable.

---

## 12. Event Cleanup and Re-Arm Policy

P26A reuses the existing P22 event model.

Recommended event cleanup rules:

```text
Use W1C to clear event bits that were handled.
Use CLEAR_EVENT_PENDING during session initialization, cleanup, or discard.
Use CLEAR_EVENT_COUNTERS when debug counters should not carry across sessions.
Do not treat event notification as completion detail.
Always inspect CQ records and queue status for authoritative completion/error detail.
Confirm event_irq / EVENT_IRQ_OUT deasserts after all enabled pending bits are cleared.
Re-arm by leaving or rewriting EVENT_ENABLE and GLOBAL_IRQ_ENABLE before the next session.
```

Event pending capture remains independent of interrupt enable.  A lifecycle cleanup sequence may disable global IRQ during cleanup for deterministic test behavior, but it must re-arm the intended event policy before starting the next event-driven session.

---

## 13. Queue Pointer and Memory Recycle Policy

### 13.1 Pointer Ownership

```text
CSR_SQ_HEAD : hardware-owned consumed-command counter
CSR_SQ_TAIL : host-owned produced-command counter / doorbell
CSR_CQ_HEAD : host-owned consumed-completion counter
CSR_CQ_TAIL : hardware-owned produced-completion counter
```

P26A preserves the monotonic counter model.

### 13.2 Pointer Reset

`RESET_QUEUE_POINTERS` is a session-discard operation.

Allowed only when:

```text
queue_busy == 0
no active command is in flight
host has decided not to preserve pending SQ work
host has consumed or intentionally discarded visible CQ records
reused SQ/CQ memory commit words have been cleared
```

Not allowed when:

```text
queue_busy == 1
active command owns a snapshotted SQ/CQ context
host wants to resume pending SQ work
CQ records still need to be consumed in order
```

### 13.3 SQ Memory Recycle

Before reusing an SQ slot:

```text
host clears or overwrites payload words
host writes CMD_CONTROL.VALID=1 last
host updates CSR_SQ_TAIL only after the command is visible
```

For session-discard cleanup, the host should clear SQ command commit words used by the discarded session so stale VALID bits cannot be consumed accidentally after pointer reset.

### 13.4 CQ Memory Recycle

Before reusing a CQ slot:

```text
host consumes any valid CQ record
host advances CSR_CQ_HEAD
host may clear completion word0 VALID for debug cleanliness
```

For session-discard cleanup, the host should clear CQ commit words in the recycled range.  Pointer reset without CQ memory cleanup can make a stale completion record look like a new completion in later debug or helper code.

---

## 14. Lower-Level Sticky Clear Policy

The queue controller mirrors summary error status, but lower-level blocks may keep their own sticky status.

P26A recommends that lifecycle cleanup explicitly clears the layers that may have participated in the failed command:

```text
P19 queue sticky:
  CSR_QUEUE_DONE_STATUS
  CSR_QUEUE_ERROR_STATUS
  CSR_QUEUE_REJECT_STATUS
  queue debug counters / last-command snapshots

P22 event sticky:
  CSR_EVENT_PENDING
  event debug counters / snapshots when desired

P18 completion writeback sticky:
  completion writeback done / error / reject status

P17 descriptor-fetch sticky:
  descriptor-fetch done / error / reject status

P16 recipe sticky:
  recipe done / error / reject status

P15 job sticky:
  job done / error / reject status

P14 micro-operation sticky:
  done / error / command-reject status when manual or lower path state is visible
```

The cleanup helper may clear a superset of lower-level sticky status for simplicity, as long as it does so while the queue is idle and after diagnostic reads have captured the failure information.

---

## 15. Configuration Reprogramming Policy

Queue base/depth/stride configuration remains host-owned and should be programmed while the queue is idle.

Allowed while idle:

```text
CSR_SQ_BASE_ADDR
CSR_SQ_DEPTH
CSR_SQ_STRIDE
CSR_CQ_BASE_ADDR
CSR_CQ_DEPTH
CSR_CQ_STRIDE
CSR_QUEUE_CONTROL
CSR_EVENT_ENABLE
CSR_EVENT_CONTROL
CSR_EVENT_CQ_THRESHOLD
```

Not allowed or expected to be rejected while busy:

```text
SQ/CQ base changes
SQ/CQ depth changes
SQ/CQ stride changes
RESET_QUEUE_POINTERS
session-discard soft reset
```

Allowed while busy by existing runtime policy:

```text
CSR_SQ_TAIL as runtime append doorbell
CSR_CQ_HEAD after host consumes CQ entries
selected event enable/control changes if the event spec allows them
STOP_QUEUE request
```

P26A does not add new configuration registers.

---

## 16. Host Runtime Helper Direction for P26B/P26C

P26B/P26C should extend the existing event-driven host runtime helper rather than duplicating cleanup sequences in each test.

Recommended helper responsibilities:

```text
lifecycle session initialization
drained-session cleanup
stopped-session work-preserving cleanup
stopped-session discard cleanup
timeout/error diagnostic snapshot
timeout/error discard cleanup
queue pointer reset while idle
SQ/CQ commit-word recycle
event pending W1C / CLEAR_PENDING cleanup
event enable/global re-arm
queue done/error/reject sticky clear
lower-level sticky clear
final reusable-state check
```

Suggested helper API direction:

```systemverilog
task host_rt_lifecycle_init_session(...);
task host_rt_lifecycle_cleanup_drained(...);
task host_rt_lifecycle_cleanup_stopped_preserve(...);
task host_rt_lifecycle_cleanup_stopped_discard(...);
task host_rt_lifecycle_capture_error_snapshot(...);
task host_rt_lifecycle_cleanup_error_discard(...);
task host_rt_lifecycle_reset_pointers_idle(...);
task host_rt_lifecycle_recycle_sq_cq_memory(...);
task host_rt_lifecycle_rearm_events(...);
task host_rt_lifecycle_check_clean_idle(...);
```

The exact names may follow the current project style.  The helper should stay a thin abstraction above existing CSR access helpers, queue programming routines, descriptor-memory helpers, CQ readback routines, event helpers, and result-compare infrastructure.

---


## 17. P26B CSR Policy Freeze / Helper Plan

P26B freezes the lifecycle CSR policy for the first implementation checkpoint.

The decision is:

```text
No new P26 CSR window
No new P26 lifecycle command register
No new queue command bit
No new event pending bit
No SQ entry format change
No CQ completion record format change
No descriptor format change
```

The P26 lifecycle model is implemented by sequencing existing CSR commands and host-memory cleanup operations in a stricter, documented order.

### 17.1 Frozen CSR Resources Used by P26

P26B uses these existing queue CSR resources:

```text
CSR_QUEUE_COMMAND.START_QUEUE
CSR_QUEUE_COMMAND.STOP_QUEUE
CSR_QUEUE_COMMAND.CLEAR_QUEUE_DONE
CSR_QUEUE_COMMAND.CLEAR_QUEUE_ERROR
CSR_QUEUE_COMMAND.CLEAR_QUEUE_COUNTERS
CSR_QUEUE_COMMAND.RESET_QUEUE_POINTERS
CSR_QUEUE_STATUS
CSR_QUEUE_DONE_STATUS
CSR_QUEUE_ERROR_STATUS
CSR_QUEUE_REJECT_STATUS
CSR_QUEUE_ERROR_DETAIL
CSR_QUEUE_ERROR_INDEX
CSR_QUEUE_LAST_CMD_TAG
CSR_SQ_BASE_ADDR / CSR_SQ_DEPTH / CSR_SQ_STRIDE
CSR_SQ_HEAD / CSR_SQ_TAIL
CSR_CQ_BASE_ADDR / CSR_CQ_DEPTH / CSR_CQ_STRIDE
CSR_CQ_HEAD / CSR_CQ_TAIL
CSR_QUEUE_SQ_OCCUPANCY
CSR_QUEUE_CQ_OCCUPANCY
CSR_QUEUE_CQ_SPACE
```

P26B uses these existing event CSR resources:

```text
CSR_EVENT_COMMAND.CLEAR_EVENT_PENDING
CSR_EVENT_COMMAND.CLEAR_EVENT_COUNTERS
CSR_EVENT_STATUS
CSR_EVENT_PENDING W1C
CSR_EVENT_ENABLE
CSR_EVENT_CONTROL
CSR_EVENT_LAST_CAUSE
CSR_EVENT_COUNT
CSR_EVENT_QUEUE_SNAPSHOT0/1
CSR_EVENT_IRQ_COUNT
```

P26B may also use existing lower-level clear mechanisms from the P17/P18/P16/P15/P14 windows when a failed queue command leaves diagnostic sticky state behind.

### 17.2 `RESET_QUEUE_POINTERS` Frozen Lifecycle Policy

`RESET_QUEUE_POINTERS` is frozen as a session-discard operation.

Allowed use:

```text
queue_busy == 0
host has captured diagnostics if the previous session ended in error
host has consumed or intentionally discarded any visible CQ records
host has cleared or will clear recycled SQ command VALID words
host has cleared or will clear recycled CQ commit words
host does not intend to preserve pending SQ work
```

Disallowed use:

```text
queue_busy == 1
active command owns a snapshotted SQ/CQ context
host intends to resume pending SQ entries after STOP_QUEUE
host has not yet consumed CQ records that must remain ordered
```

P26B does not redefine `RESET_QUEUE_POINTERS` as a hardware abort.  It must not be used to cancel an active command or roll back an in-flight descriptor fetch, recipe, GEMM, DMA, or completion writeback operation.

### 17.3 Work-Preserving Restart Policy

Work-preserving restart is frozen as a no-pointer-reset flow.

Representative use case:

```text
STOP_QUEUE accepted while SQ[0] is active
host appends SQ[1] while active
queue completes SQ[0]
queue reports stopped
SQ[1] remains pending
host restarts queue later to consume SQ[1]
```

Frozen policy:

```text
do not write RESET_QUEUE_POINTERS
do not clear pending SQ command VALID words
do not rewrite SQ_HEAD or SQ_TAIL
consume committed CQ records from completed commands
advance CSR_CQ_HEAD after CQ consumption
W1C clear handled event pending bits
clear queue done sticky bits if the helper wants a clean next wait
re-arm events
write START_QUEUE when the host chooses to resume pending work
```

This policy preserves the P21/P25 behavior that STOP_QUEUE suppresses automatic runtime-append consumption only for the stopped session.  It does not discard pending work unless the host explicitly chooses a session-discard cleanup.

### 17.4 Session-Discard Soft-Reset Policy

Session-discard cleanup is frozen as the default policy after timeout/error and as an optional policy after drained or stopped sessions.

Frozen sequence:

```text
1. Confirm queue_busy == 0 or wait for terminal status.
2. Capture queue/event/lower-level diagnostics before clearing sticky state.
3. Consume any valid CQ records that the test intends to preserve.
4. Advance CSR_CQ_HEAD only after consuming those CQ records.
5. W1C clear handled event pending bits or use CLEAR_EVENT_PENDING for full cleanup.
6. Clear queue done/error/reject sticky state with existing queue clear commands.
7. Clear lower-level sticky state required by the failed path.
8. Clear or overwrite recycled SQ command VALID words in host memory.
9. Clear or overwrite recycled CQ commit words in host memory.
10. Write RESET_QUEUE_POINTERS while idle.
11. Reprogram SQ/CQ base/depth/stride/control if the next session changes configuration.
12. Re-arm event enable/global policy.
13. Publish fresh SQ commands by writing VALID last and updating CSR_SQ_TAIL.
14. Start the next session with START_QUEUE.
```

P26B treats this as a soft reset of the queue lifecycle context, not as a global hardware reset and not as a scratchpad clear.

### 17.5 Timeout/Error Diagnostic Ordering

P26B freezes the diagnostic ordering for error cleanup.

Before clearing sticky status, the helper should capture:

```text
CSR_EVENT_PENDING
CSR_QUEUE_STATUS
CSR_QUEUE_DONE_STATUS
CSR_QUEUE_ERROR_STATUS
CSR_QUEUE_REJECT_STATUS
CSR_QUEUE_ERROR_DETAIL
CSR_QUEUE_ERROR_INDEX
CSR_QUEUE_LAST_CMD_TAG
CSR_QUEUE_LAST_CMD_CONTROL
CSR_SQ_HEAD / CSR_SQ_TAIL
CSR_CQ_HEAD / CSR_CQ_TAIL
CSR_QUEUE_SQ_OCCUPANCY / CSR_QUEUE_CQ_OCCUPANCY / CSR_QUEUE_CQ_SPACE
lower-level P17/P18/P16/P15/P14 sticky state when relevant
```

After diagnostics are captured, the helper may clear a superset of lower-level sticky status for deterministic reuse.  Clearing sticky state before diagnostic capture is allowed only in initialization code where no previous failure information is needed.

### 17.6 Event Re-Arm Policy

P26B freezes this event cleanup distinction:

```text
During normal event service:
  use CSR_EVENT_PENDING W1C for handled bits only

During session initialization or session-discard cleanup:
  CLEAR_EVENT_PENDING may be used to clear all stale pending bits
  CLEAR_EVENT_COUNTERS may be used to reset debug counters/snapshots

Before event-driven START_QUEUE:
  program CSR_EVENT_ENABLE for expected lifecycle events
  program CSR_EVENT_CONTROL.GLOBAL_IRQ_ENABLE when the test waits on event_irq / EVENT_IRQ_OUT
```

The helper must not treat event pending bits as completion detail.  CQ records and queue error/status registers remain authoritative.

### 17.7 Helper Implementation Plan

P26C should extend the existing event-driven host runtime / stress helper layer instead of adding a standalone UVM top or a standalone lifecycle CSR block.

Preferred implementation direction:

```text
extend the existing event-driven host runtime helper used by P23/P25
reuse existing CSR access helper tasks
reuse existing SQ command programming helpers
reuse existing descriptor-table programming helpers
reuse existing CQ readback/check helpers
reuse existing event wait / pending decode helpers
reuse existing result compare path
```

Suggested data structures:

```systemverilog
typedef enum int {
  P26_LIFE_CLEAN_DRAINED,
  P26_LIFE_STOPPED_PRESERVE,
  P26_LIFE_STOPPED_DISCARD,
  P26_LIFE_ERROR_DISCARD
} p26_lifecycle_policy_e;

typedef struct {
  bit [31:0] event_pending;
  bit [31:0] queue_status;
  bit [31:0] queue_done_status;
  bit [31:0] queue_error_status;
  bit [31:0] queue_reject_status;
  bit [31:0] queue_error_detail;
  bit [31:0] queue_error_index;
  bit [31:0] queue_last_cmd_tag;
  bit [31:0] queue_last_cmd_control;
  bit [31:0] sq_head;
  bit [31:0] sq_tail;
  bit [31:0] cq_head;
  bit [31:0] cq_tail;
  bit [31:0] sq_occupancy;
  bit [31:0] cq_occupancy;
  bit [31:0] cq_space;
} p26_lifecycle_snapshot_t;
```

Suggested helper tasks:

```systemverilog
task host_rt_lifecycle_capture_snapshot(output p26_lifecycle_snapshot_t snap);
task host_rt_lifecycle_clear_handled_events(bit [31:0] event_mask);
task host_rt_lifecycle_clear_all_events_and_counters();
task host_rt_lifecycle_clear_queue_done();
task host_rt_lifecycle_clear_queue_error_and_reject();
task host_rt_lifecycle_clear_lower_sticky();
task host_rt_lifecycle_recycle_sq_slots(int first_idx, int count);
task host_rt_lifecycle_recycle_cq_slots(int first_idx, int count);
task host_rt_lifecycle_reset_pointers_idle();
task host_rt_lifecycle_rearm_events(bit [31:0] event_mask, bit global_irq_enable);
task host_rt_lifecycle_cleanup_drained(bit reset_pointers);
task host_rt_lifecycle_cleanup_stopped_preserve();
task host_rt_lifecycle_cleanup_stopped_discard();
task host_rt_lifecycle_cleanup_error_discard();
task host_rt_lifecycle_check_clean_idle();
```

The helper should issue separate CSR writes for lifecycle operations where possible.  For example, do not combine `START_QUEUE`, `RESET_QUEUE_POINTERS`, and sticky clear commands in one write.  Separate writes make debug logs easier to read and keep lifecycle sequencing explicit.

### 17.8 P26B Closure Criteria

P26B is complete when:

```text
existing CSR commands are declared sufficient for first lifecycle implementation
no new P26 CSR window is allocated
RESET_QUEUE_POINTERS idle-only session-discard policy is frozen
STOP_QUEUE work-preserving restart policy is frozen
session-discard cleanup ordering is frozen
timeout/error diagnostic-before-clear ordering is frozen
event W1C versus CLEAR_EVENT_PENDING usage is frozen
P26C helper extension direction and task plan are documented
```

P26B does not add regression tests.  Full-regression count remains 135 until P26G integrates P26D/P26E/P26F representatives.

---


## 18. P26C Host Runtime Lifecycle Helper Extension

P26C implements the lifecycle helper API direction frozen by P26B inside the existing UVM host-runtime helper layer.

Implementation location:

```text
tb/uvm/helper/ai_accel_event_driven_host_runtime_stress_helper.sv
```

P26C does not add a standalone lifecycle helper file, a standalone UVM top, RTL, CSR map changes, SQ/CQ format changes, event bits, Tcl changes, or full-regression items.  The existing package already includes the P25 stress helper, so extending that helper preserves the current compile flow.

P26C adds lifecycle-focused helper types:

```systemverilog
typedef enum int unsigned {
    P26_LIFE_CLEAN_DRAINED,
    P26_LIFE_STOPPED_PRESERVE,
    P26_LIFE_STOPPED_DISCARD,
    P26_LIFE_ERROR_DISCARD
} p26_lifecycle_policy_e;

typedef struct {
    logic [31:0] event_pending;
    logic [31:0] event_status;
    logic [31:0] queue_status;
    logic [31:0] queue_done_status;
    logic [31:0] queue_error_status;
    logic [31:0] queue_reject_status;
    logic [31:0] queue_error_detail;
    logic [31:0] queue_error_index;
    logic [31:0] queue_last_cmd_tag;
    logic [31:0] queue_last_cmd_control;
    logic [31:0] sq_head;
    logic [31:0] sq_tail;
    logic [31:0] cq_head;
    logic [31:0] cq_tail;
    logic [31:0] sq_occupancy;
    logic [31:0] cq_occupancy;
    logic [31:0] cq_space;
} p26_lifecycle_snapshot_t;
```

P26C adds these lifecycle helper operations:

```text
host_rt_lifecycle_capture_snapshot
host_rt_lifecycle_wait_idle
host_rt_lifecycle_clear_handled_events
host_rt_lifecycle_clear_all_events_and_counters
host_rt_lifecycle_rearm_events
host_rt_lifecycle_clear_queue_done
host_rt_lifecycle_clear_queue_error_and_reject
host_rt_lifecycle_clear_queue_counters
host_rt_lifecycle_clear_queue_all_sticky
host_rt_lifecycle_clear_lower_sticky
host_rt_lifecycle_recycle_sq_slots
host_rt_lifecycle_recycle_cq_slots
host_rt_lifecycle_consume_visible_cq
host_rt_lifecycle_reset_pointers_idle
host_rt_lifecycle_init_session
host_rt_lifecycle_cleanup_drained
host_rt_lifecycle_cleanup_stopped_preserve
host_rt_lifecycle_cleanup_stopped_discard
host_rt_lifecycle_capture_error_snapshot
host_rt_lifecycle_cleanup_error_discard
host_rt_lifecycle_check_clean_idle
```

The helper keeps lifecycle operations explicit.  Sticky clears, pointer reset, event cleanup, event re-arm, SQ/CQ memory recycle, and lower-level sticky cleanup are intentionally separate helper calls internally so later P26D/P26E/P26F tests can debug the exact lifecycle step that failed.

P26C also adds the missing UVM-side queue command constants required by the frozen P26B policy:

```systemverilog
QUEUE_CMD_CLEAR_COUNTERS = 10
QUEUE_CMD_RESET_POINTERS = 11
```

These are added only to the UVM CSR access helper constant table.  They reflect the existing canonical queue command policy and do not allocate new CSR bits.

P26C closure criteria:

```text
P26 lifecycle helper types are available to tests
P26 drained-session cleanup helper is implemented
P26 stopped-session work-preserving cleanup helper is implemented
P26 stopped-session discard cleanup helper is implemented
P26 timeout/error session-discard cleanup helper is implemented
P26 idle-only RESET_QUEUE_POINTERS helper is implemented
P26 SQ/CQ memory recycle helpers are implemented
P26 lower-level sticky clear helper is implemented
No package / compile Tcl change is required
No regression item is added at P26C
```

---
## 19. P26 UVM Validation Plan

Recommended P26 milestone split:

```text
P26A: Queue lifecycle / soft-reset prototype spec                     PASS
P26B: Lifecycle CSR policy freeze / helper plan                       PASS
P26C: Host runtime lifecycle helper extension                         PASS
P26D: Drained-session cleanup + reinit smoke                          PASS
P26E: STOP_QUEUE stopped-session preserve/restart smoke                IMPLEMENTED / RUN PENDING
P26F: Timeout/error session-discard reinit + valid restart smoke       TODO
P26G: Full regression integration                                     TODO
P26H: Documentation closure                                           TODO
```

### 18.1 P26D Drained-Session Cleanup + Reinit Smoke

Purpose:

```text
run one normal queue session to drained
consume all CQ records
advance CQ_HEAD
clear handled event pending bits
clear queue done sticky bits
optionally reset pointers while idle
reinitialize SQ/CQ memory commit words
submit a second independent valid command
confirm normal completion
confirm final queue/event clean state
```

Suggested test name:

```text
ai_accel_subsys_csr_queue_lifecycle_drained_reinit_smoke_test
```

Expected PASS markers:

```text
[P26D_LIFECYCLE/DRAINED_CLEANUP_PASS]
[P26D_LIFECYCLE/REINIT_PASS]
[P26D_LIFECYCLE/PASS]
```

P26D implementation checkpoint:

```text
Test file: tb/uvm/test/ai_accel_subsys_csr_queue_lifecycle_drained_reinit_smoke_test.sv
Package include: ai_accel_subsys_uvm_pkg.sv P26 lifecycle test block
Regression integration: deferred to P26G
Full regression count remains 135 until P26G
```

### 18.2 P26E STOP_QUEUE Stopped-Session Preserve/Restart Smoke

Purpose:

```text
start SQ[0]
append SQ[1] while active
issue STOP_QUEUE
confirm SQ[1] is pending and not consumed
consume CQ[0]
clear stopped event / queue done sticky status
restart without resetting pointers
complete SQ[1]
then run a separate discard cleanup path:
  clear reusable SQ/CQ memory
  reset queue pointers while idle
  reinitialize and prove a fresh command starts at clean pointer state
```

Suggested test name:

```text
ai_accel_subsys_csr_queue_lifecycle_stop_restart_smoke_test
```

Expected PASS markers:

```text
[P26E_LIFECYCLE/PRESERVE_PASS]
[P26E_LIFECYCLE/RESTART_PASS]
[P26E_LIFECYCLE/PASS]
```

P26E implementation checkpoint:

```text
Test: ai_accel_subsys_csr_queue_lifecycle_stopped_preserve_restart_smoke_test
Package include: ai_accel_subsys_uvm_pkg.sv P26 lifecycle test block
Regression integration: deferred to P26G
Full regression count remains 135 until P26G
```

### 18.3 P26F Timeout/Error Session-Discard Reinit + Valid Restart Smoke

Purpose:

```text
submit finite-timeout command
observe COMMAND_TIMEOUT_ERROR and QUEUE_ERROR_EVENT
capture queue error status/detail/index/tag
consume timeout CQ record if one exists
clear event pending bits
clear queue error/reject sticky bits
clear lower-level sticky state
clear reusable SQ/CQ commit words
reset queue pointers while idle
submit known-good timeout-disabled command
observe normal CQ completion
consume CQ
confirm event pending / queue error / queue reject clean
compare result payload where applicable
```

Suggested test name:

```text
ai_accel_subsys_csr_queue_lifecycle_timeout_reinit_smoke_test
```

Expected PASS markers:

```text
[P26F_LIFECYCLE/ERROR_CAPTURE_PASS]
[P26F_LIFECYCLE/REINIT_PASS]
[P26F_LIFECYCLE/PASS]
```

---

## 20. Full Regression Plan

P26G should add a small representative lifecycle subset to full regression.

Recommended full-regression representatives:

```text
csr_queue_lifecycle_drained_reinit_case102
csr_queue_lifecycle_stop_restart_case102
csr_queue_lifecycle_timeout_reinit_case102
```

Expected count increase:

```text
Before P26G: 135
After P26G : 138
```

This keeps P26 representative rather than exhaustive.  Randomized lifecycle policy selection, randomized pointer reset timing, and broader lower-level error matrices can remain future extensions.

---

## 21. P26 Closure Criteria

P26 is complete when:

```text
P26A lifecycle / soft-reset prototype spec is complete
P26B freezes whether existing CSR commands are sufficient
P26C lifecycle helper extension is implemented
normal drained-session cleanup and reinit passes
STOP_QUEUE work-preserving restart passes
STOP_QUEUE discard cleanup and pointer reset passes
timeout/error discard cleanup and valid restart passes
P26 representatives are integrated into full regression
full regression passes at the updated count
README / CSR / queue / event / runtime / timeout / stress docs record P26 closure
uvm_regression.list records the updated regression items
no BRAM / GEMM / DMA / frontend datapath changes are required
```

---

## 22. Relationship to Existing Specs

P26 composes earlier validated policies rather than replacing them:

```text
P19 command/completion queue:
  SQ/CQ entry formats, pointer ownership, in-order completion, RESET_QUEUE_POINTERS

P20 multi-entry queue drain:
  repeated command execution with one active command at a time

P21 runtime doorbell / live queue service:
  host-owned SQ_TAIL and CQ_HEAD writes during active service

P22 event notification / interrupt-lite:
  sticky event pending, enable/global-enable, W1C clear/re-arm

P23 event-driven host runtime:
  software-like submit / wait / consume / clear / re-arm model

P24 queue timeout / watchdog:
  CMD_TIMEOUT_CYCLES, COMMAND_TIMEOUT_ERROR, QUEUE_ERROR_EVENT recovery

P25 runtime stress / robustness:
  repeated sessions, STOP_QUEUE with pending append, delayed CQ consume, timeout recovery, final clean checks
```

P26's value is turning the cleanup pieces into an explicit lifecycle contract: when to preserve work, when to discard a session, when pointer reset is legal, and what must be clean before the next start.

---

## 23. Interview Notes

A concise interview explanation:

```text
P26 was my queue lifecycle and soft-reset milestone.  After P25, the runtime stack could already survive multiple sessions, live appends, STOP_QUEUE, delayed CQ consumption, and timeout recovery.  P26 formalized the cleanup contract around those behaviors.  I separated work-preserving restart from session-discard reinitialization, defined when RESET_QUEUE_POINTERS is legal, required the host to consume or recycle CQ records before advancing CQ_HEAD or resetting pointers, and made event/queue/lower-level sticky cleanup explicit.  This makes the subsystem behave more like a host-controlled accelerator device: it can close a session, recover from stop or timeout, re-arm events, and start a new command without relying on a full reset.
```


---

## P26F Timeout/Error Reinit Smoke Fix Note

P26F timeout/error lifecycle recovery must distinguish queue-level cleanup from lower-level quiescence.
A command timeout is reported at the queue level, but it does not introduce abort, cancellation, rollback, or preemption for an already-launched P17/P16/P15/P18 path.  Therefore a host-runtime lifecycle recovery sequence may need to wait for lower-level busy indicators to deassert before issuing the known-good recovery `START_QUEUE`.

Frozen P26F recovery refinement:

```text
Queue/event sticky cleanup is necessary but not always sufficient for immediate restart.
After timeout cleanup, wait for lower-level busy summary to clear.
Clear late lower/event/queue sticky status after quiescence.
Re-arm events and then submit the timeout-disabled recovery command.
```

This refinement preserves the P26 policy of no new CSR window, no new event bit, no abort protocol, and no datapath/BRAM change.
