# P27 Memory Access Guard / Address Range Validation Prototype Spec

## 1. Purpose

This document defines the P27A memory access guard / address range validation prototype for the AI Accelerator Subsystem.

P17 through P26 established a host-programmable accelerator runtime stack:

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
```

P26 proved that drained, stopped, and timeout/error terminal sessions can be cleaned up and reused without global reset.

P27 adds the next host-runtime robustness layer:

```text
Before hardware consumes a host-provided pointer or launches a lower-level memory operation,
validate that the generated host-memory access stays inside an allowed address range.
```

The goal is not to add a new datapath architecture, a cache-coherent memory system, or an IOMMU.  The goal is to prevent malformed host-provided SQ, descriptor, DMA-source, DMA-destination, or completion-queue addresses from causing uncontrolled external-memory reads or writes.

Current baseline entering P27A:

```text
P26 queue lifecycle / soft-reset closure:
  TOTAL : 138
  PASS  : 138
  FAIL  : 0
```

---

## 2. Baseline Before P27

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
CQ completion records committed into host-visible completion memory
SQ_HEAD / CQ_TAIL pointer advancement after completion commit
CQ_HEAD host recovery during active queue service
STOP_QUEUE pending-work preserve / restart behavior
COMMAND_TIMEOUT_ERROR structured queue error reporting
P26 error cleanup requiring lower-level quiesce before known-good restart
full regression 138/138 PASS after P26G/P26H
```

P27 must preserve:

```text
one active command at a time
in-order command execution
in-order completion production
P17 descriptor format unless later explicitly changed
P18 completion record format
P19 SQ entry format
P19/P20/P21 queue CSR behavior
P22 event CSR behavior
P23 host runtime programming model
P24 timeout / watchdog reporting model
P26 lifecycle cleanup and reinit behavior
BRAM / GEMM / DMA / AXI-Stream / Direct Stream datapath behavior
```

P27 should be implemented as a guard layer around host-visible memory accesses and command validation.  It should not require BRAM, GEMM compute, AXI-Stream data-path, Direct Stream operand-buffer, or scratchpad semantic changes.

---

## 3. P27 Design Intent

P19 through P26 make the accelerator look like a small host-controlled device.  A driver can now submit work through SQ memory, receive completions through CQ memory, wait on events, stop/restart sessions, and recover from timeout/error terminal states.

The missing device-level robustness question is:

```text
What happens if the host programs an address outside the memory region that hardware is allowed to touch?
```

Without P27, many tests assume the host provides legal memory addresses:

```text
SQ base points to valid command memory
CQ base points to valid completion memory
descriptor base/count/stride point to valid descriptor memory
A/B source memory is readable
DMA store destination memory is writable
completion writeback slot is writable
```

P27 defines a bounded memory-access contract:

```text
Host-provided addresses are checked before use.
Out-of-range accesses are rejected deterministically.
Rejected commands do not launch unsafe lower-level memory transactions.
The host observes the failure through the existing queue/error/event/lifecycle model.
A valid command can still complete after P26-style cleanup and reinit.
```

Concise intent:

```text
P27 turns host-visible memory addresses from trusted testbench inputs into validated command resources.
```

---

## 4. P27A Scope

### 4.1 Included

P27A defines:

```text
memory access guard concept
host-visible address domains
range / alignment / size validation policy
where guard checks occur in the queue / descriptor / completion path
safe reject behavior before unsafe memory access
relationship to existing P19 queue errors, P22 events, and P26 lifecycle cleanup
UVM validation direction for legal and illegal address cases
P27B/P27C/P27D/P27E/P27F/P27G/P27H milestone plan
```

### 4.2 Not Included

P27A does not include:

```text
RTL implementation
CSR RTL changes
canonical CSR address map
canonical register bit fields
new SQ entry format
new CQ completion record format
new P17 descriptor format
new P18 completion record size
new P22 event bit allocation
new queue timeout field
BRAM / scratchpad memory protection
GEMM internal memory protection
AXI interconnect firewall
IOMMU / MMU / page table
cache coherency
privilege levels
multi-process isolation
virtual addressing
Linux driver
C software driver
UVM RAL model
multi-outstanding command execution
out-of-order completion
```

P27A is a prototype specification milestone only.  P27B should freeze the CSR policy and place any canonical register map, register bit fields, access types, and reset values in `axi_lite_csr_control_plane_spec.md`.

---

## 5. Fixed P27A Design Decisions

```text
Guard location                 : queue / descriptor / completion launch boundary
Primary validation target       : host-visible external memory accesses
Command execution              : still one active command at a time
Completion order               : still in-order CQ records
SQ entry format                : unchanged for P27A
CQ entry format                : unchanged for P27A
Descriptor format              : unchanged for P27A
Completion record format       : unchanged for P27A
Event model                    : reuse existing P22 queue error event path
Lifecycle model                : reuse existing P26 cleanup / reinit policy
Timeout model                  : unchanged P24 watchdog policy
BRAM / GEMM / DMA datapaths    : unchanged
CSR map                        : deferred to P27B canonical CSR policy freeze
```

P27A treats the guard as a command-safety layer.  It does not redefine the queue execution pipeline.

---

## 6. Address Domains

P27A separates host-visible address checks into logical domains.  A first implementation may map several logical domains to the same physical UVM memory model, but the policy should keep the domains distinct.

### 6.1 SQ Command Memory Domain

The SQ domain covers command entries fetched by the queue controller.

Examples:

```text
CSR_SQ_BASE_ADDR
CSR_SQ_DEPTH
CSR_SQ_STRIDE
current SQ physical index
64-byte SQ command fetch address
```

The guard should reject a queue configuration or current SQ fetch if the computed SQ entry address is outside the allowed SQ command-memory range.

### 6.2 CQ Completion Memory Domain

The CQ domain covers completion records written by P18 through the queue path.

Examples:

```text
CSR_CQ_BASE_ADDR
CSR_CQ_DEPTH
CSR_CQ_STRIDE
current CQ physical index
64-byte CQ completion write address
```

The guard should reject or fail safely before a completion writeback can write outside the allowed CQ completion-memory range.

### 6.3 Descriptor Memory Domain

The descriptor domain covers P17 descriptor table reads.

Examples:

```text
SQ command descriptor base
SQ command descriptor count
SQ command descriptor stride
per-descriptor 64-byte or 0x80-byte descriptor fetch address
```

The guard should reject malformed descriptor ranges before the descriptor fetch engine issues an out-of-range AXI read.

### 6.4 Source Memory Domain

The source domain covers external source-memory reads used by preload paths.

Examples:

```text
DMA load A source range
DMA load B source range
AXI-Stream preload source range
Direct Stream preload source range
```

The guard should reject a command or descriptor before launching a lower-level source read that would cross the allowed source-memory boundary.

### 6.5 Destination Memory Domain

The destination domain covers external destination-memory writes produced by DMA store paths.

Examples:

```text
DMA store destination base
DMA store byte count
DMA destination memory range
```

The guard should reject a command or descriptor before launching a lower-level destination write that would cross the allowed destination-memory boundary.

### 6.6 Internal Scratchpad Domain

The internal scratchpad / BRAM address map is not the primary P27A target.

Current P27A policy:

```text
host-visible external memory addresses are guarded
internal scratchpad C/A/B addresses follow existing subsystem validation policy
BRAM semantics remain unchanged
```

A later milestone may add scratchpad-window validation if needed, but P27A should avoid changing the stable BRAM baseline.

---

## 7. Guard Range Model

P27A uses a simple half-open range model for each guarded domain:

```text
allowed if:
  region_enable == 1
  addr >= region_base
  addr + size_bytes <= region_limit
  addr + size_bytes does not overflow 32-bit address arithmetic
```

The allowed range is:

```text
[region_base, region_limit)
```

This means `region_limit` is the first byte that is not accessible.

Recommended generic check:

```text
access_start = addr
access_end   = addr + size_bytes
valid        = region_enable
            && size_bytes != 0
            && access_end > access_start
            && access_start >= region_base
            && access_end <= region_limit
```

Alignment checks are domain-specific:

```text
SQ entry fetch       : entry address aligned to AXI data width and SQ stride policy
CQ completion write  : entry address aligned to AXI data width and CQ stride policy
descriptor fetch     : descriptor address aligned to AXI data width; descriptor stride policy remains P17-compatible
source memory reads  : aligned according to existing lower-level DMA / stream source rules
destination writes   : aligned according to existing DMA store byte/beat rules
```

P27A should reject integer-overflow cases even if the wrapped value would appear to fall inside the allowed region.

---

## 8. Guard Check Points

P27A defines guard checks at command boundaries, not after unsafe traffic has already been launched.

### 8.1 Queue Configuration Check

Before accepting `START_QUEUE`, the queue configuration must pass existing P19 checks plus guard range checks.

Guard additions:

```text
SQ base/depth/stride span fits inside SQ command-memory range
CQ base/depth/stride span fits inside CQ completion-memory range
SQ depth/stride multiplication does not overflow
CQ depth/stride multiplication does not overflow
```

If the queue configuration is invalid, `START_QUEUE` is rejected.  No SQ command fetch should be issued.

### 8.2 SQ Entry Fetch Check

Before fetching the current SQ command entry:

```text
sq_index = SQ_HEAD modulo SQ_DEPTH
sq_addr  = CSR_SQ_BASE_ADDR + sq_index * CSR_SQ_STRIDE
```

The guard checks:

```text
sq_addr range covers one full SQ entry
sq_addr arithmetic does not overflow
sq_addr lies inside the SQ command-memory allowed range
```

If the check fails, the queue enters a terminal error or reject path without issuing the SQ AXI read.

### 8.3 SQ Command Descriptor Range Check

After a valid SQ command is fetched but before descriptor fetch is launched, the queue validates the descriptor table span from the command fields.

The guard checks:

```text
descriptor count is non-zero when required
descriptor stride is supported by the current P17 policy
descriptor table span does not overflow
descriptor table span lies inside the descriptor-memory allowed range
```

If the check fails, P17 descriptor fetch should not be launched.

### 8.4 Descriptor Entry Fetch Check

Before each descriptor-entry read, the descriptor fetch path should check the computed descriptor entry address.

This protects against:

```text
base/count/stride combinations that pass a simple base check but overflow later entries
bad physical index calculations
future descriptor stride variants
```

For the first P27 implementation, this check may be integrated into the P17 launch-side validation if the descriptor fetch engine only reads a fixed bounded table generated from already-validated fields.

### 8.5 Descriptor Payload Source/Destination Check

After descriptor payload fields are available and before launching P16/P15 lower-level work, the selected frontend memory ranges should be checked.

For DMA load or frontend preload:

```text
A source base + A byte count lies inside source-memory range
B source base + B byte count lies inside source-memory range
```

For DMA store:

```text
store destination base + store byte count lies inside destination-memory range
```

If the check fails, the lower-level P15 job sequencer should not launch the unsafe preload/store stage.

### 8.6 Completion Writeback / CQ Slot Check

Before requesting P18 completion writeback into a CQ slot:

```text
cq_index = CQ_TAIL modulo CQ_DEPTH
cq_addr  = CSR_CQ_BASE_ADDR + cq_index * CSR_CQ_STRIDE
```

The guard checks:

```text
cq_addr range covers one full CQ completion record
cq_addr arithmetic does not overflow
cq_addr lies inside the CQ completion-memory allowed range
```

If the check fails, hardware must not issue an out-of-range completion write.  Since the CQ slot is not safe, the queue/error CSR and P22 event path become the authoritative error-reporting mechanism for this failure.

---

## 9. Error and Recovery Policy

P27A reuses the existing queue/event/lifecycle model for software-visible errors.

### 9.1 Safe Reject Before Unsafe Access

If a guard check fails before a lower-level command is launched:

```text
no unsafe AXI read/write should be issued
queue should report a deterministic error or reject
P22 should report QUEUE_ERROR_EVENT through the existing event path
P26 error cleanup should be able to clear sticky state and reinitialize the session
```

### 9.2 Completion Record Policy

If the CQ completion-memory address is valid, the implementation may write a normal error completion record into CQ.

If the CQ completion-memory address is invalid, the implementation must not write a completion record outside the allowed CQ range.

Recommended first policy:

```text
CQ-valid error path:
  write CQ error record if the selected CQ slot itself is inside the CQ range

CQ-invalid error path:
  do not write CQ
  report error through queue CSR status/detail and P22 QUEUE_ERROR_EVENT
```

This preserves the P24/P26 principle that queue CSR error/status is authoritative when no valid CQ record exists.

### 9.3 Lifecycle Recovery

After a guard error, the host runtime should follow the P26 timeout/error discard cleanup pattern:

```text
observe QUEUE_ERROR_EVENT or queue error status
capture event / queue / guard diagnostics
consume optional CQ error record if one validly committed
clear event pending bits
clear queue error/reject sticky bits
clear guard sticky status if P27B adds it
clear lower-level sticky status if any lower-level engine was launched before the guard failure
recycle SQ/CQ memory as needed
reinitialize queue configuration or region configuration
wait lower-level quiesce if the failure occurred after partial lower-level launch
submit a known-good command
confirm normal completion and final clean state
```

A guard failure detected before lower-level launch should not require lower-level quiesce.  A guard failure detected after descriptor payload decode but before a selected lower stage launches should still be cleaned through the same P26 error-discard path for consistency.

---

## 10. Guard Failure Classes

P27A defines failure classes for validation and debug.  P27B should decide how these are encoded in canonical CSR status/detail fields.

```text
GUARD_DISABLED
  Guard is required for the command, but the relevant region is disabled.

GUARD_ZERO_SIZE
  Requested access size is zero where a non-zero memory access is required.

GUARD_BASE_BELOW_RANGE
  Access start is below region_base.

GUARD_END_ABOVE_RANGE
  Access end is greater than region_limit.

GUARD_ADDRESS_OVERFLOW
  addr + size_bytes wraps or does not monotonically increase.

GUARD_ALIGNMENT_ERROR
  Address violates required alignment for the domain.

GUARD_STRIDE_ERROR
  SQ/CQ/descriptor stride is unsupported or creates an invalid span.

GUARD_DEPTH_ERROR
  SQ/CQ depth is zero, unsupported, or creates an invalid span.

GUARD_DOMAIN_MISMATCH
  An access is attempted against the wrong configured memory domain.
```

The first implementation does not need to expose every class as a separate sticky bit.  It should at least preserve enough detail for UVM to distinguish the failing domain and failing address.

---

## 11. Guard Configuration Policy

P27A does not freeze the CSR map.  The canonical register map belongs in `axi_lite_csr_control_plane_spec.md` during P27B.

However, the first implementation should provide a way to configure or derive these logical region ranges:

```text
SQ command-memory allowed range
CQ completion-memory allowed range
descriptor-memory allowed range
source-memory allowed range
destination-memory allowed range
```

Recommended policy direction for P27B:

```text
region base / limit registers are programmed while the queue is idle
range configuration writes while queue_busy is high are rejected or ignored with sticky reject status
guard enable defaults should preserve existing regression unless P27 tests explicitly enable strict checking
region limits use half-open [base, limit) semantics
canonical reset values, access types, and bit definitions are recorded only in the CSR spec
```

P27A deliberately does not allocate addresses or define register bit fields in this document.

---

## 12. Interaction with Existing Milestones

### 12.1 Relationship to P19 Queue Validation

P27 extends existing P19 queue configuration validation with memory-range validation.

Existing P19 checks remain valid:

```text
queue enabled
base alignment
non-zero depth
power-of-two depth
supported stride
occupancy within depth
```

P27 adds:

```text
computed SQ/CQ spans fit inside allowed host memory ranges
computed entry addresses do not overflow
computed entry addresses are inside the configured regions
```

### 12.2 Relationship to P22 Events

P27 should reuse the existing `QUEUE_ERROR_EVENT` for guard failures.  A new event bit is not required for P27A.

P27B may define optional guard-specific status registers, but event notification should remain summary-level:

```text
QUEUE_ERROR_EVENT wakes the host
guard/queue status explains the reason
CQ record, if valid, gives per-command completion detail
```

### 12.3 Relationship to P24 Timeout

Guard failures and timeouts are distinct.

```text
guard failure : bad address detected before or at launch boundary
timeout       : accepted command fails to make terminal progress in time
```

A guard failure should not rely on watchdog expiry to become visible.

### 12.4 Relationship to P26 Lifecycle

P27 guard errors should be recoverable through P26 error-discard cleanup.

Representative recovery expectation:

```text
bad command triggers QUEUE_ERROR_EVENT
host captures diagnostics
host clears queue/event/guard sticky state
host recycles SQ/CQ memory
host fixes address range or command address
host submits known-good command
known-good command completes
final clean idle state is observed
```

P27 should not add a new lifecycle model.

---

## 13. UVM Validation Strategy

P27 validation should reuse the existing CSR wrapper top and event-driven queue runtime style.

Common test setup:

```text
UVM_TOP = ai_accel_subsys_csr_uvm_top
CASE_ID = 102 or focused representative case
ENABLE_RESULT_CHECK = 0 for negative guard tests unless final known-good command compares results
FORCE_HELPER_MEM_PATH = 0
DMA_CLK_PERIOD_NS = 10
CORE_CLK_PERIOD_NS = 14
```

Common expected negative-test behavior:

```text
bad address command does not complete as a normal command
QUEUE_ERROR_EVENT or queue error status is observed
diagnostic status identifies guard failure domain/detail
no unsafe target memory is modified
P26 cleanup/reinit makes the queue reusable
known-good command after cleanup completes normally
UVM_ERROR == 0
UVM_FATAL == 0
```

Suggested debug markers:

```text
[P27_GUARD/ERROR_OBSERVED]
[P27_GUARD/NO_UNSAFE_ACCESS_PASS]
[P27_GUARD/RECOVERY_PASS]
[P27_GUARD/PASS]
```

---

## 14. P27 Milestone Plan

Recommended P27 split:

```text
P27A: Memory access guard prototype spec                         PASS
P27B: Memory guard CSR policy / range register map freeze        PASS
P27C: Guard helper / checker utility integration                 PASS
P27D: SQ / descriptor range validation smoke                     IMPLEMENTED / RUN PENDING
P27E: DMA source / destination range validation smoke            TODO
P27F: CQ / completion writeback guard + lifecycle recovery smoke TODO
P27G: Full regression integration                                TODO
P27H: Documentation closure                                      TODO
```

### 14.1 P27B CSR Policy / Range Register Map Freeze

P27B should decide:

```text
whether P27 gets a new CSR window or reuses existing reserved fields
which region base/limit registers exist
how guard enable bits reset
which guard status/detail fields are software-visible
how guard failures map into existing queue error/reject status
whether any new queue error bit is needed
whether P22 needs any new event bit, or reuses QUEUE_ERROR_EVENT only
```

Canonical CSR map, register bit fields, access types, and reset values must be placed in:

```text
docs/axi_lite_csr_control_plane_spec.md
```

### 14.2 P27C Guard Helper / Checker Utility Integration

P27C implements the first UVM-side guard helper and checker utility layer.

Implementation locations:

```text
tb/uvm/helper/ai_accel_csr_access_helper.sv
tb/uvm/helper/ai_accel_event_driven_host_runtime_stress_helper.sv
```

P27C is a helper-only integration checkpoint.  It does not add RTL, a standalone UVM top, a standalone sim flow, a full-regression item, an SQ/CQ format change, a descriptor format change, a completion format change, or a new event bit.

P27C adds UVM-side constants for the frozen P27B CSR window:

```text
CSR_MEM_GUARD_VERSION / COMMAND / STATUS / ERROR_STATUS / CONTROL
CSR_MEM_GUARD_REJECT_STATUS / ERROR_DETAIL / ERROR_ADDR / ERROR_SIZE_BYTES
CSR_MEM_GUARD_ERROR_DOMAIN / CHECK_COUNT / ERROR_COUNT
CSR_MEM_GUARD_LAST_CHECK_ADDR / LAST_CHECK_SIZE_BYTES / LAST_CHECK_DOMAIN
CSR_MEM_GUARD_SQ_BASE / SQ_LIMIT
CSR_MEM_GUARD_CQ_BASE / CQ_LIMIT
CSR_MEM_GUARD_DESC_BASE / DESC_LIMIT
CSR_MEM_GUARD_SRC_BASE / SRC_LIMIT
CSR_MEM_GUARD_DST_BASE / DST_LIMIT
```

P27C adds helper-side guard structures:

```systemverilog
typedef struct {
    logic [31:0] control;
    logic [31:0] sq_base;
    logic [31:0] sq_limit;
    logic [31:0] cq_base;
    logic [31:0] cq_limit;
    logic [31:0] desc_base;
    logic [31:0] desc_limit;
    logic [31:0] src_base;
    logic [31:0] src_limit;
    logic [31:0] dst_base;
    logic [31:0] dst_limit;
} p27_guard_cfg_t;

typedef struct {
    logic [31:0] status;
    logic [31:0] error_status;
    logic [31:0] reject_status;
    logic [31:0] error_detail;
    logic [31:0] error_addr;
    logic [31:0] error_size_bytes;
    logic [31:0] error_domain;
    logic [31:0] check_count;
    logic [31:0] error_count;
    logic [31:0] last_check_addr;
    logic [31:0] last_check_size_bytes;
    logic [31:0] last_check_domain;
    logic [31:0] queue_status;
    logic [31:0] queue_error_status;
    logic [31:0] queue_error_detail;
    logic [31:0] event_pending;
} p27_guard_snapshot_t;
```

P27C adds reusable helper operations:

```text
host_rt_mem_guard_control_value
host_rt_mem_guard_span_limit
host_rt_mem_guard_range_valid
host_rt_mem_guard_region_config_valid
host_rt_mem_guard_domain_name
host_rt_mem_guard_detail_name
host_rt_mem_guard_default_cfg_from_queue
host_rt_mem_guard_program_regions
host_rt_mem_guard_disable
host_rt_mem_guard_clear_all
host_rt_mem_guard_capture_snapshot
host_rt_mem_guard_log_snapshot
host_rt_mem_guard_check_clean
host_rt_mem_guard_expect_error
host_rt_mem_guard_clear_for_reuse
```

The intended P27D/P27E/P27F usage is:

```text
program legal guard regions while guard is disabled
enable selected domain checks and strict reject policy
submit one intentionally illegal command
wait for QUEUE_ERROR_EVENT or queue error status
capture guard / queue / event diagnostics
check expected guard domain and detail code
clear guard / queue / event sticky state
reuse the P26 lifecycle helper to run a known-good recovery command
```

P27C closure criteria:

```text
P27 CSR constants are available to UVM helper code
P27 guard region programming helper is available
P27 guard snapshot and log helper is available
P27 pure range-check utility is available for test-side expected checks
P27 expected-error checker validates guard error, domain, detail, and queue MEMORY_GUARD_ERROR summary
P27 guard cleanup helper composes with P26 lifecycle cleanup
No standalone test or regression item is added at P27C
```

### 14.3 P27D SQ / Descriptor Range Validation Smoke

Purpose:

```text
validate legal SQ + descriptor ranges are accepted
validate SQ base/span out-of-range rejects before SQ fetch
validate descriptor base/count/stride out-of-range rejects before P17 launch
confirm no unsafe descriptor AXI read happens for rejected command
recover through P26 cleanup and run a known-good command
```

Suggested test name:

```text
ai_accel_subsys_csr_mem_guard_sq_desc_smoke_test
```

Expected PASS markers:

```text
[P27D_GUARD/VALID_BASELINE_PASS]
[P27D_GUARD/SQ_RANGE_REJECT_PASS]
[P27D_GUARD/DESC_RANGE_REJECT_PASS]
[P27D_GUARD/RECOVERY_PASS]
[P27D_GUARD/PASS]
```

P27D implementation checkpoint:

```text
RTL files updated:
  rtl/csr/ai_accel_csr_regs.sv
  rtl/top/ai_accel_subsys_csr_top.sv
  rtl/sequencer/ai_accel_queue_fetch_controller.sv

UVM files updated:
  tb/uvm/pkg/ai_accel_subsys_uvm_pkg.sv
  tb/uvm/test/ai_accel_subsys_csr_mem_guard_sq_desc_range_smoke_test.sv

Guard coverage:
  valid SQ/CQ/DESC range baseline command
  SQ entry range reject before SQ AXI read
  descriptor table range reject before P17 descriptor-fetch launch
  P26 lifecycle cleanup and known-good recovery command

Regression integration: deferred to P27G
Full regression count remains 138 until P27G
```

### 14.4 P27E DMA Source / Destination Range Validation Smoke

Purpose:

```text
validate A source out-of-range reject
validate B source out-of-range reject
validate source range crossing boundary reject
validate DMA store destination out-of-range reject
validate valid command still completes after cleanup
```

Suggested test name:

```text
ai_accel_subsys_csr_mem_guard_dma_range_smoke_test
```

Expected PASS markers:

```text
[P27E_GUARD/SRC_RANGE_REJECT_PASS]
[P27E_GUARD/DST_RANGE_REJECT_PASS]
[P27E_GUARD/RECOVERY_PASS]
[P27E_GUARD/PASS]
```

P27E implementation checkpoint:

```text
Test file: tb/uvm/test/ai_accel_subsys_csr_mem_guard_dma_range_smoke_test.sv
Package include: ai_accel_subsys_uvm_pkg.sv P27 memory access guard test block
RTL checkpoint: wrapper-level descriptor-payload SRC/DST guard before P16/P15 launch
Regression integration: deferred to P27G
Full regression count remains 138 until P27G
```

### 14.5 P27F CQ / Completion Writeback Guard + Lifecycle Recovery Smoke

Purpose:

```text
validate CQ base/span out-of-range detection
validate unsafe completion writeback is not issued when CQ slot is invalid
observe queue error / event path when no valid CQ record can be written
recover through P26 error-discard cleanup
submit known-good command with valid CQ range
confirm normal CQ completion and final clean idle
```

Suggested test name:

```text
ai_accel_subsys_csr_mem_guard_cq_recovery_smoke_test
```

Expected PASS markers:

```text
[P27F_GUARD/CQ_RANGE_REJECT_PASS]
[P27F_GUARD/NO_CQ_WRITE_PASS]
[P27F_GUARD/RECOVERY_PASS]
[P27F_GUARD/PASS]
```

### 14.6 P27G Full Regression Integration

P27G should add a small representative subset to the full regression.

Recommended full-regression items:

```text
csr_mem_guard_sq_desc_case102
csr_mem_guard_dma_range_case102
csr_mem_guard_cq_recovery_case102
```

Expected full-regression count if three items are added:

```text
Before P27G : 138
After P27G  : 141
```

### 14.7 P27H Documentation Closure

P27H should update:

```text
README.md
axi_lite_csr_control_plane_spec.md
memory_access_guard_prototype_spec.md
uvm_regression.list
run_full_uvm_regression.tcl
```

The CSR map remains canonical only in `axi_lite_csr_control_plane_spec.md`.

---


## 15. P27B CSR Policy / Range Register Map Freeze

P27B freezes the first software-visible memory guard CSR policy.

The decision is:

```text
P27 gets a dedicated memory guard CSR window
P27 guard checking is disabled by reset to preserve existing regression behavior
strict guard rejection is opt-in through CSR_MEM_GUARD_CONTROL
all guard region limits use half-open [base, limit) semantics
P27 adds one queue-level error summary bit for memory guard failures
P27 reuses the existing P22 QUEUE_ERROR_EVENT and does not allocate a new event bit
SQ / CQ / descriptor / source / destination region registers are canonical only in the CSR spec
```

Frozen P27B CSR window:

```text
P27 memory guard CSR window : 0x640 - 0x6BC
```

Canonical register map, register bit fields, access types, reset values, and queue-error integration are recorded in:

```text
docs/axi_lite_csr_control_plane_spec.md
```

### 15.1 Frozen Guard Regions

P27B freezes five first-class guard domains:

```text
SQ command memory region
CQ completion memory region
descriptor memory region
source memory region
destination memory region
```

Each region is programmed with a base address and an exclusive limit address.

```text
valid access if:
  addr >= region_base
  addr + size_bytes <= region_limit
  addr + size_bytes does not overflow
```

A zero-sized or inverted region is invalid when the corresponding domain check is enabled.

### 15.2 Guard Enable Reset Policy

P27B freezes a backward-compatible reset policy:

```text
CSR_MEM_GUARD_CONTROL reset = 0x0000_0000
```

This means:

```text
memory guard disabled after reset
strict reject disabled after reset
all domain checks disabled after reset
existing 138/138 regression behavior is preserved until P27 tests explicitly enable guard checking
```

P27 validation tests are expected to program legal guard regions and enable only the domains they are checking.

### 15.3 Queue and Event Error Mapping

P27B freezes this queue-level mapping:

```text
CSR_QUEUE_ERROR_STATUS[9] = MEMORY_GUARD_ERROR
```

When a guard failure is detected in the queue path:

```text
CSR_MEM_GUARD_ERROR_STATUS records the guard-specific reason
CSR_MEM_GUARD_ERROR_DETAIL records domain / detail / index / state information
CSR_MEM_GUARD_ERROR_ADDR records the offending address
CSR_QUEUE_ERROR_STATUS[9] is set
CSR_QUEUE_ERROR_DETAIL[7:0] may use a P27 DETAIL_MEM_GUARD_* code
P22 QUEUE_ERROR_EVENT wakes the host
```

P27B does not allocate a new P22 event bit.  The existing `QUEUE_ERROR_EVENT` remains the notification mechanism.

### 15.4 CQ Error Record Policy

P27B freezes a safe-CQ-first policy:

```text
If the failing command has a valid CQ slot inside the enabled CQ guard range,
  hardware may write a CQ error completion record.

If the CQ slot itself is invalid or unsafe,
  hardware must not issue the completion writeback,
  CSR_MEM_GUARD_ERROR_STATUS.UNSAFE_CQ_WRITE_SUPPRESSED records the suppression,
  queue CSR error/detail and P22 QUEUE_ERROR_EVENT become authoritative.
```

This preserves P18 completion-record authority when a safe CQ slot exists while preventing unsafe completion writes when the completion target is the failing object.

### 15.5 Configuration Write Policy

P27B freezes region programming as an idle-only configuration operation.

```text
Region base/limit writes should be performed while queue_busy == 0.
Region configuration writes while queue_busy is high are rejected or ignored with guard reject sticky status.
```

The guard CSR window is a control-plane configuration and diagnostic block.  It is not a DMA engine and does not launch memory traffic by itself.

### 15.6 P27B Closure Criteria

P27B is complete when:

```text
P27 memory guard CSR window is allocated in the canonical CSR spec
region base/limit registers are frozen for SQ/CQ/descriptor/source/destination domains
control / status / error / reject / diagnostic bit definitions are frozen
guard enable reset policy preserves existing regression behavior
queue error mapping through CSR_QUEUE_ERROR_STATUS[9] is frozen
P22 event policy reuses QUEUE_ERROR_EVENT with no new event bit
CQ-safe versus CQ-suppressed error reporting policy is documented
P27A prototype spec records P27B as PASS
no RTL / Tcl / regression-list changes are required for P27B
```

P27B does not change the regression count.

Current expected status after P27B:

```text
P27A: Memory access guard prototype spec PASS
P27B: Memory guard CSR policy / range register map freeze PASS
Full regression remains:
  TOTAL : 138
  PASS  : 138
  FAIL  : 0
```

---

## 16. P27A/P27B Closure Criteria

P27A is complete when:

```text
memory guard purpose and scope are documented
host-visible address domains are defined
range / alignment / overflow validation policy is documented
guard check points are identified
safe reject / no unsafe access behavior is defined
relationship to P19 queue, P22 event, P24 timeout, and P26 lifecycle is documented
P27B CSR policy freeze is documented and canonical CSR fields are allocated only in the CSR spec
P27D SQ / descriptor range validation is implemented and passing
P27E DMA source / destination range validation smoke is implemented / run pending
P27F validation direction and PASS markers are documented
no RTL / CSR / Tcl / regression-list changes are required for P27A
```

P27A/P27B do not change the regression count.

Current expected status after P27B:

```text
P27A: Memory access guard prototype spec PASS
P27B: Memory guard CSR policy / range register map freeze PASS
Full regression remains:
  TOTAL : 138
  PASS  : 138
  FAIL  : 0
```

---

## 17. Interview Notes

P27 is useful because it shows the accelerator has moved beyond datapath correctness into host-facing device robustness.

Concise explanation:

```text
After validating queue lifecycle and recovery, I added a memory access guard layer so host-provided SQ, descriptor, DMA, and completion addresses are checked before hardware launches lower-level memory operations. Invalid commands are reported deterministically through the existing queue error, event, and lifecycle recovery paths instead of causing uncontrolled memory traffic.
```

Key points:

```text
The guard checks ranges before unsafe AXI traffic is issued.
The CQ record remains authoritative when a valid CQ slot exists.
If CQ itself is invalid, queue CSR error/detail and QUEUE_ERROR_EVENT are authoritative.
P26 lifecycle cleanup is reused for recovery.
No multi-outstanding or out-of-order execution is introduced.
BRAM / GEMM datapath semantics remain unchanged.
```
