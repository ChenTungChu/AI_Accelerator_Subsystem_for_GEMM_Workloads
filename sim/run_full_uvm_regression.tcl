# File: sim/run_full_uvm_regression.tcl
# ============================================================
# Full UVM regression runner
#
# Usage:
#   do compile_uvm.tcl
#   do run_full_uvm_regression.tcl
#
# Optional compile:
#   set DO_COMPILE 1
#   do run_full_uvm_regression.tcl
# ============================================================
# ============================================================
# Optional compile
# ============================================================
if {![info exists DO_COMPILE]} {
    set DO_COMPILE 0
}

if {$DO_COMPILE} {
    puts "\n\[REGRESSION\] Running compile_uvm.tcl first..."
    do compile_uvm.tcl
}

# ============================================================
# Regression bookkeeping
# ============================================================
set REG_TOTAL 0
set REG_PASS  0
set REG_FAIL  0

# Keep per-item results for the final pass/fail report.
set REG_PASS_ITEMS {}
set REG_FAIL_ITEMS {}

# Set STOP_ON_FIRST_FAIL=1 to stop after the first failed item.
if {![info exists STOP_ON_FIRST_FAIL]} {
    set STOP_ON_FIRST_FAIL 0
}

if {($STOP_ON_FIRST_FAIL != 0) && ($STOP_ON_FIRST_FAIL != 1)} {
    error "\[REGRESSION\] Unsupported STOP_ON_FIRST_FAIL='$STOP_ON_FIRST_FAIL'. Supported values: 0, 1"
}

# ============================================================
# Clear sticky run variables
#
# run_uvm.tcl reads top-level Questa Tcl variables.
# Clear them globally before every regression item.
# ============================================================
proc clear_uvm_run_vars {} {
    foreach v {
        UVM_TEST
        UVM_TOP
        TESTNAME
        CASE_ID

        ENABLE_RESULT_CHECK
        FORCE_HELPER_MEM_PATH
        RUN_ALL
        EXTRA_PLUSARGS
        LOG_FILE

        SMOKE_DONE_TIMEOUT_CYCLES
        DMA_STORE_DONE_TIMEOUT_CYCLES

        USE_HOST_AGENT_CLEAR_C
        USE_HOST_AGENT_READBACK_C
        USE_HOST_AGENT_PRELOAD_AB

        JOB_COUNT
        JOB0_CASE_ID
        JOB1_CASE_ID
        JOB2_CASE_ID
        JOB3_CASE_ID

        PRE_RESET_CASE_ID
        POST_RESET_CASE_ID
        RESET_HOLD_CYCLES
        POST_RESET_SETTLE_CYCLES

        DMA_CLK_PERIOD_NS
        CORE_CLK_PERIOD_NS

        GEMM_MAC_LANES
        GEMM_ENABLE_B_CACHE
        GEMM_B_CACHE_MAX_K
        GEMM_B_CACHE_MAX_N
        GEMM_ENABLE_PACKED_BCACHE_PRELOAD
        GEMM_ENABLE_A_ROW_CACHE
        GEMM_A_ROW_CACHE_MAX_K
        GEMM_ENABLE_PACKED_A_ROW_PRELOAD
        GEMM_ENABLE_K_TILING
        GEMM_K_TILE_SIZE
        GEMM_ENABLE_N_TILING
        GEMM_N_TILE_SIZE
        GEMM_ENABLE_M_TILING
        GEMM_M_TILE_SIZE
        GEMM_ENABLE_C_RMW_ACCUM

        ACCUMULATE_ENABLE

        STRESS_JOB_COUNT
        STRESS_SEED
        STRESS_RANDOM
        STRESS_GAP_CYCLES

        STORE_STRESS_JOB_COUNT
        STORE_STRESS_SEED
        STORE_STRESS_RANDOM
        STORE_STRESS_GAP_CYCLES

        AXIS_STRESS_JOB_COUNT
        AXIS_STRESS_SEED
        AXIS_STRESS_RANDOM
        AXIS_STRESS_GAP_CYCLES

        DS_STRESS_JOB_COUNT
        DS_STRESS_SEED
        DS_STRESS_RANDOM
        DS_STRESS_GAP_CYCLES

        RUN_START_WHILE_BUSY
    } {
        unset -nocomplain ::$v
    }
}

# ============================================================
# Log checking
# ============================================================
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

# ============================================================
# Regression utility procs
# ============================================================
proc get_current_log_file {} {
    if {[info exists ::LOG_FILE]} {
        return $::LOG_FILE
    }
    return "<LOG_FILE not set>"
}

proc record_reg_fail {idx name log_file} {
    global REG_FAIL_ITEMS
    lappend REG_FAIL_ITEMS [list $idx $name $log_file]
}

proc record_reg_pass {idx name log_file} {
    global REG_PASS_ITEMS
    lappend REG_PASS_ITEMS [list $idx $name $log_file]
}

proc maybe_stop_on_first_fail {idx name log_file} {
    global STOP_ON_FIRST_FAIL

    if {$STOP_ON_FIRST_FAIL} {
        puts "\n============================================================"
        puts "\[REGRESSION\] STOP_ON_FIRST_FAIL"
        puts "============================================================"
        puts "First failed item:"
        puts [format "  #%-4s %s" $idx $name]
        puts "        log: $log_file"
        puts "============================================================"
        error "\[REGRESSION\] STOP_ON_FIRST_FAIL: item #$idx '$name' failed"
    }
}

# ============================================================
# Run one regression item
# ============================================================
proc run_reg_item {name setup_body} {
    global REG_TOTAL REG_PASS REG_FAIL

    incr REG_TOTAL
    set item_idx $REG_TOTAL

    puts "\n============================================================"
    puts "\[REGRESSION\] START #$item_idx: $name"
    puts "============================================================"

    clear_uvm_run_vars

    catch {quit -sim -f}

    uplevel 1 $setup_body

    set run_status [catch {do run_uvm.tcl} run_msg]
    set item_log [get_current_log_file]

    if {$run_status != 0} {
        puts "\[REGRESSION\]\[FAIL\] Tcl/run error in: $name"
        puts $run_msg

        record_reg_fail $item_idx $name $item_log
        incr REG_FAIL

        maybe_stop_on_first_fail $item_idx $name $item_log
        return
    }

    if {[check_uvm_log $item_log]} {
        puts "\[REGRESSION\]\[PASS\] $name"
        record_reg_pass $item_idx $name $item_log
        incr REG_PASS
    } else {
        puts "\[REGRESSION\]\[FAIL\] $name"

        record_reg_fail $item_idx $name $item_log
        incr REG_FAIL

        maybe_stop_on_first_fail $item_idx $name $item_log
    }
}

# ============================================================
# Baseline host smoke
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
# Baseline DMA load
# ============================================================
run_reg_item "dma_load_smoke RUN_ALL" {
    set UVM_TEST ai_accel_subsys_dma_load_smoke_test
    set CASE_ID 100
    set ENABLE_RESULT_CHECK 1
    set RUN_ALL 1
}

run_reg_item "dma_load_error invalid_launch_and_recovery" {
    set UVM_TEST ai_accel_subsys_dma_load_error_test
    set ENABLE_RESULT_CHECK 0
}

# ============================================================
# Baseline host sequencing
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

run_reg_item "corner default 5->101->105->403" {
    set UVM_TEST ai_accel_subsys_corner_test
    set ENABLE_RESULT_CHECK 1
}

run_reg_item "midrun_reset abort=5 recovery=101" {
    set UVM_TEST ai_accel_subsys_midrun_reset_test
    set ENABLE_RESULT_CHECK 1

    set RESET_HOLD_CYCLES 5
    set POST_RESET_SETTLE_CYCLES 5

    set EXTRA_PLUSARGS "+ABORT_CASE_ID=5 +RECOVERY_CASE_ID=101 +RESET_TRIGGER_CYCLES_AFTER_BUSY=8"
}

# ============================================================
# Baseline stress / frontend paths
# ============================================================
run_reg_item "dma_load_stress 8 jobs" {
    set UVM_TEST ai_accel_subsys_dma_load_stress_test
    set ENABLE_RESULT_CHECK 1

    set STRESS_JOB_COUNT 8
    set STRESS_SEED 20260502
    set STRESS_RANDOM 1
    set STRESS_GAP_CYCLES 10
}

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

run_reg_item "dma_store_smoke RUN_ALL" {
    set UVM_TEST ai_accel_subsys_dma_store_smoke_test
    set ENABLE_RESULT_CHECK 1
    set RUN_ALL 1
}

run_reg_item "dma_store_error default" {
    set UVM_TEST ai_accel_subsys_dma_store_error_test
    set ENABLE_RESULT_CHECK 0
}

run_reg_item "dma_load_store_stress 8 jobs" {
    set UVM_TEST ai_accel_subsys_dma_load_store_stress_test
    set ENABLE_RESULT_CHECK 1

    set STORE_STRESS_JOB_COUNT 8
    set STORE_STRESS_SEED 20260502
    set STORE_STRESS_RANDOM 1
    set STORE_STRESS_GAP_CYCLES 10
}

run_reg_item "axis_stream_preload_smoke_run_all" {
    set UVM_TEST ai_accel_subsys_axis_stream_preload_smoke_test
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 100
    set RUN_ALL 1
}

run_reg_item "axis_stream_preload_error_recovery" {
    set UVM_TEST ai_accel_subsys_axis_stream_preload_error_test
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 100
}

run_reg_item "axis_stream_load_store_stress 8 jobs" {
    set UVM_TEST ai_accel_subsys_axis_stream_load_store_stress_test
    set ENABLE_RESULT_CHECK 1

    set AXIS_STRESS_JOB_COUNT 8
    set AXIS_STRESS_SEED 20260502
    set AXIS_STRESS_RANDOM 1
    set AXIS_STRESS_GAP_CYCLES 10
}

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

run_reg_item "direct_stream_error_recovery" {
    set UVM_TEST ai_accel_subsys_direct_stream_error_test
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 100
}

run_reg_item "direct_stream_smoke_run_all" {
    set UVM_TEST ai_accel_subsys_direct_stream_smoke_test
    set ENABLE_RESULT_CHECK 1
    set RUN_ALL 1
}

run_reg_item "direct_stream_load_store_stress" {
    set UVM_TEST ai_accel_subsys_direct_stream_load_store_stress_test
    set ENABLE_RESULT_CHECK 1

    set DS_STRESS_JOB_COUNT 8
    set DS_STRESS_SEED 20260502
    set DS_STRESS_RANDOM 1
    set DS_STRESS_GAP_CYCLES 10
}

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
# Performance and helper fallback
# ============================================================
run_reg_item "perf_counter_smoke" {
    set UVM_TEST ai_accel_subsys_perf_counter_smoke_test
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 100
    set RUN_ALL 1
}

run_reg_item "perf_profile" {
    set UVM_TEST ai_accel_subsys_perf_profile_test
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 100

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14
}

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
# P2: 2-lane focused smoke
#
# Regression total through this section: 38.
# ============================================================
run_reg_item "gemm_2lane_perf_counter_smoke" {
    set UVM_TEST ai_accel_subsys_perf_counter_smoke_test
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 100
    set RUN_ALL 1

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set GEMM_MAC_LANES 2
}

run_reg_item "gemm_2lane_perf_profile" {
    set UVM_TEST ai_accel_subsys_perf_profile_test
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 100
    set RUN_ALL 0

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set GEMM_MAC_LANES 2
}

run_reg_item "gemm_2lane_direct_stream_smoke" {
    set UVM_TEST ai_accel_subsys_direct_stream_smoke_test
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 100
    set RUN_ALL 1

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set GEMM_MAC_LANES 2
}

# ============================================================
# P3: 2-lane frontend stress and CDC
#
# Covers DMA, AXI-Stream, and Direct Stream load-store paths.
# Expected total after P3: 44.
# ============================================================
run_reg_item "gemm_2lane_dma_load_store_stress" {
    set UVM_TEST ai_accel_subsys_dma_load_store_stress_test
    set ENABLE_RESULT_CHECK 1

    set STORE_STRESS_JOB_COUNT 8
    set STORE_STRESS_SEED 20260502
    set STORE_STRESS_RANDOM 1
    set STORE_STRESS_GAP_CYCLES 10

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set GEMM_MAC_LANES 2
}

run_reg_item "gemm_2lane_axis_stream_load_store_stress" {
    set UVM_TEST ai_accel_subsys_axis_stream_load_store_stress_test
    set ENABLE_RESULT_CHECK 1

    set AXIS_STRESS_JOB_COUNT 8
    set AXIS_STRESS_SEED 20260502
    set AXIS_STRESS_RANDOM 1
    set AXIS_STRESS_GAP_CYCLES 10

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set GEMM_MAC_LANES 2
}

run_reg_item "gemm_2lane_direct_stream_load_store_stress" {
    set UVM_TEST ai_accel_subsys_direct_stream_load_store_stress_test
    set ENABLE_RESULT_CHECK 1

    set DS_STRESS_JOB_COUNT 8
    set DS_STRESS_SEED 20260502
    set DS_STRESS_RANDOM 1
    set DS_STRESS_GAP_CYCLES 10

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set GEMM_MAC_LANES 2
}

run_reg_item "gemm_2lane_dma_load_store_cdc" {
    set UVM_TEST ai_accel_subsys_dma_load_store_stress_test
    set ENABLE_RESULT_CHECK 1

    set STORE_STRESS_JOB_COUNT 8
    set STORE_STRESS_SEED 20260502
    set STORE_STRESS_RANDOM 1
    set STORE_STRESS_GAP_CYCLES 10

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 13

    set GEMM_MAC_LANES 2
}

run_reg_item "gemm_2lane_axis_stream_load_store_cdc" {
    set UVM_TEST ai_accel_subsys_axis_stream_load_store_stress_test
    set ENABLE_RESULT_CHECK 1

    set AXIS_STRESS_JOB_COUNT 8
    set AXIS_STRESS_SEED 20260502
    set AXIS_STRESS_RANDOM 1
    set AXIS_STRESS_GAP_CYCLES 10

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 13

    set GEMM_MAC_LANES 2
}

run_reg_item "gemm_2lane_direct_stream_load_store_cdc" {
    set UVM_TEST ai_accel_subsys_direct_stream_load_store_stress_test
    set ENABLE_RESULT_CHECK 1

    set DS_STRESS_JOB_COUNT 8
    set DS_STRESS_SEED 20260502
    set DS_STRESS_RANDOM 1
    set DS_STRESS_GAP_CYCLES 10

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 13

    set GEMM_MAC_LANES 2
}

# ============================================================
# P4: 2-lane B-cache frontend representatives
#
# Default-clock representatives only.
# Expected total after P4: 47.
# ============================================================
run_reg_item "gemm_2lane_bcache_dma_load_store_stress" {
    set UVM_TEST ai_accel_subsys_dma_load_store_stress_test
    set ENABLE_RESULT_CHECK 1

    set STORE_STRESS_JOB_COUNT 8
    set STORE_STRESS_SEED 20260502
    set STORE_STRESS_RANDOM 1
    set STORE_STRESS_GAP_CYCLES 10

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set GEMM_MAC_LANES 2
    set GEMM_ENABLE_B_CACHE 1
    set GEMM_B_CACHE_MAX_K 4
    set GEMM_B_CACHE_MAX_N 4
}

run_reg_item "gemm_2lane_bcache_axis_stream_load_store_stress" {
    set UVM_TEST ai_accel_subsys_axis_stream_load_store_stress_test
    set ENABLE_RESULT_CHECK 1

    set AXIS_STRESS_JOB_COUNT 8
    set AXIS_STRESS_SEED 20260502
    set AXIS_STRESS_RANDOM 1
    set AXIS_STRESS_GAP_CYCLES 10

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set GEMM_MAC_LANES 2
    set GEMM_ENABLE_B_CACHE 1
    set GEMM_B_CACHE_MAX_K 4
    set GEMM_B_CACHE_MAX_N 4
}

run_reg_item "gemm_2lane_bcache_direct_stream_load_store_stress" {
    set UVM_TEST ai_accel_subsys_direct_stream_load_store_stress_test
    set ENABLE_RESULT_CHECK 1

    set DS_STRESS_JOB_COUNT 8
    set DS_STRESS_SEED 20260502
    set DS_STRESS_RANDOM 1
    set DS_STRESS_GAP_CYCLES 10

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set GEMM_MAC_LANES 2
    set GEMM_ENABLE_B_CACHE 1
    set GEMM_B_CACHE_MAX_K 4
    set GEMM_B_CACHE_MAX_N 4
}

# ============================================================
# P5: packed B-cache frontend representatives
#
# Default-clock representatives only.
# Expected total after P5: 50.
# ============================================================
run_reg_item "gemm_2lane_packed_bcache_dma_load_store_stress" {
    set UVM_TEST ai_accel_subsys_dma_load_store_stress_test
    set ENABLE_RESULT_CHECK 1

    set STORE_STRESS_JOB_COUNT 8
    set STORE_STRESS_SEED 20260502
    set STORE_STRESS_RANDOM 1
    set STORE_STRESS_GAP_CYCLES 10

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set GEMM_MAC_LANES 2
    set GEMM_ENABLE_B_CACHE 1
    set GEMM_B_CACHE_MAX_K 4
    set GEMM_B_CACHE_MAX_N 4
    set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
}

run_reg_item "gemm_2lane_packed_bcache_axis_stream_load_store_stress" {
    set UVM_TEST ai_accel_subsys_axis_stream_load_store_stress_test
    set ENABLE_RESULT_CHECK 1

    set AXIS_STRESS_JOB_COUNT 8
    set AXIS_STRESS_SEED 20260502
    set AXIS_STRESS_RANDOM 1
    set AXIS_STRESS_GAP_CYCLES 10

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set GEMM_MAC_LANES 2
    set GEMM_ENABLE_B_CACHE 1
    set GEMM_B_CACHE_MAX_K 4
    set GEMM_B_CACHE_MAX_N 4
    set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
}

run_reg_item "gemm_2lane_packed_bcache_direct_stream_load_store_stress" {
    set UVM_TEST ai_accel_subsys_direct_stream_load_store_stress_test
    set ENABLE_RESULT_CHECK 1

    set DS_STRESS_JOB_COUNT 8
    set DS_STRESS_SEED 20260502
    set DS_STRESS_RANDOM 1
    set DS_STRESS_GAP_CYCLES 10

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set GEMM_MAC_LANES 2
    set GEMM_ENABLE_B_CACHE 1
    set GEMM_B_CACHE_MAX_K 4
    set GEMM_B_CACHE_MAX_N 4
    set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
}

# ============================================================
# P6: A-row cache focused and frontend representatives
#
# Covers perf/profile plus DMA, AXI-Stream, and Direct Stream paths.
# Expected total after P6: 56.
# ============================================================
run_reg_item "gemm_2lane_arow_cache_perf_counter_smoke" {
    set UVM_TEST ai_accel_subsys_perf_counter_smoke_test
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 100
    set RUN_ALL 1

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set GEMM_MAC_LANES 2
    set GEMM_ENABLE_B_CACHE 1
    set GEMM_B_CACHE_MAX_K 4
    set GEMM_B_CACHE_MAX_N 4
    set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
    set GEMM_ENABLE_A_ROW_CACHE 1
    set GEMM_A_ROW_CACHE_MAX_K 4
}

run_reg_item "gemm_2lane_arow_cache_perf_profile" {
    set UVM_TEST ai_accel_subsys_perf_profile_test
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 100
    set RUN_ALL 0

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set GEMM_MAC_LANES 2
    set GEMM_ENABLE_B_CACHE 1
    set GEMM_B_CACHE_MAX_K 4
    set GEMM_B_CACHE_MAX_N 4
    set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
    set GEMM_ENABLE_A_ROW_CACHE 1
    set GEMM_A_ROW_CACHE_MAX_K 4
}

run_reg_item "gemm_2lane_packed_bcache_arow_direct_stream_load_store_stress" {
    set UVM_TEST ai_accel_subsys_direct_stream_load_store_stress_test
    set ENABLE_RESULT_CHECK 1

    set DS_STRESS_JOB_COUNT 8
    set DS_STRESS_SEED 20260502
    set DS_STRESS_RANDOM 1
    set DS_STRESS_GAP_CYCLES 10

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set GEMM_MAC_LANES 2
    set GEMM_ENABLE_B_CACHE 1
    set GEMM_B_CACHE_MAX_K 4
    set GEMM_B_CACHE_MAX_N 4
    set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
    set GEMM_ENABLE_A_ROW_CACHE 1
    set GEMM_A_ROW_CACHE_MAX_K 4
}

run_reg_item "gemm_2lane_packed_bcache_arow_direct_stream_load_store_cdc_10_13" {
    set UVM_TEST ai_accel_subsys_direct_stream_load_store_stress_test
    set ENABLE_RESULT_CHECK 1

    set DS_STRESS_JOB_COUNT 8
    set DS_STRESS_SEED 20260502
    set DS_STRESS_RANDOM 1
    set DS_STRESS_GAP_CYCLES 10

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 13

    set GEMM_MAC_LANES 2
    set GEMM_ENABLE_B_CACHE 1
    set GEMM_B_CACHE_MAX_K 4
    set GEMM_B_CACHE_MAX_N 4
    set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
    set GEMM_ENABLE_A_ROW_CACHE 1
    set GEMM_A_ROW_CACHE_MAX_K 4
}

run_reg_item "gemm_2lane_packed_bcache_arow_dma_load_store_stress" {
    set UVM_TEST ai_accel_subsys_dma_load_store_stress_test
    set ENABLE_RESULT_CHECK 1

    set STORE_STRESS_JOB_COUNT 8
    set STORE_STRESS_SEED 20260502
    set STORE_STRESS_RANDOM 1
    set STORE_STRESS_GAP_CYCLES 10

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set GEMM_MAC_LANES 2
    set GEMM_ENABLE_B_CACHE 1
    set GEMM_B_CACHE_MAX_K 4
    set GEMM_B_CACHE_MAX_N 4
    set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
    set GEMM_ENABLE_A_ROW_CACHE 1
    set GEMM_A_ROW_CACHE_MAX_K 4
}

run_reg_item "gemm_2lane_packed_bcache_arow_axis_stream_load_store_stress" {
    set UVM_TEST ai_accel_subsys_axis_stream_load_store_stress_test
    set ENABLE_RESULT_CHECK 1

    set AXIS_STRESS_JOB_COUNT 8
    set AXIS_STRESS_SEED 20260502
    set AXIS_STRESS_RANDOM 1
    set AXIS_STRESS_GAP_CYCLES 10

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set GEMM_MAC_LANES 2
    set GEMM_ENABLE_B_CACHE 1
    set GEMM_B_CACHE_MAX_K 4
    set GEMM_B_CACHE_MAX_N 4
    set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
    set GEMM_ENABLE_A_ROW_CACHE 1
    set GEMM_A_ROW_CACHE_MAX_K 4
}

# ============================================================
# P7: packed A-row preload frontend representatives
#
# Default-clock representatives only.
# Expected total after P7: 59.
# ============================================================
run_reg_item "gemm_2lane_packed_bcache_packed_arow_dma_load_store_stress" {
    set UVM_TEST ai_accel_subsys_dma_load_store_stress_test
    set ENABLE_RESULT_CHECK 1

    set STORE_STRESS_JOB_COUNT 8
    set STORE_STRESS_SEED 20260502
    set STORE_STRESS_RANDOM 1
    set STORE_STRESS_GAP_CYCLES 10

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set GEMM_MAC_LANES 2
    set GEMM_ENABLE_B_CACHE 1
    set GEMM_B_CACHE_MAX_K 4
    set GEMM_B_CACHE_MAX_N 4
    set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
    set GEMM_ENABLE_A_ROW_CACHE 1
    set GEMM_A_ROW_CACHE_MAX_K 4
    set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1
}

run_reg_item "gemm_2lane_packed_bcache_packed_arow_axis_stream_load_store_stress" {
    set UVM_TEST ai_accel_subsys_axis_stream_load_store_stress_test
    set ENABLE_RESULT_CHECK 1

    set AXIS_STRESS_JOB_COUNT 8
    set AXIS_STRESS_SEED 20260502
    set AXIS_STRESS_RANDOM 1
    set AXIS_STRESS_GAP_CYCLES 10

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set GEMM_MAC_LANES 2
    set GEMM_ENABLE_B_CACHE 1
    set GEMM_B_CACHE_MAX_K 4
    set GEMM_B_CACHE_MAX_N 4
    set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
    set GEMM_ENABLE_A_ROW_CACHE 1
    set GEMM_A_ROW_CACHE_MAX_K 4
    set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1
}

run_reg_item "gemm_2lane_packed_bcache_packed_arow_direct_stream_load_store_stress" {
    set UVM_TEST ai_accel_subsys_direct_stream_load_store_stress_test
    set ENABLE_RESULT_CHECK 1

    set DS_STRESS_JOB_COUNT 8
    set DS_STRESS_SEED 20260502
    set DS_STRESS_RANDOM 1
    set DS_STRESS_GAP_CYCLES 10

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set GEMM_MAC_LANES 2
    set GEMM_ENABLE_B_CACHE 1
    set GEMM_B_CACHE_MAX_K 4
    set GEMM_B_CACHE_MAX_N 4
    set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
    set GEMM_ENABLE_A_ROW_CACHE 1
    set GEMM_A_ROW_CACHE_MAX_K 4
    set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1
}

# ============================================================
# P8: 4-lane full-cache frontend representatives
#
# Enables the cache-backed true 4-lane MAC path.
# Expected total after P8: 62.
# ============================================================
run_reg_item "gemm_4lane_fullcache_dma_load_store_stress" {
    set UVM_TEST ai_accel_subsys_dma_load_store_stress_test
    set ENABLE_RESULT_CHECK 1

    set STORE_STRESS_JOB_COUNT 8
    set STORE_STRESS_SEED 20260502
    set STORE_STRESS_RANDOM 1
    set STORE_STRESS_GAP_CYCLES 10

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set GEMM_MAC_LANES 4
    set GEMM_ENABLE_B_CACHE 1
    set GEMM_B_CACHE_MAX_K 4
    set GEMM_B_CACHE_MAX_N 4
    set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
    set GEMM_ENABLE_A_ROW_CACHE 1
    set GEMM_A_ROW_CACHE_MAX_K 4
    set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1
}

run_reg_item "gemm_4lane_fullcache_axis_stream_load_store_stress" {
    set UVM_TEST ai_accel_subsys_axis_stream_load_store_stress_test
    set ENABLE_RESULT_CHECK 1

    set AXIS_STRESS_JOB_COUNT 8
    set AXIS_STRESS_SEED 20260502
    set AXIS_STRESS_RANDOM 1
    set AXIS_STRESS_GAP_CYCLES 10

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set GEMM_MAC_LANES 4
    set GEMM_ENABLE_B_CACHE 1
    set GEMM_B_CACHE_MAX_K 4
    set GEMM_B_CACHE_MAX_N 4
    set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
    set GEMM_ENABLE_A_ROW_CACHE 1
    set GEMM_A_ROW_CACHE_MAX_K 4
    set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1
}

run_reg_item "gemm_4lane_fullcache_direct_stream_load_store_stress" {
    set UVM_TEST ai_accel_subsys_direct_stream_load_store_stress_test
    set ENABLE_RESULT_CHECK 1

    set DS_STRESS_JOB_COUNT 8
    set DS_STRESS_SEED 20260502
    set DS_STRESS_RANDOM 1
    set DS_STRESS_GAP_CYCLES 10

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set GEMM_MAC_LANES 4
    set GEMM_ENABLE_B_CACHE 1
    set GEMM_B_CACHE_MAX_K 4
    set GEMM_B_CACHE_MAX_N 4
    set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
    set GEMM_ENABLE_A_ROW_CACHE 1
    set GEMM_A_ROW_CACHE_MAX_K 4
    set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1
}

# ============================================================
# P9: scaled 4-lane cache representatives
#
# Forced larger-dimension CASE_ID per frontend path.
# Expected total after P9: 65.
# ============================================================
run_reg_item "gemm_4lane_scaled_fullcache_dma_load_store_case190" {
    set UVM_TEST ai_accel_subsys_dma_load_store_stress_test
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 190

    set STORE_STRESS_JOB_COUNT 1
    set STORE_STRESS_SEED 20260502
    set STORE_STRESS_RANDOM 0
    set STORE_STRESS_GAP_CYCLES 10

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set GEMM_MAC_LANES 4
    set GEMM_ENABLE_B_CACHE 1
    set GEMM_B_CACHE_MAX_K 8
    set GEMM_B_CACHE_MAX_N 8
    set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
    set GEMM_ENABLE_A_ROW_CACHE 1
    set GEMM_A_ROW_CACHE_MAX_K 8
    set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1
}

run_reg_item "gemm_4lane_scaled_fullcache_axis_stream_load_store_case191" {
    set UVM_TEST ai_accel_subsys_axis_stream_load_store_stress_test
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 191

    set AXIS_STRESS_JOB_COUNT 1
    set AXIS_STRESS_SEED 20260502
    set AXIS_STRESS_RANDOM 0
    set AXIS_STRESS_GAP_CYCLES 10

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set GEMM_MAC_LANES 4
    set GEMM_ENABLE_B_CACHE 1
    set GEMM_B_CACHE_MAX_K 8
    set GEMM_B_CACHE_MAX_N 8
    set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
    set GEMM_ENABLE_A_ROW_CACHE 1
    set GEMM_A_ROW_CACHE_MAX_K 8
    set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1
}

run_reg_item "gemm_4lane_scaled_fullcache_direct_stream_load_store_case192" {
    set UVM_TEST ai_accel_subsys_direct_stream_load_store_stress_test
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 192

    set DS_STRESS_JOB_COUNT 1
    set DS_STRESS_SEED 20260502
    set DS_STRESS_RANDOM 0
    set DS_STRESS_GAP_CYCLES 10

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set GEMM_MAC_LANES 4
    set GEMM_ENABLE_B_CACHE 1
    set GEMM_B_CACHE_MAX_K 8
    set GEMM_B_CACHE_MAX_N 8
    set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
    set GEMM_ENABLE_A_ROW_CACHE 1
    set GEMM_A_ROW_CACHE_MAX_K 8
    set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1
}

# ============================================================
# P10B: K-tiling parameter plumbing
#
# No full-regression item here; total remains 65.
# ============================================================

# ============================================================
# P10F: K-tiling frontend representatives
#
# Forced CASE_ID=195, dim=(4,4,16), two K=8 tiles.
# Expected total after P10: 68.
# ============================================================
run_reg_item "gemm_4lane_ktiling_dma_load_store_case195" {
    set UVM_TEST ai_accel_subsys_dma_load_store_stress_test
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 195

    set STORE_STRESS_JOB_COUNT 1
    set STORE_STRESS_SEED 20260502
    set STORE_STRESS_RANDOM 0
    set STORE_STRESS_GAP_CYCLES 10

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set GEMM_MAC_LANES 4
    set GEMM_ENABLE_B_CACHE 1
    set GEMM_B_CACHE_MAX_K 8
    set GEMM_B_CACHE_MAX_N 8
    set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
    set GEMM_ENABLE_A_ROW_CACHE 1
    set GEMM_A_ROW_CACHE_MAX_K 8
    set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1

    set GEMM_ENABLE_K_TILING 1
    set GEMM_K_TILE_SIZE 8
}

run_reg_item "gemm_4lane_ktiling_axis_stream_load_store_case195" {
    set UVM_TEST ai_accel_subsys_axis_stream_load_store_stress_test
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 195

    set AXIS_STRESS_JOB_COUNT 1
    set AXIS_STRESS_SEED 20260502
    set AXIS_STRESS_RANDOM 0
    set AXIS_STRESS_GAP_CYCLES 10

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set GEMM_MAC_LANES 4
    set GEMM_ENABLE_B_CACHE 1
    set GEMM_B_CACHE_MAX_K 8
    set GEMM_B_CACHE_MAX_N 8
    set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
    set GEMM_ENABLE_A_ROW_CACHE 1
    set GEMM_A_ROW_CACHE_MAX_K 8
    set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1

    set GEMM_ENABLE_K_TILING 1
    set GEMM_K_TILE_SIZE 8
}

run_reg_item "gemm_4lane_ktiling_direct_stream_load_store_case195" {
    set UVM_TEST ai_accel_subsys_direct_stream_load_store_stress_test
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 195

    set DS_STRESS_JOB_COUNT 1
    set DS_STRESS_SEED 20260502
    set DS_STRESS_RANDOM 0
    set DS_STRESS_GAP_CYCLES 10

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set GEMM_MAC_LANES 4
    set GEMM_ENABLE_B_CACHE 1
    set GEMM_B_CACHE_MAX_K 8
    set GEMM_B_CACHE_MAX_N 8
    set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
    set GEMM_ENABLE_A_ROW_CACHE 1
    set GEMM_A_ROW_CACHE_MAX_K 8
    set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1

    set GEMM_ENABLE_K_TILING 1
    set GEMM_K_TILE_SIZE 8
}

# ============================================================
# P11B: N-tiling parameter plumbing
#
# No full-regression item here; total remains 68.
# ============================================================

# ============================================================
# P11G: N-tiling frontend representatives
#
# Forced CASE_ID=200, combined K/N tiling.
# Expected total after P11: 71.
# ============================================================
run_reg_item "gemm_4lane_ntiling_dma_load_store_case200" {
    set UVM_TEST ai_accel_subsys_dma_load_store_stress_test
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 200

    set STORE_STRESS_JOB_COUNT 1
    set STORE_STRESS_SEED 20260502
    set STORE_STRESS_RANDOM 0
    set STORE_STRESS_GAP_CYCLES 10

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set SMOKE_DONE_TIMEOUT_CYCLES 100000

    set GEMM_MAC_LANES 4
    set GEMM_ENABLE_B_CACHE 1
    set GEMM_B_CACHE_MAX_K 8
    set GEMM_B_CACHE_MAX_N 8
    set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
    set GEMM_ENABLE_A_ROW_CACHE 1
    set GEMM_A_ROW_CACHE_MAX_K 8
    set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1

    set GEMM_ENABLE_K_TILING 1
    set GEMM_K_TILE_SIZE 8
    set GEMM_ENABLE_N_TILING 1
    set GEMM_N_TILE_SIZE 8
}

run_reg_item "gemm_4lane_ntiling_axis_stream_load_store_case200" {
    set UVM_TEST ai_accel_subsys_axis_stream_load_store_stress_test
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 200

    set AXIS_STRESS_JOB_COUNT 1
    set AXIS_STRESS_SEED 20260502
    set AXIS_STRESS_RANDOM 0
    set AXIS_STRESS_GAP_CYCLES 10

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set SMOKE_DONE_TIMEOUT_CYCLES 100000

    set GEMM_MAC_LANES 4
    set GEMM_ENABLE_B_CACHE 1
    set GEMM_B_CACHE_MAX_K 8
    set GEMM_B_CACHE_MAX_N 8
    set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
    set GEMM_ENABLE_A_ROW_CACHE 1
    set GEMM_A_ROW_CACHE_MAX_K 8
    set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1

    set GEMM_ENABLE_K_TILING 1
    set GEMM_K_TILE_SIZE 8
    set GEMM_ENABLE_N_TILING 1
    set GEMM_N_TILE_SIZE 8
}

run_reg_item "gemm_4lane_ntiling_direct_stream_load_store_case200" {
    set UVM_TEST ai_accel_subsys_direct_stream_load_store_stress_test
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 200

    set DS_STRESS_JOB_COUNT 1
    set DS_STRESS_SEED 20260502
    set DS_STRESS_RANDOM 0
    set DS_STRESS_GAP_CYCLES 10

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set SMOKE_DONE_TIMEOUT_CYCLES 100000

    set GEMM_MAC_LANES 4
    set GEMM_ENABLE_B_CACHE 1
    set GEMM_B_CACHE_MAX_K 8
    set GEMM_B_CACHE_MAX_N 8
    set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
    set GEMM_ENABLE_A_ROW_CACHE 1
    set GEMM_A_ROW_CACHE_MAX_K 8
    set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1

    set GEMM_ENABLE_K_TILING 1
    set GEMM_K_TILE_SIZE 8
    set GEMM_ENABLE_N_TILING 1
    set GEMM_N_TILE_SIZE 8
}

# ============================================================
# P12B: M-tiling parameter plumbing
#
# No full-regression item here; total remains 71.
# ============================================================

# ============================================================
# P12G: M-tiling frontend representatives
#
# Forced CASE_ID=207, combined M/N/K tiling with ragged tails.
# Expected total after P12: 74.
# ============================================================
run_reg_item "gemm_4lane_mtiling_dma_load_store_case207" {
    set UVM_TEST ai_accel_subsys_dma_load_store_stress_test
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 207

    set STORE_STRESS_JOB_COUNT 1
    set STORE_STRESS_SEED 20260502
    set STORE_STRESS_RANDOM 0
    set STORE_STRESS_GAP_CYCLES 10

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set SMOKE_DONE_TIMEOUT_CYCLES 200000

    set GEMM_MAC_LANES 4
    set GEMM_ENABLE_B_CACHE 1
    set GEMM_B_CACHE_MAX_K 8
    set GEMM_B_CACHE_MAX_N 8
    set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
    set GEMM_ENABLE_A_ROW_CACHE 1
    set GEMM_A_ROW_CACHE_MAX_K 8
    set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1

    set GEMM_ENABLE_K_TILING 1
    set GEMM_K_TILE_SIZE 8
    set GEMM_ENABLE_N_TILING 1
    set GEMM_N_TILE_SIZE 8
    set GEMM_ENABLE_M_TILING 1
    set GEMM_M_TILE_SIZE 2
}

run_reg_item "gemm_4lane_mtiling_axis_stream_load_store_case207" {
    set UVM_TEST ai_accel_subsys_axis_stream_load_store_stress_test
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 207

    set AXIS_STRESS_JOB_COUNT 1
    set AXIS_STRESS_SEED 20260502
    set AXIS_STRESS_RANDOM 0
    set AXIS_STRESS_GAP_CYCLES 10

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set SMOKE_DONE_TIMEOUT_CYCLES 200000

    set GEMM_MAC_LANES 4
    set GEMM_ENABLE_B_CACHE 1
    set GEMM_B_CACHE_MAX_K 8
    set GEMM_B_CACHE_MAX_N 8
    set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
    set GEMM_ENABLE_A_ROW_CACHE 1
    set GEMM_A_ROW_CACHE_MAX_K 8
    set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1

    set GEMM_ENABLE_K_TILING 1
    set GEMM_K_TILE_SIZE 8
    set GEMM_ENABLE_N_TILING 1
    set GEMM_N_TILE_SIZE 8
    set GEMM_ENABLE_M_TILING 1
    set GEMM_M_TILE_SIZE 2
}

run_reg_item "gemm_4lane_mtiling_direct_stream_load_store_case207" {
    set UVM_TEST ai_accel_subsys_direct_stream_load_store_stress_test
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 207

    set DS_STRESS_JOB_COUNT 1
    set DS_STRESS_SEED 20260502
    set DS_STRESS_RANDOM 0
    set DS_STRESS_GAP_CYCLES 10

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set SMOKE_DONE_TIMEOUT_CYCLES 200000

    set GEMM_MAC_LANES 4
    set GEMM_ENABLE_B_CACHE 1
    set GEMM_B_CACHE_MAX_K 8
    set GEMM_B_CACHE_MAX_N 8
    set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
    set GEMM_ENABLE_A_ROW_CACHE 1
    set GEMM_A_ROW_CACHE_MAX_K 8
    set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1

    set GEMM_ENABLE_K_TILING 1
    set GEMM_K_TILE_SIZE 8
    set GEMM_ENABLE_N_TILING 1
    set GEMM_N_TILE_SIZE 8
    set GEMM_ENABLE_M_TILING 1
    set GEMM_M_TILE_SIZE 2
}

# ============================================================
# P13B: C RMW parameter plumbing
#
# Adds GEMM_ENABLE_C_RMW_ACCUM and ACCUMULATE_ENABLE.
# No full-regression item here; total remains 74.
# ============================================================

# ============================================================
# P13D: C RMW focused DUT recipes
#
# Two-job partial-K recipes: job0 direct write, job1 RMW accumulate.
# ACCUMULATE_ENABLE stays 0; the test drives per-job control through UVM.
# Expected total after P13D: 79.
# ============================================================
run_reg_item "p13d_c_rmw_accum_case208" {
    set UVM_TEST ai_accel_subsys_c_rmw_accum_dut_test
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 208

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set SMOKE_DONE_TIMEOUT_CYCLES 300000

    set GEMM_ENABLE_C_RMW_ACCUM 1
    set ACCUMULATE_ENABLE 0
}

run_reg_item "p13d_c_rmw_accum_case209" {
    set UVM_TEST ai_accel_subsys_c_rmw_accum_dut_test
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 209

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set SMOKE_DONE_TIMEOUT_CYCLES 300000

    set GEMM_ENABLE_C_RMW_ACCUM 1
    set ACCUMULATE_ENABLE 0
}

run_reg_item "p13d_c_rmw_accum_case210" {
    set UVM_TEST ai_accel_subsys_c_rmw_accum_dut_test
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 210

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set SMOKE_DONE_TIMEOUT_CYCLES 300000

    set GEMM_ENABLE_C_RMW_ACCUM 1
    set ACCUMULATE_ENABLE 0
}

run_reg_item "p13d_c_rmw_accum_case211" {
    set UVM_TEST ai_accel_subsys_c_rmw_accum_dut_test
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 211

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set SMOKE_DONE_TIMEOUT_CYCLES 300000

    set GEMM_ENABLE_C_RMW_ACCUM 1
    set ACCUMULATE_ENABLE 0
}

run_reg_item "p13d_c_rmw_accum_case212" {
    set UVM_TEST ai_accel_subsys_c_rmw_accum_dut_test
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 212

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set SMOKE_DONE_TIMEOUT_CYCLES 300000

    set GEMM_ENABLE_C_RMW_ACCUM 1
    set ACCUMULATE_ENABLE 0
}

# ============================================================
# P13G: C RMW frontend representatives
#
# Forced CASE_ID=211 on DMA, AXI-Stream, and Direct Stream load-store paths.
# Uses the full P12 cache/tile stack plus GEMM_ENABLE_C_RMW_ACCUM=1.
# ACCUMULATE_ENABLE stays 0; the P13 recipe drives per-job control.
# Expected total after P13G: 82.
# ============================================================
run_reg_item "gemm_4lane_c_rmw_dma_load_store_case211" {
    set UVM_TEST ai_accel_subsys_dma_load_store_stress_test
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 211

    set STORE_STRESS_JOB_COUNT 1
    set STORE_STRESS_SEED 20260502
    set STORE_STRESS_RANDOM 0
    set STORE_STRESS_GAP_CYCLES 10

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set SMOKE_DONE_TIMEOUT_CYCLES 300000

    set GEMM_MAC_LANES 4
    set GEMM_ENABLE_B_CACHE 1
    set GEMM_B_CACHE_MAX_K 8
    set GEMM_B_CACHE_MAX_N 8
    set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
    set GEMM_ENABLE_A_ROW_CACHE 1
    set GEMM_A_ROW_CACHE_MAX_K 8
    set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1

    set GEMM_ENABLE_K_TILING 1
    set GEMM_K_TILE_SIZE 8
    set GEMM_ENABLE_N_TILING 1
    set GEMM_N_TILE_SIZE 8
    set GEMM_ENABLE_M_TILING 1
    set GEMM_M_TILE_SIZE 2

    set GEMM_ENABLE_C_RMW_ACCUM 1
    set ACCUMULATE_ENABLE 0
}

run_reg_item "gemm_4lane_c_rmw_axis_stream_load_store_case211" {
    set UVM_TEST ai_accel_subsys_axis_stream_load_store_stress_test
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 211

    set AXIS_STRESS_JOB_COUNT 1
    set AXIS_STRESS_SEED 20260502
    set AXIS_STRESS_RANDOM 0
    set AXIS_STRESS_GAP_CYCLES 10

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set SMOKE_DONE_TIMEOUT_CYCLES 300000

    set GEMM_MAC_LANES 4
    set GEMM_ENABLE_B_CACHE 1
    set GEMM_B_CACHE_MAX_K 8
    set GEMM_B_CACHE_MAX_N 8
    set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
    set GEMM_ENABLE_A_ROW_CACHE 1
    set GEMM_A_ROW_CACHE_MAX_K 8
    set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1

    set GEMM_ENABLE_K_TILING 1
    set GEMM_K_TILE_SIZE 8
    set GEMM_ENABLE_N_TILING 1
    set GEMM_N_TILE_SIZE 8
    set GEMM_ENABLE_M_TILING 1
    set GEMM_M_TILE_SIZE 2

    set GEMM_ENABLE_C_RMW_ACCUM 1
    set ACCUMULATE_ENABLE 0
}

run_reg_item "gemm_4lane_c_rmw_direct_stream_load_store_case211" {
    set UVM_TEST ai_accel_subsys_direct_stream_load_store_stress_test
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 211

    set DS_STRESS_JOB_COUNT 1
    set DS_STRESS_SEED 20260502
    set DS_STRESS_RANDOM 0
    set DS_STRESS_GAP_CYCLES 10

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set SMOKE_DONE_TIMEOUT_CYCLES 300000

    set GEMM_MAC_LANES 4
    set GEMM_ENABLE_B_CACHE 1
    set GEMM_B_CACHE_MAX_K 8
    set GEMM_B_CACHE_MAX_N 8
    set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
    set GEMM_ENABLE_A_ROW_CACHE 1
    set GEMM_A_ROW_CACHE_MAX_K 8
    set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1

    set GEMM_ENABLE_K_TILING 1
    set GEMM_K_TILE_SIZE 8
    set GEMM_ENABLE_N_TILING 1
    set GEMM_N_TILE_SIZE 8
    set GEMM_ENABLE_M_TILING 1
    set GEMM_M_TILE_SIZE 2

    set GEMM_ENABLE_C_RMW_ACCUM 1
    set ACCUMULATE_ENABLE 0
}


# ============================================================
# P14E: CSR-controlled host-primary GEMM smoke
#
# The CSR-wrapper subsystem top is selected explicitly.  These
# items use the host AXI agent for scratchpad setup/readback and
# the AXI-Lite CSR path for GEMM configuration/start/done polling.
# Expected total after P14E: 84.
# ============================================================
run_reg_item "csr_host_smoke_case100" {
    set UVM_TEST ai_accel_subsys_csr_smoke_test
    set UVM_TOP ai_accel_subsys_csr_uvm_top
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 100

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14
}

run_reg_item "csr_host_smoke_case102" {
    set UVM_TEST ai_accel_subsys_csr_smoke_test
    set UVM_TOP ai_accel_subsys_csr_uvm_top
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 102

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14
}

# ============================================================
# P14F1: CSR-controlled DMA load + GEMM + DMA store smoke
#
# The CSR-wrapper subsystem top is selected explicitly.  These
# items preload A/B through CSR-controlled DMA load commands,
# launch GEMM through CSR, store C through CSR-controlled DMA
# store, and compare the DMA destination memory against the
# software reference.
# Expected total after P14F1: 86.
# ============================================================
run_reg_item "csr_dma_load_store_case100" {
    set UVM_TEST ai_accel_subsys_csr_dma_load_store_smoke_test
    set UVM_TOP ai_accel_subsys_csr_uvm_top
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 100

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14
}

run_reg_item "csr_dma_load_store_case102" {
    set UVM_TEST ai_accel_subsys_csr_dma_load_store_smoke_test
    set UVM_TOP ai_accel_subsys_csr_uvm_top
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 102

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14
}

# ============================================================
# P14F2: CSR-controlled AXI-Stream preload + GEMM + DMA store smoke
#
# The CSR-wrapper subsystem top is selected explicitly.  These
# items preload A/B through CSR-controlled AXI-Stream preload
# commands, launch GEMM through CSR, store C through
# CSR-controlled DMA store, and compare the DMA destination
# memory against the software reference.
# Expected total after P14F2: 88.
# ============================================================
run_reg_item "csr_axis_stream_load_store_case100" {
    set UVM_TEST ai_accel_subsys_csr_axis_stream_load_store_smoke_test
    set UVM_TOP ai_accel_subsys_csr_uvm_top
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 100

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14
}

run_reg_item "csr_axis_stream_load_store_case102" {
    set UVM_TEST ai_accel_subsys_csr_axis_stream_load_store_smoke_test
    set UVM_TOP ai_accel_subsys_csr_uvm_top
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 102

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14
}

# ============================================================
# P14F3: CSR-controlled Direct Stream preload + GEMM + DMA store smoke
#
# The CSR-wrapper subsystem top is selected explicitly.  These
# items preload A/B through CSR-controlled Direct Stream preload
# commands into the GEMM operand buffers, launch GEMM through CSR
# with GEMM input stream mode enabled, store C through
# CSR-controlled DMA store, and compare the DMA destination
# memory against the software reference.
# Expected total after P14F3: 90.
# ============================================================
run_reg_item "csr_direct_stream_load_store_case100" {
    set UVM_TEST ai_accel_subsys_csr_direct_stream_load_store_smoke_test
    set UVM_TOP ai_accel_subsys_csr_uvm_top
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 100

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14
}

run_reg_item "csr_direct_stream_load_store_case102" {
    set UVM_TEST ai_accel_subsys_csr_direct_stream_load_store_smoke_test
    set UVM_TOP ai_accel_subsys_csr_uvm_top
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 102

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14
}

# ============================================================
# P15C: CSR job-level DMA load + GEMM + DMA store smoke
#
# The CSR-wrapper subsystem top is selected explicitly.  These
# items program one CSR job descriptor, issue START_JOB, let the
# hardware job sequencer run DMA load A, DMA load B, GEMM, and
# DMA store, then compare the DMA destination memory against the
# software reference.
# Expected total after P15C: 92.
# ============================================================
run_reg_item "csr_job_dma_load_store_case100" {
    set UVM_TEST ai_accel_subsys_csr_job_dma_load_store_smoke_test
    set UVM_TOP ai_accel_subsys_csr_uvm_top
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 100

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14
}

run_reg_item "csr_job_dma_load_store_case102" {
    set UVM_TEST ai_accel_subsys_csr_job_dma_load_store_smoke_test
    set UVM_TOP ai_accel_subsys_csr_uvm_top
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 102

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14
}


# ============================================================
# P15D: CSR job reject / busy / clear handling smoke
#
# The CSR-wrapper subsystem top is selected explicitly.  This
# item validates job-level descriptor reject conditions, START_JOB
# while job_busy, P14 manual command reject during a P15 job, sticky
# reject status, cleanup commands, and a valid job completion after
# benign reject injection.
# Expected total after P15D: 93.
# ============================================================
run_reg_item "csr_job_reject_error_case102" {
    set UVM_TEST ai_accel_subsys_csr_job_reject_error_test
    set UVM_TOP ai_accel_subsys_csr_uvm_top
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 102

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14
}


# ============================================================
# P15E: CSR job-level frontend-mode smoke
#
# The CSR-wrapper subsystem top is selected explicitly.  These
# items program one CSR job descriptor with a non-DMA frontend
# input mode, issue START_JOB, let the hardware job sequencer run
# AXI-Stream or Direct Stream preload for A/B, GEMM, and DMA store,
# then compare the DMA destination memory against the software
# reference.
# Expected total after P15E: 95.
# ============================================================
run_reg_item "csr_job_axis_stream_load_store_case102" {
    set UVM_TEST ai_accel_subsys_csr_job_axis_stream_load_store_smoke_test
    set UVM_TOP ai_accel_subsys_csr_uvm_top
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 102

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14
}

run_reg_item "csr_job_direct_stream_load_store_case102" {
    set UVM_TEST ai_accel_subsys_csr_job_direct_stream_load_store_smoke_test
    set UVM_TOP ai_accel_subsys_csr_uvm_top
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 102

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14
}



# ============================================================
# P16D2: CSR recipe sequencer regression representatives
#
# The CSR-wrapper subsystem top is selected explicitly.  These
# items validate the P16 recipe runner after P16C/P16D by issuing
# START_RECIPE and letting the hardware recipe sequencer dispatch
# two CSR-resident descriptor slots through the existing P15
# single-job worker.
#
# The first item validates a two-slot DMA recipe.  The second item
# validates the P13-style two-job C RMW partial-K recipe through
# the P16 recipe sequencer.
# Expected total after P16D2: 97.
# ============================================================
run_reg_item "csr_recipe_dma_two_slot_case102" {
    set UVM_TEST ai_accel_subsys_csr_recipe_dma_two_slot_smoke_test
    set UVM_TOP ai_accel_subsys_csr_uvm_top
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 102

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14
}

run_reg_item "csr_recipe_c_rmw_two_slot_case208" {
    set UVM_TEST ai_accel_subsys_csr_recipe_c_rmw_two_slot_smoke_test
    set UVM_TOP ai_accel_subsys_csr_uvm_top
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 208

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14

    set GEMM_ENABLE_C_RMW_ACCUM 1
}

# ============================================================
# P16E2: CSR recipe frontend-mode regression representatives
#
# The CSR-wrapper subsystem top is selected explicitly.  These
# items extend P16E targeted validation into the full regression
# by issuing START_RECIPE for two-slot frontend-mode recipes.
#
# The first item validates AXI-Stream preload recipe slots.  The
# second item validates Direct Stream preload recipe slots.  Both
# recipes dispatch slot0 and slot1 through the existing P15
# single-job worker and compare the final DMA-store destination
# memory against the software reference.
# Expected total after P16E2: 99.
# ============================================================
run_reg_item "csr_recipe_axis_stream_two_slot_case102" {
    set UVM_TEST ai_accel_subsys_csr_recipe_axis_stream_two_slot_smoke_test
    set UVM_TOP ai_accel_subsys_csr_uvm_top
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 102

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14
}

run_reg_item "csr_recipe_direct_stream_two_slot_case102" {
    set UVM_TEST ai_accel_subsys_csr_recipe_direct_stream_two_slot_smoke_test
    set UVM_TOP ai_accel_subsys_csr_uvm_top
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 102

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14
}


# ============================================================
# P16F2: CSR recipe reject / busy / error handling regression representative
#
# The CSR-wrapper subsystem top is selected explicitly.  This
# item extends P16F targeted validation into the full regression
# by checking recipe-level reject conditions, START_RECIPE while
# recipe_busy, P14/P15 command reject while recipe_busy, worker
# error propagation, sticky-status cleanup, and valid recipe
# recovery after error cleanup.
# Expected total after P16F2: 100.
# ============================================================
run_reg_item "csr_recipe_reject_error_case102" {
    set UVM_TEST ai_accel_subsys_csr_recipe_reject_error_test
    set UVM_TOP ai_accel_subsys_csr_uvm_top
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 102

    set FORCE_HELPER_MEM_PATH 0

    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14
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

if {[llength $REG_FAIL_ITEMS] != 0} {
    puts "\n============================================================"
    puts "\[REGRESSION\] FAILED ITEMS"
    puts "============================================================"

    foreach item $REG_FAIL_ITEMS {
        lassign $item idx item_name item_log
        puts [format "#%-4s %s" $idx $item_name]
        puts "      log: $item_log"
    }

    puts "============================================================"
}

if {$REG_FAIL != 0} {
    error "\[REGRESSION\] FAILED: $REG_FAIL item(s) failed"
} else {
    puts "\[REGRESSION\] ALL TESTS PASSED"
}
