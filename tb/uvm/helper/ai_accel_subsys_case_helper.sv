// File: tb/uvm/helper/ai_accel_subsys_case_helper.sv
`ifndef AI_ACCEL_SUBSYS_CASE_HELPER_SV
`define AI_ACCEL_SUBSYS_CASE_HELPER_SV

class ai_accel_subsys_case_helper extends uvm_object;
    `uvm_object_utils(ai_accel_subsys_case_helper)

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_case_helper");
        super.new(name);
    endfunction

    // ------------------------------------------------------------
    // Build canonical case profile by reusing seq_item helpers
    // ------------------------------------------------------------
    function ai_accel_subsys_seq_item build_case_profile(
        input int unsigned case_id,
        input ai_accel_subsys_seq_item::test_kind_e test_kind
    );
        ai_accel_subsys_seq_item item;

        item = ai_accel_subsys_seq_item::type_id::create("item");

        case (test_kind)
            ai_accel_subsys_seq_item::TEST_KIND_FIXED_BASELINE:
                item.apply_fixed_baseline_case(case_id);

            ai_accel_subsys_seq_item::TEST_KIND_VARIABLE_DIM_SMOKE:
                item.apply_variable_dim_case(case_id);

            ai_accel_subsys_seq_item::TEST_KIND_CONFIGURABLE_BASE:
                item.apply_configurable_base_case(case_id);

            ai_accel_subsys_seq_item::TEST_KIND_C_RMW_ACCUM_RECIPE:
                item.apply_c_rmw_accum_recipe_case(case_id);

            default: begin
                `uvm_fatal("CASE_HELPER/BAD_KIND",
                    $sformatf("Unsupported test_kind=%0d for case_id=%0d",
                        test_kind, case_id))
            end
        endcase

        return item;
    endfunction

    // ------------------------------------------------------------
    // Utility: clear dynamic vector
    // ------------------------------------------------------------
    task automatic zero_vector(ref int signed vec[]);
        int unsigned i;
    begin
        for (i = 0; i < vec.size(); i++) begin
            vec[i] = 0;
        end
    end
    endtask

    // ------------------------------------------------------------
    // Generic compact row-major GEMM reference model
    //
    // A layout:
    //   A[m][k] -> a_flat[m * dim_k + k]
    //
    // B layout:
    //   B[k][n] -> b_flat[kk * dim_n + n]
    //
    // C layout:
    //   C[m][n] -> c_exp[m * dim_n + n]
    // ------------------------------------------------------------
    task automatic compute_expected_c_compact(
        input  int signed   a_flat[],
        input  int signed   b_flat[],
        input  int unsigned dim_m,
        input  int unsigned dim_n,
        input  int unsigned dim_k,
        output int signed   c_exp[]
    );
        int signed   acc;
        int unsigned m;
        int unsigned n;
        int unsigned kk;
        int unsigned total_c;
    begin
        total_c = dim_m * dim_n;
        c_exp   = new[total_c];

        for (m = 0; m < dim_m; m++) begin
            for (n = 0; n < dim_n; n++) begin
                acc = 0;
                for (kk = 0; kk < dim_k; kk++) begin
                    acc += a_flat[m * dim_k + kk] *
                           b_flat[kk * dim_n + n];
                end
                c_exp[m * dim_n + n] = acc;
            end
        end
    end
    endtask

    // ------------------------------------------------------------
    // Specialized helper for fixed CASE 0:
    // identity(4x4) x known(4x4) => expected C = B directly
    // ------------------------------------------------------------
    task automatic compute_expected_identity_known_4x4(
        input  int signed b_flat[],
        output int signed c_exp[]
    );
        int unsigned i;
    begin
        c_exp = new[16];
        for (i = 0; i < 16; i++) begin
            c_exp[i] = b_flat[i];
        end
    end
    endtask

    // ------------------------------------------------------------
    // Build fixed-baseline payload:
    //   - canonical profile item
    //   - A_flat
    //   - B_flat
    //   - expected_c
    // ------------------------------------------------------------
    task automatic build_fixed_case_payload(
        input  int unsigned              case_id,
        output ai_accel_subsys_seq_item  profile_item,
        output int signed                a_flat[],
        output int signed                b_flat[],
        output int signed                expected_c[]
    );
    begin
        profile_item = build_case_profile(
            case_id,
            ai_accel_subsys_seq_item::TEST_KIND_FIXED_BASELINE
        );

        a_flat = new[16];
        b_flat = new[16];

        zero_vector(a_flat);
        zero_vector(b_flat);

        case (case_id)
            0: begin
                // A = identity
                a_flat[ 0] = 1;  a_flat[ 1] = 0;  a_flat[ 2] = 0;  a_flat[ 3] = 0;
                a_flat[ 4] = 0;  a_flat[ 5] = 1;  a_flat[ 6] = 0;  a_flat[ 7] = 0;
                a_flat[ 8] = 0;  a_flat[ 9] = 0;  a_flat[10] = 1;  a_flat[11] = 0;
                a_flat[12] = 0;  a_flat[13] = 0;  a_flat[14] = 0;  a_flat[15] = 1;

                b_flat[ 0] =  1; b_flat[ 1] =  2; b_flat[ 2] =  3; b_flat[ 3] =  4;
                b_flat[ 4] =  5; b_flat[ 5] =  6; b_flat[ 6] =  7; b_flat[ 7] =  8;
                b_flat[ 8] =  9; b_flat[ 9] = 10; b_flat[10] = 11; b_flat[11] = 12;
                b_flat[12] = 13; b_flat[13] = 14; b_flat[14] = 15; b_flat[15] = 16;
            end

            1: begin
                for (int i = 0; i < 16; i++) begin
                    a_flat[i] = 1;
                end

                b_flat[ 0] =  1; b_flat[ 1] =  2; b_flat[ 2] =  3; b_flat[ 3] =  4;
                b_flat[ 4] =  5; b_flat[ 5] =  6; b_flat[ 6] =  7; b_flat[ 7] =  8;
                b_flat[ 8] =  9; b_flat[ 9] = 10; b_flat[10] = 11; b_flat[11] = 12;
                b_flat[12] = 13; b_flat[13] = 14; b_flat[14] = 15; b_flat[15] = 16;
            end

            2: begin
                a_flat[ 0] =  1; a_flat[ 1] = -1; a_flat[ 2] =  2; a_flat[ 3] =  0;
                a_flat[ 4] =  0; a_flat[ 5] =  3; a_flat[ 6] = -2; a_flat[ 7] =  1;
                a_flat[ 8] = -1; a_flat[ 9] =  0; a_flat[10] =  1; a_flat[11] =  2;
                a_flat[12] =  2; a_flat[13] =  1; a_flat[14] =  0; a_flat[15] = -1;

                b_flat[ 0] =  2; b_flat[ 1] =  1; b_flat[ 2] = -1; b_flat[ 3] =  0;
                b_flat[ 4] =  1; b_flat[ 5] = -2; b_flat[ 6] =  3; b_flat[ 7] =  1;
                b_flat[ 8] =  0; b_flat[ 9] =  4; b_flat[10] = -1; b_flat[11] =  2;
                b_flat[12] = -3; b_flat[13] =  1; b_flat[14] =  2; b_flat[15] = -2;
            end

            3: begin
                for (int i = 0; i < 16; i++) begin
                    a_flat[i] = 0;
                end

                b_flat[ 0] =  1; b_flat[ 1] =  2; b_flat[ 2] =  3; b_flat[ 3] =  4;
                b_flat[ 4] =  5; b_flat[ 5] =  6; b_flat[ 6] =  7; b_flat[ 7] =  8;
                b_flat[ 8] =  9; b_flat[ 9] = 10; b_flat[10] = 11; b_flat[11] = 12;
                b_flat[12] = 13; b_flat[13] = 14; b_flat[14] = 15; b_flat[15] = 16;
            end

            4: begin
                a_flat[ 0] =  1; a_flat[ 1] =  2; a_flat[ 2] =  3; a_flat[ 3] =  4;
                a_flat[ 4] =  5; a_flat[ 5] =  6; a_flat[ 6] =  7; a_flat[ 7] =  8;
                a_flat[ 8] =  9; a_flat[ 9] = 10; a_flat[10] = 11; a_flat[11] = 12;
                a_flat[12] = 13; a_flat[13] = 14; a_flat[14] = 15; a_flat[15] = 16;

                b_flat[ 0] = 1;  b_flat[ 1] = 0;  b_flat[ 2] = 0;  b_flat[ 3] = 0;
                b_flat[ 4] = 0;  b_flat[ 5] = 1;  b_flat[ 6] = 0;  b_flat[ 7] = 0;
                b_flat[ 8] = 0;  b_flat[ 9] = 0;  b_flat[10] = 1;  b_flat[11] = 0;
                b_flat[12] = 0;  b_flat[13] = 0;  b_flat[14] = 0;  b_flat[15] = 1;
            end

            5: begin
                a_flat[ 0] =  2; a_flat[ 1] =  0; a_flat[ 2] =  0; a_flat[ 3] =  0;
                a_flat[ 4] =  0; a_flat[ 5] = -3; a_flat[ 6] =  0; a_flat[ 7] =  0;
                a_flat[ 8] =  0; a_flat[ 9] =  0; a_flat[10] =  4; a_flat[11] =  0;
                a_flat[12] =  0; a_flat[13] =  0; a_flat[14] =  0; a_flat[15] = -5;

                b_flat[ 0] =  6; b_flat[ 1] =  0; b_flat[ 2] =  0; b_flat[ 3] =  0;
                b_flat[ 4] =  0; b_flat[ 5] =  7; b_flat[ 6] =  0; b_flat[ 7] =  0;
                b_flat[ 8] =  0; b_flat[ 9] =  0; b_flat[10] = -2; b_flat[11] =  0;
                b_flat[12] =  0; b_flat[13] =  0; b_flat[14] =  0; b_flat[15] =  3;
            end

            6: begin
                a_flat[ 0] =  1; a_flat[ 1] =  0; a_flat[ 2] = -1; a_flat[ 3] =  0;
                a_flat[ 4] =  0; a_flat[ 5] =  2; a_flat[ 6] =  0; a_flat[ 7] = -2;
                a_flat[ 8] =  3; a_flat[ 9] =  0; a_flat[10] =  0; a_flat[11] = -3;
                a_flat[12] =  0; a_flat[13] = -4; a_flat[14] =  4; a_flat[15] =  0;

                b_flat[ 0] =  0; b_flat[ 1] =  1; b_flat[ 2] =  0; b_flat[ 3] = -1;
                b_flat[ 4] =  2; b_flat[ 5] =  0; b_flat[ 6] = -2; b_flat[ 7] =  0;
                b_flat[ 8] =  0; b_flat[ 9] =  3; b_flat[10] =  0; b_flat[11] = -3;
                b_flat[12] = -4; b_flat[13] =  0; b_flat[14] =  4; b_flat[15] =  0;
            end

            7: begin
                a_flat[ 0] =  7; a_flat[ 1] = -6; a_flat[ 2] =  5; a_flat[ 3] = -4;
                a_flat[ 4] = -3; a_flat[ 5] =  2; a_flat[ 6] = -1; a_flat[ 7] =  0;
                a_flat[ 8] =  1; a_flat[ 9] = -2; a_flat[10] =  3; a_flat[11] = -4;
                a_flat[12] =  5; a_flat[13] = -6; a_flat[14] =  7; a_flat[15] = -8;

                b_flat[ 0] = -1; b_flat[ 1] =  2; b_flat[ 2] = -3; b_flat[ 3] =  4;
                b_flat[ 4] =  5; b_flat[ 5] = -6; b_flat[ 6] =  7; b_flat[ 7] = -8;
                b_flat[ 8] =  8; b_flat[ 9] = -7; b_flat[10] =  6; b_flat[11] = -5;
                b_flat[12] = -4; b_flat[13] =  3; b_flat[14] = -2; b_flat[15] =  1;
            end

            default: begin
                `uvm_fatal("CASE_HELPER/FIXED_BAD_CASE",
                    $sformatf("Unsupported fixed-baseline case_id=%0d", case_id))
            end
        endcase

        if (case_id == 0) begin
            compute_expected_identity_known_4x4(b_flat, expected_c);
        end
        else begin
            compute_expected_c_compact(a_flat, b_flat, 4, 4, 4, expected_c);
        end
    end
    endtask

    // ------------------------------------------------------------
    // Build variable-dimension payload:
    //   - canonical profile item
    //   - A_flat
    //   - B_flat
    //   - expected_c
    //
    // This is the first useful extraction from the legacy non-UVM
    // variable_dimension_smoke_test.sv
    // ------------------------------------------------------------
    task automatic build_variable_case_payload(
        input  int unsigned              case_id,
        output ai_accel_subsys_seq_item  profile_item,
        output int signed                a_flat[],
        output int signed                b_flat[],
        output int signed                expected_c[]
    );
        int unsigned a_elems;
        int unsigned b_elems;
        int unsigned m;
        int unsigned n;
        int unsigned kk;
        int signed   val;
    begin
        profile_item = build_case_profile(
            case_id,
            ai_accel_subsys_seq_item::TEST_KIND_VARIABLE_DIM_SMOKE
        );

        a_elems = profile_item.dim_m * profile_item.dim_k;
        b_elems = profile_item.dim_k * profile_item.dim_n;

        a_flat = new[a_elems];
        b_flat = new[b_elems];

        zero_vector(a_flat);
        zero_vector(b_flat);

        case (case_id)
            100: begin
                // A = [3]
                a_flat[0] =  3;

                // B = [-2]
                b_flat[0] = -2;
            end

            101: begin
                // A =
                // [1 2
                //  3 4]
                a_flat[0] = 1; a_flat[1] = 2;
                a_flat[2] = 3; a_flat[3] = 4;

                // B =
                // [5 6
                //  7 8]
                b_flat[0] = 5; b_flat[1] = 6;
                b_flat[2] = 7; b_flat[3] = 8;
            end

            102: begin
                // A is 4x1
                a_flat[0] =  1;
                a_flat[1] =  2;
                a_flat[2] = -1;
                a_flat[3] =  3;

                // B is 1x4
                b_flat[0] =  4;
                b_flat[1] = -2;
                b_flat[2] =  1;
                b_flat[3] =  3;
            end

            103: begin
                // A is 1x4
                a_flat[0] =  1;
                a_flat[1] = -1;
                a_flat[2] =  2;
                a_flat[3] =  0;

                // B is 4x4 compact row-major
                b_flat[ 0] =  1; b_flat[ 1] =  2; b_flat[ 2] =  3; b_flat[ 3] =  4;
                b_flat[ 4] =  5; b_flat[ 5] =  6; b_flat[ 6] =  7; b_flat[ 7] =  8;
                b_flat[ 8] =  9; b_flat[ 9] = 10; b_flat[10] = 11; b_flat[11] = 12;
                b_flat[12] = 13; b_flat[13] = 14; b_flat[14] = 15; b_flat[15] = 16;
            end

            104: begin
                // A is 4x4 compact row-major
                a_flat[ 0] =  1; a_flat[ 1] =  2; a_flat[ 2] =  3; a_flat[ 3] =  4;
                a_flat[ 4] =  5; a_flat[ 5] =  6; a_flat[ 6] =  7; a_flat[ 7] =  8;
                a_flat[ 8] =  9; a_flat[ 9] = 10; a_flat[10] = 11; a_flat[11] = 12;
                a_flat[12] = 13; a_flat[13] = 14; a_flat[14] = 15; a_flat[15] = 16;

                // B is 4x1 compact row-major
                b_flat[0] =  1;
                b_flat[1] = -1;
                b_flat[2] =  2;
                b_flat[3] =  0;
            end

            105: begin
                // A is 2x4 compact row-major
                a_flat[0] =  1; a_flat[1] =  2; a_flat[2] =  3; a_flat[3] =  4;
                a_flat[4] = -1; a_flat[5] =  0; a_flat[6] =  2; a_flat[7] = -2;

                // B is 4x3 compact row-major
                b_flat[ 0] =  1; b_flat[ 1] =  2; b_flat[ 2] =  3;
                b_flat[ 3] =  4; b_flat[ 4] =  5; b_flat[ 5] =  6;
                b_flat[ 6] = -1; b_flat[ 7] =  0; b_flat[ 8] =  1;
                b_flat[ 9] =  2; b_flat[10] = -2; b_flat[11] =  1;
            end

            190: begin
                // P9F large-dimension case: M=1, N=8, K=8.
                // Purpose:
                //   - fills one 8-element A row
                //   - exercises an 8x8 B tile
                //   - keeps C output small enough for a fast focused run
                for (kk = 0; kk < profile_item.dim_k; kk++) begin
                    if ((kk % 2) == 0)
                        a_flat[kk] = int'(kk + 1);
                    else
                        a_flat[kk] = -int'(kk + 1);
                end

                for (kk = 0; kk < profile_item.dim_k; kk++) begin
                    for (n = 0; n < profile_item.dim_n; n++) begin
                        val = int'(((kk * 3) + (n * 2)) % 7) - 3;
                        if (val == 0)
                            val = 1;
                        b_flat[kk * profile_item.dim_n + n] = val;
                    end
                end
            end

            191: begin
                // P9F large-dimension case: M=2, N=8, K=8.
                // Purpose:
                //   - exercises two A rows with K=8
                //   - reuses the same 8x8 B tile across multiple output rows
                for (m = 0; m < profile_item.dim_m; m++) begin
                    for (kk = 0; kk < profile_item.dim_k; kk++) begin
                        val = int'(((m + 1) * (kk + 2)) % 9) - 4;
                        if (val == 0)
                            val = int'(m + 1);
                        a_flat[m * profile_item.dim_k + kk] = val;
                    end
                end

                for (kk = 0; kk < profile_item.dim_k; kk++) begin
                    for (n = 0; n < profile_item.dim_n; n++) begin
                        val = int'(((kk + 2) * (n + 1)) % 11) - 5;
                        if (val == 0)
                            val = -1;
                        b_flat[kk * profile_item.dim_n + n] = val;
                    end
                end
            end

            192: begin
                // P9F large/tail-dimension case: M=3, N=5, K=7.
                // Purpose:
                //   - N and K are not multiples of 4
                //   - stresses lane-tail behavior while still fitting within
                //     B-cache max K/N=8 and A-row max K=8
                for (m = 0; m < profile_item.dim_m; m++) begin
                    for (kk = 0; kk < profile_item.dim_k; kk++) begin
                        val = int'(((m + 2) * (kk + 1)) % 7) - 3;
                        if (val == 0)
                            val = 2;
                        a_flat[m * profile_item.dim_k + kk] = val;
                    end
                end

                for (kk = 0; kk < profile_item.dim_k; kk++) begin
                    for (n = 0; n < profile_item.dim_n; n++) begin
                        val = int'(((kk + 1) * (n + 3)) % 9) - 4;
                        if (val == 0)
                            val = -2;
                        b_flat[kk * profile_item.dim_n + n] = val;
                    end
                end
            end

            193: begin
                // P10C K>8 case: M=1, N=4, K=16.
                // Purpose:
                //   - first two-tile K=16 software-reference case
                //   - one A row, four C outputs, compact B footprint
                //   - expected_mac = 64, expected_output = 4
                for (kk = 0; kk < profile_item.dim_k; kk++) begin
                    val = int'(((kk + 1) * 3) % 13) - 6;
                    if (val == 0)
                        val = 3;
                    a_flat[kk] = val;
                end

                for (kk = 0; kk < profile_item.dim_k; kk++) begin
                    for (n = 0; n < profile_item.dim_n; n++) begin
                        val = int'(((kk + 2) * (n + 1)) % 17) - 8;
                        if (val == 0)
                            val = -3;
                        b_flat[kk * profile_item.dim_n + n] = val;
                    end
                end
            end

            194: begin
                // P10C K>8 case: M=2, N=4, K=16.
                // Purpose:
                //   - two A rows across two K=8-sized logical tiles
                //   - expected_mac = 128, expected_output = 8
                for (m = 0; m < profile_item.dim_m; m++) begin
                    for (kk = 0; kk < profile_item.dim_k; kk++) begin
                        val = int'(((m + 1) * (kk + 3)) % 15) - 7;
                        if (val == 0)
                            val = int'(m + 2);
                        a_flat[m * profile_item.dim_k + kk] = val;
                    end
                end

                for (kk = 0; kk < profile_item.dim_k; kk++) begin
                    for (n = 0; n < profile_item.dim_n; n++) begin
                        val = int'(((kk + 1) * (n + 2)) % 19) - 9;
                        if (val == 0)
                            val = 4;
                        b_flat[kk * profile_item.dim_n + n] = val;
                    end
                end
            end

            195: begin
                // P10C representative K>8 case: M=4, N=4, K=16.
                // Purpose:
                //   - balanced 4x4 output shape with K=16
                //   - natural future P10 regression candidate
                //   - expected_mac = 256, expected_output = 16
                for (m = 0; m < profile_item.dim_m; m++) begin
                    for (kk = 0; kk < profile_item.dim_k; kk++) begin
                        val = int'(((m + 2) * (kk + 5)) % 17) - 8;
                        if (val == 0)
                            val = -int'(m + 1);
                        a_flat[m * profile_item.dim_k + kk] = val;
                    end
                end

                for (kk = 0; kk < profile_item.dim_k; kk++) begin
                    for (n = 0; n < profile_item.dim_n; n++) begin
                        val = int'(((kk + 3) * (n + 4)) % 23) - 11;
                        if (val == 0)
                            val = int'(n + 1);
                        b_flat[kk * profile_item.dim_n + n] = val;
                    end
                end
            end

            196: begin
                // P10C odd/tail K case: M=3, N=5, K=9.
                // Purpose:
                //   - K exceeds 8 by only one element
                //   - N=5 and K=9 stress tail handling for future tiled RTL
                //   - expected_mac = 135, expected_output = 15
                for (m = 0; m < profile_item.dim_m; m++) begin
                    for (kk = 0; kk < profile_item.dim_k; kk++) begin
                        val = int'(((m + 3) * (kk + 1)) % 11) - 5;
                        if (val == 0)
                            val = 2;
                        a_flat[m * profile_item.dim_k + kk] = val;
                    end
                end

                for (kk = 0; kk < profile_item.dim_k; kk++) begin
                    for (n = 0; n < profile_item.dim_n; n++) begin
                        val = int'(((kk + 4) * (n + 2)) % 13) - 6;
                        if (val == 0)
                            val = -2;
                        b_flat[kk * profile_item.dim_n + n] = val;
                    end
                end
            end

            197: begin
                // P10C partial second-tile case: M=4, N=4, K=12.
                // Purpose:
                //   - K=12 maps to one full K=8 logical tile plus one K=4 tail
                //   - expected_mac = 192, expected_output = 16
                for (m = 0; m < profile_item.dim_m; m++) begin
                    for (kk = 0; kk < profile_item.dim_k; kk++) begin
                        val = int'(((m + 1) * (kk + 7)) % 19) - 9;
                        if (val == 0)
                            val = -4;
                        a_flat[m * profile_item.dim_k + kk] = val;
                    end
                end

                for (kk = 0; kk < profile_item.dim_k; kk++) begin
                    for (n = 0; n < profile_item.dim_n; n++) begin
                        val = int'(((kk + 5) * (n + 3)) % 17) - 8;
                        if (val == 0)
                            val = int'(kk % 3) + 1;
                        b_flat[kk * profile_item.dim_n + n] = val;
                    end
                end
            end


            198: begin
                // P11C N>8 case: M=1, N=16, K=8.
                // Purpose:
                //   - first N-tiling software-reference case
                //   - K still fits one cache8 tile
                //   - expected_mac = 128, expected_output = 16
                for (kk = 0; kk < profile_item.dim_k; kk++) begin
                    val = int'(((kk + 1) * 2) % 11) + 1;
                    a_flat[kk] = val;
                end

                for (kk = 0; kk < profile_item.dim_k; kk++) begin
                    for (n = 0; n < profile_item.dim_n; n++) begin
                        val = int'(((kk + 1) * (n + 3)) % 17) + 1;
                        b_flat[kk * profile_item.dim_n + n] = val;
                    end
                end
            end

            199: begin
                // P11C N>8 case: M=2, N=16, K=8.
                // Purpose:
                //   - two A rows with N=16
                //   - K still fits one cache8 tile
                //   - expected_mac = 256, expected_output = 32
                for (m = 0; m < profile_item.dim_m; m++) begin
                    for (kk = 0; kk < profile_item.dim_k; kk++) begin
                        val = int'(((m + 2) * (kk + 1)) % 13) + 1;
                        a_flat[m * profile_item.dim_k + kk] = val;
                    end
                end

                for (kk = 0; kk < profile_item.dim_k; kk++) begin
                    for (n = 0; n < profile_item.dim_n; n++) begin
                        val = int'(((kk + 3) * (n + 5)) % 19) + 1;
                        b_flat[kk * profile_item.dim_n + n] = val;
                    end
                end
            end

            200: begin
                // P11C representative N+K tiled case: M=4, N=16, K=16.
                // Purpose:
                //   - N requires 8+8 output-column tiles
                //   - K requires 8+8 K tiles
                //   - expected_mac = 1024, expected_output = 64
                for (m = 0; m < profile_item.dim_m; m++) begin
                    for (kk = 0; kk < profile_item.dim_k; kk++) begin
                        val = int'(((m + 1) * (kk + 4)) % 17) + 1;
                        a_flat[m * profile_item.dim_k + kk] = val;
                    end
                end

                for (kk = 0; kk < profile_item.dim_k; kk++) begin
                    for (n = 0; n < profile_item.dim_n; n++) begin
                        val = int'(((kk + 2) * (n + 1)) % 23) + 1;
                        b_flat[kk * profile_item.dim_n + n] = val;
                    end
                end
            end

            201: begin
                // P11C irregular N/K tail case: M=3, N=9, K=9.
                // Purpose:
                //   - N tile split 8+1
                //   - K tile split 8+1
                //   - expected_mac = 243, expected_output = 27
                for (m = 0; m < profile_item.dim_m; m++) begin
                    for (kk = 0; kk < profile_item.dim_k; kk++) begin
                        val = int'(((m + 3) * (kk + 2)) % 11) + 1;
                        a_flat[m * profile_item.dim_k + kk] = val;
                    end
                end

                for (kk = 0; kk < profile_item.dim_k; kk++) begin
                    for (n = 0; n < profile_item.dim_n; n++) begin
                        val = int'(((kk + 5) * (n + 2)) % 13) + 1;
                        b_flat[kk * profile_item.dim_n + n] = val;
                    end
                end
            end

            202: begin
                // P11C N-tail + K-tiling case: M=4, N=12, K=16.
                // Purpose:
                //   - N tile split 8+4
                //   - K tile split 8+8
                //   - expected_mac = 768, expected_output = 48
                for (m = 0; m < profile_item.dim_m; m++) begin
                    for (kk = 0; kk < profile_item.dim_k; kk++) begin
                        val = int'(((m + 2) * (kk + 3)) % 19) + 1;
                        a_flat[m * profile_item.dim_k + kk] = val;
                    end
                end

                for (kk = 0; kk < profile_item.dim_k; kk++) begin
                    for (n = 0; n < profile_item.dim_n; n++) begin
                        val = int'(((kk + 4) * (n + 3)) % 17) + 1;
                        b_flat[kk * profile_item.dim_n + n] = val;
                    end
                end
            end

            203: begin
                // P12C M>4 case: M=8, N=8, K=8.
                // Purpose:
                //   - first larger-M software-reference case
                //   - K/N both fit one cache8 tile
                //   - expected_mac = 512, expected_output = 64
                for (m = 0; m < profile_item.dim_m; m++) begin
                    for (kk = 0; kk < profile_item.dim_k; kk++) begin
                        val = int'(((m + 1) * (kk + 3)) % 17) + 1;
                        a_flat[m * profile_item.dim_k + kk] = val;
                    end
                end

                for (kk = 0; kk < profile_item.dim_k; kk++) begin
                    for (n = 0; n < profile_item.dim_n; n++) begin
                        val = int'(((kk + 2) * (n + 5)) % 19) + 1;
                        b_flat[kk * profile_item.dim_n + n] = val;
                    end
                end
            end

            204: begin
                // P12C M+N case: M=8, N=16, K=8.
                // Purpose:
                //   - larger M with N split 8+8
                //   - K still fits one cache8 tile
                //   - expected_mac = 1024, expected_output = 128
                for (m = 0; m < profile_item.dim_m; m++) begin
                    for (kk = 0; kk < profile_item.dim_k; kk++) begin
                        val = int'(((m + 2) * (kk + 1)) % 13) + 1;
                        a_flat[m * profile_item.dim_k + kk] = val;
                    end
                end

                for (kk = 0; kk < profile_item.dim_k; kk++) begin
                    for (n = 0; n < profile_item.dim_n; n++) begin
                        val = int'(((kk + 3) * (n + 2)) % 23) + 1;
                        b_flat[kk * profile_item.dim_n + n] = val;
                    end
                end
            end

            205: begin
                // P12C representative M+N+K tiled case: M=8, N=16, K=16.
                // Purpose:
                //   - M requires four M=2 tiles in the P12 target scheduler
                //   - N requires 8+8 output-column tiles
                //   - K requires 8+8 K tiles
                //   - expected_mac = 2048, expected_output = 128
                for (m = 0; m < profile_item.dim_m; m++) begin
                    for (kk = 0; kk < profile_item.dim_k; kk++) begin
                        val = int'(((m + 1) * (kk + 4)) % 17) + 1;
                        a_flat[m * profile_item.dim_k + kk] = val;
                    end
                end

                for (kk = 0; kk < profile_item.dim_k; kk++) begin
                    for (n = 0; n < profile_item.dim_n; n++) begin
                        val = int'(((kk + 2) * (n + 3)) % 23) + 1;
                        b_flat[kk * profile_item.dim_n + n] = val;
                    end
                end
            end

            206: begin
                // P12C irregular M/N/K tail case: M=5, N=9, K=9.
                // Purpose:
                //   - M tile split 2+2+1 in the P12 target scheduler
                //   - N tile split 8+1
                //   - K tile split 8+1
                //   - expected_mac = 405, expected_output = 45
                for (m = 0; m < profile_item.dim_m; m++) begin
                    for (kk = 0; kk < profile_item.dim_k; kk++) begin
                        val = int'(((m + 3) * (kk + 2)) % 11) + 1;
                        a_flat[m * profile_item.dim_k + kk] = val;
                    end
                end

                for (kk = 0; kk < profile_item.dim_k; kk++) begin
                    for (n = 0; n < profile_item.dim_n; n++) begin
                        val = int'(((kk + 5) * (n + 2)) % 13) + 1;
                        b_flat[kk * profile_item.dim_n + n] = val;
                    end
                end
            end

            207: begin
                // P12C M-tail + N-tail + K-tiling case: M=7, N=12, K=16.
                // Purpose:
                //   - M tile split 2+2+2+1 in the P12 target scheduler
                //   - N tile split 8+4
                //   - K tile split 8+8
                //   - expected_mac = 1344, expected_output = 84
                for (m = 0; m < profile_item.dim_m; m++) begin
                    for (kk = 0; kk < profile_item.dim_k; kk++) begin
                        val = int'(((m + 2) * (kk + 3)) % 19) + 1;
                        a_flat[m * profile_item.dim_k + kk] = val;
                    end
                end

                for (kk = 0; kk < profile_item.dim_k; kk++) begin
                    for (n = 0; n < profile_item.dim_n; n++) begin
                        val = int'(((kk + 4) * (n + 3)) % 17) + 1;
                        b_flat[kk * profile_item.dim_n + n] = val;
                    end
                end
            end

            default: begin
                `uvm_fatal("CASE_HELPER/VAR_BAD_CASE",
                    $sformatf("Unsupported variable-dimension case_id=%0d", case_id))
            end
        endcase

        compute_expected_c_compact(
            a_flat,
            b_flat,
            profile_item.dim_m,
            profile_item.dim_n,
            profile_item.dim_k,
            expected_c
        );
    end
    endtask

    // ------------------------------------------------------------
    // Build configurable-base payload:
    //   - canonical profile item
    //   - A_flat
    //   - B_flat
    //   - expected_c
    //
    // Payload policy:
    //   Reuse identity(4x4) x known(4x4), so expected C = B directly.
    //   The only thing that changes across CASE 400~403 is base map.
    // ------------------------------------------------------------
    task automatic build_configurable_base_case_payload(
        input  int unsigned              case_id,
        output ai_accel_subsys_seq_item  profile_item,
        output int signed                a_flat[],
        output int signed                b_flat[],
        output int signed                expected_c[]
    );
    begin
        profile_item = build_case_profile(
            case_id,
            ai_accel_subsys_seq_item::TEST_KIND_CONFIGURABLE_BASE
        );

        a_flat = new[16];
        b_flat = new[16];

        zero_vector(a_flat);
        zero_vector(b_flat);

        // A = identity(4x4)
        a_flat[ 0] = 1;  a_flat[ 1] = 0;  a_flat[ 2] = 0;  a_flat[ 3] = 0;
        a_flat[ 4] = 0;  a_flat[ 5] = 1;  a_flat[ 6] = 0;  a_flat[ 7] = 0;
        a_flat[ 8] = 0;  a_flat[ 9] = 0;  a_flat[10] = 1;  a_flat[11] = 0;
        a_flat[12] = 0;  a_flat[13] = 0;  a_flat[14] = 0;  a_flat[15] = 1;

        // B = known matrix
        b_flat[ 0] =  1; b_flat[ 1] =  2; b_flat[ 2] =  3; b_flat[ 3] =  4;
        b_flat[ 4] =  5; b_flat[ 5] =  6; b_flat[ 6] =  7; b_flat[ 7] =  8;
        b_flat[ 8] =  9; b_flat[ 9] = 10; b_flat[10] = 11; b_flat[11] = 12;
        b_flat[12] = 13; b_flat[13] = 14; b_flat[14] = 15; b_flat[15] = 16;

        case (case_id)
            400, 401, 402, 403: begin
                // legal configurable-base cases
            end

            default: begin
                `uvm_fatal("CASE_HELPER/CFG_BAD_CASE",
                    $sformatf("Unsupported configurable-base case_id=%0d", case_id))
            end
        endcase

        compute_expected_identity_known_4x4(b_flat, expected_c);
    end
    endtask

    // ------------------------------------------------------------
    // C RMW accumulation recipe helpers
    // ------------------------------------------------------------
    function bit is_c_rmw_accum_recipe_case(input int unsigned case_id);
        return ((case_id >= 208) && (case_id <= 212));
    endfunction

    function void get_c_rmw_accum_recipe_shape(
        input  int unsigned case_id,
        output int unsigned dim_m,
        output int unsigned dim_n,
        output int unsigned k_total
    );
        case (case_id)
            208: begin dim_m = 1; dim_n = 4;  k_total = 16; end
            209: begin dim_m = 4; dim_n = 4;  k_total = 16; end
            210: begin dim_m = 4; dim_n = 16; k_total = 16; end
            211: begin dim_m = 8; dim_n = 16; k_total = 16; end
            212: begin dim_m = 5; dim_n = 9;  k_total = 9;  end
            default: begin
                `uvm_fatal("CASE_HELPER/C_RMW_ACCUM_BAD_RECIPE",
                    $sformatf("Unsupported C RMW accumulation recipe case_id=%0d", case_id))
                dim_m = 1;
                dim_n = 1;
                k_total = 1;
            end
        endcase
    endfunction

    function int unsigned get_c_rmw_accum_recipe_job_count(input int unsigned case_id);
        if (is_c_rmw_accum_recipe_case(case_id))
            return 2;

        `uvm_fatal("CASE_HELPER/C_RMW_ACCUM_BAD_RECIPE",
            $sformatf("Unsupported C RMW accumulation recipe case_id=%0d", case_id))
        return 0;
    endfunction

    function void get_c_rmw_accum_recipe_job_info(
        input  int unsigned case_id,
        input  int unsigned job_idx,
        output int unsigned k_base,
        output int unsigned k_part,
        output bit          accumulate_enable
    );
        int unsigned job_count;
    begin
        job_count = get_c_rmw_accum_recipe_job_count(case_id);

        if (job_idx >= job_count) begin
            `uvm_fatal("CASE_HELPER/C_RMW_ACCUM_BAD_JOB_IDX",
                $sformatf("case_id=%0d job_idx=%0d exceeds job_count=%0d",
                    case_id, job_idx, job_count))
        end

        accumulate_enable = (job_idx != 0);

        case (case_id)
            208, 209, 210, 211: begin
                if (job_idx == 0) begin
                    k_base = 0;
                    k_part = 8;
                end
                else begin
                    k_base = 8;
                    k_part = 8;
                end
            end

            212: begin
                if (job_idx == 0) begin
                    k_base = 0;
                    k_part = 8;
                end
                else begin
                    k_base = 8;
                    k_part = 1;
                end
            end

            default: begin
                `uvm_fatal("CASE_HELPER/C_RMW_ACCUM_BAD_RECIPE",
                    $sformatf("Unsupported C RMW accumulation recipe case_id=%0d", case_id))
                k_base = 0;
                k_part = 0;
                accumulate_enable = 1'b0;
            end
        endcase
    end
    endfunction

    // ------------------------------------------------------------
    // Build deterministic full-K A/B matrices for a C RMW accumulation recipe.
    //
    // The generated full matrices are used only by the software
    // reference model.  Each partial job later extracts a compact
    // K-partition from these full matrices.
    // ------------------------------------------------------------
    task automatic build_c_rmw_accum_full_matrices(
        input  int unsigned case_id,
        output ai_accel_subsys_seq_item profile_item,
        output int signed   a_full[],
        output int signed   b_full[]
    );
        int unsigned dim_m;
        int unsigned dim_n;
        int unsigned k_total;
        int unsigned m;
        int unsigned n;
        int unsigned kk;
        int signed   val;
    begin
        profile_item = build_case_profile(
            case_id,
            ai_accel_subsys_seq_item::TEST_KIND_C_RMW_ACCUM_RECIPE
        );

        dim_m   = profile_item.dim_m;
        dim_n   = profile_item.dim_n;
        k_total = profile_item.dim_k;

        a_full = new[dim_m * k_total];
        b_full = new[k_total * dim_n];

        zero_vector(a_full);
        zero_vector(b_full);

        for (m = 0; m < dim_m; m++) begin
            for (kk = 0; kk < k_total; kk++) begin
                val = int'((((case_id % 13) + 1) * (m + 1) * (kk + 2)) % 17) - 8;
                if (val == 0)
                    val = ((m % 2) != 0) ? -3 : 3;
                a_full[m * k_total + kk] = val;
            end
        end

        for (kk = 0; kk < k_total; kk++) begin
            for (n = 0; n < dim_n; n++) begin
                val = int'((((case_id % 11) + 3) * (kk + 1) * (n + 3)) % 19) - 9;
                if (val == 0)
                    val = ((n % 2) != 0) ? -2 : 2;
                b_full[kk * dim_n + n] = val;
            end
        end
    end
    endtask

    // ------------------------------------------------------------
    // Extract one compact K-partition job payload from full A/B.
    // ------------------------------------------------------------
    task automatic extract_c_rmw_accum_job_payload(
        input  int signed   a_full[],
        input  int signed   b_full[],
        input  int unsigned dim_m,
        input  int unsigned dim_n,
        input  int unsigned k_total,
        input  int unsigned k_base,
        input  int unsigned k_part,
        output int signed   a_part[],
        output int signed   b_part[]
    );
        int unsigned m;
        int unsigned n;
        int unsigned lk;
    begin
        a_part = new[dim_m * k_part];
        b_part = new[k_part * dim_n];

        for (m = 0; m < dim_m; m++) begin
            for (lk = 0; lk < k_part; lk++) begin
                a_part[m * k_part + lk] = a_full[m * k_total + (k_base + lk)];
            end
        end

        for (lk = 0; lk < k_part; lk++) begin
            for (n = 0; n < dim_n; n++) begin
                b_part[lk * dim_n + n] = b_full[(k_base + lk) * dim_n + n];
            end
        end
    end
    endtask

    // ------------------------------------------------------------
    // Accumulate one partial C vector into an existing C vector.
    // ------------------------------------------------------------
    task automatic compute_expected_c_accumulate(
        input  int signed old_c[],
        input  int signed partial_c[],
        input  bit        accumulate_enable,
        output int signed new_c[]
    );
        int unsigned i;
    begin
        if (old_c.size() != partial_c.size()) begin
            `uvm_fatal("CASE_HELPER/C_RMW_ACCUM_SIZE",
                $sformatf("old_c.size=%0d partial_c.size=%0d",
                    old_c.size(), partial_c.size()))
        end

        new_c = new[partial_c.size()];

        for (i = 0; i < partial_c.size(); i++) begin
            if (accumulate_enable)
                new_c[i] = old_c[i] + partial_c[i];
            else
                new_c[i] = partial_c[i];
        end
    end
    endtask

    // ------------------------------------------------------------
    // Build full-recipe expected final C.
    // ------------------------------------------------------------
    task automatic build_c_rmw_accum_recipe_expected_payload(
        input  int unsigned              case_id,
        output ai_accel_subsys_seq_item  profile_item,
        output int signed                a_full[],
        output int signed                b_full[],
        output int signed                expected_final_c[]
    );
    begin
        build_c_rmw_accum_full_matrices(
            case_id,
            profile_item,
            a_full,
            b_full
        );

        compute_expected_c_compact(
            a_full,
            b_full,
            profile_item.dim_m,
            profile_item.dim_n,
            profile_item.dim_k,
            expected_final_c
        );
    end
    endtask

    // ------------------------------------------------------------
    // Build one partial-job payload and the expected accumulated C
    // after that job.
    // ------------------------------------------------------------
    task automatic build_c_rmw_accum_job_payload(
        input  int unsigned              case_id,
        input  int unsigned              job_idx,
        output ai_accel_subsys_seq_item  job_item,
        output int signed                a_part[],
        output int signed                b_part[],
        output int signed                expected_partial_c[],
        output int signed                expected_accumulated_c[]
    );
        ai_accel_subsys_seq_item recipe_item;
        int signed               a_full[];
        int signed               b_full[];
        int signed               tmp_a_part[];
        int signed               tmp_b_part[];
        int signed               tmp_partial_c[];
        int signed               accum_prev[];
        int signed               accum_next[];
        int unsigned             dim_m;
        int unsigned             dim_n;
        int unsigned             k_total;
        int unsigned             k_base;
        int unsigned             k_part;
        int unsigned             j;
        bit                      accum_en;
    begin
        build_c_rmw_accum_full_matrices(case_id, recipe_item, a_full, b_full);

        dim_m   = recipe_item.dim_m;
        dim_n   = recipe_item.dim_n;
        k_total = recipe_item.dim_k;

        job_item = ai_accel_subsys_seq_item::type_id::create("c_rmw_accum_job_item");
        job_item.apply_c_rmw_accum_job_case(case_id, job_idx);

        get_c_rmw_accum_recipe_job_info(case_id, job_idx, k_base, k_part, accum_en);

        extract_c_rmw_accum_job_payload(
            a_full,
            b_full,
            dim_m,
            dim_n,
            k_total,
            k_base,
            k_part,
            a_part,
            b_part
        );

        compute_expected_c_compact(
            a_part,
            b_part,
            dim_m,
            dim_n,
            k_part,
            expected_partial_c
        );

        accum_prev = new[dim_m * dim_n];
        zero_vector(accum_prev);

        for (j = 0; j <= job_idx; j++) begin
            get_c_rmw_accum_recipe_job_info(case_id, j, k_base, k_part, accum_en);

            extract_c_rmw_accum_job_payload(
                a_full,
                b_full,
                dim_m,
                dim_n,
                k_total,
                k_base,
                k_part,
                tmp_a_part,
                tmp_b_part
            );

            compute_expected_c_compact(
                tmp_a_part,
                tmp_b_part,
                dim_m,
                dim_n,
                k_part,
                tmp_partial_c
            );

            compute_expected_c_accumulate(
                accum_prev,
                tmp_partial_c,
                accum_en,
                accum_next
            );

            accum_prev = new[accum_next.size()];
            for (int unsigned i = 0; i < accum_next.size(); i++) begin
                accum_prev[i] = accum_next[i];
            end
        end

        expected_accumulated_c = new[accum_prev.size()];
        for (int unsigned i = 0; i < accum_prev.size(); i++) begin
            expected_accumulated_c[i] = accum_prev[i];
        end
    end
    endtask

endclass

`endif
