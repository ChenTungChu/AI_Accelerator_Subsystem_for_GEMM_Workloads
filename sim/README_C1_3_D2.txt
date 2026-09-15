CODE-COV-C1.3-D2 Rev-A
Frozen C1.2 Exclusion Replay / Final C1.3 Effective Audit
============================================================

Purpose
-------
Replay the EXACT frozen C1.2 G8-C exclusion ledgers against the final C1.3
canonical RAW UCDB, without modifying the RAW UCDB or the frozen exclusion Tcl.

Rev-A correction
----------------
The first C1.3-D2 wrapper generalized the three replay stages but omitted the
legacy wrapper-variable contract expected by the frozen G8-C2 exclusion Tcl.
In particular, g8_c2a_multimetric_exclusions.tcl requires G8C2_DATASET.
The first run therefore stopped at Stage 2 before valid C2-A exclusions were
applied.

Rev-A recreates the exact proven wrapper environments before each stage:
  Stage 1: G8C_* variables
  Stage 2: G8C2_* variables
  Stage 3: G8C2B_* variables

The frozen exclusion files themselves are UNCHANGED.

Safety / rerun behavior
-----------------------
No cleanup is required after the failed first run. Rev-A rebuilds Stage 1 from
coverage/code_cov/code_cov_merged.ucdb and then overwrites each downstream
working UCDB in coverage/code_cov/c1_3_d/.

Canonical RAW expected SHA256:
ff2918d43a714d0ecd70ac8b1001c84cdfc3188f0ed4f825f3489343e0a1e079

Frozen exclusion SHA256:
statement:
38b4e7543712fa35b469e7a103265711044db079be8815583376e1e833544846

C2-A:
2419f400b05636d49a19bf411add48c9dc36bf8aa78e7c2b7d71572d39d45a9c

C2-B:
d697d4a25bfd13102f75eb07cb7c032f45f6c3d0a53cca27b46173d0d07488a4

Run
---
From the normal sim/project Tcl directory:

  do run_c1_3_d_effective_replay.tcl

No compile, simulation, or full regression is required.

Do not declare C1.3-D closed from command PASS alone. Final closure still
requires RAW-vs-EFFECTIVE metric reconciliation of the generated reports.
