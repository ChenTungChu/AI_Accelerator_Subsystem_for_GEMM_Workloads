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

# Keep item-level results so a failed full regression immediately
# reports which item(s) failed and where their logs are.
set REG_PASS_ITEMS {}
set REG_FAIL_ITEMS {}

# Optional debug knob:
#   Default behavior is to run the entire regression and report all
#   failed items at the end.
#
#   To stop immediately on the first failed item:
#     set STOP_ON_FIRST_FAIL 1
#     do run_full_uvm_regression.tcl
if {![info exists STOP_ON_FIRST_FAIL]} {
    set STOP_ON_FIRST_FAIL 0
}

if {($STOP_ON_FIRST_FAIL != 0) && ($STOP_ON_FIRST_FAIL != 1)} {
    error "\[REGRESSION\] Unsupported STOP_ON_FIRST_FAIL='$STOP_ON_FIRST_FAIL'. Supported values: 0, 1"
}

# ------------------------------------------------------------
# Clear sticky Questa Tcl variables before each run
#
# IMPORTANT:
#   This proc is called from inside run_reg_item.
#   Therefore plain "unset VAR" would only target proc-local
#   variables and would not reliably clear top-level Questa Tcl
#   variables left by the previous regression item.
#
#   Use "unset ::VAR" to clear the global variables that run_uvm.tcl
#   reads.
# ------------------------------------------------------------
proc clear_uvm_run_vars {} {
    foreach v {
        UVM_TEST
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
# Utility: return current LOG_FILE or a placeholder
# ------------------------------------------------------------
proc get_current_log_file {} {
    if {[info exists ::LOG_FILE]} {
        return $::LOG_FILE
    }
    return "<LOG_FILE not set>"
}

# ------------------------------------------------------------
# Utility: record one failed item
# ------------------------------------------------------------
proc record_reg_fail {idx name log_file} {
    global REG_FAIL_ITEMS
    lappend REG_FAIL_ITEMS [list $idx $name $log_file]
}

# ------------------------------------------------------------
# Utility: record one passed item
# ------------------------------------------------------------
proc record_reg_pass {idx name log_file} {
    global REG_PASS_ITEMS
    lappend REG_PASS_ITEMS [list $idx $name $log_file]
}

# ------------------------------------------------------------
# Utility: optional fail-fast behavior
# ------------------------------------------------------------
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

# ------------------------------------------------------------
# Run one item
# ------------------------------------------------------------
proc run_reg_item {name setup_body} {
    global REG_TOTAL REG_PASS REG_FAIL

    incr REG_TOTAL
    set item_idx $REG_TOTAL

    puts "\n============================================================"
    puts "\[REGRESSION\] START #$item_idx: $name"
    puts "============================================================"

    clear_uvm_run_vars

    # Stop previous sim context if any.
    catch {quit -sim -f}

    # Apply item-specific variable setup.
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
    set ENABLE_RESULT_CHECK 1
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
# Performance profile test
# ============================================================
run_reg_item "perf_profile" {
    set UVM_TEST ai_accel_subsys_perf_profile_test
    set ENABLE_RESULT_CHECK 1
    set CASE_ID 100
    set FORCE_HELPER_MEM_PATH 0
    set DMA_CLK_PERIOD_NS 10
    set CORE_CLK_PERIOD_NS 14
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
# 2-lane GEMM subset regression
#
# These items validate the optional GEMM_MAC_LANES=2 datapath.
# Default mainline regression remains GEMM_MAC_LANES=1 unless
# explicitly overridden here.
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
# 2-lane GEMM P3 stress / CDC hardening regression
#
# These items validate GEMM_MAC_LANES=2 across the three major
# load/store paths:
#
#   1. DMA load A/B -> GEMM -> DMA store C
#   2. AXI-Stream preload A/B -> GEMM -> DMA store C
#   3. Direct Stream preload A/B -> GEMM -> DMA store C
#
# Each path is covered in:
#   - default clock ratio: dma_clk=10ns, core_clk=14ns
#   - CDC sanity ratio   : dma_clk=10ns, core_clk=13ns
#
# Expected regression total after adding these 6 P3 items:
#   38 + 6 = 44
#
# P4 B-cache representative items are added later:
#   44 + 3 = 47
#
# P5 packed B-cache representative items are added later:
#   47 + 3 = 50
#
# P6 A-row cache focused items are added later:
#   50 + 2 = 52
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
# 2-lane GEMM P4 B-cache representative regression
#
# These items validate GEMM_ENABLE_B_CACHE=1 together with the
# already-hardened GEMM_MAC_LANES=2 datapath.
#
# P4E already covered both default clock and CDC variants manually.
# Full regression keeps only the default-clock representative set
# to avoid making every full regression too heavy.
#
# Covered paths:
#   1. DMA load A/B -> GEMM with B-cache -> DMA store C
#   2. AXI-Stream preload A/B -> GEMM with B-cache -> DMA store C
#   3. Direct Stream preload A/B -> GEMM with B-cache -> DMA store C
#
# Expected regression total after adding these 3 P4 items:
#   44 + 3 = 47
#
# P5 packed B-cache representative items are added below:
#   47 + 3 = 50
#
# P6 A-row cache focused items are added later:
#   50 + 2 = 52
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
# 2-lane GEMM P5 packed B-cache preload representative regression
#
# These items validate GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1 together
# with the already-hardened GEMM_MAC_LANES=2 + GEMM_ENABLE_B_CACHE=1
# datapath.
#
# P5F already covered both default clock and CDC variants manually
# across DMA, AXI-Stream, and Direct Stream load/store stress paths.
# Full regression keeps only the default-clock representative set
# to avoid making every full regression too heavy.
#
# Covered paths:
#   1. DMA load A/B -> packed B-cache preload -> GEMM -> DMA store C
#   2. AXI-Stream preload A/B -> packed B-cache preload -> GEMM -> DMA store C
#   3. Direct Stream preload A/B -> packed B-cache preload -> GEMM -> DMA store C
#
# Expected regression total after adding these 3 P5 items:
#   47 + 3 = 50
#
# P6 A-row cache focused items are added below, bringing
# the current full regression total to:
#   50 + 2 = 52
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
# 2-lane GEMM P6 A-row cache focused regression
#
# These items validate GEMM_ENABLE_A_ROW_CACHE=1 together with
# the already-hardened performance stack:
#
#   GEMM_MAC_LANES=2
#   GEMM_ENABLE_B_CACHE=1
#   GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1
#
# P6C/P6D already validated scalar A-row cache manually with:
#   - enabled correctness smoke
#   - enabled perf/profile comparison
#
# Full regression first keeps the P6 enabled coverage focused:
#   1. A-row cache perf counter smoke RUN_ALL
#   2. A-row cache perf profile
#
# Stress / CDC representative load-store items should be added
# later after P6F manual stress/CDC closure.
#
# Expected regression total after adding these 2 P6 focused items:
#   50 + 2 = 52
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

# ============================================================
# 2-lane GEMM P6F A-row cache Direct Stream stress / CDC
# representative regression
#
# These items validate GEMM_ENABLE_A_ROW_CACHE=1 together with:
#   - GEMM_MAC_LANES=2
#   - GEMM_ENABLE_B_CACHE=1
#   - GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1
#
# Covered path:
#   Direct Stream preload A/B -> GEMM with packed B-cache
#   and A-row cache -> DMA store C
#
# Covered clock ratios:
#   1. default clock ratio: dma_clk=10ns, core_clk=14ns
#   2. CDC sanity ratio   : dma_clk=10ns, core_clk=13ns
#
# Expected regression total after adding these 2 P6F items:
#   52 + 2 = 54
# ============================================================

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

# ============================================================
# 2-lane GEMM P6 A-row cache DMA / AXI-Stream representative regression
#
# These items validate GEMM_ENABLE_A_ROW_CACHE=1 together with:
#   - GEMM_MAC_LANES=2
#   - GEMM_ENABLE_B_CACHE=1
#   - GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1
#
# P6 manual sanity already confirmed:
#   1. DMA load A/B -> packed B-cache preload -> A-row cache GEMM -> DMA store C
#   2. AXI-Stream preload A/B -> packed B-cache preload -> A-row cache GEMM -> DMA store C
#
# Together with the existing Direct Stream P6 regression items, this
# completes frontend-path coverage for the scalar A-row cache milestone.
#
# Expected regression total after adding these 2 P6 items:
#   54 + 2 = 56
# ============================================================

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
# 2-lane GEMM P7 packed A-row preload representative regression
#
# These items validate GEMM_ENABLE_PACKED_A_ROW_PRELOAD=1 together
# with the already-hardened performance stack:
#
#   GEMM_MAC_LANES=2
#   GEMM_ENABLE_B_CACHE=1
#   GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1
#   GEMM_ENABLE_A_ROW_CACHE=1
#
# P7F already covered both default clock and CDC variants manually
# across DMA, AXI-Stream, and Direct Stream load/store stress paths.
# Full regression keeps only the default-clock representative set
# to avoid making every full regression too heavy.
#
# Covered paths:
#   1. DMA load A/B -> packed B-cache preload ->
#      packed A-row preload GEMM -> DMA store C
#   2. AXI-Stream preload A/B -> packed B-cache preload ->
#      packed A-row preload GEMM -> DMA store C
#   3. Direct Stream preload A/B -> packed B-cache preload ->
#      packed A-row preload GEMM -> DMA store C
#
# Expected regression total after adding these 3 P7 items:
#   56 + 3 = 59
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
# 4-lane GEMM P8 representative regression
#
# These items validate the P8 cache-backed true 4-lane MAC path:
#
#   GEMM_MAC_LANES=4
#   GEMM_ENABLE_B_CACHE=1
#   GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1
#   GEMM_ENABLE_A_ROW_CACHE=1
#   GEMM_ENABLE_PACKED_A_ROW_PRELOAD=1
#
# P8F already covered both default clock and CDC variants manually
# across DMA, AXI-Stream, and Direct Stream load/store stress paths.
# Full regression keeps only the default-clock representative set
# to avoid making every full regression too heavy.
#
# Covered paths:
#   1. DMA load A/B -> full cache/preload GEMM -> DMA store C
#   2. AXI-Stream preload A/B -> full cache/preload GEMM -> DMA store C
#   3. Direct Stream preload A/B -> full cache/preload GEMM -> DMA store C
#
# Expected regression total after adding these 3 P8 items:
#   59 + 3 = 62
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
# 4-lane GEMM P9 scaled-cache larger-dimension representative regression
#
# These items validate the P9 scaled cache configuration:
#
#   GEMM_MAC_LANES=4
#   GEMM_ENABLE_B_CACHE=1
#   GEMM_B_CACHE_MAX_K=8
#   GEMM_B_CACHE_MAX_N=8
#   GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1
#   GEMM_ENABLE_A_ROW_CACHE=1
#   GEMM_A_ROW_CACHE_MAX_K=8
#   GEMM_ENABLE_PACKED_A_ROW_PRELOAD=1
#
# P9G manually closed the large-dimension path compatibility sanity
# across DMA, AXI-Stream, and Direct Stream load/store paths.
# Full regression keeps only one forced large CASE_ID per path so the
# default stress pools do not become heavier.
#
# Covered focused cases:
#   1. DMA load/store path        : CASE_ID=190, dim=(1,8,8)
#   2. AXI-Stream load/store path : CASE_ID=191, dim=(2,8,8)
#   3. Direct Stream load/store   : CASE_ID=192, dim=(3,5,7)
#
# Expected regression total after adding these 3 P9 items:
#   62 + 3 = 65
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
# P10B K-tiling safe parameter plumbing
#
# P10B added GEMM_ENABLE_K_TILING and GEMM_K_TILE_SIZE as default-off
# elaboration/run-script parameters. No full-regression item was added
# at that step, so the P9H regression total intentionally remained 65.
# Focused P10B smoke was run manually with GEMM_ENABLE_K_TILING=1.
# ============================================================

# ============================================================
# P10F K-tiling frontend representative regression
#
# These items integrate the P10D/P10E K-tiling coverage into the
# full regression with bounded runtime.
#
# Configuration:
#   GEMM_MAC_LANES=4
#   GEMM_ENABLE_B_CACHE=1
#   GEMM_B_CACHE_MAX_K=8
#   GEMM_B_CACHE_MAX_N=8
#   GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1
#   GEMM_ENABLE_A_ROW_CACHE=1
#   GEMM_A_ROW_CACHE_MAX_K=8
#   GEMM_ENABLE_PACKED_A_ROW_PRELOAD=1
#   GEMM_ENABLE_K_TILING=1
#   GEMM_K_TILE_SIZE=8
#
# Focused case:
#   CASE_ID=195, dim=(4,4,16), exactly two K=8 tiles.
#
# Covered paths:
#   1. DMA load/store path
#   2. AXI-Stream load/store path
#   3. Direct Stream load/store path
#
# Runtime policy:
#   Each item uses one forced CASE_ID=195 job.  This preserves
#   frontend coverage while avoiding the heavier P10E manual stress
#   run counts.
#
# Expected regression total after adding these 3 P10 items:
#   65 + 3 = 68
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
# P11B N-tiling safe parameter plumbing
#
# P11B adds GEMM_ENABLE_N_TILING and GEMM_N_TILE_SIZE as
# default-off elaboration/run-script parameters. No full-regression
# item is added at this step, so the P10F regression total
# intentionally remains 68. Focused P11B smoke should be run
# manually with GEMM_ENABLE_N_TILING=1 on a cache-fit case before
# P11C/P11D add N>8 test cases and the N-tile scheduler.
# ============================================================


# ============================================================
# P11G N-tiling frontend representative regression
#
# These items integrate the P11D/P11E N-tiling coverage into the
# full regression with bounded runtime.
#
# Configuration:
#   GEMM_MAC_LANES=4
#   GEMM_ENABLE_B_CACHE=1
#   GEMM_B_CACHE_MAX_K=8
#   GEMM_B_CACHE_MAX_N=8
#   GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1
#   GEMM_ENABLE_A_ROW_CACHE=1
#   GEMM_A_ROW_CACHE_MAX_K=8
#   GEMM_ENABLE_PACKED_A_ROW_PRELOAD=1
#   GEMM_ENABLE_K_TILING=1
#   GEMM_K_TILE_SIZE=8
#   GEMM_ENABLE_N_TILING=1
#   GEMM_N_TILE_SIZE=8
#
# Focused case:
#   CASE_ID=200, dim=(4,16,16), combined K-tiling and N-tiling.
#
# Covered paths:
#   1. DMA load/store path
#   2. AXI-Stream load/store path
#   3. Direct Stream load/store path
#
# Runtime policy:
#   Each item uses one forced CASE_ID=200 job and a longer shared
#   done timeout.  CASE_ID=200 is intentionally larger than the
#   pre-P11 smoke/stress workloads, and focused P11E validation showed
#   it can complete in about 31.4k monitor cycles on DMA/AXIS paths.
#
# Expected regression total after adding these 3 P11 items:
#   68 + 3 = 71
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
# P12B M-tiling safe parameter plumbing
#
# P12B adds GEMM_ENABLE_M_TILING and GEMM_M_TILE_SIZE as
# default-off elaboration/run-script parameters. No full-regression
# item is added at this step, so the P11G regression total
# intentionally remains 71. Focused P12B smoke should be run
# manually with GEMM_ENABLE_M_TILING=1 on an existing P11 case before
# P12C/P12D add M>current-row test cases and the multi-row scheduler.
# ============================================================


# ============================================================
# P12G M-tiling frontend representative regression
#
# These items integrate the P12D/P12E/P12F M-tiling coverage into
# the full regression with bounded runtime.
#
# Configuration:
#   GEMM_MAC_LANES=4
#   GEMM_ENABLE_B_CACHE=1
#   GEMM_B_CACHE_MAX_K=8
#   GEMM_B_CACHE_MAX_N=8
#   GEMM_ENABLE_PACKED_BCACHE_PRELOAD=1
#   GEMM_ENABLE_A_ROW_CACHE=1
#   GEMM_A_ROW_CACHE_MAX_K=8
#   GEMM_ENABLE_PACKED_A_ROW_PRELOAD=1
#   GEMM_ENABLE_K_TILING=1
#   GEMM_K_TILE_SIZE=8
#   GEMM_ENABLE_N_TILING=1
#   GEMM_N_TILE_SIZE=8
#   GEMM_ENABLE_M_TILING=1
#   GEMM_M_TILE_SIZE=2
#
# Focused case:
#   CASE_ID=207, dim=(7,12,16), combined M/N/K tiling with
#   ragged M and N tile tails.
#
# Covered paths:
#   1. DMA load/store path
#   2. AXI-Stream load/store path
#   3. Direct Stream load/store path
#
# Runtime policy:
#   Each item uses one forced CASE_ID=207 job and a longer shared
#   done timeout.  P12E/P12F focused validation already covered the
#   wider host-primary and frontend sanity matrix.  Full regression
#   keeps one representative M-tiling frontend job per path to avoid
#   making every full regression too heavy.
#
# Expected regression total after adding these 3 P12 items:
#   71 + 3 = 74
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
