file mkdir logs

# --------------------------------------------------
# Select UVM test
#   default: ai_accel_subsys_smoke_test
#
#   Supported tests:
#     ai_accel_subsys_smoke_test
#     ai_accel_subsys_back_to_back_test
#     ai_accel_subsys_reset_recovery_test
# --------------------------------------------------
if {![info exists UVM_TEST]} {
    set UVM_TEST ai_accel_subsys_smoke_test
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
#     - enables memory-path policy in tests
# --------------------------------------------------
if {![info exists ENABLE_RESULT_CHECK]} {
    set ENABLE_RESULT_CHECK 0
}

# --------------------------------------------------
# Memory Path Policy (Policy B)
#
#   Default:
#     ENABLE_RESULT_CHECK=1
#       -> use host-agent memory path
#
#   Fallback:
#     FORCE_HELPER_MEM_PATH=1
#       -> force helper memory path
#
#   Notes:
#     - host agent is the primary path
#     - helper is fallback / debug only
# --------------------------------------------------
if {![info exists FORCE_HELPER_MEM_PATH]} {
    set FORCE_HELPER_MEM_PATH 0
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
# Back-to-back test knobs
#   used by ai_accel_subsys_back_to_back_test
# --------------------------------------------------
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
#
#   Log name includes the main knobs that affect test mode,
#   so different runs are easier to distinguish.
# --------------------------------------------------
if {$UVM_TEST eq "ai_accel_subsys_back_to_back_test"} {
    transcript file logs/${UVM_TEST}_jobs_${JOB_COUNT}_${JOB0_CASE_ID}_${JOB1_CASE_ID}_${JOB2_CASE_ID}_${JOB3_CASE_ID}_result_${ENABLE_RESULT_CHECK}_forcehelper_${FORCE_HELPER_MEM_PATH}.log
} elseif {$UVM_TEST eq "ai_accel_subsys_reset_recovery_test"} {
    transcript file logs/${UVM_TEST}_pre_${PRE_RESET_CASE_ID}_post_${POST_RESET_CASE_ID}_hold_${RESET_HOLD_CYCLES}_settle_${POST_RESET_SETTLE_CYCLES}_result_${ENABLE_RESULT_CHECK}_forcehelper_${FORCE_HELPER_MEM_PATH}.log
} else {
    transcript file logs/${UVM_TEST}_case_${CASE_ID}_result_${ENABLE_RESULT_CHECK}_forcehelper_${FORCE_HELPER_MEM_PATH}.log
}
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
  +JOB_COUNT=$JOB_COUNT \
  +JOB0_CASE_ID=$JOB0_CASE_ID \
  +JOB1_CASE_ID=$JOB1_CASE_ID \
  +JOB2_CASE_ID=$JOB2_CASE_ID \
  +JOB3_CASE_ID=$JOB3_CASE_ID \
  +PRE_RESET_CASE_ID=$PRE_RESET_CASE_ID \
  +POST_RESET_CASE_ID=$POST_RESET_CASE_ID \
  +RESET_HOLD_CYCLES=$RESET_HOLD_CYCLES \
  +POST_RESET_SETTLE_CYCLES=$POST_RESET_SETTLE_CYCLES

add wave -r sim:/*
run -all

transcript off