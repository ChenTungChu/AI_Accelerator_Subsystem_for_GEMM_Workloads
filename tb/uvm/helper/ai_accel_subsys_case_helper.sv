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

endclass

`endif
