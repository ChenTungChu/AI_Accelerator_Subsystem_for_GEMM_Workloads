// File: tb/uvm/test/ai_accel_subsys_midrun_reset_test.sv
`ifndef AI_ACCEL_SUBSYS_MIDRUN_RESET_TEST_SV
`define AI_ACCEL_SUBSYS_MIDRUN_RESET_TEST_SV

class ai_accel_subsys_midrun_reset_test extends ai_accel_subsys_smoke_test;
    `uvm_component_utils(ai_accel_subsys_midrun_reset_test)

    // ------------------------------------------------------------
    // Defaults
    // ------------------------------------------------------------
    localparam int unsigned DEFAULT_ABORT_CASE_ID                  = 5;
    localparam int unsigned DEFAULT_RECOVERY_CASE_ID               = 101;
    localparam int unsigned DEFAULT_RESET_TRIGGER_CYCLES_AFTER_BUSY = 8;
    localparam int unsigned DEFAULT_RESET_HOLD_CYCLES              = 5;
    localparam int unsigned DEFAULT_POST_RESET_SETTLE_CYCLES       = 5;
    localparam int unsigned DEFAULT_BUSY_WAIT_TIMEOUT_CYCLES       = DEFAULT_DONE_TIMEOUT_CYCLES;

    // ------------------------------------------------------------
    // Selected cases / knobs
    // ------------------------------------------------------------
    int unsigned abort_case_id;
    int unsigned recovery_case_id;

    ai_accel_subsys_seq_item::test_kind_e abort_test_kind;
    ai_accel_subsys_seq_item::test_kind_e recovery_test_kind;

    int unsigned reset_trigger_cycles_after_busy;
    int unsigned reset_hold_cycles;
    int unsigned post_reset_settle_cycles;
    int unsigned busy_wait_timeout_cycles;

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_midrun_reset_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // ------------------------------------------------------------
    // Parse test selection
    //
    // Preferred knobs:
    //   +ABORT_CASE_ID
    //   +RECOVERY_CASE_ID
    //   +RESET_TRIGGER_CYCLES_AFTER_BUSY
    //
    // Compatible fallback knobs:
    //   +PRE_RESET_CASE_ID
    //   +POST_RESET_CASE_ID
    //   +RESET_HOLD_CYCLES
    //   +POST_RESET_SETTLE_CYCLES
    // ------------------------------------------------------------
    function void parse_midrun_reset_selection();
        if (!$value$plusargs("ABORT_CASE_ID=%d", abort_case_id)) begin
            if (!$value$plusargs("PRE_RESET_CASE_ID=%d", abort_case_id)) begin
                abort_case_id = DEFAULT_ABORT_CASE_ID;
            end
        end

        if (!$value$plusargs("RECOVERY_CASE_ID=%d", recovery_case_id)) begin
            if (!$value$plusargs("POST_RESET_CASE_ID=%d", recovery_case_id)) begin
                recovery_case_id = DEFAULT_RECOVERY_CASE_ID;
            end
        end

        abort_test_kind    = infer_test_kind(abort_case_id);
        recovery_test_kind = infer_test_kind(recovery_case_id);

        if (!$value$plusargs("RESET_TRIGGER_CYCLES_AFTER_BUSY=%d",
                             reset_trigger_cycles_after_busy)) begin
            reset_trigger_cycles_after_busy = DEFAULT_RESET_TRIGGER_CYCLES_AFTER_BUSY;
        end

        if (!$value$plusargs("RESET_HOLD_CYCLES=%d", reset_hold_cycles)) begin
            reset_hold_cycles = DEFAULT_RESET_HOLD_CYCLES;
        end

        if (!$value$plusargs("POST_RESET_SETTLE_CYCLES=%d",
                             post_reset_settle_cycles)) begin
            post_reset_settle_cycles = DEFAULT_POST_RESET_SETTLE_CYCLES;
        end

        if (!$value$plusargs("BUSY_WAIT_TIMEOUT_CYCLES=%d",
                             busy_wait_timeout_cycles)) begin
            busy_wait_timeout_cycles = DEFAULT_BUSY_WAIT_TIMEOUT_CYCLES;
        end

        `uvm_info("MIDRESET_TEST",
            $sformatf(
                "Selected ABORT_CASE_ID=%0d kind=%0d, RECOVERY_CASE_ID=%0d kind=%0d, RESET_TRIGGER_CYCLES_AFTER_BUSY=%0d, RESET_HOLD_CYCLES=%0d, POST_RESET_SETTLE_CYCLES=%0d",
                abort_case_id,
                abort_test_kind,
                recovery_case_id,
                recovery_test_kind,
                reset_trigger_cycles_after_busy,
                reset_hold_cycles,
                post_reset_settle_cycles
            ),
            UVM_MEDIUM)
    endfunction

    // ------------------------------------------------------------
    // Build phase
    //
    // Similar style to corner/reset tests:
    //   - parse smoke-test policy knobs
    //   - parse midrun-reset knobs
    //   - build env/helpers
    //
    // Also pre-wire a few config_db knobs for the next milestone,
    // where scoreboard/checker will explicitly support one
    // expected aborted job.
    // ------------------------------------------------------------
    function void build_phase(uvm_phase phase);

        if (!uvm_config_db#(virtual ai_accel_subsys_ctrl_if)::get(
                this, "", "vif", vif)) begin
            `uvm_fatal("TEST/NOVIF",
                "virtual interface ai_accel_subsys_ctrl_if is not set for ai_accel_subsys_midrun_reset_test")
        end

        parse_result_check_enable();
        parse_force_helper_mem_path_enable();
        parse_host_agent_clear_c_enable();
        parse_host_agent_readback_c_enable();
        parse_host_agent_preload_ab_enable();
        parse_midrun_reset_selection();

        if (enable_result_check) begin
            if (!uvm_config_db#(axi0_vif_t)::get(
                    this, "", "axi0_vif", axi0_vif)) begin
                `uvm_fatal("TEST/NOAXIVIF",
                    "axi0_vif is not set for ai_accel_subsys_midrun_reset_test")
            end
        end

        // Pass vif down to env
        uvm_config_db#(virtual ai_accel_subsys_ctrl_if)::set(
            this, "env", "vif", vif);

        // Pass axi0_vif down to env when result-check is enabled
        if (enable_result_check) begin
            uvm_config_db#(axi0_vif_t)::set(
                this, "env", "axi0_vif", axi0_vif);
        end

        // Host agent policy
        if (enable_result_check && any_host_agent_mem_path_enabled()) begin
            uvm_config_db#(uvm_active_passive_enum)::set(
                this, "env", "host_is_active", UVM_ACTIVE);
        end
        else begin
            uvm_config_db#(uvm_active_passive_enum)::set(
                this, "env", "host_is_active", UVM_PASSIVE);
        end

        // Existing scoreboard result-compare knob
        uvm_config_db#(bit)::set(
            this, "env.scoreboard", "result_check_enable", enable_result_check);

        // --------------------------------------------------------
        // Pre-wire next-step expected-abort knobs.
        // Current environment may ignore these for now.
        // --------------------------------------------------------
        uvm_config_db#(bit)::set(
            this, "env.scoreboard", "midrun_reset_test_mode", 1'b1);
        uvm_config_db#(int unsigned)::set(
            this, "env.scoreboard", "expected_aborted_job_count", 1);

        uvm_config_db#(bit)::set(
            this, "env.host_traffic_checker", "midrun_reset_test_mode", 1'b1);
        uvm_config_db#(int unsigned)::set(
            this, "env.host_traffic_checker", "expected_aborted_job_count", 1);

        env = ai_accel_subsys_env::type_id::create("env", this);

        case_helper     = ai_accel_subsys_case_helper    ::type_id::create("case_helper");
        axi_host_helper = ai_accel_subsys_axi_host_helper::type_id::create("axi_host_helper");

        if (enable_result_check) begin
            axi_host_helper.set_vif(axi0_vif);
        end
    endfunction

    // ------------------------------------------------------------
    // Wait until active compute is clearly in progress, then hold
    // a few more monitor cycles before issuing reset.
    // ------------------------------------------------------------
    task automatic wait_until_busy_then_trigger_reset();
        int unsigned wait_cycles;
        int unsigned extra_cycles;
    begin
        wait_cycles = 0;

        @vif.cb_mon;

        while (vif.cb_mon.acc_busy !== 1'b1) begin
            @vif.cb_mon;
            wait_cycles++;

            if (vif.cb_mon.acc_done === 1'b1) begin
                `uvm_fatal("MIDRESET/DONE_TOO_EARLY",
                    "acc_done asserted before mid-run reset trigger could be armed")
            end

            if (wait_cycles > busy_wait_timeout_cycles) begin
                `uvm_fatal("MIDRESET/BUSY_TIMEOUT",
                    $sformatf("Timed out waiting for acc_busy to assert after %0d cycles",
                        busy_wait_timeout_cycles))
            end
        end

        `uvm_info("MIDRESET_TEST",
            $sformatf("Observed acc_busy=1 after %0d monitor cycles, delaying reset by %0d more cycles",
                wait_cycles, reset_trigger_cycles_after_busy),
            UVM_MEDIUM)

        extra_cycles = 0;
        while (extra_cycles < reset_trigger_cycles_after_busy) begin
            @vif.cb_mon;
            extra_cycles++;

            if (vif.cb_mon.acc_done === 1'b1) begin
                `uvm_fatal("MIDRESET/DONE_BEFORE_ABORT",
                    $sformatf("acc_done asserted before scheduled mid-run reset after %0d extra cycles",
                        extra_cycles))
            end

            if (vif.cb_mon.acc_busy !== 1'b1) begin
                `uvm_error("MIDRESET/BUSY_DROPPED_EARLY",
                    $sformatf("acc_busy dropped before reset trigger at extra cycle %0d",
                        extra_cycles))
            end
        end
    end
    endtask

    // ------------------------------------------------------------
    // Apply mid-run reset
    //
    // Uses the same vif override style as reset_recovery_test v2.
    // ------------------------------------------------------------
    task automatic apply_midrun_reset();
    begin
        if ((env != null) && (env.agent != null) && (env.agent.monitor != null)) begin
            env.agent.monitor.clear_case_context();
        end
        if (env != null) begin
            env.clear_host_case_context();
        end

        `uvm_info("MIDRESET_TEST",
            $sformatf("Applying mid-run reset: hold=%0d dma cycles, settle=%0d dma cycles",
                reset_hold_cycles, post_reset_settle_cycles),
            UVM_MEDIUM)

        // --------------------------------------------------------
        // Step 1: enable reset override and drive both resets low
        // --------------------------------------------------------
        @vif.cb_drv;
        vif.cb_drv.tb_reset_override_en   <= 1'b1;
        vif.cb_drv.tb_dma_rst_n_override  <= 1'b0;
        vif.cb_drv.tb_core_rst_n_override <= 1'b0;

        repeat (reset_hold_cycles) @vif.cb_drv;

        // --------------------------------------------------------
        // Step 2: drive override resets high first
        // --------------------------------------------------------
        vif.cb_drv.tb_dma_rst_n_override  <= 1'b1;
        vif.cb_drv.tb_core_rst_n_override <= 1'b1;

        @vif.cb_drv;

        // --------------------------------------------------------
        // Step 3: release override, return control to reset mux
        // --------------------------------------------------------
        vif.cb_drv.tb_reset_override_en   <= 1'b0;
        vif.cb_drv.tb_dma_rst_n_override  <= 1'b1;
        vif.cb_drv.tb_core_rst_n_override <= 1'b1;

        wait_for_reset_release();

        repeat (post_reset_settle_cycles) @vif.cb_mon;

        if (vif.cb_mon.acc_busy === 1'b1) begin
            `uvm_error("MIDRESET/BUSY_STUCK",
                "acc_busy remains high after mid-run reset release/settle")
        end

        if (vif.cb_mon.acc_done === 1'b1) begin
            `uvm_error("MIDRESET/DONE_STUCK",
                "acc_done remains high after mid-run reset release/settle")
        end

        `uvm_info("MIDRESET_TEST",
            $sformatf("Mid-run reset completed: dma_rst_n=%0b core_rst_n=%0b acc_busy=%0b acc_done=%0b",
                vif.cb_mon.dma_rst_n,
                vif.cb_mon.core_rst_n,
                vif.cb_mon.acc_busy,
                vif.cb_mon.acc_done),
            UVM_MEDIUM)
    end
    endtask

    // ------------------------------------------------------------
    // Launch one job, wait until busy, then abort it via reset.
    //
    // Pre-start helper flow still runs, because we want the normal
    // memory preparation path before compute begins.
    //
    // No result item is published for this aborted job.
    // ------------------------------------------------------------
    task automatic run_abort_job_until_reset(
        input int unsigned case_id,
        input ai_accel_subsys_seq_item::test_kind_e test_kind,
        input int unsigned job_idx
    );
        ai_accel_subsys_smoke_seq seq;

        int signed dummy_expected_c[];
        bit        have_expected_payload;
    begin
        selected_case_id   = case_id;
        selected_test_kind = test_kind;

        if ((env == null) || (env.agent == null) || (env.agent.monitor == null)) begin
            `uvm_fatal("MIDRESET/NOMON",
                "env.agent.monitor is null before setting runtime case context")
        end

        env.agent.monitor.set_case_context(selected_case_id, selected_test_kind);

        `uvm_info("MIDRESET_TEST",
            $sformatf("Starting abort job%0d with CASE_ID=%0d test_kind=%0d",
                job_idx, selected_case_id, selected_test_kind),
            UVM_MEDIUM)

        if (enable_result_check) begin
            prepare_case_result_pre_start(dummy_expected_c, have_expected_payload);

            if (!have_expected_payload) begin
                `uvm_fatal("MIDRESET/NO_EXPECTED_PAYLOAD",
                    $sformatf("abort job%0d CASE_ID=%0d failed to prepare pre-start payload",
                        job_idx, selected_case_id))
            end
        end

        seq = ai_accel_subsys_smoke_seq::type_id::create(
            $sformatf("abort_seq_job%0d", job_idx)
        );

        seq.case_id   = selected_case_id;
        seq.test_kind = selected_test_kind;

        `uvm_info("MIDRESET_TEST",
            $sformatf("Launching abort job%0d sequence with CASE_ID=%0d test_kind=%0d",
                job_idx, seq.case_id, seq.test_kind),
            UVM_MEDIUM)

        seq.start(env.agent.sequencer);

        `uvm_info("MIDRESET_TEST",
            $sformatf("Abort job%0d launched, waiting for acc_busy before forced reset",
                job_idx),
            UVM_MEDIUM)

        wait_until_busy_then_trigger_reset();
        apply_midrun_reset();

        `uvm_info("MIDRESET_TEST",
            $sformatf("Abort job%0d CASE_ID=%0d was interrupted by reset as intended",
                job_idx, selected_case_id),
            UVM_MEDIUM)

        if ((env != null) && (env.agent != null) && (env.agent.monitor != null)) begin
            env.agent.monitor.clear_case_context();
        end
        if (env != null) begin
            env.clear_host_case_context();
        end
    end
    endtask

    // ------------------------------------------------------------
    // Reuse the normal completed-job flow for post-reset recovery.
    // ------------------------------------------------------------
    task automatic run_recovery_job(
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
        selected_case_id   = case_id;
        selected_test_kind = test_kind;

        if ((env == null) || (env.agent == null) || (env.agent.monitor == null)) begin
            `uvm_fatal("MIDRESET/NOMON",
                "env.agent.monitor is null before setting runtime case context")
        end

        env.agent.monitor.set_case_context(selected_case_id, selected_test_kind);

        `uvm_info("MIDRESET_TEST",
            $sformatf("Starting recovery job%0d with CASE_ID=%0d test_kind=%0d",
                job_idx, selected_case_id, selected_test_kind),
            UVM_MEDIUM)

        if (enable_result_check) begin
            prepare_case_result_pre_start(expected_c, have_expected_payload);

            if (!have_expected_payload) begin
                `uvm_fatal("MIDRESET/NO_EXPECTED_PAYLOAD",
                    $sformatf("recovery job%0d CASE_ID=%0d failed to prepare expected payload",
                        job_idx, selected_case_id))
            end
        end

        seq = ai_accel_subsys_smoke_seq::type_id::create(
            $sformatf("recovery_seq_job%0d", job_idx)
        );

        seq.case_id   = selected_case_id;
        seq.test_kind = selected_test_kind;

        `uvm_info("MIDRESET_TEST",
            $sformatf("Launching recovery job%0d sequence with CASE_ID=%0d test_kind=%0d",
                job_idx, seq.case_id, seq.test_kind),
            UVM_MEDIUM)

        seq.start(env.agent.sequencer);

        `uvm_info("MIDRESET_TEST",
            $sformatf("Recovery job%0d launched, now waiting for acc_done", job_idx),
            UVM_MEDIUM)

        wait_for_acc_done_rearmed();

        if (enable_result_check) begin
            collect_case_actual_post_done(actual_c, have_actual_payload);

            if (!have_actual_payload) begin
                `uvm_fatal("MIDRESET/NO_ACTUAL_PAYLOAD",
                    $sformatf("recovery job%0d CASE_ID=%0d failed to collect actual payload",
                        job_idx, selected_case_id))
            end

            publish_result_to_scoreboard(expected_c, actual_c);
        end

        `uvm_info("MIDRESET_TEST",
            $sformatf("Completed recovery job%0d CASE_ID=%0d",
                job_idx, selected_case_id),
            UVM_MEDIUM)

        if ((env != null) && (env.agent != null) && (env.agent.monitor != null)) begin
            env.agent.monitor.clear_case_context();
        end
        if (env != null) begin
            env.clear_host_case_context();
        end
    end
    endtask

    // ------------------------------------------------------------
    // Run phase
    // ------------------------------------------------------------
    task run_phase(uvm_phase phase);
    begin
        phase.raise_objection(this);

        `uvm_info("MIDRESET_TEST",
            "Starting ai_accel_subsys_midrun_reset_test",
            UVM_MEDIUM)

        wait_for_reset_release();

        // Phase 1: launch a real job, then interrupt it mid-compute
        run_abort_job_until_reset(abort_case_id, abort_test_kind, 0);

        // Phase 2: after reset, run a known-good recovery job
        run_recovery_job(recovery_case_id, recovery_test_kind, 1);

        if ((env != null) && (env.agent != null) && (env.agent.monitor != null)) begin
            env.agent.monitor.clear_case_context();
        end
        if (env != null) begin
            env.clear_host_case_context();
        end

        `uvm_info("MIDRESET_TEST",
            "Mid-run reset test completed",
            UVM_MEDIUM)

        phase.drop_objection(this);
    end
    endtask

endclass

`endif