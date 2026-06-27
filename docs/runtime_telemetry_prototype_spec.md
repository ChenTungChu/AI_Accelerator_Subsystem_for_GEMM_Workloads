# P29 Runtime Telemetry / Queue Performance Counters Prototype Spec

## 1. Purpose

This document defines the P29 runtime telemetry / queue performance counters prototype for the AI Accelerator Subsystem.

P17 through P28 established a host-programmable runtime stack:

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
    -> P26 queue lifecycle / soft-reset / reinit validation
    -> P27 memory access guard / address range validation
    -> P28 event coalescing / interrupt moderation
```

P28 proved that the host can consume CQ records in batches instead of taking one interrupt per completion.

P29 adds the next runtime observability layer:

```text
Allow hardware and UVM to measure how the runtime is being used.
```

The goal is not to change command execution, CQ format, event semantics, or the P28 coalescing policy.  The goal is to expose enough telemetry for host software and verification to answer practical questions:

```text
How many commands were accepted?
How many commands completed?
How many CQ records were committed?
How many host CQ records were consumed?
How many event IRQ opportunities were generated?
How often did moderation reduce notification rate?
How often did threshold release or timer fallback occur?
How much time did the queue spend busy, idle, or stalled?
How often did CQ full, STOP_QUEUE, timeout, or guard recovery paths occur?
```

Current baseline entering P29A:

```text
P28 event coalescing / interrupt moderation closure:
  TOTAL : 144
  PASS  : 144
  FAIL  : 0
```

---

## 2. Baseline Before P29

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
P25 runtime stress / robustness validation
P26 queue lifecycle cleanup, soft-reset, and reinit validation
P27 host-visible memory access guard and recovery validation
P28 event coalescing, moderation timer fallback, and batch CQ consume validation
CQ completion records committed into host-visible completion memory
SQ_HEAD / CQ_TAIL pointer advancement after completion commit
CQ_HEAD host recovery during active queue service
QUEUE_COMMAND_COMPLETED_EVENT / CQ_NOT_EMPTY_EVENT notification
CQ threshold / timer-based event moderation
QUEUE_ERROR_EVENT notification for timeout and memory-guard failures
full regression 144/144 PASS after P28G/P28H
```

P29 must preserve:

```text
one active command at a time
in-order command execution
in-order completion production
one CQ record per completed command
P18 completion record format
P19 SQ entry format
P19/P20/P21 queue CSR behavior
P22 event CSR pending / enable / W1C / IRQ behavior
P23 host runtime programming model
P24 timeout / watchdog reporting model
P26 lifecycle cleanup and reinit behavior
P27 memory guard error/event/recovery behavior
P28 event moderation threshold / timer / re-arm behavior
BRAM / GEMM / DMA / AXI-Stream / Direct Stream datapath behavior
```

P29 should be implemented as an observability and counter layer over the existing queue/event/runtime stack.  It should not require multi-outstanding command execution, out-of-order completion, CQ format changes, descriptor format changes, or datapath changes.

---

## 3. P29 Design Intent

P19 through P28 make the accelerator look like a small but robust host-controlled device.  A driver can submit work through SQ memory, receive CQ records, wait on events, handle CQ-full conditions, stop/restart sessions, recover from timeout, reject unsafe memory addresses, and reduce interrupts with event moderation.

The next runtime question is:

```text
Can software observe whether the runtime is efficient and healthy?
```

Without P29, correctness is visible through CQ records, event pending bits, queue status, and individual milestone debug registers.  That is enough to run directed tests, but it is not enough to build a concise performance or health profile of the runtime.

P29 defines a telemetry contract:

```text
Queue service counters summarize accepted commands, completed commands, CQ commits, and host CQ consumption.
Event telemetry summarizes event captures, IRQ eligibility, moderation releases, and completion-to-IRQ reduction.
Stall telemetry summarizes CQ-full stalls, CQ-space recovery, timeout/error/guard recovery, stopped/drained sessions, and queue reusable state.
Cycle counters summarize busy / idle / stalled time at the queue-runtime level.
Snapshot and clear policy lets software sample telemetry without disturbing functional state.
```

Concise intent:

```text
P29 turns the runtime from functionally correct and interrupt-efficient into measurable and tunable.
```

---

## 4. P29A Scope

### 4.1 Included

P29A defines:

```text
runtime telemetry concept
queue counter categories
event / interrupt efficiency counter categories
P28 moderation efficiency measurement direction
queue busy / idle / stalled cycle measurement direction
host CQ consumption observation direction
recovery / lifecycle / guard / timeout telemetry direction
snapshot and clear policy direction
relationship to existing P21/P22/P23/P24/P26/P27/P28 behavior
UVM validation direction for basic counters, interrupt efficiency, and recovery telemetry
P29B/P29C/P29D/P29E/P29F/P29G/P29H milestone plan
```

### 4.2 Not Included

P29A does not include:

```text
RTL implementation
CSR RTL changes
canonical CSR address map
canonical register bit fields
canonical access types
canonical reset values
new SQ entry format
new CQ completion record format
new P18 completion record format
new event source allocation
new timeout/watchdog policy
new memory guard policy
BRAM / scratchpad changes
GEMM datapath changes
DMA / AXI-Stream / Direct Stream datapath changes
multi-outstanding command execution
out-of-order completion
MSI/MSI-X implementation
Linux driver
C software driver
UVM RAL model
standalone telemetry top
standalone telemetry simulation flow
```

P29A is a prototype specification milestone only.  P29B should freeze the CSR policy and place any canonical register map, register bit fields, access types, and reset values in `axi_lite_csr_control_plane_spec.md`.

---

## 5. Fixed P29A Design Decisions

```text
Telemetry target              : existing CSR wrapper and queue/event runtime stack
Data authority                : CQ records remain authoritative for per-command completion detail
Execution model               : still one active command at a time
Completion order              : still in-order CQ records
CQ record production          : still one record per completed command
Event model                   : P22/P28 event pending / W1C / moderation behavior unchanged
Telemetry role                : observe and count, not schedule or alter runtime behavior
Reset compatibility           : counters reset to zero; functional behavior unchanged
SQ entry format               : unchanged for P29A
CQ entry format               : unchanged for P29A
Descriptor format             : unchanged for P29A
Completion record format      : unchanged for P29A
Lifecycle model               : reuse existing P26 cleanup / reinit policy
Memory safety model           : reuse existing P27 guard policy
Interrupt moderation model    : reuse existing P28 threshold / timer / re-arm policy
CSR map                       : P29B canonical fields frozen in CSR spec
```

P29A treats telemetry as an observational layer.  It does not redefine command execution, CQ commit, pointer advancement, event pending capture, moderation release, or error handling.

---

## 6. Telemetry Categories

P29A groups telemetry into queue service, CQ consumption, event / interrupt efficiency, moderation, stall / recovery, and cycle accounting categories.

### 6.1 Queue Service Telemetry

Queue service telemetry should answer:

```text
how many SQ commands were accepted by hardware
how many commands reached terminal completion
how many CQ records were committed
how many queue sessions started, drained, stopped, or errored
whether the final queue pointer state is reusable
```

Recommended first counter categories:

```text
queue_start_count
sq_command_accept_count
queue_command_complete_count
cq_commit_count
queue_drained_count
queue_stopped_count
queue_error_count
last_accepted_user_tag
last_completed_user_tag
```

The first implementation may reuse existing P19/P22/P26 debug state where possible, but P29 should provide a consolidated telemetry view suitable for performance and health checks.

### 6.2 Host CQ Consumption Telemetry

The existing hardware already observes host writes to `CSR_CQ_HEAD` because that register is host-owned.  P29 can use this observation to estimate host CQ consumption behavior.

Recommended first policy:

```text
count each accepted host CQ_HEAD advancement
accumulate the positive delta between old CQ_HEAD and new CQ_HEAD
track max positive CQ_HEAD delta as max observed host batch consume size
ignore non-advancing writes for consumption count
flag or count invalid backwards CQ_HEAD writes through existing queue reject/error policy if already implemented
```

This gives software and UVM a simple way to validate batch CQ service:

```text
P28D/P28F batch consume of two CQ records should contribute a CQ_HEAD delta of 2
P28E sparse timer fallback consume should contribute a CQ_HEAD delta of 1
```

P29A does not require hardware to know the host's software batch budget.  It only observes the published CQ_HEAD updates.

### 6.3 Event / Interrupt Efficiency Telemetry

P22 already has event count and IRQ count fields.  P28 adds moderation release debug counters.  P29 should consolidate these into a runtime efficiency view.

Useful questions:

```text
how many completion-style CQ records were produced
how many interrupt-eligible notifications were generated
how many completion records were covered by one notification
whether threshold moderation reduced IRQ rate
whether timer fallback bounded sparse-workload latency
```

Recommended first counter categories:

```text
event_capture_count
irq_eligible_count
completion_style_event_count
completion_cq_commit_count
coalesced_release_count
threshold_release_count
timer_release_count
urgent_bypass_count
```

Derived software metrics:

```text
completions_per_irq = completion_cq_commit_count / max(irq_eligible_count, 1)
irq_reduction_estimate = completion_cq_commit_count - irq_eligible_count
threshold_release_ratio = threshold_release_count / max(coalesced_release_count, 1)
timer_release_ratio = timer_release_count / max(coalesced_release_count, 1)
```

The hardware does not need to divide counters in P29A.  UVM or software can compute ratios from raw counters.

### 6.4 P28 Moderation Telemetry

P29 should make P28's value visible as numbers.

P28 already validates:

```text
threshold release after CQ occupancy reaches threshold
timer fallback release when threshold is not reached
batch CQ consume after one wakeup
W1C / re-arm without lost notification
```

P29 telemetry should allow UVM to prove:

```text
CQ commits can be greater than IRQ count
threshold release count increments for busy command batches
timer release count increments for sparse command batches
host consumed count matches CQ commit count after service
max CQ batch size reaches the expected batch size in P28F-like flows
```

P29 should not change the P28 event moderation release policy.  It only counts and snapshots it.

### 6.5 Stall / Recovery Telemetry

P21 through P27 already validate several recovery paths.  P29 should make those paths observable through counters.

Recommended first counter categories:

```text
cq_full_stall_count
cq_space_recovered_count
runtime_doorbell_count
runtime_append_consumed_count
timeout_error_count
memory_guard_error_count
stop_queue_request_count
stopped_session_count
drained_session_count
lifecycle_reinit_count
```

P29A does not require a new event source for these counters.  They can be driven from existing queue/event/lifecycle source points.

### 6.6 Cycle Telemetry

Cycle counters provide a coarse runtime profile.

Recommended first cycle categories:

```text
queue_enabled_cycles
queue_busy_cycles
queue_idle_cycles
queue_stalled_cycles
cq_full_stall_cycles
lower_level_wait_cycles
```

The first implementation should keep cycle accounting simple and deterministic:

```text
increment at most once per dma_clk cycle
use mutually understandable queue state predicates
clear counters only through an explicit telemetry clear command or reset
```

P29A does not require fine-grained per-stage timing histograms.  Per-stage counters can be a later milestone if needed.

---

## 7. Snapshot and Clear Model

P29 should support a predictable sample / clear workflow.

Recommended software workflow:

```text
run queue workload
wait for terminal event or desired sample point
optionally request telemetry snapshot
read telemetry counters
compute software-side ratios
optionally clear telemetry counters
run next workload
```

P29B should freeze whether the first implementation uses live counters, latched snapshots, or both.

Recommended first policy:

```text
live counters are readable at any time
snapshot command latches a coherent debug snapshot for multi-register reads
clear command resets counters and snapshots without changing functional queue state
clear command must not clear queue done/error, event pending, memory guard status, or CQ records
```

Telemetry clear must be observational only:

```text
clearing telemetry must not restart the queue
clearing telemetry must not clear SQ/CQ pointers
clearing telemetry must not clear P22 event pending bits
clearing telemetry must not clear P24 timeout status
clearing telemetry must not clear P27 memory guard diagnostics
```

---

## 8. Host Software View

P29 provides host software with a compact runtime health profile.

Example host-side checks:

```text
accepted command count equals the number of valid submitted SQ commands
completed command count equals CQ commit count for normal completions
host consumed count catches up to CQ commit count after CQ service
IRQ count is lower than CQ commit count when moderation batches completions
threshold release count increases during busy command streams
timer release count increases during sparse command streams
CQ full stall count increases only when CQ space is exhausted
memory guard error count increases only for guard-rejected commands
queue busy / stalled cycles are non-zero in expected stress cases
```

This is useful for both UVM and future software driver bring-up.

---

## 9. Interaction with Existing Milestones

### 9.1 Relationship to P21 Runtime Doorbell / Live Queue Service

P29 does not change runtime SQ_TAIL observation.

Existing P21 policy remains:

```text
host may append SQ entries while queue_busy=1
hardware observes live SQ_TAIL only at command boundaries
active command uses snapshotted SQ/CQ context
CQ-full command-boundary stall recovers when host advances CQ_HEAD
```

P29 may count runtime doorbell writes and runtime append consumption, but it must not change when appends are observed.

### 9.2 Relationship to P22 Events

P29 does not change the P22 event pending model.

P22 fundamentals remain:

```text
event pending capture is independent of interrupt enable
event_irq is derived from pending & enable & global_irq
W1C clears sticky pending bits
CQ completion record remains authoritative per-command detail
```

P29 may count event captures and IRQ-eligible assertions.  It must not redefine W1C, enable, global IRQ, or snapshot behavior.

### 9.3 Relationship to P23 Host Runtime

P29 should extend the existing UVM host runtime helper rather than creating a new UVM top or separate sim flow.

New helper behavior should be shaped like:

```text
capture telemetry snapshot
read telemetry counter set
clear telemetry counters
check expected counter deltas around queue workloads
compute software-side interrupt efficiency ratios
log a concise runtime profile
```

### 9.4 Relationship to P24 Timeout

P29 telemetry should count timeout occurrence, but it does not change timeout policy.

```text
P24 timeout still indicates failed command progress and sets queue error.
P29 timeout telemetry only counts or snapshots that timeout happened.
```

P29 must not convert a telemetry overflow or clear operation into a P24 timeout.

### 9.5 Relationship to P26 Lifecycle

P29 should not add a new lifecycle model.

After a stopped, drained, timeout, guard, or other error terminal condition, the host continues to use the P26 cleanup / reinit model:

```text
observe terminal event
consume any valid CQ records if present
clear event pending bits
clear queue / lower-level / guard sticky status as required
reinitialize or restart the session according to P26 policy
```

P29 may count drained-session cleanup, stopped-session restart, and timeout/error reinit sequences only if those source points are available in the existing helper/RTL structure.

### 9.6 Relationship to P27 Memory Guard

P29 telemetry should count memory guard failures, but it does not change guard policy.

If a memory guard failure reaches queue error:

```text
QUEUE_ERROR_EVENT still wakes the host promptly
CSR_QUEUE_ERROR_STATUS[9] remains authoritative
CSR_MEM_GUARD_* diagnostics remain authoritative
P29 memory guard telemetry is a summary count only
```

### 9.7 Relationship to P28 Event Moderation

P29 measures P28 efficiency.

P28 fundamentals remain:

```text
completion-style events may be coalesced only when moderation is enabled
threshold release occurs when CQ occupancy reaches the programmed threshold
timer release occurs when sparse CQ work waits past the timer limit
urgent events bypass moderation
W1C / re-arm must not lose notification when CQ remains non-empty
```

P29 telemetry should not influence whether a threshold or timer release occurs.  It only counts releases and host-visible outcomes.

---

## 10. Counter Width and Overflow Direction

P29A recommends simple saturating or wrapping counters, but P29B should freeze the exact policy.

Recommended first direction:

```text
32-bit counters for software-visible telemetry
increment by one for source-event counters
increment by delta for host CQ consumption counters
wrap on overflow unless P29B chooses sticky overflow bits
clear by explicit telemetry clear command
reset to zero on dma_rst_n reset
```

Rationale:

```text
32-bit counters are simple for AXI-Lite reads
UVM milestone tests are short and do not need overflow validation
software can periodically sample and clear counters
sticky overflow can be added later without changing the basic telemetry model
```

P29A does not require hardware division, ratios, histograms, or floating-point metrics.

---

## 11. UVM Validation Strategy

P29 validation should reuse the existing CSR wrapper top and event-driven queue runtime style.

Common test setup:

```text
UVM_TOP = ai_accel_subsys_csr_uvm_top
CASE_ID = 102 or focused representative case
ENABLE_RESULT_CHECK = 0 for telemetry-policy tests unless final known-good command compares results
FORCE_HELPER_MEM_PATH = 0
DMA_CLK_PERIOD_NS = 10
CORE_CLK_PERIOD_NS = 14
```

Common expected behavior:

```text
telemetry counters reset to zero after reset or clear
telemetry reads do not change functional queue/event state
accepted command count matches valid SQ command acceptance
completed command count matches CQ commit count for valid commands
host consumed count matches positive CQ_HEAD advancement
IRQ count and moderation release counts match P28D/P28E/P28F-style flows
CQ full / timeout / guard recovery counters increment only in matching recovery tests
UVM_ERROR == 0
UVM_FATAL == 0
```

Suggested debug markers:

```text
[P29_TEL/CLEAR_PASS]
[P29_TEL/BASIC_COUNTER_PASS]
[P29_TEL/IRQ_EFFICIENCY_PASS]
[P29_TEL/BATCH_COUNTER_PASS]
[P29_TEL/STALL_RECOVERY_PASS]
[P29_TEL/PASS]
```

---

## 12. P29 Milestone Plan

Recommended P29 split:

```text
P29A: Runtime telemetry prototype spec                           PASS
P29B: Telemetry CSR policy / counter map freeze                  PASS
P29C: Queue/event telemetry counter RTL integration              TODO
P29D: Basic telemetry counter smoke                              TODO
P29E: Interrupt efficiency / coalescing telemetry smoke          TODO
P29F: Stall / recovery telemetry smoke                           TODO
P29G: full regression integration                                TODO
P29H: documentation closure                                      TODO
```

### 12.1 P29B Telemetry CSR Policy / Counter Map Freeze

P29B freezes the first software-visible telemetry CSR policy.

Frozen P29B decisions:

```text
P29 allocates one new runtime telemetry CSR window after the P27 memory guard window.
P29 telemetry is disabled by reset to preserve existing behavior unless software explicitly enables it.
P29 counters are live 32-bit software-readable counters.
P29 counters wrap on overflow in the first prototype.
P29 does not add sticky overflow reporting in the first prototype.
P29 does not add hardware ratio/division registers in the first prototype.
P29 telemetry clear is observational only and must not clear functional queue/event/guard state.
P29 does not add a new event source.
P29 does not change SQ, CQ, descriptor, or completion record formats.
```

Frozen P29B telemetry window:

```text
P29 runtime telemetry CSR window : 0x6C0 - 0x73C
```

Frozen first-prototype counter groups:

```text
queue service counters
host CQ consumption counters
event / IRQ efficiency counters
P28 moderation release counters
stall / recovery counters
queue runtime cycle counters
```

Frozen source policy:

```text
queue service counters are driven from existing P19/P20/P21 queue accept / complete / drained / stopped / error points
host CQ consumption counters observe positive CSR_CQ_HEAD write deltas
event / IRQ counters observe existing P22 event capture and IRQ-eligible source points
P28 moderation counters observe existing P28 release source points
stall / recovery counters observe existing CQ-full, CQ-space, timeout, guard, and STOP_QUEUE source points
cycle counters increment once per dma_clk cycle when telemetry and cycle counting are enabled
```

Canonical register map, register bit fields, access types, and reset values are recorded only in:

```text
docs/axi_lite_csr_control_plane_spec.md
```

P29B is a policy-freeze documentation checkpoint.  It does not add RTL, UVM tests, Tcl changes, README updates, regression-list items, a standalone UVM top, a standalone sim flow, SQ/CQ format changes, descriptor format changes, completion record format changes, or datapath behavior changes.

### 12.2 P29C Queue/Event Telemetry Counter RTL Integration

P29C should integrate the first telemetry counter block into the existing CSR wrapper path.

Recommended implementation direction:

```text
reuse ai_accel_csr_regs as the CSR-visible counter owner
source queue/event/moderation pulses from existing P19/P22/P28 logic
observe host CQ_HEAD write deltas for host consume telemetry
capture queue busy / idle / stalled cycle counts in dma_clk
provide clear and optional snapshot behavior through the frozen P29B CSR policy
```

P29C should avoid:

```text
new standalone top
new standalone sim flow
new SQ/CQ format
new descriptor format
new completion format
BRAM or GEMM datapath changes
```

### 12.3 P29D Basic Telemetry Counter Smoke

Purpose:

```text
validate telemetry reset / clear behavior
validate accepted command count
validate completed command count
validate CQ commit count
validate host CQ_HEAD consumption count
validate queue busy / idle cycle counters are sane
validate reads do not disturb queue/event functional state
```

Suggested test name:

```text
ai_accel_subsys_csr_runtime_telemetry_basic_smoke_test
```

Expected PASS markers:

```text
[P29_TEL/CLEAR_PASS]
[P29_TEL/BASIC_COUNTER_PASS]
[P29_TEL/CQ_CONSUME_COUNTER_PASS]
[P29_TEL/CYCLE_COUNTER_PASS]
[P29_TEL/PASS]
```

### 12.4 P29E Interrupt Efficiency / Coalescing Telemetry Smoke

Purpose:

```text
validate P28 threshold batching is visible through telemetry
validate CQ commits can exceed IRQ count
validate threshold release counter increments
validate timer release counter increments in sparse mode
validate max host CQ consume batch size is captured
validate software-side completions-per-IRQ ratio is greater than one for threshold batching
```

Suggested test name:

```text
ai_accel_subsys_csr_runtime_telemetry_irq_efficiency_smoke_test
```

Expected PASS markers:

```text
[P29_TEL/IRQ_EFFICIENCY_PASS]
[P29_TEL/THRESHOLD_RELEASE_COUNTER_PASS]
[P29_TEL/TIMER_RELEASE_COUNTER_PASS]
[P29_TEL/BATCH_SIZE_PASS]
[P29_TEL/PASS]
```

### 12.5 P29F Stall / Recovery Telemetry Smoke

Purpose:

```text
validate CQ-full stall counter and cycle count
validate CQ-space recovered counter
validate STOP_QUEUE / stopped-session telemetry
validate timeout error telemetry
validate memory guard error telemetry
validate post-recovery telemetry remains readable and clearable
```

Suggested test name:

```text
ai_accel_subsys_csr_runtime_telemetry_stall_recovery_smoke_test
```

Expected PASS markers:

```text
[P29_TEL/CQ_FULL_STALL_PASS]
[P29_TEL/CQ_SPACE_RECOVERY_PASS]
[P29_TEL/STOP_RECOVERY_PASS]
[P29_TEL/TIMEOUT_COUNTER_PASS]
[P29_TEL/GUARD_COUNTER_PASS]
[P29_TEL/PASS]
```

### 12.6 P29G Full Regression Integration

P29G should add a small representative subset to the full regression.

Recommended full-regression items:

```text
csr_runtime_telemetry_basic_case102
csr_runtime_telemetry_irq_efficiency_case102
csr_runtime_telemetry_stall_recovery_case102
```

Expected full-regression count if three items are added:

```text
Before P29G : 144
After P29G  : 147
```

### 12.7 P29H Documentation Closure

P29H should update:

```text
README.md
axi_lite_csr_control_plane_spec.md
runtime_telemetry_prototype_spec.md
uvm_regression.list
run_full_uvm_regression.tcl
```

The CSR map remains canonical only in `axi_lite_csr_control_plane_spec.md`.

---

## 13. P29A Closure Criteria

P29A is complete when:

```text
runtime telemetry purpose and scope are documented
queue service telemetry categories are identified
host CQ consumption telemetry direction is identified
event / interrupt efficiency telemetry direction is identified
P28 moderation efficiency measurement direction is identified
stall / recovery telemetry direction is identified
cycle counter direction is identified
snapshot / clear model direction is documented
relationship to P21/P22/P23/P24/P26/P27/P28 is documented
P29B/P29C/P29D/P29E/P29F/P29G/P29H validation direction and PASS markers are documented
no RTL / CSR / Tcl / regression-list changes are required for P29A
```

P29A does not change the regression count.

Current expected status after P29A:

```text
P28H: Documentation closure                                      PASS
P29A: Runtime telemetry prototype spec                           PASS
Full regression remains:
  TOTAL : 144
  PASS  : 144
  FAIL  : 0
```

---


## 14. P29B Closure Criteria

P29B is complete when:

```text
runtime telemetry CSR window is frozen
first telemetry counter set is frozen
telemetry command / status / control policy is frozen
counter width and overflow policy are frozen
host CQ_HEAD delta observation policy is frozen
queue/event/moderation/stall/cycle source policy is frozen
clear behavior is defined as observational only
canonical register map, access types, reset values, and bit definitions are recorded only in the CSR spec
no RTL / UVM / Tcl / regression-list changes are required for P29B
```

P29B does not change the regression count.

Current expected status after P29B:

```text
P28H: Documentation closure                                      PASS
P29A: Runtime telemetry prototype spec                           PASS
P29B: Telemetry CSR policy / counter map freeze                  PASS
Full regression remains:
  TOTAL : 144
  PASS  : 144
  FAIL  : 0
```

---

## 15. Interview Notes

P29 is useful because it shows the accelerator runtime is not only correct, safe, and interrupt-efficient, but also measurable.

Concise explanation:

```text
After adding memory safety and interrupt moderation, I added runtime telemetry so software can quantify queue behavior, CQ batching efficiency, interrupt reduction, stalls, and recovery events. The command model stays single-active and in-order, but the host can now observe whether the runtime is healthy and whether coalescing is actually reducing wakeups.
```

Key points:

```text
Telemetry is observational; it does not change execution.
CQ records remain authoritative for per-command completion.
Queue counters show accepted and completed command flow.
Host CQ consumption counters show batch service behavior.
Event and IRQ counters quantify interrupt moderation efficiency.
Stall and recovery counters make CQ-full, timeout, STOP_QUEUE, and memory-guard behavior easier to debug.
Cycle counters provide a coarse runtime utilization profile.
P29 preserves existing SQ/CQ formats, P22 events, P28 moderation policy, and P27 memory-guard recovery.
```

Tradeoff explanation:

```text
The design intentionally avoids complex profiling hardware, histograms, or out-of-order execution.  The first telemetry layer is a small set of software-readable counters that are easy to validate, easy to explain, and directly useful for driver bring-up.
```


---

## P29C Queue/Event Telemetry Counter RTL Integration Checkpoint

P29C implements the first RTL integration checkpoint for the P29 runtime telemetry CSR window.

Files updated:

```text
rtl/csr/ai_accel_csr_regs.sv
```

P29C keeps telemetry observational.  The telemetry counters read queue, event, moderation, guard, and cycle source points that already exist in the CSR block.  They do not generate new queue commands, new event pending bits, new queue errors, or any lower-level datapath side effects.

Implemented telemetry CSR behavior:

```text
CSR_TELEM_VERSION reports 0x0001_0029
CSR_TELEM_CONTROL enables telemetry categories
CSR_TELEM_COMMAND.CLEAR_TELEMETRY_COUNTERS clears only telemetry counters / max trackers
telemetry is disabled by reset
all counters are 32-bit wrapping counters
```

Implemented counter source groups:

```text
Queue service counters observe START_QUEUE command writes, SQ command validation, CQ commit, drained, stopped, and queue error source points.
Host CQ consumption counters observe positive CSR_CQ_HEAD deltas and track max batch size.
Event / IRQ counters observe existing P22 event capture, IRQ eligibility, completion-style releases, and P28 moderation release causes.
Stall / recovery counters observe CQ-full stall, CQ-space recovery, timeout error, memory-guard error, and STOP_QUEUE request source points.
Cycle counters observe queue-enabled, busy, idle, CQ-full-stall, and lower-level wait cycles.
```

P29C does not add a standalone UVM top, standalone sim flow, new SQ/CQ format, new event bit, new queue policy, or BRAM/GEMM/DMA/frontend datapath change.

Current expected status after P29C implementation:

```text
P28H: Documentation closure                                      PASS
P29A: Runtime telemetry prototype spec                           PASS
P29B: Telemetry CSR policy / counter map freeze                  PASS
P29C: Queue/event telemetry counter RTL integration              PASS

Full regression remains:
  TOTAL : 144
  PASS  : 144
  FAIL  : 0
```


---

## P29D Basic Telemetry Counter Smoke Implementation Checkpoint

P29D adds the first targeted UVM validation for the P29 runtime telemetry CSR window.

Implementation files updated:

```text
tb/uvm/pkg/ai_accel_subsys_uvm_pkg.sv
tb/uvm/test/ai_accel_subsys_csr_basic_telemetry_counter_smoke_test.sv
```

P29D reuses the validated P23 event-driven two-command SQ/CQ queue drain path.  It enables the P29 telemetry CSR window, runs a two-command queue session, consumes the resulting CQ records through the existing host runtime helper, and checks that basic telemetry counters moved in the expected direction.

P29D validation flow:

```text
read CSR_TELEM_VERSION and check 0x0001_0029
verify telemetry is disabled by reset
issue CLEAR_TELEMETRY_COUNTERS while telemetry is disabled
verify selected counters are zero
enable telemetry, cycle counters, host-CQ-consume counters, and event-efficiency counters
run a two-command event-driven queue drain
wait for queue completion / CQ-not-empty / drained event notification
consume CQ[0] and CQ[1]
advance CQ_HEAD through the existing host runtime helper
W1C-ack handled event bits
check GEMM / DMA result compare still passes
check queue / CQ / event / IRQ / cycle telemetry counters
clear telemetry counters after the run and verify selected counters return to zero
```

Expected P29D PASS markers:

```text
[P29D_TELEM/RESET_PASS]
[P29D_TELEM/CLEAR_PASS]
[P29D_TELEM/ZERO_PASS]
[P29D_TELEM/ENABLE_PASS]
[P29D_TELEM/RUNTIME_COUNTERS_PASS]
[P29D_TELEM/PASS]
```

P29D checks these basic telemetry behaviors:

```text
telemetry reset disabled policy
telemetry CSR enable/status mirror behavior
CLEAR_TELEMETRY_COUNTERS clears telemetry counters only
accepted queue start count
SQ accepted command count
normal command completion count
CQ commit count
queue drained observation count
host CQ_HEAD positive update count
host CQ consumed delta count
event capture count
IRQ-eligible event count
completion-style event count
queue enabled / busy / idle cycle counters
zero error/stall/recovery counters for a clean queue session
```

P29D does not add RTL, a standalone UVM top, a standalone sim flow, a new CSR window, new event bits, SQ/CQ format changes, descriptor format changes, completion record format changes, or BRAM/GEMM/DMA/frontend datapath changes.

Current expected status after P29D implementation:

```text
P28H: Documentation closure                                      PASS
P29A: Runtime telemetry prototype spec                           PASS
P29B: Telemetry CSR policy / counter map freeze                  PASS
P29C: Queue/event telemetry counter RTL integration              PASS
P29D: Basic telemetry counter smoke                              IMPLEMENTED / RUN PENDING

Full regression remains:
  TOTAL : 144
  PASS  : 144
  FAIL  : 0
```
