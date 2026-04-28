// File: tb/uvm/test/ai_accel_subsys_corner_test.sv
`ifndef AI_ACCEL_SUBSYS_CORNER_TEST_SV
`define AI_ACCEL_SUBSYS_CORNER_TEST_SV

class ai_accel_subsys_corner_test extends ai_accel_subsys_smoke_test;
    `uvm_component_utils(ai_accel_subsys_corner_test)

    // ------------------------------------------------------------
    // Corner recipe limits / defaults
    // ------------------------------------------------------------
    localparam int unsigned MAX_CORNER_JOBS            = 4;
    localparam int unsigned DEFAULT_JOB_COUNT          = 4;
    localparam int unsigned DEFAULT_JOB0_CASE_ID       = 5;
    localparam int unsigned DEFAULT_JOB1_CASE_ID       = 101;
    localparam int unsigned DEFAULT_JOB2_CASE_ID       = 105;
    localparam int unsigned DEFAULT_JOB3_CASE_ID       = 403;
    localparam int unsigned DEFAULT_INTER_JOB_IDLE_CYC = 2;

    // ------------------------------------------------------------
    // Selected corner recipe
    // ------------------------------------------------------------
    int unsigned job_count;
    int unsigned job_case_id [MAX_CORNER_JOBS];
    ai_accel_subsys_seq_item::test_kind_e job_test_kind [MAX_CORNER_JOBS];

    int unsigned inter_job_idle_cycles;

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_corner_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // ------------------------------------------------------------
    // Parse corner selection
    //
    // Reuses the same JOB_COUNT / JOB0..JOB3_CASE_ID plusargs
    // style already used by back-to-back runs.
    //
    // Example:
    //   +JOB_COUNT=4
    //   +JOB0_CASE_ID=5
    //   +JOB1_CASE_ID=101
    //   +JOB2_CASE_ID=105
    //   +JOB3_CASE_ID=403
    // ------------------------------------------------------------
    function void parse_corner_selection();
        if (!$value$plusargs("JOB_COUNT=%d", job_count)) begin
            job_count = DEFAULT_JOB_COUNT;
        end

        if ((job_count == 0) || (job_count > MAX_CORNER_JOBS)) begin
            `uvm_fatal("CORNER/BAD_JOB_COUNT",
                $sformatf("Unsupported JOB_COUNT=%0d, valid range is 1..%0d",
                    job_count, MAX_CORNER_JOBS))
        end

        if (!$value$plusargs("JOB0_CASE_ID=%d", job_case_id[0])) begin
            job_case_id[0] = DEFAULT_JOB0_CASE_ID;
        end

        if (!$value$plusargs("JOB1_CASE_ID=%d", job_case_id[1])) begin
            job_case_id[1] = DEFAULT_JOB1_CASE_ID;
        end

        if (!$value$plusargs("JOB2_CASE_ID=%d", job_case_id[2])) begin
            job_case_id[2] = DEFAULT_JOB2_CASE_ID;
        end

        if (!$value$plusargs("JOB3_CASE_ID=%d", job_case_id[3])) begin
            job_case_id[3] = DEFAULT_JOB3_CASE_ID;
        end

        inter_job_idle_cycles = DEFAULT_INTER_JOB_IDLE_CYC;

        for (int i = 0; i < MAX_CORNER_JOBS; i++) begin
            job_test_kind[i] = infer_test_kind(job_case_id[i]);
        end

        `uvm_info("CORNER_TEST",
            $sformatf("Selected JOB_COUNT=%0d, INTER_JOB_IDLE_CYCLES=%0d",
                job_count, inter_job_idle_cycles),
            UVM_MEDIUM)

        for (int i = 0; i < job_count; i++) begin
            `uvm_info("CORNER_TEST",
                $sformatf("Job%0d CASE_ID=%0d kind=%0d",
                    i, job_case_id[i], job_test_kind[i]),
                UVM_MEDIUM)
        end
    endfunction

    // ------------------------------------------------------------
    // Build phase
    //
    // Intentionally do not call smoke_test.build_phase(), because
    // this test manages multiple jobs dynamically.
    // ------------------------------------------------------------
    function void build_phase(uvm_phase phase);

        if (!uvm_config_db#(virtual ai_accel_subsys_ctrl_if)::get(
                this, "", "vif", vif)) begin
            `uvm_fatal("TEST/NOVIF",
                "virtual interface ai_accel_subsys_ctrl_if is not set for ai_accel_subsys_corner_test")
        end

        parse_result_check_enable();
        parse_force_helper_mem_path_enable();
        parse_host_agent_clear_c_enable();
        parse_host_agent_readback_c_enable();
        parse_host_agent_preload_ab_enable();
        parse_corner_selection();

        if (enable_result_check) begin
            if (!uvm_config_db#(axi0_vif_t)::get(
                    this, "", "axi0_vif", axi0_vif)) begin
                `uvm_fatal("TEST/NOAXIVIF",
                    "axi0_vif is not set for ai_accel_subsys_corner_test")
            end
        end

        // Pass vif down to env
        uvm_config_db#(virtual ai_accel_subsys_ctrl_if)::set(
            this, "env", "vif", vif);

        // Pass axi0_vif down to env explicitly when result-check is enabled
        if (enable_result_check) begin
            uvm_config_db#(axi0_vif_t)::set(
                this, "env", "axi0_vif", axi0_vif);
        end

        // Host agent migration policy:
        //   ACTIVE when any migrated mem op uses host agent
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
    // Wait for previous acc_done to clear, then wait for a new
    // acc_done assertion for the current job.
    // ------------------------------------------------------------
    task automatic wait_for_acc_done_rearmed(
        int unsigned timeout_cycles = DEFAULT_DONE_TIMEOUT_CYCLES
    );
        int unsigned cnt;
    begin
        cnt = 0;

        @vif.cb_mon;

        // If previous job left acc_done high, wait for it to clear
        while (vif.cb_mon.acc_done === 1'b1) begin
            @vif.cb_mon;
            cnt++;

            if (cnt > timeout_cycles) begin
                `uvm_fatal("CORNER_DONE_STUCK_HIGH",
                    $sformatf("Timed out waiting for stale acc_done to deassert after %0d cycles",
                        timeout_cycles))
            end
        end

        // Wait for new acc_done assertion
        while (vif.cb_mon.acc_done !== 1'b1) begin
            @vif.cb_mon;
            cnt++;

            if (cnt > timeout_cycles) begin
                `uvm_fatal("CORNER_TIMEOUT",
                    $sformatf("Timed out waiting for new acc_done after %0d cycles",
                        timeout_cycles))
            end
        end

        `uvm_info("CORNER_TEST",
            $sformatf("Observed new acc_done after %0d monitor cycles", cnt),
            UVM_MEDIUM)
    end
    endtask

    // ------------------------------------------------------------
    // Optional idle gap between jobs
    //
    // Goal:
    //   - add a small reuse window between consecutive jobs
    //   - confirm subsystem is not stuck busy between jobs
    // ------------------------------------------------------------
    task automatic wait_inter_job_idle_gap(
        input int unsigned completed_job_idx
    );
    begin
        if (inter_job_idle_cycles == 0)
            return;

        repeat (inter_job_idle_cycles) @vif.cb_mon;

        if (vif.cb_mon.acc_busy === 1'b1) begin
            `uvm_error("CORNER/BUSY_DURING_IDLE_GAP",
                $sformatf("acc_busy remains high during inter-job idle gap after job%0d",
                    completed_job_idx))
        end

        `uvm_info("CORNER_TEST",
            $sformatf("Completed inter-job idle gap after job%0d (%0d monitor cycles)",
                completed_job_idx, inter_job_idle_cycles),
            UVM_MEDIUM)
    end
    endtask

    // ------------------------------------------------------------
    // Run one job using the inherited smoke-test helper pipeline
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
        // Rebind inherited selected_* context for helper reuse
        selected_case_id   = case_id;
        selected_test_kind = test_kind;

        if ((env == null) || (env.agent == null) || (env.agent.monitor == null)) begin
            `uvm_fatal("CORNER/NOMON",
                "env.agent.monitor is null before setting runtime case context")
        end

        env.agent.monitor.set_case_context(selected_case_id, selected_test_kind);

        `uvm_info("CORNER_TEST",
            $sformatf("Starting job%0d with CASE_ID=%0d test_kind=%0d",
                job_idx, selected_case_id, selected_test_kind),
            UVM_MEDIUM)

        if (enable_result_check) begin
            prepare_case_result_pre_start(expected_c, have_expected_payload);

            if (!have_expected_payload) begin
                `uvm_fatal("CORNER/NO_EXPECTED_PAYLOAD",
                    $sformatf("job%0d CASE_ID=%0d failed to prepare expected payload",
                        job_idx, selected_case_id))
            end
        end

        seq = ai_accel_subsys_smoke_seq::type_id::create(
            $sformatf("seq_job%0d", job_idx)
        );

        seq.case_id   = selected_case_id;
        seq.test_kind = selected_test_kind;

        `uvm_info("CORNER_TEST",
            $sformatf("Launching job%0d sequence with CASE_ID=%0d test_kind=%0d",
                job_idx, seq.case_id, seq.test_kind),
            UVM_MEDIUM)

        seq.start(env.agent.sequencer);

        `uvm_info("CORNER_TEST",
            $sformatf("job%0d launched, now waiting for acc_done", job_idx),
            UVM_MEDIUM)

        wait_for_acc_done_rearmed();

        if (enable_result_check) begin
            collect_case_actual_post_done(actual_c, have_actual_payload);

            if (!have_actual_payload) begin
                `uvm_fatal("CORNER/NO_ACTUAL_PAYLOAD",
                    $sformatf("job%0d CASE_ID=%0d failed to collect actual payload",
                        job_idx, selected_case_id))
            end

            publish_result_to_scoreboard(expected_c, actual_c);
        end

        `uvm_info("CORNER_TEST",
            $sformatf("Completed job%0d CASE_ID=%0d", job_idx, selected_case_id),
            UVM_MEDIUM)

        env.agent.monitor.clear_case_context();
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

        `uvm_info("CORNER_TEST",
            "Starting ai_accel_subsys_corner_test",
            UVM_MEDIUM)

        wait_for_reset_release();

        for (int i = 0; i < job_count; i++) begin
            run_one_job(job_case_id[i], job_test_kind[i], i);

            if (i != (job_count - 1)) begin
                wait_inter_job_idle_gap(i);
            end
        end

        if ((env != null) && (env.agent != null) && (env.agent.monitor != null)) begin
            env.agent.monitor.clear_case_context();
        end
        if (env != null) begin
            env.clear_host_case_context();
        end

        `uvm_info("CORNER_TEST",
            "Corner test completed",
            UVM_MEDIUM)

        phase.drop_objection(this);
    end
    endtask

endclass

`endif