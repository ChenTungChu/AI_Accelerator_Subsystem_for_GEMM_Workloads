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
  Overall campaign status    : CLOSED — CODE-COV-C1.3
  Regression                 : 150 / 150 PASS
  UCDB merge / report        : PASS
  Authoritative RAW bcefst   : 74.83%
  EFFECTIVE audit bcefst     : 77.34%
  RAW statement              : 5096 / 5285 = 96.42%
  EFFECTIVE statement        : 5096 / 5111 = 99.70%
  New C1.3 exclusions        : 0
  Toggle exclusions          : 0
  Known open RTL/integration bugs at signoff: 0
```

The functional coverage claim is intentionally precise:

> The project achieved 100% planned functional coverage across the defined and validated RC-COV scope.

This result does not claim exhaustive coverage of every theoretical input, parameter combination, unreachable state, or RTL implementation path.

The code coverage claim is also intentionally split into RAW and EFFECTIVE views:

```text
RAW:
  authoritative simulator result from the canonical merged UCDB

EFFECTIVE:
  exclusion-aware audit view produced on a copy of the RAW UCDB
  using the frozen C1.2 approved exclusion ledger
```

The EFFECTIVE percentage does not replace the RAW result.  C1.3 introduced no new exclusions.

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

The completed CODE-COV campaign inspected:

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

The full regression inventory is canonical only in:

```text
sim/uvm_regression.list
```

`run_full_uvm_regression.tcl` parses that list.  PROJECT-FINAL-P1-B removed the former duplicate hard-coded 150-item inventory from the Tcl runner and requalified the resulting flow at 150/150 PASS with RC-COV merge/report PASS.

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

## 10. RTL Code Coverage Method and Closure Policy

CODE-COV-C1.3 is closed for the validated synthesizable RTL scope.  This section records the method and closure policy used by the campaign.

### 10.1 Objective

The objective was to determine how completely the existing 150-item regression exercises the implemented RTL structure, then disposition each meaningful uncovered region.

The objective was not to force every metric to 100% without regard to architecture.

### 10.2 Instrumented scope

The campaign instruments synthesizable RTL reachable from:

```text
ai_accel_subsys_uvm_top
ai_accel_subsys_csr_uvm_top
```

The design scope includes the subsystem datapath, control-plane wrapper, sequencers, queue/event/guard/telemetry logic, frontend engines, DMA engines, GEMM datapath, scratchpad adapters/muxes, CDC structures, and the stable dual-port BRAM model.

The code coverage scope excludes:

```text
tb/uvm/
UVM classes
scoreboards and checkers
testbench memory responders
software reference models
test orchestration code
simulator libraries
```

### 10.3 Collected metrics

```text
statement coverage
branch coverage
condition coverage
expression coverage
toggle coverage
FSM state coverage
FSM transition coverage
```

The frozen metric set is `bcefst`.

### 10.4 Collection strategy

The campaign reuses the canonical 150-item regression.

Artifact layout:

```text
sim/coverage/code_cov/per_test/
sim/coverage/code_cov/code_cov_merged.ucdb
sim/coverage/code_cov/code_cov_manifest.tsv
sim/coverage/code_cov/code_cov_summary.txt
sim/coverage/code_cov/code_cov_details.txt
```

The flow mirrors RC-COV behavior:

```text
optional enable
clean output directory
one database per passing regression item
merge only passing databases
human-readable summary and detailed reports
deterministic final PASS / FAIL status
```

### 10.5 Gap classification

Each uncovered code region is classified as one of:

```text
A. reachable and architecturally meaningful
   -> add or extend the smallest targeted legal stimulus

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
the rationale is recorded in the frozen audit artifacts
```

Blanket exclusions used only to raise the reported percentage are not acceptable.

The canonical RAW UCDB is never modified by the exclusion flow.  Approved exclusions are applied only to a copied UCDB to produce an EFFECTIVE audit view.

### 10.7 Closure criteria

CODE-COV closes when:

```text
the full regression remains passing
the selected RTL metrics are collected and merged reproducibly
all meaningful uncovered regions are classified
reachable important gaps are covered by legal targeted behavior
parameter-disabled / unsupported / defensive gaps have written rationale
final summary and detailed reports are generated
approved exclusions are frozen and reproducible
RAW and EFFECTIVE reporting are clearly distinguished
README and coverage documentation are consistent with the final result
```

A final RAW code coverage percentage below 100% is acceptable when all remaining gaps have valid documented dispositions.

### 10.8 Final major phases

```text
CODE-COV-C1.1:
  CSR register-block statement reachability / waiver checkpoint
  PASS

CODE-COV-C1.2:
  full-RTL RAW vs EFFECTIVE reconciliation
  frozen exclusion ledger / final baseline signoff
  PASS

CODE-COV-C1.3:
  post-C1.2 legal constructive improvement
  fresh RAW delta reconciliation
  frozen-exclusion replay / evidence freeze
  PASS
```

---

## 11. RTL Code Coverage Results

### 11.1 Final authoritative RAW result

Final canonical regression and merge result:

```text
TOTAL : 150
PASS  : 150
FAIL  : 0
CODE-COV: PASS
CODE-COV UCDB MERGE AND REPORT: PASS
```

Final full-RTL RAW result:

```text
Total RAW bcefst: 74.83%

Metric                  Active      Hits    Misses
---------------------------------------------------
Statements                5285      5096       189
Branches                  2866      2645       221
FEC Condition Terms        533       373       160
FEC Expression Terms       835       655       180
FSM States                 121       121         0
FSM Transitions            279       179       100
Toggle Bins              96910     28887     68023
```

The RAW merged UCDB is the authoritative simulator result.

Final frozen RAW UCDB SHA256:

```text
ff2918d43a714d0ecd70ac8b1001c84cdfc3188f0ed4f825f3489343e0a1e079
```

### 11.2 Final EFFECTIVE audit result

The final EFFECTIVE audit applies the frozen C1.2 approved exclusion ledger to a copy of the final C1.3 RAW UCDB.  It does not edit the canonical RAW database.

```text
Total EFFECTIVE bcefst: 77.34%

Metric                  Active      Hits / Effective-covered    Misses
---------------------------------------------------------------------
Statements                5111      5096                          15
Branches                  2862      2645                         217
FEC Condition Terms        533       396                         137
FEC Expression Terms       835       701                         134
FSM States                 121       121                           0
FSM Transitions            264       179                          85
Toggle Bins              96910     28887                       68023
```

Additional aggregate audit views:

```text
RAW non-toggle multimetric       : 80.69%
EFFECTIVE non-toggle multimetric : 83.64%
RAW statement                    : 96.42%
EFFECTIVE statement              : 99.70%
Toggle RAW                       : 29.81%
Toggle EFFECTIVE                 : 29.81%
```

Condition and expression effective-covered counts reflect Questa exact-FEC exclusion accounting.  They are not additional simulation hits.

Final frozen EFFECTIVE UCDB SHA256:

```text
2cc693444c94b2ee7d9d2c70237e797a2fd371e5c90bbe74595de76e05997dbf
```

### 11.3 Frozen exclusion accounting

C1.3 reuses the C1.2 approved exclusion ledger exactly.

```text
Statement physical exclusions : 174
Safe branch exclusions        :   4
Condition exact FEC rows       :  23
Expression exact FEC rows      :  46
FSM transition exclusions      :  15
Toggle exclusions              :   0

New exclusions in C1.3        :   0
Statement covered-hit loss     :   0
Canonical RAW immutability     : PASS
```

Frozen control artifacts:

```text
sim/g8_c_statement_exclusions.tcl
sim/g8_c2a_multimetric_exclusions.tcl
sim/g8_c2b_expression_exclusions.tcl
sim/run_c1_3_d_effective_replay.tcl
```

The C1.3-D replay manifest verifies that the canonical RAW SHA256 is unchanged before and after the EFFECTIVE replay.

### 11.4 C1.3 legal constructive improvement

C1.3 started from the frozen C1.2 authoritative RAW baseline of 74.36% and ended at 74.83%.

```text
RAW bcefst improvement: +0.47 percentage points

Physical RAW hit delta:
  Statement      +1
  Branch         +7
  Condition     +11
  Expression     +4
  FSM state      +0
  FSM transition +0
  Toggle        +20
```

The added coverage came from legal constructive stimulus and regression plumbing correction.  C1.3 did not add exclusions, force internal state, or use deposit-based coverage injection.

One visible example is the Direct Stream operand-readiness pre-launch reject path: the previously protected CSR statement became a genuine RAW hit after its legal carrier was integrated into the canonical 150-item regression.

### 11.5 Historical CODE-COV-C1.1 checkpoint

CODE-COV-C1.1 was an earlier focused statement-closure checkpoint for:

```text
rtl/csr/ai_accel_csr_regs.sv
```

At that historical checkpoint:

```text
Raw statements              : 1172 / 1183 = 99.07%
Documented D3 waiver records: 11 / 11
Waiver-adjusted reachable   : 1172 / 1172 = 100.00%
Formal simulator exclusions : NONE at the C1.1 checkpoint
```

Those numbers remain valid as historical C1.1 evidence, but they are not the project's final full-RTL CODE-COV result.  The final project-level result is the C1.3 RAW / EFFECTIVE result in Sections 11.1 and 11.2.

### 11.6 Final closure decision

```text
CODE-COV-C1.1 : CLOSED
CODE-COV-C1.2 : CLOSED
CODE-COV-C1.3 : CLOSED

Final regression                 : 150 / 150 PASS
Final RAW bcefst                 : 74.83%
Final EFFECTIVE bcefst           : 77.34%
New C1.3 exclusions              : 0
Toggle exclusions                : 0
Known open RTL/integration bugs  : 0
```

Closure statement:

> CODE-COV-C1.3 is closed for the validated full synthesizable-RTL scope.  The authoritative RAW result is 74.83% bcefst.  The 77.34% EFFECTIVE result is a separately frozen exclusion-aware audit view using the unchanged C1.2 approved exclusion ledger.  C1.3 added legal constructive coverage without introducing new exclusions.

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

The final C1.3-D EFFECTIVE replay outputs under `sim/coverage/code_cov/c1_3_d/` are generated sign-off artifacts and remain ignored.  The replay Tcl and frozen exclusion-ledger Tcl files are tracked control artifacts.

---

## 13. Reproduction Commands

These commands assume the local UVM installation has been configured in `sim/local_uvm_12.tcl` as documented in the repository README.

### 13.1 Functional coverage

From `sim/`:

```tcl
set CODE_COV_ENABLE 0
set RC_COV_ENABLE 1
set RC_COV_CLEAN 1
set DO_COMPILE 1
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

The runner loads its canonical 150-item inventory from `sim/uvm_regression.list`.

### 13.2 RTL RAW code coverage

From `sim/`, use the Questa Transcript Tcl flow below.

Compile with RTL code-coverage instrumentation enabled:

```tcl
catch {quit -sim}

set RC_COV_ENABLE 0
set CODE_COV_ENABLE 1
set CODE_COV_METRICS bcefst

do compile_uvm.tcl
```

Run the existing full regression without recompiling:

```tcl
set RC_COV_ENABLE 0
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

Expected generated artifacts:

```text
sim/coverage/code_cov/code_cov_merged.ucdb
sim/coverage/code_cov/code_cov_manifest.tsv
sim/coverage/code_cov/code_cov_summary.txt
sim/coverage/code_cov/code_cov_details.txt
```

The merged UCDB and manifest remain generated artifacts.  The summary and detailed text reports are the tracked human-readable evidence.

### 13.3 Frozen EFFECTIVE sign-off replay

`sim/run_c1_3_d_effective_replay.tcl` is not a generic fresh-run coverage command.  It is the final C1.3 sign-off replay and is intentionally gated by the frozen canonical RAW SHA256 and frozen exclusion-ledger hashes.

Its purpose is to prove:

```text
C1.2 approved exclusion ledger identity is unchanged
new C1.3 exclusions are zero
canonical RAW UCDB remains immutable
final EFFECTIVE reports are produced from an isolated copy
```

A fresh code-coverage rerun should first be evaluated as a new RAW reproduction result rather than being assumed to have the same binary UCDB SHA256.

---

## 14. Final Verification Coverage Status

```text
RC-COV-A   Functional coverage architecture                 PASS
RC-COV-B   Functional coverage implementation               PASS
RC-COV-C1  UCDB collection / merge / report                 PASS
RC-COV-C2  Planned-bin refinement                            PASS
RC-COV-C3  Targeted telemetry closure                        PASS
RC-COV-D   Documentation closure                             PASS

CODE-COV-C1.1  CSR register-block closure                   PASS
CODE-COV-C1.2  RAW vs EFFECTIVE reconciliation closure      PASS
CODE-COV-C1.3  Legal constructive improvement / final freeze PASS

Regression:
  150 / 150 PASS

Planned functional coverage:
  100.00%
  7 / 7 covergroup types covered
  0 missing planned bins

Final full-RTL CODE-COV-C1.3:
  Authoritative RAW bcefst : 74.83%
  EFFECTIVE audit bcefst   : 77.34%
  RAW statement            : 5096 / 5285 = 96.42%
  EFFECTIVE statement      : 5096 / 5111 = 99.70%
  New C1.3 exclusions      : 0
  Toggle exclusions        : 0
  UCDB merge / report      : PASS

Final identity evidence:
  RAW UCDB SHA256       : ff2918d43a714d0ecd70ac8b1001c84cdfc3188f0ed4f825f3489343e0a1e079
  EFFECTIVE UCDB SHA256 : 2cc693444c94b2ee7d9d2c70237e797a2fd371e5c90bbe74595de76e05997dbf

Coverage campaign:
  CLOSED
```
