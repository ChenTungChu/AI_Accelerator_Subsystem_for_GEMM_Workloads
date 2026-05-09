// File: tb/uvm/test/ai_accel_subsys_direct_stream_error_test.sv

`ifndef AI_ACCEL_SUBSYS_DIRECT_STREAM_ERROR_TEST_SV
`define AI_ACCEL_SUBSYS_DIRECT_STREAM_ERROR_TEST_SV

class ai_accel_subsys_direct_stream_error_test
    extends ai_accel_subsys_direct_stream_smoke_test;

    `uvm_component_utils(ai_accel_subsys_direct_stream_error_test)

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_direct_stream_error_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // ------------------------------------------------------------
    // Wait for Direct Stream preload idle after expected-error op
    // ------------------------------------------------------------
    task automatic wait_ds_idle_after_error(input string tag);
        int unsigned timeout;
    begin
        timeout = 0;

        repeat (2) @(vif.cb_drv);

        while (vif.cb_drv.ds_load_busy !== 1'b0) begin
            @(vif.cb_drv);

            timeout++;
            if (timeout > 30000) begin
                `uvm_fatal("DIRECT_STREAM_ERR",
                    $sformatf("Timeout waiting Direct Stream preload idle after expected error: %s", tag))
            end
        end

        repeat (5) @(vif.cb_drv);
    end
    endtask

    // ------------------------------------------------------------
    // Launch one Direct Stream preload and expect it to fail
    //
    // This task directly controls beat count so zero-beat cases can
    // be expressed without byte_count -> ceil_div().
    //
    // operand_sel:
    //   0 = A
    //   1 = B
    //   X = invalid operand select check
    // ------------------------------------------------------------
    task automatic run_direct_stream_preload_expect_error(
        input string                  tag,
        input logic                   operand_sel,
        input logic [ADDR_WIDTH-1:0]  src_addr,
        input logic [ADDR_WIDTH-1:0]  dst_addr,
        input int unsigned            beats
    );
        int unsigned timeout;
        bit done_seen;

        timeout   = 0;
        done_seen = 0;

        `uvm_info("DIRECT_STREAM_ERR",
            $sformatf("Starting expected-error Direct Stream preload %s: operand=%0b src=0x%08h dst=0x%08h beats=%0d",
                tag, operand_sel, src_addr, dst_addr, beats),
            UVM_MEDIUM)

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
            if (timeout > 40000) begin
                `uvm_fatal("DIRECT_STREAM_ERR",
                    $sformatf("Timeout waiting for expected-error Direct Stream preload done: %s", tag))
            end
        end

        if (vif.cb_drv.ds_load_error !== 1'b1) begin
            `uvm_fatal("DIRECT_STREAM_ERR",
                $sformatf("Expected Direct Stream preload error was not reported: %s", tag))
        end

        wait_ds_idle_after_error(tag);

        @(vif.cb_drv);
        vif.cb_drv.ds_operand_sel <= OPERAND_A;

        `uvm_info("DIRECT_STREAM_ERR",
            $sformatf("Observed expected Direct Stream preload error: %s", tag),
            UVM_MEDIUM)
    endtask

    // ------------------------------------------------------------
    // Error case 1: zero ds_load_beats
    // ------------------------------------------------------------
    task automatic run_zero_beats_error();
    begin
        run_direct_stream_preload_expect_error(
            "zero_ds_load_beats",
            OPERAND_A,
            dma_src_a,
            base_a,
            0
        );
    end
    endtask

    // ------------------------------------------------------------
    // Error case 2: unaligned DS source address
    // ------------------------------------------------------------
    task automatic run_unaligned_source_error();
        int unsigned beats;
    begin
        beats = ceil_div(a_bytes, BYTES_PER_BEAT);

        run_direct_stream_preload_expect_error(
            "unaligned_ds_source_address",
            OPERAND_A,
            dma_src_a + ADDR_WIDTH'(1),
            base_a,
            beats
        );
    end
    endtask

    // ------------------------------------------------------------
    // Error case 3: unaligned logical destination/base address
    // ------------------------------------------------------------
    task automatic run_unaligned_destination_error();
        int unsigned beats;
    begin
        beats = ceil_div(a_bytes, BYTES_PER_BEAT);

        run_direct_stream_preload_expect_error(
            "unaligned_ds_destination_address",
            OPERAND_A,
            dma_src_a,
            base_a + ADDR_WIDTH'(1),
            beats
        );
    end
    endtask

    // ------------------------------------------------------------
    // Error case 4: invalid operand select
    //
    // ds_operand_sel is a 1-bit logic signal. In normal software use
    // it can only be 0 or 1, but RTL launch validation also protects
    // against X/Z. This intentionally drives X in simulation.
    // ------------------------------------------------------------
    task automatic run_invalid_operand_sel_error();
        int unsigned beats;
    begin
        beats = ceil_div(a_bytes, BYTES_PER_BEAT);

        run_direct_stream_preload_expect_error(
            "invalid_ds_operand_sel_x",
            1'bx,
            dma_src_a,
            base_a,
            beats
        );
    end
    endtask

    // ------------------------------------------------------------
    // Error case 5: Direct Stream source RRESP error injection
    //
    // UVM top DS source responder uses ctrl_if.dma_src_mem[] as
    // source storage, but has independent RRESP injection control:
    //   ds_src_set_rresp_error()
    // ------------------------------------------------------------
    task automatic run_ds_source_rresp_error();
        int unsigned beats;
    begin
        beats = ceil_div(a_bytes, BYTES_PER_BEAT);

        vif.ds_src_set_rresp_error(1'b1, 0);

        repeat (2) @(vif.cb_drv);

        run_direct_stream_preload_expect_error(
            "ds_source_rresp_error_beat0",
            OPERAND_A,
            dma_src_a,
            base_a,
            beats
        );

        vif.ds_src_set_rresp_error(1'b0, -1);

        repeat (5) @(vif.cb_drv);
    end
    endtask

    // ------------------------------------------------------------
    // Valid recovery path after Direct Stream errors
    //
    // Full recovery path:
    //   Direct Stream preload A
    //   Direct Stream preload B
    //   GEMM reads A/B from operand buffer
    //   GEMM writes C to scratchpad
    //   DMA store C
    //   destination memory compare
    //   scoreboard publish
    // ------------------------------------------------------------
    task automatic run_valid_direct_stream_recovery(input int unsigned cid);
    begin
        `uvm_info("DIRECT_STREAM_ERR",
            $sformatf("Starting valid Direct Stream recovery case after errors: CASE_ID=%0d", cid),
            UVM_LOW)

        vif.ds_src_set_rresp_error(1'b0, -1);

        run_direct_stream_one_case(cid);

        `uvm_info("DIRECT_STREAM_ERR",
            $sformatf("Completed valid Direct Stream recovery case after errors: CASE_ID=%0d", cid),
            UVM_LOW)
    end
    endtask

    // ------------------------------------------------------------
    // Main run phase
    // ------------------------------------------------------------
    task run_phase(uvm_phase phase);
        int unsigned recovery_case_id;

        phase.raise_objection(this);

        `uvm_info("DIRECT_STREAM_ERR",
            "Starting ai_accel_subsys_direct_stream_error_test",
            UVM_LOW)

        init_direct_stream_ctrl_outputs();
        init_axi0_outputs();

        wait_for_reset_release();

        // Use CASE_ID as recovery selector.
        // Default inherited from parent build_phase is CASE_ID=100.
        recovery_case_id = case_id;

        // Configure once for invalid preload attempts.
        configure_case(recovery_case_id);
        clear_c_region();
        clear_dma_destination_memory();
        preload_dma_source_memory();

        @(vif.cb_drv);
        vif.cb_drv.gemm_input_stream_mode <= 1'b0;

        vif.ds_src_set_rresp_error(1'b0, -1);
        vif.dma_dst_set_bresp_error(1'b0, -1);

        // --------------------------------------------------------
        // Expected Direct Stream preload error cases
        // --------------------------------------------------------
        run_zero_beats_error();
        run_unaligned_source_error();
        run_unaligned_destination_error();
        run_invalid_operand_sel_error();
        run_ds_source_rresp_error();

        // --------------------------------------------------------
        // Recovery:
        //   Valid Direct Stream A/B preload
        //   -> GEMM
        //   -> DMA store
        //   -> destination compare
        //   -> scoreboard
        // --------------------------------------------------------
        run_valid_direct_stream_recovery(recovery_case_id);

        @(vif.cb_drv);
        vif.cb_drv.gemm_input_stream_mode <= 1'b0;
        vif.cb_drv.ds_operand_sel         <= OPERAND_A;

        `uvm_info("DIRECT_STREAM_ERR",
            "ai_accel_subsys_direct_stream_error_test completed",
            UVM_LOW)

        phase.drop_objection(this);
    endtask

endclass

`endif