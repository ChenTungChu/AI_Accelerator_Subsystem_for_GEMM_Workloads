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
    // Latency sanity range
    // ------------------------------------------------------------
    localparam int unsigned MIN_VALID_LATENCY = 1;
    localparam int unsigned MAX_VALID_LATENCY = 50000;

    // ------------------------------------------------------------
    // Analysis imports
    // ------------------------------------------------------------
    uvm_analysis_imp_ctrl   #(ai_accel_subsys_seq_item,    ai_accel_subsys_scoreboard) ctrl_analysis_export;
    uvm_analysis_imp_result #(ai_accel_subsys_result_item, ai_accel_subsys_scoreboard) result_analysis_export;

    // ------------------------------------------------------------
    // Control-path summary
    // ------------------------------------------------------------
    int unsigned observed_start_count;
    int unsigned observed_done_count;

    // ------------------------------------------------------------
    // Result-path summary
    // ------------------------------------------------------------
    bit          result_check_enable;
    int unsigned observed_result_count;
    int unsigned result_pass_count;
    int unsigned result_fail_count;

    // ------------------------------------------------------------
    // Mid-run reset / expected-abort support
    // ------------------------------------------------------------
    bit          midrun_reset_test_mode;
    int unsigned expected_aborted_job_count;

    // ------------------------------------------------------------
    // Multi-job pairing state
    //
    // Only DONE-side ctrl items participate in result pairing.
    // START-side items are observed/logged, but not queued here.
    // ------------------------------------------------------------
    ai_accel_subsys_seq_item    ctrl_q[$];
    ai_accel_subsys_result_item result_q[$];

    int unsigned matched_job_count;
    int unsigned ctrl_profile_pass_count;
    int unsigned ctrl_latency_pass_count;
    int unsigned ctrl_result_pair_pass_count;

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

        observed_start_count        = 0;
        observed_done_count         = 0;

        observed_result_count       = 0;
        result_pass_count           = 0;
        result_fail_count           = 0;

        matched_job_count           = 0;
        ctrl_profile_pass_count     = 0;
        ctrl_latency_pass_count     = 0;
        ctrl_result_pair_pass_count = 0;

        result_check_enable         = 1'b0;
        midrun_reset_test_mode      = 1'b0;
        expected_aborted_job_count  = 0;

        void'(uvm_config_db#(bit)::get(this, "", "result_check_enable", result_check_enable));
        void'(uvm_config_db#(bit)::get(this, "", "midrun_reset_test_mode", midrun_reset_test_mode));
        void'(uvm_config_db#(int unsigned)::get(this, "", "expected_aborted_job_count", expected_aborted_job_count));
    endfunction

    // ------------------------------------------------------------
    // Clone helpers
    // ------------------------------------------------------------
    function ai_accel_subsys_seq_item clone_ctrl_item(ai_accel_subsys_seq_item src);
        ai_accel_subsys_seq_item dst;
        dst = ai_accel_subsys_seq_item::type_id::create("dst");
        dst.copy(src);
        return dst;
    endfunction

    function ai_accel_subsys_result_item clone_result_item(ai_accel_subsys_result_item src);
        ai_accel_subsys_result_item dst;
        dst = ai_accel_subsys_result_item::type_id::create("dst");
        dst.copy(src);
        return dst;
    endfunction

    // ------------------------------------------------------------
    // Summary expectation helpers
    // ------------------------------------------------------------
    function int unsigned get_expected_aborted_count();
        if (midrun_reset_test_mode)
            return expected_aborted_job_count;
        return 0;
    endfunction

    function int unsigned get_expected_completed_count();
        int unsigned exp_abort;
    begin
        exp_abort = get_expected_aborted_count();

        if (observed_start_count < exp_abort)
            return 0;

        return (observed_start_count - exp_abort);
    end
    endfunction

    function int unsigned get_observed_aborted_count();
    begin
        if (observed_start_count < observed_done_count)
            return 0;

        return (observed_start_count - observed_done_count);
    end
    endfunction

    // ------------------------------------------------------------
    // Ctrl-event classification helpers
    //
    // Legacy compatibility:
    //   if ctrl_event_kind == CTRL_EVENT_NONE, fall back to done_seen
    // ------------------------------------------------------------
    function bit is_start_side_ctrl(ai_accel_subsys_seq_item item);
        if (item == null)
            return 1'b0;

        if (item.ctrl_event_kind == ai_accel_subsys_seq_item::CTRL_EVENT_START)
            return 1'b1;

        if (item.ctrl_event_kind == ai_accel_subsys_seq_item::CTRL_EVENT_DONE)
            return 1'b0;

        // Legacy fallback
        return !item.done_seen;
    endfunction

    function bit is_done_side_ctrl(ai_accel_subsys_seq_item item);
        if (item == null)
            return 1'b0;

        if (item.ctrl_event_kind == ai_accel_subsys_seq_item::CTRL_EVENT_DONE)
            return 1'b1;

        if (item.ctrl_event_kind == ai_accel_subsys_seq_item::CTRL_EVENT_START)
            return 1'b0;

        // Legacy fallback
        return item.done_seen;
    endfunction

    function string ctrl_event_kind_name(ai_accel_subsys_seq_item item);
        if (item == null)
            return "NULL";

        case (item.ctrl_event_kind)
            ai_accel_subsys_seq_item::CTRL_EVENT_NONE:  return "NONE";
            ai_accel_subsys_seq_item::CTRL_EVENT_START: return "START";
            ai_accel_subsys_seq_item::CTRL_EVENT_DONE:  return "DONE";
            default:                                    return "UNKNOWN";
        endcase
    endfunction

    // ------------------------------------------------------------
    // CTRL write callback
    //
    // Phase-aware behavior on the same ctrl path:
    //   - START events are observed/logged only
    //   - DONE  events go through profile/latency/pairing flow
    // ------------------------------------------------------------
    function void write_ctrl(ai_accel_subsys_seq_item t);
        ai_accel_subsys_seq_item item;

        item = clone_ctrl_item(t);

        if (is_start_side_ctrl(item)) begin
            observed_start_count++;

            `uvm_info("SB",
                $sformatf(
                    "Observed ctrl START event #%0d: case_id=%0d test_kind=%0d base_a=0x%08h base_b=0x%08h base_c=0x%08h dim=(%0d,%0d,%0d) event_kind=%s done_seen=%0d start_cycle=%0d done_cycle=%0d latency_cycles=%0d test_name=%s",
                    observed_start_count,
                    item.case_id, item.test_kind,
                    item.base_addr_a, item.base_addr_b, item.base_addr_c,
                    item.dim_m, item.dim_n, item.dim_k,
                    ctrl_event_kind_name(item),
                    item.done_seen, item.start_cycle, item.done_cycle, item.latency_cycles,
                    item.test_name
                ),
                UVM_MEDIUM)

            return;
        end

        if (is_done_side_ctrl(item)) begin
            observed_done_count++;

            `uvm_info("SB",
                $sformatf(
                    "Observed ctrl DONE event #%0d: case_id=%0d test_kind=%0d base_a=0x%08h base_b=0x%08h base_c=0x%08h dim=(%0d,%0d,%0d) event_kind=%s done_seen=%0d start_cycle=%0d done_cycle=%0d latency_cycles=%0d test_name=%s",
                    observed_done_count,
                    item.case_id, item.test_kind,
                    item.base_addr_a, item.base_addr_b, item.base_addr_c,
                    item.dim_m, item.dim_n, item.dim_k,
                    ctrl_event_kind_name(item),
                    item.done_seen, item.start_cycle, item.done_cycle, item.latency_cycles,
                    item.test_name
                ),
                UVM_MEDIUM)

            check_ctrl_item_profile(item);
            check_ctrl_item_done_latency(item);

            ctrl_q.push_back(item);
            try_match_jobs();
            return;
        end

        `uvm_warning("SB/CTRL_EVENT_UNKNOWN",
            $sformatf("Ignoring ctrl item with unsupported event classification: case_id=%0d test_kind=%0d event_kind=%s done_seen=%0d",
                item.case_id, item.test_kind, ctrl_event_kind_name(item), item.done_seen))
    endfunction

    // ------------------------------------------------------------
    // RESULT write callback
    // ------------------------------------------------------------
    function void write_result(ai_accel_subsys_result_item t);
        ai_accel_subsys_result_item item;

        observed_result_count++;

        item = clone_result_item(t);

        if (!item.compare_done)
            item.run_compare();

        if (item.compare_pass) begin
            result_pass_count++;
            `uvm_info("SB",
                $sformatf(
                    "Result compare PASS: case_id=%0d test_kind=%0d dim=(%0d,%0d,%0d) elements=%0d",
                    item.case_id,
                    item.test_kind,
                    item.dim_m,
                    item.dim_n,
                    item.dim_k,
                    item.element_count
                ),
                UVM_MEDIUM)
        end
        else begin
            result_fail_count++;
            `uvm_error("SB/RESULT_MISMATCH",
                $sformatf(
                    "Result compare FAIL: case_id=%0d test_kind=%0d mismatch_count=%0d first_idx=%0d first_row=%0d first_col=%0d exp=%0d act=%0d",
                    item.case_id,
                    item.test_kind,
                    item.mismatch_count,
                    item.first_mismatch_idx,
                    item.first_mismatch_row,
                    item.first_mismatch_col,
                    item.first_expected,
                    item.first_actual
                ))
        end

        result_q.push_back(item);
        try_match_jobs();
    endfunction

    // ------------------------------------------------------------
    // Common expect helpers
    // ------------------------------------------------------------
    function void expect_base_map_item(
        ai_accel_subsys_seq_item item,
        bit [31:0] a_exp,
        bit [31:0] b_exp,
        bit [31:0] c_exp,
        string profile_name
    );
        if (item.base_addr_a !== a_exp) begin
            `uvm_error("SB/BASE_A",
                $sformatf("[%s] base_addr_a mismatch: got=0x%08h exp=0x%08h",
                    profile_name, item.base_addr_a, a_exp))
        end

        if (item.base_addr_b !== b_exp) begin
            `uvm_error("SB/BASE_B",
                $sformatf("[%s] base_addr_b mismatch: got=0x%08h exp=0x%08h",
                    profile_name, item.base_addr_b, b_exp))
        end

        if (item.base_addr_c !== c_exp) begin
            `uvm_error("SB/BASE_C",
                $sformatf("[%s] base_addr_c mismatch: got=0x%08h exp=0x%08h",
                    profile_name, item.base_addr_c, c_exp))
        end
    endfunction

    function void expect_dims_item(
        ai_accel_subsys_seq_item item,
        int unsigned m_exp,
        int unsigned n_exp,
        int unsigned k_exp,
        string profile_name
    );
        if (item.dim_m !== m_exp) begin
            `uvm_error("SB/DIM_M",
                $sformatf("[%s] dim_m mismatch: got=%0d exp=%0d",
                    profile_name, item.dim_m, m_exp))
        end

        if (item.dim_n !== n_exp) begin
            `uvm_error("SB/DIM_N",
                $sformatf("[%s] dim_n mismatch: got=%0d exp=%0d",
                    profile_name, item.dim_n, n_exp))
        end

        if (item.dim_k !== k_exp) begin
            `uvm_error("SB/DIM_K",
                $sformatf("[%s] dim_k mismatch: got=%0d exp=%0d",
                    profile_name, item.dim_k, k_exp))
        end
    endfunction

    // ------------------------------------------------------------
    // Fixed-baseline checks
    // ------------------------------------------------------------
    function void check_fixed_baseline_case(
        ai_accel_subsys_seq_item item,
        int unsigned case_id
    );
        case (case_id)
            0, 1, 2, 3, 4, 5, 6, 7: begin
                expect_base_map_item(item, BASE_A_DEFAULT, BASE_B_DEFAULT, BASE_C_DEFAULT,
                                     $sformatf("fixed_case_%0d", case_id));
                expect_dims_item(item, 4, 4, 4, $sformatf("fixed_case_%0d", case_id));

                ctrl_profile_pass_count++;

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
    function void check_variable_dim_case(
        ai_accel_subsys_seq_item item,
        int unsigned case_id
    );
        expect_base_map_item(item, BASE_A_DEFAULT, BASE_B_DEFAULT, BASE_C_DEFAULT,
                             $sformatf("var_case_%0d", case_id));

        case (case_id)
            100: expect_dims_item(item, 1, 1, 1, "var100");
            101: expect_dims_item(item, 2, 2, 2, "var101");
            102: expect_dims_item(item, 4, 4, 1, "var102");
            103: expect_dims_item(item, 1, 4, 4, "var103");
            104: expect_dims_item(item, 4, 1, 4, "var104");
            105: expect_dims_item(item, 2, 3, 4, "var105");

            // P9F larger-dimension cases for cache-dimension scaling.
            //
            // These cases intentionally exercise dimensions beyond the original
            // <=4 variable-dimension set, while still using the default base map.
            //
            //   190: M=1, N=8, K=8  -> fills B-cache K/N=8 with one A row
            //   191: M=2, N=8, K=8  -> two A rows with B-cache reuse
            //   192: M=3, N=5, K=7  -> non-power-of-two / non-multiple-of-4 tail case
            190: expect_dims_item(item, 1, 8, 8, "var190");
            191: expect_dims_item(item, 2, 8, 8, "var191");
            192: expect_dims_item(item, 3, 5, 7, "var192");

            default: begin
                `uvm_error("SB/VAR_BAD_CASE",
                    $sformatf("Unsupported variable-dimension case_id=%0d", case_id))
                return;
            end
        endcase

        ctrl_profile_pass_count++;

        `uvm_info("SB",
            $sformatf("Matched variable-dimension case %0d", case_id),
            UVM_LOW)
    endfunction

    // ------------------------------------------------------------
    // Configurable-base checks
    // ------------------------------------------------------------
    function void check_configurable_base_case(
        ai_accel_subsys_seq_item item,
        int unsigned case_id
    );
        expect_dims_item(item, 4, 4, 4, $sformatf("cfg_case_%0d", case_id));

        case (case_id)
            400: expect_base_map_item(item, BASE_A_DEFAULT, BASE_B_DEFAULT, BASE_C_DEFAULT, "cfg400");
            401: expect_base_map_item(item, CFG401_BASE_A, CFG401_BASE_B, CFG401_BASE_C, "cfg401");
            402: expect_base_map_item(item, CFG402_BASE_A, CFG402_BASE_B, CFG402_BASE_C, "cfg402");
            403: expect_base_map_item(item, CFG403_BASE_A, CFG403_BASE_B, CFG403_BASE_C, "cfg403");
            default: begin
                `uvm_error("SB/CFG_BAD_CASE",
                    $sformatf("Unsupported configurable-base case_id=%0d", case_id))
                return;
            end
        endcase

        ctrl_profile_pass_count++;

        `uvm_info("SB",
            $sformatf("Matched configurable-base case %0d", case_id),
            UVM_LOW)
    endfunction

    // ------------------------------------------------------------
    // Top-level control-profile check
    //
    // Only DONE-side ctrl items should reach here.
    // ------------------------------------------------------------
    function void check_ctrl_item_profile(ai_accel_subsys_seq_item item);
        if (item == null) begin
            `uvm_error("SB/NOCTRL", "ctrl item is null, cannot check selected profile")
            return;
        end

        case (item.test_kind)
            ai_accel_subsys_seq_item::TEST_KIND_FIXED_BASELINE:
                check_fixed_baseline_case(item, item.case_id);

            ai_accel_subsys_seq_item::TEST_KIND_VARIABLE_DIM_SMOKE:
                check_variable_dim_case(item, item.case_id);

            ai_accel_subsys_seq_item::TEST_KIND_CONFIGURABLE_BASE:
                check_configurable_base_case(item, item.case_id);

            default:
                `uvm_error("SB/BAD_KIND",
                    $sformatf("Unsupported test_kind=%0d for case_id=%0d",
                        item.test_kind, item.case_id))
        endcase
    endfunction

    // ------------------------------------------------------------
    // Helper: check done / latency consistency
    //
    // Only DONE-side ctrl items should reach here.
    // ------------------------------------------------------------
    function void check_ctrl_item_done_latency(ai_accel_subsys_seq_item item);
        int unsigned exp_latency;
    begin
        if (item == null) begin
            `uvm_error("SB/NOCTRL", "ctrl item is null, cannot check done/latency")
            return;
        end

        if (!item.done_seen) begin
            `uvm_error("SB/NODONE", "Scoreboard DONE-side transaction indicates done_seen=0")
            return;
        end

        if (item.done_cycle < item.start_cycle) begin
            `uvm_error("SB/CYCLE_ORDER",
                $sformatf("done_cycle < start_cycle: start=%0d done=%0d",
                    item.start_cycle, item.done_cycle))
        end

        exp_latency = item.done_cycle - item.start_cycle;

        if (item.latency_cycles !== exp_latency) begin
            `uvm_error("SB/LATENCY_MISMATCH",
                $sformatf("latency mismatch: got=%0d exp=%0d (start=%0d done=%0d)",
                    item.latency_cycles, exp_latency,
                    item.start_cycle, item.done_cycle))
        end

        if (item.latency_cycles < MIN_VALID_LATENCY) begin
            `uvm_error("SB/LATENCY_TOO_SMALL",
                $sformatf("latency too small: %0d", item.latency_cycles))
        end

        if (item.latency_cycles > MAX_VALID_LATENCY) begin
            `uvm_error("SB/LATENCY_TOO_LARGE",
                $sformatf("latency too large: %0d", item.latency_cycles))
        end

        ctrl_latency_pass_count++;

        `uvm_info("SB",
            $sformatf("Latency check passed: case_id=%0d start=%0d done=%0d latency=%0d cycles",
                item.case_id, item.start_cycle, item.done_cycle, item.latency_cycles),
            UVM_LOW)
    end
    endfunction

    // ------------------------------------------------------------
    // Pairing check between ctrl/result
    // ------------------------------------------------------------
    function void check_ctrl_result_alignment(
        ai_accel_subsys_seq_item ctrl_item,
        ai_accel_subsys_result_item result_item
    );
        if (ctrl_item.case_id !== result_item.case_id) begin
            `uvm_error("SB/PAIR_CASE_ID",
                $sformatf("ctrl/result case_id mismatch: ctrl=%0d result=%0d",
                    ctrl_item.case_id, result_item.case_id))
        end

        if (ctrl_item.test_kind !== result_item.test_kind) begin
            `uvm_error("SB/PAIR_KIND",
                $sformatf("ctrl/result test_kind mismatch: ctrl=%0d result=%0d",
                    ctrl_item.test_kind, result_item.test_kind))
        end

        if (ctrl_item.base_addr_a !== result_item.base_addr_a) begin
            `uvm_error("SB/PAIR_BASE_A",
                $sformatf("ctrl/result base_addr_a mismatch: ctrl=0x%08h result=0x%08h",
                    ctrl_item.base_addr_a, result_item.base_addr_a))
        end

        if (ctrl_item.base_addr_b !== result_item.base_addr_b) begin
            `uvm_error("SB/PAIR_BASE_B",
                $sformatf("ctrl/result base_addr_b mismatch: ctrl=0x%08h result=0x%08h",
                    ctrl_item.base_addr_b, result_item.base_addr_b))
        end

        if (ctrl_item.base_addr_c !== result_item.base_addr_c) begin
            `uvm_error("SB/PAIR_BASE_C",
                $sformatf("ctrl/result base_addr_c mismatch: ctrl=0x%08h result=0x%08h",
                    ctrl_item.base_addr_c, result_item.base_addr_c))
        end

        if (ctrl_item.dim_m !== result_item.dim_m) begin
            `uvm_error("SB/PAIR_DIM_M",
                $sformatf("ctrl/result dim_m mismatch: ctrl=%0d result=%0d",
                    ctrl_item.dim_m, result_item.dim_m))
        end

        if (ctrl_item.dim_n !== result_item.dim_n) begin
            `uvm_error("SB/PAIR_DIM_N",
                $sformatf("ctrl/result dim_n mismatch: ctrl=%0d result=%0d",
                    ctrl_item.dim_n, result_item.dim_n))
        end

        if (ctrl_item.dim_k !== result_item.dim_k) begin
            `uvm_error("SB/PAIR_DIM_K",
                $sformatf("ctrl/result dim_k mismatch: ctrl=%0d result=%0d",
                    ctrl_item.dim_k, result_item.dim_k))
        end

        ctrl_result_pair_pass_count++;

        `uvm_info("SB",
            $sformatf("Paired ctrl/result job #%0d: case_id=%0d test_kind=%0d",
                matched_job_count + 1, ctrl_item.case_id, ctrl_item.test_kind),
            UVM_LOW)
    endfunction

    // ------------------------------------------------------------
    // Try to pair queued DONE-side ctrl items with result items
    // ------------------------------------------------------------
    function void try_match_jobs();
        ai_accel_subsys_seq_item    ctrl_item;
        ai_accel_subsys_result_item result_item;
    begin
        while ((ctrl_q.size() > 0) && (result_q.size() > 0)) begin
            ctrl_item   = ctrl_q.pop_front();
            result_item = result_q.pop_front();

            check_ctrl_result_alignment(ctrl_item, result_item);
            matched_job_count++;
        end
    end
    endfunction

    // ------------------------------------------------------------
    // Result-path summary check
    // ------------------------------------------------------------
    function void check_result_summary();
        int unsigned expected_completed_count;
    begin
        if (!result_check_enable)
            return;

        expected_completed_count = get_expected_completed_count();

        if (expected_completed_count == 0) begin
            if (observed_result_count != 0) begin
                `uvm_error("SB/UNEXPECTED_RESULT",
                    $sformatf("Expected zero completed jobs, but observed %0d result_item(s)",
                        observed_result_count))
            end

            `uvm_info("SB",
                $sformatf("Result summary: observed=%0d pass=%0d fail=%0d expected_completed=%0d",
                    observed_result_count, result_pass_count, result_fail_count, expected_completed_count),
                UVM_LOW)
            return;
        end

        if (observed_result_count == 0) begin
            `uvm_error("SB/NORESULT",
                "Result checking is enabled, but no result_item was observed")
            return;
        end

        if (observed_result_count != expected_completed_count) begin
            `uvm_error("SB/RESULT_COUNT",
                $sformatf("Result count mismatch: observed=%0d expected_completed=%0d",
                    observed_result_count, expected_completed_count))
        end

        if (result_fail_count != 0) begin
            `uvm_error("SB/RESULT_FAIL_SUMMARY",
                $sformatf("Result compare observed %0d fail item(s)", result_fail_count))
        end

        `uvm_info("SB",
            $sformatf("Result summary: observed=%0d pass=%0d fail=%0d expected_completed=%0d",
                observed_result_count, result_pass_count, result_fail_count, expected_completed_count),
            UVM_LOW)
    end
    endfunction

    // ------------------------------------------------------------
    // Pairing summary check
    // ------------------------------------------------------------
    function void check_pairing_summary();
        int unsigned expected_completed_count;
    begin
        expected_completed_count = get_expected_completed_count();

        if (ctrl_q.size() != 0) begin
            `uvm_error("SB/CTRL_Q_NOT_EMPTY",
                $sformatf("Unpaired DONE-side ctrl items remain in queue: %0d", ctrl_q.size()))
        end

        if (result_q.size() != 0) begin
            `uvm_error("SB/RESULT_Q_NOT_EMPTY",
                $sformatf("Unpaired result items remain in queue: %0d", result_q.size()))
        end

        if (result_check_enable) begin
            if (observed_done_count != observed_result_count) begin
                `uvm_error("SB/CTRL_RESULT_COUNT",
                    $sformatf("DONE/result count mismatch: done=%0d result=%0d",
                        observed_done_count, observed_result_count))
            end
        end

        if (result_check_enable) begin
            if (matched_job_count != observed_done_count) begin
                `uvm_error("SB/MATCH_COUNT",
                    $sformatf("matched job count mismatch: matched=%0d done=%0d",
                        matched_job_count, observed_done_count))
            end
        end

        if (observed_done_count != expected_completed_count) begin
            `uvm_error("SB/EXPECTED_COMPLETED_COUNT",
                $sformatf("completed count mismatch: done=%0d expected_completed=%0d",
                    observed_done_count, expected_completed_count))
        end

        `uvm_info("SB",
            $sformatf("Pairing summary: matched=%0d ctrl_profile_pass=%0d ctrl_latency_pass=%0d ctrl_result_pair_pass=%0d",
                matched_job_count,
                ctrl_profile_pass_count,
                ctrl_latency_pass_count,
                ctrl_result_pair_pass_count),
            UVM_LOW)
    end
    endfunction

    // ------------------------------------------------------------
    // Report phase
    // ------------------------------------------------------------
    function void report_phase(uvm_phase phase);
        int unsigned expected_aborted_count;
        int unsigned expected_completed_count;
        int unsigned observed_aborted_count;

        super.report_phase(phase);

        expected_aborted_count   = get_expected_aborted_count();
        expected_completed_count = get_expected_completed_count();
        observed_aborted_count   = get_observed_aborted_count();

        `uvm_info("SB",
            $sformatf("Control summary: start=%0d completed=%0d",
                observed_start_count, observed_done_count),
            UVM_LOW)

        if (midrun_reset_test_mode) begin
            `uvm_info("SB",
                $sformatf("Abort summary: expected_aborted=%0d observed_aborted=%0d expected_completed=%0d",
                    expected_aborted_count, observed_aborted_count, expected_completed_count),
                UVM_LOW)
        end

        if (observed_start_count == 0) begin
            `uvm_error("SB/NOSTART", "Scoreboard did not observe any acc_start event")
            return;
        end

        if (observed_start_count < expected_aborted_count) begin
            `uvm_error("SB/ABORT_COUNT_BAD",
                $sformatf("observed_start_count=%0d is smaller than expected_aborted_job_count=%0d",
                    observed_start_count, expected_aborted_count))
        end

        if (midrun_reset_test_mode) begin
            if (observed_done_count != expected_completed_count) begin
                `uvm_error("SB/DONE_COUNT",
                    $sformatf("Expected completed count to match (start - expected_aborted), but start=%0d expected_aborted=%0d completed=%0d expected_completed=%0d",
                        observed_start_count,
                        expected_aborted_count,
                        observed_done_count,
                        expected_completed_count))
            end
        end
        else begin
            if (observed_done_count != observed_start_count) begin
                `uvm_error("SB/DONE_COUNT",
                    $sformatf("Expected completed count to match start count, but start=%0d completed=%0d",
                        observed_start_count, observed_done_count))
            end
        end

        check_result_summary();
        check_pairing_summary();
    endfunction

endclass

`endif