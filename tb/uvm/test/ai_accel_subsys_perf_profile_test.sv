// File: tb/uvm/test/ai_accel_subsys_perf_profile_test.sv

`ifndef AI_ACCEL_SUBSYS_PERF_PROFILE_TEST_SV
`define AI_ACCEL_SUBSYS_PERF_PROFILE_TEST_SV

class ai_accel_subsys_perf_profile_test
    extends ai_accel_subsys_perf_counter_smoke_test;

    `uvm_component_utils(ai_accel_subsys_perf_profile_test)

    // ------------------------------------------------------------
    // Profile configuration
    // ------------------------------------------------------------
    int unsigned profile_sample_delay_cycles;
    int unsigned profile_gap_cycles;

    localparam int unsigned PERF_PROFILE_CASE_COUNT = 8;
    int unsigned profile_cases [PERF_PROFILE_CASE_COUNT];

    // ------------------------------------------------------------
    // Profile record
    // ------------------------------------------------------------
    typedef struct {
        int unsigned case_id;
        int unsigned test_kind;

        int unsigned dim_m;
        int unsigned dim_n;
        int unsigned dim_k;

        int unsigned expected_mac_count;
        int unsigned expected_output_count;

        logic [31:0] busy_cycles;
        logic [31:0] mac_count;
        logic [31:0] output_count;
    } perf_profile_record_t;

    perf_profile_record_t profile_records[$];

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(
        string name = "ai_accel_subsys_perf_profile_test",
        uvm_component parent = null
    );
        super.new(name, parent);
    endfunction

    // ------------------------------------------------------------
    // Build phase
    // ------------------------------------------------------------
    function void build_phase(uvm_phase phase);
    begin
        super.build_phase(phase);

        profile_sample_delay_cycles = 8;
        profile_gap_cycles          = 10;

        void'($value$plusargs("PERF_PROFILE_SAMPLE_DELAY_CYCLES=%0d",
                              profile_sample_delay_cycles));
        void'($value$plusargs("PERF_PROFILE_GAP_CYCLES=%0d",
                              profile_gap_cycles));

        // Host-primary RUN_ALL profile recipe.
        //
        // Same ordering used by the main smoke/RUN_ALL style tests:
        //   variable dimensions first
        //   fixed baseline
        //   configurable-base cases
        profile_cases[0] = 100;
        profile_cases[1] = 101;
        profile_cases[2] = 105;
        profile_cases[3] = 5;
        profile_cases[4] = 400;
        profile_cases[5] = 401;
        profile_cases[6] = 402;
        profile_cases[7] = 403;

        `uvm_info("PERF_PROFILE",
            $sformatf("Configured perf profile: sample_delay_cycles=%0d gap_cycles=%0d cases=%0d",
                profile_sample_delay_cycles,
                profile_gap_cycles,
                PERF_PROFILE_CASE_COUNT),
            UVM_MEDIUM)
    end
    endfunction

    // ------------------------------------------------------------
    // Wait inter-profile gap
    // ------------------------------------------------------------
    task automatic wait_profile_gap();
        int unsigned i;
    begin
        for (i = 0; i < profile_gap_cycles; i++) begin
            @(vif.cb_drv);
        end
    end
    endtask

    // ------------------------------------------------------------
    // Sample and check counters for profile
    //
    // Profile test still checks the architectural counters:
    //   mac_count    == M*N*K
    //   output_count == M*N
    //
    // But it does NOT lock exact busy_cycles values.
    // busy_cycles is printed as a profiling number.
    // ------------------------------------------------------------
    task automatic sample_profile_counters(
        input  int unsigned cid,
        input  ai_accel_subsys_seq_item profile_item,
        output logic [31:0] busy_cycles,
        output logic [31:0] mac_count,
        output logic [31:0] output_count
    );
        int unsigned wait_i;

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

        for (wait_i = 0; wait_i < profile_sample_delay_cycles; wait_i++) begin
            @(vif.cb_drv);
        end

        busy_cycles  = vif.cb_drv.gemm_perf_busy_cycles;
        mac_count    = vif.cb_drv.gemm_perf_mac_count;
        output_count = vif.cb_drv.gemm_perf_output_count;

        `uvm_info("PERF_PROFILE",
            $sformatf("Profile counters: CASE_ID=%0d dim=(%0d,%0d,%0d) busy_cycles=%0d mac_count=%0d expected_mac=%0d output_count=%0d expected_output=%0d",
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
            `uvm_fatal("PERF_PROFILE/BUSY_ZERO",
                $sformatf("gemm_perf_busy_cycles is zero for CASE_ID=%0d", cid))
        end

        if (mac_count !== expected_mac_count[31:0]) begin
            `uvm_fatal("PERF_PROFILE/MAC_MISMATCH",
                $sformatf("gemm_perf_mac_count mismatch for CASE_ID=%0d: got=%0d expected=%0d",
                    cid,
                    mac_count,
                    expected_mac_count))
        end

        if (output_count !== expected_output_count[31:0]) begin
            `uvm_fatal("PERF_PROFILE/OUTPUT_MISMATCH",
                $sformatf("gemm_perf_output_count mismatch for CASE_ID=%0d: got=%0d expected=%0d",
                    cid,
                    output_count,
                    expected_output_count))
        end
    end
    endtask

    // ------------------------------------------------------------
    // Store profile record
    // ------------------------------------------------------------
    task automatic store_profile_record(
        input int unsigned cid,
        input ai_accel_subsys_seq_item profile_item,
        input logic [31:0] busy_cycles,
        input logic [31:0] mac_count,
        input logic [31:0] output_count
    );
        perf_profile_record_t rec;
    begin
        rec.case_id               = cid;
        rec.test_kind             = int'(selected_test_kind);

        rec.dim_m                 = int'(profile_item.dim_m);
        rec.dim_n                 = int'(profile_item.dim_n);
        rec.dim_k                 = int'(profile_item.dim_k);

        rec.expected_mac_count    =
            calc_expected_mac_count(
                int'(profile_item.dim_m),
                int'(profile_item.dim_n),
                int'(profile_item.dim_k)
            );

        rec.expected_output_count =
            calc_expected_output_count(
                int'(profile_item.dim_m),
                int'(profile_item.dim_n)
            );

        rec.busy_cycles           = busy_cycles;
        rec.mac_count             = mac_count;
        rec.output_count          = output_count;

        profile_records.push_back(rec);
    end
    endtask

    // ------------------------------------------------------------
    // Run one profiled host-primary case
    //
    // Flow:
    //   prepare expected payload
    //   host preload A/B + clear C
    //   launch GEMM
    //   wait acc_done
    //   sample counters
    //   host readback C
    //   scoreboard publish
    //   store profile record
    // ------------------------------------------------------------
    task automatic run_profile_one_case(input int unsigned cid);
        ai_accel_subsys_smoke_seq seq;
        ai_accel_subsys_seq_item  profile_item;

        int signed expected_c[];
        int signed actual_c[];

        bit have_expected_payload;
        bit have_actual_payload;

        logic [31:0] busy_cycles;
        logic [31:0] mac_count;
        logic [31:0] output_count;
    begin
        selected_case_id   = cid;
        selected_test_kind = infer_test_kind(selected_case_id);

        profile_item = build_selected_profile_item();

        // Multi-case profile needs runtime monitor context.
        // Static config_db context only tracks the initial CASE_ID.
        set_perf_monitor_case_context(selected_case_id);

        `uvm_info("PERF_PROFILE",
            $sformatf("Starting profiled case: CASE_ID=%0d test_kind=%0d dim=(%0d,%0d,%0d)",
                selected_case_id,
                selected_test_kind,
                profile_item.dim_m,
                profile_item.dim_n,
                profile_item.dim_k),
            UVM_LOW)

        if (enable_result_check) begin
            prepare_case_result_pre_start(expected_c, have_expected_payload);

            if (!have_expected_payload) begin
                `uvm_fatal("PERF_PROFILE/NO_EXPECTED_PAYLOAD",
                    "enable_result_check=1 but expected payload was not prepared")
            end
        end

        seq = ai_accel_subsys_smoke_seq::type_id::create("perf_profile_seq");

        seq.case_id   = selected_case_id;
        seq.test_kind = selected_test_kind;

        `uvm_info("PERF_PROFILE",
            $sformatf("Launching smoke sequence for profile: CASE_ID=%0d test_kind=%0d",
                seq.case_id,
                seq.test_kind),
            UVM_MEDIUM)

        seq.start(env.agent.sequencer);

        wait_for_acc_done();

        sample_profile_counters(
            selected_case_id,
            profile_item,
            busy_cycles,
            mac_count,
            output_count
        );

        store_profile_record(
            selected_case_id,
            profile_item,
            busy_cycles,
            mac_count,
            output_count
        );

        if (enable_result_check) begin
            collect_case_actual_post_done(actual_c, have_actual_payload);

            if (!have_actual_payload) begin
                `uvm_fatal("PERF_PROFILE/NO_ACTUAL_PAYLOAD",
                    "enable_result_check=1 but actual payload was not collected")
            end

            publish_result_to_scoreboard(expected_c, actual_c);
        end

        clear_perf_monitor_case_context();

        `uvm_info("PERF_PROFILE",
            $sformatf("Completed profiled case: CASE_ID=%0d",
                selected_case_id),
            UVM_LOW)
    end
    endtask

    // ------------------------------------------------------------
    // Print profile summary
    // ------------------------------------------------------------
    task automatic print_profile_summary();
        int unsigned idx;
        perf_profile_record_t rec;
    begin
        `uvm_info("PERF_PROFILE_SUMMARY",
            "============================================================",
            UVM_LOW)
        `uvm_info("PERF_PROFILE_SUMMARY",
            "GEMM PERFORMANCE PROFILE SUMMARY",
            UVM_LOW)
        `uvm_info("PERF_PROFILE_SUMMARY",
            "============================================================",
            UVM_LOW)
        `uvm_info("PERF_PROFILE_SUMMARY",
            "CASE_ID | KIND | M | N | K | MACS | OUTPUTS | GEMM_BUSY_CYCLES",
            UVM_LOW)
        `uvm_info("PERF_PROFILE_SUMMARY",
            "------------------------------------------------------------",
            UVM_LOW)

        for (idx = 0; idx < profile_records.size(); idx++) begin
            rec = profile_records[idx];

            `uvm_info("PERF_PROFILE_SUMMARY",
                $sformatf("%0d | %0d | %0d | %0d | %0d | %0d | %0d | %0d",
                    rec.case_id,
                    rec.test_kind,
                    rec.dim_m,
                    rec.dim_n,
                    rec.dim_k,
                    rec.expected_mac_count,
                    rec.expected_output_count,
                    rec.busy_cycles),
                UVM_LOW)
        end

        `uvm_info("PERF_PROFILE_SUMMARY",
            "============================================================",
            UVM_LOW)
    end
    endtask

    // ------------------------------------------------------------
    // Main run phase
    // ------------------------------------------------------------
    task run_phase(uvm_phase phase);
        int unsigned idx;

        phase.raise_objection(this);

        `uvm_info("PERF_PROFILE",
            "Starting ai_accel_subsys_perf_profile_test",
            UVM_LOW)

        profile_records.delete();

        wait_for_reset_release();

        for (idx = 0; idx < PERF_PROFILE_CASE_COUNT; idx++) begin
            run_profile_one_case(profile_cases[idx]);

            if ((idx + 1) < PERF_PROFILE_CASE_COUNT) begin
                wait_profile_gap();
            end
        end

        print_profile_summary();

        `uvm_info("PERF_PROFILE",
            "ai_accel_subsys_perf_profile_test completed",
            UVM_LOW)

        phase.drop_objection(this);
    endtask

endclass

`endif