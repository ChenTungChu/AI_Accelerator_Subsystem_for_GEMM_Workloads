// File: tb/uvm/test/ai_accel_subsys_dma_load_store_stress_test.sv

`ifndef AI_ACCEL_SUBSYS_DMA_LOAD_STORE_STRESS_TEST_SV
`define AI_ACCEL_SUBSYS_DMA_LOAD_STORE_STRESS_TEST_SV

class ai_accel_subsys_dma_load_store_stress_test
    extends ai_accel_subsys_dma_store_smoke_test;

    `uvm_component_utils(ai_accel_subsys_dma_load_store_stress_test)

    // ------------------------------------------------------------
    // Stress knobs
    //
    // STORE_STRESS_JOB_COUNT:
    //   number of DMA-load + GEMM + DMA-store jobs in one simulation
    //
    // STORE_STRESS_SEED:
    //   deterministic pseudo-random seed
    //
    // STORE_STRESS_RANDOM:
    //   1 -> pseudo-random case selection
    //   0 -> round-robin case selection
    //
    // STORE_STRESS_GAP_CYCLES:
    //   idle cycles between jobs
    // ------------------------------------------------------------
    int unsigned store_stress_job_count;
    int unsigned store_stress_seed;
    int unsigned store_stress_random;
    int unsigned store_stress_gap_cycles;

    // Optional forced-case mode for focused P9G/P9H larger-dimension and P10E K-tiling frontend checks.
    //
    // run_uvm.tcl may pass a default +CASE_ID=0 even for stress tests that
    // do not intentionally request a focused case.  CASE_ID=0 is therefore
    // treated as "not forced" for this stress wrapper.
    //
    // When +CASE_ID=<nonzero id> is provided, pick_case() bypasses the
    // built-in stress pool and every job runs the selected CASE_ID.
    bit          force_case_id_valid;
    int unsigned forced_case_id;

    localparam int unsigned DEFAULT_STORE_STRESS_JOB_COUNT = 20;
    localparam int unsigned DEFAULT_STORE_STRESS_SEED      = 32'h2026_0502;
    localparam int unsigned DEFAULT_STORE_STRESS_RANDOM    = 1;
    localparam int unsigned DEFAULT_STORE_STRESS_GAP       = 10;

    // Supported full DMA-load + DMA-store GEMM case pool.
    int unsigned supported_cases [0:7];

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_dma_load_store_stress_test",
                 uvm_component parent = null);
        super.new(name, parent);

        supported_cases[0] = 100;
        supported_cases[1] = 101;
        supported_cases[2] = 105;
        supported_cases[3] = 5;
        supported_cases[4] = 400;
        supported_cases[5] = 401;
        supported_cases[6] = 402;
        supported_cases[7] = 403;
    endfunction

    // ------------------------------------------------------------
    // Build phase
    // ------------------------------------------------------------
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        force_case_id_valid = 1'b0;
        forced_case_id      = 0;

        if (!$value$plusargs("STORE_STRESS_JOB_COUNT=%0d", store_stress_job_count)) begin
            store_stress_job_count = DEFAULT_STORE_STRESS_JOB_COUNT;
        end

        if (!$value$plusargs("STORE_STRESS_SEED=%0d", store_stress_seed)) begin
            store_stress_seed = DEFAULT_STORE_STRESS_SEED;
        end

        if (!$value$plusargs("STORE_STRESS_RANDOM=%0d", store_stress_random)) begin
            store_stress_random = DEFAULT_STORE_STRESS_RANDOM;
        end

        if (!$value$plusargs("STORE_STRESS_GAP_CYCLES=%0d", store_stress_gap_cycles)) begin
            store_stress_gap_cycles = DEFAULT_STORE_STRESS_GAP;
        end

        if ($value$plusargs("CASE_ID=%0d", forced_case_id)) begin
            // CASE_ID=0 is a run_uvm.tcl default placeholder for stress tests.
            // It must not enable forced-case mode, otherwise default/random
            // stress regression items try to run unsupported CASE_ID=0.
            force_case_id_valid = (forced_case_id != 0);
        end

        if (store_stress_job_count == 0) begin
            `uvm_fatal("DMA_LOAD_STORE_STRESS",
                "STORE_STRESS_JOB_COUNT must be non-zero")
        end

        `uvm_info("DMA_LOAD_STORE_STRESS",
            $sformatf("Configured load-store stress knobs: job_count=%0d seed=0x%08h random=%0d gap_cycles=%0d enable_result_check=%0d forced_case=%0d forced_case_id=%0d",
                store_stress_job_count,
                store_stress_seed,
                store_stress_random,
                store_stress_gap_cycles,
                enable_result_check,
                force_case_id_valid,
                forced_case_id),
            UVM_MEDIUM)

        if (force_case_id_valid) begin
            `uvm_info("DMA_LOAD_STORE_STRESS",
                $sformatf("Forced CASE_ID mode enabled: all DMA load-store stress jobs will run CASE_ID=%0d",
                    forced_case_id),
                UVM_MEDIUM)

            if ((forced_case_id >= 193) && (forced_case_id <= 197)) begin
                `uvm_info("DMA_LOAD_STORE_STRESS",
                    "Forced CASE_ID is in the P10 K-tiling focused case range 193..197",
                    UVM_MEDIUM)
            end
        end
    endfunction

    // ------------------------------------------------------------
    // Deterministic LCG pseudo-random generator
    //
    // This avoids simulator-dependent random stability issues.
    // ------------------------------------------------------------
    function automatic int unsigned next_rand(ref int unsigned state);
        state = (state * 32'd1664525) + 32'd1013904223;
        return state;
    endfunction

    // ------------------------------------------------------------
    // Pick next case
    // ------------------------------------------------------------
    function automatic int unsigned pick_case(
        input int unsigned job_idx,
        ref   int unsigned rand_state
    );
        int unsigned idx;
        int unsigned rnd;
    begin
        if (force_case_id_valid) begin
            return forced_case_id;
        end

        if (store_stress_random != 0) begin
            rnd = next_rand(rand_state);
            idx = rnd % 8;
        end
        else begin
            idx = job_idx % 8;
        end

        return supported_cases[idx];
    end
    endfunction

    // ------------------------------------------------------------
    // Print supported case pool
    // ------------------------------------------------------------
    task automatic print_case_pool();
        int unsigned i;
        string s;
    begin
        s = "";

        for (i = 0; i < 8; i++) begin
            if (i == 0) begin
                s = $sformatf("%0d", supported_cases[i]);
            end
            else begin
                s = {s, $sformatf(", %0d", supported_cases[i])};
            end
        end

        `uvm_info("DMA_LOAD_STORE_STRESS",
            $sformatf("Supported load-store stress case pool: {%s}", s),
            UVM_MEDIUM)

        if (force_case_id_valid) begin
            `uvm_info("DMA_LOAD_STORE_STRESS",
                $sformatf("Built-in pool selection is bypassed by forced CASE_ID=%0d",
                    forced_case_id),
                UVM_MEDIUM)
        end
    end
    endtask

    // ------------------------------------------------------------
    // Main run phase
    //
    // Reuses ai_accel_subsys_dma_store_smoke_test::run_one_case().
    //
    // Each job performs:
    //   clear C
    //   clear dma_dst_mem
    //   preload DMA source A/B
    //   DMA load A
    //   DMA load B
    //   GEMM
    //   DMA store C to destination memory
    //   destination memory compare
    //   optional scoreboard publish
    // ------------------------------------------------------------
    task run_phase(uvm_phase phase);
        int unsigned job_idx;
        int unsigned cid;
        int unsigned rand_state;

        phase.raise_objection(this);

        `uvm_info("DMA_LOAD_STORE_STRESS",
            "Starting ai_accel_subsys_dma_load_store_stress_test",
            UVM_LOW)

        init_ctrl_outputs();
        init_axi0_outputs();

        wait_for_reset_release();

        print_case_pool();

        rand_state = store_stress_seed;

        for (job_idx = 0; job_idx < store_stress_job_count; job_idx++) begin
            cid = pick_case(job_idx, rand_state);

            `uvm_info("DMA_LOAD_STORE_STRESS",
                $sformatf("Starting load-store stress job %0d/%0d: CASE_ID=%0d",
                    job_idx + 1,
                    store_stress_job_count,
                    cid),
                UVM_LOW)

            run_one_case(cid);

            `uvm_info("DMA_LOAD_STORE_STRESS",
                $sformatf("Completed load-store stress job %0d/%0d: CASE_ID=%0d",
                    job_idx + 1,
                    store_stress_job_count,
                    cid),
                UVM_LOW)

            if (job_idx + 1 < store_stress_job_count) begin
                repeat (store_stress_gap_cycles) @(vif.cb_drv);
            end
        end

        `uvm_info("DMA_LOAD_STORE_STRESS",
            $sformatf("ai_accel_subsys_dma_load_store_stress_test completed: jobs=%0d",
                store_stress_job_count),
            UVM_LOW)

        phase.drop_objection(this);
    endtask

endclass

`endif