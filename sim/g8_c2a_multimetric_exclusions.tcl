# ============================================================
# CODE-COV-C1.2-G8-C2-A Rev-B
# Exact Branch / Condition / Expression / FSM Exclusions
#
# IMPORTANT Rev-B correction:
#   Questa 10.7c branch -item exclusions operate at decision-item
#   granularity and can remove the covered companion arm of an IF.
#   Therefore Rev-B physically applies only branch exclusions that
#   can be represented safely with -allfalse.
#
#   G8-B approval of the other branch residues is NOT revoked.
#   Those approved true/explicit-arm misses remain visible in the
#   effective UCDB because the tool cannot exclude them without
#   collateral covered-bin loss at this granularity.
#
# Input:
#   coverage/code_cov/g8_c/code_cov_g8_c_statement_effective.ucdb
#
# Policy:
#   - No statement exclusions added here.
#   - No toggle exclusions.
#   - Condition/expression exclusions are exact zero FEC rows.
#   - FSM exclusions are exact transitions.
#   - Port0-owner-mux expression residue and CSR-top expression
#     residue remain deferred to G8-C2-B.
# ============================================================

if {![info exists G8C2_DATASET]} {
    error {G8-C2-A Rev-B requires G8C2_DATASET to be defined by the wrapper.}
}

proc g8c2_excl_branch_allfalse {src line} {
    global G8C2_DATASET
    coverage exclude \
        -srcfile $src \
        -linerange $line \
        -allfalse \
        -code b \
        -dataset $G8C2_DATASET
}

proc g8c2_excl_cond_row {src line row} {
    global G8C2_DATASET
    coverage exclude \
        -srcfile $src \
        -feccondrow $line $row \
        -dataset $G8C2_DATASET
}

proc g8c2_excl_expr_row {src line row} {
    global G8C2_DATASET
    coverage exclude \
        -srcfile $src \
        -fecexprrow $line $row \
        -dataset $G8C2_DATASET
}

proc g8c2_excl_ftrans {du state_var transition} {
    global G8C2_DATASET
    coverage exclude \
        -du $du \
        -ftrans $state_var $transition \
        -dataset $G8C2_DATASET
}

# ------------------------------------------------------------
# Branch: ONLY safely representable all-false bins
# ------------------------------------------------------------

# gemm_scratchpad_adapter: two approved all-false handshake residues.
g8c2_excl_branch_allfalse ../rtl/subsystem/gemm_scratchpad_adapter.sv 192
g8c2_excl_branch_allfalse ../rtl/subsystem/gemm_scratchpad_adapter.sv 228

# dma_load_engine: this default-branch item was empirically proven safe in
# C2-A Rev-A: RAW 33/32/1 -> EFFECTIVE 32/32/0 with zero covered-hit loss.
coverage exclude \
    -srcfile ../rtl/subsystem/dma_load_engine.sv \
    -linerange 399 \
    -item b 1 \
    -dataset $G8C2_DATASET

# CSR top: domain helper IF/ELSE-IF chain all-false residue.
# The all-false bin belongs to the decision tree starting at line 1055.
g8c2_excl_branch_allfalse ../rtl/top/ai_accel_subsys_csr_top.sv 1055

# Intentionally NOT physically excluded in Rev-B:
#   dma_scratchpad_write_adapter.sv     lines 342, 318
#   dma_store_engine.sv                 lines 345,526,442,450,457,476,491,512
#   scratchpad_port0_owner_mux.sv       line 309
#   scratchpad_port1_owner_mux.sv       line 335
#   ai_accel_subsys.sv                  line 603
#   ai_accel_subsys_csr_top.sv          line 1083
#
# These remain G8-B-approved structural residues, but the attempted
# branch -item representation removed covered companion arms in C2-A Rev-A.

# ------------------------------------------------------------
# Condition/FEC: 23 approved zero rows
# ------------------------------------------------------------

# dma_scratchpad_write_adapter: 4
g8c2_excl_cond_row ../rtl/subsystem/dma_scratchpad_write_adapter.sv 222 4
g8c2_excl_cond_row ../rtl/subsystem/dma_scratchpad_write_adapter.sv 222 6
g8c2_excl_cond_row ../rtl/subsystem/dma_scratchpad_write_adapter.sv 318 2
g8c2_excl_cond_row ../rtl/subsystem/dma_scratchpad_write_adapter.sv 318 4

# dma_store_engine: 1
g8c2_excl_cond_row ../rtl/subsystem/dma_store_engine.sv 509 1

# ai_accel_subsys: 4
g8c2_excl_cond_row ../rtl/top/ai_accel_subsys.sv 603 2
g8c2_excl_cond_row ../rtl/top/ai_accel_subsys.sv 603 4
g8c2_excl_cond_row ../rtl/top/ai_accel_subsys.sv 973 4
g8c2_excl_cond_row ../rtl/top/ai_accel_subsys.sv 973 6

# ai_accel_subsys_csr_top: 14
g8c2_excl_cond_row ../rtl/top/ai_accel_subsys_csr_top.sv 1009 4
g8c2_excl_cond_row ../rtl/top/ai_accel_subsys_csr_top.sv 1011 4
g8c2_excl_cond_row ../rtl/top/ai_accel_subsys_csr_top.sv 1011 6
g8c2_excl_cond_row ../rtl/top/ai_accel_subsys_csr_top.sv 1011 8
g8c2_excl_cond_row ../rtl/top/ai_accel_subsys_csr_top.sv 1011 10
g8c2_excl_cond_row ../rtl/top/ai_accel_subsys_csr_top.sv 1011 12
g8c2_excl_cond_row ../rtl/top/ai_accel_subsys_csr_top.sv 1011 14
g8c2_excl_cond_row ../rtl/top/ai_accel_subsys_csr_top.sv 1057 1
g8c2_excl_cond_row ../rtl/top/ai_accel_subsys_csr_top.sv 1083 2
g8c2_excl_cond_row ../rtl/top/ai_accel_subsys_csr_top.sv 1091 2
g8c2_excl_cond_row ../rtl/top/ai_accel_subsys_csr_top.sv 1091 6
g8c2_excl_cond_row ../rtl/top/ai_accel_subsys_csr_top.sv 1202 8
g8c2_excl_cond_row ../rtl/top/ai_accel_subsys_csr_top.sv 1907 8
g8c2_excl_cond_row ../rtl/top/ai_accel_subsys_csr_top.sv 2256 4

# ------------------------------------------------------------
# Expression/FEC: 23 approved zero rows in C2-A
#
# Deliberately deferred to C2-B:
#   scratchpad_port0_owner_mux : 6 approved expression terms
#   ai_accel_subsys_csr_top    : 17 approved expression terms
# ------------------------------------------------------------

# dma_scratchpad_write_adapter: 5
g8c2_excl_expr_row ../rtl/subsystem/dma_scratchpad_write_adapter.sv 142 3
g8c2_excl_expr_row ../rtl/subsystem/dma_scratchpad_write_adapter.sv 144 3
g8c2_excl_expr_row ../rtl/subsystem/dma_scratchpad_write_adapter.sv 161 4
g8c2_excl_expr_row ../rtl/subsystem/dma_scratchpad_write_adapter.sv 161 6
g8c2_excl_expr_row ../rtl/subsystem/dma_scratchpad_write_adapter.sv 190 4

# dma_store_engine: 8
g8c2_excl_expr_row ../rtl/subsystem/dma_store_engine.sv 229 3
g8c2_excl_expr_row ../rtl/subsystem/dma_store_engine.sv 230 3
g8c2_excl_expr_row ../rtl/subsystem/dma_store_engine.sv 234 3
g8c2_excl_expr_row ../rtl/subsystem/dma_store_engine.sv 239 2
g8c2_excl_expr_row ../rtl/subsystem/dma_store_engine.sv 239 4
g8c2_excl_expr_row ../rtl/subsystem/dma_store_engine.sv 239 6
g8c2_excl_expr_row ../rtl/subsystem/dma_store_engine.sv 239 7
g8c2_excl_expr_row ../rtl/subsystem/dma_store_engine.sv 249 6

# scratchpad_port1_owner_mux: 2
g8c2_excl_expr_row ../rtl/subsystem/scratchpad_port1_owner_mux.sv 179 2
g8c2_excl_expr_row ../rtl/subsystem/scratchpad_port1_owner_mux.sv 179 4

# ai_accel_subsys: 8
g8c2_excl_expr_row ../rtl/top/ai_accel_subsys.sv 686 9
g8c2_excl_expr_row ../rtl/top/ai_accel_subsys.sv 686 11
g8c2_excl_expr_row ../rtl/top/ai_accel_subsys.sv 701 4
g8c2_excl_expr_row ../rtl/top/ai_accel_subsys.sv 701 6
g8c2_excl_expr_row ../rtl/top/ai_accel_subsys.sv 701 8
g8c2_excl_expr_row ../rtl/top/ai_accel_subsys.sv 955 4
g8c2_excl_expr_row ../rtl/top/ai_accel_subsys.sv 981 4
g8c2_excl_expr_row ../rtl/top/ai_accel_subsys.sv 981 6

# ------------------------------------------------------------
# FSM transitions: 15 approved exact transitions
# ------------------------------------------------------------

# gemm_scratchpad_adapter: 5
g8c2_excl_ftrans gemm_scratchpad_adapter state_q S_WR_ADDR->S_IDLE
g8c2_excl_ftrans gemm_scratchpad_adapter state_q S_RD_ADDR->S_IDLE
g8c2_excl_ftrans gemm_scratchpad_adapter state_q S_RD_RETURN->S_IDLE
g8c2_excl_ftrans gemm_scratchpad_adapter state_q S_WR_DATA->S_IDLE
g8c2_excl_ftrans gemm_scratchpad_adapter state_q S_WR_RESP->S_IDLE

# dma_load_engine: 4
g8c2_excl_ftrans dma_load_engine state S_START_LOADER->S_IDLE
g8c2_excl_ftrans dma_load_engine state S_START_DMA->S_IDLE
g8c2_excl_ftrans dma_load_engine state S_WAIT_DONE->S_IDLE
g8c2_excl_ftrans dma_load_engine state S_ABORT_RESET->S_IDLE

# dma_scratchpad_write_adapter: 1
g8c2_excl_ftrans dma_scratchpad_write_adapter state S_SEND_AW_W->S_WAIT_REQ

# dma_store_engine: 5
g8c2_excl_ftrans dma_store_engine state S_SEND_AR->S_IDLE
g8c2_excl_ftrans dma_store_engine state S_WAIT_R->S_DONE_PULSE
g8c2_excl_ftrans dma_store_engine state S_WAIT_R->S_IDLE
g8c2_excl_ftrans dma_store_engine state S_SEND_AW_W->S_IDLE
g8c2_excl_ftrans dma_store_engine state S_WAIT_B->S_IDLE
