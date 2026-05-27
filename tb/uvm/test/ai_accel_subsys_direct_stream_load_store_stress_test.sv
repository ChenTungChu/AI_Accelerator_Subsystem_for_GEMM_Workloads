// File: tb/uvm/test/ai_accel_subsys_direct_stream_load_store_stress_test.sv

`ifndef AI_ACCEL_SUBSYS_DIRECT_STREAM_LOAD_STORE_STRESS_TEST_SV
`define AI_ACCEL_SUBSYS_DIRECT_STREAM_LOAD_STORE_STRESS_TEST_SV

class ai_accel_subsys_direct_stream_load_store_stress_test
    extends ai_accel_subsys_direct_stream_smoke_test;

    `uvm_component_utils(ai_accel_subsys_direct_stream_load_store_stress_test)

    // ------------------------------------------------------------
    // Stress configuration
    // ------------------------------------------------------------
    int unsigned ds_stress_job_count;
    int unsigned ds_stress_seed;
    int unsigned ds_stress_random;
    int unsigned ds_stress_gap_cycles;

    // Optional forced-case mode for focused P9G/P9H larger-dimension path checks.
    //
    // run_uvm.tcl may pass a default +CASE_ID=0 even for stress tests that
    // do not intentionally request a focused case.  CASE_ID=0 is therefore
    // treated as "not forced" for this stress wrapper.
    //
    // When +CASE_ID=<nonzero id> is provided, select_case_for_job() bypasses
    // the built-in stress pool and every job runs the selected CASE_ID.
    bit          force_case_id_valid;
    int unsigned forced_case_id;

    int unsigned rng_state;

    // Supported case pool:
    //   100 -> 101 -> 105 -> 5 -> 400 -> 401 -> 402 -> 403
    localparam int unsigned DS_STRESS_CASE_COUNT = 8;
    int unsigned ds_stress_cases [DS_STRESS_CASE_COUNT];

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(
        string name = "ai_accel_subsys_direct_stream_load_store_stress_test",
        uvm_component parent = null
    );
        super.new(name, parent);
    endfunction

    // ------------------------------------------------------------
    // Build phase
    // ------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        ds_stress_job_count  = 8;
        ds_stress_seed       = 32'd20260502;
        ds_stress_random     = 1;
        ds_stress_gap_cycles = 10;

        force_case_id_valid  = 1'b0;
        forced_case_id       = 0;

        void'($value$plusargs("DS_STRESS_JOB_COUNT=%0d",  ds_stress_job_count));
        void'($value$plusargs("DS_STRESS_SEED=%0d",       ds_stress_seed));
        void'($value$plusargs("DS_STRESS_RANDOM=%0d",     ds_stress_random));
        void'($value$plusargs("DS_STRESS_GAP_CYCLES=%0d", ds_stress_gap_cycles));

        if ($value$plusargs("CASE_ID=%0d", forced_case_id)) begin
            // CASE_ID=0 is a run_uvm.tcl default placeholder for stress tests.
            // It must not enable forced-case mode, otherwise default/random
            // stress regression items try to run unsupported CASE_ID=0.
            force_case_id_valid = (forced_case_id != 0);
        end

        if (ds_stress_job_count == 0) begin
            `uvm_fatal("DIRECT_STREAM_STRESS",
                "DS_STRESS_JOB_COUNT must be non-zero")
        end

        ds_stress_cases[0] = 100;
        ds_stress_cases[1] = 101;
        ds_stress_cases[2] = 105;
        ds_stress_cases[3] = 5;
        ds_stress_cases[4] = 400;
        ds_stress_cases[5] = 401;
        ds_stress_cases[6] = 402;
        ds_stress_cases[7] = 403;

        rng_state = ds_stress_seed;

        `uvm_info("DIRECT_STREAM_STRESS",
            $sformatf("Configured Direct Stream load-store stress: jobs=%0d seed=%0d random=%0d gap_cycles=%0d forced_case=%0d forced_case_id=%0d",
                ds_stress_job_count,
                ds_stress_seed,
                ds_stress_random,
                ds_stress_gap_cycles,
                force_case_id_valid,
                forced_case_id),
            UVM_MEDIUM)

        if (force_case_id_valid) begin
            `uvm_info("DIRECT_STREAM_STRESS",
                $sformatf("Forced CASE_ID mode enabled: all Direct Stream stress jobs will run CASE_ID=%0d",
                    forced_case_id),
                UVM_MEDIUM)
        end
    endfunction

    // ------------------------------------------------------------
    // Deterministic LCG random generator
    //
    // Keeps case ordering reproducible and independent of simulator
    // class-random sequencing.
    // ------------------------------------------------------------
    function automatic int unsigned next_rand();
        rng_state = (rng_state * 32'd1664525) + 32'd1013904223;
        return rng_state;
    endfunction

    // ------------------------------------------------------------
    // Select case for stress job
    // ------------------------------------------------------------
    function automatic int unsigned select_case_for_job(
        input int unsigned job_idx
    );
        int unsigned rand_value;
        int unsigned case_idx;
    begin
        if (force_case_id_valid) begin
            return forced_case_id;
        end

        if (ds_stress_random != 0) begin
            rand_value = next_rand();
            case_idx   = rand_value % DS_STRESS_CASE_COUNT;
        end
        else begin
            case_idx = job_idx % DS_STRESS_CASE_COUNT;
        end

        return ds_stress_cases[case_idx];
    end
    endfunction

    // ------------------------------------------------------------
    // Wait inter-job gap
    // ------------------------------------------------------------
    task automatic wait_stress_gap();
        int unsigned i;
    begin
        for (i = 0; i < ds_stress_gap_cycles; i++) begin
            @(vif.cb_drv);
        end
    end
    endtask

    // ------------------------------------------------------------
    // Run one Direct Stream stress job
    //
    // Full path:
    //   dma_src_mem[]
    //     -> ds_src_axi_ar/r
    //     -> axi_mm2s_dma
    //     -> axis_async_fifo
    //     -> axi_stream_loader
    //     -> gemm_operand_buffer_write_adapter
    //     -> gemm_operand_buffer A/B
    //     -> gemm_input_mem_router
    //     -> GEMM
    //     -> scratchpad C
    //     -> dma_store_engine
    //     -> dma_dst_mem[]
    //     -> destination compare
    //     -> scoreboard
    // ------------------------------------------------------------
    task automatic run_direct_stream_stress_job(
        input int unsigned job_idx,
        input int unsigned cid
    );
    begin
        `uvm_info("DIRECT_STREAM_STRESS",
            $sformatf("Starting Direct Stream stress job %0d/%0d: CASE_ID=%0d",
                job_idx + 1,
                ds_stress_job_count,
                cid),
            UVM_LOW)

        run_direct_stream_one_case(cid);

        `uvm_info("DIRECT_STREAM_STRESS",
            $sformatf("Completed Direct Stream stress job %0d/%0d: CASE_ID=%0d",
                job_idx + 1,
                ds_stress_job_count,
                cid),
            UVM_LOW)
    end
    endtask

    // ------------------------------------------------------------
    // Main run phase
    // ------------------------------------------------------------
    task run_phase(uvm_phase phase);
        int unsigned job_idx;
        int unsigned cid;

        phase.raise_objection(this);

        `uvm_info("DIRECT_STREAM_STRESS",
            "Starting ai_accel_subsys_direct_stream_load_store_stress_test",
            UVM_LOW)

        init_direct_stream_ctrl_outputs();
        init_axi0_outputs();

        wait_for_reset_release();

        // Make sure all error-injection state is clean for stress.
        vif.dma_src_set_rresp_error(1'b0, -1);
        vif.axis_src_set_rresp_error(1'b0, -1);
        vif.ds_src_set_rresp_error(1'b0, -1);
        vif.dma_dst_set_bresp_error(1'b0, -1);

        @(vif.cb_drv);
        vif.cb_drv.gemm_input_stream_mode <= 1'b0;
        vif.cb_drv.ds_load_start          <= 1'b0;
        vif.cb_drv.ds_operand_sel         <= 1'b0;

        rng_state = ds_stress_seed;

        for (job_idx = 0; job_idx < ds_stress_job_count; job_idx++) begin
            cid = select_case_for_job(job_idx);

            run_direct_stream_stress_job(job_idx, cid);

            if ((job_idx + 1) < ds_stress_job_count) begin
                wait_stress_gap();
            end
        end

        @(vif.cb_drv);
        vif.cb_drv.gemm_input_stream_mode <= 1'b0;
        vif.cb_drv.ds_load_start          <= 1'b0;
        vif.cb_drv.ds_operand_sel         <= 1'b0;

        `uvm_info("DIRECT_STREAM_STRESS",
            $sformatf("ai_accel_subsys_direct_stream_load_store_stress_test completed: jobs=%0d",
                ds_stress_job_count),
            UVM_LOW)

        phase.drop_objection(this);
    endtask

endclass

`endif