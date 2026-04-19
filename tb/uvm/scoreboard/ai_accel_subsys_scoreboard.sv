// File: tb/uvm/scoreboard/ai_accel_subsys_scoreboard.sv
`ifndef AI_ACCEL_SUBSYS_SCOREBOARD_SV
`define AI_ACCEL_SUBSYS_SCOREBOARD_SV

`uvm_analysis_imp_decl(_ctrl)
`uvm_analysis_imp_decl(_result)

class ai_accel_subsys_scoreboard extends uvm_component;
    `uvm_component_utils(ai_accel_subsys_scoreboard)

    // ------------------------------------------------------------
    // Common base maps
    // ------------------------------------------------------------
    localparam bit [31:0] BASE_A_DEFAULT = 32'h0000_0000;
    localparam bit [31:0] BASE_B_DEFAULT = 32'h0000_0100;
    localparam bit [31:0] BASE_C_DEFAULT = 32'h0000_0200;

    localparam bit [31:0] CFG401_BASE_A = 32'h0000_0040;
    localparam bit [31:0] CFG401_BASE_B = 32'h0000_0140;
    localparam bit [31:0] CFG401_BASE_C = 32'h0000_0240;

    localparam bit [31:0] CFG402_BASE_A = 32'h0000_0080;
    localparam bit [31:0] CFG402_BASE_B = 32'h0000_0180;
    localparam bit [31:0] CFG402_BASE_C = 32'h0000_0280;

    localparam bit [31:0] CFG403_BASE_A = 32'h0000_0020;
    localparam bit [31:0] CFG403_BASE_B = 32'h0000_0060;
    localparam bit [31:0] CFG403_BASE_C = 32'h0000_00A0;

    // ------------------------------------------------------------
    // First-step latency sanity range
    // ------------------------------------------------------------
    localparam int unsigned MIN_VALID_LATENCY = 1;
    localparam int unsigned MAX_VALID_LATENCY = 50000;

    // ------------------------------------------------------------
    // Analysis imports
    // ------------------------------------------------------------
    uvm_analysis_imp_ctrl   #(ai_accel_subsys_seq_item,    ai_accel_subsys_scoreboard) ctrl_analysis_export;
    uvm_analysis_imp_result #(ai_accel_subsys_result_item, ai_accel_subsys_scoreboard) result_analysis_export;

    // ------------------------------------------------------------
    // Control-path state
    // ------------------------------------------------------------
    int unsigned observed_start_count;
    int unsigned observed_done_count;
    ai_accel_subsys_seq_item last_seen_item;

    // ------------------------------------------------------------
    // Result-path state
    // ------------------------------------------------------------
    bit          result_check_enable;
    int unsigned observed_result_count;
    int unsigned result_pass_count;
    int unsigned result_fail_count;
    ai_accel_subsys_result_item last_result_item;

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        ctrl_analysis_export   = new("ctrl_analysis_export", this);
        result_analysis_export = new("result_analysis_export", this);
    endfunction

    // ------------------------------------------------------------
    // Build phase
    // ------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        observed_start_count = 0;
        observed_done_count  = 0;

        observed_result_count = 0;
        result_pass_count     = 0;
        result_fail_count     = 0;

        result_check_enable   = 1'b0;

        void'(uvm_config_db#(bit)::get(this, "", "result_check_enable", result_check_enable));
    endfunction

    // ------------------------------------------------------------
    // CTRL write callback
    // ------------------------------------------------------------
    function void write_ctrl(ai_accel_subsys_seq_item t);
        observed_start_count++;

        if (t.done_seen)
            observed_done_count++;

        last_seen_item = ai_accel_subsys_seq_item::type_id::create("last_seen_item");
        last_seen_item.copy(t);

        `uvm_info("SB",
            $sformatf(
                "Observed ctrl event #%0d: case_id=%0d test_kind=%0d base_a=0x%08h base_b=0x%08h base_c=0x%08h dim=(%0d,%0d,%0d) done_seen=%0d start_cycle=%0d done_cycle=%0d latency_cycles=%0d test_name=%s",
                observed_start_count,
                t.case_id, t.test_kind,
                t.base_addr_a, t.base_addr_b, t.base_addr_c,
                t.dim_m, t.dim_n, t.dim_k,
                t.done_seen, t.start_cycle, t.done_cycle, t.latency_cycles,
                t.test_name
            ),
            UVM_MEDIUM)
    endfunction

    // ------------------------------------------------------------
    // RESULT write callback
    // ------------------------------------------------------------
    function void write_result(ai_accel_subsys_result_item t);
        observed_result_count++;

        last_result_item = ai_accel_subsys_result_item::type_id::create("last_result_item");
        last_result_item.copy(t);

        if (!last_result_item.compare_done)
            last_result_item.run_compare();

        if (last_result_item.compare_pass) begin
            result_pass_count++;
            `uvm_info("SB",
                $sformatf(
                    "Result compare PASS: case_id=%0d test_kind=%0d dim=(%0d,%0d,%0d) elements=%0d",
                    last_result_item.case_id,
                    last_result_item.test_kind,
                    last_result_item.dim_m,
                    last_result_item.dim_n,
                    last_result_item.dim_k,
                    last_result_item.element_count
                ),
                UVM_MEDIUM)
        end
        else begin
            result_fail_count++;
            `uvm_error("SB/RESULT_MISMATCH",
                $sformatf(
                    "Result compare FAIL: case_id=%0d test_kind=%0d mismatch_count=%0d first_idx=%0d exp=%0d act=%0d",
                    last_result_item.case_id,
                    last_result_item.test_kind,
                    last_result_item.mismatch_count,
                    last_result_item.first_mismatch_idx,
                    last_result_item.first_expected,
                    last_result_item.first_actual
                ))
        end
    endfunction

    // ------------------------------------------------------------
    // Utility helpers
    // ------------------------------------------------------------
    function void expect_base_map(
        bit [31:0] a_exp,
        bit [31:0] b_exp,
        bit [31:0] c_exp,
        string profile_name
    );
        if (last_seen_item.base_addr_a !== a_exp) begin
            `uvm_error("SB/BASE_A",
                $sformatf("[%s] base_addr_a mismatch: got=0x%08h exp=0x%08h",
                    profile_name, last_seen_item.base_addr_a, a_exp))
        end

        if (last_seen_item.base_addr_b !== b_exp) begin
            `uvm_error("SB/BASE_B",
                $sformatf("[%s] base_addr_b mismatch: got=0x%08h exp=0x%08h",
                    profile_name, last_seen_item.base_addr_b, b_exp))
        end

        if (last_seen_item.base_addr_c !== c_exp) begin
            `uvm_error("SB/BASE_C",
                $sformatf("[%s] base_addr_c mismatch: got=0x%08h exp=0x%08h",
                    profile_name, last_seen_item.base_addr_c, c_exp))
        end
    endfunction

    function void expect_dims(
        int unsigned m_exp,
        int unsigned n_exp,
        int unsigned k_exp,
        string profile_name
    );
        if (last_seen_item.dim_m !== m_exp) begin
            `uvm_error("SB/DIM_M",
                $sformatf("[%s] dim_m mismatch: got=%0d exp=%0d",
                    profile_name, last_seen_item.dim_m, m_exp))
        end

        if (last_seen_item.dim_n !== n_exp) begin
            `uvm_error("SB/DIM_N",
                $sformatf("[%s] dim_n mismatch: got=%0d exp=%0d",
                    profile_name, last_seen_item.dim_n, n_exp))
        end

        if (last_seen_item.dim_k !== k_exp) begin
            `uvm_error("SB/DIM_K",
                $sformatf("[%s] dim_k mismatch: got=%0d exp=%0d",
                    profile_name, last_seen_item.dim_k, k_exp))
        end
    endfunction

    // ------------------------------------------------------------
    // Fixed-baseline checks
    // ------------------------------------------------------------
    function void check_fixed_baseline_case(int unsigned case_id);
        case (case_id)
            0, 1, 2, 3, 4, 5, 6, 7: begin
                expect_base_map(BASE_A_DEFAULT, BASE_B_DEFAULT, BASE_C_DEFAULT,
                                $sformatf("fixed_case_%0d", case_id));
                expect_dims(4, 4, 4, $sformatf("fixed_case_%0d", case_id));

                `uvm_info("SB",
                    $sformatf("Matched fixed-baseline case %0d", case_id),
                    UVM_LOW)
            end
            default: begin
                `uvm_error("SB/FIXED_BAD_CASE",
                    $sformatf("Unsupported fixed-baseline case_id=%0d", case_id))
            end
        endcase
    endfunction

    // ------------------------------------------------------------
    // Variable-dimension checks
    // ------------------------------------------------------------
    function void check_variable_dim_case(int unsigned case_id);
        expect_base_map(BASE_A_DEFAULT, BASE_B_DEFAULT, BASE_C_DEFAULT,
                        $sformatf("var_case_%0d", case_id));

        case (case_id)
            100: expect_dims(1, 1, 1, "var100");
            101: expect_dims(2, 2, 2, "var101");
            102: expect_dims(4, 4, 1, "var102");
            103: expect_dims(1, 4, 4, "var103");
            104: expect_dims(4, 1, 4, "var104");
            105: expect_dims(2, 3, 4, "var105");
            default: begin
                `uvm_error("SB/VAR_BAD_CASE",
                    $sformatf("Unsupported variable-dimension case_id=%0d", case_id))
                return;
            end
        endcase

        `uvm_info("SB",
            $sformatf("Matched variable-dimension case %0d", case_id),
            UVM_LOW)
    endfunction

    // ------------------------------------------------------------
    // Configurable-base checks
    // ------------------------------------------------------------
    function void check_configurable_base_case(int unsigned case_id);
        expect_dims(4, 4, 4, $sformatf("cfg_case_%0d", case_id));

        case (case_id)
            400: expect_base_map(BASE_A_DEFAULT, BASE_B_DEFAULT, BASE_C_DEFAULT, "cfg400");
            401: expect_base_map(CFG401_BASE_A, CFG401_BASE_B, CFG401_BASE_C, "cfg401");
            402: expect_base_map(CFG402_BASE_A, CFG402_BASE_B, CFG402_BASE_C, "cfg402");
            403: expect_base_map(CFG403_BASE_A, CFG403_BASE_B, CFG403_BASE_C, "cfg403");
            default: begin
                `uvm_error("SB/CFG_BAD_CASE",
                    $sformatf("Unsupported configurable-base case_id=%0d", case_id))
                return;
            end
        endcase

        `uvm_info("SB",
            $sformatf("Matched configurable-base case %0d", case_id),
            UVM_LOW)
    endfunction

    // ------------------------------------------------------------
    // Top-level control-profile check
    // ------------------------------------------------------------
    function void check_selected_profile();
        if (last_seen_item == null) begin
            `uvm_error("SB/NOLAST", "last_seen_item is null, cannot check selected profile")
            return;
        end

        case (last_seen_item.test_kind)
            ai_accel_subsys_seq_item::TEST_KIND_FIXED_BASELINE:
                check_fixed_baseline_case(last_seen_item.case_id);

            ai_accel_subsys_seq_item::TEST_KIND_VARIABLE_DIM_SMOKE:
                check_variable_dim_case(last_seen_item.case_id);

            ai_accel_subsys_seq_item::TEST_KIND_CONFIGURABLE_BASE:
                check_configurable_base_case(last_seen_item.case_id);

            default:
                `uvm_error("SB/BAD_KIND",
                    $sformatf("Unsupported test_kind=%0d for case_id=%0d",
                        last_seen_item.test_kind, last_seen_item.case_id))
        endcase
    endfunction

    // ------------------------------------------------------------
    // Helper: check done / latency consistency
    // ------------------------------------------------------------
    function void check_done_latency();
        int unsigned exp_latency;
    begin
        if (last_seen_item == null) begin
            `uvm_error("SB/NOLAST", "last_seen_item is null, cannot check done/latency")
            return;
        end

        if (!last_seen_item.done_seen) begin
            `uvm_error("SB/NODONE", "Scoreboard transaction indicates done_seen=0")
            return;
        end

        if (last_seen_item.done_cycle < last_seen_item.start_cycle) begin
            `uvm_error("SB/CYCLE_ORDER",
                $sformatf("done_cycle < start_cycle: start=%0d done=%0d",
                    last_seen_item.start_cycle, last_seen_item.done_cycle))
        end

        exp_latency = last_seen_item.done_cycle - last_seen_item.start_cycle;

        if (last_seen_item.latency_cycles !== exp_latency) begin
            `uvm_error("SB/LATENCY_MISMATCH",
                $sformatf("latency mismatch: got=%0d exp=%0d (start=%0d done=%0d)",
                    last_seen_item.latency_cycles, exp_latency,
                    last_seen_item.start_cycle, last_seen_item.done_cycle))
        end

        if (last_seen_item.latency_cycles < MIN_VALID_LATENCY) begin
            `uvm_error("SB/LATENCY_TOO_SMALL",
                $sformatf("latency too small: %0d", last_seen_item.latency_cycles))
        end

        if (last_seen_item.latency_cycles > MAX_VALID_LATENCY) begin
            `uvm_error("SB/LATENCY_TOO_LARGE",
                $sformatf("latency too large: %0d", last_seen_item.latency_cycles))
        end

        `uvm_info("SB",
            $sformatf("Latency check passed: start=%0d done=%0d latency=%0d cycles",
                last_seen_item.start_cycle,
                last_seen_item.done_cycle,
                last_seen_item.latency_cycles),
            UVM_LOW)
    end
    endfunction

    // ------------------------------------------------------------
    // Result-path summary check
    // ------------------------------------------------------------
    function void check_result_summary();
        if (!result_check_enable)
            return;

        if (observed_result_count == 0) begin
            `uvm_error("SB/NORESULT", "Result checking is enabled, but no result_item was observed")
            return;
        end

        if (result_fail_count != 0) begin
            `uvm_error("SB/RESULT_FAIL_SUMMARY",
                $sformatf("Result compare observed %0d fail item(s)", result_fail_count))
        end

        `uvm_info("SB",
            $sformatf("Result summary: observed=%0d pass=%0d fail=%0d",
                observed_result_count, result_pass_count, result_fail_count),
            UVM_LOW)
    endfunction

    // ------------------------------------------------------------
    // Report phase
    // ------------------------------------------------------------
    function void report_phase(uvm_phase phase);
        super.report_phase(phase);

        `uvm_info("SB",
            $sformatf("Control summary: start=%0d completed=%0d",
                observed_start_count, observed_done_count),
            UVM_LOW)

        if (observed_start_count == 0) begin
            `uvm_error("SB/NOSTART", "Scoreboard did not observe any acc_start event")
            return;
        end

        if (observed_start_count != 1) begin
            `uvm_error("SB/COUNT",
                $sformatf("Expected exactly 1 start event, but observed %0d",
                    observed_start_count))
        end

        if (observed_done_count != 1) begin
            `uvm_error("SB/DONE_COUNT",
                $sformatf("Expected exactly 1 completed event, but observed %0d",
                    observed_done_count))
        end

        check_selected_profile();
        check_done_latency();
        check_result_summary();
    endfunction

endclass

`endif