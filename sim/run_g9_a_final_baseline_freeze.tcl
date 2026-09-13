# ============================================================
# CODE-COV-C1.2-G9-A
# Final Baseline / Closure Evidence Freeze
#
# Purpose:
#   Freeze the final source baseline identity and the already-proven
#   G8-C coverage evidence without modifying RTL/UVM/UCDB content.
#
# Run from the project repository root (preferred) or from a directory
# inside the same Git worktree.
#
# QuestaSim 10.7c / Windows
# ============================================================

set G9A_OUT_DIR "coverage/code_cov/g9_a"
set G9A_FREEZE_FILE "$G9A_OUT_DIR/g9_a_final_baseline_freeze.txt"
set G9A_GIT_STATUS_FILE "$G9A_OUT_DIR/g9_a_git_status.txt"
set G9A_EVIDENCE_HASH_FILE "$G9A_OUT_DIR/g9_a_evidence_sha256.txt"

set G9A_RAW_UCDB "coverage/code_cov/code_cov_merged.ucdb"
set G9A_EFFECTIVE_UCDB "coverage/code_cov/g8_c/code_cov_g8_c2b_multimetric_effective.ucdb"

set G9A_CRITICAL_EVIDENCE [list \
    "coverage/code_cov/code_cov_merged.ucdb" \
    "coverage/code_cov/g8_c/code_cov_g8_c2b_multimetric_effective.ucdb" \
    "coverage/code_cov/g8_c/g8_c3_raw_bcefst_summary.txt" \
    "coverage/code_cov/g8_c/g8_c3_effective_bcefst_summary.txt" \
    "coverage/code_cov/g8_c/g8_c3_effective_multimetric_summary.txt" \
    "coverage/code_cov/g8_c/g8_c3_effective_statement_summary.txt" \
    "coverage/code_cov/g8_c/g8_c3_effective_toggle_summary.txt" \
    "coverage/code_cov/g8_c/g8_c3_raw_immutability_sha256.txt" \
]

# Optional reproducibility/control artifacts. These are hashed if present.
set G9A_OPTIONAL_CONTROL_ARTIFACTS [list \
    "g8_c_statement_exclusions.tcl" \
    "run_g8_c_statement_effective.tcl" \
    "g8_c2a_multimetric_exclusions.tcl" \
    "run_g8_c2a_multimetric_effective.tcl" \
    "g8_c2b_expression_exclusions.tcl" \
    "run_g8_c2b_expression_effective.tcl" \
    "run_g8_c3_final_reconciliation.tcl" \
]

proc g9a_sha256 {path} {
    set output [exec certutil -hashfile $path SHA256]
    foreach line [split $output "\n"] {
        set clean [string trim $line]
        regsub -all {\s} $clean "" clean
        set clean [string tolower $clean]
        if {[regexp {^[0-9a-f]{64}$} $clean]} {
            return $clean
        }
    }
    error [format {Unable to parse SHA256 for: %s} $path]
}

proc g9a_write_block {fp title body} {
    puts $fp "------------------------------------------------------------"
    puts $fp $title
    puts $fp "------------------------------------------------------------"
    puts $fp $body
    puts $fp ""
}

file mkdir $G9A_OUT_DIR

puts {[G9-A] Final Baseline / Closure Evidence Freeze starting.}

# ------------------------------------------------------------
# Git baseline identity
# ------------------------------------------------------------
set git_ok 1
set git_root ""
set git_head ""
set git_branch ""
set git_subject ""
set git_commit_time ""

if {[catch {exec git rev-parse --show-toplevel} git_root_msg]} {
    set git_ok 0
    set git_root "UNAVAILABLE"
    set git_head "UNAVAILABLE"
    set git_branch "UNAVAILABLE"
    set git_subject "UNAVAILABLE"
    set git_commit_time "UNAVAILABLE"
} else {
    set git_root [string trim $git_root_msg]
    set git_head [string trim [exec git rev-parse HEAD]]
    set git_branch [string trim [exec git rev-parse --abbrev-ref HEAD]]
    set git_subject [string trim [exec git show -s --format=%s HEAD]]
    set git_commit_time [string trim [exec git show -s --format=%ci HEAD]]
}

set git_status ""
set git_diff_names ""
set git_cached_names ""

if {$git_ok} {
    catch {set git_status [exec git status --porcelain --untracked-files=all]}
    catch {set git_diff_names [exec git diff --name-only]}
    catch {set git_cached_names [exec git diff --cached --name-only]}
}

set git_clean 0
if {$git_ok && [string trim $git_status] eq ""} {
    set git_clean 1
}

set gs [open $G9A_GIT_STATUS_FILE "w"]
puts $gs [format {Git root   : %s} $git_root]
puts $gs [format {Git branch : %s} $git_branch]
puts $gs [format {Git HEAD   : %s} $git_head]
puts $gs [format {Commit time: %s} $git_commit_time]
puts $gs [format {Subject    : %s} $git_subject]
puts $gs ""
puts $gs "git status --porcelain --untracked-files=all"
puts $gs "------------------------------------------------------------"
if {[string trim $git_status] eq ""} {
    puts $gs "<clean>"
} else {
    puts $gs $git_status
}
puts $gs ""
puts $gs "git diff --name-only"
puts $gs "------------------------------------------------------------"
if {[string trim $git_diff_names] eq ""} {
    puts $gs "<none>"
} else {
    puts $gs $git_diff_names
}
puts $gs ""
puts $gs "git diff --cached --name-only"
puts $gs "------------------------------------------------------------"
if {[string trim $git_cached_names] eq ""} {
    puts $gs "<none>"
} else {
    puts $gs $git_cached_names
}
close $gs

# ------------------------------------------------------------
# Evidence existence + SHA256 freeze
# ------------------------------------------------------------
set critical_missing 0
set eh [open $G9A_EVIDENCE_HASH_FILE "w"]

puts $eh "CODE-COV-C1.2-G9-A Evidence SHA256 Freeze"
puts $eh ""

puts $eh "CRITICAL EVIDENCE"
puts $eh "================="
foreach path $G9A_CRITICAL_EVIDENCE {
    if {[file exists $path]} {
        set h [g9a_sha256 $path]
        puts $eh [format {%s  %s} $h $path]
    } else {
        incr critical_missing
        puts $eh [format {MISSING  %s} $path]
    }
}

puts $eh ""
puts $eh "OPTIONAL CONTROL ARTIFACTS"
puts $eh "=========================="
foreach path $G9A_OPTIONAL_CONTROL_ARTIFACTS {
    if {[file exists $path]} {
        set h [g9a_sha256 $path]
        puts $eh [format {%s  %s} $h $path]
    } else {
        puts $eh [format {NOT_PRESENT  %s} $path]
    }
}
close $eh

# ------------------------------------------------------------
# Freeze summary
# ------------------------------------------------------------
set fp [open $G9A_FREEZE_FILE "w"]

puts $fp "============================================================"
puts $fp "CODE-COV-C1.2-G9-A"
puts $fp "Final Baseline / Closure Evidence Freeze"
puts $fp "============================================================"
puts $fp ""

g9a_write_block $fp "SOURCE BASELINE" [format \
"Git available : %s
Git root      : %s
Git branch    : %s
Git HEAD      : %s
Commit time   : %s
Commit subject: %s
Working tree  : %s" \
[expr {$git_ok ? "YES" : "NO"}] \
$git_root \
$git_branch \
$git_head \
$git_commit_time \
$git_subject \
[expr {$git_clean ? "CLEAN" : "NOT_CLEAN_OR_UNAVAILABLE"}]]

g9a_write_block $fp "FROZEN VALIDATED FUNCTIONAL BASELINE" \
"Full regression : 150 / 150 PASS
CODE-COV        : PASS
UCDB merge      : PASS
UCDB report     : PASS
Known open real integration bugs : 0"

g9a_write_block $fp "FROZEN RAW / EFFECTIVE COVERAGE BASELINE" \
"RAW authoritative bcefst      : 74.36%
Final EFFECTIVE bcefst         : 76.87%
Final EFFECTIVE bcef           : 82.94%
Final EFFECTIVE statement      : 99.68%
Toggle RAW == EFFECTIVE        : 29.78%

RAW statement                  : 5285 / 5095 / 190
EFFECTIVE statement            : 5111 / 5095 / 16

RAW branch                     : 2866 / 2638 / 228
EFFECTIVE branch               : 2862 / 2638 / 224

RAW condition                  : 533 / 362 / 171
EFFECTIVE condition            : 533 / 385 / 148

RAW expression                 : 835 / 651 / 184
EFFECTIVE expression           : 835 / 697 / 138

RAW FSM states                 : 121 / 121 / 0
EFFECTIVE FSM states           : 121 / 121 / 0

RAW FSM transitions            : 279 / 179 / 100
EFFECTIVE FSM transitions      : 264 / 179 / 85

RAW toggle                     : 96910 / 28867 / 68043
EFFECTIVE toggle               : 96910 / 28867 / 68043"

g9a_write_block $fp "G8 CLOSURE BASELINE" \
"G8-C1 : CLOSED
G8-C2 : CLOSED
G8-C3 : CLOSED
G8-C  : CLOSED

Statement physical exclusions : 174
Safe branch exclusions         : 4
Condition exact FEC rows       : 23
Expression exact FEC rows      : 46
FSM transition exclusions      : 15
Toggle exclusions              : 0

Protected constructive statement misses retained : 16
Approved branch residues retained due tool granularity : 14
Repaired real bugs converted to exclusions : 0"

g9a_write_block $fp "EVIDENCE FREEZE STATUS" [format \
"Critical evidence files missing : %d
Git baseline captured            : %s
Working tree clean              : %s

Evidence hash inventory:
  %s

Git status snapshot:
  %s" \
$critical_missing \
[expr {$git_ok ? "YES" : "NO"}] \
[expr {$git_clean ? "YES" : "NO"}] \
$G9A_EVIDENCE_HASH_FILE \
$G9A_GIT_STATUS_FILE]

set g9a_pass 1
if {!$git_ok} {
    set g9a_pass 0
}
if {$critical_missing != 0} {
    set g9a_pass 0
}

puts $fp "------------------------------------------------------------"
puts $fp "G9-A PRELIMINARY RESULT"
puts $fp "------------------------------------------------------------"
if {$g9a_pass} {
    puts $fp "PASS"
    puts $fp ""
    puts $fp "NOTE:"
    puts $fp "A dirty Git working tree does not automatically fail this capture."
    puts $fp "It must be reviewed to distinguish source changes from ignored/"
    puts $fp "generated closure artifacts before G9-A is formally CLOSED."
} else {
    puts $fp "OPEN / REVIEW REQUIRED"
}
puts $fp ""
puts $fp "============================================================"
close $fp

if {!$git_ok} {
    puts {[G9-A][WARN] Git baseline could not be captured.}
}
if {$critical_missing != 0} {
    puts [format {[G9-A][WARN] Missing critical evidence files: %d} $critical_missing]
}

puts [format {[G9-A] Git HEAD: %s} $git_head]
puts [format {[G9-A] Working tree: %s} [expr {$git_clean ? "CLEAN" : "NOT CLEAN / REVIEW REQUIRED"}]]
puts [format {[G9-A] Critical evidence missing: %d} $critical_missing]
puts [format {[G9-A] Freeze record: %s} $G9A_FREEZE_FILE]

if {$g9a_pass} {
    puts {[G9-A] PASS: baseline identity and critical evidence inventory captured.}
    puts {[G9-A] IMPORTANT: formal closure still requires review of the Git status snapshot and final evidence ledger.}
} else {
    puts {[G9-A] OPEN: capture completed, but one or more baseline/evidence gates require review.}
}
