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
# RC-COV / CODE-COV UCDB collection / merge controls
#
# Default full-regression behavior:
#   - RC-COV enabled
#   - CODE-COV disabled
#
# Functional coverage:
#   set RC_COV_ENABLE 1
#
# RTL code coverage:
#   set CODE_COV_ENABLE 1
#   set DO_COMPILE 1
#
# RC-COV and CODE-COV intentionally run separately so the
# generated UCDBs and reports remain independent.
# ============================================================
if {![info exists CODE_COV_ENABLE]} {
    set CODE_COV_ENABLE 0
}

if {($CODE_COV_ENABLE != 0) && ($CODE_COV_ENABLE != 1)} {
    error "\[REGRESSION\] Unsupported CODE_COV_ENABLE='$CODE_COV_ENABLE'. Supported values: 0, 1"
}

if {![info exists RC_COV_ENABLE]} {
    if {$CODE_COV_ENABLE} {
        set RC_COV_ENABLE 0
    } else {
        set RC_COV_ENABLE 1
    }
}

if {($RC_COV_ENABLE != 0) && ($RC_COV_ENABLE != 1)} {
    error "\[REGRESSION\] Unsupported RC_COV_ENABLE='$RC_COV_ENABLE'. Supported values: 0, 1"
}

if {$RC_COV_ENABLE && $CODE_COV_ENABLE} {
    error "\[REGRESSION\] RC-COV and CODE-COV must run separately"
}

if {![info exists RC_COV_ROOT_DIR]} {
    set RC_COV_ROOT_DIR coverage/rc_cov
}

if {![info exists RC_COV_CLEAN]} {
    set RC_COV_CLEAN 1
}

if {($RC_COV_CLEAN != 0) && ($RC_COV_CLEAN != 1)} {
    error "\[REGRESSION\] Unsupported RC_COV_CLEAN='$RC_COV_CLEAN'. Supported values: 0, 1"
}

set RC_COV_PER_TEST_DIR  [file join $RC_COV_ROOT_DIR per_test]
set RC_COV_MERGED_FILE   [file join $RC_COV_ROOT_DIR rc_cov_merged.ucdb]
set RC_COV_SUMMARY_FILE  [file join $RC_COV_ROOT_DIR rc_cov_summary.txt]
set RC_COV_DETAILS_FILE  [file join $RC_COV_ROOT_DIR rc_cov_details.txt]
set RC_COV_MANIFEST_FILE [file join $RC_COV_ROOT_DIR rc_cov_manifest.tsv]
set RC_COV_FLOW_OK 1

if {$RC_COV_ENABLE} {
    if {$RC_COV_CLEAN} {
        catch {file delete -force $RC_COV_PER_TEST_DIR}
        catch {file delete -force $RC_COV_MERGED_FILE}
        catch {file delete -force $RC_COV_SUMMARY_FILE}
        catch {file delete -force $RC_COV_DETAILS_FILE}
        catch {file delete -force $RC_COV_MANIFEST_FILE}
    }

    file mkdir $RC_COV_PER_TEST_DIR

    set manifest_fp [open $RC_COV_MANIFEST_FILE w]
    puts $manifest_fp "index\tname\tstatus\tlog\tucdb"
    close $manifest_fp

    puts "\[REGRESSION\]\[RC_COV\] Coverage collection enabled"
    puts "\[REGRESSION\]\[RC_COV\] Per-test UCDB dir: $RC_COV_PER_TEST_DIR"
}

if {![info exists CODE_COV_ROOT_DIR]} {
    set CODE_COV_ROOT_DIR coverage/code_cov
}

if {![info exists CODE_COV_CLEAN]} {
    set CODE_COV_CLEAN 1
}

if {($CODE_COV_CLEAN != 0) && ($CODE_COV_CLEAN != 1)} {
    error "\[REGRESSION\] Unsupported CODE_COV_CLEAN='$CODE_COV_CLEAN'. Supported values: 0, 1"
}

if {![info exists CODE_COV_METRICS]} {
    set CODE_COV_METRICS bcefst
}

if {![regexp {^[bcefst]+$} $CODE_COV_METRICS]} {
    error "\[REGRESSION\] Unsupported CODE_COV_METRICS='$CODE_COV_METRICS'. Use only b, c, e, f, s, t"
}

set CODE_COV_PER_TEST_DIR  [file join $CODE_COV_ROOT_DIR per_test]
set CODE_COV_MERGED_FILE   [file join $CODE_COV_ROOT_DIR code_cov_merged.ucdb]
set CODE_COV_SUMMARY_FILE  [file join $CODE_COV_ROOT_DIR code_cov_summary.txt]
set CODE_COV_DETAILS_FILE  [file join $CODE_COV_ROOT_DIR code_cov_details.txt]
set CODE_COV_MANIFEST_FILE [file join $CODE_COV_ROOT_DIR code_cov_manifest.tsv]
set CODE_COV_FLOW_OK 1

if {$CODE_COV_ENABLE} {
    set CODE_COV_MARKER_FILE [file join work .code_cov_instrumented]

    if {![file exists $CODE_COV_MARKER_FILE]} {
        error "\[REGRESSION\] CODE-COV requested, but work was not compiled with CODE_COV_ENABLE=1. Set DO_COMPILE=1 or re-run compile_uvm.tcl with CODE_COV_ENABLE=1"
    }

    set marker_fp [open $CODE_COV_MARKER_FILE r]
    set compiled_code_cov_metrics [string trim [read $marker_fp]]
    close $marker_fp

    if {$compiled_code_cov_metrics ne $CODE_COV_METRICS} {
        error "\[REGRESSION\] CODE-COV metric mismatch: work='$compiled_code_cov_metrics', run='$CODE_COV_METRICS'"
    }

    if {$CODE_COV_CLEAN} {
        catch {file delete -force $CODE_COV_PER_TEST_DIR}
        catch {file delete -force $CODE_COV_MERGED_FILE}
        catch {file delete -force $CODE_COV_SUMMARY_FILE}
        catch {file delete -force $CODE_COV_DETAILS_FILE}
        catch {file delete -force $CODE_COV_MANIFEST_FILE}
    }

    file mkdir $CODE_COV_PER_TEST_DIR

    set manifest_fp [open $CODE_COV_MANIFEST_FILE w]
    puts $manifest_fp "index\tname\tstatus\tlog\tucdb"
    close $manifest_fp

    puts "\[REGRESSION\]\[CODE_COV\] RTL code coverage collection enabled"
    puts "\[REGRESSION\]\[CODE_COV\] Metrics: $CODE_COV_METRICS"
    puts "\[REGRESSION\]\[CODE_COV\] Per-test UCDB dir: $CODE_COV_PER_TEST_DIR"
}

# Preserve all 150 regression logs unless the caller explicitly
# selects a different retention count.
if {![info exists LOG_KEEP_COUNT]} {
    set LOG_KEEP_COUNT 250
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
set REG_COV_FILES {}
set REG_CODE_COV_FILES {}

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

        ENABLE_COVERAGE
        COVERAGE_OUTPUT_DIR
        COVERAGE_RUN_TAG
        COVERAGE_FILE

        ENABLE_CODE_COVERAGE
        CODE_COVERAGE_OUTPUT_DIR
        CODE_COVERAGE_RUN_TAG
        CODE_COVERAGE_FILE

        VSIM_COVERAGE_ARGS

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
# RC-COV utility procs
# ============================================================
proc get_current_coverage_file {} {
    if {[info exists ::COVERAGE_FILE] && ($::COVERAGE_FILE ne "")} {
        return $::COVERAGE_FILE
    }
    return "<COVERAGE_FILE not set>"
}

proc check_ucdb_file {ucdb_file} {
    if {![file exists $ucdb_file]} {
        puts "\[REGRESSION\]\[RC_COV\]\[FAIL\] UCDB file not found: $ucdb_file"
        return 0
    }

    if {[file size $ucdb_file] <= 0} {
        puts "\[REGRESSION\]\[RC_COV\]\[FAIL\] UCDB file is empty: $ucdb_file"
        return 0
    }

    return 1
}

proc append_cov_manifest {idx name status log_file ucdb_file} {
    global RC_COV_ENABLE RC_COV_MANIFEST_FILE

    if {!$RC_COV_ENABLE} {
        return
    }

    set fp [open $RC_COV_MANIFEST_FILE a]
    puts $fp "$idx\t$name\t$status\t$log_file\t$ucdb_file"
    close $fp
}

proc resolve_vcover_executable {} {
    set vsim_exe [info nameofexecutable]
    set bin_dir [file dirname $vsim_exe]

    foreach candidate [list \
        [file join $bin_dir vcover.exe] \
        [file join $bin_dir vcover] \
        vcover] {
        if {($candidate eq "vcover") || [file exists $candidate]} {
            return $candidate
        }
    }

    return "vcover"
}

proc run_external_command {label command_list} {
    puts "\[REGRESSION\]\[RC_COV\] $label"
    puts "\[REGRESSION\]\[RC_COV\] command: [join $command_list { }]"

    set status [catch {
        exec {*}$command_list 2>@1
    } message]

    if {$message ne ""} {
        puts $message
    }

    if {$status != 0} {
        puts "\[REGRESSION\]\[RC_COV\]\[FAIL\] $label failed"
        return 0
    }

    return 1
}

proc finalize_rc_cov {} {
    global RC_COV_ENABLE
    global RC_COV_MERGED_FILE RC_COV_SUMMARY_FILE RC_COV_DETAILS_FILE
    global REG_COV_FILES

    if {!$RC_COV_ENABLE} {
        puts "\[REGRESSION\]\[RC_COV\] Coverage collection disabled"
        return 1
    }

    if {[llength $REG_COV_FILES] == 0} {
        puts "\[REGRESSION\]\[RC_COV\]\[FAIL\] No passing-test UCDB files were collected"
        return 0
    }

    catch {quit -sim -f}

    set vcover_exe [resolve_vcover_executable]

    set merge_cmd [list $vcover_exe merge -out $RC_COV_MERGED_FILE]
    foreach ucdb_file $REG_COV_FILES {
        lappend merge_cmd $ucdb_file
    }

    if {![run_external_command \
        "Merging [llength $REG_COV_FILES] passing-test UCDB file(s)" \
        $merge_cmd]} {
        return 0
    }

    set summary_cmd [list \
        $vcover_exe report \
        $RC_COV_MERGED_FILE \
        > $RC_COV_SUMMARY_FILE]

    if {![run_external_command \
        "Generating functional coverage summary report" \
        $summary_cmd]} {
        return 0
    }

    set details_cmd [list \
        $vcover_exe report \
        -details \
        $RC_COV_MERGED_FILE \
        > $RC_COV_DETAILS_FILE]

    if {![run_external_command \
        "Generating functional coverage detailed report" \
        $details_cmd]} {
        return 0
    }

    puts "\[REGRESSION\]\[RC_COV\]\[PASS\] Merged UCDB: $RC_COV_MERGED_FILE"
    puts "\[REGRESSION\]\[RC_COV\]\[PASS\] Summary report: $RC_COV_SUMMARY_FILE"
    puts "\[REGRESSION\]\[RC_COV\]\[PASS\] Detailed report: $RC_COV_DETAILS_FILE"
    return 1
}

# ============================================================
# CODE-COV utility procs
# ============================================================
proc get_current_code_coverage_file {} {
    if {[info exists ::CODE_COVERAGE_FILE] && ($::CODE_COVERAGE_FILE ne "")} {
        return $::CODE_COVERAGE_FILE
    }
    return "<CODE_COVERAGE_FILE not set>"
}

proc check_code_ucdb_file {ucdb_file} {
    if {![file exists $ucdb_file]} {
        puts "\[REGRESSION\]\[CODE_COV\]\[FAIL\] UCDB file not found: $ucdb_file"
        return 0
    }

    if {[file size $ucdb_file] <= 0} {
        puts "\[REGRESSION\]\[CODE_COV\]\[FAIL\] UCDB file is empty: $ucdb_file"
        return 0
    }

    return 1
}

proc append_code_cov_manifest {idx name status log_file ucdb_file} {
    global CODE_COV_ENABLE CODE_COV_MANIFEST_FILE

    if {!$CODE_COV_ENABLE} {
        return
    }

    set fp [open $CODE_COV_MANIFEST_FILE a]
    puts $fp "$idx\t$name\t$status\t$log_file\t$ucdb_file"
    close $fp
}

proc run_code_cov_external_command {label command_list} {
    puts "\[REGRESSION\]\[CODE_COV\] $label"
    puts "\[REGRESSION\]\[CODE_COV\] command: [join $command_list { }]"

    set status [catch {
        exec {*}$command_list 2>@1
    } message]

    if {$message ne ""} {
        puts $message
    }

    if {$status != 0} {
        puts "\[REGRESSION\]\[CODE_COV\]\[FAIL\] $label failed"
        return 0
    }

    return 1
}

proc finalize_code_cov {} {
    global CODE_COV_ENABLE CODE_COV_METRICS
    global CODE_COV_MERGED_FILE CODE_COV_SUMMARY_FILE CODE_COV_DETAILS_FILE
    global REG_CODE_COV_FILES

    if {!$CODE_COV_ENABLE} {
        puts "\[REGRESSION\]\[CODE_COV\] Coverage collection disabled"
        return 1
    }

    if {[llength $REG_CODE_COV_FILES] == 0} {
        puts "\[REGRESSION\]\[CODE_COV\]\[FAIL\] No passing-test UCDB files were collected"
        return 0
    }

    catch {quit -sim -f}

    set vcover_exe [resolve_vcover_executable]

    set merge_cmd [list $vcover_exe merge -out $CODE_COV_MERGED_FILE]
    foreach ucdb_file $REG_CODE_COV_FILES {
        lappend merge_cmd $ucdb_file
    }

    if {![run_code_cov_external_command \
        "Merging [llength $REG_CODE_COV_FILES] passing-test UCDB file(s)" \
        $merge_cmd]} {
        return 0
    }

    set summary_cmd [list \
        $vcover_exe report \
        -code $CODE_COV_METRICS \
        $CODE_COV_MERGED_FILE \
        > $CODE_COV_SUMMARY_FILE]

    if {![run_code_cov_external_command \
        "Generating RTL code coverage summary report" \
        $summary_cmd]} {
        return 0
    }

    set details_cmd [list \
        $vcover_exe report \
        -details \
        -code $CODE_COV_METRICS \
        $CODE_COV_MERGED_FILE \
        > $CODE_COV_DETAILS_FILE]

    if {![run_code_cov_external_command \
        "Generating RTL code coverage detailed report" \
        $details_cmd]} {
        return 0
    }

    puts "\[REGRESSION\]\[CODE_COV\]\[PASS\] Merged UCDB: $CODE_COV_MERGED_FILE"
    puts "\[REGRESSION\]\[CODE_COV\]\[PASS\] Summary report: $CODE_COV_SUMMARY_FILE"
    puts "\[REGRESSION\]\[CODE_COV\]\[PASS\] Detailed report: $CODE_COV_DETAILS_FILE"
    return 1
}

# ============================================================
# Run one regression item
# ============================================================
proc run_reg_item {name setup_body} {
    global REG_TOTAL REG_PASS REG_FAIL
    global REG_COV_FILES REG_CODE_COV_FILES
    global RC_COV_ENABLE RC_COV_PER_TEST_DIR
    global CODE_COV_ENABLE CODE_COV_PER_TEST_DIR CODE_COV_METRICS

    incr REG_TOTAL
    set item_idx $REG_TOTAL

    puts "\n============================================================"
    puts "\[REGRESSION\] START #$item_idx: $name"
    puts "============================================================"

    clear_uvm_run_vars

    catch {quit -sim -f}

    uplevel 1 $setup_body

    if {$RC_COV_ENABLE} {
        set ::ENABLE_COVERAGE 1
        set ::COVERAGE_OUTPUT_DIR $RC_COV_PER_TEST_DIR
        set ::COVERAGE_RUN_TAG [format "%03d" $item_idx]
    } else {
        set ::ENABLE_COVERAGE 0
    }

    if {$CODE_COV_ENABLE} {
        set ::ENABLE_CODE_COVERAGE 1
        set ::CODE_COVERAGE_OUTPUT_DIR $CODE_COV_PER_TEST_DIR
        set ::CODE_COVERAGE_RUN_TAG [format "%03d" $item_idx]
        set ::CODE_COV_METRICS $CODE_COV_METRICS
    } else {
        set ::ENABLE_CODE_COVERAGE 0
    }

    set run_status [catch {do run_uvm.tcl} run_msg]
    set item_log [get_current_log_file]
    set item_cov [get_current_coverage_file]
    set item_code_cov [get_current_code_coverage_file]

    if {$run_status != 0} {
        puts "\[REGRESSION\]\[FAIL\] Tcl/run error in: $name"
        puts $run_msg

        append_cov_manifest $item_idx $name "RUN_FAIL" $item_log $item_cov
        append_code_cov_manifest $item_idx $name "RUN_FAIL" $item_log $item_code_cov
        record_reg_fail $item_idx $name $item_log
        incr REG_FAIL

        maybe_stop_on_first_fail $item_idx $name $item_log
        return
    }

    set log_ok [check_uvm_log $item_log]
    set rc_cov_ok 1
    set code_cov_ok 1

    if {$RC_COV_ENABLE} {
        set rc_cov_ok [check_ucdb_file $item_cov]
    }

    if {$CODE_COV_ENABLE} {
        set code_cov_ok [check_code_ucdb_file $item_code_cov]
    }

    if {$log_ok && $rc_cov_ok && $code_cov_ok} {
        puts "\[REGRESSION\]\[PASS\] $name"
        append_cov_manifest $item_idx $name "PASS" $item_log $item_cov
        append_code_cov_manifest $item_idx $name "PASS" $item_log $item_code_cov
        record_reg_pass $item_idx $name $item_log
        incr REG_PASS

        if {$RC_COV_ENABLE} {
            lappend REG_COV_FILES $item_cov
        }

        if {$CODE_COV_ENABLE} {
            lappend REG_CODE_COV_FILES $item_code_cov
        }
    } else {
        puts "\[REGRESSION\]\[FAIL\] $name"

        if {!$log_ok} {
            set item_status "UVM_FAIL"
        } elseif {!$rc_cov_ok} {
            set item_status "RC_UCDB_FAIL"
        } else {
            set item_status "CODE_UCDB_FAIL"
        }

        append_cov_manifest $item_idx $name $item_status $item_log $item_cov
        append_code_cov_manifest $item_idx $name $item_status $item_log $item_code_cov
        record_reg_fail $item_idx $name $item_log
        incr REG_FAIL

        maybe_stop_on_first_fail $item_idx $name $item_log
    }
}

# ============================================================
# Canonical regression inventory
#
# PROJECT-FINAL-P1-B policy:
#   sim/uvm_regression.list is the single source of truth for
#   regression item names, ordering, UVM tests, and per-item knobs.
#
# The list format is intentionally simple:
#
#   # NNN: human-readable regression item name
#   <UVM_TEST> [TCL_VAR VALUE ...] [+KEY=VALUE ...] [+FLAG ...]
#
# Known run_uvm.tcl-friendly +KEY=VALUE knobs are promoted to Tcl
# variables.  Unknown +KEY=VALUE / +FLAG tokens are forwarded
# unchanged through EXTRA_PLUSARGS.
#
# This removes the historical duplicate 150-item inventory that
# was hard-coded in this runner and prevents list/runner divergence.
# ============================================================
if {![info exists REGRESSION_LIST_FILE]} {
    set REGRESSION_LIST_FILE uvm_regression.list
}

if {![file exists $REGRESSION_LIST_FILE]} {
    error "\[REGRESSION\] Canonical regression list not found: $REGRESSION_LIST_FILE"
}

# Variables that may be assigned directly by uvm_regression.list.
# Keep this list aligned with the user-facing knobs consumed by
# run_uvm.tcl / clear_uvm_run_vars.
set REGRESSION_TCL_ASSIGNABLE_VARS [list \
    UVM_TOP \
    CASE_ID \
    ENABLE_RESULT_CHECK \
    FORCE_HELPER_MEM_PATH \
    RUN_ALL \
    SMOKE_DONE_TIMEOUT_CYCLES \
    DMA_STORE_DONE_TIMEOUT_CYCLES \
    USE_HOST_AGENT_CLEAR_C \
    USE_HOST_AGENT_READBACK_C \
    USE_HOST_AGENT_PRELOAD_AB \
    JOB_COUNT \
    JOB0_CASE_ID \
    JOB1_CASE_ID \
    JOB2_CASE_ID \
    JOB3_CASE_ID \
    PRE_RESET_CASE_ID \
    POST_RESET_CASE_ID \
    RESET_HOLD_CYCLES \
    POST_RESET_SETTLE_CYCLES \
    DMA_CLK_PERIOD_NS \
    CORE_CLK_PERIOD_NS \
    GEMM_MAC_LANES \
    GEMM_ENABLE_B_CACHE \
    GEMM_B_CACHE_MAX_K \
    GEMM_B_CACHE_MAX_N \
    GEMM_ENABLE_PACKED_BCACHE_PRELOAD \
    GEMM_ENABLE_A_ROW_CACHE \
    GEMM_A_ROW_CACHE_MAX_K \
    GEMM_ENABLE_PACKED_A_ROW_PRELOAD \
    GEMM_ENABLE_K_TILING \
    GEMM_K_TILE_SIZE \
    GEMM_ENABLE_N_TILING \
    GEMM_N_TILE_SIZE \
    GEMM_ENABLE_M_TILING \
    GEMM_M_TILE_SIZE \
    GEMM_ENABLE_C_RMW_ACCUM \
    ACCUMULATE_ENABLE \
    STRESS_JOB_COUNT \
    STRESS_SEED \
    STRESS_RANDOM \
    STRESS_GAP_CYCLES \
    STORE_STRESS_JOB_COUNT \
    STORE_STRESS_SEED \
    STORE_STRESS_RANDOM \
    STORE_STRESS_GAP_CYCLES \
    AXIS_STRESS_JOB_COUNT \
    AXIS_STRESS_SEED \
    AXIS_STRESS_RANDOM \
    AXIS_STRESS_GAP_CYCLES \
    DS_STRESS_JOB_COUNT \
    DS_STRESS_SEED \
    DS_STRESS_RANDOM \
    DS_STRESS_GAP_CYCLES \
    RUN_START_WHILE_BUSY \
]

proc load_regression_inventory {list_file} {
    set fp [open $list_file r]

    set items [list]
    set pending_no ""
    set pending_name ""
    set line_no 0

    while {[gets $fp raw_line] >= 0} {
        incr line_no
        set line [string trim $raw_line]

        if {$line eq ""} {
            continue
        }

        if {[string index $line 0] eq "#"} {
            if {[regexp {^#\s*([0-9][0-9][0-9]):\s*(.+)$} $line -> item_no item_name]} {
                if {$pending_no ne ""} {
                    close $fp
                    error "\[REGRESSION\] $list_file:$line_no starts item #$item_no before item #$pending_no has a configuration line"
                }

                scan $item_no %d pending_no
                set pending_name [string trim $item_name]
            }
            continue
        }

        if {$pending_no eq ""} {
            close $fp
            error "\[REGRESSION\] $list_file:$line_no has a configuration line without a preceding '# NNN: name' record"
        }

        lappend items [list $pending_no $pending_name $line]
        set pending_no ""
        set pending_name ""
    }

    close $fp

    if {$pending_no ne ""} {
        error "\[REGRESSION\] $list_file ends before item #$pending_no receives a configuration line"
    }

    if {[llength $items] == 0} {
        error "\[REGRESSION\] No regression items were loaded from $list_file"
    }

    set expected_no 1
    foreach item $items {
        lassign $item item_no item_name config_line

        if {$item_no != $expected_no} {
            error "\[REGRESSION\] Non-contiguous regression numbering in $list_file: expected #[format %03d $expected_no], found #[format %03d $item_no] ('$item_name')"
        }

        incr expected_no
    }

    return $items
}

proc build_regression_setup_body {config_line} {
    global REGRESSION_TCL_ASSIGNABLE_VARS

    set tokens $config_line

    if {[llength $tokens] == 0} {
        error "\[REGRESSION\] Empty regression configuration line"
    }

    set uvm_test [lindex $tokens 0]
    set setup_body "[list set UVM_TEST $uvm_test]\n"
    set extra_plusargs [list]

    set idx 1
    set token_count [llength $tokens]

    while {$idx < $token_count} {
        set token [lindex $tokens $idx]

        if {[string match "+*" $token]} {
            if {[regexp {^\+([^=]+)=(.*)$} $token -> key value]} {
                if {[lsearch -exact $REGRESSION_TCL_ASSIGNABLE_VARS $key] >= 0} {
                    append setup_body "[list set $key $value]\n"
                } else {
                    lappend extra_plusargs $token
                }
            } else {
                lappend extra_plusargs $token
            }

            incr idx
            continue
        }

        if {($idx + 1) >= $token_count} {
            error "\[REGRESSION\] Missing value after Tcl knob '$token' in: $config_line"
        }

        set key $token
        set value [lindex $tokens [expr {$idx + 1}]]

        if {[lsearch -exact $REGRESSION_TCL_ASSIGNABLE_VARS $key] < 0} {
            error "\[REGRESSION\] Unsupported Tcl knob '$key' in: $config_line"
        }

        append setup_body "[list set $key $value]\n"
        incr idx 2
    }

    if {[llength $extra_plusargs] != 0} {
        append setup_body "[list set EXTRA_PLUSARGS $extra_plusargs]\n"
    }

    return $setup_body
}

set REGRESSION_ITEMS [load_regression_inventory $REGRESSION_LIST_FILE]

puts "\[REGRESSION\] Canonical inventory: $REGRESSION_LIST_FILE"
puts "\[REGRESSION\] Loaded [llength $REGRESSION_ITEMS] regression item(s)"

foreach item $REGRESSION_ITEMS {
    lassign $item item_no item_name config_line

    # load_regression_inventory already proves numbering is contiguous;
    # this guard also catches accidental bookkeeping drift at execution.
    set expected_no [expr {$REG_TOTAL + 1}]
    if {$item_no != $expected_no} {
        error "\[REGRESSION\] Execution index mismatch: expected #[format %03d $expected_no], got #[format %03d $item_no] ('$item_name')"
    }

    set setup_body [build_regression_setup_body $config_line]
    run_reg_item $item_name $setup_body
}


# ============================================================
# RC-COV / CODE-COV merge / report
#
# Only UCDBs from regression items that passed both the UVM
# log check and the enabled per-test UCDB existence check are
# merged.
# ============================================================
if {$RC_COV_ENABLE} {
    if {$REG_FAIL == 0} {
        set RC_COV_FLOW_OK [finalize_rc_cov]
    } else {
        set RC_COV_FLOW_OK 0
        puts "\[REGRESSION\]\[RC_COV\] Merge/report skipped because one or more regression items failed"
    }
}

if {$CODE_COV_ENABLE} {
    if {$REG_FAIL == 0} {
        set CODE_COV_FLOW_OK [finalize_code_cov]
    } else {
        set CODE_COV_FLOW_OK 0
        puts "\[REGRESSION\]\[CODE_COV\] Merge/report skipped because one or more regression items failed"
    }
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
if {$RC_COV_ENABLE} {
    set RC_COV_STATUS_TEXT [expr {$RC_COV_FLOW_OK ? "PASS" : "FAIL"}]
    puts "RC-COV: $RC_COV_STATUS_TEXT"
}
if {$CODE_COV_ENABLE} {
    set CODE_COV_STATUS_TEXT [expr {$CODE_COV_FLOW_OK ? "PASS" : "FAIL"}]
    puts "CODE-COV: $CODE_COV_STATUS_TEXT"
}
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
} elseif {$RC_COV_ENABLE && !$RC_COV_FLOW_OK} {
    error "\[REGRESSION\] TESTS PASSED BUT RC-COV MERGE/REPORT FAILED"
} elseif {$CODE_COV_ENABLE && !$CODE_COV_FLOW_OK} {
    error "\[REGRESSION\] TESTS PASSED BUT CODE-COV MERGE/REPORT FAILED"
} else {
    puts "\[REGRESSION\] ALL TESTS PASSED"
    if {$RC_COV_ENABLE} {
        puts "\[REGRESSION\] RC-COV UCDB MERGE AND REPORT PASSED"
    }
    if {$CODE_COV_ENABLE} {
        puts "\[REGRESSION\] CODE-COV UCDB MERGE AND REPORT PASSED"
    }
}
