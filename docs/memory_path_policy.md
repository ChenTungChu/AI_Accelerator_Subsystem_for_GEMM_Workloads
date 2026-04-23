# Memory Path Policy

## Overview

目前 UVM testbench 的 memory access 採用固定策略：

- 預設走 **host agent**
- `helper` 只作為 **fallback / debug** 使用

這個策略目前適用於：

- `ai_accel_subsys_smoke_test`
- `ai_accel_subsys_back_to_back_test`
- `ai_accel_subsys_reset_recovery_test`

---

## Default behavior

當開啟：

```tcl
+ENABLE_RESULT_CHECK=1

memory path 會預設走 host agent。

包含以下操作：

clear C
preload A
preload B
readback C

這是目前主要的驗證路徑，也是 regression 預設應該使用的模式。

Fallback behavior

如果另外加上：

+FORCE_HELPER_MEM_PATH=1

則 memory path 會退回 helper。

這個模式主要用在：

debug
快速確認 host-agent path 以外的基準行為
檢查 fallback 機制本身沒有壞掉

一般 regression 不建議長期用 helper 當主路徑。

Legacy override knobs

下面這幾個 knob 目前還保留：

+USE_HOST_AGENT_CLEAR_C=0/1
+USE_HOST_AGENT_READBACK_C=0/1
+USE_HOST_AGENT_PRELOAD_AB=0/1

這些主要是給局部 debug 用，不建議當成平常操作方式。

目前建議的使用習慣是：

日常跑法：只用 +ENABLE_RESULT_CHECK=1
需要 fallback：加 +FORCE_HELPER_MEM_PATH=1
只有在要 isolate 單一路徑時，才去動 USE_HOST_AGENT_*
Priority

目前 priority 如下：

明確指定的 USE_HOST_AGENT_*
FORCE_HELPER_MEM_PATH
default policy

也就是說，如果同時設：

+FORCE_HELPER_MEM_PATH=1
+USE_HOST_AGENT_CLEAR_C=1

那 clear C 仍然會走 host agent，因為 explicit override 優先。

Expected log behavior
Host-agent mode

在 default host-agent mode 下，log 通常會看到：

via host_agent
Clearing C via host_agent
Preloading A/B via host_agent
Reading back C via host_agent

而且 host_agent 會是 active。

Helper fallback mode

在 fallback mode 下，log 通常會看到：

via helper

而且 host_agent 會是 passive。

Why host monitor still sees traffic in helper mode

這是正常現象。

即使 memory path 退回 helper，bus activity 仍然發生在同一條 axi0 路徑上，所以 passive host monitor 一樣會看到 write/read。

差別在於：

host-agent primary mode
會有完整的 sequencer / driver / response flow，metadata 也比較完整
helper fallback mode
monitor 仍然看得到 bus activity，但通常不會有完整的 host sequence context

所以 fallback mode 下看到 AXI_HOST_MON 訊息，不代表 host agent 真的在主動送 transaction。

Recommended usage
Smoke test
default
catch {unset FORCE_HELPER_MEM_PATH}
catch {unset USE_HOST_AGENT_CLEAR_C}
catch {unset USE_HOST_AGENT_READBACK_C}
catch {unset USE_HOST_AGENT_PRELOAD_AB}

set UVM_TEST ai_accel_subsys_smoke_test
set CASE_ID 101
set ENABLE_RESULT_CHECK 1
do run_uvm.tcl
fallback
catch {unset USE_HOST_AGENT_CLEAR_C}
catch {unset USE_HOST_AGENT_READBACK_C}
catch {unset USE_HOST_AGENT_PRELOAD_AB}

set UVM_TEST ai_accel_subsys_smoke_test
set CASE_ID 101
set ENABLE_RESULT_CHECK 1
set FORCE_HELPER_MEM_PATH 1
do run_uvm.tcl
Back-to-back test
default
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
fallback
catch {unset USE_HOST_AGENT_CLEAR_C}
catch {unset USE_HOST_AGENT_READBACK_C}
catch {unset USE_HOST_AGENT_PRELOAD_AB}

set UVM_TEST ai_accel_subsys_back_to_back_test
set ENABLE_RESULT_CHECK 1
set FORCE_HELPER_MEM_PATH 1
set JOB_COUNT 2
set JOB0_CASE_ID 100
set JOB1_CASE_ID 101
do run_uvm.tcl
Reset-recovery test
default
catch {unset FORCE_HELPER_MEM_PATH}
catch {unset USE_HOST_AGENT_CLEAR_C}
catch {unset USE_HOST_AGENT_READBACK_C}
catch {unset USE_HOST_AGENT_PRELOAD_AB}

set UVM_TEST ai_accel_subsys_reset_recovery_test
set ENABLE_RESULT_CHECK 1
set PRE_RESET_CASE_ID 5
set POST_RESET_CASE_ID 101
do run_uvm.tcl
fallback
catch {unset USE_HOST_AGENT_CLEAR_C}
catch {unset USE_HOST_AGENT_READBACK_C}
catch {unset USE_HOST_AGENT_PRELOAD_AB}

set UVM_TEST ai_accel_subsys_reset_recovery_test
set ENABLE_RESULT_CHECK 1
set FORCE_HELPER_MEM_PATH 1
set PRE_RESET_CASE_ID 5
set POST_RESET_CASE_ID 101
do run_uvm.tcl
Regression guidance

建議目前把 regression 分成兩層：

Main path

uvm_host_agent_regression.list

使用 host-agent default path
作為主要 regression
Sanity fallback

uvm_helper_fallback_sanity.list

只保留少量 testcase
用來確認 fallback 機制還正常