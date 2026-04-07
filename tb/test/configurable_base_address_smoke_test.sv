// File: tb/test/configurable_base_address_smoke_test.sv

// ============================================================
// Configurable base address smoke test
//
// Purpose:
// - Verify base_addr_a / base_addr_b / base_addr_c are truly functional
// - Verify preload, GEMM read path, C writeback, and readback all follow
//   the configured base address map
//
// Uses shared objects already declared elsewhere in tb_top flow:
// - A_mat / B_mat / C_got / C_exp
// - i / j / k
// - clear_all_arrays()
// - host_write_u8()
// - host_write_u32()
// - host_read_u32()
// - start_accel()
// - wait_done()
//
// Also uses shared reference-check helpers from:
// - subsystem_reference_check_helpers.sv
//
// CASE summary:
//   CASE=400 : baseline map
//   CASE=401 : shifted map #1
//   CASE=402 : shifted map #2
//   CASE=403 : tighter but non-overlapping map
// ============================================================

// ============================================================
// Common helpers
// ============================================================
task automatic set_base_addr_map(
    input logic [ADDR_WIDTH-1:0] a_base,
    input logic [ADDR_WIDTH-1:0] b_base,
    input logic [ADDR_WIDTH-1:0] c_base
);
begin
    base_addr_a = a_base;
    base_addr_b = b_base;
    base_addr_c = c_base;
end
endtask

task automatic init_identity_known_matrices();
begin
    clear_all_arrays();

    // A = identity(4x4)
    A_mat[ 0] = 1;  A_mat[ 1] = 0;  A_mat[ 2] = 0;  A_mat[ 3] = 0;
    A_mat[ 4] = 0;  A_mat[ 5] = 1;  A_mat[ 6] = 0;  A_mat[ 7] = 0;
    A_mat[ 8] = 0;  A_mat[ 9] = 0;  A_mat[10] = 1;  A_mat[11] = 0;
    A_mat[12] = 0;  A_mat[13] = 0;  A_mat[14] = 0;  A_mat[15] = 1;

    // B = known matrix
    B_mat[ 0] =  1; B_mat[ 1] =  2; B_mat[ 2] =  3; B_mat[ 3] =  4;
    B_mat[ 4] =  5; B_mat[ 5] =  6; B_mat[ 6] =  7; B_mat[ 7] =  8;
    B_mat[ 8] =  9; B_mat[ 9] = 10; B_mat[10] = 11; B_mat[11] = 12;
    B_mat[12] = 13; B_mat[13] = 14; B_mat[14] = 15; B_mat[15] = 16;
end
endtask

task automatic clear_c_region_at_current_base();
begin
    for (i = 0; i < 16; i++) begin
        host_write_u32(base_addr_c + (i * 4), 32'd0);
    end
end
endtask

task automatic preload_matrices_at_current_base();
begin
    for (i = 0; i < 16; i++) begin
        host_write_u8(base_addr_a + i, A_mat[i]);
        host_write_u8(base_addr_b + i, B_mat[i]);
    end
end
endtask

task automatic readback_c_matrix_at_current_base();
    logic [31:0] tmp;
begin
    for (i = 0; i < 16; i++) begin
        C_got[i] = 0;
    end

    for (i = 0; i < 16; i++) begin
        host_read_u32(base_addr_c + (i * 4), tmp);
        C_got[i] = $signed(tmp);
    end
end
endtask

// ============================================================
// Case setup
// ============================================================
task automatic init_configurable_base_case(input int case_id);
begin
    init_identity_known_matrices();
    refchk_compute_expected_identity_known_4x4();

    case (case_id)
        400: begin
            $display("[INFO] CASE 400: baseline base map");
            set_base_addr_map(32'h0000, 32'h0100, 32'h0200);
        end

        401: begin
            $display("[INFO] CASE 401: shifted base map #1");
            set_base_addr_map(32'h0040, 32'h0140, 32'h0240);
        end

        402: begin
            $display("[INFO] CASE 402: shifted base map #2");
            set_base_addr_map(32'h0080, 32'h0180, 32'h0280);
        end

        403: begin
            $display("[INFO] CASE 403: tighter non-overlapping base map");
            set_base_addr_map(32'h0020, 32'h0060, 32'h00A0);
        end

        default: begin
            $display("[INFO] Unknown configurable-base CASE=%0d, fallback to 400", case_id);
            set_base_addr_map(32'h0000, 32'h0100, 32'h0200);
        end
    endcase
end
endtask

// ============================================================
// Test runner
// ============================================================
task automatic run_configurable_base_address_smoke_test(input int case_id);
begin
    $display("[INFO] Init configurable-base test vectors and base map");
    init_configurable_base_case(case_id);

    $display("[INFO] Current base map: A=0x%08h B=0x%08h C=0x%08h",
             base_addr_a, base_addr_b, base_addr_c);

    $display("[INFO] Clear C region at current base");
    clear_c_region_at_current_base();

    $display("[INFO] Preload A/B to scratchpad through axi0_if at current base");
    preload_matrices_at_current_base();

    $display("[INFO] Start accelerator");
    start_accel();

    $display("[INFO] Wait acc_done");
    wait_done();

    repeat (5) @(posedge dma_clk);

    $display("[INFO] Read back C matrix at current base");
    readback_c_matrix_at_current_base();

    $display("[INFO] Compare results");
    refchk_compare_flat_region(
        16,
        $sformatf("config_base_case_%0d", case_id)
    );
end
endtask