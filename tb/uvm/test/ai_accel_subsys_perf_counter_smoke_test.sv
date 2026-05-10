// File: tb/uvm/test/ai_accel_subsys_perf_counter_smoke_test.sv

`ifndef AI_ACCEL_SUBSYS_PERF_COUNTER_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_PERF_COUNTER_SMOKE_TEST_SV

class ai_accel_subsys_perf_counter_smoke_test
    extends ai_accel_subsys_smoke_test;

    `uvm_component_utils(ai_accel_subsys_perf_counter_smoke_test)

    // ------------------------------------------------------------
    // Perf smoke configuration
    // ------------------------------------------------------------
    int unsigned perf_run_all;
    int unsigned perf_sample_delay_cycles;

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(
        string name = "ai_accel_subsys_perf_counter_smoke_test",
        uvm_component parent = null
    );
        super.new(name, parent);
    endfunction

    // ------------------------------------------------------------
    // Build phase
    // ------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        int unsigned tmp;
    begin
        super.build_phase(phase);

        perf_run_all              = 0;
        perf_sample_delay_cycles  = 8;

        void'($value$plusargs("RUN_ALL=%0d", perf_run_all));
        void'($value$plusargs("PERF_SAMPLE_DELAY_CYCLES=%0d", perf_sample_delay_cycles));

        // For this perf test, default to CASE_ID=100 if user did
        // not explicitly provide CASE_ID and RUN_ALL is not enabled.
        if ((perf_run_all == 0) && !$value$plusargs("CASE_ID=%0d", tmp)) begin
            selected_case_id   = 100;
            selected_test_kind = infer_test_kind(selected_case_id);

            `uvm_info("PERF_COUNTER_SMOKE",
                "No CASE_ID provided; defaulting perf counter smoke to CASE_ID=100",
                UVM_MEDIUM)
        end

        `uvm_info("PERF_COUNTER_SMOKE",
            $sformatf("Configured perf counter smoke: run_all=%0d sample_delay_cycles=%0d selected_case_id=%0d",
                perf_run_all,
                perf_sample_delay_cycles,
                selected_case_id),
            UVM_MEDIUM)
    end
    endfunction

    // ------------------------------------------------------------
    // Expected MAC count
    //
    // Current GEMM definition:
    //   C[MxN] = A[MxK] x B[KxN]
    //
    // Therefore:
    //   MAC_COUNT    = M * N * K
    //   OUTPUT_COUNT = M * N
    // ------------------------------------------------------------
    function automatic int unsigned calc_expected_mac_count(
        input int unsigned m,
        input int unsigned n,
        input int unsigned k
    );
        return m * n * k;
    endfunction

    function automatic int unsigned calc_expected_output_count(
        input int unsigned m,
        input int unsigned n
    );
        return m * n;
    endfunction

    // ------------------------------------------------------------
    // Monitor runtime context control
    //
    // ai_accel_subsys_perf_counter_smoke_test extends the host
    // primary smoke test, whose default monitor context is static
    // from build_phase. RUN_ALL is multi-case, so each case must
    // update monitor runtime context before acc_start.
    // ------------------------------------------------------------
    task automatic set_perf_monitor_case_context(input int unsigned cid);
        ai_accel_subsys_seq_item::test_kind_e kind;
    begin
        kind = infer_test_kind(cid);

        if (env != null &&
            env.agent != null &&
            env.agent.monitor != null) begin

            env.agent.monitor.set_case_context(cid, kind);
        end
    end
    endtask

    task automatic clear_perf_monitor_case_context();
    begin
        if (env != null &&
            env.agent != null &&
            env.agent.monitor != null) begin

            env.agent.monitor.clear_case_context();
        end
    end
    endtask

    // ------------------------------------------------------------
    // Sample and check performance counters
    //
    // These counters come from gemm_top and are stable after
    // acc_done until the next accepted GEMM start.
    // ------------------------------------------------------------
    task automatic sample_and_check_perf_counters(
        input int unsigned cid,
        input ai_accel_subsys_seq_item profile_item
    );
        int unsigned wait_i;

        logic [31:0] busy_cycles;
        logic [31:0] mac_count;
        logic [31:0] output_count;

        int unsigned expected_mac_count;
        int unsigned expected_output_count;
    begin
        expected_mac_count =
            calc_expected_mac_count(
                int'(profile_item.dim_m),
                int'(profile_item.dim_n),
                int'(profile_item.dim_k)
            );

        expected_output_count =
            calc_expected_output_count(
                int'(profile_item.dim_m),
                int'(profile_item.dim_n)
            );

        for (wait_i = 0; wait_i < perf_sample_delay_cycles; wait_i++) begin
            @(vif.cb_drv);
        end

        busy_cycles = vif.cb_drv.gemm_perf_busy_cycles;
        mac_count   = vif.cb_drv.gemm_perf_mac_count;
        output_count= vif.cb_drv.gemm_perf_output_count;

        `uvm_info("PERF_COUNTER_SMOKE",
            $sformatf("Sampled counters: CASE_ID=%0d dim=(%0d,%0d,%0d) busy_cycles=%0d mac_count=%0d expected_mac=%0d output_count=%0d expected_output=%0d",
                cid,
                profile_item.dim_m,
                profile_item.dim_n,
                profile_item.dim_k,
                busy_cycles,
                mac_count,
                expected_mac_count,
                output_count,
                expected_output_count),
            UVM_LOW)

        if (busy_cycles == 0) begin
            `uvm_fatal("PERF_COUNTER_SMOKE/BUSY_ZERO",
                $sformatf("gemm_perf_busy_cycles is zero for CASE_ID=%0d", cid))
        end

        if (mac_count !== expected_mac_count[31:0]) begin
            `uvm_fatal("PERF_COUNTER_SMOKE/MAC_MISMATCH",
                $sformatf("gemm_perf_mac_count mismatch for CASE_ID=%0d: got=%0d expected=%0d",
                    cid,
                    mac_count,
                    expected_mac_count))
        end

        if (output_count !== expected_output_count[31:0]) begin
            `uvm_fatal("PERF_COUNTER_SMOKE/OUTPUT_MISMATCH",
                $sformatf("gemm_perf_output_count mismatch for CASE_ID=%0d: got=%0d expected=%0d",
                    cid,
                    output_count,
                    expected_output_count))
        end

        `uvm_info("PERF_COUNTER_SMOKE",
            $sformatf("PASS counters: CASE_ID=%0d MAC=%0d OUTPUT=%0d BUSY_CYCLES=%0d",
                cid,
                mac_count,
                output_count,
                busy_cycles),
            UVM_LOW)
    end
    endtask

    // ------------------------------------------------------------
    // Run one perf-counter checked host-primary case
    //
    // This intentionally mirrors the base smoke test flow:
    //   prepare expected payload
    //   launch ai_accel_subsys_smoke_seq
    //   wait acc_done
    //   sample/check counters
    //   collect actual payload
    //   publish scoreboard result
    // ------------------------------------------------------------
    task automatic run_perf_counter_one_case(input int unsigned cid);
        ai_accel_subsys_smoke_seq seq;
        ai_accel_subsys_seq_item  profile_item;

        int signed expected_c[];
        int signed actual_c[];

        bit have_expected_payload;
        bit have_actual_payload;
    begin
        selected_case_id   = cid;
        selected_test_kind = infer_test_kind(selected_case_id);

        profile_item = build_selected_profile_item();

        // Multi-case RUN_ALL needs runtime monitor context.
        // The static config_db context is only valid for the initial CASE_ID.
        // Without this, ctrl START/DONE events stay tagged as the first case.
        set_perf_monitor_case_context(selected_case_id);

        `uvm_info("PERF_COUNTER_SMOKE",
            $sformatf("Starting perf counter checked case: CASE_ID=%0d test_kind=%0d dim=(%0d,%0d,%0d)",
                selected_case_id,
                selected_test_kind,
                profile_item.dim_m,
                profile_item.dim_n,
                profile_item.dim_k),
            UVM_LOW)

        if (enable_result_check) begin
            prepare_case_result_pre_start(expected_c, have_expected_payload);

            if (!have_expected_payload) begin
                `uvm_fatal("PERF_COUNTER_SMOKE/NO_EXPECTED_PAYLOAD",
                    "enable_result_check=1 but expected payload was not prepared")
            end
        end

        seq = ai_accel_subsys_smoke_seq::type_id::create("perf_counter_smoke_seq");

        seq.case_id   = selected_case_id;
        seq.test_kind = selected_test_kind;

        `uvm_info("PERF_COUNTER_SMOKE",
            $sformatf("Launching smoke sequence for perf counter check: CASE_ID=%0d test_kind=%0d",
                seq.case_id,
                seq.test_kind),
            UVM_MEDIUM)

        seq.start(env.agent.sequencer);

        wait_for_acc_done();

        sample_and_check_perf_counters(selected_case_id, profile_item);

        if (enable_result_check) begin
            collect_case_actual_post_done(actual_c, have_actual_payload);

            if (!have_actual_payload) begin
                `uvm_fatal("PERF_COUNTER_SMOKE/NO_ACTUAL_PAYLOAD",
                    "enable_result_check=1 but actual payload was not collected")
            end

            publish_result_to_scoreboard(expected_c, actual_c);
        end

        clear_perf_monitor_case_context();

        `uvm_info("PERF_COUNTER_SMOKE",
            $sformatf("Completed perf counter checked case: CASE_ID=%0d",
                selected_case_id),
            UVM_LOW)
    end
    endtask

    // ------------------------------------------------------------
    // Main run phase
    // ------------------------------------------------------------
    task run_phase(uvm_phase phase);
        phase.raise_objection(this);

        `uvm_info("PERF_COUNTER_SMOKE",
            "Starting ai_accel_subsys_perf_counter_smoke_test",
            UVM_LOW)

        wait_for_reset_release();

        if (perf_run_all != 0) begin
            run_perf_counter_one_case(100);
            repeat (10) @(vif.cb_drv);

            run_perf_counter_one_case(101);
            repeat (10) @(vif.cb_drv);

            run_perf_counter_one_case(105);
            repeat (10) @(vif.cb_drv);

            run_perf_counter_one_case(5);
        end
        else begin
            run_perf_counter_one_case(selected_case_id);
        end

        `uvm_info("PERF_COUNTER_SMOKE",
            "ai_accel_subsys_perf_counter_smoke_test completed",
            UVM_LOW)

        phase.drop_objection(this);
    endtask

endclass

`endif