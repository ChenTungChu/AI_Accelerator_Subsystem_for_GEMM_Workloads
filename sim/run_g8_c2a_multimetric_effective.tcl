# ============================================================
# CODE-COV-C1.2-G8-C2-A Rev-B2
# Exact Multi-Metric Physical Proof
# QuestaSim 10.7c
# ============================================================

set G8C2_INPUT_UCDB "coverage/code_cov/g8_c/code_cov_g8_c_statement_effective.ucdb"
set G8C2_DIR        "coverage/code_cov/g8_c"
set G8C2_EFF_UCDB   "$G8C2_DIR/code_cov_g8_c2a_multimetric_effective.ucdb"
set G8C2_DATASET    "code_cov_g8_c2a_multimetric_effective"
set G8C2_EXCL_TCL   "g8_c2a_multimetric_exclusions.tcl"

puts [format {[G8-C2-A Rev-B2] Input statement-effective UCDB: %s} $G8C2_INPUT_UCDB]
puts [format {[G8-C2-A Rev-B2] Output multi-metric UCDB: %s} $G8C2_EFF_UCDB]

if {![file exists $G8C2_INPUT_UCDB]} {
    error [format {G8-C2-A Rev-B input UCDB not found: %s} $G8C2_INPUT_UCDB]
}
if {![file exists $G8C2_EXCL_TCL]} {
    error [format {G8-C2-A Rev-B exclusion Tcl not found: %s} $G8C2_EXCL_TCL]
}

file mkdir $G8C2_DIR
catch {dataset close $G8C2_DATASET}

# Always rebuild from the proven G8-C1 statement-effective artifact.
file copy -force $G8C2_INPUT_UCDB $G8C2_EFF_UCDB

coverage open $G8C2_EFF_UCDB $G8C2_DATASET

set g8c2_rc [catch {
    do $G8C2_EXCL_TCL
    coverage save $G8C2_EFF_UCDB
} g8c2_msg]

catch {dataset close $G8C2_DATASET}

if {$g8c2_rc != 0} {
    error [format {[G8-C2-A Rev-B2][FAIL] Exclusion/save failed: %s} $g8c2_msg]
}

vcover report -code s \
    -output "$G8C2_DIR/g8_c2a_effective_statement_summary.txt" \
    $G8C2_EFF_UCDB

vcover report -code bcef \
    -output "$G8C2_DIR/g8_c2a_effective_multimetric_summary.txt" \
    $G8C2_EFF_UCDB

vcover report -details -code bcef \
    -output "$G8C2_DIR/g8_c2a_effective_multimetric_details.txt" \
    $G8C2_EFF_UCDB

vcover report -details -zeros -code bcef \
    -output "$G8C2_DIR/g8_c2a_effective_multimetric_zeros.txt" \
    $G8C2_EFF_UCDB

puts {[G8-C2-A Rev-B2] PASS: artifact and reports generated.}
puts {[G8-C2-A Rev-B2] IMPORTANT: command PASS is not coverage-proof closure.}
puts {[G8-C2-A Rev-B2] Branch true/explicit-arm residues intentionally remain visible if Questa cannot isolate them without covered-bin loss.}
