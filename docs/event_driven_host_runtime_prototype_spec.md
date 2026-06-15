# P23 Event-Driven Host Runtime / Queue Driver Model Prototype Spec

## 1. Purpose

This document defines the P23A event-driven host runtime / queue driver model prototype for the AI Accelerator Subsystem.

P19 introduced a host-visible submission queue and completion queue:

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

P20 extended the queue controller to drain multiple SQ entries in order.  P21 extended the drain model into runtime live queue service by allowing the host to append SQ entries while the queue was active.  P22 added an event notification / interrupt-lite CSR layer so software can observe command completion, queue terminal status, error status, and selected runtime-service events without continuously polling every queue register.

P23 raises the validation level from individual hardware features into a driver-like host runtime model:

```text
host runtime initializes SQ/CQ
host runtime submits SQ commands
host runtime rings the queue doorbell
hardware executes commands and writes CQ records
P22 event layer notifies the host runtime
host runtime consumes CQ records
host runtime advances CQ_HEAD
host runtime clears / re-arms event pending bits
```

The P23A goal is not to add a Linux driver or a new hardware queue architecture.  The goal is to define a small UVM-side driver-style runtime that exercises the already validated P19/P20/P21/P22 queue and event semantics in the way host software would use them.

Current baseline entering P23A:

```text
P22H event notification / interrupt-lite closure:
  TOTAL : 125
  PASS  : 125
  FAIL  : 0
```

Current closure after P23G/P23H:

```text
P23 event-driven host runtime / queue driver model closure:
  TOTAL : 129
  PASS  : 129
  FAIL  : 0
```

---

## 2. Baseline Before P23

The validated baseline includes:

```text
P17 memory-backed descriptor fetch
P18 memory-backed completion writeback
P19 host-visible SQ/CQ queue prototype
P20 multi-entry in-order queue drain
P21 runtime doorbell / live queue service
P22 event notification / interrupt-lite CSR layer
CQ completion records committed into host-visible completion memory
SQ_HEAD / CQ_TAIL pointer advancement after completion commit
CQ-full stall and host CQ_HEAD recovery during active service
STOP_QUEUE / STOP_AFTER_THIS graceful stop behavior
P22 pending / enable / global IRQ / W1C / re-arm behavior
full regression 125/125 PASS after P22G
```

P23 must preserve:

```text
one active command at a time
in-order command execution
in-order completion production
P17 descriptor format
P18 completion record format
P19 SQ entry format
P19/P20/P21 queue CSR semantics
P22 event CSR semantics
BRAM / GEMM / DMA / AXI-Stream / Direct Stream datapath behavior
```

P23 should be implemented primarily as UVM helper / test infrastructure and documentation.  No new hardware datapath behavior is expected for P23A/P23B.

---

## 3. P23 Design Intent

P19 through P22 validated the hardware queue and event features in targeted tests.  P23 validates the host-side programming model that combines those features.

Without P23, the testbench can still be feature-centric:

```text
one test programs SQ and checks CQ
one test checks event pending bits
one test checks W1C clear / re-arm
one test checks runtime append
```

P23 introduces a runtime-centric view:

```text
host runtime submit(command)
host runtime start_or_doorbell_queue()
host runtime wait_for_event()
host runtime drain_cq()
host runtime advance_cq_head()
host runtime clear_events()
host runtime continue_or_stop()
```

The design intent is to make the subsystem look like a small host-programmable accelerator from the UVM sequence point of view.

Concise intent:

```text
P23 is a UVM driver-style host runtime model above the validated SQ/CQ queue and P22 event layer.
It validates that software can submit commands, rely on event notification, consume CQ records, update CQ_HEAD, and re-arm events without changing the hardware datapath.
```

---

## 4. P23A Scope

### 4.1 Included

P23A defines:

```text
event-driven host runtime design intent
host runtime responsibility split
SQ command submission policy
queue doorbell policy
P22 event wait / acknowledge / re-arm policy
CQ record consumption policy
CQ_HEAD advancement policy
runtime append policy
CQ-full recovery policy
stop / error runtime handling policy
expected UVM helper architecture for P23B
validation plan for P23C through P23H
full-regression closure plan
```

### 4.2 Not Included

P23A does not include:

```text
RTL implementation
CSR RTL changes
UVM helper implementation
UVM tests
new CSR addresses
new SQ or CQ entry formats
interrupt controller integration
MSI/MSI-X
PCIe integration
Linux driver
C software driver
UVM RAL model
multi-vector interrupt allocation
interrupt moderation timer
multi-outstanding queue execution
out-of-order completion
command cancellation or preemption
cache-coherent host memory ordering
BRAM / GEMM / DMA / frontend datapath changes
```

P23A is a specification milestone only.

---

## 5. Fixed P23 Design Decisions

```text
Runtime location              : UVM/helper layer, not RTL datapath
Hardware queue model          : existing P19/P20/P21 queue
Notification model            : existing P22 event CSR / event_irq semantics
Command execution             : one active command at a time
Completion order              : in-order CQ records
SQ entry format               : existing P19 64-byte SQ command entry
CQ entry format               : existing P18 64-byte completion record
Event pending/clear           : existing P22 W1C / CLEAR_EVENT_PENDING policy
Event re-arm                  : existing P22 pending clear followed by later event capture
CQ recovery                   : host consumes CQ and writes CSR_CQ_HEAD
Runtime append                : host writes SQ entry, writes VALID last, updates CSR_SQ_TAIL
Driver style                  : deterministic UVM runtime helper, not OS driver
BRAM / GEMM / DMA / frontend  : unchanged
```

P23 does not redefine the queue or event hardware.  It validates the software usage pattern of the existing queue and event hardware.

---

## 6. Host Runtime Model

The P23 host runtime owns a small set of responsibilities:

```text
queue initialization
SQ command construction
SQ_TAIL publication / doorbell update
event wait and decode
CQ record polling / consumption
CQ_HEAD update after consumed completions
event W1C clear and re-arm
runtime append during active queue service
stop and error recovery sequences
```

The runtime does not own:

```text
GEMM datapath scheduling internals
P17 descriptor fetch internals
P18 completion record construction
queue-controller FSM internals
P22 event generation internals
```

Recommended runtime API style for P23B:

```systemverilog
task host_rt_init_queue(...);
task host_rt_program_descriptor_table(...);
task host_rt_submit_sq_cmd(...);
task host_rt_ring_doorbell(...);
task host_rt_wait_event(...);
task host_rt_consume_cq(...);
task host_rt_clear_event_bits(...);
task host_rt_rearm_events(...);
task host_rt_stop_queue(...);
task host_rt_recover_from_cq_full(...);
task host_rt_check_error_event(...);
```

The exact helper names may follow the existing project naming style, but the runtime should remain a thin abstraction around existing CSR helper calls and memory helper calls.

---

## 7. Queue Initialization Policy

The host runtime initializes SQ/CQ before starting a session.

Recommended sequence:

```text
1. Clear SQ memory entries used by the test.
2. Clear CQ memory commit words used by the test.
3. Program CSR_SQ_BASE_ADDR, CSR_SQ_DEPTH, CSR_SQ_STRIDE.
4. Program CSR_CQ_BASE_ADDR, CSR_CQ_DEPTH, CSR_CQ_STRIDE.
5. Reset or initialize SQ_HEAD / SQ_TAIL / CQ_HEAD / CQ_TAIL while queue is idle.
6. Program CSR_QUEUE_CONTROL policy bits.
7. Clear P22 event pending bits and event counters.
8. Program CSR_EVENT_ENABLE for expected events.
9. Program CSR_EVENT_CONTROL.GLOBAL_IRQ_ENABLE when event-driven wait is intended.
```

P23 should avoid relying on stale queue or event sticky bits from previous tests.

---

## 8. SQ Submission and Doorbell Policy

For each submitted command, the host runtime must preserve the command visibility policy:

```text
1. Choose sq_index = SQ_TAIL % SQ_DEPTH.
2. Write SQ payload words first.
3. Write CMD_CONTROL.VALID=1 last.
4. Update CSR_SQ_TAIL to publish the new command.
5. If the queue is idle, write CSR_QUEUE_COMMAND.START_QUEUE.
6. If the queue is active, the SQ_TAIL write acts as a runtime doorbell for the next command-boundary check.
```

The runtime must not update SQ_TAIL before the command commit word is visible.

For event-driven tests, the runtime should enable at least:

```text
QUEUE_COMMAND_COMPLETED_EVENT
CQ_NOT_EMPTY_EVENT
```

Additional events are enabled depending on the scenario.

---

## 9. Event Wait Policy

P23 uses the P22 event layer as the host notification mechanism.

The preferred wait condition is:

```text
CSR_EVENT_STATUS.EVENT_IRQ_OUT == 1
```

or, when the UVM top exposes the wrapper-level interrupt signal directly:

```text
event_irq == 1
```

The event-driven runtime should not continuously poll all queue CSRs as its primary completion mechanism.  It may poll `CSR_EVENT_STATUS` as a proxy for the interrupt-lite output in the UVM environment.

Recommended wait flow:

```text
1. Wait for EVENT_IRQ_OUT or event_irq assertion.
2. Read CSR_EVENT_PENDING.
3. Decode which event bits fired.
4. Read queue status or CQ records only as needed for the event.
5. Consume CQ records if CQ-related event fired.
6. W1C clear handled event bits.
7. Confirm EVENT_IRQ_OUT deasserts when no enabled pending bits remain.
```

Pending capture remains independent of interrupt enable.  P23 should explicitly preserve the P22 behavior that event bits may already be pending before they become interrupt-eligible.

---

## 10. CQ Consumption Policy

The CQ record remains the authoritative per-command completion detail.

When the runtime sees a completion-related event:

```text
1. Read CSR_CQ_TAIL.
2. Compare against local consumed CQ_HEAD shadow.
3. For each available CQ entry:
     read completion word0
     confirm VALID commit bit is set
     read remaining completion words
     check command tag / status / count fields expected by the test
     optionally clear CQ word0 for debug cleanliness
4. Write CSR_CQ_HEAD to publish consumed completions.
5. Clear completion-related P22 event bits.
```

P23 should not treat the interrupt as completion detail.  The interrupt only tells the runtime to inspect CQ records and queue status.

---

## 11. Event Clear and Re-Arm Policy

The runtime clears event pending bits after handling them.

Recommended clear policy:

```text
Use W1C to clear only the event bits that were handled.
Use CLEAR_EVENT_PENDING only for initialization, cleanup, or tests that intentionally clear all pending events.
Use CLEAR_EVENT_COUNTERS only for debug-counter reset points.
```

Re-arm means:

```text
handled event pending bit is cleared
EVENT_ENABLE remains programmed or is restored
GLOBAL_IRQ_ENABLE remains programmed or is restored
later hardware event source fires again
same pending bit sets again
event_irq / EVENT_IRQ_OUT asserts again in level mode
```

P23F should validate this behavior using a realistic queue event in addition to the P22F software TEST_EVENT behavior if practical.

---

## 12. Runtime Append Policy

For live queue service, the host runtime may append commands while the queue is active.

Runtime append sequence:

```text
1. Start the queue with at least one visible SQ command.
2. Wait until queue_busy is observed or active command progress is inferred.
3. Program a new SQ entry at the current SQ_TAIL index.
4. Write CMD_CONTROL.VALID last.
5. Write CSR_SQ_TAIL to publish the append.
6. Wait for P22 runtime or completion event.
7. Confirm appended command eventually appears as a CQ record if no stop/error condition intervenes.
```

P23 does not change the P21 command-boundary observation rule.  The active command remains isolated from SQ_TAIL updates until the next command boundary.

---

## 13. CQ-Full Recovery Policy

P23 should model how a host runtime recovers from CQ backpressure.

Recommended sequence:

```text
1. Configure a small CQ depth.
2. Submit enough SQ commands to fill CQ.
3. Observe CQ_FULL_STALL_EVENT or queue stalled status through event wait.
4. Runtime consumes one or more CQ entries.
5. Runtime writes CSR_CQ_HEAD to publish free CQ space.
6. Hardware observes CQ space recovery and continues at a command boundary.
7. Runtime observes later completion event and consumes the remaining CQ record.
```

This flow validates that event-driven service can make progress without resetting the queue.

---

## 14. Stop and Error Handling Policy

### 14.1 Graceful Stop

The runtime may request STOP_QUEUE during active service.

Expected behavior:

```text
active command completes normally
completion record commits if applicable
queue reports stopped sticky status
P22 sets QUEUE_STOPPED_EVENT
runtime consumes any produced CQ record
runtime clears stopped event pending bit
runtime may later restart the queue if pending SQ entries remain
```

### 14.2 Queue Error

When the runtime observes QUEUE_ERROR_EVENT:

```text
1. Read CSR_QUEUE_ERROR_STATUS and CSR_QUEUE_REJECT_STATUS.
2. Read CSR_QUEUE_ERROR_DETAIL and CSR_QUEUE_LAST_CMD_TAG if useful.
3. Consume any CQ reject completion if one was produced.
4. Clear queue error / reject sticky bits according to queue policy.
5. Clear P22 QUEUE_ERROR_EVENT pending bit.
6. Reinitialize or restart the queue only after sticky error policy is satisfied.
```

P23 should keep error recovery deterministic and avoid masking real queue errors as expected behavior unless the test intentionally injected the error.

---

## 15. Ordering and Visibility Policy

P23 relies on the existing ordering contracts:

```text
host writes SQ payload before CMD_CONTROL.VALID
host writes CSR_SQ_TAIL after SQ command commit word
hardware consumes SQ command after SQ_HEAD != SQ_TAIL and VALID=1
P18 writes CQ payload before CQ commit word
P19/P20/P21 advances CQ_TAIL only after completion commit succeeds
P22 QUEUE_COMMAND_COMPLETED_EVENT is generated after CQ_TAIL advancement / completion commit
host consumes CQ record before advancing CSR_CQ_HEAD
host clears P22 pending after handling the event
```

These ordering points are the core of the driver-like runtime model.

---

## 16. Suggested UVM Architecture for P23B

P23B should add a reusable helper layer rather than duplicating long queue programming sequences in every test.

Recommended file direction:

```text
tb/uvm/test/ai_accel_subsys_csr_event_runtime_helper.sv
```

or, if the existing helper file style is preferred:

```text
tb/uvm/test/ai_accel_subsys_queue_runtime_helper.sv
```

The helper should reuse existing lower-level helpers:

```text
ai_accel_csr_access_helper
queue command programming helper routines
memory descriptor programming helper routines
CQ readback/check helper routines
```

P23B should avoid adding:

```text
standalone event CSR top
standalone event CSR block
standalone event inject interface
new sim flow
new RTL datapath module
```

The runtime helper should be included in the existing UVM package and compiled by the existing `compile_uvm.tcl` flow.

---

## 17. P23 UVM Validation Plan

Recommended P23 milestone split:

```text
P23A: Event-driven host runtime prototype spec
P23B: UVM host runtime helper / driver-style API
P23C: Event-driven single queue command smoke
P23D: Event-driven multi-command queue drain smoke
P23E: Event-driven runtime append / live doorbell smoke
P23F: Event-driven CQ full recovery / stopped / error handling
P23G: Full regression integration
P23H: Documentation closure
```

### 17.1 P23C Event-Driven Single Queue Command Smoke

Purpose:

```text
submit one SQ command
start queue
wait using P22 event notification
consume one CQ record
advance CQ_HEAD
W1C clear completion-related event bits
confirm event_irq / EVENT_IRQ_OUT deasserts
compare result payload where applicable
```

Suggested test name:

```text
ai_accel_subsys_csr_event_runtime_single_cmd_smoke_test
```

### 17.2 P23D Event-Driven Multi-Command Queue Drain Smoke

Purpose:

```text
submit multiple SQ commands before START_QUEUE
wait for event-driven completion notifications
consume CQ records in order
advance CQ_HEAD as records are consumed
clear and re-arm event pending bits between service loops
confirm final SQ_HEAD / CQ_TAIL values
```

Suggested test name:

```text
ai_accel_subsys_csr_event_runtime_multi_cmd_smoke_test
```

### 17.3 P23E Event-Driven Runtime Append / Live Doorbell Smoke

Purpose:

```text
start queue with one command
append another command while active
publish append by updating SQ_TAIL
wait for event-driven notification
consume CQ records in order
confirm runtime-appended command completed without second START_QUEUE
```

Suggested test name:

```text
ai_accel_subsys_csr_event_runtime_append_smoke_test
```

### 17.4 P23F Event-Driven CQ Full Recovery / Stop / Error Handling

Purpose:

```text
validate event-driven CQ full stall recovery through CQ_HEAD update
validate STOP_QUEUE event-driven handling
validate QUEUE_ERROR_EVENT event-driven handling
validate event clear / re-arm after stop or error handling
```

P23F may be one combined representative test or two smaller tests if debug clarity is better.

Suggested test name:

```text
ai_accel_subsys_csr_event_runtime_recovery_smoke_test
```

---

## 18. Full Regression Plan

P23G should add a small representative subset to full regression.

Validated full-regression representatives:

```text
csr_event_driven_single_queue_command_case102
csr_event_driven_multi_command_queue_drain_case102
csr_event_driven_runtime_append_case102
csr_event_driven_cq_full_stop_error_case102
```

Expected count increase:

```text
Before P23G: 125
After P23G : 129
```

This keeps P23 representative rather than exhaustive.

---

## 19. P23 Closure Criteria

P23 is complete when:

```text
P23A prototype spec is complete
P23B reusable UVM host runtime helper is implemented
host runtime can initialize SQ/CQ and P22 event state
host runtime can submit SQ commands and ring the queue doorbell
host runtime can wait on event notification rather than full queue polling
host runtime can consume CQ records and advance CQ_HEAD
host runtime can W1C clear and re-arm event pending bits
host runtime can handle runtime append while active
host runtime can recover from CQ full by consuming CQ and updating CQ_HEAD
host runtime can handle STOP_QUEUE and queue error event paths
full regression passes with P23 representatives
no BRAM / GEMM / DMA / frontend datapath changes are required
```

---

## 20. Interview Summary

P23 is the step that turns the queue and event hardware into a software-like runtime flow.

Concise explanation:

```text
P19 gave the subsystem a host-visible SQ/CQ queue.
P20 made the queue drain multiple commands in order.
P21 allowed the host to append commands while the queue was active.
P22 added interrupt-lite event notification.
P23 validates the driver-style usage model: submit SQ commands, wait for event notification, consume CQ records, advance CQ_HEAD, clear events, and continue service.
```

The design remains intentionally conservative:

```text
single active command
in-order completions
one shared interrupt-lite event summary
no OS driver dependency
no MSI/MSI-X
no datapath rewrite
```

The main value of P23 is that it demonstrates an end-to-end host programming model, not just isolated RTL features.

## 21. P23 Validation Result and Closure Status

P23 is closed through P23G full regression integration and P23H documentation closure.

Validated implementation / UVM milestones:

```text
P23A: Event-driven host runtime prototype spec                    PASS
P23B: UVM host runtime helper / driver-style API                  PASS
P23C: Event-driven single queue command smoke                     PASS
P23D: Event-driven multi-command queue drain smoke                PASS
P23E: Event-driven runtime append / live doorbell smoke           PASS
P23F: Event-driven CQ full recovery / stopped / error handling    PASS
P23G: Full regression integration                                 PASS
P23H: Documentation closure                                       PASS
```

Validated test names:

```text
ai_accel_subsys_csr_event_driven_single_queue_command_smoke_test
ai_accel_subsys_csr_event_driven_multi_command_queue_drain_smoke_test
ai_accel_subsys_csr_event_driven_runtime_append_smoke_test
ai_accel_subsys_csr_event_driven_cq_full_stop_error_smoke_test
```

Validated full-regression entries:

```text
csr_event_driven_single_queue_command_case102
csr_event_driven_multi_command_queue_drain_case102
csr_event_driven_runtime_append_case102
csr_event_driven_cq_full_stop_error_case102
```

Full regression after P23G:

```text
TOTAL : 129
PASS  : 129
FAIL  : 0
```

Validated host-runtime behavior:

```text
initialize SQ/CQ and P22 event state
program SQ command entries with VALID written last
publish SQ_TAIL as the queue doorbell
start a queue session when idle
wait on P22 event notification instead of polling all queue state as the primary completion mechanism
read and validate CQ completion records after event notification
advance CSR_CQ_HEAD after host consumption
W1C-ack handled event bits and re-arm the event path
append SQ entries while live queue service is active
recover CQ-full stalls by consuming CQ and updating CSR_CQ_HEAD
handle STOP_QUEUE / stopped event paths
handle invalid SQ command / QUEUE_ERROR_EVENT paths
```

P23 did not introduce any new CSR address, SQ entry format, CQ entry format, completion record format, interrupt-vector model, BRAM behavior, GEMM datapath behavior, DMA behavior, AXI-Stream behavior, or Direct Stream behavior.



---

## 22. P25 Runtime Stress / Robustness Validation

P25 extends the P23 event-driven host runtime model from functional driver-style smoke tests into representative runtime stress / robustness validation.  It does not change the hardware datapath, SQ entry format, CQ entry format, CSR address map, or event bit allocation.

Validated P25 implementation / UVM milestones:

```text
P25A: Runtime stress / robustness spec                         PASS
P25B: Event-driven host runtime stress helper extension        PASS
P25C: Multi-session queue runtime stress smoke                 PASS
P25D: Runtime append + CQ consume timing variation smoke       PASS
P25E: STOP / timeout / recovery mixed stress smoke             PASS
P25F: Full regression integration                              PASS
P25G: Documentation closure                                    PASS
```

Validated P25 test names:

```text
ai_accel_subsys_csr_event_driven_multi_session_stress_test
ai_accel_subsys_csr_event_driven_append_consume_stress_test
ai_accel_subsys_csr_event_driven_stop_timeout_recovery_stress_test
```

Validated full-regression entries:

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

Validated runtime stress behavior:

```text
multiple event-driven runtime sessions can be initialized, run, cleaned up, and reused
runtime SQ append remains visible only through CSR_SQ_TAIL publication and command-boundary observation
CQ consumption may be intentionally delayed; later CSR_CQ_HEAD updates recover CQ space
STOP_QUEUE completes the active command but prevents automatic consumption of a pending appended SQ entry
pending SQ entries can be restarted and completed after stopped-event handling
timeout produces COMMAND_TIMEOUT_ERROR and QUEUE_ERROR_EVENT
host clears event, queue, and lower-level sticky state after timeout
post-timeout valid command completes normally
final event pending, queue error, and queue reject state are clean
```

P25 keeps the P23 runtime helper model software-like: submit SQ, wait event, consume CQ, advance CQ_HEAD, W1C-ack events, clear sticky errors when required, and restart service only after the observable CSR state is clean.
