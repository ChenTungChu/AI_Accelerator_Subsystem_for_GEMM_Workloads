// File: tb/uvm/test/ai_accel_subsys_csr_axis_stream_load_store_smoke_test.sv
`ifndef AI_ACCEL_SUBSYS_CSR_AXIS_STREAM_LOAD_STORE_SMOKE_TEST_SV
`define AI_ACCEL_SUBSYS_CSR_AXIS_STREAM_LOAD_STORE_SMOKE_TEST_SV

// ------------------------------------------------------------
// CSR-controlled AXI-Stream preload + GEMM + DMA store representative smoke
//
// Scope:
//   - preload A/B into the shared source memory model
//   - use CSR START_AXIS_LOAD to copy A into scratchpad
//   - use CSR START_AXIS_LOAD to copy B into scratchpad
//   - use CSR START_GEMM to launch host-primary scratchpad GEMM
//   - use CSR START_DMA_STORE to move C into the destination memory model
//   - compare destination memory against the software reference directly
//
// This focused CSR test intentionally bypasses the legacy sideband
// driver/scoreboard launch path.  Pass/fail is determined by CSR
// command/status sequencing and the final DMA destination memory compare.
// ------------------------------------------------------------

class ai_accel_subsys_csr_axis_stream_load_store_smoke_test extends ai_accel_subsys_csr_smoke_test;
    `uvm_component_utils(ai_accel_subsys_csr_axis_stream_load_store_smoke_test)

    localparam int unsigned BYTES_PER_BEAT = 8;

    localparam logic [31:0] AXIS_SRC_A_BASE = 32'h0000_0000;
    localparam logic [31:0] AXIS_SRC_B_BASE = 32'h0000_0100;
    localparam logic [31:0] DMA_DST_C_BASE  = 32'h0000_0000;

    // ------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------
    function new(string name = "ai_accel_subsys_csr_axis_stream_load_store_smoke_test",
                 uvm_component parent = null);
        super.new(name, parent);
    endfunction

    // ------------------------------------------------------------
    // Size helpers
    // ------------------------------------------------------------
    function automatic int unsigned bytes_to_beats(input int unsigned byte_count);
        if (byte_count == 0) begin
            `uvm_fatal("CSR_AXIS_SMOKE/ZERO_BYTES",
                "Attempted to convert zero byte_count to AXI-Stream preload beats")
        end

        return (byte_count + BYTES_PER_BEAT - 1) / BYTES_PER_BEAT;
    endfunction

    function automatic int unsigned c_word_count(input ai_accel_subsys_seq_item profile_item);
        return int'(profile_item.dim_m) * int'(profile_item.dim_n);
    endfunction

    // ------------------------------------------------------------
    // Case payload builder
    // ------------------------------------------------------------
    task automatic build_selected_payload(
        output ai_accel_subsys_seq_item profile_item,
        output int signed               a_flat[],
        output int signed               b_flat[],
        output int signed               expected_c[]
    );
    begin
        case (selected_test_kind)
            ai_accel_subsys_seq_item::TEST_KIND_FIXED_BASELINE: begin
                case_helper.build_fixed_case_payload(
                    selected_case_id,
                    profile_item,
                    a_flat,
                    b_flat,
                    expected_c
                );
            end

            ai_accel_subsys_seq_item::TEST_KIND_VARIABLE_DIM_SMOKE: begin
                case_helper.build_variable_case_payload(
                    selected_case_id,
                    profile_item,
                    a_flat,
                    b_flat,
                    expected_c
                );
            end

            ai_accel_subsys_seq_item::TEST_KIND_CONFIGURABLE_BASE: begin
                case_helper.build_configurable_base_case_payload(
                    selected_case_id,
                    profile_item,
                    a_flat,
                    b_flat,
                    expected_c
                );
            end

            default: begin
                `uvm_fatal("CSR_AXIS_SMOKE/BAD_KIND",
                    $sformatf("Unsupported CSR AXI-Stream load-store smoke test_kind=%0d CASE_ID=%0d",
                        selected_test_kind, selected_case_id))
            end
        endcase
    end
    endtask

    // ------------------------------------------------------------
    // Source/destination memory model preparation
    // ------------------------------------------------------------
    task automatic write_u8_payload_to_shared_src(
        input logic [31:0] base_addr,
        input int signed   payload[]
    );
        int unsigned i;
        logic [7:0] byte_value;
    begin
        for (i = 0; i < payload.size(); i++) begin
            byte_value = payload[i][7:0];
            vif.dma_src_mem_write_byte(
                base_addr + 32'(i),
                byte_value
            );
        end
    end
    endtask

    task automatic prepare_axis_source_and_destination(
        input int signed a_flat[],
        input int signed b_flat[]
    );
    begin
        vif.dma_src_mem_clear();
        vif.dma_dst_mem_clear();

        vif.dma_src_set_rresp_error(1'b0, -1);
        vif.axis_src_set_rresp_error(1'b0, -1);
        vif.ds_src_set_rresp_error(1'b0, -1);
        vif.dma_dst_set_bresp_error(1'b0, -1);

        write_u8_payload_to_shared_src(AXIS_SRC_A_BASE, a_flat);
        write_u8_payload_to_shared_src(AXIS_SRC_B_BASE, b_flat);

        `uvm_info("CSR_AXIS_SMOKE",
            $sformatf("Prepared AXI-Stream source payloads: A src=0x%08h bytes=%0d, B src=0x%08h bytes=%0d, dst C base=0x%08h",
                AXIS_SRC_A_BASE,
                a_flat.size(),
                AXIS_SRC_B_BASE,
                b_flat.size(),
                DMA_DST_C_BASE),
            UVM_MEDIUM)
    end
    endtask

    // ------------------------------------------------------------
    // Generic CSR done polling for non-GEMM operations
    // ------------------------------------------------------------
    task automatic csr_poll_done_bit(
        input int unsigned timeout_cycles,
        input int unsigned done_bit,
        input string       tag
    );
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        int unsigned cnt;
    begin
        cnt = 0;

        forever begin
            csr.read32_expect_okay(
                ai_accel_csr_access_helper::CSR_DONE_STATUS,
                done_status
            );

            csr.read32_expect_okay(
                ai_accel_csr_access_helper::CSR_ERROR_STATUS,
                error_status
            );

            csr.read32_expect_okay(
                ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS,
                reject_status
            );

            if (error_status != 32'h0000_0000) begin
                `uvm_fatal("CSR_AXIS_SMOKE/ERROR_STATUS",
                    $sformatf("%s: CSR_ERROR_STATUS became nonzero: 0x%08h",
                        tag, error_status))
            end

            if (reject_status != 32'h0000_0000) begin
                `uvm_fatal("CSR_AXIS_SMOKE/REJECT_STATUS",
                    $sformatf("%s: CSR_CMD_REJECT_STATUS became nonzero: 0x%08h",
                        tag, reject_status))
            end

            if (done_status[done_bit]) begin
                `uvm_info("CSR_AXIS_SMOKE",
                    $sformatf("Observed CSR %s done after %0d poll cycle(s): DONE_STATUS=0x%08h",
                        tag, cnt, done_status),
                    UVM_MEDIUM)
                return;
            end

            @(posedge csr_vif.clk);
            cnt++;

            if (cnt > timeout_cycles) begin
                `uvm_fatal("CSR_AXIS_SMOKE/DONE_TIMEOUT",
                    $sformatf("Timed out waiting for CSR %s done after %0d cycles",
                        tag, timeout_cycles))
            end
        end
    end
    endtask

    // ------------------------------------------------------------
    // CSR AXI-Stream preload command sequence
    // ------------------------------------------------------------
    task automatic csr_write_axis_load_config(
        input logic [31:0] src_base,
        input logic [31:0] dst_base,
        input int unsigned beats,
        input string       tag
    );
    begin
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_AXIS_SRC_BASE,
            src_base
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_AXIS_DST_BASE,
            dst_base
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_AXIS_LOAD_BEATS,
            32'(beats)
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_AXIS_SRC_BASE,
            src_base,
            {tag, " CSR_AXIS_SRC_BASE"}
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_AXIS_DST_BASE,
            dst_base,
            {tag, " CSR_AXIS_DST_BASE"}
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_AXIS_LOAD_BEATS,
            32'(beats),
            {tag, " CSR_AXIS_LOAD_BEATS"}
        );

        `uvm_info("CSR_AXIS_SMOKE",
            $sformatf("Programmed CSR AXI-Stream preload %s: src=0x%08h dst=0x%08h beats=%0d",
                tag, src_base, dst_base, beats),
            UVM_MEDIUM)
    end
    endtask

    task automatic csr_start_axis_load(input string tag);
        logic [31:0] cmd;
    begin
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::CMD_START_AXIS_LOAD] = 1'b1;
        csr.issue_command(cmd);

        `uvm_info("CSR_AXIS_SMOKE",
            $sformatf("Issued CSR START_AXIS_LOAD command for %s", tag),
            UVM_MEDIUM)
    end
    endtask

    task automatic run_one_axis_load(
        input logic [31:0] src_base,
        input logic [31:0] dst_base,
        input int unsigned byte_count,
        input string       tag
    );
        int unsigned beats;
    begin
        beats = bytes_to_beats(byte_count);

        csr_clear_sticky_status();
        csr_write_axis_load_config(src_base, dst_base, beats, tag);
        csr_start_axis_load(tag);
        csr_poll_done_bit(
            done_timeout_cycles,
            ai_accel_csr_access_helper::DONE_AXIS_LOAD,
            {"AXIS_LOAD_", tag}
        );

        repeat (2) @(posedge csr_vif.clk);
    end
    endtask

    // ------------------------------------------------------------
    // CODE-COV-C1.1-D1 P14 AXI-Stream reject probes
    // ------------------------------------------------------------
    task automatic run_d1_axis_reject_probes(
        input logic [31:0] dst_base
    );
    begin
        csr_clear_sticky_status();

        csr_write_axis_load_config(AXIS_SRC_A_BASE, dst_base, 0, "D1_ZERO_AXIS");
        csr_start_axis_load("D1_ZERO_AXIS");
        repeat (2) @(posedge csr_vif.clk);
        csr_expect_p14_reject_bit(C1D1_P14_REJ_ZERO_LENGTH,
            "START_AXIS_LOAD with zero beats");
        csr_clear_p14_reject_status("after zero-beat AXIS load reject");

        csr_write_axis_load_config(AXIS_SRC_A_BASE, dst_base, 8, "D1_BUSY_AXIS");
        csr_start_axis_load("D1_BUSY_AXIS");
        csr_wait_p14_status_bit(C1D1_P14_STATUS_AXIS_LOAD_BUSY,
            done_timeout_cycles, "AXIS load before busy-start reject");
        csr_start_axis_load("D1_BUSY_AXIS_SECOND_START");
        repeat (2) @(posedge csr_vif.clk);
        csr_expect_p14_reject_bit(C1D1_P14_REJ_AXIS_BUSY,
            "START_AXIS_LOAD while AXIS load busy");
        csr_clear_p14_reject_status("after AXIS load busy reject");
        csr_poll_done_bit(done_timeout_cycles,
            ai_accel_csr_access_helper::DONE_AXIS_LOAD,
            "D1_AXIS_BUSY_OWNER");

        csr_clear_sticky_status();
        `uvm_info("CODE_COV_C1D1/P14_AXIS_REJECT_PASS",
            "P14 AXI-Stream zero-length and genuine-busy reject probes PASS",
            UVM_MEDIUM)
    end
    endtask

    // ------------------------------------------------------------
    // CODE-COV-C1.1-D2 P14 genuine AXI-Stream source error propagation
    // ------------------------------------------------------------
    task automatic run_d2_axis_error_probe(
        input logic [31:0] dst_base,
        input int unsigned byte_count
    );
        logic [31:0] status;
        logic [31:0] done_status;
        logic [31:0] error_status;
        logic [31:0] reject_status;
        logic [31:0] expected_error;
        logic [31:0] expected_done;
        int unsigned beats;
        int unsigned cnt;
    begin
        beats          = bytes_to_beats(byte_count);
        expected_error = 32'h0000_0001 << 1;
        expected_done  = 32'h0000_0001 << ai_accel_csr_access_helper::DONE_AXIS_LOAD;

        csr_clear_sticky_status();
        repeat (2) @(posedge csr_vif.clk);

        vif.axis_src_set_rresp_error(1'b1, 0);
        csr_write_axis_load_config(AXIS_SRC_A_BASE, dst_base, beats, "D2_AXIS_ERROR");
        csr_start_axis_load("D2_AXIS_ERROR");

        cnt = 0;
        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_STATUS, status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_ERROR_STATUS, error_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS, reject_status);

            if (reject_status != 32'h0000_0000) begin
                vif.axis_src_set_rresp_error(1'b0, -1);
                `uvm_fatal("CODE_COV_C1D2/P14_AXIS_REJECT",
                    $sformatf("Unexpected P14 reject during genuine AXI-Stream RRESP error probe: reject=0x%08h status=0x%08h",
                        reject_status, status))
            end

            if ((error_status != 32'h0000_0000) && (error_status != expected_error)) begin
                vif.axis_src_set_rresp_error(1'b0, -1);
                `uvm_fatal("CODE_COV_C1D2/P14_AXIS_BAD_ERROR",
                    $sformatf("Unexpected P14 error bits during AXI-Stream RRESP probe: expected=0x%08h actual=0x%08h",
                        expected_error, error_status))
            end

            if (error_status == expected_error) begin
                break;
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > done_timeout_cycles) begin
                vif.axis_src_set_rresp_error(1'b0, -1);
                `uvm_fatal("CODE_COV_C1D2/P14_AXIS_TIMEOUT",
                    $sformatf("Timed out waiting for P14 AXI-Stream error after %0d cycles", done_timeout_cycles))
            end
        end

        vif.axis_src_set_rresp_error(1'b0, -1);

        // AXI-Stream engine error is level-held until the next accepted
        // AXIS start.  Wait for the failed owner to drain first.
        cnt = 0;
        while (status[C1D1_P14_STATUS_AXIS_LOAD_BUSY]) begin
            @(posedge csr_vif.clk);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_STATUS, status);
            cnt++;
            if (cnt > done_timeout_cycles) begin
                `uvm_fatal("CODE_COV_C1D2/P14_AXIS_BUSY_TIMEOUT",
                    "AXI-Stream load engine remained busy after genuine RRESP error")
            end
        end

        // Remove any DONE left by the terminal failed operation without
        // attempting to clear ERROR while the engine still drives it high.
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_DONE_STATUS,
            expected_done
        );

        // Re-arm the engine with a genuine legal start.  The engine clears
        // its level-held dma_error_q on this accepted start.
        csr_write_axis_load_config(AXIS_SRC_A_BASE, dst_base, beats, "D2_AXIS_RECOVERY");
        csr_start_axis_load("D2_AXIS_RECOVERY");

        cnt = 0;
        forever begin
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_STATUS, status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_DONE_STATUS, done_status);
            csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS, reject_status);

            if (reject_status != 32'h0000_0000) begin
                `uvm_fatal("CODE_COV_C1D2/P14_AXIS_RECOVERY_REJECT",
                    $sformatf("Recovery AXI-Stream start was rejected: reject=0x%08h status=0x%08h",
                        reject_status, status))
            end

            if (status[C1D1_P14_STATUS_AXIS_LOAD_BUSY] ||
                ((done_status & expected_done) != 32'h0000_0000)) begin
                break;
            end

            @(posedge csr_vif.clk);
            cnt++;
            if (cnt > done_timeout_cycles) begin
                `uvm_fatal("CODE_COV_C1D2/P14_AXIS_RECOVERY_START_TIMEOUT",
                    "Recovery AXI-Stream operation never became active or completed")
            end
        end

        repeat (2) @(posedge csr_vif.clk);

        // Now the source engine is deasserting axis_load_error.  Direct W1C
        // can clear the CSR sticky bit without it being immediately re-latched.
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_ERROR_STATUS,
            expected_error
        );
        repeat (2) @(posedge csr_vif.clk);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_ERROR_STATUS, error_status);
        csr.read32_expect_okay(ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS, reject_status);
        if ((error_status != 32'h0000_0000) || (reject_status != 32'h0000_0000)) begin
            `uvm_fatal("CODE_COV_C1D2/P14_AXIS_CLEAR",
                $sformatf("P14 sticky cleanup failed after AXI-Stream recovery re-arm: error=0x%08h reject=0x%08h",
                    error_status, reject_status))
        end

        csr_poll_done_bit(
            done_timeout_cycles,
            ai_accel_csr_access_helper::DONE_AXIS_LOAD,
            "D2_AXIS_RECOVERY"
        );
        csr_clear_sticky_status();

        `uvm_info("CODE_COV_C1D2/P14_AXIS_ERROR_PASS",
            $sformatf("Genuine AXI-Stream source RRESP error propagated to P14 ERROR_STATUS and recovered: observed=0x%08h post_rearm_clear=0x%08h",
                expected_error, error_status),
            UVM_MEDIUM)
    end
    endtask

    // ------------------------------------------------------------
    // CSR DMA store command sequence
    // ------------------------------------------------------------
    task automatic csr_write_dma_store_config(
        input logic [31:0] src_base,
        input logic [31:0] dst_base,
        input int unsigned byte_count
    );
    begin
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_DMA_STORE_SRC_BASE,
            src_base
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_DMA_STORE_DST_BASE,
            dst_base
        );

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_DMA_STORE_BYTE_COUNT,
            32'(byte_count)
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_DMA_STORE_SRC_BASE,
            src_base,
            "CSR_DMA_STORE_SRC_BASE"
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_DMA_STORE_DST_BASE,
            dst_base,
            "CSR_DMA_STORE_DST_BASE"
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_DMA_STORE_BYTE_COUNT,
            32'(byte_count),
            "CSR_DMA_STORE_BYTE_COUNT"
        );

        `uvm_info("CSR_AXIS_SMOKE",
            $sformatf("Programmed CSR DMA store: src=0x%08h dst=0x%08h bytes=%0d",
                src_base, dst_base, byte_count),
            UVM_MEDIUM)
    end
    endtask

    task automatic csr_start_dma_store();
        logic [31:0] cmd;
    begin
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::CMD_START_DMA_STORE] = 1'b1;
        csr.issue_command(cmd);

        `uvm_info("CSR_AXIS_SMOKE",
            "Issued CSR START_DMA_STORE command",
            UVM_MEDIUM)
    end
    endtask

    task automatic run_dma_store(
        input logic [31:0] src_base,
        input logic [31:0] dst_base,
        input int unsigned byte_count
    );
    begin
        csr_clear_sticky_status();
        csr_write_dma_store_config(src_base, dst_base, byte_count);
        csr_start_dma_store();
        csr_poll_done_bit(
            done_timeout_cycles,
            ai_accel_csr_access_helper::DONE_DMA_STORE,
            "DMA_STORE_C"
        );

        repeat (5) @(posedge csr_vif.clk);
    end
    endtask

    // ------------------------------------------------------------
    // Destination-memory result collection
    // ------------------------------------------------------------
    task automatic collect_dma_destination_c(
        input  int unsigned c_elems,
        output int signed   actual_c[]
    );
    begin
        vif.dma_dst_mem_read_s32_array(
            DMA_DST_C_BASE,
            c_elems,
            actual_c
        );

        `uvm_info("CSR_AXIS_SMOKE",
            $sformatf("Collected C result from DMA destination memory: base=0x%08h words=%0d",
                DMA_DST_C_BASE, c_elems),
            UVM_MEDIUM)
    end
    endtask

    // ------------------------------------------------------------
    // Run phase
    // ------------------------------------------------------------
    task run_phase(uvm_phase phase);
        ai_accel_subsys_seq_item profile_item;
        int signed               a_flat[];
        int signed               b_flat[];
        int signed               expected_c[];
        int signed               actual_c[];
        int unsigned             c_elems;
        int unsigned             c_bytes;
    begin
        phase.raise_objection(this);

        `uvm_info("CSR_AXIS_SMOKE",
            "Starting CSR-controlled AXI-Stream preload + GEMM + DMA store smoke test",
            UVM_MEDIUM)

        wait_for_reset_release();
        csr.init_bus();
        csr.wait_reset_release();

        build_selected_payload(
            profile_item,
            a_flat,
            b_flat,
            expected_c
        );

        c_elems = c_word_count(profile_item);
        c_bytes = c_elems * 4;

        if (expected_c.size() != c_elems) begin
            `uvm_fatal("CSR_AXIS_SMOKE/EXPECTED_SIZE",
                $sformatf("Expected C size mismatch: expected_c.size=%0d c_elems=%0d",
                    expected_c.size(), c_elems))
        end

        prepare_axis_source_and_destination(a_flat, b_flat);

        if ((get_type_name() == "ai_accel_subsys_csr_axis_stream_load_store_smoke_test") &&
            (selected_case_id == 102)) begin
            run_d1_axis_reject_probes(profile_item.base_addr_a);
            run_d2_axis_error_probe(profile_item.base_addr_a, a_flat.size());
        end

        run_one_axis_load(
            AXIS_SRC_A_BASE,
            profile_item.base_addr_a,
            a_flat.size(),
            "A"
        );

        run_one_axis_load(
            AXIS_SRC_B_BASE,
            profile_item.base_addr_b,
            b_flat.size(),
            "B"
        );

        csr_clear_sticky_status();
        csr_write_gemm_config(profile_item);
        csr_start_gemm();
        csr_poll_gemm_done(done_timeout_cycles);
        csr_check_perf_snapshot();

        run_dma_store(
            profile_item.base_addr_c,
            DMA_DST_C_BASE,
            c_bytes
        );

        collect_dma_destination_c(c_elems, actual_c);
        compare_result_vectors(expected_c, actual_c);

        `uvm_info("CSR_AXIS_SMOKE",
            $sformatf("CSR-controlled AXI-Stream preload + GEMM + DMA store smoke completed: CASE_ID=%0d test_kind=%0d A_bytes=%0d B_bytes=%0d C_words=%0d",
                selected_case_id,
                selected_test_kind,
                a_flat.size(),
                b_flat.size(),
                c_elems),
            UVM_MEDIUM)

        phase.drop_objection(this);
    end
    endtask

endclass

`endif
