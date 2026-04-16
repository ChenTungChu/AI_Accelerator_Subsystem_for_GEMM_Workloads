file mkdir logs

# --------------------------------------------------
# Select UVM test
#   default: ai_accel_subsys_smoke_test
#   usage examples:
#     do run_uvm.tcl
#     set UVM_TEST ai_accel_subsys_smoke_test; do run_uvm.tcl
# --------------------------------------------------
if {![info exists UVM_TEST]} {
    set UVM_TEST ai_accel_subsys_smoke_test
}

# --------------------------------------------------
# Transcript log
# --------------------------------------------------
transcript file logs/${UVM_TEST}.log
transcript on

# --------------------------------------------------
# Run sim
# --------------------------------------------------
vsim -L uvm12 -voptargs=+acc work.ai_accel_subsys_uvm_top \
  -uvmcontrol=all \
  +UVM_TESTNAME=$UVM_TEST

add wave -r sim:/*
run -all

transcript off