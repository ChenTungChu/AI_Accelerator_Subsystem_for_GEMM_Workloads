// File: tb/uvm/test/ai_accel_subsys_direct_stream_smoke_test.sv

`ifndef AI_ACCEL_SUBSYS_DIRECT_STREAM_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_DIRECT_STREAM_SMOKE_TEST_SV

class ai_accel_subsys_direct_stream_smoke_test
    extends ai_accel_subsys_dma_store_smoke_test;

    `uvm_component_utils(ai_accel_subsys_direct_stream_smoke_test)

    localparam logic OPERAND_A = 1'b0;
    localparam logic OPERAND_B = 1'b1;

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_direct_stream_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // ------------------------------------------------------------
    // Build Direct Stream test name from case id / test kind
    // ------------------------------------------------------------
    function automatic string build_direct_stream_test_name(
        input int unsigned cid,
        input ai_accel_subsys_seq_item::test_kind_e kind
    );
        case (kind)
            ai_accel_subsys_seq_item::TEST_KIND_FIXED_BASELINE:
                return $sformatf("direct_stream_fixed_baseline_case_%0d", cid);

            ai_accel_subsys_seq_item::TEST_KIND_VARIABLE_DIM_SMOKE:
                return $sformatf("direct_stream_variable_dim_case_%0d", cid);

            ai_accel_subsys_seq_item::TEST_KIND_CONFIGURABLE_BASE:
                return $sformatf("direct_stream_config_base_case_%0d", cid);

            ai_accel_subsys_seq_item::TEST_KIND_C_RMW_ACCUM_RECIPE:
                return $sformatf("direct_stream_c_rmw_accum_recipe_%0d", cid);

            default:
                return $sformatf("direct_stream_case_%0d_kind_%0d", cid, kind);
        endcase
    endfunction

    // ------------------------------------------------------------
    // Initialize Direct Stream specific ctrl_if outputs
    // ------------------------------------------------------------
    task automatic init_direct_stream_ctrl_outputs();
    begin
        init_ctrl_outputs();

        @(vif.cb_drv);

        vif.cb_drv.gemm_input_stream_mode <= 1'b0;

        vif.cb_drv.ds_load_start    <= 1'b0;
        vif.cb_drv.ds_src_base_addr <= '0;
        vif.cb_drv.ds_dst_base_addr <= '0;
        vif.cb_drv.ds_load_beats    <= '0;
        vif.cb_drv.ds_operand_sel   <= OPERAND_A;

        vif.ds_src_set_rresp_error(1'b0, -1);
    end
    endtask

    // ------------------------------------------------------------
    // Publish Direct Stream result vectors to scoreboard
    // ------------------------------------------------------------
    task automatic publish_direct_stream_result_to_scoreboard(
        input int unsigned cid,
        input int signed   expected_dyn[],
        input int signed   actual_dyn[]
    );
        ai_accel_subsys_seq_item::test_kind_e kind;
        string test_name;
    begin
        if (!enable_result_check) begin
            return;
        end

        if (env == null) begin
            `uvm_fatal("DIRECT_STREAM_SMOKE/NOENV",
                "env is null in publish_direct_stream_result_to_scoreboard()")
        end

        if (env.result_bridge == null) begin
            `uvm_fatal("DIRECT_STREAM_SMOKE/NOBRIDGE",
                "env.result_bridge is null in publish_direct_stream_result_to_scoreboard()")
        end

        kind      = infer_test_kind(cid);
        test_name = build_direct_stream_test_name(cid, kind);

        `uvm_info("DIRECT_STREAM_SMOKE",
            $sformatf("Publishing Direct Stream result payload: case_id=%0d test_kind=%0d C_words=%0d",
                cid, kind, expected_dyn.size()),
            UVM_MEDIUM)

        env.result_bridge.publish_case_result(
            cid,
            kind,
            test_name,

            base_a,
            base_b,
            base_c,

            dim_m_i[DIM_WIDTH-1:0],
            dim_n_i[DIM_WIDTH-1:0],
            dim_k_i[DIM_WIDTH-1:0],

            expected_dyn,
            actual_dyn
        );
    end
    endtask

    // ------------------------------------------------------------
    // Launch one Direct Stream operand preload job
    //
    // Path:
    //   ctrl_if.dma_src_mem[]
    //     -> ds_src_axi_ar/r responder
    //     -> axi_mm2s_dma
    //     -> axis_async_fifo
    //     -> axi_stream_loader
    //     -> gemm_operand_buffer_write_adapter
    //     -> gemm_operand_buffer A/B
    //
    // operand_sel:
    //   0 = A
    //   1 = B
    // ------------------------------------------------------------
    task automatic run_direct_stream_preload(
        input string                  tag,
        input logic                   operand_sel,
        input logic [ADDR_WIDTH-1:0]  src_addr,
        input logic [ADDR_WIDTH-1:0]  dst_addr,
        input int unsigned            byte_count
    );
        int unsigned timeout;
        int unsigned beats;
        bit done_seen;

        timeout   = 0;
        done_seen = 0;
        beats     = ceil_div(byte_count, BYTES_PER_BEAT);

        if (beats == 0) begin
            `uvm_fatal("DIRECT_STREAM_SMOKE",
                $sformatf("Invalid zero-beat Direct Stream preload for %s", tag))
        end

        if (!addr_is_beat_aligned(src_addr)) begin
            `uvm_fatal("DIRECT_STREAM_SMOKE",
                $sformatf("Direct Stream source address must be beat aligned for %s: src=0x%08h",
                    tag, src_addr))
        end

        if (!addr_is_beat_aligned(dst_addr)) begin
            `uvm_fatal("DIRECT_STREAM_SMOKE",
                $sformatf("Direct Stream destination/base address must be beat aligned for %s: dst=0x%08h",
                    tag, dst_addr))
        end

        `uvm_info("DIRECT_STREAM_SMOKE",
            $sformatf("Starting Direct Stream preload %s: operand=%0d src=0x%08h dst_base=0x%08h bytes=%0d beats=%0d",
                tag, operand_sel, src_addr, dst_addr, byte_count, beats),
            UVM_MEDIUM)

        vif.ds_src_set_rresp_error(1'b0, -1);

        @(vif.cb_drv);
        vif.cb_drv.ds_src_base_addr <= src_addr;
        vif.cb_drv.ds_dst_base_addr <= dst_addr;
        vif.cb_drv.ds_load_beats    <= beats[31:0];
        vif.cb_drv.ds_operand_sel   <= operand_sel;
        vif.cb_drv.ds_load_start    <= 1'b1;

        @(vif.cb_drv);
        vif.cb_drv.ds_load_start    <= 1'b0;

        while (!done_seen) begin
            @(vif.cb_drv);

            if (vif.cb_drv.ds_load_done === 1'b1) begin
                done_seen = 1;
            end

            timeout++;
            if (timeout > 30000) begin
                `uvm_fatal("DIRECT_STREAM_SMOKE",
                    $sformatf("Timeout waiting for Direct Stream preload done: %s", tag))
            end
        end

        if (vif.cb_drv.ds_load_error !== 1'b0) begin
            `uvm_fatal("DIRECT_STREAM_SMOKE",
                $sformatf("Direct Stream preload reported error: %s", tag))
        end

        repeat (8) @(vif.cb_drv);

        if (vif.cb_drv.ds_load_busy !== 1'b0) begin
            `uvm_fatal("DIRECT_STREAM_SMOKE",
                $sformatf("Direct Stream preload busy did not clear after done: %s", tag))
        end

        `uvm_info("DIRECT_STREAM_SMOKE",
            $sformatf("Completed Direct Stream preload %s", tag),
            UVM_MEDIUM)
    endtask

    // ------------------------------------------------------------
    // Configure and start GEMM in Direct Stream input mode
    //
    // GEMM A/B reads:
    //   gemm_input_mem_router -> gemm_operand_buffer
    //
    // GEMM C writes:
    //   gemm_input_mem_router -> gemm_scratchpad_adapter -> scratchpad
    // ------------------------------------------------------------
    task automatic run_direct_stream_gemm(input int unsigned cid);
        int unsigned timeout;
        bit done_seen;

        timeout   = 0;
        done_seen = 0;

        set_monitor_case_context(cid);

        `uvm_info("DIRECT_STREAM_SMOKE",
            $sformatf("Starting GEMM in Direct Stream mode: case_id=%0d dim=(%0d,%0d,%0d) accumulate_enable=%0d",
                cid, dim_m_i, dim_n_i, dim_k_i, accumulate_enable_i),
            UVM_MEDIUM)

        @(vif.cb_drv);
        vif.cb_drv.gemm_input_stream_mode <= 1'b1;

        vif.cb_drv.base_addr_a <= base_a;
        vif.cb_drv.base_addr_b <= base_b;
        vif.cb_drv.base_addr_c <= base_c;

        vif.cb_drv.dim_m <= dim_m_i[DIM_WIDTH-1:0];
        vif.cb_drv.dim_n <= dim_n_i[DIM_WIDTH-1:0];
        vif.cb_drv.dim_k <= dim_k_i[DIM_WIDTH-1:0];
        vif.cb_drv.accumulate_enable <= accumulate_enable_i;

        repeat (2) @(vif.cb_drv);

        vif.cb_drv.acc_start <= 1'b1;
        @(vif.cb_drv);
        vif.cb_drv.acc_start <= 1'b0;

        while (!done_seen) begin
            @(vif.cb_drv);

            if (vif.cb_drv.acc_done === 1'b1) begin
                done_seen = 1;
            end

            timeout++;
            if (timeout > gemm_done_timeout_cycles) begin
                `uvm_fatal("DIRECT_STREAM_SMOKE",
                    $sformatf("Timeout waiting for acc_done in Direct Stream GEMM after %0d cycles",
                        gemm_done_timeout_cycles))
            end
        end

        repeat (5) @(vif.cb_drv);

        `uvm_info("DIRECT_STREAM_SMOKE",
            "Direct Stream GEMM completed",
            UVM_MEDIUM)
    endtask

    // ------------------------------------------------------------
    // C RMW accumulation frontend hooks
    //
    // Parent run_c_rmw_accum_frontend_recipe() owns the multi-job
    // recipe flow.  These overrides only change how each compact
    // partial A/B payload reaches the accelerator frontend and how
    // GEMM is launched in Direct Stream input mode.
    // ------------------------------------------------------------
    virtual task automatic run_c_rmw_accum_frontend_preload_ab(
        input int unsigned             cid,
        input ai_accel_subsys_seq_item job_item
    );
    begin
        @(vif.cb_drv);
        vif.cb_drv.gemm_input_stream_mode <= 1'b0;

        preload_dma_source_memory();

        run_direct_stream_preload("A", OPERAND_A, dma_src_a, base_a, a_bytes);
        run_direct_stream_preload("B", OPERAND_B, dma_src_b, base_b, b_bytes);
    end
    endtask

    virtual task automatic run_c_rmw_accum_frontend_gemm(
        input int unsigned             cid,
        input ai_accel_subsys_seq_item job_item
    );
    begin
        run_direct_stream_gemm(cid);

        @(vif.cb_drv);
        vif.cb_drv.gemm_input_stream_mode <= 1'b0;
    end
    endtask

    virtual task automatic publish_frontend_result_to_scoreboard(
        input int unsigned cid,
        input int signed   expected_dyn[],
        input int signed   actual_dyn[]
    );
    begin
        publish_direct_stream_result_to_scoreboard(cid, expected_dyn, actual_dyn);
    end
    endtask

    // ------------------------------------------------------------
    // Run one Direct Stream configured case
    // ------------------------------------------------------------
    task automatic run_direct_stream_one_case(input int unsigned cid);
        int signed expected_dyn[];
        int signed actual_dyn[];
    begin
        if (is_c_rmw_accum_recipe_case(cid)) begin
            run_c_rmw_accum_frontend_recipe(cid);
            return;
        end

        case_id = cid;
        configure_case(case_id);

        // Make sure Direct Stream mode is not accidentally enabled
        // while clearing C or doing setup traffic.
        @(vif.cb_drv);
        vif.cb_drv.gemm_input_stream_mode <= 1'b0;

        clear_c_region();
        clear_dma_destination_memory();
        preload_dma_source_memory();

        // --------------------------------------------------------
        // Key difference from DMA-store smoke:
        //
        //   Old:
        //     DMA load A/B into scratchpad
        //
        //   New:
        //     Direct Stream preload A/B into operand buffer
        // --------------------------------------------------------
        run_direct_stream_preload("A", OPERAND_A, dma_src_a, base_a, a_bytes);
        run_direct_stream_preload("B", OPERAND_B, dma_src_b, base_b, b_bytes);

        run_direct_stream_gemm(case_id);

        // GEMM mode was already latched at acc_start. Put external
        // mode back to scratchpad mode after acc_done for cleanliness.
        @(vif.cb_drv);
        vif.cb_drv.gemm_input_stream_mode <= 1'b0;

        run_dma_store_c();
        read_dst_and_compare_c(actual_dyn);

        if (enable_result_check) begin
            build_expected_result_vector(expected_dyn);
            publish_direct_stream_result_to_scoreboard(case_id, expected_dyn, actual_dyn);
        end

        clear_monitor_case_context();

        `uvm_info("DIRECT_STREAM_SMOKE",
            $sformatf("Completed Direct Stream CASE_ID=%0d", cid),
            UVM_LOW)
    end
    endtask

    // ------------------------------------------------------------
    // Main run phase
    // ------------------------------------------------------------
    task run_phase(uvm_phase phase);
        phase.raise_objection(this);

        `uvm_info("DIRECT_STREAM_SMOKE",
            "Starting ai_accel_subsys_direct_stream_smoke_test",
            UVM_LOW)

        init_direct_stream_ctrl_outputs();
        init_axi0_outputs();

        wait_for_reset_release();

        if (run_all != 0) begin
            run_direct_stream_one_case(100);
            repeat (10) @(vif.cb_drv);

            run_direct_stream_one_case(101);
            repeat (10) @(vif.cb_drv);

            run_direct_stream_one_case(105);
            repeat (10) @(vif.cb_drv);

            run_direct_stream_one_case(5);
            repeat (10) @(vif.cb_drv);

            run_direct_stream_one_case(400);
            repeat (10) @(vif.cb_drv);

            run_direct_stream_one_case(401);
            repeat (10) @(vif.cb_drv);

            run_direct_stream_one_case(402);
            repeat (10) @(vif.cb_drv);

            run_direct_stream_one_case(403);
        end
        else begin
            run_direct_stream_one_case(case_id);
        end

        @(vif.cb_drv);
        vif.cb_drv.gemm_input_stream_mode <= 1'b0;

        `uvm_info("DIRECT_STREAM_SMOKE",
            "ai_accel_subsys_direct_stream_smoke_test completed",
            UVM_LOW)

        phase.drop_objection(this);
    endtask

endclass

`endif