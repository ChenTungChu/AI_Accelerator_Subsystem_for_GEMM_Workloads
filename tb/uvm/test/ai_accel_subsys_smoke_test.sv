// File: tb/uvm/test/ai_accel_subsys_smoke_test.sv
// C_RMW_ACCUM_SANITY: this replacement file contains class ai_accel_subsys_c_rmw_accum_dut_test and its factory registration.
`ifndef AI_ACCEL_SUBSYS_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_SMOKE_TEST_SV

// ------------------------------------------------------------
// Smoke test
//
// This is the base single-job subsystem test.
//
// Main responsibilities:
//   - decode CASE_ID into one supported test profile
//   - prepare expected data and pre-start memory setup
//   - launch the subsystem control sequence
//   - collect post-done data and publish compare payload
//
// Memory path policy:
//   - default path  = host agent
//   - fallback path = helper
//
// Helper remains available for fallback / debug, but is no
// longer the primary path.
// ------------------------------------------------------------

class ai_accel_subsys_smoke_test extends uvm_test;
    `uvm_component_utils(ai_accel_subsys_smoke_test)

    // ------------------------------------------------------------
    // AXI host vif typedef
    //   Must match ai_accel_subsys_uvm_top.sv
    // ------------------------------------------------------------
    typedef virtual axi_mm_if #(
        .ADDR_WIDTH (32),
        .DATA_WIDTH (64),
        .ID_WIDTH   (4),
        .HAS_BURST  (1)
    ) axi0_vif_t;

    // ------------------------------------------------------------
    // Components / helpers
    // ------------------------------------------------------------
    ai_accel_subsys_env             env;
    ai_accel_subsys_case_helper     case_helper;
    ai_accel_subsys_axi_host_helper axi_host_helper;

    // ------------------------------------------------------------
    // Virtual interfaces
    // ------------------------------------------------------------
    virtual ai_accel_subsys_ctrl_if vif;
    axi0_vif_t                      axi0_vif;

    // ------------------------------------------------------------
    // Constants
    // ------------------------------------------------------------
    localparam int unsigned DEFAULT_DONE_TIMEOUT_CYCLES = 20000;
    localparam int unsigned DEFAULT_CASE_ID             = 0;

    // ------------------------------------------------------------
    // Selected test configuration
    // ------------------------------------------------------------
    int unsigned selected_case_id;
    ai_accel_subsys_seq_item::test_kind_e selected_test_kind;
    int unsigned done_timeout_cycles;

    // ------------------------------------------------------------
    // Result check / memory path policy
    //
    // Policy B:
    //   - ENABLE_RESULT_CHECK=1
    //       -> default memory path uses host agent
    //   - FORCE_HELPER_MEM_PATH=1
    //       -> force helper fallback path
    //
    // Legacy per-path knobs are still kept for path-level debug,
    // but they are not the normal way to run the test.
    // ------------------------------------------------------------
    bit enable_result_check;
    bit force_helper_mem_path;

    bit use_host_agent_clear_c;
    bit use_host_agent_readback_c;
    bit use_host_agent_preload_ab;

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_smoke_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // ------------------------------------------------------------
    // Infer test kind from case id
    // ------------------------------------------------------------
    function automatic ai_accel_subsys_seq_item::test_kind_e infer_test_kind(
        input int unsigned case_id
    );
        if (case_id <= 99) begin
            return ai_accel_subsys_seq_item::TEST_KIND_FIXED_BASELINE;
        end
        else if ((case_id >= 100) && (case_id <= 207)) begin
            return ai_accel_subsys_seq_item::TEST_KIND_VARIABLE_DIM_SMOKE;
        end
        else if ((case_id >= 208) && (case_id <= 212)) begin
            return ai_accel_subsys_seq_item::TEST_KIND_C_RMW_ACCUM_RECIPE;
        end
        else if ((case_id >= 400) && (case_id <= 499)) begin
            return ai_accel_subsys_seq_item::TEST_KIND_CONFIGURABLE_BASE;
        end
        else begin
            `uvm_fatal("TEST/BADCASE",
                $sformatf("Unsupported CASE_ID=%0d for current smoke test", case_id))
            return ai_accel_subsys_seq_item::TEST_KIND_FIXED_BASELINE;
        end
    endfunction

    // ------------------------------------------------------------
    // Parse test selection
    // ------------------------------------------------------------
    function void parse_test_selection();
        if (!$value$plusargs("CASE_ID=%d", selected_case_id)) begin
            selected_case_id = DEFAULT_CASE_ID;
        end

        selected_test_kind = infer_test_kind(selected_case_id);

        `uvm_info("SMOKE_TEST",
            $sformatf("Selected CASE_ID=%0d, inferred test_kind=%0d",
                selected_case_id, selected_test_kind),
            UVM_MEDIUM)
    endfunction

    // ------------------------------------------------------------
    // Parse smoke done timeout
    //
    // Default:
    //   DEFAULT_DONE_TIMEOUT_CYCLES
    //
    // Override:
    //   +SMOKE_DONE_TIMEOUT_CYCLES=<cycles>
    // ------------------------------------------------------------
    function void parse_done_timeout_cycles();
        int unsigned tmp;
    begin
        done_timeout_cycles = DEFAULT_DONE_TIMEOUT_CYCLES;

        if ($value$plusargs("SMOKE_DONE_TIMEOUT_CYCLES=%d", tmp)) begin
            if (tmp == 0) begin
                `uvm_warning("SMOKE_TEST/BAD_TIMEOUT",
                    "SMOKE_DONE_TIMEOUT_CYCLES=0 is invalid; using default timeout")
            end
            else begin
                done_timeout_cycles = tmp;
            end
        end

        `uvm_info("SMOKE_TEST",
            $sformatf("done_timeout_cycles=%0d", done_timeout_cycles),
            UVM_MEDIUM)
    end
    endfunction

    // ------------------------------------------------------------
    // Parse result-check enable
    //
    // When enabled, smoke_test prepares expected data, performs
    // post-done readback, and publishes compare payload to the
    // scoreboard.
    // ------------------------------------------------------------
    function void parse_result_check_enable();
        int unsigned tmp;
    begin
        enable_result_check = 1'b0;

        if ($value$plusargs("ENABLE_RESULT_CHECK=%d", tmp)) begin
            enable_result_check = (tmp != 0);
        end

        `uvm_info("SMOKE_TEST",
            $sformatf("enable_result_check=%0d", enable_result_check),
            UVM_MEDIUM)
    end
    endfunction

    // ------------------------------------------------------------
    // Parse helper-fallback force knob
    // ------------------------------------------------------------
    function void parse_force_helper_mem_path_enable();
        int unsigned tmp;
    begin
        force_helper_mem_path = 1'b0;

        if ($value$plusargs("FORCE_HELPER_MEM_PATH=%d", tmp)) begin
            force_helper_mem_path = (tmp != 0);
        end

        if (force_helper_mem_path && !enable_result_check) begin
            `uvm_warning("SMOKE_TEST/FORCE_HELPER_UNUSED",
                "FORCE_HELPER_MEM_PATH=1 but enable_result_check=0, so memory-path policy is not exercised")
        end

        `uvm_info("SMOKE_TEST",
            $sformatf("force_helper_mem_path=%0d", force_helper_mem_path),
            UVM_MEDIUM)
    end
    endfunction

    // ------------------------------------------------------------
    // Default policy for one mem path
    // ------------------------------------------------------------
    function bit default_use_host_agent_mem_path();
    begin
        if (!enable_result_check)
            return 1'b0;

        if (force_helper_mem_path)
            return 1'b0;

        return 1'b1;
    end
    endfunction

    // ------------------------------------------------------------
    // Helper: any mem path currently uses host agent
    // ------------------------------------------------------------
    function bit any_host_agent_mem_path_enabled();
    begin
        return (use_host_agent_clear_c ||
                use_host_agent_readback_c ||
                use_host_agent_preload_ab);
    end
    endfunction

    // ------------------------------------------------------------
    // Parse optional clear-C path override
    // ------------------------------------------------------------
    function void parse_host_agent_clear_c_enable();
        int unsigned tmp;
        int unsigned force_tmp;
        bit          explicit_override;
    begin
        explicit_override = 1'b0;

        if ($value$plusargs("FORCE_HELPER_MEM_PATH=%d", force_tmp)) begin
            force_helper_mem_path = (force_tmp != 0);
        end

        use_host_agent_clear_c = default_use_host_agent_mem_path();

        if ($value$plusargs("USE_HOST_AGENT_CLEAR_C=%d", tmp)) begin
            use_host_agent_clear_c = (tmp != 0);
            explicit_override      = 1'b1;
        end

        if (explicit_override && force_helper_mem_path) begin
            `uvm_warning("SMOKE_TEST/CLEAR_POLICY_MIXED",
                "FORCE_HELPER_MEM_PATH=1 together with USE_HOST_AGENT_CLEAR_C override; explicit per-path override takes precedence")
        end

        if (use_host_agent_clear_c && !enable_result_check) begin
            `uvm_warning("SMOKE_TEST/HOST_CLEAR_UNUSED",
                "USE_HOST_AGENT_CLEAR_C resolves to 1 but enable_result_check=0, so clear-C path will not be exercised")
        end

        `uvm_info("SMOKE_TEST",
            $sformatf("use_host_agent_clear_c=%0d", use_host_agent_clear_c),
            UVM_MEDIUM)
    end
    endfunction

    // ------------------------------------------------------------
    // Parse optional readback-C path override
    // ------------------------------------------------------------
    function void parse_host_agent_readback_c_enable();
        int unsigned tmp;
        int unsigned force_tmp;
        bit          explicit_override;
    begin
        explicit_override = 1'b0;

        if ($value$plusargs("FORCE_HELPER_MEM_PATH=%d", force_tmp)) begin
            force_helper_mem_path = (force_tmp != 0);
        end

        use_host_agent_readback_c = default_use_host_agent_mem_path();

        if ($value$plusargs("USE_HOST_AGENT_READBACK_C=%d", tmp)) begin
            use_host_agent_readback_c = (tmp != 0);
            explicit_override         = 1'b1;
        end

        if (explicit_override && force_helper_mem_path) begin
            `uvm_warning("SMOKE_TEST/READBACK_POLICY_MIXED",
                "FORCE_HELPER_MEM_PATH=1 together with USE_HOST_AGENT_READBACK_C override; explicit per-path override takes precedence")
        end

        if (use_host_agent_readback_c && !enable_result_check) begin
            `uvm_warning("SMOKE_TEST/HOST_READBACK_UNUSED",
                "USE_HOST_AGENT_READBACK_C resolves to 1 but enable_result_check=0, so readback-C path will not be exercised")
        end

        `uvm_info("SMOKE_TEST",
            $sformatf("use_host_agent_readback_c=%0d", use_host_agent_readback_c),
            UVM_MEDIUM)
    end
    endfunction

    // ------------------------------------------------------------
    // Parse optional preload-A/B path override
    // ------------------------------------------------------------
    function void parse_host_agent_preload_ab_enable();
        int unsigned tmp;
        int unsigned force_tmp;
        bit          explicit_override;
    begin
        explicit_override = 1'b0;

        if ($value$plusargs("FORCE_HELPER_MEM_PATH=%d", force_tmp)) begin
            force_helper_mem_path = (force_tmp != 0);
        end

        use_host_agent_preload_ab = default_use_host_agent_mem_path();

        if ($value$plusargs("USE_HOST_AGENT_PRELOAD_AB=%d", tmp)) begin
            use_host_agent_preload_ab = (tmp != 0);
            explicit_override         = 1'b1;
        end

        if (explicit_override && force_helper_mem_path) begin
            `uvm_warning("SMOKE_TEST/PRELOAD_POLICY_MIXED",
                "FORCE_HELPER_MEM_PATH=1 together with USE_HOST_AGENT_PRELOAD_AB override; explicit per-path override takes precedence")
        end

        if (use_host_agent_preload_ab && !enable_result_check) begin
            `uvm_warning("SMOKE_TEST/HOST_PRELOAD_UNUSED",
                "USE_HOST_AGENT_PRELOAD_AB resolves to 1 but enable_result_check=0, so preload-A/B path will not be exercised")
        end

        `uvm_info("SMOKE_TEST",
            $sformatf("use_host_agent_preload_ab=%0d", use_host_agent_preload_ab),
            UVM_MEDIUM)
    end
    endfunction

    // ------------------------------------------------------------
    // Build a temporary profile item from selected_case_id /
    // selected_test_kind so we reuse the same case mapping logic.
    // ------------------------------------------------------------
    function ai_accel_subsys_seq_item build_selected_profile_item();
        ai_accel_subsys_seq_item item;

        item = ai_accel_subsys_seq_item::type_id::create("profile_item");

        case (selected_test_kind)
            ai_accel_subsys_seq_item::TEST_KIND_FIXED_BASELINE:
                item.apply_fixed_baseline_case(selected_case_id);

            ai_accel_subsys_seq_item::TEST_KIND_VARIABLE_DIM_SMOKE:
                item.apply_variable_dim_case(selected_case_id);

            ai_accel_subsys_seq_item::TEST_KIND_CONFIGURABLE_BASE:
                item.apply_configurable_base_case(selected_case_id);

            ai_accel_subsys_seq_item::TEST_KIND_C_RMW_ACCUM_RECIPE:
                item.apply_c_rmw_accum_recipe_case(selected_case_id);

            default:
                `uvm_fatal("TEST/BAD_KIND",
                    $sformatf("Unsupported selected_test_kind=%0d for CASE_ID=%0d",
                        selected_test_kind, selected_case_id))
        endcase

        return item;
    endfunction

    // ------------------------------------------------------------
    // Helper: current path names
    // ------------------------------------------------------------
    function string get_clear_c_path_name();
        if (use_host_agent_clear_c)
            return "host_agent";
        else
            return "helper";
    endfunction

    function string get_readback_c_path_name();
        if (use_host_agent_readback_c)
            return "host_agent";
        else
            return "helper";
    endfunction

    function string get_preload_ab_path_name();
        if (use_host_agent_preload_ab)
            return "host_agent";
        else
            return "helper";
    endfunction

    // ------------------------------------------------------------
    // Publish result vectors to scoreboard through result_bridge
    // ------------------------------------------------------------
    task automatic publish_result_to_scoreboard(
        input int signed expected_c[],
        input int signed actual_c[]
    );
        ai_accel_subsys_seq_item profile_item;
    begin
        if (env == null) begin
            `uvm_fatal("TEST/NOENV",
                "env is null in publish_result_to_scoreboard()")
        end

        if (env.result_bridge == null) begin
            `uvm_fatal("TEST/NOBRIDGE",
                "env.result_bridge is null in publish_result_to_scoreboard()")
        end

        profile_item = build_selected_profile_item();

        `uvm_info("SMOKE_TEST",
            $sformatf("Publishing result payload for CASE_ID=%0d test_kind=%0d",
                profile_item.case_id, profile_item.test_kind),
            UVM_MEDIUM)

        env.result_bridge.publish_case_result(
            profile_item.case_id,
            profile_item.test_kind,
            profile_item.test_name,

            profile_item.base_addr_a,
            profile_item.base_addr_b,
            profile_item.base_addr_c,

            profile_item.dim_m,
            profile_item.dim_n,
            profile_item.dim_k,

            expected_c,
            actual_c
        );
    end
    endtask

    // ------------------------------------------------------------
    // Clear C region before acc_start
    // ------------------------------------------------------------
    task automatic clear_c_region_pre_start(
        input ai_accel_subsys_seq_item profile_item,
        input int unsigned             c_elems
    );
        axi_mm_host_seq      host_seq;
        axi_mm_host_seq_item rsp_item;
    begin
        if (!use_host_agent_clear_c) begin
            axi_host_helper.clear_u32_region(profile_item.base_addr_c, c_elems);
            return;
        end

        if (env == null) begin
            `uvm_fatal("SMOKE_TEST/NOENV",
                "env is null in clear_c_region_pre_start()")
        end

        if (env.host_agent == null) begin
            `uvm_fatal("SMOKE_TEST/NOHOSTAGENT",
                "env.host_agent is null in clear_c_region_pre_start()")
        end

        if (env.host_agent.sequencer == null) begin
            `uvm_fatal("SMOKE_TEST/NOHOSTSEQ",
                "env.host_agent.sequencer is null; host-agent path is selected for clear-C")
        end

        host_seq = axi_mm_host_seq::type_id::create("host_clear_c_seq");

        host_seq.set_enable_log(1'b1);
        host_seq.set_case_context(
            profile_item.case_id,
            profile_item.test_kind,
            profile_item.test_name,
            0
        );

        host_seq.queue_clear_c(profile_item.base_addr_c, c_elems);

        env.set_host_case_context(
            profile_item.case_id,
            profile_item.test_kind,
            profile_item.test_name,
            0
        );

        `uvm_info("SMOKE_TEST",
            $sformatf("Clearing C via host_agent: case_id=%0d test_kind=%0d addr=0x%08h words=%0d",
                profile_item.case_id,
                profile_item.test_kind,
                profile_item.base_addr_c,
                c_elems),
            UVM_MEDIUM)

        host_seq.start(env.host_agent.sequencer);

        env.clear_host_case_context();

        if (host_seq.get_response_count() != 1) begin
            `uvm_fatal("SMOKE_TEST/HOST_CLEAR_RSP_COUNT",
                $sformatf("Expected 1 host clear-C response, got %0d",
                    host_seq.get_response_count()))
        end

        rsp_item = host_seq.get_response_item(0);
        if (rsp_item == null) begin
            `uvm_fatal("SMOKE_TEST/HOST_CLEAR_NULL_RSP",
                "Host clear-C response item is null")
        end

        if (!rsp_item.response_valid) begin
            `uvm_fatal("SMOKE_TEST/HOST_CLEAR_BAD_RSP",
                "Host clear-C response_valid=0")
        end
    end
    endtask

    // ------------------------------------------------------------
    // Preload A/B before acc_start
    // ------------------------------------------------------------
    task automatic preload_ab_pre_start(
        input ai_accel_subsys_seq_item profile_item,
        input int signed               a_flat[],
        input int signed               b_flat[]
    );
        axi_mm_host_seq      host_seq;
        axi_mm_host_seq_item rsp_item;
    begin
        if (!use_host_agent_preload_ab) begin
            axi_host_helper.preload_u8_vector(profile_item.base_addr_a, a_flat);
            axi_host_helper.preload_u8_vector(profile_item.base_addr_b, b_flat);
            return;
        end

        if (env == null) begin
            `uvm_fatal("SMOKE_TEST/NOENV",
                "env is null in preload_ab_pre_start()")
        end

        if (env.host_agent == null) begin
            `uvm_fatal("SMOKE_TEST/NOHOSTAGENT",
                "env.host_agent is null in preload_ab_pre_start()")
        end

        if (env.host_agent.sequencer == null) begin
            `uvm_fatal("SMOKE_TEST/NOHOSTSEQ",
                "env.host_agent.sequencer is null; host-agent path is selected for preload-A/B")
        end

        host_seq = axi_mm_host_seq::type_id::create("host_preload_ab_seq");

        host_seq.set_enable_log(1'b1);
        host_seq.set_case_context(
            profile_item.case_id,
            profile_item.test_kind,
            profile_item.test_name,
            0
        );

        host_seq.queue_preload_a(profile_item.base_addr_a, a_flat);
        host_seq.queue_preload_b(profile_item.base_addr_b, b_flat);

        env.set_host_case_context(
            profile_item.case_id,
            profile_item.test_kind,
            profile_item.test_name,
            0
        );

        `uvm_info("SMOKE_TEST",
            $sformatf("Preloading A/B via host_agent: case_id=%0d test_kind=%0d base_a=0x%08h base_b=0x%08h a_bytes=%0d b_bytes=%0d",
                profile_item.case_id,
                profile_item.test_kind,
                profile_item.base_addr_a,
                profile_item.base_addr_b,
                a_flat.size(),
                b_flat.size()),
            UVM_MEDIUM)

        host_seq.start(env.host_agent.sequencer);

        env.clear_host_case_context();

        if (host_seq.get_response_count() != 2) begin
            `uvm_fatal("SMOKE_TEST/HOST_PRELOAD_RSP_COUNT",
                $sformatf("Expected 2 host preload responses, got %0d",
                    host_seq.get_response_count()))
        end

        rsp_item = host_seq.get_response_item(0);
        if (rsp_item == null) begin
            `uvm_fatal("SMOKE_TEST/HOST_PRELOAD_NULL_RSP0",
                "Host preload response[0] is null")
        end
        if (!rsp_item.response_valid) begin
            `uvm_fatal("SMOKE_TEST/HOST_PRELOAD_BAD_RSP0",
                "Host preload response[0] response_valid=0")
        end

        rsp_item = host_seq.get_response_item(1);
        if (rsp_item == null) begin
            `uvm_fatal("SMOKE_TEST/HOST_PRELOAD_NULL_RSP1",
                "Host preload response[1] is null")
        end
        if (!rsp_item.response_valid) begin
            `uvm_fatal("SMOKE_TEST/HOST_PRELOAD_BAD_RSP1",
                "Host preload response[1] response_valid=0")
        end
    end
    endtask

    // ------------------------------------------------------------
    // Read back C region after acc_done
    // ------------------------------------------------------------
    task automatic readback_c_region_post_done(
        input  ai_accel_subsys_seq_item profile_item,
        input  int unsigned             c_elems,
        output int signed               actual_c[],
        output bit                      have_actual_payload
    );
        axi_mm_host_seq      host_seq;
        axi_mm_host_seq_item rsp_item;
        int unsigned         i;
    begin
        have_actual_payload = 1'b0;

        repeat (5) @(posedge axi0_vif.clk);

        if (!use_host_agent_readback_c) begin
            axi_host_helper.readback_s32_vector(
                profile_item.base_addr_c,
                c_elems,
                actual_c
            );
            have_actual_payload = 1'b1;
            return;
        end

        if (env == null) begin
            `uvm_fatal("SMOKE_TEST/NOENV",
                "env is null in readback_c_region_post_done()")
        end

        if (env.host_agent == null) begin
            `uvm_fatal("SMOKE_TEST/NOHOSTAGENT",
                "env.host_agent is null in readback_c_region_post_done()")
        end

        if (env.host_agent.sequencer == null) begin
            `uvm_fatal("SMOKE_TEST/NOHOSTSEQ",
                "env.host_agent.sequencer is null; host-agent path is selected for readback-C")
        end

        host_seq = axi_mm_host_seq::type_id::create("host_readback_c_seq");

        host_seq.set_enable_log(1'b1);
        host_seq.set_case_context(
            profile_item.case_id,
            profile_item.test_kind,
            profile_item.test_name,
            0
        );

        host_seq.queue_readback_c(profile_item.base_addr_c, c_elems);

        env.set_host_case_context(
            profile_item.case_id,
            profile_item.test_kind,
            profile_item.test_name,
            0
        );

        `uvm_info("SMOKE_TEST",
            $sformatf("Reading back C via host_agent: case_id=%0d test_kind=%0d addr=0x%08h words=%0d",
                profile_item.case_id,
                profile_item.test_kind,
                profile_item.base_addr_c,
                c_elems),
            UVM_MEDIUM)

        host_seq.start(env.host_agent.sequencer);

        env.clear_host_case_context();

        if (host_seq.get_response_count() != 1) begin
            `uvm_fatal("SMOKE_TEST/HOST_READBACK_RSP_COUNT",
                $sformatf("Expected 1 host readback response, got %0d",
                    host_seq.get_response_count()))
        end

        rsp_item = host_seq.get_response_item(0);
        if (rsp_item == null) begin
            `uvm_fatal("SMOKE_TEST/HOST_READBACK_NULL_RSP",
                "Host readback response item is null")
        end

        if (!rsp_item.response_valid) begin
            `uvm_fatal("SMOKE_TEST/HOST_READBACK_BAD_RSP",
                "Host readback response_valid=0")
        end

        if (rsp_item.read_data_s32.size() != c_elems) begin
            `uvm_fatal("SMOKE_TEST/HOST_READBACK_SIZE",
                $sformatf("Host readback size mismatch: got=%0d exp=%0d",
                    rsp_item.read_data_s32.size(), c_elems))
        end

        actual_c = new[c_elems];
        for (i = 0; i < c_elems; i++) begin
            actual_c[i] = rsp_item.read_data_s32[i];
        end

        have_actual_payload = 1'b1;
    end
    endtask

    // ------------------------------------------------------------
    // Prepare fixed-baseline case
    // ------------------------------------------------------------
    task automatic prepare_fixed_case_pre_start(
        output int signed expected_c[],
        output bit        have_expected_payload
    );
        ai_accel_subsys_seq_item profile_item;
        int signed               a_flat[];
        int signed               b_flat[];
        int unsigned             c_elems;
    begin
        have_expected_payload = 1'b0;

        case_helper.build_fixed_case_payload(
            selected_case_id,
            profile_item,
            a_flat,
            b_flat,
            expected_c
        );

        c_elems = 16;

        `uvm_info("SMOKE_TEST",
            $sformatf("Pre-start prep for fixed case %0d: preload A=%0d bytes B=%0d bytes via %s, clear C=%0d words via %s",
                selected_case_id, a_flat.size(), b_flat.size(),
                get_preload_ab_path_name(),
                c_elems, get_clear_c_path_name()),
            UVM_MEDIUM)

        clear_c_region_pre_start(profile_item, c_elems);
        preload_ab_pre_start(profile_item, a_flat, b_flat);

        have_expected_payload = 1'b1;
    end
    endtask

    // ------------------------------------------------------------
    // Prepare variable-dimension case
    // ------------------------------------------------------------
    task automatic prepare_variable_case_pre_start(
        output int signed expected_c[],
        output bit        have_expected_payload
    );
        ai_accel_subsys_seq_item profile_item;
        int signed               a_flat[];
        int signed               b_flat[];
        int unsigned             c_elems;
    begin
        have_expected_payload = 1'b0;

        case_helper.build_variable_case_payload(
            selected_case_id,
            profile_item,
            a_flat,
            b_flat,
            expected_c
        );

        c_elems = profile_item.dim_m * profile_item.dim_n;

        `uvm_info("SMOKE_TEST",
            $sformatf("Pre-start prep for variable case %0d: preload A=%0d bytes B=%0d bytes via %s, clear C=%0d words via %s",
                selected_case_id, a_flat.size(), b_flat.size(),
                get_preload_ab_path_name(),
                c_elems, get_clear_c_path_name()),
            UVM_MEDIUM)

        clear_c_region_pre_start(profile_item, c_elems);
        preload_ab_pre_start(profile_item, a_flat, b_flat);

        have_expected_payload = 1'b1;
    end
    endtask

    // ------------------------------------------------------------
    // Prepare configurable-base case
    // ------------------------------------------------------------
    task automatic prepare_configurable_base_case_pre_start(
        output int signed expected_c[],
        output bit        have_expected_payload
    );
        ai_accel_subsys_seq_item profile_item;
        int signed               a_flat[];
        int signed               b_flat[];
        int unsigned             c_elems;
    begin
        have_expected_payload = 1'b0;

        case_helper.build_configurable_base_case_payload(
            selected_case_id,
            profile_item,
            a_flat,
            b_flat,
            expected_c
        );

        c_elems = 16;

        `uvm_info("SMOKE_TEST",
            $sformatf("Pre-start prep for configurable-base case %0d: preload A=%0d bytes B=%0d bytes via %s, clear C=%0d words via %s at A=0x%08h B=0x%08h C=0x%08h",
                selected_case_id, a_flat.size(), b_flat.size(),
                get_preload_ab_path_name(),
                c_elems, get_clear_c_path_name(),
                profile_item.base_addr_a, profile_item.base_addr_b, profile_item.base_addr_c),
            UVM_MEDIUM)

        clear_c_region_pre_start(profile_item, c_elems);
        preload_ab_pre_start(profile_item, a_flat, b_flat);

        have_expected_payload = 1'b1;
    end
    endtask

    // ------------------------------------------------------------
    // Read back actual C after acc_done for fixed-baseline case
    // ------------------------------------------------------------
    task automatic readback_fixed_case_post_done(
        output int signed actual_c[],
        output bit        have_actual_payload
    );
        ai_accel_subsys_seq_item profile_item;
        int unsigned             c_elems;
    begin
        have_actual_payload = 1'b0;

        profile_item = build_selected_profile_item();
        c_elems      = 16;

        `uvm_info("SMOKE_TEST",
            $sformatf("Post-done readback for fixed case %0d: C=%0d words via %s",
                selected_case_id, c_elems, get_readback_c_path_name()),
            UVM_MEDIUM)

        readback_c_region_post_done(
            profile_item,
            c_elems,
            actual_c,
            have_actual_payload
        );
    end
    endtask

    // ------------------------------------------------------------
    // Read back actual C after acc_done for variable-dimension case
    // ------------------------------------------------------------
    task automatic readback_variable_case_post_done(
        output int signed actual_c[],
        output bit        have_actual_payload
    );
        ai_accel_subsys_seq_item profile_item;
        int unsigned             c_elems;
    begin
        have_actual_payload = 1'b0;

        profile_item = build_selected_profile_item();
        c_elems      = profile_item.dim_m * profile_item.dim_n;

        `uvm_info("SMOKE_TEST",
            $sformatf("Post-done readback for variable case %0d: C=%0d words via %s",
                selected_case_id, c_elems, get_readback_c_path_name()),
            UVM_MEDIUM)

        readback_c_region_post_done(
            profile_item,
            c_elems,
            actual_c,
            have_actual_payload
        );
    end
    endtask

    // ------------------------------------------------------------
    // Read back actual C after acc_done for configurable-base case
    // ------------------------------------------------------------
    task automatic readback_configurable_base_case_post_done(
        output int signed actual_c[],
        output bit        have_actual_payload
    );
        ai_accel_subsys_seq_item profile_item;
        int unsigned             c_elems;
    begin
        have_actual_payload = 1'b0;

        profile_item = build_selected_profile_item();
        c_elems      = 16;

        `uvm_info("SMOKE_TEST",
            $sformatf("Post-done readback for configurable-base case %0d: C=%0d words via %s",
                selected_case_id, c_elems, get_readback_c_path_name()),
            UVM_MEDIUM)

        readback_c_region_post_done(
            profile_item,
            c_elems,
            actual_c,
            have_actual_payload
        );
    end
    endtask

    // ------------------------------------------------------------
    // Dispatch pre-start preparation for the selected case
    // ------------------------------------------------------------
    task automatic prepare_case_result_pre_start(
        output int signed expected_c[],
        output bit        have_expected_payload
    );
    begin
        have_expected_payload = 1'b0;

        case (selected_test_kind)
            ai_accel_subsys_seq_item::TEST_KIND_FIXED_BASELINE: begin
                prepare_fixed_case_pre_start(expected_c, have_expected_payload);
            end

            ai_accel_subsys_seq_item::TEST_KIND_VARIABLE_DIM_SMOKE: begin
                prepare_variable_case_pre_start(expected_c, have_expected_payload);
            end

            ai_accel_subsys_seq_item::TEST_KIND_CONFIGURABLE_BASE: begin
                prepare_configurable_base_case_pre_start(expected_c, have_expected_payload);
            end

            default: begin
                `uvm_fatal("TEST/RESULT_PREP_UNSUPPORTED",
                    $sformatf("Result-prep path not implemented yet for test_kind=%0d CASE_ID=%0d",
                        selected_test_kind, selected_case_id))
            end
        endcase
    end
    endtask

    // ------------------------------------------------------------
    // Dispatch post-done actual-data collection for the selected case
    // ------------------------------------------------------------
    task automatic collect_case_actual_post_done(
        output int signed actual_c[],
        output bit        have_actual_payload
    );
    begin
        have_actual_payload = 1'b0;

        case (selected_test_kind)
            ai_accel_subsys_seq_item::TEST_KIND_FIXED_BASELINE: begin
                readback_fixed_case_post_done(actual_c, have_actual_payload);
            end

            ai_accel_subsys_seq_item::TEST_KIND_VARIABLE_DIM_SMOKE: begin
                readback_variable_case_post_done(actual_c, have_actual_payload);
            end

            ai_accel_subsys_seq_item::TEST_KIND_CONFIGURABLE_BASE: begin
                readback_configurable_base_case_post_done(actual_c, have_actual_payload);
            end

            default: begin
                `uvm_fatal("TEST/RESULT_READBACK_UNSUPPORTED",
                    $sformatf("Result-readback path not implemented yet for test_kind=%0d CASE_ID=%0d",
                        selected_test_kind, selected_case_id))
            end
        endcase
    end
    endtask

    // ------------------------------------------------------------
    // Build phase
    // ------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        string uvm_testname;
        bit    c_rmw_accum_dut_test_selected;

        super.build_phase(phase);

        c_rmw_accum_dut_test_selected = 1'b0;
        if ($value$plusargs("UVM_TESTNAME=%s", uvm_testname)) begin
            c_rmw_accum_dut_test_selected = (uvm_testname == "ai_accel_subsys_c_rmw_accum_dut_test");
        end

        if (!uvm_config_db#(virtual ai_accel_subsys_ctrl_if)::get(
                this, "", "vif", vif)) begin
            `uvm_fatal("TEST/NOVIF",
                "virtual interface ai_accel_subsys_ctrl_if is not set for ai_accel_subsys_smoke_test")
        end

        parse_test_selection();
        parse_done_timeout_cycles();
        parse_result_check_enable();
        parse_force_helper_mem_path_enable();
        parse_host_agent_clear_c_enable();
        parse_host_agent_readback_c_enable();
        parse_host_agent_preload_ab_enable();

        if (c_rmw_accum_dut_test_selected) begin
            if (selected_case_id == 0) begin
                selected_case_id = 208;
            end

            selected_test_kind        = ai_accel_subsys_seq_item::TEST_KIND_C_RMW_ACCUM_RECIPE;
            enable_result_check       = 1'b1;
            force_helper_mem_path     = 1'b0;
            use_host_agent_clear_c    = 1'b1;
            use_host_agent_readback_c = 1'b1;
            use_host_agent_preload_ab = 1'b1;

            `uvm_info("SMOKE_TEST",
                $sformatf("C RMW accumulation DUT test selected: CASE_ID=%0d, forcing recipe test_kind, result_check=1, host-agent memory path",
                    selected_case_id),
                UVM_MEDIUM)
        end

        if (!uvm_config_db#(axi0_vif_t)::get(
                this, "", "axi0_vif", axi0_vif)) begin
            `uvm_fatal("TEST/NOAXIVIF",
                "axi0_vif is not set for ai_accel_subsys_smoke_test")
        end

        uvm_config_db#(virtual ai_accel_subsys_ctrl_if)::set(
            this, "env", "vif", vif);

        uvm_config_db#(axi0_vif_t)::set(
            this, "env", "axi0_vif", axi0_vif);

        uvm_config_db#(int unsigned)::set(
            this, "env.agent.monitor", "selected_case_id", selected_case_id);

        uvm_config_db#(ai_accel_subsys_seq_item::test_kind_e)::set(
            this, "env.agent.monitor", "selected_test_kind", selected_test_kind);

        if (enable_result_check && any_host_agent_mem_path_enabled()) begin
            uvm_config_db#(uvm_active_passive_enum)::set(
                this, "env", "host_is_active", UVM_ACTIVE);
        end
        else begin
            uvm_config_db#(uvm_active_passive_enum)::set(
                this, "env", "host_is_active", UVM_PASSIVE);
        end

        uvm_config_db#(bit)::set(
            this, "env.scoreboard", "result_check_enable", enable_result_check);

        uvm_config_db#(bit)::set(
            this, "env.scoreboard", "c_rmw_accum_final_result_only_mode",
            (selected_test_kind == ai_accel_subsys_seq_item::TEST_KIND_C_RMW_ACCUM_RECIPE));

        env = ai_accel_subsys_env::type_id::create("env", this);

        case_helper     = ai_accel_subsys_case_helper    ::type_id::create("case_helper");
        axi_host_helper = ai_accel_subsys_axi_host_helper::type_id::create("axi_host_helper");

        axi_host_helper.set_vif(axi0_vif);
    endfunction

    // ------------------------------------------------------------
    // Wait until subsystem reset is released
    // ------------------------------------------------------------
    task automatic wait_for_reset_release();
        @vif.cb_mon;
        while ((vif.cb_mon.dma_rst_n !== 1'b1) || (vif.cb_mon.core_rst_n !== 1'b1)) begin
            @vif.cb_mon;
        end
    endtask

    // ------------------------------------------------------------
    // Wait for acc_done with timeout
    // ------------------------------------------------------------
    task automatic wait_for_acc_done(
        int unsigned timeout_cycles = DEFAULT_DONE_TIMEOUT_CYCLES
    );
        int unsigned cnt;
    begin
        cnt = 0;

        @vif.cb_mon;
        while (vif.cb_mon.acc_done !== 1'b1) begin
            @vif.cb_mon;
            cnt++;

            if (cnt > timeout_cycles) begin
                `uvm_fatal("SMOKE_TIMEOUT",
                    $sformatf("Timed out waiting for acc_done after %0d cycles", timeout_cycles))
            end
        end

        `uvm_info("SMOKE_TEST",
            $sformatf("Observed acc_done after %0d monitor cycles", cnt),
            UVM_MEDIUM)
    end
    endtask

    task automatic wait_for_acc_done_rearmed(
        int unsigned timeout_cycles = DEFAULT_DONE_TIMEOUT_CYCLES
    );
        int unsigned cnt;
    begin
        cnt = 0;

        @vif.cb_mon;

        // If previous job/reset state left acc_done high, wait for it to clear
        while (vif.cb_mon.acc_done === 1'b1) begin
            @vif.cb_mon;
            cnt++;

            if (cnt > timeout_cycles) begin
                `uvm_fatal("MIDRESET_DONE_STUCK_HIGH",
                    $sformatf("Timed out waiting for stale acc_done to deassert after %0d cycles",
                        timeout_cycles))
            end
        end

        // Wait for a new acc_done assertion
        while (vif.cb_mon.acc_done !== 1'b1) begin
            @vif.cb_mon;
            cnt++;

            if (cnt > timeout_cycles) begin
                `uvm_fatal("MIDRESET_TIMEOUT",
                    $sformatf("Timed out waiting for new acc_done after %0d cycles",
                        timeout_cycles))
            end
        end

        `uvm_info("MIDRESET_TEST",
            $sformatf("Observed new acc_done after %0d monitor cycles", cnt),
            UVM_MEDIUM)
    end
    endtask

    // ------------------------------------------------------------
    // Run phase
    // ------------------------------------------------------------
    task run_phase(uvm_phase phase);
        ai_accel_subsys_smoke_seq seq;

        int signed expected_c[];
        int signed actual_c[];
        bit        have_expected_payload;
        bit        have_actual_payload;

        phase.raise_objection(this);

        `uvm_info("SMOKE_TEST",
            "Starting ai_accel_subsys_smoke_test",
            UVM_MEDIUM)

        wait_for_reset_release();

        if (enable_result_check) begin
            prepare_case_result_pre_start(expected_c, have_expected_payload);

            if (!have_expected_payload) begin
                `uvm_fatal("TEST/NO_EXPECTED_PAYLOAD",
                    "enable_result_check=1 but expected payload was not prepared")
            end
        end

        seq = ai_accel_subsys_smoke_seq::type_id::create("seq");

        seq.case_id   = selected_case_id;
        seq.test_kind = selected_test_kind;

        `uvm_info("SMOKE_TEST",
            $sformatf("Launching smoke sequence with CASE_ID=%0d test_kind=%0d",
                seq.case_id, seq.test_kind),
            UVM_MEDIUM)

        seq.start(env.agent.sequencer);

        `uvm_info("SMOKE_TEST",
            "Completed ai_accel_subsys_smoke_seq, now waiting for acc_done",
            UVM_MEDIUM)

        wait_for_acc_done(done_timeout_cycles);

        if (enable_result_check) begin
            collect_case_actual_post_done(actual_c, have_actual_payload);

            if (!have_actual_payload) begin
                `uvm_fatal("TEST/NO_ACTUAL_PAYLOAD",
                    "enable_result_check=1 but actual payload was not collected")
            end

            publish_result_to_scoreboard(expected_c, actual_c);
        end

        `uvm_info("SMOKE_TEST",
            "Smoke test completed with acc_done observed",
            UVM_MEDIUM)

        phase.drop_objection(this);
    endtask

endclass


// ------------------------------------------------------------
// C RMW accumulation partial-job sequence
// ------------------------------------------------------------
class ai_accel_subsys_c_rmw_accum_job_seq extends uvm_sequence #(ai_accel_subsys_seq_item);
    `uvm_object_utils(ai_accel_subsys_c_rmw_accum_job_seq)

    int unsigned case_id;
    int unsigned job_idx;

    function new(string name = "ai_accel_subsys_c_rmw_accum_job_seq");
        super.new(name);
    endfunction

    task body();
        ai_accel_subsys_seq_item req;
    begin
        req = ai_accel_subsys_seq_item::type_id::create("req");

        start_item(req);
        req.apply_c_rmw_accum_job_case(case_id, job_idx);
        finish_item(req);
    end
    endtask
endclass


// ------------------------------------------------------------
// C RMW accumulation DUT focused test
//
// This test drives the real subsystem with a two-job partial-K
// accumulation recipe:
//   job0: accumulate_enable=0, write first partial C
//   job1: accumulate_enable=1, read old C and accumulate second partial C
//
// Only the final C result is read back and compared against the
// full-K software reference payload.
// ------------------------------------------------------------
class ai_accel_subsys_c_rmw_accum_dut_test extends ai_accel_subsys_smoke_test;
    `uvm_component_utils(ai_accel_subsys_c_rmw_accum_dut_test)

    bit run_all;

    function new(string name = "ai_accel_subsys_c_rmw_accum_dut_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        int unsigned tmp;
        super.build_phase(phase);

        run_all = 1'b0;
        if ($value$plusargs("RUN_ALL=%d", tmp)) begin
            run_all = (tmp != 0);
        end

        if (selected_case_id == 0) begin
            selected_case_id = 208;
        end

        selected_test_kind = ai_accel_subsys_seq_item::TEST_KIND_C_RMW_ACCUM_RECIPE;

        uvm_config_db#(int unsigned)::set(
            this, "env.agent.monitor", "selected_case_id", selected_case_id);

        uvm_config_db#(ai_accel_subsys_seq_item::test_kind_e)::set(
            this, "env.agent.monitor", "selected_test_kind", selected_test_kind);

        uvm_config_db#(bit)::set(
            this, "env.scoreboard", "c_rmw_accum_final_result_only_mode", 1'b1);
    endfunction

    task automatic set_c_rmw_accum_monitor_context(input int unsigned case_id_in);
    begin
        if ((env != null) &&
            (env.agent != null) &&
            (env.agent.monitor != null)) begin
            env.agent.monitor.selected_case_id   = case_id_in;
            env.agent.monitor.selected_test_kind = ai_accel_subsys_seq_item::TEST_KIND_C_RMW_ACCUM_RECIPE;
        end
    end
    endtask

    task automatic run_one_recipe(input int unsigned case_id_in);
        ai_accel_subsys_seq_item recipe_item;
        ai_accel_subsys_seq_item job_item;
        ai_accel_subsys_c_rmw_accum_job_seq seq;

        int signed   a_full[];
        int signed   b_full[];
        int signed   expected_final_c[];

        int signed   a_part[];
        int signed   b_part[];
        int signed   expected_partial_c[];
        int signed   expected_accumulated_c[];
        int signed   actual_c[];

        bit          have_actual_payload;
        int unsigned job_count;
        int unsigned c_elems;
    begin
        if (!case_helper.is_c_rmw_accum_recipe_case(case_id_in)) begin
            `uvm_fatal("C_RMW_ACCUM_DUT/BAD_CASE",
                $sformatf("Unsupported C RMW accumulation DUT recipe CASE_ID=%0d", case_id_in))
        end

        selected_case_id   = case_id_in;
        selected_test_kind = ai_accel_subsys_seq_item::TEST_KIND_C_RMW_ACCUM_RECIPE;
        set_c_rmw_accum_monitor_context(case_id_in);

        case_helper.build_c_rmw_accum_recipe_expected_payload(
            case_id_in,
            recipe_item,
            a_full,
            b_full,
            expected_final_c
        );

        job_count = case_helper.get_c_rmw_accum_recipe_job_count(case_id_in);
        c_elems   = recipe_item.dim_m * recipe_item.dim_n;

        `uvm_info("C_RMW_ACCUM_DUT",
            $sformatf("Starting CASE_ID=%0d two-job DUT accumulation recipe dim=(%0d,%0d,%0d) jobs=%0d C_words=%0d",
                case_id_in,
                recipe_item.dim_m,
                recipe_item.dim_n,
                recipe_item.dim_k,
                job_count,
                c_elems),
            UVM_MEDIUM)

        clear_c_region_pre_start(recipe_item, c_elems);

        for (int unsigned job_idx = 0; job_idx < job_count; job_idx++) begin
            case_helper.build_c_rmw_accum_job_payload(
                case_id_in,
                job_idx,
                job_item,
                a_part,
                b_part,
                expected_partial_c,
                expected_accumulated_c
            );

            `uvm_info("C_RMW_ACCUM_DUT",
                $sformatf("CASE_ID=%0d launching job=%0d/%0d dim=(%0d,%0d,%0d) k_base=%0d k_part=%0d accumulate_enable=%0d A_part=%0d B_part=%0d partial_C=%0d",
                    case_id_in,
                    job_item.recipe_job_idx,
                    job_item.recipe_job_count,
                    job_item.dim_m,
                    job_item.dim_n,
                    job_item.dim_k,
                    job_item.recipe_k_base,
                    job_item.recipe_k_part,
                    job_item.accumulate_enable,
                    a_part.size(),
                    b_part.size(),
                    expected_partial_c.size()),
                UVM_MEDIUM)

            preload_ab_pre_start(job_item, a_part, b_part);

            seq = ai_accel_subsys_c_rmw_accum_job_seq::type_id::create(
                $sformatf("c_rmw_accum_job_seq_case_%0d_job_%0d", case_id_in, job_idx));
            seq.case_id = case_id_in;
            seq.job_idx = job_idx;

            seq.start(env.agent.sequencer);
            wait_for_acc_done_rearmed(done_timeout_cycles);

            `uvm_info("C_RMW_ACCUM_DUT",
                $sformatf("CASE_ID=%0d completed job=%0d/%0d accumulate_enable=%0d",
                    case_id_in,
                    job_item.recipe_job_idx,
                    job_item.recipe_job_count,
                    job_item.accumulate_enable),
                UVM_MEDIUM)
        end

        readback_c_region_post_done(
            recipe_item,
            c_elems,
            actual_c,
            have_actual_payload
        );

        if (!have_actual_payload) begin
            `uvm_fatal("C_RMW_ACCUM_DUT/NO_ACTUAL_PAYLOAD",
                "C RMW accumulation DUT test did not collect final actual C payload")
        end

        publish_result_to_scoreboard(expected_final_c, actual_c);

        `uvm_info("C_RMW_ACCUM_DUT",
            $sformatf("CASE_ID=%0d DUT accumulation recipe completed and final result was published", case_id_in),
            UVM_LOW)
    end
    endtask

    task run_phase(uvm_phase phase);
        int unsigned case_id_to_run;
    begin
        phase.raise_objection(this);

        `uvm_info("C_RMW_ACCUM_DUT",
            "Starting C RMW accumulation DUT focused test",
            UVM_MEDIUM)

        wait_for_reset_release();

        if (run_all) begin
            for (int unsigned cid = 208; cid <= 212; cid++) begin
                run_one_recipe(cid);
            end
        end
        else begin
            case_id_to_run = selected_case_id;

            if (case_id_to_run == 0) begin
                case_id_to_run = 208;
            end

            run_one_recipe(case_id_to_run);
        end

        `uvm_info("C_RMW_ACCUM_DUT",
            "C RMW accumulation DUT focused test completed",
            UVM_MEDIUM)

        phase.drop_objection(this);
    end
    endtask
endclass


// ------------------------------------------------------------
// C RMW accumulation reference-model self-check
//
// This test does not drive the DUT.  It validates the C RMW accumulation software
// recipe database and reference-model decomposition:
//   full-K expected C == accumulated compact partial-job C vectors.
//
// It is intended for the C RMW accumulation reference-model flow before DUT-focused validation.
// ------------------------------------------------------------
class ai_accel_subsys_c_rmw_accum_ref_model_test extends uvm_test;
    `uvm_component_utils(ai_accel_subsys_c_rmw_accum_ref_model_test)

    ai_accel_subsys_case_helper case_helper;

    int unsigned selected_case_id;
    bit          run_all;

    function new(string name = "ai_accel_subsys_c_rmw_accum_ref_model_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        int unsigned tmp;
        super.build_phase(phase);

        case_helper = ai_accel_subsys_case_helper::type_id::create("case_helper");

        selected_case_id = 208;
        if ($value$plusargs("CASE_ID=%d", tmp)) begin
            if (tmp != 0) begin
                selected_case_id = tmp;
            end
        end

        run_all = 1'b0;
        if ($value$plusargs("RUN_ALL=%d", tmp)) begin
            run_all = (tmp != 0);
        end
    endfunction

    task automatic compare_vectors(
        input string       tag,
        input int signed   exp[],
        input int signed   act[]
    );
        int unsigned i;
    begin
        if (exp.size() != act.size()) begin
            `uvm_fatal("C_RMW_ACCUM_REF/SIZE",
                $sformatf("%s size mismatch exp=%0d act=%0d",
                    tag, exp.size(), act.size()))
        end

        for (i = 0; i < exp.size(); i++) begin
            if (exp[i] !== act[i]) begin
                `uvm_fatal("C_RMW_ACCUM_REF/MISMATCH",
                    $sformatf("%s mismatch idx=%0d exp=%0d act=%0d",
                        tag, i, exp[i], act[i]))
            end
        end
    end
    endtask

    task automatic copy_vector(
        input  int signed src[],
        output int signed dst[]
    );
        int unsigned i;
    begin
        dst = new[src.size()];
        for (i = 0; i < src.size(); i++) begin
            dst[i] = src[i];
        end
    end
    endtask

    task automatic run_one_recipe(input int unsigned case_id);
        ai_accel_subsys_seq_item recipe_item;
        ai_accel_subsys_seq_item job_item;
        int signed               a_full[];
        int signed               b_full[];
        int signed               expected_final_c[];
        int signed               a_part[];
        int signed               b_part[];
        int signed               expected_partial_c[];
        int signed               expected_accumulated_c[];
        int signed               running_accum[];
        int signed               running_next[];
        int unsigned             job_idx;
        int unsigned             job_count;
    begin
        if (!case_helper.is_c_rmw_accum_recipe_case(case_id)) begin
            `uvm_fatal("C_RMW_ACCUM_REF/BAD_CASE",
                $sformatf("Unsupported C RMW accumulation reference recipe CASE_ID=%0d", case_id))
        end

        case_helper.build_c_rmw_accum_recipe_expected_payload(
            case_id,
            recipe_item,
            a_full,
            b_full,
            expected_final_c
        );

        job_count = case_helper.get_c_rmw_accum_recipe_job_count(case_id);
        running_accum = new[recipe_item.dim_m * recipe_item.dim_n];
        case_helper.zero_vector(running_accum);

        `uvm_info("C_RMW_ACCUM_REF",
            $sformatf("Checking CASE_ID=%0d recipe dim=(%0d,%0d,%0d) jobs=%0d full_A=%0d full_B=%0d C_words=%0d",
                case_id,
                recipe_item.dim_m,
                recipe_item.dim_n,
                recipe_item.dim_k,
                job_count,
                a_full.size(),
                b_full.size(),
                expected_final_c.size()),
            UVM_MEDIUM)

        for (job_idx = 0; job_idx < job_count; job_idx++) begin
            case_helper.build_c_rmw_accum_job_payload(
                case_id,
                job_idx,
                job_item,
                a_part,
                b_part,
                expected_partial_c,
                expected_accumulated_c
            );

            case_helper.compute_expected_c_accumulate(
                running_accum,
                expected_partial_c,
                job_item.accumulate_enable,
                running_next
            );

            compare_vectors(
                $sformatf("case%0d_job%0d_accumulated", case_id, job_idx),
                expected_accumulated_c,
                running_next
            );

            copy_vector(running_next, running_accum);

            `uvm_info("C_RMW_ACCUM_REF",
                $sformatf("CASE_ID=%0d job=%0d/%0d k_base=%0d k_part=%0d accum=%0d A_part=%0d B_part=%0d partial_C=%0d",
                    case_id,
                    job_item.recipe_job_idx,
                    job_item.recipe_job_count,
                    job_item.recipe_k_base,
                    job_item.recipe_k_part,
                    job_item.accumulate_enable,
                    a_part.size(),
                    b_part.size(),
                    expected_partial_c.size()),
                UVM_MEDIUM)
        end

        compare_vectors(
            $sformatf("case%0d_final", case_id),
            expected_final_c,
            running_accum
        );

        `uvm_info("C_RMW_ACCUM_REF",
            $sformatf("CASE_ID=%0d reference recipe PASS: final C matches accumulated partial jobs", case_id),
            UVM_LOW)
    end
    endtask

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);

        `uvm_info("C_RMW_ACCUM_REF",
            "Starting C RMW accumulation reference-model self-check",
            UVM_MEDIUM)

        if (run_all) begin
            for (int unsigned cid = 208; cid <= 212; cid++) begin
                run_one_recipe(cid);
            end
        end
        else begin
            run_one_recipe(selected_case_id);
        end

        `uvm_info("C_RMW_ACCUM_REF",
            "C RMW accumulation reference-model self-check completed",
            UVM_MEDIUM)

        phase.drop_objection(this);
    endtask
endclass

`endif
