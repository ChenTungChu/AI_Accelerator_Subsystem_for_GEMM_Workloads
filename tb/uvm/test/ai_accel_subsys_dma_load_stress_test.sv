// File: tb/uvm/test/ai_accel_subsys_dma_load_stress_test.sv

`ifndef AI_ACCEL_SUBSYS_DMA_LOAD_STRESS_TEST_SV
`define AI_ACCEL_SUBSYS_DMA_LOAD_STRESS_TEST_SV

class ai_accel_subsys_dma_load_stress_test extends ai_accel_subsys_dma_load_smoke_test;

    `uvm_component_utils(ai_accel_subsys_dma_load_stress_test)

    // ------------------------------------------------------------
    // Stress knobs
    //
    // STRESS_JOB_COUNT:
    //   number of DMA-loaded GEMM jobs in one simulation
    //
    // STRESS_SEED:
    //   deterministic pseudo-random seed
    //
    // STRESS_RANDOM:
    //   1 -> pseudo-random case selection
    //   0 -> round-robin case selection
    //
    // STRESS_GAP_CYCLES:
    //   idle cycles between jobs
    // ------------------------------------------------------------
    int unsigned stress_job_count;
    int unsigned stress_seed;
    int unsigned stress_random;
    int unsigned stress_gap_cycles;

    localparam int unsigned DEFAULT_STRESS_JOB_COUNT = 20;
    localparam int unsigned DEFAULT_STRESS_SEED      = 32'h2026_0502;
    localparam int unsigned DEFAULT_STRESS_RANDOM    = 1;
    localparam int unsigned DEFAULT_STRESS_GAP       = 10;

    // Supported DMA-load GEMM case pool.
    int unsigned supported_cases [0:7];

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_dma_load_stress_test",
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

        if (!$value$plusargs("STRESS_JOB_COUNT=%0d", stress_job_count)) begin
            stress_job_count = DEFAULT_STRESS_JOB_COUNT;
        end

        if (!$value$plusargs("STRESS_SEED=%0d", stress_seed)) begin
            stress_seed = DEFAULT_STRESS_SEED;
        end

        if (!$value$plusargs("STRESS_RANDOM=%0d", stress_random)) begin
            stress_random = DEFAULT_STRESS_RANDOM;
        end

        if (!$value$plusargs("STRESS_GAP_CYCLES=%0d", stress_gap_cycles)) begin
            stress_gap_cycles = DEFAULT_STRESS_GAP;
        end

        if (stress_job_count == 0) begin
            `uvm_fatal("DMA_LOAD_STRESS",
                "STRESS_JOB_COUNT must be non-zero")
        end

        `uvm_info("DMA_LOAD_STRESS",
            $sformatf("Configured stress knobs: job_count=%0d seed=0x%08h random=%0d gap_cycles=%0d enable_result_check=%0d",
                stress_job_count,
                stress_seed,
                stress_random,
                stress_gap_cycles,
                enable_result_check),
            UVM_MEDIUM)
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
        if (stress_random != 0) begin
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

        `uvm_info("DMA_LOAD_STRESS",
            $sformatf("Supported stress case pool: {%s}", s),
            UVM_MEDIUM)
    end
    endtask

    // ------------------------------------------------------------
    // Main run phase
    // ------------------------------------------------------------
    task run_phase(uvm_phase phase);
        int unsigned job_idx;
        int unsigned cid;
        int unsigned rand_state;

        phase.raise_objection(this);

        `uvm_info("DMA_LOAD_STRESS",
            "Starting ai_accel_subsys_dma_load_stress_test",
            UVM_LOW)

        init_ctrl_outputs();
        init_axi0_outputs();

        wait_for_reset_release();

        print_case_pool();

        rand_state = stress_seed;

        for (job_idx = 0; job_idx < stress_job_count; job_idx++) begin
            cid = pick_case(job_idx, rand_state);

            `uvm_info("DMA_LOAD_STRESS",
                $sformatf("Starting stress job %0d/%0d: CASE_ID=%0d",
                    job_idx + 1,
                    stress_job_count,
                    cid),
                UVM_LOW)

            run_one_case(cid);

            `uvm_info("DMA_LOAD_STRESS",
                $sformatf("Completed stress job %0d/%0d: CASE_ID=%0d",
                    job_idx + 1,
                    stress_job_count,
                    cid),
                UVM_LOW)

            if (job_idx + 1 < stress_job_count) begin
                repeat (stress_gap_cycles) @(vif.cb_drv);
            end
        end

        `uvm_info("DMA_LOAD_STRESS",
            $sformatf("ai_accel_subsys_dma_load_stress_test completed: jobs=%0d",
                stress_job_count),
            UVM_LOW)

        phase.drop_objection(this);
    endtask

endclass

`endif