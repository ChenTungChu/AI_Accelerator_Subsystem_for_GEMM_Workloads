# ============================================================
# CODE-COV-C1.2-G8-C2-B
# Port0 Owner / CSR-Top Expression Physical Normalization
# QuestaSim 10.7c
# ============================================================

set G8C2B_INPUT_UCDB "coverage/code_cov/g8_c/code_cov_g8_c2a_multimetric_effective.ucdb"
set G8C2B_DIR        "coverage/code_cov/g8_c"
set G8C2B_EFF_UCDB   "$G8C2B_DIR/code_cov_g8_c2b_multimetric_effective.ucdb"
set G8C2B_DATASET    "code_cov_g8_c2b_multimetric_effective"
set G8C2B_EXCL_TCL   "g8_c2b_expression_exclusions.tcl"

puts [format {[G8-C2-B] Input C2-A UCDB: %s} $G8C2B_INPUT_UCDB]
puts [format {[G8-C2-B] Output C2-B UCDB: %s} $G8C2B_EFF_UCDB]

if {![file exists $G8C2B_INPUT_UCDB]} {
    error [format {G8-C2-B input UCDB not found: %s} $G8C2B_INPUT_UCDB]
}
if {![file exists $G8C2B_EXCL_TCL]} {
    error [format {G8-C2-B exclusion Tcl not found: %s} $G8C2B_EXCL_TCL]
}

file mkdir $G8C2B_DIR
catch {dataset close $G8C2B_DATASET}

# Always rebuild from the physically-proven C2-A artifact.
file copy -force $G8C2B_INPUT_UCDB $G8C2B_EFF_UCDB

coverage open $G8C2B_EFF_UCDB $G8C2B_DATASET

set g8c2b_rc [catch {
    do $G8C2B_EXCL_TCL
    coverage save $G8C2B_EFF_UCDB
} g8c2b_msg]

catch {dataset close $G8C2B_DATASET}

if {$g8c2b_rc != 0} {
    error [format {[G8-C2-B][FAIL] Exclusion/save failed: %s} $g8c2b_msg]
}

# Regression-proof reports: statement and all non-toggle control metrics.
vcover report -code s \
    -output "$G8C2B_DIR/g8_c2b_effective_statement_summary.txt" \
    $G8C2B_EFF_UCDB

vcover report -code bcef \
    -output "$G8C2B_DIR/g8_c2b_effective_multimetric_summary.txt" \
    $G8C2B_EFF_UCDB

vcover report -details -code bcef \
    -output "$G8C2B_DIR/g8_c2b_effective_multimetric_details.txt" \
    $G8C2B_EFF_UCDB

vcover report -details -zeros -code bcef \
    -output "$G8C2B_DIR/g8_c2b_effective_multimetric_zeros.txt" \
    $G8C2B_EFF_UCDB

# Toggle is not modified; emit a summary so G8-C3 can prove that directly.
vcover report -code t \
    -output "$G8C2B_DIR/g8_c2b_effective_toggle_summary.txt" \
    $G8C2B_EFF_UCDB

puts {[G8-C2-B] PASS: expression-only artifact and reports generated.}
puts {[G8-C2-B] IMPORTANT: command PASS is not final coverage-proof closure.}
puts {[G8-C2-B] Expected: Port0 expression 56/56/0 and CSR-top expression 134/134/0, with all C2-A metrics otherwise unchanged.}
