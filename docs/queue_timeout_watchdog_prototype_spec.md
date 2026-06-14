# P24 Queue Timeout / Watchdog / Runtime Recovery Prototype Spec

## 1. Purpose

This document defines the P24A queue timeout / watchdog / runtime recovery prototype for the AI Accelerator Subsystem.

P17 through P23 established a host-programmable accelerator path:

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
```

P23 validated the driver-style host runtime behavior for normal completion, multi-command drain, runtime append, CQ-full recovery, graceful stop, and queue validation error handling.

P24 extends that runtime model with bounded progress detection:

```text
accepted queue command
    -> per-command watchdog starts
    -> command reaches terminal completion before timeout
        -> normal CQ completion / normal event path
    -> or watchdog expires before terminal completion
        -> queue timeout sticky error
        -> optional timeout CQ record
        -> P22 QUEUE_ERROR_EVENT notification
        -> P23-style host runtime recovery
```

The goal is not to add preemption, cancellation, or multi-outstanding execution.  The goal is to prevent a driver-visible queue session from hanging forever when a lower-level command path fails to make terminal progress.

Current baseline entering P24A:

```text
P23H event-driven host runtime closure:
  TOTAL : 129
  PASS  : 129
  FAIL  : 0
```

---

## 2. Baseline Before P24

The validated baseline includes:

```text
P17 memory-backed descriptor fetch
P18 memory-backed completion writeback
P19 host-visible SQ/CQ command queue prototype
P20 multi-entry in-order queue drain
P21 runtime doorbell / live queue service
P22 event notification / interrupt-lite CSR layer
P23 event-driven UVM host runtime helper
CQ completion records committed into host-visible completion memory
SQ_HEAD / CQ_TAIL pointer advancement after completion commit
CQ-full stall and CQ_HEAD recovery during active service
STOP_QUEUE / STOP_AFTER_THIS graceful stop behavior
QUEUE_ERROR_EVENT based runtime wake-up and cleanup
full regression 129/129 PASS after P23G/P23H
```

P24 must preserve:

```text
one active command at a time
in-order command execution
in-order completion production
P17 descriptor format
P18 completion record format
P19 SQ entry format
P19/P20/P21 queue CSR window
P22 event CSR window
P23 event-driven host runtime programming model
BRAM / GEMM / DMA / AXI-Stream / Direct Stream datapath behavior
```

P24 should be implemented as a small robustness extension to the queue controller and UVM runtime validation.  It should not destabilize the GEMM datapath or introduce a new queue architecture.

---

## 3. P24 Design Intent

P19 through P23 made the accelerator queue usable from a software-like runtime model.  The missing robustness question is:

```text
What happens if an accepted command does not reach terminal status?
```

Without P24, the host runtime can wait for:

```text
CQ completion event
queue drained event
queue stopped event
queue error event
```

but there is no hardware-owned deadline that guarantees a stuck command eventually becomes visible as a structured error.

P24 adds a per-command watchdog tied to the accepted SQ command context.  The command entry already includes an optional timeout field:

```text
CMD_TIMEOUT_CYCLES
```

P24 defines how that field is used.

Concise intent:

```text
P24 converts CMD_TIMEOUT_CYCLES from a reserved/debug field into a bounded-progress contract for queue commands.
If an accepted command does not reach terminal status before the programmed timeout, the queue reports a structured timeout error, wakes the event-driven host runtime, and allows deterministic cleanup/recovery.
```

---

## 4. P24A Scope

### 4.1 Included

P24A defines:

```text
queue timeout design intent
per-command watchdog start/stop policy
CMD_TIMEOUT_CYCLES semantics
timeout disabled policy
timeout terminal status policy
queue sticky error policy for timeout
timeout completion-record policy
timeout event-notification policy
host-runtime recovery sequence
timeout interaction with CQ full / STOP_QUEUE / validation error
expected RTL delta direction
expected UVM validation split for P24B through P24H
full-regression closure plan
```

### 4.2 Not Included

P24A does not include:

```text
RTL implementation
CSR RTL changes
UVM tests
new CSR address allocation
new SQ or CQ entry size
new descriptor format
new completion record size
new event CSR window
hard abort of an in-flight DMA / GEMM / recipe operation
preemption
command cancellation rollback
multiple outstanding commands
out-of-order completion
interrupt controller integration
MSI/MSI-X
Linux driver
C software driver
UVM RAL model
cache-coherent host interface
BRAM / GEMM / DMA / frontend datapath changes
```

P24A is a specification milestone only.  P24B later freezes the exact CSR timeout bit, queue error detail encoding, and timeout completion-record mapping without allocating new CSR addresses.

---

## 5. Fixed P24 Design Decisions

```text
Timeout granularity            : per accepted SQ command
Timeout field source           : existing SQ word CMD_TIMEOUT_CYCLES
Timeout disabled value         : CMD_TIMEOUT_CYCLES == 0
Timeout counter domain         : dma_clk / queue controller clock domain
Timeout start point            : after command is accepted and enters active queue execution
Timeout stop point             : when the active command reaches terminal queue status
Timeout terminal behavior      : set queue timeout/error sticky, stop queue service
Command execution model        : still one active command at a time
Completion ordering            : still in-order
CQ record format               : existing P18 64-byte completion record, with timeout status encoded in existing status/detail fields
Event notification             : existing P22 QUEUE_ERROR_EVENT path
Host recovery model            : existing P23 event-driven runtime cleanup/restart style
BRAM / GEMM / DMA / frontend   : unchanged
```

P24 does not require a new CSR window.  Any CSR bit-definition cleanup required by P24B must be recorded in the canonical CSR document:

```text
docs/axi_lite_csr_control_plane_spec.md
```

---

## 6. Timeout Programming Model

The host programs the timeout through the existing SQ command entry field:

```text
CMD_TIMEOUT_CYCLES
```

Recommended semantics:

```text
CMD_TIMEOUT_CYCLES = 0
  timeout disabled for this command

CMD_TIMEOUT_CYCLES > 0
  start a per-command watchdog after command acceptance
  decrement or increment once per dma_clk cycle while the command is active
  if the command reaches terminal status before timeout expires, clear the watchdog normally
  if the watchdog expires first, report queue timeout terminal status
```

The timeout budget belongs to the active command snapshot.  Host writes to the SQ entry after command acceptance must not change the active timeout budget.

The timeout should include the full lower-level execution path for one SQ command:

```text
command fetch accepted
P17 descriptor fetch launch / execution
P16 recipe sequencing
P15 job sequencing
selected frontend / GEMM / DMA store path
P18 completion writeback
queue pointer advancement / terminal status
```

The timeout does not need to include idle time before the command is accepted.

---

## 7. Watchdog Lifecycle

### 7.1 Start Point

The watchdog starts only after a command has been accepted by the queue controller.

A command is considered accepted when:

```text
SQ entry has been fetched
CMD_CONTROL.VALID has been validated
queue-level command fields are valid
CQ space is available or a timeout completion policy has reserved a CQ slot
active command context is snapshotted
queue controller commits to launching the command into the P17/P16/P15/P18 path
```

The watchdog should not start for:

```text
invalid queue configuration reject before SQ fetch
START_QUEUE reject while queue_busy
SQ empty drained state
CQ full stall before consuming the next SQ entry
command fetch AXI error before command contents are known
```

### 7.2 Active Counting Window

The watchdog is active while the queue controller owns one command context.

Suggested active window:

```text
Q_PREP_LAUNCH
Q_START_DESC_FETCH
Q_WAIT_DESC_FETCH_ACCEPT
Q_WAIT_RECIPE_TERMINAL
Q_START_COMPLETION
Q_WAIT_COMPLETION
Q_ADVANCE_POINTERS, until terminal queue status is committed
```

The exact FSM state names may differ, but the policy is:

```text
once the queue has consumed one SQ command and promised terminal handling, the watchdog is responsible for bounding progress until terminal handling completes.
```

### 7.3 Stop Point

The watchdog stops normally when the command reaches terminal queue status.

Normal terminal examples:

```text
successful completion record committed and CQ_TAIL advanced
command validation reject completion committed, if reject completion policy is enabled
queue-level lower error became sticky before watchdog expiry
STOP_QUEUE / STOP_AFTER_THIS graceful stop after command completion
reset
```

If another non-timeout queue error occurs first, that error wins over the timeout for the terminal reason.

### 7.4 Expiry Point

The watchdog expires when:

```text
active_watchdog_count >= active_cmd_timeout_cycles
and active_cmd_timeout_cycles != 0
and command has not reached terminal status
```

On expiry:

```text
set queue timeout sticky error
capture active SQ index / CQ index / user tag / state into debug registers
stop accepting further SQ commands
request a timeout completion record if the configured policy allows it
raise P22 QUEUE_ERROR_EVENT
```

---

## 8. Timeout Error Policy

P24 timeout is a queue-level terminal error.

Required sticky state:

```text
CSR_QUEUE_ERROR_STATUS timeout-related bit is set
CSR_QUEUE_ERROR_DETAIL records timeout detail
CSR_QUEUE_ERROR_INDEX records the active SQ/CQ physical index
CSR_QUEUE_LAST_CMD_TAG remains the active command user tag
CSR_QUEUE_STATUS.QUEUE_ERROR becomes visible
queue_busy eventually deasserts after timeout terminal handling completes
```

P24B freezes the exact canonical CSR usage:

```text
CSR_QUEUE_ERROR_STATUS[6] = COMMAND_TIMEOUT_ERROR
CSR_QUEUE_ERROR_DETAIL[7:0] = DETAIL_COMMAND_TIMEOUT or a phase-specific DETAIL_TIMEOUT_* code
CSR_QUEUE_ERROR_DETAIL[15:8] = active SQ physical index
CSR_QUEUE_ERROR_DETAIL[23:16] = reserved CQ physical index, when one exists
CSR_QUEUE_ERROR_DETAIL[31:24] = queue FSM state at timeout capture
CSR_QUEUE_ERROR_INDEX uses the existing SQ/CQ physical-index packing
```

Frozen timeout detail values:

```text
DETAIL_COMMAND_TIMEOUT
DETAIL_TIMEOUT_IN_DESC_FETCH
DETAIL_TIMEOUT_IN_RECIPE
DETAIL_TIMEOUT_IN_COMPLETION_WB
DETAIL_TIMEOUT_IN_QUEUE_ADVANCE
```

These detail encodings are mirrored into the canonical CSR control-plane spec.

---

## 9. Timeout Completion Record Policy

P24 should attempt to produce a CQ completion record for a timeout when it is safe and useful.  P24B freezes the record mapping without changing the 64-byte P18 record size.

Recommended first policy:

```text
If the command was accepted and a CQ slot was reserved before launch:
  write a timeout completion record into the reserved CQ slot where practical
  commit word remains written last
  CQ_TAIL advances only after timeout completion record commit succeeds

If completion writeback itself is the stuck lower-level operation:
  do not require a second nested completion writeback path
  queue timeout/error CSR status is authoritative
  CQ_TAIL must not advance unless a valid completion record commit succeeds
```

This avoids circular dependency:

```text
if P18 completion writeback is the hung block, P24 must not depend on P18 to report the timeout.
```

Therefore P24 defines two reporting levels:

```text
Primary timeout report:
  queue CSR sticky error + P22 QUEUE_ERROR_EVENT

Optional structured completion report:
  timeout CQ record, only when completion writeback is available and successfully commits
```

The host runtime must treat queue CSR error status as authoritative even if no CQ timeout record exists.

P24B timeout completion record mapping:

```text
COMP_COMMIT.VALID=1
COMP_COMMIT.OVERALL_ERROR=1
COMP_STATUS_FLAGS.QUEUE_TIMEOUT=1
COMP_FIRST_USER_TAG and COMP_LAST_USER_TAG may carry the active SQ CMD_USER_TAG
COMP_ERROR_DETAIL mirrors CSR_QUEUE_ERROR_DETAIL when practical
```

If the completion writeback path itself is timed out, no nested completion writeback is required and `CSR_CQ_TAIL` must not advance unless a valid timeout record has already committed.

---

## 10. Timeout Event Notification Policy

P24 reuses the existing P22 event layer.

When a timeout error becomes sticky:

```text
P22 QUEUE_ERROR_EVENT pending bit is set
if QUEUE_ERROR_EVENT is enabled and GLOBAL_IRQ_ENABLE=1, event_irq asserts
host runtime wakes through the same P23 event wait path
```

No new P22 event bit is required for P24A.

Rationale:

```text
QUEUE_ERROR_EVENT already tells the host to inspect queue error status.
Timeout is a queue error subtype, not a new independent notification class.
```

If later software wants a distinct timeout event, that can be a future milestone.  P24 should keep the event model small.

---

## 11. Host Runtime Recovery Policy

P24 builds directly on the P23 host runtime model.

Recommended recovery flow:

```text
1. Host submits an SQ command with CMD_TIMEOUT_CYCLES != 0.
2. Hardware accepts the command and starts the watchdog.
3. Timeout occurs before command terminal completion.
4. P22 QUEUE_ERROR_EVENT wakes the host runtime.
5. Host reads CSR_EVENT_PENDING and confirms QUEUE_ERROR_EVENT.
6. Host reads CSR_QUEUE_ERROR_STATUS / CSR_QUEUE_ERROR_DETAIL / CSR_QUEUE_ERROR_INDEX / CSR_QUEUE_LAST_CMD_TAG.
7. Host checks CQ_TAIL and CQ commit word to see whether a timeout CQ record was produced.
8. Host consumes any valid timeout CQ record and advances CQ_HEAD if needed.
9. Host W1C clears event pending bits.
10. Host clears queue sticky error according to queue policy.
11. Host clears lower-level sticky status required by the failed path.
12. Host submits or restarts a known-good command.
13. Known-good command completes normally.
```

P24F should validate the full event-driven recovery sequence.

---

## 12. Interaction With Existing Queue Behavior

### 12.1 CQ Full

CQ full before command acceptance remains a stall, not a timeout, unless P24B explicitly defines a separate CQ-full wait timeout.

Recommended P24A policy:

```text
Do not start command watchdog while stalled before command acceptance due to CQ full.
CQ full stall is recovered by host CQ_HEAD update as validated in P21/P23.
```

A future timeout may cover CQ-full stall duration, but that should be a separate policy bit or detail code.

### 12.2 STOP_QUEUE

If STOP_QUEUE is requested while a command is active:

```text
active command continues normally
watchdog remains active for that command
if command completes before timeout, STOP_QUEUE produces normal stopped terminal status
if timeout expires first, timeout error wins over graceful stop
```

### 12.3 STOP_AFTER_THIS

If the active command has STOP_AFTER_THIS set:

```text
watchdog still applies while the command is active
if command completes before timeout, stopped-after-command behavior is normal
if timeout expires first, timeout error wins
```

### 12.4 Command Validation Error

If command validation fails before lower-level launch:

```text
normal validation error/reject policy applies
watchdog may not need to start because the command reaches terminal reject immediately
```

If a reject completion writeback is attempted and that writeback hangs, a completion-writeback timeout may be reported if P24 timeout covers the completion phase.

### 12.5 Descriptor Fetch / Recipe / Job Errors

If descriptor fetch, recipe, or job error becomes sticky before timeout expiry:

```text
that lower-level error wins as the terminal reason
watchdog stops normally at queue error terminal status
```

Timeout is only reported when no other terminal reason arrived before the deadline.

---

## 13. Suggested RTL Delta for P24C

P24A does not implement RTL, but the expected RTL delta should remain small.

Likely modified RTL:

```text
rtl/sequencer/ai_accel_queue_fetch_controller.sv
rtl/csr/ai_accel_csr_regs.sv, only if canonical timeout status/detail bits are clarified
rtl/top/ai_accel_subsys_csr_top.sv, only if timeout status needs additional plumbing
```

Likely queue-controller additions:

```text
active_cmd_timeout_cycles_q
active_watchdog_count_q
active_watchdog_enable_q
active_watchdog_expired_q
timeout_error_pulse
timeout_detail_q
timeout_state_snapshot_q
timeout terminal branch from active wait states
optional timeout completion request path
```

Recommended implementation rule:

```text
The watchdog belongs to the queue controller, not to P17/P16/P15/P18 individually.
```

This keeps P24 localized and avoids modifying lower-level datapath engines.

---

## 14. UVM Validation Plan

Recommended P24 milestone split:

```text
P24A: Queue timeout / watchdog prototype spec
P24B: Timeout CSR / completion-record policy update                      PASS
P24C: Queue controller timeout RTL / compile smoke                    PASS
P24D: Descriptor-fetch / recipe wait timeout smoke                    PASS
P24E: Completion-writeback timeout / blocked-completion smoke        PASS
P24F: Event-driven host timeout recovery smoke                        PASS
P24G: Full regression integration                                      PASS
P24H: Documentation closure                                           PASS
```

### 14.1 P24D Descriptor-Fetch / Recipe Wait Timeout Smoke

Purpose:

```text
submit one SQ command with finite CMD_TIMEOUT_CYCLES
force or model a lower-level path that does not reach terminal status before timeout
observe queue timeout sticky error
observe QUEUE_ERROR_EVENT through P22
confirm no additional SQ command is consumed after timeout
confirm queue can be cleared after timeout
```

Possible implementation options:

```text
UVM inject/control hook to hold a lower-level done response
or use an intentionally tiny timeout budget that expires during normal descriptor/recipe latency
```

The tiny-timeout approach is preferred if deterministic across simulation timing.

### 14.2 P24E Completion-Writeback Timeout / Blocked Completion Smoke

Purpose:

```text
cover timeout while command has reached recipe terminal status but completion commit has not completed
confirm queue does not advance CQ_TAIL unless a valid completion commit occurs
confirm queue CSR timeout status remains authoritative if no CQ record is produced
```

This test must avoid falsely requiring a timeout CQ record when the completion path is the stuck path.

### 14.3 P24F Event-Driven Host Timeout Recovery Smoke

Purpose:

```text
use the P23 host runtime helper style
submit a command with finite timeout
wait on P22 QUEUE_ERROR_EVENT
read queue timeout/error status
consume timeout CQ record if one exists
ack event pending bits
clear queue sticky error
submit or restart a known-good command
confirm known-good command completes normally
```

This is the most important P24 representative because it proves the driver-like runtime does not hang permanently after timeout.

---

## 15. Full Regression Plan

P24G should add a small representative subset to full regression.

Recommended full-regression representatives:

```text
csr_queue_timeout_desc_fetch_case102
csr_queue_timeout_completion_wb_case102
csr_queue_timeout_recovery_case102
```

Expected count increase:

```text
Before P24G: 129
After P24G : 132
```

This keeps timeout validation representative rather than exhaustive.

---

## 16. P24 Closure Criteria

P24 is complete when:

```text
P24A timeout / watchdog policy is documented
P24B canonical CSR timeout status/detail policy is documented if CSR-visible fields are clarified
queue controller implements deterministic per-command watchdog behavior
watchdog disabled mode preserves existing regressions
timeout sticky error is visible through queue CSR status
P22 QUEUE_ERROR_EVENT is generated on timeout
CQ timeout record policy is implemented or explicitly documented as CSR-only for selected paths
P23-style host runtime can recover after timeout and run a valid command
full regression includes timeout representatives
full regression passes after P24G
```

---

## 17. Interview-Friendly Summary

P24 adds fault containment to the queue/runtime stack:

```text
P23 proved the host can operate the accelerator through SQ/CQ and events.
P24 proves the host is not stuck forever if a queue command fails to make progress.
The queue controller owns a per-command watchdog, reports timeout as a structured queue error, wakes the host through the existing event layer, and supports controlled runtime recovery.
```

The design remains correctness-first:

```text
single active command
in-order completion
existing SQ/CQ formats
existing event layer
no datapath rewrite
no BRAM change
```


---

## 18. P24B CSR / Completion Policy Freeze

P24B freezes the software-visible timeout reporting policy:

```text
No new CSR window
No new event bit
No SQ/CQ entry-size change
Existing SQ word6 CMD_TIMEOUT_CYCLES becomes the per-command watchdog budget
CSR_QUEUE_ERROR_STATUS[6] is COMMAND_TIMEOUT_ERROR
CSR_QUEUE_ERROR_DETAIL carries timeout detail and active SQ/CQ/state snapshot
P22 QUEUE_ERROR_EVENT is the timeout notification path
Timeout CQ record uses the existing P18 64-byte completion record when a record can be safely committed
CSR status is authoritative when timeout completion writeback is unavailable or is itself the timed-out path
```

P24B is documentation-only.  RTL implementation starts in P24C.


---

## 19. P24 Validation Result and Closure Status

P24G closes the queue timeout / watchdog feature through targeted validation and full-regression integration.

Validated targeted tests:

```text
ai_accel_subsys_csr_queue_timeout_desc_fetch_smoke_test
ai_accel_subsys_csr_queue_timeout_completion_wb_smoke_test
ai_accel_subsys_csr_queue_timeout_recovery_smoke_test
```

Validated full-regression representatives:

```text
csr_queue_timeout_desc_fetch_case102
csr_queue_timeout_completion_wb_case102
csr_queue_timeout_recovery_case102
```

Validated behavior:

```text
CMD_TIMEOUT_CYCLES=0 leaves the existing queue path compatible
Descriptor-fetch / recipe-side timeout reports DETAIL_TIMEOUT_IN_DESC_FETCH
Blocked completion-writeback timeout reports DETAIL_TIMEOUT_IN_COMPLETION_WB
Timeout sets CSR_QUEUE_ERROR_STATUS.COMMAND_TIMEOUT_ERROR
Timeout raises P22 QUEUE_ERROR_EVENT
Event pending bits are W1C-cleanable after timeout
Host clears sticky queue/lower-level status and restarts with a valid command
Post-timeout valid command completes and commits a normal CQ record
```

Full regression after P24G:

```text
TOTAL : 132
PASS  : 132
FAIL  : 0
```

P24H documentation closure records the validated timeout policy without adding new CSR windows, new event bits, new SQ/CQ formats, or BRAM / GEMM / DMA / frontend datapath changes.
