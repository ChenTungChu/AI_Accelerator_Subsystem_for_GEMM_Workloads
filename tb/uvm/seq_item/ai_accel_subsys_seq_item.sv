// File: tb/uvm/seq_item/ai_accel_subsys_seq_item.sv
`ifndef AI_ACCEL_SUBSYS_SEQ_ITEM_SV
`define AI_ACCEL_SUBSYS_SEQ_ITEM_SV

class ai_accel_subsys_seq_item extends uvm_sequence_item;

    // ------------------------------------------------------------
    // Test kind
    // ------------------------------------------------------------
    typedef enum int {
        TEST_KIND_FIXED_BASELINE        = 0,
        TEST_KIND_VARIABLE_DIM_SMOKE    = 1,
        TEST_KIND_CONFIGURABLE_BASE     = 2,
        TEST_KIND_BACK_TO_BACK_SMOKE    = 3,
        TEST_KIND_RESET_RECOVERY_SMOKE  = 4,
        TEST_KIND_C_RMW_ACCUM_RECIPE   = 5
    } test_kind_e;

    // ------------------------------------------------------------
    // Control event kind
    //
    // Same ctrl path, now phase-aware.
    //
    // CTRL_EVENT_NONE:
    //   profile-only / request-style item
    //
    // CTRL_EVENT_START:
    //   monitor observed acc_start
    //
    // CTRL_EVENT_DONE:
    //   monitor observed acc_done
    // ------------------------------------------------------------
    typedef enum int {
        CTRL_EVENT_NONE  = 0,
        CTRL_EVENT_START = 1,
        CTRL_EVENT_DONE  = 2
    } ctrl_event_kind_e;

    // ------------------------------------------------------------
    // Basic control fields
    // ------------------------------------------------------------
    rand int unsigned case_id;
    rand test_kind_e  test_kind;

    // ------------------------------------------------------------
    // GEMM runtime configuration
    // ------------------------------------------------------------
    rand bit [31:0] base_addr_a;
    rand bit [31:0] base_addr_b;
    rand bit [31:0] base_addr_c;

    rand int unsigned dim_m;
    rand int unsigned dim_n;
    rand int unsigned dim_k;

    // ------------------------------------------------------------
    // Optional metadata
    // ------------------------------------------------------------
    string test_name;

    // ------------------------------------------------------------
    // C RMW accumulation recipe metadata
    //
    // C RMW accumulation recipes are multi-job software/testbench recipes.  The
    // recipe case_id describes the full logical GEMM shape, while
    // each partial job uses compact A/B payloads with dim_k equal to
    // the current K partition.
    // ------------------------------------------------------------
    rand bit          accumulate_enable;
    rand int unsigned recipe_job_idx;
    rand int unsigned recipe_job_count;
    rand int unsigned recipe_k_total;
    rand int unsigned recipe_k_base;
    rand int unsigned recipe_k_part;

    // ------------------------------------------------------------
    // Control-event metadata
    // ------------------------------------------------------------
    ctrl_event_kind_e ctrl_event_kind;

    bit          done_seen;
    int unsigned start_cycle;
    int unsigned done_cycle;
    int unsigned latency_cycles;

    // ------------------------------------------------------------
    // Constraints
    // ------------------------------------------------------------
    constraint c_dims_valid {
        dim_m inside {[1:255]};
        dim_n inside {[1:255]};
        dim_k inside {[1:255]};
    }

    constraint c_base_addr_aligned {
        base_addr_a[1:0] == 2'b00;
        base_addr_b[1:0] == 2'b00;
        base_addr_c[1:0] == 2'b00;
    }

    // Keep first-step configurable-base cases clean and non-overlapping
    constraint c_base_addr_ordered {
        base_addr_a < base_addr_b;
        base_addr_b < base_addr_c;
    }

    // ------------------------------------------------------------
    // UVM automation
    // ------------------------------------------------------------
    `uvm_object_utils_begin(ai_accel_subsys_seq_item)
        `uvm_field_int(case_id, UVM_DEFAULT)
        `uvm_field_enum(test_kind_e, test_kind, UVM_DEFAULT)

        `uvm_field_int(base_addr_a, UVM_DEFAULT | UVM_HEX)
        `uvm_field_int(base_addr_b, UVM_DEFAULT | UVM_HEX)
        `uvm_field_int(base_addr_c, UVM_DEFAULT | UVM_HEX)

        `uvm_field_int(dim_m, UVM_DEFAULT)
        `uvm_field_int(dim_n, UVM_DEFAULT)
        `uvm_field_int(dim_k, UVM_DEFAULT)

        `uvm_field_string(test_name, UVM_DEFAULT)

        `uvm_field_int(accumulate_enable, UVM_DEFAULT)
        `uvm_field_int(recipe_job_idx, UVM_DEFAULT)
        `uvm_field_int(recipe_job_count, UVM_DEFAULT)
        `uvm_field_int(recipe_k_total, UVM_DEFAULT)
        `uvm_field_int(recipe_k_base, UVM_DEFAULT)
        `uvm_field_int(recipe_k_part, UVM_DEFAULT)

        `uvm_field_enum(ctrl_event_kind_e, ctrl_event_kind, UVM_DEFAULT)
        `uvm_field_int(done_seen, UVM_DEFAULT)
        `uvm_field_int(start_cycle, UVM_DEFAULT)
        `uvm_field_int(done_cycle, UVM_DEFAULT)
        `uvm_field_int(latency_cycles, UVM_DEFAULT)
    `uvm_object_utils_end

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_seq_item");
        super.new(name);

        case_id   = 0;
        test_kind = TEST_KIND_FIXED_BASELINE;

        base_addr_a = 32'h0000_0000;
        base_addr_b = 32'h0000_0100;
        base_addr_c = 32'h0000_0200;

        dim_m = 4;
        dim_n = 4;
        dim_k = 4;

        test_name = "";

        clear_c_rmw_accum_metadata();
        clear_ctrl_event();
    endfunction

    // ------------------------------------------------------------
    // Clear C RMW accumulation metadata
    // ------------------------------------------------------------
    function void clear_c_rmw_accum_metadata();
        accumulate_enable = 1'b0;
        recipe_job_idx    = 0;
        recipe_job_count  = 1;
        recipe_k_total    = 0;
        recipe_k_base     = 0;
        recipe_k_part     = 0;
    endfunction

    // ------------------------------------------------------------
    // C RMW accumulation recipe shape helpers
    // ------------------------------------------------------------
    function bit is_c_rmw_accum_recipe_case(int unsigned id);
        return ((id >= 208) && (id <= 212));
    endfunction

    function void get_c_rmw_accum_recipe_shape(
        input  int unsigned id,
        output int unsigned m_out,
        output int unsigned n_out,
        output int unsigned k_total_out
    );
        case (id)
            208: begin m_out = 1; n_out = 4;  k_total_out = 16; end
            209: begin m_out = 4; n_out = 4;  k_total_out = 16; end
            210: begin m_out = 4; n_out = 16; k_total_out = 16; end
            211: begin m_out = 8; n_out = 16; k_total_out = 16; end
            212: begin m_out = 5; n_out = 9;  k_total_out = 9;  end
            default: begin m_out = 1; n_out = 1;  k_total_out = 1;  end
        endcase
    endfunction

    function int unsigned get_c_rmw_accum_recipe_job_count(int unsigned id);
        if (is_c_rmw_accum_recipe_case(id))
            return 2;
        return 1;
    endfunction

    function void get_c_rmw_accum_recipe_job_info(
        input  int unsigned id,
        input  int unsigned job_idx,
        output int unsigned k_base_out,
        output int unsigned k_part_out,
        output bit          accumulate_enable_out
    );
        int unsigned k_total_local;
        int unsigned m_unused;
        int unsigned n_unused;
    begin
        get_c_rmw_accum_recipe_shape(id, m_unused, n_unused, k_total_local);

        accumulate_enable_out = (job_idx != 0);

        case (id)
            208, 209, 210, 211: begin
                if (job_idx == 0) begin
                    k_base_out = 0;
                    k_part_out = 8;
                end
                else begin
                    k_base_out = 8;
                    k_part_out = 8;
                end
            end

            212: begin
                if (job_idx == 0) begin
                    k_base_out = 0;
                    k_part_out = 8;
                end
                else begin
                    k_base_out = 8;
                    k_part_out = 1;
                end
            end

            default: begin
                k_base_out = 0;
                k_part_out = k_total_local;
                accumulate_enable_out = 1'b0;
            end
        endcase
    end
    endfunction

    // ------------------------------------------------------------
    // Clear control-event fields
    // ------------------------------------------------------------
    function void clear_ctrl_event();
        ctrl_event_kind = CTRL_EVENT_NONE;
        done_seen       = 1'b0;
        start_cycle     = 0;
        done_cycle      = 0;
        latency_cycles  = 0;
    endfunction

    // ------------------------------------------------------------
    // Mark START event
    // ------------------------------------------------------------
    function void mark_start_event(
        input int unsigned start_cycle_in
    );
        ctrl_event_kind = CTRL_EVENT_START;
        done_seen       = 1'b0;
        start_cycle     = start_cycle_in;
        done_cycle      = 0;
        latency_cycles  = 0;
    endfunction

    // ------------------------------------------------------------
    // Mark DONE event
    // ------------------------------------------------------------
    function void mark_done_event(
        input int unsigned start_cycle_in,
        input int unsigned done_cycle_in
    );
        ctrl_event_kind = CTRL_EVENT_DONE;
        done_seen       = 1'b1;
        start_cycle     = start_cycle_in;
        done_cycle      = done_cycle_in;

        if (done_cycle_in >= start_cycle_in)
            latency_cycles = done_cycle_in - start_cycle_in;
        else
            latency_cycles = 0;
    endfunction

    // ------------------------------------------------------------
    // Helper predicates
    // ------------------------------------------------------------
    function bit is_ctrl_event();
        return (ctrl_event_kind != CTRL_EVENT_NONE);
    endfunction

    function bit is_ctrl_start_event();
        return (ctrl_event_kind == CTRL_EVENT_START);
    endfunction

    function bit is_ctrl_done_event();
        return (ctrl_event_kind == CTRL_EVENT_DONE);
    endfunction

    // ------------------------------------------------------------
    // Helper: apply one of the known non-UVM baseline profiles
    // ------------------------------------------------------------
    function void apply_fixed_baseline_case(int unsigned id);
        case_id   = id;
        test_kind = TEST_KIND_FIXED_BASELINE;
        test_name = $sformatf("fixed_baseline_case_%0d", id);

        base_addr_a = 32'h0000_0000;
        base_addr_b = 32'h0000_0100;
        base_addr_c = 32'h0000_0200;

        dim_m = 4;
        dim_n = 4;
        dim_k = 4;

        clear_c_rmw_accum_metadata();
        clear_ctrl_event();
    endfunction

    function void apply_variable_dim_case(int unsigned id);
        case_id   = id;
        test_kind = TEST_KIND_VARIABLE_DIM_SMOKE;
        test_name = $sformatf("variable_dim_case_%0d", id);

        base_addr_a = 32'h0000_0000;
        base_addr_b = 32'h0000_0100;
        base_addr_c = 32'h0000_0200;

        case (id)
            100: begin dim_m = 1; dim_n = 1; dim_k = 1; end
            101: begin dim_m = 2; dim_n = 2; dim_k = 2; end
            102: begin dim_m = 4; dim_n = 4; dim_k = 1; end
            103: begin dim_m = 1; dim_n = 4; dim_k = 4; end
            104: begin dim_m = 4; dim_n = 1; dim_k = 4; end
            105: begin dim_m = 2; dim_n = 3; dim_k = 4; end

            // P9F larger-dimension variable cases.
            // They intentionally remain in the existing 100~199
            // variable-dimension CASE_ID range, so smoke_test
            // infer_test_kind() does not need a new CASE_ID class.
            190: begin dim_m = 1; dim_n = 8; dim_k = 8; end
            191: begin dim_m = 2; dim_n = 8; dim_k = 8; end
            192: begin dim_m = 3; dim_n = 5; dim_k = 7; end

            // P10C K>8 software-reference / test-case support.
            // These cases intentionally exceed the P9 cache-fit K<=8 class
            // and are used to prepare the UVM case database, payload builder,
            // scoreboard profile checks, and software reference model before
            // enabling the P10 tiled RTL datapath.
            193: begin dim_m = 1; dim_n = 4; dim_k = 16; end
            194: begin dim_m = 2; dim_n = 4; dim_k = 16; end
            195: begin dim_m = 4; dim_n = 4; dim_k = 16; end
            196: begin dim_m = 3; dim_n = 5; dim_k = 9;  end
            197: begin dim_m = 4; dim_n = 4; dim_k = 12; end

            // P11C N>8 software-reference / test-case support.
            // These cases prepare the UVM case database, payload builder,
            // scoreboard profile checks, and software reference model before
            // enabling the P11 N-tile scheduler RTL.
            198: begin dim_m = 1; dim_n = 16; dim_k = 8;  end
            199: begin dim_m = 2; dim_n = 16; dim_k = 8;  end
            200: begin dim_m = 4; dim_n = 16; dim_k = 16; end
            201: begin dim_m = 3; dim_n = 9;  dim_k = 9;  end
            202: begin dim_m = 4; dim_n = 12; dim_k = 16; end

            // P12C M>4 software-reference / test-case support.
            // These cases prepare the UVM case database, payload builder,
            // scoreboard profile checks, and software reference model before
            // enabling the P12 multi-row M-tile scheduler RTL.
            203: begin dim_m = 8; dim_n = 8;  dim_k = 8;  end
            204: begin dim_m = 8; dim_n = 16; dim_k = 8;  end
            205: begin dim_m = 8; dim_n = 16; dim_k = 16; end
            206: begin dim_m = 5; dim_n = 9;  dim_k = 9;  end
            207: begin dim_m = 7; dim_n = 12; dim_k = 16; end

            default: begin dim_m = 1; dim_n = 1; dim_k = 1; end
        endcase

        clear_c_rmw_accum_metadata();
        clear_ctrl_event();
    endfunction

    function void apply_configurable_base_case(int unsigned id);
        case_id   = id;
        test_kind = TEST_KIND_CONFIGURABLE_BASE;
        test_name = $sformatf("config_base_case_%0d", id);

        dim_m = 4;
        dim_n = 4;
        dim_k = 4;

        case (id)
            400: begin
                base_addr_a = 32'h0000_0000;
                base_addr_b = 32'h0000_0100;
                base_addr_c = 32'h0000_0200;
            end
            401: begin
                base_addr_a = 32'h0000_0040;
                base_addr_b = 32'h0000_0140;
                base_addr_c = 32'h0000_0240;
            end
            402: begin
                base_addr_a = 32'h0000_0080;
                base_addr_b = 32'h0000_0180;
                base_addr_c = 32'h0000_0280;
            end
            403: begin
                base_addr_a = 32'h0000_0020;
                base_addr_b = 32'h0000_0060;
                base_addr_c = 32'h0000_00A0;
            end
            default: begin
                base_addr_a = 32'h0000_0000;
                base_addr_b = 32'h0000_0100;
                base_addr_c = 32'h0000_0200;
            end
        endcase

        clear_c_rmw_accum_metadata();
        clear_ctrl_event();
    endfunction

    // ------------------------------------------------------------
    // Apply C RMW accumulation recipe profile
    // ------------------------------------------------------------
    function void apply_c_rmw_accum_recipe_case(int unsigned id);
        int unsigned m_tmp;
        int unsigned n_tmp;
        int unsigned k_tmp;

        case_id   = id;
        test_kind = TEST_KIND_C_RMW_ACCUM_RECIPE;
        test_name = $sformatf("c_rmw_accum_recipe_%0d", id);

        base_addr_a = 32'h0000_0000;
        base_addr_b = 32'h0000_0100;
        base_addr_c = 32'h0000_0200;

        get_c_rmw_accum_recipe_shape(id, m_tmp, n_tmp, k_tmp);

        dim_m = m_tmp;
        dim_n = n_tmp;
        dim_k = k_tmp;

        clear_c_rmw_accum_metadata();
        recipe_job_count = get_c_rmw_accum_recipe_job_count(id);
        recipe_k_total   = k_tmp;
        recipe_k_part    = k_tmp;

        clear_ctrl_event();
    endfunction

    // ------------------------------------------------------------
    // Apply one C RMW accumulation partial-job profile
    // ------------------------------------------------------------
    function void apply_c_rmw_accum_job_case(
        int unsigned id,
        int unsigned job_idx_in
    );
        int unsigned m_tmp;
        int unsigned n_tmp;
        int unsigned k_total_tmp;
        int unsigned k_base_tmp;
        int unsigned k_part_tmp;
        bit          accum_tmp;

        case_id   = id;
        test_kind = TEST_KIND_C_RMW_ACCUM_RECIPE;

        base_addr_a = 32'h0000_0000;
        base_addr_b = 32'h0000_0100;
        base_addr_c = 32'h0000_0200;

        get_c_rmw_accum_recipe_shape(id, m_tmp, n_tmp, k_total_tmp);
        get_c_rmw_accum_recipe_job_info(id, job_idx_in, k_base_tmp, k_part_tmp, accum_tmp);

        dim_m = m_tmp;
        dim_n = n_tmp;
        dim_k = k_part_tmp;

        accumulate_enable = accum_tmp;
        recipe_job_idx    = job_idx_in;
        recipe_job_count  = get_c_rmw_accum_recipe_job_count(id);
        recipe_k_total    = k_total_tmp;
        recipe_k_base     = k_base_tmp;
        recipe_k_part     = k_part_tmp;

        test_name = $sformatf("c_rmw_accum_recipe_%0d_job_%0d_of_%0d_kbase_%0d_kpart_%0d_accum_%0d",
            id,
            recipe_job_idx,
            recipe_job_count,
            recipe_k_base,
            recipe_k_part,
            accumulate_enable);

        clear_ctrl_event();
    endfunction

    // ------------------------------------------------------------
    // Pretty print helper
    // ------------------------------------------------------------
    virtual function string convert2string();
        return $sformatf(
            "test_name=%s case_id=%0d kind=%0d base_a=0x%08h base_b=0x%08h base_c=0x%08h dim_m=%0d dim_n=%0d dim_k=%0d accumulate_enable=%0d recipe_job_idx=%0d recipe_job_count=%0d recipe_k_total=%0d recipe_k_base=%0d recipe_k_part=%0d ctrl_event_kind=%0d done_seen=%0d start_cycle=%0d done_cycle=%0d latency_cycles=%0d",
            test_name,
            case_id,
            test_kind,
            base_addr_a,
            base_addr_b,
            base_addr_c,
            dim_m,
            dim_n,
            dim_k,
            accumulate_enable,
            recipe_job_idx,
            recipe_job_count,
            recipe_k_total,
            recipe_k_base,
            recipe_k_part,
            ctrl_event_kind,
            done_seen,
            start_cycle,
            done_cycle,
            latency_cycles
        );
    endfunction

endclass

`endif
