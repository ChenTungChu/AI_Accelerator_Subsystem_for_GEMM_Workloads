CODE-COV-C1.2-G8-C1 — Statement-only effective UCDB proof package (Rev-B)

Purpose
-------
Create a separate effective UCDB from the canonical post-R3 RAW merged UCDB,
apply only the 174 G8-B-approved statement source-line exclusions, and generate
RAW/EFFECTIVE statement reports for physical reconciliation.

Questa 10.7c compatibility fixes
--------------------------------
Rev-A fixed Tcl square-bracket command substitution in log strings.
Rev-B fixes Coverage View dataset lifetime handling:
  * coverage open <ucdb> <logical_name>
  * dataset close <logical_name>

Questa 10.7c does NOT provide a "coverage close" subcommand.  The wrapper also
closes a leftover G8-C1 dataset at startup so it can be rerun safely after an
interrupted prior attempt.

Files
-----
  g8_c_statement_exclusions.tcl
  run_g8_c_statement_effective.tcl
  g8_c_statement_manifest.txt
  README_G8_C1.txt

Run
---
From the project simulation directory:

  do run_g8_c_statement_effective.tcl

No compile or simulation is required.

Canonical RAW input
-------------------
  coverage/code_cov/code_cov_merged.ucdb

Effective working copy
----------------------
  coverage/code_cov/g8_c/code_cov_g8_c_statement_effective.ucdb

Generated proof reports
-----------------------
  coverage/code_cov/g8_c/g8_c_raw_statement_summary.txt
  coverage/code_cov/g8_c/g8_c_raw_statement_details.txt
  coverage/code_cov/g8_c/g8_c_effective_statement_summary.txt
  coverage/code_cov/g8_c/g8_c_effective_statement_details.txt

Do not declare G8-C1 closed until RAW vs EFFECTIVE reconciliation proves:
  * covered statement hits are unchanged,
  * only G8-B-approved statement objects disappeared,
  * protected constructive misses remain visible,
  * canonical RAW UCDB remains untouched.


Rev-C correction (physical-bin normalization)
---------------------------------------------
The Rev-B proof exposed one line-granularity hazard in Questa: rtl/mem/axi_mm_dual_port_bram.sv line 1316 has two statement items on the same source line. Item 1 is covered; item 2 is the approved zero-hit candidate. A line-wide -code s exclusion removed both and caused covered hits to fall from 5095 to 5094. Rev-C uses -item s 2 so only the approved zero-hit physical bin is excluded.

Rev-C acceptance target:
  RAW       5285 active / 5095 hits / 190 misses
  EFFECTIVE 5111 active / 5095 hits / 16 misses
  covered-hit loss = 0
  protected constructive misses remain = 16
