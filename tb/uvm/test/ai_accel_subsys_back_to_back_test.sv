// File: tb/uvm/test/ai_accel_subsys_back_to_back_test.sv
`ifndef AI_ACCEL_SUBSYS_BACK_TO_BACK_TEST_SV
`define AI_ACCEL_SUBSYS_BACK_TO_BACK_TEST_SV

// ------------------------------------------------------------
// Back-to-back test
//
// This test extends the base smoke-test flow to run multiple
// jobs in one simulation without a full test restart.
//
// Main responsibilities:
//   - parse a list of CASE_ID jobs from plusargs
//   - run each job sequentially
//   - reuse the inherited pre-start / post-done memory flow
//   - confirm that consecutive jobs still complete correctly
//
// Memory path policy follows the same Policy B as smoke_test:
//   - default path  = host agent
//   - fallback path = helper
// ------------------------------------------------------------

class ai_accel_subsys_back_to_back_test extends ai_accel_subsys_smoke_test;
    `uvm_component_utils(ai_accel_subsys_back_to_back_test)

    // ------------------------------------------------------------
    // Multi-job support
    // ------------------------------------------------------------
    localparam int unsigned MAX_BACK_TO_BACK_JOBS = 4;

    // ------------------------------------------------------------
    // Default job recipe
    //
    // Default:
    //   JOB_COUNT = 2
    //   JOB0      = 100
    //   JOB1      = 101
    //
    // Extra defaults are prepared for larger JOB_COUNT use:
    //   JOB2 default = 5
    //   JOB3 default = 400
    // ------------------------------------------------------------
    localparam int unsigned DEFAULT_JOB_COUNT    = 2;
    localparam int unsigned DEFAULT_JOB0_CASE_ID = 100;
    localparam int unsigned DEFAULT_JOB1_CASE_ID = 101;
    localparam int unsigned DEFAULT_JOB2_CASE_ID = 5;
    localparam int unsigned DEFAULT_JOB3_CASE_ID = 400;

    // ------------------------------------------------------------
    // Selected back-to-back jobs
    // ------------------------------------------------------------
    int unsigned job_count;
    int unsigned job_case_id   [0:MAX_BACK_TO_BACK_JOBS-1];
    ai_accel_subsys_seq_item::test_kind_e job_test_kind [0:MAX_BACK_TO_BACK_JOBS-1];

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_back_to_back_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // ------------------------------------------------------------
    // Parse back-to-back job selection
    // ------------------------------------------------------------
    function void parse_back_to_back_selection();
        int unsigned tmp_job_count;
        int unsigned i;
    begin
        if (!$value$plusargs("JOB_COUNT=%d", tmp_job_count)) begin
            tmp_job_count = DEFAULT_JOB_COUNT;
        end

        if ((tmp_job_count < 1) || (tmp_job_count > MAX_BACK_TO_BACK_JOBS)) begin
            `uvm_fatal("B2B/BAD_JOB_COUNT",
                $sformatf("JOB_COUNT=%0d is invalid, supported range is 1..%0d",
                    tmp_job_count, MAX_BACK_TO_BACK_JOBS))
        end

        job_count = tmp_job_count;

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

        for (i = 0; i < job_count; i++) begin
            job_test_kind[i] = infer_test_kind(job_case_id[i]);
        end

        `uvm_info("B2B_TEST",
            $sformatf("Selected JOB_COUNT=%0d", job_count),
            UVM_MEDIUM)

        for (i = 0; i < job_count; i++) begin
            `uvm_info("B2B_TEST",
                $sformatf("Job%0d CASE_ID=%0d kind=%0d",
                    i, job_case_id[i], job_test_kind[i]),
                UVM_MEDIUM)
        end
    end
    endfunction

    // ------------------------------------------------------------
    // Build phase
    //
    // This test does not call smoke_test.build_phase(), because
    // smoke_test assumes a single selected case.
    //
    // Here back-to-back test manages:
    //   - its own job list
    //   - the shared Policy B memory-path setup
    //   - env configuration for multi-job execution
    // ------------------------------------------------------------
    function void build_phase(uvm_phase phase);

        if (!uvm_config_db#(virtual ai_accel_subsys_ctrl_if)::get(
                this, "", "vif", vif)) begin
            `uvm_fatal("TEST/NOVIF",
                "virtual interface ai_accel_subsys_ctrl_if is not set for ai_accel_subsys_back_to_back_test")
        end

        parse_result_check_enable();
        parse_force_helper_mem_path_enable();
        parse_host_agent_clear_c_enable();
        parse_host_agent_readback_c_enable();
        parse_host_agent_preload_ab_enable();
        parse_back_to_back_selection();

        if (enable_result_check) begin
            if (!uvm_config_db#(axi0_vif_t)::get(
                    this, "", "axi0_vif", axi0_vif)) begin
                `uvm_fatal("TEST/NOAXIVIF",
                    "axi0_vif is not set for ai_accel_subsys_back_to_back_test")
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
    // This is used between back-to-back jobs to avoid treating a
    // stale done signal from the previous job as the new one.
    // ------------------------------------------------------------
    task automatic wait_for_acc_done_rearmed(
        int unsigned timeout_cycles = DEFAULT_DONE_TIMEOUT_CYCLES
    );
        int unsigned cnt;
    begin
        cnt = 0;

        @vif.cb_mon;

        while (vif.cb_mon.acc_done === 1'b1) begin
            @vif.cb_mon;
            cnt++;

            if (cnt > timeout_cycles) begin
                `uvm_fatal("B2B_DONE_STUCK_HIGH",
                    $sformatf("Timed out waiting for stale acc_done to deassert after %0d cycles",
                        timeout_cycles))
            end
        end

        while (vif.cb_mon.acc_done !== 1'b1) begin
            @vif.cb_mon;
            cnt++;

            if (cnt > timeout_cycles) begin
                `uvm_fatal("B2B_TIMEOUT",
                    $sformatf("Timed out waiting for new acc_done after %0d cycles",
                        timeout_cycles))
            end
        end

        `uvm_info("B2B_TEST",
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
        selected_case_id   = case_id;
        selected_test_kind = test_kind;

        if ((env == null) || (env.agent == null) || (env.agent.monitor == null)) begin
            `uvm_fatal("B2B/NOMON",
                "env.agent.monitor is null before setting runtime case context")
        end

        env.agent.monitor.set_case_context(selected_case_id, selected_test_kind);

        `uvm_info("B2B_TEST",
            $sformatf("Starting job%0d with CASE_ID=%0d test_kind=%0d",
                job_idx, selected_case_id, selected_test_kind),
            UVM_MEDIUM)

        if (enable_result_check) begin
            prepare_case_result_pre_start(expected_c, have_expected_payload);

            if (!have_expected_payload) begin
                `uvm_fatal("B2B/NO_EXPECTED_PAYLOAD",
                    $sformatf("job%0d CASE_ID=%0d failed to prepare expected payload",
                        job_idx, selected_case_id))
            end
        end

        seq = ai_accel_subsys_smoke_seq::type_id::create(
            $sformatf("seq_job%0d", job_idx)
        );

        seq.case_id   = selected_case_id;
        seq.test_kind = selected_test_kind;

        `uvm_info("B2B_TEST",
            $sformatf("Launching job%0d sequence with CASE_ID=%0d test_kind=%0d",
                job_idx, seq.case_id, seq.test_kind),
            UVM_MEDIUM)

        seq.start(env.agent.sequencer);

        `uvm_info("B2B_TEST",
            $sformatf("job%0d launched, now waiting for acc_done", job_idx),
            UVM_MEDIUM)

        wait_for_acc_done_rearmed();

        if (enable_result_check) begin
            collect_case_actual_post_done(actual_c, have_actual_payload);

            if (!have_actual_payload) begin
                `uvm_fatal("B2B/NO_ACTUAL_PAYLOAD",
                    $sformatf("job%0d CASE_ID=%0d failed to collect actual payload",
                        job_idx, selected_case_id))
            end

            publish_result_to_scoreboard(expected_c, actual_c);
        end

        `uvm_info("B2B_TEST",
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
    //
    // Flow:
    //   1. wait for reset release
    //   2. run each selected job in sequence
    //   3. clear remaining runtime context
    // ------------------------------------------------------------
    task run_phase(uvm_phase phase);
        int unsigned job_idx;
    begin
        phase.raise_objection(this);

        `uvm_info("B2B_TEST",
            "Starting ai_accel_subsys_back_to_back_test",
            UVM_MEDIUM)

        wait_for_reset_release();

        for (job_idx = 0; job_idx < job_count; job_idx++) begin
            run_one_job(job_case_id[job_idx], job_test_kind[job_idx], job_idx);
        end

        if ((env != null) && (env.agent != null) && (env.agent.monitor != null)) begin
            env.agent.monitor.clear_case_context();
        end
        if (env != null) begin
            env.clear_host_case_context();
        end

        `uvm_info("B2B_TEST",
            "Back-to-back test completed",
            UVM_MEDIUM)

        phase.drop_objection(this);
    end
    endtask

endclass

`endif