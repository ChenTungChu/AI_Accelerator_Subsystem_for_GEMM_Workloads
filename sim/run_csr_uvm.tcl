# File: sim/run_csr_uvm.tcl
file mkdir logs

# --------------------------------------------------
# Select CSR UVM test
# --------------------------------------------------
set SUPPORTED_CSR_UVM_TESTS [list \
    ai_accel_csr_regs_smoke_test \
]

if {![info exists UVM_TEST] && [info exists TESTNAME]} {
    set UVM_TEST $TESTNAME
}

if {![info exists UVM_TEST]} {
    set UVM_TEST ai_accel_csr_regs_smoke_test
}

if {[lsearch -exact $SUPPORTED_CSR_UVM_TESTS $UVM_TEST] < 0} {
    error "Unsupported CSR UVM_TEST='$UVM_TEST'. Supported tests: $SUPPORTED_CSR_UVM_TESTS"
}

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

set LOG_DATE_PREFIX [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
set LOG_FILE logs/${LOG_DATE_PREFIX}_${UVM_TEST}.log

transcript file $LOG_FILE
transcript on

vsim -L uvm12 \
  -voptargs=+acc \
  work.ai_accel_csr_regs_uvm_top \
  -uvmcontrol=all \
  +UVM_TESTNAME=$UVM_TEST

onfinish stop

add wave -r sim:/*
run -all

transcript off

prune_old_logs logs $LOG_KEEP_COUNT
