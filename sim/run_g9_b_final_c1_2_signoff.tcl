# ============================================================
# CODE-COV-C1.2-G9-B Rev-A
# Final C1.2 Closure Record / Signoff Freeze
#
# Rev-A fix:
#   The original G9-B clean-tree gate was self-invalidating because
#   the three new G9-B audit/control files themselves appear as
#   untracked files after extraction into sim/.
#
#   Rev-A evaluates Git cleanliness from the repository root and
#   ignores ONLY the G9-B audit/control artifacts listed below.
#   Any other modified/staged/untracked path still fails signoff.
#
# Run from:
#   <repo>/sim
#
# No RTL/UVM/docs/UCDB modification.
# QuestaSim 10.7c / Windows
# ============================================================

set G9B_OUT_DIR "coverage/code_cov/g9_b"
set G9B_VERIFY_FILE "$G9B_OUT_DIR/g9_b_signoff_verification.txt"
set G9B_RECORD_FILE "$G9B_OUT_DIR/g9_b_final_c1_2_closure_record.txt"

set G9B_EXPECTED_BRANCH "main"
set G9B_EXPECTED_HEAD   "41f31d7c6e4dfe6765fe41000df856b342b8276a"
set G9B_EXPECTED_SUBJECT "Completed final RAW vs. Effective reconciliation closure"

set G9B_EXPECTED_HASHES [dict create \
    "coverage/code_cov/code_cov_merged.ucdb" \
        "8ae9c124f259d48a5e8aaa12c9156b9fc7695e77246afd1ebe2b42f7b99c32f8" \
    "coverage/code_cov/g8_c/code_cov_g8_c2b_multimetric_effective.ucdb" \
        "87eaabc414a196a2288f8e5ffbb5bab7c502a83295f99d7f60e5ed4f4b8decdc" \
    "coverage/code_cov/g8_c/g8_c3_raw_bcefst_summary.txt" \
        "ed80b03f68357e585a10463ba1a94e54fa4d00c8c50a40fee03d0a012034037d" \
    "coverage/code_cov/g8_c/g8_c3_effective_bcefst_summary.txt" \
        "83ef83edf94e9158fe78d2c91ca1eccec3198f177e7b2bb1fe35f9e271bab406" \
    "coverage/code_cov/g8_c/g8_c3_effective_multimetric_summary.txt" \
        "e0677c4ee607f917756c68d7d86d3318481a46717375a801ff94ff4b9af89ba1" \
    "coverage/code_cov/g8_c/g8_c3_effective_statement_summary.txt" \
        "364d47c52781e717e8c0328fc937e6105b9d4864a029d3f46b584f9d352f22ee" \
    "coverage/code_cov/g8_c/g8_c3_effective_toggle_summary.txt" \
        "74e9d6a48965986ff4beac2e97e3e199b47779ea7863b0cda1d6486ae2cb5236" \
    "coverage/code_cov/g8_c/g8_c3_raw_immutability_sha256.txt" \
        "02ad7848e10583de7e72c9c3426cf1478315f97165c53c885ace689718aee019" \
]

# Root-relative paths that are allowed to be untracked/modified during
# G9-B itself. Nothing else is ignored.
set G9B_ALLOWED_DIRTY_EXACT [list \
    "sim/run_g9_b_final_c1_2_signoff.tcl" \
    "sim/g9_b_final_signoff_manifest.txt" \
    "sim/README_G9_B.txt" \
]

set G9B_ALLOWED_DIRTY_PREFIX [list \
    "sim/coverage/code_cov/g9_b/" \
]

proc g9b_sha256 {path} {
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

proc g9b_bool {v} {
    if {$v} { return "PASS" }
    return "FAIL"
}

proc g9b_status_path {line} {
    # Porcelain v1: first two chars are XY, char 3 is a space.
    # Everything after that is the path (or "old -> new" for rename).
    if {[string length $line] < 4} {
        return ""
    }
    set p [string trim [string range $line 3 end]]

    # For rename/copy, audit the destination path.
    set arrow " -> "
    set idx [string first $arrow $p]
    if {$idx >= 0} {
        set p [string trim [string range $p [expr {$idx + [string length $arrow]}] end]]
    }

    # Remove porcelain quoting for ordinary quoted paths.
    if {[string length $p] >= 2 &&
        [string index $p 0] eq "\"" &&
        [string index $p end] eq "\""} {
        set p [string range $p 1 end-1]
    }

    # Normalize path separators for matching.
    regsub -all {\\} $p {/} p
    return $p
}

proc g9b_is_allowed_dirty {path exact_list prefix_list} {
    foreach allowed $exact_list {
        if {$path eq $allowed} {
            return 1
        }
    }
    foreach prefix $prefix_list {
        if {[string first $prefix $path] == 0} {
            return 1
        }
    }
    return 0
}

file mkdir $G9B_OUT_DIR

puts {[G9-B Rev-A] Final C1.2 Closure Record / Signoff Freeze starting.}

# -----------------------------------------------------------------
# Git final-baseline verification.
# Use -C <repo-root> so porcelain paths are deterministic/root-relative.
# -----------------------------------------------------------------
set git_ok 1
set git_root ""
set git_branch ""
set git_head ""
set git_subject ""
set git_status_raw ""
set git_status_blocking [list]
set git_status_allowed [list]

if {[catch {exec git rev-parse --show-toplevel} msg]} {
    set git_ok 0
} else {
    set git_root [string trim $msg]
}

if {$git_ok && [catch {exec git -C $git_root rev-parse --abbrev-ref HEAD} msg]} {
    set git_ok 0
} elseif {$git_ok} {
    set git_branch [string trim $msg]
}

if {$git_ok && [catch {exec git -C $git_root rev-parse HEAD} msg]} {
    set git_ok 0
} elseif {$git_ok} {
    set git_head [string trim $msg]
}

if {$git_ok && [catch {exec git -C $git_root show -s --format=%s HEAD} msg]} {
    set git_ok 0
} elseif {$git_ok} {
    set git_subject [string trim $msg]
}

if {$git_ok} {
    catch {set git_status_raw [exec git -C $git_root status --porcelain=v1 --untracked-files=all]}
}

if {$git_ok && [string trim $git_status_raw] ne ""} {
    foreach line [split $git_status_raw "\n"] {
        set line [string trimright $line "\r"]
        if {[string trim $line] eq ""} {
            continue
        }
        set path [g9b_status_path $line]
        if {[g9b_is_allowed_dirty $path $G9B_ALLOWED_DIRTY_EXACT $G9B_ALLOWED_DIRTY_PREFIX]} {
            lappend git_status_allowed $line
        } else {
            lappend git_status_blocking $line
        }
    }
}

set branch_pass [expr {$git_ok && ($git_branch eq $G9B_EXPECTED_BRANCH)}]
set head_pass [expr {$git_ok && ($git_head eq $G9B_EXPECTED_HEAD)}]
set subject_pass [expr {$git_ok && ($git_subject eq $G9B_EXPECTED_SUBJECT)}]

# "Clean" for signoff means: no dirty path outside the explicit G9-B
# self-artifact allowlist.
set clean_pass [expr {$git_ok && ([llength $git_status_blocking] == 0)}]

# -----------------------------------------------------------------
# Evidence hash verification.
# -----------------------------------------------------------------
set hash_pass 1
set hash_missing 0
set hash_mismatch 0
set hash_lines [list]

dict for {path expected} $G9B_EXPECTED_HASHES {
    if {![file exists $path]} {
        set hash_pass 0
        incr hash_missing
        lappend hash_lines [format {MISSING  %s} $path]
    } else {
        set actual [g9b_sha256 $path]
        if {$actual ne $expected} {
            set hash_pass 0
            incr hash_mismatch
            lappend hash_lines [format {FAIL  %s
      expected: %s
      actual  : %s} $path $expected $actual]
        } else {
            lappend hash_lines [format {PASS  %s
      sha256: %s} $path $actual]
        }
    }
}

set signoff_pass [expr {
    $git_ok &&
    $branch_pass &&
    $head_pass &&
    $subject_pass &&
    $clean_pass &&
    $hash_pass
}]

# -----------------------------------------------------------------
# Detailed verification file.
# -----------------------------------------------------------------
set vf [open $G9B_VERIFY_FILE "w"]
puts $vf "============================================================"
puts $vf "CODE-COV-C1.2-G9-B Rev-A"
puts $vf "Final C1.2 Closure Record / Signoff Verification"
puts $vf "============================================================"
puts $vf ""
puts $vf "GIT BASELINE VERIFICATION"
puts $vf "------------------------------------------------------------"
puts $vf [format {Git available : %s} [g9b_bool $git_ok]]
puts $vf [format {Git root      : %s} $git_root]
puts $vf [format {Branch        : %s} $git_branch]
puts $vf [format {Branch match  : %s} [g9b_bool $branch_pass]]
puts $vf [format {HEAD          : %s} $git_head]
puts $vf [format {HEAD match    : %s} [g9b_bool $head_pass]]
puts $vf [format {Subject       : %s} $git_subject]
puts $vf [format {Subject match : %s} [g9b_bool $subject_pass]]
puts $vf ""
puts $vf "G9-B SELF-ARTIFACT STATUS ENTRIES (ALLOWED)"
puts $vf "------------------------------------------------------------"
if {[llength $git_status_allowed] == 0} {
    puts $vf "<none>"
} else {
    foreach line $git_status_allowed {
        puts $vf $line
    }
}
puts $vf ""
puts $vf "BLOCKING STATUS ENTRIES"
puts $vf "------------------------------------------------------------"
if {[llength $git_status_blocking] == 0} {
    puts $vf "<none>"
} else {
    foreach line $git_status_blocking {
        puts $vf $line
    }
}
puts $vf ""
puts $vf [format {Baseline clean gate: %s} [g9b_bool $clean_pass]]
puts $vf ""
puts $vf "CRITICAL EVIDENCE SHA256 VERIFICATION"
puts $vf "------------------------------------------------------------"
foreach line $hash_lines {
    puts $vf $line
}
puts $vf ""
puts $vf [format {Missing files  : %d} $hash_missing]
puts $vf [format {Hash mismatch  : %d} $hash_mismatch]
puts $vf [format {Hash gate      : %s} [g9b_bool $hash_pass]]
puts $vf ""
puts $vf "FINAL SIGNOFF GATE"
puts $vf "------------------------------------------------------------"
puts $vf [format {RESULT: %s} [g9b_bool $signoff_pass]]
puts $vf "============================================================"
close $vf

# -----------------------------------------------------------------
# Final C1.2 closure record.
# -----------------------------------------------------------------
set rf [open $G9B_RECORD_FILE "w"]
puts $rf "============================================================"
puts $rf "CODE-COV-C1.2"
puts $rf "FINAL CLOSURE / SIGNOFF RECORD"
puts $rf "============================================================"
puts $rf ""
puts $rf "FINAL SOURCE BASELINE"
puts $rf "------------------------------------------------------------"
puts $rf "Branch : main"
puts $rf "HEAD   : 41f31d7c6e4dfe6765fe41000df856b342b8276a"
puts $rf "Subject: Completed final RAW vs. Effective reconciliation closure"
puts $rf "Baseline source/evidence dirty entries required: NONE"
puts $rf "G9-B self-audit artifacts are excluded from the clean-tree gate."
puts $rf ""
puts $rf "FUNCTIONAL VALIDATION"
puts $rf "------------------------------------------------------------"
puts $rf "Full regression : 150 / 150 PASS"
puts $rf "FAIL            : 0"
puts $rf "CODE-COV        : PASS"
puts $rf "UCDB merge      : PASS"
puts $rf "UCDB report     : PASS"
puts $rf "Known open real integration bugs : 0"
puts $rf ""
puts $rf "AUTHORITATIVE RAW COVERAGE"
puts $rf "------------------------------------------------------------"
puts $rf "Filtered bcefst aggregate : 74.36%"
puts $rf ""
puts $rf "FINAL EFFECTIVE AUDIT VIEW"
puts $rf "------------------------------------------------------------"
puts $rf "bcefst    : 76.87%"
puts $rf "bcef      : 82.94%"
puts $rf "statement : 99.68%"
puts $rf "toggle    : 29.78%  (RAW == EFFECTIVE)"
puts $rf ""
puts $rf "FINAL RAW -> EFFECTIVE METRIC LEDGER"
puts $rf "------------------------------------------------------------"
puts $rf "Statement       RAW 5285/5095/190  -> EFF 5111/5095/16"
puts $rf "Branch          RAW 2866/2638/228  -> EFF 2862/2638/224"
puts $rf "Condition       RAW 533/362/171    -> EFF 533/385/148"
puts $rf "Expression      RAW 835/651/184    -> EFF 835/697/138"
puts $rf "FSM states      RAW 121/121/0      -> EFF 121/121/0"
puts $rf "FSM transitions RAW 279/179/100    -> EFF 264/179/85"
puts $rf "Toggle          RAW 96910/28867/68043 -> EFF 96910/28867/68043"
puts $rf ""
puts $rf "EXCLUSION / RESIDUE ACCOUNTING"
puts $rf "------------------------------------------------------------"
puts $rf "Statement physical exclusions                  : 174"
puts $rf "Safe branch exclusions                          : 4"
puts $rf "Condition exact FEC rows                        : 23"
puts $rf "Expression exact FEC rows                       : 46"
puts $rf "FSM transition exclusions                       : 15"
puts $rf "Toggle exclusions                               : 0"
puts $rf "Protected constructive statement misses retained: 16"
puts $rf "Approved branch residues retained (tool limit) : 14"
puts $rf "Repaired real bugs converted to exclusions      : 0"
puts $rf ""
puts $rf "MILESTONE CLOSURE STATUS"
puts $rf "------------------------------------------------------------"
puts $rf "G8-C1 : CLOSED"
puts $rf "G8-C2 : CLOSED"
puts $rf "G8-C3 : CLOSED"
puts $rf "G8-C  : CLOSED"
puts $rf "G9-A  : CLOSED"
puts $rf [format {G9-B  : %s} [expr {$signoff_pass ? "CLOSED" : "OPEN"}]]
puts $rf ""
if {$signoff_pass} {
    puts $rf "CODE-COV-C1.2 : CLOSED"
    puts $rf ""
    puts $rf "SIGNOFF RESULT: PASS"
} else {
    puts $rf "CODE-COV-C1.2 : OPEN"
    puts $rf ""
    puts $rf "SIGNOFF RESULT: FAIL"
}
puts $rf ""
puts $rf "IMPORTANT INTERPRETATION"
puts $rf "------------------------------------------------------------"
puts $rf "74.36% is the authoritative RAW physical code-coverage baseline."
puts $rf "76.87% is an exclusion-aware EFFECTIVE audit view and must not be"
puts $rf "reported as a raw-regression coverage increase."
puts $rf ""
puts $rf "No RTL/UVM/source change is performed by G9-B."
puts $rf "No compile/simulation/full regression is required."
puts $rf "============================================================"
close $rf

puts [format {[G9-B Rev-A] Verification report: %s} $G9B_VERIFY_FILE]
puts [format {[G9-B Rev-A] Closure record     : %s} $G9B_RECORD_FILE]

if {$signoff_pass} {
    puts {[G9-B Rev-A] PASS: exact final source/evidence baseline matches G9-A freeze.}
    puts {[G9-B Rev-A] CODE-COV-C1.2 final signoff record emitted with CLOSED status.}
} else {
    puts {[G9-B Rev-A] FAIL: baseline/evidence outside G9-B self-artifacts no longer matches G9-A freeze.}
    error {CODE-COV-C1.2-G9-B Rev-A signoff gate failed. Review g9_b_signoff_verification.txt.}
}
