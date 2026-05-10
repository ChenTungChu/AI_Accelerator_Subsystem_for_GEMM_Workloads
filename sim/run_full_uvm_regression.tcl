# File: sim/run_full_uvm_regression.tcl

# ============================================================
# Full UVM regression runner
#
# Usage:
#   do compile_uvm.tcl
#   do run_full_uvm_regression.tcl
#
# Or:
#   set DO_COMPILE 1
#   do run_full_uvm_regression.tcl
# ============================================================

# ------------------------------------------------------------
# Optional compile
# ------------------------------------------------------------
if {![info exists DO_COMPILE]} {
    set DO_COMPILE 0
}

if {$DO_COMPILE} {
    puts "\n\[REGRESSION\] Running compile_uvm.tcl first..."
    do compile_uvm.tcl
}

# ------------------------------------------------------------
# Regression bookkeeping
# ------------------------------------------------------------
set REG_TOTAL 0
set REG_PASS  0
set REG_FAIL  0

# ------------------------------------------------------------
# Clear sticky Questa Tcl variables before each run
# ------------------------------------------------------------
proc clear_uvm_run_vars {} {
    unset -nocomplain UVM_TEST
    unset -nocomplain TESTNAME
    unset -nocomplain CASE_ID

    unset -nocomplain ENABLE_RESULT_CHECK
    unset -nocomplain FORCE_HELPER_MEM_PATH
    unset -nocomplain RUN_ALL
    unset -nocomplain EXTRA_PLUSARGS

    unset -nocomplain USE_HOST_AGENT_CLEAR_C
    unset -nocomplain USE_HOST_AGENT_READBACK_C
    unset -nocomplain USE_HOST_AGENT_PRELOAD_AB

    unset -nocomplain JOB_COUNT
    unset -nocomplain JOB0_CASE_ID
    unset -nocomplain JOB1_CASE_ID
    unset -nocomplain JOB2_CASE_ID
    unset -nocomplain JOB3_CASE_ID

    unset -nocomplain PRE_RESET_CASE_ID
    unset -nocomplain POST_RESET_CASE_ID
    unset -nocomplain RESET_HOLD_CYCLES
    unset -nocomplain POST_RESET_SETTLE_CYCLES
}

# ------------------------------------------------------------
# Check generated log summary
# ------------------------------------------------------------
proc check_uvm_log {log_file} {
    if {![file exists $log_file]} {
        puts "\[REGRESSION\]\[FAIL\] Log file not found: $log_file"
        return 0
    }

    set fp [open $log_file r]
    set txt [read $fp]
    close $fp

    set has_zero_error [regexp {UVM_ERROR[ \t]*:[ \t]*0} $txt]
    set has_zero_fatal [regexp {UVM_FATAL[ \t]*:[ \t]*0} $txt]

    if {$has_zero_error && $has_zero_fatal} {
        return 1
    }

    puts "\[REGRESSION\]\[FAIL\] Non-zero UVM_ERROR/UVM_FATAL or missing summary in: $log_file"
    return 0
}

# ------------------------------------------------------------
# Run one item
# ------------------------------------------------------------
proc run_reg_item {name setup_body} {
    global REG_TOTAL REG_PASS REG_FAIL LOG_FILE

    incr REG_TOTAL

    puts "\n============================================================"
    puts "\[REGRESSION\] START #$REG_TOTAL: $name"
    puts "============================================================"

    clear_uvm_run_vars

    # Stop previous sim context if any.
    catch {quit -sim -f}

    # Apply item-specific variable setup.
    uplevel 1 $setup_body

    set run_status [catch {do run_uvm.tcl} run_msg]

    if {$run_status != 0} {
        puts "\[REGRESSION\]\[FAIL\] Tcl/run error in: $name"
        puts $run_msg
        incr REG_FAIL
        return
    }

    if {[info exists LOG_FILE] && [check_uvm_log $LOG_FILE]} {
        puts "\[REGRESSION\]\[PASS\] $name"
        incr REG_PASS
    } else {
        puts "\[REGRESSION\]\[FAIL\] $name"
        incr REG_FAIL
    }
}

# ============================================================
# Smoke test: primary host path
# ============================================================

run_reg_item "smoke CASE_ID=5" {
    set UVM_TEST ai_accel_subsys_smoke_test
    set CASE_ID 5
    set ENABLE_RESULT_CHECK 1
}

run_reg_item "smoke CASE_ID=100" {
    set UVM_TEST ai_accel_subsys_smoke_test
    set CASE_ID 100
    set ENABLE_RESULT_CHECK 1
}

run_reg_item "smoke CASE_ID=101" {
    set UVM_TEST ai_accel_subsys_smoke_test
    set CASE_ID 101
    set ENABLE_RESULT_CHECK 1
}

run_reg_item "smoke CASE_ID=105" {
    set UVM_TEST ai_accel_subsys_smoke_test
    set CASE_ID 105
    set ENABLE_RESULT_CHECK 1
}

run_reg_item "smoke CASE_ID=400" {
    set UVM_TEST ai_accel_subsys_smoke_test
    set CASE_ID 400
    set ENABLE_RESULT_CHECK 1
}

run_reg_item "smoke CASE_ID=401" {
    set UVM_TEST ai_accel_subsys_smoke_test
    set CASE_ID 401
    set ENABLE_RESULT_CHECK 1
}

run_reg_item "smoke CASE_ID=402" {
    set UVM_TEST ai_accel_subsys_smoke_test
    set CASE_ID 402
    set ENABLE_RESULT_CHECK 1
}

run_reg_item "smoke CASE_ID=403" {
    set UVM_TEST ai_accel_subsys_smoke_test
    set CASE_ID 403
    set ENABLE_RESULT_CHECK 1
}

# ============================================================
# DMA load smoke: primary DMA-load path
# ============================================================

run_reg_item "dma_load_smoke RUN_ALL" {
    set UVM_TEST ai_accel_subsys_dma_load_smoke_test
    set CASE_ID 100
    set RUN_ALL 1
}

# ============================================================
# DMA load error / recovery test
# ============================================================

run_reg_item "dma_load_error invalid_launch_and_recovery" {
    set UVM_TEST ai_accel_subsys_dma_load_error_test
    set ENABLE_RESULT_CHECK 0
}

# ============================================================
# Back-to-back test: primary host path
# ============================================================

run_reg_item "back_to_back 100->101" {
    set UVM_TEST ai_accel_subsys_back_to_back_test
    set ENABLE_RESULT_CHECK 1
    set JOB_COUNT 2
    set JOB0_CASE_ID 100
    set JOB1_CASE_ID 101
}

run_reg_item "back_to_back 5->0" {
    set UVM_TEST ai_accel_subsys_back_to_back_test
    set ENABLE_RESULT_CHECK 1
    set JOB_COUNT 2
    set JOB0_CASE_ID 5
    set JOB1_CASE_ID 0
}

run_reg_item "back_to_back 5->101->400" {
    set UVM_TEST ai_accel_subsys_back_to_back_test
    set ENABLE_RESULT_CHECK 1
    set JOB_COUNT 3
    set JOB0_CASE_ID 5
    set JOB1_CASE_ID 101
    set JOB2_CASE_ID 400
}

# ============================================================
# Reset recovery test: primary host path
# ============================================================

run_reg_item "reset_recovery 5->101" {
    set UVM_TEST ai_accel_subsys_reset_recovery_test
    set ENABLE_RESULT_CHECK 1
    set PRE_RESET_CASE_ID 5
    set POST_RESET_CASE_ID 101
}

run_reg_item "reset_recovery 5->400" {
    set UVM_TEST ai_accel_subsys_reset_recovery_test
    set ENABLE_RESULT_CHECK 1
    set PRE_RESET_CASE_ID 5
    set POST_RESET_CASE_ID 400
}

# ============================================================
# Corner test: primary host path
# ============================================================

run_reg_item "corner default 5->101->105->403" {
    set UVM_TEST ai_accel_subsys_corner_test
    set ENABLE_RESULT_CHECK 1
}

# ============================================================
# Mid-run reset / abort recovery test
#
# NOTE:
#   ABORT_CASE_ID / RECOVERY_CASE_ID are passed through EXTRA_PLUSARGS
#   because run_uvm.tcl currently forwards EXTRA_PLUSARGS as an escape hatch.
# ============================================================

run_reg_item "midrun_reset abort=5 recovery=101" {
    set UVM_TEST ai_accel_subsys_midrun_reset_test
    set ENABLE_RESULT_CHECK 1
    set RESET_HOLD_CYCLES 5
    set POST_RESET_SETTLE_CYCLES 5
    set EXTRA_PLUSARGS "+ABORT_CASE_ID=5 +RECOVERY_CASE_ID=101 +RESET_TRIGGER_CYCLES_AFTER_BUSY=8"
}

# ============================================================
# DMA load stress test
# ============================================================

run_reg_item "dma_load_stress 8 jobs" {
    set UVM_TEST ai_accel_subsys_dma_load_stress_test
    set ENABLE_RESULT_CHECK 1
    set STRESS_JOB_COUNT 8
    set STRESS_SEED 20260502
    set STRESS_RANDOM 1
    set STRESS_GAP_CYCLES 10
}

# ============================================================
# CDC sanity
# ============================================================
run_reg_item "dma_load_stress cdc 8 jobs clk10_13" {
    set UVM_TEST ai_accel_subsys_dma_load_stress_test
    set ENABLE_RESULT_CHECK 1
    set STRESS_JOB_COUNT 8
    set STRESS_SEED 20260502
    set STRESS_RANDOM 1
    set STRESS_GAP_CYCLES 10
    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 13
}

# ============================================================
# DMA store stress test
# ============================================================
run_reg_item "dma_store_smoke RUN_ALL" {
    set UVM_TEST ai_accel_subsys_dma_store_smoke_test
    set ENABLE_RESULT_CHECK 1
    set RUN_ALL 1
}

# ============================================================
# DMA store error test
# ============================================================
run_reg_item "dma_store_error default" {
    set UVM_TEST ai_accel_subsys_dma_store_error_test
    set ENABLE_RESULT_CHECK 0
}

# ============================================================
# DMA store stress test
# ============================================================
run_reg_item "dma_load_store_stress 8 jobs" {
    set UVM_TEST ai_accel_subsys_dma_load_store_stress_test
    set ENABLE_RESULT_CHECK 1
    set STORE_STRESS_JOB_COUNT 8
    set STORE_STRESS_SEED 20260502
    set STORE_STRESS_RANDOM 1
    set STORE_STRESS_GAP_CYCLES 10
}

# ============================================================
# AXIS stream preload smoke test
# ============================================================
run_reg_item "axis_stream_preload_smoke_run_all" {
    set UVM_TEST ai_accel_subsys_axis_stream_preload_smoke_test
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 100
    set RUN_ALL 1
}

# ============================================================
# AXIS stream preload error test
# ============================================================
run_reg_item "axis_stream_preload_error_recovery" {
    set UVM_TEST ai_accel_subsys_axis_stream_preload_error_test
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 100
}

# ============================================================
# AXIS stream load store stress test
# ============================================================
run_reg_item "axis_stream_load_store_stress 8 jobs" {
    set UVM_TEST ai_accel_subsys_axis_stream_load_store_stress_test
    set ENABLE_RESULT_CHECK 1
    set AXIS_STRESS_JOB_COUNT 8
    set AXIS_STRESS_SEED 20260502
    set AXIS_STRESS_RANDOM 1
    set AXIS_STRESS_GAP_CYCLES 10
}

# ============================================================
# AXIS stream CDC clock-ratio sanity
# ============================================================
run_reg_item "axis_stream_load_store_stress_cdc_10_13" {
    set UVM_TEST ai_accel_subsys_axis_stream_load_store_stress_test
    set ENABLE_RESULT_CHECK 1
    set AXIS_STRESS_JOB_COUNT 8
    set AXIS_STRESS_SEED 20260502
    set AXIS_STRESS_RANDOM 1
    set AXIS_STRESS_GAP_CYCLES 10
    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 13
}

# ============================================================
# Direct stream error test
# ============================================================
run_reg_item "direct_stream_error_recovery" {
    set UVM_TEST ai_accel_subsys_direct_stream_error_test
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 100
}

# ============================================================
# Direct stream smoke test
# ============================================================
run_reg_item "direct_stream_smoke_run_all" {
    set UVM_TEST ai_accel_subsys_direct_stream_smoke_test
    set ENABLE_RESULT_CHECK 1
    set RUN_ALL 1
}

# ============================================================
# Direct stream load store test
# ============================================================
run_reg_item "direct_stream_load_store_stress" {
    set UVM_TEST ai_accel_subsys_direct_stream_load_store_stress_test
    set ENABLE_RESULT_CHECK 1
    set DS_STRESS_JOB_COUNT 8
    set DS_STRESS_SEED 20260502
    set DS_STRESS_RANDOM 1
    set DS_STRESS_GAP_CYCLES 10
}

# ============================================================
# Direct stream load store CDC sanity
# ============================================================
run_reg_item "direct_stream_load_store_stress_cdc_10_13" {
    set UVM_TEST ai_accel_subsys_direct_stream_load_store_stress_test
    set ENABLE_RESULT_CHECK 1
    set DS_STRESS_JOB_COUNT 8
    set DS_STRESS_SEED 20260502
    set DS_STRESS_RANDOM 1
    set DS_STRESS_GAP_CYCLES 10
    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 13
}

# ============================================================
# Performance counter smoke test
# ============================================================
run_reg_item "perf_counter_smoke" {
    set UVM_TEST ai_accel_subsys_perf_counter_smoke_test
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 100
    set RUN_ALL 1
}

# ============================================================
# Helper fallback sanity
# ============================================================

run_reg_item "helper smoke CASE_ID=101" {
    set UVM_TEST ai_accel_subsys_smoke_test
    set CASE_ID 101
    set ENABLE_RESULT_CHECK 1
    set FORCE_HELPER_MEM_PATH 1
}

run_reg_item "helper back_to_back 100->101" {
    set UVM_TEST ai_accel_subsys_back_to_back_test
    set ENABLE_RESULT_CHECK 1
    set FORCE_HELPER_MEM_PATH 1
    set JOB_COUNT 2
    set JOB0_CASE_ID 100
    set JOB1_CASE_ID 101
}

run_reg_item "helper reset_recovery 5->101" {
    set UVM_TEST ai_accel_subsys_reset_recovery_test
    set ENABLE_RESULT_CHECK 1
    set FORCE_HELPER_MEM_PATH 1
    set PRE_RESET_CASE_ID 5
    set POST_RESET_CASE_ID 101
}

# ============================================================
# Final summary
# ============================================================

puts "\n============================================================"
puts "\[REGRESSION\] FINAL SUMMARY"
puts "============================================================"
puts "TOTAL : $REG_TOTAL"
puts "PASS  : $REG_PASS"
puts "FAIL  : $REG_FAIL"
puts "============================================================"

if {$REG_FAIL != 0} {
    error "\[REGRESSION\] FAILED: $REG_FAIL item(s) failed"
} else {
    puts "\[REGRESSION\] ALL TESTS PASSED"
}