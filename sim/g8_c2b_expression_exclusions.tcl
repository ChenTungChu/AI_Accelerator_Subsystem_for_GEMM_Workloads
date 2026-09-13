# ============================================================
# CODE-COV-C1.2-G8-C2-B
# Port0 Owner / CSR-Top Expression Physical Normalization
#
# Input:
#   coverage/code_cov/g8_c/code_cov_g8_c2a_multimetric_effective.ucdb
#
# Policy:
#   - Expression/FEC only.
#   - Exact zero rows only.
#   - No statement exclusions added here.
#   - No branch exclusions added here.
#   - No condition exclusions added here.
#   - No FSM exclusions added here.
#   - No toggle exclusions.
# ============================================================

if {![info exists G8C2B_DATASET]} {
    error {G8-C2-B requires G8C2B_DATASET to be defined by the wrapper.}
}

proc g8c2b_excl_expr_row {src line row} {
    global G8C2B_DATASET
    coverage exclude \
        -srcfile $src \
        -fecexprrow $line $row \
        -dataset $G8C2B_DATASET
}

# ------------------------------------------------------------
# scratchpad_port0_owner_mux.sv
# 6 G8-B-approved expression terms
# ------------------------------------------------------------

# Dual-owner / selection invariants.
g8c2b_excl_expr_row ../rtl/subsystem/scratchpad_port0_owner_mux.sv 109 2
g8c2b_excl_expr_row ../rtl/subsystem/scratchpad_port0_owner_mux.sv 109 4
g8c2b_excl_expr_row ../rtl/subsystem/scratchpad_port0_owner_mux.sv 111 4

# DMA-load WLAST producer contract (bimodal row).
g8c2b_excl_expr_row ../rtl/subsystem/scratchpad_port0_owner_mux.sv 175 3

# BRAM target-contract terms.
g8c2b_excl_expr_row ../rtl/subsystem/scratchpad_port0_owner_mux.sv 276 3
g8c2b_excl_expr_row ../rtl/subsystem/scratchpad_port0_owner_mux.sv 301 3

# ------------------------------------------------------------
# ai_accel_subsys_csr_top.sv
# 17 G8-B-approved expression terms
# ------------------------------------------------------------

g8c2b_excl_expr_row ../rtl/top/ai_accel_subsys_csr_top.sv 1110 6
g8c2b_excl_expr_row ../rtl/top/ai_accel_subsys_csr_top.sv 1250 6
g8c2b_excl_expr_row ../rtl/top/ai_accel_subsys_csr_top.sv 1253 3
g8c2b_excl_expr_row ../rtl/top/ai_accel_subsys_csr_top.sv 1259 3
g8c2b_excl_expr_row ../rtl/top/ai_accel_subsys_csr_top.sv 1262 3
g8c2b_excl_expr_row ../rtl/top/ai_accel_subsys_csr_top.sv 1290 8
g8c2b_excl_expr_row ../rtl/top/ai_accel_subsys_csr_top.sv 1290 9
g8c2b_excl_expr_row ../rtl/top/ai_accel_subsys_csr_top.sv 1296 5
g8c2b_excl_expr_row ../rtl/top/ai_accel_subsys_csr_top.sv 1932 4
g8c2b_excl_expr_row ../rtl/top/ai_accel_subsys_csr_top.sv 1932 7

# Bimodal FEC rows.
g8c2b_excl_expr_row ../rtl/top/ai_accel_subsys_csr_top.sv 1947 4
g8c2b_excl_expr_row ../rtl/top/ai_accel_subsys_csr_top.sv 1947 6
g8c2b_excl_expr_row ../rtl/top/ai_accel_subsys_csr_top.sv 1952 4
g8c2b_excl_expr_row ../rtl/top/ai_accel_subsys_csr_top.sv 1952 6

g8c2b_excl_expr_row ../rtl/top/ai_accel_subsys_csr_top.sv 2304 5
g8c2b_excl_expr_row ../rtl/top/ai_accel_subsys_csr_top.sv 2304 8
g8c2b_excl_expr_row ../rtl/top/ai_accel_subsys_csr_top.sv 2304 10
