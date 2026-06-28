# P30 Driver-Facing Runtime ABI Prototype Spec

## 1. Purpose

This document defines the P30 driver-facing runtime ABI prototype for the AI Accelerator Subsystem.

P19 through P29 established a host-programmable runtime stack:

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
    -> P29 runtime telemetry / queue performance counters
```

P29 proved that the host can measure accepted commands, completed commands, CQ commits, host CQ consumption, IRQ reduction, moderation releases, CQ-full stalls, CQ-space recovery, and queue runtime cycles.

P30 adds the next software-facing layer:

```text
Define the driver-visible programming contract for using the validated runtime stack.
```

The goal is not to add another hardware queue feature.  The goal is to specify how driver software should bring up the device, program memory objects, arm events, submit SQ work, consume CQ completions, use interrupt moderation, sample telemetry, and recover from expected runtime conditions.

Concise intent:

```text
P30 turns the validated queue/event/guard/moderation/telemetry hardware stack into a stable software-facing runtime ABI.
```

---

## 2. Baseline Before P30

The validated baseline entering P30 includes:

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
P29 runtime telemetry, interrupt-efficiency counters, and stall/recovery counters
CQ completion records committed into host-visible completion memory
SQ_HEAD / CQ_TAIL pointer advancement after completion commit
CQ_HEAD host recovery during active queue service
P22 event wait / W1C / re-arm runtime model
P28 threshold / timer-based event moderation
P29 software-readable telemetry counters
full regression 147/147 PASS after P29G/P29H
```

P30 must preserve:

```text
one active command at a time
in-order command execution
in-order completion production
one CQ record per completed command
P18 completion record format
P19 SQ entry format
P19/P20/P21 queue CSR behavior
P22 event CSR pending / enable / W1C / IRQ behavior
P24 timeout / watchdog reporting model
P26 lifecycle cleanup and reinit behavior
P27 memory guard error/event/recovery behavior
P28 event moderation threshold / timer / re-arm behavior
P29 telemetry counter behavior
BRAM / GEMM / DMA / AXI-Stream / Direct Stream datapath behavior
```

P30A is a prototype specification milestone only.  It does not change RTL, UVM, Tcl, README, regression list, CSR addresses, SQ/CQ formats, descriptor formats, completion formats, event bits, or datapath behavior.

---

## 3. P30 Design Intent

The current hardware runtime is already functional, recoverable, safe, interrupt-efficient, and measurable.  A software driver still needs one stable contract that answers:

```text
What memory objects must the driver allocate?
What CSR windows must the driver program?
Which registers are host-owned versus hardware-owned?
What is the legal init sequence?
When should events be armed?
How should CQ records be consumed?
How should event pending bits be W1C-cleared and re-armed?
How should memory guard be enabled?
How should moderation and telemetry be sampled?
What should the driver do after CQ-full, STOP_QUEUE, timeout, or memory-guard error?
Which operations are allowed while queue_busy is high?
Which operations are forbidden while queue_busy is high?
```

P30 treats the existing CSR and memory-visible runtime as a device ABI:

```text
The hardware provides stable registers, memory object formats, event semantics, and telemetry counters.
The driver follows a defined ordering contract and does not rely on implementation-private FSM timing.
```

P30 should make the programming model easy to explain in a driver bring-up interview:

```text
A host allocates SQ/CQ/descriptor/source/destination memory, programs guard regions and queue pointers, arms events, writes SQ entries, rings the doorbell, waits for event notification, consumes CQ records, updates CQ_HEAD, W1C-clears events, samples telemetry, and repeats.  Recovery paths use the same queue/event/lifecycle contract.
```

---

## 4. P30A Scope

### 4.1 Included

P30A defines:

```text
driver-facing runtime ABI concept
software-visible memory object model
CSR programming order direction
host-owned versus hardware-owned pointer policy
event arm / wait / W1C / re-arm ordering direction
CQ consume and batch service policy direction
memory guard setup direction
interrupt moderation setup direction
runtime telemetry sample / clear direction
runtime recovery sequence direction
relationship to P19/P20/P21/P22/P23/P24/P26/P27/P28/P29 behavior
P30B/P30C/P30D/P30E/P30F/P30G/P30H milestone plan
```

### 4.2 Not Included

P30A does not include:

```text
RTL implementation
CSR RTL changes
canonical CSR address map changes
new register bit fields
new access types
new reset values
new SQ entry format
new CQ completion record format
new descriptor format
new completion record format
new P22 event source allocation
new P29 telemetry counter allocation
new queue execution policy
new timeout/watchdog policy
new memory guard policy
BRAM / scratchpad changes
GEMM datapath changes
DMA / AXI-Stream / Direct Stream datapath changes
multi-queue support
priority queue support
out-of-order completion
MSI/MSI-X implementation
Linux driver
C software driver
UVM RAL model
standalone ABI top
standalone ABI simulation flow
```

P30A documents how software should use the existing runtime.  Any canonical CSR map, register bit fields, access types, and reset values remain recorded only in `axi_lite_csr_control_plane_spec.md`.

---

## 5. Fixed P30A Design Decisions

```text
ABI target                   : existing CSR wrapper and host-visible SQ/CQ runtime stack
Driver contract level         : CSR programming order + memory object ownership + event/CQ/telemetry flow
Execution model               : still one active command at a time
Completion order              : still in-order CQ records
CQ record production          : still one record per completed command
Completion authority          : CQ records remain authoritative for per-command completion detail
Event role                    : wakeup / summary notification only
Telemetry role                : performance / health summary only
Memory safety model           : reuse P27 guard policy
Interrupt moderation model    : reuse P28 threshold / timer / re-arm policy
Telemetry model               : reuse P29 counters and clear policy
Lifecycle model               : reuse P26 cleanup / reinit policy
CSR map                       : unchanged for P30A
SQ/CQ/descriptor formats       : unchanged for P30A
Standalone sim flow            : not allowed for P30A
```

P30A intentionally avoids new hardware features.  The milestone is valuable because it makes the already-validated runtime usable as a stable software-facing device model.

---

## 6. Driver-Visible Runtime Objects

The P30 ABI is built from CSR windows and host-visible memory objects.

### 6.1 CSR Windows Used by the ABI

The driver uses the existing CSR windows:

```text
P14 micro-operation CSR window
P15 job CSR window
P16 recipe CSR window
P17 descriptor-fetch CSR window
P18 completion-writeback CSR window
P19 queue CSR window
P22 event notification CSR window
P27 memory guard CSR window
P29 runtime telemetry CSR window
```

The ABI should prefer the queue/event/guard/telemetry runtime path for normal operation:

```text
P19 queue window              : SQ/CQ base/depth/head/tail/control/status
P22 event window              : event pending/enable/control/W1C/threshold/moderation
P27 memory guard window       : allowed memory regions and guard diagnostics
P29 telemetry window          : runtime counters and clear policy
```

P14/P15/P16/P17/P18 windows remain useful for debug, directed validation, and lower-level smoke tests.  A normal driver-facing queue runtime should not need to issue individual P14 micro-operations.

### 6.2 Host-Visible Memory Objects

The driver allocates and owns these memory objects:

```text
SQ command ring memory
CQ completion ring memory
descriptor table memory
source payload memory
result / destination memory
```

The hardware reads or writes these objects only through the existing validated runtime path:

```text
SQ memory             : hardware reads SQ entries
CQ memory             : hardware writes CQ completion records
Descriptor memory     : hardware reads descriptor records
Source memory         : DMA / AXI-Stream / Direct Stream frontend reads
Destination memory    : DMA store writes
```

P30A does not change the format or stride of any memory object.

### 6.3 Pointer Ownership

The ABI follows the existing P19/P21 ownership model:

```text
SQ_BASE / SQ_DEPTH / SQ_STRIDE : host programmed while queue is idle
SQ_HEAD                       : hardware-owned consumed-command counter
SQ_TAIL                       : host-owned produced-command counter / doorbell
CQ_BASE / CQ_DEPTH / CQ_STRIDE : host programmed while queue is idle
CQ_HEAD                       : host-owned consumed-completion counter
CQ_TAIL                       : hardware-owned produced-completion counter
```

Allowed while queue is active:

```text
host may update SQ_TAIL to publish appended work
host may update CQ_HEAD after consuming CQ records
host may arm / W1C / re-arm event registers
host may read queue/event/guard/telemetry status
host may clear telemetry counters if it only wants a new measurement window
```

Forbidden or rejected while queue is active:

```text
changing SQ/CQ base address
changing SQ/CQ depth
changing SQ/CQ stride
changing guard region policy if the implementation rejects config writes while busy
resetting queue pointers
assuming telemetry clear changes functional state
assuming event W1C consumes CQ records
```

---

## 7. Canonical Driver Initialization Direction

P30B should freeze the exact driver programming checklist.  P30A recommends this initialization direction.

### 7.1 Cold Boot / Reset Initialization

Recommended cold boot sequence:

```text
1. wait for CSR_READY on the relevant CSR windows
2. confirm queue is idle and no lower-level engines are busy
3. clear lower-level sticky done/error/debug state if required
4. clear queue done/error/reject sticky state
5. clear event pending bits and event counters
6. clear telemetry counters
7. program memory guard regions
8. enable memory guard checks if this runtime requires guard protection
9. program SQ/CQ base, depth, stride, and initial pointers
10. program event enable mask and event control
11. program optional event moderation threshold/timer
12. enable telemetry and selected telemetry counter categories
13. publish SQ entries in memory
14. write SQ_TAIL doorbell value
15. issue START_QUEUE or rely on the selected doorbell/start policy
```

Ordering rationale:

```text
Clear sticky state before starting a new software-visible session.
Program guard before launching memory traffic.
Program queue base/depth/stride before queue start.
Arm events before queue start to avoid missing the first wakeup opportunity.
Enable telemetry before workload start if the sample should include the full session.
```

### 7.2 Queue Session Setup

A driver-visible queue session is valid when:

```text
SQ and CQ memory regions are allocated and aligned
SQ and CQ depth are non-zero and supported
SQ and CQ stride match the hardware-supported entry size
SQ_TAIL >= SQ_HEAD in the current monotonic epoch
CQ_TAIL >= CQ_HEAD in the current monotonic epoch
CQ has space before starting a command that must produce a CQ record
memory guard regions cover SQ, CQ, descriptor, source, and destination spans when guard is enabled
all relevant sticky queue errors are cleared or intentionally being diagnosed
```

P30 should avoid exposing implementation-private FSM states as required driver inputs.  The driver should rely on status bits, done/error sticky bits, event pending bits, CQ records, and telemetry counters.

---

## 8. Command Submission ABI Direction

### 8.1 Basic Submission

Recommended submission sequence:

```text
1. fill one or more SQ command entries in host-visible SQ memory
2. ensure descriptor/source/destination payload memory is visible to the hardware memory model
3. update CSR_SQ_TAIL to publish the produced command count
4. if queue is idle, issue START_QUEUE
5. if queue is already active, rely on runtime SQ_TAIL doorbell observation at command boundaries
```

P21 live-service policy remains:

```text
host may append SQ entries while queue_busy=1
hardware observes live SQ_TAIL only at command boundaries
active command uses snapshotted SQ/CQ context and is isolated from later host pointer writes
```

### 8.2 Completion Detection

The driver must treat the CQ record as the authoritative command completion detail:

```text
event pending bit wakes the driver
CQ_TAIL / CQ_HEAD determine available CQ records
CQ record content determines command completion status and details
queue done/error sticky bits summarize terminal conditions
telemetry counters summarize runtime behavior but do not replace CQ records
```

The driver should not assume that one event equals one command.  P28 moderation may coalesce multiple CQ completions into one event notification.

---

## 9. Event / Interrupt ABI Direction

P22/P28 event behavior is a wakeup contract, not a completion-data contract.

### 9.1 Event Arming

Recommended event arm sequence:

```text
1. clear stale event pending bits if beginning a new clean session
2. program CSR_EVENT_ENABLE with the desired event mask
3. program CSR_EVENT_CONTROL.GLOBAL_IRQ_ENABLE
4. enable snapshot capture if queue snapshots are useful for debug
5. program P28 moderation controls if using coalescing
```

Recommended default queue runtime event mask should include at least:

```text
CQ_NOT_EMPTY_EVENT
CQ_THRESHOLD_EVENT when threshold moderation is used
CQ_MODERATION_TIMER_EVENT when timer fallback is used
QUEUE_DRAINED_EVENT
QUEUE_STOPPED_EVENT
QUEUE_ERROR_EVENT
CQ_FULL_STALL_EVENT when live CQ-full recovery is supported
CQ_SPACE_RECOVERED_EVENT when live CQ-full recovery is supported
```

### 9.2 Event Service Loop

Recommended event service loop:

```text
1. wait for event_irq or poll CSR_EVENT_PENDING
2. read CSR_EVENT_PENDING / STATUS / snapshot registers
3. read queue status and CQ occupancy
4. consume all available CQ records that the driver wants to process now
5. update CSR_CQ_HEAD by the number of consumed CQ records
6. handle terminal queue events or recovery events if present
7. W1C-clear the event pending bits that were handled
8. re-arm event path by preserving event enable/control policy
9. if CQ remains non-empty and moderation retrigger policy is enabled, expect re-notification
```

The recommended ordering consumes CQ records before W1C/re-arm in normal completion service.  This avoids immediately retriggering the same CQ-not-empty condition when the driver already intends to drain the available CQ records.

### 9.3 Coalesced Event Interpretation

When P28 moderation is enabled:

```text
one event notification may cover multiple CQ completions
CQ occupancy determines how many CQ records are available
P29 irq_eligible_count may be lower than CQ commit count
P29 max_cq_batch_size should reflect batched CQ_HEAD updates
```

Driver implication:

```text
the driver loop should be CQ-driven after wakeup, not event-count-driven
```

---

## 10. CQ Consumption ABI Direction

The driver consumes CQ records by advancing `CSR_CQ_HEAD` after reading the records.

Recommended policy:

```text
read CQ_HEAD and CQ_TAIL or CSR_QUEUE_CQ_OCCUPANCY
for each available CQ record selected by software budget:
  read the CQ record from host-visible CQ memory
  validate the CQ record commit word / status as defined by the P18/P19 completion format
  process success or error status
write CSR_CQ_HEAD = old_CQ_HEAD + consumed_count
```

Batch consumption is preferred when moderation is enabled:

```text
consume multiple CQ records per wakeup when CQ occupancy > 1
write CQ_HEAD once for the batch when possible
sample P29 CQ consumed and max batch counters for efficiency validation
```

The driver must not advance `CSR_CQ_HEAD` past visible committed CQ records.

---

## 11. Memory Guard ABI Direction

P27 memory guard is the software-programmable safety boundary for host-visible memory traffic.

Recommended guard setup sequence:

```text
1. wait for queue idle
2. program SQ allowed region
3. program CQ allowed region
4. program descriptor allowed region
5. program source allowed region
6. program destination allowed region
7. enable desired domain checks
8. enable strict reject policy if unsafe accesses must be blocked before launch
9. clear old guard diagnostics before starting a new clean session
```

Driver contract:

```text
all SQ/CQ/descriptor/source/destination memory used by a session must fall inside the enabled guard ranges
if a guard failure occurs, CSR_MEM_GUARD_* diagnostics are authoritative for the memory-safety detail
queue error and P22 QUEUE_ERROR_EVENT are the runtime notification path
P29 memory-guard telemetry is only a summary counter
```

The driver should not change guard regions while queue execution is active unless the implementation explicitly permits that operation.  The current P30 direction assumes guard policy changes are idle-time configuration operations.

---

## 12. Telemetry ABI Direction

P29 telemetry gives the driver a runtime health and efficiency profile.

Recommended telemetry usage:

```text
clear telemetry counters before a measurement window
enable telemetry categories before starting the workload
run the queue session
wait for the desired terminal or sampling point
read telemetry counters
compute software-side ratios
optionally clear telemetry counters for the next measurement window
```

Common derived software metrics:

```text
accepted_commands        = CSR_TELEM_SQ_ACCEPT_COUNT
completed_commands       = CSR_TELEM_CMD_COMPLETE_COUNT
cq_commits               = CSR_TELEM_CQ_COMMIT_COUNT
host_consumed_cq         = CSR_TELEM_CQ_CONSUMED_COUNT
interrupt_reduction      = CSR_TELEM_CQ_COMMIT_COUNT - CSR_TELEM_IRQ_ELIGIBLE_COUNT
completions_per_irq      = CSR_TELEM_CQ_COMMIT_COUNT / max(CSR_TELEM_IRQ_ELIGIBLE_COUNT, 1)
max_batch_size           = CSR_TELEM_MAX_CQ_BATCH_SIZE
stall_events             = CSR_TELEM_CQ_FULL_STALL_COUNT
stall_cycles             = CSR_TELEM_CQ_FULL_STALL_CYCLES
```

Telemetry clear contract:

```text
clearing telemetry does not clear queue state
clearing telemetry does not clear SQ/CQ pointers
clearing telemetry does not clear event pending bits
clearing telemetry does not clear timeout status
clearing telemetry does not clear memory guard diagnostics
clearing telemetry does not remove CQ records
```

---

## 13. Recovery ABI Direction

P30 should define software-visible recovery sequences for common runtime conditions.

### 13.1 CQ-Full Stall Recovery

Expected condition:

```text
CQ space reaches zero
queue stalls at command boundary
CQ_FULL_STALL_EVENT wakes the driver
```

Recommended recovery sequence:

```text
1. read event pending and queue status
2. read available CQ record(s)
3. advance CSR_CQ_HEAD
4. wait for or observe CQ_SPACE_RECOVERED_EVENT
5. W1C-clear handled event bits
6. allow queue to resume
7. later consume the next CQ record after the stalled command completes
```

Expected telemetry:

```text
CQ full stall count increments
CQ space recovered count increments
CQ full stall cycles are non-zero
queue error count remains zero for a normal CQ-full stall
```

### 13.2 STOP_QUEUE Recovery

Expected condition:

```text
host requests STOP_QUEUE
queue stops at a command boundary or after active command completion
pending SQ entries may be preserved according to P26 policy
```

Recommended recovery direction:

```text
1. observe QUEUE_STOPPED_EVENT
2. consume any valid CQ records already committed
3. W1C-clear handled event bits
4. choose preserve/restart or cleanup/reinit path according to P26 policy
5. restart queue when ready
```

### 13.3 Timeout Recovery

Expected condition:

```text
accepted command exceeds its watchdog budget
queue reports COMMAND_TIMEOUT_ERROR
P22 QUEUE_ERROR_EVENT wakes the driver
```

Recommended recovery direction:

```text
1. observe QUEUE_ERROR_EVENT
2. read CSR_QUEUE_ERROR_STATUS and CSR_QUEUE_ERROR_DETAIL
3. consume any valid CQ error record if one was safely committed
4. clear event pending bits
5. perform P26 timeout/error lifecycle cleanup
6. clear lower-level sticky state as required
7. reinitialize queue session
8. submit a known-good command
```

Expected telemetry:

```text
timeout error count increments
queue error count increments
post-recovery known-good command can complete
```

### 13.4 Memory Guard Reject Recovery

Expected condition:

```text
P27 guard rejects an unsafe SQ / CQ / descriptor / source / destination access
queue reports MEMORY_GUARD_ERROR when the failure reaches queue level
P22 QUEUE_ERROR_EVENT wakes the driver
```

Recommended recovery direction:

```text
1. observe QUEUE_ERROR_EVENT
2. read queue error status/detail
3. read CSR_MEM_GUARD_ERROR_STATUS and guard diagnostics
4. do not trust unsafe CQ memory if CQ guard failed and completion writeback was suppressed
5. clear event pending bits
6. clear guard and queue sticky status as required
7. correct memory regions or command descriptors
8. reinitialize and submit a known-good command
```

Expected telemetry:

```text
memory guard error count increments
queue error count increments
post-recovery known-good command can complete
```

---

## 14. Driver Rules and Anti-Rules

### 14.1 Rules

A P30-compliant driver should:

```text
program SQ/CQ/guard configuration while queue is idle
arm events before starting queue service
publish SQ entries before advancing SQ_TAIL
use CQ records as authoritative completion detail
advance CQ_HEAD only after reading committed CQ records
W1C-clear only handled event pending bits
use P26 cleanup/reinit policy after timeout or guard errors
use P29 telemetry for measurement, not functional control
batch CQ consumption when moderation coalesces completions
```

### 14.2 Anti-Rules

A P30-compliant driver should not:

```text
assume one event means one command completed
assume event pending bits contain completion detail
assume telemetry counters replace CQ record parsing
advance CQ_HEAD beyond committed CQ_TAIL
change SQ/CQ base/depth/stride while queue is busy
rely on implementation-private FSM timing
clear telemetry to recover queue state
clear events before consuming CQ records when the CQ records are intended to be handled immediately
ignore memory guard diagnostics after a guard failure
restart after timeout without P26 cleanup / reinit sequencing
```

---

## 15. UVM Validation Strategy

P30 validation should reuse the existing CSR wrapper top and event-driven host runtime style.

Common test setup:

```text
UVM_TOP = ai_accel_subsys_csr_uvm_top
CASE_ID = 102 or focused representative case
ENABLE_RESULT_CHECK = 0 for ABI-policy tests unless final known-good command compares results
FORCE_HELPER_MEM_PATH = 0
DMA_CLK_PERIOD_NS = 10
CORE_CLK_PERIOD_NS = 14
```

P30 tests should use helper/API behavior that resembles driver software:

```text
driver_init()
driver_program_guard_regions()
driver_setup_queue()
driver_enable_events()
driver_enable_moderation()
driver_enable_telemetry()
driver_submit_sq_batch()
driver_wait_event()
driver_consume_cq_batch()
driver_ack_and_rearm_events()
driver_sample_telemetry()
driver_recover_cq_full()
driver_recover_timeout()
driver_recover_guard_error()
driver_shutdown_or_reinit()
```

P30 should avoid creating a standalone UVM top or a new simulation flow.  It should consolidate and reuse the existing P23/P25/P26/P28/P29 helper behaviors.

---

## 16. P30 Milestone Plan

Recommended P30 split:

```text
P30A: Driver-facing runtime ABI prototype spec                   PASS
P30B: CSR programming sequence / ABI policy freeze               PASS
P30C: Host runtime driver helper cleanup / API consolidation     TODO
P30D: Cold boot -> queue setup -> first command smoke            PASS
P30E: Steady-state driver loop smoke                             IMPLEMENTED / RUN PENDING
P30F: Driver recovery contract smoke                             TODO
P30G: full regression integration                                TODO
P30H: documentation closure                                      TODO
```

### 16.1 P30B CSR Programming Sequence / ABI Policy Freeze

P30B freezes the first driver-visible programming contract.

Frozen P30B policy set:

```text
cold boot / reset sequence
queue setup sequence
memory guard setup sequence
event arm / W1C / re-arm sequence
CQ consumption sequence
moderation setup sequence
telemetry sample / clear sequence
CQ-full recovery sequence
STOP_QUEUE recovery sequence
timeout recovery sequence
memory guard recovery sequence
idle-time versus active-time register write policy
```

P30B does not add RTL, UVM tests, Tcl scripts, README updates, regression-list items, CSR addresses, register bit fields, SQ/CQ formats, descriptor formats, completion record formats, event sources, telemetry counters, a standalone UVM top, or a standalone simulation flow.

### 16.2 P30C Host Runtime Driver Helper Cleanup / API Consolidation

P30C should consolidate existing helper behavior into a driver-style helper layer.

Recommended implementation direction:

```text
reuse P23 event-driven host runtime helper
reuse P25 stress snapshot utilities
reuse P26 lifecycle cleanup utilities
reuse P27 guard checker utilities
reuse P28 moderation helper utilities
reuse P29 telemetry helper utilities
expose a small driver-style API rather than scattered milestone-specific calls
```

P30C should avoid changing hardware behavior.

### 16.3 P30D Cold Boot -> Queue Setup -> First Command Smoke

Purpose:

```text
validate the canonical driver init order from reset / idle into one valid queue command
validate event arm before queue start
validate memory guard setup before memory traffic
validate telemetry enable before workload
validate first CQ record and result compare
```

Suggested test name:

```text
ai_accel_subsys_csr_driver_abi_cold_boot_smoke_test
```

Expected PASS markers:

```text
[P30D_ABI/INIT_PASS]
[P30D_ABI/GUARD_SETUP_PASS]
[P30D_ABI/EVENT_ARM_PASS]
[P30D_ABI/QUEUE_SETUP_PASS]
[P30D_ABI/FIRST_COMMAND_PASS]
[P30D_ABI/PASS]
```

### 16.4 P30E Steady-State Driver Loop Smoke

Purpose:

```text
validate repeated driver loop operation
submit multiple SQ commands
wait event notification
batch consume CQ records
advance CQ_HEAD
W1C / re-arm event path
sample telemetry
confirm IRQ reduction when moderation is enabled
```

Suggested test name:

```text
ai_accel_subsys_csr_driver_abi_steady_state_smoke_test
```

Expected PASS markers:

```text
[P30E_ABI/SUBMIT_PASS]
[P30E_ABI/EVENT_WAIT_PASS]
[P30E_ABI/BATCH_CONSUME_PASS]
[P30E_ABI/REARM_PASS]
[P30E_ABI/TELEMETRY_SAMPLE_PASS]
[P30E_ABI/PASS]
```

### 16.5 P30F Driver Recovery Contract Smoke

Purpose:

```text
validate driver-visible recovery sequencing across representative runtime conditions
CQ-full recovery
STOP_QUEUE preserve/restart recovery
timeout lifecycle cleanup and known-good restart
memory guard reject cleanup and known-good restart
telemetry readable after recovery
```

Suggested test name:

```text
ai_accel_subsys_csr_driver_abi_recovery_smoke_test
```

Expected PASS markers:

```text
[P30F_ABI/CQ_FULL_RECOVERY_PASS]
[P30F_ABI/STOP_RESTART_PASS]
[P30F_ABI/TIMEOUT_RECOVERY_PASS]
[P30F_ABI/GUARD_RECOVERY_PASS]
[P30F_ABI/TELEMETRY_AFTER_RECOVERY_PASS]
[P30F_ABI/PASS]
```

### 16.6 P30G Full Regression Integration

P30G should add a small representative subset to the full regression.

Recommended full-regression items:

```text
csr_driver_abi_cold_boot_case102
csr_driver_abi_steady_state_case102
csr_driver_abi_recovery_case102
```

Expected full-regression count if three items are added:

```text
Before P30G : 147
After P30G  : 150
```

### 16.7 P30H Documentation Closure

P30H should update:

```text
README.md
driver_runtime_abi_prototype_spec.md
uvm_regression.list
run_full_uvm_regression.tcl
```

The CSR map remains canonical only in `axi_lite_csr_control_plane_spec.md`.

---

## 17. P30A Closure Criteria

P30A is complete when:

```text
driver-facing runtime ABI purpose and scope are documented
runtime memory object model is documented
host-owned versus hardware-owned pointer policy is documented
cold boot / queue setup direction is documented
event arm / wait / W1C / re-arm direction is documented
CQ consumption and batch service direction is documented
memory guard setup direction is documented
telemetry sample / clear direction is documented
CQ-full / STOP_QUEUE / timeout / guard recovery direction is documented
driver rules and anti-rules are documented
relationship to P19/P20/P21/P22/P23/P24/P26/P27/P28/P29 is documented
P30B/P30C/P30D/P30E/P30F/P30G/P30H validation direction and PASS markers are documented
no RTL / CSR / Tcl / regression-list changes are required for P30A
```

P30A does not change the regression count.

Current expected status after P30A:

```text
P29H: Documentation closure                                      PASS
P30A: Driver-facing runtime ABI prototype spec                   PASS
Full regression remains:
  TOTAL : 147
  PASS  : 147
  FAIL  : 0
```

---

## 18. Interview Notes

P30 is useful because it shows that the accelerator is not just a pile of RTL features.  It has a coherent software-facing runtime contract.

Concise explanation:

```text
After closing runtime telemetry, I defined the driver-facing ABI.  The hardware still uses a simple single-active in-order queue, but the driver now has a documented sequence for reset, memory guard setup, SQ/CQ programming, event arming, command submission, CQ consumption, interrupt moderation, telemetry sampling, and recovery.
```

Key points:

```text
The ABI is built on existing validated CSR windows and memory object formats.
CQ records remain authoritative for per-command completion.
Events are wakeups, not completion records.
Telemetry is measurement, not control.
Memory guard is configured before unsafe host-visible memory traffic.
CQ_HEAD and SQ_TAIL are the only normal active-time queue pointer updates from the host.
P26 lifecycle cleanup is the recovery foundation for timeout and guard failures.
P28 moderation and P29 telemetry make the driver loop interrupt-efficient and measurable.
P30 avoids over-expanding into multi-queue or out-of-order execution.
```

Tradeoff explanation:

```text
I intentionally kept the runtime ABI small.  Instead of adding multi-queue or MSI-X early, I first made the existing queue/event/guard/moderation/telemetry stack deterministic and driver-usable.  That makes the subsystem easier to validate, easier to debug, and easier to explain.
```

---

## 19. P30B CSR Programming Sequence / ABI Policy Freeze Checkpoint

P30B freezes the first driver-facing runtime ABI policy for software and UVM driver-style validation.

Files updated:

```text
docs/driver_runtime_abi_prototype_spec.md
```

P30B is a documentation-only policy freeze.  It does not change the CSR address map, register access types, reset values, SQ/CQ entry formats, descriptor formats, completion record formats, event sources, telemetry counters, RTL, UVM tests, Tcl scripts, README, or regression list.

The CSR map remains canonical only in:

```text
docs/axi_lite_csr_control_plane_spec.md
```

### 19.1 Frozen ABI Principle

The P30B driver ABI is built on the existing P19 through P29 runtime stack:

```text
SQ/CQ runtime ownership comes from P19/P20/P21.
Event notification and W1C behavior come from P22/P28.
Lifecycle cleanup and reinit behavior come from P26.
Memory safety setup and diagnostics come from P27.
Interrupt moderation comes from P28.
Runtime telemetry and measurement come from P29.
```

P30B freezes the driver contract as an ordering and ownership policy, not as a new hardware feature.

Core ABI principle:

```text
The driver owns memory allocation, SQ production, CQ consumption, event service, guard setup, moderation policy, and telemetry sampling.
The hardware owns command consumption, CQ production, event capture, guard enforcement, and telemetry counting.
```

### 19.2 Frozen Cold-Boot / Reset Programming Sequence

The P30B cold-boot sequence is frozen as:

```text
1. wait for CSR_READY on the CSR wrapper path
2. confirm queue is idle and lower-level engines are quiescent
3. clear lower-level sticky done/error/debug state when starting a clean session
4. clear queue done/error/reject sticky state
5. clear event pending bits and event counters
6. clear telemetry counters
7. program memory guard regions while queue is idle
8. enable the desired memory guard domains and strict policy while queue is idle
9. program SQ/CQ base, depth, stride, and initial monotonic pointers while queue is idle
10. program event enable mask and event control
11. program event moderation threshold/timer/control when moderation is used
12. enable telemetry and selected telemetry counter categories
13. write SQ entries into host-visible SQ memory
14. update CSR_SQ_TAIL to publish produced SQ entries
15. issue CSR_QUEUE_COMMAND.START_QUEUE when the queue is idle
```

Frozen rationale:

```text
sticky status is cleared before a new driver-visible session
memory guard is programmed before unsafe host-visible traffic can launch
queue geometry is programmed only while idle
events are armed before queue start to avoid losing the first wakeup opportunity
telemetry is enabled before workload start when the full session should be measured
SQ_TAIL publishes already-written SQ entries, never speculative entries
```

### 19.3 Frozen Queue Setup Policy

A P30B-compliant queue setup must program these fields while queue service is idle:

```text
CSR_SQ_BASE_ADDR
CSR_SQ_DEPTH
CSR_SQ_STRIDE
CSR_SQ_TAIL initial value
CSR_CQ_BASE_ADDR
CSR_CQ_DEPTH
CSR_CQ_STRIDE
CSR_CQ_HEAD initial value
CSR_QUEUE_CONTROL policy bits
```

Hardware-owned pointer fields remain read-only to the driver:

```text
CSR_SQ_HEAD
CSR_CQ_TAIL
```

Frozen queue validity policy:

```text
SQ and CQ base addresses must be aligned to the hardware-supported access size.
SQ and CQ depth must be non-zero and supported.
SQ and CQ stride must remain 0x40 for the current ABI.
SQ_TAIL must not publish entries that have not been written in SQ memory.
CQ_HEAD must not advance beyond committed CQ records.
Queue pointer monotonic epochs are preserved across normal drained and stopped reuse.
RESET_QUEUE_POINTERS is an idle-time operation only.
```

### 19.4 Frozen Memory Guard Setup Policy

When memory guard is used, P30B freezes the guard setup order as:

```text
1. wait for queue idle
2. program SQ allowed region
3. program CQ allowed region
4. program descriptor allowed region
5. program source allowed region
6. program destination allowed region
7. enable desired domain checks
8. enable strict reject policy when unsafe traffic must be blocked
9. clear old guard diagnostics before starting a clean session
```

Frozen guard contract:

```text
Guard regions are idle-time configuration.
All SQ/CQ/descriptor/source/destination accesses used by a session must fit inside enabled guard regions.
Guard diagnostics are authoritative for memory-safety detail.
QUEUE_ERROR_EVENT is the runtime notification path when a guard failure reaches queue level.
P29 memory-guard telemetry is a summary counter only.
```

### 19.5 Frozen Event Arm / Service / Re-arm Policy

P30B freezes the event arm sequence as:

```text
1. clear stale event pending bits for a clean session
2. program CSR_EVENT_ENABLE with the selected event mask
3. program CSR_EVENT_CONTROL.GLOBAL_IRQ_ENABLE when interrupt-style wakeup is desired
4. keep snapshot capture enabled when debug snapshots are useful
5. program P28 moderation control only after the threshold/timer policy is known
```

Recommended baseline driver event mask:

```text
CQ_NOT_EMPTY_EVENT
CQ_THRESHOLD_EVENT when threshold moderation is used
CQ_MODERATION_TIMER_EVENT when timer fallback is used
QUEUE_DRAINED_EVENT
QUEUE_STOPPED_EVENT
QUEUE_ERROR_EVENT
CQ_FULL_STALL_EVENT when live CQ-full recovery is supported
CQ_SPACE_RECOVERED_EVENT when live CQ-full recovery is supported
```

P30B freezes the event service order as:

```text
1. wait for event_irq or poll CSR_EVENT_PENDING
2. read CSR_EVENT_PENDING and CSR_EVENT_STATUS
3. read queue status / CQ occupancy when deciding service budget
4. consume the desired committed CQ records
5. advance CSR_CQ_HEAD by the number of consumed records
6. process terminal or recovery event bits
7. W1C-clear only the event pending bits that were handled
8. preserve or restore the event enable/control policy for the next wakeup
9. if CQ remains non-empty and retrigger policy is enabled, expect another notification
```

Frozen event interpretation policy:

```text
Events are wakeups, not completion records.
CQ records are authoritative per-command completion detail.
One event may cover multiple CQ records when moderation is enabled.
The driver loop must be CQ-occupancy driven after wakeup, not event-count driven.
```

### 19.6 Frozen CQ Consumption Policy

P30B freezes the CQ consume policy as:

```text
1. determine available CQ records from CQ_HEAD/CQ_TAIL or CSR_QUEUE_CQ_OCCUPANCY
2. read committed CQ records from host-visible CQ memory
3. validate the CQ record commit/status words according to the existing completion format
4. process normal or error completion detail from the CQ record
5. write CSR_CQ_HEAD = old_CQ_HEAD + consumed_count
```

Batch consumption policy:

```text
The driver may consume multiple CQ records per wakeup.
The driver should write CQ_HEAD once per batch when practical.
P29 CQ consumed and max batch counters are used only to measure this behavior.
```

Forbidden behavior:

```text
The driver must not advance CQ_HEAD past committed CQ_TAIL.
The driver must not treat event W1C as CQ consumption.
The driver must not treat telemetry clear as CQ consumption.
```

### 19.7 Frozen Moderation Setup Policy

When P28 moderation is used, P30B freezes setup as:

```text
1. program CSR_EVENT_CQ_THRESHOLD before enabling threshold moderation
2. program CSR_EVENT_MOD_TIMER_LIMIT before enabling timer fallback
3. program CSR_EVENT_MOD_CONTROL for threshold and/or timer release policy
4. arm the corresponding event bits in CSR_EVENT_ENABLE
5. enable global IRQ if interrupt-style wakeup is desired
```

Frozen moderation interpretation:

```text
Moderation may reduce notification rate but does not reduce CQ record count.
CQ commit count remains one per completed command.
Threshold release and timer release are notification policies only.
Urgent queue terminal / error / recovery events may bypass moderation.
```

### 19.8 Frozen Telemetry Sample / Clear Policy

P30B freezes telemetry setup and sampling as:

```text
1. clear telemetry counters before a measurement window
2. enable CSR_TELEM_CONTROL.TELEMETRY_ENABLE
3. enable cycle / host-CQ-consume / event-efficiency categories as needed
4. run the queue workload
5. sample telemetry counters at the desired point
6. compute software-side ratios from raw counters
7. optionally clear telemetry counters before the next measurement window
```

Frozen telemetry interpretation:

```text
Telemetry is measurement, not control.
Telemetry counters do not replace CQ records.
Telemetry clear is observational only.
Telemetry clear must not clear queue state, SQ/CQ pointers, event pending bits, timeout status, guard diagnostics, lower-level sticky status, or CQ records.
```

### 19.9 Frozen Active-Time Register Write Policy

P30B freezes these active-time host operations as allowed:

```text
write CSR_SQ_TAIL to publish appended SQ entries
write CSR_CQ_HEAD after consuming CQ records
read queue / event / guard / telemetry status
write CSR_EVENT_PENDING W1C bits for handled events
update CSR_EVENT_ENABLE / CSR_EVENT_CONTROL for interrupt policy
clear telemetry counters for a new measurement window
issue STOP_QUEUE when graceful stop is desired
```

P30B freezes these operations as idle-time only or rejected while active:

```text
change SQ/CQ base address
change SQ/CQ depth
change SQ/CQ stride
reset queue pointers
change memory guard regions or guard domain policy
assume lower-level P14/P15/P16/P17/P18 manual commands can safely bypass queue ownership
```

### 19.10 Frozen CQ-Full Recovery Sequence

P30B freezes CQ-full recovery as a non-error backpressure path:

```text
1. observe CQ_FULL_STALL_EVENT or CSR_QUEUE_STATUS.CQ_FULL / QUEUE_STALLED
2. read and process available CQ records
3. advance CSR_CQ_HEAD
4. observe CQ_SPACE_RECOVERED_EVENT or queue progress
5. W1C-clear handled CQ-full / CQ-space event bits
6. allow the queue to resume at the next command-boundary check
```

Expected telemetry:

```text
CQ_FULL_STALL_COUNT increments
CQ_SPACE_RECOVERED_COUNT increments
CQ_FULL_STALL_CYCLES is non-zero
QUEUE_ERROR_COUNT remains zero for normal CQ-full recovery
```

### 19.11 Frozen STOP_QUEUE Recovery Sequence

P30B freezes STOP_QUEUE as a graceful, command-boundary stop policy:

```text
1. driver writes CSR_QUEUE_COMMAND.STOP_QUEUE
2. hardware finishes or reaches a command boundary according to existing P26 policy
3. driver observes QUEUE_STOPPED_EVENT
4. driver consumes any committed CQ records
5. driver W1C-clears handled event bits
6. driver either restarts preserved pending work or performs cleanup/reinit
```

STOP_QUEUE does not imply command failure.  It is a lifecycle control path.

### 19.12 Frozen Timeout Recovery Sequence

P30B freezes timeout recovery as an error lifecycle path:

```text
1. observe QUEUE_ERROR_EVENT
2. read CSR_QUEUE_ERROR_STATUS and CSR_QUEUE_ERROR_DETAIL
3. identify COMMAND_TIMEOUT_ERROR
4. consume any valid CQ error record if safely committed
5. W1C-clear handled event pending bits
6. perform P26 timeout/error lifecycle cleanup
7. clear lower-level sticky state as required
8. reinitialize queue session
9. submit a known-good command
```

Expected telemetry:

```text
TIMEOUT_ERROR_COUNT increments
QUEUE_ERROR_COUNT increments
post-recovery known-good command can complete
```

### 19.13 Frozen Memory Guard Recovery Sequence

P30B freezes memory guard recovery as a safety-error lifecycle path:

```text
1. observe QUEUE_ERROR_EVENT
2. read CSR_QUEUE_ERROR_STATUS and CSR_QUEUE_ERROR_DETAIL
3. identify MEMORY_GUARD_ERROR when present
4. read CSR_MEM_GUARD_ERROR_STATUS and guard diagnostics
5. do not trust unsafe CQ memory if CQ guard failed and completion writeback was suppressed
6. W1C-clear handled event pending bits
7. clear guard and queue sticky status as required
8. correct memory regions or command descriptors
9. reinitialize and submit a known-good command
```

Expected telemetry:

```text
MEM_GUARD_ERROR_COUNT increments
QUEUE_ERROR_COUNT increments
post-recovery known-good command can complete
```

### 19.14 P30B Closure Criteria

P30B is complete when:

```text
cold boot / reset programming sequence is frozen
queue setup sequence is frozen
memory guard setup sequence is frozen
event arm / service / W1C / re-arm sequence is frozen
CQ consumption and batch service sequence is frozen
moderation setup sequence is frozen
telemetry sample / clear sequence is frozen
active-time versus idle-time register write policy is frozen
CQ-full recovery sequence is frozen
STOP_QUEUE recovery sequence is frozen
timeout recovery sequence is frozen
memory guard recovery sequence is frozen
no RTL / CSR / UVM / Tcl / regression-list changes are required for P30B
```

Current expected status after P30B:

```text
P29H: Documentation closure                                      PASS
P30A: Driver-facing runtime ABI prototype spec                   PASS
P30B: CSR programming sequence / ABI policy freeze               PASS
Full regression remains:
  TOTAL : 147
  PASS  : 147
  FAIL  : 0
```



---

## 20. P30C Host Runtime Driver Helper Cleanup / API Consolidation Checkpoint

P30C adds a UVM helper consolidation checkpoint for the P30 driver-facing ABI.

Implementation files updated:

```text
tb/uvm/helper/ai_accel_csr_access_helper.sv
tb/uvm/helper/ai_accel_event_driven_host_runtime_stress_helper.sv
```

P30C does not change RTL, CSR address allocation, register bit definitions, SQ/CQ formats, descriptor formats, completion record formats, event bits, telemetry counters, UVM top selection, Tcl flow, or regression-list contents.

### 20.1 Consolidation Intent

P19 through P29 built the runtime stack through several directed helper layers.  P30C keeps those lower-level helper functions intact and adds a thin driver-facing layer above them.

The intent is to make later P30D/P30E/P30F tests read like a software driver sequence rather than a milestone-by-milestone collection of primitive CSR writes.

P30C consolidates helper coverage for:

```text
telemetry CSR constants and read/clear/enable helpers
telemetry snapshot / log helpers
P30 driver ABI configuration bundle
cold-boot runtime initialization sequence
SQ submit + doorbell helper
START_QUEUE helper
CQ consume helper
event W1C + re-arm helper
telemetry sample helper
```

### 20.2 CSR Helper Consolidation

`ai_accel_csr_access_helper.sv` now exposes the P29 telemetry CSR constants that were previously local to P29D/P29E/P29F tests.

The added helper constants mirror the canonical P29B CSR policy in `axi_lite_csr_control_plane_spec.md`:

```text
CSR_TELEM_VERSION                  0x6C0
CSR_TELEM_COMMAND                  0x6C4
CSR_TELEM_STATUS                   0x6C8
CSR_TELEM_CONTROL                  0x6CC
CSR_TELEM_QUEUE_START_COUNT        0x6D0
CSR_TELEM_SQ_ACCEPT_COUNT          0x6D4
CSR_TELEM_CMD_COMPLETE_COUNT       0x6D8
CSR_TELEM_CQ_COMMIT_COUNT          0x6DC
CSR_TELEM_QUEUE_DRAINED_COUNT      0x6E0
CSR_TELEM_QUEUE_STOPPED_COUNT      0x6E4
CSR_TELEM_QUEUE_ERROR_COUNT        0x6E8
CSR_TELEM_CQ_HEAD_UPDATE_COUNT     0x6EC
CSR_TELEM_CQ_CONSUMED_COUNT        0x6F0
CSR_TELEM_MAX_CQ_BATCH_SIZE        0x6F4
CSR_TELEM_EVENT_CAPTURE_COUNT      0x6F8
CSR_TELEM_IRQ_ELIGIBLE_COUNT       0x6FC
CSR_TELEM_COMPLETION_EVENT_COUNT   0x700
CSR_TELEM_COALESCED_RELEASE_COUNT  0x704
CSR_TELEM_THRESHOLD_RELEASE_COUNT  0x708
CSR_TELEM_TIMER_RELEASE_COUNT      0x70C
CSR_TELEM_URGENT_BYPASS_COUNT      0x710
CSR_TELEM_CQ_FULL_STALL_COUNT      0x714
CSR_TELEM_CQ_SPACE_RECOVERED_COUNT 0x718
CSR_TELEM_TIMEOUT_ERROR_COUNT      0x71C
CSR_TELEM_MEM_GUARD_ERROR_COUNT    0x720
CSR_TELEM_STOP_QUEUE_REQUEST_COUNT 0x724
CSR_TELEM_QUEUE_ENABLED_CYCLES     0x728
CSR_TELEM_QUEUE_BUSY_CYCLES        0x72C
CSR_TELEM_QUEUE_IDLE_CYCLES        0x730
CSR_TELEM_QUEUE_STALLED_CYCLES     0x734
CSR_TELEM_CQ_FULL_STALL_CYCLES     0x738
CSR_TELEM_LOWER_WAIT_CYCLES        0x73C
```

This is a UVM helper cleanup only.  The canonical CSR map remains in `axi_lite_csr_control_plane_spec.md`.

### 20.3 Driver ABI Helper Bundle

P30C adds a reusable `p30_driver_runtime_abi_cfg_t` configuration bundle containing:

```text
queue configuration
memory guard configuration
event moderation configuration
event enable mask
event threshold / control policy
telemetry control value
enable_guard
enable_event_moderation
enable_telemetry
clear_queue_memory
clear_lower_sticky
```

This lets later P30 tests pass one ABI configuration object through the bring-up, service, and recovery helper APIs.

### 20.4 P30C Helper APIs

P30C adds these driver-facing helper APIs:

```text
host_rt_telem_control_value
host_rt_telem_clear
host_rt_telem_enable
host_rt_telem_disable
host_rt_telem_capture_snapshot
host_rt_telem_log_snapshot
host_rt_telem_snapshot_and_log
host_rt_telem_check_selected_zero
host_rt_abi_default_cfg
host_rt_abi_cold_boot_init
host_rt_abi_submit_command
host_rt_abi_start_queue
host_rt_abi_consume_one_cq
host_rt_abi_ack_and_rearm
host_rt_abi_sample_telemetry
```

The APIs are intentionally thin wrappers over existing P23/P26/P27/P28/P29 helper behavior.  They do not hide the lower-level primitives from directed tests.

### 20.5 Frozen P30C Policy

P30C freezes these helper-layer policies:

```text
P30 driver ABI tests should prefer P30 helper APIs for normal driver flow.
P30 tests may still call lower-level helpers when they intentionally validate a narrow sub-policy.
Telemetry helper constants live in ai_accel_csr_access_helper for UVM reuse.
P30 helper APIs must not change functional hardware state beyond the CSR writes required by the ABI sequence.
P30 cold-boot init must program guard regions before queue traffic when guard is enabled.
P30 cold-boot init must clear telemetry before enabling a measurement window.
P30 event ack/re-arm must preserve the P28 moderation path when moderation is enabled.
P30 CQ consumption must still advance CSR_CQ_HEAD after software has consumed CQ records.
```

### 20.6 P30C Closure Criteria

P30C is complete when:

```text
P29 telemetry CSR constants are available from the CSR helper
telemetry clear / enable / snapshot helper APIs are available
P30 driver ABI configuration bundle is available
cold-boot init helper is available
submit / start / CQ consume / ack-rearm / telemetry sample helpers are available
existing lower-level helper APIs remain available
no RTL / CSR map / SQ-CQ format / event-bit / Tcl / regression-list changes are required
```

Current expected status after P30C:

```text
P29H: Documentation closure                                      PASS
P30A: Driver-facing runtime ABI prototype spec                   PASS
P30B: CSR programming sequence / ABI policy freeze               PASS
P30C: Host runtime driver helper cleanup / API consolidation     PASS
Full regression remains:
  TOTAL : 147
  PASS  : 147
  FAIL  : 0
```


---

## 21. P30D Cold Boot / Queue Setup / First Command Smoke Checkpoint

P30D adds the first targeted UVM validation for the P30 driver-facing runtime ABI.

Implementation files updated:

```text
tb/uvm/pkg/ai_accel_subsys_uvm_pkg.sv
tb/uvm/test/ai_accel_subsys_csr_driver_abi_cold_boot_first_command_smoke_test.sv
```

P30D reuses the validated P19 through P29 queue / event / guard / telemetry runtime stack and the P30C helper API consolidation.  The test body is intentionally written as a software-driver-style bring-up flow instead of as a collection of unrelated low-level CSR transactions.

P30D validation flow:

```text
wait for reset release
initialize CSR bus access
build the selected CASE_ID payload
prepare DMA source / destination memories
program one memory-backed descriptor table
build one SQ command pointing at that descriptor table
build a P30 driver ABI configuration bundle
run P30 cold-boot init helper
  clear queue / event / lower-level / guard / telemetry sticky state
  program memory guard SQ / CQ / descriptor ranges
  program queue base / depth / stride / pointers
  arm queue completion and drained events
  enable telemetry
submit one SQ command
publish SQ_TAIL=1
issue START_QUEUE
wait for event notification
consume CQ[0]
advance CSR_CQ_HEAD
W1C-ack handled events and re-arm
sample telemetry
compare DMA destination C against the software reference
```

The memory guard is enabled for the normal driver bring-up path with SQ, CQ, and descriptor checks enabled.  Source and destination guard checks are left disabled in P30D because the first smoke focuses on the cold-boot / queue / event / telemetry ABI sequence.  Negative guard recovery is reserved for P30F.

Expected P30D PASS markers:

```text
[P30_ABI/INIT_PASS]
[P30D_ABI/COLD_BOOT_PASS]
[P30D_ABI/EVENT_PASS]
[P30_ABI/CQ_CONSUME]
[P30_ABI/ACK_REARM_PASS]
[P30D_ABI/QUEUE_STATE_PASS]
[P27_GUARD/CLEAN_PASS]
[P30_ABI/TELEM_SAMPLE_PASS]
[P30D_ABI/TELEMETRY_PASS]
[P30D_ABI/PASS]
```

P30D checks these driver ABI behaviors:

```text
cold boot helper leaves the queue idle and clean
memory guard can be programmed before queue traffic
queue setup is software-visible and reusable
first SQ command can be submitted through the P30 helper API
event wait sees CQ-not-empty / command-completed / drained notification
CQ consume advances CSR_CQ_HEAD
W1C ack plus re-arm clears handled event bits
CQ record remains the authoritative completion detail
telemetry captures start / accept / complete / CQ commit / CQ consume / event / IRQ / cycle counters
no timeout, memory guard, STOP_QUEUE, CQ-full stall, or moderation counters increment in the clean first-command path
GEMM / DMA result compare still passes
```

P30D does not add RTL, a CSR address window, register bit fields, SQ/CQ format changes, descriptor format changes, completion record format changes, event bits, telemetry counters, a standalone UVM top, or a standalone sim flow.

Current expected status after P30D validation:

```text
P29H: Documentation closure                                      PASS
P30A: Driver-facing runtime ABI prototype spec                   PASS
P30B: CSR programming sequence / ABI policy freeze               PASS
P30C: Host runtime driver helper cleanup / API consolidation     PASS
P30D: Cold boot -> queue setup -> first command smoke            PASS

Full regression remains:
  TOTAL : 147
  PASS  : 147
  FAIL  : 0
```

---

## 22. P30E Steady-State Driver Loop Smoke Checkpoint

P30E adds the second targeted UVM validation for the P30 driver-facing runtime ABI.

Implementation files updated:

```text
tb/uvm/pkg/ai_accel_subsys_uvm_pkg.sv
tb/uvm/test/ai_accel_subsys_csr_driver_abi_steady_state_loop_smoke_test.sv
```

P30E reuses the P30C driver-facing helper API and the P30D cold-boot bring-up sequence.  Unlike P30D, which proves the first command after initialization, P30E validates that software can stay in a steady-state driver loop over one monotonic SQ/CQ pointer epoch without re-running full cold boot initialization between commands.

P30E validation flow:

```text
wait for reset release
initialize CSR bus access
build the selected CASE_ID payload
prepare DMA source / destination memories
program three memory-backed descriptor tables
build one P30 driver ABI configuration bundle
run P30 cold-boot init helper once
  clear queue / event / lower-level / guard / telemetry sticky state
  program memory guard SQ / CQ / descriptor ranges
  program queue base / depth / stride / pointers
  arm queue completion and drained events
  enable telemetry
for each steady-state loop iteration:
  build one SQ command with a unique command tag and descriptor base
  submit the SQ command at the next SQ physical index
  publish the next monotonic SQ_TAIL value
  issue START_QUEUE
  wait for event notification
  consume the matching CQ entry
  advance CSR_CQ_HEAD
  W1C-ack handled events and re-arm
  clear queue done sticky before the next iteration
sample telemetry after the final iteration
check final SQ/CQ monotonic pointer state
check memory guard remains clean
compare DMA destination C against the software reference
```

P30E intentionally consumes one CQ entry per wakeup.  It proves the steady-state driver loop contract without enabling P28 moderation; batched CQ consumption remains covered by P28/P29 and can be reused by later P30 tests when needed.

Expected P30E PASS markers:

```text
[P30_ABI/INIT_PASS]
[P30E_ABI/COLD_BOOT_PASS]
[P30E_ABI/SUBMIT_PASS]
[P30E_ABI/EVENT_WAIT_PASS]
[P30_ABI/CQ_CONSUME]
[P30_ABI/ACK_REARM_PASS]
[P30E_ABI/ITER_PASS]
[P30E_ABI/REARM_PASS]
[P30E_ABI/LOOP_STATE_PASS]
[P27_GUARD/CLEAN_PASS]
[P30_ABI/TELEM_SAMPLE_PASS]
[P30E_ABI/TELEMETRY_PASS]
[P30E_ABI/PASS]
```

P30E checks these driver ABI behaviors:

```text
cold boot helper is run once before the steady-state loop
queue configuration remains reusable across multiple START_QUEUE sessions
SQ_HEAD / SQ_TAIL advance monotonically across loop iterations
CQ_HEAD / CQ_TAIL advance monotonically as software consumes CQ records
software can W1C-ack and re-arm events after each wakeup
queue done sticky can be cleared between drained steady-state iterations
CQ records remain the authoritative per-command completion detail
telemetry accumulates queue start / accept / complete / CQ commit / CQ consume counters across the loop
max CQ batch size remains one when the driver consumes one CQ record per wakeup
memory guard remains clean across repeated queue traffic
no timeout, memory guard, STOP_QUEUE, CQ-full stall, or moderation counters increment in the clean steady-state loop
GEMM / DMA result compare still passes
```

P30E does not add RTL, a CSR address window, register bit fields, SQ/CQ format changes, descriptor format changes, completion record format changes, event bits, telemetry counters, a standalone UVM top, or a standalone sim flow.

Current expected status after P30E implementation:

```text
P29H: Documentation closure                                      PASS
P30A: Driver-facing runtime ABI prototype spec                   PASS
P30B: CSR programming sequence / ABI policy freeze               PASS
P30C: Host runtime driver helper cleanup / API consolidation     PASS
P30D: Cold boot -> queue setup -> first command smoke            PASS
P30E: Steady-state driver loop smoke                             IMPLEMENTED / RUN PENDING

Full regression remains:
  TOTAL : 147
  PASS  : 147
  FAIL  : 0
```

