# File: sim/run_uvm.tcl
file mkdir logs

# --------------------------------------------------
# Log retention policy
#
# Keep only the newest LOG_KEEP_COUNT .log files.
# Default: 50
# --------------------------------------------------
if {![info exists LOG_KEEP_COUNT]} {
    set LOG_KEEP_COUNT 50
}

proc prune_old_logs {log_dir keep_count} {
    if {$keep_count <= 0} {
        return
    }

    set files [glob -nocomplain -directory $log_dir *.log]
    set decorated [list]

    foreach f $files {
        if {[file isfile $f]} {
            lappend decorated [list [file mtime $f] $f]
        }
    }

    # newest first
    set sorted [lsort -integer -decreasing -index 0 $decorated]

    set idx 0
    foreach item $sorted {
        incr idx

        if {$idx > $keep_count} {
            set old_file [lindex $item 1]
            catch {file delete -force $old_file}
        }
    }
}

# --------------------------------------------------
# Supported tests
# --------------------------------------------------
set SUPPORTED_UVM_TESTS [list \
    ai_accel_subsys_smoke_test \
    ai_accel_subsys_back_to_back_test \
    ai_accel_subsys_reset_recovery_test \
    ai_accel_subsys_corner_test \
    ai_accel_subsys_midrun_reset_test \
    ai_accel_subsys_dma_load_smoke_test \
    ai_accel_subsys_dma_load_error_test \
    ai_accel_subsys_dma_load_stress_test \
    ai_accel_subsys_dma_store_smoke_test \
    ai_accel_subsys_dma_store_error_test \
    ai_accel_subsys_dma_load_store_stress_test \
    ai_accel_subsys_axis_stream_preload_smoke_test \
    ai_accel_subsys_axis_stream_preload_error_test \
    ai_accel_subsys_axis_stream_load_store_stress_test \
    ai_accel_subsys_direct_stream_smoke_test \
    ai_accel_subsys_direct_stream_error_test \
    ai_accel_subsys_direct_stream_load_store_stress_test \
    ai_accel_subsys_perf_counter_smoke_test \
    ai_accel_subsys_perf_profile_test \
    ai_accel_subsys_c_rmw_accum_ref_model_test \
    ai_accel_subsys_c_rmw_accum_dut_test \
    ai_accel_csr_regs_smoke_test \
    ai_accel_subsys_csr_smoke_test \
    ai_accel_subsys_csr_dma_load_store_smoke_test \
    ai_accel_subsys_csr_axis_stream_load_store_smoke_test \
    ai_accel_subsys_csr_direct_stream_load_store_smoke_test \
    ai_accel_subsys_csr_job_dma_load_store_smoke_test \
    ai_accel_subsys_csr_job_reject_error_test \
    ai_accel_subsys_csr_job_axis_stream_load_store_smoke_test \
    ai_accel_subsys_csr_job_direct_stream_load_store_smoke_test \
    ai_accel_subsys_csr_recipe_dma_two_slot_smoke_test \
    ai_accel_subsys_csr_recipe_c_rmw_two_slot_smoke_test \
    ai_accel_subsys_csr_recipe_axis_stream_two_slot_smoke_test \
    ai_accel_subsys_csr_recipe_direct_stream_two_slot_smoke_test \
    ai_accel_subsys_csr_recipe_reject_error_test \
    ai_accel_subsys_csr_desc_fetch_smoke_test \
    ai_accel_subsys_csr_desc_fetch_dma_two_slot_smoke_test \
    ai_accel_subsys_csr_desc_fetch_c_rmw_two_slot_smoke_test \
    ai_accel_subsys_csr_desc_fetch_direct_stream_two_slot_smoke_test \
    ai_accel_subsys_csr_desc_fetch_reject_error_test \
    ai_accel_subsys_csr_completion_wb_smoke_test \
    ai_accel_subsys_csr_desc_fetch_dma_completion_wb_test \
    ai_accel_subsys_csr_desc_fetch_c_rmw_completion_wb_test \
    ai_accel_subsys_csr_desc_fetch_direct_stream_completion_wb_test \
    ai_accel_subsys_csr_completion_wb_error_busy_clear_test \
    ai_accel_subsys_csr_queue_desc_fetch_dma_smoke_test \
    ai_accel_subsys_csr_queue_completion_wb_smoke_test \
    ai_accel_subsys_csr_queue_reject_error_test \
    ai_accel_subsys_csr_queue_two_command_dma_smoke_test \
    ai_accel_subsys_csr_queue_mixed_dma_ds_c_rmw_smoke_test \
    ai_accel_subsys_csr_queue_wraparound_smoke_test \
    ai_accel_subsys_csr_queue_stop_behavior_smoke_test \
    ai_accel_subsys_csr_queue_runtime_doorbell_dma_smoke_test \
    ai_accel_subsys_csr_queue_runtime_doorbell_mixed_smoke_test \
    ai_accel_subsys_csr_queue_cq_full_live_recovery_smoke_test \
    ai_accel_subsys_csr_queue_stop_live_service_smoke_test \
]

# --------------------------------------------------
# TESTNAME compatibility
#
# Preferred variable:
#   UVM_TEST
#
# Backward-compatible alias:
#   TESTNAME
# --------------------------------------------------
if {![info exists UVM_TEST] && [info exists TESTNAME]} {
    set UVM_TEST $TESTNAME
}

# --------------------------------------------------
# Select UVM test
#   default: ai_accel_subsys_smoke_test
# --------------------------------------------------
if {![info exists UVM_TEST]} {
    set UVM_TEST ai_accel_subsys_smoke_test
}

if {[lsearch -exact $SUPPORTED_UVM_TESTS $UVM_TEST] < 0} {
    error "Unsupported UVM_TEST='$UVM_TEST'. Supported tests: $SUPPORTED_UVM_TESTS"
}

# --------------------------------------------------
# Select simulation top
#
# Default:
#   ai_accel_subsys_uvm_top for existing sideband subsystem tests
#
# CSR standalone register smoke uses ai_accel_csr_regs_uvm_top.
# Future CSR-controlled subsystem tests can set:
#   set UVM_TOP ai_accel_subsys_csr_uvm_top
# --------------------------------------------------
set SUPPORTED_UVM_TOPS [list \
    ai_accel_subsys_uvm_top \
    ai_accel_subsys_csr_uvm_top \
    ai_accel_csr_regs_uvm_top \
]

if {![info exists UVM_TOP]} {
    if {$UVM_TEST eq "ai_accel_csr_regs_smoke_test"} {
        set UVM_TOP ai_accel_csr_regs_uvm_top
    } elseif {($UVM_TEST eq "ai_accel_subsys_csr_smoke_test") ||
              ($UVM_TEST eq "ai_accel_subsys_csr_dma_load_store_smoke_test") ||
              ($UVM_TEST eq "ai_accel_subsys_csr_axis_stream_load_store_smoke_test") ||
              ($UVM_TEST eq "ai_accel_subsys_csr_direct_stream_load_store_smoke_test") ||
              ($UVM_TEST eq "ai_accel_subsys_csr_job_dma_load_store_smoke_test") ||
              ($UVM_TEST eq "ai_accel_subsys_csr_job_reject_error_test") ||
              ($UVM_TEST eq "ai_accel_subsys_csr_job_axis_stream_load_store_smoke_test") ||
              ($UVM_TEST eq "ai_accel_subsys_csr_job_direct_stream_load_store_smoke_test") ||
              ($UVM_TEST eq "ai_accel_subsys_csr_recipe_dma_two_slot_smoke_test") ||
              ($UVM_TEST eq "ai_accel_subsys_csr_recipe_c_rmw_two_slot_smoke_test") ||
              ($UVM_TEST eq "ai_accel_subsys_csr_recipe_axis_stream_two_slot_smoke_test") ||
              ($UVM_TEST eq "ai_accel_subsys_csr_recipe_direct_stream_two_slot_smoke_test") ||
              ($UVM_TEST eq "ai_accel_subsys_csr_recipe_reject_error_test")} {
        set UVM_TOP ai_accel_subsys_csr_uvm_top
    } else {
        set UVM_TOP ai_accel_subsys_uvm_top
    }
}

if {[lsearch -exact $SUPPORTED_UVM_TOPS $UVM_TOP] < 0} {
    error "Unsupported UVM_TOP='$UVM_TOP'. Supported tops: $SUPPORTED_UVM_TOPS"
}

# --------------------------------------------------
# Case selection
# --------------------------------------------------
if {![info exists CASE_ID]} {
    set CASE_ID 0
}

if {($UVM_TEST eq "ai_accel_subsys_c_rmw_accum_dut_test") && ($CASE_ID == 0)} {
    set CASE_ID 208
}

if {($UVM_TEST eq "ai_accel_subsys_csr_job_reject_error_test") && ($CASE_ID == 0)} {
    set CASE_ID 102
}

if {($UVM_TEST eq "ai_accel_subsys_csr_recipe_dma_two_slot_smoke_test") && ($CASE_ID == 0)} {
    set CASE_ID 102
}

if {($UVM_TEST eq "ai_accel_subsys_csr_recipe_c_rmw_two_slot_smoke_test") && ($CASE_ID == 0)} {
    set CASE_ID 208
}

if {($UVM_TEST eq "ai_accel_subsys_csr_recipe_axis_stream_two_slot_smoke_test") && ($CASE_ID == 0)} {
    set CASE_ID 102
}

if {($UVM_TEST eq "ai_accel_subsys_csr_recipe_direct_stream_two_slot_smoke_test") && ($CASE_ID == 0)} {
    set CASE_ID 102
}

if {($UVM_TEST eq "ai_accel_subsys_csr_recipe_reject_error_test") && ($CASE_ID == 0)} {
    set CASE_ID 102
}

# --------------------------------------------------
# Result checking
#
#   ENABLE_RESULT_CHECK=1:
#     - enables expected/actual compare
#     - enables Policy B memory-path selection in tests
# --------------------------------------------------
if {![info exists ENABLE_RESULT_CHECK]} {
    set ENABLE_RESULT_CHECK 0
}

if {$UVM_TEST eq "ai_accel_subsys_c_rmw_accum_dut_test"} {
    set ENABLE_RESULT_CHECK 1
}

# --------------------------------------------------
# Smoke / frontend done timeout knob
#
#   Default:
#     Do not forward a timeout plusarg. Each test class keeps
#     its own historical default timeout.
#
#   Manual long-running P11D/P11E focused run:
#     set SMOKE_DONE_TIMEOUT_CYCLES 100000
#     do run_uvm.tcl
#
#   When explicitly set, this value is forwarded as:
#     +SMOKE_DONE_TIMEOUT_CYCLES=<cycles>
#
#   This shared knob is consumed by:
#     - ai_accel_subsys_smoke_test
#     - ai_accel_subsys_dma_store_smoke_test
#       and its load-store frontend wrappers
# --------------------------------------------------
set SMOKE_DONE_TIMEOUT_ARG_LIST [list]
set SMOKE_DONE_TIMEOUT_MODE     class_default

if {[info exists SMOKE_DONE_TIMEOUT_CYCLES]} {
    if {$SMOKE_DONE_TIMEOUT_CYCLES <= 0} {
        error "Unsupported SMOKE_DONE_TIMEOUT_CYCLES='$SMOKE_DONE_TIMEOUT_CYCLES'. Must be > 0"
    }

    set SMOKE_DONE_TIMEOUT_MODE $SMOKE_DONE_TIMEOUT_CYCLES
    lappend SMOKE_DONE_TIMEOUT_ARG_LIST +SMOKE_DONE_TIMEOUT_CYCLES=$SMOKE_DONE_TIMEOUT_CYCLES
}

# --------------------------------------------------
# Memory Path Policy (Policy B)
#
#   Primary mode:
#     ENABLE_RESULT_CHECK=1
#       -> host-agent memory path is the default
#
#   Fallback mode:
#     FORCE_HELPER_MEM_PATH=1
#       -> force helper memory path
#
#   Notes:
#     - host agent is the main path
#     - helper is fallback / debug only
# --------------------------------------------------
if {![info exists FORCE_HELPER_MEM_PATH]} {
    set FORCE_HELPER_MEM_PATH 0
}

if {$FORCE_HELPER_MEM_PATH} {
    set MEM_PATH_MODE helper_fallback
} else {
    set MEM_PATH_MODE host_primary
}

# --------------------------------------------------
# C RMW runtime control bit
#
# Default:
#   ACCUMULATE_ENABLE=0 keeps the default write-final-C behavior.
#
# Manual C RMW accumulation plumbing smoke:
#   set GEMM_ENABLE_C_RMW_ACCUM 1
#   set ACCUMULATE_ENABLE 0
#   do run_uvm.tcl
#
# Note:
#   This knob forwards the default runtime C RMW accumulation bit.
#   Recipe tests may still drive per-job accumulation through UVM.
# --------------------------------------------------
if {![info exists ACCUMULATE_ENABLE]} {
    set ACCUMULATE_ENABLE 0
}

if {($ACCUMULATE_ENABLE != 0) && ($ACCUMULATE_ENABLE != 1)} {
    error "Unsupported ACCUMULATE_ENABLE='$ACCUMULATE_ENABLE'. Supported values: 0, 1"
}

# --------------------------------------------------
# Legacy per-path overrides
#
#   These are kept only for fine-grain debug.
#   They are NOT the normal way to run tests anymore.
#
#   IMPORTANT:
#     - do not auto-create defaults here
#     - only forward them to vsim when explicitly set
#       in the current Tcl session
#     - these variables are sticky inside the same
#       Questa Tcl session unless you unset them
#
#   Supported overrides:
#     USE_HOST_AGENT_CLEAR_C
#     USE_HOST_AGENT_READBACK_C
#     USE_HOST_AGENT_PRELOAD_AB
# --------------------------------------------------
set LEGACY_HOST_OVERRIDE_ARGS [list]

if {[info exists USE_HOST_AGENT_CLEAR_C]} {
    lappend LEGACY_HOST_OVERRIDE_ARGS +USE_HOST_AGENT_CLEAR_C=$USE_HOST_AGENT_CLEAR_C
}

if {[info exists USE_HOST_AGENT_READBACK_C]} {
    lappend LEGACY_HOST_OVERRIDE_ARGS +USE_HOST_AGENT_READBACK_C=$USE_HOST_AGENT_READBACK_C
}

if {[info exists USE_HOST_AGENT_PRELOAD_AB]} {
    lappend LEGACY_HOST_OVERRIDE_ARGS +USE_HOST_AGENT_PRELOAD_AB=$USE_HOST_AGENT_PRELOAD_AB
}

# --------------------------------------------------
# Internally generated extra plusargs
#
# These are generated by run_uvm.tcl from friendly Tcl
# variables such as RUN_ALL, AXIS_STRESS_JOB_COUNT, etc.
# --------------------------------------------------
set EXTRA_ARGS [list]

# --------------------------------------------------
# Job-selection knobs
#
#   back_to_back_test:
#     - keep friendly defaults
#
#   corner_test:
#     - do NOT auto-create defaults here
#     - only forward JOB_* plusargs when explicitly set
#       in the current Tcl session
#     - otherwise let the test class use its own
#       internal default recipe
# --------------------------------------------------
set JOB_ARG_LIST [list]

if {$UVM_TEST eq "ai_accel_subsys_back_to_back_test"} {
    if {![info exists JOB_COUNT]} {
        set JOB_COUNT 2
    }

    if {![info exists JOB0_CASE_ID]} {
        set JOB0_CASE_ID 100
    }

    if {![info exists JOB1_CASE_ID]} {
        set JOB1_CASE_ID 101
    }

    if {![info exists JOB2_CASE_ID]} {
        set JOB2_CASE_ID 5
    }

    if {![info exists JOB3_CASE_ID]} {
        set JOB3_CASE_ID 400
    }

    lappend JOB_ARG_LIST +JOB_COUNT=$JOB_COUNT
    lappend JOB_ARG_LIST +JOB0_CASE_ID=$JOB0_CASE_ID
    lappend JOB_ARG_LIST +JOB1_CASE_ID=$JOB1_CASE_ID
    lappend JOB_ARG_LIST +JOB2_CASE_ID=$JOB2_CASE_ID
    lappend JOB_ARG_LIST +JOB3_CASE_ID=$JOB3_CASE_ID

} elseif {$UVM_TEST eq "ai_accel_subsys_corner_test"} {
    if {[info exists JOB_COUNT]} {
        lappend JOB_ARG_LIST +JOB_COUNT=$JOB_COUNT
    }

    if {[info exists JOB0_CASE_ID]} {
        lappend JOB_ARG_LIST +JOB0_CASE_ID=$JOB0_CASE_ID
    }

    if {[info exists JOB1_CASE_ID]} {
        lappend JOB_ARG_LIST +JOB1_CASE_ID=$JOB1_CASE_ID
    }

    if {[info exists JOB2_CASE_ID]} {
        lappend JOB_ARG_LIST +JOB2_CASE_ID=$JOB2_CASE_ID
    }

    if {[info exists JOB3_CASE_ID]} {
        lappend JOB_ARG_LIST +JOB3_CASE_ID=$JOB3_CASE_ID
    }
}

# --------------------------------------------------
# RUN_ALL knobs
#
#   RUN_ALL=0:
#     run selected CASE_ID only
#
#   RUN_ALL=1:
#     run built-in mini-regression recipe
# --------------------------------------------------
set DMA_SMOKE_ARG_LIST [list]

if {($UVM_TEST eq "ai_accel_subsys_dma_load_smoke_test") ||
    ($UVM_TEST eq "ai_accel_subsys_dma_store_smoke_test") ||
    ($UVM_TEST eq "ai_accel_subsys_axis_stream_preload_smoke_test") ||
    ($UVM_TEST eq "ai_accel_subsys_direct_stream_smoke_test") ||
    ($UVM_TEST eq "ai_accel_subsys_perf_counter_smoke_test") ||
    ($UVM_TEST eq "ai_accel_subsys_c_rmw_accum_ref_model_test") ||
    ($UVM_TEST eq "ai_accel_subsys_c_rmw_accum_dut_test")} {

    if {![info exists RUN_ALL]} {
        set RUN_ALL 0
    }

    lappend DMA_SMOKE_ARG_LIST +RUN_ALL=$RUN_ALL
}

# --------------------------------------------------
# DMA-load stress knobs
#
#   used by ai_accel_subsys_dma_load_stress_test
#
#   STRESS_JOB_COUNT:
#     number of DMA-loaded GEMM jobs
#
#   STRESS_SEED:
#     deterministic pseudo-random seed
#
#   STRESS_RANDOM:
#     1 -> pseudo-random case selection
#     0 -> round-robin case selection
#
#   STRESS_GAP_CYCLES:
#     idle cycles between jobs
# --------------------------------------------------
set DMA_LOAD_STRESS_ARG_LIST [list]

if {$UVM_TEST eq "ai_accel_subsys_dma_load_stress_test"} {
    if {![info exists STRESS_JOB_COUNT]} {
        set STRESS_JOB_COUNT 20
    }

    if {![info exists STRESS_SEED]} {
        set STRESS_SEED 20260502
    }

    if {![info exists STRESS_RANDOM]} {
        set STRESS_RANDOM 1
    }

    if {![info exists STRESS_GAP_CYCLES]} {
        set STRESS_GAP_CYCLES 10
    }

    lappend DMA_LOAD_STRESS_ARG_LIST +STRESS_JOB_COUNT=$STRESS_JOB_COUNT
    lappend DMA_LOAD_STRESS_ARG_LIST +STRESS_SEED=$STRESS_SEED
    lappend DMA_LOAD_STRESS_ARG_LIST +STRESS_RANDOM=$STRESS_RANDOM
    lappend DMA_LOAD_STRESS_ARG_LIST +STRESS_GAP_CYCLES=$STRESS_GAP_CYCLES
}

# --------------------------------------------------
# DMA load-store stress knobs
#
#   used by:
#     ai_accel_subsys_dma_load_store_stress_test
#
#   STORE_STRESS_JOB_COUNT:
#     number of full DMA load -> GEMM -> DMA store jobs
#
#   STORE_STRESS_SEED:
#     deterministic pseudo-random seed
#
#   STORE_STRESS_RANDOM:
#     1 -> pseudo-random case selection
#     0 -> round-robin case selection
#
#   STORE_STRESS_GAP_CYCLES:
#     idle cycles between jobs
# --------------------------------------------------
set DMA_LOAD_STORE_STRESS_ARG_LIST [list]

if {$UVM_TEST eq "ai_accel_subsys_dma_load_store_stress_test"} {
    if {![info exists STORE_STRESS_JOB_COUNT]} {
        set STORE_STRESS_JOB_COUNT 20
    }

    if {![info exists STORE_STRESS_SEED]} {
        set STORE_STRESS_SEED 20260502
    }

    if {![info exists STORE_STRESS_RANDOM]} {
        set STORE_STRESS_RANDOM 1
    }

    if {![info exists STORE_STRESS_GAP_CYCLES]} {
        set STORE_STRESS_GAP_CYCLES 10
    }

    lappend DMA_LOAD_STORE_STRESS_ARG_LIST +STORE_STRESS_JOB_COUNT=$STORE_STRESS_JOB_COUNT
    lappend DMA_LOAD_STORE_STRESS_ARG_LIST +STORE_STRESS_SEED=$STORE_STRESS_SEED
    lappend DMA_LOAD_STORE_STRESS_ARG_LIST +STORE_STRESS_RANDOM=$STORE_STRESS_RANDOM
    lappend DMA_LOAD_STORE_STRESS_ARG_LIST +STORE_STRESS_GAP_CYCLES=$STORE_STRESS_GAP_CYCLES
}

# --------------------------------------------------
# DMA store error optional knobs
#
#   Default full-regression mode:
#     RUN_START_WHILE_BUSY is not forwarded unless explicitly set.
#
#   Manual optional run:
#     set RUN_START_WHILE_BUSY 1
#     do run_uvm.tcl
#
#   Existing EXTRA_PLUSARGS flow is still supported:
#     set EXTRA_PLUSARGS "+RUN_START_WHILE_BUSY=1"
# --------------------------------------------------
set DMA_STORE_ERROR_ARG_LIST [list]
set DMA_STORE_ERROR_MODE default

if {$UVM_TEST eq "ai_accel_subsys_dma_store_error_test"} {
    if {[info exists RUN_START_WHILE_BUSY]} {
        lappend DMA_STORE_ERROR_ARG_LIST +RUN_START_WHILE_BUSY=$RUN_START_WHILE_BUSY

        if {$RUN_START_WHILE_BUSY} {
            set DMA_STORE_ERROR_MODE start_while_busy
        } else {
            set DMA_STORE_ERROR_MODE default
        }
    }
}

# --------------------------------------------------
# Clock period knobs
#
# Defaults match ai_accel_subsys_uvm_top.sv:
#   dma_clk  period = 10 ns
#   core_clk period = 14 ns
# --------------------------------------------------
set CLOCK_ARG_LIST [list]

if {![info exists DMA_CLK_PERIOD_NS]} {
    set DMA_CLK_PERIOD_NS 10
}

if {![info exists CORE_CLK_PERIOD_NS]} {
    set CORE_CLK_PERIOD_NS 14
}

lappend CLOCK_ARG_LIST +DMA_CLK_PERIOD_NS=$DMA_CLK_PERIOD_NS
lappend CLOCK_ARG_LIST +CORE_CLK_PERIOD_NS=$CORE_CLK_PERIOD_NS

# --------------------------------------------------
# GEMM MAC lane parameter
#
# Default:
#   GEMM_MAC_LANES=1 keeps the existing single-lane baseline.
#
# Manual 2-lane / 4-lane run:
#   set GEMM_MAC_LANES 2
#   do run_uvm.tcl
#
#   set GEMM_MAC_LANES 4
#   do run_uvm.tcl
# --------------------------------------------------
if {![info exists GEMM_MAC_LANES]} {
    set GEMM_MAC_LANES 1
}

if {($GEMM_MAC_LANES != 1) &&
    ($GEMM_MAC_LANES != 2) &&
    ($GEMM_MAC_LANES != 4)} {
    error "Unsupported GEMM_MAC_LANES='$GEMM_MAC_LANES'. Supported values: 1, 2, 4"
}

# --------------------------------------------------
# Reset-recovery test knobs
#   used by ai_accel_subsys_reset_recovery_test
# --------------------------------------------------
if {![info exists PRE_RESET_CASE_ID]} {
    set PRE_RESET_CASE_ID 5
}

if {![info exists POST_RESET_CASE_ID]} {
    set POST_RESET_CASE_ID 101
}

if {![info exists RESET_HOLD_CYCLES]} {
    set RESET_HOLD_CYCLES 5
}

if {![info exists POST_RESET_SETTLE_CYCLES]} {
    set POST_RESET_SETTLE_CYCLES 5
}

# --------------------------------------------------
# Stream load store stress test plusargs
#   used by ai_accel_subsys_axis_stream_load_store_stress_test
# --------------------------------------------------
if {$UVM_TEST eq "ai_accel_subsys_axis_stream_load_store_stress_test"} {
    if {![info exists AXIS_STRESS_JOB_COUNT]} {
        set AXIS_STRESS_JOB_COUNT 8
    }
    if {![info exists AXIS_STRESS_SEED]} {
        set AXIS_STRESS_SEED 20260502
    }
    if {![info exists AXIS_STRESS_RANDOM]} {
        set AXIS_STRESS_RANDOM 1
    }
    if {![info exists AXIS_STRESS_GAP_CYCLES]} {
        set AXIS_STRESS_GAP_CYCLES 10
    }

    lappend EXTRA_ARGS +AXIS_STRESS_JOB_COUNT=$AXIS_STRESS_JOB_COUNT
    lappend EXTRA_ARGS +AXIS_STRESS_SEED=$AXIS_STRESS_SEED
    lappend EXTRA_ARGS +AXIS_STRESS_RANDOM=$AXIS_STRESS_RANDOM
    lappend EXTRA_ARGS +AXIS_STRESS_GAP_CYCLES=$AXIS_STRESS_GAP_CYCLES
}

# --------------------------------------------------
# Forward stress test plusargs
#   used by ai_accel_subsys_direct_stream_load_store_stress_test
# --------------------------------------------------
if {$UVM_TEST eq "ai_accel_subsys_direct_stream_load_store_stress_test"} {
    if {![info exists DS_STRESS_JOB_COUNT]} {
        set DS_STRESS_JOB_COUNT 8
    }
    if {![info exists DS_STRESS_SEED]} {
        set DS_STRESS_SEED 20260502
    }
    if {![info exists DS_STRESS_RANDOM]} {
        set DS_STRESS_RANDOM 1
    }
    if {![info exists DS_STRESS_GAP_CYCLES]} {
        set DS_STRESS_GAP_CYCLES 10
    }

    lappend EXTRA_ARGS +DS_STRESS_JOB_COUNT=$DS_STRESS_JOB_COUNT
    lappend EXTRA_ARGS +DS_STRESS_SEED=$DS_STRESS_SEED
    lappend EXTRA_ARGS +DS_STRESS_RANDOM=$DS_STRESS_RANDOM
    lappend EXTRA_ARGS +DS_STRESS_GAP_CYCLES=$DS_STRESS_GAP_CYCLES
}

# --------------------------------------------------
# GEMM B-cache parameter
#
# Default:
#   GEMM_ENABLE_B_CACHE=0 keeps the current B-cache baseline.
#
# Manual B-cache run:
#   set GEMM_ENABLE_B_CACHE 1
#   do run_uvm.tcl
# --------------------------------------------------
if {![info exists GEMM_ENABLE_B_CACHE]} {
    set GEMM_ENABLE_B_CACHE 0
}

if {($GEMM_ENABLE_B_CACHE != 0) && ($GEMM_ENABLE_B_CACHE != 1)} {
    error "Unsupported GEMM_ENABLE_B_CACHE='$GEMM_ENABLE_B_CACHE'. Supported values: 0, 1"
}

# --------------------------------------------------
# GEMM B-cache dimension parameters
#
# Default:
#   GEMM_B_CACHE_MAX_K=4 and GEMM_B_CACHE_MAX_N=4 preserve
#   the baseline cache configuration unless explicitly overridden.
#
# Manual cache scaling run:
#   set GEMM_ENABLE_B_CACHE 1
#   set GEMM_B_CACHE_MAX_K 8
#   set GEMM_B_CACHE_MAX_N 8
#   do run_uvm.tcl
# --------------------------------------------------
if {![info exists GEMM_B_CACHE_MAX_K]} {
    set GEMM_B_CACHE_MAX_K 4
}

if {$GEMM_B_CACHE_MAX_K <= 0} {
    error "Unsupported GEMM_B_CACHE_MAX_K='$GEMM_B_CACHE_MAX_K'. Must be > 0"
}

if {![info exists GEMM_B_CACHE_MAX_N]} {
    set GEMM_B_CACHE_MAX_N 4
}

if {$GEMM_B_CACHE_MAX_N <= 0} {
    error "Unsupported GEMM_B_CACHE_MAX_N='$GEMM_B_CACHE_MAX_N'. Must be > 0"
}

# --------------------------------------------------
# GEMM packed B-cache preload parameter
#
# Default:
#   GEMM_ENABLE_PACKED_BCACHE_PRELOAD=0 keeps the current baseline.
#
# Manual packed B-cache preload run:
#   set GEMM_ENABLE_B_CACHE 1
#   set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
#   do run_uvm.tcl
# --------------------------------------------------
if {![info exists GEMM_ENABLE_PACKED_BCACHE_PRELOAD]} {
    set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 0
}

if {($GEMM_ENABLE_PACKED_BCACHE_PRELOAD != 0) && ($GEMM_ENABLE_PACKED_BCACHE_PRELOAD != 1)} {
    error "Unsupported GEMM_ENABLE_PACKED_BCACHE_PRELOAD='$GEMM_ENABLE_PACKED_BCACHE_PRELOAD'. Supported values: 0, 1"
}

# --------------------------------------------------
# GEMM A-row cache parameters
#
# Default:
#   GEMM_ENABLE_A_ROW_CACHE=0 keeps A-row cache disabled unless
#   explicitly overridden.
#
# Manual A-row cache run:
#   set GEMM_MAC_LANES 2
#   set GEMM_ENABLE_B_CACHE 1
#   set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
#   set GEMM_ENABLE_A_ROW_CACHE 1
#   set GEMM_A_ROW_CACHE_MAX_K 4
#   do run_uvm.tcl
#
# Note:
#   A-row cache is enabled only when the RTL parameter is explicitly set.
# --------------------------------------------------
if {![info exists GEMM_ENABLE_A_ROW_CACHE]} {
    set GEMM_ENABLE_A_ROW_CACHE 0
}

if {($GEMM_ENABLE_A_ROW_CACHE != 0) && ($GEMM_ENABLE_A_ROW_CACHE != 1)} {
    error "Unsupported GEMM_ENABLE_A_ROW_CACHE='$GEMM_ENABLE_A_ROW_CACHE'. Supported values: 0, 1"
}

if {![info exists GEMM_A_ROW_CACHE_MAX_K]} {
    set GEMM_A_ROW_CACHE_MAX_K 4
}

if {$GEMM_A_ROW_CACHE_MAX_K <= 0} {
    error "Unsupported GEMM_A_ROW_CACHE_MAX_K='$GEMM_A_ROW_CACHE_MAX_K'. Must be > 0"
}

# --------------------------------------------------
# GEMM packed A-row preload parameter
#
# Default:
#   GEMM_ENABLE_PACKED_A_ROW_PRELOAD=0 keeps packed A-row preload
#   disabled unless explicitly overridden.
#
# Manual packed A-row preload run:
#   set GEMM_MAC_LANES 2
#   set GEMM_ENABLE_B_CACHE 1
#   set GEMM_ENABLE_PACKED_BCACHE_PRELOAD 1
#   set GEMM_ENABLE_A_ROW_CACHE 1
#   set GEMM_A_ROW_CACHE_MAX_K 4
#   set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 1
#   do run_uvm.tcl
#
# Note:
#   Packed A-row preload is enabled only when the RTL parameter is explicitly set.
# --------------------------------------------------
if {![info exists GEMM_ENABLE_PACKED_A_ROW_PRELOAD]} {
    set GEMM_ENABLE_PACKED_A_ROW_PRELOAD 0
}

if {($GEMM_ENABLE_PACKED_A_ROW_PRELOAD != 0) && ($GEMM_ENABLE_PACKED_A_ROW_PRELOAD != 1)} {
    error "Unsupported GEMM_ENABLE_PACKED_A_ROW_PRELOAD='$GEMM_ENABLE_PACKED_A_ROW_PRELOAD'. Supported values: 0, 1"
}

# --------------------------------------------------
# GEMM K-tiling parameters
#
# Default:
#   GEMM_ENABLE_K_TILING=0 keeps K tiling disabled unless explicitly overridden.
#
# Manual K-tiling run:
#   set GEMM_ENABLE_K_TILING 1
#   set GEMM_K_TILE_SIZE 8
#   do run_uvm.tcl
#
# Note:
#   K tiling is enabled only when the RTL parameter is explicitly set.
# --------------------------------------------------
if {![info exists GEMM_ENABLE_K_TILING]} {
    set GEMM_ENABLE_K_TILING 0
}

if {($GEMM_ENABLE_K_TILING != 0) && ($GEMM_ENABLE_K_TILING != 1)} {
    error "Unsupported GEMM_ENABLE_K_TILING='$GEMM_ENABLE_K_TILING'. Supported values: 0, 1"
}

if {![info exists GEMM_K_TILE_SIZE]} {
    set GEMM_K_TILE_SIZE 8
}

if {$GEMM_K_TILE_SIZE <= 0} {
    error "Unsupported GEMM_K_TILE_SIZE='$GEMM_K_TILE_SIZE'. Must be > 0"
}


# --------------------------------------------------
# GEMM N-tiling parameters
#
# Default:
#   GEMM_ENABLE_N_TILING=0 keeps N tiling disabled unless explicitly overridden.
#
# Manual N-tiling run:
#   set GEMM_ENABLE_N_TILING 1
#   set GEMM_N_TILE_SIZE 8
#   do run_uvm.tcl
#
# Note:
#   N tiling is enabled only when the RTL parameter is explicitly set.
# --------------------------------------------------
if {![info exists GEMM_ENABLE_N_TILING]} {
    set GEMM_ENABLE_N_TILING 0
}

if {($GEMM_ENABLE_N_TILING != 0) && ($GEMM_ENABLE_N_TILING != 1)} {
    error "Unsupported GEMM_ENABLE_N_TILING='$GEMM_ENABLE_N_TILING'. Supported values: 0, 1"
}

if {![info exists GEMM_N_TILE_SIZE]} {
    set GEMM_N_TILE_SIZE 8
}

if {$GEMM_N_TILE_SIZE <= 0} {
    error "Unsupported GEMM_N_TILE_SIZE='$GEMM_N_TILE_SIZE'. Must be > 0"
}

# --------------------------------------------------
# GEMM M-tiling parameters
#
# Default:
#   GEMM_ENABLE_M_TILING=0 keeps M tiling disabled unless explicitly overridden.
#
# Manual M-tiling run:
#   set GEMM_ENABLE_M_TILING 1
#   set GEMM_M_TILE_SIZE 2
#   do run_uvm.tcl
#
# Note:
#   P12B only propagates/elaborates the parameters. RTL compute
#   behavior remains the K+N tiling path until the multi-row
#   tile scheduler is implemented in a later step.
# --------------------------------------------------
if {![info exists GEMM_ENABLE_M_TILING]} {
    set GEMM_ENABLE_M_TILING 0
}

if {($GEMM_ENABLE_M_TILING != 0) && ($GEMM_ENABLE_M_TILING != 1)} {
    error "Unsupported GEMM_ENABLE_M_TILING='$GEMM_ENABLE_M_TILING'. Supported values: 0, 1"
}

if {![info exists GEMM_M_TILE_SIZE]} {
    set GEMM_M_TILE_SIZE 2
}

if {$GEMM_M_TILE_SIZE <= 0} {
    error "Unsupported GEMM_M_TILE_SIZE='$GEMM_M_TILE_SIZE'. Must be > 0"
}

# --------------------------------------------------
# GEMM C RMW accumulation parameter
#
# Default:
#   GEMM_ENABLE_C_RMW_ACCUM=0 keeps C RMW accumulation disabled
#   unless explicitly overridden.
#
# Manual C RMW accumulation plumbing smoke:
#   set GEMM_ENABLE_C_RMW_ACCUM 1
#   set ACCUMULATE_ENABLE 0
#   do run_uvm.tcl
#
# Note:
#   C RMW accumulation is enabled only when the RTL parameter is explicitly set.
# --------------------------------------------------
if {![info exists GEMM_ENABLE_C_RMW_ACCUM]} {
    if {$UVM_TEST eq "ai_accel_subsys_csr_recipe_c_rmw_two_slot_smoke_test"} {
        set GEMM_ENABLE_C_RMW_ACCUM 1
    } else {
        set GEMM_ENABLE_C_RMW_ACCUM 0
    }
}

if {($GEMM_ENABLE_C_RMW_ACCUM != 0) && ($GEMM_ENABLE_C_RMW_ACCUM != 1)} {
    error "Unsupported GEMM_ENABLE_C_RMW_ACCUM='$GEMM_ENABLE_C_RMW_ACCUM'. Supported values: 0, 1"
}



puts "\[run_uvm\] UVM_TOP=$UVM_TOP UVM_TEST=$UVM_TEST CASE_ID=$CASE_ID ENABLE_RESULT_CHECK=$ENABLE_RESULT_CHECK FORCE_HELPER_MEM_PATH=$FORCE_HELPER_MEM_PATH ACCUMULATE_ENABLE=$ACCUMULATE_ENABLE SMOKE_DONE_TIMEOUT=$SMOKE_DONE_TIMEOUT_MODE"
puts "\[run_uvm\] GEMM_MAC_LANES=$GEMM_MAC_LANES GEMM_ENABLE_B_CACHE=$GEMM_ENABLE_B_CACHE GEMM_B_CACHE_MAX_K=$GEMM_B_CACHE_MAX_K GEMM_B_CACHE_MAX_N=$GEMM_B_CACHE_MAX_N GEMM_ENABLE_PACKED_BCACHE_PRELOAD=$GEMM_ENABLE_PACKED_BCACHE_PRELOAD GEMM_ENABLE_A_ROW_CACHE=$GEMM_ENABLE_A_ROW_CACHE GEMM_A_ROW_CACHE_MAX_K=$GEMM_A_ROW_CACHE_MAX_K GEMM_ENABLE_PACKED_A_ROW_PRELOAD=$GEMM_ENABLE_PACKED_A_ROW_PRELOAD GEMM_ENABLE_K_TILING=$GEMM_ENABLE_K_TILING GEMM_K_TILE_SIZE=$GEMM_K_TILE_SIZE GEMM_ENABLE_N_TILING=$GEMM_ENABLE_N_TILING GEMM_N_TILE_SIZE=$GEMM_N_TILE_SIZE GEMM_ENABLE_M_TILING=$GEMM_ENABLE_M_TILING GEMM_M_TILE_SIZE=$GEMM_M_TILE_SIZE GEMM_ENABLE_C_RMW_ACCUM=$GEMM_ENABLE_C_RMW_ACCUM"


# --------------------------------------------------
# Extra plusargs
#
#   Optional escape hatch for temporary debug knobs.
#
#   Example:
#     set EXTRA_PLUSARGS "+FOO=1 +BAR=2"
# --------------------------------------------------
if {![info exists EXTRA_PLUSARGS]} {
    set EXTRA_PLUSARGS [list]
}

# --------------------------------------------------
# Transcript log naming
#
# Format:
#   YYYYMMDD_HHMMSS_<test_specific_name>.log
# --------------------------------------------------
set LOG_DATE_PREFIX [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]

if {($UVM_TEST eq "ai_accel_csr_regs_smoke_test") ||
    ($UVM_TEST eq "ai_accel_subsys_csr_smoke_test") ||
    ($UVM_TEST eq "ai_accel_subsys_csr_dma_load_store_smoke_test") ||
              ($UVM_TEST eq "ai_accel_subsys_csr_axis_stream_load_store_smoke_test") ||
              ($UVM_TEST eq "ai_accel_subsys_csr_direct_stream_load_store_smoke_test") ||
              ($UVM_TEST eq "ai_accel_subsys_csr_job_dma_load_store_smoke_test") ||
              ($UVM_TEST eq "ai_accel_subsys_csr_job_reject_error_test") ||
              ($UVM_TEST eq "ai_accel_subsys_csr_job_axis_stream_load_store_smoke_test") ||
              ($UVM_TEST eq "ai_accel_subsys_csr_job_direct_stream_load_store_smoke_test") ||
              ($UVM_TEST eq "ai_accel_subsys_csr_recipe_dma_two_slot_smoke_test") ||
              ($UVM_TEST eq "ai_accel_subsys_csr_recipe_c_rmw_two_slot_smoke_test") ||
              ($UVM_TEST eq "ai_accel_subsys_csr_recipe_axis_stream_two_slot_smoke_test") ||
              ($UVM_TEST eq "ai_accel_subsys_csr_recipe_direct_stream_two_slot_smoke_test") ||
              ($UVM_TEST eq "ai_accel_subsys_csr_recipe_reject_error_test")} {
    set LOG_BASENAME ${UVM_TEST}_${UVM_TOP}_case_${CASE_ID}_result_${ENABLE_RESULT_CHECK}_${MEM_PATH_MODE}.log

} elseif {$UVM_TEST eq "ai_accel_subsys_back_to_back_test"} {
    set LOG_BASENAME ${UVM_TEST}_jobs_${JOB_COUNT}_${JOB0_CASE_ID}_${JOB1_CASE_ID}_${JOB2_CASE_ID}_${JOB3_CASE_ID}_result_${ENABLE_RESULT_CHECK}_${MEM_PATH_MODE}.log

} elseif {$UVM_TEST eq "ai_accel_subsys_corner_test"} {
    if {[llength $JOB_ARG_LIST] == 0} {
        set LOG_BASENAME ${UVM_TEST}_class_default_result_${ENABLE_RESULT_CHECK}_${MEM_PATH_MODE}.log
    } else {
        set LOG_BASENAME ${UVM_TEST}_job_override_result_${ENABLE_RESULT_CHECK}_${MEM_PATH_MODE}.log
    }

} elseif {$UVM_TEST eq "ai_accel_subsys_reset_recovery_test"} {
    set LOG_BASENAME ${UVM_TEST}_pre_${PRE_RESET_CASE_ID}_post_${POST_RESET_CASE_ID}_hold_${RESET_HOLD_CYCLES}_settle_${POST_RESET_SETTLE_CYCLES}_result_${ENABLE_RESULT_CHECK}_${MEM_PATH_MODE}.log

} elseif {($UVM_TEST eq "ai_accel_subsys_dma_load_smoke_test") ||
          ($UVM_TEST eq "ai_accel_subsys_dma_store_smoke_test") ||
          ($UVM_TEST eq "ai_accel_subsys_axis_stream_preload_smoke_test") ||
          ($UVM_TEST eq "ai_accel_subsys_direct_stream_smoke_test") ||
          ($UVM_TEST eq "ai_accel_subsys_perf_counter_smoke_test") ||
          ($UVM_TEST eq "ai_accel_subsys_c_rmw_accum_ref_model_test") ||
          ($UVM_TEST eq "ai_accel_subsys_c_rmw_accum_dut_test")} {
    if {$RUN_ALL} {
        set LOG_BASENAME ${UVM_TEST}_run_all_result_${ENABLE_RESULT_CHECK}_${MEM_PATH_MODE}.log
    } else {
        set LOG_BASENAME ${UVM_TEST}_case_${CASE_ID}_result_${ENABLE_RESULT_CHECK}_${MEM_PATH_MODE}.log
    }

} elseif {$UVM_TEST eq "ai_accel_subsys_perf_profile_test"} {
    set LOG_BASENAME ${UVM_TEST}_profile_result_${ENABLE_RESULT_CHECK}_${MEM_PATH_MODE}.log

} elseif {$UVM_TEST eq "ai_accel_subsys_dma_load_error_test"} {
    set LOG_BASENAME ${UVM_TEST}_error_recovery_result_${ENABLE_RESULT_CHECK}_${MEM_PATH_MODE}.log

} elseif {$UVM_TEST eq "ai_accel_subsys_dma_store_error_test"} {
    set LOG_BASENAME ${UVM_TEST}_${DMA_STORE_ERROR_MODE}_result_${ENABLE_RESULT_CHECK}_${MEM_PATH_MODE}.log

} elseif {$UVM_TEST eq "ai_accel_subsys_dma_load_stress_test"} {
    set LOG_BASENAME ${UVM_TEST}_jobs_${STRESS_JOB_COUNT}_seed_${STRESS_SEED}_random_${STRESS_RANDOM}_gap_${STRESS_GAP_CYCLES}_result_${ENABLE_RESULT_CHECK}_${MEM_PATH_MODE}.log

} elseif {$UVM_TEST eq "ai_accel_subsys_dma_load_store_stress_test"} {
    set LOG_BASENAME ${UVM_TEST}_jobs_${STORE_STRESS_JOB_COUNT}_seed_${STORE_STRESS_SEED}_random_${STORE_STRESS_RANDOM}_gap_${STORE_STRESS_GAP_CYCLES}_result_${ENABLE_RESULT_CHECK}_${MEM_PATH_MODE}.log

} else {
    set LOG_BASENAME ${UVM_TEST}_case_${CASE_ID}_result_${ENABLE_RESULT_CHECK}_${MEM_PATH_MODE}.log
}

# --------------------------------------------------
# Compact transcript log naming
#
# Questa on Windows can fail to open transcript files
# when the resolved path becomes too long. Keep names
# readable, but shorten common regression tokens.
# --------------------------------------------------
set LOG_BASENAME [string map [list \
    "ai_accel_subsys_" "aas_" \
    "ai_accel_csr_regs_smoke_test" "csr_regs_smoke" \
    "ai_accel_subsys_csr_dma_load_store_smoke_test" "csr_dma_ls_smoke" \
    "ai_accel_subsys_csr_axis_stream_load_store_smoke_test" "csr_axis_ls_smoke" \
    "ai_accel_subsys_csr_direct_stream_load_store_smoke_test" "csr_ds_ls_smoke" \
    "ai_accel_subsys_csr_job_dma_load_store_smoke_test" "csr_job_dma_ls" \
    "ai_accel_subsys_csr_job_reject_error_test" "csr_job_reject" \
    "ai_accel_subsys_csr_job_axis_stream_load_store_smoke_test" "csr_job_axis_ls" \
    "ai_accel_subsys_csr_job_direct_stream_load_store_smoke_test" "csr_job_ds_ls" \
    "ai_accel_subsys_csr_recipe_dma_two_slot_smoke_test" "csr_recipe_dma_2slot" \
    "ai_accel_subsys_csr_recipe_c_rmw_two_slot_smoke_test" "csr_recipe_c_rmw_2slot" \
    "ai_accel_subsys_csr_recipe_axis_stream_two_slot_smoke_test" "csr_recipe_axis_2slot" \
    "ai_accel_subsys_csr_recipe_direct_stream_two_slot_smoke_test" "csr_recipe_ds_2slot" \
    "ai_accel_subsys_csr_recipe_reject_error_test" "csr_recipe_reject" \
    "ai_accel_subsys_csr_smoke_test" "csr_subsys_smoke" \
    "ai_accel_csr_regs_uvm_top" "csr_regs_top" \
    "ai_accel_subsys_csr_uvm_top" "aas_csr_top" \
    "axis_stream_load_store_stress_test" "axis_ls_stress" \
    "direct_stream_load_store_stress_test" "ds_ls_stress" \
    "dma_load_store_stress_test" "dma_ls_stress" \
    "axis_stream_preload_smoke_test" "axis_pre_smoke" \
    "axis_stream_preload_error_test" "axis_pre_err" \
    "direct_stream_smoke_test" "ds_smoke" \
    "direct_stream_error_test" "ds_err" \
    "dma_load_smoke_test" "dma_l_smoke" \
    "dma_load_error_test" "dma_l_err" \
    "dma_load_stress_test" "dma_l_stress" \
    "dma_store_smoke_test" "dma_s_smoke" \
    "dma_store_error_test" "dma_s_err" \
    "perf_counter_smoke_test" "perf_cnt" \
    "perf_profile_test" "perf_prof" \
    "c_rmw_accum_ref_model_test" "c_rmw_ref" \
    "c_rmw_accum_dut_test" "c_rmw_dut" \
    "back_to_back_test" "b2b" \
    "reset_recovery_test" "rst_rec" \
    "corner_test" "corner" \
    "midrun_reset_test" "mid_rst" \
    "smoke_test" "smoke" \
    "_result_" "_r" \
    "_host_primary" "_host" \
    "_helper_fallback" "_helper" \
    "_jobs_" "_j" \
    "_seed_" "_s" \
    "_random_" "_rnd" \
    "_gap_" "_g" \
    "_case_" "_c" \
] $LOG_BASENAME]

# Add compact GEMM feature tags.
#
# l  = GEMM_MAC_LANES
# bc = GEMM_ENABLE_B_CACHE
# bk = GEMM_B_CACHE_MAX_K
# bn = GEMM_B_CACHE_MAX_N
# pb = GEMM_ENABLE_PACKED_BCACHE_PRELOAD
# ar = GEMM_ENABLE_A_ROW_CACHE
# ak = GEMM_A_ROW_CACHE_MAX_K
# pa = GEMM_ENABLE_PACKED_A_ROW_PRELOAD
# kt = GEMM_ENABLE_K_TILING
# ks = GEMM_K_TILE_SIZE
# nt = GEMM_ENABLE_N_TILING
# ns = GEMM_N_TILE_SIZE
# mt = GEMM_ENABLE_M_TILING
# ms = GEMM_M_TILE_SIZE
# cr = GEMM_ENABLE_C_RMW_ACCUM
# ae = ACCUMULATE_ENABLE
if {$UVM_TOP ne "ai_accel_csr_regs_uvm_top"} {
    set LOG_BASENAME [string map [list ".log" "_l${GEMM_MAC_LANES}_bc${GEMM_ENABLE_B_CACHE}_bk${GEMM_B_CACHE_MAX_K}_bn${GEMM_B_CACHE_MAX_N}_pb${GEMM_ENABLE_PACKED_BCACHE_PRELOAD}_ar${GEMM_ENABLE_A_ROW_CACHE}_ak${GEMM_A_ROW_CACHE_MAX_K}_pa${GEMM_ENABLE_PACKED_A_ROW_PRELOAD}_kt${GEMM_ENABLE_K_TILING}_ks${GEMM_K_TILE_SIZE}_nt${GEMM_ENABLE_N_TILING}_ns${GEMM_N_TILE_SIZE}_mt${GEMM_ENABLE_M_TILING}_ms${GEMM_M_TILE_SIZE}_cr${GEMM_ENABLE_C_RMW_ACCUM}_ae${ACCUMULATE_ENABLE}.log"] $LOG_BASENAME]
}

set LOG_FILE logs/${LOG_DATE_PREFIX}_${LOG_BASENAME}

# Defensive: keep this close to transcript file in case the script is
# invoked from a clean working directory or logs/ was deleted mid-session.
file mkdir [file dirname $LOG_FILE]

transcript file $LOG_FILE
transcript on

# --------------------------------------------------
# Run simulation
#
# Existing subsystem tops receive GEMM generics and subsystem plusargs.
# The standalone CSR register top is a unit-level CSR smoke and does
# not have GEMM generics.
# --------------------------------------------------
if {$UVM_TOP eq "ai_accel_csr_regs_uvm_top"} {
    vsim -L uvm12 \
      -voptargs=+acc \
      work.$UVM_TOP \
      -uvmcontrol=all \
      +UVM_TESTNAME=$UVM_TEST \
      {*}$EXTRA_PLUSARGS
} else {
    vsim -L uvm12 \
      -voptargs=+acc \
      -gGEMM_MAC_LANES=$GEMM_MAC_LANES \
      -gGEMM_ENABLE_B_CACHE=$GEMM_ENABLE_B_CACHE \
      -gGEMM_B_CACHE_MAX_K=$GEMM_B_CACHE_MAX_K \
      -gGEMM_B_CACHE_MAX_N=$GEMM_B_CACHE_MAX_N \
      -gGEMM_ENABLE_PACKED_BCACHE_PRELOAD=$GEMM_ENABLE_PACKED_BCACHE_PRELOAD \
      -gGEMM_ENABLE_A_ROW_CACHE=$GEMM_ENABLE_A_ROW_CACHE \
      -gGEMM_A_ROW_CACHE_MAX_K=$GEMM_A_ROW_CACHE_MAX_K \
      -gGEMM_ENABLE_PACKED_A_ROW_PRELOAD=$GEMM_ENABLE_PACKED_A_ROW_PRELOAD \
      -gGEMM_ENABLE_K_TILING=$GEMM_ENABLE_K_TILING \
      -gGEMM_K_TILE_SIZE=$GEMM_K_TILE_SIZE \
      -gGEMM_ENABLE_N_TILING=$GEMM_ENABLE_N_TILING \
      -gGEMM_N_TILE_SIZE=$GEMM_N_TILE_SIZE \
      -gGEMM_ENABLE_M_TILING=$GEMM_ENABLE_M_TILING \
      -gGEMM_M_TILE_SIZE=$GEMM_M_TILE_SIZE \
      -gGEMM_ENABLE_C_RMW_ACCUM=$GEMM_ENABLE_C_RMW_ACCUM \
      work.$UVM_TOP \
      -uvmcontrol=all \
      +UVM_TESTNAME=$UVM_TEST \
      +CASE_ID=$CASE_ID \
      +ENABLE_RESULT_CHECK=$ENABLE_RESULT_CHECK \
      +FORCE_HELPER_MEM_PATH=$FORCE_HELPER_MEM_PATH \
      +ACCUMULATE_ENABLE=$ACCUMULATE_ENABLE \
      {*}$SMOKE_DONE_TIMEOUT_ARG_LIST \
      {*}$LEGACY_HOST_OVERRIDE_ARGS \
      {*}$JOB_ARG_LIST \
      {*}$DMA_SMOKE_ARG_LIST \
      {*}$DMA_LOAD_STRESS_ARG_LIST \
      {*}$DMA_LOAD_STORE_STRESS_ARG_LIST \
      {*}$DMA_STORE_ERROR_ARG_LIST \
      {*}$EXTRA_ARGS \
      {*}$CLOCK_ARG_LIST \
      +PRE_RESET_CASE_ID=$PRE_RESET_CASE_ID \
      +POST_RESET_CASE_ID=$POST_RESET_CASE_ID \
      +RESET_HOLD_CYCLES=$RESET_HOLD_CYCLES \
      +POST_RESET_SETTLE_CYCLES=$POST_RESET_SETTLE_CYCLES \
      {*}$EXTRA_PLUSARGS
}

# --------------------------------------------------
# Suppress GUI confirmation dialog when UVM calls $finish
# --------------------------------------------------
onfinish stop

add wave -r sim:/*
run -all

transcript off

# --------------------------------------------------
# Keep only the newest LOG_KEEP_COUNT log files
# --------------------------------------------------
prune_old_logs logs $LOG_KEEP_COUNT
