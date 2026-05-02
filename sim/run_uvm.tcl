file mkdir logs

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
]

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
# Smoke-test case selection
#   used by ai_accel_subsys_smoke_test
# --------------------------------------------------
if {![info exists CASE_ID]} {
    set CASE_ID 0
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

# --------------------------------------------------
# Build optional legacy override arg list
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
# Transcript log naming
# --------------------------------------------------
if {$UVM_TEST eq "ai_accel_subsys_back_to_back_test"} {
    set LOG_FILE logs/${UVM_TEST}_jobs_${JOB_COUNT}_${JOB0_CASE_ID}_${JOB1_CASE_ID}_${JOB2_CASE_ID}_${JOB3_CASE_ID}_result_${ENABLE_RESULT_CHECK}_${MEM_PATH_MODE}.log
} elseif {$UVM_TEST eq "ai_accel_subsys_corner_test"} {
    if {[llength $JOB_ARG_LIST] == 0} {
        set LOG_FILE logs/${UVM_TEST}_class_default_result_${ENABLE_RESULT_CHECK}_${MEM_PATH_MODE}.log
    } else {
        set LOG_FILE logs/${UVM_TEST}_job_override_result_${ENABLE_RESULT_CHECK}_${MEM_PATH_MODE}.log
    }
} elseif {$UVM_TEST eq "ai_accel_subsys_reset_recovery_test"} {
    set LOG_FILE logs/${UVM_TEST}_pre_${PRE_RESET_CASE_ID}_post_${POST_RESET_CASE_ID}_hold_${RESET_HOLD_CYCLES}_settle_${POST_RESET_SETTLE_CYCLES}_result_${ENABLE_RESULT_CHECK}_${MEM_PATH_MODE}.log
} else {
    set LOG_FILE logs/${UVM_TEST}_case_${CASE_ID}_result_${ENABLE_RESULT_CHECK}_${MEM_PATH_MODE}.log
}

transcript file $LOG_FILE
transcript on

# --------------------------------------------------
# Run simulation
#
#   Policy knobs:
#     +ENABLE_RESULT_CHECK
#     +FORCE_HELPER_MEM_PATH
#
#   Optional legacy overrides are forwarded only when
#   explicitly set in the Tcl session.
# --------------------------------------------------
vsim -L uvm12 -voptargs=+acc work.ai_accel_subsys_uvm_top \
  -uvmcontrol=all \
  +UVM_TESTNAME=$UVM_TEST \
  +CASE_ID=$CASE_ID \
  +ENABLE_RESULT_CHECK=$ENABLE_RESULT_CHECK \
  +FORCE_HELPER_MEM_PATH=$FORCE_HELPER_MEM_PATH \
  {*}$LEGACY_HOST_OVERRIDE_ARGS \
  {*}$JOB_ARG_LIST \
  +PRE_RESET_CASE_ID=$PRE_RESET_CASE_ID \
  +POST_RESET_CASE_ID=$POST_RESET_CASE_ID \
  +RESET_HOLD_CYCLES=$RESET_HOLD_CYCLES \
  +POST_RESET_SETTLE_CYCLES=$POST_RESET_SETTLE_CYCLES

add wave -r sim:/*
run -all

transcript off