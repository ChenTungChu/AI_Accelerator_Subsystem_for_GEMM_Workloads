# ============================================================
# CODE-COV-C1.2-G8-C3
# Final RAW vs EFFECTIVE Reconciliation / Closure
# QuestaSim 10.7c / Windows
#
# READ-ONLY proof:
#   RAW       : coverage/code_cov/code_cov_merged.ucdb
#   EFFECTIVE : coverage/code_cov/g8_c/code_cov_g8_c2b_multimetric_effective.ucdb
#
# This script does NOT open either UCDB for editing and does NOT save
# either UCDB. It only runs vcover reports and hashes the RAW file
# before/after reporting.
# ============================================================

set G8C3_RAW_UCDB "coverage/code_cov/code_cov_merged.ucdb"
set G8C3_EFF_UCDB "coverage/code_cov/g8_c/code_cov_g8_c2b_multimetric_effective.ucdb"
set G8C3_DIR      "coverage/code_cov/g8_c"

proc g8c3_sha256 {path} {
    # Windows certutil is available on standard Windows installations.
    set output [exec certutil -hashfile $path SHA256]
    foreach line [split $output "\n"] {
        set clean [string trim $line]
        regsub -all {\s} $clean "" clean
        set clean [string tolower $clean]
        if {[regexp {^[0-9a-f]{64}$} $clean]} {
            return $clean
        }
    }
    error [format {Unable to parse SHA256 from certutil output for: %s} $path]
}

puts {[G8-C3] Final RAW vs EFFECTIVE reconciliation starting.}
puts [format {[G8-C3] RAW       : %s} $G8C3_RAW_UCDB]
puts [format {[G8-C3] EFFECTIVE : %s} $G8C3_EFF_UCDB]

if {![file exists $G8C3_RAW_UCDB]} {
    error [format {G8-C3 RAW UCDB not found: %s} $G8C3_RAW_UCDB]
}
if {![file exists $G8C3_EFF_UCDB]} {
    error [format {G8-C3 EFFECTIVE UCDB not found: %s} $G8C3_EFF_UCDB]
}

file mkdir $G8C3_DIR

# -----------------------------------------------------------------
# Canonical RAW immutability proof: SHA256 before.
# -----------------------------------------------------------------
set raw_sha_before [g8c3_sha256 $G8C3_RAW_UCDB]
puts [format {[G8-C3] RAW SHA256 before: %s} $raw_sha_before]

# -----------------------------------------------------------------
# Final reports.
# -----------------------------------------------------------------

# Full authoritative RAW / EFFECTIVE filtered views.
vcover report -code bcefst \
    -output "$G8C3_DIR/g8_c3_raw_bcefst_summary.txt" \
    $G8C3_RAW_UCDB

vcover report -code bcefst \
    -output "$G8C3_DIR/g8_c3_effective_bcefst_summary.txt" \
    $G8C3_EFF_UCDB

# Statement isolation proof.
vcover report -code s \
    -output "$G8C3_DIR/g8_c3_raw_statement_summary.txt" \
    $G8C3_RAW_UCDB

vcover report -code s \
    -output "$G8C3_DIR/g8_c3_effective_statement_summary.txt" \
    $G8C3_EFF_UCDB

# Non-toggle control-flow proof.
vcover report -code bcef \
    -output "$G8C3_DIR/g8_c3_raw_multimetric_summary.txt" \
    $G8C3_RAW_UCDB

vcover report -code bcef \
    -output "$G8C3_DIR/g8_c3_effective_multimetric_summary.txt" \
    $G8C3_EFF_UCDB

# Toggle invariance proof.
vcover report -code t \
    -output "$G8C3_DIR/g8_c3_raw_toggle_summary.txt" \
    $G8C3_RAW_UCDB

vcover report -code t \
    -output "$G8C3_DIR/g8_c3_effective_toggle_summary.txt" \
    $G8C3_EFF_UCDB

# Remaining effective misses for final audit:
#   - protected constructive statement misses
#   - approved-but-tool-granularity-limited branch residues
#   - other non-G8-approved RAW residues intentionally left untouched
vcover report -details -zeros -code bcefs \
    -output "$G8C3_DIR/g8_c3_effective_remaining_zeros.txt" \
    $G8C3_EFF_UCDB

# -----------------------------------------------------------------
# Canonical RAW immutability proof: SHA256 after.
# -----------------------------------------------------------------
set raw_sha_after [g8c3_sha256 $G8C3_RAW_UCDB]
puts [format {[G8-C3] RAW SHA256 after : %s} $raw_sha_after]

set hash_fp [open "$G8C3_DIR/g8_c3_raw_immutability_sha256.txt" "w"]
puts $hash_fp [format {RAW UCDB: %s} $G8C3_RAW_UCDB]
puts $hash_fp [format {SHA256 before: %s} $raw_sha_before]
puts $hash_fp [format {SHA256 after : %s} $raw_sha_after]
if {$raw_sha_before eq $raw_sha_after} {
    puts $hash_fp {RESULT: PASS}
} else {
    puts $hash_fp {RESULT: FAIL}
}
close $hash_fp

if {$raw_sha_before ne $raw_sha_after} {
    error {G8-C3 FAIL: canonical RAW UCDB SHA256 changed during reconciliation.}
}

puts {[G8-C3] PASS: report generation completed and canonical RAW SHA256 is unchanged.}
puts {[G8-C3] IMPORTANT: this is command/hash PASS only. Final G8-C closure requires metric-ledger reconciliation of the generated reports.}
