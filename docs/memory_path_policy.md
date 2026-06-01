# Memory Path Policy

## Overview

This document defines two related but separate policies:

```text
1. UVM memory setup/readback path
2. GEMM runtime memory routing path
```

The UVM memory path controls how tests clear C, preload A/B, and read back C.
The GEMM runtime memory path controls how `gemm_top` reads A/B/C and writes C during compute.

Both policies are part of the AI accelerator subsystem verification baseline.

---

## 1. UVM Memory Setup / Readback Policy

The default UVM testbench memory access path is:

```text
host agent primary
helper fallback/debug only
```

This policy currently applies to host-primary style tests such as:

```text
ai_accel_subsys_smoke_test
ai_accel_subsys_back_to_back_test
ai_accel_subsys_reset_recovery_test
```

### 1.1 Default Behavior

When result checking is enabled:

```tcl
set ENABLE_RESULT_CHECK 1
```

the testbench uses the host agent by default for:

```text
clear C
preload A
preload B
readback C
```

This is the main verification path and should remain the default regression mode.

### 1.2 Helper Fallback

To force helper-based setup/readback:

```tcl
set FORCE_HELPER_MEM_PATH 1
```

Use this mode only for:

```text
debug
fallback sanity
isolating host-agent issues
quick comparison against the older helper path
```

General regression should not use helper as the primary memory path.

### 1.3 Legacy Override Knobs

These knobs are still supported for focused debug:

```tcl
set USE_HOST_AGENT_CLEAR_C    0 ;# or 1
set USE_HOST_AGENT_READBACK_C 0 ;# or 1
set USE_HOST_AGENT_PRELOAD_AB 0 ;# or 1
```

Recommended usage:

```text
normal run       : ENABLE_RESULT_CHECK=1 only
fallback run     : add FORCE_HELPER_MEM_PATH=1
focused isolate  : use USE_HOST_AGENT_* only when debugging one operation
```

### 1.4 Priority

Priority is:

```text
1. explicit USE_HOST_AGENT_* override
2. FORCE_HELPER_MEM_PATH
3. default host-agent policy
```

Example:

```tcl
set FORCE_HELPER_MEM_PATH 1
set USE_HOST_AGENT_CLEAR_C 1
```

In this case, `clear C` still uses the host agent because the explicit override has the highest priority.

### 1.5 Expected Log Behavior

Host-agent mode usually shows:

```text
via host_agent
Clearing C via host_agent
Preloading A/B via host_agent
Reading back C via host_agent
```

and the host agent is active.

Helper fallback mode usually shows:

```text
via helper
```

and the host agent is passive.

### 1.6 Why the Host Monitor Still Sees Traffic in Helper Mode

This is expected.

Even when setup/readback uses helper, bus activity still appears on the same AXI0 path. A passive host monitor can still observe those writes and reads.

The difference is:

```text
host-agent primary mode:
  sequencer / driver / response flow is active
  metadata is complete

helper fallback mode:
  monitor can still see bus activity
  host sequence context is not the source of the transaction
```

Therefore, seeing `AXI_HOST_MON` messages in helper mode does not mean the host agent actively drove the transaction.

---

## 2. GEMM Runtime Memory Routing Policy

This policy describes the path used by the GEMM core while a job is running.

### 2.1 Scratchpad Mode

In scratchpad mode:

```text
GEMM A reads -> scratchpad adapter
GEMM B reads -> scratchpad adapter
GEMM C reads -> scratchpad adapter
GEMM C writes -> scratchpad adapter
```

This is the baseline mode used by host-primary, DMA load-store, and AXI-Stream preload flows.

### 2.2 Direct Stream Mode

In Direct Stream mode, only A/B operand reads are redirected to the operand buffer:

```text
GEMM A reads -> operand buffer A
GEMM B reads -> operand buffer B
```

C remains scratchpad-backed:

```text
GEMM C RMW old-C reads -> scratchpad adapter
GEMM C writes          -> scratchpad adapter
```

This rule is required by P13 C read-modify-write accumulation.

A valid Direct Stream P13 job sequence is:

```text
Direct Stream preload A_part/B_part into operand buffer
GEMM reads A/B from operand buffer
if accumulate_enable=1, GEMM reads old C from scratchpad
GEMM writes updated C to scratchpad
DMA store exports final C after the last partial job
```

### 2.3 Direct Stream Router Rule

The router policy is:

```text
direct_stream_mode = 0:
  all GEMM reads/writes pass through scratchpad

direct_stream_mode = 1:
  A/B reads route to operand buffer
  non-A/B reads route to scratchpad
  writes route to scratchpad
```

The non-A/B read path is used by P13 C RMW old-C reads.

---

## 3. Recommended Run Examples

### 3.1 Smoke Test, Default Host-Agent Path

```tcl
catch {unset FORCE_HELPER_MEM_PATH}
catch {unset USE_HOST_AGENT_CLEAR_C}
catch {unset USE_HOST_AGENT_READBACK_C}
catch {unset USE_HOST_AGENT_PRELOAD_AB}

set UVM_TEST ai_accel_subsys_smoke_test
set CASE_ID 101
set ENABLE_RESULT_CHECK 1
do run_uvm.tcl
```

### 3.2 Smoke Test, Helper Fallback

```tcl
catch {unset USE_HOST_AGENT_CLEAR_C}
catch {unset USE_HOST_AGENT_READBACK_C}
catch {unset USE_HOST_AGENT_PRELOAD_AB}

set UVM_TEST ai_accel_subsys_smoke_test
set CASE_ID 101
set ENABLE_RESULT_CHECK 1
set FORCE_HELPER_MEM_PATH 1
do run_uvm.tcl
```

### 3.3 Back-to-Back Test, Default Host-Agent Path

```tcl
catch {unset FORCE_HELPER_MEM_PATH}
catch {unset USE_HOST_AGENT_CLEAR_C}
catch {unset USE_HOST_AGENT_READBACK_C}
catch {unset USE_HOST_AGENT_PRELOAD_AB}

set UVM_TEST ai_accel_subsys_back_to_back_test
set ENABLE_RESULT_CHECK 1
set JOB_COUNT 2
set JOB0_CASE_ID 100
set JOB1_CASE_ID 101
do run_uvm.tcl
```

### 3.4 Reset-Recovery Test, Default Host-Agent Path

```tcl
catch {unset FORCE_HELPER_MEM_PATH}
catch {unset USE_HOST_AGENT_CLEAR_C}
catch {unset USE_HOST_AGENT_READBACK_C}
catch {unset USE_HOST_AGENT_PRELOAD_AB}

set UVM_TEST ai_accel_subsys_reset_recovery_test
set ENABLE_RESULT_CHECK 1
set PRE_RESET_CASE_ID 5
set POST_RESET_CASE_ID 101
do run_uvm.tcl
```

---

## 4. Regression Guidance

Use a two-layer policy:

```text
main regression:
  host-agent default path

fallback sanity:
  small helper-based subset only
```

Recommended default:

```text
Use host-agent memory setup/readback in main regression.
Keep helper fallback for debug and sanity only.
```

P13 C RMW frontend representative items use frontend-specific A/B preload paths and keep C result export through the existing DMA store / result bridge path.
