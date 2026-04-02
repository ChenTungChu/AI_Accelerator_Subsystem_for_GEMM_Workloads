file mkdir logs

# --------------------------------------------------
# Select case
#   default CASE=0
#   usage examples:
#     do run.tcl
#     set CASE_ID 1; do run.tcl
# --------------------------------------------------
if {![info exists CASE_ID]} {
    set CASE_ID 0
}

# --------------------------------------------------
# Transcript log
# --------------------------------------------------
transcript file logs/case_${CASE_ID}.log
transcript on

# --------------------------------------------------
# Run sim
# --------------------------------------------------
vsim -voptargs=+acc work.ai_accel_subsystem_tb_top +CASE=$CASE_ID

add wave -r sim:/*
run -all

transcript off