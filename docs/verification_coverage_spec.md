# AI Accelerator Subsystem Verification Coverage Spec

## 1. Purpose

This document is the canonical coverage specification for the AI Accelerator Subsystem project.

It defines:

```text
requirement-driven functional coverage architecture
functional covergroup and planned-bin policy
functional coverage collection / merge / report flow
functional coverage closure results
RTL code coverage scope and planned metrics
code coverage gap classification and exclusion policy
coverage artifact layout and version-control policy
coverage closure criteria
```

This document does not define CSR addresses, register bit fields, access types, or reset values.  Those remain canonical in `axi_lite_csr_control_plane_spec.md`.

The regression item inventory and per-test run parameters remain canonical in `uvm_regression.list`.

The README contains only the high-level project status and validated coverage scope.

---

## 2. Coverage Status

```text
Simulator:
  QuestaSim-64 10.7c

Functional coverage:
  Status                     : CLOSED
  Regression                 : 150 / 150 PASS
  Total covergroup coverage  : 100.00%
  Covergroup types           : 7 / 7 covered
  Missing planned bins       : 0
  UCDB merge / report        : PASS
  vcover errors / warnings   : 0 / 0

RTL code coverage:
  Status                     : NOT STARTED
  Next milestone             : CODE-COV
```

The functional coverage claim is intentionally precise:

> The project achieved 100% planned functional coverage across the defined and validated RC-COV scope.

This result does not claim exhaustive coverage of every theoretical input, parameter combination, unreachable state, or RTL implementation path.

---

## 3. Coverage Terminology

### 3.1 Requirement-driven functional coverage

Functional coverage answers whether the validated architectural behaviors and representative configuration classes were observed.

The model is implemented in:

```text
tb/uvm/cov/ai_accel_subsys_functional_coverage.sv
```

Functional coverage is not a substitute for scoreboard checking.  A coverage hit proves observation, not correctness.  Correctness remains established by the existing tests, scoreboards, checkers, memory comparisons, CSR checks, and recovery checks.

### 3.2 RTL code coverage

Code coverage answers whether executable RTL implementation structures were exercised.

The planned CODE-COV campaign will inspect:

```text
statement coverage
branch coverage
condition coverage
expression coverage
toggle coverage
FSM state / transition coverage
```

Code coverage is not a substitute for requirement-driven functional coverage.  High code coverage can occur without testing the intended architectural requirement.

### 3.3 Closure

Coverage closure means every planned obligation is dispositioned.

A disposition is one of:

```text
covered by the existing regression
covered by a targeted test
approved as parameter-disabled
approved as unsupported / outside validated scope
approved as defensive or unreachable
approved as testbench / simulation-only and outside RTL scope
```

A raw percentage alone is not sufficient for closure.

---

## 4. Functional Coverage Architecture

The RC-COV implementation uses a hybrid architecture with three information sources.

### 4.1 Control-monitor transaction source

The existing subsystem control monitor publishes `ai_accel_subsys_seq_item` transactions through its analysis port.

The functional coverage subscriber uses these transactions for:

```text
START and DONE events
test-kind classes
CASE_ID-derived profile classes
M / N / K dimension classes
job-profile classes
latency classes
```

This source is applicable to the legacy sideband-controlled top and to direct control activity visible in the CSR top.

### 4.2 Passive AXI-Lite CSR observation source

The CSR top provides the existing `axi_lite_if` virtual interface to the coverage component.

The passive observer:

```text
does not drive AXI-Lite signals
reconstructs independent AW and W channel handshakes
reconstructs AR and R channel handshakes
decodes writes only after address and data are both available
decodes reads only after the matching read response is available
samples queue, event, moderation, guard, and telemetry behavior
```

The observer uses the existing CSR bus and does not add a standalone interface, top, monitor agent, or simulation flow.

### 4.3 Static build-configuration source

Each UVM top supplies static configuration through `uvm_config_db`.

Covered static attributes include:

```text
legacy versus CSR top
GEMM_MAC_LANES
B-cache enable
packed B-cache preload
A-row cache enable
packed A-row preload
K / N / M tiling enables
C RMW enable
DMA and core clock periods
```

### 4.4 Top behavior

```text
Legacy top:
  control-monitor coverage enabled
  static-configuration coverage enabled
  CSR coverage quietly disabled because no CSR virtual interface exists

CSR top:
  control-monitor coverage enabled
  static-configuration coverage enabled
  passive AXI-Lite CSR coverage enabled
```

---

## 5. Functional Coverage Model

The final RC-COV model contains seven covergroup domains.

### 5.1 `cg_ctrl_event`

Purpose:

```text
observe START and DONE activity
classify validated job kinds
classify validated case/profile groups
cover planned START / DONE by job-kind combinations
```

Planned classes include fixed baseline, variable dimension, configurable jobs, C RMW recipes, cache-scaled jobs, and K/N/M tiling representatives.

### 5.2 `cg_job_profile`

Purpose:

```text
cover validated M / N / K dimension classes
cover milestone-level job profile classes
cover short / medium / long / very-long latency classes
```

The model uses explicit profile classes rather than an unrestricted M x N x K Cartesian cross.

### 5.3 `cg_static_cfg`

Purpose:

```text
cover validated UVM tops
cover validated MAC lane counts
cover validated cache / packed preload combinations
cover validated K / N / M tiling combinations
cover validated C RMW combinations
cover nominal and CDC clock-ratio classes
cover explicit validated top/lane, lane/cache, and tiling/C-RMW profiles
```

The model does not claim unsupported or unvalidated parameter combinations.

### 5.4 `cg_queue_runtime`

Purpose:

```text
cover planned queue commands
cover idle / busy / stalled / error states
cover started / drained / completed / stopped / error / reject outcomes
cover validated SQ occupancy classes
cover empty / partial / full CQ occupancy classes
```

Transient CQ-full stall behavior may be sampled from the corresponding event semantic so a short status interval is not lost.

### 5.5 `cg_event_moderation`

Purpose:

```text
cover all planned event causes
cover immediate, threshold, and threshold-plus-timer policy
cover retrigger disabled / enabled
cover immediate, threshold, timer, and urgent-bypass release profiles
cover host W1C ack / re-arm action
```

Moderation policy and retrigger behavior are covered separately.

### 5.6 `cg_memory_guard`

Purpose:

```text
cover guard disabled and strict modes
cover clean, SQ, CQ, descriptor, source, and destination domains
cover clean and validated range-error detail classes
cover explicit legal domain / error pairs
```

The model covers the validated P27 range-guard contract instead of crossing every diagnostic code with every domain.

### 5.7 `cg_telemetry`

Purpose:

```text
cover telemetry clear command observation
cover reads of all planned telemetry counters
cover non-zero activity for all planned telemetry counters
```

The final closure includes real non-zero observations for:

```text
timer release telemetry
STOP_QUEUE request telemetry
CQ-full stall and recovery telemetry
timeout and guard error telemetry
busy and stalled cycle telemetry
```

---

## 6. Planned-Bin Policy

The project uses requirement-driven planned bins.

### 6.1 Included obligations

A bin is a closure obligation when it represents:

```text
an architectural requirement
a validated milestone behavior
a supported representative configuration
an expected runtime state or terminal outcome
a software-visible CSR behavior
a meaningful recovery or error path
```

### 6.2 Excluded obligations

The model does not create closure obligations for:

```text
unbounded theoretical Cartesian combinations
unsupported parameter combinations
parameter combinations not present in the validated regression scope
semantically impossible combinations
values used only as invalid sentinels
test orchestration labels that are not observable transaction semantics
```

### 6.3 Gap treatment

A meaningful reachable gap is not ignored only to increase the percentage.

The RC-COV process is:

```text
1. confirm the coverage decode and sampling semantics
2. confirm the requirement is in the validated scope
3. reuse an existing test when possible
4. add the smallest targeted behavior needed
5. rerun the full 150-item regression
6. close only after the merged report has no missing planned bins
```

---

## 7. Functional Coverage Collection and Merge Flow

### 7.1 Single-test collection

`sim/run_uvm.tcl` supports optional coverage collection.

A coverage-enabled run:

```text
enables simulator coverage
keeps the simulator alive after UVM report_phase
saves one UCDB
reports a deterministic coverage-save PASS / FAIL result
```

### 7.2 Full-regression collection

`sim/run_full_uvm_regression.tcl` supports RC-COV collection through:

```text
RC_COV_ENABLE
RC_COV_ROOT_DIR
RC_COV_CLEAN
```

The flow:

```text
runs the existing 150-item regression
saves one compact UCDB per passing item
requires both a passing UVM log and a non-empty UCDB
records per-item coverage paths in a manifest
merges only passing test UCDBs
generates summary and detailed text reports
fails RC-COV if collection, merge, or report generation fails
```

### 7.3 Default artifact paths

```text
sim/coverage/rc_cov/per_test/
sim/coverage/rc_cov/rc_cov_merged.ucdb
sim/coverage/rc_cov/rc_cov_manifest.tsv
sim/coverage/rc_cov/rc_cov_summary.txt
sim/coverage/rc_cov/rc_cov_details.txt
```

Manual targeted runs may use:

```text
sim/coverage/rc_cov/manual/
```

---

## 8. Functional Coverage Closure History

### 8.1 RC-COV-A / RC-COV-B

```text
functional coverage architecture defined
hybrid control-monitor / passive-CSR model implemented
coverage component integrated into the existing UVM environment
legacy and CSR tops configured without adding a new top or flow
```

### 8.2 RC-COV-C1

```text
single-test UCDB save validated
150-test UCDB collection / merge / report validated
initial total covergroup coverage: 70.64%
```

The initial report exposed over-broad Cartesian crosses and several decode / classification mismatches.

### 8.3 RC-COV-C2

The coverage model was refined to the validated planned scope.

Key refinements:

```text
job test kinds separated from test orchestration scenarios
M / N / K Cartesian cross replaced by milestone profile classes
static configuration crosses restricted to validated profiles
queue stalled semantic sampled from validated CQ-full behavior
event policy separated from retrigger behavior
event and moderation coverage converted to explicit planned classes
memory guard coverage converted to legal domain / range-error pairs
telemetry clear / read / non-zero behavior separated
```

Result:

```text
total covergroup coverage: 99.49%
remaining planned gaps:
  telemetry timer_release non-zero
  telemetry stop_request non-zero
```

### 8.4 RC-COV-C3

No new test class or regression item was added.

Existing P29 tests were extended in place:

```text
ai_accel_subsys_csr_basic_telemetry_counter_smoke_test
  accepted a live STOP_QUEUE request
  observed STOP_QUEUE_REQUEST_COUNT > 0
  verified post-clear return to zero

ai_accel_subsys_csr_interrupt_efficiency_telemetry_smoke_test
  retained threshold-release validation
  added a sparse threshold-plus-timer phase
  observed TIMER_RELEASE_COUNT > 0
  verified THRESHOLD_RELEASE_COUNT == 0 in the timer phase
```

Final result:

```text
TOTAL : 150
PASS  : 150
FAIL  : 0

TOTAL COVERGROUP COVERAGE : 100.00%
COVERGROUP TYPES          : 7
MISSING PLANNED BINS      : 0
ERRORS                    : 0
WARNINGS                  : 0
```

### 8.5 RC-COV-D

```text
README high-level status updated
verification_coverage_spec.md established as the canonical coverage document
uvm_regression.list updated without changing the 150-item inventory
final summary and detailed reports retained under sim/coverage/rc_cov/
```

---

## 9. Final Functional Coverage Result

```text
cg_ctrl_event       : 100.00%
cg_job_profile      : 100.00%
cg_static_cfg       : 100.00%
cg_queue_runtime    : 100.00%
cg_event_moderation : 100.00%
cg_memory_guard     : 100.00%
cg_telemetry        : 100.00%
```

Final tracked evidence:

```text
sim/coverage/rc_cov/rc_cov_summary.txt
sim/coverage/rc_cov/rc_cov_details.txt
```

Closure statement:

> RC-COV is closed at 100% planned functional coverage for the defined and validated scope, with 150/150 regression items passing and no missing planned bins.

---

## 10. RTL Code Coverage Plan

CODE-COV is the final technical milestone for this project.

### 10.1 Objective

The objective is to determine how completely the existing 150-item regression exercises the implemented RTL structure, then disposition each meaningful uncovered region.

The objective is not to force every metric to 100% without regard to architecture.

### 10.2 Initial instrumented scope

The initial baseline will target synthesizable RTL reachable from:

```text
ai_accel_subsys_uvm_top
ai_accel_subsys_csr_uvm_top
```

The intended design scope includes the subsystem datapath, control-plane wrapper, sequencers, queue/event/guard/telemetry logic, frontend engines, DMA engines, GEMM datapath, scratchpad adapters/muxes, CDC structures, and the stable dual-port BRAM model.

The initial code coverage scope excludes:

```text
tb/uvm/
UVM classes
scoreboards and checkers
testbench memory responders
software reference models
test orchestration code
simulator libraries
```

Any additional exclusion will be documented after the baseline report is reviewed.

### 10.3 Planned metrics

```text
statement coverage
branch coverage
condition coverage
expression coverage
toggle coverage
FSM state coverage
FSM transition coverage
```

The exact Questa instrumentation switches and report commands will be frozen during CODE-COV-A.

### 10.4 Collection strategy

The first baseline will reuse the existing 150-item regression.

Planned artifact layout:

```text
sim/coverage/code_cov/per_test/
sim/coverage/code_cov/code_cov_merged.ucdb
sim/coverage/code_cov/code_cov_manifest.tsv
sim/coverage/code_cov/code_cov_summary.txt
sim/coverage/code_cov/code_cov_details.txt
```

The final flow should mirror RC-COV behavior:

```text
optional enable
clean output directory
one database per passing regression item
merge only passing databases
human-readable summary and detailed reports
deterministic final PASS / FAIL status
```

### 10.5 Gap classification

Each uncovered code region will be classified as one of:

```text
A. reachable and architecturally meaningful
   -> add or extend the smallest targeted test

B. reachable only in a supported configuration absent from the regression
   -> decide whether the validated scope should expand

C. parameter-disabled in the validated configuration matrix
   -> document exclusion rationale

D. unsupported configuration or non-goal
   -> document exclusion rationale

E. defensive / illegal-state / unreachable code
   -> prove or explain unreachability and document exclusion

F. testbench, simulation-only, debug-only, or tool-generated code
   -> exclude from RTL closure scope
```

### 10.6 Exclusion policy

An exclusion is acceptable only when:

```text
the source location is identified
the reason is specific
the reason is reviewable
the exclusion does not hide a reachable architectural requirement
the rationale is recorded in this document
```

Blanket exclusions used only to raise the reported percentage are not acceptable.

### 10.7 CODE-COV closure criteria

CODE-COV may close when:

```text
the full regression remains passing
the selected RTL metrics are collected and merged reproducibly
all meaningful uncovered regions are classified
reachable important gaps are covered by targeted behavior
parameter-disabled / unsupported / defensive gaps have written rationale
final summary and detailed reports are generated
approved exclusions are documented
README and uvm_regression.list are updated
```

A final code coverage percentage below 100% is acceptable when all remaining gaps have valid documented dispositions.

### 10.8 CODE-COV milestone plan

```text
CODE-COV-A:
  instrumentation scope and Tcl flow

CODE-COV-B:
  150-test baseline collection and merged report

CODE-COV-C:
  uncovered RTL classification and review

CODE-COV-D:
  minimal targeted tests and approved exclusions

CODE-COV-E:
  final regression, final reports, and documentation closure
```

---

## 11. RTL Code Coverage Results

Current status:

```text
NOT STARTED
```

This section will be updated after CODE-COV-B with:

```text
baseline metric results
uncovered module / line / branch inventory
gap classifications
targeted test changes
approved exclusions
final metric results
```

---

## 12. Coverage Artifact and Version-Control Policy

The project keeps final human-readable reports and ignores generated binary or intermediate databases.

Tracked:

```text
sim/coverage/rc_cov/rc_cov_summary.txt
sim/coverage/rc_cov/rc_cov_details.txt

sim/coverage/code_cov/code_cov_summary.txt
sim/coverage/code_cov/code_cov_details.txt
```

Ignored:

```text
sim/coverage/*_cov/manual/
sim/coverage/*_cov/per_test/
sim/coverage/*_cov/*_merged.ucdb
sim/coverage/*_cov/*_manifest.tsv
other generated coverage databases and transient artifacts
```

The summary and detailed text reports are simulator-generated evidence and should not be hand edited.

---

## 13. Reproduction Commands

### 13.1 Functional coverage

From `sim/`:

```tcl
set DO_COMPILE 1
set RC_COV_ENABLE 1
set RC_COV_CLEAN 1
set STOP_ON_FIRST_FAIL 0

do run_full_uvm_regression.tcl
```

Expected result:

```text
TOTAL : 150
PASS  : 150
FAIL  : 0
RC-COV: PASS

TOTAL COVERGROUP COVERAGE: 100.00%
COVERGROUP TYPES: 7
Errors: 0, Warnings: 0
```

### 13.2 RTL code coverage

The final CODE-COV commands are intentionally deferred until CODE-COV-A freezes the compile, elaboration, simulation, merge, and report switches.

---

## 14. Final Verification Coverage Status

```text
RC-COV-A   Functional coverage architecture        PASS
RC-COV-B   Functional coverage implementation      PASS
RC-COV-C1  UCDB collection / merge / report        PASS
RC-COV-C2  Planned-bin refinement                   PASS
RC-COV-C3  Targeted telemetry closure               PASS
RC-COV-D   Documentation closure                    PASS

Planned functional coverage:
  100.00%
  7 / 7 covergroup types covered
  0 missing planned bins
  150 / 150 regression items PASS

CODE-COV:
  NEXT
```
