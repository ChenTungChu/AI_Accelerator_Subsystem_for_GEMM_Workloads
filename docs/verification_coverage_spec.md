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
  Overall campaign status    : IN PROGRESS
  Closed scope               : CODE-COV-C1.1
  Primary closure target     : rtl/csr/ai_accel_csr_regs.sv
  Regression                 : 150 / 150 PASS
  UCDB merge / report        : PASS
  Raw statement coverage     : 1172 / 1183 = 99.07%
  Remaining raw misses       : 11
  D3 waiver records          : 11 / 11 documented
  Reachable adjusted coverage: 1172 / 1172 = 100.00%
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

### 11.1 CODE-COV-C1.1 scope

CODE-COV-C1.1 closes statement coverage for the integrated CSR register block:

```text
rtl/csr/ai_accel_csr_regs.sv
```

This scope was selected because the block concentrates the software-visible AXI-Lite decode, command admission, sticky status, event, memory-guard, telemetry, and W1C behavior.

The broader CODE-COV campaign remains in progress for the rest of the synthesizable RTL scope.  The result in this section must not be interpreted as 99.07% statement coverage for every RTL file.

### 11.2 Full-regression closure result

Final full-regression result:

```text
TOTAL : 150
PASS  : 150
FAIL  : 0
CODE-COV: PASS

CODE-COV UCDB MERGE AND REPORT: PASS
```

Final merged result for `rtl/csr/ai_accel_csr_regs.sv`:

```text
Statements              1172 / 1183   99.07%   11 misses
Branches                 922 / 979    94.17%   57 misses
FEC Condition Terms       68 / 95     71.57%   27 misses
FEC Expression Terms     140 / 168    83.33%   28 misses
Toggle Bins             3360 / 19154  17.54%
```

The filtered all-file CODE-COV report result is:

```text
Total Coverage By File: 70.44%
```

The final tracked evidence is:

```text
sim/coverage/code_cov/code_cov_summary.txt
sim/coverage/code_cov/code_cov_details.txt
```

### 11.3 Statement-closure history

The final CODE-COV-C1.1 statement progression was:

```text
C1.1-C baseline                  1148 / 1183   97.04%   35 misses
C1.1-D1 reachable decode/reject   +18 hits
C1.1-D2-A genuine error paths      +6 hits
C1.1-D final                    1172 / 1183   99.07%   11 misses
```

The `+24` statement delta is exactly:

```text
D1   : 18 / 18 retained in the full merged report
D2-A :  6 /  6 retained in the full merged report
```

No RTL change, new test class, new regression item, force, or internal-state injection was used to obtain the D1/D2-A closure.

### 11.4 D3 waiver / exclusion policy

The D3 record is a project review and sign-off record.

It does not modify the simulator database and does not change the raw Questa result:

```text
Raw simulator-reported statement coverage:
  1172 / 1183 = 99.07%

Documented current-revision exclusions:
  11 statements

Waiver-adjusted reachable statement coverage:
  1172 / (1183 - 11) = 1172 / 1172 = 100.00%
```

The `100.00%` value above is waiver-adjusted reachable coverage only.  It must not be reported as raw simulator coverage.

Formal Questa exclusions applied to the merged UCDB:

```text
NONE
```

Prohibited closure methods:

```text
forcing internal FSM state or internal error signals
injecting impossible internal ownership conflicts
changing RTL only to increase coverage
performing a zero-state W1C write only to hit a statement
claiming closure from functional markers without vcover -details evidence
```

### 11.5 C1.1-D3 waiver / exclusion record

| RTL line | Source construct | Classification | Current-revision rationale | Re-open condition |
|---:|---|---|---|---|
| 1305 | `is_power_of_two()` return | Static / elaboration-time | Called only by the fixed `STRB_WIDTH=4` parameter-sanity check. Questa constant folding leaves the function return as an uncovered source statement. An illegal parameter run that intentionally terminates in `$fatal` is not a meaningful runtime coverage obligation. | Re-open if the validated CSR width/strobe parameter matrix expands or the call becomes runtime-variable. |
| 1428 | `recipe_slot_descriptor_valid()` out-of-range return | Structural defensive guard | All current callers iterate with `0 <= slot_i < P16_RECIPE_QUEUE_DEPTH`; the out-of-range predicate cannot be true through a legal caller. | Re-open if a new caller can pass an unbounded slot index. |
| 1477 | `recipe_slot_read_data()` out-of-range return | Structural defensive guard | CSR read dispatch calls the helper only after `recipe_slot_addr_is_valid()` proves the slot index is in range. | Re-open if a direct caller bypasses address validation. |
| 2661 | `EVENT_SRC_RUNTIME_DOORBELL` classification | Current-scope tied-off source | Event ABI positions 8 and 9 are retained, but the current RTL ties `RUNTIME_DOORBELL_EVENT` and `RUNTIME_APPEND_CONSUMED_EVENT` raw producers low. P21 live queue service remains implemented independently of these optional notification sources. | Re-open when either runtime event producer is implemented. |
| 2669 | `EVENT_SRC_NONE` default | Structural default guard | `build_event_last_cause()` is called only for a non-zero valid event mask; `first_event_index()` therefore returns a valid allocated index instead of the empty-mask sentinel. | Re-open if last-cause construction is allowed for an empty or invalid mask. |
| 3772 | `JOB_ERR_SEQUENCE` sticky capture | Defensive ownership invariant | P15 admission and P14 manual-command ownership rules prevent legal software from creating the worker-busy / illegal-stage conflicts that assert `job_sequence_error`. | Re-open if concurrent ownership, runtime descriptor mutation, or a software-visible sequence-error path is added. |
| 3796 | `RECIPE_ERR_SLOT_JOB_REJECT` sticky capture | Reserved / unimplemented producer | The current recipe sequencer has no `job_reject` feedback input and no assignment that asserts `recipe_slot_job_reject`. The signal is only reset/deasserted. | Re-open if P15 reject feedback or an assertion producer is added. |
| 3800 | `RECIPE_ERR_SEQUENCE` sticky capture | Defensive ownership invariant | P16 owns the P15 worker while a recipe is active, and external `START_JOB` attempts are rejected before they can steal the worker during dispatch. | Re-open if recipe/P15 concurrent ownership policy changes. |
| 3804 | `RECIPE_ERR_SLOT_RANGE` sticky capture | Admission-masked defensive check | CSR `START_RECIPE` admission rejects an invalid selected range before generating `recipe_start_pulse`; the sequencer cannot receive an invalid range through the legal front door. | Re-open if front-door range validation is removed or runtime range mutation is allowed. |
| 3808 | `RECIPE_ERR_SLOT_DESCRIPTOR` sticky capture | Admission / snapshot defensive check | Selected descriptors are validated before `recipe_start_pulse` and copied into the accepted recipe snapshot. Later CSR writes do not corrupt the active snapshot. | Re-open if descriptor validation or snapshot immutability changes. |
| 4616 | `CSR_RECIPE_SLOT_REJECT_MASK` direct W1C | Semantic-dependency waiver | The statement is syntactically writable, but no legal current-revision path creates a genuine non-zero slot-reject mask. Writing W1C data while the mask is zero would be coverage gaming rather than functional validation. | Re-open when a genuine non-zero `recipe_slot_reject_mask_q` producer becomes architecturally reachable. |

### 11.6 D3 closure decision

```text
D3 candidates reviewed              : 11 / 11
Legal reachable coverage targets     :  0 / 11
Current-revision waiver records      : 11 / 11
Unresolved holds                     :  0
Unexpected full-merge statement miss :  0

RTL changes                          : NONE
New tests                            : NONE
Regression inventory                 : 150 unchanged
Force / internal-state injection     : NONE
Formal simulator exclusions applied  : NONE
```

Closure statement:

> CODE-COV-C1.1 is closed for `rtl/csr/ai_accel_csr_regs.sv` at 99.07% raw statement coverage.  The remaining 11 statements have reviewable current-revision dispositions, yielding 100.00% waiver-adjusted reachable statement coverage without changing the raw simulator result.

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

From `sim/`, use the Questa Transcript Tcl flow below.

Compile with RTL code-coverage instrumentation enabled:

```tcl
catch {quit -sim}

set CODE_COV_ENABLE 1
set CODE_COV_METRICS bcefst

do compile_uvm.tcl
```

Run the existing full regression without recompiling:

```tcl
set CODE_COV_ENABLE 1
set CODE_COV_METRICS bcefst
set DO_COMPILE 0
set STOP_ON_FIRST_FAIL 0

do run_full_uvm_regression.tcl
```

Expected result:

```text
TOTAL : 150
PASS  : 150
FAIL  : 0
CODE-COV: PASS

[REGRESSION] ALL TESTS PASSED
[REGRESSION] CODE-COV UCDB MERGE AND REPORT PASSED
```

Expected final artifacts:

```text
sim/coverage/code_cov/code_cov_merged.ucdb
sim/coverage/code_cov/code_cov_manifest.tsv
sim/coverage/code_cov/code_cov_summary.txt
sim/coverage/code_cov/code_cov_details.txt
```

The merged UCDB and manifest remain generated artifacts.  The summary and detailed text reports are the tracked human-readable evidence.

---

## 14. Final Verification Coverage Status

```text
RC-COV-A   Functional coverage architecture                 PASS
RC-COV-B   Functional coverage implementation               PASS
RC-COV-C1  UCDB collection / merge / report                 PASS
RC-COV-C2  Planned-bin refinement                            PASS
RC-COV-C3  Targeted telemetry closure                        PASS
RC-COV-D   Documentation closure                             PASS

CODE-COV-C1.1-B  CSR decode / reject closure                PASS
CODE-COV-C1.1-C  CSR sticky / W1C closure                   PASS
CODE-COV-C1.1-D1 Reachable decode / reject closure          PASS
CODE-COV-C1.1-D2 Genuine error-path closure                 PASS
CODE-COV-C1.1-D3 Reachability / exclusion record            PASS

Regression:
  150 / 150 PASS

Planned functional coverage:
  100.00%
  7 / 7 covergroup types covered
  0 missing planned bins

CSR register-block RTL statement coverage:
  Raw simulator result              : 1172 / 1183 = 99.07%
  Documented current-revision misses: 11
  Waiver-adjusted reachable result  : 1172 / 1172 = 100.00%
  Formal simulator exclusions       : NONE
  UCDB merge / report               : PASS

Broader RTL CODE-COV campaign:
  IN PROGRESS
```
