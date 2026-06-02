// File: tb/uvm/test/ai_accel_subsys_csr_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_SMOKE_TEST_SV

// ------------------------------------------------------------
// CSR-controlled host-primary GEMM smoke test
//
// Scope:
//   - use the existing host AXI agent to preload A/B and read back C
//   - use the AXI-Lite CSR path to program GEMM config and issue start
//   - poll CSR sticky done/error status instead of driving sideband start
//   - compare C directly in the test
//
// This test intentionally disables the legacy sideband control/result
// scoreboard path.  The sideband control monitor does not observe the
// CSR-generated start pulse inside the wrapper, so this focused test
// checks the CSR-controlled path directly.
// ------------------------------------------------------------

class ai_accel_subsys_csr_smoke_test extends ai_accel_subsys_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_smoke_test)

    typedef virtual axi_lite_if #(
        .ADDR_WIDTH (12),
        .DATA_WIDTH (32)
    ) csr_vif_t;

    csr_vif_t                  csr_vif;
    ai_accel_csr_access_helper csr;

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_csr_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // ------------------------------------------------------------
    // Build phase
    // ------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(csr_vif_t)::get(this, "", "csr_vif", csr_vif)) begin
            `uvm_fatal("CSR_SMOKE/NOCSRVIF",
                "csr_vif is not set for ai_accel_subsys_csr_smoke_test")
        end

        csr = ai_accel_csr_access_helper::type_id::create("csr");
        csr.set_vif(csr_vif);

        // This is a host-primary CSR test regardless of run-script
        // defaults.  Keep the host agent active and force all memory
        // setup/readback through the host AXI path.
        enable_result_check       = 1'b1;
        force_helper_mem_path     = 1'b0;
        use_host_agent_clear_c    = 1'b1;
        use_host_agent_readback_c = 1'b1;
        use_host_agent_preload_ab = 1'b1;

        uvm_config_db#(uvm_active_passive_enum)::set(
            this, "env", "host_is_active", UVM_ACTIVE);

        // Disable legacy sideband scoreboard/checker expectations for
        // this focused CSR path.  The test performs the final C compare
        // directly after CSR_DONE_STATUS reports GEMM completion.
        uvm_config_db#(bit)::set(
            this, "env.scoreboard", "result_check_enable", 1'b0);

        uvm_config_db#(bit)::set(
            this, "env.host_traffic_checker", "enable_check", 1'b0);

        uvm_config_db#(bit)::set(
            this, "env.host_traffic_checker", "strict_check_enable", 1'b0);

        apply_csr_focused_report_policy();
    endfunction

    // ------------------------------------------------------------
    // End-of-elaboration phase
    // ------------------------------------------------------------
    function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        apply_csr_focused_report_policy();
    endfunction

    // ------------------------------------------------------------
    // Start-of-simulation phase
    // ------------------------------------------------------------
    function void start_of_simulation_phase(uvm_phase phase);
        super.start_of_simulation_phase(phase);
        apply_csr_focused_report_policy();
    endfunction

    // ------------------------------------------------------------
    // CSR-focused legacy report policy
    // ------------------------------------------------------------
    function void apply_csr_focused_report_policy();
        if ((env != null) && (env.scoreboard != null)) begin
            // The legacy scoreboard observes sideband acc_start/acc_done
            // traffic.  In this test, GEMM is launched by the CSR wrapper
            // and the C result is checked directly after CSR_DONE_STATUS.
            // Demote the expected legacy-sideband no-start summary so the
            // focused CSR test can report a clean pass/fail result.
            env.scoreboard.set_report_severity_id_override(
                UVM_ERROR, "SB/NOSTART", UVM_INFO);
        end

        if ((env != null) &&
            (env.agent != null) &&
            (env.agent.monitor != null)) begin
            // The sideband monitor can still see the public acc_done level,
            // but it does not see the internal CSR-generated acc_start pulse.
            // Demote that expected CSR-mode observation from WARNING to INFO.
            env.agent.monitor.set_report_severity_id_override(
                UVM_WARNING, "MON/DONE_WITHOUT_ACTIVE_JOB", UVM_INFO);
        end
    endfunction

    // ------------------------------------------------------------
    // CSR status helpers
    // ------------------------------------------------------------
    task automatic csr_clear_sticky_status();
        logic [31:0] clear_cmd;
    begin
        clear_cmd = 32'h0000_0000;
        clear_cmd[ai_accel_csr_access_helper::CMD_CLEAR_DONE]  = 1'b1;
        clear_cmd[ai_accel_csr_access_helper::CMD_CLEAR_ERROR] = 1'b1;
        clear_cmd[ai_accel_csr_access_helper::CMD_CLEAR_PERF]  = 1'b1;

        csr.issue_command(clear_cmd);
    end
    endtask

    task automatic csr_write_gemm_config(
        input ai_accel_subsys_seq_item profile_item
    );
        logic [31:0] mode_value;
    begin
        mode_value = 32'h0000_0000;
        mode_value[0] = 1'b0;  // scratchpad/host-primary input path
        mode_value[1] = profile_item.accumulate_enable;

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_MODE,
            mode_value
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_BASE_ADDR_A,
            profile_item.base_addr_a
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_BASE_ADDR_B,
            profile_item.base_addr_b
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_BASE_ADDR_C,
            profile_item.base_addr_c
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_DIM_M,
            32'(profile_item.dim_m)
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_DIM_N,
            32'(profile_item.dim_n)
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_DIM_K,
            32'(profile_item.dim_k)
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_BASE_ADDR_A,
            profile_item.base_addr_a,
            "CSR_BASE_ADDR_A"
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_BASE_ADDR_B,
            profile_item.base_addr_b,
            "CSR_BASE_ADDR_B"
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_BASE_ADDR_C,
            profile_item.base_addr_c,
            "CSR_BASE_ADDR_C"
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_DIM_M,
            32'(profile_item.dim_m),
            "CSR_DIM_M"
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_DIM_N,
            32'(profile_item.dim_n),
            "CSR_DIM_N"
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_DIM_K,
            32'(profile_item.dim_k),
            "CSR_DIM_K"
        );

        `uvm_info("CSR_SMOKE",
            $sformatf("Programmed CSR GEMM config: case_id=%0d base_a=0x%08h base_b=0x%08h base_c=0x%08h dim=(%0d,%0d,%0d) mode=0x%08h",
                profile_item.case_id,
                profile_item.base_addr_a,
                profile_item.base_addr_b,
                profile_item.base_addr_c,
                profile_item.dim_m,
                profile_item.dim_n,
                profile_item.dim_k,
                mode_value),
            UVM_MEDIUM)
    end
    endtask

    task automatic csr_start_gemm();
        logic [31:0] cmd;
    begin
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::CMD_START_GEMM] = 1'b1;
        csr.issue_command(cmd);

        `uvm_info("CSR_SMOKE",
            "Issued CSR START_GEMM command",
            UVM_MEDIUM)
    end
    endtask

    task automatic csr_poll_gemm_done(
        input int unsigned timeout_cycles
    );
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        int unsigned cnt;
    begin
        cnt = 0;

        forever begin
            csr.read32_expect_okay(
                ai_accel_csr_access_helper::CSR_DONE_STATUS,
                done_status
            );

            csr.read32_expect_okay(
                ai_accel_csr_access_helper::CSR_ERROR_STATUS,
                error_status
            );

            csr.read32_expect_okay(
                ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS,
                reject_status
            );

            if (error_status != 32'h0000_0000) begin
                `uvm_fatal("CSR_SMOKE/ERROR_STATUS",
                    $sformatf("CSR_ERROR_STATUS became nonzero: 0x%08h",
                        error_status))
            end

            if (reject_status != 32'h0000_0000) begin
                `uvm_fatal("CSR_SMOKE/REJECT_STATUS",
                    $sformatf("CSR_CMD_REJECT_STATUS became nonzero: 0x%08h",
                        reject_status))
            end

            if (done_status[ai_accel_csr_access_helper::DONE_GEMM]) begin
                `uvm_info("CSR_SMOKE",
                    $sformatf("Observed CSR GEMM done after %0d poll cycle(s): DONE_STATUS=0x%08h",
                        cnt, done_status),
                    UVM_MEDIUM)
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;

            if (cnt > timeout_cycles) begin
                `uvm_fatal("CSR_SMOKE/DONE_TIMEOUT",
                    $sformatf("Timed out waiting for CSR GEMM done after %0d cycles",
                        timeout_cycles))
            end
        end
    end
    endtask

    task automatic csr_check_perf_snapshot();
        logic [31:0] busy_cycles;
        logic [31:0] mac_count;
        logic [31:0] output_count;
    begin
        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_PERF_BUSY_CYCLES,
            busy_cycles
        );

        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_PERF_MAC_COUNT,
            mac_count
        );

        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_PERF_OUTPUT_COUNT,
            output_count
        );

        `uvm_info("CSR_SMOKE",
            $sformatf("CSR perf snapshot: busy_cycles=%0d mac_count=%0d output_count=%0d",
                busy_cycles, mac_count, output_count),
            UVM_MEDIUM)
    end
    endtask

    // ------------------------------------------------------------
    // Direct result compare
    // ------------------------------------------------------------
    task automatic compare_result_vectors(
        input int signed expected_c[],
        input int signed actual_c[]
    );
        int unsigned i;
        int unsigned mismatch_count;
    begin
        if (expected_c.size() != actual_c.size()) begin
            `uvm_fatal("CSR_SMOKE/SIZE",
                $sformatf("C result size mismatch: expected=%0d actual=%0d",
                    expected_c.size(), actual_c.size()))
        end

        mismatch_count = 0;

        for (i = 0; i < expected_c.size(); i++) begin
            if (expected_c[i] !== actual_c[i]) begin
                mismatch_count++;

                if (mismatch_count <= 8) begin
                    `uvm_error("CSR_SMOKE/MISMATCH",
                        $sformatf("C mismatch idx=%0d expected=%0d actual=%0d",
                            i, expected_c[i], actual_c[i]))
                end
            end
        end

        if (mismatch_count != 0) begin
            `uvm_fatal("CSR_SMOKE/COMPARE_FAIL",
                $sformatf("CSR-controlled GEMM result compare failed: mismatches=%0d/%0d",
                    mismatch_count, expected_c.size()))
        end

        `uvm_info("CSR_SMOKE",
            $sformatf("CSR-controlled GEMM result compare PASS: elements=%0d",
                expected_c.size()),
            UVM_MEDIUM)
    end
    endtask

    // ------------------------------------------------------------
    // Run phase
    // ------------------------------------------------------------
    task run_phase(uvm_phase phase);
        ai_accel_subsys_seq_item profile_item;
        int signed               expected_c[];
        int signed               actual_c[];
        bit                      have_expected_payload;
        bit                      have_actual_payload;
    begin
        phase.raise_objection(this);

        `uvm_info("CSR_SMOKE",
            "Starting CSR-controlled host-primary GEMM smoke test",
            UVM_MEDIUM)

        wait_for_reset_release();
        csr.init_bus();
        csr.wait_reset_release();

        if ((selected_test_kind != ai_accel_subsys_seq_item::TEST_KIND_FIXED_BASELINE) &&
            (selected_test_kind != ai_accel_subsys_seq_item::TEST_KIND_VARIABLE_DIM_SMOKE) &&
            (selected_test_kind != ai_accel_subsys_seq_item::TEST_KIND_CONFIGURABLE_BASE)) begin
            `uvm_fatal("CSR_SMOKE/BAD_KIND",
                $sformatf("Unsupported CSR smoke test_kind=%0d CASE_ID=%0d",
                    selected_test_kind, selected_case_id))
        end

        profile_item = build_selected_profile_item();

        prepare_case_result_pre_start(
            expected_c,
            have_expected_payload
        );

        if (!have_expected_payload) begin
            `uvm_fatal("CSR_SMOKE/NO_EXPECTED",
                "Expected payload was not prepared")
        end

        csr_clear_sticky_status();
        csr_write_gemm_config(profile_item);
        csr_start_gemm();
        csr_poll_gemm_done(done_timeout_cycles);
        csr_check_perf_snapshot();

        collect_case_actual_post_done(
            actual_c,
            have_actual_payload
        );

        if (!have_actual_payload) begin
            `uvm_fatal("CSR_SMOKE/NO_ACTUAL",
                "Actual C payload was not collected")
        end

        compare_result_vectors(expected_c, actual_c);

        `uvm_info("CSR_SMOKE",
            $sformatf("CSR-controlled host-primary GEMM smoke completed: CASE_ID=%0d test_kind=%0d",
                selected_case_id, selected_test_kind),
            UVM_MEDIUM)

        phase.drop_objection(this);
    end
    endtask

endclass

`endif
