file mkdir logs

# --------------------------------------------------
# Select UVM test
#   default: ai_accel_subsys_smoke_test
# --------------------------------------------------
if {![info exists UVM_TEST]} {
    set UVM_TEST ai_accel_subsys_smoke_test
}

# --------------------------------------------------
# Select CASE_ID
#   default: 0
#   examples:
#     do run_uvm.tcl
#     set CASE_ID 101; do run_uvm.tcl
#     set CASE_ID 400; do run_uvm.tcl
# --------------------------------------------------
if {![info exists CASE_ID]} {
    set CASE_ID 0
}

# --------------------------------------------------
# Enable result checking
#   default: 0
#   examples:
#     set ENABLE_RESULT_CHECK 1; do run_uvm.tcl
# --------------------------------------------------
if {![info exists ENABLE_RESULT_CHECK]} {
    set ENABLE_RESULT_CHECK 0
}

# --------------------------------------------------
# Transcript log
# --------------------------------------------------
transcript file logs/${UVM_TEST}_case_${CASE_ID}_result_${ENABLE_RESULT_CHECK}.log
transcript on

# --------------------------------------------------
# Run sim
# --------------------------------------------------
vsim -L uvm12 -voptargs=+acc work.ai_accel_subsys_uvm_top \
  -uvmcontrol=all \
  +UVM_TESTNAME=$UVM_TEST \
  +CASE_ID=$CASE_ID \
  +ENABLE_RESULT_CHECK=$ENABLE_RESULT_CHECK

add wave -r sim:/*
run -all

transcript off