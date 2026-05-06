// File: tb/uvm/test/ai_accel_subsys_axis_stream_preload_error_test.sv

`ifndef AI_ACCEL_SUBSYS_AXIS_STREAM_PRELOAD_ERROR_TEST_SV
`define AI_ACCEL_SUBSYS_AXIS_STREAM_PRELOAD_ERROR_TEST_SV

class ai_accel_subsys_axis_stream_preload_error_test
    extends ai_accel_subsys_axis_stream_preload_smoke_test;

    `uvm_component_utils(ai_accel_subsys_axis_stream_preload_error_test)

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_axis_stream_preload_error_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // ------------------------------------------------------------
    // Wait for AXIS preload idle after an expected-error operation
    // ------------------------------------------------------------
    task automatic wait_axis_idle_after_error(input string tag);
        int unsigned timeout;
    begin
        timeout = 0;

        repeat (2) @(vif.cb_drv);

        while (vif.cb_drv.axis_load_busy !== 1'b0) begin
            @(vif.cb_drv);

            timeout++;
            if (timeout > 20000) begin
                `uvm_fatal("AXIS_PRELOAD_ERR",
                    $sformatf("Timeout waiting AXIS preload idle after expected error: %s", tag))
            end
        end

        repeat (5) @(vif.cb_drv);
    end
    endtask

    // ------------------------------------------------------------
    // Launch one AXI-Stream preload job and expect it to fail
    //
    // This directly drives beat count so zero-beat tests can be
    // expressed without going through byte_count -> ceil_div().
    // ------------------------------------------------------------
    task automatic run_axis_preload_expect_error(
        input string                  tag,
        input logic [ADDR_WIDTH-1:0]  src_addr,
        input logic [ADDR_WIDTH-1:0]  dst_addr,
        input int unsigned            beats
    );
        int unsigned timeout;
        bit done_seen;

        timeout   = 0;
        done_seen = 0;

        `uvm_info("AXIS_PRELOAD_ERR",
            $sformatf("Starting expected-error AXIS preload %s: src=0x%08h dst=0x%08h beats=%0d",
                tag, src_addr, dst_addr, beats),
            UVM_MEDIUM)

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
            if (timeout > 30000) begin
                `uvm_fatal("AXIS_PRELOAD_ERR",
                    $sformatf("Timeout waiting for expected-error AXIS preload done: %s", tag))
            end
        end

        if (vif.cb_drv.axis_load_error !== 1'b1) begin
            `uvm_fatal("AXIS_PRELOAD_ERR",
                $sformatf("Expected AXIS preload error was not reported: %s", tag))
        end

        wait_axis_idle_after_error(tag);

        `uvm_info("AXIS_PRELOAD_ERR",
            $sformatf("Observed expected AXIS preload error: %s", tag),
            UVM_MEDIUM)
    endtask

    // ------------------------------------------------------------
    // Error case 1: zero axis_load_beats
    // ------------------------------------------------------------
    task automatic run_zero_beats_error();
    begin
        run_axis_preload_expect_error(
            "zero_axis_load_beats",
            dma_src_a,
            base_a,
            0
        );
    end
    endtask

    // ------------------------------------------------------------
    // Error case 2: unaligned AXIS source address
    // ------------------------------------------------------------
    task automatic run_unaligned_source_error();
        int unsigned beats;
    begin
        beats = ceil_div(a_bytes, BYTES_PER_BEAT);

        run_axis_preload_expect_error(
            "unaligned_axis_source_address",
            dma_src_a + ADDR_WIDTH'(1),
            base_a,
            beats
        );
    end
    endtask

    // ------------------------------------------------------------
    // Error case 3: unaligned scratchpad destination address
    // ------------------------------------------------------------
    task automatic run_unaligned_destination_error();
        int unsigned beats;
    begin
        beats = ceil_div(a_bytes, BYTES_PER_BEAT);

        run_axis_preload_expect_error(
            "unaligned_axis_destination_address",
            dma_src_a,
            base_a + ADDR_WIDTH'(1),
            beats
        );
    end
    endtask

    // ------------------------------------------------------------
    // Error case 4: AXIS source RRESP error injection
    //
    // The UVM top AXIS source responder uses ctrl_if.dma_src_mem[]
    // as storage but has independent RRESP injection control:
    //   axis_src_set_rresp_error()
    // ------------------------------------------------------------
    task automatic run_axis_source_rresp_error();
        int unsigned beats;
    begin
        beats = ceil_div(a_bytes, BYTES_PER_BEAT);

        vif.axis_src_set_rresp_error(1'b1, 0);

        repeat (2) @(vif.cb_drv);

        run_axis_preload_expect_error(
            "axis_source_rresp_error_beat0",
            dma_src_a,
            base_a,
            beats
        );

        vif.axis_src_set_rresp_error(1'b0, -1);

        repeat (5) @(vif.cb_drv);
    end
    endtask

    // ------------------------------------------------------------
    // Valid recovery path after AXIS preload errors
    //
    // Full recovery path:
    //   AXIS preload A
    //   AXIS preload B
    //   GEMM
    //   DMA store C
    //   destination memory compare
    //   scoreboard publish
    // ------------------------------------------------------------
    task automatic run_valid_axis_recovery(input int unsigned cid);
        int signed expected_dyn[];
        int signed actual_dyn[];
    begin
        `uvm_info("AXIS_PRELOAD_ERR",
            $sformatf("Starting valid AXIS recovery case after errors: CASE_ID=%0d", cid),
            UVM_LOW)

        configure_case(cid);

        clear_c_region();
        clear_dma_destination_memory();
        preload_dma_source_memory();

        vif.axis_src_set_rresp_error(1'b0, -1);

        run_axis_preload("A_recovery", dma_src_a, base_a, a_bytes);
        run_axis_preload("B_recovery", dma_src_b, base_b, b_bytes);

        run_gemm(cid);

        run_dma_store_c();
        read_dst_and_compare_c(actual_dyn);

        if (enable_result_check) begin
            build_expected_result_vector(expected_dyn);
            publish_axis_result_to_scoreboard(cid, expected_dyn, actual_dyn);
        end

        clear_monitor_case_context();

        `uvm_info("AXIS_PRELOAD_ERR",
            $sformatf("Completed valid AXIS recovery case after errors: CASE_ID=%0d", cid),
            UVM_LOW)
    end
    endtask

    // ------------------------------------------------------------
    // Main run phase
    // ------------------------------------------------------------
    task run_phase(uvm_phase phase);
        int unsigned recovery_case_id;

        phase.raise_objection(this);

        `uvm_info("AXIS_PRELOAD_ERR",
            "Starting ai_accel_subsys_axis_stream_preload_error_test",
            UVM_LOW)

        init_axis_ctrl_outputs();
        init_axi0_outputs();

        wait_for_reset_release();

        // Use CASE_ID as recovery case selector.
        // Default is inherited from parent build_phase: CASE_ID=100.
        recovery_case_id = case_id;

        // Configure once before invalid AXIS preload attempts.
        // Error cases use the same A source/base context.
        configure_case(recovery_case_id);
        clear_c_region();
        clear_dma_destination_memory();
        preload_dma_source_memory();

        vif.axis_src_set_rresp_error(1'b0, -1);

        // --------------------------------------------------------
        // Expected AXIS preload error cases
        // --------------------------------------------------------
        run_zero_beats_error();
        run_unaligned_source_error();
        run_unaligned_destination_error();
        run_axis_source_rresp_error();

        // --------------------------------------------------------
        // Recovery:
        //   Valid AXIS preload A/B -> GEMM -> DMA store -> compare
        // --------------------------------------------------------
        run_valid_axis_recovery(recovery_case_id);

        `uvm_info("AXIS_PRELOAD_ERR",
            "ai_accel_subsys_axis_stream_preload_error_test completed",
            UVM_LOW)

        phase.drop_objection(this);
    endtask

endclass

`endif