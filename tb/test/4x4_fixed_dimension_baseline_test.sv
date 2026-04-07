// File: tb/test/4x4_fixed_dimension_baseline_test.sv

// ============================================================
// Test data
// ============================================================
byte signed A_mat [0:15];
byte signed B_mat [0:15];
int  signed C_got [0:15];
int  signed C_exp [0:15];

integer i, j, k;

// ============================================================
// Common helpers
// ============================================================
task automatic clear_all_arrays();
begin
    for (i = 0; i < 16; i++) begin
        A_mat[i] = 0;
        B_mat[i] = 0;
        C_got[i] = 0;
        C_exp[i] = 0;
    end
end
endtask

task automatic clear_c_region();
begin
    for (i = 0; i < 16; i++) begin
        host_write_u32(BASE_C + (i * 4), 32'd0);
    end
end
endtask

// ============================================================
// CASE 0
// ============================================================
task automatic init_case_identity_known();
begin
    A_mat[ 0] = 1;  A_mat[ 1] = 0;  A_mat[ 2] = 0;  A_mat[ 3] = 0;
    A_mat[ 4] = 0;  A_mat[ 5] = 1;  A_mat[ 6] = 0;  A_mat[ 7] = 0;
    A_mat[ 8] = 0;  A_mat[ 9] = 0;  A_mat[10] = 1;  A_mat[11] = 0;
    A_mat[12] = 0;  A_mat[13] = 0;  A_mat[14] = 0;  A_mat[15] = 1;

    B_mat[ 0] =  1; B_mat[ 1] =  2; B_mat[ 2] =  3; B_mat[ 3] =  4;
    B_mat[ 4] =  5; B_mat[ 5] =  6; B_mat[ 6] =  7; B_mat[ 7] =  8;
    B_mat[ 8] =  9; B_mat[ 9] = 10; B_mat[10] = 11; B_mat[11] = 12;
    B_mat[12] = 13; B_mat[13] = 14; B_mat[14] = 15; B_mat[15] = 16;
end
endtask

// ============================================================
// CASE 1
// ============================================================
task automatic init_case_all_ones_known();
begin
    for (i = 0; i < 16; i++) begin
        A_mat[i] = 1;
    end

    B_mat[ 0] =  1; B_mat[ 1] =  2; B_mat[ 2] =  3; B_mat[ 3] =  4;
    B_mat[ 4] =  5; B_mat[ 5] =  6; B_mat[ 6] =  7; B_mat[ 7] =  8;
    B_mat[ 8] =  9; B_mat[ 9] = 10; B_mat[10] = 11; B_mat[11] = 12;
    B_mat[12] = 13; B_mat[13] = 14; B_mat[14] = 15; B_mat[15] = 16;
end
endtask

// ============================================================
// CASE 2
// ============================================================
task automatic init_case_signed_mixed();
begin
    A_mat[ 0] =  1; A_mat[ 1] = -1; A_mat[ 2] =  2; A_mat[ 3] =  0;
    A_mat[ 4] =  0; A_mat[ 5] =  3; A_mat[ 6] = -2; A_mat[ 7] =  1;
    A_mat[ 8] = -1; A_mat[ 9] =  0; A_mat[10] =  1; A_mat[11] =  2;
    A_mat[12] =  2; A_mat[13] =  1; A_mat[14] =  0; A_mat[15] = -1;

    B_mat[ 0] =  2; B_mat[ 1] =  1; B_mat[ 2] = -1; B_mat[ 3] =  0;
    B_mat[ 4] =  1; B_mat[ 5] = -2; B_mat[ 6] =  3; B_mat[ 7] =  1;
    B_mat[ 8] =  0; B_mat[ 9] =  4; B_mat[10] = -1; B_mat[11] =  2;
    B_mat[12] = -3; B_mat[13] =  1; B_mat[14] =  2; B_mat[15] = -2;
end
endtask

// ============================================================
// CASE 3
// ============================================================
task automatic init_case_zero_a_known();
begin
    for (i = 0; i < 16; i++) begin
        A_mat[i] = 0;
    end

    B_mat[ 0] =  1; B_mat[ 1] =  2; B_mat[ 2] =  3; B_mat[ 3] =  4;
    B_mat[ 4] =  5; B_mat[ 5] =  6; B_mat[ 6] =  7; B_mat[ 7] =  8;
    B_mat[ 8] =  9; B_mat[ 9] = 10; B_mat[10] = 11; B_mat[11] = 12;
    B_mat[12] = 13; B_mat[13] = 14; B_mat[14] = 15; B_mat[15] = 16;
end
endtask

// ============================================================
// CASE 4
// ============================================================
task automatic init_case_known_b_identity();
begin
    A_mat[ 0] =  1; A_mat[ 1] =  2; A_mat[ 2] =  3; A_mat[ 3] =  4;
    A_mat[ 4] =  5; A_mat[ 5] =  6; A_mat[ 6] =  7; A_mat[ 7] =  8;
    A_mat[ 8] =  9; A_mat[ 9] = 10; A_mat[10] = 11; A_mat[11] = 12;
    A_mat[12] = 13; A_mat[13] = 14; A_mat[14] = 15; A_mat[15] = 16;

    B_mat[ 0] = 1;  B_mat[ 1] = 0;  B_mat[ 2] = 0;  B_mat[ 3] = 0;
    B_mat[ 4] = 0;  B_mat[ 5] = 1;  B_mat[ 6] = 0;  B_mat[ 7] = 0;
    B_mat[ 8] = 0;  B_mat[ 9] = 0;  B_mat[10] = 1;  B_mat[11] = 0;
    B_mat[12] = 0;  B_mat[13] = 0;  B_mat[14] = 0;  B_mat[15] = 1;
end
endtask

// ============================================================
// CASE 5
// ============================================================
task automatic init_case_diagonal_diagonal();
begin
    A_mat[ 0] =  2; A_mat[ 1] =  0; A_mat[ 2] =  0; A_mat[ 3] =  0;
    A_mat[ 4] =  0; A_mat[ 5] = -3; A_mat[ 6] =  0; A_mat[ 7] =  0;
    A_mat[ 8] =  0; A_mat[ 9] =  0; A_mat[10] =  4; A_mat[11] =  0;
    A_mat[12] =  0; A_mat[13] =  0; A_mat[14] =  0; A_mat[15] = -5;

    B_mat[ 0] =  6; B_mat[ 1] =  0; B_mat[ 2] =  0; B_mat[ 3] =  0;
    B_mat[ 4] =  0; B_mat[ 5] =  7; B_mat[ 6] =  0; B_mat[ 7] =  0;
    B_mat[ 8] =  0; B_mat[ 9] =  0; B_mat[10] = -2; B_mat[11] =  0;
    B_mat[12] =  0; B_mat[13] =  0; B_mat[14] =  0; B_mat[15] =  3;
end
endtask

// ============================================================
// CASE 6
// ============================================================
task automatic init_case_sparse_checkerboard();
begin
    A_mat[ 0] =  1; A_mat[ 1] =  0; A_mat[ 2] = -1; A_mat[ 3] =  0;
    A_mat[ 4] =  0; A_mat[ 5] =  2; A_mat[ 6] =  0; A_mat[ 7] = -2;
    A_mat[ 8] =  3; A_mat[ 9] =  0; A_mat[10] =  0; A_mat[11] = -3;
    A_mat[12] =  0; A_mat[13] = -4; A_mat[14] =  4; A_mat[15] =  0;

    B_mat[ 0] =  0; B_mat[ 1] =  1; B_mat[ 2] =  0; B_mat[ 3] = -1;
    B_mat[ 4] =  2; B_mat[ 5] =  0; B_mat[ 6] = -2; B_mat[ 7] =  0;
    B_mat[ 8] =  0; B_mat[ 9] =  3; B_mat[10] =  0; B_mat[11] = -3;
    B_mat[12] = -4; B_mat[13] =  0; B_mat[14] =  4; B_mat[15] =  0;
end
endtask

// ============================================================
// CASE 7
// ============================================================
task automatic init_case_larger_signed_safe();
begin
    A_mat[ 0] =  7; A_mat[ 1] = -6; A_mat[ 2] =  5; A_mat[ 3] = -4;
    A_mat[ 4] = -3; A_mat[ 5] =  2; A_mat[ 6] = -1; A_mat[ 7] =  0;
    A_mat[ 8] =  1; A_mat[ 9] = -2; A_mat[10] =  3; A_mat[11] = -4;
    A_mat[12] =  5; A_mat[13] = -6; A_mat[14] =  7; A_mat[15] = -8;

    B_mat[ 0] = -1; B_mat[ 1] =  2; B_mat[ 2] = -3; B_mat[ 3] =  4;
    B_mat[ 4] =  5; B_mat[ 5] = -6; B_mat[ 6] =  7; B_mat[ 7] = -8;
    B_mat[ 8] =  8; B_mat[ 9] = -7; B_mat[10] =  6; B_mat[11] = -5;
    B_mat[12] = -4; B_mat[13] =  3; B_mat[14] = -2; B_mat[15] =  1;
end
endtask

task automatic init_test_vectors(input int case_id);
begin
    clear_all_arrays();

    case (case_id)
        0: begin
            $display("[INFO] CASE 0: identity x known");
            init_case_identity_known();
        end
        1: begin
            $display("[INFO] CASE 1: all-ones x known");
            init_case_all_ones_known();
        end
        2: begin
            $display("[INFO] CASE 2: signed mixed");
            init_case_signed_mixed();
        end
        3: begin
            $display("[INFO] CASE 3: zero A x known");
            init_case_zero_a_known();
        end
        4: begin
            $display("[INFO] CASE 4: known x identity");
            init_case_known_b_identity();
        end
        5: begin
            $display("[INFO] CASE 5: diagonal x diagonal");
            init_case_diagonal_diagonal();
        end
        6: begin
            $display("[INFO] CASE 6: sparse / checkerboard-like");
            init_case_sparse_checkerboard();
        end
        7: begin
            $display("[INFO] CASE 7: larger signed magnitude (safe range)");
            init_case_larger_signed_safe();
        end
        default: begin
            $display("[INFO] Unknown CASE=%0d, fallback to CASE 0", case_id);
            init_case_identity_known();
        end
    endcase
end
endtask

task automatic preload_matrices();
begin
    for (i = 0; i < 16; i++) begin
        host_write_u8(BASE_A + i, A_mat[i]);
        host_write_u8(BASE_B + i, B_mat[i]);
    end
end
endtask

task automatic readback_c_matrix();
    logic [31:0] tmp;
begin
    for (i = 0; i < 16; i++) begin
        C_got[i] = 0;
    end

    for (i = 0; i < 16; i++) begin
        host_read_u32(BASE_C + (i * 4), tmp);
        C_got[i] = $signed(tmp);
    end
end
endtask

task automatic run_4x4_fixed_dimension_baseline_test(input int case_id);
begin
    $display("[INFO] Init test vectors");
    init_test_vectors(case_id);

    $display("[INFO] Compute expected C");
    if (case_id == 0) begin
        refchk_compute_expected_identity_known_4x4();
    end
    else begin
        refchk_compute_expected_c_compact(4, 4, 4);
    end

    $display("[INFO] Clear C region");
    clear_c_region();

    $display("[INFO] Preload A/B to scratchpad through axi0_if");
    preload_matrices();

    $display("[INFO] Start accelerator");
    start_accel();

    $display("[INFO] Wait acc_done");
    wait_done();

    repeat (5) @(posedge dma_clk);

    $display("[INFO] Read back C matrix");
    readback_c_matrix();

    $display("[INFO] Compare results");
    refchk_compare_flat_region(
        16,
        $sformatf("fixed_baseline_case_%0d", case_id)
    );
end
endtask