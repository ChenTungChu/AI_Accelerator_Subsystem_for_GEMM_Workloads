# P25 Runtime Stress / Robustness Prototype Spec

## 1. Purpose

This document defines the P25A runtime stress / robustness prototype for the AI Accelerator Subsystem.

P17 through P24 established a host-programmable accelerator path:

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
```

P23 validated the driver-style event-driven host runtime model for normal completion, multi-command drain, runtime append, CQ-full recovery, graceful stop, and queue validation error handling.  P24 added bounded-progress detection through `CMD_TIMEOUT_CYCLES`, queue timeout sticky status, optional timeout completion reporting, and event-driven host recovery.

P25 raises that validated stack into runtime stress / robustness validation:

```text
multiple runtime sessions
runtime SQ append while the queue is active
variable CQ consume timing
STOP_QUEUE interaction with pending runtime appends
timeout-triggered QUEUE_ERROR_EVENT recovery
post-stop / post-timeout queue reuse
final event / queue / sticky-state cleanliness checks
```

The goal is not to add a new RTL queue architecture, a new CSR window, or a new datapath feature.  The goal is to validate that the already-implemented P19/P20/P21/P22/P23/P24 runtime stack remains reusable across repeated host sessions and mixed robustness scenarios.

Current baseline entering P25A:

```text
P24 queue timeout / watchdog closure:
  TOTAL : 132
  PASS  : 132
  FAIL  : 0
```

Current closure after P25G:

```text
P25 runtime stress / robustness closure:
  TOTAL : 135
  PASS  : 135
  FAIL  : 0
```

---

## 2. Baseline Before P25

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
CQ completion records committed into host-visible completion memory
SQ_HEAD / CQ_TAIL pointer advancement after completion commit
CQ_HEAD host recovery during active queue service
STOP_QUEUE / STOP_AFTER_THIS graceful command-boundary stop behavior
QUEUE_ERROR_EVENT based runtime wake-up and cleanup
COMMAND_TIMEOUT_ERROR structured queue error reporting
full regression 132/132 PASS after P24G/P24H
```

P25 must preserve:

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
BRAM / GEMM / DMA / AXI-Stream / Direct Stream datapath behavior
```

P25 should be implemented as UVM runtime helper extensions and representative stress tests.  It should not require BRAM, GEMM, DMA, AXI-Stream, Direct Stream, descriptor-format, completion-format, SQ-format, CQ-format, or CSR-address changes.

---

## 3. P25 Design Intent

P19 through P24 validate individual capabilities and bounded recovery paths.  P25 validates whether those capabilities compose under a software-like runtime model over more than one short command sequence.

Without P25, validation can remain feature-centric:

```text
one test checks multi-command drain
one test checks runtime append
one test checks event notification
one test checks CQ full recovery
one test checks STOP_QUEUE
one test checks timeout recovery
```

P25 introduces a stress-centric view:

```text
start a runtime session
submit commands
wait on event notification
consume CQ at different timing points
clear and re-arm events
append while active
stop or timeout one session
clean sticky state
restart or run a new session
compare results
prove final queue/event state is reusable
```

Concise intent:

```text
P25 is a UVM runtime stress milestone above the validated queue, event, host-runtime, and timeout stack.
It validates repeated runtime sessions, live append timing, CQ consume timing variation, STOP_QUEUE handling, timeout recovery, and final queue/event cleanliness without changing the hardware datapath.
```

---

## 4. P25A Scope

### 4.1 Included

P25A defines:

```text
runtime stress / robustness design intent
multi-session queue runtime stress policy
runtime append while active stress policy
CQ consume timing variation policy
STOP_QUEUE plus pending runtime append policy
timeout-triggered recovery policy
post-error / post-stop cleanup policy
final event / queue / sticky-state cleanliness policy
expected UVM helper extension direction for P25B
validation plan for P25C through P25G
full-regression closure plan
```

### 4.2 Not Included

P25A does not include:

```text
RTL implementation
CSR RTL changes
new CSR addresses
new SQ or CQ entry format
new descriptor format
new completion record size
new interrupt/event bit allocation
new timeout CSR field
new BRAM / scratchpad behavior
new GEMM datapath behavior
new DMA / frontend datapath behavior
multi-outstanding queue execution
out-of-order completion
preemption or cancellation
Linux driver
C software driver
UVM RAL model
cache-coherent host memory ordering
```

P25A is a specification milestone.  The implementation work is expected to live in UVM helper/test files and existing full-regression integration scripts.

---

## 5. Fixed P25 Design Decisions

```text
Stress location               : UVM host runtime helper and tests
Hardware queue model          : existing P19/P20/P21 queue controller
Notification model            : existing P22 event CSR / event_irq semantics
Runtime model                 : existing P23 event-driven host runtime style
Timeout model                 : existing P24 CMD_TIMEOUT_CYCLES watchdog policy
Command execution             : one active command at a time
Completion order              : in-order CQ records
SQ entry format               : existing P19 64-byte SQ command entry
CQ entry format               : existing P18 64-byte completion record
Event pending/clear           : existing P22 W1C / CLEAR_EVENT_PENDING policy
CQ consume policy             : host consumes CQ records before advancing CSR_CQ_HEAD
Runtime append policy         : host writes SQ payload, writes VALID last, then updates CSR_SQ_TAIL
STOP_QUEUE policy             : stop after active command; suppress pending runtime append until restart
Timeout recovery policy       : QUEUE_ERROR_EVENT wakes host; host clears event/queue/lower sticky state
BRAM / GEMM / DMA / frontend  : unchanged
```

P25 does not redefine the queue or event hardware.  It validates that the software-visible runtime model remains deterministic and reusable under repeated and mixed host actions.

---

## 6. Runtime Stress Themes

P25 focuses on robustness patterns that are closer to host-driver behavior than isolated hardware feature tests.

### 6.1 Multi-Session Runtime Reuse

A session is a host-visible queue service interval:

```text
initialize or clean queue/event state
submit one or more SQ commands
start or doorbell the queue
wait on event notification
consume CQ records
advance CQ_HEAD
clear/re-arm event bits
observe drained / stopped / error terminal state
```

P25 validates that the queue and event layer can be reused across multiple sessions without relying on reset between sessions.

### 6.2 Runtime Append While Active

The host may append commands while `queue_busy=1`:

```text
write appended SQ payload first
write CMD_CONTROL.VALID last
update CSR_SQ_TAIL as the runtime doorbell
hardware observes the new SQ_TAIL only at command boundaries
active command snapshot remains isolated from host pointer writes
```

P25 stresses append timing across command boundaries and event handling points.

### 6.3 CQ Consume Timing Variation

The host may consume CQ records immediately, delay consumption, or consume after multiple event observations.

P25 validates:

```text
completion commit is visible before CQ_TAIL advancement
event notification does not replace CQ record inspection
host advances CQ_HEAD only after consuming valid CQ records
late CQ consumption does not corrupt later runtime append behavior
final CQ occupancy / CQ space reports are clean after consumption
```

### 6.4 STOP_QUEUE With Pending Runtime Append

P25 validates that `STOP_QUEUE` wins over runtime append after the active command:

```text
active SQ command completes normally
CQ record commits normally
STOPPED_AFTER_COMMAND / QUEUE_STOPPED_EVENT is observed
runtime-appended pending SQ entry is not auto-consumed in the stopped session
host may restart the queue later to consume the pending entry
```

### 6.5 Timeout / Error Recovery

P25 validates P24 timeout recovery in a mixed runtime stress context:

```text
submit finite-timeout command
observe COMMAND_TIMEOUT_ERROR
observe P22 QUEUE_ERROR_EVENT
consume timeout CQ record if one exists
W1C clear handled event bits
clear queue sticky error/reject state
clear lower-level sticky state when required
submit a known-good timeout-disabled command
observe normal CQ completion and result compare
```

### 6.6 Final Cleanliness

At the end of each stress test, the host runtime should verify:

```text
event pending bits are clean or intentionally disabled
queue is reusable
queue error status is zero
queue reject status is zero
CQ records expected by the test are consumed
SQ/CQ pointer state matches the test expectation
result compare passes when the command is expected to produce GEMM output
```

---

## 7. P25B Host Runtime Stress Helper Direction

P25B should extend the existing P23 host runtime helper rather than duplicating long CSR/memory sequences in each stress test.

Recommended helper responsibilities:

```text
runtime session setup and cleanup
SQ/CQ memory initialization
P17 descriptor table programming
SQ command construction with user tags and timeout budgets
event enable/global-enable programming
event wait / pending decode / W1C acknowledge
CQ record read / commit validation / optional clear
CQ_HEAD advancement
queue sticky clear / lower-level sticky clear
runtime append publication through CSR_SQ_TAIL
STOP_QUEUE request handling
final queue/event clean checks
result compare bridge integration where applicable
```

Suggested helper API direction:

```systemverilog
task host_rt_stress_init_session(...);
task host_rt_stress_submit_cmd(...);
task host_rt_stress_append_cmd_while_active(...);
task host_rt_stress_wait_and_consume_cq(...);
task host_rt_stress_delay_cq_consume(...);
task host_rt_stress_issue_stop_queue(...);
task host_rt_stress_expect_timeout_error(...);
task host_rt_stress_clear_queue_event_and_lower_sticky(...);
task host_rt_stress_check_final_clean(...);
```

The exact names may follow the current project style.  The helper should remain a thin abstraction above existing CSR helper calls, queue programming routines, descriptor-memory helpers, CQ readback routines, and result-compare infrastructure.

---

## 8. P25 UVM Validation Plan

Final P25 milestone split:

```text
P25A: Runtime stress / robustness prototype spec                  PASS
P25B: Event-driven host runtime stress helper extension           PASS
P25C: Multi-session queue runtime stress smoke                    PASS
P25D: Runtime append + CQ consume timing variation smoke          PASS
P25E: STOP / timeout / recovery mixed stress smoke                PASS
P25F: Full regression integration                                 PASS
P25G: Documentation closure                                       PASS
```

### 8.1 P25C Multi-Session Queue Runtime Stress Smoke

Purpose:

```text
run multiple queue runtime sessions without reset
submit one or more SQ commands per session
wait on P22 event notification
consume CQ records per session
advance CQ_HEAD per session
clear/re-arm event pending bits per session
confirm queue can be restarted and reused
compare results for each expected GEMM-producing command
```

Suggested test name:

```text
ai_accel_subsys_csr_event_driven_multi_session_stress_test
```

Expected PASS marker:

```text
[P25C_HOST_RT/PASS]
```

### 8.2 P25D Runtime Append + CQ Consume Timing Variation Smoke

Purpose:

```text
start queue with an initial SQ command
append another SQ command while active
vary when CQ records are consumed and CQ_HEAD is advanced
verify event clear/re-arm still works after delayed consumption
verify appended command completion appears in order
verify final SQ_HEAD / CQ_TAIL / CQ_HEAD state
compare result payloads where applicable
```

Suggested test name:

```text
ai_accel_subsys_csr_event_driven_append_consume_stress_test
```

Expected PASS marker:

```text
[P25D_HOST_RT/PASS]
```

### 8.3 P25E STOP / Timeout / Recovery Mixed Stress Smoke

Purpose:

```text
STOP_QUEUE live-service phase:
  start SQ[0]
  append SQ[1] while active
  issue STOP_QUEUE
  verify SQ[1] is not auto-consumed
  consume CQ[0]
  restart queue
  complete pending SQ[1]
  consume CQ[1]
  cleanup events
  compare results

Timeout recovery phase:
  submit finite-timeout command
  observe COMMAND_TIMEOUT_ERROR
  observe QUEUE_ERROR_EVENT
  W1C acknowledge event pending bits
  clear queue / lower-level sticky state
  submit valid timeout-disabled command
  observe normal CQ completion
  consume CQ
  cleanup events
  compare results

Final reusable check:
  event pending clean
  queue reusable
  queue error / reject clear
```

Suggested test name:

```text
ai_accel_subsys_csr_event_driven_stop_timeout_recovery_stress_test
```

Expected PASS markers:

```text
[P25E_HOST_RT/STOP_PASS]
[P25E_HOST_RT/TIMEOUT_RECOVERY_PASS]
[P25E_HOST_RT/PASS]
```

---

## 9. Full Regression Plan

P25F adds the three representative stress tests to full regression.

Validated full-regression representatives:

```text
csr_event_driven_multi_session_stress_case102
csr_event_driven_append_consume_stress_case102
csr_event_driven_stop_timeout_recovery_stress_case102
```

Expected count increase:

```text
Before P25F: 132
After P25F : 135
```

Validated P25F/P25G result:

```text
TOTAL : 135
PASS  : 135
FAIL  : 0
```

This keeps P25 representative rather than exhaustive.  Longer random stress, randomized SQ/CQ depths, randomized event masks, and larger command batches can remain future extensions.

---

## 10. P25 Closure Criteria

P25 is complete when:

```text
P25A runtime stress / robustness prototype spec is complete
P25B runtime stress helper extension is implemented
multi-session queue runtime stress passes
runtime append + CQ consume timing variation stress passes
STOP_QUEUE + timeout recovery mixed stress passes
P25 representatives are integrated into full regression
full regression passes at 135/135
README / CSR / queue / event / runtime / timeout docs record P25 closure
uvm_regression.list records 135 regression items
no BRAM / GEMM / DMA / frontend datapath changes are required
```

---

## 11. Relationship to Existing Specs

P25 composes earlier validated policies rather than replacing them:

```text
P19 command/completion queue:
  SQ/CQ entry formats, pointer ownership, in-order completion

P20 multi-entry queue drain:
  repeated command execution with one active command at a time

P21 runtime doorbell / live queue service:
  host-owned SQ_TAIL and CQ_HEAD writes during active service

P22 event notification / interrupt-lite:
  sticky event pending, enable/global-enable, W1C clear/re-arm

P23 event-driven host runtime:
  driver-style submit / wait / consume / clear / re-arm model

P24 queue timeout / watchdog:
  CMD_TIMEOUT_CYCLES, COMMAND_TIMEOUT_ERROR, QUEUE_ERROR_EVENT recovery
```

P25's value is proving that these pieces remain deterministic when exercised together under repeated runtime-session stress.

---

## 12. Interview Notes

A concise interview explanation:

```text
P25 was my runtime robustness milestone.  By this point the queue, completion queue, event notification, host-runtime helper, and timeout watchdog already worked in targeted tests.  P25 did not add a new datapath feature; it validated that the software-visible accelerator model could survive realistic runtime sequences: repeated sessions, appends while the queue was active, different CQ consume timing, STOP_QUEUE with pending work, timeout-triggered QUEUE_ERROR_EVENT recovery, and a final reusable queue/event state.  This is important because a host-programmable accelerator is not only about computing one GEMM correctly; it also has to be restartable, observable, and recoverable across command sessions without reset.
```


*/
