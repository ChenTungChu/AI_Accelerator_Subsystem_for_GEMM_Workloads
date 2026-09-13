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

    // CODE-COV-C1.2-G7-K3-C isolated dual-port arbitration probe.
    // Keep Port0 and Port1 scratchpad ranges disjoint from the normal
    // A/B/C regions used by this representative smoke flow.
    localparam logic [31:0] G7_K3C_HOST_DST_BASE = 32'h0000_0C00;
    localparam logic [31:0] G7_K3C_AXIS_SRC_BASE = 32'h0000_0400;
    localparam logic [31:0] G7_K3C_AXIS_DST_BASE = 32'h0000_0E00;

    localparam int unsigned G7_K3C_PROBE_BYTES = 512;
    localparam int unsigned G7_K3C_HOST_WORDS  = G7_K3C_PROBE_BYTES / 4;

    localparam logic [31:0] G7_K3C_HOST_FILL_VALUE = 32'hC3C3_C3C3;
    localparam logic [7:0]  G7_K3C_AXIS_FILL_BYTE  = 8'hA5;

    // CODE-COV-C1.2-G7-Y2 shared GEMM launch producer-contract probes.
    // Keep the additional AXI-Stream scratchpad range disjoint from the
    // normal A/B/C regions.  Direct Stream writes the operand buffer, so its
    // destination is the legal operand-A base rather than scratchpad Port1.
    localparam logic [31:0] G7_Y2_AXIS_SRC_BASE = 32'h0000_0600;
    localparam logic [31:0] G7_Y2_AXIS_DST_BASE = 32'h0000_0E00;
    localparam logic [31:0] G7_Y2_DS_SRC_BASE   = 32'h0000_0680;
    localparam logic [31:0] G7_Y2_DS_DST_BASE   = 32'h0000_0000;

    localparam int unsigned G7_Y2_OWNER_BEATS        = 8;
    localparam int unsigned G7_Y2_OWNER_BYTES        = G7_Y2_OWNER_BEATS * BYTES_PER_BEAT;
    localparam int unsigned G7_Y2_REJ_GEMM_BUSY_BIT  = 0;

    localparam logic [7:0] G7_Y2_AXIS_FILL_BYTE = 8'h5A;
    localparam logic [7:0] G7_Y2_DS_FILL_BYTE   = 8'hD5;


    // CODE-COV-C1.2-G7-Y3-A independent DMA-reset / CDC re-arm probe.
    // Exercise the reset ordering that normal POR intentionally does not
    // generate: dma_rst_n=0 while core_rst_n=1.  Keep the probe idle-only so
    // it validates reset isolation / CDC re-arm without defining mid-job
    // partial-domain reset semantics.
    localparam int unsigned G7_Y3_DMA_RESET_HOLD_CYCLES = 6;
    localparam int unsigned G7_Y3_CDC_REARM_CYCLES      = 16;

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
    // CODE-COV-C1.2-G7-K3-C
    // Dual-Port Simultaneous-Ready Arbitration Collision Reachability
    //
    // Purpose:
    //   - Port0: legal serialized host AXI-MM writes
    //   - Port1: legal CSR-controlled AXI-Stream scratchpad preload
    //   - run both for a sustained interval so completed bursts from both
    //     ports contend for the shared commit engine while it returns to
    //     CE_IDLE.
    //
    // Coverage targets in rtl/mem/axi_mm_dual_port_bram.sv:
    //   1201 : P1 starvation counter increments during simultaneous-ready
    //   1225 : simultaneous-ready with nonzero P0 quota grants Port0
    //   1239 : contested Port0 grant decrements P0 quota
    //
    // No force, hierarchical corruption, BRAM RTL change, or new test class.
    // ------------------------------------------------------------
    task automatic g7_k3c_prepare_axis_probe_source();
        int unsigned i;
    begin
        for (i = 0; i < G7_K3C_PROBE_BYTES; i++) begin
            vif.dma_src_mem_write_byte(
                G7_K3C_AXIS_SRC_BASE + 32'(i),
                G7_K3C_AXIS_FILL_BYTE
            );
        end

        `uvm_info("CODE_COV_C1_2G7_K3C",
            $sformatf("Prepared arbitration probe AXIS source: src=0x%08h bytes=%0d fill=0x%02h",
                G7_K3C_AXIS_SRC_BASE,
                G7_K3C_PROBE_BYTES,
                G7_K3C_AXIS_FILL_BYTE),
            UVM_MEDIUM)
    end
    endtask

    task automatic g7_k3c_check_one_read(
        input axi_mm_host_seq      seq,
        input int unsigned         rsp_idx,
        input logic [31:0]         expected_value,
        input string               tag
    );
        axi_mm_host_seq_item rsp;
    begin
        rsp = seq.get_response_item(rsp_idx);

        if (rsp == null) begin
            `uvm_fatal("CODE_COV_C1_2G7_K3C/NULL_RSP",
                $sformatf("%s: response[%0d] is null", tag, rsp_idx))
        end

        if (!rsp.response_valid) begin
            `uvm_fatal("CODE_COV_C1_2G7_K3C/INVALID_RSP",
                $sformatf("%s: response[%0d] is not valid: %s",
                    tag, rsp_idx, rsp.convert2string()))
        end

        if (rsp.read_data_s32.size() != 1) begin
            `uvm_fatal("CODE_COV_C1_2G7_K3C/BAD_READ_SIZE",
                $sformatf("%s: expected one S32 read value, got %0d",
                    tag, rsp.read_data_s32.size()))
        end

        if (rsp.read_data_s32[0] !== $signed(expected_value)) begin
            `uvm_fatal("CODE_COV_C1_2G7_K3C/READBACK_MISMATCH",
                $sformatf("%s: expected=0x%08h actual=0x%08h",
                    tag,
                    expected_value,
                    rsp.read_data_s32[0]))
        end

        `uvm_info("CODE_COV_C1_2G7_K3C/CHECK",
            $sformatf("%s PASS: 0x%08h", tag, expected_value),
            UVM_MEDIUM)
    end
    endtask

    task automatic run_g7_k3c_dual_port_arbitration_probe();
        axi_mm_host_seq host_write_seq;
        axi_mm_host_seq host_read_seq;
        int unsigned    axis_beats;
    begin
        axis_beats = bytes_to_beats(G7_K3C_PROBE_BYTES);

        g7_k3c_prepare_axis_probe_source();

        // Pre-program Port1 before starting the concurrent window so the
        // CSR configuration traffic itself does not consume the overlap.
        csr_clear_sticky_status();
        csr_write_axis_load_config(
            G7_K3C_AXIS_SRC_BASE,
            G7_K3C_AXIS_DST_BASE,
            axis_beats,
            "G7_K3C_ARB"
        );

        host_write_seq = axi_mm_host_seq::type_id::create("g7_k3c_host_write_seq");
        host_write_seq.set_case_context(
            selected_case_id,
            selected_test_kind,
            "g7_k3c_dual_port_arbitration",
            0
        );
        host_write_seq.queue_fill_u32(
            G7_K3C_HOST_DST_BASE,
            G7_K3C_HOST_WORDS,
            G7_K3C_HOST_FILL_VALUE,
            axi_mm_host_seq_item::AXI_HOST_ROLE_GENERIC
        );

        `uvm_info("CODE_COV_C1_2G7_K3C",
            $sformatf("Starting sustained legal Port0/Port1 arbitration probe: P0=[0x%08h,+%0dB) P1=[0x%08h,+%0dB) axis_beats=%0d",
                G7_K3C_HOST_DST_BASE,
                G7_K3C_PROBE_BYTES,
                G7_K3C_AXIS_DST_BASE,
                G7_K3C_PROBE_BYTES,
                axis_beats),
            UVM_MEDIUM)

        // Both threads are legal public-interface traffic.  The long,
        // serialized streams intentionally overlap for many commit-engine
        // opportunities; no internal signal is forced or sampled.
        fork
            begin : g7_k3c_port1_axis_thread
                csr_start_axis_load("G7_K3C_ARB");
                csr_poll_done_bit(
                    done_timeout_cycles,
                    ai_accel_csr_access_helper::DONE_AXIS_LOAD,
                    "G7_K3C_ARB"
                );
            end

            begin : g7_k3c_port0_host_thread
                host_write_seq.start(env.host_agent.sequencer);
            end
        join

        repeat (4) @(posedge csr_vif.clk);

        // Read back both ends of each isolated region after contention has
        // drained.  This proves arbitration did not corrupt either owner's
        // committed data while leaving the collision proof itself to code
        // coverage.
        host_read_seq = axi_mm_host_seq::type_id::create("g7_k3c_host_read_seq");
        host_read_seq.set_case_context(
            selected_case_id,
            selected_test_kind,
            "g7_k3c_dual_port_arbitration_readback",
            0
        );

        host_read_seq.queue_read_s32(
            G7_K3C_HOST_DST_BASE,
            1,
            axi_mm_host_seq_item::AXI_HOST_ROLE_GENERIC
        );
        host_read_seq.queue_read_s32(
            G7_K3C_HOST_DST_BASE + G7_K3C_PROBE_BYTES - 4,
            1,
            axi_mm_host_seq_item::AXI_HOST_ROLE_GENERIC
        );
        host_read_seq.queue_read_s32(
            G7_K3C_AXIS_DST_BASE,
            1,
            axi_mm_host_seq_item::AXI_HOST_ROLE_GENERIC
        );
        host_read_seq.queue_read_s32(
            G7_K3C_AXIS_DST_BASE + G7_K3C_PROBE_BYTES - 4,
            1,
            axi_mm_host_seq_item::AXI_HOST_ROLE_GENERIC
        );

        host_read_seq.start(env.host_agent.sequencer);

        if (host_read_seq.get_response_count() != 4) begin
            `uvm_fatal("CODE_COV_C1_2G7_K3C/RSP_COUNT",
                $sformatf("Expected 4 arbitration-probe readback responses, got %0d",
                    host_read_seq.get_response_count()))
        end

        g7_k3c_check_one_read(
            host_read_seq,
            0,
            G7_K3C_HOST_FILL_VALUE,
            "Port0 first word"
        );
        g7_k3c_check_one_read(
            host_read_seq,
            1,
            G7_K3C_HOST_FILL_VALUE,
            "Port0 last word"
        );
        g7_k3c_check_one_read(
            host_read_seq,
            2,
            {4{G7_K3C_AXIS_FILL_BYTE}},
            "Port1 first word"
        );
        g7_k3c_check_one_read(
            host_read_seq,
            3,
            {4{G7_K3C_AXIS_FILL_BYTE}},
            "Port1 last word"
        );

        csr_clear_sticky_status();

        `uvm_info("CODE_COV_C1_2G7_K3C/PASS",
            "Legal sustained Port0 host + Port1 AXI-Stream arbitration probe PASS; exact simultaneous-ready closure requires statement report confirmation",
            UVM_MEDIUM)
    end
    endtask

    // ------------------------------------------------------------
    // CODE-COV-C1.2-G7-X3 GEMM launch-reservation / AXI-Stream
    // adjacent-start rejection and recovery probe
    //
    // This is intentionally plusarg-gated from run_phase.  The critical
    // ordering remains two legal CSR writes with no busy polling or
    // arbitrary delay between them:
    //
    //   START_GEMM -> normal AXI-Lite B response -> START_AXIS_LOAD
    //
    // After the X3 RTL repair, the accepted GEMM launch must reserve
    // acc_busy in dma_clk before the second command can be applied.  The
    // AXI-Stream command must therefore be rejected at the CSR boundary,
    // with no AXI-Stream engine launch and no Port1 owner overlap.  After
    // GEMM completes and the reservation releases, the same preload command
    // is retried and must complete normally.
    // ------------------------------------------------------------
    task automatic run_g7_x3_gemm_launch_reservation_probe(
        input ai_accel_subsys_seq_item profile_item,
        input int signed               a_flat[],
        input int signed               b_flat[]
    );
        logic [31:0] cmd;
        logic [31:0] reject_status;
        logic [31:0] done_status;
        int unsigned axis_beats;
        int unsigned overlap_count_before;
        int unsigned overlap_count_after;
        int unsigned cnt;
        bit          axis_busy_seen;
        bit          stream_active_seen;
        bit          acc_busy_dma_seen;
        bit          acc_busy_core_seen;
        bit          reservation_released;
    begin
        if (selected_case_id != 102) begin
            `uvm_fatal("CODE_COV_C1P2_G7_X3/BAD_CASE",
                $sformatf("G7-X3 probe is defined for CASE_ID=102, got CASE_ID=%0d",
                    selected_case_id))
        end

        // Establish valid A/B scratchpad contents first so the GEMM launch is
        // architecturally valid.  These operations complete before the
        // critical adjacent-command window.
        run_one_axis_load(
            AXIS_SRC_A_BASE,
            profile_item.base_addr_a,
            a_flat.size(),
            "G7_X3_PRELOAD_A"
        );

        run_one_axis_load(
            AXIS_SRC_B_BASE,
            profile_item.base_addr_b,
            b_flat.size(),
            "G7_X3_PRELOAD_B"
        );

        // Pre-program both command contexts before START_GEMM.  The probe
        // AXI-Stream destination stays outside the GEMM A/B/C regions so this
        // validates ownership reservation rather than deliberate data aliasing.
        axis_beats = 1;
        csr_clear_sticky_status();
        csr_write_gemm_config(profile_item);
        csr_write_axis_load_config(
            AXIS_SRC_A_BASE,
            G7_K3C_AXIS_DST_BASE,
            axis_beats,
            "G7_X3_ADJACENT"
        );
        csr_clear_sticky_status();

        if (vif.axis_load_busy) begin
            `uvm_fatal("CODE_COV_C1P2_G7_X3/AXIS_NOT_IDLE",
                "AXI-Stream preload engine was busy before the adjacent-start probe")
        end

        overlap_count_before = vif.port1_illegal_overlap_observed_count;
        axis_busy_seen        = 1'b0;
        stream_active_seen    = 1'b0;
        acc_busy_dma_seen     = 1'b0;
        acc_busy_core_seen    = 1'b0;

        `uvm_info("CODE_COV_C1P2_G7_X3/START",
            $sformatf("Starting GEMM launch-reservation / adjacent AXIS rejection probe: GEMM dim=(%0d,%0d,%0d), AXIS src=0x%08h dst=0x%08h beats=%0d, overlap_count_before=%0d",
                profile_item.dim_m,
                profile_item.dim_n,
                profile_item.dim_k,
                AXIS_SRC_A_BASE,
                G7_K3C_AXIS_DST_BASE,
                axis_beats,
                overlap_count_before),
            UVM_MEDIUM)

        // Use the public command primitive directly so there is no inserted
        // poll or arbitrary delay after START_GEMM.  By the time the normal
        // AXI-Lite B response completes, the X3 launch reservation must be
        // externally visible as acc_busy.
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::CMD_START_GEMM] = 1'b1;
        csr.issue_command(cmd);

        if (!vif.acc_busy) begin
            `uvm_fatal("CODE_COV_C1P2_G7_X3/RESERVATION_NOT_VISIBLE",
                "START_GEMM write completed but acc_busy was still low before the immediately adjacent START_AXIS_LOAD")
        end

        `uvm_info("CODE_COV_C1P2_G7_X3/GEMM_ISSUED",
            "START_GEMM write completed with dma-domain launch reservation visible; issuing START_AXIS_LOAD immediately",
            UVM_MEDIUM)

        csr_start_axis_load("G7_X3_ADJACENT");

        // Observe several dma_clk cycles after the rejected command.  A legal
        // X3 result keeps the AXI-Stream engine inactive and the sticky Port1
        // overlap counter unchanged while GEMM proceeds normally.
        for (cnt = 0; cnt < 16; cnt++) begin
            axis_busy_seen     |= vif.axis_load_busy;
            stream_active_seen |= vif.axis_stream_load_active_obs;
            acc_busy_dma_seen  |= vif.acc_busy;
            acc_busy_core_seen |= vif.acc_busy_core_obs;

            overlap_count_after = vif.port1_illegal_overlap_observed_count;
            if ((overlap_count_after > overlap_count_before) ||
                vif.port1_illegal_overlap_obs) begin
                `uvm_fatal("CODE_COV_C1P2_G7_X3/PORT1_OVERLAP",
                    $sformatf("Port1 illegal overlap occurred after the adjacent AXIS command: overlap_count %0d -> %0d",
                        overlap_count_before,
                        overlap_count_after))
            end

            @(posedge csr_vif.clk);
        end

        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS,
            reject_status
        );

        if (!reject_status[C1D1_P14_REJ_AXIS_BUSY]) begin
            `uvm_fatal("CODE_COV_C1P2_G7_X3/NO_AXIS_BUSY_REJECT",
                $sformatf("Adjacent START_AXIS_LOAD was not rejected by ACC_BUSY reservation: reject=0x%08h",
                    reject_status))
        end

        if (axis_busy_seen || stream_active_seen) begin
            `uvm_fatal("CODE_COV_C1P2_G7_X3/AXIS_LAUNCHED",
                $sformatf("Rejected adjacent START_AXIS_LOAD still launched activity: axis_busy_seen=%0d stream_active_seen=%0d",
                    axis_busy_seen,
                    stream_active_seen))
        end

        overlap_count_after = vif.port1_illegal_overlap_observed_count;
        if (overlap_count_after != overlap_count_before) begin
            `uvm_fatal("CODE_COV_C1P2_G7_X3/OVERLAP_COUNT_CHANGED",
                $sformatf("Port1 overlap counter changed across rejected adjacent command: %0d -> %0d",
                    overlap_count_before,
                    overlap_count_after))
        end

        `uvm_info("CODE_COV_C1P2_G7_X3/ADJACENT_REJECT_PASS",
            $sformatf("Adjacent START_AXIS_LOAD rejected with REJ_AXIS_BUSY and no Port1 overlap: reject=0x%08h overlap_count=%0d axis_busy_seen=%0d stream_active_seen=%0d acc_busy_dma_seen=%0d acc_busy_core_seen=%0d",
                reject_status,
                overlap_count_after,
                axis_busy_seen,
                stream_active_seen,
                acc_busy_dma_seen,
                acc_busy_core_seen),
            UVM_MEDIUM)

        // Remove only the expected command-reject sticky state before using
        // the existing GEMM completion poller.
        csr_clear_p14_reject_status(
            "after G7-X3 adjacent START_AXIS_LOAD busy reject"
        );

        csr_poll_gemm_done(done_timeout_cycles);
        csr_check_perf_snapshot();

        `uvm_info("CODE_COV_C1P2_G7_X3/GEMM_DONE",
            "GEMM completed normally after the rejected adjacent AXI-Stream command",
            UVM_MEDIUM)

        // The synchronized core busy level may take a small number of dma_clk
        // cycles to fall after done.  Wait explicitly for the exported busy
        // reservation/status to release before testing recovery.
        reservation_released = 1'b0;
        for (cnt = 0; cnt < 64; cnt++) begin
            if (!vif.acc_busy) begin
                reservation_released = 1'b1;
                break;
            end
            @(posedge csr_vif.clk);
        end

        if (!reservation_released) begin
            `uvm_fatal("CODE_COV_C1P2_G7_X3/RESERVATION_STUCK",
                "acc_busy did not release within 64 dma_clk cycles after GEMM completion")
        end

        csr_clear_sticky_status();

        // Retry the exact same AXI-Stream command after GEMM ownership has
        // released.  This proves the reservation does not create a permanent
        // interlock and that the normal preload path remains functional.
        csr_start_axis_load("G7_X3_RECOVERY");
        csr_poll_done_bit(
            done_timeout_cycles,
            ai_accel_csr_access_helper::DONE_AXIS_LOAD,
            "AXIS_LOAD_G7_X3_RECOVERY"
        );

        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_DONE_STATUS,
            done_status
        );

        if (!done_status[ai_accel_csr_access_helper::DONE_AXIS_LOAD]) begin
            `uvm_fatal("CODE_COV_C1P2_G7_X3/RECOVERY_DONE_MISSING",
                $sformatf("Recovery AXI-Stream preload did not leave DONE_AXIS_LOAD set: DONE_STATUS=0x%08h",
                    done_status))
        end

        overlap_count_after = vif.port1_illegal_overlap_observed_count;
        if ((overlap_count_after != overlap_count_before) ||
            vif.port1_illegal_overlap_obs) begin
            `uvm_fatal("CODE_COV_C1P2_G7_X3/RECOVERY_OVERLAP",
                $sformatf("Port1 overlap observed during post-GEMM recovery preload: overlap_count %0d -> %0d",
                    overlap_count_before,
                    overlap_count_after))
        end

        `uvm_info("CODE_COV_C1P2_G7_X3/RECOVERY_PASS",
            $sformatf("AXI-Stream preload accepted after GEMM reservation released: DONE_STATUS=0x%08h overlap_count=%0d",
                done_status,
                overlap_count_after),
            UVM_MEDIUM)

        csr_clear_sticky_status();

        `uvm_info("CODE_COV_C1P2_G7_X3/PASS",
            "GEMM launch-reservation / adjacent AXI-Stream rejection and recovery probe PASS",
            UVM_MEDIUM)
    end
    endtask


    // ------------------------------------------------------------
    // CODE-COV-C1.2-G7-Y2 shared GEMM launch busy-guard
    // producer-contract reconciliation
    //
    // Both probes intentionally use legal public CSR commands and keep the
    // critical ordering adjacent, with no busy poll or arbitrary delay:
    //
    //   START_AXIS_LOAD -> normal AXI-Lite B response -> START_GEMM
    //   START_DS_LOAD   -> normal AXI-Lite B response -> START_GEMM
    //
    // The GEMM command must be rejected at the CSR producer boundary while
    // the current preload owner remains active.  Therefore the lower shared
    // acc_start_pulse_dma_accepted busy terms should remain defensive misses.
    // ------------------------------------------------------------
    task automatic g7_y2_prepare_owner_sources();
        int unsigned i;
    begin
        for (i = 0; i < G7_Y2_OWNER_BYTES; i++) begin
            vif.dma_src_mem_write_byte(
                G7_Y2_AXIS_SRC_BASE + 32'(i),
                G7_Y2_AXIS_FILL_BYTE
            );
            vif.dma_src_mem_write_byte(
                G7_Y2_DS_SRC_BASE + 32'(i),
                G7_Y2_DS_FILL_BYTE
            );
        end

        vif.axis_src_set_rresp_error(1'b0, -1);
        vif.ds_src_set_rresp_error(1'b0, -1);

        `uvm_info("CODE_COV_C1P2_G7_Y2/SRC",
            $sformatf("Prepared Y2 owner sources: AXIS src=0x%08h bytes=%0d fill=0x%02h, DS src=0x%08h bytes=%0d fill=0x%02h",
                G7_Y2_AXIS_SRC_BASE,
                G7_Y2_OWNER_BYTES,
                G7_Y2_AXIS_FILL_BYTE,
                G7_Y2_DS_SRC_BASE,
                G7_Y2_OWNER_BYTES,
                G7_Y2_DS_FILL_BYTE),
            UVM_MEDIUM)
    end
    endtask

    task automatic csr_write_ds_load_config(
        input logic [31:0] src_base,
        input logic [31:0] dst_base,
        input int unsigned beats,
        input logic        operand_sel,
        input string       tag
    );
        logic [31:0] control_value;
    begin
        control_value = operand_sel ? 32'h0000_0001 : 32'h0000_0000;

        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_DS_SRC_BASE,
            src_base
        );
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_DS_DST_BASE,
            dst_base
        );
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_DS_LOAD_BEATS,
            32'(beats)
        );
        csr.write32_expect_okay(
            ai_accel_csr_access_helper::CSR_DS_CONTROL,
            control_value
        );

        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_DS_SRC_BASE,
            src_base,
            {tag, " CSR_DS_SRC_BASE"}
        );
        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_DS_DST_BASE,
            dst_base,
            {tag, " CSR_DS_DST_BASE"}
        );
        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_DS_LOAD_BEATS,
            32'(beats),
            {tag, " CSR_DS_LOAD_BEATS"}
        );
        csr.expect_read32(
            ai_accel_csr_access_helper::CSR_DS_CONTROL,
            control_value,
            {tag, " CSR_DS_CONTROL"}
        );

        `uvm_info("CSR_AXIS_SMOKE",
            $sformatf("Programmed CSR Direct Stream preload %s: operand=%0d src=0x%08h dst=0x%08h beats=%0d",
                tag,
                operand_sel,
                src_base,
                dst_base,
                beats),
            UVM_MEDIUM)
    end
    endtask

    task automatic csr_start_ds_load(input string tag);
        logic [31:0] cmd;
    begin
        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::CMD_START_DS_LOAD] = 1'b1;
        csr.issue_command(cmd);

        `uvm_info("CSR_AXIS_SMOKE",
            $sformatf("Issued CSR START_DS_LOAD command for %s", tag),
            UVM_MEDIUM)
    end
    endtask

    task automatic g7_y2_expect_gemm_busy_reject(input string tag);
        logic [31:0] reject_status;
    begin
        csr.read32_expect_okay(
            ai_accel_csr_access_helper::CSR_CMD_REJECT_STATUS,
            reject_status
        );

        if (!reject_status[G7_Y2_REJ_GEMM_BUSY_BIT]) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Y2/NO_GEMM_BUSY_REJECT",
                $sformatf("%s: expected REJ_GEMM_BUSY after adjacent START_GEMM, reject=0x%08h",
                    tag,
                    reject_status))
        end

        `uvm_info("CODE_COV_C1P2_G7_Y2/GEMM_REJECT_OBSERVED",
            $sformatf("%s: observed expected REJ_GEMM_BUSY, reject=0x%08h",
                tag,
                reject_status),
            UVM_MEDIUM)
    end
    endtask

    task automatic run_g7_y2_shared_gemm_busy_guard_probe(
        input ai_accel_subsys_seq_item profile_item
    );
        logic [31:0] cmd;
        int unsigned cnt;
        int unsigned overlap_count_before;
        int unsigned overlap_count_after;
        bit          axis_busy_seen;
        bit          ds_busy_seen;
        bit          acc_busy_seen;
        bit          acc_busy_core_seen;
    begin
        if (selected_case_id != 102) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Y2/BAD_CASE",
                $sformatf("G7-Y2 probe is defined for CASE_ID=102, got CASE_ID=%0d",
                    selected_case_id))
        end

        g7_y2_prepare_owner_sources();

        `uvm_info("CODE_COV_C1P2_G7_Y2/START",
            "Starting shared GEMM launch busy-guard producer-contract probe: AXIS-owner and Direct-Stream-owner directions",
            UVM_MEDIUM)

        // --------------------------------------------------------
        // A) AXI-Stream owner blocks an immediately adjacent GEMM.
        // --------------------------------------------------------
        csr_clear_sticky_status();
        csr_write_gemm_config(profile_item);
        csr_write_axis_load_config(
            G7_Y2_AXIS_SRC_BASE,
            G7_Y2_AXIS_DST_BASE,
            G7_Y2_OWNER_BEATS,
            "G7_Y2_AXIS_OWNER"
        );
        csr_clear_sticky_status();

        if (vif.axis_load_busy || vif.acc_busy) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Y2/AXIS_PRECONDITION",
                $sformatf("AXIS->GEMM probe did not start idle: axis_busy=%0d acc_busy=%0d",
                    vif.axis_load_busy,
                    vif.acc_busy))
        end

        overlap_count_before = vif.port1_illegal_overlap_observed_count;
        axis_busy_seen        = 1'b0;
        acc_busy_seen         = 1'b0;
        acc_busy_core_seen    = 1'b0;

        csr_start_axis_load("G7_Y2_AXIS_OWNER");

        `uvm_info("CODE_COV_C1P2_G7_Y2_AXIS/OWNER_START",
            "START_AXIS_LOAD write completed; issuing START_GEMM immediately with no busy poll or inserted delay",
            UVM_MEDIUM)

        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::CMD_START_GEMM] = 1'b1;
        csr.issue_command(cmd);

        for (cnt = 0; cnt < 16; cnt++) begin
            axis_busy_seen     |= vif.axis_load_busy;
            acc_busy_seen      |= vif.acc_busy;
            acc_busy_core_seen |= vif.acc_busy_core_obs;

            overlap_count_after = vif.port1_illegal_overlap_observed_count;
            if ((overlap_count_after > overlap_count_before) ||
                vif.port1_illegal_overlap_obs) begin
                `uvm_fatal("CODE_COV_C1P2_G7_Y2_AXIS/PORT1_OVERLAP",
                    $sformatf("Port1 overlap occurred during AXIS-owner GEMM-reject probe: overlap_count %0d -> %0d",
                        overlap_count_before,
                        overlap_count_after))
            end

            @(posedge csr_vif.clk);
        end

        g7_y2_expect_gemm_busy_reject("AXIS owner blocks GEMM");

        if (!axis_busy_seen) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Y2_AXIS/OWNER_NOT_BUSY",
                "AXI-Stream owner never asserted busy during the AXIS->GEMM probe")
        end

        if (acc_busy_seen || acc_busy_core_seen) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Y2_AXIS/GEMM_LAUNCHED",
                $sformatf("Rejected START_GEMM still launched accelerator activity: acc_busy_seen=%0d acc_busy_core_seen=%0d",
                    acc_busy_seen,
                    acc_busy_core_seen))
        end

        overlap_count_after = vif.port1_illegal_overlap_observed_count;
        if (overlap_count_after != overlap_count_before) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Y2_AXIS/OVERLAP_COUNT_CHANGED",
                $sformatf("Port1 overlap counter changed during AXIS->GEMM rejection: %0d -> %0d",
                    overlap_count_before,
                    overlap_count_after))
        end

        csr_clear_p14_reject_status(
            "after G7-Y2 AXIS-owner START_GEMM busy reject"
        );
        csr_poll_done_bit(
            done_timeout_cycles,
            ai_accel_csr_access_helper::DONE_AXIS_LOAD,
            "G7_Y2_AXIS_OWNER"
        );

        `uvm_info("CODE_COV_C1P2_G7_Y2_AXIS/GEMM_REJECT_PASS",
            $sformatf("Adjacent START_GEMM rejected while AXI-Stream owned Port1: axis_busy_seen=%0d acc_busy_seen=%0d acc_busy_core_seen=%0d overlap_count=%0d",
                axis_busy_seen,
                acc_busy_seen,
                acc_busy_core_seen,
                overlap_count_after),
            UVM_MEDIUM)

        csr_clear_sticky_status();

        // --------------------------------------------------------
        // B) Direct Stream owner blocks an immediately adjacent GEMM.
        // --------------------------------------------------------
        csr_write_gemm_config(profile_item);
        csr_write_ds_load_config(
            G7_Y2_DS_SRC_BASE,
            G7_Y2_DS_DST_BASE,
            G7_Y2_OWNER_BEATS,
            1'b0,
            "G7_Y2_DS_OWNER"
        );
        csr_clear_sticky_status();

        if (vif.ds_load_busy || vif.acc_busy) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Y2/DS_PRECONDITION",
                $sformatf("DS->GEMM probe did not start idle: ds_busy=%0d acc_busy=%0d",
                    vif.ds_load_busy,
                    vif.acc_busy))
        end

        ds_busy_seen      = 1'b0;
        acc_busy_seen     = 1'b0;
        acc_busy_core_seen = 1'b0;

        csr_start_ds_load("G7_Y2_DS_OWNER");

        `uvm_info("CODE_COV_C1P2_G7_Y2_DS/OWNER_START",
            "START_DS_LOAD write completed; issuing START_GEMM immediately with no busy poll or inserted delay",
            UVM_MEDIUM)

        cmd = 32'h0000_0000;
        cmd[ai_accel_csr_access_helper::CMD_START_GEMM] = 1'b1;
        csr.issue_command(cmd);

        for (cnt = 0; cnt < 16; cnt++) begin
            ds_busy_seen       |= vif.ds_load_busy;
            acc_busy_seen      |= vif.acc_busy;
            acc_busy_core_seen |= vif.acc_busy_core_obs;
            @(posedge csr_vif.clk);
        end

        g7_y2_expect_gemm_busy_reject("Direct Stream owner blocks GEMM");

        if (!ds_busy_seen) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Y2_DS/OWNER_NOT_BUSY",
                "Direct Stream owner never asserted busy during the DS->GEMM probe")
        end

        if (acc_busy_seen || acc_busy_core_seen) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Y2_DS/GEMM_LAUNCHED",
                $sformatf("Rejected START_GEMM still launched accelerator activity: acc_busy_seen=%0d acc_busy_core_seen=%0d",
                    acc_busy_seen,
                    acc_busy_core_seen))
        end

        csr_clear_p14_reject_status(
            "after G7-Y2 Direct-Stream-owner START_GEMM busy reject"
        );
        csr_poll_done_bit(
            done_timeout_cycles,
            ai_accel_csr_access_helper::DONE_DS_LOAD,
            "G7_Y2_DS_OWNER"
        );

        `uvm_info("CODE_COV_C1P2_G7_Y2_DS/GEMM_REJECT_PASS",
            $sformatf("Adjacent START_GEMM rejected while Direct Stream owner was busy: ds_busy_seen=%0d acc_busy_seen=%0d acc_busy_core_seen=%0d",
                ds_busy_seen,
                acc_busy_seen,
                acc_busy_core_seen),
            UVM_MEDIUM)

        // --------------------------------------------------------
        // C) Shared release/recovery: after both owners complete, a normal
        // GEMM launch must be accepted and complete.  The normal A/B
        // scratchpad preloads performed by run_phase remain intact.
        // --------------------------------------------------------
        csr_clear_sticky_status();
        csr_write_gemm_config(profile_item);
        csr_start_gemm();
        csr_poll_gemm_done(done_timeout_cycles);
        csr_check_perf_snapshot();

        `uvm_info("CODE_COV_C1P2_G7_Y2/RECOVERY_PASS",
            "GEMM launch accepted and completed after both preload-owner busy guards released",
            UVM_MEDIUM)

        csr_clear_sticky_status();

        `uvm_info("CODE_COV_C1P2_G7_Y2/PASS",
            "Shared GEMM launch producer-contract probe PASS: AXIS owner and Direct Stream owner both reject adjacent GEMM launch and recover cleanly",
            UVM_MEDIUM)
    end
    endtask

    // ------------------------------------------------------------
    // CODE-COV-C1.2-G7-Y3-A
    // Independent DMA-reset / core-alive CDC re-arm probe.
    //
    // Normal POR releases dma_rst_n first and core_rst_n second, so it never
    // creates dma_rst_n=0 while core_rst_n=1.  The existing TB reset override
    // is used here to construct that legal independent-reset ordering without
    // forcing any DUT-internal signal.
    // ------------------------------------------------------------
    task automatic run_g7_y3_dma_only_reset_cdc_rearm_probe();
        int unsigned cnt;
        int unsigned overlap_count_before;
        int unsigned overlap_count_after;
        bit          false_acc_busy_seen;
        bit          false_acc_done_seen;
        bit          false_core_busy_seen;
    begin
        if (selected_case_id != 102) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Y3_A/BAD_CASE",
                $sformatf("G7-Y3-A probe is defined for CASE_ID=102, got CASE_ID=%0d",
                    selected_case_id))
        end

        if ((vif.dma_rst_n !== 1'b1) ||
            (vif.core_rst_n !== 1'b1)) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Y3_A/PRE_RESET_STATE",
                $sformatf("G7-Y3-A requires both resets released before override: dma_rst_n=%b core_rst_n=%b",
                    vif.dma_rst_n,
                    vif.core_rst_n))
        end

        if (vif.acc_busy ||
            vif.acc_busy_core_obs ||
            vif.dma_load_busy ||
            vif.axis_load_busy ||
            vif.ds_load_busy ||
            vif.dma_store_busy) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Y3_A/PRE_BUSY",
                $sformatf("G7-Y3-A must start idle: acc_busy=%0d acc_busy_core=%0d dma_load_busy=%0d axis_busy=%0d ds_busy=%0d dma_store_busy=%0d",
                    vif.acc_busy,
                    vif.acc_busy_core_obs,
                    vif.dma_load_busy,
                    vif.axis_load_busy,
                    vif.ds_load_busy,
                    vif.dma_store_busy))
        end

        overlap_count_before = vif.port1_illegal_overlap_observed_count;

        `uvm_info("CODE_COV_C1P2_G7_Y3_A/START",
            "Starting independent DMA-reset / core-alive CDC re-arm probe at system idle",
            UVM_MEDIUM)

        // First enable the override while preserving the already released
        // reset state.  This avoids introducing a transition on either reset
        // merely from selecting the override mux.
        @(negedge csr_vif.clk);
        vif.tb_dma_rst_n_override  = 1'b1;
        vif.tb_core_rst_n_override = 1'b1;
        vif.tb_reset_override_en   = 1'b1;

        @(posedge csr_vif.clk);
        if ((vif.dma_rst_n !== 1'b1) ||
            (vif.core_rst_n !== 1'b1)) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Y3_A/OVERRIDE_ARM",
                $sformatf("Reset override arm disturbed released resets: dma_rst_n=%b core_rst_n=%b",
                    vif.dma_rst_n,
                    vif.core_rst_n))
        end

        // Construct the missing legal reset ordering: DMA reset asserted while
        // core reset remains released.
        @(negedge csr_vif.clk);
        vif.tb_dma_rst_n_override = 1'b0;

        for (cnt = 0; cnt < G7_Y3_DMA_RESET_HOLD_CYCLES; cnt++) begin
            @(posedge csr_vif.clk);

            if ((vif.dma_rst_n !== 1'b0) ||
                (vif.core_rst_n !== 1'b1)) begin
                `uvm_fatal("CODE_COV_C1P2_G7_Y3_A/RESET_ORDER",
                    $sformatf("Expected DMA-only reset ordering was not held: cycle=%0d dma_rst_n=%b core_rst_n=%b",
                        cnt,
                        vif.dma_rst_n,
                        vif.core_rst_n))
            end

            if (vif.acc_busy ||
                vif.acc_done ||
                vif.acc_busy_core_obs ||
                vif.port1_illegal_overlap_obs) begin
                `uvm_fatal("CODE_COV_C1P2_G7_Y3_A/SPURIOUS_DURING_RESET",
                    $sformatf("Spurious accelerator activity during DMA-only reset: acc_busy=%0d acc_done=%0d acc_busy_core=%0d overlap=%0d",
                        vif.acc_busy,
                        vif.acc_done,
                        vif.acc_busy_core_obs,
                        vif.port1_illegal_overlap_obs))
            end
        end

        `uvm_info("CODE_COV_C1P2_G7_Y3_A/DMA_ONLY_RESET_PASS",
            $sformatf("Observed legal independent reset ordering for %0d dma_clk cycles: dma_rst_n=0 core_rst_n=1 with no spurious accelerator activity",
                G7_Y3_DMA_RESET_HOLD_CYCLES),
            UVM_MEDIUM)

        // Release the DMA reset while core remains alive, then give both CDC
        // armed synchronizers ample time to seed from their current source
        // toggle values.  No false GEMM start/done is allowed during re-arm.
        @(negedge csr_vif.clk);
        vif.tb_dma_rst_n_override = 1'b1;

        false_acc_busy_seen  = 1'b0;
        false_acc_done_seen  = 1'b0;
        false_core_busy_seen = 1'b0;

        for (cnt = 0; cnt < G7_Y3_CDC_REARM_CYCLES; cnt++) begin
            @(posedge csr_vif.clk);

            if ((vif.dma_rst_n !== 1'b1) ||
                (vif.core_rst_n !== 1'b1)) begin
                `uvm_fatal("CODE_COV_C1P2_G7_Y3_A/RELEASE_STATE",
                    $sformatf("Both resets were not released during CDC re-arm: cycle=%0d dma_rst_n=%b core_rst_n=%b",
                        cnt,
                        vif.dma_rst_n,
                        vif.core_rst_n))
            end

            false_acc_busy_seen  |= vif.acc_busy;
            false_acc_done_seen  |= vif.acc_done;
            false_core_busy_seen |= vif.acc_busy_core_obs;

            if (vif.port1_illegal_overlap_obs) begin
                `uvm_fatal("CODE_COV_C1P2_G7_Y3_A/REARM_OVERLAP",
                    "Port1 illegal overlap asserted during DMA-reset CDC re-arm")
            end
        end

        overlap_count_after = vif.port1_illegal_overlap_observed_count;

        if (false_acc_busy_seen ||
            false_acc_done_seen ||
            false_core_busy_seen) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Y3_A/SPURIOUS_REARM",
                $sformatf("False activity observed during CDC re-arm: acc_busy_seen=%0d acc_done_seen=%0d acc_busy_core_seen=%0d",
                    false_acc_busy_seen,
                    false_acc_done_seen,
                    false_core_busy_seen))
        end

        if (overlap_count_after != overlap_count_before) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Y3_A/OVERLAP_COUNT_CHANGED",
                $sformatf("Port1 illegal-overlap counter changed across DMA-only reset/re-arm: %0d -> %0d",
                    overlap_count_before,
                    overlap_count_after))
        end

        `uvm_info("CODE_COV_C1P2_G7_Y3_A/CDC_REARM_PASS",
            $sformatf("CDC re-arm completed with no false start/done/busy or Port1 overlap across %0d observation cycles",
                G7_Y3_CDC_REARM_CYCLES),
            UVM_MEDIUM)

        // Return control to the normal POR mux only after both override reset
        // values are high.  POR has already completed, so this handoff must be
        // transition-free.
        @(negedge csr_vif.clk);
        vif.tb_dma_rst_n_override  = 1'b1;
        vif.tb_core_rst_n_override = 1'b1;
        vif.tb_reset_override_en   = 1'b0;

        repeat (2) @(posedge csr_vif.clk);

        if ((vif.dma_rst_n !== 1'b1) ||
            (vif.core_rst_n !== 1'b1)) begin
            `uvm_fatal("CODE_COV_C1P2_G7_Y3_A/POR_HANDOFF",
                $sformatf("POR handoff did not preserve released resets: dma_rst_n=%b core_rst_n=%b",
                    vif.dma_rst_n,
                    vif.core_rst_n))
        end

        // Reinitialize only the TB-side AXI-Lite drive values.  The DUT CSR
        // block has legitimately reset and the remainder of CASE_ID=102 will
        // reprogram all state before use.
        csr.init_bus();
        csr.wait_reset_release();

        `uvm_info("CODE_COV_C1P2_G7_Y3_A/PASS",
            "Independent DMA-reset / core-alive reset ordering and CDC re-arm PASS; normal CASE_ID=102 smoke continues as recovery qualification",
            UVM_MEDIUM)
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

        if ((get_type_name() == "ai_accel_subsys_csr_axis_stream_load_store_smoke_test") &&
            (selected_case_id == 102)) begin
            run_g7_y3_dma_only_reset_cdc_rearm_probe();
        end

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

        // One-off G7-X3 launch-reservation repair probe.  The plusarg
        // keeps the validated default 150-test regression behavior
        // unchanged when the probe is not explicitly requested.
        if ($test$plusargs("G7_X3_PROBE")) begin
            run_g7_x3_gemm_launch_reservation_probe(
                profile_item,
                a_flat,
                b_flat
            );

            phase.drop_objection(this);
            return;
        end

        if ((get_type_name() == "ai_accel_subsys_csr_axis_stream_load_store_smoke_test") &&
            (selected_case_id == 102)) begin
            run_d1_axis_reject_probes(profile_item.base_addr_a);
            run_d2_axis_error_probe(profile_item.base_addr_a, a_flat.size());
            run_g7_k3c_dual_port_arbitration_probe();
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

        if ((get_type_name() == "ai_accel_subsys_csr_axis_stream_load_store_smoke_test") &&
            (selected_case_id == 102)) begin
            run_g7_y2_shared_gemm_busy_guard_probe(profile_item);
        end

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
