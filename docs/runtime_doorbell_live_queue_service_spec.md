# P21 Runtime Doorbell / Live Queue Service Spec

## 1. Purpose

This document defines the P21A/P21B runtime doorbell / live queue service policy for the AI Accelerator Subsystem.

P19 introduced a host-visible submission queue and completion queue prototype:

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

P20 extended that path into an in-order multi-entry queue drain:

```text
START_QUEUE
    -> SQ[0] -> execute -> CQ[0]
    -> SQ[1] -> execute -> CQ[1]
    -> SQ[2] -> execute -> CQ[2]
    -> drain until SQ empty / stop / error
```

P21 extends P20 with a runtime doorbell policy.  While a queue drain session is active, the host may append additional SQ entries and update `CSR_SQ_TAIL`.  The queue controller observes the new tail only at safe command boundaries and may continue draining without requiring another `START_QUEUE` kick, as long as the drain session has not already reached the drained terminal state.

P21 remains intentionally conservative:

```text
one active command at a time
in-order SQ_HEAD to SQ_TAIL command execution
in-order CQ_TAIL completion production
no out-of-order completion
no overlapping command execution
no interrupt model
no driver model
no BRAM / GEMM / DMA / frontend datapath changes
```

The goal is to make the P20 host queue behave more like a runtime-serviced accelerator queue while keeping the implementation deterministic and explainable.

Current baseline entering P21A/P21B:

```text
P20G / P20H multi-entry queue drain closure:
  TOTAL : 117
  PASS  : 117
  FAIL  : 0
```

---

## 2. Baseline Before P21

The validated P20 queue model includes:

```text
P19 queue CSR register window at 0x580 - 0x5FC
P19 SQ command entry format
P18 CQ completion record format
P20 RUN_UNTIL_EMPTY auto-drain
multi-entry SQ drain
multiple in-order CQ completion records
SQ/CQ physical wrap-around using monotonic counters
STOP_AFTER_THIS command-boundary stop
STOP_QUEUE graceful stop
full regression 117/117 PASS
```

P21 builds only on the queue-controller policy above P19/P20.

P21 must preserve the existing lower-level hierarchy:

```text
P14 CSR micro-operation path      -> debug / compatibility
P15 single-job sequencer          -> one descriptor worker
P16 CSR-resident recipe sequencer -> multi-slot recipe dispatcher
P17 descriptor fetch prototype    -> memory-backed recipe descriptor loader
P18 completion writeback          -> memory-backed completion record writer
P19 queue controller              -> host command / completion queue wrapper
P20 in-order queue drain          -> repeated single-command path
P21 runtime doorbell policy       -> observe host tail updates at command boundaries
```

P21 must not require changes to:

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
P19/P20 queue CSR address map
```

---

## 3. P21 Design Intent

P20 validates batch-style queue draining:

```text
host writes a batch of SQ entries
host updates SQ_TAIL
host writes START_QUEUE
hardware drains visible entries until SQ empty / stop / error
```

P21 validates runtime doorbell behavior:

```text
host writes SQ[0]
host updates SQ_TAIL=1
host writes START_QUEUE
hardware begins executing SQ[0]

while hardware is active:
  host writes SQ[1]
  host writes CMD_CONTROL.VALID last
  host updates CSR_SQ_TAIL=2

hardware reaches the command boundary after SQ[0]
hardware re-reads SQ_TAIL
hardware observes SQ_HEAD != SQ_TAIL
hardware fetches SQ[1] without requiring another START_QUEUE
```

The key design point is that P21 observes host-owned pointer updates only at safe command boundaries.  The active command continues to use its already-snapshotted SQ/CQ context and is not affected by host writes during execution.

P21 is not a multi-outstanding queue, scheduler, prefetcher, interrupt controller, or driver model.

---

## 4. P21A Scope

### 4.1 Included

P21A defines:

```text
runtime doorbell design intent
append-while-active submission policy
safe command-boundary SQ_TAIL observation policy
safe command-boundary CQ_HEAD / CQ space observation policy
active command snapshot isolation policy
CQ full stall and host recovery while a drain session is active
STOP_QUEUE interaction with runtime append
STOP_AFTER_THIS interaction with runtime append
UVM validation plan
full-regression closure plan
```

### 4.2 Not Included

P21A does not include:

```text
RTL implementation
CSR RTL changes
new CSR addresses
new CSR bit definitions
UVM tests
interrupt output
MSI/MSI-X style interrupt model
always-on idle polling after SQ empty
multiple outstanding commands
overlapped queue fetch and command execution
out-of-order completion
prefetch of future SQ entries while one command is active
scheduler priority
command cancellation / preemption
cache-coherent host interface
Linux driver
C software driver
UVM RAL model
AXI interconnect / NoC integration
DMA / GEMM / frontend datapath changes
```

The first P21 implementation should validate append-while-active behavior without turning the queue controller into an always-on daemon.

---

## 5. P21B Live Doorbell Policy Scope

P21B freezes the queue-controller policy for observing host-owned doorbell updates while the queue is active.

P21B is still a spec / design-policy milestone.  It should not add RTL by itself.

P21B defines:

```text
when CSR_SQ_TAIL writes may be observed
when CSR_CQ_HEAD writes may be observed
when a runtime append is eligible for immediate continuation
when the controller still reports drained
how CQ full recovery works during an active session
how STOP_QUEUE and STOP_AFTER_THIS suppress further runtime append processing
what command context must be snapshotted
what CSR map remains unchanged
```

P21B intentionally reuses the P19/P20 CSR map.  The canonical queue CSR register map remains in:

```text
docs/axi_lite_csr_control_plane_spec.md
```

No P21A/P21B CSR register-map update is required beyond documenting that `CSR_SQ_TAIL` and `CSR_CQ_HEAD` are host-owned runtime doorbells that may be written while the queue controller is enabled.

---

## 6. Fixed P21 Design Decisions

```text
Outstanding command count       : one active command at a time
Command order                   : in-order SQ_HEAD -> SQ_TAIL
Completion order                : in-order CQ_TAIL follows accepted command order
Execution overlap               : not allowed in P21
Command prefetch while active   : not required in P21
Queue entry size                : existing P19/P20 64-byte SQ entry
Completion entry size           : existing P18/P19/P20 64-byte CQ entry
Descriptor format               : existing P17 descriptor format unchanged
Completion record format        : existing P18 record format unchanged
Pointer model                   : existing monotonic SQ_HEAD/SQ_TAIL/CQ_HEAD/CQ_TAIL counters
Physical index                  : pointer modulo depth
CSR map                         : existing P19/P20 queue CSR map unchanged
Doorbell source                 : host writes CSR_SQ_TAIL
CQ recovery source              : host writes CSR_CQ_HEAD
BRAM / GEMM / DMA / frontend    : unchanged
```

P21 does not change the host memory commit policy:

```text
host writes SQ command payload first
host writes SQ command VALID word last
host updates CSR_SQ_TAIL after the SQ entry is visible
hardware writes CQ completion payload first
hardware writes CQ commit word last
hardware updates CSR_CQ_TAIL only after completion commit succeeds
```

---

## 7. Runtime Doorbell Session Model

A runtime doorbell session begins when `CSR_QUEUE_COMMAND.START_QUEUE` is accepted.

At session start:

```text
queue_busy is set
QUEUE_STARTED sticky status is set
queue configuration is validated
SQ_HEAD / SQ_TAIL / CQ_HEAD / CQ_TAIL are read for the first command-boundary check
```

During the session:

```text
hardware accepts one SQ command at a time
hardware snapshots the active command context
hardware executes through P17/P16/P15 and P18
hardware advances SQ_HEAD and CQ_TAIL at command terminal status
hardware then re-evaluates live SQ_TAIL and CQ_HEAD before accepting another command
```

The session continues when:

```text
RUN_UNTIL_EMPTY=1
no stop request is pending
no terminal queue error is pending
SQ_HEAD != latest CSR_SQ_TAIL
latest CQ space is non-zero
lower-level engines are idle
```

The session ends when:

```text
SQ_HEAD == latest CSR_SQ_TAIL at a command boundary
RUN_UNTIL_EMPTY=0 and one command completed
STOP_QUEUE was requested and the active command completed
CMD_CONTROL.STOP_AFTER_THIS was set for the active command
queue-level error occurs and STOP_ON_ERROR=1
reset occurs
```

P21 keeps the first implementation kick-driven:

```text
If the controller reaches SQ empty before the host appends another visible SQ entry, it reports drained and queue_busy returns to 0.
A later host append after drained requires another START_QUEUE kick.
```

This is the smallest useful runtime doorbell model and is enough to validate append-while-active submission.

---

## 8. Runtime `CSR_SQ_TAIL` Observation Policy

`CSR_SQ_TAIL` is host-owned and may be written while the queue controller is enabled or busy.

The queue controller must observe `CSR_SQ_TAIL` only at command-boundary decision points:

```text
before accepting the first command after START_QUEUE
after the active command reaches terminal queue status
after SQ_HEAD has been advanced for the active command
after any CQ_TAIL update has completed for the active command
after completion/writeback status for the active command is finalized
```

The queue controller must not use a changing `CSR_SQ_TAIL` value to alter the active command's already-snapshotted context.

Safe active-command snapshot:

```text
sq_head_snapshot
sq_index_snapshot
sq_entry_addr_snapshot
cmd_control_snapshot
cmd_user_tag_snapshot
cmd_desc_base_snapshot
cmd_desc_count_snapshot
cmd_desc_stride_snapshot
cmd_completion_flags_snapshot
cmd_timeout_snapshot
cq_tail_snapshot
cq_index_snapshot
cq_entry_addr_snapshot
```

Host writes to `CSR_SQ_TAIL` while a command is executing are treated as a doorbell for the next command-boundary check.

---

## 9. Runtime `CSR_CQ_HEAD` Observation Policy

`CSR_CQ_HEAD` is host-owned and may be written while the queue controller is enabled or busy.

The queue controller observes `CSR_CQ_HEAD` at command-boundary checks and CQ-full stall checks.

Before accepting a command:

```text
cq_occupancy = CSR_CQ_TAIL - latest CSR_CQ_HEAD
cq_space     = CSR_CQ_DEPTH - cq_occupancy
```

If `cq_space == 0`:

```text
queue controller stalls before fetching the next SQ entry
SQ_HEAD does not advance
no command-memory AXI read is issued for the next command
QUEUE_STALLED / CQ_FULL live status is asserted
no queue error is set by default
```

When host consumes one or more CQ entries and updates `CSR_CQ_HEAD`:

```text
cq_space becomes non-zero
if no stop/error condition is pending, the active drain session can continue
```

This extends the P20 CQ full behavior from batch drain to runtime service.

---

## 10. Runtime Append Eligibility

A host-appended SQ entry is eligible for runtime continuation when all conditions are true:

```text
queue_busy is still high
RUN_UNTIL_EMPTY=1
no STOP_QUEUE is pending
active command did not have STOP_AFTER_THIS=1
queue error sticky is not set
host wrote the SQ entry payload first
host wrote CMD_CONTROL.VALID=1 last
host advanced CSR_SQ_TAIL after the entry became visible
CQ space is available
lower-level engines are idle at command boundary
```

If these conditions are met, hardware may continue from the just-completed command to the newly appended command without another `START_QUEUE` write.

If the queue already reported drained before the host append:

```text
queue_busy is 0
new START_QUEUE is required
```

---

## 11. Stop Behavior During Runtime Service

### 11.1 `STOP_QUEUE`

`CSR_QUEUE_COMMAND.STOP_QUEUE` requests a graceful stop.

If a command is active:

```text
finish the active command
attempt normal completion writeback
advance SQ_HEAD / CQ_TAIL normally after completion commit
set STOPPED_AFTER_COMMAND sticky status
do not fetch a runtime-appended SQ entry
clear queue_busy after the command boundary
```

A runtime append that occurs after `STOP_QUEUE` is pending is not consumed in the current session.

### 11.2 `STOP_AFTER_THIS`

If the active command has `CMD_CONTROL.STOP_AFTER_THIS=1`:

```text
execute the command normally
write the completion record normally
advance SQ_HEAD / CQ_TAIL normally
set STOPPED_AFTER_COMMAND sticky status
do not consume any runtime-appended SQ entry
```

This preserves the P20 command-boundary stop contract even when the host updates `CSR_SQ_TAIL` while the command is active.

---

## 12. Error Behavior During Runtime Service

Default P21 policy:

```text
STOP_ON_ERROR=1
```

When a queue-level error occurs:

```text
set queue error sticky status
record error index/detail
stop the runtime service session
require CLEAR_QUEUE_ERROR before another START_QUEUE can be accepted
```

Runtime appends do not bypass sticky error handling.

If the active command fails completion writeback before CQ commit:

```text
CQ_TAIL must not advance
queue error sticky is set
runtime service stops
CSR completion-writeback status remains authoritative for writeback details
```

---

## 13. Suggested RTL Delta for Later P21C/P21D

P21A/P21B do not implement RTL, but the expected RTL delta should remain small.

Likely modified RTL:

```text
rtl/sequencer/ai_accel_queue_fetch_controller.sv
rtl/top/ai_accel_subsys_csr_top.sv, only if additional internal pulse plumbing is needed
```

Likely queue-controller additions:

```text
live_tail_check at command boundary
latest SQ_TAIL sample before next command acceptance
latest CQ_HEAD sample before next command acceptance and while CQ-full stalled
runtime_append_seen debug flag or internal event, optional
command-boundary branch that distinguishes:
  continue with newly appended command
  drained because SQ empty
  stopped because STOP_QUEUE / STOP_AFTER_THIS
  stalled because CQ full
```

No new RTL modules are expected for P21C/P21D.

---

## 14. UVM Validation Plan

Recommended P21 milestone split:

```text
P21A: Runtime doorbell / live queue service spec
P21B: Queue controller live SQ_TAIL observation policy
P21C: Append-while-active DMA queue smoke
P21D: Append-while-active mixed queue smoke
P21E: CQ full stall + host CQ_HEAD recovery during active service
P21F: STOP_QUEUE during live service
P21G: Full regression integration
P21H: Docs closure
```

### 14.1 P21C Append-While-Active DMA Queue Smoke

Purpose:

```text
validate host can append SQ[1] while SQ[0] is active
validate hardware observes updated SQ_TAIL at command boundary
validate hardware continues to SQ[1] without a second START_QUEUE
validate SQ_HEAD advances by 2
validate CQ_TAIL advances by 2
validate CQ[0] and CQ[1] completion records commit in order
```

Suggested test name:

```text
ai_accel_subsys_csr_queue_runtime_append_dma_smoke_test
```

Representative sequence:

```text
program SQ[0]
set SQ_TAIL=1
START_QUEUE
wait until queue_busy / command active
program SQ[1]
write SQ[1].CMD_CONTROL.VALID last
write SQ_TAIL=2
wait for final drain
expect SQ_HEAD=2, CQ_TAIL=2, CQ_OCC=2
```

### 14.2 P21D Append-While-Active Mixed Queue Smoke

Purpose:

```text
validate runtime append across different command/recipe profiles
validate per-command P17/P18 sticky clear still happens between commands
validate second CQ record reflects the appended command context
```

Recommended combination:

```text
SQ[0] = DMA descriptor recipe
SQ[1] = Direct Stream descriptor recipe or C RMW descriptor recipe
```

The stronger representative is:

```text
SQ[0] = DMA descriptor recipe
SQ[1] = Direct Stream descriptor recipe
SQ[2] = C RMW descriptor recipe, appended while earlier command is active
```

### 14.3 P21E CQ Full Stall + Host Recovery During Active Service

Purpose:

```text
validate runtime service stalls on CQ full at command boundary
validate no extra SQ command is consumed while CQ full
validate host can advance CQ_HEAD while queue_busy remains high
validate hardware observes new CQ_HEAD and resumes service
```

Representative sequence:

```text
program CQ depth small enough to become full after one command
START_QUEUE
append more SQ commands while active
allow first completion to fill CQ
observe CQ_FULL / QUEUE_STALLED
host consumes CQ[0] and writes CQ_HEAD=1
hardware resumes and consumes next SQ command
```

### 14.4 P21F STOP_QUEUE During Live Service

Purpose:

```text
validate STOP_QUEUE wins over runtime append
validate active command completes normally
validate appended command is not consumed after stop request
validate stopped status is set without queue error
```

Representative sequence:

```text
program SQ[0]
START_QUEUE
while SQ[0] active:
  program SQ[1]
  update SQ_TAIL=2
  issue STOP_QUEUE
expect:
  SQ_HEAD=1
  CQ_TAIL=1
  SQ[1] remains pending
  STOPPED_AFTER_COMMAND sticky set
```

---

## 15. Full Regression Plan

P21G should add a small representative subset to full regression.

Recommended full-regression representatives:

```text
csr_queue_runtime_append_dma_case102
csr_queue_runtime_append_mixed_case208
csr_queue_runtime_cq_full_recovery_case102
csr_queue_runtime_stop_case102
```

Expected count increase:

```text
Before P21G: 117
After P21G : 121
```

This should remain a representative regression, not an exhaustive runtime queue stress suite.

---

## 16. P21 Closure Criteria

P21 is complete when:

```text
P21A/P21B design policy is documented
host can update SQ_TAIL while queue is active
queue controller observes SQ_TAIL at command boundaries
runtime-appended commands are consumed in order without a second START_QUEUE
active command snapshots are isolated from host pointer updates
CQ full stall and host CQ_HEAD recovery work during active service
STOP_QUEUE suppresses further runtime appends after the active command
STOP_AFTER_THIS suppresses further runtime appends after the marked command
full regression passes with P21 representatives
no BRAM / GEMM / DMA / frontend datapath changes are required
```

---

## 17. Interview Summary

P21 is the step that turns P20 from a batch queue drain into a runtime-serviced queue.

Concise explanation:

```text
P19 proved one SQ command can run through P17/P16/P15 and complete through P18 into CQ.
P20 repeated that path in order until the visible queue became empty.
P21 lets the host append more SQ entries while the controller is still active; the hardware safely observes the updated SQ_TAIL only at command boundaries.
```

The design remains intentionally conservative:

```text
one active command
in-order execution
in-order completion
no out-of-order behavior
no interrupt dependency
no datapath rewrite
```

The main design advantage is that P21 improves host-interface realism while preserving a small, deterministic queue controller.
