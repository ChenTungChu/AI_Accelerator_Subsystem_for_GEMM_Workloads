// File: tb/uvm/test/ai_accel_subsys_reset_recovery_test.sv
`ifndef AI_ACCEL_SUBSYS_RESET_RECOVERY_TEST_SV
`define AI_ACCEL_SUBSYS_RESET_RECOVERY_TEST_SV

// ------------------------------------------------------------
// Reset-recovery test
//
// This test extends the base smoke-test flow to check whether
// the subsystem can recover cleanly after a runtime reset.
//
// Main responsibilities:
//   - run one known-good job before reset
//   - apply a controlled recovery reset through ctrl_if
//   - confirm reset clears busy/done state
//   - run another job after reset
//   - reuse the inherited pre-start / post-done memory flow
//
// Memory path policy follows the same Policy B as smoke_test:
//   - default path  = host agent
//   - fallback path = helper
// ------------------------------------------------------------

class ai_accel_subsys_reset_recovery_test extends ai_accel_subsys_smoke_test;
    `uvm_component_utils(ai_accel_subsys_reset_recovery_test)

    // ------------------------------------------------------------
    // Default reset-recovery recipe
    // ------------------------------------------------------------
    localparam int unsigned DEFAULT_PRE_RESET_CASE_ID        = 5;
    localparam int unsigned DEFAULT_POST_RESET_CASE_ID       = 101;
    localparam int unsigned DEFAULT_RESET_HOLD_CYCLES        = 5;
    localparam int unsigned DEFAULT_POST_RESET_SETTLE_CYCLES = 5;

    // ------------------------------------------------------------
    // Selected cases / reset knobs
    // ------------------------------------------------------------
    int unsigned pre_reset_case_id;
    int unsigned post_reset_case_id;

    ai_accel_subsys_seq_item::test_kind_e pre_reset_test_kind;
    ai_accel_subsys_seq_item::test_kind_e post_reset_test_kind;

    int unsigned reset_hold_cycles;
    int unsigned post_reset_settle_cycles;

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_reset_recovery_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // ------------------------------------------------------------
    // Parse reset-recovery selection
    //
    // Examples:
    //   +PRE_RESET_CASE_ID=5   +POST_RESET_CASE_ID=101
    //   +PRE_RESET_CASE_ID=5   +POST_RESET_CASE_ID=5
    //   +PRE_RESET_CASE_ID=400 +POST_RESET_CASE_ID=403
    //   +RESET_HOLD_CYCLES=8   +POST_RESET_SETTLE_CYCLES=8
    // ------------------------------------------------------------
    function void parse_reset_recovery_selection();
        if (!$value$plusargs("PRE_RESET_CASE_ID=%d", pre_reset_case_id)) begin
            pre_reset_case_id = DEFAULT_PRE_RESET_CASE_ID;
        end

        if (!$value$plusargs("POST_RESET_CASE_ID=%d", post_reset_case_id)) begin
            post_reset_case_id = DEFAULT_POST_RESET_CASE_ID;
        end

        if (!$value$plusargs("RESET_HOLD_CYCLES=%d", reset_hold_cycles)) begin
            reset_hold_cycles = DEFAULT_RESET_HOLD_CYCLES;
        end

        if (!$value$plusargs("POST_RESET_SETTLE_CYCLES=%d", post_reset_settle_cycles)) begin
            post_reset_settle_cycles = DEFAULT_POST_RESET_SETTLE_CYCLES;
        end

        pre_reset_test_kind  = infer_test_kind(pre_reset_case_id);
        post_reset_test_kind = infer_test_kind(post_reset_case_id);

        `uvm_info("RESET_TEST",
            $sformatf("Selected PRE_RESET_CASE_ID=%0d kind=%0d, POST_RESET_CASE_ID=%0d kind=%0d, RESET_HOLD_CYCLES=%0d, POST_RESET_SETTLE_CYCLES=%0d",
                pre_reset_case_id,  pre_reset_test_kind,
                post_reset_case_id, post_reset_test_kind,
                reset_hold_cycles, post_reset_settle_cycles),
            UVM_MEDIUM)
    endfunction

    // ------------------------------------------------------------
    // Build phase
    //
    // This test does not call smoke_test.build_phase(), because
    // smoke_test assumes a single selected case.
    //
    // Here reset-recovery test manages:
    //   - its own pre-reset / post-reset case selection
    //   - the shared Policy B memory-path setup
    //   - env configuration for recovery-reset execution
    // ------------------------------------------------------------
    function void build_phase(uvm_phase phase);

        if (!uvm_config_db#(virtual ai_accel_subsys_ctrl_if)::get(
                this, "", "vif", vif)) begin
            `uvm_fatal("TEST/NOVIF",
                "virtual interface ai_accel_subsys_ctrl_if is not set for ai_accel_subsys_reset_recovery_test")
        end

        parse_result_check_enable();
        parse_force_helper_mem_path_enable();
        parse_host_agent_clear_c_enable();
        parse_host_agent_readback_c_enable();
        parse_host_agent_preload_ab_enable();
        parse_reset_recovery_selection();

        if (enable_result_check) begin
            if (!uvm_config_db#(axi0_vif_t)::get(
                    this, "", "axi0_vif", axi0_vif)) begin
                `uvm_fatal("TEST/NOAXIVIF",
                    "axi0_vif is not set for ai_accel_subsys_reset_recovery_test")
            end
        end

        // Pass control interface down to env
        uvm_config_db#(virtual ai_accel_subsys_ctrl_if)::set(
            this, "env", "vif", vif);

        // Pass axi0_vif down when result-check flow is enabled
        if (enable_result_check) begin
            uvm_config_db#(axi0_vif_t)::set(
                this, "env", "axi0_vif", axi0_vif);
        end

        // Policy B:
        //   host agent is ACTIVE only when at least one memory path
        //   is routed through host agent for this run.
        if (enable_result_check && any_host_agent_mem_path_enabled()) begin
            uvm_config_db#(uvm_active_passive_enum)::set(
                this, "env", "host_is_active", UVM_ACTIVE);
        end
        else begin
            uvm_config_db#(uvm_active_passive_enum)::set(
                this, "env", "host_is_active", UVM_PASSIVE);
        end

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
    // Wait for a re-armed acc_done event
    //
    // This is used before sampling the next completion so a stale
    // done signal from the previous phase is not mistaken as new.
    // ------------------------------------------------------------
    task automatic wait_for_acc_done_rearmed(
        int unsigned timeout_cycles = DEFAULT_DONE_TIMEOUT_CYCLES
    );
        int unsigned cnt;
    begin
        cnt = 0;

        @vif.cb_mon;

        // If previous state left acc_done high, wait for it to clear
        while (vif.cb_mon.acc_done === 1'b1) begin
            @vif.cb_mon;
            cnt++;

            if (cnt > timeout_cycles) begin
                `uvm_fatal("RESET_DONE_STUCK_HIGH",
                    $sformatf("Timed out waiting for stale acc_done to deassert after %0d cycles",
                        timeout_cycles))
            end
        end

        // Wait for new acc_done assertion
        while (vif.cb_mon.acc_done !== 1'b1) begin
            @vif.cb_mon;
            cnt++;

            if (cnt > timeout_cycles) begin
                `uvm_fatal("RESET_TIMEOUT",
                    $sformatf("Timed out waiting for new acc_done after %0d cycles",
                        timeout_cycles))
            end
        end

        `uvm_info("RESET_TEST",
            $sformatf("Observed new acc_done after %0d monitor cycles", cnt),
            UVM_MEDIUM)
    end
    endtask

    // ------------------------------------------------------------
    // Run one job using the inherited smoke-test pipeline
    //
    // Flow for each job:
    //   1. bind selected case context
    //   2. prepare pre-start payload / memory state
    //   3. launch control sequence
    //   4. wait for a fresh acc_done
    //   5. collect post-done data and publish compare payload
    // ------------------------------------------------------------
    task automatic run_one_job(
        input int unsigned case_id,
        input ai_accel_subsys_seq_item::test_kind_e test_kind,
        input int unsigned job_idx
    );
        ai_accel_subsys_smoke_seq seq;

        int signed expected_c[];
        int signed actual_c[];
        bit        have_expected_payload;
        bit        have_actual_payload;
    begin
        // Rebind inherited selected-case context for reuse
        selected_case_id   = case_id;
        selected_test_kind = test_kind;

        if ((env == null) || (env.agent == null) || (env.agent.monitor == null)) begin
            `uvm_fatal("RESET/NOMON",
                "env.agent.monitor is null before setting runtime case context")
        end

        env.agent.monitor.set_case_context(selected_case_id, selected_test_kind);

        `uvm_info("RESET_TEST",
            $sformatf("Starting job%0d with CASE_ID=%0d test_kind=%0d",
                job_idx, selected_case_id, selected_test_kind),
            UVM_MEDIUM)

        if (enable_result_check) begin
            prepare_case_result_pre_start(expected_c, have_expected_payload);

            if (!have_expected_payload) begin
                `uvm_fatal("RESET/NO_EXPECTED_PAYLOAD",
                    $sformatf("job%0d CASE_ID=%0d failed to prepare expected payload",
                        job_idx, selected_case_id))
            end
        end

        seq = ai_accel_subsys_smoke_seq::type_id::create(
            $sformatf("seq_job%0d", job_idx)
        );

        seq.case_id   = selected_case_id;
        seq.test_kind = selected_test_kind;

        `uvm_info("RESET_TEST",
            $sformatf("Launching job%0d sequence with CASE_ID=%0d test_kind=%0d",
                job_idx, seq.case_id, seq.test_kind),
            UVM_MEDIUM)

        seq.start(env.agent.sequencer);

        `uvm_info("RESET_TEST",
            $sformatf("job%0d launched, now waiting for acc_done", job_idx),
            UVM_MEDIUM)

        wait_for_acc_done_rearmed();

        if (enable_result_check) begin
            collect_case_actual_post_done(actual_c, have_actual_payload);

            if (!have_actual_payload) begin
                `uvm_fatal("RESET/NO_ACTUAL_PAYLOAD",
                    $sformatf("job%0d CASE_ID=%0d failed to collect actual payload",
                        job_idx, selected_case_id))
            end

            publish_result_to_scoreboard(expected_c, actual_c);
        end

        `uvm_info("RESET_TEST",
            $sformatf("Completed job%0d CASE_ID=%0d", job_idx, selected_case_id),
            UVM_MEDIUM)

        env.agent.monitor.clear_case_context();
        if (env != null) begin
            env.clear_host_case_context();
        end
    end
    endtask

    // ------------------------------------------------------------
    // Apply recovery reset
    //
    // This test drives the reset override signals through ctrl_if
    // so reset can be asserted and released during runtime.
    //
    // Expected ctrl_if signals:
    //   tb_reset_override_en
    //   tb_dma_rst_n_override
    //   tb_core_rst_n_override
    // ------------------------------------------------------------
    task automatic apply_recovery_reset();
    begin
        if ((env != null) && (env.agent != null) && (env.agent.monitor != null)) begin
            env.agent.monitor.clear_case_context();
        end
        if (env != null) begin
            env.clear_host_case_context();
        end

        `uvm_info("RESET_TEST",
            $sformatf("Applying recovery reset: hold=%0d dma cycles, settle=%0d dma cycles",
                reset_hold_cycles, post_reset_settle_cycles),
            UVM_MEDIUM)

        // --------------------------------------------------------
        // Step 1: enable reset override and drive both resets low
        // --------------------------------------------------------
        @vif.cb_drv;
        vif.cb_drv.tb_reset_override_en   <= 1'b1;
        vif.cb_drv.tb_dma_rst_n_override  <= 1'b0;
        vif.cb_drv.tb_core_rst_n_override <= 1'b0;

        // Hold reset low for the requested number of dma cycles
        repeat (reset_hold_cycles) @vif.cb_drv;

        // --------------------------------------------------------
        // Step 2: drive override resets high first
        // --------------------------------------------------------
        vif.cb_drv.tb_dma_rst_n_override  <= 1'b1;
        vif.cb_drv.tb_core_rst_n_override <= 1'b1;

        // Give one cycle for the high level to propagate
        @vif.cb_drv;

        // --------------------------------------------------------
        // Step 3: release override and return control to normal
        // reset ownership
        // --------------------------------------------------------
        vif.cb_drv.tb_reset_override_en   <= 1'b0;
        vif.cb_drv.tb_dma_rst_n_override  <= 1'b1;
        vif.cb_drv.tb_core_rst_n_override <= 1'b1;

        wait_for_reset_release();

        repeat (post_reset_settle_cycles) @vif.cb_mon;

        if (vif.cb_mon.acc_busy === 1'b1) begin
            `uvm_error("RESET/BUSY_STUCK",
                "acc_busy remains high after reset release/settle")
        end

        if (vif.cb_mon.acc_done === 1'b1) begin
            `uvm_error("RESET/DONE_STUCK",
                "acc_done remains high after reset release/settle")
        end

        `uvm_info("RESET_TEST",
            $sformatf("Recovery reset completed: dma_rst_n=%0b core_rst_n=%0b acc_busy=%0b acc_done=%0b",
                vif.cb_mon.dma_rst_n,
                vif.cb_mon.core_rst_n,
                vif.cb_mon.acc_busy,
                vif.cb_mon.acc_done),
            UVM_MEDIUM)
    end
    endtask

    // ------------------------------------------------------------
    // Run phase
    //
    // Flow:
    //   1. wait for reset release
    //   2. run one known-good job before reset
    //   3. apply recovery reset
    //   4. run one job after reset
    //   5. clear remaining runtime context
    // ------------------------------------------------------------
    task run_phase(uvm_phase phase);
    begin
        phase.raise_objection(this);

        `uvm_info("RESET_TEST",
            "Starting ai_accel_subsys_reset_recovery_test",
            UVM_MEDIUM)

        wait_for_reset_release();

        // Phase 1: run one job before reset
        run_one_job(pre_reset_case_id, pre_reset_test_kind, 0);

        // Phase 2: apply recovery reset
        apply_recovery_reset();

        // Phase 3: run one job after reset
        run_one_job(post_reset_case_id, post_reset_test_kind, 1);

        if ((env != null) && (env.agent != null) && (env.agent.monitor != null)) begin
            env.agent.monitor.clear_case_context();
        end
        if (env != null) begin
            env.clear_host_case_context();
        end

        `uvm_info("RESET_TEST",
            "Reset recovery test completed",
            UVM_MEDIUM)

        phase.drop_objection(this);
    end
    endtask

endclass

`endif