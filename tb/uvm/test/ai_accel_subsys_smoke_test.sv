// File: tb/uvm/test/ai_accel_subsys_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_SMOKE_TEST_SV

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

    // ------------------------------------------------------------
    // Result-check control
    // ------------------------------------------------------------
    bit enable_result_check;

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
        else if ((case_id >= 100) && (case_id <= 199)) begin
            return ai_accel_subsys_seq_item::TEST_KIND_VARIABLE_DIM_SMOKE;
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
    // Parse optional result-check enable
    //   usage:
    //     +ENABLE_RESULT_CHECK=1
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

            default:
                `uvm_fatal("TEST/BAD_KIND",
                    $sformatf("Unsupported selected_test_kind=%0d for CASE_ID=%0d",
                        selected_test_kind, selected_case_id))
        endcase

        return item;
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
    // Prepare fixed-baseline case:
    //   - build canonical profile
    //   - build A/B flat vectors
    //   - build expected_c
    //   - clear C region
    //   - preload A/B
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
            $sformatf("Pre-start prep for fixed case %0d: preload A=%0d bytes B=%0d bytes, clear C=%0d words",
                selected_case_id, a_flat.size(), b_flat.size(), c_elems),
            UVM_MEDIUM)

        axi_host_helper.clear_u32_region(profile_item.base_addr_c, c_elems);
        axi_host_helper.preload_u8_vector(profile_item.base_addr_a, a_flat);
        axi_host_helper.preload_u8_vector(profile_item.base_addr_b, b_flat);

        have_expected_payload = 1'b1;
    end
    endtask

    // ------------------------------------------------------------
    // Prepare variable-dimension case:
    //   - build canonical profile
    //   - build A/B flat vectors
    //   - build expected_c
    //   - clear C region
    //   - preload A/B
    //
    // First version only implements VARIABLE_DIM_SMOKE result path.
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
            $sformatf("Pre-start prep for variable case %0d: preload A=%0d bytes B=%0d bytes, clear C=%0d words",
                selected_case_id, a_flat.size(), b_flat.size(), c_elems),
            UVM_MEDIUM)

        axi_host_helper.clear_u32_region(profile_item.base_addr_c, c_elems);
        axi_host_helper.preload_u8_vector(profile_item.base_addr_a, a_flat);
        axi_host_helper.preload_u8_vector(profile_item.base_addr_b, b_flat);

        have_expected_payload = 1'b1;
    end
    endtask

    // ------------------------------------------------------------
    // Prepare configurable-base case:
    //   - build canonical profile
    //   - build A/B flat vectors
    //   - build expected_c
    //   - clear C region
    //   - preload A/B
    //
    // Payload policy:
    //   Reuse identity(4x4) x known(4x4), but honor configurable
    //   base_addr_a/base_addr_b/base_addr_c from profile_item.
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
            $sformatf("Pre-start prep for configurable-base case %0d: preload A=%0d bytes B=%0d bytes, clear C=%0d words at A=0x%08h B=0x%08h C=0x%08h",
                selected_case_id, a_flat.size(), b_flat.size(), c_elems,
                profile_item.base_addr_a, profile_item.base_addr_b, profile_item.base_addr_c),
            UVM_MEDIUM)

        axi_host_helper.clear_u32_region(profile_item.base_addr_c, c_elems);
        axi_host_helper.preload_u8_vector(profile_item.base_addr_a, a_flat);
        axi_host_helper.preload_u8_vector(profile_item.base_addr_b, b_flat);

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

        // Keep same spirit as legacy flow: wait a few dma_clk cycles
        repeat (5) @(posedge axi0_vif.clk);

        axi_host_helper.readback_s32_vector(
            profile_item.base_addr_c,
            c_elems,
            actual_c
        );

        have_actual_payload = 1'b1;
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

        // Keep same spirit as legacy flow: wait a few dma_clk cycles
        repeat (5) @(posedge axi0_vif.clk);

        axi_host_helper.readback_s32_vector(
            profile_item.base_addr_c,
            c_elems,
            actual_c
        );

        have_actual_payload = 1'b1;
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

        // Keep same spirit as legacy flow: wait a few dma_clk cycles
        repeat (5) @(posedge axi0_vif.clk);

        axi_host_helper.readback_s32_vector(
            profile_item.base_addr_c,
            c_elems,
            actual_c
        );

        have_actual_payload = 1'b1;
    end
    endtask

    // ------------------------------------------------------------
    // Dispatcher: pre-start case prep
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
    // Dispatcher: post-done actual readback
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
        super.build_phase(phase);

        if (!uvm_config_db#(virtual ai_accel_subsys_ctrl_if)::get(
                this, "", "vif", vif)) begin
            `uvm_fatal("TEST/NOVIF",
                "virtual interface ai_accel_subsys_ctrl_if is not set for ai_accel_subsys_smoke_test")
        end

        // Parse selection early so child components can get it in build_phase
        parse_test_selection();
        parse_result_check_enable();

        // When result check is enabled, smoke_test also needs AXI host vif
        if (enable_result_check) begin
            if (!uvm_config_db#(axi0_vif_t)::get(
                    this, "", "axi0_vif", axi0_vif)) begin
                `uvm_fatal("TEST/NOAXIVIF",
                    "axi0_vif is not set for ai_accel_subsys_smoke_test")
            end
        end

        // Pass vif down to env
        uvm_config_db#(virtual ai_accel_subsys_ctrl_if)::set(
            this, "env", "vif", vif);

        // Pass selected case context down to monitor
        uvm_config_db#(int unsigned)::set(
            this, "env.agent.monitor", "selected_case_id", selected_case_id);

        uvm_config_db#(ai_accel_subsys_seq_item::test_kind_e)::set(
            this, "env.agent.monitor", "selected_test_kind", selected_test_kind);

        // Pass result-check enable down to scoreboard
        uvm_config_db#(bit)::set(
            this, "env.scoreboard", "result_check_enable", enable_result_check);

        env = ai_accel_subsys_env::type_id::create("env", this);

        case_helper     = ai_accel_subsys_case_helper    ::type_id::create("case_helper");
        axi_host_helper = ai_accel_subsys_axi_host_helper::type_id::create("axi_host_helper");

        if (enable_result_check) begin
            axi_host_helper.set_vif(axi0_vif);
        end
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

        // Pass selected case profile to sequence
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

        wait_for_acc_done();

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

`endif