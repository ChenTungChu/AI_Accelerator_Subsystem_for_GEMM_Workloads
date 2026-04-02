// File: tb/test/variable_dimension_smoke_test.sv

// ============================================================
// Variable-dimension smoke test
//
// Uses shared objects already declared elsewhere in tb_top flow:
// - A_mat / B_mat / C_got / C_exp
// - i / j / k
// - clear_all_arrays()
// - clear_c_region()
// - host_write_u8()
// - host_read_u32()
// - start_accel()
// - wait_done()
//
// CASE summary:
//   CASE=100 : 1x1x1
//   CASE=101 : 2x2x2
//   CASE=102 : 4x4x1
//   CASE=103 : 1x4x4
//   CASE=104 : 4x1x4
//   CASE=105 : 2x3x4
// ============================================================

int TEST_DIM_M;
int TEST_DIM_N;
int TEST_DIM_K;

// ============================================================
// Common helper
// ============================================================
task automatic set_test_dims(
    input int m,
    input int n,
    input int k_in
);
begin
    TEST_DIM_M = m;
    TEST_DIM_N = n;
    TEST_DIM_K = k_in;

    dim_m = m;
    dim_n = n;
    dim_k = k_in;
end
endtask

// ============================================================
// Case initialization
//
// IMPORTANT:
// Use compact row-major layout that matches DUT addressing:
//   A[m][k] -> A_mat[m * TEST_DIM_K + k]
//   B[k][n] -> B_mat[k * TEST_DIM_N + n]
// ============================================================

task automatic init_case_1x1x1();
begin
    clear_all_arrays();
    set_test_dims(1, 1, 1);

    // A = [3]
    A_mat[0] = 3;

    // B = [-2]
    B_mat[0] = -2;
end
endtask

task automatic init_case_2x2x2();
begin
    clear_all_arrays();
    set_test_dims(2, 2, 2);

    // A =
    // [1 2
    //  3 4]
    A_mat[0] = 1; A_mat[1] = 2;
    A_mat[2] = 3; A_mat[3] = 4;

    // B =
    // [5 6
    //  7 8]
    B_mat[0] = 5; B_mat[1] = 6;
    B_mat[2] = 7; B_mat[3] = 8;
end
endtask

task automatic init_case_4x4x1();
begin
    clear_all_arrays();
    set_test_dims(4, 4, 1);

    // A is 4x1
    // [ 1
    //   2
    //  -1
    //   3 ]
    A_mat[0] =  1;
    A_mat[1] =  2;
    A_mat[2] = -1;
    A_mat[3] =  3;

    // B is 1x4
    // [4 -2 1 3]
    B_mat[0] =  4;
    B_mat[1] = -2;
    B_mat[2] =  1;
    B_mat[3] =  3;
end
endtask

task automatic init_case_1x4x4();
begin
    clear_all_arrays();
    set_test_dims(1, 4, 4);

    // A is 1x4
    A_mat[0] =  1;
    A_mat[1] = -1;
    A_mat[2] =  2;
    A_mat[3] =  0;

    // B is 4x4 compact row-major
    B_mat[ 0] =  1; B_mat[ 1] =  2; B_mat[ 2] =  3; B_mat[ 3] =  4;
    B_mat[ 4] =  5; B_mat[ 5] =  6; B_mat[ 6] =  7; B_mat[ 7] =  8;
    B_mat[ 8] =  9; B_mat[ 9] = 10; B_mat[10] = 11; B_mat[11] = 12;
    B_mat[12] = 13; B_mat[13] = 14; B_mat[14] = 15; B_mat[15] = 16;
end
endtask

task automatic init_case_4x1x4();
begin
    clear_all_arrays();
    set_test_dims(4, 1, 4);

    // A is 4x4 compact row-major
    A_mat[ 0] =  1; A_mat[ 1] =  2; A_mat[ 2] =  3; A_mat[ 3] =  4;
    A_mat[ 4] =  5; A_mat[ 5] =  6; A_mat[ 6] =  7; A_mat[ 7] =  8;
    A_mat[ 8] =  9; A_mat[ 9] = 10; A_mat[10] = 11; A_mat[11] = 12;
    A_mat[12] = 13; A_mat[13] = 14; A_mat[14] = 15; A_mat[15] = 16;

    // B is 4x1 compact row-major
    B_mat[0] =  1;
    B_mat[1] = -1;
    B_mat[2] =  2;
    B_mat[3] =  0;
end
endtask

task automatic init_case_2x3x4();
begin
    clear_all_arrays();
    set_test_dims(2, 3, 4);

    // A is 2x4 compact row-major
    A_mat[0] =  1; A_mat[1] =  2; A_mat[2] =  3; A_mat[3] =  4;
    A_mat[4] = -1; A_mat[5] =  0; A_mat[6] =  2; A_mat[7] = -2;

    // B is 4x3 compact row-major
    B_mat[ 0] =  1; B_mat[ 1] =  2; B_mat[ 2] =  3;
    B_mat[ 3] =  4; B_mat[ 4] =  5; B_mat[ 5] =  6;
    B_mat[ 6] = -1; B_mat[ 7] =  0; B_mat[ 8] =  1;
    B_mat[ 9] =  2; B_mat[10] = -2; B_mat[11] =  1;
end
endtask

task automatic init_variable_test_vectors(input int case_id);
begin
    case (case_id)
        100: begin
            $display("[INFO] CASE 100: variable dim 1x1x1");
            init_case_1x1x1();
        end
        101: begin
            $display("[INFO] CASE 101: variable dim 2x2x2");
            init_case_2x2x2();
        end
        102: begin
            $display("[INFO] CASE 102: variable dim 4x4x1");
            init_case_4x4x1();
        end
        103: begin
            $display("[INFO] CASE 103: variable dim 1x4x4");
            init_case_1x4x4();
        end
        104: begin
            $display("[INFO] CASE 104: variable dim 4x1x4");
            init_case_4x1x4();
        end
        105: begin
            $display("[INFO] CASE 105: variable dim 2x3x4");
            init_case_2x3x4();
        end
        default: begin
            $display("[INFO] Unknown variable CASE=%0d, fallback to 100", case_id);
            init_case_1x1x1();
        end
    endcase
end
endtask

// ============================================================
// Reference model
// ============================================================
task automatic compute_expected_c_variable();
    int signed acc;
begin
    for (i = 0; i < TEST_DIM_M; i++) begin
        for (j = 0; j < TEST_DIM_N; j++) begin
            acc = 0;
            for (k = 0; k < TEST_DIM_K; k++) begin
                acc += $signed(A_mat[i*TEST_DIM_K + k]) *
                       $signed(B_mat[k*TEST_DIM_N + j]);
            end
            C_exp[i*TEST_DIM_N + j] = acc;
        end
    end
end
endtask

// ============================================================
// Memory preload / readback
//
// Preload the contiguous valid storage region only.
// Unused entries remain zero because clear_all_arrays() already ran.
// ============================================================
task automatic preload_variable_matrices();
    int a_elems;
    int b_elems;
begin
    a_elems = TEST_DIM_M * TEST_DIM_K;
    b_elems = TEST_DIM_K * TEST_DIM_N;

    for (i = 0; i < a_elems; i++) begin
        host_write_u8(BASE_A + i, A_mat[i]);
    end

    for (i = 0; i < b_elems; i++) begin
        host_write_u8(BASE_B + i, B_mat[i]);
    end
end
endtask

task automatic readback_variable_c_matrix();
    logic [31:0] tmp;
    int c_elems;
begin
    c_elems = TEST_DIM_M * TEST_DIM_N;

    for (i = 0; i < c_elems; i++) begin
        host_read_u32(BASE_C + (i * 4), tmp);
        C_got[i] = $signed(tmp);
    end
end
endtask

// ============================================================
// Compare only valid output region
// ============================================================
task automatic compare_variable_results(input int case_id);
    int error_count;
begin
    error_count = 0;

    for (i = 0; i < TEST_DIM_M; i++) begin
        for (j = 0; j < TEST_DIM_N; j++) begin
            if (C_got[i*TEST_DIM_N + j] !== C_exp[i*TEST_DIM_N + j]) begin
                $display("[ERROR] C[%0d,%0d] mismatch: got=%0d exp=%0d",
                         i, j, C_got[i*TEST_DIM_N + j], C_exp[i*TEST_DIM_N + j]);
                error_count++;
            end
            else begin
                $display("[OK]    C[%0d,%0d] = %0d",
                         i, j, C_got[i*TEST_DIM_N + j]);
            end
        end
    end

    if (error_count == 0) begin
        $display("====================================================");
        $display("VARIABLE-DIMENSION SMOKE PASS (CASE=%0d)", case_id);
        $display("====================================================");
    end
    else begin
        $display("====================================================");
        $display("VARIABLE-DIMENSION SMOKE FAIL (CASE=%0d), error_count=%0d",
                 case_id, error_count);
        $display("====================================================");
        $fatal(1);
    end
end
endtask

// ============================================================
// Test runner
// ============================================================
task automatic run_variable_dimension_smoke_test(input int case_id);
begin
    $display("[INFO] Init variable-dimension test vectors");
    init_variable_test_vectors(case_id);

    $display("[INFO] Compute expected C for variable-dimension case");
    compute_expected_c_variable();

    $display("[INFO] Clear C region");
    clear_c_region();

    $display("[INFO] Preload A/B to scratchpad through axi0_if");
    preload_variable_matrices();

    $display("[INFO] Start accelerator");
    start_accel();

    $display("[INFO] Wait acc_done");
    wait_done();

    repeat (5) @(posedge dma_clk);

    $display("[INFO] Read back C matrix");
    readback_variable_c_matrix();

    $display("[INFO] Compare results");
    compare_variable_results(case_id);
end
endtask