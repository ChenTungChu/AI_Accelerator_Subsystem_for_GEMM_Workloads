// File: tb/uvm/test/ai_accel_subsys_axis_stream_load_store_stress_test.sv

`ifndef AI_ACCEL_SUBSYS_AXIS_STREAM_LOAD_STORE_STRESS_TEST_SV
`define AI_ACCEL_SUBSYS_AXIS_STREAM_LOAD_STORE_STRESS_TEST_SV

class ai_accel_subsys_axis_stream_load_store_stress_test
    extends ai_accel_subsys_axis_stream_preload_smoke_test;

    `uvm_component_utils(ai_accel_subsys_axis_stream_load_store_stress_test)

    // ------------------------------------------------------------
    // Stress configuration
    // ------------------------------------------------------------
    int unsigned axis_stress_job_count;
    int unsigned axis_stress_seed;
    int unsigned axis_stress_random;
    int unsigned axis_stress_gap_cycles;

    // Optional forced-case mode for focused P9G/P9H larger-dimension, P10E K-tiling, P11C/P11F N-tiling, and P12C/P12F M-tiling frontend checks.
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

    // Supported stress case pool.
    //
    // Keep same coverage shape as existing RUN_ALL recipes:
    //   100 -> 101 -> 105 -> 5 -> 400 -> 401 -> 402 -> 403
    localparam int unsigned AXIS_STRESS_CASE_COUNT = 8;
    int unsigned axis_stress_cases [AXIS_STRESS_CASE_COUNT];

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(
        string name = "ai_accel_subsys_axis_stream_load_store_stress_test",
        uvm_component parent = null
    );
        super.new(name, parent);
    endfunction

    // ------------------------------------------------------------
    // Build phase
    // ------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        axis_stress_job_count  = 8;
        axis_stress_seed       = 32'd20260502;
        axis_stress_random     = 1;
        axis_stress_gap_cycles = 10;

        force_case_id_valid    = 1'b0;
        forced_case_id         = 0;

        void'($value$plusargs("AXIS_STRESS_JOB_COUNT=%0d", axis_stress_job_count));
        void'($value$plusargs("AXIS_STRESS_SEED=%0d",      axis_stress_seed));
        void'($value$plusargs("AXIS_STRESS_RANDOM=%0d",    axis_stress_random));
        void'($value$plusargs("AXIS_STRESS_GAP_CYCLES=%0d", axis_stress_gap_cycles));

        if ($value$plusargs("CASE_ID=%0d", forced_case_id)) begin
            // CASE_ID=0 is a run_uvm.tcl default placeholder for stress tests.
            // It must not enable forced-case mode, otherwise default/random
            // stress regression items try to run unsupported CASE_ID=0.
            force_case_id_valid = (forced_case_id != 0);
        end

        if (axis_stress_job_count == 0) begin
            `uvm_fatal("AXIS_LS_STRESS",
                "AXIS_STRESS_JOB_COUNT must be non-zero")
        end

        axis_stress_cases[0] = 100;
        axis_stress_cases[1] = 101;
        axis_stress_cases[2] = 105;
        axis_stress_cases[3] = 5;
        axis_stress_cases[4] = 400;
        axis_stress_cases[5] = 401;
        axis_stress_cases[6] = 402;
        axis_stress_cases[7] = 403;

        rng_state = axis_stress_seed;

        `uvm_info("AXIS_LS_STRESS",
            $sformatf("Configured AXIS load-store stress: jobs=%0d seed=%0d random=%0d gap_cycles=%0d forced_case=%0d forced_case_id=%0d",
                axis_stress_job_count,
                axis_stress_seed,
                axis_stress_random,
                axis_stress_gap_cycles,
                force_case_id_valid,
                forced_case_id),
            UVM_MEDIUM)

        if (force_case_id_valid) begin
            `uvm_info("AXIS_LS_STRESS",
                $sformatf("Forced CASE_ID mode enabled: all AXIS load-store stress jobs will run CASE_ID=%0d",
                    forced_case_id),
                UVM_MEDIUM)

            if ((forced_case_id >= 193) && (forced_case_id <= 197)) begin
                `uvm_info("AXIS_LS_STRESS",
                    "Forced CASE_ID is in the P10 K-tiling focused case range 193..197",
                    UVM_MEDIUM)
            end

            if ((forced_case_id >= 198) && (forced_case_id <= 202)) begin
                `uvm_info("AXIS_LS_STRESS",
                    "Forced CASE_ID is in the P11 N-tiling focused case range 198..202",
                    UVM_MEDIUM)
            end

            if ((forced_case_id >= 203) && (forced_case_id <= 207)) begin
                `uvm_info("AXIS_LS_STRESS",
                    "Forced CASE_ID is in the P12 M-tiling focused case range 203..207",
                    UVM_MEDIUM)
            end
        end
    endfunction

    // ------------------------------------------------------------
    // Simple deterministic LCG random generator
    //
    // Avoids depending on simulator-specific class RNG sequencing.
    // ------------------------------------------------------------
    function automatic int unsigned next_rand();
        rng_state = (rng_state * 32'd1664525) + 32'd1013904223;
        return rng_state;
    endfunction

    // ------------------------------------------------------------
    // Select case for job
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

        if (axis_stress_random != 0) begin
            rand_value = next_rand();
            case_idx   = rand_value % AXIS_STRESS_CASE_COUNT;
        end
        else begin
            case_idx = job_idx % AXIS_STRESS_CASE_COUNT;
        end

        return axis_stress_cases[case_idx];
    end
    endfunction

    // ------------------------------------------------------------
    // Wait inter-job gap
    // ------------------------------------------------------------
    task automatic wait_stress_gap();
        int unsigned i;
    begin
        for (i = 0; i < axis_stress_gap_cycles; i++) begin
            @(vif.cb_drv);
        end
    end
    endtask

    // ------------------------------------------------------------
    // Run one stress job
    //
    // Full path:
    //   dma_src_mem[]
    //     -> axis_src_axi_ar/r
    //     -> axi_mm2s_dma
    //     -> axis_async_fifo
    //     -> axi_stream_loader
    //     -> axis_scratchpad_write_adapter
    //     -> scratchpad Port1
    //     -> GEMM
    //     -> DMA store C
    //     -> dma_dst_mem[]
    //     -> compare / scoreboard
    // ------------------------------------------------------------
    task automatic run_axis_stress_job(
        input int unsigned job_idx,
        input int unsigned cid
    );
    begin
        `uvm_info("AXIS_LS_STRESS",
            $sformatf("Starting AXIS load-store stress job %0d/%0d: CASE_ID=%0d",
                job_idx + 1,
                axis_stress_job_count,
                cid),
            UVM_LOW)

        // Reuse the already verified AXIS preload smoke per-case flow.
        //
        // This performs:
        //   configure_case()
        //   clear_c_region()
        //   clear_dma_destination_memory()
        //   preload_dma_source_memory()
        //   AXIS preload A
        //   AXIS preload B
        //   GEMM
        //   DMA store C
        //   destination compare
        //   scoreboard publish
        run_axis_one_case(cid);

        `uvm_info("AXIS_LS_STRESS",
            $sformatf("Completed AXIS load-store stress job %0d/%0d: CASE_ID=%0d",
                job_idx + 1,
                axis_stress_job_count,
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

        `uvm_info("AXIS_LS_STRESS",
            "Starting ai_accel_subsys_axis_stream_load_store_stress_test",
            UVM_LOW)

        init_axis_ctrl_outputs();
        init_axi0_outputs();

        wait_for_reset_release();

        // Make sure error-injection state is clean for stress.
        vif.dma_src_set_rresp_error(1'b0, -1);
        vif.axis_src_set_rresp_error(1'b0, -1);
        vif.dma_dst_set_bresp_error(1'b0, -1);

        rng_state = axis_stress_seed;

        for (job_idx = 0; job_idx < axis_stress_job_count; job_idx++) begin
            cid = select_case_for_job(job_idx);

            run_axis_stress_job(job_idx, cid);

            if ((job_idx + 1) < axis_stress_job_count) begin
                wait_stress_gap();
            end
        end

        `uvm_info("AXIS_LS_STRESS",
            $sformatf("ai_accel_subsys_axis_stream_load_store_stress_test completed: jobs=%0d",
                axis_stress_job_count),
            UVM_LOW)

        phase.drop_objection(this);
    endtask

endclass

`endif