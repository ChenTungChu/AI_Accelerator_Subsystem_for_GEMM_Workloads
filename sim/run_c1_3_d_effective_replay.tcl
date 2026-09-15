# ============================================================
# CODE-COV-C1.3-D2 Rev-A
# Frozen C1.2 Exclusion Replay / Final C1.3 Effective Audit
# Rev-A: preserve legacy G8-C wrapper-variable contracts for frozen exclusion Tcl.
# QuestaSim 10.7c / Windows
#
# Purpose:
#   Apply the EXACT frozen C1.2 G8-C exclusion ledger to the
#   final C1.3 canonical RAW UCDB without modifying that RAW UCDB.
#
# Canonical RAW input (READ-ONLY):
#   coverage/code_cov/code_cov_merged.ucdb
#
# C1.3-D working/output directory:
#   coverage/code_cov/c1_3_d/
#
# Frozen exclusion inputs (must match C1.2 authoritative SHA256):
#   g8_c_statement_exclusions.tcl
#   g8_c2a_multimetric_exclusions.tcl
#   g8_c2b_expression_exclusions.tcl
#
# This script:
#   1) verifies canonical RAW identity,
#   2) verifies all three frozen exclusion-ledger files,
#   3) copies RAW into an isolated C1.3-D working artifact,
#   4) replays statement -> multi-metric -> expression exclusions,
#   5) emits RAW vs EFFECTIVE reports,
#   6) proves canonical RAW SHA256 is unchanged.
#
# No RTL/UVM compile or simulation is performed.
# No toggle exclusion is applied.
# ============================================================

set C13D_RAW_UCDB       "coverage/code_cov/code_cov_merged.ucdb"
set C13D_OUT_DIR        "coverage/code_cov/c1_3_d"

set C13D_STMT_UCDB      "$C13D_OUT_DIR/code_cov_c1_3_d_statement_effective.ucdb"
set C13D_C2A_UCDB       "$C13D_OUT_DIR/code_cov_c1_3_d_multimetric_a_effective.ucdb"
set C13D_FINAL_EFF_UCDB "$C13D_OUT_DIR/code_cov_c1_3_d_effective.ucdb"

set C13D_STMT_DATASET   "code_cov_c1_3_d_statement_effective"
set C13D_C2A_DATASET    "code_cov_c1_3_d_multimetric_a_effective"
set C13D_C2B_DATASET    "code_cov_c1_3_d_effective"

set C13D_STMT_EXCL      "g8_c_statement_exclusions.tcl"
set C13D_C2A_EXCL       "g8_c2a_multimetric_exclusions.tcl"
set C13D_C2B_EXCL       "g8_c2b_expression_exclusions.tcl"

# Final C1.3 canonical RAW identity frozen at C1.3-D0.
set C13D_EXPECTED_RAW_SHA256  "ff2918d43a714d0ecd70ac8b1001c84cdfc3188f0ed4f825f3489343e0a1e079"

# Exact C1.2 G8-C exclusion-ledger identities frozen at C1.3-D1.
set C13D_EXPECTED_STMT_SHA256 "38b4e7543712fa35b469e7a103265711044db079be8815583376e1e833544846"
set C13D_EXPECTED_C2A_SHA256  "2419f400b05636d49a19bf411add48c9dc36bf8aa78e7c2b7d71572d39d45a9c"
set C13D_EXPECTED_C2B_SHA256  "d697d4a25bfd13102f75eb07cb7c032f45f6c3d0a53cca27b46173d0d07488a4"

proc c13d_sha256 {path} {
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

proc c13d_require_hash {label path expected} {
    if {![file exists $path]} {
        error [format {[C1.3-D2][FAIL] Missing %s: %s} $label $path]
    }
    set actual [c13d_sha256 $path]
    puts [format {[C1.3-D2] %s SHA256: %s} $label $actual]
    if {$actual ne $expected} {
        error [format {[C1.3-D2][FAIL] %s SHA256 mismatch. Expected %s, got %s} $label $expected $actual]
    }
    return $actual
}

proc c13d_apply_exclusions {label input_ucdb output_ucdb dataset excl_tcl} {
    catch {dataset close $dataset}

    if {![file exists $input_ucdb]} {
        error [format {[C1.3-D2][FAIL] %s input UCDB not found: %s} $label $input_ucdb]
    }
    if {![file exists $excl_tcl]} {
        error [format {[C1.3-D2][FAIL] %s exclusion Tcl not found: %s} $label $excl_tcl]
    }

    file copy -force $input_ucdb $output_ucdb

    puts [format {[C1.3-D2] %s input : %s} $label $input_ucdb]
    puts [format {[C1.3-D2] %s output: %s} $label $output_ucdb]

    set edit_rc [catch {
        coverage open $output_ucdb $dataset
        do $excl_tcl
        coverage save $output_ucdb
    } edit_msg]

    # QuestaSim 10.7c: coverage open creates a view-mode dataset;
    # close it with dataset close before vcover reads the saved UCDB.
    catch {dataset close $dataset}

    if {$edit_rc != 0} {
        puts [format {[C1.3-D2][FAIL] %s exclusion/save failed.} $label]
        puts $edit_msg
        error [format {[C1.3-D2] %s construction failed.} $label]
    }

    puts [format {[C1.3-D2] %s replay completed.} $label]
}

puts {[C1.3-D2] Frozen C1.2 exclusion replay starting.}
puts [format {[C1.3-D2] Canonical RAW (read-only): %s} $C13D_RAW_UCDB]
puts [format {[C1.3-D2] Isolated output directory : %s} $C13D_OUT_DIR]

file mkdir $C13D_OUT_DIR

# -----------------------------------------------------------------
# Gate 1: canonical RAW + frozen exclusion-ledger identity checks.
# -----------------------------------------------------------------
set raw_sha_before [c13d_require_hash \
    "Canonical RAW" \
    $C13D_RAW_UCDB \
    $C13D_EXPECTED_RAW_SHA256]

set stmt_sha [c13d_require_hash \
    "Statement exclusion ledger" \
    $C13D_STMT_EXCL \
    $C13D_EXPECTED_STMT_SHA256]

set c2a_sha [c13d_require_hash \
    "C2-A multi-metric exclusion ledger" \
    $C13D_C2A_EXCL \
    $C13D_EXPECTED_C2A_SHA256]

set c2b_sha [c13d_require_hash \
    "C2-B expression exclusion ledger" \
    $C13D_C2B_EXCL \
    $C13D_EXPECTED_C2B_SHA256]

puts {[C1.3-D2] Frozen control-ledger identity check: PASS}

# -----------------------------------------------------------------
# Gate 2: replay the exact frozen C1.2 exclusion sequence.
#
# IMPORTANT COMPATIBILITY NOTE:
# The frozen G8-C exclusion Tcl files are not standalone.  They were
# intentionally written against the variable contract of their proven
# Questa 10.7c wrappers.  Recreate those legacy wrapper variables here
# before each replay stage so the EXACT frozen exclusion files can be
# reused without modification.
# -----------------------------------------------------------------

# Stage 1 legacy wrapper contract (G8-C1 Rev-C).
set G8C_RAW_UCDB $C13D_RAW_UCDB
set G8C_OUT_DIR  $C13D_OUT_DIR
set G8C_EFF_UCDB $C13D_STMT_UCDB
set G8C_EXCL_TCL $C13D_STMT_EXCL
set G8C_DATASET  $C13D_STMT_DATASET

puts [format {[C1.3-D2] Stage 1 compatibility dataset: %s} $G8C_DATASET]
c13d_apply_exclusions \
    "Stage 1 / statement" \
    $C13D_RAW_UCDB \
    $C13D_STMT_UCDB \
    $C13D_STMT_DATASET \
    $C13D_STMT_EXCL

# Stage 2 legacy wrapper contract (G8-C2-A Rev-B2).
# g8_c2a_multimetric_exclusions.tcl explicitly requires G8C2_DATASET.
set G8C2_INPUT_UCDB $C13D_STMT_UCDB
set G8C2_DIR        $C13D_OUT_DIR
set G8C2_EFF_UCDB   $C13D_C2A_UCDB
set G8C2_DATASET    $C13D_C2A_DATASET
set G8C2_EXCL_TCL   $C13D_C2A_EXCL

puts [format {[C1.3-D2] Stage 2 compatibility dataset: %s} $G8C2_DATASET]
c13d_apply_exclusions \
    "Stage 2 / branch-condition-FSM" \
    $C13D_STMT_UCDB \
    $C13D_C2A_UCDB \
    $C13D_C2A_DATASET \
    $C13D_C2A_EXCL

# Stage 3 legacy wrapper contract (G8-C2-B).
# Mirror the original G8C2B_* environment as well, so the frozen
# expression exclusion Tcl sees the same wrapper contract it was
# validated with during C1.2.
set G8C2B_INPUT_UCDB $C13D_C2A_UCDB
set G8C2B_DIR        $C13D_OUT_DIR
set G8C2B_EFF_UCDB   $C13D_FINAL_EFF_UCDB
set G8C2B_DATASET    $C13D_C2B_DATASET
set G8C2B_EXCL_TCL   $C13D_C2B_EXCL

puts [format {[C1.3-D2] Stage 3 compatibility dataset: %s} $G8C2B_DATASET]
c13d_apply_exclusions \
    "Stage 3 / expression normalization" \
    $C13D_C2A_UCDB \
    $C13D_FINAL_EFF_UCDB \
    $C13D_C2B_DATASET \
    $C13D_C2B_EXCL

# -----------------------------------------------------------------
# Gate 3: report generation. These are read-only vcover operations.
# -----------------------------------------------------------------
puts {[C1.3-D2] Generating RAW vs EFFECTIVE reports.}

# Full bcefst views.
vcover report -code bcefst \
    -output "$C13D_OUT_DIR/c1_3_d_raw_bcefst_summary.txt" \
    $C13D_RAW_UCDB

vcover report -code bcefst \
    -output "$C13D_OUT_DIR/c1_3_d_effective_bcefst_summary.txt" \
    $C13D_FINAL_EFF_UCDB

# Statement isolation proof.
vcover report -code s \
    -output "$C13D_OUT_DIR/c1_3_d_raw_statement_summary.txt" \
    $C13D_RAW_UCDB

vcover report -code s \
    -output "$C13D_OUT_DIR/c1_3_d_effective_statement_summary.txt" \
    $C13D_FINAL_EFF_UCDB

vcover report -details -code s \
    -output "$C13D_OUT_DIR/c1_3_d_effective_statement_details.txt" \
    $C13D_FINAL_EFF_UCDB

# Non-toggle control-flow proof.
vcover report -code bcef \
    -output "$C13D_OUT_DIR/c1_3_d_raw_multimetric_summary.txt" \
    $C13D_RAW_UCDB

vcover report -code bcef \
    -output "$C13D_OUT_DIR/c1_3_d_effective_multimetric_summary.txt" \
    $C13D_FINAL_EFF_UCDB

vcover report -details -code bcef \
    -output "$C13D_OUT_DIR/c1_3_d_effective_multimetric_details.txt" \
    $C13D_FINAL_EFF_UCDB

# Toggle invariance proof. No toggle exclusion is ever applied above.
vcover report -code t \
    -output "$C13D_OUT_DIR/c1_3_d_raw_toggle_summary.txt" \
    $C13D_RAW_UCDB

vcover report -code t \
    -output "$C13D_OUT_DIR/c1_3_d_effective_toggle_summary.txt" \
    $C13D_FINAL_EFF_UCDB

# Remaining effective misses for final D2/D3 audit.
vcover report -details -zeros -code bcefs \
    -output "$C13D_OUT_DIR/c1_3_d_effective_remaining_zeros.txt" \
    $C13D_FINAL_EFF_UCDB

# -----------------------------------------------------------------
# Gate 4: canonical RAW immutability proof.
# -----------------------------------------------------------------
set raw_sha_after [c13d_sha256 $C13D_RAW_UCDB]
set eff_sha       [c13d_sha256 $C13D_FINAL_EFF_UCDB]

puts [format {[C1.3-D2] RAW SHA256 before: %s} $raw_sha_before]
puts [format {[C1.3-D2] RAW SHA256 after : %s} $raw_sha_after]
puts [format {[C1.3-D2] EFFECTIVE SHA256 : %s} $eff_sha]

set manifest_path "$C13D_OUT_DIR/c1_3_d_replay_manifest.txt"
set manifest_fp [open $manifest_path "w"]
puts $manifest_fp {CODE-COV-C1.3-D2 — Frozen C1.2 Exclusion Replay Manifest}
puts $manifest_fp {============================================================}
puts $manifest_fp [format {Canonical RAW UCDB: %s} $C13D_RAW_UCDB]
puts $manifest_fp [format {RAW SHA256 before: %s} $raw_sha_before]
puts $manifest_fp [format {RAW SHA256 after : %s} $raw_sha_after]
puts $manifest_fp [format {Final EFFECTIVE UCDB: %s} $C13D_FINAL_EFF_UCDB]
puts $manifest_fp [format {Final EFFECTIVE SHA256: %s} $eff_sha]
puts $manifest_fp {}
puts $manifest_fp [format {Statement exclusion Tcl: %s} $C13D_STMT_EXCL]
puts $manifest_fp [format {Statement exclusion SHA256: %s} $stmt_sha]
puts $manifest_fp [format {C2-A exclusion Tcl: %s} $C13D_C2A_EXCL]
puts $manifest_fp [format {C2-A exclusion SHA256: %s} $c2a_sha]
puts $manifest_fp [format {C2-B exclusion Tcl: %s} $C13D_C2B_EXCL]
puts $manifest_fp [format {C2-B exclusion SHA256: %s} $c2b_sha]
puts $manifest_fp {}
puts $manifest_fp {New exclusions introduced by C1.3-D2: 0}
puts $manifest_fp {Toggle exclusions introduced by C1.3-D2: 0}
if {$raw_sha_before eq $raw_sha_after} {
    puts $manifest_fp {Canonical RAW immutability: PASS}
} else {
    puts $manifest_fp {Canonical RAW immutability: FAIL}
}
close $manifest_fp

if {$raw_sha_before ne $raw_sha_after} {
    error {C1.3-D2 FAIL: canonical RAW UCDB SHA256 changed during frozen-exclusion replay.}
}

puts {[C1.3-D2] PASS: frozen exclusion replay and report generation completed.}
puts {[C1.3-D2] PASS: canonical RAW SHA256 is unchanged.}
puts {[C1.3-D2] IMPORTANT: command/hash PASS is not final C1.3-D closure.}
puts {[C1.3-D2] Next: reconcile RAW vs EFFECTIVE metrics, confirm no covered-hit loss / toggle change, then perform final Git freeze.}
