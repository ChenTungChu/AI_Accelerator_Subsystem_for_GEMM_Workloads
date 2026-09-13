CODE-COV-C1.2-G8-C2-B
Port0 Owner / CSR-Top Expression Physical Normalization

Files:
  g8_c2b_expression_exclusions.tcl
  run_g8_c2b_expression_effective.tcl
  g8_c2b_expression_manifest.txt
  README_G8_C2B.txt

Run from the same project/sim directory used for the previous G8-C scripts:

  do run_g8_c2b_expression_effective.tcl

No compile, simulation, or full regression is required.

Generated reports:
  coverage/code_cov/g8_c/g8_c2b_effective_statement_summary.txt
  coverage/code_cov/g8_c/g8_c2b_effective_multimetric_summary.txt
  coverage/code_cov/g8_c/g8_c2b_effective_multimetric_details.txt
  coverage/code_cov/g8_c/g8_c2b_effective_multimetric_zeros.txt
  coverage/code_cov/g8_c/g8_c2b_effective_toggle_summary.txt

This stage is expression-only. It does not attempt to hide the 14
G8-B-approved branch residues that Questa 10.7c cannot isolate without
collateral covered-bin loss.
