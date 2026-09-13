CODE-COV-C1.2-G8-C3
Final RAW vs EFFECTIVE Reconciliation / Closure

Files:
  run_g8_c3_final_reconciliation.tcl
  g8_c3_final_reconciliation_manifest.txt
  README_G8_C3.txt

Run from the same project/sim directory used for prior G8-C scripts:

  do run_g8_c3_final_reconciliation.tcl

No compile, simulation, or full regression is required.

The script is report-only:
  - it does not coverage-open either UCDB for editing;
  - it does not coverage-save either UCDB;
  - it hashes the canonical RAW UCDB before and after report generation.

Generated evidence:
  coverage/code_cov/g8_c/g8_c3_raw_bcefst_summary.txt
  coverage/code_cov/g8_c/g8_c3_effective_bcefst_summary.txt
  coverage/code_cov/g8_c/g8_c3_raw_statement_summary.txt
  coverage/code_cov/g8_c/g8_c3_effective_statement_summary.txt
  coverage/code_cov/g8_c/g8_c3_raw_multimetric_summary.txt
  coverage/code_cov/g8_c/g8_c3_effective_multimetric_summary.txt
  coverage/code_cov/g8_c/g8_c3_raw_toggle_summary.txt
  coverage/code_cov/g8_c/g8_c3_effective_toggle_summary.txt
  coverage/code_cov/g8_c/g8_c3_effective_remaining_zeros.txt
  coverage/code_cov/g8_c/g8_c3_raw_immutability_sha256.txt

For the next review, the minimum files to upload are:
  1. g8_c3_raw_bcefst_summary.txt
  2. g8_c3_effective_bcefst_summary.txt
  3. g8_c3_effective_multimetric_summary.txt
  4. g8_c3_effective_statement_summary.txt
  5. g8_c3_effective_toggle_summary.txt
  6. g8_c3_raw_immutability_sha256.txt

The remaining-zero report is useful if any expected ledger count does not match.
