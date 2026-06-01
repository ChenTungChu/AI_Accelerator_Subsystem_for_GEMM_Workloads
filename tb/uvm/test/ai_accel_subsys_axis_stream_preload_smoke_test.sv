// File: tb/uvm/test/ai_accel_subsys_axis_stream_preload_smoke_test.sv

`ifndef AI_ACCEL_SUBSYS_AXIS_STREAM_PRELOAD_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_AXIS_STREAM_PRELOAD_SMOKE_TEST_SV

class ai_accel_subsys_axis_stream_preload_smoke_test
    extends ai_accel_subsys_dma_store_smoke_test;

    `uvm_component_utils(ai_accel_subsys_axis_stream_preload_smoke_test)

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_axis_stream_preload_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // ------------------------------------------------------------
    // Build AXIS-specific test name from case id / test kind
    // ------------------------------------------------------------
    function automatic string build_axis_test_name(
        input int unsigned cid,
        input ai_accel_subsys_seq_item::test_kind_e kind
    );
        case (kind)
            ai_accel_subsys_seq_item::TEST_KIND_FIXED_BASELINE:
                return $sformatf("axis_stream_preload_fixed_baseline_case_%0d", cid);

            ai_accel_subsys_seq_item::TEST_KIND_VARIABLE_DIM_SMOKE:
                return $sformatf("axis_stream_preload_variable_dim_case_%0d", cid);

            ai_accel_subsys_seq_item::TEST_KIND_CONFIGURABLE_BASE:
                return $sformatf("axis_stream_preload_config_base_case_%0d", cid);

            ai_accel_subsys_seq_item::TEST_KIND_C_RMW_ACCUM_RECIPE:
                return $sformatf("axis_stream_c_rmw_accum_recipe_%0d", cid);

            default:
                return $sformatf("axis_stream_preload_case_%0d_kind_%0d", cid, kind);
        endcase
    endfunction

    // ------------------------------------------------------------
    // Initialize ctrl_if outputs
    //
    // Reuse parent initialization, then add AXIS preload outputs.
    // ------------------------------------------------------------
    task automatic init_axis_ctrl_outputs();
    begin
        init_ctrl_outputs();

        @(vif.cb_drv);

        vif.cb_drv.axis_load_start    <= 1'b0;
        vif.cb_drv.axis_src_base_addr <= '0;
        vif.cb_drv.axis_dst_base_addr <= '0;
        vif.cb_drv.axis_load_beats    <= '0;

        vif.axis_src_set_rresp_error(1'b0, -1);
    end
    endtask

    // ------------------------------------------------------------
    // Publish AXIS result vectors to scoreboard through result_bridge
    //
    // Same payload format as DMA-store smoke.
    // Only test_name is changed so scoreboard/reporting shows AXIS path.
    // ------------------------------------------------------------
    task automatic publish_axis_result_to_scoreboard(
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
            `uvm_fatal("AXIS_PRELOAD_SMOKE/NOENV",
                "env is null in publish_axis_result_to_scoreboard()")
        end

        if (env.result_bridge == null) begin
            `uvm_fatal("AXIS_PRELOAD_SMOKE/NOBRIDGE",
                "env.result_bridge is null in publish_axis_result_to_scoreboard()")
        end

        kind      = infer_test_kind(cid);
        test_name = build_axis_test_name(cid, kind);

        `uvm_info("AXIS_PRELOAD_SMOKE",
            $sformatf("Publishing AXIS preload result payload: case_id=%0d test_kind=%0d C_words=%0d",
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
    // Launch one AXI-Stream preload job
    //
    // Source:
    //   ctrl_if.dma_src_mem[] through axis_src_axi_ar/r responder
    //
    // Path:
    //   axis_src_axi_ar/r
    //     -> axi_mm2s_dma
    //     -> axis_async_fifo
    //     -> axi_stream_loader
    //     -> axis_scratchpad_write_adapter
    //     -> scratchpad Port1
    // ------------------------------------------------------------
    task automatic run_axis_preload(
        input string                  tag,
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
            `uvm_fatal("AXIS_PRELOAD_SMOKE",
                $sformatf("Invalid zero-beat AXIS preload for %s", tag))
        end

        if (!addr_is_beat_aligned(src_addr)) begin
            `uvm_fatal("AXIS_PRELOAD_SMOKE",
                $sformatf("AXIS preload source address must be beat aligned for %s: src=0x%08h",
                    tag, src_addr))
        end

        if (!addr_is_beat_aligned(dst_addr)) begin
            `uvm_fatal("AXIS_PRELOAD_SMOKE",
                $sformatf("AXIS preload destination address must be beat aligned for %s: dst=0x%08h",
                    tag, dst_addr))
        end

        `uvm_info("AXIS_PRELOAD_SMOKE",
            $sformatf("Starting AXIS preload %s: src=0x%08h dst=0x%08h bytes=%0d beats=%0d",
                tag, src_addr, dst_addr, byte_count, beats),
            UVM_MEDIUM)

        vif.axis_src_set_rresp_error(1'b0, -1);

        @(vif.cb_drv);
        vif.cb_drv.axis_src_base_addr <= src_addr;
        vif.cb_drv.axis_dst_base_addr <= dst_addr;
        vif.cb_drv.axis_load_beats    <= beats[31:0];
        vif.cb_drv.axis_load_start    <= 1'b1;

        @(vif.cb_drv);
        vif.cb_drv.axis_load_start    <= 1'b0;

        while (!done_seen) begin
            @(vif.cb_drv);

            if (vif.cb_drv.axis_load_done === 1'b1) begin
                done_seen = 1;
            end

            timeout++;
            if (timeout > 20000) begin
                `uvm_fatal("AXIS_PRELOAD_SMOKE",
                    $sformatf("Timeout waiting for AXIS preload done: %s", tag))
            end
        end

        if (vif.cb_drv.axis_load_error !== 1'b0) begin
            `uvm_fatal("AXIS_PRELOAD_SMOKE",
                $sformatf("AXIS preload reported error: %s", tag))
        end

        repeat (8) @(vif.cb_drv);

        if (vif.cb_drv.axis_load_busy !== 1'b0) begin
            `uvm_fatal("AXIS_PRELOAD_SMOKE",
                $sformatf("AXIS preload busy did not clear after done: %s", tag))
        end

        `uvm_info("AXIS_PRELOAD_SMOKE",
            $sformatf("Completed AXIS preload %s", tag),
            UVM_MEDIUM)
    endtask

    // ------------------------------------------------------------
    // C RMW accumulation frontend hook
    //
    // Parent run_c_rmw_accum_frontend_recipe() owns the multi-job
    // recipe flow.  This override only changes how each compact
    // partial A/B payload reaches the accelerator frontend.
    // ------------------------------------------------------------
    virtual task automatic run_c_rmw_accum_frontend_preload_ab(
        input int unsigned             cid,
        input ai_accel_subsys_seq_item job_item
    );
    begin
        preload_dma_source_memory();

        run_axis_preload("A", dma_src_a, base_a, a_bytes);
        run_axis_preload("B", dma_src_b, base_b, b_bytes);
    end
    endtask

    virtual task automatic publish_frontend_result_to_scoreboard(
        input int unsigned cid,
        input int signed   expected_dyn[],
        input int signed   actual_dyn[]
    );
    begin
        publish_axis_result_to_scoreboard(cid, expected_dyn, actual_dyn);
    end
    endtask

    // ------------------------------------------------------------
    // Run one AXIS-preload configured case
    // ------------------------------------------------------------
    task automatic run_axis_one_case(input int unsigned cid);
        int signed expected_dyn[];
        int signed actual_dyn[];
    begin
        if (is_c_rmw_accum_recipe_case(cid)) begin
            run_c_rmw_accum_frontend_recipe(cid);
            return;
        end

        case_id = cid;
        configure_case(case_id);

        clear_c_region();
        clear_dma_destination_memory();
        preload_dma_source_memory();

        // --------------------------------------------------------
        // Key difference from dma_store_smoke:
        //
        //   Old:
        //     DMA load A/B through Port0
        //
        //   New:
        //     AXI-Stream preload A/B through Port1
        // --------------------------------------------------------
        run_axis_preload("A", dma_src_a, base_a, a_bytes);
        run_axis_preload("B", dma_src_b, base_b, b_bytes);

        run_gemm(case_id);

        run_dma_store_c();
        read_dst_and_compare_c(actual_dyn);

        if (enable_result_check) begin
            build_expected_result_vector(expected_dyn);
            publish_axis_result_to_scoreboard(case_id, expected_dyn, actual_dyn);
        end

        clear_monitor_case_context();

        `uvm_info("AXIS_PRELOAD_SMOKE",
            $sformatf("Completed AXIS preload CASE_ID=%0d", cid),
            UVM_LOW)
    end
    endtask

    // ------------------------------------------------------------
    // Main run phase
    // ------------------------------------------------------------
    task run_phase(uvm_phase phase);
        phase.raise_objection(this);

        `uvm_info("AXIS_PRELOAD_SMOKE",
            "Starting ai_accel_subsys_axis_stream_preload_smoke_test",
            UVM_LOW)

        init_axis_ctrl_outputs();
        init_axi0_outputs();

        wait_for_reset_release();

        if (run_all != 0) begin
            run_axis_one_case(100);
            repeat (10) @(vif.cb_drv);

            run_axis_one_case(101);
            repeat (10) @(vif.cb_drv);

            run_axis_one_case(105);
            repeat (10) @(vif.cb_drv);

            run_axis_one_case(5);
            repeat (10) @(vif.cb_drv);

            run_axis_one_case(400);
            repeat (10) @(vif.cb_drv);

            run_axis_one_case(401);
            repeat (10) @(vif.cb_drv);

            run_axis_one_case(402);
            repeat (10) @(vif.cb_drv);

            run_axis_one_case(403);
        end
        else begin
            run_axis_one_case(case_id);
        end

        `uvm_info("AXIS_PRELOAD_SMOKE",
            "ai_accel_subsys_axis_stream_preload_smoke_test completed",
            UVM_LOW)

        phase.drop_objection(this);
    endtask

endclass

`endif