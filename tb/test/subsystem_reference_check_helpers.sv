// File: tb/test/subsystem_reference_check_helpers.sv

// ============================================================
// Subsystem reference-check helpers
//
// Purpose:
// - Provide shared helper tasks for subsystem-level expected-result
//   generation and result comparison
// - Keep current non-UVM testbench flow simple
// - Serve as a future bridge toward scoreboard/reference-model reuse
//
// IMPORTANT:
// - This file assumes A_mat / B_mat / C_got / C_exp have already
//   been declared in the current scope before this file is included.
// ============================================================

// ------------------------------------------------------------
// Clear expected/got result buffers
// ------------------------------------------------------------
task automatic refchk_clear_result_buffers(
    input int total_slots
);
    int idx;
begin
    for (idx = 0; idx < total_slots; idx++) begin
        C_got[idx] = 0;
        C_exp[idx] = 0;
    end
end
endtask

// ------------------------------------------------------------
// Generic compact row-major GEMM reference model
//
// A layout:
//   A[m][k] -> A_mat[m * dim_k + k]
//
// B layout:
//   B[k][n] -> B_mat[k * dim_n + n]
//
// C layout:
//   C[m][n] -> C_exp[m * dim_n + n]
// ------------------------------------------------------------
task automatic refchk_compute_expected_c_compact(
    input int dim_m_local,
    input int dim_n_local,
    input int dim_k_local
);
    int signed acc;
    int m;
    int n;
    int kk;
    int idx;
begin
    for (idx = 0; idx < (dim_m_local * dim_n_local); idx++) begin
        C_exp[idx] = 0;
    end

    for (m = 0; m < dim_m_local; m++) begin
        for (n = 0; n < dim_n_local; n++) begin
            acc = 0;
            for (kk = 0; kk < dim_k_local; kk++) begin
                acc += $signed(A_mat[m * dim_k_local + kk]) *
                       $signed(B_mat[kk * dim_n_local + n]);
            end
            C_exp[m * dim_n_local + n] = acc;
        end
    end
end
endtask

// ------------------------------------------------------------
// Specialized helper for fixed 4x4 identity x known
//
// Current policy:
// - For A = identity(4x4), expected C = B directly
// ------------------------------------------------------------
task automatic refchk_compute_expected_identity_known_4x4();
    int idx;
begin
    for (idx = 0; idx < 16; idx++) begin
        C_exp[idx] = B_mat[idx];
    end
end
endtask

// ------------------------------------------------------------
// Generic compare for compact valid region
//
// Compares:
//   C_got[m * dim_n + n] vs C_exp[m * dim_n + n]
//
// label is only used for printing
// ------------------------------------------------------------
task automatic refchk_compare_compact_region(
    input int    dim_m_local,
    input int    dim_n_local,
    input string label
);
    int error_count;
    int flat_idx;
    int m;
    int n;
begin
    error_count = 0;

    for (m = 0; m < dim_m_local; m++) begin
        for (n = 0; n < dim_n_local; n++) begin
            flat_idx = m * dim_n_local + n;

            if (C_got[flat_idx] !== C_exp[flat_idx]) begin
                $display("[ERROR][%s] C[%0d,%0d] mismatch: got=%0d exp=%0d",
                         label, m, n, C_got[flat_idx], C_exp[flat_idx]);
                error_count++;
            end
            else begin
                $display("[OK][%s]    C[%0d,%0d] = %0d",
                         label, m, n, C_got[flat_idx]);
            end
        end
    end

    if (error_count == 0) begin
        $display("====================================================");
        $display("[INFO][%s] REFERENCE CHECK PASS", label);
        $display("====================================================");
    end
    else begin
        $display("====================================================");
        $display("[INFO][%s] REFERENCE CHECK FAIL, error_count=%0d",
                 label, error_count);
        $display("====================================================");
        $fatal(1);
    end
end
endtask

// ------------------------------------------------------------
// Generic compare for flat 1-D region of length total_elems
//
// Useful for existing fixed 4x4 baseline style comparisons
// ------------------------------------------------------------
task automatic refchk_compare_flat_region(
    input int    total_elems,
    input string label
);
    int error_count;
    int idx;
begin
    error_count = 0;

    for (idx = 0; idx < total_elems; idx++) begin
        if (C_got[idx] !== C_exp[idx]) begin
            $display("[ERROR][%s] C[%0d] mismatch: got=%0d exp=%0d",
                     label, idx, C_got[idx], C_exp[idx]);
            error_count++;
        end
        else begin
            $display("[OK][%s]    C[%0d] = %0d",
                     label, idx, C_got[idx]);
        end
    end

    if (error_count == 0) begin
        $display("====================================================");
        $display("[INFO][%s] REFERENCE CHECK PASS", label);
        $display("====================================================");
    end
    else begin
        $display("====================================================");
        $display("[INFO][%s] REFERENCE CHECK FAIL, error_count=%0d",
                 label, error_count);
        $display("====================================================");
        $fatal(1);
    end
end
endtask