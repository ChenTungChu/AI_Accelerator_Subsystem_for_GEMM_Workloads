# DMA Load CDC Integration Spec

## 1. Purpose

This document defines the CDC-aware integration baseline for the AI Accelerator Subsystem DMA load path.

The subsystem currently supports the following verified scratchpad-based DMA load flow:

```text
DMA source memory
    -> dma_load_engine
    -> scratchpad_port0_owner_mux
    -> scratchpad BRAM Port0
    -> GEMM reads A/B through scratchpad Port1
    -> GEMM writes C back to scratchpad
    -> host reads back C
    -> result_bridge / scoreboard
```

The purpose of this milestone is to make the DMA-load-to-GEMM flow robust across `dma_clk` and `core_clk` while preserving the existing verified behavior.

This is still a **scratchpad load architecture**, not yet a direct stream-to-GEMM architecture.

---

## 2. Current Verified Baseline

Current verified status:

```text
Full UVM regression: 22 / 22 PASS
```

The baseline includes:

- host-primary GEMM path
- DMA load smoke path
- DMA load error / recovery path
- DMA source RRESP error recovery
- DMA load stress regression
- configurable clock-period regression
- CDC clock-ratio sanity run
- GEMM control/status CDC cleanup
- scoreboard result checking
- ctrl/result pairing

The current full regression includes one DMA-load CDC sanity item using a non-default `dma_clk` / `core_clk` ratio.

---

## 3. Design Principle

The CDC integration follows this rule:

```text
Do not move data across clock domains unless the architecture requires it.
```

For the current scratchpad load path, DMA data does not need to cross through an AXI-Stream async FIFO yet.

The reason is:

- DMA load writes A/B into scratchpad through Port0 in the `dma_clk` domain.
- GEMM reads A/B from scratchpad through Port1 in the `core_clk` domain.
- The dual-port scratchpad is the current data boundary.
- GEMM is launched only after DMA load completes successfully.

Therefore, the current CDC work focuses on:

```text
control/status CDC
clock-ratio regression
clear clock-domain ownership
```

not direct stream-to-core data movement.

---

## 4. Clock Domain Partition

### 4.1 DMA / Host-Side Domain

Clock:

```text
dma_clk
```

Owns:

- host AXI0 path
- scratchpad Port0 owner mux
- DMA source AXI-MM read side
- `axi_mm2s_dma`
- `axi_stream_loader`
- `dma_scratchpad_write_adapter`
- `dma_load_engine`
- DMA load status:
  - `dma_load_busy`
  - `dma_load_done`
  - `dma_load_error`
- external control interface observation side
- synchronized accelerator status returned from `core_clk`

This domain is responsible for loading A/B into scratchpad.

### 4.2 Core-Side Domain

Clock:

```text
core_clk
```

Owns:

- GEMM core
- GEMM scratchpad adapter
- scratchpad Port1 access
- core-domain GEMM configuration registers
- core-domain GEMM start pulse
- raw GEMM status:
  - `gemm_busy_core`
  - `gemm_done_core`

This domain is responsible for consuming A/B from scratchpad and producing C.

---

## 5. Current v3.1 Architecture

The CDC-aware scratchpad load architecture is:

```text
dma_clk domain
-------------------------------------------------------
DMA source AXI-MM read
    -> axi_mm2s_dma
    -> AXI-Stream internal path
    -> axi_stream_loader
    -> dma_scratchpad_write_adapter
    -> scratchpad_port0_owner_mux
    -> scratchpad Port0 write


scratchpad memory boundary
-------------------------------------------------------
A/B data becomes visible to core-side GEMM after DMA load
is complete and scratchpad write responses are committed.


core_clk domain
-------------------------------------------------------
GEMM start
    -> GEMM reads A/B from scratchpad Port1
    -> GEMM writes C
    -> acc_done
```

This keeps the proven scratchpad-based behavior while making the control/status CDC boundary explicit.

---

## 6. Implemented CDC Hardening

### 6.1 `acc_start`: `dma_clk` to `core_clk`

External `acc_start` is treated as a `dma_clk`-domain control signal.

Implemented behavior:

```text
dma_clk:
    acc_start rising edge detect
    capture GEMM config
    toggle start event

core_clk:
    2FF synchronize start toggle
    generate one-cycle gemm_start_core pulse
    latch captured config into core-domain registers
```

This prevents a multi-cycle `acc_start` level from creating multiple GEMM starts.

### 6.2 GEMM Config Bus

The following config signals are captured in `dma_clk` on `acc_start` rising edge:

```text
base_addr_a
base_addr_b
base_addr_c
dim_m
dim_n
dim_k
```

They are then latched into `core_clk` registers when the synchronized GEMM start pulse is generated.

`gemm_top` now receives only core-domain config registers.

This removes the previous direct use of DMA-side config buses inside the core-domain GEMM logic.

### 6.3 `acc_done`: `core_clk` to `dma_clk`

The raw core-side done pulse is converted into a toggle event:

```text
core_clk:
    acc_done_core_pulse
        -> acc_done_toggle_core_q

dma_clk:
    2FF synchronize toggle
    XOR previous synchronized value
        -> acc_done one-cycle pulse
```

The external `acc_done` output is now a `dma_clk`-domain pulse.

This avoids missing a narrow one-cycle `core_clk` pulse when observed from `dma_clk`.

### 6.4 `acc_busy`: `core_clk` to `dma_clk`

The core-side busy level is synchronized back into `dma_clk` using a 2FF level synchronizer.

The external `acc_busy` output is now a `dma_clk`-domain synchronized level.

---

## 7. DMA Load Control and Status

### 7.1 DMA Load Start

`dma_load_start` remains in the `dma_clk` domain.

No CDC is currently required for DMA load start.

### 7.2 DMA Load Done / Error

`dma_load_done` and `dma_load_error` are generated in the `dma_clk` domain.

No CDC is currently required for the existing software/testbench sequencing, because the testbench waits for DMA load completion from the DMA-side control interface before launching GEMM.

### 7.3 DMA-to-GEMM Sequencing

Current sequencing remains explicit:

```text
load A through DMA
wait dma_load_done && !dma_load_error

load B through DMA
wait dma_load_done && !dma_load_error

pulse acc_start
wait acc_done
read back C
compare result
```

There is no automatic DMA-to-GEMM start chain in the current baseline.

---

## 8. Control and Sequencing Rules

### 8.1 DMA Load Job Completion

A DMA load job is complete only when:

```text
dma_load_done  = 1
dma_load_error = 0
```

At this point:

- DMA source read has completed.
- Loader has accepted the stream.
- Adapter has completed scratchpad writes.
- Scratchpad Port0 ownership can return to host.
- GEMM may safely be launched afterward.

### 8.2 GEMM Job Start

A GEMM job may start only after:

```text
A load done without error
B load done without error
scratchpad Port0 ownership returned to host/non-DMA mode
core reset is released
```

### 8.3 Error Behavior

If DMA load reports:

```text
dma_load_done  = 1
dma_load_error = 1
```

Then:

- GEMM must not start using that payload.
- Port0 ownership must recover.
- host sanity access should still work.
- a later valid DMA load should still be possible.

This preserves the existing DMA error/recovery behavior.

---

## 9. Reset Rules

### 9.1 DMA Reset

`dma_rst_n` resets:

- DMA load engine
- DMA source responder model, if applicable
- scratchpad Port0 owner mux control
- DMA-side control/status state
- DMA-side start/config capture registers
- DMA-side synchronized accelerator status

### 9.2 Core Reset

`core_rst_n` resets:

- GEMM core
- GEMM scratchpad adapter
- core-side GEMM config registers
- core-side start synchronizer state
- core-side done toggle state

### 9.3 Cross-Domain Reset Expectation

The design should tolerate:

- both resets asserted together
- DMA reset while core is idle
- core reset after DMA load completion
- mid-run core reset during GEMM execution

The current CDC cleanup synchronizer logic resets safely when either side reset is asserted for cross-domain status/start synchronizer state.

---

## 10. Configurable Clock-Period Support

The UVM top supports plusarg-controlled clock periods:

```text
+DMA_CLK_PERIOD_NS=<real>
+CORE_CLK_PERIOD_NS=<real>
```

Default behavior:

```text
dma_clk  period = 10 ns
core_clk period = 14 ns
```

Example CDC sanity configurations:

```tcl
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 13
```

```tcl
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 7
```

The run script forwards these values into simulation.

---

## 11. Verification Plan

The CDC-aware milestone reuses existing tests.

No new functional test is required for this baseline.

### 11.1 Compile

```tcl
do compile_uvm.tcl
```

Pass criteria:

- compile passes
- no new interface/modport error
- no new CDC wiring error

### 11.2 DMA Load Smoke RUN_ALL

```tcl
set UVM_TEST ai_accel_subsys_dma_load_smoke_test
set ENABLE_RESULT_CHECK 1
set RUN_ALL 1
do run_uvm.tcl
```

Pass criteria:

- all DMA RUN_ALL cases pass
- result bridge publishes all expected results
- scoreboard pairing passes

### 11.3 DMA Load Error / Recovery

```tcl
set UVM_TEST ai_accel_subsys_dma_load_error_test
set ENABLE_RESULT_CHECK 0
do run_uvm.tcl
```

Pass criteria:

- invalid launch cases pass
- source RRESP error injection passes
- post-error DMA/GEMM recovery passes

### 11.4 DMA Load Stress

```tcl
set UVM_TEST ai_accel_subsys_dma_load_stress_test
set ENABLE_RESULT_CHECK 1
set STRESS_JOB_COUNT 8
set STRESS_SEED 20260502
set STRESS_RANDOM 1
set STRESS_GAP_CYCLES 10
do run_uvm.tcl
```

Pass criteria:

- all stress jobs complete
- scoreboard result summary passes
- ctrl/result pairing passes

### 11.5 CDC Clock-Ratio Sanity

Recommended full-regression CDC sanity item:

```tcl
set UVM_TEST ai_accel_subsys_dma_load_stress_test
set ENABLE_RESULT_CHECK 1
set STRESS_JOB_COUNT 8
set STRESS_SEED 20260502
set STRESS_RANDOM 1
set STRESS_GAP_CYCLES 10
set DMA_CLK_PERIOD_NS 10
set CORE_CLK_PERIOD_NS 13
do run_uvm.tcl
```

Pass criteria:

- all stress jobs complete
- no deadlock
- scoreboard result compare passes
- ctrl/result pairing passes

### 11.6 Full Regression

```tcl
do run_full_uvm_regression.tcl
```

Current pass criteria:

```text
TOTAL : 22
PASS  : 22
FAIL  : 0
```

---

## 12. Known Warning Policy

The current Questa `vsim-3838` multiple-driver warning related to `axi_mm_if` clocking-block implicit drivers and the Port0 owner mux is treated as a known simulator/interface warning.

It is not part of this CDC milestone.

Do not modify the shared BRAM `axi_mm_if.sv` only to remove this warning unless the BRAM repository regression is also updated and fully re-run.

Current status:

```text
Known warning accepted.
Functional regression passes.
No BRAM interface semantic change required.
```

---

## 13. Acceptance Criteria

The CDC-aware DMA load milestone is complete when:

1. Clock ownership is clear in RTL.
2. DMA load datapath remains in `dma_clk`.
3. GEMM compute datapath remains in `core_clk`.
4. `acc_start` crosses from `dma_clk` to `core_clk` through a safe toggle synchronizer.
5. GEMM config is captured before start and latched in `core_clk`.
6. `acc_done` crosses from `core_clk` to `dma_clk` through a toggle synchronizer.
7. `acc_busy` crosses from `core_clk` to `dma_clk` through a level synchronizer.
8. DMA load smoke passes with scoreboard enabled.
9. DMA load error/recovery passes.
10. DMA load stress passes.
11. At least one CDC clock-ratio sanity run passes.
12. Full UVM regression passes.
13. No new UVM error or fatal is introduced.
14. No new BRAM interface semantic change is required.

Current status:

```text
All acceptance criteria met for the scratchpad DMA-load CDC baseline.
Full UVM regression: 22 / 22 PASS
```

---

## 14. Recommended Implementation Status

Completed:

```text
[x] Clock period plusargs
[x] run_uvm.tcl clock plusarg forwarding
[x] DMA load stress CDC sanity run
[x] Full regression item for CDC clock ratio
[x] acc_start rising-edge protection
[x] acc_start dma_clk -> core_clk toggle synchronizer
[x] GEMM config capture in dma_clk
[x] GEMM config latch in core_clk
[x] acc_done core_clk -> dma_clk toggle synchronizer
[x] acc_busy core_clk -> dma_clk level synchronizer
[x] Full UVM regression 22/22 PASS
```

Not included in this milestone:

```text
[ ] direct AXI-Stream async FIFO to GEMM
[ ] automatic DMA-to-GEMM start chain
[ ] S2MM result DMA
[ ] tiling / multi-MAC optimization
```

---

## 15. Future Milestones

### 15.1 Direct AXI-Stream GEMM Frontend

Future architecture:

```text
DMA MM2S
    -> AXI-Stream async FIFO
    -> GEMM stream frontend
    -> compute
```

This would be the real `AXI-Stream feeding GEMM` path.

It should be treated as a separate milestone from the current scratchpad DMA-load CDC baseline.

### 15.2 S2MM Result Path

A future S2MM path may write GEMM output directly to memory through a DMA writeback engine.

### 15.3 Tiling / Multi-MAC Compute

After DMA / stream / CDC boundaries are stable, the project can move toward:

- tiled GEMM
- multiple MAC lanes
- local buffering
- performance counters
- throughput-oriented architecture
