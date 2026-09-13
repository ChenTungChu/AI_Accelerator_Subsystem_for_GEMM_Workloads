# CODE-COV-C1.2-G8-C1 Rev-C — Build statement-only effective UCDB
# Run from the project simulation directory where coverage/code_cov/code_cov_merged.ucdb exists.

set G8C_RAW_UCDB "coverage/code_cov/code_cov_merged.ucdb"
set G8C_OUT_DIR  "coverage/code_cov/g8_c"
set G8C_EFF_UCDB "$G8C_OUT_DIR/code_cov_g8_c_statement_effective.ucdb"
set G8C_EXCL_TCL "g8_c_statement_exclusions.tcl"
set G8C_DATASET  "code_cov_g8_c_statement_effective"

if {![file exists $G8C_RAW_UCDB]} {
    error [format {[G8-C1] Missing canonical RAW UCDB: %s} $G8C_RAW_UCDB]
}
if {![file exists $G8C_EXCL_TCL]} {
    error [format {[G8-C1] Missing exclusion Tcl: %s} $G8C_EXCL_TCL]
}

# A previous interrupted G8-C1 run may have left the view-mode UCDB dataset open.
# Questa 10.7c closes coverage-view datasets with "dataset close", not "coverage close".
catch {dataset close $G8C_DATASET}

file mkdir $G8C_OUT_DIR
file copy -force $G8C_RAW_UCDB $G8C_EFF_UCDB

puts [format {[G8-C1] RAW (read-only source): %s} $G8C_RAW_UCDB]
puts [format {[G8-C1] EFFECTIVE working copy: %s} $G8C_EFF_UCDB]
puts [format {[G8-C1] Coverage dataset: %s} $G8C_DATASET]

set g8c_edit_status [catch {
    coverage open $G8C_EFF_UCDB $G8C_DATASET
    do $G8C_EXCL_TCL
    coverage save $G8C_EFF_UCDB
} g8c_edit_msg]

# coverage open creates a view-mode dataset. Close it with dataset close so the
# saved UCDB is not left open while vcover reads it below. Ignore close failure
# here because the primary edit/save status is reported separately.
catch {dataset close $G8C_DATASET}

if {$g8c_edit_status != 0} {
    puts {[G8-C1][FAIL] Unable to build/save statement-effective UCDB.}
    puts $g8c_edit_msg
    error {[G8-C1] Statement-effective UCDB construction failed.}
}

# Generate statement-only proof reports. These do not change either UCDB.
set g8c_report_status [catch {
    exec vcover report -code s $G8C_RAW_UCDB > "$G8C_OUT_DIR/g8_c_raw_statement_summary.txt"
    exec vcover report -details -code s $G8C_RAW_UCDB > "$G8C_OUT_DIR/g8_c_raw_statement_details.txt"
    exec vcover report -code s $G8C_EFF_UCDB > "$G8C_OUT_DIR/g8_c_effective_statement_summary.txt"
    exec vcover report -details -code s $G8C_EFF_UCDB > "$G8C_OUT_DIR/g8_c_effective_statement_details.txt"
} g8c_report_msg]

if {$g8c_report_status != 0} {
    puts {[G8-C1][FAIL] Effective UCDB was saved, but vcover report generation failed.}
    puts $g8c_report_msg
    error {[G8-C1] Statement proof report generation failed.}
}

puts {[G8-C1] PASS: Rev-C statement effective UCDB and reports generated.}
puts {[G8-C1] Next: reconcile RAW vs EFFECTIVE; do not declare closure until covered-hit loss = 0 and only approved objects changed.}
