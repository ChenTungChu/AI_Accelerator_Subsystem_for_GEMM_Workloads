CODE-COV-C1.2-G8-C2-A Rev-B
Physical-safe Branch / Condition / Expression / FSM artifact.

Replace the previous C2-A files with these files and run:

  do run_g8_c2a_multimetric_effective.tcl

No compile, simulation, or full regression is required.

Expected reports:
  coverage/code_cov/g8_c/g8_c2a_effective_statement_summary.txt
  coverage/code_cov/g8_c/g8_c2a_effective_multimetric_summary.txt
  coverage/code_cov/g8_c/g8_c2a_effective_multimetric_details.txt
  coverage/code_cov/g8_c/g8_c2a_effective_multimetric_zeros.txt

Rev-B intentionally leaves 14 G8-B-approved branch misses physically
visible because the first proof showed that branch `-item b` exclusions
can remove covered companion arms in Questa 10.7c.

This is the correct behavior: preserve covered evidence rather than
inflate effective branch coverage.

The dma_load_engine line-399 branch exclusion is retained because Rev-A empirically proved RAW 33/32/1 -> EFFECTIVE 32/32/0 with zero covered-hit loss.
