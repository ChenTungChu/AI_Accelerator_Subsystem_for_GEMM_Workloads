# P28 Event Coalescing / Interrupt Moderation Prototype Spec

## 1. Purpose

This document defines the P28 event coalescing / interrupt moderation prototype for the AI Accelerator Subsystem.

P28A introduced the prototype intent.  P28B freezes the first software-visible Event CSR moderation policy while keeping the canonical register map, bit fields, access types, and reset values in `axi_lite_csr_control_plane_spec.md`.

P17 through P27 established a host-programmable accelerator runtime stack:

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
```

P27 proved that host-provided SQ, descriptor, source, destination, and CQ addresses can be checked before unsafe lower-level memory operations are launched.

P28 adds the next host-runtime efficiency layer:

```text
Allow hardware to write one CQ record per completed command,
but avoid forcing the host to take one interrupt per completion.
```

The goal is not to change the command execution model, CQ record format, or event CSR fundamentals.  The goal is to let the P22/P23 event-driven runtime consume completions in batches while preserving deterministic wakeup behavior for errors, stops, stalls, and recovery.

Current baseline entering P28A:

```text
P27 memory access guard closure:
  TOTAL : 141
  PASS  : 141
  FAIL  : 0
```

---

## 2. Baseline Before P28

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
P26 queue lifecycle cleanup, soft-reset, and reinit validation
P27 host-visible memory access guard and recovery validation
CQ completion records committed into host-visible completion memory
SQ_HEAD / CQ_TAIL pointer advancement after completion commit
CQ_HEAD host recovery during active queue service
QUEUE_COMMAND_COMPLETED_EVENT / CQ_NOT_EMPTY_EVENT notification
QUEUE_ERROR_EVENT notification for timeout and memory-guard failures
full regression 141/141 PASS after P27G/P27H
```

P28 must preserve:

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
BRAM / GEMM / DMA / AXI-Stream / Direct Stream datapath behavior
```

P28 should be implemented as an event-notification policy extension over the existing queue/event/runtime stack.  It should not require multi-outstanding command execution, out-of-order completion, CQ format changes, or datapath changes.

---

## 3. P28 Design Intent

P19 through P27 make the accelerator look like a small but robust host-controlled device.  A driver can submit work through SQ memory, receive CQ records, wait on events, handle CQ-full conditions, stop/restart sessions, recover from timeout, and reject unsafe memory addresses.

The next runtime-efficiency question is:

```text
Can the host consume several CQ records per wakeup instead of being notified once per command?
```

Without P28, the event-driven runtime is intentionally simple:

```text
command completes
CQ record commits
CQ_TAIL advances
P22 sets completion / CQ-not-empty event
host wakes
host consumes CQ
host clears / rearms events
```

This is correct and easy to debug, but a real driver often wants to reduce interrupt rate:

```text
multiple commands complete
multiple CQ records accumulate
hardware coalesces notification
host wakes once
host consumes several CQ records
host advances CQ_HEAD once or in a tight loop
host W1C clears and rearms events
```

P28 defines a coalesced notification contract:

```text
CQ records remain authoritative and are still committed per command.
Event notification may be delayed until a CQ occupancy threshold is reached.
A moderation timer can provide bounded latency when threshold is not reached.
Urgent terminal/error conditions bypass coalescing and wake the host immediately.
Host runtime can batch-consume CQ records and re-arm without losing notifications.
```

Concise intent:

```text
P28 turns the event path from per-completion notification into bounded, batch-friendly host notification.
```

---

## 4. P28A Scope

### 4.1 Included

P28A defines:

```text
event coalescing concept
interrupt moderation concept
CQ threshold notification policy
moderation timer fallback policy
which event sources may be coalesced
which event sources must bypass coalescing
host batch-CQ consume / re-arm model
relationship to existing P21 CQ-full recovery, P22 events, P23 runtime, P24 timeout, P26 lifecycle, and P27 guard errors
UVM validation direction for threshold, timer, batching, and recovery cases
P28B/P28C/P28D/P28E/P28F/P28G/P28H milestone plan
```

### 4.2 Not Included

P28A does not include:

```text
RTL implementation
CSR RTL changes
canonical CSR address map
canonical register bit fields
new SQ entry format
new CQ completion record format
new P18 completion record format
new P22 event bit allocation beyond the P28B timer-release event bit
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
interrupt controller integration
clock-domain rewrite
```

P28A is a prototype specification milestone only.  P28B should freeze the CSR policy and place any canonical register map, register bit fields, access types, and reset values in `axi_lite_csr_control_plane_spec.md`.

---

## 5. Fixed P28A Design Decisions

```text
Notification target            : P22 event / interrupt-lite layer
Data authority                 : CQ records remain authoritative
Execution model                : still one active command at a time
Completion order               : still in-order CQ records
CQ record production           : still one record per completed command
Host consumption               : may consume multiple CQ records per wakeup
Moderation scope               : completion / CQ-not-empty style events only
Urgent events                  : queue error / stopped / drained / CQ-full recovery bypass coalescing
Reset compatibility            : moderation disabled by reset
SQ entry format                : unchanged for P28A
CQ entry format                : unchanged for P28A
Descriptor format              : unchanged for P28A
Completion record format       : unchanged for P28A
Lifecycle model                : reuse existing P26 cleanup / reinit policy
Memory safety model            : reuse existing P27 guard policy
CSR map                        : P28B canonical fields frozen in CSR spec
```

P28A treats coalescing as a notification policy.  It does not redefine command execution, CQ commit, pointer advancement, or completion record semantics.

---

## 6. Notification Sources

P28A separates P22 event sources into coalescible and urgent classes.

### 6.1 Coalescible Completion Sources

These event sources may be coalesced when moderation is enabled:

```text
QUEUE_COMMAND_COMPLETED_EVENT
CQ_NOT_EMPTY_EVENT
CQ_THRESHOLD_EVENT
```

These events describe useful CQ work for the host.  Delaying the interrupt for a bounded time is acceptable as long as CQ records are already committed and visible in CQ memory.

Coalescing does not mean dropping completions:

```text
CQ_TAIL advances per committed completion.
CQ memory contains every completion record.
Event pending state summarizes that host-visible CQ work is available.
The host determines how many records to consume by reading CQ_HEAD / CQ_TAIL or CQ occupancy.
```

### 6.2 Urgent Terminal / Error Sources

These event sources should bypass completion coalescing:

```text
QUEUE_ERROR_EVENT
QUEUE_STOPPED_EVENT
QUEUE_DRAINED_EVENT
CQ_FULL_STALL_EVENT
CQ_SPACE_RECOVERED_EVENT
RUNTIME_DOORBELL_EVENT
RUNTIME_APPEND_CONSUMED_EVENT
TEST_EVENT
```

Rationale:

```text
QUEUE_ERROR_EVENT must wake the host promptly for timeout / guard / sequence failures.
QUEUE_STOPPED_EVENT is a host-requested control-plane terminal condition.
QUEUE_DRAINED_EVENT is a session boundary and should remain visible for cleanup logic.
CQ_FULL_STALL_EVENT may require host action to free CQ space.
CQ_SPACE_RECOVERED_EVENT is part of active-service recovery.
Runtime doorbell debug events should remain observable without batching policy ambiguity.
TEST_EVENT should preserve existing P22 smoke determinism.
```

P28B may further refine the bypass policy, but P28A keeps urgent events conservative to avoid hiding control-plane state transitions.

---

## 7. Coalescing Model

### 7.1 Immediate Compatibility Mode

The reset-compatible behavior is the existing P22 behavior:

```text
completion commit
    -> completion-related event pending bit can be set immediately
    -> event_irq follows pending & enable & global_irq
```

P28 tests explicitly enable moderation.  Existing 141/141 regression behavior should remain unchanged when moderation is disabled.

### 7.2 CQ Occupancy Threshold

The threshold policy is:

```text
if moderation is enabled
and CQ occupancy after a completion is >= CQ_NOTIFY_THRESHOLD
then hardware may set the coalesced CQ notification event
```

Recommended first policy:

```text
CQ_NOTIFY_THRESHOLD = 0 : threshold disabled; moderation reset keeps immediate compatibility mode
CQ_NOTIFY_THRESHOLD = 1 : equivalent to notify when at least one CQ is available
CQ_NOTIFY_THRESHOLD > 1 : batch notification after that many unconsumed CQ entries are visible
```

The event layer should sample CQ occupancy only after a valid CQ completion commit or at defined re-arm points.  It should not speculate about commands that have not yet committed a CQ record.

### 7.3 Moderation Timer Fallback

A threshold-only policy can delay notification indefinitely when the workload is sparse.  P28 adds a moderation timer fallback:

```text
when first unnotified CQ entry becomes visible,
start moderation timer

if CQ occupancy reaches threshold before timer expires,
set coalesced CQ notification event and stop timer

if timer expires while CQ occupancy is still non-zero,
set coalesced CQ notification event and stop timer
```

Recommended first policy:

```text
TIMER_CYCLES = 0 : timer disabled
TIMER_CYCLES > 0 : bounded-latency fallback enabled
```

The timer is a notification timer only.  It is distinct from the P24 command timeout watchdog:

```text
P24 watchdog : command made no terminal progress in time -> queue error
P28 timer    : CQ work exists but threshold was not reached -> notify host
```

P28 timer expiry is not an error.

### 7.4 Coalesced Event Commit Point

P28 should set event pending only after a safe visibility point:

```text
CQ record final commit word is visible
CQ_TAIL has advanced
CQ occupancy reflects the new record
coalescing condition is satisfied
```

This preserves the P18/P19/P20/P21 rule that event notification never advertises a completion record before the record is valid.

---

## 8. Host Batch Consume Model

P28 extends the P23 event-driven host runtime style with batch CQ consumption.

Recommended host loop:

```text
wait for event_irq or event pending
read event snapshot / queue snapshot
read CQ_HEAD and CQ_TAIL
while CQ_HEAD != CQ_TAIL and batch budget not exhausted:
  read CQ record at CQ_HEAD physical index
  validate commit word / tag / status
  consume record
  increment local CQ_HEAD
write CSR_CQ_HEAD with the new consumed counter
W1C event pending bits
re-arm event enable / global IRQ
if CQ still non-empty after re-arm, expect either immediate re-notification or timer/threshold re-trigger according to policy
```

P28 should allow either of these host update styles:

```text
advance CQ_HEAD after each consumed record
advance CQ_HEAD once after consuming a batch
```

The first UVM helper may choose the simpler batched writeback policy:

```text
consume N records from memory
write CSR_CQ_HEAD once with the final counter
```

### 8.1 Batch Budget

The host may limit how many CQ records it consumes per wakeup.

Examples:

```text
consume all visible CQ entries
consume up to a fixed software budget
consume until a specific user tag is observed
```

P28 hardware does not need to know the host software budget unless P28B explicitly adds a debug CSR.  The authoritative source of remaining work is still CQ_HEAD/CQ_TAIL.

### 8.2 Re-arm / Lost Notification Avoidance

P28 must avoid a lost-notification hole around W1C and re-arm.

If software clears pending events while CQ remains non-empty, one of these policies should hold:

```text
if CQ occupancy still meets threshold, event pending is reasserted at a defined sampling point
if threshold is not met but CQ is non-empty and timer is enabled, moderation timer restarts
if immediate compatibility mode is active, CQ_NOT_EMPTY_EVENT can be reasserted immediately
```

The host should not need to poll forever after clearing a coalesced event while unconsumed CQ records remain.

---

## 9. Interaction with Existing Milestones

### 9.1 Relationship to P21 Runtime Doorbell / Live Queue Service

P28 does not change runtime SQ_TAIL observation.

Existing P21 policy remains:

```text
host may append SQ entries while queue_busy=1
hardware observes live SQ_TAIL only at command boundaries
active command uses snapshotted SQ/CQ context
CQ-full command-boundary stall recovers when host advances CQ_HEAD
```

P28 adds notification batching after CQ commits.  It does not allow hardware to consume SQ entries out of order or complete commands out of order.

### 9.2 Relationship to P22 Events

P28 is an extension of the P22 event policy.

P22 fundamentals remain:

```text
event pending capture is independent of interrupt enable
event_irq is derived from pending & enable & global_irq
W1C clears sticky pending bits
CQ completion record remains authoritative per-command detail
```

P28 modifies when completion-related pending bits are set while moderation is enabled.  It should not redefine W1C, enable, global IRQ, or snapshot basics.

### 9.3 Relationship to P23 Host Runtime

P28C should extend the existing host runtime helper rather than creating a new UVM top or separate sim flow.

New helper behavior should be shaped like:

```text
submit SQ command(s)
wait for coalesced event
batch consume CQ records
advance CQ_HEAD
clear/re-arm events
check no stale pending state remains
continue service or recover according to existing runtime policy
```

### 9.4 Relationship to P24 Timeout

P28 moderation timer is not a watchdog.

```text
P24 timeout indicates failed command progress and sets queue error.
P28 moderation timer indicates delayed notification for already-visible CQ work.
```

P24 timeout / QUEUE_ERROR_EVENT must bypass coalescing and wake the host promptly.

### 9.5 Relationship to P26 Lifecycle

P28 should not add a new lifecycle model.

After a stopped, drained, timeout, guard, or other error terminal condition, the host continues to use the P26 cleanup / reinit model:

```text
observe terminal event
consume any valid CQ records if present
clear event pending bits
clear queue / lower-level / guard sticky status as required
reinitialize or restart the session according to P26 policy
```

### 9.6 Relationship to P27 Memory Guard

P27 guard failures must bypass completion coalescing.

If a memory guard failure reaches queue error:

```text
QUEUE_ERROR_EVENT should wake the host promptly
CSR_QUEUE_ERROR_STATUS[9] remains authoritative
CSR_MEM_GUARD_* diagnostics remain authoritative
CQ error record may exist only if CQ slot is safe
```

P28 should not delay memory guard error visibility behind a CQ threshold or moderation timer.

---

## 10. P28B Frozen CSR Policy Summary

P28B freezes the Event CSR moderation policy and records the canonical register map, register bit fields, access types, and reset values in `axi_lite_csr_control_plane_spec.md`.

Frozen CSR policy summary:

```text
reuse the existing P22 event CSR window
preserve CSR_EVENT_CQ_THRESHOLD semantics as the CQ occupancy threshold
use previously reserved P22 event offsets for moderation control/status/timer/debug
moderation disabled by reset to preserve existing 141/141 regression behavior
completion coalescing opt-in through Event CSR control
urgent event bypass policy documented in CSR policy notes
one optional timer-release event bit is frozen for timer fallback observability
```

Frozen software-visible concepts:

```text
MODERATION_ENABLE
CQ_THRESHOLD_ENABLE
MODERATION_TIMER_ENABLE
RETRIGGER_ON_STILL_NONEMPTY
CQ_MODERATION_TIMER_EVENT
MODERATION_TIMER_LIMIT
MODERATION_STATUS
MODERATION_RELEASE_DEBUG
```

These names are summarized here only for architectural context.  The canonical addresses, bit positions, access types, and reset values are defined only in the CSR spec.

---

## 11. Error and Recovery Policy

P28 coalescing should not create new queue error causes for normal batching behavior.

Normal coalesced behavior:

```text
CQ records accumulate
notification delayed by threshold / timer policy
host wakes
host consumes CQ records
host advances CQ_HEAD
host clears/re-arms events
queue continues service
```

This is not an error.

P28 implementation errors or unsupported CSR combinations may be reported through a future P28 event/moderation reject status if P28B defines one, but the first prototype should keep the software-visible model simple.

Urgent events bypass moderation:

```text
QUEUE_ERROR_EVENT
QUEUE_STOPPED_EVENT
QUEUE_DRAINED_EVENT
CQ_FULL_STALL_EVENT
CQ_SPACE_RECOVERED_EVENT
```

A known-good command should still complete normally after any P26-style cleanup that was already valid before P28.

---

## 12. UVM Validation Strategy

P28 validation should reuse the existing CSR wrapper top and event-driven queue runtime style.

Common test setup:

```text
UVM_TOP = ai_accel_subsys_csr_uvm_top
CASE_ID = 102 or focused representative case
ENABLE_RESULT_CHECK = 0 for notification-policy tests unless final known-good command compares results
FORCE_HELPER_MEM_PATH = 0
DMA_CLK_PERIOD_NS = 10
CORE_CLK_PERIOD_NS = 14
```

Common expected behavior:

```text
CQ records are still committed in order
CQ_TAIL advances for every completed command
host sees fewer interrupt wakeups than CQ records when moderation is enabled
host batch-consumes multiple CQ records correctly
W1C / re-arm does not lose notification if CQ remains non-empty
urgent queue error / stopped / drained / CQ-full events are not hidden by moderation
UVM_ERROR == 0
UVM_FATAL == 0
```

Suggested debug markers:

```text
[P28_MOD/THRESHOLD_EVENT_PASS]
[P28_MOD/TIMER_FALLBACK_PASS]
[P28_MOD/BATCH_CONSUME_PASS]
[P28_MOD/REARM_PASS]
[P28_MOD/URGENT_BYPASS_PASS]
[P28_MOD/PASS]
```

---

## 13. P28 Milestone Plan

Recommended P28 split:

```text
P28A: Event coalescing / interrupt moderation prototype spec     PASS
P28B: Event CSR moderation policy freeze                         PASS
P28C: Host runtime batch-CQ consume helper extension             PASS
P28D: CQ threshold interrupt smoke                               IMPLEMENTED / RUN PENDING
P28E: moderation timer fallback smoke                            TODO
P28F: multi-command batch consume / re-arm recovery smoke        TODO
P28G: full regression integration                                TODO
P28H: documentation closure                                      TODO
```

### 13.1 P28B Event CSR Moderation Policy Freeze

P28B freezes the first Event CSR moderation policy.

Frozen P28B decisions:

```text
P28 reuses reserved addresses inside the existing P22 event CSR window
P28 does not allocate a new CSR window
CSR_EVENT_CQ_THRESHOLD is reused as the CQ occupancy threshold register
moderation is disabled by reset to preserve existing 141/141 regression behavior
completion / CQ-not-empty style event notification is coalesced only when software explicitly enables moderation
moderation release may be caused by CQ threshold or moderation timer expiry
urgent terminal / error / recovery events bypass completion coalescing
host W1C / re-arm while CQ remains non-empty must either reassert notification or restart moderation timing at a defined sampling point
P28 adds one optional timer-release event source so software can distinguish timer fallback from threshold release
```

P28B freezes these event-source classes:

```text
Coalescible when moderation is enabled:
  QUEUE_COMMAND_COMPLETED_EVENT
  CQ_NOT_EMPTY_EVENT
  CQ_THRESHOLD_EVENT
  CQ_MODERATION_TIMER_EVENT

Urgent bypass, not delayed by moderation:
  QUEUE_ERROR_EVENT
  QUEUE_STOPPED_EVENT
  QUEUE_DRAINED_EVENT
  CQ_FULL_STALL_EVENT
  CQ_SPACE_RECOVERED_EVENT
  RUNTIME_DOORBELL_EVENT
  RUNTIME_APPEND_CONSUMED_EVENT
  TEST_EVENT
```

P28B freezes the first release policy:

```text
when moderation is disabled:
  preserve existing P22 immediate event behavior

when moderation is enabled and a CQ completion commits:
  update CQ_TAIL and CQ occupancy as usual
  hold completion-style notification until a release condition is met

threshold release:
  if threshold moderation is enabled and CQ occupancy reaches CSR_EVENT_CQ_THRESHOLD
  then set coalesced CQ notification pending bits

timer release:
  if timer moderation is enabled and a first unnotified CQ entry is visible
  then start the moderation timer
  if the timer expires before threshold release
  then set coalesced CQ notification pending bits

urgent bypass:
  queue error / stopped / drained / CQ-full recovery / runtime debug / TEST_EVENT sources set pending immediately
```

P28B freezes the first W1C / re-arm policy:

```text
If software clears coalesced event pending bits while CQ remains non-empty,
hardware must resample CQ occupancy at the next defined event sampling point.

If occupancy already meets threshold, notification may reassert immediately.
If occupancy does not meet threshold but timer moderation is enabled, the timer restarts.
If moderation is disabled, existing immediate CQ-not-empty behavior is preserved.
```

Canonical register map, register bit fields, access types, reset values, and the optional timer-release event bit are recorded only in:

```text
docs/axi_lite_csr_control_plane_spec.md
```

P28B is a policy-freeze documentation checkpoint.  It does not add RTL, UVM tests, Tcl changes, regression-list items, SQ/CQ format changes, descriptor format changes, completion record format changes, or a standalone simulation flow.

Current expected status after P28B:

```text
P27H: Documentation closure                                      PASS
P28A: Event coalescing / interrupt moderation prototype spec     PASS
P28B: Event CSR moderation policy freeze                         PASS
P28C: Host runtime batch-CQ consume helper extension             PASS
Full regression remains:
  TOTAL : 141
  PASS  : 141
  FAIL  : 0
```

### 13.2 P28C Host Runtime Batch-CQ Consume Helper Extension

P28C extends the existing UVM host runtime helper layer for batch-oriented host service.

Implementation locations:

```text
tb/uvm/helper/ai_accel_csr_access_helper.sv
tb/uvm/helper/ai_accel_event_driven_host_runtime_stress_helper.sv
```

P28C adds UVM-side CSR constants for the frozen P28B event moderation fields:

```text
CSR_EVENT_MOD_CONTROL
CSR_EVENT_MOD_STATUS
CSR_EVENT_MOD_TIMER_LIMIT
CSR_EVENT_MOD_DEBUG
P28_EVENT_CQ_MOD_TIMER
EVENT_MOD_CONTROL_*
EVENT_MOD_STATUS_*
EVENT_MOD_DEBUG_*
P28_MOD_RELEASE_*
```

P28C adds helper-side moderation structures:

```systemverilog
typedef struct {
    logic [31:0] mod_control;
    logic [31:0] event_enable_mask;
    logic [31:0] event_control;
    logic [31:0] cq_threshold;
    logic [31:0] timer_limit;
} p28_event_mod_cfg_t;

typedef struct {
    logic [31:0] event_status;
    logic [31:0] event_pending;
    logic [31:0] event_enable;
    logic [31:0] event_control;
    logic [31:0] event_last_cause;
    logic [31:0] event_count;
    logic [31:0] event_irq_count;
    logic [31:0] event_cq_threshold;
    logic [31:0] mod_control;
    logic [31:0] mod_status;
    logic [31:0] mod_timer_limit;
    logic [31:0] mod_debug;
    logic [31:0] queue_status;
    logic [31:0] queue_done_status;
    logic [31:0] queue_error_status;
    logic [31:0] queue_reject_status;
    logic [31:0] sq_head;
    logic [31:0] sq_tail;
    logic [31:0] cq_head;
    logic [31:0] cq_tail;
    logic [31:0] sq_occupancy;
    logic [31:0] cq_occupancy;
    logic [31:0] cq_space;
} p28_event_mod_snapshot_t;

typedef struct {
    logic [31:0] start_cq_head;
    logic [31:0] start_cq_tail;
    logic [31:0] visible_count;
    logic [31:0] consumed_count;
    logic [31:0] final_cq_head;
    logic [31:0] first_commit_word;
    logic [31:0] last_commit_word;
    logic [31:0] first_user_tag;
    logic [31:0] last_user_tag;
} p28_cq_batch_result_t;
```

P28C adds reusable helper operations:

```text
host_rt_event_mod_control_value
host_rt_event_mod_completion_mask
host_rt_event_mod_release_name
host_rt_event_mod_status_cq_occ
host_rt_event_mod_status_unnotified
host_rt_event_mod_debug_release_cause
host_rt_event_mod_debug_release_count
host_rt_event_mod_debug_threshold_count
host_rt_event_mod_debug_timer_count
host_rt_event_mod_default_cfg
host_rt_event_mod_program
host_rt_event_mod_disable
host_rt_event_mod_capture_snapshot
host_rt_event_mod_log_snapshot
host_rt_event_mod_snapshot_and_log
host_rt_event_mod_wait_notification
host_rt_event_mod_expect_no_irq_delta
host_rt_event_mod_expect_pending
host_rt_event_mod_expect_release_cause
host_rt_event_mod_expect_cq_occupancy
host_rt_event_mod_consume_cq_batch
host_rt_event_mod_ack_and_rearm
host_rt_event_mod_expect_urgent_bypass
```

The intended P28D/P28E/P28F usage is:

```text
program moderation policy through the P22/P28 event CSR window
submit commands through the existing P19/P21 queue runtime path
wait for a coalesced CQ notification instead of per-command IRQ
capture event / moderation / queue / CQ snapshots
consume a visible CQ batch
publish one CSR_CQ_HEAD update after the batch
W1C clear and re-arm coalesced events
check no early IRQ, threshold release, timer release, and urgent bypass behavior
```

P28C is a helper-only integration checkpoint.  It does not add RTL, a standalone UVM top, a standalone sim flow, a full-regression item, an SQ/CQ format change, a descriptor format change, a completion format change, or a new CSR window.

P28C closure criteria:

```text
P28 event moderation CSR constants are available to UVM helper code
P28 moderation policy programming helper is available
P28 event/moderation/queue snapshot and log helper is available
P28 coalesced notification wait helper is available
P28 batch-CQ consume helper advances CQ_HEAD once after consuming a batch
P28 event W1C / re-arm helper composes with existing P22 event helper behavior
P28 no-early-IRQ, release-cause, CQ occupancy, pending-event, and urgent-bypass checkers are available
No standalone test or regression item is added at P28C
```

### 13.3 P28D CQ Threshold Interrupt Smoke

Purpose:

```text
validate completion records accumulate without per-completion IRQ when threshold > 1
validate IRQ/event appears when CQ occupancy reaches threshold
validate host consumes multiple CQ records in one wakeup
validate event W1C / re-arm after batch consume
```

Suggested test name:

```text
ai_accel_subsys_csr_event_coalesce_threshold_smoke_test
```

Expected PASS markers:

```text
[P28D_MOD/VALID_BASELINE_PASS]
[P28D_MOD/NO_EARLY_IRQ_PASS]
[P28D_MOD/THRESHOLD_IRQ_PASS]
[P28D_MOD/BATCH_CONSUME_PASS]
[P28D_MOD/PASS]
```

### 13.4 P28E Moderation Timer Fallback Smoke

Purpose:

```text
validate threshold can be larger than available completions
validate first CQ record can start a moderation timer
validate timer expiry wakes the host even when threshold is not reached
validate timer expiry is not reported as a queue error
validate host can consume the sparse CQ record and re-arm cleanly
```

Suggested test name:

```text
ai_accel_subsys_csr_event_coalesce_timer_smoke_test
```

Expected PASS markers:

```text
[P28E_MOD/BASELINE_PASS]
[P28E_MOD/NO_THRESHOLD_PASS]
[P28E_MOD/TIMER_IRQ_PASS]
[P28E_MOD/BATCH_CONSUME_PASS]
[P28E_MOD/PASS]
```

### 13.5 P28F Multi-Command Batch Consume / Re-arm Recovery Smoke

Purpose:

```text
validate multi-command live service with coalesced notification
validate host can consume multiple CQ records, update CQ_HEAD, W1C, and re-arm
validate new commands appended after re-arm are still serviced
validate urgent error / stopped / drained event is not hidden by moderation
validate final lifecycle clean idle state
```

Suggested test name:

```text
ai_accel_subsys_csr_event_coalesce_batch_rearm_smoke_test
```

Expected PASS markers:

```text
[P28F_MOD/BATCH1_PASS]
[P28F_MOD/REARM_PASS]
[P28F_MOD/BATCH2_PASS]
[P28F_MOD/URGENT_BYPASS_PASS]
[P28F_MOD/RECOVERY_PASS]
[P28F_MOD/PASS]
```

### 13.6 P28G Full Regression Integration

P28G should add a small representative subset to the full regression.

Recommended full-regression items:

```text
csr_event_coalesce_threshold_case102
csr_event_coalesce_timer_case102
csr_event_coalesce_batch_rearm_case102
```

Expected full-regression count if three items are added:

```text
Before P28G : 141
After P28G  : 144
```

### 13.7 P28H Documentation Closure

P28H should update:

```text
README.md
axi_lite_csr_control_plane_spec.md
event_coalescing_interrupt_moderation_prototype_spec.md
uvm_regression.list
run_full_uvm_regression.tcl
```

The CSR map remains canonical only in `axi_lite_csr_control_plane_spec.md`.

---

## 14. P28B Closure Criteria

P28B is complete when:

```text
P28 event moderation policy is frozen
P28 reuses the existing P22 event CSR window instead of allocating a new window
CQ threshold and moderation timer release policy are documented
coalescible completion-style events and urgent bypass events are documented
W1C / re-arm / still-nonempty-CQ retrigger policy is documented
canonical moderation registers and the optional timer-release event bit are recorded only in the CSR spec
no RTL / UVM / Tcl / regression-list changes are required for P28B
```

P28B does not change the regression count.

Current expected status after P28B:

```text
P27H: Documentation closure                                      PASS
P28A: Event coalescing / interrupt moderation prototype spec     PASS
P28B: Event CSR moderation policy freeze                         PASS
P28C: Host runtime batch-CQ consume helper extension             PASS
Full regression remains:
  TOTAL : 141
  PASS  : 141
  FAIL  : 0
```

---

## 15. P28C Host Runtime Batch-CQ Helper Closure

P28C implements the UVM-side helper layer needed by the later P28D/P28E/P28F targeted tests.

Files updated:

```text
tb/uvm/helper/ai_accel_csr_access_helper.sv
tb/uvm/helper/ai_accel_event_driven_host_runtime_stress_helper.sv
```

P28C does not change RTL or the CSR map.  The canonical P28 event moderation register map remains in `axi_lite_csr_control_plane_spec.md`.

Validation status after P28C:

```text
P27H: Documentation closure                                      PASS
P28A: Event coalescing / interrupt moderation prototype spec     PASS
P28B: Event CSR moderation policy freeze                         PASS
P28C: Host runtime batch-CQ consume helper extension             PASS
Full regression remains:
  TOTAL : 141
  PASS  : 141
  FAIL  : 0
```

P28C is treated as PASS after the helper extension compiled successfully in the integrated UVM package. P28D is the first targeted RTL/UVM checkpoint that uses these helpers for CQ-threshold interrupt moderation validation.

---

## 15. P28A Closure Criteria

P28A is complete when:

```text
event coalescing purpose and scope are documented
completion-related coalescible event sources are identified
urgent bypass event sources are identified
CQ threshold notification policy is defined
moderation timer fallback policy is defined
host batch-CQ consume / CQ_HEAD update / W1C re-arm policy is documented
relationship to P21/P22/P23/P24/P26/P27 is documented
P28B/P28C/P28D/P28E/P28F/P28G/P28H validation direction and PASS markers are documented
no RTL / CSR / Tcl / regression-list changes are required for P28A
```

P28A does not change the regression count.

Current expected status after P28C:

```text
P27H: Documentation closure                                      PASS
P28A: Event coalescing / interrupt moderation prototype spec     PASS
P28B: Event CSR moderation policy freeze                         PASS
P28C: Host runtime batch-CQ consume helper extension             PASS
Full regression remains:
  TOTAL : 141
  PASS  : 141
  FAIL  : 0
```

---

## 16. Interview Notes

P28 is useful because it shows the accelerator runtime is moving from correctness and safety into host-service efficiency.

Concise explanation:

```text
After adding memory protection, I added interrupt moderation and CQ batching so the host runtime does not need to take one interrupt per completion. CQ records are still committed in order, but the event layer can coalesce notifications based on CQ occupancy threshold or a moderation timer. The host wakes once, consumes multiple CQ records, advances CQ_HEAD, clears/re-arms events, and queue service continues.
```

Key points:

```text
CQ records remain authoritative.
Coalescing changes notification timing, not command execution.
Threshold notification reduces interrupt rate for busy command streams.
Timer fallback bounds latency for sparse command streams.
Error / stopped / drained / CQ-full recovery events bypass moderation.
The host runtime batch-consumes CQ records and re-arms events safely.
P28 preserves single-active-command, in-order completion, existing SQ/CQ formats, and P27 memory-guard recovery.
```

Tradeoff explanation:

```text
The design intentionally avoids multi-outstanding commands and out-of-order completion.  That keeps the one-person project understandable while still adding a realistic driver-facing optimization: fewer host wakeups for the same in-order CQ record stream.
```


---

## 16. P28D CQ Threshold Interrupt Smoke Implementation Checkpoint

P28D implements the first event coalescing / interrupt moderation RTL and targeted UVM validation checkpoint.

Implementation files updated:

```text
rtl/csr/ai_accel_csr_regs.sv
tb/uvm/pkg/ai_accel_subsys_uvm_pkg.sv
tb/uvm/test/ai_accel_subsys_csr_event_mod_cq_threshold_smoke_test.sv
```

P28D does not require a new standalone UVM top, a new sim flow, a new CSR window, an SQ/CQ format change, a descriptor format change, a completion record format change, or a BRAM/GEMM/DMA/frontend datapath change.

P28D RTL policy:

```text
CSR_EVENT_MOD_CONTROL enables moderation explicitly; reset preserves immediate P22 behavior
completion-style CQ events are held when moderation is enabled
CQ threshold release uses CSR_EVENT_CQ_THRESHOLD
urgent queue/error/debug events bypass moderation
CQ records are still committed in order at every command completion
event_irq is generated only when released pending bits are enabled and GLOBAL_IRQ_ENABLE is set
```

P28D UVM validation flow:

```text
program moderation threshold = 2
a single valid command commits one CQ record without early completion IRQ
a two-command queue drain commits two CQ records and releases CQ threshold notification
host consumes visible CQ records as a batch
host publishes one CQ_HEAD update after batch consume
host W1C-clears and re-arms the event path
final DMA result compare still passes
```

Expected P28D PASS markers:

```text
[P28D_MOD/VALID_BASELINE_PASS]
[P28D_MOD/NO_EARLY_IRQ_PASS]
[P28D_MOD/THRESHOLD_IRQ_PASS]
[P28D_MOD/BATCH_CONSUME_PASS]
[P28D_MOD/REARM_PASS]
[P28D_MOD/PASS]
```

Current status after P28D implementation:

```text
P27H: Documentation closure                                      PASS
P28A: Event coalescing / interrupt moderation prototype spec     PASS
P28B: Event CSR moderation policy freeze                         PASS
P28C: Host runtime batch-CQ consume helper extension             PASS
P28D: CQ threshold interrupt smoke                               IMPLEMENTED / RUN PENDING

Full regression remains:
  TOTAL : 141
  PASS  : 141
  FAIL  : 0
```
