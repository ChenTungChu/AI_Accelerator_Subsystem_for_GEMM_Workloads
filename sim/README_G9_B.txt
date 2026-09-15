CODE-COV-C1.2-G9-B Rev-A

Why Rev-A
---------
The first script failed only because the new G9-B audit files themselves
made `git status` non-clean after extraction. This is an audit-script
self-reference issue, not a source/evidence mismatch.

Run from:
  <repo>/sim

Command:
  do run_g9_b_final_c1_2_signoff.tcl

No compile is required.
No simulation is required.
No full regression is required.

Replace the three original G9-B package files in sim/ with this Rev-A set.

Generated files:
  coverage/code_cov/g9_b/g9_b_signoff_verification.txt
  coverage/code_cov/g9_b/g9_b_final_c1_2_closure_record.txt

Upload both generated files after the run.
