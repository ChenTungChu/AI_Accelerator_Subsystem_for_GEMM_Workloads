# P22 Event Notification / Interrupt-Lite Spec

## 1. Purpose

This document defines the P22 event notification / interrupt-lite layer for the AI Accelerator Subsystem.

P19 introduced a host-visible submission queue and completion queue around the existing P17 descriptor-fetch and P18 completion-writeback path:

```text
host-visible SQ command entry
    -> P19 queue controller
    -> P17 descriptor fetch
    -> P16 recipe sequencer
    -> P15 job sequencer
    -> selected datapath
    -> P18 completion writeback
    -> host-visible CQ completion record
```

P20 extended the P19 queue from a single-command queue wrapper into a multi-entry in-order queue drain:

```text
SQ[0] -> execute -> CQ[0]
SQ[1] -> execute -> CQ[1]
SQ[2] -> execute -> CQ[2]
...
```

P21 extended the P20 batch drain model into runtime live queue service:

```text
host starts the queue with one or more visible SQ entries
hardware executes one command at a time
while hardware is active, host may append additional SQ entries
host publishes appended entries by updating CSR_SQ_TAIL
hardware observes the new SQ_TAIL only at command boundaries
```

P22 adds a small software-visible event notification / interrupt-lite layer above the validated queue completion and runtime-service semantics.  The goal is to let software observe queue progress without polling every queue CSR or CQ memory location continuously.

The notification layer is intentionally small:

```text
queue completion / drained / stopped / error / CQ backpressure / runtime doorbell events
    -> sticky event pending bits
    -> per-event interrupt enable mask
    -> optional event counter and last-cause snapshot
    -> one shared event_irq output when globally enabled
```

P22 does not replace the completion queue.  The completion record in CQ memory remains the authoritative per-command result.  P22 only adds a summary notification mechanism that tells software that something worth checking has happened.

Baseline entering P22A/P22B:

```text
P21H runtime doorbell / live queue service closure:
  TOTAL : 121
  PASS  : 121
  FAIL  : 0
```

Current closure after P22G/P22H:

```text
P22 event notification / interrupt-lite closure:
  TOTAL : 125
  PASS  : 125
  FAIL  : 0
```

---

## 2. Baseline Before P22

The validated baseline includes:

```text
P17 memory-backed descriptor fetch
P18 memory-backed completion writeback
P19 host-visible SQ/CQ queue prototype
P20 multi-entry in-order queue drain
P21 runtime doorbell / live queue service
completion records committed into CQ memory
SQ_HEAD / CQ_TAIL pointer advancement after completion commit
CQ full stall and host CQ_HEAD recovery during active service
STOP_AFTER_THIS / STOP_QUEUE graceful stop behavior
SQ/CQ physical wrap validation
full regression 121/121 PASS after P21G
```

P22 builds only on the existing queue status, completion-commit, CQ-full, and runtime-doorbell observation points.

P22 must preserve:

```text
one active command at a time
in-order command execution
in-order completion production
P17 descriptor format
P18 completion record format
P19 SQ entry format
P19/P20/P21 queue CSR semantics
BRAM / GEMM / DMA / AXI-Stream / Direct Stream datapath behavior
```

P22 may add one notification output pin in the CSR wrapper top, but it must not require changes to the datapath blocks.

---

## 3. P22 Design Intent

P19/P20/P21 gave software a realistic queue model:

```text
host submits commands through SQ memory
hardware executes commands in order
hardware writes completion records into CQ memory
host can append SQ entries while the queue is active
host consumes completion records through CQ memory
```

Without P22, software discovers progress by polling:

```text
CSR_QUEUE_STATUS
CSR_QUEUE_DONE_STATUS
CSR_QUEUE_ERROR_STATUS
CSR_CQ_TAIL
CQ memory commit words
```

P22 adds a notification summary:

```text
if a command completion commits to CQ:
  set QUEUE_COMMAND_COMPLETED_EVENT pending
  optionally assert event_irq

if the queue drains to empty:
  set QUEUE_DRAINED_EVENT pending
  optionally assert event_irq

if the queue stops gracefully:
  set QUEUE_STOPPED_EVENT pending
  optionally assert event_irq

if the queue enters error:
  set QUEUE_ERROR_EVENT pending
  optionally assert event_irq

if runtime doorbell activity is observed:
  set RUNTIME_DOORBELL_EVENT / RUNTIME_APPEND_CONSUMED_EVENT pending
  optionally assert event_irq
```

The host still reads CQ records for detailed completion information.

Concise intent:

```text
P22 is a lightweight event-notification layer above P21 live queue service.
It summarizes queue progress through sticky CSR event bits and an optional single interrupt-lite output.
```

---

## 4. P22A Scope

### 4.1 Included

P22A defines:

```text
event notification / interrupt-lite design intent
event sources
pending / enable / global-enable policy
interrupt-lite output policy
acknowledge / clear behavior
relationship to CQ completion records
relationship to P19/P20/P21 queue pointer advancement
runtime doorbell notification behavior
CQ full stall / CQ space recovery notification behavior
error and stop notification behavior
UVM validation plan
full-regression closure plan
```

### 4.2 Not Included

P22A does not include:

```text
RTL implementation
CSR RTL changes
UVM tests
interrupt controller integration
MSI/MSI-X
PCIe integration
Linux driver
C software driver
UVM RAL model
multi-vector interrupt allocation
interrupt moderation with timers
cache-coherent host memory ordering
multi-outstanding queue execution
out-of-order completion
command cancellation or preemption
BRAM / GEMM / DMA / frontend datapath changes
```

P22A is a specification milestone only.

---

## 5. P22B CSR Map Scope

P22B freezes the software-visible event notification CSR window.

The canonical CSR register map, register access types, reset values, and bit definitions are recorded in:

```text
docs/axi_lite_csr_control_plane_spec.md
```

P22B adds a new CSR window after the P19/P20/P21 queue window:

```text
P22 event notification CSR window: 0x600 - 0x63C
```

P22B is still documentation-only.  It does not add RTL, UVM tests, Tcl scripts, README updates, or regression-list entries by itself.

---

## 6. Fixed P22 Design Decisions

```text
Event source granularity        : queue-level summary events
Completion detail source        : existing P18/P19/P20/P21 CQ completion records
Interrupt output                : optional single event_irq output from CSR wrapper
Interrupt enable default        : disabled after reset
Pending bits                    : sticky until host clears them
Event capture                   : pending bits set even when interrupt output is disabled
Interrupt mode                  : default level while enabled pending bits are non-zero
Interrupt vectors               : one shared output in P22
MSI/MSI-X                       : not included
CQ record format                : unchanged
SQ/CQ pointer model             : unchanged
Runtime doorbell semantics      : unchanged from P21
BRAM / GEMM / DMA / frontend    : unchanged
```

P22 intentionally starts with one shared notification output rather than a full interrupt controller.

---

## 7. Event Sources

P22 defines the following first event sources:

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

### 7.1 Queue Command Completed Event

Generated when a queue command's completion record has committed and the queue controller advances `CSR_CQ_TAIL`.

```text
P18 completion record commit succeeds
CQ_TAIL advances
QUEUE_COMMAND_COMPLETED_EVENT pending bit is set
```

This event is tied to completion visibility, not merely to recipe done.

### 7.2 Queue Drained Event

Generated when the queue reaches SQ empty and enters a drained terminal state.

```text
SQ_HEAD == latest SQ_TAIL at command boundary
QUEUE_DRAINED sticky status is set
QUEUE_DRAINED_EVENT pending bit is set
```

### 7.3 Queue Stopped Event

Generated when the queue stops gracefully after an active command due to:

```text
CSR_QUEUE_COMMAND.STOP_QUEUE
CMD_CONTROL.STOP_AFTER_THIS
RUN_UNTIL_EMPTY=0 one-command service policy
```

The event is not an error.  It is a notification that the queue stopped at a clean command boundary.

### 7.4 Queue Error Event

Generated when a queue-level error or reject status becomes sticky.

Examples:

```text
command fetch error
command validation error
descriptor-fetch error propagated to queue level
recipe error propagated to queue level
completion writeback error
invalid queue configuration reject
START_QUEUE while sticky error is uncleared
```

The event layer does not redefine error policy.  It only mirrors the queue error event into `CSR_EVENT_PENDING`.

### 7.5 CQ Not Empty / Threshold Events

Generated when the completion queue becomes non-empty or crosses a configured occupancy threshold.

Recommended first policy:

```text
CQ_NOT_EMPTY_EVENT is generated when CQ occupancy transitions from zero to non-zero at an event sampling point.
CQ_THRESHOLD_EVENT is generated when CSR_EVENT_CQ_THRESHOLD != 0 and CQ occupancy is >= threshold.
```

These events are summary notifications only.  The host still reads CQ entries to consume completions.

### 7.6 CQ Full Stall / CQ Space Recovered Events

Generated around queue backpressure:

```text
CQ_FULL_STALL_EVENT:
  queue controller reaches a command boundary
  SQ still has work or runtime append is visible
  CQ space is zero
  controller stalls before consuming the next SQ entry

CQ_SPACE_RECOVERED_EVENT:
  controller is stalled on CQ full
  host advances CSR_CQ_HEAD
  CQ space becomes non-zero
```

This event pair is useful for P21 live service because the host can recover progress by consuming CQ entries and updating `CSR_CQ_HEAD` while the queue remains active.

### 7.7 Runtime Doorbell Events

Generated around P21 live-service behavior:

```text
RUNTIME_DOORBELL_EVENT:
  host updates CSR_SQ_TAIL while queue_busy=1

RUNTIME_APPEND_CONSUMED_EVENT:
  a command that became visible through runtime SQ_TAIL update is later accepted at a command boundary
```

The active command's snapshot remains unaffected by these events.

### 7.8 Test Event

Generated by a software command for CSR smoke validation.

```text
CSR_EVENT_COMMAND.FORCE_TEST_EVENT = 1
```

The test event allows standalone validation of pending / enable / clear / irq behavior before connecting real queue event sources.

---

## 8. Pending / Enable / IRQ Policy

### 8.1 Pending Capture

Event pending bits are sticky.

```text
hardware event source fires -> set CSR_EVENT_PENDING bit
host W1C write             -> clear selected pending bits
CLEAR_EVENT_PENDING command -> clear all pending bits
```

Pending capture is independent of interrupt enable.

```text
CSR_EVENT_ENABLE bit = 0:
  pending still captures
  event_irq does not assert from that bit
```

### 8.2 Interrupt Enable

`CSR_EVENT_ENABLE` masks which pending bits contribute to `event_irq`.

```text
irq_eligible = |(CSR_EVENT_PENDING & CSR_EVENT_ENABLE)
```

### 8.3 Global Enable

`CSR_EVENT_CONTROL.GLOBAL_IRQ_ENABLE` gates the shared output.

```text
event_irq = GLOBAL_IRQ_ENABLE && irq_eligible
```

After reset:

```text
CSR_EVENT_PENDING = 0
CSR_EVENT_ENABLE  = 0
GLOBAL_IRQ_ENABLE = 0
event_irq         = 0
```

### 8.4 Level Interrupt Default

The default P22 output mode is level-style:

```text
event_irq remains high while at least one enabled pending bit is set
software clears the pending bit through W1C
if no enabled pending bits remain, event_irq deasserts
```

Pulse mode is reserved for later validation and can remain unimplemented or tied to level mode in the first RTL checkpoint.

---

## 9. Relationship to CQ Completion Records

P22 is not the source of per-command completion detail.

Authoritative completion detail remains:

```text
CQ entry memory record written by P18 completion writeback
```

P22 only provides summary notification:

```text
something happened; software should inspect queue status and/or CQ records
```

Required visibility ordering for command-completed notification:

```text
P18 writes completion payload words
P18 writes commit word last
P18 receives final OKAY BRESP
P19/P20/P21 advances CQ_TAIL
P22 sets QUEUE_COMMAND_COMPLETED_EVENT pending
```

The event must not report command completion before the CQ record commit is visible.

---

## 10. Snapshot and Counter Policy

P22 may capture debug snapshots when an event fires.

Recommended snapshots:

```text
CSR_EVENT_LAST_CAUSE:
  last event bit index
  event source class
  queue FSM state, if available

CSR_EVENT_QUEUE_SNAPSHOT0:
  SQ_HEAD / SQ_TAIL / CQ_HEAD / CQ_TAIL low bits

CSR_EVENT_QUEUE_SNAPSHOT1:
  queue status / done / error / reject low bits
```

`CSR_EVENT_COUNT` increments when an event source sets at least one pending bit.

`CSR_EVENT_IRQ_COUNT` increments when a newly captured event is interrupt-eligible:

```text
GLOBAL_IRQ_ENABLE=1
and event bit is enabled by CSR_EVENT_ENABLE
```

These counters are debug aids.  They must not affect queue behavior.

---

## 11. Error and Stop Behavior

P22 does not change queue error or stop semantics.

When a queue error occurs:

```text
queue error sticky status is set
QUEUE_ERROR_EVENT pending bit is set
if enabled, event_irq asserts
queue remains stopped until queue error is cleared according to existing P19/P20/P21 policy
```

When STOP_QUEUE or STOP_AFTER_THIS stops the queue:

```text
active command completes normally
completion record commits normally if applicable
queue stopped sticky status is set
QUEUE_STOPPED_EVENT pending bit is set
no queue error is set solely because of graceful stop
```

Runtime appends do not bypass STOP_QUEUE or STOP_AFTER_THIS.  P22 may notify that the runtime doorbell happened, but the queue still suppresses further appended commands after a stop request.

---

## 12. Implemented RTL Delta for P22C/P22D/P22E

P22 keeps the event notification logic integrated into the existing CSR wrapper path.  It does not retain a standalone event CSR block, standalone event injection interface, or standalone event UVM top.

Modified RTL:

```text
rtl/csr/ai_accel_csr_regs.sv
rtl/top/ai_accel_subsys_csr_top.sv
```

Modified UVM top / package integration:

```text
tb/top/ai_accel_subsys_csr_uvm_top.sv
tb/uvm/helper/ai_accel_csr_access_helper.sv
tb/uvm/pkg/ai_accel_subsys_uvm_pkg.sv
```

Event source inputs are generated from existing queue and CSR state transitions:

```text
queue command completion / CQ commit
queue drained terminal state
queue stopped terminal state
queue validation / propagated error
CQ non-empty observation
software TEST_EVENT command
```

Event outputs remain summary-only:

```text
CSR_EVENT_PENDING / CSR_EVENT_STATUS CSR readback
event_irq interrupt-lite summary output
```

No BRAM, GEMM, DMA, AXI-Stream, or Direct Stream datapath module is modified for P22.

---

## 13. UVM Validation Plan

Recommended P22 milestone split:

```text
P22A: Event notification / interrupt-lite prototype spec
P22B: Event CSR register map freeze
P22C: Integrated Event CSR smoke
P22D: Queue completion event smoke
P22E: Queue drained / stopped / error event smoke
P22F: Event mask / W1C clear / re-arm behavior
P22G: Full regression integration
P22H: Documentation closure
```

### 13.1 P22C Integrated Event CSR Smoke

Purpose:

```text
validate reset values
validate EVENT_ENABLE write/readback
validate EVENT_CONTROL write/readback
validate FORCE_TEST_EVENT
validate EVENT_PENDING W1C clear
validate CLEAR_EVENT_PENDING command
validate event counter and last-cause snapshots
validate event_irq disabled by default
validate event_irq when globally enabled and enabled pending bit is set
validate the event CSR window inside `ai_accel_subsys_csr_uvm_top`, without a standalone event top
```

### 13.2 P22D Queue Completion Event Smoke

Purpose:

```text
run one or more queue commands through the P21 queue path
wait for CQ completion commit
check QUEUE_COMMAND_COMPLETED_EVENT pending
check EVENT_COUNT increments
check EVENT_LAST_CAUSE captures queue source
check event_irq behavior when enabled
verify CQ completion records remain correct
```

### 13.3 P22E Queue Drained / Stopped / Error Event Smoke

Purpose:

```text
validate QUEUE_STOPPED_EVENT after STOP_QUEUE or STOP_AFTER_THIS
validate QUEUE_ERROR_EVENT after a queue reject/error condition
validate QUEUE_DRAINED_EVENT after empty-SQ drain
validate event pending bits can be cleared independently
```

### 13.4 P22F Event Mask / Clear / Re-Arm Behavior

Purpose:

```text
pending bit set while enable bit is zero does not assert event_irq
setting enable after pending asserts event_irq in level mode when global enable is set
W1C clear deasserts event_irq when no enabled pending bits remain
multiple pending bits share one event_irq output
new event after clear re-arms and reasserts event_irq
CLEAR_EVENT_COUNTERS resets debug counters while idle
```

---

## 14. Full Regression Plan

P22G should add a small representative subset to full regression.

Recommended full-regression representatives:

```text
csr_event_csr_smoke
csr_queue_completion_event_case102
csr_queue_drained_stopped_error_event_case102
csr_event_mask_w1c_rearm
```

Expected count increase:

```text
Before P22G: 121
After P22G : 125
```

This keeps P22 representative rather than exhaustive.

---

## 15. P22 Closure Criteria

P22 is complete when:

```text
P22A/P22B documentation is complete
canonical event CSR window is recorded in axi_lite_csr_control_plane_spec.md
event pending / enable / control registers are implemented
event_irq output is implemented at the CSR wrapper boundary
queue command-completed event is validated after CQ commit
queue drained / stopped / error events are validated
W1C pending clear and interrupt deassertion are validated
full regression passes with P22 representatives
no BRAM / GEMM / DMA / frontend datapath changes are required
```

---

## 16. P22 Validation Result and Closure Status

P22G closes event notification / interrupt-lite through targeted validation and full-regression integration.

Validated targeted tests:

```text
ai_accel_subsys_event_csr_smoke_test
ai_accel_subsys_csr_queue_completion_event_smoke_test
ai_accel_subsys_csr_queue_drained_stopped_error_event_smoke_test
ai_accel_subsys_csr_event_mask_w1c_rearm_smoke_test
```

Validated full-regression representatives:

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

P22H documentation closure records the validated notification behavior without adding a new standalone CSR block, changing the SQ/CQ formats, changing the CQ completion record format, or modifying BRAM / GEMM / DMA / frontend datapaths.

## 17. Interview Summary

P22 adds the missing notification layer above the live host-visible queue.

Concise explanation:

```text
P19 gave the accelerator a host-visible SQ/CQ command path.
P20 made that queue drain multiple entries in order.
P21 let software append SQ entries while the queue was still active.
P22 adds a lightweight event/interrupt layer so software does not need to constantly poll every queue CSR.
The CQ record is still the authoritative completion detail; the interrupt only says that completion, drained, stopped, error, or backpressure status should be inspected.
```

The design stays small because it uses a single shared notification output, sticky pending bits, per-event enables, and the already validated P21 queue completion and command-boundary events.
